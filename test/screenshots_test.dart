import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_screenshot/golden_screenshot.dart';
import 'package:joey_mcp_client_flutter/models/conversation.dart';
import 'package:joey_mcp_client_flutter/models/message.dart';
import 'package:joey_mcp_client_flutter/widgets/message_bubble.dart';
import 'package:joey_mcp_client_flutter/widgets/thinking_indicator.dart';

// ──────────────────────────────────────────────
// Font loading for readable golden screenshots
// ──────────────────────────────────────────────

/// Load Noto Sans and Noto Emoji fonts so golden screenshots render
/// real readable text instead of Ahem rectangles.
Future<void> _loadTestFonts() async {
  final notoSansData = File('test/fonts/NotoSans-Regular.ttf').readAsBytesSync();
  final notoEmojiData = File('test/fonts/NotoEmoji-Regular.ttf').readAsBytesSync();

  // Register Noto Sans under all platform font family names that
  // Flutter / Material may resolve to, plus common fallbacks used
  // by renderers like mermaid.
  const fontFamilies = [
    'Roboto', // Android default
    'sans-serif',
    '.SF Pro Text', // iOS
    '.SF Pro Display',
    '.AppleSystemUIFont',
    'Segoe UI', // Windows
    'Ubuntu', // Linux
    'Arial', // Common fallback
    'Helvetica', // Common fallback
    'Inter', // golden_screenshot default
    'FlutterTest', // Flutter test default
  ];

  for (final family in fontFamilies) {
    final loader = FontLoader(family);
    loader.addFont(Future.value(ByteData.view(notoSansData.buffer)));
    await loader.load();
  }

  // Register emoji font
  final emojiLoader = FontLoader('Noto Emoji');
  emojiLoader.addFont(Future.value(ByteData.view(notoEmojiData.buffer)));
  await emojiLoader.load();
}

// ──────────────────────────────────────────────
// App theme (matches main.dart dark theme)
// ──────────────────────────────────────────────

ThemeData get _appDarkTheme => ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color.fromARGB(255, 1, 234, 255),
    brightness: Brightness.dark,
  ),
  useMaterial3: true,
  scaffoldBackgroundColor: const Color(0xFF0D1117),
  cardTheme: const CardThemeData(
    color: Color(0xFF161B22),
    elevation: 0,
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: Color(0xFF161B22),
    foregroundColor: Colors.white,
    elevation: 0,
  ),
  dialogTheme: const DialogThemeData(
    backgroundColor: Color(0xFF1C2128),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: const Color(0xFF1C2128),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFF30363D)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFF30363D)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFF01EAFF), width: 2),
    ),
  ),
  dividerColor: const Color(0xFF30363D),
  listTileTheme: const ListTileThemeData(iconColor: Colors.white70),
);

// ──────────────────────────────────────────────
// Mock data
// ──────────────────────────────────────────────

final _mockConversations = [
  Conversation(
    id: '1',
    title: 'Plan my Tokyo trip itinerary',
    model: 'anthropic/claude-sonnet-4',
    createdAt: DateTime.now().subtract(const Duration(minutes: 30)),
    updatedAt: DateTime.now().subtract(const Duration(minutes: 5)),
  ),
  Conversation(
    id: '2',
    title: 'Log today\'s meals and calories',
    model: 'google/gemini-2.5-pro',
    createdAt: DateTime.now().subtract(const Duration(hours: 2)),
    updatedAt: DateTime.now().subtract(const Duration(hours: 1)),
  ),
  Conversation(
    id: '3',
    title: 'What\'s on my task list this week?',
    model: 'anthropic/claude-sonnet-4',
    createdAt: DateTime.now().subtract(const Duration(hours: 5)),
    updatedAt: DateTime.now().subtract(const Duration(hours: 3)),
  ),
  Conversation(
    id: '4',
    title: 'Summarize my meeting notes',
    model: 'openai/gpt-4o',
    createdAt: DateTime.now().subtract(const Duration(days: 1)),
    updatedAt: DateTime.now().subtract(const Duration(days: 1)),
  ),
  Conversation(
    id: '5',
    title: 'Help me learn Spanish vocabulary',
    model: 'openai/gpt-4o',
    createdAt: DateTime.now().subtract(const Duration(days: 2)),
    updatedAt: DateTime.now().subtract(const Duration(days: 2)),
  ),
  Conversation(
    id: '6',
    title: 'Track my morning habits',
    model: 'anthropic/claude-sonnet-4',
    createdAt: DateTime.now().subtract(const Duration(days: 3)),
    updatedAt: DateTime.now().subtract(const Duration(days: 3)),
  ),
  Conversation(
    id: '7',
    title: 'Research best budget laptops',
    model: 'google/gemini-2.5-pro',
    createdAt: DateTime.now().subtract(const Duration(days: 5)),
    updatedAt: DateTime.now().subtract(const Duration(days: 4)),
  ),
];

