# System Architecture

## High-Level Overview

The n8n Outlook automation system is a hybrid architecture that combines rule-based classification (Gateway) with AI-powered analysis (Validator) to intelligently process and categorize email communications.

```
┌─────────────────────────────────────────────────────────────────────┐
│                      Microsoft Outlook / Graph API                   │
│                     (Email Source & Sync Target)                     │
└────────────────┬─────────────────────────────────┬──────────────────┘
                 │                                 │
                 │ Delta Sync                      │ Bidirectional Sync
                 ▼                                 ▼
┌─────────────────────────────────┐  ┌─────────────────────────────────┐
│   Outlook Emails Fetch          │  │   Outlook Sync DB → OL          │
│   (Delta API, Metadata)         │  │   (Apply decisions to Outlook)  │
└────────────┬────────────────────┘  └─────────────────────────────────┘
             │
             ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    PostgreSQL Database (outlook schema)              │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐  │
│  │ emails_ingest    │  │ email_bodies     │  │ delta_state      │  │
│  │ (Metadata)       │  │ (HTML content)   │  │ (Sync checkpoints│  │
│  └──────────────────┘  └──────────────────┘  └──────────────────┘  │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐  │
│  │ classification_  │  │ contact_lists    │  │ rules_snapshot   │  │
│  │ rules (Static)   │  │ (Dynamic VIP)    │  │ (Cache)          │  │
│  └──────────────────┘  └──────────────────┘  └──────────────────┘  │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐  │
│  │ email_interest   │  │ content_analysis │  │ action_decisions │  │
│  │ (Classifications)│  │ (AI insights)    │  │ (Sync queue)     │  │
│  └──────────────────┘  └──────────────────┘  └──────────────────┘  │
└────────────┬────────────────────────────────────────────────────────┘
             │
             ▼
┌─────────────────────────────────────────────────────────────────────┐
│              Outlook Validate Select (Orchestrator)                  │
│  ┌────────────────────────────────────────────────────────────────┐ │
│  │ 1. Select unprocessed emails (analyzed_at IS NULL)            │ │
│  │ 2. Check if body content exists → Fetch if needed             │ │
│  │ 3. Pre-process: HTML→text, SafeLinks decode, sanitize         │ │
│  │ 4. Split into batches (configurable size)                     │ │
│  │ 5. Call Outlook Validate Analyse for each batch               │ │
│  └────────────────────────────────────────────────────────────────┘ │
└────────────┬────────────────────────────────────────────────────────┘
             │
             ▼
┌─────────────────────────────────────────────────────────────────────┐
│           Outlook Validate Analyse (AI Engine)                      │
│  ┌────────────────────────────────────────────────────────────────┐ │
│  │ HYBRID SYSTEM WITH PROMPT CACHING                              │ │
│  │                                                                 │ │
│  │ 1. Load Rules Snapshot (24h cache)                            │ │
│  │    ├─ Cache hit? → Use cached rules                           │ │
│  │    └─ Cache miss? → Build from classification_rules           │ │
│  │                                                                 │ │
│  │ 2. Build AI Prompt with Injected Rules                        │ │
│  │    ├─ System prompt: Category definitions                     │ │
│  │    ├─ Rules DSL: Known senders & patterns                     │ │
│  │    └─ User prompt: Batch of emails to analyze                 │ │
│  │                                                                 │ │
│  │ 3. Call Claude API with Prompt Caching                        │ │
│  │    ├─ Cache system prompt (rules version tracked)             │ │
│  │    └─ Return: Array of classifications                        │ │
│  │                                                                 │ │
│  │ 4. Parse & Store Results                                      │ │
│  │    ├─ email_interest (decision)                               │ │
│  │    ├─ content_analysis (entities, summary)                    │ │
│  │    └─ ai_analysis_log (audit trail)                           │ │
│  └────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────┘
             │
             ▼
┌─────────────────────────────────────────────────────────────────────┐
│              Outlook Sync DB (Decision Applier)                      │
│  ┌────────────────────────────────────────────────────────────────┐ │
│  │ 1. Read email_interest decisions (status='proposed')          │ │
│  │ 2. Map to Outlook actions (categories, flags, importance)     │ │
│  │ 3. Update via Microsoft Graph PATCH API                       │ │
│  │ 4. Store in action_decisions (sync_status='synced')           │ │
│  └────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────┘
```

## Core Components

