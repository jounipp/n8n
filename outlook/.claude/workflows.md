# n8n Workflows Documentation

## Overview

This document provides a comprehensive catalog of all n8n workflows in the Outlook email automation system. Each workflow is documented with its purpose, trigger mechanism, key nodes, dependencies, and execution patterns.

## Workflow Execution Order

The system follows this typical execution sequence:

```
1. Outlook Emails Fetch (Every 5-10 min)
   ↓
2. Outlook Body Fetch (On-demand when needed)
   ↓
3. Outlook Validate Select (Every 4 min)
   ↓
4. Outlook Validate Analyse (Called by Select)
   ↓
5. Outlook Sync DB (Every 15 min)
   ↓
6. Outlook Sync OL (Every 5 min - monitors user changes)
```

---

## Core Workflows

### 1. Outlook Emails Fetch

**File:** `Outlook Emails Fetch.json`

**Purpose:** Fetches email metadata from Microsoft Outlook using Delta API for incremental sync

**Trigger:**
- Type: Schedule Trigger
- Interval: Every 5-10 minutes (configurable)
- `Schedule Every 5 min` node

**Configuration (set_config node):**
```javascript
{
  USER_UPN: "jouni.pappila@repoxcapital.fi",
  GRAPH_TOP: 10000,                    // Items per page
  PAGES_PER_RUN: 7,                    // Max pages per execution
  MAX_ITEMS_PER_RUN: 70,               // Max emails per execution
  GRAPH_SELECT: "id,parentFolderId,receivedDateTime,subject,from,...",
  GRAPH_EXPAND: "attachments($select=id,name,contentType,size,isInline)"
}
```

**Key Nodes:**

1. **load_targets_saapuneet**
   - Type: PostgreSQL
   - Purpose: Load last sync checkpoint from `delta_state` table
   - Selects: `user_upn`, `resource_path`, `resume_link`, `folder_id`

2. **prepare_delta_url**
   - Type: Code (JavaScript)
   - Purpose: Constructs Microsoft Graph API URL with delta token or starts fresh
   - Output: `url`, `is_resume`, `user_upn`, `resource_path`

3. **reset_run_counters**
   - Type: Code (JavaScript)
   - Purpose: Initialize page and item counters at start of run
   - Sets: `pages_in_run=0`, `items_processed_in_run=0`

4. **fetch_emails_http**
   - Type: HTTP Request
   - Purpose: Call Microsoft Graph Delta API
   - Endpoint: `GET /users/{upn}/mailFolders/{id}/messages/delta`
   - Auth: OAuth2 (Microsoft Graph)
   - Retry: 3 attempts with exponential backoff

5. **process_emails**
   - Type: Code (JavaScript)
   - Purpose: Normalize Graph API response, extract metadata
   - Carries: `nextLink`, `deltaLink`, pagination state
   - Injects: `user_upn` to each message

6. **parse_headers**
   - Type: Code (JavaScript)
   - Purpose: Extract email headers (Message-ID, References, List-Unsubscribe, etc.)
   - Creates: `email_headers` object for each message

7. **parse_attachments**
   - Type: Code (JavaScript)
   - Purpose: Process attachment metadata, flag large files for review
   - Creates: `attachments_metadata` and `attachment_review_items`
   - Threshold: 25 MB for automatic review queue

8. **has_emails**
   - Type: IF node
   - Condition: `items_processed > 0`
   - Routes non-empty responses to processing pipeline

9. **map_ingest_min**
   - Type: Code (JavaScript)
   - Purpose: Transform Graph API format to database schema
   - Extracts: `from_address`, `from_domain`, `to_recipients`, `subject`, etc.
   - Generates: `dedupe_key` (SHA256 of internet_message_id + received_datetime)

10. **extract_meta_changes**
    - Type: Code (JavaScript)
    - Purpose: Separate full emails from tombstone/meta-change events
    - Identifies: `@removed` markers for deleted messages
    - Splits: `emails[]` and `meta_events[]`

11. **has_meta_events**
    - Type: IF node
    - Condition: `meta_events` array not empty
    - Routes deletion/change events to separate processing

12. **split_meta_event**
    - Type: Code (JavaScript)
    - Purpose: Convert meta events array to individual items
    - Cross-references: Graph API `value[]` with stored events

13. **apply_meta_change**
    - Type: IF node
    - Condition: `event_type === 'deleted'`
    - Routes true deletions to mark_deleted node

14. **check_row_exists**
    - Type: PostgreSQL
    - Purpose: Verify email exists in database before soft delete
    - Query: `SELECT EXISTS WHERE message_id = $1`

15. **mark_deleted**
    - Type: PostgreSQL
    - Purpose: Soft delete email by setting `is_deleted=TRUE`, `deleted_at=NOW()`

