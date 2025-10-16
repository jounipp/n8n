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


-- ==========================================
-- 1. INTERNAL-DOMAINIT (classification_rules)
-- ==========================================

-- Nämä MYÖS contact_lists:ssa, mutta lisätään tänne varmistukseksi
-- Jos contact_lists hajoaa, nämä toimivat backuppina

INSERT INTO outlook.classification_rules
  (version, is_active, scope, feature, key_value, target_category, recommended_action, priority, rule_type, notes)
VALUES
  ('cda_2025-10-15T14-00-00', TRUE, 'domain', 'from_domain', 'repoxcapital.fi', 'internal', 'review', 30, 'single', 'Oma yritys - kaikki viestit'),
  ('cda_2025-10-15T14-00-00', TRUE, 'domain', 'from_domain', 'corenum.fi', 'internal', 'review', 30, 'single', 'Oma yritys / sisäinen'),
  ('cda_2025-10-15T14-00-00', TRUE, 'domain', 'from_domain', 'sharkaccount.fi', 'internal', 'review', 30, 'single', 'Oma yritys / sisäinen')

ON CONFLICT (version, feature, key_value) DO NOTHING;


-- ==========================================
-- 2. BUSINESS_CRITICAL -DOMAINIT
-- ==========================================

-- Tärkeät yhteistyökumppanit (EI VIP-finance listalla)

INSERT INTO outlook.classification_rules
  (version, is_active, scope, feature, key_value, target_category, recommended_action, priority, rule_type, notes)
VALUES
  ('cda_2025-10-15T14-00-00', TRUE, 'domain', 'from_domain', 'kaivonporaus.com', 'business_critical', 'review', 30, 'single', 'Tärkeä kumppani (20 personal → business)'),
  ('cda_2025-10-15T14-00-00', TRUE, 'domain', 'from_domain', 'cactos.fi', 'business_critical', 'review', 30, 'single', 'Tärkeä kumppani'),
  ('cda_2025-10-15T14-00-00', TRUE, 'domain', 'from_domain', 'news.cactos.fi', 'notifications', 'archive', 30, 'single', 'Cactos notifications')

ON CONFLICT (version, feature, key_value) DO NOTHING;


-- ==========================================
-- 3. FINANCIAL_NEWS - Muut lähteet (EI VIP-listalla)
-- ==========================================

-- Nämä eivät ole VIP-listalla, mutta datasta vahvistettu financial_news

-- HUOM: Bloomberg, SeekingAlpha, Inderes jne. VAIN contact_lists:ssa
-- → EI classification_rules sääntöä, AI päättää financial/marketing/notif

-- Pienet/keskikokoiset financial-lähteet:
INSERT INTO outlook.classification_rules
  (version, is_active, scope, feature, key_value, target_category, recommended_action, priority, rule_type, notes)
VALUES
  -- Message-ID domainit (jos from_domain puuttuu)
  ('cda_2025-10-15T14-00-00', TRUE, 'domain', 'message_id_domain', 'eu-north-1.amazonses.com', 'financial_news', 'review', 20, 'single', 'SES financial newsletters'),
  ('cda_2025-10-15T14-00-00', TRUE, 'domain', 'unsub_domain', 'www.anpdm.com', 'financial_news', 'review', 20, 'single', 'Financial newsletter unsubscribe'),
  ('cda_2025-10-15T14-00-00', TRUE, 'domain', 'unsub_domain', 'xk9r6.mjt.lu', 'financial_news', 'review', 20, 'single', 'Mailjet financial'),
  ('cda_2025-10-15T14-00-00', TRUE, 'domain', 'list_domain', '30b8ff5109d76134b3751dcc5.255309.list-id.mcsv.net', 'financial_news', 'review', 20, 'single', 'Mailchimp financial list')

ON CONFLICT (version, feature, key_value) DO NOTHING;


-- ==========================================
-- 4. INDUSTRY_NEWS
-- ==========================================

-- Teknologia/ei-rahoitus uutislähteet

INSERT INTO outlook.classification_rules
  (version, is_active, scope, feature, key_value, target_category, recommended_action, priority, rule_type, notes)
VALUES
  ('cda_2025-10-15T14-00-00', TRUE, 'domain', 'from_domain', 'knx.org', 'industry_news', 'review', 30, 'single', 'Teknologia-standardi (9 viesti industry vs 19 marketing)')

ON CONFLICT (version, feature, key_value) DO NOTHING;


-- ==========================================
-- 5. NOTIFICATIONS - Teknologia/palvelut
-- ==========================================

