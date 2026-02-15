import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../models/pending_audio.dart';
import '../models/pending_image.dart';
import '../utils/audio_attachment_handler.dart';

/// Result returned from the [EditMessageDialog].
class EditMessageResult {
  final String text;
  final List<PendingImage> images;
  final List<PendingAudio> audios;

  EditMessageResult({
    required this.text,
    required this.images,
    required this.audios,
  });
}

/// A dialog that lets the user edit a message's text and manage its attached
/// images and audio before re-sending.  Images decoded from the original
/// message's [imageDataJson] are shown as thumbnails with remove buttons,
/// exactly like the pending-image strip in [MessageInput].  Audio attachments
/// are shown as removable chips.
class EditMessageDialog extends StatefulWidget {
  /// The original message text.
  final String initialText;

  /// The original message's `imageData` JSON string (may be null).
  final String? imageDataJson;

  /// The original message's `audioData` JSON string (may be null).
  final String? audioDataJson;

  const EditMessageDialog({
    super.key,
    required this.initialText,
    this.imageDataJson,
    this.audioDataJson,
  });

  @override
  State<EditMessageDialog> createState() => _EditMessageDialogState();
}

class _EditMessageDialogState extends State<EditMessageDialog> {
  late final TextEditingController _controller;
  late final List<PendingImage> _images;
  late final List<PendingAudio> _audios;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
    _images = _decodeImages(widget.imageDataJson);
    _audios = _decodeAudios(widget.audioDataJson);
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

  /// Decode the message's audioData JSON into a list of [PendingAudio]s.
  static List<PendingAudio> _decodeAudios(String? audioDataJson) {
    if (audioDataJson == null) return [];
    try {
      final list = jsonDecode(audioDataJson) as List;
      return list.asMap().entries.map((entry) {
        final audio = entry.value;
        final data = audio['data'] as String;
        final mimeType = audio['mimeType'] as String? ?? 'audio/mpeg';
        return PendingAudio(
          bytes: Uint8List.fromList(base64Decode(data)),
          mimeType: mimeType,
          fileName: 'Audio ${entry.key + 1}',
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

  void _removeAudio(int index) {
    setState(() {
      _audios.removeAt(index);
    });
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty && _images.isEmpty && _audios.isEmpty) return;
    Navigator.pop(
      context,
      EditMessageResult(text: text, images: _images, audios: _audios),
    );
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
            // --- Audio chips ---
            if (_audios.isNotEmpty) ...[
              SizedBox(
                height: 44,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _audios.length,
                  itemBuilder: (context, index) {
                    final audio = _audios[index];
                    return Padding(
                      padding: const EdgeInsets.only(right: 8.0, bottom: 4.0),
                      child: Chip(
                        avatar: Icon(
                          Icons.audio_file,
                          size: 18,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        label: Text(
                          audio.fileName ??
                              (audio.duration != null
                                  ? AudioAttachmentHandler.formatDuration(
                                      audio.duration!)
                                  : 'Audio'),
                          style: const TextStyle(fontSize: 13),
                        ),
                        deleteIcon: const Icon(Icons.close, size: 16),
                        onDeleted: () => _removeAudio(index),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
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