16. **filter_full_emails**
    - Type: Code (JavaScript)
    - Purpose: Remove tombstones and incomplete records
    - Validates: `received_datetime` exists and not `@removed`

17. **upsert_emails**
    - Type: PostgreSQL
    - Purpose: Insert or update emails_ingest table
    - Conflict: ON CONSTRAINT `emails_ingest_dedupe_key_key`
    - Updates: Mutable fields (is_read, flag_status, categories, folder)
    - Preserves: Immutable fields (message_id, received_datetime, subject)

18. **upsert_email_headers**
    - Type: PostgreSQL
    - Purpose: Store full email headers in separate table
    - Conflict: ON CONFLICT (message_id) DO NOTHING
    - Stores: Full `headers` JSONB + extracted key headers

19. **upsert_attachments_metadata**
    - Type: PostgreSQL
    - Purpose: Store attachment metadata
    - Conflict: ON CONFLICT (message_id, attachment_id) DO NOTHING

20. **insert_attachment_review_queue**
    - Type: PostgreSQL
    - Purpose: Queue large/suspicious attachments for review
    - Criteria: `size_bytes > 25MB` OR `attachment_type='archive'`

21. **calc_run_limit**
    - Type: Code (JavaScript)
    - Purpose: Increment counters after each page
    - Increments: `items_processed_in_run`, `pages_in_run`

22. **should_continue**
    - Type: IF node
    - Conditions:
      - `items_processed_in_run < MAX_ITEMS_PER_RUN`
      - `pages_in_run < PAGES_PER_RUN`
      - `nextLink` exists
    - Decision: Continue pagination or finalize

23. **compact_for_next_page**
    - Type: Code (JavaScript)
    - Purpose: Prepare state for next page fetch
    - Preserves: `nextLink`, `user_upn`, `resource_path`, counters

24. **state_for_paging**
    - Type: Code (JavaScript)
    - Purpose: Pass pagination state to fetch_next_page
    - Reads: Previous node outputs for counter continuity

25. **fetch_next_page**
    - Type: HTTP Request
    - Purpose: Follow `@odata.nextLink` for pagination
    - Auth: OAuth2 (Microsoft Graph)
    - Loops back: To `process_emails` node

26. **has_next_link**
    - Type: IF node
    - Condition: `nextLink` or `next_link` exists
    - Routes: To save_progres (pagination continues) or can_save_delta (end of sync)

27. **save_progres**
    - Type: PostgreSQL
    - Purpose: Update progress during pagination
    - Updates: `next_link`, `items_processed` in `delta_state`

28. **can_save_delta**
    - Type: IF node
    - Conditions:
      - `deltaLink` exists AND
      - `nextLink` does NOT exist
    - Decision: Final checkpoint or just progress update

29. **save_delta_link**
    - Type: PostgreSQL
    - Purpose: Save final delta checkpoint for next sync
    - Updates: `delta_link`, `last_sync_success=NOW()`, `sync_status='completed'`

30. **save_progress_only**
    - Type: PostgreSQL
    - Purpose: Update progress without finalizing (mid-pagination)

**Data Flow:**
1. Load last sync checkpoint from `delta_state`
2. Construct Graph API URL with delta token
3. Fetch emails (paginated, max 10000 per page)
4. Parse headers and attachments
5. Separate full emails from meta-events
6. Upsert emails to database (dedupe by dedupe_key)
7. Process deletions (soft delete with tombstone)
8. Continue pagination if under limits
9. Save final delta token when complete

**Performance:**
- Incremental sync: Only fetches changed messages
- Pagination: Processes up to 7 pages per run (configurable)
- Item limit: Max 70 emails per run to prevent timeouts
- Delta API: Maintains server-side change tracking

**Error Handling:**
- Retry: 3 attempts on API failures
- Continue on error: `onError: "continueErrorOutput"` for pagination
- Tombstone handling: Separate pipeline for deleted messages
- Deduplication: Uses `dedupe_key` to prevent duplicates

---

### 2. Outlook Body Fetch

**File:** `Outlook Body Fetch.json`

**Purpose:** Fetches full HTML body content for emails that need analysis

**Trigger:**
- Type: Called by other workflows (Execute Workflow node)
- Typically called by: `Outlook Validate Select` when `needs_body=TRUE`

**Input Parameters:**
- `message_ids`: Array of message IDs needing body content
- `user_upn`: User principal name

**Key Nodes:**

1. **select_messages_needing_body**
   - Type: PostgreSQL
   - Purpose: Load emails marked with `needs_body=TRUE`
   - Filters: `needs_body=TRUE AND body_fetched_at IS NULL`

2. **build_batch_request**
   - Type: Code (JavaScript)
   - Purpose: Construct Graph API `$batch` request payload
   - Format:
     ```json
     {
       "requests": [
         {
           "id": "0",
           "method": "GET",
           "url": "/users/{upn}/messages/{id}?$select=body"
         }
       ]
     }
     ```

