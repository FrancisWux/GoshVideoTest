import 'dart:async';
import 'dart:io';

import 'package:awesome_video_kit/awesome_video_kit.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const VideoDecodeDemoApp());
}

class VideoDecodeDemoApp extends StatelessWidget {
  const VideoDecodeDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GoshVideoTest',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const VideoDecodeDemoPage(),
    );
  }
}

class VideoDecodeDemoPage extends StatefulWidget {
  const VideoDecodeDemoPage({super.key});

  @override
  State<VideoDecodeDemoPage> createState() => _VideoDecodeDemoPageState();
}

class _VideoDecodeDemoPageState extends State<VideoDecodeDemoPage> {
  final List<String> _logs = <String>[];
  StreamSubscription<int>? _progressSubscription;
  StreamSubscription<NativeLogEntry>? _nativeLogSubscription;
  File? _inputFile;
  String? _outputPath;
  double _progress = 0;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _nativeLogSubscription = AwesomeVideoKit.nativeLogStream.listen(
      (entry) {
        if (entry.isError) {
          _addLog('ERROR', '[AwesomeVideoKit] ${entry.message}');
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        _addLog(
          'ERROR',
          'AwesomeVideoKit native log stream failed',
          error: error,
          stackTrace: stackTrace,
        );
      },
    );
    _addLog('INFO', 'Demo started');
    _addLog('INFO', 'awesome_video_kit ref=v0.0.5');
    _addLog('INFO', 'Flow / Flujo: Select local video / Seleccionar video local → Read media info / Leer información multimedia → Transcode to MP4 / Convertir a MP4 → Read output media info / Leer información multimedia de salida');
  }

  @override
  void dispose() {
    _progressSubscription?.cancel();
    _nativeLogSubscription?.cancel();
    super.dispose();
  }

  void _addLog(String level, String message, {Object? error, StackTrace? stackTrace}) {
    final timestamp = DateTime.now().toIso8601String();
    final lines = <String>['[$timestamp] [$level] $message'];
    if (error != null) {
      lines.add('error_type=${error.runtimeType}');
      lines.add('error=$error');
    }
    if (stackTrace != null) {
      lines.add('stack_trace:');
      lines.add(stackTrace.toString());
    }
    if (!mounted) return;
    setState(() => _logs.add(lines.join('\n')));
  }

  Future<void> _pickVideo() async {
    if (_working) return;
    _addLog('INFO', 'Opening video picker');
    try {
      final result = await ImagePicker().pickVideo(source: ImageSource.gallery);
      if (!mounted || result == null) {
        _addLog('INFO', 'Video picker cancelled');
        return;
      }
      final path = result.path;
      if (path.isEmpty) throw StateError('Selected video has no readable local path.');
      final file = File(path);
      final exists = await file.exists();
      if (!exists) throw StateError('Selected video does not exist: $path');
      final bytes = await file.length();
      setState(() {
        _inputFile = file;
        _outputPath = null;
        _progress = 0;
      });
      _addLog(
        'INFO',
        'Video selected path=$path size_mb=${(bytes / 1000000).toStringAsFixed(3)}',
      );
    } catch (error, stackTrace) {
      _addLog('ERROR', 'Video picker failed', error: error, stackTrace: stackTrace);
    }
  }

  Future<void> _transcode() async {
    final inputFile = _inputFile;
    if (_working || inputFile == null) return;

    setState(() {
      _working = true;
      _progress = 0;
      _outputPath = null;
    });
    _addLog('INFO', 'Transcode task started input=${inputFile.path}');

    Directory? workDirectory;
    try {
      final sourceInfo = await _readMediaInfo(inputFile.path, 'source');
      final sourceStream = sourceInfo.videoStreams.first;
      final dimensions = _rotatedDimensions(sourceStream);
      final policy = _buildTranscodePolicy(sourceStream, dimensions);
      _addLog(
        'INFO',
        'Transcode options width=${policy.width} height=${policy.height} '
            'bitrate=${policy.bitrate} frame_rate=${policy.frameRate} '
            'apply_display_rotation=true',
      );

      workDirectory = await Directory.systemTemp.createTemp('gosh_video_demo_');
      final outputFile = File('${workDirectory.path}/transcoded.mp4');
      _addLog('INFO', 'Output path=${outputFile.path}');

      _progressSubscription = AwesomeVideoKit.transcodeProgressStream.listen(
        (percent) {
          if (!mounted || !_working) return;
          final nextProgress = (percent / 100).clamp(0.0, 1.0);
          setState(() => _progress = nextProgress);
        },
        onError: (Object error, StackTrace stackTrace) {
          _addLog(
            'WARN',
            'Transcode progress stream error',
            error: error,
            stackTrace: stackTrace,
          );
        },
      );

      final outputPath = await AwesomeVideoKit.transcodeVideo(
        inputPath: inputFile.path,
        outputPath: outputFile.path,
        options: VideoTranscodeOptions(
          videoWidth: policy.width,
          videoHeight: policy.height,
          videoBitrate: policy.bitrate,
          frameRate: policy.frameRate,
          applyDisplayRotation: true,
          faststart: true,
        ),
      );
      _addLog('INFO', 'Native transcode returned output=$outputPath');

      final output = File(outputPath);
      final outputBytes = await output.length();
      _addLog(
        'INFO',
        'Output file verified exists=${await output.exists()} '
            'size_mb=${(outputBytes / 1000000).toStringAsFixed(3)}',
      );
      final outputInfo = await _readMediaInfo(outputPath, 'output');
      final outputStream = outputInfo.videoStreams.first;
      final outputDimensions = _rotatedDimensions(outputStream);
      if (outputDimensions.width <= 0 || outputDimensions.height <= 0) {
        throw StateError('Output video dimensions are invalid.');
      }
      setState(() {
        _progress = 1;
        _outputPath = outputPath;
      });
      _addLog(
        'SUCCESS',
        'Decode and transcode verification passed '
            'output_resolution=${outputDimensions.width}x${outputDimensions.height}',
      );
      _showResultSnackBar('Transcode succeeded / Conversión completada');
    } catch (error, stackTrace) {
      _addLog('ERROR', 'Decode or transcode verification failed', error: error, stackTrace: stackTrace);
      _showResultSnackBar('Transcode failed / Conversión fallida');
    } finally {
      await _progressSubscription?.cancel();
      _progressSubscription = null;
      if (mounted) setState(() => _working = false);
      if (workDirectory != null) {
        _addLog('INFO', 'Temporary directory retained for this process path=${workDirectory.path}');
      }
    }
  }

