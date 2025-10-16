# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is an **n8n workflow automation system** for intelligent Outlook email processing. It fetches emails from Microsoft Graph API, analyzes them with AI (Claude), and stores structured data in PostgreSQL. The system uses delta sync for incremental updates and implements a sophisticated email classification pipeline.

**Key Technologies:**
- **n8n** (workflow automation platform)
- **Microsoft Graph API** (Outlook/Exchange integration)
- **PostgreSQL** (data storage with `outlook` schema)
- **Anthropic Claude API** (AI email classification and analysis)

**Primary User:** `jouni.pappila@repoxcapital.fi` (financial services context)

## Architecture

### Core Workflow Pipeline

```
┌─────────────────────────────────────────────────────────────────────┐
│ 1. EMAIL FETCH (Outlook Emails Fetch.json)                         │
│    Delta Sync → Parse Headers → Extract Attachments → DB Upsert    │
└─────────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────────┐
│ 2. ORCHESTRATOR (Outlook_Orchestrator_KESKEN.json)                 │
│    Webhook Handler → Change Events → Folder Resolution → DB Sync   │
└─────────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────────┐
│ 3. VALIDATION SELECTION (Outlook Validate Select.json)             │
│    Select Unanalyzed → Body Fetch → Pre-AI Guard → Batch Split     │
└─────────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────────┐
│ 4. AI ANALYSIS (Outlook Validate Analyse.json)                     │
│    Claude API → Parse Response → Upsert Analysis + Interest + Log  │
└─────────────────────────────────────────────────────────────────────┘
```

### Database Schema (`Schema_outlook.sql`)

**Core Tables:**
- `emails_ingest` - Main email records with metadata
- `email_bodies` - Full email body content (separate for performance)
- `email_headers` - Raw email headers and technical metadata
- `attachments` - Attachment metadata
- `email_interest` - AI classification results (priority, category, actions)
- `content_analysis` - AI content analysis (sentiment, entities, topics)
- `action_decisions` - Final action recommendations
- `ai_analysis_log` - Audit trail for AI analysis
- `delta_state` - Delta sync state tracking
- `sender_classification` - Sender pattern learning
- `folders_cache` - Outlook folder hierarchy cache

**Key Fields:**
- `message_id` - Outlook's unique message identifier (primary key)
- `dedupe_key` - Deduplication using `internetMessageId` or fallback
- `analyzed_at` - Timestamp marking AI analysis completion
- `auto_processed` - Lock flag for concurrent processing
- `needs_body` - Flag for body fetch requirement

## Workflow Details

### 1. Outlook Emails Fetch (`Outlook Emails Fetch.json`)

**Purpose:** Fetch emails using Microsoft Graph Delta API

**Key Nodes:**
- `load_targets_saapuneet` - Queries delta_state for next folder to sync
- `prepare_delta_url` - Builds Graph API delta/pagination URL
- `fetch_emails_http` - Calls Graph API with OAuth
- `parse_headers` - Extracts email headers (List-Unsubscribe, Message-ID, etc.)
- `parse_attachments` - Processes attachment metadata and creates review queue
- `upsert_emails` - Bulk upsert to `emails_ingest` using `dedupe_key`
- `save_delta_link` - Persists `@odata.deltaLink` for next run

**Delta Sync Logic:**
- Uses `@odata.deltaLink` to fetch only changes since last sync
- Pagination via `@odata.nextLink` (processes up to 7 pages per run)
- Tracks tombstones (`@removed`) for deletions
- Run limits: `MAX_ITEMS_PER_RUN=70`, `PAGES_PER_RUN=7`

**Configuration:**
```javascript
GRAPH_SELECT = "id,parentFolderId,receivedDateTime,subject,from,toRecipients,...,internetMessageHeaders"
GRAPH_EXPAND = "attachments($select=id,name,contentType,size,isInline)"
GRAPH_TOP = 10000
```

### 2. Outlook Orchestrator (`Outlook_Orchestrator_KESKEN.json`)

**Purpose:** Real-time webhook handler for Outlook change notifications

**Webhook Endpoints:**
- `POST /webhook/graph/mail` - Receives Microsoft Graph subscription notifications
- `GET /webhook/graph/mail` - Validation token endpoint

