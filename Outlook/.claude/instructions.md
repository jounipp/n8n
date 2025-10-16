# n8n Outlook Email Automation System

## Overview

This project implements an intelligent email classification and automation system for Microsoft Outlook using n8n workflows, AI-powered analysis, and PostgreSQL database. The system automatically categorizes incoming emails, prioritizes them based on business relevance, and syncs decisions back to Outlook with appropriate labels and flags.

**Key Features:**
- Automated email fetching and body content retrieval from Microsoft Graph API
- Hybrid classification system combining rule-based logic and AI analysis
- 10-category classification system (business_critical, financial_news, personal_communication, etc.)
- Bidirectional sync between database and Outlook
- Batch processing with AI prompt caching for cost optimization
- Delta sync for efficient incremental updates
- Comprehensive audit logging and analytics

## Prerequisites

### Required Accounts & Services
- **Microsoft 365 account** with Microsoft Graph API access
  - App registration in Azure AD with Mail.Read, Mail.ReadWrite permissions
  - OAuth2 authentication configured in n8n
- **PostgreSQL database** (version 12+)
  - Schema: `outlook`
  - Requires extensions: `uuid-ossp`, `pg_trgm`
- **n8n instance** (self-hosted or cloud)
  - Version 1.0+ recommended
- **Anthropic Claude API** access
  - Model: claude-sonnet-4-5-20250929
  - Prompt caching enabled

### Environment Variables
```bash
USER_UPN=jouni.pappila@repoxcapital.fi  # Primary user email
```

### n8n Credentials
Configure in n8n Settings > Credentials:
1. **Microsoft Graph API OAuth2**
   - Client ID, Client Secret from Azure App Registration
   - Redirect URI: `https://your-n8n-instance/oauth-callback`
2. **PostgreSQL**
   - Host, Port, Database, User, Password
3. **Anthropic API**
   - API Key from Anthropic Console

## Quick Start Guide

### 1. Database Setup

```bash
# Create schema and tables
psql -U postgres -d outlook_db -f Database/Schema_outlook.sql

# Seed classification rules
psql -U postgres -d outlook_db -f Scripts/classification_rules_FINAL.sql

# Create contact lists
psql -U postgres -d outlook_db -f Scripts/create_contact_lists_table.sql
psql -U postgres -d outlook_db -f Scripts/populate_contact_lists.sql
```

### 2. Import Workflows to n8n

Import the following workflows in order:
1. `Outlook Emails Fetch.json` - Fetches email metadata
2. `Outlook Body Fetch.json` - Retrieves email body content
3. `Outlook Validate Select.json` - Selection and orchestration workflow
4. `Outlook Validate Analyse.json` - AI-powered email analysis
5. `Outlook Sync DB.json` - Syncs database decisions to Outlook
6. `Outlook Sync OL.json` - Syncs Outlook changes to database

### 3. Configure Workflow Credentials

For each imported workflow:
- Update PostgreSQL credentials
- Update Microsoft Graph OAuth2 credentials
- Update Anthropic API credentials
- Set `user_upn` parameter in configuration nodes

### 4. Test the System

```bash
# Trigger initial email fetch
# In n8n: Execute "Outlook Emails Fetch" workflow manually

# Verify database ingestion
psql -U postgres -d outlook_db -c "SELECT COUNT(*) FROM outlook.emails_ingest;"

# Test classification workflow
# Execute "Outlook Validate Select" workflow manually

# Check results
psql -U postgres -d outlook_db -c "SELECT primary_category, COUNT(*) FROM outlook.email_interest GROUP BY 1;"
```

### 5. Enable Automated Processing

- **Outlook Emails Fetch**: Enable schedule trigger (every 10 minutes)
- **Outlook Validate Select**: Enable schedule trigger (every 4 minutes)
- **Outlook Sync DB**: Enable schedule trigger (every 15 minutes)

## Common Commands

### Database Queries

```sql
-- View unprocessed emails
SELECT message_id, subject, from_address, received_datetime
FROM outlook.emails_ingest
WHERE analyzed_at IS NULL
LIMIT 10;

-- Check classification statistics
SELECT primary_category, COUNT(*), AVG(confidence) as avg_conf
FROM outlook.email_interest
GROUP BY primary_category
ORDER BY COUNT(*) DESC;

-- Monitor sync status
SELECT sync_status, COUNT(*)
FROM outlook.action_decisions
GROUP BY sync_status;

-- View recent process logs
SELECT workflow_name, operation, stage, items_processed, created_at
FROM outlook.process_log
ORDER BY created_at DESC
LIMIT 20;
```

### Workflow Operations

