# Coding Conventions & Best Practices

## General Principles

### Code Philosophy
- **Explicit over implicit**: Prefer clear, verbose code over clever shortcuts
- **Fail fast**: Validate inputs early and throw descriptive errors
- **Idempotency**: All workflows should be safe to run multiple times
- **Auditability**: Log all significant operations to database tables

### Language Usage
- **Finnish**: Business logic documentation, AI prompts, category names
- **English**: Code comments, variable names, technical documentation
- **Mixed context**: This is intentional for financial domain in Finnish market

## n8n Workflow Standards

### Workflow Naming

**Pattern:** `<System> <Verb> <Object>`

Examples:
- `Outlook Emails Fetch` - Fetches emails from Outlook
- `Outlook Validate Select` - Selects emails for validation
- `Outlook Sync DB` - Syncs database to Outlook

**Avoid:**
- Generic names: `Process Data`, `Main Workflow`
- Abbreviations without context: `OL_VAL_SEL`
- Version suffixes in name: `Fetch v2` (use description field instead)

### Node Naming

**Best Practices:**
1. **Use snake_case for all node names** (lowercase with underscores)
   - Good: `fetch_delta_messages`, `upsert_email_interest`
   - Bad: `FetchDeltaMessages`, `Upsert-Email-Interest`

2. **Use verb prefixes** to indicate action:
   - `get_`: Read from database or API (no modification)
   - `load_`: Read multiple items or complex query
   - `fetch_`: Retrieve from external API
   - `upsert_`: Insert or update database record
   - `insert_`: Create new database record only
   - `update_`: Modify existing database record
   - `mark_`: Update a status flag
   - `build_`: Construct data structure or payload
   - `parse_`: Extract/transform data from response
   - `validate_`: Check conditions/constraints
   - `check_`: Boolean condition evaluation

3. **Descriptive suffixes** for clarity:
   - Database nodes: `_from_db`, `_to_db`
   - API calls: `_api`, `_graph`, `_claude`
   - Transformations: `_to_json`, `_normalize`

4. **Add "Notes" to complex nodes:**
   - Right-click node → Add Note
   - Explain WHY, not WHAT (code shows what)
   - Document tricky business logic or workarounds

### Node Configuration

**JavaScript Code Nodes:**

```javascript
// GOOD: Clear function with input validation
function sanitizeText(s) {
  if (s == null) return '';
  let t = String(s);
  t = t.replace(/\uFEFF/g, '');  // Remove BOM
  t = t.replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/g, '');  // Control chars
  return t.trim();
}

return items.map(item => {
  const subject = sanitizeText(item.json.subject);
  const body = sanitizeText(item.json.body_text);

  return {
    json: {
      message_id: item.json.message_id,
      subject: subject,
      body: body
    }
  };
});

// BAD: Unclear, no validation
return items.map(i => ({
  json: {
    m: i.json.mid,
    s: String(i.json.subj || '').trim(),
    b: i.json.txt
  }
}));
```

**Key Rules:**
1. Always validate required fields exist before accessing
2. Use descriptive variable names (no single-letter except iterators)
3. Handle null/undefined with defaults or early returns
4. Add comments for non-obvious logic
5. Prefer Array.map() over for loops for transformations
6. Use const/let, never var

**PostgreSQL Nodes:**

```sql
-- GOOD: Parameterized query with clear structure
WITH picked AS (
  SELECT
    e.message_id,
    e.subject,
    e.from_address,
    e.received_datetime
  FROM outlook.emails_ingest e
  WHERE e.analyzed_at IS NULL
    AND COALESCE(e.is_deleted, false) = false
  ORDER BY e.received_datetime DESC
  LIMIT $1 OFFSET $2
  FOR UPDATE SKIP LOCKED
)
SELECT * FROM picked;

-- Query Replacement:
-- {{ [ $json.limit || 100, $json.offset || 0 ] }}
```

