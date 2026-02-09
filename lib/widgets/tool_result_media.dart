import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

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

/// Renders audio players from a tool result's audioData JSON string.
class ToolResultAudio extends StatelessWidget {
  final String audioDataJson;
  final String messageId;

  const ToolResultAudio({
    super.key,
    required this.audioDataJson,
    required this.messageId,
  });

  @override
  Widget build(BuildContext context) {
    try {
      final audioList = jsonDecode(audioDataJson) as List;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: audioList.asMap().entries.map<Widget>((entry) {
          final audio = entry.value;
          final data = audio['data'] as String;
          final mimeType = audio['mimeType'] as String? ?? 'audio/wav';
          return AudioPlayerWidget(
            key: ValueKey('${messageId}_audio_${entry.key}'),
            base64Data: data,
            mimeType: mimeType,
          );
        }).toList(),
      );
    } catch (e) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          'Failed to parse audio data',
          style: TextStyle(
            color: Theme.of(context).colorScheme.error,
            fontSize: 13,
          ),
        ),
      );
    }
  }
}

/// A StatefulWidget that decodes base64 audio data, writes to a temp file,
/// and plays it via just_audio.
class AudioPlayerWidget extends StatefulWidget {
  final String base64Data;
  final String mimeType;

  const AudioPlayerWidget({
    super.key,
    required this.base64Data,
    required this.mimeType,
  });

  @override
  State<AudioPlayerWidget> createState() => _AudioPlayerWidgetState();
}

class _AudioPlayerWidgetState extends State<AudioPlayerWidget> {
  late final AudioPlayer _player;
  bool _isReady = false;
  bool _hasError = false;
  String _errorMessage = '';
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _initAudio();
  }

  Future<void> _initAudio() async {
    try {
      // Decode base64 to bytes
      final bytes = Uint8List.fromList(base64Decode(widget.base64Data));

      // Determine file extension from mime type
      final ext = _extensionFromMimeType(widget.mimeType);

      // Write to temporary file (just_audio cannot play from raw bytes directly)
      final tempDir = await getTemporaryDirectory();
      if (!await tempDir.exists()) {
        await tempDir.create(recursive: true);
      }
      final tempFile = File(
        '${tempDir.path}/audio_${widget.base64Data.hashCode.abs()}.$ext',
      );
      await tempFile.writeAsBytes(bytes);

      // Set up the player
      final duration = await _player.setFilePath(tempFile.path);

      // Listen to player state changes
      _player.playerStateStream.listen((state) {
        if (mounted) {
          setState(() {
            _isPlaying = state.playing;
          });
        }
      });

      _player.positionStream.listen((pos) {
        if (mounted) {
          setState(() {
            _position = pos;
          });
        }
      });

      _player.durationStream.listen((dur) {
        if (mounted && dur != null) {
          setState(() {
            _duration = dur;
          });
        }
      });

      if (mounted) {
        setState(() {
          _isReady = true;
          _duration = duration ?? Duration.zero;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = e.toString();
        });
      }
    }
  }

  String _extensionFromMimeType(String mimeType) {
    switch (mimeType.toLowerCase()) {
      case 'audio/wav':
      case 'audio/wave':
      case 'audio/x-wav':
        return 'wav';
      case 'audio/mp3':
      case 'audio/mpeg':
        return 'mp3';
      case 'audio/ogg':
      case 'audio/vorbis':
        return 'ogg';
      case 'audio/aac':
        return 'aac';
      case 'audio/flac':
        return 'flac';
      case 'audio/mp4':
      case 'audio/m4a':
        return 'm4a';
      case 'audio/webm':
        return 'webm';
      default:
        return 'wav';
    }
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) {
      return '${d.inHours}:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
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
                Icons.audio_file,
                color: Theme.of(context).colorScheme.onErrorContainer,
                size: 20,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Failed to load audio (${widget.mimeType}): $_errorMessage',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (!_isReady) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Loading audio...',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
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
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Play/pause button
            IconButton(
              icon: Icon(
                _isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                size: 32,
              ),
              color: Theme.of(context).colorScheme.primary,
              onPressed: () async {
                if (_isPlaying) {
                  await _player.pause();
                } else {
                  // Reset to start if playback completed
                  if (_position >= _duration && _duration > Duration.zero) {
                    await _player.seek(Duration.zero);
                  }
                  await _player.play();
                }
              },
            ),
            // Progress slider
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 6,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 12,
                      ),
                    ),
                    child: Slider(
                      value: _duration.inMilliseconds > 0
                          ? _position.inMilliseconds
                              .clamp(0, _duration.inMilliseconds)
                              .toDouble()
                          : 0,
                      max: _duration.inMilliseconds > 0
                          ? _duration.inMilliseconds.toDouble()
                          : 1,
                      onChanged: (value) {
                        _player.seek(Duration(milliseconds: value.toInt()));
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _formatDuration(_position),
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                        Text(
                          _formatDuration(_duration),
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Mime type label
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Icon(
                Icons.audio_file,
                size: 18,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
