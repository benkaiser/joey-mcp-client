import 'dart:typed_data';

/// Holds a pending image attachment before it is sent
class PendingImage {
  final Uint8List bytes;
  final String mimeType;

  PendingImage({required this.bytes, required this.mimeType});
}