```bash
# Export workflow backup
# In n8n: Workflow menu > Download

# Check workflow execution history
# In n8n: Executions tab > Filter by workflow

# Monitor active executions
# In n8n: Executions > Running
```

## Troubleshooting

### Issue: Emails not fetching

**Symptoms:** No new rows in `emails_ingest` table

**Solutions:**
1. Check Microsoft Graph API credentials are valid
2. Verify user permissions include Mail.Read
3. Check `delta_state` table for sync status:
   ```sql
   SELECT * FROM outlook.delta_state WHERE user_upn = 'your-email@domain.com';
   ```
4. Review `process_log` for errors:
   ```sql
   SELECT * FROM outlook.process_log WHERE workflow_name = 'outlook_emails_fetch' ORDER BY created_at DESC LIMIT 5;
   ```

### Issue: AI analysis failing

**Symptoms:** Emails stuck with `analyzed_at IS NULL`

**Solutions:**
1. Verify Anthropic API key is valid
2. Check API rate limits and quotas
3. Review error logs in n8n execution history
4. Ensure body content exists:
   ```sql
   SELECT message_id FROM outlook.emails_ingest WHERE needs_body = TRUE;
   ```

### Issue: Sync not updating Outlook

**Symptoms:** `sync_status = 'pending'` in `action_decisions`

**Solutions:**
1. Check Microsoft Graph OAuth2 token hasn't expired
2. Verify Mail.ReadWrite permissions
3. Review sync_log table:
   ```sql
   SELECT * FROM outlook.sync_log WHERE sync_status = 'failed' ORDER BY created_at DESC LIMIT 10;
   ```

### Issue: High AI costs

**Symptoms:** Unexpected API costs

**Solutions:**
1. Verify prompt caching is enabled in `ai_classify_emails_cache` node
2. Check cache hit rate:
   ```sql
   SELECT detail->>'cache_hit_rate' FROM outlook.process_log WHERE operation = 'ai_classify' ORDER BY created_at DESC LIMIT 10;
   ```
3. Increase batch size in `set_config` node (default: 2 batches)
4. Review rules coverage:
   ```sql
   SELECT model_name, COUNT(*) FROM outlook.email_interest GROUP BY model_name;
   -- Goal: 80%+ from 'rule_engine', <20% from 'claude'
   ```

### Issue: Duplicate emails

**Symptoms:** Multiple rows for same email

**Solutions:**
1. Check `dedupe_key` uniqueness constraint
2. Clean duplicates:
   ```sql
   DELETE FROM outlook.emails_ingest
   WHERE id NOT IN (
     SELECT MIN(id) FROM outlook.emails_ingest GROUP BY message_id
   );
   ```

## Performance Optimization

### Database Indexes

Ensure these indexes exist (created by Schema_outlook.sql):
- `emails_ingest.message_id` (PRIMARY KEY)
- `emails_ingest.received_datetime` (DESC)
- `emails_ingest.analyzed_at` (WHERE NULL)
- `email_interest.message_id, model_name, model_version` (UNIQUE)

### Workflow Configuration

**Batch Processing:**
- `set_config` node → `batch` parameter: Increase for larger volumes (default: 2)
- `MAX_BODY_CHARS`: Reduce to lower token costs (default: 100000)

**Concurrent Execution:**
- Enable workflow setting: "Allow Multiple Executions"
- Limit to 3-5 concurrent runs to avoid API rate limits

### Rules Optimization

Run Category Discovery Analysis monthly to identify new rule candidates:
```bash
# Execute the analysis workflow
n8n execute workflow "Category Discovery Analysis"

# Review proposed rules
psql -U postgres -d outlook_db -f Scripts/classification_rules_gap.sql
```

## System Architecture

See `architecture.md` for detailed component descriptions and data flow diagrams.

## Development Workflow

See `conventions.md` for coding standards and best practices.

## Workflow Catalog

See `workflows.md` for detailed documentation of all n8n workflows, triggers, and node configurations.

## Support & Documentation

- **Project Documentation**: This directory (`.claude/`)
- **Implementation Guides**: `IMPLEMENTATION_GUIDE.md`, `GATEWAY_INTEGRATION_GUIDE.md`, `HYBRID_SYSTEM_GUIDE.md`
- **Decisions Log**: `DECISIONS_FI.md`, `CATEGORY_DECISIONS_NEEDED.md`
- **Database Scripts**: `Scripts/` directory
- **Workflow Exports**: `Workflows/` directory

## Version History

- **v1.0** (2025-10-08): Initial hybrid system with rule-based gateway + AI analysis
- **v1.1** (2025-10-13): Added classification_rules table and gateway workflows
- **v1.2** (2025-10-15): Implemented contact_lists for VIP/personal contacts
- **Current**: Hybrid system with prompt caching and rules versioning
