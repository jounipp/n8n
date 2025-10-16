-- Seed or update missing Gateway rules for full 10-category coverage
-- WARNING: This is a template. Review and edit WHERE conditions before running.
-- Run inside a transaction and ROLLBACK if unsure.

BEGIN;

-- Example helpers: company domain and bulk/newsletter heuristics
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_type WHERE typname = 'email_rule_condition'
  ) THEN
    -- Placeholder: if you have a JSON structure in rules, skip this
    CREATE TYPE email_rule_condition AS ENUM ('subject', 'from_domain', 'list_id', 'precedence', 'has_unsubscribe');
  END IF;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- Insert skeleton rows for missing categories; fill conditions per environment
WITH taxonomy AS (
  SELECT unnest(ARRAY[
    'personal_communication','industry_news','internal','regulatory'
  ]) AS cat
), missing AS (
  SELECT t.cat
  FROM taxonomy t
  LEFT JOIN outlook.classification_rules cr ON cr.primary_category = t.cat
  WHERE cr.id IS NULL
)
INSERT INTO outlook.classification_rules (
  id, version, is_active, primary_category, rule_name, rule_definition
)
SELECT 
  gen_random_uuid(),
  'seed_v1',
  false,
  m.cat,
  'SEED_' || m.cat,
  jsonb_build_object(
    'priority', 50,
    'conditions', jsonb_build_array(
      -- TODO: replace with real conditions per category
      CASE m.cat
        WHEN 'personal_communication' THEN jsonb_build_object('type','and','all', jsonb_build_array(
          jsonb_build_object('field','precedence','op','!=','value','bulk'),
          jsonb_build_object('field','has_unsubscribe','op','=', 'value', false),
          jsonb_build_object('field','to_count','op','<=','value', 3)
        ))
        WHEN 'industry_news' THEN jsonb_build_object('type','or','any', jsonb_build_array(
          jsonb_build_object('field','from_domain','op','in','value', jsonb_build_array('bloomberg.com','reuters.com','ft.com')),
          jsonb_build_object('field','subject','op','ilike_any','value', jsonb_build_array('%daily briefing%','%morning update%','%industry%'))
        ))
        WHEN 'internal' THEN jsonb_build_object('type','and','all', jsonb_build_array(
          jsonb_build_object('field','from_domain','op','ends_with','value','repoxcapital.fi'),
          jsonb_build_object('field','precedence','op','!=','value','bulk')
        ))
        WHEN 'regulatory' THEN jsonb_build_object('type','or','any', jsonb_build_array(
          jsonb_build_object('field','from_domain','op','in','value', jsonb_build_array('sec.gov','esma.europa.eu','fca.org.uk','finanssivalvonta.fi')),
          jsonb_build_object('field','subject','op','ilike_any','value', jsonb_build_array('%regulator%','%compliance%','%regulatory%','%disclosure%'))
        ))
      END
    )
  )
FROM missing m;

-- Optional: set is_active true after review
-- UPDATE outlook.classification_rules SET is_active = true WHERE rule_name LIKE 'SEED_%';

ROLLBACK; -- switch to COMMIT after verifying the inserted JSON structures

