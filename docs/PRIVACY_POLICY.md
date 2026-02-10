# Privacy Policy

## Overview

Joey MCP Client (operated by Kaiserapps) is designed with a privacy-first approach. Your conversation data stays on your device and is only transmitted to the services you explicitly configure. This document describes how your data is handled.

**Last Updated:** February 10, 2026

## Data Storage

All conversation data — including messages, attachments, and conversation metadata — is stored **locally on your device** using SQLite. Joey MCP Client does not operate any backend servers that store your conversations. If you delete the app or clear its data, your conversations are permanently removed.

### What is stored locally

- Conversation history (messages, tool calls, responses)
- MCP server configurations
- OpenRouter authentication credentials
- User preferences and settings

## Data Transmission

Joey MCP Client only transmits your data in two scenarios, both of which are initiated by your direct use of the app:

### 1. OpenRouter (LLM Processing)

When you send a message in a conversation, the relevant conversation context is transmitted to [OpenRouter](https://openrouter.ai) for LLM (Large Language Model) processing. This is required to generate AI responses. [OpenRouter's privacy policy](https://openrouter.ai/privacy) governs how they handle data sent to their API.

- **What is sent:** Conversation messages and context necessary for generating a response
- **Why:** To process your messages through the AI model you have selected
- **When:** Only when you actively send a message in a conversation

### 2. MCP Servers (Tool Execution)

When the AI model invokes a tool provided by an MCP server you have connected, the relevant tool command is sent to that MCP server for execution. The responses from MCP servers are stored locally on your device and may be included in subsequent messages to OpenRouter as part of the conversation context.

- **What is sent:** Tool invocation commands as determined by the AI model and approved by you
- **Why:** To execute tool calls on MCP servers you have configured
- **When:** Only when a tool call is triggered during a conversation with a connected MCP server

## Third-Party Data Sharing

Joey MCP Client (operated by Kaiserapps) **does not transmit your conversation data to any third parties** outside of the two uses described above:

1. **OpenRouter** — for LLM processing
2. **User-configured MCP servers** — for tool execution

No conversation data is sold, shared with advertisers, or sent to analytics services. No data is collected by Kaiserapps beyond what is described in this policy.

## MCP Server Privacy

MCP servers are configured entirely by you, the user. Joey MCP Client connects only to MCP servers that you explicitly add. Each MCP server is operated by its own provider and is subject to its own privacy practices. Kaiserapps is not responsible for the data handling practices of third-party MCP servers you choose to connect.

## Data Security

- OpenRouter authentication uses OAuth 2.0 with PKCE for secure credential exchange
- MCP server connections support OAuth 2.1 with PKCE where supported by the server
- All network communication uses HTTPS
- Authentication tokens are stored locally on device

## Your Control

You have full control over your data at all times:

- **Delete conversations** — Remove any conversation and its messages from local storage
- **Disconnect MCP servers** — Remove any MCP server configuration to stop all communication with it
- **Log out of OpenRouter** — Clear your OpenRouter credentials to stop all LLM communication
- **Uninstall the app** — Removes all locally stored data permanently

## Changes to This Policy

Any changes to this privacy policy will be reflected in updated versions of the app. We encourage you to review this policy periodically.

## Contact

If you have questions about this privacy policy, please contact Kaiserapps through the app's official channels.
