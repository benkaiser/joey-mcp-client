import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/conversation_provider.dart';
import '../models/conversation.dart';
import '../services/default_model_service.dart';
import '../services/database_service.dart';
import '../widgets/mcp_server_selection_dialog.dart';
import 'chat_screen.dart';
import 'model_picker_screen.dart';
import 'settings_screen.dart';

class ConversationListScreen extends StatelessWidget {
  const ConversationListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Joey MCP Client'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: Consumer<ConversationProvider>(
        builder: (context, provider, child) {
          final conversations = provider.conversations;

          if (conversations.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.chat_bubble_outline,
                    size: 64,
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No conversations yet',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Start a new chat to get started',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            itemCount: conversations.length,
            itemBuilder: (context, index) {
              final conversation = conversations[index];
              return _ConversationListItem(
                conversation: conversation,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          ChatScreen(conversation: conversation),
                    ),
                  );
                },
                onDelete: () {
                  _showDeleteDialog(context, provider, conversation);
                },
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          // Check for default model
          final defaultModel = await DefaultModelService.getDefaultModel();

          String? selectedModel;

          if (defaultModel != null) {
            // Use default model directly, bypass model picker
            selectedModel = defaultModel;
          } else {
            // Show model picker if no default is set
            selectedModel = await Navigator.push<String>(
              context,
              MaterialPageRoute(
                builder: (context) => const ModelPickerScreen(),
              ),
            );
          }

          if (selectedModel != null && context.mounted) {
            // Show MCP server selection dialog
            final selectedServerIds = await showDialog<List<String>>(
              context: context,
              builder: (context) => const McpServerSelectionDialog(),
            );

            // User cancelled
            if (selectedServerIds == null && context.mounted) {
              return;
            }

            if (context.mounted) {
              final provider = context.read<ConversationProvider>();
              final conversation = await provider.createConversation(
                model: selectedModel,
              );

              // Save MCP server associations
              if (selectedServerIds != null && selectedServerIds.isNotEmpty) {
                await DatabaseService.instance.setConversationMcpServers(
                  conversation.id,
                  selectedServerIds,
                );
              }

              if (context.mounted) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        ChatScreen(conversation: conversation),
                  ),
                );
              }
            }
          }
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showDeleteDialog(
    BuildContext context,
    ConversationProvider provider,
    Conversation conversation,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Conversation'),
        content: Text(
          'Are you sure you want to delete "${conversation.title}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await provider.deleteConversation(conversation.id);
              if (context.mounted) {
                Navigator.pop(context);
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _ConversationListItem extends StatelessWidget {
  final Conversation conversation;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ConversationListItem({
    required this.conversation,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('MMM d, yyyy');
    final timeFormat = DateFormat('h:mm a');
    final now = DateTime.now();
    final isToday =
        conversation.updatedAt.year == now.year &&
        conversation.updatedAt.month == now.month &&
        conversation.updatedAt.day == now.day;

    return ListTile(
      leading: CircleAvatar(child: Icon(Icons.chat, size: 20)),
      title: Text(
        conversation.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            conversation.model,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            isToday
                ? timeFormat.format(conversation.updatedAt)
                : dateFormat.format(conversation.updatedAt),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
          ),
        ],
      ),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline),
        onPressed: onDelete,
        color: Colors.grey[600],
      ),
      onTap: onTap,
    );
  }
}
