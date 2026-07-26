import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

const String progressPrefix = '__VIDEO2SRT_PROGRESS__ ';
const String customModelPreset = 'custom';
const Map<String, String> modelRepos = {
  'large-v2': 'Systran/faster-whisper-large-v2',
  'large-v3': 'Systran/faster-whisper-large-v3',
};

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows) {
    FilePickerWindows.registerWith();
  }
  runApp(const Video2SrtApp());
}

class Video2SrtApp extends StatelessWidget {
  const Video2SrtApp({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF006A62),
      brightness: Brightness.light,
    ).copyWith(
      secondary: const Color(0xFF8A4F00),
      surface: const Color(0xFFFBFDFC),
      surfaceContainerHighest: const Color(0xFFE7EFEA),
    );

    return MaterialApp(
      title: 'Video2Srt',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: colorScheme.surface,
        filledButtonTheme: const FilledButtonThemeData(
          style: ButtonStyle(
            minimumSize: WidgetStatePropertyAll(Size(0, 56)),
            padding: WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 28, vertical: 18),
            ),
            textStyle: WidgetStatePropertyAll(
              TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        outlinedButtonTheme: const OutlinedButtonThemeData(
          style: ButtonStyle(
            minimumSize: WidgetStatePropertyAll(Size(0, 54)),
            padding: WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 26, vertical: 17),
            ),
            textStyle: WidgetStatePropertyAll(
              TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        textButtonTheme: const TextButtonThemeData(
          style: ButtonStyle(
            minimumSize: WidgetStatePropertyAll(Size(0, 50)),
            padding: WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 20, vertical: 15),
            ),
            textStyle: WidgetStatePropertyAll(
              TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: colorScheme.surfaceContainerLowest,
          border: const OutlineInputBorder(),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: colorScheme.outlineVariant),
          ),
        ),
      ),
      home: const WorkbenchScreen(),
    );
  }
}

class BackendPaths {
  const BackendPaths({
    required this.root,
    required this.executable,
    required this.baseArgs,
    required this.config,
    required this.exampleConfig,
    required this.manifest,
    required this.dataRoot,
  });

  final Directory root;
  final String executable;
  final List<String> baseArgs;
  final File config;
  final File exampleConfig;
  final File manifest;
  final Directory dataRoot;

  String get displayCommand {
    return [executable, ...baseArgs].join(' ');
  }

  static Future<BackendPaths> discover() async {
    final executableDir = File(Platform.resolvedExecutable).parent;
    final configuredRoot = Platform.environment['VIDEO2SRT_BACKEND_ROOT'];
    final candidates = <Directory>[
      if (configuredRoot != null && configuredRoot.isNotEmpty)
        Directory(configuredRoot),
      Directory('${executableDir.path}${Platform.pathSeparator}backend'),
      executableDir,
      Directory.current,
      Directory.current.parent,
      executableDir.parent,
    ];

    final uniqueCandidates = <String>{};
    for (final root in candidates) {
      final normalized = root.absolute.path;
      if (!uniqueCandidates.add(normalized)) {
        continue;
      }
      final backend = await _fromRoot(root);
      if (backend != null) {
        return backend;
      }
    }
    throw StateError(
      '没有找到 transcribe.py 或 transcribe.exe。请设置 VIDEO2SRT_BACKEND_ROOT。',
    );
  }

  static Future<BackendPaths?> _fromRoot(Directory root) async {
    final config = File('${root.path}${Platform.pathSeparator}config.json');
    final exampleConfig =
        File('${root.path}${Platform.pathSeparator}config.example.json');
    final manifest =
        File('${root.path}${Platform.pathSeparator}backend_manifest.json');
    final bundledExecutable = File('${root.path}${Platform.pathSeparator}'
        '${Platform.isWindows ? 'transcribe.exe' : 'transcribe'}');
    if (await bundledExecutable.exists()) {
      final dataRoot = _userDataRoot();
      return BackendPaths(
        root: root,
        executable: bundledExecutable.path,
        baseArgs: const [],
        config: File('${dataRoot.path}${Platform.pathSeparator}config.json'),
        exampleConfig: exampleConfig,
        manifest: manifest,
        dataRoot: dataRoot,
      );
    }

    final script = File('${root.path}${Platform.pathSeparator}transcribe.py');
    if (await script.exists()) {
      return BackendPaths(
        root: root,
        executable: await _findPython(root),
        baseArgs: [script.path],
        config: config,
        exampleConfig: exampleConfig,
        manifest: manifest,
        dataRoot: root,
      );
    }
    return null;
  }

  static Directory _userDataRoot() {
    final base = Platform.environment['APPDATA'] ??
        Platform.environment['LOCALAPPDATA'] ??
        Platform.environment['HOME'] ??
        Directory.current.path;
    return Directory('$base${Platform.pathSeparator}Video2Srt');
  }

