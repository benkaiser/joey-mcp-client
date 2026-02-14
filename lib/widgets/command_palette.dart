import 'package:flutter/material.dart';
import '../models/mcp_server.dart';

/// A row of action chips for accessing prompts, MCP servers, and debug info.
class CommandPalette extends StatelessWidget {
  final List<McpServer> mcpServers;
  final VoidCallback onOpenPrompts;
  final VoidCallback onOpenServers;
  final VoidCallback onOpenDebug;

  const CommandPalette({
    super.key,
    required this.mcpServers,
    required this.onOpenPrompts,
    required this.onOpenServers,
    required this.onOpenDebug,
  });

  @override
  Widget build(BuildContext context) {
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
              label: Text(
                mcpServers.isNotEmpty
                    ? 'MCP Servers (${mcpServers.length})'
                    : 'MCP Servers',
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
}
