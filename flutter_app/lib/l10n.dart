import 'package:flutter/material.dart';

enum AppLanguage {
  chinese,
  english,
}

extension AppLanguageData on AppLanguage {
  Locale get locale {
    return this == AppLanguage.chinese
        ? const Locale('zh', 'CN')
        : const Locale('en', 'US');
  }

  String get code {
    return this == AppLanguage.chinese ? 'zh-CN' : 'en-US';
  }
}

AppLanguage appLanguageFromCode(String? code) {
  return code == 'en-US' ? AppLanguage.english : AppLanguage.chinese;
}

class AppStrings {
  const AppStrings(this.language);

  final AppLanguage language;

  String text(String chinese, String english) {
    return language == AppLanguage.chinese ? chinese : english;
  }

  String get navTranscribe => text('转录', 'Transcribe');
  String get navModels => text('模型', 'Models');
  String get navSettings => text('设置', 'Settings');
  String get transcribeWorkbench => text('转录工作台', 'Transcription');
  String get modelManagement => text('模型管理', 'Model management');
  String get runtimeSettings => text('运行设置', 'Runtime settings');
  String get stopCurrentTask => text('停止当前任务', 'Stop current task');
  String get noCurrentTask => text('当前没有任务', 'No active task');
  String get task => text('任务', 'Task');
  String get saveConfig => text('保存配置', 'Save config');
  String get videoRoot => text('视频根目录', 'Video root');
  String get subtitleOutput => text('字幕输出目录', 'Subtitle output');
  String get singleVideo => text('单个视频', 'Single video');
  String get processingLimit => text('处理数量', 'Limit');
  String get forceExisting => text('覆盖已有字幕', 'Overwrite existing');
  String get pushToSource => text('推送到源目录', 'Copy to source folder');
  String get batchTranscribe => text('批量转录', 'Batch transcribe');
  String get singleTranscribe => text('转录单文件', 'Transcribe file');
  String get repairSubtitles => text('修复已有字幕', 'Repair subtitles');
  String get currentProgress => text('当前进度', 'Current progress');
  String get currentVideo => text('当前视频', 'Current video');
  String get runLog => text('运行日志', 'Run log');
  String get modelTitle => text('faster-whisper 模型', 'faster-whisper models');
  String get customModelDirectory => text('自定义模型目录', 'Custom model directory');
  String get selectedCustomModel =>
      text('已选模型：自定义目录', 'Selected model: custom directory');
  String selectedModel(String name) =>
      text('已选模型：$name', 'Selected model: $name');
  String get hardwareAndCache => text('硬件与缓存', 'Hardware and cache');
  String get environmentCheck => text('环境自检', 'Check environment');
  String get runtimeDevice => text('运行设备', 'Runtime device');
  String get automatic => text('自动选择', 'Auto');
  String get computeType => text('计算精度', 'Compute type');
  String get defaultValue => text('默认', 'Default');
  String get localVideoCache => text('本地视频缓存目录', 'Local video cache');
  String get useLocalCache => text('使用本地视频缓存', 'Use local video cache');
  String get deleteCache => text('任务完成后删除缓存', 'Delete cache after task');
  String get preserveRoot => text('输出时保留视频根目录名', 'Preserve source root name');
  String backendPackage(String mode, String profile) =>
      text('后端包：$mode / $profile', 'Backend package: $mode / $profile');
  String get modelDownload => text('模型下载', 'Model download');
  String get httpProxy => text('HTTP 代理', 'HTTP proxy');
  String get httpsProxy => text('HTTPS 代理', 'HTTPS proxy');
  String get hfEndpoint => text('HF Endpoint', 'HF endpoint');
  String get sentenceBreaking => text('断句', 'Sentence splitting');
  String get lineChars => text('单行字数', 'Characters per line');
  String get sentenceChars => text('单条字数', 'Characters per caption');
  String get sentenceDuration => text('单条秒数', 'Caption duration');
  String get gapThreshold => text('停顿阈值（秒）', 'Pause threshold (s)');
  String get saveSettings => text('保存设置', 'Save settings');
  String get interfaceSettings => text('界面', 'Interface');
  String get interfaceLanguage => text('界面语言', 'Interface language');
  String get simplifiedChinese => text('简体中文', 'Simplified Chinese');
  String get english => 'English';
  String get download => text('下载', 'Download');
  String get waitingTask => text('等待任务', 'Waiting for task');
  String get waitingOutput => text('等待任务输出', 'Waiting for task output');
  String get currentVideoDash => text('当前视频：-', 'Current video: -');
  String currentVideoValue(String value) =>
      text('当前视频：$value', 'Current video: $value');
  String currentStage(String value) => text('当前阶段：$value', 'Stage: $value');
  String completedValue(String value) => text('完成：$value', 'Completed: $value');
  String get chooseDirectory => text('选择目录', 'Choose directory');
  String get chooseVideoAudio => text('选择视频或音频', 'Choose video or audio');
  String choose(String label) => text('选择$label', 'Choose $label');
  String clear(String label) => text('清空$label', 'Clear $label');
  String get outputDirectoryRequired =>
      text('请输入输出目录', 'Enter an output directory');
  String get validNumberRequired => text('请输入有效数值', 'Enter a valid number');
  String get configSaved => text('配置已保存', 'Config saved');
  String get noVideoRoot => text('请先选择视频根目录', 'Choose a video root first');
  String get noSingleVideo => text('请先选择单个视频', 'Choose a single video first');
  String get emptyBackend => text('后端未就绪', 'Backend is not ready');
  String get fixSettings => text('请先修正设置项', 'Fix the settings first');
  String get emptyModel => text('等待任务', 'Waiting for task');
  String get downloadingModel => text('正在下载模型', 'Downloading model');
  String get modelDownloadComplete => text('模型下载完成', 'Model download complete');
  String get modelReady =>
      text('模型就绪，开始转录', 'Model ready, starting transcription');
  String get transcribing => text('正在转录', 'Transcribing');
  String get localCacheReady => text('本地缓存就绪', 'Local cache ready');
  String get copyingToCache => text('复制到本地缓存', 'Copying to local cache');
  String get reusingCache => text('复用本地缓存', 'Reusing local cache');
  String get loadingModel => text('加载模型', 'Loading model');
  String get modelLoading => text('模型加载', 'Model loading');
  String get modelUnavailable => text('模型不可用', 'Model unavailable');
  String get taskComplete => text('任务完成', 'Task complete');
  String get taskFailed => text('任务失败', 'Task failed');
  String get allComplete => text('全部完成', 'All complete');
  String get preparingTranscription => text('准备转录', 'Preparing transcription');
  String get currentVideoComplete => text('当前视频完成', 'Current video complete');
  String get currentVideoSkipped => text('已跳过当前视频', 'Current video skipped');
  String get currentVideoFailed => text('当前视频失败', 'Current video failed');
  String get transcriptionRetrying => text('转录重试中', 'Retrying transcription');
  String get transcriptionRetry => text('转录重试', 'Transcription retry');
  String get stopping => text('正在停止', 'Stopping');
  String get backendStartingFailed => text('后端启动失败', 'Backend failed to start');
  String taskExit(int code) => text('任务退出：$code', 'Task exited: $code');
  String stage(String value) => text(value, _stageEnglish(value));
  String stageWithName(String stage, String name) =>
      text('当前阶段：$stage · $name', 'Stage: ${_stageEnglish(stage)} · $name');
  String stageOnly(String stage) =>
      text('当前阶段：$stage', 'Stage: ${_stageEnglish(stage)}');
  String progressStage(
          String stage, double percent, Object current, Object duration) =>
      text(
        '$stage ${percent.toStringAsFixed(0)}%  $current/${duration}s',
        '${_stageEnglish(stage)} ${percent.toStringAsFixed(0)}%  $current/${duration}s',
      );
  String activityStage(String stage, Object elapsed) => text(
      '$stage（已运行 $elapsed 秒）', '${_stageEnglish(stage)} ($elapsed s elapsed)');

