import 'package:flutter/material.dart';
import '../models/mcp_server.dart';

/// Status of OAuth flow for a server
enum McpOAuthCardStatus {
  /// Waiting for user to initiate auth
  pending,
  /// Auth flow in progress (browser opened)
  inProgress,
  /// Successfully authenticated
  completed,
  /// Auth failed or was cancelled
  failed,
}

/// Card widget for displaying MCP OAuth authentication requests
class McpOAuthCard extends StatelessWidget {
  final McpServer server;
  final McpOAuthCardStatus status;
  final String? errorMessage;
  final VoidCallback? onAuthenticate;
  final VoidCallback? onSkip;
  final VoidCallback? onRetry;

  const McpOAuthCard({
    super.key,
    required this.server,
    this.status = McpOAuthCardStatus.pending,
    this.errorMessage,
    this.onAuthenticate,
    this.onSkip,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    Color borderColor;
    Color iconColor;
    IconData icon;
    String title;
    String subtitle;

    switch (status) {
      case McpOAuthCardStatus.pending:
        borderColor = colorScheme.primary;
        iconColor = colorScheme.primary;
        icon = Icons.lock_outline;
        title = 'Authentication Required';
        subtitle = '${server.name} requires you to sign in to access its tools.';
        break;
      case McpOAuthCardStatus.inProgress:
        borderColor = Colors.orange.shade600;
        iconColor = Colors.orange.shade600;
        icon = Icons.hourglass_top;
        title = 'Waiting for Authentication';
        subtitle = 'Complete the sign-in in your browser, then return here.';
        break;
      case McpOAuthCardStatus.completed:
        borderColor = Colors.green.shade600;
        iconColor = Colors.green.shade600;
        icon = Icons.check_circle_outline;
        title = 'Authentication Complete';
        subtitle = 'Successfully connected to ${server.name}.';
        break;
      case McpOAuthCardStatus.failed:
        borderColor = Colors.red.shade600;
        iconColor = Colors.red.shade600;
        icon = Icons.error_outline;
        title = 'Authentication Failed';
        subtitle = errorMessage ?? 'Failed to authenticate with ${server.name}.';
        break;
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      decoration: BoxDecoration(
        border: Border.all(color: borderColor, width: 1.5),
        borderRadius: BorderRadius.circular(12),
        color: colorScheme.surfaceContainerLow,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Row(
              children: [
                Icon(icon, color: iconColor, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: iconColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        server.name,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            // Subtitle/Description
            Text(
              subtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurface,
              ),
            ),
            
            // Server URL
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.dns_outlined,
                    size: 14,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      server.url,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontFamily: 'monospace',
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            
            // Actions
            const SizedBox(height: 16),
            _buildActions(context, colorScheme),
          ],
        ),
      ),
    );
  }

  Widget _buildActions(BuildContext context, ColorScheme colorScheme) {
    switch (status) {
      case McpOAuthCardStatus.pending:
        return Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (onSkip != null)
              TextButton(
                onPressed: onSkip,
                child: const Text('Skip'),
              ),
            const SizedBox(width: 8),
            if (onAuthenticate != null)
              FilledButton.icon(
                onPressed: onAuthenticate,
                icon: const Icon(Icons.login, size: 18),
                label: const Text('Sign In'),
              ),
          ],
        );
      
      case McpOAuthCardStatus.inProgress:
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.orange.shade600,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'Waiting for browser...',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        );
      
      case McpOAuthCardStatus.completed:
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.check,
              color: Colors.green.shade600,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              'Connected',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.green.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        );
      
      case McpOAuthCardStatus.failed:
        return Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (onSkip != null)
              TextButton(
                onPressed: onSkip,
                child: const Text('Skip'),
              ),
            const SizedBox(width: 8),
            if (onRetry != null)
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Retry'),
              ),
          ],
        );
    }
  }
}

/// Card shown at the top of chat when multiple servers need OAuth
class McpOAuthBanner extends StatelessWidget {
  final List<McpServer> serversNeedingAuth;
  final VoidCallback onAuthenticateAll;
  final VoidCallback? onDismiss;

  const McpOAuthBanner({
    super.key,
    required this.serversNeedingAuth,
    required this.onAuthenticateAll,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (serversNeedingAuth.isEmpty) {
      return const SizedBox.shrink();
    }

    final serverNames = serversNeedingAuth.map((s) => s.name).join(', ');

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  Icons.lock_outline,
                  color: colorScheme.onPrimaryContainer,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Sign in to MCP Servers',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (onDismiss != null)
                  IconButton(
                    onPressed: onDismiss,
                    icon: Icon(
                      Icons.close,
                      color: colorScheme.onPrimaryContainer,
                      size: 20,
                    ),
                    constraints: const BoxConstraints(),
                    padding: EdgeInsets.zero,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${serversNeedingAuth.length} server${serversNeedingAuth.length > 1 ? 's' : ''} require${serversNeedingAuth.length == 1 ? 's' : ''} authentication: $serverNames',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onPrimaryContainer.withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onAuthenticateAll,
                icon: const Icon(Icons.login, size: 18),
                label: Text(
                  serversNeedingAuth.length == 1
                      ? 'Sign In'
                      : 'Sign In to All',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