const _conversationId = 'chat-1';

/// Screenshot 2: Nutrition tracking via MCP tool (collapsed)
List<Message> _nutritionToolMessages() => [
  // Earlier conversation context
  Message(
    id: 'tc-0a',
    conversationId: _conversationId,
    role: MessageRole.user,
    content: 'I had oatmeal with blueberries and a black coffee for breakfast.',
    timestamp: DateTime.now().subtract(const Duration(minutes: 25)),
  ),
  Message(
    id: 'tc-0b',
    conversationId: _conversationId,
    role: MessageRole.assistant,
    content: '',
    timestamp: DateTime.now().subtract(const Duration(minutes: 24)),
    toolCallData: jsonEncode([
      {
        'id': 'call_0',
        'type': 'function',
        'function': {
          'name': 'log_meal',
          'arguments': jsonEncode({
            'meal': 'breakfast',
            'items': [
              {'name': 'Oatmeal with blueberries', 'calories': 310, 'protein': 22},
              {'name': 'Black coffee', 'calories': 5, 'protein': 0},
            ],
          }),
        },
      },
    ]),
  ),
  Message(
    id: 'tc-0c',
    conversationId: _conversationId,
    role: MessageRole.tool,
    content: 'Meal logged. Daily totals: 315 cal, 22g protein.',
    timestamp: DateTime.now().subtract(const Duration(minutes: 24)),
    toolCallId: 'call_0',
    toolName: 'log_meal',
  ),
  Message(
    id: 'tc-0d',
    conversationId: _conversationId,
    role: MessageRole.assistant,
    content:
        'Logged your breakfast — 315 calories and 22g of protein. '
        'Great start to the day! You have **1,685 calories** remaining.',
    timestamp: DateTime.now().subtract(const Duration(minutes: 23)),
  ),
  // Main conversation
  Message(
    id: 'tc-1',
    conversationId: _conversationId,
    role: MessageRole.user,
    content: 'I just had a chicken salad for lunch with a glass of orange juice.',
    timestamp: DateTime.now().subtract(const Duration(minutes: 10)),
  ),
  // Tool call (collapsed in non-thinking mode)
  Message(
    id: 'tc-2',
    conversationId: _conversationId,
    role: MessageRole.assistant,
    content: '',
    timestamp: DateTime.now().subtract(const Duration(minutes: 9)),
    toolCallData: jsonEncode([
      {
        'id': 'call_1',
        'type': 'function',
        'function': {
          'name': 'log_meal',
          'arguments': jsonEncode({
            'meal': 'lunch',
            'items': [
              {'name': 'Grilled chicken salad', 'calories': 350, 'protein': 35},
              {'name': 'Orange juice (8oz)', 'calories': 110, 'protein': 2},
            ],
          }),
        },
      },
    ]),
  ),
  // Tool result
  Message(
    id: 'tc-3',
    conversationId: _conversationId,
    role: MessageRole.tool,
    content:
        'Meal logged successfully. Daily totals updated:\n'
        '- Calories: 820 / 2,000\n'
        '- Protein: 62g / 150g\n'
        '- Remaining: 1,180 cal',
    timestamp: DateTime.now().subtract(const Duration(minutes: 9)),
    toolCallId: 'call_1',
    toolName: 'log_meal',
  ),
  // Assistant response
  Message(
    id: 'tc-4',
    conversationId: _conversationId,
    role: MessageRole.assistant,
    content:
        'Logged your lunch! Here\'s your day so far:\n\n'
        '| Meal | Calories | Protein |\n'
        '|------|----------|---------|\n'
        '| Breakfast | 360 cal | 25g |\n'
        '| Lunch | 460 cal | 37g |\n'
        '| **Total** | **820 cal** | **62g** |\n\n'
        'You have **1,180 calories** remaining for today. '
        'You\'re on track with your protein goal — great choice with the chicken salad!',
    timestamp: DateTime.now().subtract(const Duration(minutes: 8)),
  ),
];

