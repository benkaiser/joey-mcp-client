import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../models/mcp_server.dart';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._init();
  static Database? _database;
  static const String _localToolsConfiguredSentinel = '__configured__';

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
      version: 17,
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
        audioData TEXT,
        usageData TEXT,
        uiData TEXT,
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

    await db.execute('''
      CREATE TABLE conversation_local_tools (
        conversationId TEXT NOT NULL,
        localToolId TEXT NOT NULL,
        PRIMARY KEY (conversationId, localToolId),
        FOREIGN KEY (conversationId) REFERENCES conversations (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_conversation_local_tools ON conversation_local_tools(conversationId)
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
    if (oldVersion < 14) {
      // Add audioData column for MCP audio content in tool results
      await db.execute('''
        ALTER TABLE messages ADD COLUMN audioData TEXT
      ''');
    }
    if (oldVersion < 15) {
      // Add usageData column for OpenRouter token/cost information
      await db.execute('''
        ALTER TABLE messages ADD COLUMN usageData TEXT
      ''');
    }
    if (oldVersion < 16) {
      // Add uiData column for MCP App UI data attached to tool result messages
      await db.execute('''
        ALTER TABLE messages ADD COLUMN uiData TEXT
      ''');
    }
    if (oldVersion < 17) {
      await db.execute('''
        CREATE TABLE conversation_local_tools (
          conversationId TEXT NOT NULL,
          localToolId TEXT NOT NULL,
          PRIMARY KEY (conversationId, localToolId),
          FOREIGN KEY (conversationId) REFERENCES conversations (id) ON DELETE CASCADE
        )
      ''');
      await db.execute('''
        CREATE INDEX idx_conversation_local_tools ON conversation_local_tools(conversationId)
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
    // Exclude imageData, audioData, and uiData to avoid CursorWindow overflow on Android.
    // These columns can exceed the ~2MB per-row limit.
    // Use getMessageBlobData() or getFullMessagesForConversation() to load them.
    // We use a raw query to include a computed 'hasUiData' flag so the UI knows
    // which messages have uiData without loading the (potentially large) content.
    try {
      final result = await db.rawQuery(
        '''SELECT id, conversationId, role, content, timestamp,
           reasoning, toolCallData, toolCallId, toolName,
           elicitationData, notificationData, usageData,
           CASE WHEN uiData IS NOT NULL THEN 1 ELSE 0 END AS hasUiData
           FROM messages WHERE conversationId = ? ORDER BY timestamp ASC''',
        [conversationId],
      );
      return result.map((map) => Message.fromMap(map)).toList();
    } catch (e) {
      // Fallback: if the batch query still fails (e.g. very large content column),
      // load messages one at a time to avoid CursorWindow overflow.
      print(
        'Warning: Batch message query failed, falling back to per-message loading: $e',
      );
      final idResult = await db.query(
        'messages',
        columns: ['id'],
        where: 'conversationId = ?',
        whereArgs: [conversationId],
        orderBy: 'timestamp ASC',
      );

      final messages = <Message>[];
      for (final row in idResult) {
        final messageId = row['id'] as String;
        try {
          final msgResult = await db.query(
            'messages',
            where: 'id = ?',
            whereArgs: [messageId],
          );
          if (msgResult.isNotEmpty) {
            messages.add(Message.fromMap(msgResult.first));
          }
        } catch (e2) {
          print('Warning: Failed to load message $messageId: $e2');
        }
      }
      return messages;
    }
  }

  /// Read a single large text column in chunks using SUBSTR() to bypass
  /// Android's ~2MB CursorWindow per-row limit.
  /// Returns null if the column is NULL or the row doesn't exist.
  Future<String?> _readLargeColumn(
    Database db,
    String table,
    String column,
    String whereClause,
    List<Object?> whereArgs,
  ) async {
    // First get the length
    final lenResult = await db.rawQuery(
      'SELECT LENGTH($column) AS len FROM $table WHERE $whereClause',
      whereArgs,
    );
    if (lenResult.isEmpty || lenResult.first['len'] == null) return null;

    final totalLength = lenResult.first['len'] as int;
    if (totalLength == 0) return '';

    // Read in 1MB chunks (well under the ~2MB CursorWindow limit)
    const chunkSize = 1000000;
    final buffer = StringBuffer();
    for (int offset = 0; offset < totalLength; offset += chunkSize) {
      final result = await db.rawQuery(
        'SELECT SUBSTR($column, ${offset + 1}, $chunkSize) AS chunk FROM $table WHERE $whereClause',
        whereArgs,
      );
      if (result.isNotEmpty && result.first['chunk'] != null) {
        buffer.write(result.first['chunk'] as String);
      }
    }
    return buffer.toString();
  }

  /// Fetch just the blob columns (imageData, audioData, uiData) for a single message.
  /// Each column is fetched in a separate query to avoid CursorWindow overflow
  /// when multiple large blobs exist on the same message.
  /// Falls back to chunked reading if a single column exceeds the CursorWindow limit.
  /// Returns a map with 'imageData', 'audioData', and 'uiData' keys (nullable).
  Future<Map<String, String?>> getMessageBlobData(String messageId) async {
    final db = await database;
    final blobs = <String, String?>{
      'imageData': null,
      'audioData': null,
      'uiData': null,
    };
    for (final column in ['imageData', 'audioData', 'uiData']) {
      try {
        final result = await db.query(
          'messages',
          columns: [column],
          where: 'id = ?',
          whereArgs: [messageId],
        );
        if (result.isNotEmpty) {
          blobs[column] = result.first[column] as String?;
        }
      } catch (e) {
        // Single column exceeds CursorWindow — read in chunks
        try {
          blobs[column] = await _readLargeColumn(
            db,
            'messages',
            column,
            'id = ?',
            [messageId],
          );
        } catch (e2) {
          print('Warning: Failed to load $column for message $messageId: $e2');
        }
      }
    }
    return blobs;
  }

  /// Fetch just the uiData column for a single message.
  /// Uses its own query to avoid CursorWindow overflow from other large blobs.
  /// Falls back to chunked reading if the value exceeds the CursorWindow limit.
  Future<String?> getMessageUiData(String messageId) async {
    final db = await database;
    try {
      final result = await db.query(
        'messages',
        columns: ['uiData'],
        where: 'id = ?',
        whereArgs: [messageId],
      );
      if (result.isNotEmpty) {
        return result.first['uiData'] as String?;
      }
    } catch (e) {
      // Single column exceeds CursorWindow — read in chunks
      try {
        return await _readLargeColumn(db, 'messages', 'uiData', 'id = ?', [
          messageId,
        ]);
      } catch (e2) {
        print('Warning: Failed to load uiData for message $messageId: $e2');
      }
    }
    return null;
  }

  /// Fetch all messages for a conversation with ALL columns including blobs.
  /// Fetches lightweight columns first, then loads each blob column individually
  /// per message to avoid CursorWindow overflow on Android.
  /// Used for export and API calls that need image/audio data.
  Future<List<Message>> getFullMessagesForConversation(
    String conversationId,
  ) async {
    final db = await database;
    // First get the message IDs in order
    final idResult = await db.query(
      'messages',
      columns: ['id'],
      where: 'conversationId = ?',
      whereArgs: [conversationId],
      orderBy: 'timestamp ASC',
    );

    final messages = <Message>[];
    for (final row in idResult) {
      final messageId = row['id'] as String;
      try {
        // Load lightweight columns (no blobs)
        final lightResult = await db.query(
          'messages',
          columns: [
            'id',
            'conversationId',
            'role',
            'content',
            'timestamp',
            'reasoning',
            'toolCallData',
            'toolCallId',
            'toolName',
            'elicitationData',
            'notificationData',
            'usageData',
          ],
          where: 'id = ?',
          whereArgs: [messageId],
        );
        if (lightResult.isEmpty) continue;

        // Load each blob column individually to avoid CursorWindow overflow.
        // Falls back to chunked SUBSTR reading if a single column is still too large.
        final blobValues = <String, String?>{
          'imageData': null,
          'audioData': null,
          'uiData': null,
        };
        for (final column in blobValues.keys) {
          try {
            final blobResult = await db.query(
              'messages',
              columns: [column],
              where: 'id = ?',
              whereArgs: [messageId],
            );
            if (blobResult.isNotEmpty) {
              blobValues[column] = blobResult.first[column] as String?;
            }
          } catch (e) {
            // Single column exceeds CursorWindow — read in chunks
            try {
              blobValues[column] = await _readLargeColumn(
                db,
                'messages',
                column,
                'id = ?',
                [messageId],
              );
            } catch (e2) {
              print(
                'Warning: Failed to load $column for message $messageId: $e2',
              );
            }
          }
        }

        // Merge blob data into the lightweight map
        final map = Map<String, dynamic>.from(lightResult.first);
        map['imageData'] = blobValues['imageData'];
        map['audioData'] = blobValues['audioData'];
        map['uiData'] = blobValues['uiData'];
        messages.add(Message.fromMap(map));
      } catch (e) {
        print('Warning: Failed to load message $messageId: $e');
      }
    }
    return messages;
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

  Future<void> setConversationLocalTools(
    String conversationId,
    List<String> localToolIds,
  ) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete(
        'conversation_local_tools',
        where: 'conversationId = ?',
        whereArgs: [conversationId],
      );

      await txn.insert('conversation_local_tools', {
        'conversationId': conversationId,
        'localToolId': _localToolsConfiguredSentinel,
      });

      for (final localToolId in localToolIds) {
        await txn.insert('conversation_local_tools', {
          'conversationId': conversationId,
          'localToolId': localToolId,
        });
      }
    });
  }

  Future<List<String>> getConversationLocalTools(String conversationId) async {
    final db = await database;
    final result = await db.query(
      'conversation_local_tools',
      columns: ['localToolId'],
      where: 'conversationId = ? AND localToolId != ?',
      whereArgs: [conversationId, _localToolsConfiguredSentinel],
      orderBy: 'localToolId ASC',
    );
    return result.map((row) => row['localToolId'] as String).toList();
  }

  Future<bool> hasConversationLocalToolSettings(String conversationId) async {
    final db = await database;
    final result = await db.query(
      'conversation_local_tools',
      columns: ['localToolId'],
      where: 'conversationId = ? AND localToolId = ?',
      whereArgs: [conversationId, _localToolsConfiguredSentinel],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  /// Search conversations by title and message content.
  /// Returns conversations that match the query, ordered by relevance (updatedAt DESC).
  Future<List<Conversation>> searchConversations(String query) async {
    final db = await database;
    final likeQuery = '%$query%';

    // Search conversations whose title matches OR that contain messages matching the query.
    // Only search user and assistant messages (skip tool results, notifications, etc.)
    final result = await db.rawQuery(
      '''
      SELECT DISTINCT c.* FROM conversations c
      LEFT JOIN messages m ON c.id = m.conversationId
      WHERE c.title LIKE ? COLLATE NOCASE
         OR (m.content LIKE ? COLLATE NOCASE AND m.role IN ('user', 'assistant'))
      ORDER BY c.updatedAt DESC
    ''',
      [likeQuery, likeQuery],
    );
    return result.map((map) => Conversation.fromMap(map)).toList();
  }
}