### 1. Data Ingestion Layer

#### Outlook Emails Fetch Workflow
**Purpose:** Fetches email metadata using Microsoft Graph Delta API

**Key Nodes:**
- `get_delta_state`: Retrieves last sync checkpoint from `delta_state` table
- `fetch_delta_messages`: Calls `/me/mailFolders/inbox/messages/delta` endpoint
- `transform_and_ingest`: Normalizes Graph API response to database schema
- `upsert_emails`: Inserts/updates `emails_ingest` table

**Data Flow:**
1. Read `delta_link` from previous sync
2. Fetch new/changed messages (pagination supported via `@odata.nextLink`)
3. Extract metadata: subject, from, received_datetime, has_attachments
4. Generate `dedupe_key` = SHA256(internet_message_id + received_datetime)
5. Upsert to `emails_ingest` (conflict on dedupe_key → skip)
6. Update `delta_state` with new `delta_link`

**Performance:**
- Incremental sync: Only changed messages since last run
- Batch size: 100 messages per API call
- Runs every 10 minutes (schedule trigger)

#### Outlook Body Fetch Workflow
**Purpose:** Retrieves full HTML body content for emails needing analysis

**Key Nodes:**
- `select_needs_body`: SELECT WHERE needs_body=TRUE AND body_fetched_at IS NULL
- `fetch_body_content`: Calls `/me/messages/{id}?$select=body` endpoint
- `upsert_body`: Inserts into `email_bodies` table

**Data Flow:**
1. Select emails with `needs_body=TRUE` flag
2. For each message_id, fetch full body via Graph API
3. Store HTML content in separate `email_bodies` table (normalized design)
4. Update `emails_ingest.body_fetched_at` timestamp

**Performance:**
- Triggered by Validate Select when body is missing
- Parallel execution: Up to 5 concurrent fetches
- Retry logic: Exponential backoff on 429 rate limit errors

### 2. Classification Layer

#### Hybrid Classification System

The system uses a two-tier approach:

**Tier 1: Rule-Based Gateway (Deterministic)**
- **Contact Lists** (Dynamic VIP):
  - `vip_finance`: Bloomberg, Inderes, SeekingAlpha → AI decides category
  - `vip_personal`: Specific addresses from VIP domains → business_critical
  - `personal`: Known personal contacts → personal_communication
  - `business_critical`: Key partners → business_critical
  - `internal`: Own organization domains → internal
- **Classification Rules** (Static Patterns):
  - Extracted from historical data analysis
  - Priority-ordered matching (10-40, lower = higher priority)
  - Scopes: `from_address` (10), `from_domain` (20-30), `message_id_domain` (20)

**Tier 2: AI Analysis (Adaptive)**
- Claude Sonnet 4.5 with prompt caching
- 10-category classification system
- Injected rules provide learned patterns
- Confidence scoring (0-100%)
- Entity extraction and sentiment analysis

#### Rules Snapshot & Caching

**Table:** `outlook.rules_snapshot`

**Purpose:** Cache compiled rules for AI prompt injection

**Lifecycle:**
1. **Check Cache** (on each Validate Analyse run):
   - Query `rules_snapshot WHERE is_active=TRUE AND expires_at > NOW()`
   - If valid → use cached `rules_dsl`

2. **Build New Snapshot** (on cache miss):
   - Load all active rules from `classification_rules`
   - Sort by priority and support
   - Generate DSL format:
     ```
     === FINANCIAL_NEWS ===
     - JOS from_domain="inderes.fi" → financial_news (KORKEA tarkkuus, 1097 osumaa)
     ```
   - Save to `rules_snapshot` with TTL=24h

3. **Invalidation:**
   - Automatic: After 24 hours (TTL expiry)
   - Manual: When new rules added via Category Discovery Analysis

**Versioning:**
- Format: `hybrid_YYYY-MM-DD_rN` (e.g., `hybrid_2025-10-15_r34`)
- Tracked in `email_interest.rule_conditions` for audit trail

### 3. AI Analysis Engine

#### Outlook Validate Analyse Workflow

**Prompt Architecture:**