/// Screenshot 3: Habit tracking check-in (no tool use, rich markdown)
List<Message> _habitTrackingMessages() => [
  // Earlier conversation context
  Message(
    id: 'ht-0a',
    conversationId: _conversationId,
    role: MessageRole.user,
    content: 'Can you set up a habit tracker for me? I want to track meditation, exercise, reading, and journaling.',
    timestamp: DateTime.now().subtract(const Duration(minutes: 15)),
  ),
  Message(
    id: 'ht-0b',
    conversationId: _conversationId,
    role: MessageRole.assistant,
    content: '',
    timestamp: DateTime.now().subtract(const Duration(minutes: 14)),
    toolCallData: jsonEncode([
      {
        'id': 'call_setup',
        'type': 'function',
        'function': {
          'name': 'create_habit_tracker',
          'arguments': jsonEncode({
            'habits': ['meditation', 'exercise', 'reading', 'journaling'],
          }),
        },
      },
    ]),
  ),
  Message(
    id: 'ht-0c',
    conversationId: _conversationId,
    role: MessageRole.tool,
    content: 'Habit tracker created with 4 habits.',
    timestamp: DateTime.now().subtract(const Duration(minutes: 14)),
    toolCallId: 'call_setup',
    toolName: 'create_habit_tracker',
  ),
  Message(
    id: 'ht-0d',
    conversationId: _conversationId,
    role: MessageRole.assistant,
    content:
        'All set! I\'ve created your habit tracker with 4 daily habits: '
        '**meditation**, **exercise**, **reading**, and **journaling**. '
        'I\'ll check in each morning. Ready to log today\'s progress?',
    timestamp: DateTime.now().subtract(const Duration(minutes: 13)),
  ),
  // Main question
  Message(
    id: 'ht-1',
    conversationId: _conversationId,
    role: MessageRole.user,
    content: 'How have my morning habits been going this week?',
    timestamp: DateTime.now().subtract(const Duration(minutes: 6)),
  ),
  // Tool call (collapsed)
  Message(
    id: 'ht-2',
    conversationId: _conversationId,
    role: MessageRole.assistant,
    content: '',
    timestamp: DateTime.now().subtract(const Duration(minutes: 5)),
    toolCallData: jsonEncode([
      {
        'id': 'call_2',
        'type': 'function',
        'function': {
          'name': 'get_habit_log',
          'arguments': jsonEncode({
            'week': 'current',
            'habits': ['meditation', 'exercise', 'reading', 'journaling'],
          }),
        },
      },
    ]),
  ),
  // Tool result
  Message(
    id: 'ht-3',
    conversationId: _conversationId,
    role: MessageRole.tool,
    content: 'Habit data for Feb 10-14 retrieved.',
    timestamp: DateTime.now().subtract(const Duration(minutes: 5)),
    toolCallId: 'call_2',
    toolName: 'get_habit_log',
  ),
  // Assistant response
  Message(
    id: 'ht-4',
    conversationId: _conversationId,
    role: MessageRole.assistant,
    content:
        'Here\'s your habit streak this week:\n\n'
        '| Habit | Mon | Tue | Wed | Thu | Fri |\n'
        '|-------|-----|-----|-----|-----|-----|\n'
        '| Meditation | Yes | Yes | Yes | Yes | Yes |\n'
        '| Exercise | Yes | No | Yes | Yes | No |\n'
        '| Reading | Yes | Yes | No | Yes | Yes |\n'
        '| Journaling | No | Yes | Yes | No | Yes |\n\n'
        '**Great job on meditation** — a perfect 5/5 streak!\n\n'
        'Exercise slipped on Tuesday and Friday. Want me to schedule reminders for those days next week?',
    timestamp: DateTime.now().subtract(const Duration(minutes: 4)),
  ),
];

