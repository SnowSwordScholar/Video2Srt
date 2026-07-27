import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'l10n.dart';

const String progressPrefix = '__VIDEO2SRT_PROGRESS__ ';
const String customModelPreset = 'custom';
const String windowsFontFamily = 'Microsoft YaHei UI';
const List<String> windowsFontFallback = [
  'Microsoft YaHei',
  'SimHei',
  'SimSun',
  'Segoe UI',
];
const Map<String, String> modelRepos = {
  'large-v2': 'Systran/faster-whisper-large-v2',
  'large-v3': 'Systran/faster-whisper-large-v3',
};
final ValueNotifier<AppLanguage> appLanguageNotifier =
    ValueNotifier<AppLanguage>(AppLanguage.chinese);

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

    return ValueListenableBuilder<AppLanguage>(
      valueListenable: appLanguageNotifier,
      builder: (context, language, _) {
        final locale = language.locale;
        return MaterialApp(
          title: 'Video2Srt',
          debugShowCheckedModeBanner: false,
          locale: locale,
          supportedLocales: const [
            Locale('zh', 'CN'),
            Locale('en', 'US'),
          ],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          builder: (context, child) {
            final content = child ?? const SizedBox.shrink();
            if (!Platform.isWindows) {
              return content;
            }
            return DefaultTextStyle.merge(
              style: TextStyle(
                fontFamily: windowsFontFamily,
                fontFamilyFallback: windowsFontFallback,
                locale: locale,
              ),
              child: content,
            );
          },
          theme: ThemeData(
            useMaterial3: true,
            fontFamily: Platform.isWindows ? windowsFontFamily : null,
            fontFamilyFallback: Platform.isWindows ? windowsFontFallback : null,
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
      },
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
      ..._ancestorDirectories(executableDir),
      ..._ancestorDirectories(Directory.current),
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

  static Iterable<Directory> _ancestorDirectories(Directory start) sync* {
    var current = start.absolute;
    while (true) {
      yield current;
      final parent = current.parent;
      if (parent.path == current.path) {
        return;
      }
      current = parent;
    }
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
        'PYTHONUNBUFFERED': '1',
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
  StreamSubscription<List<int>>? _stdoutSub;
  StreamSubscription<List<int>>? _stderrSub;
  Timer? _backendOutputWatchdog;

  bool _backendReportedFailure = false;
  bool _receivedBackendOutput = false;
  int _pageIndex = 0;
  String _modelPreset = 'large-v3';
  String _device = 'auto';
  String _computeType = 'default';
  bool _preserveRoot = true;
  bool _useLocalCache = true;
  bool _deleteCache = true;
  bool _force = false;
  bool _pushToSource = false;
  bool _isBusy = false;
  bool _progressIndeterminate = false;
  double _progress = 0;
  String _progressText = '';
  String _currentVideo = '';
  DateTime? _batchEstimateStartedAt;
  int? _batchEstimateFirstVideoIndex;
  int? _batchEstimateTotal;
  double _batchEstimateFirstVideoPercent = 0;

  AppLanguage _language = AppLanguage.chinese;
  final List<String> _logs = [];
  final List<_VideoProgress> _videoProgresses = [];
  Timer? _configSaveDebounce;

  AppStrings get _s => AppStrings(_language);

  @override
  void initState() {
    super.initState();
    _loadWorkspace();
  }

  @override
  void dispose() {
    _stdoutSub?.cancel();
    _stderrSub?.cancel();
    _backendOutputWatchdog?.cancel();

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
      final language =
          appLanguageFromCode('${config['ui_language'] ?? 'zh-CN'}');
      appLanguageNotifier.value = language;
      setState(() {
        _backend = backend;
        _config = config;
        _manifest = manifest;
        _language = language;
        _progressText = _s.waitingTask;
        _currentVideo = _s.currentVideoDash;
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
        _pushToSource = config['push_to_source'] == true;
        _appendLog(_s.labelValue(_s.backendDirectory, backend.root.path));
        _appendLog(_s.labelValue(_s.backendCommand, backend.displayCommand));
        _appendLog(_s.labelValue(_s.configFile, backend.config.path));
        if (manifest.isNotEmpty) {
          _appendLog(
            _s.backendPackage(
              (manifest['backend_mode'] ?? '-').toString(),
              (manifest['package_profile'] ?? '-').toString(),
            ),
          );
        }
      });
    } catch (error) {
      if (mounted) {
        setState(() => _appendLog(_s.failure(_s.initializationFailed, error)));
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
      throw StateError(_s.emptyBackend);
    }
    if (!(_formKey.currentState?.validate() ?? false)) {
      throw StateError(_s.fixSettings);
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
      ..['push_to_source'] = _pushToSource
      ..['ui_language'] = _language.code
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
          setState(() => _appendLog(_s.failure(_s.autoSaveFailed, error)));
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
        dialogTitle: _s.chooseDirectory,
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
      setState(() => _appendLog(_s.failure(_s.directoryPickerFailed, error)));
      _showMessage(_s.failure(_s.directoryPickerFailed, error));
    }
  }

  Future<void> _pickVideo() async {
    try {
      final selection = await FilePicker.pickFiles(
        dialogTitle: _s.chooseVideoAudio,
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
      setState(() => _appendLog(_s.failure(_s.filePickerFailed, error)));
      _showMessage(_s.failure(_s.filePickerFailed, error));
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
      _showMessage(_s.failure(_s.modelSelectionSaveFailed, error));
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
      _showMessage(_s.failure(_s.modelSelectionSaveFailed, error));
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
      _showMessage(_s.noVideoRoot);
      return;
    }
    if (single && _singleFileController.text.trim().isEmpty) {
      _showMessage(_s.noSingleVideo);
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
        if (_pushToSource) {
          args.add('--push-source');
        }
      }
      await _startProcess(
        args,
        title: repair ? _s.repairSubtitles : _s.startTranscription,
      );
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
        title: _s.downloadModel(model),
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
        title: _s.environmentCheck,
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
      throw StateError(_s.emptyBackend);
    }
    final initialStage =
        downloading ? _s.preparingModelDownload : _s.startingBackend;
    final waitingStage =
        downloading ? _s.waitingModelDownload : _s.waitingBackend;
    final commandArgs = [
      ...backend.baseArgs,
      '--config',
      backend.config.path,
      ...args
    ];

    setState(() {
      _isBusy = true;
      _progressIndeterminate = true;
      _progress = 0;
      _backendReportedFailure = false;
      _receivedBackendOutput = false;
      _videoProgresses.clear();
      _batchEstimateStartedAt = null;
      _batchEstimateFirstVideoIndex = null;
      _batchEstimateTotal = null;
      _batchEstimateFirstVideoPercent = 0;
      _progressText = initialStage;
      _currentVideo = downloading
          ? _s.stageWithName(initialStage, _modelPreset)
          : _s.stageOnly(initialStage);
      _appendLog(_s.taskLog(title));
      _appendLog(
        _s.stageLog(initialStage, downloading ? _modelPreset : ''),
      );
      _appendLog('> ${backend.executable} ${commandArgs.join(' ')}');
    });

    late final Process process;
    try {
      process = await backend.start(args);
    } catch (error) {
      if (mounted) {
        setState(() {
          _process = null;
          _isBusy = false;
          _progressIndeterminate = false;
          _progressText = _s.backendStartingFailed;
          _currentVideo = _s.stageOnly(_s.backendStartingFailed);
          _appendLog(_s.failure(_s.backendStartingFailed, error));
        });
      }
      rethrow;
    }

    setState(() {
      _process = process;
      _progressText = waitingStage;
      _currentVideo = downloading
          ? _s.stageWithName(waitingStage, _modelPreset)
          : _s.stageOnly(waitingStage);
      _appendLog(_s.backendProcessStarted(process.pid));
      _appendLog(
        _s.stageLog(waitingStage, downloading ? _modelPreset : ''),
      );
    });
    _startBackendOutputWatchdog(process.pid, waitingStage);

    final stdoutDone = Completer<void>();
    final stderrDone = Completer<void>();
    final stdoutLines = _ProcessLineCollector((line) {
      _markBackendOutputReceived();
      _handleOutputLine(line);
    });
    final stderrLines = _ProcessLineCollector((line) {
      _markBackendOutputReceived();
      if (mounted) {
        setState(() {
          _appendLog(line);
        });
      }
    });

    _stdoutSub = process.stdout.listen(
      stdoutLines.add,
      onError: (Object error, StackTrace stackTrace) {
        if (mounted) {
          setState(() => _appendLog(_s.failure(_s.outputDecodeFailed, error)));
        }
      },
      onDone: () {
        stdoutLines.close();
        if (!stdoutDone.isCompleted) {
          stdoutDone.complete();
        }
      },
      cancelOnError: false,
    );
    _stderrSub = process.stderr.listen(
      stderrLines.add,
      onError: (Object error, StackTrace stackTrace) {
        if (mounted) {
          setState(() => _appendLog(_s.failure(_s.outputDecodeFailed, error)));
        }
      },
      onDone: () {
        stderrLines.close();
        if (!stderrDone.isCompleted) {
          stderrDone.complete();
        }
      },
      cancelOnError: false,
    );

    final exitCode = await process.exitCode;

    _backendOutputWatchdog?.cancel();
    _backendOutputWatchdog = null;
    try {
      await Future.wait([stdoutDone.future, stderrDone.future])
          .timeout(const Duration(seconds: 2));
    } catch (_) {
      // The process has already exited; do not let a stuck pipe keep the UI busy.
    }
    await _stdoutSub?.cancel();
    await _stderrSub?.cancel();
    if (!mounted) {
      return;
    }
    setState(() {
      _process = null;
      _isBusy = false;
      _progressIndeterminate = false;
      if (exitCode == 0 && !_backendReportedFailure) {
        _progress = 1;
      }
      if (!_backendReportedFailure) {
        _progressText = exitCode == 0 ? _s.taskComplete : _s.taskExit(exitCode);
      }
      _appendLog(_s.processExited(exitCode));
    });
  }

  void _markBackendOutputReceived() {
    _receivedBackendOutput = true;
  }

  void _startBackendOutputWatchdog(int pid, String waitingStage) {
    _backendOutputWatchdog?.cancel();
    final startedAt = DateTime.now();
    var lastLoggedAt = 0;
    _backendOutputWatchdog = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!mounted || !_isBusy || _process == null) {
        timer.cancel();
        return;
      }
      if (_receivedBackendOutput) {
        timer.cancel();
        return;
      }
      final elapsed = DateTime.now().difference(startedAt).inSeconds;
      setState(() {
        _progressText = _s.backendNoOutputWaiting(elapsed);
        _currentVideo = _s.stageOnly(waitingStage);
        if (elapsed >= 10 && elapsed - lastLoggedAt >= 20) {
          lastLoggedAt = elapsed;
          _appendLog(_s.backendNoOutputLog(pid, elapsed));
        }
      });
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

  int _eventInt(Map<String, dynamic> event, String key) {
    final value = event[key];
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  double? _eventDouble(Map<String, dynamic> event, String key) {
    final value = event[key];
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '');
  }

  void _upsertVideoProgress({
    required int index,
    required int total,
    String? name,
    String? stage,
    double? percent,
    String? status,
    double? current,
    double? duration,
  }) {
    if (index <= 0) {
      return;
    }
    final position =
        _videoProgresses.indexWhere((video) => video.index == index);
    if (position < 0) {
      _videoProgresses.add(
        _VideoProgress(
          index: index,
          total: total,
          name: name == null || name.trim().isEmpty
              ? _s.videoItemLabel(index, total)
              : name.trim(),
          stage: stage ?? '',
          percent: percent ?? 0,
          status: status ?? 'running',
          current: current,
          duration: duration,
        ),
      );
    } else {
      final video = _videoProgresses[position];
      if (total > 0) {
        video.total = total;
      }
      if (name != null && name.trim().isNotEmpty) {
        video.name = name.trim();
      }
      if (stage != null) {
        video.stage = stage;
      }
      if (percent != null) {
        video.percent = percent.clamp(0, 100).toDouble();
      }
      if (status != null) {
        video.status = status;
      }
      if (current != null) {
        video.current = current;
      }
      if (duration != null) {
        video.duration = duration;
      }
    }
    _videoProgresses.sort((left, right) => left.index.compareTo(right.index));
  }

  void _setOverallProgress(int index, int total, double percent) {
    if (index <= 0 || total <= 0) {
      return;
    }
    final clipped = percent.clamp(0, 100).toDouble();
    _progress = ((index - 1) + (clipped / 100)) / total;
  }

  void _recordBatchEstimateProgress(int index, int total, double percent) {
    if (_batchEstimateStartedAt != null || index <= 0 || total <= 0) {
      return;
    }
    _batchEstimateStartedAt = DateTime.now();
    _batchEstimateFirstVideoIndex = index;
    _batchEstimateTotal = total;
    _batchEstimateFirstVideoPercent = percent.clamp(0, 100).toDouble();
  }

  String _batchEstimateText() {
    if (!_isBusy && _progress >= 1 && !_backendReportedFailure) {
      return _s.estimatedRemaining(_formatEstimateDuration(Duration.zero));
    }

    final startedAt = _batchEstimateStartedAt;
    final firstIndex = _batchEstimateFirstVideoIndex;
    final total = _batchEstimateTotal;
    if (!_isBusy || startedAt == null || firstIndex == null || total == null) {
      return _s.estimatedRemainingCalculating;
    }

    _VideoProgress? active;
    for (final video in _videoProgresses) {
      if (video.status == 'running') {
        active = video;
        break;
      }
    }
    final activeFraction = active == null
        ? 0.0
        : active.percent.clamp(0, 100).toDouble() / 100;
    final completedWork = _videoProgresses
            .where(
              (video) =>
                  video.index >= firstIndex &&
                  (video.status == 'ok' || video.status == 'fail'),
            )
            .length +
        activeFraction -
        (_batchEstimateFirstVideoPercent / 100);
    if (completedWork <= 0.01) {
      return _s.estimatedRemainingCalculating;
    }

    final terminalCount =
        _videoProgresses.where((video) => video.isTerminal).length;
    final remainingWork = total - terminalCount - activeFraction;
    if (remainingWork <= 0) {
      return _s.estimatedRemaining(_formatEstimateDuration(Duration.zero));
    }

    final elapsedMilliseconds =
        DateTime.now().difference(startedAt).inMilliseconds;
    if (elapsedMilliseconds <= 0) {
      return _s.estimatedRemainingCalculating;
    }
    final remainingMilliseconds =
        (elapsedMilliseconds * remainingWork / completedWork).round();
    return _s.estimatedRemaining(
      _formatEstimateDuration(Duration(milliseconds: remainingMilliseconds)),
    );
  }

  String _formatEstimateDuration(Duration duration) {
    final seconds = duration.inSeconds.clamp(0, 99 * 24 * 60 * 60).toInt();
    final days = seconds ~/ (24 * 60 * 60);
    final hours = (seconds % (24 * 60 * 60)) ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    if (_language == AppLanguage.chinese) {
      if (days > 0) {
        return '$days 天 $hours 小时';
      }
      if (hours > 0) {
        return '$hours 小时 $minutes 分钟';
      }
      if (minutes > 0) {
        return '$minutes 分钟';
      }
      return '$seconds 秒';
    }
    if (days > 0) {
      return '${days}d ${hours}h';
    }
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    if (minutes > 0) {
      return '${minutes}m';
    }
    return '${seconds}s';
  }

  void _handleProgressEvent(Map<String, dynamic> event) {
    final type = (event['event'] ?? '').toString();
    final s = _s;
    setState(() {
      switch (type) {
        case 'video_start':
          final index = _eventInt(event, 'index');
          final total = _eventInt(event, 'total');
          final name = (event['name'] ?? '').toString().trim();
          _upsertVideoProgress(
            index: index,
            total: total,
            name: name,
            stage: '准备视频文件',
            percent: 0,
            status: 'running',
          );
          _progressIndeterminate = true;
          _setOverallProgress(index, total, 0);
          _currentVideo = s.currentVideoIndexed(index, total, name);
          _progressText = s.preparingVideo;
          break;
        case 'progress':
          final index = _eventInt(event, 'index');
          final total = _eventInt(event, 'total');
          final percent = _eventDouble(event, 'percent') ?? 0;
          final stage = (event['stage'] ?? '转录中').toString();
          final name = (event['name'] ?? '').toString().trim();
          final current = _eventDouble(event, 'current');
          final duration = _eventDouble(event, 'duration');
          _upsertVideoProgress(
            index: index,
            total: total,
            name: name,
            stage: stage,
            percent: percent,
            status: 'running',
            current: current,
            duration: duration,
          );
          _progressIndeterminate = false;
          _setOverallProgress(index, total, percent);
          _recordBatchEstimateProgress(index, total, percent);
          _progressText = s.progressStage(
            stage,
            percent,
            current ?? 0,
            duration ?? 0,
          );
          if (name.isNotEmpty) {
            _currentVideo = s.stageWithName(stage, name);
          }
          break;
        case 'stage':
          final index = _eventInt(event, 'index');
          final total = _eventInt(event, 'total');
          final percent = _eventDouble(event, 'percent');
          final stage = (event['stage'] ?? '处理中').toString();
          final name = (event['name'] ?? '').toString().trim();
          _upsertVideoProgress(
            index: index,
            total: total,
            name: name,
            stage: stage,
            percent: percent,
            status: 'running',
          );
          _progressIndeterminate = percent == null;
          if (percent != null) {
            _setOverallProgress(index, total, percent);
          }
          _progressText = s.stage(stage);
          _currentVideo =
              name.isEmpty ? s.stageOnly(stage) : s.stageWithName(stage, name);
          _appendLog(s.stageLog(stage, name));
          break;
        case 'video_done':
          final index = _eventInt(event, 'index');
          final total = _eventInt(event, 'total');
          final name = (event['name'] ?? '').toString().trim();
          final status = (event['status'] ?? '').toString();
          _upsertVideoProgress(
            index: index,
            total: total,
            name: name,
            percent: status == 'fail' ? null : 100,
            status: status,
          );
          _progressIndeterminate = false;
          _setOverallProgress(index, total, 100);
          _progressText = s.videoStatus(status);
          if (name.isNotEmpty) {
            _currentVideo = s.currentVideoValue(name);
          }
          break;
        case 'activity':
          final index = _eventInt(event, 'index');
          final total = _eventInt(event, 'total');
          final name = (event['name'] ?? '').toString().trim();
          final stage = (event['stage'] ?? '处理中').toString();
          final elapsed = _eventInt(event, 'elapsed');
          final percent = _eventDouble(event, 'percent');
          final current = _eventDouble(event, 'current');
          final duration = _eventDouble(event, 'duration');
          _upsertVideoProgress(
            index: index,
            total: total,
            name: name,
            stage: stage,
            percent: percent,
            current: current,
            duration: duration,
            status: 'running',
          );
          if (percent != null) {
            _progressIndeterminate = false;
            _setOverallProgress(index, total, percent);
          }
          _progressText = s.activityStage(stage, elapsed);
          if (name.isNotEmpty) {
            _currentVideo = s.stageWithName(stage, name);
          }
          break;
        case 'error':
          final stage = (event['stage'] ?? '任务失败').toString();
          final error = (event['error'] ?? '').toString().trim();
          final name = (event['name'] ?? '').toString().trim();
          _backendReportedFailure = true;
          _progressIndeterminate = false;
          _progressText = s.stage(stage);
          _currentVideo =
              name.isEmpty ? s.stageOnly(stage) : s.stageWithName(stage, name);
          if (error.isNotEmpty) {
            _appendLog(s.failure(s.stage(stage), error));
          }
          break;
        case 'model_download_start':
          final name = (event['name'] ?? '').toString();
          _progressIndeterminate = true;
          _currentVideo = s.stageWithName('模型下载', name);
          _progressText = s.downloadingModel;
          _appendLog(s.stageLog('模型下载', name));
          break;
        case 'runtime':
          final device = (event['device'] ?? '-').toString();
          final computeType = (event['compute_type'] ?? '-').toString();
          _progressIndeterminate = true;
          _progressText = '${s.loadingModel} ($device / $computeType)';
          _currentVideo = s.stageOnly('模型加载');
          _appendLog(s.runtimeLog(device, computeType));
          break;
        case 'runtime_check':
          final environmentOk = event['ok'] == true;
          final transcriptionReady = event['transcription_ready'] == true;
          final modelError = (event['model_error'] ?? '').toString().trim();
          final modelPath = (event['model_path'] ?? '').toString().trim();
          final passed = environmentOk && transcriptionReady;
          _backendReportedFailure = !passed;
          _progressIndeterminate = false;
          _progress = passed ? 1 : 0;
          _progressText = passed
              ? s.stage('环境自检通过')
              : transcriptionReady
                  ? s.stage('环境自检发现问题')
                  : s.modelUnavailable;
          _currentVideo = s.stageOnly(
            passed
                ? '环境自检通过'
                : transcriptionReady
                    ? '环境自检发现问题'
                    : '模型不可用',
          );
          _appendLog(
            s.runtimeCheckLog(passed, event['cuda_device_count'] ?? 0),
          );
          if (!transcriptionReady) {
            _appendLog(
              s.failure(
                s.modelUnavailable,
                modelError.isNotEmpty ? modelError : modelPath,
              ),
            );
          }
          break;
        case 'model_download_done':
          final name = (event['name'] ?? '').toString();
          _progressIndeterminate = false;
          _progress = 1;
          _progressText = s.modelDownloadComplete;
          _currentVideo = s.completedValue(s.modelName(name));
          _appendLog(s.modelDownloadLog((event['target'] ?? '').toString()));
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
        _progressText = _s.stopping;
      });
    }
  }

  void _setLanguage(AppLanguage language) {
    setState(() {
      _language = language;
      _config = Map<String, dynamic>.from(_config)
        ..['ui_language'] = language.code;
      appLanguageNotifier.value = language;
      if (!_isBusy) {
        _progressText = _s.waitingTask;
        _currentVideo = _s.currentVideoDash;
      }
    });
    _scheduleConfigSave();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 960;
    final s = _s;
    final destinations = [
      NavigationRailDestination(
        icon: const Icon(Icons.subtitles_outlined),
        selectedIcon: const Icon(Icons.subtitles),
        label: Text(s.navTranscribe),
      ),
      NavigationRailDestination(
        icon: const Icon(Icons.download_outlined),
        selectedIcon: const Icon(Icons.download),
        label: Text(s.navModels),
      ),
      NavigationRailDestination(
        icon: const Icon(Icons.tune_outlined),
        selectedIcon: const Icon(Icons.tune),
        label: Text(s.navSettings),
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
                            message: s.stopCurrentTask,
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
                            message: s.noCurrentTask,
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
                    title: [
                      s.transcribeWorkbench,
                      s.modelManagement,
                      s.runtimeSettings,
                    ][_pageIndex],
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
    final s = _s;
    final _VideoProgress? activeVideo = _videoProgresses.isEmpty
        ? null
        : _videoProgresses.lastWhere(
            (video) => !video.isTerminal,
            orElse: () => _videoProgresses.last,
          );
    final activeVideoHasTimeline =
        activeVideo?.duration != null && activeVideo!.duration! > 0;
    return _PageBody(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final logHeight = constraints.maxHeight < 760 ? 220.0 : 280.0;
          return ListView(
            children: [
              _SectionHeader(
                title: s.task,
                action: TextButton.icon(
                  onPressed: _isBusy ? null : _saveConfig,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(s.saveConfig),
                ),
              ),
              const SizedBox(height: 12),
              _PathField(
                label: s.videoRoot,
                controller: _sourceController,
                icon: Icons.folder_open_outlined,
                onPick:
                    _isBusy ? null : () => _pickDirectory(_sourceController),
              ),
              const SizedBox(height: 12),
              _PathField(
                label: s.subtitleOutput,
                controller: _outputController,
                icon: Icons.output_outlined,
                onPick:
                    _isBusy ? null : () => _pickDirectory(_outputController),
                requiredMessage: s.outputDirectoryRequired,
              ),
              const SizedBox(height: 12),
              _PathField(
                label: s.singleVideo,
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
                      decoration: InputDecoration(labelText: s.processingLimit),
                    ),
                  ),
                  FilterChip(
                    label: Text(s.forceExisting),
                    selected: _force,
                    onSelected: _isBusy
                        ? null
                        : (value) => setState(() => _force = value),
                  ),
                  FilterChip(
                    label: Text(s.pushToSource),
                    selected: _pushToSource,
                    onSelected: _isBusy
                        ? null
                        : (value) => setState(() => _pushToSource = value),
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
                    label: Text(s.batchTranscribe),
                  ),
                  OutlinedButton.icon(
                    onPressed:
                        _isBusy ? null : () => _runTranscription(single: true),
                    icon: const Icon(Icons.play_circle_outline),
                    label: Text(s.singleTranscribe),
                  ),
                  OutlinedButton.icon(
                    onPressed:
                        _isBusy ? null : () => _runTranscription(repair: true),
                    icon: const Icon(Icons.auto_fix_high_outlined),
                    label: Text(s.repairSubtitles),
                  ),
                ],
              ),
              const SizedBox(height: 30),
              _SectionHeader(title: s.currentProgress),
              const SizedBox(height: 10),
              Text(
                _currentVideo,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              if (activeVideo != null) ...[
                const SizedBox(height: 10),
                Text(
                  s.activeVideoProgress,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${s.videoItemLabel(activeVideo.index, activeVideo.total)}  ${activeVideo.isTerminal ? s.videoStatus(activeVideo.status) : s.stage(activeVideo.stage)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      activeVideoHasTimeline
                          ? '${activeVideo.percent.toStringAsFixed(0)}%  ${s.videoPosition(activeVideo.current ?? 0, activeVideo.duration!)}'
                          : s.calculatingProgress,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  minHeight: 7,
                  borderRadius: BorderRadius.circular(999),
                  value: activeVideoHasTimeline || activeVideo.isTerminal
                      ? activeVideo.percent.clamp(0, 100).toDouble() / 100
                      : null,
                ),
              ],
              const SizedBox(height: 12),
              Text(
                s.batchProgress,
                style: Theme.of(context).textTheme.bodySmall,
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
                      _batchEstimateText(),
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
              if (_videoProgresses.isNotEmpty) ...[
                const SizedBox(height: 14),
                _VideoProgressPanel(
                  videos: _videoProgresses,
                  strings: s,
                ),
              ],
              const SizedBox(height: 30),
              _SectionHeader(title: s.runLog),
              const SizedBox(height: 10),
              SizedBox(
                height: logHeight,
                child: _LogPanel(
                  controller: _logScrollController,
                  lines: _logs,
                  emptyText: s.waitingOutput,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildModelsPage() {
    final s = _s;
    final backend = _backend;
    return _PageBody(
      child: ListView(
        children: [
          _SectionHeader(title: s.modelTitle),
          const SizedBox(height: 20),
          for (final entry in modelRepos.entries) ...[
            _ModelRow(
              name: entry.key,
              repo: entry.value,
              groupValue: _modelPreset,
              path: backend == null ? '' : _presetModelPath(backend, entry.key),
              downloadLabel: s.download,
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
            title: Text(s.customModelDirectory),
          ),
          _PathField(
            label: s.customModelDirectory,
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
                ? s.selectedCustomModel
                : s.selectedModel(_modelPreset),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsPage() {
    final s = _s;
    return _PageBody(
      child: ListView(
        children: [
          _SectionHeader(title: s.interfaceSettings),
          const SizedBox(height: 12),
          DropdownButtonFormField<AppLanguage>(
            value: _language,
            decoration: InputDecoration(labelText: s.interfaceLanguage),
            items: [
              DropdownMenuItem(
                value: AppLanguage.chinese,
                child: Text(s.simplifiedChinese),
              ),
              DropdownMenuItem(
                value: AppLanguage.english,
                child: Text(s.english),
              ),
            ],
            onChanged: _isBusy
                ? null
                : (value) {
                    if (value != null) {
                      _setLanguage(value);
                    }
                  },
          ),
          const SizedBox(height: 28),
          _SectionHeader(
            title: s.hardwareAndCache,
            action: OutlinedButton.icon(
              onPressed: _isBusy ? null : _checkRuntime,
              icon: const Icon(Icons.health_and_safety_outlined),
              label: Text(s.environmentCheck),
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth > 680;
              final List<Widget> fields = [
                DropdownButtonFormField<String>(
                  value: _device,
                  decoration: InputDecoration(labelText: s.runtimeDevice),
                  items: [
                    DropdownMenuItem(value: 'auto', child: Text(s.automatic)),
                    const DropdownMenuItem(value: 'cuda', child: Text('CUDA')),
                    const DropdownMenuItem(value: 'cpu', child: Text('CPU')),
                  ],
                  onChanged: _isBusy
                      ? null
                      : (value) => setState(() => _device = value ?? 'auto'),
                ),
                DropdownButtonFormField<String>(
                  value: _computeType,
                  decoration: InputDecoration(labelText: s.computeType),
                  items: [
                    DropdownMenuItem(
                      value: 'default',
                      child: Text(s.defaultValue),
                    ),
                    const DropdownMenuItem(
                      value: 'float16',
                      child: Text('float16'),
                    ),
                    const DropdownMenuItem(
                      value: 'int8_float16',
                      child: Text('int8_float16'),
                    ),
                    const DropdownMenuItem(value: 'int8', child: Text('int8')),
                    const DropdownMenuItem(
                      value: 'float32',
                      child: Text('float32'),
                    ),
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
            label: s.localVideoCache,
            controller: _cacheController,
            icon: Icons.storage_outlined,
            onPick: _isBusy ? null : () => _pickDirectory(_cacheController),
          ),
          const SizedBox(height: 6),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(s.useLocalCache),
            value: _useLocalCache,
            onChanged: _isBusy
                ? null
                : (value) => setState(() => _useLocalCache = value),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(s.deleteCache),
            value: _deleteCache,
            onChanged: _isBusy
                ? null
                : (value) => setState(() => _deleteCache = value),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(s.preserveRoot),
            value: _preserveRoot,
            onChanged: _isBusy
                ? null
                : (value) => setState(() => _preserveRoot = value),
          ),
          if (_manifest.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                s.backendPackage(
                  '${_manifest['backend_mode'] ?? '-'}',
                  '${_manifest['package_profile'] ?? '-'}',
                ),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
          const SizedBox(height: 28),
          _SectionHeader(title: s.modelDownload),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth > 680;
              final List<Widget> fields = [
                TextFormField(
                  controller: _httpProxyController,
                  decoration: InputDecoration(labelText: s.httpProxy),
                ),
                TextFormField(
                  controller: _httpsProxyController,
                  decoration: InputDecoration(labelText: s.httpsProxy),
                ),
                TextFormField(
                  controller: _hfEndpointController,
                  decoration: InputDecoration(labelText: s.hfEndpoint),
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
          _SectionHeader(title: s.sentenceBreaking),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth > 680;
              final List<Widget> fields = [
                _NumberField(
                  label: s.lineChars,
                  controller: _lineCharsController,
                  integer: true,
                  invalidMessage: s.validNumberRequired,
                ),
                _NumberField(
                  label: s.sentenceChars,
                  controller: _sentenceCharsController,
                  integer: true,
                  invalidMessage: s.validNumberRequired,
                ),
                _NumberField(
                  label: s.sentenceDuration,
                  controller: _sentenceDurationController,
                  invalidMessage: s.validNumberRequired,
                ),
                _NumberField(
                  label: s.gapThreshold,
                  controller: _gapController,
                  invalidMessage: s.validNumberRequired,
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
                        _showMessage(s.configSaved);
                      } catch (error) {
                        _showMessage('$error');
                      }
                    },
              icon: const Icon(Icons.save_outlined),
              label: Text(s.saveSettings),
            ),
          ),
        ],
      ),
    );
  }
}

class _VideoProgress {
  _VideoProgress({
    required this.index,
    required this.total,
    required this.name,
    required this.stage,
    required this.percent,
    required this.status,
    this.current,
    this.duration,
  });

  final int index;
  int total;
  String name;
  String stage;
  double percent;
  String status;
  double? current;
  double? duration;

  bool get isTerminal => status == 'ok' || status == 'skip' || status == 'fail';
}

class _VideoProgressPanel extends StatelessWidget {
  const _VideoProgressPanel({
    required this.videos,
    required this.strings,
  });

  final List<_VideoProgress> videos;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final total = videos.fold<int>(
      0,
      (maxTotal, video) => video.total > maxTotal ? video.total : maxTotal,
    );
    final completed = videos.where((video) => video.isTerminal).length;
    final visibleTotal = total > 0 ? total : videos.length;
    final height = videos.length > 3 ? 252.0 : videos.length * 84.0;
    final colorScheme = Theme.of(context).colorScheme;

    return ExpansionTile(
      initiallyExpanded: false,
      tilePadding: EdgeInsets.zero,
      childrenPadding: EdgeInsets.zero,
      title: Text(strings.videoProgressSummary(completed, visibleTotal)),
      subtitle: Text(
        strings.videoProgressHint,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      children: [
        SizedBox(
          height: height,
          child: ListView.separated(
            primary: false,
            itemCount: videos.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final video = videos[index];
              final IconData icon;
              final Color iconColor;
              switch (video.status) {
                case 'ok':
                  icon = Icons.check_circle_outline;
                  iconColor = colorScheme.primary;
                  break;
                case 'skip':
                  icon = Icons.skip_next_outlined;
                  iconColor = colorScheme.secondary;
                  break;
                case 'fail':
                  icon = Icons.error_outline;
                  iconColor = colorScheme.error;
                  break;
                default:
                  icon = Icons.play_circle_outline;
                  iconColor = colorScheme.tertiary;
              }
              final position = video.current != null && video.duration != null
                  ? '  ${strings.videoPosition(video.current!, video.duration!)}'
                  : '';
              final hasTimeline = video.duration != null && video.duration! > 0;
              final progressValue =
                  video.isTerminal || hasTimeline || video.percent > 0
                      ? video.percent.clamp(0, 100).toDouble() / 100
                      : null;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, color: iconColor),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            video.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${strings.videoItemLabel(video.index, video.total)}  '
                            '${video.isTerminal ? strings.videoStatus(video.status) : strings.stage(video.stage)}$position',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 7),
                          LinearProgressIndicator(
                            value: progressValue,
                            minHeight: 5,
                            color: iconColor,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${video.percent.toStringAsFixed(0)}%',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
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

class _ProcessLineCollector {
  _ProcessLineCollector(this.onLine);

  final void Function(String line) onLine;
  final List<int> _buffer = [];

  void add(List<int> chunk) {
    for (final byte in chunk) {
      if (byte == 10) {
        _flush();
      } else {
        _buffer.add(byte);
      }
    }
  }

  void close() {
    if (_buffer.isNotEmpty) {
      _flush();
    }
  }

  void _flush() {
    final bytes = List<int>.from(_buffer);
    _buffer.clear();
    if (bytes.isNotEmpty && bytes.last == 13) {
      bytes.removeLast();
    }
    onLine(_decodeLine(bytes));
  }

  String _decodeLine(List<int> bytes) {
    try {
      return utf8.decode(bytes, allowMalformed: false);
    } catch (_) {
      try {
        return systemEncoding.decode(bytes);
      } catch (_) {
        return utf8.decode(bytes, allowMalformed: true);
      }
    }
  }
}

class _LogPanel extends StatelessWidget {
  const _LogPanel({
    required this.controller,
    required this.lines,
    required this.emptyText,
  });

  final ScrollController controller;
  final List<String> lines;
  final String emptyText;

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
              lines.isEmpty ? emptyText : lines.join('\n'),
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
    this.requiredMessage,
  });

  final String label;
  final TextEditingController controller;
  final IconData icon;
  final VoidCallback? onPick;
  final VoidCallback? onClear;
  final ValueChanged<String>? onChanged;
  final String? requiredMessage;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings(appLanguageNotifier.value);
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
              message: strings.choose(label),
              child: IconButton(
                onPressed: onPick,
                icon: const Icon(Icons.folder_open_outlined),
              ),
            ),
            if (onClear != null)
              Tooltip(
                message: strings.clear(label),
                child: IconButton(
                  onPressed: onClear,
                  icon: const Icon(Icons.clear),
                ),
              ),
          ],
        ),
      ),
      validator: (value) {
        if (requiredMessage != null &&
            (value == null || value.trim().isEmpty)) {
          return requiredMessage;
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
    required this.invalidMessage,
  });

  final String label;
  final TextEditingController controller;
  final bool integer;
  final String invalidMessage;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: label),
      validator: (value) {
        final raw = value?.trim() ?? '';
        final number = integer ? int.tryParse(raw) : double.tryParse(raw);
        return number == null ? invalidMessage : null;
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
    required this.downloadLabel,
  });

  final String name;
  final String repo;
  final String path;
  final String groupValue;
  final VoidCallback? onSelect;
  final VoidCallback? onDownload;
  final String downloadLabel;

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
            label: Text(downloadLabel),
          ),
        ],
      ),
    );
  }
}
