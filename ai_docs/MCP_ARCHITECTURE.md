# MCP Integration Architecture

## Component Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                        Flutter App UI                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌──────────────┐  ┌──────────────────┐  ┌─────────────────┐   │
│  │   Settings   │  │ Conversation     │  │   Chat Screen   │   │
│  │   Screen     │  │ List Screen      │  │                 │   │
│  │              │  │                  │  │ - Shows MCP     │   │
│  │ - Manage MCP │  │ - Create new     │  │   server count  │   │
│  │   Servers    │  │   conversation   │  │ - Displays tool │   │
│  │ - Add/Edit/  │  │ - Select MCP     │  │   execution     │   │
│  │   Delete     │  │   servers        │  │ - Handles LLM   │   │
│  │              │  │                  │  │   responses     │   │
│  └──────┬───────┘  └────────┬─────────┘  └────────┬────────┘   │
│         │                   │                      │            │
└─────────┼───────────────────┼──────────────────────┼────────────┘
          │                   │                      │
          │                   │                      │
          └───────────────────┴──────────────────────┘
                              │
          ┌───────────────────▼──────────────────────┐
          │          Services Layer                   │
          ├───────────────────────────────────────────┤
          │                                           │
          │  ┌──────────────────────────────────┐    │
          │  │    DatabaseService               │    │
          │  │  - Store MCP server configs      │    │
          │  │  - Link servers to conversations │    │
          │  └──────────────┬───────────────────┘    │
          │                 │                         │
          │  ┌──────────────▼───────────────────┐    │
          │  │    McpClientService              │    │
          │  │  - Initialize connection         │    │
          │  │  - List tools                    │    │
          │  │  - Execute tool calls            │    │
          │  └──────────────┬───────────────────┘    │
          │                 │                         │
          │  ┌──────────────▼───────────────────┐    │
          │  │    OpenRouterService             │    │
          │  │  - Send messages with tools      │    │
          │  │  - Handle tool call responses    │    │
          │  └──────────────┬───────────────────┘    │
          │                 │                         │
          └─────────────────┼─────────────────────────┘
                            │
            ┌───────────────┴────────────────┐
            │                                 │
            ▼                                 ▼
  ┌─────────────────┐              ┌──────────────────┐
  │  Remote MCP     │              │   OpenRouter     │
  │  Servers        │              │   API (LLM)      │
  │                 │              │                  │
  │  - Server 1     │              │  - Claude        │
  │  - Server 2     │              │  - GPT-4         │
  │  - Server 3     │              │  - etc.          │
  └─────────────────┘              └──────────────────┘
```

## Data Flow

### 1. Conversation Creation

```
User → Create Conversation → Select LLM Model → Select MCP Servers
                                                        ↓
                                                 Save to Database
                                                        ↓
                                                  Open Chat
```

### 2. Message Flow with Tool Calls

```
User Message
    ↓
Save to Database
    ↓
Load MCP Servers for Conversation
    ↓
Initialize MCP Clients (one per server)
    ↓
Fetch Tools from all MCP Servers
    ↓
Aggregate Tools
    ↓
Send to LLM (OpenRouter) with:
  - User message
  - Conversation history
  - Available tools
    ↓
LLM Response Contains Tool Calls?
    ↓
  YES → Execute Tools
    ↓
    For each tool call:
      - Show "Calling tool" message
      - Find MCP server that has the tool
      - Execute via McpClientService
      - Collect result
    ↓
    Send tool results back to LLM
    ↓
    LLM generates final response
    ↓
  NO → Direct response
    ↓
Save Assistant Message to Database
    ↓
Display to User
```

## Database Relationships

```
┌─────────────────┐
│  conversations  │
│  - id           │──────┐
│  - title        │      │
│  - model        │      │
│  - createdAt    │      │
│  - updatedAt    │      │
└─────────────────┘      │
                         │
                         │ 1:N
                         │
         ┌───────────────▼──────────────────┐
         │  conversation_mcp_servers        │
         │  - conversationId (FK)           │
         │  - mcpServerId (FK)              │
         └──────┬───────────────────────────┘
                │
                │ N:1
                │
        ┌───────▼──────────┐
        │   mcp_servers    │
        │   - id           │
        │   - name         │
        │   - url          │
        │   - headers      │
        │   - isEnabled    │
        │   - createdAt    │
        │   - updatedAt    │
        └──────────────────┘
```

## MCP Protocol Flow

```
App                         MCP Server
 │                               │
 │  POST /mcp/v1                 │
 │  { method: "initialize" }     │
 │─────────────────────────────>│
 │                               │
 │  { result: { ... } }          │
 │<─────────────────────────────│
 │                               │
 │  POST /mcp/v1                 │
 │  { method: "tools/list" }     │
 │─────────────────────────────>│
 │                               │
 │  { result: { tools: [...] } } │
 │<─────────────────────────────│
 │                               │
 │  POST /mcp/v1                 │
 │  { method: "tools/call",      │
 │    params: { name, args } }   │
 │─────────────────────────────>│
 │                               │
 │  { result: { content: [...] }}│
 │<─────────────────────────────│
```

## Security Model

```
┌──────────────────────────────────────────────────┐
│                  User Device                      │
│                                                   │
│  ┌────────────────────────────────────────┐     │
│  │  Local Database (SQLite)               │     │
│  │  - Stores MCP server URLs              │     │
│  │  - Stores authentication headers        │     │
│  │    (encrypted by OS)                    │     │
│  └────────────────────────────────────────┘     │
│                                                   │
│  ┌────────────────────────────────────────┐     │
│  │  HTTPS Only                             │     │
│  │  - All MCP communication over HTTPS     │     │
│  │  - OpenRouter API over HTTPS            │     │
│  └────────────────────────────────────────┘     │
│                                                   │
└──────────────────────────────────────────────────┘
                      │
                      │ HTTPS
                      │
        ┌─────────────┴──────────────┐
        │                            │
        ▼                            ▼
┌────────────────┐          ┌─────────────────┐
│  MCP Servers   │          │  OpenRouter API │
│  (User-hosted) │          │  (Third-party)  │
│                │          │                 │
│  - Custom auth │          │  - OAuth tokens │
│  - API keys    │          │  - Managed by   │
│  - Headers     │          │    app          │
└────────────────┘          └─────────────────┘
```