3. **fetch_bodies_batch**
   - Type: HTTP Request
   - Endpoint: `POST https://graph.microsoft.com/v1.0/$batch`
   - Auth: OAuth2 (Microsoft Graph)
   - Batch size: Up to 20 requests per batch

4. **parse_batch_response**
   - Type: Code (JavaScript)
   - Purpose: Extract body content from batch responses
   - Handles: Failed requests, 404s, rate limits

5. **upsert_email_bodies**
   - Type: PostgreSQL
   - Purpose: Insert body content into `email_bodies` table
   - Conflict: ON CONFLICT (message_id) DO UPDATE
   - Stores: `content` (HTML), `content_type`, `size_bytes`

6. **update_body_fetched_status**
   - Type: PostgreSQL
   - Purpose: Mark emails as body_fetched
   - Updates: `emails_ingest.needs_body=FALSE`, `body_fetched_at=NOW()`

**Data Flow:**
1. Select emails needing body content
2. Build batch request (up to 20 messages)
3. Call Graph API `$batch` endpoint
4. Parse responses and extract body HTML
5. Upsert to `email_bodies` table
6. Update fetch status in `emails_ingest`

**Performance:**
- Batch processing: Up to 20 bodies per API call
- Selective fetching: Only when `needs_body=TRUE`
- Separate storage: Keeps `emails_ingest` table lean

---

### 3. Outlook Validate Select

**File:** `Outlook Validate Select.json`

**Purpose:** Orchestrates email analysis pipeline - selects unprocessed emails, fetches bodies if needed, and batches for AI analysis

**Trigger:**
- Type: Schedule Trigger
- Interval: Every 4 minutes
- `Schedule Trigger 7 min` node

**Configuration (set_config node):**
```javascript
{
  batch: 2,                      // Number of batches to split
  offset: 0,                     // SQL OFFSET for pagination
  limit: 4,                      // Items per batch
  MAX_BODY_CHARS: 100000,        // Body truncation limit
  user_upn: "jouni.pappila@repoxcapital.fi"
}
```

**Key Nodes:**

1. **candidate_select**
   - Type: PostgreSQL
   - Purpose: Select emails pending analysis
   - Query:
     ```sql
     SELECT e.*, eb.content AS body_content
     FROM emails_ingest e
     LEFT JOIN email_bodies eb ON eb.message_id = e.message_id
     WHERE e.analyzed_at IS NULL
       AND e.is_deleted = FALSE
       AND e.auto_processed = FALSE
     ORDER BY e.received_datetime DESC
     LIMIT $1 OFFSET $2
     FOR UPDATE SKIP LOCKED
     ```
   - Lock: `FOR UPDATE SKIP LOCKED` prevents concurrent processing

2. **if_has_body**
   - Type: IF node
   - Condition: `has_body=TRUE AND analyzed_at IS NULL`
   - Routes: Emails with body to processing, others to body fetch

3. **if_needs_body**
   - Type: IF node
   - Condition: `needs_body=TRUE`
   - Routes: To body fetch workflow if missing

4. **collect_message_ids**
   - Type: Code (JavaScript)
   - Purpose: Aggregate message IDs for batch body fetch
   - Output: `message_ids[]`, `batch_items[]`

5. **Call body Fetch**
   - Type: Execute Workflow
   - Target: `Outlook Body Fetch`
   - Mode: Wait for completion
   - Input: `message_ids` array

6. **db_read_bodies**
   - Type: PostgreSQL
   - Purpose: Re-read bodies after fetch workflow completes
   - Uses: JSONB array parameter for batch IN query

7. **Merge**
   - Type: Merge node
   - Mode: Combine by position
   - Purpose: Join original email data with fetched bodies

8. **inject_body_content**
   - Type: Code (JavaScript)
   - Purpose: Merge body_content into email object
   - Sets: `has_body=TRUE`, `needs_body=FALSE` flags

9. **pre_ai_guard**
   - Type: Code (JavaScript)
   - Purpose: Sanitize and prepare email content for AI
   - Operations:
     - HTML → plain text (strip tags, decode entities)
     - Decode SafeLinks URLs (unwrap Microsoft tracking links)
     - Normalize whitespace (remove control chars, collapse newlines)
     - Smart truncate to MAX_BODY_CHARS (prefer paragraph/sentence boundaries)
     - Calculate body_hash (SHA256)
   - Output: `body_text` (cleaned), `body_hash`, `tokens_est`

10. **mark_validated**
    - Type: PostgreSQL
    - Purpose: Mark email as in-progress
    - Updates: `auto_processed=TRUE`, `updated_at=NOW()`

11. **split_in_batches**
    - Type: Code (JavaScript)
    - Purpose: Divide emails into N batches for parallel AI processing
    - Config: `batch` parameter (default: 2)
    - Output: Array of batch objects with `batch_items[]`

