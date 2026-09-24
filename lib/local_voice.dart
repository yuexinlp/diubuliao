import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

class SenseVoiceModelPaths {
  static const assetRoot =
      'assets/models/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2025-09-09';
  static const modelAsset = '$assetRoot/model.int8.onnx';
  static const tokensAsset = '$assetRoot/tokens.txt';
  static const modelDirectoryName = 'sensevoice';
}

class LocalVoiceRecognizer {
  LocalVoiceRecognizer({AudioRecorder? recorder})
    : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;
  sherpa.OfflineRecognizer? _recognizer;
  String? _recordingPath;
  bool _bindingsInitialized = false;

  bool get isRecording => _recordingPath != null;

  Future<void> start({void Function(String message)? onStatus}) async {
    await _prepareModel(onStatus: onStatus);
    if (!await _recorder.hasPermission()) {
      throw StateError('需要麦克风权限');
    }

    final tempDirectory = await getTemporaryDirectory();
    final path =
        '${tempDirectory.path}${Platform.pathSeparator}voice_query.wav';
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
        noiseSuppress: true,
        echoCancel: true,
      ),
      path: path,
    );
    _recordingPath = path;
  }

  Future<String> stopAndRecognize({
    void Function(String message)? onStatus,
  }) async {
    final path = await _recorder.stop();
    final recordingPath = path ?? _recordingPath;
    _recordingPath = null;
    if (recordingPath == null) {
      throw StateError('没有正在进行的录音');
    }
    onStatus?.call('正在分析声音...');

    final recognizer = _recognizer;
    if (recognizer == null) {
      throw StateError('本地语音模型尚未准备好');
    }
    final wave = sherpa.readWave(recordingPath);
    if (wave.samples.isEmpty || wave.sampleRate <= 0) {
      throw StateError('录音文件为空');
    }

    final stream = recognizer.createStream();
    try {
      stream.acceptWaveform(samples: wave.samples, sampleRate: wave.sampleRate);
      recognizer.decode(stream);
      return recognizer.getResult(stream).text.trim();
    } finally {
      stream.free();
      try {
        await File(recordingPath).delete();
      } catch (_) {
        // The temporary recording is best-effort cleanup only.
      }
    }
  }

  Future<void> dispose() async {
    if (_recordingPath != null) {
      await _recorder.cancel();
      _recordingPath = null;
    }
    _recognizer?.free();
    _recognizer = null;
    await _recorder.dispose();
  }

  Future<void> _prepareModel({void Function(String message)? onStatus}) async {
    if (_recognizer != null) return;

    onStatus?.call('正在准备本地语音模型...');
    final supportDirectory = await getApplicationSupportDirectory();
    final modelDirectory = Directory(
      '${supportDirectory.path}${Platform.pathSeparator}${SenseVoiceModelPaths.modelDirectoryName}',
    );
    await modelDirectory.create(recursive: true);

    final modelPath = await _copyAssetIfNeeded(
      SenseVoiceModelPaths.modelAsset,
      '${modelDirectory.path}${Platform.pathSeparator}model.int8.onnx',
    );
    final tokensPath = await _copyAssetIfNeeded(
      SenseVoiceModelPaths.tokensAsset,
      '${modelDirectory.path}${Platform.pathSeparator}tokens.txt',
    );

    if (!_bindingsInitialized) {
      sherpa.initBindings();
      _bindingsInitialized = true;
    }

    final senseVoice = sherpa.OfflineSenseVoiceModelConfig(
      model: modelPath,
      language: '',
      useInverseTextNormalization: true,
    );
    final model = sherpa.OfflineModelConfig(
      senseVoice: senseVoice,
      tokens: tokensPath,
      numThreads: 2,
      debug: false,
    );
    _recognizer = sherpa.OfflineRecognizer(
      sherpa.OfflineRecognizerConfig(model: model),
    );
  }

  Future<String> _copyAssetIfNeeded(String asset, String destination) async {
    final file = File(destination);
    if (await file.exists() && await file.length() > 0) {
      return destination;
    }
    final data = await rootBundle.load(asset);
    await file.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );
    return destination;
  }
}