  static Future<String> _findPython(Directory root) async {
    final configuredPython = Platform.environment['VIDEO2SRT_PYTHON'];
    if (configuredPython != null && configuredPython.isNotEmpty) {
      return configuredPython;
    }

    final candidates = <File>[
      File('${root.path}${Platform.pathSeparator}.venv'
          '${Platform.pathSeparator}Scripts${Platform.pathSeparator}python.exe'),
      File('${root.path}${Platform.pathSeparator}runtime'
          '${Platform.pathSeparator}python.exe'),
      File('${root.path}${Platform.pathSeparator}runtime'
          '${Platform.pathSeparator}Scripts${Platform.pathSeparator}python.exe'),
      File('${root.path}${Platform.pathSeparator}runtime'
          '${Platform.pathSeparator}bin${Platform.pathSeparator}python.exe'),
    ];
    for (final candidate in candidates) {
      if (await candidate.exists()) {
        return candidate.path;
      }
    }
    return Platform.isWindows ? 'python.exe' : 'python3';
  }

  Future<Process> start(List<String> args) {
    return Process.start(
      executable,
      [...baseArgs, '--config', config.path, ...args],
      workingDirectory: root.path,
      environment: {
        ...Platform.environment,
        'PYTHONIOENCODING': 'utf-8',
        'PYTHONUTF8': '1',
      },
    );
  }
}

class WorkbenchScreen extends StatefulWidget {
  const WorkbenchScreen({super.key});

  @override
  State<WorkbenchScreen> createState() => _WorkbenchScreenState();
}

class _WorkbenchScreenState extends State<WorkbenchScreen> {
  final _formKey = GlobalKey<FormState>();
  final _sourceController = TextEditingController();
  final _outputController = TextEditingController();
  final _modelController = TextEditingController();
  final _cacheController = TextEditingController();
  final _singleFileController = TextEditingController();
  final _limitController = TextEditingController();
  final _lineCharsController = TextEditingController();
  final _sentenceCharsController = TextEditingController();
  final _sentenceDurationController = TextEditingController();
  final _gapController = TextEditingController();
  final _httpProxyController = TextEditingController();
  final _httpsProxyController = TextEditingController();
  final _hfEndpointController = TextEditingController();
  final _logScrollController = ScrollController();

  BackendPaths? _backend;
  Map<String, dynamic> _config = {};
  Map<String, dynamic> _manifest = {};
  Process? _process;
  StreamSubscription<String>? _stdoutSub;
  StreamSubscription<String>? _stderrSub;
  int _pageIndex = 0;
  String _modelPreset = 'large-v3';
  String _device = 'auto';
  String _computeType = 'default';
  bool _preserveRoot = true;
  bool _useLocalCache = true;
  bool _deleteCache = true;
  bool _force = false;
  bool _pushCloud = false;
  bool _isBusy = false;
  bool _progressIndeterminate = false;
  double _progress = 0;
  String _progressText = '等待任务';
  String _currentVideo = '当前视频：-';
  final List<String> _logs = [];
  Timer? _configSaveDebounce;

  @override
  void initState() {
    super.initState();
    _loadWorkspace();
  }

  @override
  void dispose() {
    _stdoutSub?.cancel();
    _stderrSub?.cancel();
    _process?.kill();
    _sourceController.dispose();
    _outputController.dispose();
    _modelController.dispose();
    _cacheController.dispose();
    _singleFileController.dispose();
    _limitController.dispose();
    _lineCharsController.dispose();
    _sentenceCharsController.dispose();
    _sentenceDurationController.dispose();
    _gapController.dispose();
    _httpProxyController.dispose();
    _httpsProxyController.dispose();
    _hfEndpointController.dispose();
    _logScrollController.dispose();
    _configSaveDebounce?.cancel();
    super.dispose();
  }

