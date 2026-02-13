import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../models/pending_image.dart';

/// Result returned from the [EditMessageDialog].
class EditMessageResult {
  final String text;
  final List<PendingImage> images;

  EditMessageResult({required this.text, required this.images});
}

/// A dialog that lets the user edit a message's text and manage its attached
/// images before re-sending.  Images decoded from the original message's
/// [imageDataJson] are shown as thumbnails with remove buttons, exactly like
/// the pending-image strip in [MessageInput].
class EditMessageDialog extends StatefulWidget {
  /// The original message text.
  final String initialText;

  /// The original message's `imageData` JSON string (may be null).
  final String? imageDataJson;

  const EditMessageDialog({
    super.key,
    required this.initialText,
    this.imageDataJson,
  });

  @override
  State<EditMessageDialog> createState() => _EditMessageDialogState();
}

class _EditMessageDialogState extends State<EditMessageDialog> {
  late final TextEditingController _controller;
  late final List<PendingImage> _images;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
    _images = _decodeImages(widget.imageDataJson);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Decode the message's imageData JSON into a list of [PendingImage]s.
  static List<PendingImage> _decodeImages(String? imageDataJson) {
    if (imageDataJson == null) return [];
    try {
      final list = jsonDecode(imageDataJson) as List;
      return list.map((img) {
        final data = img['data'] as String;
        final mimeType = img['mimeType'] as String? ?? 'image/png';
        return PendingImage(
          bytes: Uint8List.fromList(base64Decode(data)),
          mimeType: mimeType,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  void _removeImage(int index) {
    setState(() {
      _images.removeAt(index);
    });
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty && _images.isEmpty) return;
    Navigator.pop(context, EditMessageResult(text: text, images: _images));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit Message'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Edit your message below. All messages after this one will be removed, and the conversation will continue from this point.',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            // --- Image thumbnails ---
            if (_images.isNotEmpty) ...[
              SizedBox(
                height: 80,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _images.length,
                  itemBuilder: (context, index) {
                    final img = _images[index];
                    return Padding(
                      padding: const EdgeInsets.only(right: 8.0, bottom: 4.0),
                      child: Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.memory(
                              img.bytes,
                              width: 72,
                              height: 72,
                              fit: BoxFit.cover,
                              gaplessPlayback: true,
                            ),
                          ),
                          Positioned(
                            top: 0,
                            right: 0,
                            child: GestureDetector(
                              onTap: () => _removeImage(index),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.6),
                                  shape: BoxShape.circle,
                                ),
                                padding: const EdgeInsets.all(2),
                                child: const Icon(
                                  Icons.close,
                                  size: 14,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
            ],
            // --- Text field ---
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Type your message...',
              ),
              maxLines: null,
              autofocus: true,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _submit,
          child: const Text('Edit and Resend'),
        ),
      ],
    );
  }
}