```javascript
// System Prompt (CACHED)
{
  type: "text",
  text: `
    Olet rahoituskäyttöön koulutettu sähköpostiluokittelun asiantuntija.

    RULES VERSION: hybrid_2025-10-15_r34
    RULES COUNT: 34

    ═══════════════════════════════════════════════
    TUNNETUT LÄHETTÄJÄT JA SÄÄNNÖT
    ═══════════════════════════════════════════════

    === FINANCIAL_NEWS ===
    - JOS from_domain="inderes.fi" → financial_news (KORKEA tarkkuus, 1097 osumaa)
    - JOS from_domain="seekingalpha.com" → financial_news (KORKEA tarkkuus, 433 osumaa)

    === BUSINESS_CRITICAL ===
    - JOS from_domain="kaivonporaus.com" → business_critical (KORKEA tarkkuus, 20 osumaa)

    [... 31 more rules ...]

    PRIMARY_CATEGORY LUOKITTELU:
    1. business_critical - Sopimukset, laskut, kriittiset kumppanit
    2. personal_communication - 1:1 henkilökohtainen viestintä
    3. financial_news - Sijoitusuutiset, analyysit, markkinadata
    4. marketing - Mainokset, kampanjat
    5. notifications - Järjestelmäilmoitukset
    6. industry_news - Toimiala-uutiset (EI rahoitus)
    7. internal - Oma organisaatio
    8. regulatory - Säädökset, compliance
    9. spam_low_value - Roskaposti
    10. uncategorized - Epäselvät tapaukset
  `,
  cache_control: { type: "ephemeral" }  // ← Anthropic prompt caching
}

// User Prompt (DYNAMIC)
{
  role: "user",
  content: `
    Analysoi seuraavat 2 sähköpostia ja palauta JSON-taulukko:

    [
      {
        "message_id": "AAMkAG...",
        "subject": "Inderes: Nokia - Osta",
        "from": "noreply@inderes.fi",
        "text": "Nokia julkaisi Q4 tuloksen..."
      },
      {
        "message_id": "AAMkAG...",
        "subject": "Lasku #1234",
        "from": "invoice@kaivonporaus.com",
        "text": "Lasku eräpäivä 7 päivää..."
      }
    ]
  `
}
```

**AI Response Format:**

```json
[
  {
    "message_id": "AAMkAG...",
    "classification": {
      "primary_category": "financial_news",
      "confidence": 95
    },
    "content_analysis": {
      "language": "fi",
      "word_count": 234,
      "ai_summary": "Inderesin osakeanalyysi Nokiasta",
      "topics": ["sijoitus", "teknologia"],
      "sentiment_score": 0.6
    },
    "decision": {
      "interest_label": "financial_news",
      "recommended_action": "review",
      "priority_score": 70,
      "confidence": 95
    }
  }
]
```

**Node Breakdown:**

1. **Start (ExecuteWorkflowTrigger)**: Receives batch_items from Validate Select
2. **get_rules_snapshot**: Check cache validity
3. **check_cache_valid**: If expired → load_classification_rules
4. **build_rules_dsl**: Generate DSL text from rules
5. **save_rules_snapshot**: Update cache with new version
6. **merge_rules_to_batch**: Combine rules + batch data
7. **build_batch_prompt_cache**: Construct system + user prompts
8. **ai_classify_emails_cache**: POST to Claude API with prompt caching headers
9. **parse_ai_json_cache**: Extract JSON array from AI response
10. **build_log_ai_cache**: Split response into ca/ei/log objects
11. **upsert_content_analysis**: Store analysis results
12. **upsert_email_interest**: Store classification decisions
13. **insert_ai_analysis_log**: Audit trail with full raw response
14. **mark_analyzed**: Set analyzed_at timestamp

**Error Handling:**
- Missing body content → placeholder classification (uncategorized)
- AI parse failure → generate error placeholders with `_error` field
- API timeout → retry with exponential backoff
- Token limit exceeded → truncate body_text to MAX_BODY_CHARS (100k default)

### 4. Synchronization Layer

#### Outlook Sync DB Workflow

**Purpose:** Apply database decisions back to Outlook

**Mapping Logic:**

```javascript
// Primary Category → Outlook Categories (tags)
const CATEGORY_MAP = {
  'business_critical': ['Business Critical', 'Action Required'],
  'financial_news': ['Financial', 'Investment'],
  'personal_communication': ['Personal'],
  'notifications': ['Notification'],
  'industry_news': ['Industry News'],
  'internal': ['Internal'],
  'regulatory': ['Regulatory'],
  'spam_low_value': ['Spam'],
  'marketing': ['Marketing']
};

// Recommended Action → Outlook Flag
const FLAG_MAP = {
  'urgent': 'flagged',
  'follow_up': 'flagged',
  'read': null,
  'review': null,
  'archive': null,
  'none': null
};

// Priority Score → Importance
const IMPORTANCE_MAP = {
  high: priority_score >= 80,
  normal: priority_score >= 30,
  low: priority_score < 30
};
```

