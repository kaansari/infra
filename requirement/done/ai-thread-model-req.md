Yes. I’d model it as a small `AIThreadService` that owns persistent chat/thread history. The agent service would call this service instead of keeping `histories map[string][]message` in memory.

Key idea: **thread identity must always include authenticated `user_id` + profile + client/session thread id**.

**Proto Proposal**

```proto
syntax = "proto3";

package ai;

option go_package = "github.com/kaansari/ceerat-contracts/proto/ai";

service AIThreadService {
  rpc GetOrCreateThread(GetOrCreateThreadRequest) returns (Thread);
  rpc GetThread(GetThreadRequest) returns (Thread);
  rpc ListThreads(ListThreadsRequest) returns (ListThreadsResponse);
  rpc AppendMessage(AppendMessageRequest) returns (ThreadMessage);
  rpc ReplaceThreadMessages(ReplaceThreadMessagesRequest) returns (Thread);
  rpc DeleteThread(DeleteThreadRequest) returns (DeleteThreadResponse);
}

enum ThreadProfile {
  THREAD_PROFILE_UNSPECIFIED = 0;
  THREAD_PROFILE_AGENT = 1;
  THREAD_PROFILE_CUSTOMER = 2;
}

enum ThreadMessageRole {
  THREAD_MESSAGE_ROLE_UNSPECIFIED = 0;
  THREAD_MESSAGE_ROLE_USER = 1;
  THREAD_MESSAGE_ROLE_ASSISTANT = 2;
}

message Thread {
  string id = 1;
  string user_id = 2;
  ThreadProfile profile = 3;

  // Caller-facing conversation id, like the current session_id.
  string external_thread_id = 4;

  string title = 5;
  int32 message_count = 6;

  string created_at = 7;
  string updated_at = 8;

  repeated ThreadMessage messages = 9;
}

message ThreadMessage {
  string id = 1;
  string thread_id = 2;
  string user_id = 3;
  ThreadProfile profile = 4;
  ThreadMessageRole role = 5;
  string content = 6;

  // Optional JSON for future fields: model, tool actions, token usage, etc.
  string metadata_json = 7;

  string created_at = 8;
}

message GetOrCreateThreadRequest {
  ThreadProfile profile = 1;
  string external_thread_id = 2;
  string title = 3;
}

message GetThreadRequest {
  ThreadProfile profile = 1;
  string external_thread_id = 2;

  // Defaults to recent messages only.
  int32 message_limit = 3;
}

message ListThreadsRequest {
  ThreadProfile profile = 1;
  int32 page_size = 2;
  string page_token = 3;
}

message ListThreadsResponse {
  repeated Thread threads = 1;
  string next_page_token = 2;
}

message AppendMessageRequest {
  ThreadProfile profile = 1;
  string external_thread_id = 2;
  ThreadMessageRole role = 3;
  string content = 4;
  string metadata_json = 5;
}

message ReplaceThreadMessagesRequest {
  ThreadProfile profile = 1;
  string external_thread_id = 2;
  repeated NewThreadMessage messages = 3;
}

message NewThreadMessage {
  ThreadMessageRole role = 1;
  string content = 2;
  string metadata_json = 3;
}

message DeleteThreadRequest {
  string user_id = 1;
  ThreadProfile profile = 2;
  string external_thread_id = 3;
}

message DeleteThreadResponse {
  bool deleted = 1;
}
```

**Database Model**

```sql
CREATE TABLE ai_threads (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    profile TEXT NOT NULL CHECK (profile IN ('agent', 'customer')),
    external_thread_id TEXT NOT NULL,
    title TEXT NOT NULL DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    UNIQUE (user_id, profile, external_thread_id)
);

CREATE INDEX idx_ai_threads_user_profile_updated
    ON ai_threads (user_id, profile, updated_at DESC);
```

```sql
CREATE TABLE ai_thread_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    thread_id UUID NOT NULL REFERENCES ai_threads(id) ON DELETE CASCADE,
    user_id UUID NOT NULL,
    profile TEXT NOT NULL CHECK (profile IN ('agent', 'customer')),
    role TEXT NOT NULL CHECK (role IN ('user', 'assistant')),
    content TEXT NOT NULL,
    metadata_json JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_ai_thread_messages_thread_created
    ON ai_thread_messages (thread_id, created_at ASC);

CREATE INDEX idx_ai_thread_messages_user_profile_created
    ON ai_thread_messages (user_id, profile, created_at DESC);
```

**Important Security Rule**

Even if the request includes `user_id`, the backup service should prefer the authenticated user from JWT metadata. So internally:

```text
effective_user_id = auth_context.user_id
```

The request `user_id` can be used only for validation or admin use cases, not trusted directly from the client.

**How Agent Service Would Use It**

For each chat request:

1. Resolve profile:
   - `/agent/chat` -> `THREAD_PROFILE_AGENT`
   - `/customer/chat` -> `THREAD_PROFILE_CUSTOMER`

2. Resolve thread:
   ```text
   user_id + profile + session_id
   ```

3. Load recent messages:
   ```text
   GetThread(message_limit: 20)
   ```

4. Send those messages to OpenAI.

5. After final assistant reply, persist only sanitized messages:
   - user message
   - final assistant message
   - no tool protocol messages
   - no raw tool results unless you explicitly want audit storage later

This gives you a local replacement for OpenAI Threads while keeping ownership and retention inside Ceerat.