  Future<void> _loadWorkspace() async {
    try {
      final backend = await BackendPaths.discover();
      final configFile = await backend.config.exists()
          ? backend.config
          : backend.exampleConfig;
      final content = await configFile.readAsString();
      final config = jsonDecode(content) as Map<String, dynamic>;
      Map<String, dynamic> manifest = {};
      if (await backend.manifest.exists()) {
        try {
          manifest = jsonDecode(await backend.manifest.readAsString())
              as Map<String, dynamic>;
        } catch (_) {
          manifest = {};
        }
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _backend = backend;
        _config = config;
        _manifest = manifest;
        _sourceController.text = '${config['src_root'] ?? ''}';
        _outputController.text = '${config['dst_root'] ?? 'output'}';
        _modelController.text = '${config['model_base'] ?? ''}';
        _cacheController.text = '${config['cache_dir'] ?? '.cache/videos'}';
        _lineCharsController.text = '${config['max_chars_per_line'] ?? 18}';
        _sentenceCharsController.text =
            '${config['max_chars_per_sentence'] ?? 28}';
        _sentenceDurationController.text =
            '${config['max_sentence_duration'] ?? 4.8}';
        _gapController.text = '${config['gap_threshold'] ?? 0.45}';
        _httpProxyController.text = '${config['http_proxy'] ?? ''}';
        _httpsProxyController.text = '${config['https_proxy'] ?? ''}';
        _hfEndpointController.text = '${config['hf_endpoint'] ?? ''}';
        _modelPreset = _inferModelPreset(
          backend,
          '${config['model_preset'] ?? 'large-v3'}',
          _modelController.text,
        );
        _device = '${config['device'] ?? 'auto'}';
        _computeType = '${config['compute_type'] ?? 'default'}';
        _preserveRoot = config['preserve_source_root_name'] != false;
        _useLocalCache = config['use_local_cache'] != false;
        _deleteCache = config['delete_cache_after'] != false;
        _appendLog('后端目录：${backend.root.path}');
        _appendLog('后端命令：${backend.displayCommand}');
        _appendLog('配置文件：${backend.config.path}');
        if (manifest.isNotEmpty) {
          _appendLog(
            '后端包：${manifest['backend_mode'] ?? '-'} / '
            '${manifest['package_profile'] ?? '-'}',
          );
        }
      });
    } catch (error) {
      if (mounted) {
        setState(() => _appendLog('初始化失败：$error'));
      }
    }
  }

  void _appendLog(String line) {
    _logs.add(line);
    if (_logs.length > 600) {
      _logs.removeRange(0, _logs.length - 600);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_logScrollController.hasClients) {
        return;
      }
      _logScrollController.animateTo(
        _logScrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  String _presetModelPath(BackendPaths backend, String preset) {
    return '${backend.dataRoot.path}${Platform.pathSeparator}models'
        '${Platform.pathSeparator}$preset';
  }

  bool _isAbsolutePath(String path) {
    if (Platform.isWindows) {
      return RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(path) ||
          path.startsWith(r'\\');
    }
    return path.startsWith('/');
  }

  String _resolveAgainstBackend(String raw) {
    final backend = _backend;
    final value = raw.trim();
    if (value.isEmpty || _isAbsolutePath(value) || backend == null) {
      return value;
    }
    return '${backend.dataRoot.path}${Platform.pathSeparator}$value';
  }

  String _normalizeComparablePath(String raw) {
    final resolved = _resolveAgainstBackend(raw);
    if (resolved.isEmpty) {
      return '';
    }
    var path = Directory(resolved)
        .absolute
        .path
        .replaceAll('/', Platform.pathSeparator)
        .replaceAll('\\', Platform.pathSeparator);
    while (path.endsWith(Platform.pathSeparator) && path.length > 3) {
      path = path.substring(0, path.length - 1);
    }
    return Platform.isWindows ? path.toLowerCase() : path;
  }

  String _inferModelPreset(
    BackendPaths backend,
    String configuredPreset,
    String modelBase,
  ) {
    if (configuredPreset == customModelPreset) {
      return customModelPreset;
    }
    final preset = modelRepos.containsKey(configuredPreset)
        ? configuredPreset
        : 'large-v3';
    if (modelBase.trim().isEmpty) {
      return preset;
    }
    final configuredPath = _normalizeComparablePath(modelBase);
    final defaultPath =
        _normalizeComparablePath(_presetModelPath(backend, preset));
    if (configuredPath.isNotEmpty && configuredPath != defaultPath) {
      return customModelPreset;
    }
    return preset;
  }

  String? _initialDirectoryFor(
    String raw, {
    String fallback = '',
    bool treatAsFile = false,
  }) {
    final candidates = <String>[
      raw,
      fallback,
      _sourceController.text,
      _backend?.dataRoot.path ?? '',
    ];
    for (final candidate in candidates) {
      final value = candidate.trim();
      if (value.isEmpty) {
        continue;
      }
      final resolved = _resolveAgainstBackend(value);
      final directory = Directory(resolved);
      if (directory.existsSync()) {
        return directory.absolute.path;
      }
      final file = File(resolved);
      if (file.existsSync()) {
        return file.parent.absolute.path;
      }
      if (treatAsFile) {
        final parent = file.parent;
        if (parent.existsSync()) {
          return parent.absolute.path;
        }
      }
      var parent = directory.parent;
      while (parent.path != parent.parent.path) {
        if (parent.existsSync()) {
          return parent.absolute.path;
        }
        parent = parent.parent;
      }
    }
    return null;
  }

  double get _boundedProgress {
    if (_progress < 0) {
      return 0;
    }
    if (_progress > 1) {
      return 1;
    }
    return _progress;
  }

  Future<void> _saveConfig({bool quiet = false}) async {
    final backend = _backend;
    if (backend == null) {
      throw StateError('后端未就绪');
    }
    if (!(_formKey.currentState?.validate() ?? false)) {
      throw StateError('请先修正设置项');
    }

    final config = Map<String, dynamic>.from(_config)
      ..['src_root'] = _sourceController.text.trim()
      ..['dst_root'] = _outputController.text.trim()
      ..['model_preset'] = _modelPreset
      ..['model_base'] = _modelController.text.trim()
      ..['cache_dir'] = _cacheController.text.trim()
      ..['preserve_source_root_name'] = _preserveRoot
      ..['use_local_cache'] = _useLocalCache
      ..['delete_cache_after'] = _deleteCache
      ..['device'] = _device
      ..['compute_type'] = _computeType
      ..['http_proxy'] = _httpProxyController.text.trim()
      ..['https_proxy'] = _httpsProxyController.text.trim()
      ..['hf_endpoint'] = _hfEndpointController.text.trim()
      ..['max_chars_per_line'] = int.parse(_lineCharsController.text.trim())
      ..['max_chars_per_sentence'] =
          int.parse(_sentenceCharsController.text.trim())
      ..['max_sentence_duration'] =
          double.parse(_sentenceDurationController.text.trim())
      ..['gap_threshold'] = double.parse(_gapController.text.trim());

    await backend.config.parent.create(recursive: true);
    await backend.config.writeAsString(
      const JsonEncoder.withIndent('  ').convert(config),
    );
    if (mounted) {
      setState(() {
        _config = config;
        if (!quiet) {
          _appendLog('已保存配置：${backend.config.path}');
        }
      });
    }
  }

  void _scheduleConfigSave() {
    _configSaveDebounce?.cancel();
    _configSaveDebounce = Timer(const Duration(milliseconds: 600), () async {
      if (!mounted || _backend == null || _isBusy) {
        return;
      }
      try {
        await _saveConfig(quiet: true);
      } catch (error) {
        if (mounted) {
          setState(() => _appendLog('自动保存配置失败：$error'));
        }
      }
    });
  }

  Future<void> _pickDirectory(
    TextEditingController controller, {
    void Function(String selected)? onPicked,
  }) async {
    try {
      final selected = await FilePicker.getDirectoryPath(
        dialogTitle: '选择目录',
        lockParentWindow: true,
        initialDirectory: _initialDirectoryFor(controller.text),
      );
      if (selected != null) {
        setState(() {
          controller.text = selected;
          onPicked?.call(selected);
        });
      }
    } catch (error) {
      setState(() => _appendLog('打开目录选择器失败：$error'));
      _showMessage('打开目录选择器失败：$error');
    }
  }

  Future<void> _pickVideo() async {
    try {
      final selection = await FilePicker.pickFiles(
        dialogTitle: '选择视频或音频',
        initialDirectory: _initialDirectoryFor(
          _singleFileController.text,
          fallback: _sourceController.text,
          treatAsFile: true,
        ),
        lockParentWindow: true,
        type: FileType.custom,
        allowedExtensions: const ['mp4', 'mkv', 'mov', 'm4a', 'mp3', 'wav'],
      );
      final path = selection?.files.single.path;
      if (path != null) {
        setState(() => _singleFileController.text = path);
      }
    } catch (error) {
      setState(() => _appendLog('打开文件选择器失败：$error'));
      _showMessage('打开文件选择器失败：$error');
    }
  }

  void _applyModelPreset(String value) {
    _modelPreset = value;
    final backend = _backend;
    if (modelRepos.containsKey(value) && backend != null) {
      _modelController.text = _presetModelPath(backend, value);
    }
  }

  Future<void> _selectModelPreset(String value) async {
    setState(() => _applyModelPreset(value));
    try {
      await _saveConfig(quiet: true);
    } catch (error) {
      _showMessage('保存模型选择失败：$error');
    }
  }

  void _setCustomModelPath(String path) {
    _modelPreset = customModelPreset;
    _modelController.text = path;
    _scheduleConfigSave();
  }

  Future<void> _selectCustomModelPreset() async {
    setState(() => _modelPreset = customModelPreset);
    try {
      await _saveConfig(quiet: true);
    } catch (error) {
      _showMessage('保存模型选择失败：$error');
    }
  }

  void _markCustomModel() {
    if (_modelPreset != customModelPreset) {
      setState(() => _modelPreset = customModelPreset);
    }
    _scheduleConfigSave();
  }

  Future<void> _runTranscription(
      {bool repair = false, bool single = false}) async {
    if (_isBusy) {
      return;
    }
    if (!repair && _sourceController.text.trim().isEmpty && !single) {
      _showMessage('请先选择视频根目录');
      return;
    }
    if (single && _singleFileController.text.trim().isEmpty) {
      _showMessage('请先选择单个视频');
      return;
    }

    try {
      await _saveConfig();
      final args = <String>['--emit-progress'];
      if (repair) {
        args.add('--repair-existing');
      } else {
        if (single) {
          args.addAll(['--file', _singleFileController.text.trim()]);
        }
        final limit = _limitController.text.trim();
        if (limit.isNotEmpty) {
          args.addAll(['--limit', limit]);
        }
        if (_force) {
          args.add('--force');
        }
        if (_pushCloud) {
          args.add('--push-cloud');
        }
      }
      await _startProcess(args, title: repair ? '修复已有字幕' : '开始转录');
    } catch (error) {
      _showMessage('$error');
    }
  }

  Future<void> _downloadModel(String model) async {
    if (_isBusy) {
      return;
    }
    try {
      setState(() => _applyModelPreset(model));
      await _saveConfig();
      await _startProcess(
        ['--emit-progress', '--download-model', model],
        title: '下载 $model',
        downloading: true,
      );
    } catch (error) {
      _showMessage('$error');
    }
  }

  Future<void> _checkRuntime() async {
    if (_isBusy) {
      return;
    }
    try {
      await _saveConfig();
      await _startProcess(
        ['--emit-progress', '--check-runtime'],
        title: '环境自检',
      );
    } catch (error) {
      _showMessage('$error');
    }
  }

  Future<void> _startProcess(
    List<String> args, {
    required String title,
    bool downloading = false,
  }) async {
    final backend = _backend;
    if (backend == null) {
      throw StateError('后端未就绪');
    }
    final process = await backend.start(args);
    setState(() {
      _process = process;
      _isBusy = true;
      _progressIndeterminate = true;
      _progress = 0;
      _progressText = title;
      _currentVideo =
          downloading ? '当前阶段：准备下载模型 · $_modelPreset' : '当前阶段：$title';
      _appendLog('> ${backend.displayCommand} ${args.join(' ')}');
    });

    _stdoutSub = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_handleOutputLine);
    _stderrSub = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      if (mounted) {
        setState(() => _appendLog(line));
      }
    });

    final exitCode = await process.exitCode;
    await _stdoutSub?.cancel();
    await _stderrSub?.cancel();
    if (!mounted) {
      return;
    }
    setState(() {
      _process = null;
      _isBusy = false;
      _progressIndeterminate = false;
      _progress = exitCode == 0 ? 1 : _progress;
      _progressText = exitCode == 0 ? '任务完成' : '任务退出：$exitCode';
      _appendLog('进程结束，退出码 $exitCode');
    });
  }

  void _handleOutputLine(String line) {
    if (!mounted) {
      return;
    }
    final progressLine = line.trimLeft();
    if (progressLine.startsWith(progressPrefix)) {
      try {
        final event = jsonDecode(progressLine.substring(progressPrefix.length))
            as Map<String, dynamic>;
        _handleProgressEvent(event);
      } catch (_) {
        setState(() => _appendLog(line));
      }
      return;
    }
    setState(() => _appendLog(line));
  }

  void _handleProgressEvent(Map<String, dynamic> event) {
    final type = '${event['event'] ?? ''}';
    setState(() {
      switch (type) {
        case 'video_start':
          _progressIndeterminate = true;
          _progress = 0;
          _currentVideo =
              '当前视频：[${event['index']}/${event['total']}] ${event['name']}';
          _progressText = '准备转录';
          break;
        case 'progress':
          final percent = (event['percent'] as num?)?.toDouble() ?? 0;
          final stage = '${event['stage'] ?? '转录中'}';
          _progressIndeterminate = false;
          _progress = percent / 100;
          _progressText = '$stage ${percent.toStringAsFixed(0)}%  '
              '${event['current'] ?? 0}/${event['duration'] ?? 0}s';
          final name = '${event['name'] ?? ''}'.trim();
          if (name.isNotEmpty) {
            _currentVideo = '当前阶段：$stage · $name';
          }
          break;
        case 'stage':
          final percent = (event['percent'] as num?)?.toDouble();
          final stage = '${event['stage'] ?? '处理中'}';
          _progressIndeterminate = percent == null;
          if (percent != null) {
            _progress = percent / 100;
          }
          _progressText = stage;
          final name = '${event['name'] ?? ''}'.trim();
          _currentVideo = name.isEmpty ? '当前阶段：$stage' : '当前阶段：$stage · $name';
          _appendLog(name.isEmpty ? '阶段：$stage' : '阶段：$stage  $name');
          break;
        case 'video_done':
          final name = '${event['name'] ?? ''}'.trim();
          final status = '${event['status'] ?? ''}';
          _progressIndeterminate = false;
          _progress = 1;
          _progressText = status == 'skip'
              ? '已跳过当前视频'
              : status == 'fail'
                  ? '当前视频失败'
                  : '当前视频完成';
          if (name.isNotEmpty) {
            _currentVideo = '完成：$name';
          }
          break;
        case 'model_download_start':
          _progressIndeterminate = true;
          _currentVideo = '当前阶段：模型下载 · ${event['name']}';
          _progressText = '正在下载模型';
          _appendLog('阶段：模型下载  ${event['name']}');
          break;
        case 'runtime':
          _progressIndeterminate = true;
          _progressText =
              '加载模型（${event['device'] ?? '-'} / ${event['compute_type'] ?? '-'}）';
          _currentVideo = '当前阶段：模型加载';
          _appendLog(
            '运行设备：${event['device']}  计算精度：${event['compute_type']}',
          );
          break;
        case 'runtime_check':
          final ok = event['ok'] == true;
          _progressIndeterminate = false;
          _progress = 1;
          _progressText = ok ? '环境自检通过' : '环境自检发现问题';
          _currentVideo = ok ? '当前阶段：环境自检通过' : '当前阶段：环境自检发现问题';
          _appendLog(
            '环境自检：${ok ? '通过' : '未通过'}  '
            'CUDA 设备：${event['cuda_device_count'] ?? 0}  '
            '推荐：${event['device'] ?? '-'} / '
            '${event['compute_type'] ?? '-'}',
          );
          break;
        case 'model_download_done':
          _progressIndeterminate = false;
          _progress = 1;
          _progressText = '模型下载完成';
          _currentVideo = '完成：模型 ${event['name']}';
          _appendLog('模型下载完成：${event['target']}');
          break;
      }
    });
  }

  void _stopProcess() {
    final process = _process;
    if (process != null) {
      process.kill();
      setState(() {
        _progressIndeterminate = true;
        _progressText = '正在停止';
      });
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 960;
    const destinations = [
      NavigationRailDestination(
        icon: Icon(Icons.subtitles_outlined),
        selectedIcon: Icon(Icons.subtitles),
        label: Text('转录'),
      ),
      NavigationRailDestination(
        icon: Icon(Icons.download_outlined),
        selectedIcon: Icon(Icons.download),
        label: Text('模型'),
      ),
      NavigationRailDestination(
        icon: Icon(Icons.tune_outlined),
        selectedIcon: Icon(Icons.tune),
        label: Text('设置'),
      ),
    ];

    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            NavigationRail(
              extended: !compact,
              selectedIndex: _pageIndex,
              onDestinationSelected: (index) {
                setState(() => _pageIndex = index);
              },
              leading: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                child: compact
                    ? const Icon(Icons.closed_caption, size: 28)
                    : const Row(
                        children: [
                          Icon(Icons.closed_caption, size: 28),
                          SizedBox(width: 10),
                          Text(
                            'Video2Srt',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
              ),
              destinations: destinations,
              trailing: Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 64),
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: _isBusy
                        ? Tooltip(
                            message: '停止当前任务',
                            child: IconButton.filledTonal(
                              onPressed: _stopProcess,
                              style: IconButton.styleFrom(
                                fixedSize: const Size(64, 64),
                                iconSize: 32,
                              ),
                              icon: const Icon(Icons.stop_circle_outlined),
                            ),
                          )
                        : Tooltip(
                            message: '当前没有任务',
                            child: Container(
                              width: 58,
                              height: 58,
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.check_circle_outline,
                                size: 32,
                                color: Theme.of(context).colorScheme.outline,
                              ),
                            ),
                          ),
                  ),
                ),
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: Column(
                children: [
                  _TopBar(
                    title: ['转录工作台', '模型管理', '运行设置'][_pageIndex],
                    busy: _isBusy,
                    text: _progressText,
                  ),
                  Expanded(
                    child: Form(
                      key: _formKey,
                      child: IndexedStack(
                        index: _pageIndex,
                        children: [
                          _buildTranscribePage(),
                          _buildModelsPage(),
                          _buildSettingsPage(),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTranscribePage() {
    return _PageBody(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final logHeight = constraints.maxHeight < 760 ? 220.0 : 280.0;
          return ListView(
            children: [
              _SectionHeader(
                title: '任务',
                action: TextButton.icon(
                  onPressed: _isBusy ? null : _saveConfig,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('保存配置'),
                ),
              ),
              const SizedBox(height: 12),
              _PathField(
                label: '视频根目录',
                controller: _sourceController,
                icon: Icons.folder_open_outlined,
                onPick:
                    _isBusy ? null : () => _pickDirectory(_sourceController),
              ),
              const SizedBox(height: 12),
              _PathField(
                label: '字幕输出目录',
                controller: _outputController,
                icon: Icons.output_outlined,
                onPick:
                    _isBusy ? null : () => _pickDirectory(_outputController),
              ),
              const SizedBox(height: 12),
              _PathField(
                label: '单个视频',
                controller: _singleFileController,
                icon: Icons.movie_outlined,
                onPick: _isBusy ? null : _pickVideo,
                onClear: _isBusy
                    ? null
                    : () => setState(() => _singleFileController.clear()),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 130,
                    child: TextFormField(
                      controller: _limitController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '处理数量'),
                    ),
                  ),
                  FilterChip(
                    label: const Text('覆盖已有字幕'),
                    selected: _force,
                    onSelected: _isBusy
                        ? null
                        : (value) => setState(() => _force = value),
                  ),
                  FilterChip(
                    label: const Text('推送到云端'),
                    selected: _pushCloud,
                    onSelected: _isBusy
                        ? null
                        : (value) => setState(() => _pushCloud = value),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    onPressed: _isBusy ? null : () => _runTranscription(),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('批量转录'),
                  ),
                  OutlinedButton.icon(
                    onPressed:
                        _isBusy ? null : () => _runTranscription(single: true),
                    icon: const Icon(Icons.play_circle_outline),
                    label: const Text('转录单文件'),
                  ),
                  OutlinedButton.icon(
                    onPressed:
                        _isBusy ? null : () => _runTranscription(repair: true),
                    icon: const Icon(Icons.auto_fix_high_outlined),
                    label: const Text('修复已有字幕'),
                  ),
                ],
              ),
              const SizedBox(height: 30),
              const _SectionHeader(title: '当前进度'),
              const SizedBox(height: 10),
              Text(
                _currentVideo,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                minHeight: 9,
                borderRadius: BorderRadius.circular(999),
                backgroundColor:
                    Theme.of(context).colorScheme.surfaceContainerHighest,
                color: Theme.of(context).colorScheme.primary,
                value: _progressIndeterminate ? null : _boundedProgress,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _progressText,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  if (!_progressIndeterminate && _isBusy)
                    Text(
                      '${(_boundedProgress * 100).round()}%',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                ],
              ),
              const SizedBox(height: 30),
              const _SectionHeader(title: '运行日志'),
              const SizedBox(height: 10),
              SizedBox(
                height: logHeight,
                child: _LogPanel(
                  controller: _logScrollController,
                  lines: _logs,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildModelsPage() {
    final backend = _backend;
    return _PageBody(
      child: ListView(
        children: [
          const _SectionHeader(title: 'faster-whisper 模型'),
          const SizedBox(height: 20),
          for (final entry in modelRepos.entries) ...[
            _ModelRow(
              name: entry.key,
              repo: entry.value,
              groupValue: _modelPreset,
              path: backend == null ? '' : _presetModelPath(backend, entry.key),
              onSelect: _isBusy
                  ? null
                  : () => unawaited(_selectModelPreset(entry.key)),
              onDownload: _isBusy ? null : () => _downloadModel(entry.key),
            ),
            const Divider(height: 1),
          ],
          const SizedBox(height: 24),
          RadioListTile<String>(
            contentPadding: EdgeInsets.zero,
            value: customModelPreset,
            groupValue: _modelPreset,
            onChanged:
                _isBusy ? null : (_) => unawaited(_selectCustomModelPreset()),
            title: const Text('自定义模型目录'),
          ),
          _PathField(
            label: '自定义模型目录',
            controller: _modelController,
            icon: Icons.folder_special_outlined,
            onPick: _isBusy
                ? null
                : () => _pickDirectory(
                      _modelController,
                      onPicked: _setCustomModelPath,
                    ),
            onChanged: (_) => _markCustomModel(),
          ),
          const SizedBox(height: 12),
          Text(
            _modelPreset == customModelPreset
                ? '已选模型：自定义目录'
                : '已选模型：$_modelPreset',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsPage() {
    return _PageBody(
      child: ListView(
        children: [
          _SectionHeader(
            title: '硬件与缓存',
            action: OutlinedButton.icon(
              onPressed: _isBusy ? null : _checkRuntime,
              icon: const Icon(Icons.health_and_safety_outlined),
              label: const Text('环境自检'),
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth > 680;
              final fields = [
                DropdownButtonFormField<String>(
                  value: _device,
                  decoration: const InputDecoration(labelText: '运行设备'),
                  items: const [
                    DropdownMenuItem(value: 'auto', child: Text('自动选择')),
                    DropdownMenuItem(value: 'cuda', child: Text('CUDA')),
                    DropdownMenuItem(value: 'cpu', child: Text('CPU')),
                  ],
                  onChanged: _isBusy
                      ? null
                      : (value) => setState(() => _device = value ?? 'auto'),
                ),
                DropdownButtonFormField<String>(
                  value: _computeType,
                  decoration: const InputDecoration(labelText: '计算精度'),
                  items: const [
                    DropdownMenuItem(value: 'default', child: Text('默认')),
                    DropdownMenuItem(value: 'float16', child: Text('float16')),
                    DropdownMenuItem(
                      value: 'int8_float16',
                      child: Text('int8_float16'),
                    ),
                    DropdownMenuItem(value: 'int8', child: Text('int8')),
                    DropdownMenuItem(value: 'float32', child: Text('float32')),
                  ],
                  onChanged: _isBusy
                      ? null
                      : (value) =>
                          setState(() => _computeType = value ?? 'default'),
                ),
              ];
              return wide
                  ? Row(
                      children: [
                        Expanded(child: fields[0]),
                        const SizedBox(width: 12),
                        Expanded(child: fields[1]),
                      ],
                    )
                  : Column(
                      children: [
                        fields[0],
                        const SizedBox(height: 12),
                        fields[1],
                      ],
                    );
            },
          ),
          const SizedBox(height: 12),
          _PathField(
            label: '本地视频缓存目录',
            controller: _cacheController,
            icon: Icons.storage_outlined,
            onPick: _isBusy ? null : () => _pickDirectory(_cacheController),
          ),
          const SizedBox(height: 6),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('使用本地视频缓存'),
            value: _useLocalCache,
            onChanged: _isBusy
                ? null
                : (value) => setState(() => _useLocalCache = value),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('任务完成后删除缓存'),
            value: _deleteCache,
            onChanged: _isBusy
                ? null
                : (value) => setState(() => _deleteCache = value),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('输出时保留视频根目录名'),
            value: _preserveRoot,
            onChanged: _isBusy
                ? null
                : (value) => setState(() => _preserveRoot = value),
          ),
          if (_manifest.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '后端包：${_manifest['backend_mode'] ?? '-'} / '
                '${_manifest['package_profile'] ?? '-'}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
          const SizedBox(height: 28),
          const _SectionHeader(title: '模型下载'),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth > 680;
              final fields = [
                TextFormField(
                  controller: _httpProxyController,
                  decoration: const InputDecoration(labelText: 'HTTP 代理'),
                ),
                TextFormField(
                  controller: _httpsProxyController,
                  decoration: const InputDecoration(labelText: 'HTTPS 代理'),
                ),
                TextFormField(
                  controller: _hfEndpointController,
                  decoration: const InputDecoration(labelText: 'HF Endpoint'),
                ),
              ];
              if (!wide) {
                return Column(
                  children: [
                    fields[0],
                    const SizedBox(height: 12),
                    fields[1],
                    const SizedBox(height: 12),
                    fields[2],
                  ],
                );
              }
              return Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: fields[0]),
                      const SizedBox(width: 12),
                      Expanded(child: fields[1]),
                    ],
                  ),
                  const SizedBox(height: 12),
                  fields[2],
                ],
              );
            },
          ),
          const SizedBox(height: 28),
          const _SectionHeader(title: '断句'),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth > 680;
              final fields = [
                _NumberField(
                  label: '单行字数',
                  controller: _lineCharsController,
                  integer: true,
                ),
                _NumberField(
                  label: '单条字数',
                  controller: _sentenceCharsController,
                  integer: true,
                ),
                _NumberField(
                  label: '单条秒数',
                  controller: _sentenceDurationController,
                ),
                _NumberField(
                  label: '停顿阈值（秒）',
                  controller: _gapController,
                ),
              ];
              return GridView.count(
                crossAxisCount: wide ? 2 : 1,
                shrinkWrap: true,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: wide ? 4.6 : 5,
                physics: const NeverScrollableScrollPhysics(),
                children: fields,
              );
            },
          ),
          const SizedBox(height: 24),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _isBusy
                  ? null
                  : () async {
                      try {
                        await _saveConfig();
                        _showMessage('配置已保存');
                      } catch (error) {
                        _showMessage('$error');
                      }
                    },
              icon: const Icon(Icons.save_outlined),
              label: const Text('保存设置'),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.busy,
    required this.text,
  });

  final String title;
  final bool busy;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          if (busy)
            Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Text(text, style: Theme.of(context).textTheme.labelLarge),
              ],
            ),
        ],
      ),
    );
  }
}

class _PageBody extends StatelessWidget {
  const _PageBody({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Center(
          child: SizedBox(
            width: constraints.maxWidth > 1120 ? 1120 : constraints.maxWidth,
            height: constraints.maxHeight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
              child: child,
            ),
          ),
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.action});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        if (action != null) action!,
      ],
    );
  }
}

