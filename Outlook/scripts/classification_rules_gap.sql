-- Audit Gateway rules vs. 10-category taxonomy and estimate coverage from existing signals
-- Safe to run read-only.

WITH taxonomy AS (
  SELECT unnest(ARRAY[
    'business_critical','financial_news','marketing','notifications','spam_low_value',
    'personal_communication','industry_news','internal','regulatory','uncategorized'
  ]) AS cat
), rules AS (
  SELECT primary_category AS cat, COUNT(*) AS rules, COUNT(*) FILTER (WHERE is_active) AS active
  FROM outlook.classification_rules
  GROUP BY primary_category
),
signals AS (
  -- approximate signal distribution across the taxonomy using content/email_interest
  SELECT
    COALESCE(
      (SELECT e.primary_category FROM outlook.email_interest e WHERE e.message_id = ei.message_id ORDER BY e.decided_at DESC LIMIT 1),
      (SELECT c.primary_category FROM outlook.content_analysis c WHERE c.message_id = ei.message_id ORDER BY c.analyzed_at DESC LIMIT 1),
      'uncategorized'
    ) AS cat
  FROM outlook.emails_ingest ei
), sigdist AS (
  SELECT LOWER(cat) AS cat, COUNT(*) AS examples
  FROM signals
  GROUP BY LOWER(cat)
)
SELECT t.cat,
       COALESCE(r.rules, 0)   AS rules_total,
        COALESCE(r.active, 0)  AS rules_active,
       COALESCE(s.examples, 0) AS sample_emails
FROM taxonomy t
LEFT JOIN rules r ON r.cat = t.cat
LEFT JOIN sigdist s ON s.cat = t.cat
ORDER BY t.cat;

