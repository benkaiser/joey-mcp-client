import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../providers/conversation_provider.dart';
import '../services/openrouter_service.dart';
import '../services/default_model_service.dart';
import '../widgets/message_bubble.dart';

class ChatScreen extends StatefulWidget {
  final Conversation conversation;

  const ChatScreen({super.key, required this.conversation});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  bool _isLoading = false;
  Map<String, dynamic>? _modelDetails;
  bool _hasGeneratedTitle = false;

  @override
  void initState() {
    super.initState();
    _loadModelDetails();
  }

  Future<void> _loadModelDetails() async {
    try {
      final openRouterService = context.read<OpenRouterService>();
      final models = await openRouterService.getModels();
      final model = models.firstWhere(
        (m) => m['id'] == widget.conversation.model,
        orElse: () => {},
      );
      if (mounted) {
        setState(() {
          _modelDetails = model;
        });
      }
    } catch (e) {
      // Silently fail - pricing is not critical
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 100), () {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      });
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final provider = context.read<ConversationProvider>();
    final openRouterService = context.read<OpenRouterService>();

    // Add user message
    final userMessage = Message(
      id: const Uuid().v4(),
      conversationId: widget.conversation.id,
      role: MessageRole.user,
      content: text,
      timestamp: DateTime.now(),
    );

    await provider.addMessage(userMessage);

    _messageController.text = '';

    _scrollToBottom();

    // Get AI response
    setState(() => _isLoading = true);

    try {
      // Get all messages for context
      final messages = provider.getMessages(widget.conversation.id);

      // Format messages for OpenRouter API
      final apiMessages = messages
          .map(
            (msg) => {
              'role': msg.role == MessageRole.user ? 'user' : 'assistant',
              'content': msg.content,
            },
          )
          .toList();

      // Create a placeholder message for streaming
      final assistantMessage = Message(
        id: const Uuid().v4(),
        conversationId: widget.conversation.id,
        role: MessageRole.assistant,
        content: '',
        timestamp: DateTime.now(),
      );

      await provider.addMessage(assistantMessage);
      setState(() => _isLoading = false);
      _scrollToBottom();

      // Make streaming API request using the conversation's selected model
      final stream = openRouterService.chatCompletionStream(
        model: widget.conversation.model,
        messages: apiMessages,
      );

      String fullContent = '';
      await for (final chunk in stream) {
        fullContent += chunk;
        await provider.updateMessageContent(assistantMessage.id, fullContent);
        _scrollToBottom();
      }

      // Auto-generate title after first response if enabled
      if (!_hasGeneratedTitle && mounted) {
        _hasGeneratedTitle = true;
        final autoTitleEnabled =
            await DefaultModelService.getAutoTitleEnabled();
        if (autoTitleEnabled) {
          _generateConversationTitle(provider, openRouterService);
        }
      }
    } catch (e) {
      // Show error message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ConversationProvider>(
      builder: (context, provider, child) {
        final conversation = provider.conversations.firstWhere(
          (c) => c.id == widget.conversation.id,
          orElse: () => widget.conversation,
        );

        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(conversation.title),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        conversation.model,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_modelDetails != null &&
                        _modelDetails!['pricing'] != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        _getPricingText(),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
            backgroundColor: Theme.of(context).colorScheme.inversePrimary,
            actions: [
              IconButton(
                icon: const Icon(Icons.edit),
                onPressed: () => _showRenameDialog(),
              ),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: Builder(
                  builder: (context) {
                    final messages = provider.getMessages(
                      widget.conversation.id,
                    );

                    if (messages.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.message_outlined,
                              size: 64,
                              color: Theme.of(
                                context,
                              ).colorScheme.primary.withValues(alpha: 0.5),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Start a conversation',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Type a message below to begin',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      );
                    }

                    return ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        return MessageBubble(message: messages[index]);
                      },
                    );
                  },
                ),
              ),
              if (_isLoading)
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    children: [
                      const SizedBox(width: 16),
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Thinking...',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              _buildMessageInput(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMessageInput() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            offset: const Offset(0, -1),
            blurRadius: 4,
            color: Colors.black.withValues(alpha: 0.1),
          ),
        ],
      ),
      padding: const EdgeInsets.all(8.0),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _messageController,
                focusNode: _focusNode,
                decoration: InputDecoration(
                  hintText: 'Type a message...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                maxLines: null,
                textInputAction: TextInputAction.send,
                onSubmitted: (val) {
                  _sendMessage();
                  _focusNode.requestFocus();
                },
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: _isLoading ? null : _sendMessage,
              icon: const Icon(Icons.send),
              style: IconButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                disabledBackgroundColor: Colors.grey[300],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _generateConversationTitle(
    ConversationProvider provider,
    OpenRouterService openRouterService,
  ) async {
    // Only generate if conversation still has default title
    final currentTitle = widget.conversation.title;
    if (!currentTitle.startsWith('New Chat')) return;

    try {
      final messages = provider.getMessages(widget.conversation.id);
      if (messages.isEmpty) return;

      // Create a prompt for title generation
      final apiMessages = [
        {
          'role': 'user',
          'content':
              'Based on this conversation, generate a short, descriptive title (maximum 6 words, no quotes): ${messages.first.content}',
        },
      ];

      final response = await openRouterService.chatCompletion(
        model: widget.conversation.model,
        messages: apiMessages,
      );

      final title = (response['choices'][0]['message']['content'] as String)
          .trim()
          .replaceAll('"', '')
          .replaceAll("'", '');

      if (title.isNotEmpty && mounted) {
        await provider.updateConversationTitle(widget.conversation.id, title);
      }
    } catch (e) {
      // Silently fail - title generation is not critical
    }
  }

  void _showRenameDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => _RenameDialog(
        initialTitle: widget.conversation.title,
        onSave: (newTitle) async {
          await context.read<ConversationProvider>().updateConversationTitle(
            widget.conversation.id,
            newTitle,
          );
        },
      ),
    );
  }

  String _getPricingText() {
    if (_modelDetails == null || _modelDetails!['pricing'] == null) {
      return '';
    }

    final pricing = _modelDetails!['pricing'] as Map<String, dynamic>;
    final completionPrice = pricing['completion'];

    if (completionPrice == null) return '';

    // Convert string price to double and multiply by 1M
    final pricePerToken = double.tryParse(completionPrice.toString()) ?? 0.0;
    final pricePerMillion = pricePerToken * 1000000;

    return '(\$${pricePerMillion.toStringAsFixed(2)}/M out)';
  }
}

class _RenameDialog extends StatefulWidget {
  final String initialTitle;
  final Future<void> Function(String) onSave;

  const _RenameDialog({required this.initialTitle, required this.onSave});

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialTitle);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rename Conversation'),
      content: TextField(
        controller: _controller,
        decoration: const InputDecoration(
          labelText: 'Conversation Title',
          border: OutlineInputBorder(),
        ),
        autofocus: true,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () async {
            final newTitle = _controller.text.trim();
            if (newTitle.isNotEmpty) {
              await widget.onSave(newTitle);
            }
            if (context.mounted) {
              Navigator.pop(context);
            }
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
