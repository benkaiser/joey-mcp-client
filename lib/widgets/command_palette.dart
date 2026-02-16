import 'package:flutter/material.dart';
import '../models/mcp_server.dart';

/// A row of action chips for accessing prompts, MCP servers, and debug info.
class CommandPalette extends StatelessWidget {
  final List<McpServer> mcpServers;

  /// IDs of servers that are currently connected (have an active MCP client).
  final Set<String> connectedServerIds;

  final VoidCallback onOpenPrompts;
  final VoidCallback onOpenServers;
  final VoidCallback onOpenDebug;

  const CommandPalette({
    super.key,
    required this.mcpServers,
    required this.connectedServerIds,
    required this.onOpenPrompts,
    required this.onOpenServers,
    required this.onOpenDebug,
  });

  @override
  Widget build(BuildContext context) {
    // Compute status counts
    int connected = 0;
    int orange = 0; // needs OAuth / connecting
    int disconnected = 0;

    for (final server in mcpServers) {
      if (connectedServerIds.contains(server.id)) {
        connected++;
      } else if (server.needsOAuth) {
        orange++;
      } else {
        disconnected++;
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 4.0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            if (mcpServers.isNotEmpty) ...[
              ActionChip(
                avatar: Icon(
                  Icons.auto_awesome,
                  size: 18,
                  color: Theme.of(context).colorScheme.primary,
                ),
                label: const Text('Prompts'),
                onPressed: onOpenPrompts,
                side: BorderSide(
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.5),
                ),
              ),
              const SizedBox(width: 8),
            ],
            ActionChip(
              avatar: Icon(
                Icons.dns,
                size: 18,
                color: mcpServers.isNotEmpty
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    mcpServers.isNotEmpty
                        ? 'MCP Servers (${mcpServers.length})'
                        : 'MCP Servers',
                  ),
                  if (mcpServers.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    _buildStatusDots(connected, orange, disconnected),
                  ],
                ],
              ),
              onPressed: onOpenServers,
              side: BorderSide(
                color: mcpServers.isNotEmpty
                    ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.5)
                    : Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            if (mcpServers.isNotEmpty) ...[
              const SizedBox(width: 8),
              ActionChip(
                avatar: Icon(
                  Icons.bug_report_outlined,
                  size: 18,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                label: const Text('Debug'),
                onPressed: onOpenDebug,
                side: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Builds a compact row of colored dots with counts.
  Widget _buildStatusDots(int connected, int orange, int disconnected) {
    final dots = <Widget>[];

    if (connected > 0) {
      dots.add(_StatusDot(color: Colors.green, count: connected));
    }
    if (orange > 0) {
      dots.add(_StatusDot(color: Colors.orange, count: orange));
    }
    if (disconnected > 0) {
      dots.add(_StatusDot(color: Colors.red, count: disconnected));
    }

    if (dots.isEmpty) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < dots.length; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          dots[i],
        ],
      ],
    );
  }
}

class _StatusDot extends StatelessWidget {
  final Color color;
  final int count;

  const _StatusDot({required this.color, required this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 2),
        Text(
          '$count',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}