/// Screenshot 4: Knowledge base / recipe lookup
List<Message> _knowledgeBaseMessages() => [
  // Earlier conversation context
  Message(
    id: 'kb-0a',
    conversationId: _conversationId,
    role: MessageRole.user,
    content: 'What ingredients do I have in my pantry?',
    timestamp: DateTime.now().subtract(const Duration(minutes: 12)),
  ),
  Message(
    id: 'kb-0b',
    conversationId: _conversationId,
    role: MessageRole.assistant,
    content: '',
    timestamp: DateTime.now().subtract(const Duration(minutes: 11)),
    toolCallData: jsonEncode([
      {
        'id': 'call_pantry',
        'type': 'function',
        'function': {
          'name': 'get_pantry',
          'arguments': jsonEncode({}),
        },
      },
    ]),
  ),
  Message(
    id: 'kb-0c',
    conversationId: _conversationId,
    role: MessageRole.tool,
    content: 'Pantry contents retrieved.',
    timestamp: DateTime.now().subtract(const Duration(minutes: 11)),
    toolCallId: 'call_pantry',
    toolName: 'get_pantry',
  ),
  Message(
    id: 'kb-0d',
    conversationId: _conversationId,
    role: MessageRole.assistant,
    content:
        'Here\'s what you have in your pantry:\n\n'
        '**Proteins:** chicken breast, ground beef, eggs\n'
        '**Grains:** jasmine rice, pasta, bread\n'
        '**Produce:** onions, garlic, lemons, spinach\n'
        '**Pantry staples:** olive oil, soy sauce, chicken broth\n\n'
        'Want me to suggest some recipes with these?',
    timestamp: DateTime.now().subtract(const Duration(minutes: 10)),
  ),
  // Main query
  Message(
    id: 'kb-1',
    conversationId: _conversationId,
    role: MessageRole.user,
    content: 'Find me a quick dinner recipe that uses chicken and rice.',
    timestamp: DateTime.now().subtract(const Duration(minutes: 5)),
  ),
  Message(
    id: 'kb-2',
    conversationId: _conversationId,
    role: MessageRole.assistant,
    content: '',
    timestamp: DateTime.now().subtract(const Duration(minutes: 4)),
    toolCallData: jsonEncode([
      {
        'id': 'call_3',
        'type': 'function',
        'function': {
          'name': 'search_recipes',
          'arguments': jsonEncode({
            'ingredients': ['chicken', 'rice'],
            'max_time': 30,
          }),
        },
      },
    ]),
  ),
  Message(
    id: 'kb-3',
    conversationId: _conversationId,
    role: MessageRole.tool,
    content: 'Found 3 matching recipes under 30 minutes.',
    timestamp: DateTime.now().subtract(const Duration(minutes: 4)),
    toolCallId: 'call_3',
    toolName: 'search_recipes',
  ),
  Message(
    id: 'kb-4',
    conversationId: _conversationId,
    role: MessageRole.assistant,
    content:
        '## One-Pan Lemon Herb Chicken & Rice\n'
        '25 minutes · Serves 4\n\n'
        '### Ingredients\n'
        '- 4 chicken thighs\n'
        '- 1 1/2 cups jasmine rice\n'
        '- 2 cups chicken broth\n'
        '- 1 lemon (juiced + zested)\n'
        '- 2 cloves garlic, minced\n'
        '- Fresh herbs (parsley, thyme)\n\n'
        '### Instructions\n'
        '1. Season chicken with salt, pepper, and lemon zest\n'
        '2. Sear chicken skin-side down for 5 min\n'
        '3. Add garlic, rice, broth, and lemon juice\n'
        '4. Cover and simmer for 18 min\n'
        '5. Rest 5 min, then garnish with fresh herbs\n\n'
        'This is a family favorite — everything cooks in one pan!',
    timestamp: DateTime.now().subtract(const Duration(minutes: 3)),
  ),
];

/// Screenshot 5: Mermaid diagram — morning routine flowchart
/// The mermaid chart is pre-rendered to PNG externally (via mmdc CLI)
/// and embedded via a special marker, since Flutter's test font environment
/// cannot render text inside the mermaid CustomPainter.
const _mermaidMarker = '{{MERMAID:morning_routine}}';

List<Message> _mermaidMessages() => [
  // Earlier conversation context
  Message(
    id: 'mm-0a',
    conversationId: _conversationId,
    role: MessageRole.user,
    content: 'I want to optimize my morning routine. Can you help me map it out?',
    timestamp: DateTime.now().subtract(const Duration(minutes: 8)),
  ),
  Message(
    id: 'mm-0b',
    conversationId: _conversationId,
    role: MessageRole.assistant,
    content:
        'Of course! Let\'s start by listing your current morning activities. '
        'What does your typical morning look like from wake-up to starting work?',
    timestamp: DateTime.now().subtract(const Duration(minutes: 7)),
  ),
  Message(
    id: 'mm-0c',
    conversationId: _conversationId,
    role: MessageRole.user,
    content:
        'I wake up at 6:30, drink water, then either work out or do some stretching '
        'depending on the day. After that I shower, have breakfast, review my tasks, '
        'and start work around 8:30.',
    timestamp: DateTime.now().subtract(const Duration(minutes: 5)),
  ),
  // Main request
  Message(
    id: 'mm-1',
    conversationId: _conversationId,
    role: MessageRole.user,
    content: 'Show me a diagram of my morning routine flow.',
    timestamp: DateTime.now().subtract(const Duration(minutes: 3)),
  ),
  Message(
    id: 'mm-2',
    conversationId: _conversationId,
    role: MessageRole.assistant,
    content:
        'Here\'s your morning routine as a flowchart:\n\n'
        '$_mermaidMarker\n\n'
        'Your routine takes about **2 hours** from wake-up to starting work. '
        'The workout/stretch branch keeps it flexible for rest days.',
    timestamp: DateTime.now().subtract(const Duration(minutes: 2)),
  ),
];

