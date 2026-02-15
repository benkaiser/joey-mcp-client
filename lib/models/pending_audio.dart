import 'dart:typed_data';

/// Holds a pending audio attachment before it is sent
class PendingAudio {
  final Uint8List bytes;
  final String mimeType;
  final Duration? duration;
  final String? fileName;

  PendingAudio({
    required this.bytes,
    required this.mimeType,
    this.duration,
    this.fileName,
  });
}