**Change Types Handled:**
- `created` - New message
- `updated` - Metadata change (isRead, categories, flag, folder)
- `deleted` - Soft delete (sets `is_deleted=true`)

**Key Features:**
- **Folder Resolution:** Looks up folder names from `folders_cache`, fetches from Graph if missing
- **No-op Detection:** Skips redundant updates by comparing prev/current state
- **Client State Validation:** Verifies `clientState` matches expected value for security

### 3. Outlook Validate Select (`Outlook Validate Select.json`)

**Purpose:** Selects unanalyzed emails and prepares them for AI analysis

**Selection Criteria:**
```sql
WHERE analyzed_at IS NULL
  AND is_deleted = false
  AND auto_processed = false
ORDER BY received_datetime DESC
LIMIT 20
```

**Body Fetch Process:**
- Checks `needs_body` flag
- Calls `Outlook Body Fetch` workflow to fetch missing bodies
- Merges body content back to candidate emails

**Pre-AI Guard (`pre_ai_guard` node):**
- HTML → text conversion
- SafeLinks URL decoding (`safelinks.protection.outlook.com`)
- Whitespace normalization
- Smart truncation at `MAX_BODY_CHARS=100000`
- Computes `body_hash` and `tokens_est`

**Batching:**
- Splits into N batches (configurable `batch=2`)
- Calls `Outlook Validate Analyse` for each batch (non-blocking)

### 4. Outlook Validate Analyse (`Outlook Validate Analyse.json`)

**Purpose:** AI-powered email classification and analysis

**AI Model:** Claude Sonnet 4.5 (`claude-sonnet-4-5-20250929`)

**Prompt Caching:** Uses Anthropic's prompt caching feature
- System prompt cached with `cache_control: { type: "ephemeral" }`
- Reduces costs for repeated batch analyses

**Classification Categories (10 required):**
1. `business_critical` - Contracts, invoices, legal
2. `personal_communication` - Direct personal messages
3. `financial_news` - Market updates, stock analysis
4. `marketing` - Promotional content
5. `notifications` - Automated system messages
6. `industry_news` - Sector trends and research
7. `internal` - Company-internal communications
8. `regulatory` - Compliance and legal requirements
9. `spam_low_value` - Junk mail
10. `uncategorized` - Unclear cases

**Analysis Output:**
- **classification** - Category, confidence, pattern matching
- **content_analysis** - Language, word count, sentiment, entities, topics, content_structure
- **decision** - Priority score, recommended action, due date, `requires_deep_analysis` flag

**Recommended Actions:**
- `none`, `read`, `review`, `follow_up`, `urgent`, `archive`, `calendar_consider`

**Database Writes:**
- `email_interest` - Classification + decision
- `content_analysis` - Content metadata
- `ai_analysis_log` - Raw AI response audit
- `emails_ingest.analyzed_at` - Marks completion

### 5. Outlook Body Fetch (`Outlook Body Fetch.json`)

**Purpose:** Fetches full email body content from Graph API

**API Call:**
```
GET /users/{upn}/messages/{id}?$select=body,uniqueBody,bodyPreview
Header: Prefer: outlook.body-content-type="text"
```

**Error Handling:**
- HTTP 429/5xx → `mark_retry_backoff` with exponential backoff
- Other errors → `mark_fatal`
- Empty body → `mark_empty_retry` (2-hour delay)

**Status Tracking:**
- `needs_body` flag
- `last_body_fetch_status` (`ok`, `empty`, `retryable:429`, `fatal:404`)
- `retry_at` timestamp

## Database Operations

### Upsert Pattern

Most workflows use `ON CONFLICT ... DO UPDATE` for idempotent inserts:

```sql
INSERT INTO outlook.emails_ingest (message_id, subject, ...)
VALUES (...)
ON CONFLICT ON CONSTRAINT emails_ingest_dedupe_key_key DO UPDATE SET
  subject = EXCLUDED.subject,
  updated_at = NOW()
```

### Deduplication Strategy

- Primary: `internetMessageId` (global email identifier)
- Fallback: `message_id || '|' || receivedDateTime`

### Concurrency Control