12. **Call Outlook Validate Analyse**
    - Type: Execute Workflow
    - Target: `Outlook Validate Analyse`
    - Mode: Do NOT wait (async execution)
    - Input: `batch_items[]` for each batch

**Data Flow:**
1. Select up to LIMIT unprocessed emails
2. Check if body content exists
3. If missing → Call Body Fetch workflow
4. Merge bodies with email metadata
5. Sanitize content (HTML→text, SafeLinks, truncate)
6. Mark as in-progress to prevent double-processing
7. Split into batches
8. Call Analyse workflow for each batch (async)

**Performance:**
- Batch size: Configurable (default: 2 batches, 4 items per batch)
- Async execution: Launches Analyse workflows in parallel
- Skip locked: `FOR UPDATE SKIP LOCKED` prevents race conditions
- Body caching: Fetches bodies once, reuses in pipeline

**Error Handling:**
- Missing bodies: Calls Body Fetch workflow automatically
- Empty result set: Exits gracefully (no error)
- Lock contention: Skips locked rows (concurrent executions safe)

---

### 4. Outlook Validate Analyse

**File:** `Outlook Validate Analyse.json`

**Purpose:** AI-powered email classification using Claude with hybrid rules + prompt caching

**Trigger:**
- Type: Execute Workflow Trigger
- Called by: `Outlook Validate Select`
- Input: `batch_items[]` array with email data

**Key Nodes:**

1. **Start**
   - Type: Execute Workflow Trigger
   - Receives: `batch_items[]` from calling workflow

2. **get_rules_snapshot**
   - Type: PostgreSQL
   - Purpose: Check if valid cached rules exist
   - Query:
     ```sql
     SELECT * FROM rules_snapshot
     WHERE is_active=TRUE AND expires_at > NOW()
     ORDER BY created_at DESC LIMIT 1
     ```
   - Returns: `version`, `rules_json`, `rules_dsl`, `expires_at`

3. **check_cache_valid**
   - Type: IF node
   - Conditions:
     - `version` NOT empty
     - `expires_at > NOW()`
   - Routes: Cache hit → use cached rules, Cache miss → build new

4. **load_classification_rules**
   - Type: PostgreSQL
   - Purpose: Load active rules with latest metrics (cache miss path)
   - Query:
     ```sql
     SELECT r.*, m.support, m.precision_cat_pct
     FROM classification_rules r
     LEFT JOIN LATERAL (
       SELECT support, precision_cat_pct
       FROM classification_rule_metrics
       WHERE rule_id = r.id
       ORDER BY measured_at DESC LIMIT 1
     ) m ON TRUE
     WHERE r.is_active=TRUE
     ORDER BY r.priority ASC, m.support DESC
     ```

5. **build_rules_dsl**
   - Type: Code (JavaScript)
   - Purpose: Generate human-readable DSL for AI prompt
   - Format:
     ```
     === FINANCIAL_NEWS ===
     - JOS from_domain="inderes.fi" → financial_news (KORKEA tarkkuus, 1097 osumaa, toimenpide: review)
     ```
   - Groups: By `target_category`
   - Sorts: By `priority` ASC, `support` DESC

6. **save_rules_snapshot**
   - Type: PostgreSQL
   - Purpose: Cache compiled rules for 24 hours
   - Invalidates: Previous snapshots (SET is_active=FALSE)
   - Inserts: New snapshot with version `hybrid_YYYY-MM-DD_rN`

7. **merge_rules_to_batch**
   - Type: Code (JavaScript)
   - Purpose: Combine batch_items with rules data
   - Handles: Multiple input sources (Start node + rules nodes)
   - Output: Merged object with both `batch_items` and `rules_*` fields

8. **build_batch_prompt_cache**
   - Type: Code (JavaScript)
   - Purpose: Construct AI prompt with injected rules
   - System Prompt Parts:
     - Base: Role definition, rules version metadata
     - Rules Section: DSL injected here (CACHED)
     - Categories: 10-category definitions
   - User Prompt:
     - JSON array of emails: `[{message_id, subject, from, text}]`
   - Output Format:
     ```javascript
     {
       system: [{
         type: "text",
         text: FULL_SYSTEM_PROMPT,
         cache_control: { type: "ephemeral" }  // ← Anthropic prompt caching
       }],
       messages: [{
         role: "user",
         content: USER_PROMPT
       }]
     }
     ```

9. **ai_classify_emails_cache**
   - Type: HTTP Request
   - Endpoint: `POST https://api.anthropic.com/v1/messages`
   - Headers:
     - `anthropic-version: 2023-06-01`
     - `anthropic-beta: prompt-caching-2024-07-31`
   - Body:
     ```json
     {
       "model": "claude-sonnet-4-5-20250929",
       "max_tokens": 30000,
       "system": $json.system,  // With cache_control
       "messages": $json.messages
     }
     ```
   - Auth: API Key (Anthropic)
   - On Error: Route to error branch