**Key Rules:**
1. Use CTEs (WITH clauses) for complex queries (improves readability)
2. Always use parameterized queries ($1, $2) never string interpolation
3. Add WHERE clauses for is_deleted=false (soft delete support)
4. Use COALESCE() for nullable boolean columns
5. Add FOR UPDATE SKIP LOCKED for queue-like patterns
6. Indent nested queries consistently (2 spaces)
7. Comment non-obvious JOINs or WHERE conditions

**HTTP Request Nodes (API Calls):**

```json
{
  "method": "POST",
  "url": "https://api.anthropic.com/v1/messages",
  "authentication": "predefinedCredentialType",
  "nodeCredentialType": "anthropicApi",
  "sendHeaders": true,
  "headerParameters": {
    "parameters": [
      {
        "name": "anthropic-version",
        "value": "2023-06-01"
      },
      {
        "name": "anthropic-beta",
        "value": "prompt-caching-2024-07-31"
      }
    ]
  },
  "sendBody": true,
  "specifyBody": "json",
  "jsonBody": "={{ { \"model\": \"claude-sonnet-4-5-20250929\", \"max_tokens\": 30000, \"system\": $json.system, \"messages\": $json.messages } }}",
  "options": {
    "response": {
      "response": {
        "responseFormat": "json"
      }
    }
  }
}
```

**Key Rules:**
1. Always set `responseFormat: "json"` for JSON APIs
2. Use credential manager, never hardcode API keys
3. Add all required headers explicitly
4. Use expression syntax (={{...}}) for dynamic values
5. Enable "Continue on Error" for non-critical API calls
6. Add retry logic in n8n settings (3 retries, exponential backoff)

### Workflow Error Handling

**Pattern 1: Error Branch**

```
┌──────────────┐
│ Risky Node   │
└──────┬───────┘
       │ Success
       ├────────────────────┐
       │                    │ Error
       ▼                    ▼
┌──────────────┐   ┌────────────────┐
│ Process OK   │   │ Handle Error   │
└──────────────┘   └────────┬───────┘
                            │
                            ▼
                   ┌────────────────┐
                   │ Mark Failed    │
                   │ Log to DB      │
                   └────────────────┘
```

**Implementation:**
- Set node option: "Continue On Fail" = true
- Add IF node after: `{{ $json.error }}` exists?
- Error branch should always log to `process_log` table

**Pattern 2: Try-Catch in Code**

```javascript
return items.map(item => {
  try {
    const result = complexOperation(item.json);
    return {
      json: {
        ...result,
        status: 'success'
      }
    };
  } catch (error) {
    return {
      json: {
        message_id: item.json.message_id,
        status: 'error',
        error_message: error.message,
        stack_trace: error.stack
      }
    };
  }
});
```

### Configuration Management

**Use Set node for configuration:**

```javascript
// Node name: set_config
{
  "batch": 2,                    // Number of batches to split
  "limit": 4,                    // Items per batch
  "MAX_BODY_CHARS": 100000,      // Body truncation limit
  "user_upn": "user@domain.com", // Primary user
  "TRIM_LEADING_TRAILING_LINES": 0
}
```

**Access in downstream nodes:**
```javascript
const cfg = $node['set_config']?.json || {};
const maxChars = Number(cfg.MAX_BODY_CHARS ?? 12000);
const upn = cfg.user_upn || $env.USER_UPN || null;
```

**Benefits:**
- Single source of truth for configuration
- Easy to change without editing code
- Can be overridden per execution
- Self-documenting workflow parameters

## JavaScript Code Standards

### Function Naming

```javascript
// GOOD: Clear, descriptive names
function sanitizeText(s) { ... }
function pickMinimalInputFields(x) { ... }
function buildDslFromRules(rules) { ... }

// BAD: Unclear abbreviations
function san(s) { ... }
function pick(x) { ... }
function build(r) { ... }
```

### Error Messages

```javascript
// GOOD: Contextual, actionable error
if (!json?.message_id) {
  throw new Error('build_log_ai: message_id puuttuu inputista. Tarkista parse_ai_json output.');
}

// BAD: Generic, unhelpful error
if (!json?.message_id) {
  throw new Error('Missing field');
}
```

