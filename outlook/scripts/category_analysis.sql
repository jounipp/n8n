-- ==========================================
-- KATEGORIA-ANALYYSI: Selvitetään käytössä olevat kategoriat ja domainit
-- ==========================================

-- 1. KATEGORIOIDEN JAKAUMA (email_interest)
-- Näyttää mitä kategorioita AI on käyttänyt ja kuinka usein
SELECT
  primary_category,
  COUNT(*) as viesti_count,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) as prosentti,
  MIN(decided_at) as ensimmainen,
  MAX(decided_at) as viimeisin,
  COUNT(DISTINCT model_name) as eri_mallit,
  AVG(confidence) as keskivarmuus
FROM outlook.email_interest
WHERE decided_at IS NOT NULL
GROUP BY primary_category
ORDER BY viesti_count DESC;

-- ==========================================
-- 2. DOMAINIT KATEGORIOITTAIN
-- ==========================================

-- 2A. TOP DOMAINIT jokaisessa kategoriassa
WITH domain_category AS (
  SELECT
    ei.primary_category,
    e.from_domain,
    COUNT(*) as viesti_count,
    AVG(ei.confidence) as avg_confidence,
    STRING_AGG(DISTINCT e.subject, ' | ') FILTER (WHERE e.subject IS NOT NULL) as sample_subjects
  FROM outlook.email_interest ei
  JOIN outlook.emails_ingest e ON e.message_id = ei.message_id
  WHERE ei.primary_category IS NOT NULL
    AND e.from_domain IS NOT NULL
    AND e.is_deleted = FALSE
  GROUP BY ei.primary_category, e.from_domain
)
SELECT
  primary_category,
  from_domain,
  viesti_count,
  ROUND(avg_confidence::numeric, 1) as avg_confidence,
  LEFT(sample_subjects, 200) as sample_subjects_preview
FROM domain_category
WHERE viesti_count >= 3  -- Vain domainit joilla 3+ viestiä
ORDER BY primary_category, viesti_count DESC;


-- ==========================================
-- 3. INDUSTRY_NEWS LÄHTEET
-- ==========================================

-- 3A. Kaikki industry_news domainit
SELECT
  'INDUSTRY_NEWS' as kategoria,
  e.from_domain,
  COUNT(*) as viesti_count,
  COUNT(DISTINCT e.from_address) as eri_lahettajia,
  STRING_AGG(DISTINCT e.from_address, ', ') FILTER (WHERE e.from_address IS NOT NULL) as lahettajat,
  ARRAY_AGG(DISTINCT SUBSTRING(e.subject, 1, 80)) FILTER (WHERE e.subject IS NOT NULL) as sample_subjects
FROM outlook.email_interest ei
JOIN outlook.emails_ingest e ON e.message_id = ei.message_id
WHERE ei.primary_category = 'industry_news'
  AND e.is_deleted = FALSE
GROUP BY e.from_domain
ORDER BY viesti_count DESC;

-- 3B. Industry news lähettäjät joilla LIST-ID (uutiskirjeet)
SELECT
  'INDUSTRY_NEWS (uutiskirjeet)' as tyyppi,
  e.from_domain,
  e.list_id,
  COUNT(*) as viesti_count,
  STRING_AGG(DISTINCT SUBSTRING(e.subject, 1, 100), ' | ') as aihe_esimerkit
FROM outlook.email_interest ei
JOIN outlook.emails_ingest e ON e.message_id = ei.message_id
WHERE ei.primary_category = 'industry_news'
  AND e.list_id IS NOT NULL
  AND e.is_deleted = FALSE
GROUP BY e.from_domain, e.list_id
ORDER BY viesti_count DESC;


-- ==========================================
-- 4. REGULATORY LÄHTEET
-- ==========================================