  String get startTranscription => text('开始转录', 'Start transcription');
  String downloadModel(String model) => text('下载 $model', 'Download $model');
  String get startingBackend => text('启动后端', 'Starting backend');
  String get waitingBackend => text('等待后端响应', 'Waiting for backend');
  String get preparingModelDownload =>
      text('准备下载模型', 'Preparing model download');
  String get waitingModelDownload =>
      text('等待模型下载响应', 'Waiting for model download');
  String taskLog(String value) => text('任务：$value', 'Task: $value');
  String stageLog(String stage, [String name = '']) => name.isEmpty
      ? text('阶段：$stage', 'Stage: ${_stageEnglish(stage)}')
      : text('阶段：$stage  $name', 'Stage: ${_stageEnglish(stage)}  $name');
  String get initializationFailed => text('初始化失败', 'Initialization failed');
  String get backendDirectory => text('后端目录', 'Backend directory');
  String get backendCommand => text('后端命令', 'Backend command');
  String get configFile => text('配置文件', 'Config file');
  String get backendNotFound =>
      text('未找到后端程序', 'Backend executable was not found');
  String get directoryPickerFailed =>
      text('打开目录选择器失败', 'Could not open directory picker');
  String get filePickerFailed =>
      text('打开文件选择器失败', 'Could not open file picker');
  String get modelSelectionSaveFailed =>
      text('保存模型选择失败', 'Could not save model selection');
  String get autoSaveFailed =>
      text('自动保存配置失败', 'Could not save configuration automatically');
  String get outputDecodeFailed =>
      text('读取后端输出失败', 'Could not read backend output');
  String backendProcessStarted(int pid) =>
      text('后端进程已启动，PID：$pid', 'Backend process started, PID: $pid');
  String backendNoOutputWaiting(int seconds) => text(
      '后端已启动，等待输出 $seconds 秒',
      'Backend started, waiting for output for $seconds s');
  String backendNoOutputLog(int pid, int seconds) => text(
      '后端进程 $pid 已启动，但 $seconds 秒内没有 stdout/stderr 输出',
      'Backend process $pid started, but produced no stdout/stderr for $seconds s');
  String configSavedTo(String path) =>
      text('已保存配置：$path', 'Saved config: $path');
  String processExited(int code) =>
      text('进程结束，退出码 $code', 'Process exited with code $code');
  String currentVideoIndexed(int index, int total, String name) => text(
      '当前视频：[$index/$total] $name', 'Current video: [$index/$total] $name');
  String get preparingVideo => text('准备转录', 'Preparing transcription');
  String videoStatus(String status) {
    switch (status) {
      case 'ok':
        return text('已完成', 'Completed');
      case 'skip':
        return text('已跳过', 'Skipped');
      case 'fail':
        return text('失败', 'Failed');
      default:
        return text('进行中', 'In progress');
    }
  }