class _LogPanel extends StatelessWidget {
  const _LogPanel({
    required this.controller,
    required this.lines,
  });

  final ScrollController controller;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          fontFamily: 'Consolas',
          height: 1.45,
        );
    return Container(
      color: colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.all(14),
      child: Scrollbar(
        controller: controller,
        thumbVisibility: lines.length > 6,
        child: SingleChildScrollView(
          controller: controller,
          child: Align(
            alignment: Alignment.topLeft,
            child: SelectableText(
              lines.isEmpty ? '等待任务输出' : lines.join('\n'),
              style: textStyle,
            ),
          ),
        ),
      ),
    );
  }
}

class _PathField extends StatelessWidget {
  const _PathField({
    required this.label,
    required this.controller,
    required this.icon,
    required this.onPick,
    this.onClear,
    this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final IconData icon;
  final VoidCallback? onPick;
  final VoidCallback? onClear;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      minLines: 1,
      maxLines: 1,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Tooltip(
              message: '选择$label',
              child: IconButton(
                onPressed: onPick,
                icon: const Icon(Icons.folder_open_outlined),
              ),
            ),
            if (onClear != null)
              Tooltip(
                message: '清空$label',
                child: IconButton(
                  onPressed: onClear,
                  icon: const Icon(Icons.clear),
                ),
              ),
          ],
        ),
      ),
      validator: (value) {
        if (label == '字幕输出目录' && (value == null || value.trim().isEmpty)) {
          return '请输入输出目录';
        }
        return null;
      },
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.label,
    required this.controller,
    this.integer = false,
  });

  final String label;
  final TextEditingController controller;
  final bool integer;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: label),
      validator: (value) {
        final raw = value?.trim() ?? '';
        final number = integer ? int.tryParse(raw) : double.tryParse(raw);
        return number == null ? '请输入有效数值' : null;
      },
    );
  }
}

class _ModelRow extends StatelessWidget {
  const _ModelRow({
    required this.name,
    required this.repo,
    required this.path,
    required this.groupValue,
    required this.onSelect,
    required this.onDownload,
  });

  final String name;
  final String repo;
  final String path;
  final String groupValue;
  final VoidCallback? onSelect;
  final VoidCallback? onDownload;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Radio<String>(
            value: name,
            groupValue: groupValue,
            onChanged: onSelect == null ? null : (_) => onSelect!(),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: InkWell(
              onTap: onSelect,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 3),
                  Text(repo, style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 3),
                  Text(
                    path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.tonalIcon(
            onPressed: onDownload,
            icon: const Icon(Icons.download_outlined),
            label: const Text('下载'),
          ),
        ],
      ),
    );
  }
}