-- 4A. Kaikki regulatory domainit ja lähettäjät
SELECT
  'REGULATORY' as kategoria,
  e.from_domain,
  e.from_address,
  COUNT(*) as viesti_count,
  ARRAY_AGG(DISTINCT e.subject) FILTER (WHERE e.subject IS NOT NULL) as subjects
FROM outlook.email_interest ei
JOIN outlook.emails_ingest e ON e.message_id = ei.message_id
WHERE ei.primary_category = 'regulatory'
  AND e.is_deleted = FALSE
GROUP BY e.from_domain, e.from_address
ORDER BY viesti_count DESC;

-- 4B. Avainsanat regulatory-viesteissä
SELECT
  'REGULATORY avainsanat aiheissa' as tyyppi,
  LOWER(word) as avainsana,
  COUNT(*) as esiintyy_viesteissa
FROM (
  SELECT
    unnest(string_to_array(LOWER(e.subject), ' ')) as word
  FROM outlook.email_interest ei
  JOIN outlook.emails_ingest e ON e.message_id = ei.message_id
  WHERE ei.primary_category = 'regulatory'
    AND e.subject IS NOT NULL
    AND e.is_deleted = FALSE
) words
WHERE LENGTH(word) > 3  -- Ohita lyhyet sanat
GROUP BY LOWER(word)
ORDER BY esiintyy_viesteissa DESC
LIMIT 30;


-- ==========================================
-- 5. PERSONAL_COMMUNICATION POIKKEUKSET
-- ==========================================

-- 5A. Personal communication lähettäjät (ei-bulk)
SELECT
  'PERSONAL_COMMUNICATION' as kategoria,
  e.from_domain,
  e.from_address,
  COUNT(*) as viesti_count,
  -- Onko bulk-merkkejä?
  BOOL_OR(e.list_id IS NOT NULL) as has_list_id,
  BOOL_OR(e.unsubscribe_link IS NOT NULL) as has_unsubscribe,
  BOOL_OR(e.precedence = 'bulk') as is_bulk_precedence,
  BOOL_OR(e.auto_submitted IS NOT NULL) as has_auto_submitted,
  STRING_AGG(DISTINCT SUBSTRING(e.subject, 1, 80), ' | ') as sample_subjects
FROM outlook.email_interest ei
JOIN outlook.emails_ingest e ON e.message_id = ei.message_id
WHERE ei.primary_category = 'personal_communication'
  AND e.is_deleted = FALSE
GROUP BY e.from_domain, e.from_address
ORDER BY viesti_count DESC;

-- 5B. Personal communication: todella henkilökohtaiset (ei mitään bulk-merkkejä)
SELECT
  'PERSONAL (ei-bulk)' as tyyppi,
  e.from_domain,
  e.from_address,
  COUNT(*) as viesti_count,
  AVG(ei.confidence) as avg_confidence,
  STRING_AGG(DISTINCT SUBSTRING(e.subject, 1, 60), ' | ') as subjects
FROM outlook.email_interest ei
JOIN outlook.emails_ingest e ON e.message_id = ei.message_id
WHERE ei.primary_category = 'personal_communication'
  AND e.list_id IS NULL
  AND e.unsubscribe_link IS NULL
  AND e.precedence IS DISTINCT FROM 'bulk'
  AND e.is_deleted = FALSE
GROUP BY e.from_domain, e.from_address
HAVING COUNT(*) >= 2  -- Vähintään 2 viestiä
ORDER BY viesti_count DESC;


-- ==========================================
-- 6. KAIKKI KATEGORIAT: Domain-yhteenveto
-- ==========================================

