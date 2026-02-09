import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pasteboard/pasteboard.dart';
import '../models/pending_image.dart';

/// Delegate class that handles image attachment operations for the chat screen.
class ImageAttachmentHandler {
  final ImagePicker _imagePicker = ImagePicker();
  final List<PendingImage> pendingImages = [];

  /// Callback invoked when the pending images list changes.
  VoidCallback? onStateChanged;

  /// Whether we're running on a desktop platform
  bool get isDesktop =>
      !kIsWeb && (Platform.isMacOS || Platform.isLinux || Platform.isWindows);

  /// Handle paste on desktop: check clipboard for image data
  Future<void> handleDesktopPaste() async {
    try {
      final imageBytes = await Pasteboard.image;
      if (imageBytes != null && imageBytes.isNotEmpty) {
        pendingImages.add(
          PendingImage(bytes: imageBytes, mimeType: 'image/png'),
        );
        onStateChanged?.call();
      }
    } catch (e) {
      // Silently fail — clipboard may just contain text
    }
  }

  /// Pick images from the device gallery (supports multi-select)
  Future<void> pickImageFromGallery(BuildContext context) async {
    try {
      final List<XFile> images = await _imagePicker.pickMultiImage(
        imageQuality: 85,
        maxWidth: 2048,
        maxHeight: 2048,
      );
      for (final image in images) {
        await _addImageFile(image);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to pick image: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Take a photo from the device camera
  Future<void> pickImageFromCamera(BuildContext context) async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 2048,
        maxHeight: 2048,
      );
      if (image != null) {
        await _addImageFile(image);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to capture image: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Handle content inserted via the soft keyboard (Android image paste/insert)
  void onContentInserted(KeyboardInsertedContent content) async {
    if (content.hasData) {
      final bytes = content.data;
      if (bytes != null && bytes.isNotEmpty) {
        final mimeType = content.mimeType;
        pendingImages.add(PendingImage(bytes: bytes, mimeType: mimeType));
        onStateChanged?.call();
      }
    } else {
      // Some keyboards provide a URI instead of raw data
      try {
        final file = XFile(content.uri);
        await _addImageFile(file);
      } catch (e) {
        debugPrint('Failed to load inserted content from URI: $e');
      }
    }
  }

  /// Add an XFile image to the pending list
  Future<void> _addImageFile(XFile file) async {
    final bytes = await file.readAsBytes();
    final mimeType = mimeTypeFromPath(file.path);
    pendingImages.add(
      PendingImage(bytes: Uint8List.fromList(bytes), mimeType: mimeType),
    );
    onStateChanged?.call();
  }

  /// Determine MIME type from file extension
  String mimeTypeFromPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.bmp')) return 'image/bmp';
    return 'image/png'; // Default
  }

  /// Show a warning if the current model doesn't support image input
  void showModelImageWarningIfNeeded(
    BuildContext context,
    Map<String, dynamic>? modelDetails,
    String currentModel,
  ) {
    final supportsImages =
        modelDetails != null &&
        modelDetails['architecture'] != null &&
        (modelDetails['architecture']['input_modalities'] as List?)?.contains(
              'image',
            ) ==
            true;

    if (!supportsImages && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Warning: $currentModel may not support image input',
          ),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  /// Remove a pending image at the given index
  void removeAt(int index) {
    pendingImages.removeAt(index);
    onStateChanged?.call();
  }

  /// Clear all pending images
  void clear() {
    pendingImages.clear();
  }
}
