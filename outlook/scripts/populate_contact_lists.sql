-- ==========================================
-- POPULATE CONTACT_LISTS - Alkudata
-- Perustuu päätöksiin 2025-10-15
-- ==========================================

-- ==========================================
-- 1. VIP FINANCE -LÄHTEET (domain-taso)
-- ==========================================

-- Nämä ovat VIP-rahoituslähteitä, mutta EI domain-sääntöä classification_rules:iin
-- AI päättää onko financial_news, marketing vai notifications

INSERT INTO outlook.contact_lists
  (list_type, identifier_type, identifier_value, target_category, recommended_action, priority, notes)
VALUES
  -- Tier 1: Suurimmat lähteet
  ('vip_finance', 'from_domain', 'seekingalpha.com', 'financial_news', 'review', 30, '3825 viestiä, AI päättää financial/marketing/notif'),
  ('vip_finance', 'from_domain', 'news.bloomberg.com', 'financial_news', 'review', 30, '2070 viestiä, AI päättää financial/industry'),
  ('vip_finance', 'from_domain', 'message.bloomberg.com', 'financial_news', 'review', 30, 'Bloomberg secondary domain'),
  ('vip_finance', 'from_domain', 't.message.bloomberg.com', 'financial_news', 'review', 30, 'Bloomberg tertiary domain'),

  -- Tier 2: Suomalaiset rahoituslähteet
  ('vip_finance', 'from_domain', 'inderes.fi', 'financial_news', 'review', 30, 'Inderes analyysit'),
  ('vip_finance', 'from_domain', 'mail.inderes.com', 'financial_news', 'review', 30, 'Inderes newsletter'),
  ('vip_finance', 'from_domain', 'notifications.inderes.com', 'financial_news', 'review', 30, 'Inderes notifications'),
  ('vip_finance', 'from_domain', 'mail.nordnet.fi', 'financial_news', 'review', 30, 'Nordnet newsletter'),
  ('vip_finance', 'from_domain', 'nordnet.fi', 'financial_news', 'review', 30, 'Nordnet main domain'),

  -- Tier 3: Pankit
  ('vip_finance', 'from_domain', 'nordea.com', 'financial_news', 'review', 30, 'Nordea pankki'),
  ('vip_finance', 'from_domain', 'nordea.fi', 'financial_news', 'review', 30, 'Nordea FI'),
  ('vip_finance', 'from_domain', 'alandsbanken.fi', 'financial_news', 'review', 30, 'Ålandsbanken'),

  -- Tier 4: Muut analyysitalot
  ('vip_finance', 'from_domain', 'redeye.se', 'financial_news', 'review', 30, 'Redeye analyysit'),
  ('vip_finance', 'from_domain', 'kauppalehti.fi', 'financial_news', 'review', 30, 'Kauppalehti, AI päättää financial/industry'),
  ('vip_finance', 'from_domain', 'uutiskirje.kauppalehti.fi', 'financial_news', 'review', 30, 'Kauppalehti newsletter')

ON CONFLICT (list_type, identifier_type, identifier_value) DO NOTHING;


-- ==========================================
-- 2. VIP PERSONAL -KONTAKTIT
-- ==========================================

-- VIP-lähteistä tulevat henkilökohtaiset kontaktit
-- Nämä ohittavat domain-tason ja menevät business_critical-kategoriaan

-- HUOM: Lisää tähän tunnettuja VIP-henkilöitä kun niitä ilmenee
-- Esim:
-- INSERT INTO outlook.contact_lists
--   (list_type, identifier_type, identifier_value, target_category, recommended_action, priority, notes)
-- VALUES
--   ('vip_personal', 'from_address', 'john.analyst@bloomberg.com', 'business_critical', 'review', 10, 'Bloomberg henkilökohtainen kontakti');


-- ==========================================
-- 3. PERSONAL -KONTAKTIT (henkilökohtaiset)
-- ==========================================

-- Partial match: pasi.penkkala osuu kaikkiin pasi.penkkala@*.com

INSERT INTO outlook.contact_lists
  (list_type, identifier_type, identifier_value, target_category, recommended_action, priority, notes)