SELECT
  ei.primary_category,
  COUNT(DISTINCT e.from_domain) as uniikkeja_domaineja,
  COUNT(DISTINCT e.from_address) as uniikkeja_lahettajia,
  COUNT(*) as viesteja_yhteensa,
  -- Bulk-indikaattorit
  ROUND(100.0 * COUNT(*) FILTER (WHERE e.list_id IS NOT NULL) / NULLIF(COUNT(*), 0), 1) as pct_has_list_id,
  ROUND(100.0 * COUNT(*) FILTER (WHERE e.unsubscribe_link IS NOT NULL) / NULLIF(COUNT(*), 0), 1) as pct_has_unsubscribe,
  ROUND(100.0 * COUNT(*) FILTER (WHERE e.precedence = 'bulk') / NULLIF(COUNT(*), 0), 1) as pct_bulk_precedence
FROM outlook.email_interest ei
JOIN outlook.emails_ingest e ON e.message_id = ei.message_id
WHERE ei.primary_category IS NOT NULL
  AND e.is_deleted = FALSE
GROUP BY ei.primary_category
ORDER BY viesteja_yhteensa DESC;


-- ==========================================
-- 7. CLASSIFICATION_RULES: Mitä sääntöjä on olemassa?
-- ==========================================

SELECT
  target_category,
  feature,
  COUNT(*) as saantoja_maara,
  STRING_AGG(DISTINCT key_value, ', ') FILTER (WHERE key_value IS NOT NULL) as key_values_sample
FROM outlook.classification_rules
WHERE is_active = TRUE
GROUP BY target_category, feature
ORDER BY target_category, feature;


-- ==========================================
-- 8. PUUTTUVAT SÄÄNNÖT: Kategoriat joilla EI ole classification_rules
-- ==========================================

WITH categories_in_use AS (
  SELECT DISTINCT primary_category
  FROM outlook.email_interest
  WHERE primary_category IS NOT NULL
),
categories_with_rules AS (
  SELECT DISTINCT target_category
  FROM outlook.classification_rules
  WHERE is_active = TRUE
)
SELECT
  ciu.primary_category,
  CASE
    WHEN cwr.target_category IS NOT NULL THEN 'Sääntöjä olemassa'
    ELSE 'EI SÄÄNTÖJÄ - kandidaatti uusille säännöille'
  END as saannot_status,
  (SELECT COUNT(*) FROM outlook.email_interest ei WHERE ei.primary_category = ciu.primary_category) as viesteja_kategoriassa
FROM categories_in_use ciu
LEFT JOIN categories_with_rules cwr ON cwr.target_category = ciu.primary_category
ORDER BY viesteja_kategoriassa DESC;


-- ==========================================
-- 9. EHDOTUKSET UUSIKSI SÄÄNNÖIKSI
-- Etsii domainit/lähettäjät joilla korkea konsistenssi mutta EI vielä sääntöä
-- ==========================================

WITH candidate_domains AS (
  SELECT
    ei.primary_category,
    e.from_domain,
    COUNT(*) as msg_count,
    AVG(ei.confidence) as avg_confidence,
    -- Tarkista onko jo sääntö
    EXISTS(
      SELECT 1 FROM outlook.classification_rules cr
      WHERE cr.is_active = TRUE
        AND cr.feature = 'from_domain'
        AND cr.key_value = e.from_domain
    ) as has_rule
  FROM outlook.email_interest ei
  JOIN outlook.emails_ingest e ON e.message_id = ei.message_id
  WHERE ei.primary_category IS NOT NULL
    AND e.from_domain IS NOT NULL
    AND e.is_deleted = FALSE
  GROUP BY ei.primary_category, e.from_domain
)
SELECT
  primary_category,
  from_domain,
  msg_count,
  ROUND(avg_confidence::numeric, 1) as avg_confidence,
  CASE has_rule
    WHEN TRUE THEN 'Sääntö olemassa'
    ELSE 'EHDOKAS uudeksi säännöksi'
  END as status
FROM candidate_domains
WHERE msg_count >= 5  -- Vähintään 5 viestiä
  AND avg_confidence >= 80  -- Korkea varmuus
  AND has_rule = FALSE  -- Ei vielä sääntöä
ORDER BY primary_category, msg_count DESC;