**Data Flow:**
1. Query `email_interest` WHERE status='proposed' AND NOT EXISTS in action_decisions
2. Join with `emails_ingest` to get Graph API message_id
3. For each decision:
   - Map primary_category → categories array
   - Map recommended_action → flag_status
   - Map priority_score → importance
4. Construct Graph API PATCH payload:
   ```json
   {
     "categories": ["Financial", "Investment"],
     "flag": { "flagStatus": "flagged" },
     "importance": "high"
   }
   ```
5. Call `/me/messages/{id}` PATCH endpoint
6. Insert to `action_decisions` (sync_status='synced', synced_to_outlook_at=NOW())
7. Log to `sync_log` table

**Conflict Resolution:**
- If user modified in Outlook → detect via `lastModifiedDateTime`
- User wins: Set sync_status='user_modified', don't overwrite
- Log to `user_feedback` table for rule refinement

#### Outlook Sync OL Workflow

**Purpose:** Sync user changes in Outlook back to database

**Data Flow:**
1. Fetch messages with lastModifiedDateTime > last_sync
2. Compare Outlook state vs. action_decisions.outlook_state_snapshot
3. Detect changes:
   - Category added/removed
   - Flag changed
   - Moved to different folder
4. Update `user_feedback` table:
   - Store AI vs. User category for ML feedback loop
   - Calculate correction_strength (how different from AI)
5. Update `action_decisions.sync_status` = 'user_modified'

## Database Schema

### Core Tables

#### emails_ingest
**Purpose:** Master table for all email metadata

**Key Columns:**
- `message_id` (PK): Graph API unique ID
- `internet_message_id`: RFC 822 Message-ID header
- `received_datetime`: Timestamp for sorting
- `from_address`, `from_domain`: Sender info
- `subject`, `body_preview`: Content preview
- `needs_body`: Flag if full HTML body needed
- `analyzed_at`: NULL = pending analysis
- `is_deleted`: Soft delete flag

**Indexes:**
- `(message_id)` - PRIMARY KEY
- `(analyzed_at)` WHERE analyzed_at IS NULL - Pending queue
- `(received_datetime DESC)` - Time-based queries

#### email_bodies
**Purpose:** Separate table for large HTML content (normalization)

**Key Columns:**
- `message_id` (PK, FK → emails_ingest)
- `content`: Full HTML body
- `content_type`: 'html' or 'text'
- `size_bytes`: Content length

**Why Separate?**
- emails_ingest queries faster without large TEXT columns
- Body fetched on-demand (not all emails need analysis)
- Easier to purge old bodies while keeping metadata

#### classification_rules
**Purpose:** Static rule patterns extracted from historical data

**Key Columns:**
- `id` (PK): UUID
- `version`: Rule set version (e.g., 'cda_2025-10-15T14-00-00')
- `is_active`: Enable/disable flag
- `scope`: 'address', 'domain', 'header'
- `feature`: 'from_address', 'from_domain', 'message_id_domain', etc.
- `key_value`: Pattern to match
- `target_category`: Output category
- `priority`: Matching order (10=highest)
- `recommended_action`: 'review', 'archive', 'urgent', etc.

**Example Rows:**
```sql
INSERT INTO classification_rules (version, feature, key_value, target_category, priority)
VALUES
  ('cda_2025-10-15', 'from_domain', 'inderes.fi', 'financial_news', 20),
  ('cda_2025-10-15', 'from_address', 'invoice@partner.com', 'business_critical', 10);
```

#### contact_lists
**Purpose:** Dynamic VIP and personal contact management

**Key Columns:**
- `list_type`: 'vip_finance', 'vip_personal', 'personal', 'business_critical', 'internal'
- `identifier_type`: 'from_address', 'from_domain', 'from_address_contains'
- `identifier_value`: Email or domain to match
- `target_category`: Desired category
- `priority`: Matching order (10=highest)

**Use Cases:**
- `vip_finance` domainit → AI päättää tarkan kategorian (financial_news vs. marketing)
- `personal` from_address_contains → personal_communication
- `internal` from_domain → internal

