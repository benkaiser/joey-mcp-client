import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../models/pending_image.dart';

/// The message input bar at the bottom of the chat screen.
///
/// Contains an image attachment button, text field, pending image thumbnails,
/// and a send/stop button.
class MessageInput extends StatelessWidget {
  final TextEditingController messageController;
  final FocusNode focusNode;
  final bool isLoading;
  final List<PendingImage> pendingImages;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final VoidCallback onPickImageFromGallery;
  final VoidCallback? onPickImageFromCamera;
  final void Function(int index) onRemovePendingImage;
  final void Function(KeyboardInsertedContent) onContentInserted;

  const MessageInput({
    super.key,
    required this.messageController,
    required this.focusNode,
    required this.isLoading,
    required this.pendingImages,
    required this.onSend,
    required this.onStop,
    required this.onPickImageFromGallery,
    this.onPickImageFromCamera,
    required this.onRemovePendingImage,
    required this.onContentInserted,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            offset: const Offset(0, -1),
            blurRadius: 4,
            color: Colors.black.withValues(alpha: 0.3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(8.0),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Pending image thumbnails
            if (pendingImages.isNotEmpty)
              SizedBox(
                height: 80,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: pendingImages.length,
                  itemBuilder: (context, index) {
                    final img = pendingImages[index];
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
                              onTap: () => onRemovePendingImage(index),
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
            Row(
              children: [
                // Attachment button — popup on mobile, simple button on desktop
                if (!kIsWeb && (Platform.isIOS || Platform.isAndroid))
                  PopupMenuButton<String>(
                    icon: Icon(
                      Icons.add_photo_alternate_outlined,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    tooltip: 'Attach image',
                    onSelected: (value) {
                      switch (value) {
                        case 'gallery':
                          onPickImageFromGallery();
                          break;
                        case 'camera':
                          onPickImageFromCamera?.call();
                          break;
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'gallery',
                        child: ListTile(
                          leading: Icon(Icons.photo_library_outlined),
                          title: Text('Photo Library'),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'camera',
                        child: ListTile(
                          leading: Icon(Icons.camera_alt_outlined),
                          title: Text('Camera'),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                        ),
                      ),
                    ],
                  )
                else
                  IconButton(
                    icon: Icon(
                      Icons.add_photo_alternate_outlined,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    tooltip: 'Attach image',
                    onPressed: onPickImageFromGallery,
                  ),
                Expanded(
                  child: TextField(
                    controller: messageController,
                    focusNode: focusNode,
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    maxLines: null,
                    textInputAction: TextInputAction.newline,
                    contentInsertionConfiguration:
                        ContentInsertionConfiguration(
                          onContentInserted: onContentInserted,
                          allowedMimeTypes: const [
                            'image/png',
                            'image/jpeg',
                            'image/gif',
                            'image/webp',
                            'image/bmp',
                          ],
                        ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: isLoading ? onStop : onSend,
                  icon: Icon(isLoading ? Icons.stop : Icons.send),
                  style: IconButton.styleFrom(
                    backgroundColor: isLoading
                        ? Theme.of(context).colorScheme.error
                        : Theme.of(context).colorScheme.primary,
                    foregroundColor: isLoading
                        ? Theme.of(context).colorScheme.onError
                        : Theme.of(context).colorScheme.onPrimary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