- `auto_processed` flag prevents duplicate AI analysis
- `FOR UPDATE SKIP LOCKED` in candidate selection queries

## Common Development Commands

### Testing Workflows

Since these are n8n workflows (JSON files), you cannot run them directly from command line. They must be:
1. Imported into n8n UI
2. Configured with credentials
3. Executed via n8n's execution engine

### Database Queries

Connect to PostgreSQL and use the `outlook` schema:

```sql
-- View unanalyzed emails
SELECT message_id, subject, from_address, received_datetime
FROM outlook.emails_ingest
WHERE analyzed_at IS NULL AND is_deleted = false
LIMIT 10;

-- Check AI analysis results
SELECT ei.message_id, ei.primary_category, ei.confidence, ei.priority_score
FROM outlook.email_interest ei
JOIN outlook.emails_ingest e ON e.message_id = ei.message_id
ORDER BY ei.created_at DESC
LIMIT 10;

-- Delta sync status
SELECT user_upn, resource_path, sync_status, last_sync_success, items_processed
FROM outlook.delta_state;
```

### Key Configuration Points

**Graph API Credentials:**
- OAuth2 credential: "Graph Outlook" (ID: `wINgbOJ2X4ZzA7NV`)
- Requires Microsoft Graph permissions: `Mail.Read`, `Mail.ReadWrite`

**PostgreSQL Credential:**
- ID: `4rl59kH75QNg0oSk`
- Database: Uses `outlook` schema

**Anthropic API:**
- Credential ID: `XlrgzrywMY0KCmRC`
- Model: `claude-sonnet-4-5-20250929`

## Important Patterns

### JavaScript Node Conventions

**Item Processing:**
```javascript
// Run Once for All Items (preferred for aggregation)
return items.map(item => {
  const j = item.json || {};
  // ... process
  return { json: { ...result } };
});

// Run Once for Each Item (for simple transforms)
return items.map(item => ({ json: item.json }));
```

**Accessing Other Nodes:**
```javascript
// Get data from another node by name
const otherNodeData = $node['other_node_name'].json;

// Get data from specific item index
const items = $items('node_name');
const firstItem = items[0]?.json;
```

### Error Handling

All workflows implement error branches:
- `onError: "continueErrorOutput"` on HTTP nodes
- Separate error paths with `prepare_error_params` → `mark_error` pattern

### Timestamps

Always use UTC:
```javascript
const now = new Date().toISOString(); // Returns ISO 8601 UTC string
```

Database stores as `timestamptz` (timezone-aware).

## Caveats and Gotchas

1. **Message ID Encoding:** Always `encodeURIComponent()` for Graph API URLs
2. **Dedupe Key Uniqueness:** `internetMessageId` can be null; fallback is essential
3. **Body Content Separation:** Bodies are in separate table (`email_bodies`) for performance
4. **Folder Cache Staleness:** Folder names may be outdated; orchestrator refreshes on miss
5. **AI Prompt Sensitivity:** Changing system prompt invalidates cache; coordinate batch changes
6. **Webhook Security:** Always validate `clientState` parameter
7. **Delta Link Expiry:** Delta links expire after ~30 days; workflow handles reinitialization
8. **Attachment Size Limit:** 25 MB threshold for automatic download; larger go to review queue

## Troubleshooting

**Emails not being analyzed:**
- Check `analyzed_at IS NULL AND auto_processed = false`
- Verify `needs_body = false` (body must be fetched first)
- Check AI analysis logs in `outlook.ai_analysis_log`

**Delta sync stuck:**
- Inspect `delta_state` table for `sync_status` and `last_error`
- Check `items_processed` hasn't exceeded reasonable limits
- Verify OAuth token hasn't expired

**AI classification errors:**
- Review `outlook.process_log` for validation errors
- Check if response parsing failed (look for `uncategorized` with confidence=0)
- Verify prompt caching headers in HTTP request logs

## Related Files

- `Schema_outlook.sql` - Complete database schema with constraints
- `Category Discovery Analysis_dokumentaatio.docx` - Business requirements (Finnish)
- `Logiikka_kaavio_nimet.xlsx` - Workflow logic diagram
- `read_doc.py` - Utility to extract text from Word document