#### email_interest
**Purpose:** AI and rule-based classification decisions

**Key Columns:**
- `message_id` (FK → emails_ingest)
- `model_name`: 'claude', 'rule_engine'
- `model_version`: 'claude-sonnet-4-5-20250929', 'cda_2025-10-15'
- `primary_category`: One of 10 categories
- `confidence`: 0-100%
- `priority_score`: 0-100 (for sorting)
- `recommended_action`: 'none', 'read', 'review', 'follow_up', 'urgent', 'archive'
- `status`: 'proposed', 'accepted', 'void'
- `decided_at`: Decision timestamp

**Unique Constraint:** (message_id, model_name, model_version)
- Allows multiple AI versions to classify same email
- Enables A/B testing of rule sets

#### content_analysis
**Purpose:** Detailed content parsing and entity extraction

**Key Columns:**
- `message_id` (FK → emails_ingest)
- `language`: Detected language (fi, en, sv)
- `word_count`, `sentence_count`: Text metrics
- `topics`: Array of extracted topics
- `persons_mentioned`, `organizations_mentioned`: Named entities
- `sentiment_score`: -1.0 (negative) to 1.0 (positive)
- `business_relevance_score`: 0-100%
- `ai_summary`: 1-2 sentence summary
- `content_structure`: JSONB with structural analysis

#### action_decisions
**Purpose:** Queue for syncing decisions to Outlook

**Key Columns:**
- `message_id` (PK, FK → emails_ingest)
- `attention_tier`: 'A' (high), 'B' (low)
- `outlook_categories`: Array to apply
- `outlook_flag_status`: 'flagged', 'complete', null
- `outlook_importance`: 'high', 'normal', 'low'
- `folder_location`: 'inbox', 'archive', 'trash'
- `sync_status`: 'pending', 'synced', 'failed', 'user_modified'
- `synced_to_outlook_at`: Timestamp of last sync
- `outlook_state_snapshot`: JSONB of Outlook state after sync

#### rules_snapshot
**Purpose:** Cached compiled rules for AI prompt injection

**Key Columns:**
- `version`: Unique identifier (e.g., 'hybrid_2025-10-15_r34')
- `rules_json`: JSONB array of all active rules
- `rules_dsl`: Human-readable DSL text for prompt
- `expires_at`: TTL timestamp (NOW() + 24 hours)
- `is_active`: Only one active snapshot at a time
- `rules_count`, `total_support`, `avg_precision`: Metadata

### Audit & Logging Tables

#### ai_analysis_log
**Purpose:** Complete audit trail of all AI API calls

**Columns:**
- `message_id`: Which email
- `analyzer_version`: 'claude-sonnet-4-5-20250929'
- `analyzed_at`: Timestamp
- `raw_analysis`: Full JSONB response from Claude API

**Retention:** Keep indefinitely for debugging and ML training data

#### process_log
**Purpose:** Workflow execution metrics and errors

**Columns:**
- `workflow_name`: 'delta_validate', 'outlook_sync_db', etc.
- `operation`: 'fetch', 'analyze', 'sync'
- `stage`: Specific node or phase
- `items_processed`, `items_failed`: Counts
- `api_calls_made`: Rate limit tracking
- `duration_ms`: Performance metrics
- `error_message`, `stack_trace`: Debugging

#### sync_log
**Purpose:** Track all sync operations between DB and Outlook

**Columns:**
- `message_id`
- `sync_direction`: 'outlook_to_db', 'db_to_outlook', 'bidirectional'
- `sync_type`: 'category_update', 'folder_move', 'flag_update'
- `sync_status`: 'pending', 'synced', 'failed', 'conflict'
- `outlook_state`: JSONB snapshot before sync
- `db_state`: JSONB snapshot of DB decision
- `changes_made`: JSONB diff

#### user_feedback
**Purpose:** Capture user corrections for ML feedback loop

**Columns:**
- `message_id`
- `ai_attention_tier`, `user_attention_tier`: Comparison
- `ai_categories`, `user_categories`: Difference detection
- `feedback_type`: 'tier_correction', 'category_correction', 'manual_delete', etc.
- `correction_strength`: How different (0-100)

## API Integrations

### Microsoft Graph API

**Base URL:** `https://graph.microsoft.com/v1.0`