### Data Validation

```javascript
// GOOD: Defensive validation with fallbacks
function getAiText(json) {
  if (!json) return null;

  // Check multiple possible locations
  if (json.content && Array.isArray(json.content) && json.content[0]?.text) {
    return json.content[0].text;
  }
  if (typeof json === 'string') return json;
  if (json.text) return json.text;

  return null;
}

// Usage with fallback
const rawIn = getAiText(aiOutput) || '';
if (!rawIn) {
  console.error('AI returned empty response');
  return createErrorPlaceholder(item.message_id, 'Empty AI response');
}

// BAD: Assumes structure exists
const rawIn = json.content[0].text;  // Crashes if any part is undefined
```

### Constants and Magic Numbers

```javascript
// GOOD: Named constants
const DEFAULT_CONFIDENCE = 0;
const MAX_CONFIDENCE = 100;
const DEFAULT_TTL_HOURS = 24;
const HIGH_PRIORITY_THRESHOLD = 80;

if (confidence < 0 || confidence > MAX_CONFIDENCE) {
  confidence = Math.max(0, Math.min(MAX_CONFIDENCE, confidence));
}

// BAD: Magic numbers
if (confidence < 0 || confidence > 100) {
  confidence = Math.max(0, Math.min(100, confidence));
}
```

### Array Operations

```javascript
// GOOD: Functional style with map/filter/reduce
const validItems = items
  .filter(item => item.json?.message_id)
  .map(item => ({
    message_id: item.json.message_id,
    subject: sanitizeText(item.json.subject)
  }));

// BAD: Imperative loops with mutations
const validItems = [];
for (let i = 0; i < items.length; i++) {
  if (items[i].json && items[i].json.message_id) {
    const obj = {};
    obj.message_id = items[i].json.message_id;
    obj.subject = sanitizeText(items[i].json.subject);
    validItems.push(obj);
  }
}
```

### Logging & Debugging

```javascript
// GOOD: Structured logging with context
console.log('Rules loaded:', {
  version: rulesData.version,
  from_cache: rulesData.from_cache,
  count: rulesData.rules?.length || 0,
  expires_at: rulesData.expires_at
});

// BAD: Unstructured string concatenation
console.log('Rules: ' + rulesData.version + ' count=' + rulesData.rules.length);
```

## SQL Conventions

### Schema Naming

**Tables:** `lowercase_with_underscores`
- Good: `emails_ingest`, `classification_rules`, `action_decisions`
- Bad: `EmailsIngest`, `classificationRules`, `ActionDecisions`

**Columns:** `lowercase_with_underscores`
- Good: `message_id`, `from_address`, `received_datetime`
- Bad: `messageId`, `fromAddress`, `receivedDateTime`

**Constraints:** `{table}_{columns}_{type}`
- Examples:
  - `emails_ingest_pkey` (PRIMARY KEY)
  - `email_interest_message_id_fkey` (FOREIGN KEY)
  - `action_decisions_attention_tier_check` (CHECK)

### Query Structure

```sql
-- GOOD: Clear structure with CTEs and formatting
WITH recent_emails AS (
  SELECT
    e.message_id,
    e.subject,
    e.from_address,
    e.received_datetime
  FROM outlook.emails_ingest e
  WHERE e.analyzed_at IS NULL
    AND COALESCE(e.is_deleted, false) = false
  ORDER BY e.received_datetime DESC
  LIMIT 100
),
classifications AS (
  SELECT
    ei.message_id,
    ei.primary_category,
    ei.confidence
  FROM outlook.email_interest ei
  WHERE ei.status = 'proposed'
)
SELECT
  re.*,
  c.primary_category,
  c.confidence
FROM recent_emails re
LEFT JOIN classifications c ON c.message_id = re.message_id;

-- BAD: Unreadable inline query
SELECT e.message_id,e.subject,e.from_address,ei.primary_category FROM outlook.emails_ingest e LEFT JOIN outlook.email_interest ei ON ei.message_id=e.message_id WHERE e.analyzed_at IS NULL AND e.is_deleted=false ORDER BY e.received_datetime DESC LIMIT 100;
```

