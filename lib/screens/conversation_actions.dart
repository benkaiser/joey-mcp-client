import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../models/mcp_server.dart';
import '../providers/conversation_provider.dart';
import '../services/openrouter_service.dart';
import '../services/database_service.dart';
import '../services/conversation_import_export_service.dart';
import '../widgets/rename_dialog.dart';
import 'chat_screen.dart';
import 'model_picker_screen.dart';

/// Mixin that provides conversation-level actions:
/// sharing, new conversation, model switching, title generation, rename.
mixin ConversationActionsMixin on State<ChatScreen> {
  // These must be provided by the host class
  Map<String, dynamic>? get modelDetails;
  List<McpServer> get mcpServers;
  String getCurrentModel();
  void loadModelDetails();

  Future<void> shareConversation() async {
    final provider = context.read<ConversationProvider>();
    final messages = provider.getMessages(widget.conversation.id);

    if (messages.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No messages to share')),
        );
      }
      return;
    }

    final conversation = provider.conversations.firstWhere(
      (c) => c.id == widget.conversation.id,
    );

    final markdown = _conversationToMarkdown(conversation, messages);

    // On desktop, copy to clipboard since the share sheet lacks a copy option.
    // On mobile, use the native share sheet.
    final isDesktop = !kIsWeb &&
        (Platform.isMacOS || Platform.isWindows || Platform.isLinux);
    if (isDesktop) {
      await Clipboard.setData(ClipboardData(text: markdown));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Conversation copied to clipboard')),
        );
      }
    } else {
      await SharePlus.instance.share(ShareParams(text: markdown));
    }
  }

  Future<void> exportConversationAsJson() async {
    final provider = context.read<ConversationProvider>();
    final messages = provider.getMessages(widget.conversation.id);

    if (messages.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No messages to export')),
        );
      }
      return;
    }

    final conversation = provider.conversations.firstWhere(
      (c) => c.id == widget.conversation.id,
    );

    final jsonString = ConversationImportExportService.exportSingleConversation(
      conversation,
      messages,
    );

    final isDesktop = !kIsWeb &&
        (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

    try {
      if (isDesktop) {
        // On desktop, use file_picker to save file
        final result = await FilePicker.platform.saveFile(
          dialogTitle: 'Export Conversation',
          fileName: '${_sanitizeFileName(conversation.title)}.json',
          type: FileType.custom,
          allowedExtensions: ['json'],
        );
        if (result != null) {
          await File(result).writeAsString(jsonString);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Conversation exported')),
            );
          }
        }
      } else {
        // On mobile, write to temp file and share
        final tempDir = await getTemporaryDirectory();
        final fileName = '${_sanitizeFileName(conversation.title)}.json';
        final tempFile = File('${tempDir.path}/$fileName');
        await tempFile.writeAsString(jsonString);
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(tempFile.path)],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to export: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _sanitizeFileName(String name) {
    return name
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .replaceAll(RegExp(r'\s+'), '_')
        .toLowerCase();
  }

  String _conversationToMarkdown(
    Conversation conversation,
    List<Message> messages,
  ) {
    final buffer = StringBuffer();

    buffer.writeln('# ${conversation.title}');
    buffer.writeln();

    for (final message in messages) {
      switch (message.role) {
        case MessageRole.user:
          buffer.writeln('## User');
          buffer.writeln();
          buffer.writeln(message.content);
          buffer.writeln();
        case MessageRole.assistant:
          // Skip assistant messages that are only tool calls with no content
          if (message.content.isEmpty) break;
          buffer.writeln('## Assistant');
          buffer.writeln();
          buffer.writeln(message.content);
          buffer.writeln();
        case MessageRole.tool:
        case MessageRole.system:
        case MessageRole.modelChange:
        case MessageRole.elicitation:
        case MessageRole.mcpNotification:
          // Skip non-conversational messages
          break;
      }
    }

    return buffer.toString().trimRight();
  }

  Future<void> startNewConversation() async {
    final provider = context.read<ConversationProvider>();

    // Create a new conversation with the same model as the current one
    final newConversation = await provider.createConversation(
      model: getCurrentModel(),
    );

    // Copy MCP servers from current conversation to new conversation
    if (mcpServers.isNotEmpty) {
      final serverIds = mcpServers.map((s) => s.id).toList();
      await DatabaseService.instance.setConversationMcpServers(
        newConversation.id,
        serverIds,
      );
    }

    if (mounted) {
      // Replace current chat screen with the new conversation
      // Use fade transition to indicate this is a replacement, not forward navigation
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              ChatScreen(conversation: newConversation),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 200),
        ),
      );
    }
  }

  /// Open the model picker and switch the conversation's model
  Future<void> changeModel() async {
    final currentModel = getCurrentModel();
    final selectedModel = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (context) => ModelPickerScreen(
          defaultModel: currentModel,
          showDefaultToggle: false,
        ),
      ),
    );

    if (selectedModel == null || selectedModel == currentModel || !mounted) {
      return;
    }

    final provider = context.read<ConversationProvider>();

    // Update the conversation model in the database
    await provider.updateConversationModel(
      widget.conversation.id,
      selectedModel,
    );

    // Add a visual indicator for the model change
    final modelChangeMessage = Message(
      id: const Uuid().v4(),
      conversationId: widget.conversation.id,
      role: MessageRole.modelChange,
      content: 'Model changed from $currentModel to $selectedModel',
      timestamp: DateTime.now(),
    );
    await provider.addMessage(modelChangeMessage);

    // Refresh model details for the new model
    loadModelDetails();
  }

  Future<void> generateConversationTitle(
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
              'Based on this conversation, generate a short, descriptive title (less than 10 words, no quotes): ${messages.first.content}',
        },
      ];

      final response = await openRouterService.chatCompletion(
        model: getCurrentModel(),
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

  String getPricingText() {
    if (modelDetails == null || modelDetails!['pricing'] == null) {
      return '';
    }

    final pricing = modelDetails!['pricing'] as Map<String, dynamic>;
    final completionPrice = pricing['completion'];

    if (completionPrice == null) return '';

    // Convert string price to double and multiply by 1M
    final pricePerToken = double.tryParse(completionPrice.toString()) ?? 0.0;
    final pricePerMillion = pricePerToken * 1000000;

    return '(\$${pricePerMillion.toStringAsFixed(2)}/M out)';
  }

  void showRenameDialog(String currentTitle) {
    showDialog(
      context: context,
      builder: (dialogContext) => RenameDialog(
        initialTitle: currentTitle,
        onSave: (newTitle) async {
          await context.read<ConversationProvider>().updateConversationTitle(
            widget.conversation.id,
            newTitle,
          );
        },
      ),
    );
  }
}
