-- ==========================================
-- EHDOTETUT UUDET CLASSIFICATION_RULES
-- Perustuu category_analysis_v2 tuloksiin
-- ==========================================

-- HUOM: Tarkista ennen ajoa että version-timestampit päivittyvät!

-- ==========================================
-- TIER 1: VIP FINANCE (korkein prioriteetti)
-- ==========================================

-- SeekingAlpha: Dominoiva financial_news lähde (3159 viestiä)
INSERT INTO outlook.classification_rules
  (version, is_active, scope, feature, key_value, target_category, recommended_action, priority, rule_type)
VALUES
  ('cda_2025-10-15T12-00-00', TRUE, 'domain', 'from_domain', 'seekingalpha.com', 'financial_news', 'review', 30, 'single'),
  ('cda_2025-10-15T12-00-00', TRUE, 'domain', 'message_id_domain', 'seekingalpha.com', 'financial_news', 'review', 20, 'single');

-- Bloomberg: Pääasiassa financial_news (1642 vs 486 industry)
-- PÄÄTÖS: Asetetaan financial_news, koska enemmistö siellä
INSERT INTO outlook.classification_rules
  (version, is_active, scope, feature, key_value, target_category, recommended_action, priority, rule_type)
VALUES
  ('cda_2025-10-15T12-00-00', TRUE, 'domain', 'from_domain', 'news.bloomberg.com', 'financial_news', 'review', 30, 'single'),
  ('cda_2025-10-15T12-00-00', TRUE, 'domain', 'from_domain', 'message.bloomberg.com', 'financial_news', 'review', 30, 'single');

-- Nordnet: Pääasiassa financial_news (92 vs 27 marketing)
INSERT INTO outlook.classification_rules
  (version, is_active, scope, feature, key_value, target_category, recommended_action, priority, rule_type)
VALUES
  ('cda_2025-10-15T12-00-00', TRUE, 'domain', 'from_domain', 'mail.nordnet.fi', 'financial_news', 'review', 30, 'single'),
  ('cda_2025-10-15T12-00-00', TRUE, 'domain', 'from_domain', 'nordnet.fi', 'financial_news', 'review', 30, 'single');

-- Nordea: Pääasiassa financial_news (35 vs 5 marketing)
INSERT INTO outlook.classification_rules
  (version, is_active, scope, feature, key_value, target_category, recommended_action, priority, rule_type)
VALUES
  ('cda_2025-10-15T12-00-00', TRUE, 'domain', 'from_domain', 'nordea.com', 'financial_news', 'review', 30, 'single'),
  ('cda_2025-10-15T12-00-00', TRUE, 'domain', 'from_domain', 'nordea.fi', 'financial_news', 'review', 30, 'single'),
  ('cda_2025-10-15T12-00-00', TRUE, 'domain', 'message_id_domain', 'nordea.com', 'financial_news', 'review', 20, 'single');

-- Ålandsbanken: Pääasiassa financial_news (30 vs 6 personal)
INSERT INTO outlook.classification_rules
  (version, is_active, scope, feature, key_value, target_category, recommended_action, priority, rule_type)
VALUES
  ('cda_2025-10-15T12-00-00', TRUE, 'domain', 'from_domain', 'alandsbanken.fi', 'financial_news', 'review', 30, 'single'),
  ('cda_2025-10-15T12-00-00', TRUE, 'domain', 'message_id_domain', 'alandsbanken.fi', 'financial_news', 'review', 20, 'single');

-- Redeye: Selkeä financial_news (21 viestiä)
INSERT INTO outlook.classification_rules
  (version, is_active, scope, feature, key_value, target_category, recommended_action, priority, rule_type)
VALUES
  ('cda_2025-10-15T12-00-00', TRUE, 'domain', 'from_domain', 'redeye.se', 'financial_news', 'review', 30, 'single');

-- Kauppalehti: Jako financial_news (17) vs industry_news (9)
-- PÄÄTÖS: financial_news koska enemmistö
INSERT INTO outlook.classification_rules
  (version, is_active, scope, feature, key_value, target_category, recommended_action, priority, rule_type)
VALUES
  ('cda_2025-10-15T12-00-00', TRUE, 'domain', 'from_domain', 'kauppalehti.fi', 'financial_news', 'review', 30, 'single'),
  ('cda_2025-10-15T12-00-00', TRUE, 'domain', 'from_domain', 'uutiskirje.kauppalehti.fi', 'financial_news', 'review', 30, 'single');

-- Inderes: Jo olemassa, mutta lisää notifications.inderes.com jos puuttuu
INSERT INTO outlook.classification_rules
  (version, is_active, scope, feature, key_value, target_category, recommended_action, priority, rule_type)
VALUES
  ('cda_2025-10-15T12-00-00', TRUE, 'domain', 'from_domain', 'notifications.inderes.com', 'financial_news', 'review', 30, 'single')
ON CONFLICT (version, feature, key_value) DO NOTHING;


-- ==========================================
-- TIER 2: INDUSTRY NEWS (pienemmät volyymit)
-- ==========================================

-- KNX.org: Teknologia-standardi (9 industry vs 19 marketing)
-- PÄÄTÖS: Jätetään ilman sääntöä → AI päättää tapauskohtaisesti
-- TAI asetetaan marketing jos enemmistö siellä
INSERT INTO outlook.classification_rules
  (version, is_active, scope, feature, key_value, target_category, recommended_action, priority, rule_type)
