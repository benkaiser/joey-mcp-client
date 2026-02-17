import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/message.dart';
import 'usage_info_button.dart';

/// A minimal left-aligned indicator for thinking/tool messages
/// when full thinking display is disabled.
class ThinkingIndicator extends StatelessWidget {
  final Message message;

  const ThinkingIndicator({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final indicators = _getIndicators();
    if (indicators.isEmpty) return const SizedBox.shrink();

    // Show usage button inline for assistant messages with tool calls
    final showUsage = message.role == MessageRole.assistant &&
        message.usageData != null;

    return Padding(
      padding: const EdgeInsets.only(left: 16, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 6,
        children: indicators.map((indicator) {
          return Builder(
            builder: (context) => Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                Icon(
                  indicator.icon,
                  size: 14,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  indicator.text,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                // Show usage button inline on the last indicator row
                if (showUsage && indicator == indicators.last) ...[
                  const SizedBox(width: 6),
                  UsageInfoButton(usageDataJson: message.usageData!),
                ],
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  List<_IndicatorData> _getIndicators() {
    final indicators = <_IndicatorData>[];

    // Tool result message
    if (message.role == MessageRole.tool) {
      final toolName = message.toolName ?? 'tool';
      final isError =
          message.content.startsWith('Failed to parse tool arguments') ||
          message.content.startsWith('Error executing tool') ||
          message.content.startsWith('Tool not found') ||
          message.content.startsWith('MCP error');
      indicators.add(
        _IndicatorData(
          icon: isError ? Icons.error_outline : Icons.check_circle_outline,
          text: isError ? 'Error from $toolName' : 'Result from $toolName',
        ),
      );
      return indicators;
    }

    // MCP notification message
    if (message.role == MessageRole.mcpNotification) {
      String serverName = 'MCP Server';
      if (message.notificationData != null) {
        try {
          final data = jsonDecode(message.notificationData!);
          serverName = data['serverName'] ?? 'MCP Server';
        } catch (e) {
          // Ignore parse errors
        }
      }
      indicators.add(
        _IndicatorData(
          icon: Icons.notifications_outlined,
          text: 'Notification from $serverName',
        ),
      );
      return indicators;
    }

    // Assistant message - check for reasoning first
    if (message.role == MessageRole.assistant &&
        message.reasoning != null &&
        message.reasoning!.isNotEmpty) {
      indicators.add(
        _IndicatorData(icon: Icons.psychology_outlined, text: 'Thinking...'),
      );
    }

    // Assistant message with tool calls
    if (message.role == MessageRole.assistant && message.toolCallData != null) {
      try {
        final toolCalls = jsonDecode(message.toolCallData!) as List;
        if (toolCalls.isNotEmpty) {
          final toolNames = toolCalls
              .map((tc) => tc['function']['name'] as String)
              .toList();
          final text = toolNames.length == 1
              ? 'Calling ${toolNames.first}'
              : 'Calling ${toolNames.length} tools';
          indicators.add(
            _IndicatorData(icon: Icons.build_outlined, text: text),
          );
        }
      } catch (e) {
        indicators.add(
          _IndicatorData(icon: Icons.build_outlined, text: 'Calling tool'),
        );
      }
    }

    return indicators;
  }
}

class _IndicatorData {
  final IconData icon;
  final String text;

  _IndicatorData({required this.icon, required this.text});
}
