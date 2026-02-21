import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../models/pending_audio.dart';
import '../models/pending_image.dart';
import '../utils/audio_attachment_handler.dart';

/// The message input bar at the bottom of the chat screen.
///
/// Contains an attachment button, text field, pending image/audio thumbnails,
/// recording controls, and a send/stop button.
class MessageInput extends StatelessWidget {
  final TextEditingController messageController;
  final FocusNode focusNode;
  final bool isLoading;
  final List<PendingImage> pendingImages;
  final List<PendingAudio> pendingAudios;
  final bool isRecording;
  final Duration recordingDuration;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final VoidCallback onPickImageFromGallery;
  final VoidCallback? onPickImageFromCamera;
  final VoidCallback onPickAudioFile;
  final VoidCallback onStartRecording;
  final VoidCallback onStopRecording;
  final VoidCallback onCancelRecording;
  final void Function(int index) onRemovePendingImage;
  final void Function(int index) onRemovePendingAudio;
  final void Function(KeyboardInsertedContent) onContentInserted;

  const MessageInput({
    super.key,
    required this.messageController,
    required this.focusNode,
    required this.isLoading,
    required this.pendingImages,
    required this.pendingAudios,
    required this.isRecording,
    required this.recordingDuration,
    required this.onSend,
    required this.onStop,
    required this.onPickImageFromGallery,
    this.onPickImageFromCamera,
    required this.onPickAudioFile,
    required this.onStartRecording,
    required this.onStopRecording,
    required this.onCancelRecording,
    required this.onRemovePendingImage,
    required this.onRemovePendingAudio,
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
            // Pending audio chips
            if (pendingAudios.isNotEmpty)
              SizedBox(
                height: 44,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: pendingAudios.length,
                  itemBuilder: (context, index) {
                    final audio = pendingAudios[index];
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
                        onDeleted: () => onRemovePendingAudio(index),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                    );
                  },
                ),
              ),
            // Recording indicator
            if (isRecording)
              _buildRecordingBar(context),
            // Main input row
            if (!isRecording)
              Row(
                children: [
                  // Attachment button — popup with image + audio options
                  _buildAttachmentButton(context),
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
                      minLines: 1,
                      maxLines: 4,
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

  Widget _buildAttachmentButton(BuildContext context) {
    final isMobile = !kIsWeb && (Platform.isIOS || Platform.isAndroid);

    return PopupMenuButton<String>(
      icon: Icon(
        Icons.attach_file,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      tooltip: 'Attach media',
      onSelected: (value) {
        switch (value) {
          case 'gallery':
            onPickImageFromGallery();
            break;
          case 'camera':
            onPickImageFromCamera?.call();
            break;
          case 'audio_file':
            onPickAudioFile();
            break;
          case 'record':
            onStartRecording();
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
        if (isMobile)
          const PopupMenuItem(
            value: 'camera',
            child: ListTile(
              leading: Icon(Icons.camera_alt_outlined),
              title: Text('Camera'),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
          ),
        const PopupMenuItem(
          value: 'audio_file',
          child: ListTile(
            leading: Icon(Icons.audio_file_outlined),
            title: Text('Audio File'),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ),
        const PopupMenuItem(
          value: 'record',
          child: ListTile(
            leading: Icon(Icons.mic_outlined),
            title: Text('Record Audio'),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ),
      ],
    );
  }

  Widget _buildRecordingBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          // Pulsing red dot
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.3, end: 1.0),
            duration: const Duration(milliseconds: 700),
            builder: (context, value, child) {
              return Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: value),
                  shape: BoxShape.circle,
                ),
              );
            },
            onEnd: () {},
          ),
          const SizedBox(width: 12),
          // Duration
          Text(
            AudioAttachmentHandler.formatDuration(recordingDuration),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.onSurface,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const Spacer(),
          // Cancel button
          TextButton.icon(
            onPressed: onCancelRecording,
            icon: const Icon(Icons.delete_outline, size: 20),
            label: const Text('Cancel'),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
          ),
          const SizedBox(width: 8),
          // Stop / Save button
          FilledButton.icon(
            onPressed: onStopRecording,
            icon: const Icon(Icons.stop, size: 20),
            label: const Text('Done'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}
