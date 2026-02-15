import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import '../models/pending_audio.dart';

/// Delegate class that handles audio attachment operations for the chat screen.
class AudioAttachmentHandler {
  final List<PendingAudio> pendingAudios = [];
  AudioRecorder? _recorder;
  bool _isRecording = false;
  Duration _recordingDuration = Duration.zero;
  String? _recordingPath;

  /// Callback invoked when the pending audios list or recording state changes.
  VoidCallback? onStateChanged;

  bool get isRecording => _isRecording;
  Duration get recordingDuration => _recordingDuration;

  /// Pick audio files from the device
  Future<void> pickAudioFile(BuildContext context) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: true,
      );
      if (result != null) {
        for (final file in result.files) {
          if (file.path != null) {
            final bytes = await File(file.path!).readAsBytes();
            final mimeType = _mimeTypeFromPath(file.path!);
            pendingAudios.add(
              PendingAudio(
                bytes: Uint8List.fromList(bytes),
                mimeType: mimeType,
                fileName: file.name,
              ),
            );
          }
        }
        onStateChanged?.call();
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to pick audio: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Start recording audio
  Future<void> startRecording(BuildContext context) async {
    try {
      _recorder = AudioRecorder();
      if (!await _recorder!.hasPermission()) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Microphone permission denied'),
              backgroundColor: Colors.red,
            ),
          );
        }
        await _recorder!.dispose();
        _recorder = null;
        return;
      }

      // Get a temp file path for the recording
      final tempDir = await getTemporaryDirectory();
      _recordingPath =
          '${tempDir.path}/recording_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _recorder!.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          sampleRate: 44100,
          numChannels: 1,
        ),
        path: _recordingPath!,
      );

      _isRecording = true;
      _recordingDuration = Duration.zero;
      onStateChanged?.call();

      // Track recording duration
      _trackDuration();
    } catch (e) {
      debugPrint('Failed to start recording: $e');
      try {
        await _recorder?.dispose();
      } catch (_) {}
      _recorder = null;
      _recordingPath = null;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to start recording: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Track recording duration with periodic updates
  void _trackDuration() async {
    while (_isRecording && _recorder != null) {
      await Future.delayed(const Duration(milliseconds: 200));
      if (_isRecording) {
        _recordingDuration += const Duration(milliseconds: 200);
        onStateChanged?.call();
      }
    }
  }

  /// Stop recording and add the recording as a pending audio
  Future<void> stopRecording() async {
    if (!_isRecording) return;

    final recorder = _recorder;
    final duration = _recordingDuration;

    // Immediately update state so the UI responds
    _isRecording = false;
    _recordingDuration = Duration.zero;
    _recorder = null;
    onStateChanged?.call();

    if (recorder == null) return;

    try {
      final path = await recorder.stop();
      final audioPath = path ?? _recordingPath;

      if (audioPath != null) {
        final file = File(audioPath);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          if (bytes.isNotEmpty) {
            pendingAudios.add(
              PendingAudio(
                bytes: Uint8List.fromList(bytes),
                mimeType: 'audio/mp4',
                duration: duration,
                fileName: 'Recording',
              ),
            );
          }
        }
      }

      await recorder.dispose();
      _recordingPath = null;
      onStateChanged?.call();
    } catch (e) {
      debugPrint('Failed to stop recording: $e');
      try {
        await recorder.dispose();
      } catch (_) {}
      _recordingPath = null;
      onStateChanged?.call();
    }
  }

  /// Cancel the current recording without saving
  Future<void> cancelRecording() async {
    if (!_isRecording) return;

    final recorder = _recorder;
    final recordingPath = _recordingPath;

    // Immediately update state so the UI responds
    _isRecording = false;
    _recordingDuration = Duration.zero;
    _recorder = null;
    _recordingPath = null;
    onStateChanged?.call();

    if (recorder == null) return;

    try {
      await recorder.stop();

      // Delete the temp file
      if (recordingPath != null) {
        final file = File(recordingPath);
        if (await file.exists()) {
          await file.delete();
        }
      }

      await recorder.dispose();
    } catch (e) {
      debugPrint('Failed to cancel recording: $e');
      try {
        await recorder.dispose();
      } catch (_) {}
    }
  }

  /// Determine MIME type from file extension
  String _mimeTypeFromPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.mp3')) return 'audio/mpeg';
    if (lower.endsWith('.wav')) return 'audio/wav';
    if (lower.endsWith('.m4a')) return 'audio/mp4';
    if (lower.endsWith('.aac')) return 'audio/aac';
    if (lower.endsWith('.ogg')) return 'audio/ogg';
    if (lower.endsWith('.flac')) return 'audio/flac';
    if (lower.endsWith('.wma')) return 'audio/x-ms-wma';
    if (lower.endsWith('.webm')) return 'audio/webm';
    if (lower.endsWith('.opus')) return 'audio/ogg';
    if (lower.endsWith('.mp4')) return 'audio/mp4';
    return 'audio/mpeg'; // Default
  }

  /// Show a warning if the current model doesn't support audio input
  void showModelAudioWarningIfNeeded(
    BuildContext context,
    Map<String, dynamic>? modelDetails,
    String currentModel,
  ) {
    final supportsAudio =
        modelDetails != null &&
        modelDetails['architecture'] != null &&
        (modelDetails['architecture']['input_modalities'] as List?)?.contains(
              'audio',
            ) ==
            true;

    if (!supportsAudio && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Warning: $currentModel may not support audio input',
          ),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  /// Whether we're running on a mobile platform (has recording support)
  bool get isMobile =>
      !kIsWeb && (Platform.isIOS || Platform.isAndroid);

  /// Remove a pending audio at the given index
  void removeAt(int index) {
    pendingAudios.removeAt(index);
    onStateChanged?.call();
  }

  /// Clear all pending audios
  void clear() {
    pendingAudios.clear();
  }

  /// Dispose of the recorder
  Future<void> dispose() async {
    if (_isRecording) {
      await cancelRecording();
    }
    try {
      await _recorder?.dispose();
    } catch (_) {}
    _recorder = null;
  }

  /// Format a duration as MM:SS
  static String formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
