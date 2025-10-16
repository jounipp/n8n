-- Purpose: Prepare historical decisions in DB from existing analysis signals
-- Scope: audit taxonomy coverage; derive normalized categories; preview and upsert into outlook.action_decisions
-- Notes: run in staging first; transaction ends with ROLLBACK by default

BEGIN;

-- 1) Define target taxonomy (AI prompt classes)
WITH target_taxonomy AS (
  SELECT unnest(ARRAY[
    'business_critical',
    'financial_news',
    'marketing',
    'notifications',
    'spam_low_value',
    'personal_communication',
    'industry_news',
    'internal',
    'regulatory',
    'uncategorized'
  ]) AS cat
),
-- 2) Audit: classification_rules coverage (if available)
rules AS (
  SELECT cr.id, cr.version, cr.is_active, cr.primary_category
  FROM outlook.classification_rules cr
  WHERE cr.primary_category IS NOT NULL
),
rules_cov AS (
  SELECT t.cat, COUNT(r.id) AS rules_count, COUNT(r.id) FILTER (WHERE r.is_active) AS active_rules
  FROM target_taxonomy t
  LEFT JOIN rules r ON r.primary_category = t.cat
  GROUP BY t.cat
),
-- 3) Candidate source signals for category
src AS (
  SELECT 
    ei.message_id,
    -- Prefer explicit decision if already exists
    NULLIF(ad.outlook_primary_category, '')            AS dec_primary,  -- optional column; may not exist
    (SELECT e.primary_category FROM outlook.email_interest e WHERE e.message_id = ei.message_id ORDER BY e.decided_at DESC LIMIT 1) AS interest_primary,
    (SELECT c.primary_category   FROM outlook.content_analysis c WHERE c.message_id = ei.message_id ORDER BY c.analyzed_at DESC LIMIT 1) AS content_primary,
    (SELECT (c.categories_found)[1] FROM outlook.content_analysis c WHERE c.message_id = ei.message_id AND c.categories_found IS NOT NULL AND array_length(c.categories_found,1) > 0 ORDER BY c.analyzed_at DESC LIMIT 1) AS first_found
  FROM outlook.emails_ingest ei
  LEFT JOIN outlook.action_decisions ad ON ad.message_id = ei.message_id
),
ranked AS (
  SELECT 
    s.message_id,
    COALESCE(
      NULLIF(s.dec_primary,''),
      NULLIF(s.interest_primary,''),
      NULLIF(s.content_primary,''),
      NULLIF(s.first_found,'')
    ) AS raw_category
  FROM src s
),
-- 4) Normalize to target taxonomy (lowercase, fallback to uncategorized)
normalized AS (
  SELECT 
    r.message_id,
    CASE 
      WHEN LOWER(r.raw_category) IN (SELECT cat FROM target_taxonomy) THEN LOWER(r.raw_category)
      ELSE 'uncategorized'
    END AS primary_category
  FROM ranked r
),
-- 5) Preview changes vs existing action_decisions
preview AS (
  SELECT 
    n.message_id,
    n.primary_category,
    ad.outlook_categories AS existing_categories,
    ad.outlook_flag_status AS existing_flag
  FROM normalized n
  LEFT JOIN outlook.action_decisions ad ON ad.message_id = n.message_id
)
SELECT '== Taxonomy coverage (rules) ==' AS section;

SELECT * FROM rules_cov ORDER BY cat;

SELECT '== Derivation preview (first 100) ==' AS section;

SELECT 
  p.message_id,
  p.primary_category,
  p.existing_categories,
  p.existing_flag
FROM preview p
ORDER BY p.message_id
LIMIT 100;

-- 6) UPSERT decisions (commented by default)
-- INSERT INTO outlook.action_decisions AS ad (
--   message_id, outlook_categories, outlook_flag_status, sync_status, updated_at
-- )
-- SELECT 
--   n.message_id,
--   ARRAY[n.primary_category]::text[] AS outlook_categories,
--   COALESCE(ad.outlook_flag_status, 'notFlagged') AS outlook_flag_status,
--   'pending'::text AS sync_status,
--   NOW()
-- FROM normalized n
-- LEFT JOIN outlook.action_decisions ad ON ad.message_id = n.message_id
-- ON CONFLICT (message_id) DO UPDATE SET
--   outlook_categories  = EXCLUDED.outlook_categories,
--   outlook_flag_status = COALESCE(EXCLUDED.outlook_flag_status, 'notFlagged'),
--   sync_status         = 'pending',
--   updated_at          = NOW();

-- 7) Combined JSON report (single row)
WITH 
  cov AS (
    SELECT jsonb_agg(jsonb_build_object('category', cat, 'rules', rules_count, 'active_rules', active_rules) ORDER BY cat) AS cov
    FROM rules_cov
  ),
  sample AS (
    SELECT jsonb_agg(jsonb_build_object(
      'message_id', p.message_id,
      'primary_category', p.primary_category,
      'existing_categories', p.existing_categories,
      'existing_flag', p.existing_flag
    )) AS rows
    FROM preview p
    LIMIT 100
  )
SELECT jsonb_build_object(
  'taxonomy', jsonb_build_object('expected', ARRAY[
    'business_critical','financial_news','marketing','notifications','spam_low_value','personal_communication','industry_news','internal','regulatory','uncategorized'
  ]),
  'rules_coverage', (SELECT cov FROM cov),
  'derivation_preview', COALESCE((SELECT rows FROM sample), '[]'::jsonb)
) AS report;

ROLLBACK; -- Replace with COMMIT and uncomment UPSERT to apply