### INSERT/UPDATE Patterns

**Upsert (INSERT ON CONFLICT):**

```sql
-- GOOD: Explicit conflict handling with conditional update
INSERT INTO outlook.email_interest (
  message_id,
  model_name,
  model_version,
  primary_category,
  confidence,
  decided_at
)
VALUES ($1, $2, $3, $4, $5, $6::timestamptz)
ON CONFLICT (message_id, model_name, model_version) DO UPDATE SET
  primary_category = EXCLUDED.primary_category,
  confidence = EXCLUDED.confidence,
  decided_at = EXCLUDED.decided_at
WHERE
  -- Only update if newer or higher confidence
  (email_interest.decided_at IS NULL OR EXCLUDED.decided_at > email_interest.decided_at)
  AND (email_interest.confidence IS NULL OR EXCLUDED.confidence >= email_interest.confidence);
```

**Soft Delete:**

```sql
-- GOOD: Soft delete with timestamp
UPDATE outlook.emails_ingest
SET
  is_deleted = TRUE,
  deleted_at = NOW()
WHERE message_id = $1;

-- All queries include: WHERE COALESCE(is_deleted, false) = false
```

### Indexing Guidelines

**Create indexes for:**
1. Foreign key columns: `message_id` in child tables
2. Frequently filtered columns: `analyzed_at IS NULL`, `sync_status = 'pending'`
3. Sort columns: `received_datetime DESC`
4. Partial indexes for hot queries:
   ```sql
   CREATE INDEX idx_emails_unprocessed
   ON outlook.emails_ingest (received_datetime DESC)
   WHERE analyzed_at IS NULL AND COALESCE(is_deleted, false) = false;
   ```

**Avoid over-indexing:**
- Don't index low-cardinality columns (e.g., boolean flags) unless used in WHERE heavily
- Don't create composite indexes unless query uses ALL prefix columns

### Transaction Management

```sql
-- GOOD: Explicit transaction boundaries for multi-step operations
BEGIN;

-- Step 1: Reserve emails for processing
WITH picked AS (
  UPDATE outlook.emails_ingest
  SET auto_processed = true
  WHERE message_id IN (
    SELECT message_id FROM outlook.emails_ingest
    WHERE analyzed_at IS NULL
    LIMIT 10
    FOR UPDATE SKIP LOCKED
  )
  RETURNING *
)
-- Step 2: Create processing record
INSERT INTO outlook.process_log (workflow_name, operation, items_processed)
SELECT 'validate_analyse', 'select', COUNT(*) FROM picked;

COMMIT;
```

## Python Script Standards

### Script Header

```python
#!/usr/bin/env python3
"""
read_doc.py - Extract text content from DOCX files

Usage:
  python read_doc.py <filename.docx>

Dependencies:
  - python-docx
"""
import sys
from docx import Document

# Set UTF-8 encoding for stdout
sys.stdout.reconfigure(encoding='utf-8')
```

### Error Handling

```python
# GOOD: Explicit error messages
try:
    doc = Document(filename)
except FileNotFoundError:
    print(f"Error: File '{filename}' not found", file=sys.stderr)
    sys.exit(1)
except Exception as e:
    print(f"Error reading document: {e}", file=sys.stderr)
    sys.exit(1)

# BAD: Silent failure or generic error
try:
    doc = Document(filename)
except:
    pass
```

### Output Formatting

```python
# GOOD: Clean output (empty lines between paragraphs)
for para in doc.paragraphs:
    text = para.text.strip()
    if text:
        print(text)
        print()  # Empty line separator

# BAD: No separation, hard to read
for para in doc.paragraphs:
    print(para.text)
```

## Git Commit Conventions

### Commit Message Format

```
<type>(<scope>): <subject>

<body>

<footer>
```

