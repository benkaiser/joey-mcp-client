import 'dart:async';
import 'package:adaptive_dialog/adaptive_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/conversation_provider.dart';
import '../models/conversation.dart';
import '../services/default_model_service.dart';
import '../services/database_service.dart';
import '../widgets/mcp_server_selection_dialog.dart';
import '../utils/date_formatter.dart';
import 'chat_screen.dart';
import 'model_picker_screen.dart';
import 'settings_screen.dart';

class ConversationListScreen extends StatefulWidget {
  const ConversationListScreen({super.key});

  @override
  State<ConversationListScreen> createState() => _ConversationListScreenState();
}

class _ConversationListScreenState extends State<ConversationListScreen> {
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final FocusNode _pageFocusNode = FocusNode();
  List<Conversation>? _searchResults;
  Timer? _searchDebounce;

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _pageFocusNode.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _startSearch() {
    setState(() {
      _isSearching = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocusNode.requestFocus();
    });
  }

  void _stopSearch() {
    _searchDebounce?.cancel();
    setState(() {
      _isSearching = false;
      _searchController.clear();
      _searchResults = null;
    });
    _pageFocusNode.requestFocus();
  }

  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = null;
      });
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 300), () async {
      final provider = context.read<ConversationProvider>();
      final results = await provider.searchConversations(query);
      if (mounted) {
        setState(() {
          _searchResults = results;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true): _startSearch,
        const SingleActivator(LogicalKeyboardKey.escape): _stopSearch,
      },
      child: Focus(
        focusNode: _pageFocusNode,
        autofocus: true,
        child: Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                decoration: const InputDecoration(
                  hintText: 'Search conversations...',
                  border: InputBorder.none,
                ),
                onChanged: _onSearchChanged,
              )
            : const Text('Joey MCP Client'),
        actions: [
          if (_isSearching)
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Close search',
              onPressed: _stopSearch,
            )
          else ...[
            IconButton(
              icon: const Icon(Icons.search),
              tooltip: 'Search conversations',
              onPressed: _startSearch,
            ),
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: 'Settings',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const SettingsScreen(),
                  ),
                );
              },
            ),
          ],
        ],
      ),
      body: Consumer<ConversationProvider>(
        builder: (context, provider, child) {
          final conversations = _searchResults ?? provider.conversations;

          if (provider.conversations.isEmpty) {
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
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            );
          }

          if (_isSearching && _searchResults != null && conversations.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.search_off,
                    size: 64,
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No results found',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Try a different search term',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            itemCount: conversations.length,
            itemBuilder: (context, index) {
              final conversation = conversations[index];
              return Dismissible(
                key: Key(conversation.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  color: Colors.red,
                  child: const Icon(Icons.delete, color: Colors.white),
                ),
                onDismissed: (direction) {
                  provider.deleteConversation(conversation.id);
                },
                child: _ConversationListItem(
                  conversation: conversation,
                  searchQuery: _isSearching
                      ? _searchController.text.trim()
                      : null,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            ChatScreen(conversation: conversation),
                      ),
                    );
                  },
                  onLongPress: () async {
                    final result = await showModalActionSheet<String>(
                      context: context,
                      actions: [
                        const SheetAction(
                          key: 'delete',
                          label: 'Delete',
                          isDestructiveAction: true,
                        ),
                      ],
                    );
                    if (result == 'delete') {
                      provider.deleteConversation(conversation.id);
                    }
                  },
                ),
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
            // Default model exists — show combined dialog with model override option
            if (!context.mounted) return;

            final result = await showDialog<dynamic>(
              context: context,
              builder: (context) =>
                  McpServerSelectionDialog(selectedModel: defaultModel),
            );

            // User cancelled
            if (result == null || !context.mounted) return;

            List<String> selectedServerIds;
            if (result is McpServerSelectionResult) {
              selectedModel = result.model;
              selectedServerIds = result.serverIds;
            } else if (result is List<String>) {
              selectedModel = defaultModel;
              selectedServerIds = result;
            } else {
              return;
            }

            final provider = context.read<ConversationProvider>();
            final conversation = await provider.createConversation(
              model: selectedModel,
            );

            if (selectedServerIds.isNotEmpty) {
              await DatabaseService.instance.setConversationMcpServers(
                conversation.id,
                selectedServerIds,
              );
            }

            if (context.mounted) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ChatScreen(conversation: conversation),
                ),
              );
            }
          } else {
            // No default model — show model picker first
            selectedModel = await Navigator.push<String>(
              context,
              MaterialPageRoute(
                builder: (context) => const ModelPickerScreen(),
              ),
            );

            if (selectedModel == null || !context.mounted) return;

            // Show MCP server selection dialog (without model section)
            final selectedServerIds = await showDialog<List<String>>(
              context: context,
              builder: (context) => const McpServerSelectionDialog(),
            );

            // User cancelled
            if (selectedServerIds == null || !context.mounted) return;

            final provider = context.read<ConversationProvider>();
            final conversation = await provider.createConversation(
              model: selectedModel,
            );

            if (selectedServerIds.isNotEmpty) {
              await DatabaseService.instance.setConversationMcpServers(
                conversation.id,
                selectedServerIds,
              );
            }

            if (context.mounted) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ChatScreen(conversation: conversation),
                ),
              );
            }
          }
        },
        child: const Icon(Icons.add),
      ),
    ),
    ),
    );
  }
}

class _ConversationListItem extends StatelessWidget {
  final Conversation conversation;
  final String? searchQuery;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _ConversationListItem({
    required this.conversation,
    this.searchQuery,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(child: Icon(Icons.chat, size: 20)),
      title: searchQuery != null && searchQuery!.isNotEmpty
          ? _HighlightedText(
              text: conversation.title,
              query: searchQuery!,
              style: Theme.of(context).textTheme.bodyLarge,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            )
          : Text(
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
            DateFormatter.formatConversationDate(conversation.updatedAt),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }
}

/// Widget that highlights occurrences of [query] within [text].
class _HighlightedText extends StatelessWidget {
  final String text;
  final String query;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;

  const _HighlightedText({
    required this.text,
    required this.query,
    this.style,
    this.maxLines,
    this.overflow,
  });

  @override
  Widget build(BuildContext context) {
    if (query.isEmpty) {
      return Text(text, style: style, maxLines: maxLines, overflow: overflow);
    }

    final spans = <TextSpan>[];
    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    int start = 0;

    while (true) {
      final idx = lowerText.indexOf(lowerQuery, start);
      if (idx == -1) {
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }
      if (idx > start) {
        spans.add(TextSpan(text: text.substring(start, idx)));
      }
      spans.add(
        TextSpan(
          text: text.substring(idx, idx + query.length),
          style: TextStyle(
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
      start = idx + query.length;
    }

    return RichText(
      text: TextSpan(
        style: style ?? DefaultTextStyle.of(context).style,
        children: spans,
      ),
      maxLines: maxLines,
      overflow: overflow ?? TextOverflow.clip,
    );
  }
}