**Authentication:** OAuth2 with delegated permissions
- Scopes: `Mail.Read`, `Mail.ReadWrite`, `User.Read`

**Key Endpoints:**

1. **Delta Sync (Incremental Fetch)**
   ```
   GET /me/mailFolders/{folderId}/messages/delta
   Query params:
     - $select: id,subject,from,receivedDateTime,hasAttachments,categories,flag,importance
     - $top: 100
   Response:
     - value[]: Array of messages
     - @odata.nextLink: Pagination token
     - @odata.deltaLink: Checkpoint for next sync
   ```

2. **Fetch Message Body**
   ```
   GET /me/messages/{id}?$select=body
   Response:
     - body.contentType: "html" or "text"
     - body.content: Full HTML/text content
   ```

3. **Update Message Properties**
   ```
   PATCH /me/messages/{id}
   Body:
     {
       "categories": ["Business Critical", "Action Required"],
       "flag": { "flagStatus": "flagged" },
       "importance": "high"
     }
   ```

4. **Move Message to Folder**
   ```
   POST /me/messages/{id}/move
   Body: { "destinationId": "{folderId}" }
   ```

**Rate Limits:**
- 10,000 API requests per 10 minutes per user
- Retry-After header on 429 responses
- Implemented in n8n: Exponential backoff with jitter

### Anthropic Claude API

**Base URL:** `https://api.anthropic.com/v1`

**Authentication:** API Key in `x-api-key` header

**Prompt Caching Endpoint:**
```
POST /messages
Headers:
  anthropic-version: 2023-06-01
  anthropic-beta: prompt-caching-2024-07-31
  content-type: application/json
Body:
  {
    "model": "claude-sonnet-4-5-20250929",
    "max_tokens": 30000,
    "system": [
      {
        "type": "text",
        "text": "SYSTEM_PROMPT_WITH_RULES",
        "cache_control": { "type": "ephemeral" }  // ← Cache this!
      }
    ],
    "messages": [
      { "role": "user", "content": "USER_PROMPT_WITH_EMAILS" }
    ]
  }
Response:
  {
    "id": "msg_...",
    "content": [{ "type": "text", "text": "[JSON_ARRAY_RESPONSE]" }],
    "usage": {
      "input_tokens": 15234,
      "cache_creation_input_tokens": 12000,  // First time
      "cache_read_input_tokens": 12000,      // Subsequent calls
      "output_tokens": 3421
    }
  }
```

**Cost Optimization:**
- Cache hit: 90% cost reduction on system prompt tokens
- Rules snapshot TTL: 24h (balance freshness vs. cache hit rate)
- Batch processing: 2-4 emails per API call (configurable)

**Token Limits:**
- Input: 200,000 tokens (model limit)
- Output: 30,000 tokens (our configuration)
- Body truncation: MAX_BODY_CHARS=100,000 characters ≈ 25,000 tokens

## Data Flow Diagrams

### Email Processing Pipeline