**Types:**
- `feat`: New feature (e.g., `feat(workflow): add prompt caching support`)
- `fix`: Bug fix (e.g., `fix(sql): correct soft delete WHERE clause`)
- `refactor`: Code restructuring without behavior change
- `docs`: Documentation updates
- `chore`: Maintenance tasks (dependencies, config)
- `test`: Test additions or corrections
- `perf`: Performance improvements

**Scopes:**
- `workflow`: n8n workflow changes
- `sql`: Database schema or query changes
- `script`: Python/JS utility scripts
- `docs`: Documentation files
- `config`: Configuration files

**Examples:**

```
feat(workflow): implement hybrid rules system with prompt caching

- Add rules_snapshot table for caching compiled rules
- Modify Validate Analyse to check cache before building rules
- Add DSL generation for AI prompt injection
- Track rules version in email_interest for auditability

Closes #42
```

```
fix(sql): handle null values in confidence scoring

Previous query crashed when confidence was NULL. Added COALESCE
with default value of 0 to prevent NULL propagation.

Affected queries:
- email_interest upsert
- classification_rule_metrics calculation
```

### Branch Naming

**Pattern:** `<type>/<short-description>`

Examples:
- `feat/contact-lists-implementation`
- `fix/body-fetch-timeout`
- `refactor/prompt-builder-cleanup`
- `docs/architecture-diagrams`

### .gitignore Best Practices

```gitignore
# Credentials and secrets
.env
credentials.json
*.key

# n8n exports with credentials (always export without!)
*_with_credentials.json

# Database dumps
*.sql.gz
*.dump

# OS files
.DS_Store
Thumbs.db

# Editor files
.vscode/
.idea/
*.swp

# Logs
logs/
*.log

# Python
__pycache__/
*.pyc
venv/
```

## Security Best Practices

### Credentials Management

**NEVER:**
- Hardcode API keys in workflow JSON
- Commit `.env` files to git
- Share database passwords in documentation
- Include credentials in error messages or logs

**ALWAYS:**
- Use n8n credential manager for all secrets
- Rotate credentials every 90 days
- Use separate credentials for dev/staging/production
- Enable 2FA on all service accounts

### SQL Injection Prevention

```javascript
// GOOD: Parameterized query
const query = `
  SELECT * FROM outlook.emails_ingest
  WHERE from_address = $1 AND received_datetime > $2;
`;
const params = [emailAddress, startDate];

// BAD: String interpolation (SQL injection risk!)
const query = `
  SELECT * FROM outlook.emails_ingest
  WHERE from_address = '${emailAddress}' AND received_datetime > '${startDate}';
`;
```

### Data Sanitization

```javascript
// GOOD: Sanitize before AI prompt injection
function sanitizeForPrompt(text) {
  if (!text) return '';

  // Remove control characters
  let cleaned = text.replace(/[\u0000-\u001F\u007F-\u009F]/g, '');

  // Escape potential prompt injection attempts
  cleaned = cleaned.replace(/\[INST\]/gi, '[BLOCKED]');
  cleaned = cleaned.replace(/\<\|system\|\>/gi, '[BLOCKED]');

  // Truncate to reasonable length
  if (cleaned.length > 100000) {
    cleaned = cleaned.substring(0, 100000) + '... [TRUNCATED]';
  }

  return cleaned;
}
```

### API Rate Limiting

```javascript
// GOOD: Implement backoff on rate limit errors
try {
  const response = await callGraphApi(endpoint);
  return response;
} catch (error) {
  if (error.statusCode === 429) {
    const retryAfter = parseInt(error.headers['retry-after']) || 60;
    console.log(`Rate limited. Waiting ${retryAfter}s before retry.`);
    await sleep(retryAfter * 1000);
    return await callGraphApi(endpoint);  // Retry once
  }
  throw error;
}
```

## Testing Guidelines

### Manual Testing Checklist

**Before Committing Workflow Changes:**
1. Test with 1 email (validate logic)
2. Test with batch of 5 emails (validate batching)
3. Test with empty result set (validate error handling)
4. Check all database inserts successful
5. Verify no credentials leaked in workflow JSON export

