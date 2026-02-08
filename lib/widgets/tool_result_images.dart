import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';

/// Renders images from a tool result's imageData JSON string.
/// Used both in MessageBubble and when showing images in thinking-hidden mode.
class ToolResultImages extends StatelessWidget {
  final String imageDataJson;
  final String messageId;

  const ToolResultImages({
    super.key,
    required this.imageDataJson,
    required this.messageId,
  });

  @override
  Widget build(BuildContext context) {
    try {
      final images = jsonDecode(imageDataJson) as List;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: images.asMap().entries.map<Widget>((entry) {
          final img = entry.value;
          final data = img['data'] as String;
          final mimeType = img['mimeType'] as String? ?? 'image/png';
          return CachedImageWidget(
            key: ValueKey('${messageId}_img_${entry.key}'),
            base64Data: data,
            mimeType: mimeType,
          );
        }).toList(),
      );
    } catch (e) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          'Failed to parse image data',
          style: TextStyle(
            color: Theme.of(context).colorScheme.error,
            fontSize: 13,
          ),
        ),
      );
    }
  }
}

/// A StatefulWidget that decodes base64 image data once and caches the bytes,
/// preventing flicker during parent rebuilds (e.g. streaming tokens).
class CachedImageWidget extends StatefulWidget {
  final String base64Data;
  final String mimeType;

  const CachedImageWidget({
    super.key,
    required this.base64Data,
    required this.mimeType,
  });

  @override
  State<CachedImageWidget> createState() => _CachedImageWidgetState();
}

class _CachedImageWidgetState extends State<CachedImageWidget> {
  late final Uint8List _bytes;
  late final bool _decodeError;

  @override
  void initState() {
    super.initState();
    try {
      _bytes = Uint8List.fromList(base64Decode(widget.base64Data));
      _decodeError = false;
    } catch (e) {
      _bytes = Uint8List(0);
      _decodeError = true;
    }
  }

  void _showFullScreenImage(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: Text(widget.mimeType, style: const TextStyle(fontSize: 14)),
          ),
          body: Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: Image.memory(_bytes, fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_decodeError) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.errorContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.broken_image,
                color: Theme.of(context).colorScheme.onErrorContainer,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Failed to decode image (${widget.mimeType})',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: GestureDetector(
        onTap: () => _showFullScreenImage(context),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 300),
            child: Image.memory(
              _bytes,
              fit: BoxFit.contain,
              gaplessPlayback: true,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.broken_image,
                        color: Theme.of(context).colorScheme.onErrorContainer,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Failed to load image (${widget.mimeType})',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