10. **parse_ai_response** (Success branch)
    - Type: Code (Placeholder)
    - Purpose: Extract successful AI response metadata

11. **parse_ai_response1** (Error branch)
    - Type: Code (Placeholder)
    - Purpose: Handle AI API errors

12. **parse_ai_json_cache**
    - Type: Code (JavaScript)
    - Purpose: Extract and validate JSON array from AI response
    - Algorithm:
      - Find longest valid JSON array in response text
      - Handle truncated responses (AI hit token limit)
      - Generate error placeholders for missing emails
      - Validate each object has required fields
    - Error Recovery: Creates `_error` placeholders for failed items

13. **log_ai_usage_cache**
    - Type: PostgreSQL
    - Purpose: Log AI API usage for cost tracking
    - Stores: `input_tokens`, `cache_read_input_tokens`, `output_tokens`

14. **build_log_ai_cache**
    - Type: Code (JavaScript)
    - Purpose: Split AI response into three objects per email
    - Outputs:
      - `ca`: content_analysis (summary, entities, topics)
      - `ei`: email_interest (category, confidence, action)
      - `log`: ai_analysis_log (full raw response)
    - Timestamps: Uses shared `NOW()` for consistency

15. **upsert_content_analysis**
    - Type: PostgreSQL
    - Purpose: Store detailed content analysis
    - Conflict: ON CONFLICT (message_id) DO UPDATE WHERE analyzed_at > previous
    - Fields: `language`, `word_count`, `topics`, `ai_summary`, `sentiment_score`, etc.

16. **upsert_email_interest**
    - Type: PostgreSQL
    - Purpose: Store classification decision
    - Conflict: ON CONFLICT (message_id, model_name, model_version) DO UPDATE WHERE confidence >= previous
    - Fields: `primary_category`, `confidence`, `priority_score`, `recommended_action`, etc.

17. **normalize_ei**
    - Type: Code (JavaScript)
    - Purpose: Normalize `recommended_action` to standard set
    - Maps:
      - `archive_after_review` → `archive`
      - `review_and_decide` → `review`
      - `follow_up_in_days` → `follow_up`
    - Clamps: `confidence` and `priority_score` to 0-100 range

18. **insert_ai_analysis_log**
    - Type: PostgreSQL
    - Purpose: Append-only audit log of AI responses
    - No conflict: INSERT only, never updates
    - Stores: Full JSONB `raw_analysis` for debugging

19. **mark_analyzed**
    - Type: PostgreSQL
    - Purpose: Mark email as analyzed
    - Updates: `emails_ingest.analyzed_at=NOW()`

20. **prepare_error_params** (Error branch)
    - Type: Code (JavaScript)
    - Purpose: Extract error details for logging
    - Handles: Missing message_id, API errors, parsing failures

21. **mark_error**
    - Type: PostgreSQL
    - Purpose: Mark email processing as failed
    - Updates: `auto_processed=FALSE`, appends error to `notes` field

**Data Flow (Happy Path):**
1. Receive batch_items from Select workflow
2. Check rules cache validity
3. If cache miss → Load rules, build DSL, save snapshot
4. Merge rules with batch data
5. Build AI prompt (system + rules + user)
6. Call Claude API with prompt caching
7. Parse JSON response (array of classifications)
8. Split into ca/ei/log objects
9. Parallel upserts: content_analysis, email_interest, ai_analysis_log
10. Mark emails as analyzed

**Data Flow (Error Path):**
1. AI API fails or times out
2. Route to error branch
3. Extract error message
4. Mark email as failed (auto_processed=FALSE)
5. Log error to notes field

**Performance:**
- Prompt caching: 90% cost reduction on cached system prompt
- Cache hit rate: High when rules stable (24h TTL)
- Batch processing: 2-4 emails per API call
- Token optimization: Body truncated to 100k chars (~25k tokens)

**Cost Optimization:**
- Cache rules: System prompt cached for 24 hours
- Rules versioning: Only rebuild when rules change
- Batch size: Balance API calls vs. timeout risk
- Body truncation: Smart truncate at paragraph/sentence boundaries

---

### 5. Outlook Sync DB

**File:** `Outlook Sync DB.json`

**Purpose:** Monitors Outlook for user changes and syncs them back to database (reverse sync)

**Trigger:**
- Type: Schedule Trigger
- Interval: Every 5 minutes
- `Every 5 minutes` node

**Key Nodes:**

