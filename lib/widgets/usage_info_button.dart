import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// A button that shows a graph icon and displays usage/cost info on click.
/// On desktop, also shows a tooltip on hover.
class UsageInfoButton extends StatelessWidget {
  final String usageDataJson;

  const UsageInfoButton({super.key, required this.usageDataJson});

  Map<String, dynamic> _parseUsage() {
    try {
      return jsonDecode(usageDataJson) as Map<String, dynamic>;
    } catch (e) {
      return {};
    }
  }

  String _buildTooltipText(Map<String, dynamic> usage) {
    final promptTokens = usage['prompt_tokens'] ?? 0;
    final completionTokens = usage['completion_tokens'] ?? 0;
    final totalTokens = usage['total_tokens'] ?? 0;
    final cost = usage['cost'];

    final parts = <String>[];
    parts.add('In: $promptTokens');
    parts.add('Out: $completionTokens');
    parts.add('Total: $totalTokens');
    if (cost != null) {
      parts.add('Cost: \$${_formatCost(cost)}');
    }
    return parts.join('\n');
  }

  static String _formatCost(dynamic cost) {
    if (cost == null) return '—';
    final value = (cost is num) ? cost.toDouble() : double.tryParse(cost.toString()) ?? 0;
    if (value == 0) return '0';
    if (value < 0.0001) {
      return value.toStringAsExponential(2);
    }
    if (value < 0.01) {
      return value.toStringAsFixed(6);
    }
    return value.toStringAsFixed(4);
  }

  @override
  Widget build(BuildContext context) {
    final usage = _parseUsage();
    if (usage.isEmpty) return const SizedBox.shrink();

    final isDesktop = defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux;

    final button = InkWell(
      onTap: () => _showUsageDialog(context, usage),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(
          Icons.bar_chart_rounded,
          size: 14,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );

    if (isDesktop) {
      return Tooltip(
        message: _buildTooltipText(usage),
        child: button,
      );
    }

    return button;
  }

  void _showUsageDialog(BuildContext context, Map<String, dynamic> usage) {
    showDialog(
      context: context,
      builder: (context) => UsageDetailsDialog(usage: usage),
    );
  }
}

/// Dialog that shows detailed usage/cost breakdown.
class UsageDetailsDialog extends StatelessWidget {
  final Map<String, dynamic> usage;

  const UsageDetailsDialog({super.key, required this.usage});

  @override
  Widget build(BuildContext context) {
    final promptTokens = usage['prompt_tokens'] ?? 0;
    final completionTokens = usage['completion_tokens'] ?? 0;
    final totalTokens = usage['total_tokens'] ?? 0;
    final cost = usage['cost'];
    final isByok = usage['is_byok'] == true;

    // Prompt token details
    final promptDetails =
        usage['prompt_tokens_details'] as Map<String, dynamic>?;
    final cachedTokens = promptDetails?['cached_tokens'];
    final cacheWriteTokens = promptDetails?['cache_write_tokens'];
    final audioInputTokens = promptDetails?['audio_tokens'];
    final videoTokens = promptDetails?['video_tokens'];

    // Completion token details
    final completionDetails =
        usage['completion_tokens_details'] as Map<String, dynamic>?;
    final reasoningTokens = completionDetails?['reasoning_tokens'];
    final imageOutputTokens = completionDetails?['image_tokens'];

    // Cost details
    final costDetails = usage['cost_details'] as Map<String, dynamic>?;
    final upstreamCost = costDetails?['upstream_inference_cost'];
    final promptCost = costDetails?['upstream_inference_prompt_cost'];
    final completionCost = costDetails?['upstream_inference_completions_cost'];

    // Server tool use
    final serverToolUse = usage['server_tool_use'] as Map<String, dynamic>?;
    final webSearchRequests = serverToolUse?['web_search_requests'];

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            Icons.bar_chart_rounded,
            size: 20,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 8),
          const Text('Usage Details'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Token section
            _buildSectionHeader(context, 'Tokens'),
            _buildRow(context, 'Prompt tokens', _formatNumber(promptTokens)),
            _buildRow(
              context,
              'Completion tokens',
              _formatNumber(completionTokens),
            ),
            _buildDivider(context),
            _buildRow(
              context,
              'Total tokens',
              _formatNumber(totalTokens),
              bold: true,
            ),

            // Prompt details
            if (promptDetails != null) ...[
              const SizedBox(height: 16),
              _buildSectionHeader(context, 'Prompt Breakdown'),
              if (cachedTokens != null && cachedTokens > 0)
                _buildRow(
                  context,
                  'Cached tokens',
                  _formatNumber(cachedTokens),
                ),
              if (cacheWriteTokens != null && cacheWriteTokens > 0)
                _buildRow(
                  context,
                  'Cache write tokens',
                  _formatNumber(cacheWriteTokens),
                ),
              if (audioInputTokens != null && audioInputTokens > 0)
                _buildRow(
                  context,
                  'Audio tokens',
                  _formatNumber(audioInputTokens),
                ),
              if (videoTokens != null && videoTokens > 0)
                _buildRow(
                  context,
                  'Video tokens',
                  _formatNumber(videoTokens),
                ),
            ],

            // Completion details
            if (completionDetails != null) ...[
              const SizedBox(height: 16),
              _buildSectionHeader(context, 'Completion Breakdown'),
              if (reasoningTokens != null && reasoningTokens > 0)
                _buildRow(
                  context,
                  'Reasoning tokens',
                  _formatNumber(reasoningTokens),
                ),
              if (imageOutputTokens != null && imageOutputTokens > 0)
                _buildRow(
                  context,
                  'Image tokens',
                  _formatNumber(imageOutputTokens),
                ),
            ],

            // Cost section
            if (cost != null) ...[
              const SizedBox(height: 16),
              _buildSectionHeader(context, 'Cost'),
              if (costDetails != null) ...[
                if (promptCost != null)
                  _buildRow(
                    context,
                    'Prompt cost',
                    '\$${UsageInfoButton._formatCost(promptCost)}',
                  ),
                if (completionCost != null)
                  _buildRow(
                    context,
                    'Completion cost',
                    '\$${UsageInfoButton._formatCost(completionCost)}',
                  ),
                if (upstreamCost != null)
                  _buildRow(
                    context,
                    'Upstream cost',
                    '\$${UsageInfoButton._formatCost(upstreamCost)}',
                  ),
                _buildDivider(context),
              ],
              _buildRow(
                context,
                'Total cost',
                '\$${UsageInfoButton._formatCost(cost)}',
                bold: true,
              ),
              if (isByok)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Using your own API key (BYOK)',
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
            ],

            // Server tool use
            if (webSearchRequests != null && webSearchRequests > 0) ...[
              const SizedBox(height: 16),
              _buildSectionHeader(context, 'Server Tools'),
              _buildRow(
                context,
                'Web searches',
                _formatNumber(webSearchRequests),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildRow(
    BuildContext context,
    String label,
    String value, {
    bool bold = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurface,
              fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          const SizedBox(width: 16),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontFamily: 'monospace',
              color: Theme.of(context).colorScheme.onSurface,
              fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Divider(
        height: 1,
        color: Theme.of(context).colorScheme.outlineVariant,
      ),
    );
  }

  String _formatNumber(dynamic value) {
    if (value == null) return '0';
    final num n = value is num ? value : num.tryParse(value.toString()) ?? 0;
    if (n >= 1000000) {
      return '${(n / 1000000).toStringAsFixed(1)}M';
    }
    if (n >= 1000) {
      return '${(n / 1000).toStringAsFixed(1)}K';
    }
    return n.toString();
  }
}
