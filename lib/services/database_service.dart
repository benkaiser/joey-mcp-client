import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../models/mcp_server.dart';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._init();
  static Database? _database;

  DatabaseService._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('joey_mcp.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 13,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE conversations (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        model TEXT NOT NULL,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE messages (
        id TEXT PRIMARY KEY,
        conversationId TEXT NOT NULL,
        role TEXT NOT NULL,
        content TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        reasoning TEXT,
        toolCallData TEXT,
        toolCallId TEXT,
        toolName TEXT,
        elicitationData TEXT,
        notificationData TEXT,
        imageData TEXT,
        FOREIGN KEY (conversationId) REFERENCES conversations (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_messages_conversation ON messages(conversationId)
    ''');

    await db.execute('''
      CREATE TABLE mcp_servers (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        url TEXT NOT NULL,
        headers TEXT,
        isEnabled INTEGER NOT NULL DEFAULT 1,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        oauthStatus TEXT DEFAULT 'none',
        oauthTokens TEXT,
        oauthClientId TEXT,
        oauthClientSecret TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE conversation_mcp_servers (
        conversationId TEXT NOT NULL,
        mcpServerId TEXT NOT NULL,
        sessionId TEXT,
        PRIMARY KEY (conversationId, mcpServerId),
        FOREIGN KEY (conversationId) REFERENCES conversations (id) ON DELETE CASCADE,
        FOREIGN KEY (mcpServerId) REFERENCES mcp_servers (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_conversation_servers ON conversation_mcp_servers(conversationId)
    ''');
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Add model column to existing conversations table
      await db.execute('''
        ALTER TABLE conversations ADD COLUMN model TEXT NOT NULL DEFAULT 'openai/gpt-3.5-turbo'
      ''');
    }
    if (oldVersion < 3) {
      // Add MCP server tables
      await db.execute('''
        CREATE TABLE mcp_servers (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          url TEXT NOT NULL,
          headers TEXT,
          isEnabled INTEGER NOT NULL DEFAULT 1,
          createdAt TEXT NOT NULL,
          updatedAt TEXT NOT NULL
        )
      ''');

      await db.execute('''
        CREATE TABLE conversation_mcp_servers (
          conversationId TEXT NOT NULL,
          mcpServerId TEXT NOT NULL,
          PRIMARY KEY (conversationId, mcpServerId),
          FOREIGN KEY (conversationId) REFERENCES conversations (id) ON DELETE CASCADE,
          FOREIGN KEY (mcpServerId) REFERENCES mcp_servers (id) ON DELETE CASCADE
        )
      ''');

      await db.execute('''
        CREATE INDEX idx_conversation_servers ON conversation_mcp_servers(conversationId)
      ''');
    }
    if (oldVersion < 4) {
      // Add isDisplayOnly column to messages table
      await db.execute('''
        ALTER TABLE messages ADD COLUMN isDisplayOnly INTEGER NOT NULL DEFAULT 0
      ''');
    }
    if (oldVersion < 5) {
      // Add tool-related columns to messages table
      await db.execute('''
        ALTER TABLE messages ADD COLUMN toolCallData TEXT
      ''');
      await db.execute('''
        ALTER TABLE messages ADD COLUMN toolCallId TEXT
      ''');
      await db.execute('''
        ALTER TABLE messages ADD COLUMN toolName TEXT
      ''');
    }
    if (oldVersion < 6) {
      // Remove isDisplayOnly column - we'll handle this in the UI
      // SQLite doesn't support DROP COLUMN, so we need to recreate the table
      await db.execute('''
        CREATE TABLE messages_new (
          id TEXT PRIMARY KEY,
          conversationId TEXT NOT NULL,
          role TEXT NOT NULL,
          content TEXT NOT NULL,
          timestamp TEXT NOT NULL,
          toolCallData TEXT,
          toolCallId TEXT,
          toolName TEXT,
          FOREIGN KEY (conversationId) REFERENCES conversations (id) ON DELETE CASCADE
        )
      ''');

      await db.execute('''
        INSERT INTO messages_new (id, conversationId, role, content, timestamp, toolCallData, toolCallId, toolName)
        SELECT id, conversationId, role, content, timestamp, toolCallData, toolCallId, toolName
        FROM messages
      ''');

      await db.execute('DROP TABLE messages');
      await db.execute('ALTER TABLE messages_new RENAME TO messages');

      await db.execute('''
        CREATE INDEX idx_messages_conversation ON messages(conversationId)
      ''');
    }
    if (oldVersion < 7) {
      // Add reasoning column to messages table
      await db.execute('''
        ALTER TABLE messages ADD COLUMN reasoning TEXT
      ''');
    }
    if (oldVersion < 8) {
      // Add elicitationData column to messages table for inline elicitation cards
      await db.execute('''
        ALTER TABLE messages ADD COLUMN elicitationData TEXT
      ''');
    }
    if (oldVersion < 9) {
      // Add notificationData column to messages table for MCP server notifications
      await db.execute('''
        ALTER TABLE messages ADD COLUMN notificationData TEXT
      ''');
    }
    if (oldVersion < 10) {
      // Add OAuth columns to mcp_servers table
      await db.execute('''
        ALTER TABLE mcp_servers ADD COLUMN oauthStatus TEXT DEFAULT 'none'
      ''');
      await db.execute('''
        ALTER TABLE mcp_servers ADD COLUMN oauthTokens TEXT
      ''');
      await db.execute('''
        ALTER TABLE mcp_servers ADD COLUMN oauthClientId TEXT
      ''');
    }
    if (oldVersion < 11) {
      // Add OAuth client secret column
      await db.execute('''
        ALTER TABLE mcp_servers ADD COLUMN oauthClientSecret TEXT
      ''');
    }
    if (oldVersion < 12) {
      // Add sessionId column for MCP session resumption
      await db.execute('''
        ALTER TABLE conversation_mcp_servers ADD COLUMN sessionId TEXT
      ''');
    }
    if (oldVersion < 13) {
      // Add imageData column for MCP image content in tool results
      await db.execute('''
        ALTER TABLE messages ADD COLUMN imageData TEXT
      ''');
    }
  }

  // Conversation operations
  Future<void> insertConversation(Conversation conversation) async {
    final db = await database;
    await db.insert(
      'conversations',
      conversation.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Conversation>> getAllConversations() async {
    final db = await database;
    final result = await db.query('conversations', orderBy: 'updatedAt DESC');
    return result.map((map) => Conversation.fromMap(map)).toList();
  }

  Future<void> updateConversation(Conversation conversation) async {
    final db = await database;
    await db.update(
      'conversations',
      conversation.toMap(),
      where: 'id = ?',
      whereArgs: [conversation.id],
    );
  }

  Future<void> deleteConversation(String id) async {
    final db = await database;
    await db.delete('conversations', where: 'id = ?', whereArgs: [id]);
    // Messages will be deleted automatically due to CASCADE
  }

  // Message operations
  Future<void> insertMessage(Message message) async {
    final db = await database;
    await db.insert(
      'messages',
      message.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateMessage(Message message) async {
    final db = await database;
    await db.update(
      'messages',
      message.toMap(),
      where: 'id = ?',
      whereArgs: [message.id],
    );
  }

  Future<void> deleteMessage(String messageId) async {
    final db = await database;
    await db.delete('messages', where: 'id = ?', whereArgs: [messageId]);
  }

  Future<List<Message>> getMessagesForConversation(
    String conversationId,
  ) async {
    final db = await database;
    final result = await db.query(
      'messages',
      where: 'conversationId = ?',
      whereArgs: [conversationId],
      orderBy: 'timestamp ASC',
    );
    return result.map((map) => Message.fromMap(map)).toList();
  }

  Future<void> deleteMessagesForConversation(String conversationId) async {
    final db = await database;
    await db.delete(
      'messages',
      where: 'conversationId = ?',
      whereArgs: [conversationId],
    );
  }

  Future<void> close() async {
    final db = await database;
    await db.close();
  }

  // MCP Server operations
  Future<void> insertMcpServer(McpServer server) async {
    final db = await database;
    await db.insert(
      'mcp_servers',
      server.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<McpServer>> getAllMcpServers() async {
    final db = await database;
    final result = await db.query('mcp_servers', orderBy: 'name ASC');
    return result.map((map) => McpServer.fromMap(map)).toList();
  }

  Future<void> updateMcpServer(McpServer server) async {
    final db = await database;
    await db.update(
      'mcp_servers',
      server.toMap(),
      where: 'id = ?',
      whereArgs: [server.id],
    );
  }

  Future<void> deleteMcpServer(String id) async {
    final db = await database;
    await db.delete('mcp_servers', where: 'id = ?', whereArgs: [id]);
  }

  // Conversation-MCP Server relationship operations
  Future<void> setConversationMcpServers(
    String conversationId,
    List<String> serverIds,
  ) async {
    final db = await database;
    await db.transaction((txn) async {
      // Delete existing associations
      await txn.delete(
        'conversation_mcp_servers',
        where: 'conversationId = ?',
        whereArgs: [conversationId],
      );

      // Insert new associations
      for (final serverId in serverIds) {
        await txn.insert('conversation_mcp_servers', {
          'conversationId': conversationId,
          'mcpServerId': serverId,
        });
      }
    });
  }

  Future<List<McpServer>> getConversationMcpServers(
    String conversationId,
  ) async {
    final db = await database;
    final result = await db.rawQuery(
      '''
      SELECT s.* FROM mcp_servers s
      INNER JOIN conversation_mcp_servers cs ON s.id = cs.mcpServerId
      WHERE cs.conversationId = ?
      ORDER BY s.name ASC
    ''',
      [conversationId],
    );
    return result.map((map) => McpServer.fromMap(map)).toList();
  }

  /// Get the stored MCP session ID for a specific conversation-server pair
  Future<String?> getMcpSessionId(
    String conversationId,
    String mcpServerId,
  ) async {
    final db = await database;
    final result = await db.query(
      'conversation_mcp_servers',
      columns: ['sessionId'],
      where: 'conversationId = ? AND mcpServerId = ?',
      whereArgs: [conversationId, mcpServerId],
    );
    if (result.isNotEmpty) {
      return result.first['sessionId'] as String?;
    }
    return null;
  }

  /// Update the MCP session ID for a specific conversation-server pair
  Future<void> updateMcpSessionId(
    String conversationId,
    String mcpServerId,
    String? sessionId,
  ) async {
    final db = await database;
    await db.update(
      'conversation_mcp_servers',
      {'sessionId': sessionId},
      where: 'conversationId = ? AND mcpServerId = ?',
      whereArgs: [conversationId, mcpServerId],
    );
  }

  /// Get all stored MCP session IDs for a conversation
  Future<Map<String, String?>> getAllMcpSessionIds(
    String conversationId,
  ) async {
    final db = await database;
    final result = await db.query(
      'conversation_mcp_servers',
      columns: ['mcpServerId', 'sessionId'],
      where: 'conversationId = ?',
      whereArgs: [conversationId],
    );
    return {
      for (final row in result)
        row['mcpServerId'] as String: row['sessionId'] as String?,
    };
  }
}