1. **fetch_synced_messages**
   - Type: PostgreSQL
   - Purpose: Select messages that were previously synced
   - Query:
     ```sql
     SELECT e.message_id, ad.outlook_categories, ad.outlook_flag_status
     FROM emails_ingest e
     JOIN action_decisions ad ON e.message_id = ad.message_id
     WHERE ad.sync_status = 'synced'
       AND ad.synced_to_outlook_at < NOW() - INTERVAL '5 minutes'
       AND e.is_deleted = FALSE
     LIMIT 50
     ```

2. **has_messages**
   - Type: IF node
   - Condition: `message_id` exists
   - Routes: Empty result to no_messages endpoint

3. **build_batch_request**
   - Type: Code (JavaScript)
   - Purpose: Construct Graph API `$batch` request to fetch current Outlook state
   - Requests:
     ```json
     {
       "id": "0",
       "method": "GET",
       "url": "/users/{upn}/messages/{id}?$select=id,categories,importance,flag,isRead"
     }
     ```

4. **fetch_outlook_state**
   - Type: HTTP Request
   - Endpoint: `POST https://graph.microsoft.com/v1.0/$batch`
   - Purpose: Fetch current state of messages from Outlook
   - Batch size: Up to 20 messages

5. **Merge**
   - Type: Merge node
   - Mode: Combine by position
   - Purpose: Join Outlook responses with DB data

6. **detect_changes**
   - Type: Code (JavaScript)
   - Purpose: Compare Outlook state vs. DB state
   - Detects:
     - `categoryChanged`: Categories array differs
     - `flagChanged`: Flag status differs
     - `importanceChanged`: Importance level differs
   - Output: Array of changes with old/new values

7. **has_changes**
   - Type: IF node
   - Condition: `message_id` exists (changes detected)
   - Routes: No changes to no_changes endpoint

8. **save_user_feedback**
   - Type: PostgreSQL
   - Purpose: Record user correction to `user_feedback` table
   - Fields:
     - `message_id`, `feedback_type='category_correction'`
     - `ai_categories` (old), `user_categories` (new)
     - `from_address`, `from_domain`

9. **prepare_update_data**
   - Type: Code (JavaScript)
   - Purpose: Transform data for update queries
   - Converts: Arrays to JSON strings, structures `outlook_state`

10. **update_action_decisions**
    - Type: PostgreSQL
    - Purpose: Update decision record with user's changes
    - Updates:
      - `outlook_categories`, `outlook_flag_status`, `outlook_importance`
      - `sync_status='synced'` (restore after user modification)
      - `outlook_state_snapshot` (current state)

11. **update_sender_learning**
    - Type: PostgreSQL
    - Purpose: Adjust sender classification based on user feedback
    - Logic:
      - Increment `user_corrections` counter
      - Reduce `confidence_score` if >5 corrections in 30 days
      - Target: `sender_classification` table by `sender_key`

12. **log_sync**
    - Type: PostgreSQL
    - Purpose: Log sync event to `sync_log` table
    - Fields:
      - `sync_direction='outlook_to_db'`
      - `sync_type='user_correction'`
      - `outlook_state`, `db_state`, `changes_made` (JSONB)

**Data Flow:**
1. Select synced messages from last 5+ minutes
2. Fetch current Outlook state via batch API
3. Compare Outlook vs. DB state
4. Detect differences (categories, flag, importance)
5. Save to user_feedback table
6. Update action_decisions with user's changes
7. Update sender learning metrics
8. Log sync event

**Purpose:**
- Feedback loop: Capture user corrections for ML training
- State consistency: Keep DB in sync with Outlook
- Learning: Adjust sender classifications based on corrections

---

### 6. Outlook Sync OL

**File:** `Outlook Sync OL.json`

**Purpose:** Applies database decisions back to Outlook (forward sync)

**Trigger:**
- Type: Schedule Trigger
- Interval: Every 15 minutes

**Key Nodes:**

1. **select_pending_decisions**
   - Type: PostgreSQL
   - Purpose: Select decisions awaiting sync to Outlook
   - Query:
     ```sql
     SELECT ei.*, ad.*
     FROM email_interest ei
     JOIN action_decisions ad ON ei.message_id = ad.message_id
     WHERE ad.sync_status = 'pending'
     LIMIT 50
     ```

2. **map_to_outlook_actions**
   - Type: Code (JavaScript)
   - Purpose: Transform DB decisions to Outlook API format
   - Mappings:
     - `primary_category` → `categories[]` array
     - `recommended_action` → `flag.flagStatus`
     - `priority_score` → `importance`
   - Example:
     ```javascript
     {
       categories: ["Financial", "Investment"],
       flag: { flagStatus: "flagged" },
       importance: "high"
     }
     ```

3. **build_patch_batch**
   - Type: Code (JavaScript)
   - Purpose: Build Graph API `$batch` with PATCH requests
   - Requests:
     ```json
     {
       "id": "0",
       "method": "PATCH",
       "url": "/users/{upn}/messages/{id}",
       "body": {
         "categories": [...],
         "flag": {...},
         "importance": "..."
       }
     }
     ```