/// Screenshot 6: Image analysis — user sends a photo and asks about it
List<Message> _imageAnalysisMessages() => [
  Message(
    id: 'ia-0a',
    conversationId: _conversationId,
    role: MessageRole.user,
    content: 'I\'m planning a hiking trip. Can you help me figure out what gear I need?',
    timestamp: DateTime.now().subtract(const Duration(minutes: 12)),
  ),
  Message(
    id: 'ia-0b',
    conversationId: _conversationId,
    role: MessageRole.assistant,
    content:
        'I\'d be happy to help with your hiking trip! To give you the best gear recommendations, '
        'it would help to know:\n\n'
        '- **Where** are you hiking?\n'
        '- **How long** is the trail?\n'
        '- **What season** will you be going?\n\n'
        'If you have any photos of the terrain or trail conditions, feel free to share them!',
    timestamp: DateTime.now().subtract(const Duration(minutes: 11)),
  ),
  Message(
    id: 'ia-1',
    conversationId: _conversationId,
    role: MessageRole.user,
    content: 'Here\'s a photo from the area. What kind of terrain is this and what should I pack?',
    timestamp: DateTime.now().subtract(const Duration(minutes: 5)),
    imageData: jsonEncode([
      {
        'data': _landscapeImageBase64,
        'mimeType': 'image/jpeg',
      },
    ]),
  ),
  Message(
    id: 'ia-2',
    conversationId: _conversationId,
    role: MessageRole.assistant,
    content:
        'This is a stunning **alpine mountain landscape** with rugged peaks and '
        'what appears to be glacial terrain. Based on this photo, here\'s what I\'d recommend:\n\n'
        '### Essential Gear\n'
        '- **Hiking boots** with ankle support and good grip\n'
        '- **Layered clothing** — temperatures can drop quickly at altitude\n'
        '- **Waterproof jacket** — weather changes fast in the mountains\n'
        '- **Trekking poles** for steep, rocky sections\n'
        '- **Sun protection** — UV is stronger at elevation\n\n'
        '### Safety Items\n'
        '- First aid kit\n'
        '- Trail map and compass (don\'t rely only on GPS)\n'
        '- Emergency whistle and headlamp\n\n'
        'The terrain looks moderately challenging with some steep elevation changes. '
        'How long is the hike you\'re planning?',
    timestamp: DateTime.now().subtract(const Duration(minutes: 4)),
  ),
];

// ──────────────────────────────────────────────
// Mock screens (self-contained, no services)
// ──────────────────────────────────────────────

/// Mock conversation list screen
class _MockConversationListScreen extends StatelessWidget {
  const _MockConversationListScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Joey MCP Client'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Search conversations',
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () {},
          ),
        ],
      ),
      body: ListView.builder(
        itemCount: _mockConversations.length,
        itemBuilder: (context, index) {
          final conversation = _mockConversations[index];
          return _MockConversationListItem(conversation: conversation);
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _MockConversationListItem extends StatelessWidget {
  final Conversation conversation;
  const _MockConversationListItem({required this.conversation});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const CircleAvatar(child: Icon(Icons.chat, size: 20)),
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
            _formatDate(conversation.updatedAt),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      onTap: () {},
    );
  }

  String _formatDate(DateTime updatedAt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(updatedAt.year, updatedAt.month, updatedAt.day);
    final diff = today.difference(date).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return '$diff days ago';
    return '${updatedAt.month}/${updatedAt.day}/${updatedAt.year}';
  }
}

/// Mock chat screen that renders provided messages
class _MockChatScreen extends StatelessWidget {
  final String title;
  final String model;
  final List<Message> messages;
  final bool showThinking;
  final int mcpServerCount;
  final bool scrollToTop;