  String videoProgressSummary(int completed, int total) =>
      text('视频详情（$completed/$total）', 'Video details ($completed/$total)');
  String get batchProgress => text('批量进度', 'Batch progress');
  String get estimatedRemainingCalculating =>
      text('预计剩余时间：估算中', 'Estimated remaining: calculating');
  String estimatedRemaining(String value) =>
      text('预计剩余时间：$value', 'Estimated remaining: $value');
  String get calculatingProgress => text('计算中', 'Calculating');
  String get activeVideoProgress => text('当前视频进度', 'Current video progress');

  String get videoProgressHint =>
      text('每个视频的阶段与转录进度', 'Stage and transcription progress for each video');
  String videoItemLabel(int index, int total) =>
      text('视频 $index/$total', 'Video $index/$total');
  String videoPosition(Object current, Object duration) =>
      text('$current / $duration 秒', '$current / $duration s');
  String labelValue(String label, String value) =>
      text('$label：$value', '$label: $value');
  String failure(String prefix, Object error) =>
      text('$prefix：$error', '$prefix: $error');
  String batchVideoStatus(String status, int index, int total) {
    switch (status) {
      case 'OK':
        return text('完成 $index/$total', 'Completed $index/$total');
      case 'SKIP':
        return text('跳过 $index/$total', 'Skipped $index/$total');
      default:
        return text('失败 $index/$total', 'Failed $index/$total');
    }
  }

  String modelName(String name) => text('模型 $name', 'Model $name');
  String runtimeLog(String device, String computeType) =>
      text('运行环境：$device / $computeType', 'Runtime: $device / $computeType');
  String runtimeCheckLog(bool ok, Object cudaDeviceCount) {
    final chineseResult = ok ? '通过' : '发现问题';
    final englishResult = ok ? 'OK' : 'Failed';
    return text(
      '环境自检：$chineseResult  CUDA：$cudaDeviceCount',
      'Runtime check: $englishResult  CUDA: $cudaDeviceCount',
    );
  }

  String modelDownloadLog(String target) =>
      text('模型下载完成：$target', 'Model download complete: $target');

  String _stageEnglish(String value) {
    const translations = {
      '扫描视频': 'Scanning videos',
      '加载模型': 'Loading model',
      '模型就绪，开始转录': 'Model ready, starting transcription',
      '准备下载模型': 'Preparing model download',
      '下载模型文件': 'Downloading model files',
      '准备视频文件': 'Preparing video',
      '正在初始化音频解码': 'Initializing audio decoding',
      '正在识别音频': 'Recognizing audio',
      '使用原始视频文件': 'Using source video',
      '复用本地缓存': 'Reusing local cache',
      '复制到本地缓存': 'Copying to local cache',
      '本地缓存就绪': 'Local cache ready',
      '转录中': 'Transcribing',
      '等待转录进度': 'Waiting for transcription',
      '写入字幕': 'Writing subtitles',
      '处理中': 'Processing',
      '模型下载': 'Model download',
      '模型加载': 'Model loading',
      '模型不可用': 'Model unavailable',
      '加载模型失败': 'Model loading failed',
      '环境自检通过': 'Environment check passed',
      '环境自检发现问题': 'Environment check found issues',
      'CUDA 初始化失败，改用 CPU 加载模型': 'CUDA initialization failed, loading on CPU',
    };
    if (value.startsWith('加载模型（共 ')) {
      return 'Loading model';
    }
    return translations[value] ?? value;
  }
}