VALUES
  ('personal', 'from_address_contains', 'pasi.penkkala', 'personal_communication', 'review', 15, 'Henkilökohtainen kontakti'),
  ('personal', 'from_address_contains', 'outi.penkkala', 'personal_communication', 'review', 15, 'Henkilökohtainen kontakti'),
  ('personal', 'from_address_contains', 'janne.maliranta', 'personal_communication', 'review', 15, 'Henkilökohtainen kontakti'),
  ('personal', 'from_address_contains', 'sara.saksi', 'personal_communication', 'review', 15, 'Henkilökohtainen kontakti'),
  ('personal', 'from_address_contains', 'kalle.saksi', 'personal_communication', 'review', 15, 'Henkilökohtainen kontakti'),
  ('personal', 'from_address_contains', 'heidi.pappila', 'personal_communication', 'review', 15, 'Henkilökohtainen kontakti'),
  ('personal', 'from_address_contains', 'marjo.pappila', 'personal_communication', 'review', 15, 'Henkilökohtainen kontakti'),
  ('personal', 'from_address_contains', 'hannu.helander', 'personal_communication', 'review', 15, 'Henkilökohtainen kontakti'),
  ('personal', 'from_address_contains', 'lauri.vähämäki', 'personal_communication', 'review', 15, 'Henkilökohtainen kontakti'),
  ('personal', 'from_address_contains', 'henri.pappila', 'personal_communication', 'review', 15, 'Henkilökohtainen kontakti'),
  ('personal', 'from_address_contains', 'marcus.edenwall', 'personal_communication', 'review', 15, 'Henkilökohtainen kontakti')

ON CONFLICT (list_type, identifier_type, identifier_value) DO NOTHING;


-- ==========================================
-- 4. BUSINESS_CRITICAL -DOMAINIT
-- ==========================================

-- Tärkeät yhteistyökumppanit ja asiakkaat (domain-taso)

INSERT INTO outlook.contact_lists
  (list_type, identifier_type, identifier_value, target_category, recommended_action, priority, notes)
VALUES
  ('business_critical', 'from_domain', 'kaivonporaus.com', 'business_critical', 'review', 30, 'Tärkeä yhteistyökumppani'),
  ('business_critical', 'from_domain', 'cactos.fi', 'business_critical', 'review', 30, 'Tärkeä yhteistyökumppani')

ON CONFLICT (list_type, identifier_type, identifier_value) DO NOTHING;


-- ==========================================
-- 5. INTERNAL -DOMAINIT
-- ==========================================

-- Oma yritys ja sisäiset domainit

INSERT INTO outlook.contact_lists
  (list_type, identifier_type, identifier_value, target_category, recommended_action, priority, notes)
VALUES
  ('internal', 'from_domain', 'repoxcapital.fi', 'internal', 'review', 30, 'Oma yritys'),
  ('internal', 'from_domain', 'corenum.fi', 'internal', 'review', 30, 'Oma yritys / sisäinen'),
  ('internal', 'from_domain', 'sharkaccount.fi', 'internal', 'review', 30, 'Oma yritys / sisäinen')

ON CONFLICT (list_type, identifier_type, identifier_value) DO NOTHING;


-- ==========================================
-- YHTEENVETO
-- ==========================================

SELECT
  list_type,
  COUNT(*) as contact_count,
  STRING_AGG(DISTINCT target_category, ', ') as target_categories
FROM outlook.contact_lists
WHERE is_active = TRUE
GROUP BY list_type
ORDER BY
  CASE list_type
    WHEN 'vip_finance' THEN 1
    WHEN 'vip_personal' THEN 2
    WHEN 'personal' THEN 3
    WHEN 'business_critical' THEN 4
    WHEN 'internal' THEN 5
  END;

-- Näytä kaikki lisätyt kontaktit
SELECT
  list_type,
  identifier_type,
  identifier_value,
  target_category,
  priority,
  notes
FROM outlook.contact_lists
WHERE is_active = TRUE
ORDER BY
  CASE list_type
    WHEN 'vip_personal' THEN 1
    WHEN 'personal' THEN 2
    WHEN 'vip_finance' THEN 3
    WHEN 'business_critical' THEN 4
    WHEN 'internal' THEN 5
  END,
  priority,
  identifier_value;