  const _MockChatScreen({
    required this.title,
    required this.model,
    required this.messages,
    this.showThinking = false,
    this.mcpServerCount = 0,
    this.scrollToTop = false,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Row(
              children: [
                Flexible(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          model,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.swap_horiz,
                        size: 14,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ],
                  ),
                ),
                if (mcpServerCount > 0) ...[
                  const SizedBox(width: 8),
                  Icon(
                    Icons.dns,
                    size: 14,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '$mcpServerCount MCP',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
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
            icon: Icon(
              showThinking ? Icons.visibility : Icons.visibility_off,
            ),
            tooltip: showThinking ? 'Hide thinking' : 'Show thinking',
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: 'Share',
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.note_add),
            tooltip: 'New conversation',
            onPressed: () {},
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: messages.isEmpty
                ? _buildEmptyState(context)
                : _buildMessageList(context),
          ),
          _buildMessageInput(context),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.message_outlined,
                  size: 64,
                  color: Theme.of(context).colorScheme.primary
                      .withValues(alpha: 0.5),
                ),
                const SizedBox(height: 16),
                Text(
                  'Start a conversation',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  'Type a message below to begin',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        // Command palette
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: _buildCommandPalette(context),
        ),
      ],
    );
  }

  Widget _buildCommandPalette(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4.0),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (mcpServerCount > 0)
            ActionChip(
              avatar: Icon(
                Icons.auto_awesome,
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              ),
              label: const Text('Prompts'),
              onPressed: () {},
              side: BorderSide(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
              ),
            ),
          ActionChip(
            avatar: Icon(
              Icons.dns,
              size: 18,
              color: mcpServerCount > 0
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            label: Text(
              mcpServerCount > 0
                  ? 'MCP Servers ($mcpServerCount)'
                  : 'MCP Servers',
            ),
            onPressed: () {},
            side: BorderSide(
              color: mcpServerCount > 0
                  ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.5)
                  : Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          if (mcpServerCount > 0)
            ActionChip(
              avatar: Icon(
                Icons.bug_report_outlined,
                size: 18,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              label: const Text('Debug'),
              onPressed: () {},
              side: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMessageList(BuildContext context) {
    // Build display items in forward order, then render normally
    final displayItems = <Widget>[];

    for (final message in messages) {
      // Tool result messages - show as collapsed indicator
      if (message.role == MessageRole.tool) {
        if (!showThinking) {
          displayItems.add(ThinkingIndicator(message: message));
        } else {
          final isError =
              message.content.startsWith('Failed to parse tool arguments') ||
              message.content.startsWith('Error executing tool') ||
              message.content.startsWith('Tool not found') ||
              message.content.startsWith('MCP error');
          final icon = isError ? '❌' : '✅';
          final formattedMessage = message.copyWith(
            content:
                '$icon **Result from ${message.toolName}:**\n\n${message.content}',
          );
          displayItems.add(
            MessageBubble(
              message: formattedMessage,
              showThinking: showThinking,
            ),
          );
        }
        continue;
      }

      // Assistant messages with tool calls - show as collapsed indicator
      if (message.role == MessageRole.assistant && message.toolCallData != null) {
        if (!showThinking) {
          displayItems.add(ThinkingIndicator(message: message));
        } else {
          // Build tool call display
          String toolCallContent = '';
          try {
            final toolCalls = jsonDecode(message.toolCallData!) as List;
            for (final toolCall in toolCalls) {
              final toolName = toolCall['function']['name'];
              final toolArgsStr = toolCall['function']['arguments'];
              if (toolCallContent.isNotEmpty) toolCallContent += '\n\n';
              toolCallContent += '🔧 **Calling tool:** $toolName';
              try {
                final Map<String, dynamic> toolArgs;
                if (toolArgsStr is String) {
                  toolArgs = Map<String, dynamic>.from(
                    const JsonCodec().decode(toolArgsStr),
                  );
                } else {
                  toolArgs = Map<String, dynamic>.from(toolArgsStr);
                }
                if (toolArgs.isNotEmpty) {
                  final prettyArgs =
                      const JsonEncoder.withIndent('  ').convert(toolArgs);
                  toolCallContent +=
                      '\n\nArguments:\n```json\n$prettyArgs\n```';
                }
              } catch (_) {
                toolCallContent +=
                    '\n\nArguments:\n```\n$toolArgsStr\n```';
              }
            }
          } catch (_) {}

          final formattedMessage = Message(
            id: message.id,
            conversationId: message.conversationId,
            role: message.role,
            content: toolCallContent,
            timestamp: message.timestamp,
            toolCallData: message.toolCallData,
          );
          displayItems.add(
            MessageBubble(
              message: formattedMessage,
              showThinking: showThinking,
            ),
          );
        }
        continue;
      }

      // Regular messages — check for mermaid marker
      if (message.content.contains(_mermaidMarker)) {
        displayItems.add(
          _MermaidMessageWidget(message: message, showThinking: showThinking),
        );
      } else {
        displayItems.add(
          MessageBubble(message: message, showThinking: showThinking),
        );
      }
    }

    // When scrollToTop is true, render in natural order (top-down).
    // Otherwise use a reversed ListView so content gravitates to the bottom.
    if (scrollToTop) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ...displayItems,
          if (mcpServerCount > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: _buildCommandPalette(context),
            ),
        ],
      );
    }

    // Build the final list in reversed order for a reversed ListView
    // (index 0 = bottom). Command palette first (bottom), then messages
    // newest-to-oldest.
    final reversedItems = <Widget>[
      // Command palette at the bottom of the message list
      if (mcpServerCount > 0)
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: _buildCommandPalette(context),
        ),
      ...displayItems.reversed,
    ];

    return ListView(
      reverse: true,
      padding: const EdgeInsets.all(16),
      children: reversedItems,
    );
  }

  Widget _buildMessageInput(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            offset: const Offset(0, -1),
            blurRadius: 4,
            color: Colors.black.withValues(alpha: 0.3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(8.0),
      child: SafeArea(
        child: Row(
          children: [
            IconButton(
              icon: Icon(
                Icons.add_photo_alternate_outlined,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              onPressed: () {},
            ),
            Expanded(
              child: TextField(
                controller: TextEditingController(),
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
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: () {},
              icon: const Icon(Icons.send),
              style: IconButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pre-load mermaid image bytes synchronously at test startup
/// so Image.memory doesn't trigger async loading during pumpFrames.
late final Uint8List _mermaidImageBytes;

/// Pre-load landscape image as base64 for the image analysis screenshot.
late final String _landscapeImageBase64;

/// Renders an assistant message that contains a mermaid marker.
/// Splits the content around the marker, renders text via MessageBubble
/// (SmoothMarkdown) and the diagram as a pre-rendered PNG in a styled
/// container matching flutter_smooth_markdown's mermaid wrapper.
class _MermaidMessageWidget extends StatelessWidget {
  final Message message;
  final bool showThinking;

  const _MermaidMessageWidget({
    required this.message,
    this.showThinking = false,
  });

  @override
  Widget build(BuildContext context) {
    final parts = message.content.split(_mermaidMarker);
    final beforeText = parts[0].trim();
    final afterText = parts.length > 1 ? parts[1].trim() : '';

    // Combine into one assistant bubble: text before, diagram, text after
    final combinedContent = [beforeText, if (afterText.isNotEmpty) afterText]
        .join('\n\n');
    final textMessage = message.copyWith(content: combinedContent);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Render text portions via normal MessageBubble
        MessageBubble(message: textMessage, showThinking: showThinking),
        // Render pre-rendered mermaid diagram in styled container
        Padding(
          padding: const EdgeInsets.only(left: 16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.grey.withValues(alpha: 0.3),
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Image.memory(
                  _mermaidImageBytes,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────
// Screenshot tests
// ──────────────────────────────────────────────

void main() {
  _mermaidImageBytes = File('test/assets/morning_routine.png').readAsBytesSync();
  _landscapeImageBase64 = base64Encode(
    File('test/assets/mountain_landscape.jpg').readAsBytesSync(),
  );

  group('Play Store Screenshots:', () {
    _screenshot(
      '1_conversation_list',
      home: const _MockConversationListScreen(),
    );

    _screenshot(
      '2_chat_nutrition_tracking',
      home: _MockChatScreen(
        title: 'Log today\'s meals',
        model: 'anthropic/claude-sonnet-4',
        messages: _nutritionToolMessages(),
        showThinking: false,
        mcpServerCount: 1,
      ),
    );

    _screenshot(
      '3_chat_habit_tracking',
      home: _MockChatScreen(
        title: 'My morning habits',
        model: 'anthropic/claude-sonnet-4',
        messages: _habitTrackingMessages(),
        showThinking: false,
        mcpServerCount: 1,
      ),
    );

    _screenshot(
      '4_chat_recipe_search',
      home: _MockChatScreen(
        title: 'Quick dinner ideas',
        model: 'google/gemini-2.5-pro',
        messages: _knowledgeBaseMessages(),
        showThinking: false,
        mcpServerCount: 1,
      ),
    );

    _screenshot(
      '5_chat_mermaid_diagram',
      home: _MockChatScreen(
        title: 'My morning routine',
        model: 'anthropic/claude-sonnet-4',
        messages: _mermaidMessages(),
        mcpServerCount: 1,
        scrollToTop: true,
      ),
    );

    _screenshot(
      '6_chat_image_analysis',
      home: _MockChatScreen(
        title: 'Hiking trip planning',
        model: 'anthropic/claude-sonnet-4',
        messages: _imageAnalysisMessages(),
      ),
    );
  });

  group('App Store Screenshots:', () {
    _screenshotIOS(
      '1_conversation_list',
      home: const _MockConversationListScreen(),
    );

    _screenshotIOS(
      '2_chat_nutrition_tracking',
      home: _MockChatScreen(
        title: 'Log today\'s meals',
        model: 'anthropic/claude-sonnet-4',
        messages: _nutritionToolMessages(),
        showThinking: false,
        mcpServerCount: 1,
      ),
    );

    _screenshotIOS(
      '3_chat_habit_tracking',
      home: _MockChatScreen(
        title: 'My morning habits',
        model: 'anthropic/claude-sonnet-4',
        messages: _habitTrackingMessages(),
        showThinking: false,
        mcpServerCount: 1,
      ),
    );

    _screenshotIOS(
      '4_chat_recipe_search',
      home: _MockChatScreen(
        title: 'Quick dinner ideas',
        model: 'google/gemini-2.5-pro',
        messages: _knowledgeBaseMessages(),
        showThinking: false,
        mcpServerCount: 1,
      ),
    );

    _screenshotIOS(
      '5_chat_mermaid_diagram',
      home: _MockChatScreen(
        title: 'My morning routine',
        model: 'anthropic/claude-sonnet-4',
        messages: _mermaidMessages(),
        mcpServerCount: 1,
        scrollToTop: true,
      ),
    );

    _screenshotIOS(
      '6_chat_image_analysis',
      home: _MockChatScreen(
        title: 'Hiking trip planning',
        model: 'anthropic/claude-sonnet-4',
        messages: _imageAnalysisMessages(),
      ),
    );
  });

  group('Mac App Store Screenshots:', () {
    _screenshotMac(
      '1_conversation_list',
      home: const _MockConversationListScreen(),
    );

    _screenshotMac(
      '2_chat_nutrition_tracking',
      home: _MockChatScreen(
        title: 'Log today\'s meals',
        model: 'anthropic/claude-sonnet-4',
        messages: _nutritionToolMessages(),
        showThinking: false,
        mcpServerCount: 1,
      ),
    );

    _screenshotMac(
      '3_chat_habit_tracking',
      home: _MockChatScreen(
        title: 'My morning habits',
        model: 'anthropic/claude-sonnet-4',
        messages: _habitTrackingMessages(),
        showThinking: false,
        mcpServerCount: 1,
      ),
    );

    _screenshotMac(
      '4_chat_recipe_search',
      home: _MockChatScreen(
        title: 'Quick dinner ideas',
        model: 'google/gemini-2.5-pro',
        messages: _knowledgeBaseMessages(),
        showThinking: false,
        mcpServerCount: 1,
      ),
    );

    _screenshotMac(
      '5_chat_mermaid_diagram',
      home: _MockChatScreen(
        title: 'My morning routine',
        model: 'anthropic/claude-sonnet-4',
        messages: _mermaidMessages(),
        mcpServerCount: 1,
        scrollToTop: true,
      ),
    );

    _screenshotMac(
      '6_chat_image_analysis',
      home: _MockChatScreen(
        title: 'Hiking trip planning',
        model: 'anthropic/claude-sonnet-4',
        messages: _imageAnalysisMessages(),
      ),
    );
  });
}

void _screenshot(
  String name, {
  required Widget home,
  ScreenshotFrameColors? frameColors,
}) {
  // Generate for both Android phone and tablet (Play Store)
  final goldenDevices = [
    GoldenScreenshotDevices.androidPhone,
    GoldenScreenshotDevices.androidTablet,
  ];

  for (final goldenDevice in goldenDevices) {
    testGoldens('$name for ${goldenDevice.name}', (tester) async {
      final device = goldenDevice.device;

      await _loadTestFonts();

      await tester.pumpWidget(
        ScreenshotApp(
          device: device,
          frameColors: frameColors ?? ScreenshotFrameColors.light,
          themeMode: ThemeMode.dark,
          darkTheme: _appDarkTheme,
          debugShowCheckedModeBanner: false,
          home: home,
        ),
      );

      await tester.loadAssets();
      await tester.pump();
      await tester.pumpFrames(
        tester.widget(find.byType(ScreenshotApp)),
        const Duration(seconds: 1),
      );

      await tester.expectScreenshot(device, name);
    });
  }
}

// Custom iPhone 6.5" device for App Store (iPhone 11 Pro Max / XS Max)
const _iphone65 = ScreenshotDevice(
  platform: TargetPlatform.iOS,
  resolution: Size(1284, 2778),
  pixelRatio: 3,
  goldenSubFolder: 'iphone65Screenshots/',
  frameBuilder: ScreenshotFrame.iphone,
);

void _screenshotMac(
  String name, {
  required Widget home,
  ScreenshotFrameColors? frameColors,
}) {
  testGoldens('$name for macbook', (tester) async {
    final device = GoldenScreenshotDevices.macbook.device;

    await _loadTestFonts();

    await tester.pumpWidget(
      ScreenshotApp(
        device: device,
        frameColors: frameColors ?? ScreenshotFrameColors.light,
        themeMode: ThemeMode.dark,
        darkTheme: _appDarkTheme,
        debugShowCheckedModeBanner: false,
        home: home,
      ),
    );

    await tester.loadAssets();
    await tester.pump();
    await tester.pumpFrames(
      tester.widget(find.byType(ScreenshotApp)),
      const Duration(seconds: 1),
    );

    await tester.expectScreenshot(device, name);
  });
}

void _screenshotIOS(
  String name, {
  required Widget home,
  ScreenshotFrameColors? frameColors,
}) {
  // Generate for iPhone 6.9", iPhone 6.5", and iPad (App Store)
  final goldenDevices = <({String name, ScreenshotDevice device})>[
    (name: 'iphone', device: GoldenScreenshotDevices.iphone.device),
    (name: 'iphone65', device: _iphone65),
    (name: 'ipad', device: GoldenScreenshotDevices.ipad.device),
  ];

  for (final goldenDevice in goldenDevices) {
    testGoldens('$name for ${goldenDevice.name}', (tester) async {
      final device = goldenDevice.device;

      await _loadTestFonts();

      await tester.pumpWidget(
        ScreenshotApp(
          device: device,
          frameColors: frameColors ?? ScreenshotFrameColors.light,
          themeMode: ThemeMode.dark,
          darkTheme: _appDarkTheme,
          debugShowCheckedModeBanner: false,
          home: home,
        ),
      );

      await tester.loadAssets();
      await tester.pump();
      await tester.pumpFrames(
        tester.widget(find.byType(ScreenshotApp)),
        const Duration(seconds: 1),
      );

      await tester.expectScreenshot(device, name);
    });
  }
}
