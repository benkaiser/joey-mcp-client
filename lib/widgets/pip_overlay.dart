import 'package:flutter/material.dart';

/// A draggable, resizable floating PIP (picture-in-picture) overlay window.
/// Used to display an MCP App WebView in a small floating window
/// above the chat area.
class PipOverlay extends StatefulWidget {
  final Widget child;
  final String title;
  final VoidCallback? onClose;
  final VoidCallback? onFullscreen;
  final VoidCallback? onReturnInline;

  const PipOverlay({
    super.key,
    required this.child,
    this.title = 'PIP',
    this.onClose,
    this.onFullscreen,
    this.onReturnInline,
  });

  @override
  State<PipOverlay> createState() => _PipOverlayState();
}

class _PipOverlayState extends State<PipOverlay> {
  // Position offset from bottom-right corner
  Offset _offset = const Offset(16, 16);
  double _width = 280;
  double _height = 200;
  static const double _headerHeight = 32;
  static const double _minWidth = 180;
  static const double _minHeight = 120;
  static const double _resizeHandleSize = 16;
  static const double _edgePadding = 8;
  static const double _topPadding = 56; // Extra padding from top to avoid overlapping AppBar

  /// Clamp offset so the entire PIP window stays within the parent bounds.
  /// Uses [_edgePadding] for left/right/bottom and [_topPadding] for top
  /// to keep the PIP clear of the AppBar.
  void _clampOffset(Size parentSize) {
    final totalHeight = _height + _headerHeight;
    // right offset: 0 means flush with right edge, max means flush with left
    final maxRight = parentSize.width - _width - _edgePadding;
    // bottom offset: max keeps the PIP below the top padding
    final maxBottom = parentSize.height - totalHeight - _topPadding;
    _offset = Offset(
      _offset.dx.clamp(_edgePadding, maxRight.clamp(_edgePadding, double.infinity)),
      _offset.dy.clamp(_edgePadding, maxBottom.clamp(_edgePadding, double.infinity)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final maxWidth = screenSize.width * 0.9;
    final maxHeight = screenSize.height * 0.8;

    // Ensure the window stays in bounds after screen resizes
    _clampOffset(screenSize);

    return Positioned(
      right: _offset.dx,
      bottom: _offset.dy,
      width: _width,
      height: _height + _headerHeight,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        color: Theme.of(context).colorScheme.surfaceContainer,
        child: Stack(
          children: [
            Column(
              children: [
                // Header bar with drag handle and controls
                GestureDetector(
                  onPanUpdate: (details) {
                    setState(() {
                      _offset = Offset(
                        _offset.dx - details.delta.dx,
                        _offset.dy - details.delta.dy,
                      );
                      _clampOffset(MediaQuery.of(context).size);
                    });
                  },
                  child: Container(
                    height: _headerHeight,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    ),
                    child: Row(
                      children: [
                        const SizedBox(width: 8),
                        // Drag handle indicator
                        Icon(
                          Icons.drag_indicator,
                          size: 16,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            widget.title,
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (widget.onFullscreen != null)
                          _HeaderButton(
                            icon: Icons.fullscreen,
                            tooltip: 'Fullscreen',
                            onPressed: widget.onFullscreen!,
                          ),
                        if (widget.onReturnInline != null)
                          _HeaderButton(
                            icon: Icons.close_fullscreen,
                            tooltip: 'Return inline',
                            onPressed: widget.onReturnInline!,
                          ),
                        if (widget.onClose != null)
                          _HeaderButton(
                            icon: Icons.close,
                            tooltip: 'Close',
                            onPressed: widget.onClose!,
                          ),
                      ],
                    ),
                  ),
                ),
                // WebView content area
                Expanded(child: widget.child),
              ],
            ),
            // Top-left corner resize handle (since PIP is anchored bottom-right)
            Positioned(
              left: 0,
              top: 0,
              width: _resizeHandleSize,
              height: _resizeHandleSize,
              child: GestureDetector(
                onPanUpdate: (details) {
                  setState(() {
                    _width = (_width - details.delta.dx).clamp(_minWidth, maxWidth);
                    _height = (_height - details.delta.dy).clamp(_minHeight, maxHeight);
                    _clampOffset(screenSize);
                  });
                },
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeUpLeft,
                  child: _buildResizeCorner(context),
                ),
              ),
            ),
            // Bottom-left corner resize handle
            Positioned(
              left: 0,
              bottom: 0,
              width: _resizeHandleSize,
              height: _resizeHandleSize,
              child: GestureDetector(
                onPanUpdate: (details) {
                  setState(() {
                    _width = (_width - details.delta.dx).clamp(_minWidth, maxWidth);
                    final newHeight = (_height + details.delta.dy).clamp(_minHeight, maxHeight);
                    final heightDelta = newHeight - _height;
                    _height = newHeight;
                    _offset = Offset(_offset.dx, _offset.dy - heightDelta);
                    _clampOffset(screenSize);
                  });
                },
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeDownLeft,
                  child: _buildResizeCorner(context),
                ),
              ),
            ),
            // Top-right corner resize handle
            Positioned(
              right: 0,
              top: 0,
              width: _resizeHandleSize,
              height: _resizeHandleSize,
              child: GestureDetector(
                onPanUpdate: (details) {
                  setState(() {
                    final newWidth = (_width + details.delta.dx).clamp(_minWidth, maxWidth);
                    final widthDelta = newWidth - _width;
                    _width = newWidth;
                    _offset = Offset(_offset.dx - widthDelta, _offset.dy);
                    _height = (_height - details.delta.dy).clamp(_minHeight, maxHeight);
                    _clampOffset(screenSize);
                  });
                },
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeUpRight,
                  child: _buildResizeCorner(context),
                ),
              ),
            ),
            // Bottom-right corner resize handle
            Positioned(
              right: 0,
              bottom: 0,
              width: _resizeHandleSize,
              height: _resizeHandleSize,
              child: GestureDetector(
                onPanUpdate: (details) {
                  setState(() {
                    final newWidth = (_width + details.delta.dx).clamp(_minWidth, maxWidth);
                    final widthDelta = newWidth - _width;
                    _width = newWidth;
                    _offset = Offset(_offset.dx - widthDelta, _offset.dy);
                    final newHeight = (_height + details.delta.dy).clamp(_minHeight, maxHeight);
                    final heightDelta = newHeight - _height;
                    _height = newHeight;
                    _offset = Offset(_offset.dx, _offset.dy - heightDelta);
                    _clampOffset(screenSize);
                  });
                },
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeDownRight,
                  child: _buildResizeCorner(context),
                ),
              ),
            ),
            // Left edge resize handle
            Positioned(
              left: 0,
              top: _resizeHandleSize,
              width: _resizeHandleSize / 2,
              bottom: _resizeHandleSize,
              child: GestureDetector(
                onPanUpdate: (details) {
                  setState(() {
                    _width = (_width - details.delta.dx).clamp(_minWidth, maxWidth);
                    _clampOffset(screenSize);
                  });
                },
                child: const MouseRegion(
                  cursor: SystemMouseCursors.resizeLeft,
                  child: SizedBox.expand(),
                ),
              ),
            ),
            // Top edge resize handle
            Positioned(
              top: 0,
              left: _resizeHandleSize,
              right: _resizeHandleSize,
              height: _resizeHandleSize / 2,
              child: GestureDetector(
                onPanUpdate: (details) {
                  setState(() {
                    _height = (_height - details.delta.dy).clamp(_minHeight, maxHeight);
                    _clampOffset(screenSize);
                  });
                },
                child: const MouseRegion(
                  cursor: SystemMouseCursors.resizeUp,
                  child: SizedBox.expand(),
                ),
              ),
            ),
            // Right edge resize handle
            Positioned(
              right: 0,
              top: _resizeHandleSize,
              width: _resizeHandleSize / 2,
              bottom: _resizeHandleSize,
              child: GestureDetector(
                onPanUpdate: (details) {
                  setState(() {
                    final newWidth = (_width + details.delta.dx).clamp(_minWidth, maxWidth);
                    final widthDelta = newWidth - _width;
                    _width = newWidth;
                    _offset = Offset(_offset.dx - widthDelta, _offset.dy);
                    _clampOffset(screenSize);
                  });
                },
                child: const MouseRegion(
                  cursor: SystemMouseCursors.resizeRight,
                  child: SizedBox.expand(),
                ),
              ),
            ),
            // Bottom edge resize handle
            Positioned(
              bottom: 0,
              left: _resizeHandleSize,
              right: _resizeHandleSize,
              height: _resizeHandleSize / 2,
              child: GestureDetector(
                onPanUpdate: (details) {
                  setState(() {
                    final newHeight = (_height + details.delta.dy).clamp(_minHeight, maxHeight);
                    final heightDelta = newHeight - _height;
                    _height = newHeight;
                    _offset = Offset(_offset.dx, _offset.dy - heightDelta);
                    _clampOffset(screenSize);
                  });
                },
                child: const MouseRegion(
                  cursor: SystemMouseCursors.resizeDown,
                  child: SizedBox.expand(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResizeCorner(BuildContext context) {
    return Container(
      width: _resizeHandleSize,
      height: _resizeHandleSize,
      color: Colors.transparent,
    );
  }
}

class _HeaderButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _HeaderButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 28,
      height: 28,
      child: IconButton(
        icon: Icon(icon, size: 14),
        tooltip: tooltip,
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}
