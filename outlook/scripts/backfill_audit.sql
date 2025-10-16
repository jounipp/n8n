-- NOTE: Adjust array types if needed (e.g., text[]). Run in staging first.
-- This script provides: audit, normalization, and backfill candidate extraction.

BEGIN;

-- 1) AUDIT: Totals and gaps
SELECT '== Audit: totals & gaps ==' AS section;
-- Total ingested emails
SELECT COUNT(*) AS total_emails FROM outlook.emails_ingest;

-- With analysis/decision present
SELECT 
  (SELECT COUNT(*) FROM outlook.ai_analysis_log)          AS analyses,
  (SELECT COUNT(*) FROM outlook.action_decisions)         AS decisions;

-- Missing DB flags/categories (treat NULL as missing; adjust if empty array notation differs)
SELECT 
  COUNT(*) FILTER (WHERE flag_status IS NULL OR flag_status = '')        AS missing_flag_status,
  COUNT(*) FILTER (WHERE categories IS NULL OR array_length(categories,1) IS NULL) AS missing_categories
FROM outlook.emails_ingest;

-- Decisions not synced to Outlook yet
SELECT COUNT(*) AS pending_decisions
FROM outlook.action_decisions ad
WHERE ad.synced_to_outlook_at IS NULL OR ad.sync_status IS DISTINCT FROM 'synced';

-- Flags distribution (verify prevalent values like 'notFlagged')
SELECT '== Flags distribution ==' AS section;
SELECT COALESCE(flag_status,'<NULL>') AS flag_status, COUNT(*) AS n
FROM outlook.emails_ingest
GROUP BY 1
ORDER BY n DESC;

-- Categories emptiness (robust) — handles array vs. non-array storage
SELECT '== Categories emptiness (robust) ==' AS section;
SELECT COUNT(*) AS missing_categories_robust
FROM outlook.emails_ingest ei
WHERE (
  -- If array type, treat NULL or 0 length as missing
  (pg_typeof(ei.categories)::text LIKE '%[]' AND (cardinality(ei.categories) IS NULL OR cardinality(ei.categories) = 0))
  OR
  -- If non-array, treat NULL/empty/JSON-empty as missing
  (pg_typeof(ei.categories)::text NOT LIKE '%[]' AND (ei.categories IS NULL OR ei.categories::text IN ('', '[]', '{}')))
);

-- 2) AUDIT: Mismatches between DB and decision (order-insensitive category compare)
SELECT '== Mismatch: DB vs decisions ==' AS section;
WITH norm AS (
  SELECT 
    ei.message_id,
    ei.flag_status                         AS db_flag,
    ad.outlook_flag_status                 AS dec_flag,
    COALESCE(ei.categories, ARRAY[]::text[])      AS db_cats,
    COALESCE(ad.outlook_categories, ARRAY[]::text[]) AS dec_cats
  FROM outlook.emails_ingest ei
  JOIN outlook.action_decisions ad ON ad.message_id = ei.message_id
), cmp AS (
  SELECT 
    message_id,
    db_flag, dec_flag,
    (SELECT array_agg(x ORDER BY x) FROM unnest(db_cats) x)  AS db_cats_sorted,
    (SELECT array_agg(x ORDER BY x) FROM unnest(dec_cats) x) AS dec_cats_sorted
  FROM norm
)
SELECT 
  COUNT(*) FILTER (WHERE db_flag IS DISTINCT FROM dec_flag)                        AS flag_mismatch,
  COUNT(*) FILTER (WHERE db_cats_sorted IS DISTINCT FROM dec_cats_sorted)          AS categories_mismatch
FROM cmp;

-- 3) NORMALIZATION (DRY-RUN): Preview updates to align DB to decisions
SELECT '== Preview: DB normalization from decisions ==' AS section;
SELECT 
  ei.message_id,
  ei.flag_status      AS db_flag_old,
  ad.outlook_flag_status AS db_flag_new,
  ei.categories       AS db_cats_old,
  ad.outlook_categories  AS db_cats_new
FROM outlook.emails_ingest ei
JOIN outlook.action_decisions ad ON ad.message_id = ei.message_id
WHERE (ei.flag_status IS DISTINCT FROM ad.outlook_flag_status)
   OR (
     (SELECT array_agg(x ORDER BY x) FROM unnest(COALESCE(ei.categories, ARRAY[]::text[])) x) IS DISTINCT FROM
     (SELECT array_agg(x ORDER BY x) FROM unnest(COALESCE(ad.outlook_categories, ARRAY[]::text[])) x)
   )
LIMIT 100;

-- 4) NORMALIZATION (EXECUTE): Update DB from decisions
-- WARNING: Uncomment when ready.
-- UPDATE outlook.emails_ingest ei
-- SET 
--   flag_status = ad.outlook_flag_status,
--   categories  = ad.outlook_categories,
--   updated_at  = now()
-- FROM outlook.action_decisions ad
-- WHERE ad.message_id = ei.message_id
--   AND (
--     ei.flag_status IS DISTINCT FROM ad.outlook_flag_status OR
--     (SELECT array_agg(x ORDER BY x) FROM unnest(COALESCE(ei.categories, ARRAY[]::text[])) x) IS DISTINCT FROM
--     (SELECT array_agg(x ORDER BY x) FROM unnest(COALESCE(ad.outlook_categories, ARRAY[]::text[])) x)
--   );