```
┌─────────────────────────────────────────────────────────────────────┐
│ PHASE 1: INGESTION (Every 10 min)                                   │
└─────────────────────────────────────────────────────────────────────┘
  Outlook Delta API
         │
         │ Delta sync (new/changed messages)
         ▼
  emails_ingest (needs_body=TRUE, analyzed_at=NULL)
         │
         │
┌────────┴─────────────────────────────────────────────────────────────┐
│ PHASE 2: BODY FETCH (On-demand)                                      │
└───────────────────────────────────────────────────────────────────────┘
  Validate Select: IF needs_body AND !body_content
         │
         │ Call: Outlook Body Fetch workflow
         ▼
  Graph API: /messages/{id}?$select=body
         │
         ▼
  email_bodies (content=HTML)
         │
         │ Update: emails_ingest.needs_body=FALSE
         │
┌────────┴─────────────────────────────────────────────────────────────┐
│ PHASE 3: PREPROCESSING (Per batch)                                   │
└───────────────────────────────────────────────────────────────────────┘
  pre_ai_guard node
         │
         ├─ HTML → plain text (strip tags)
         ├─ Decode SafeLinks (URL unwrapping)
         ├─ Normalize whitespace (\\r\\n, tabs, zero-width chars)
         ├─ Truncate to MAX_BODY_CHARS (smart: paragraph > sentence > hard cut)
         └─ Calculate body_hash (SHA256)
         │
         ▼
  body_text (sanitized, ready for AI)
         │
┌────────┴─────────────────────────────────────────────────────────────┐
│ PHASE 4: RULE LOADING (Cache check)                                  │
└───────────────────────────────────────────────────────────────────────┘
  get_rules_snapshot
         │
         ├─ IF cache valid (expires_at > NOW())
         │  └─ Use cached rules_dsl
         │
         └─ ELSE: Build new snapshot
            │
            ├─ Load: classification_rules (is_active=TRUE)
            ├─ Load: classification_rule_metrics (latest)
            ├─ Sort: priority ASC, support DESC
            ├─ Generate DSL:
            │  "JOS from_domain='inderes.fi' → financial_news (KORKEA, 1097 osumaa)"
            ├─ Version: hybrid_YYYY-MM-DD_rN
            └─ Save: rules_snapshot (TTL=24h)
         │
         ▼
  rules_version, rules_dsl
         │
┌────────┴─────────────────────────────────────────────────────────────┐
│ PHASE 5: AI ANALYSIS (Batch call)                                    │
└───────────────────────────────────────────────────────────────────────┘
  build_batch_prompt_cache
         │
         ├─ Construct system prompt:
         │  ├─ Base: "Olet rahoitus-asiantuntija..."
         │  ├─ Inject: rules_dsl (from snapshot)
         │  └─ Categories: 10 category definitions
         │
         ├─ Construct user prompt:
         │  └─ JSON array of emails: [{ message_id, subject, from, text }]
         │
         ▼
  ai_classify_emails_cache (HTTP Request node)
         │
         │ POST /v1/messages
         │ Cache system prompt (ephemeral)
         │
         ▼
  Claude API Response
         │
         │ [
         │   { message_id, classification, content_analysis, decision },
         │   { message_id, classification, content_analysis, decision }
         │ ]
         │
┌────────┴─────────────────────────────────────────────────────────────┐
│ PHASE 6: RESULT PARSING & STORAGE                                    │
└───────────────────────────────────────────────────────────────────────┘
  parse_ai_json_cache
         │
         ├─ Extract JSON array from AI text response
         ├─ Handle truncated responses (find longest valid JSON)
         ├─ Generate placeholders for missing emails
         │
         ▼
  build_log_ai_cache
         │
         ├─ Split each result into 3 objects:
         │  ├─ ca: content_analysis fields
         │  ├─ ei: email_interest fields
         │  └─ log: ai_analysis_log fields
         │
         ▼
  Parallel inserts:
         │
         ├─ upsert_content_analysis
         │  └─ INSERT ON CONFLICT (message_id) DO UPDATE
         │
         ├─ upsert_email_interest
         │  └─ INSERT ON CONFLICT (message_id, model_name, model_version) DO UPDATE
         │
         ├─ insert_ai_analysis_log
         │  └─ INSERT (no conflict, append-only log)
         │
         └─ mark_analyzed
            └─ UPDATE emails_ingest SET analyzed_at=NOW()
         │
┌────────┴─────────────────────────────────────────────────────────────┐
│ PHASE 7: SYNC TO OUTLOOK (Every 15 min)                              │
└───────────────────────────────────────────────────────────────────────┘
  Outlook Sync DB workflow
         │
         │ SELECT email_interest WHERE status='proposed'
         │
         ▼
  Map to Outlook actions:
         │
         ├─ primary_category → categories array
         ├─ recommended_action → flag_status
         ├─ priority_score → importance
         │
         ▼
  PATCH /me/messages/{id}
         │
         │ Apply: categories, flag, importance
         │
         ▼
  action_decisions (sync_status='synced', synced_to_outlook_at=NOW())
         │
         └─ Store outlook_state_snapshot (JSONB)
```

### Rule Discovery & Evolution