4. **apply_to_outlook**
   - Type: HTTP Request
   - Endpoint: `POST https://graph.microsoft.com/v1.0/$batch`
   - Purpose: Apply all changes in single batch call

5. **parse_batch_responses**
   - Type: Code (JavaScript)
   - Purpose: Check for successful vs. failed updates
   - Extracts: HTTP status codes from batch responses

6. **update_sync_status**
   - Type: PostgreSQL
   - Purpose: Mark decisions as synced or failed
   - Updates:
     - `sync_status='synced'` (success) or `'failed'` (error)
     - `synced_to_outlook_at=NOW()`
     - `outlook_state_snapshot` (JSONB of applied state)

7. **log_sync_events**
   - Type: PostgreSQL
   - Purpose: Log to `sync_log` table
   - Fields:
     - `sync_direction='db_to_outlook'`
     - `sync_type` (category_update, folder_move, flag_update)
     - `sync_status`, `changes_made`

**Data Flow:**
1. Select pending decisions (sync_status='pending')
2. Map to Outlook API format
3. Build batch PATCH request
4. Apply changes via Graph API
5. Parse responses (success/failure)
6. Update sync_status in action_decisions
7. Log sync events

**Conflict Resolution:**
- User-modified: If `lastModifiedDateTime` changed, mark as `sync_status='user_modified'`
- User wins: Don't overwrite user changes
- Feedback: Log user modifications to `user_feedback` table

---

## Supporting Workflows

### 7. Outlook_folder_discovery

**File:** `Outlook_folder_discovery.json`

**Purpose:** Discovers and catalogs all email folders in the mailbox

**Trigger:**
- Type: Manual or Schedule
- Use case: Initial setup or periodic folder structure updates

**Key Operations:**
1. Fetch folder hierarchy from Graph API
2. Store in `folders_cache` table
3. Build `folder_path` recursively (e.g., "Inbox/Archive/2024")

### 8. Category Discovery Analysis

**File:** `Category Discovery Analysis.json`

**Purpose:** Analyzes historical email data to discover new classification rule candidates

**Trigger:**
- Type: Manual (run weekly or monthly)

**Algorithm:**
1. Group emails by `from_domain`, `from_address`, `message_id_domain`
2. Calculate metrics:
   - `support`: COUNT(DISTINCT message_id)
   - `precision_cat_pct`: % classified to same category
   - `avg_relevance_pct`: AVG(confidence score)
3. Filter candidates:
   - `support >= 5` (minimum occurrences)
   - `precision_cat_pct >= 80%` (consistency threshold)
   - NOT EXISTS in `classification_rules` (new patterns only)
4. Generate INSERT statements for review

**Output:**
- SQL file with proposed rules
- Manual review and approval required before execution

### 9. Outlook Validate Select (Backup)

**File:** `Outlook Validate Select_BACKUP.json`

**Purpose:** Backup version of main selection workflow

**Note:** Keep for rollback if changes break production

---

## Workflow Dependencies

### Dependency Graph

```
Outlook Emails Fetch
  ↓ (writes to emails_ingest)
Outlook Body Fetch ← (called by) ← Outlook Validate Select
  ↓ (writes to email_bodies)
Outlook Validate Select
  ↓ (calls)
Outlook Validate Analyse
  ↓ (writes to email_interest, content_analysis, action_decisions)
Outlook Sync OL (reads action_decisions)
  ↓ (updates Outlook via Graph API)
Outlook Sync DB (monitors Outlook changes)
  ↓ (updates action_decisions, user_feedback)
```

### Database Table Usage

**Emails Ingest:**
- Written by: Outlook Emails Fetch
- Read by: Outlook Validate Select, Outlook Sync OL

**email_bodies:**
- Written by: Outlook Body Fetch
- Read by: Outlook Validate Select (for AI analysis)

**classification_rules:**
- Written by: Manual scripts (Category Discovery output)
- Read by: Outlook Validate Analyse (rules loading)

**rules_snapshot:**
- Written by: Outlook Validate Analyse (cache management)
- Read by: Outlook Validate Analyse (cache check)

**email_interest:**
- Written by: Outlook Validate Analyse (AI decisions)
- Read by: Outlook Sync OL (sync decisions to Outlook)

**action_decisions:**
- Written by: Outlook Validate Analyse (initial), Outlook Sync DB (updates)
- Read by: Outlook Sync OL (pending sync queue)

**user_feedback:**
- Written by: Outlook Sync DB (user corrections)
- Read by: Category Discovery Analysis (ML training data)

---

## Execution Patterns

### Initial Setup (Cold Start)