**SQL Testing:**
```sql
-- Always test with LIMIT first
SELECT * FROM outlook.emails_ingest LIMIT 1;

-- Then run actual query
SELECT COUNT(*) FROM outlook.emails_ingest WHERE ...;

-- For updates, wrap in transaction and ROLLBACK for testing
BEGIN;
UPDATE outlook.emails_ingest SET analyzed_at = NOW() WHERE message_id = 'test-id';
SELECT * FROM outlook.emails_ingest WHERE message_id = 'test-id';
ROLLBACK;  -- Undo changes
```

### Validation Queries

**After Workflow Execution:**

```sql
-- Verify processing completed
SELECT
  COUNT(*) as total,
  COUNT(*) FILTER (WHERE analyzed_at IS NOT NULL) as analyzed,
  COUNT(*) FILTER (WHERE analyzed_at IS NULL) as pending
FROM outlook.emails_ingest;

-- Check for errors
SELECT * FROM outlook.process_log
WHERE error_message IS NOT NULL
ORDER BY created_at DESC LIMIT 5;

-- Validate sync status
SELECT sync_status, COUNT(*)
FROM outlook.action_decisions
GROUP BY sync_status;
```

## Performance Optimization

### Batch Processing

```javascript
// GOOD: Process items in configurable batches
const BATCH_SIZE = cfg.batch_size || 10;
const batches = [];

for (let i = 0; i < items.length; i += BATCH_SIZE) {
  batches.push(items.slice(i, i + BATCH_SIZE));
}

// Process each batch
for (const batch of batches) {
  await processBatch(batch);
}

// BAD: Process all items at once (memory issues with large datasets)
const results = await processAll(items);
```

### Database Query Optimization

```sql
-- GOOD: Use indexes and limit results
SELECT e.message_id, e.subject
FROM outlook.emails_ingest e
WHERE e.analyzed_at IS NULL
  AND e.received_datetime > NOW() - INTERVAL '7 days'
ORDER BY e.received_datetime DESC
LIMIT 100;

-- BAD: Full table scan without limits
SELECT * FROM outlook.emails_ingest
WHERE analyzed_at IS NULL;
```

### API Call Optimization

```javascript
// GOOD: Parallel API calls with limit
const MAX_CONCURRENT = 5;
const chunks = chunkArray(items, MAX_CONCURRENT);

for (const chunk of chunks) {
  await Promise.all(chunk.map(item => fetchBody(item)));
}

// BAD: Sequential API calls (slow)
for (const item of items) {
  await fetchBody(item);
}
```

## Documentation Standards

### Code Comments

```javascript
// GOOD: Explain WHY, not WHAT
// Parse longest valid JSON array because AI sometimes returns
// partial arrays when hitting token limits. We want to recover
// as many results as possible rather than failing the entire batch.
const arr = findLongestValidArray(cleaned);

// BAD: Redundant comment that repeats the code
// Find longest valid array
const arr = findLongestValidArray(cleaned);
```

### Workflow Documentation

**Each workflow should have:**
1. **Description field**: One-sentence summary of purpose
2. **Tags**: Categorization (e.g., `ingestion`, `analysis`, `sync`)
3. **README note** (first node):
   ```
   WORKFLOW: Outlook Validate Analyse
   PURPOSE: AI-powered email classification with prompt caching
   TRIGGER: Called by Outlook Validate Select
   INPUT: batch_items array with email data
   OUTPUT: Classifications written to email_interest table
   DEPENDENCIES: PostgreSQL, Anthropic API
   ```

### SQL Script Headers