-- 5) BACKFILL CANDIDATES: What to push to Outlook
SELECT '== Backfill candidates to Outlook ==' AS section;
SELECT 
  ei.message_id,
  ei.user_upn,
  ei.folder_name,
  ad.outlook_categories AS categories_to_set,
  ad.outlook_flag_status AS flag_to_set
FROM outlook.emails_ingest ei
JOIN outlook.action_decisions ad ON ad.message_id = ei.message_id
WHERE (ad.synced_to_outlook_at IS NULL OR ad.sync_status IS DISTINCT FROM 'synced')
  AND (ad.outlook_categories IS NOT NULL OR ad.outlook_flag_status IS NOT NULL)
LIMIT 500;

-- 6) DECISION MARKING: Mark as synced after successful Outlook PATCH (run from app/workflow)
-- UPDATE outlook.action_decisions
-- SET sync_status = 'synced', synced_to_outlook_at = now(), updated_at = now()
-- WHERE message_id = ANY(:patched_message_ids);

-- 7) COMBINED REPORT (single row, JSON) — place as last SELECT so most clients show it
WITH
  total_emails AS (
    SELECT COUNT(*) AS n FROM outlook.emails_ingest
  ),
  analyses AS (
    SELECT COUNT(*) AS n FROM outlook.ai_analysis_log
  ),
  decisions AS (
    SELECT COUNT(*) AS n FROM outlook.action_decisions
  ),
  gaps AS (
    SELECT 
      COUNT(*) FILTER (WHERE flag_status IS NULL OR flag_status = '') AS missing_flag_status,
      COUNT(*) FILTER (WHERE categories IS NULL OR array_length(categories,1) IS NULL) AS missing_categories
    FROM outlook.emails_ingest
  ),
  norm AS (
    SELECT 
      ei.message_id,
      ei.flag_status                         AS db_flag,
      ad.outlook_flag_status                 AS dec_flag,
      COALESCE(ei.categories, ARRAY[]::text[])      AS db_cats,
      COALESCE(ad.outlook_categories, ARRAY[]::text[]) AS dec_cats
    FROM outlook.emails_ingest ei
    JOIN outlook.action_decisions ad ON ad.message_id = ei.message_id
  ),
  cmp AS (
    SELECT 
      message_id,
      db_flag, dec_flag,
      (SELECT array_agg(x ORDER BY x) FROM unnest(db_cats) x)  AS db_cats_sorted,
      (SELECT array_agg(x ORDER BY x) FROM unnest(dec_cats) x) AS dec_cats_sorted
    FROM norm
  ),
  mismatch AS (
    SELECT 
      COUNT(*) FILTER (WHERE db_flag IS DISTINCT FROM dec_flag)               AS flag_mismatch,
      COUNT(*) FILTER (WHERE db_cats_sorted IS DISTINCT FROM dec_cats_sorted) AS categories_mismatch
    FROM cmp
  ),
  preview AS (
    SELECT jsonb_agg(jsonb_build_object(
      'message_id', ei.message_id,
      'db_flag_old', ei.flag_status,
      'db_flag_new', ad.outlook_flag_status,
      'db_cats_old', ei.categories,
      'db_cats_new', ad.outlook_categories
    )) AS rows
    FROM outlook.emails_ingest ei
    JOIN outlook.action_decisions ad ON ad.message_id = ei.message_id
    WHERE (ei.flag_status IS DISTINCT FROM ad.outlook_flag_status)
       OR (
         (SELECT array_agg(x ORDER BY x) FROM unnest(COALESCE(ei.categories, ARRAY[]::text[])) x) IS DISTINCT FROM
         (SELECT array_agg(x ORDER BY x) FROM unnest(COALESCE(ad.outlook_categories, ARRAY[]::text[])) x)
       )
    LIMIT 100
  ),
  candidates AS (
    SELECT jsonb_agg(jsonb_build_object(
      'message_id', ei.message_id,
      'user_upn', ei.user_upn,
      'folder_name', ei.folder_name,
      'categories_to_set', ad.outlook_categories,
      'flag_to_set', ad.outlook_flag_status
    )) AS rows
    FROM outlook.emails_ingest ei
    JOIN outlook.action_decisions ad ON ad.message_id = ei.message_id
    WHERE (ad.synced_to_outlook_at IS NULL OR ad.sync_status IS DISTINCT FROM 'synced')
      AND (ad.outlook_categories IS NOT NULL OR ad.outlook_flag_status IS NOT NULL)
    LIMIT 100
  )
SELECT jsonb_build_object(
  'audit', jsonb_build_object(
    'total_emails', (SELECT n FROM total_emails),
    'analyses', (SELECT n FROM analyses),
    'decisions', (SELECT n FROM decisions),
    'missing_flag_status', (SELECT missing_flag_status FROM gaps),
    'missing_categories', (SELECT missing_categories FROM gaps)
  ),
  'mismatch', (SELECT to_jsonb(mismatch.*) FROM mismatch),
  'preview', COALESCE((SELECT rows FROM preview), '[]'::jsonb),
  'backfill_candidates', COALESCE((SELECT rows FROM candidates), '[]'::jsonb)
) AS report;

ROLLBACK; -- Replace with COMMIT after validating on staging