1. Run `Outlook_folder_discovery` to catalog folders
2. Manually populate `classification_rules` with seed data
3. Enable `Outlook Emails Fetch` to populate `emails_ingest`
4. Wait for initial fetch to complete (may take hours for large mailboxes)
5. Run `Category Discovery Analysis` on historical data
6. Enable `Outlook Validate Select` to start classification pipeline
7. Enable `Outlook Sync OL` to apply decisions to Outlook

### Steady State Operation

**Every 5 minutes:**
- Outlook Emails Fetch: Delta sync for new/changed emails
- Outlook Sync DB: Monitor for user changes

**Every 4 minutes:**
- Outlook Validate Select: Process unanalyzed emails

**Every 15 minutes:**
- Outlook Sync OL: Apply pending decisions to Outlook

**Weekly:**
- Category Discovery Analysis: Identify new rule candidates
- Review and approve new rules
- Execute SQL to add to `classification_rules`

### Error Recovery

**Scenario: AI API timeout**
- Email remains with `analyzed_at=NULL`
- Next run of Validate Select will retry
- After 3 failures: Check `emails_ingest.notes` for error log

**Scenario: Outlook sync failure**
- Decision remains with `sync_status='pending'`
- Next run of Sync OL will retry
- Check `sync_log` for detailed error messages

**Scenario: Duplicate emails**
- `dedupe_key` constraint prevents duplicates
- Emails Fetch: ON CONFLICT DO UPDATE (idempotent)

### Monitoring Queries

**Unprocessed queue:**
```sql
SELECT COUNT(*) FROM emails_ingest WHERE analyzed_at IS NULL;
```

**Sync backlog:**
```sql
SELECT COUNT(*) FROM action_decisions WHERE sync_status = 'pending';
```

**Recent errors:**
```sql
SELECT * FROM process_log
WHERE error_message IS NOT NULL
ORDER BY created_at DESC LIMIT 10;
```

**AI cost tracking:**
```sql
SELECT
  DATE(created_at) as date,
  COUNT(*) as batches,
  SUM((detail->>'usage'->>'input_tokens')::int) as total_input_tokens,
  SUM((detail->>'usage'->>'cache_read_input_tokens')::int) as cached_tokens
FROM process_log
WHERE operation = 'ai_classify'
GROUP BY 1
ORDER BY 1 DESC;
```

---

## Configuration Reference

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `USER_UPN` | (required) | Primary user email address |
| `GRAPH_TOP` | 10000 | Items per Graph API page |
| `PAGES_PER_RUN` | 7 | Max pages per fetch execution |
| `MAX_ITEMS_PER_RUN` | 70 | Max emails per fetch execution |
| `MAX_BODY_CHARS` | 100000 | Body truncation limit |
| `batch` | 2 | Number of AI batches |

### Workflow Settings (n8n)

**All workflows:**
- Timezone: Europe/Helsinki (UTC+03:00)
- Execution order: Serial (no parallel executions of same workflow)
- Retry on fail: Enabled (3 attempts)
- Error workflow: None (errors logged to database)

**Outlook Emails Fetch:**
- Timeout: 5 minutes per node
- Allow multiple executions: No (delta sync requires sequential)

**Outlook Validate Analyse:**
- Timeout: 10 minutes (AI can be slow)
- Allow multiple executions: Yes (batches processed in parallel)

**Outlook Sync OL:**
- Timeout: 2 minutes
- Allow multiple executions: No (prevent race conditions)

---

## Troubleshooting

### Workflow not triggering

**Symptoms:** Schedule trigger not executing

**Solutions:**
1. Check n8n is running: `systemctl status n8n` (if self-hosted)
2. Verify trigger is active: Green toggle in n8n UI
3. Check execution history: May be failing silently

### Workflow stuck in "Running" state

**Symptoms:** Execution shows as running for >10 minutes

**Solutions:**
1. Check for infinite loops (pagination logic)
2. Review `should_continue` conditions
3. Kill execution: Click "Stop Execution" in n8n UI

### High AI costs

**Symptoms:** Unexpected Anthropic API charges

**Solutions:**
1. Verify prompt caching enabled: Check `anthropic-beta` header
2. Check cache hit rate:
   ```sql
   SELECT detail->>'usage'->>'cache_read_input_tokens'
   FROM process_log WHERE operation='ai_classify';
   ```
3. Reduce batch size: Lower `batch` parameter in set_config
4. Increase rules coverage: More emails classified by rules = fewer AI calls

### Emails not syncing to Outlook

**Symptoms:** `sync_status='pending'` not changing

**Solutions:**
1. Check Graph API token: May be expired (re-authenticate)
2. Verify permissions: Mail.ReadWrite required
3. Check rate limits: Graph API throttling (429 errors)
4. Review sync_log:
   ```sql
   SELECT * FROM sync_log WHERE sync_status='failed' ORDER BY created_at DESC LIMIT 10;
   ```

---

**Last Updated:** 2025-10-16
**Document Version:** 1.0
**Maintained By:** Project team