```sql
-- ==========================================
-- CLASSIFICATION_RULES - LOPULLISET SÄÄNNÖT
-- Perustuu SQL-analyysiin ja päätöksiin 2025-10-15
-- ==========================================

-- HUOM: Nämä säännöt täydentävät contact_lists-taulua
-- contact_lists = dynaamisesti ylläpidettävä (VIP, personal, internal)
-- classification_rules = staattinen sääntöpohja (louhittu datasta)

-- Version timestamp - PÄIVITÄ tämä!
DO $$
DECLARE
  v_version TEXT := 'cda_2025-10-15T14-00-00';
BEGIN
  RAISE NOTICE 'Inserting rules with version: %', v_version;
END $$;
```

## Naming Patterns Reference

### Categories (Primary Classification)

**Standard Set (Use exactly these strings):**
1. `business_critical` - Sopimukset, laskut, kriittiset kumppanit
2. `personal_communication` - Henkilökohtainen 1:1 viestintä
3. `financial_news` - Sijoitusuutiset, analyysit, pörssitiedot
4. `marketing` - Mainokset, kampanjat, myyntiviestit
5. `notifications` - Järjestelmäilmoitukset, vahvistukset
6. `industry_news` - Toimiala-uutiset (ei rahoitus)
7. `internal` - Oma organisaation viestit
8. `regulatory` - Viranomaisviestit, säädökset
9. `spam_low_value` - Roskaposti, ei-relevantti
10. `uncategorized` - Epäselvät tapaukset

### Actions (Recommended Action)

**Standard Set:**
- `none` - Ei toimenpiteitä
- `read` - Lue kun ehdit
- `review` - Tarkista sisältö
- `follow_up` - Vaatii seurantaa
- `urgent` - Välitön toimenpide
- `archive` - Arkistoi suoraan
- `calendar_consider` - Harkitse kalenterimerkintää

### Database Prefixes

**Table Prefixes:**
- No prefix: Core domain tables (`emails_ingest`, `action_decisions`)
- `_log` suffix: Audit tables (`ai_analysis_log`, `process_log`, `sync_log`)
- `_state` suffix: State tracking (`delta_state`)
- `_cache` suffix: Caching tables (`folders_cache`)
- `_snapshot` suffix: Versioned caches (`rules_snapshot`)

**Column Suffixes:**
- `_at`: Timestamps (`analyzed_at`, `created_at`, `synced_to_outlook_at`)
- `_id`: Foreign keys or identifiers (`message_id`, `rule_id`)
- `_count`: Numeric counts (`word_count`, `rules_count`)
- `_pct`: Percentages as integers (`precision_cat_pct`, `avg_relevance_pct`)
- `_score`: Normalized scores 0-100 (`confidence_score`, `priority_score`)
- `_status`: Status enums (`sync_status`, `processing_status`)
- `_datetime`: Full datetime fields from Graph API (`received_datetime`)
- `_upn`: User Principal Name (email address) (`user_upn`)

## Version Control Best Practices

### Workflow Export Guidelines

**Before Exporting:**
1. Remove all pinData (test data)
2. Clear execution history
3. Export WITHOUT credentials (uncheck "Include credentials")
4. Verify JSON has no sensitive data:
   ```bash
   grep -i "password\|api_key\|secret\|token" workflow.json
   ```

**File Naming:**
- Use workflow name as filename
- Replace spaces with underscores: `Outlook_Emails_Fetch.json`
- Don't add version numbers to filename (use Git tags instead)

### Git Workflow

**Feature Development:**
```bash
# Create feature branch
git checkout -b feat/contact-lists-implementation

# Make changes, test thoroughly

# Commit incrementally
git add Database/create_contact_lists_table.sql
git commit -m "feat(sql): add contact_lists table schema"

git add Workflows/Outlook_Validate_Select.json
git commit -m "feat(workflow): integrate contact_lists lookup in gateway"

# Push and create PR
git push origin feat/contact-lists-implementation
```

**Hotfix:**
```bash
git checkout main
git checkout -b fix/body-fetch-timeout
# Fix issue
git commit -m "fix(workflow): increase body fetch timeout to 30s"
git push origin fix/body-fetch-timeout
# Merge immediately after testing
```

---

**Last Updated:** 2025-10-16
**Maintained By:** Project team
**Review Frequency:** Quarterly or when major changes introduced