```
┌─────────────────────────────────────────────────────────────────────┐
│ Weekly: Category Discovery Analysis Workflow                        │
└─────────────────────────────────────────────────────────────────────┘
  1. Analyze historical email_interest data
         │
         ├─ Group by: from_domain, from_address, message_id_domain
         ├─ Calculate metrics:
         │  ├─ support: COUNT(DISTINCT message_id)
         │  ├─ precision_cat_pct: % same category
         │  └─ avg_relevance_pct: AVG(confidence)
         │
         ▼
  2. Filter candidates:
         │
         ├─ support >= 5 (minimum occurrences)
         ├─ precision_cat_pct >= 80% (consistency threshold)
         └─ NOT EXISTS in classification_rules (new patterns only)
         │
         ▼
  3. Generate INSERT statements:
         │
         │ INSERT INTO classification_rules
         │   (version, feature, key_value, target_category, priority)
         │ VALUES
         │   ('cda_2025-10-22', 'from_domain', 'new-sender.com', 'financial_news', 30);
         │
         ▼
  4. Review & execute SQL (manual approval)
         │
         ▼
  5. Invalidate rules_snapshot
         │
         │ UPDATE rules_snapshot SET is_active=FALSE WHERE is_active=TRUE;
         │
         ▼
  6. Next AI batch will rebuild snapshot with new rules
```

## Security & Compliance

### Authentication
- **Microsoft Graph**: OAuth2 delegated permissions (no app-only, user consent required)
- **Database**: SSL/TLS encrypted connections, credential rotation every 90 days
- **Anthropic API**: API key stored in n8n credentials vault

### Data Privacy
- **Email Content**: Stored in EU region PostgreSQL (GDPR compliant)
- **Retention Policy**:
  - emails_ingest: Keep metadata indefinitely (business records)
  - email_bodies: Purge after 90 days (EXECUTE `DELETE FROM email_bodies WHERE created_at < NOW() - INTERVAL '90 days'`)
  - ai_analysis_log: Keep 1 year for audit (anonymize after)
- **PII Handling**: Entity extraction includes persons_mentioned, but no PII stored outside encrypted DB

### Access Control
- **Database**: Row-level security (RLS) by user_upn if multi-tenant
- **n8n Workflows**: Execution permissions restricted to admin role
- **API Keys**: Stored in n8n encrypted credentials, never in workflow JSON

## Monitoring & Observability

### Key Metrics

**Email Processing:**
```sql
-- Unprocessed queue size
SELECT COUNT(*) FROM outlook.emails_ingest WHERE analyzed_at IS NULL;

-- Processing rate (emails/hour)
SELECT
  DATE_TRUNC('hour', analyzed_at) as hour,
  COUNT(*) as processed
FROM outlook.emails_ingest
WHERE analyzed_at >= NOW() - INTERVAL '24 hours'
GROUP BY 1 ORDER BY 1 DESC;

-- Category distribution
SELECT primary_category, COUNT(*), AVG(confidence)
FROM outlook.email_interest
WHERE decided_at >= NOW() - INTERVAL '7 days'
GROUP BY 1 ORDER BY 2 DESC;
```

**AI Performance:**
```sql
-- Average latency per batch
SELECT
  AVG(duration_ms) as avg_ms,
  AVG(items_processed) as avg_batch_size
FROM outlook.process_log
WHERE operation = 'ai_classify'
  AND created_at >= NOW() - INTERVAL '7 days';

-- Prompt cache hit rate
SELECT
  detail->>'usage'->>'cache_read_input_tokens' as cache_hit_tokens,
  detail->>'usage'->>'input_tokens' as total_tokens,
  ROUND(100.0 * (detail->>'usage'->>'cache_read_input_tokens')::float / (detail->>'usage'->>'input_tokens')::float, 2) as cache_hit_rate
FROM outlook.process_log
WHERE operation = 'ai_classify'
ORDER BY created_at DESC LIMIT 10;
```

**Sync Health:**
```sql
-- Sync queue backlog
SELECT COUNT(*) FROM outlook.action_decisions WHERE sync_status = 'pending';

-- Sync failure rate
SELECT
  sync_status,
  COUNT(*) as count,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) as pct
FROM outlook.action_decisions
GROUP BY 1;

-- User corrections (feedback loop)
SELECT COUNT(*) as corrections
FROM outlook.user_feedback
WHERE created_at >= NOW() - INTERVAL '7 days';
```

### Alerts & Thresholds

**Set up alerts for:**
1. **Unprocessed queue > 100 emails** → Check if Validate Select workflow is running
2. **Sync failures > 10%** → Check Microsoft Graph API token expiry
3. **AI error rate > 5%** → Check Anthropic API key and rate limits
4. **Cache hit rate < 50%** → Check rules_snapshot TTL and invalidation logic
5. **Processing latency > 10s per email** → Check database indexes and API response times

**Implementation:** Use PostgreSQL triggers or external monitoring (e.g., Grafana + Prometheus)