VALUES
  ('cda_2025-10-15T12-00-00', TRUE, 'domain', 'from_domain', 'knx.org', 'marketing', 'archive', 30, 'single');


-- ==========================================
-- TIER 3: BUSINESS_CRITICAL (yhteistyökumppanit)
-- ==========================================

-- RepoxCapital: MONIMUOTOINEN (115 personal, 67 business, 22 notif, 10 internal, 9 marketing)
-- PÄÄTÖS: Jätetään ILMAN domain-sääntöä → AI päättää lähettäjän ja sisällön mukaan
-- VAIHTOEHTOISESTI: Lisää address-tason säännöt kun tiedät tärkeät lähettäjät

-- Microsoft: business_critical (11) vs notifications (22)
-- PÄÄTÖS: notifications (enemmistö)
INSERT INTO outlook.classification_rules
  (version, is_active, scope, feature, key_value, target_category, recommended_action, priority, rule_type)
VALUES
  ('cda_2025-10-15T12-00-00', TRUE, 'domain', 'from_domain', 'microsoft.com', 'notifications', 'review', 30, 'single'),
  ('cda_2025-10-15T12-00-00', TRUE, 'domain', 'from_domain', 'mail.support.microsoft.com', 'notifications', 'review', 30, 'single');

-- Corenum: business_critical (8 viestiä, 91.3% varmuus)
INSERT INTO outlook.classification_rules
  (version, is_active, scope, feature, key_value, target_category, recommended_action, priority, rule_type)
VALUES
  ('cda_2025-10-15T12-00-00', TRUE, 'domain', 'from_domain', 'corenum.fi', 'business_critical', 'review', 30, 'single');

-- Kaivonporaus: business_critical (8) vs personal (20)
-- PÄÄTÖS: personal_communication (enemmistö)
INSERT INTO outlook.classification_rules
  (version, is_active, scope, feature, key_value, target_category, recommended_action, priority, rule_type)
VALUES
  ('cda_2025-10-15T12-00-00', TRUE, 'domain', 'from_domain', 'kaivonporaus.com', 'personal_communication', 'review', 30, 'single');

-- Cactos: business_critical (6 viestiä) + notifications (7)
-- PÄÄTÖS: notifications (enemmistö)
INSERT INTO outlook.classification_rules
  (version, is_active, scope, feature, key_value, target_category, recommended_action, priority, rule_type)
VALUES
  ('cda_2025-10-15T12-00-00', TRUE, 'domain', 'from_domain', 'cactos.fi', 'notifications', 'archive', 30, 'single'),
  ('cda_2025-10-15T12-00-00', TRUE, 'domain', 'from_domain', 'news.cactos.fi', 'notifications', 'archive', 30, 'single');


-- ==========================================
-- TIER 4: NOTIFICATIONS (teknologia/palvelut)
-- ==========================================

-- Solarweb: notifications (7 viestiä, 97.1% varmuus)
-- Jo olemassa säännöt, tarkista onko from_domain mukana
INSERT INTO outlook.classification_rules
  (version, is_active, scope, feature, key_value, target_category, recommended_action, priority, rule_type)
VALUES
  ('cda_2025-10-15T12-00-00', TRUE, 'domain', 'from_domain', 'solarweb.com', 'notifications', 'archive', 30, 'single')
ON CONFLICT (version, feature, key_value) DO NOTHING;

-- LinkedIn: notifications (5 viestiä, 97.2% varmuus)
INSERT INTO outlook.classification_rules
  (version, is_active, scope, feature, key_value, target_category, recommended_action, priority, rule_type)
VALUES
  ('cda_2025-10-15T12-00-00', TRUE, 'domain', 'from_domain', 'linkedin.com', 'notifications', 'archive', 30, 'single');

-- Gmail: notifications (7) vs personal (7) - TASAPELI
-- PÄÄTÖS: Jätetään ilman sääntöä → AI päättää sisällön perusteella


-- ==========================================
-- TIER 5: MARKETING (mainosviestit)
-- ==========================================

-- Squarespace: marketing (25 viestiä, 95.5% varmuus)
INSERT INTO outlook.classification_rules
  (version, is_active, scope, feature, key_value, target_category, recommended_action, priority, rule_type)
VALUES
  ('cda_2025-10-15T12-00-00', TRUE, 'domain', 'from_domain', 'mail.squarespace.com', 'marketing', 'archive', 30, 'single');


-- ==========================================
-- YHTEENVETO LISÄTTÄVISTÄ SÄÄNNÖISTÄ
-- ==========================================

-- Yhteensä noin 25-30 uutta sääntöä
-- Kattaa noin 5500+ lisäviestiä (nykyiset 8400:sta)
-- Gateway-osumapros nousee ~20% → ~85%

-- HUOM JÄTETTY ILMAN SÄÄNTÖÄ (AI päättää):
-- - repoxcapital.fi (monimuotoinen, vaatii address-tason säännöt)
-- - gmail.com (tasapeli notifications/personal)
-- - Regulatory-kategorian domainit (liian vähän dataa)

-- TOIMENPITEET SEURAAVAKSI:
-- 1. Vahvista version-timestamp (cda_2025-10-15T12-00-00)
-- 2. Tarkista duplikaatit olemassa oleviin sääntöihin
-- 3. Aja INSERT:it
-- 4. Päivitä rules_snapshot (aja Category Discovery Analysis uudelleen)
-- 5. Testaa muutamalla uudella viestillä