  Future<MediaInfo> _readMediaInfo(String path, String label) async {
    _addLog('INFO', 'Reading $label media info path=$path');
    final info = await AwesomeVideoKit.getMediaInfo(filePath: path);
    if (info == null || info.videoStreams.isEmpty) {
      throw StateError('$label media info has no video stream.');
    }
    final stream = info.videoStreams.first;
    final dimensions = _rotatedDimensions(stream);
    final durationUs = stream.duration > 0 ? stream.duration : info.duration;
    final fps = stream.frameRate.den == 0
        ? 0.0
        : stream.frameRate.num / stream.frameRate.den;
    _addLog(
      'INFO',
      '$label decoded '
          'resolution=${dimensions.width}x${dimensions.height} '
          'duration_s=${(durationUs / Duration.microsecondsPerSecond).toStringAsFixed(2)} '
          'codec=${stream.codecName} fps=${fps.toStringAsFixed(2)} '
          'rotation_deg=${stream.rotationDegrees} '
          'audio_streams=${info.audioStreams.length} '
          'audio_codec=${info.audioStreams.isEmpty ? 'none' : info.audioStreams.first.codecName}',
    );
    return info;
  }

  ({int width, int height}) _rotatedDimensions(VideoStreamInfo stream) {
    final rotated = stream.rotation == VideoRotation.rotation90 ||
        stream.rotation == VideoRotation.rotation270;
    return (
      width: rotated ? stream.dimension.height : stream.dimension.width,
      height: rotated ? stream.dimension.width : stream.dimension.height,
    );
  }

  ({int width, int height, int bitrate, int frameRate}) _buildTranscodePolicy(
    VideoStreamInfo stream,
    ({int width, int height}) dimensions,
  ) {
    final shortSide = dimensions.width < dimensions.height
        ? dimensions.width
        : dimensions.height;
    var targetShortSide = shortSide;
    if (shortSide >= 720) {
      targetShortSide = 720;
    } else if (shortSide >= 540) {
      targetShortSide = 540;
    } else if (shortSide >= 480) {
      targetShortSide = 480;
    } else if (shortSide >= 360) {
      targetShortSide = 360;
    }
    final scale = shortSide > 0 ? targetShortSide / shortSide : 1.0;
    var width = (dimensions.width * scale).round();
    var height = (dimensions.height * scale).round();
    if (width.isOdd) width -= 1;
    if (height.isOdd) height -= 1;
    final frameRate = stream.frameRate.den <= 0 || stream.frameRate.num <= 0
        ? 30
        : (stream.frameRate.num / stream.frameRate.den).round().clamp(1, 30);
    final bitrate = targetShortSide >= 540 ? 1600000 : 1500000;
    return (width: width, height: height, bitrate: bitrate, frameRate: frameRate);
  }

  void _showResultSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _copyLogs() async {
    await Clipboard.setData(ClipboardData(text: _logs.join('\n\n')));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Logs copied / Registros copiados')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final inputName = _inputFile?.path.split(Platform.pathSeparator).last;
    return Scaffold(
      appBar: AppBar(
        title: const Text('GoshVideoTest'),
        actions: [
          IconButton(
            tooltip: 'Copy logs / Copiar registros',
            onPressed: _logs.isEmpty ? null : _copyLogs,
            icon: const Icon(Icons.copy),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OutlinedButton.icon(
              onPressed: _working ? null : _pickVideo,
              icon: const Icon(Icons.video_library_outlined),
              label: Text(inputName == null ? 'Select local video / Seleccionar video local' : 'Select another video / Seleccionar otro video'),
            ),
            if (inputName != null) ...[
              const SizedBox(height: 8),
              Text('Selected / Seleccionado: $inputName', maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _working || _inputFile == null ? null : _transcode,
              icon: const Icon(Icons.play_arrow),
              label: Text(_working ? 'Transcoding / Convirtiendo ${(100 * _progress).toStringAsFixed(0)}%' : 'Start decode and transcode / Iniciar decodificación y conversión'),
            ),
            if (_working) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(value: _progress == 0 ? null : _progress),
            ],
            if (_outputPath != null) ...[
              const SizedBox(height: 8),
              Text(
                'Output file / Archivo de salida: $_outputPath',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.green.shade700),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('Full logs / Registros completos', style: TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                Text('${_logs.length} entries / entradas', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: _logs.isEmpty
                    ? const Text('No logs yet / Aún no hay registros', style: TextStyle(color: Colors.white70))
                    : SelectionArea(
                        child: ListView.builder(
                          itemCount: _logs.length,
                          itemBuilder: (context, index) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Text(
                              _logs[index],
                              style: const TextStyle(
                                color: Colors.white,
                                fontFamily: 'monospace',
                                fontSize: 12,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