INSERT INTO outlook.classification_rules
  (version, is_active, scope, feature, key_value, target_category, recommended_action, priority, rule_type, notes)
VALUES
  -- Microsoft (22 notifications vs 11 business_critical)
  ('cda_2025-10-15T14-00-00', TRUE, 'domain', 'from_domain', 'microsoft.com', 'notifications', 'review', 30, 'single', 'Microsoft notifications'),
  ('cda_2025-10-15T14-00-00', TRUE, 'domain', 'from_domain', 'mail.support.microsoft.com', 'notifications', 'review', 30, 'single', 'Microsoft support'),

  -- LinkedIn
  ('cda_2025-10-15T14-00-00', TRUE, 'domain', 'from_domain', 'linkedin.com', 'notifications', 'archive', 30, 'single', 'LinkedIn notifications (5 viesti)'),

  -- IoT/energia palvelut
  ('cda_2025-10-15T14-00-00', TRUE, 'domain', 'from_domain', 'solarweb.com', 'notifications', 'archive', 30, 'single', 'Solar monitoring'),
  ('cda_2025-10-15T14-00-00', TRUE, 'domain', 'message_id_domain', 'mtasv.net', 'notifications', 'archive', 20, 'single', 'SMTP relay notifications'),
  ('cda_2025-10-15T14-00-00', TRUE, 'domain', 'message_id_domain', 'message-id.smtpcorp.com', 'notifications', 'archive', 20, 'single', 'SMTP corp notifications')

ON CONFLICT (version, feature, key_value) DO NOTHING;


-- ==========================================
-- 6. MARKETING
-- ==========================================

INSERT INTO outlook.classification_rules
  (version, is_active, scope, feature, key_value, target_category, recommended_action, priority, rule_type, notes)
VALUES
  -- Squarespace
  ('cda_2025-10-15T14-00-00', TRUE, 'domain', 'from_domain', 'mail.squarespace.com', 'marketing', 'archive', 30, 'single', 'Squarespace marketing (25 viesti)'),

  -- Microsoft Store
  ('cda_2025-10-15T14-00-00', TRUE, 'domain', 'from_domain', 'microsoftstore.microsoft.com', 'marketing', 'archive', 30, 'single', 'Microsoft Store marketing'),
  ('cda_2025-10-15T14-00-00', TRUE, 'domain', 'message_id_domain', 'microsoftstore.microsoft.com', 'marketing', 'archive', 20, 'single', 'Microsoft Store MID'),
  ('cda_2025-10-15T14-00-00', TRUE, 'domain', 'unsub_domain', 'account.microsoft.com', 'marketing', 'archive', 20, 'single', 'Microsoft account unsub')

ON CONFLICT (version, feature, key_value) DO NOTHING;


-- ==========================================
-- YHTEENVETO
-- ==========================================

-- Laske uudet säännöt
WITH new_rules AS (
  SELECT COUNT(*) as count
  FROM outlook.classification_rules
  WHERE version = 'cda_2025-10-15T14-00-00'
    AND is_active = TRUE
),
existing_rules AS (
  SELECT COUNT(*) as count
  FROM outlook.classification_rules
  WHERE version != 'cda_2025-10-15T14-00-00'
    AND is_active = TRUE
)
SELECT
  'NEW RULES' as type,
  n.count as rules_count
FROM new_rules n
UNION ALL
SELECT
  'EXISTING RULES' as type,
  e.count as rules_count
FROM existing_rules e
UNION ALL
SELECT
  'TOTAL ACTIVE' as type,
  COUNT(*) as rules_count
FROM outlook.classification_rules
WHERE is_active = TRUE;

-- Näytä uudet säännöt kategorioi ttain
SELECT
  target_category,
  COUNT(*) as rule_count,
  STRING_AGG(DISTINCT feature, ', ') as features_used
FROM outlook.classification_rules
WHERE version = 'cda_2025-10-15T14-00-00'
  AND is_active = TRUE
GROUP BY target_category
ORDER BY rule_count DESC;

-- Näytä kaikki uudet säännöt
SELECT
  target_category,
  feature,
  key_value,
  recommended_action,
  priority,
  notes
FROM outlook.classification_rules
WHERE version = 'cda_2025-10-15T14-00-00'
  AND is_active = TRUE
ORDER BY
  target_category,
  CASE feature
    WHEN 'from_address' THEN 1
    WHEN 'sender_address' THEN 2
    WHEN 'from_domain' THEN 3
    WHEN 'message_id_domain' THEN 4
    WHEN 'list_domain' THEN 5
    WHEN 'unsub_domain' THEN 6
  END,
  key_value;
