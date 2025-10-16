-- ==========================================
-- KATEGORIA-ANALYYSI V2: Korjattu versio paremmilla esimerkeillä
-- ==========================================

-- 1. KATEGORIOIDEN JAKAUMA (email_interest)
SELECT
  primary_category,
  COUNT(*) as viesti_count,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) as prosentti,
  MIN(decided_at) as ensimmainen,
  MAX(decided_at) as viimeisin,
  COUNT(DISTINCT model_name) as eri_mallit,
  ROUND(AVG(confidence)::numeric, 1) as keskivarmuus
FROM outlook.email_interest
WHERE decided_at IS NOT NULL
GROUP BY primary_category
ORDER BY viesti_count DESC;

-- ==========================================
-- 2. TOP DOMAINIT KATEGORIOITTAIN (paranneltu)
-- ==========================================

WITH domain_stats AS (
  SELECT
    ei.primary_category,
    e.from_domain,
    COUNT(*) as viesti_count,
    ROUND(AVG(ei.confidence)::numeric, 1) as avg_confidence
  FROM outlook.email_interest ei
  JOIN outlook.emails_ingest e ON e.message_id = ei.message_id
  WHERE ei.primary_category IS NOT NULL
    AND e.from_domain IS NOT NULL
    AND e.is_deleted = FALSE
  GROUP BY ei.primary_category, e.from_domain
  HAVING COUNT(*) >= 3
),
samples AS (
  SELECT DISTINCT ON (ds.primary_category, ds.from_domain)
    ds.primary_category,
    ds.from_domain,
    ds.viesti_count,
    ds.avg_confidence,
    SUBSTRING(e.subject, 1, 150) as sample_subject
  FROM domain_stats ds
  JOIN outlook.emails_ingest e ON e.from_domain = ds.from_domain
  WHERE e.subject IS NOT NULL
  ORDER BY ds.primary_category, ds.from_domain, e.received_datetime DESC
)
SELECT * FROM samples
ORDER BY primary_category, viesti_count DESC;


-- ==========================================
-- 3. INDUSTRY_NEWS ANALYYSI
-- ==========================================

-- 3A. Industry news domainit ja lähettäjät
WITH industry_stats AS (
  SELECT
    e.from_domain,
    COUNT(*) as viesti_count,
    COUNT(DISTINCT e.from_address) as eri_lahettajia,
    ARRAY_AGG(DISTINCT e.from_address) FILTER (WHERE e.from_address IS NOT NULL) as lahettajat,
    BOOL_OR(e.list_id IS NOT NULL) as has_newsletter,
    BOOL_OR(e.unsubscribe_link IS NOT NULL) as has_unsubscribe
  FROM outlook.email_interest ei
  JOIN outlook.emails_ingest e ON e.message_id = ei.message_id
  WHERE ei.primary_category = 'industry_news'
    AND e.is_deleted = FALSE
  GROUP BY e.from_domain
)
SELECT
  'INDUSTRY_NEWS' as kategoria,
  from_domain,
  viesti_count,
  eri_lahettajia,
  ARRAY_TO_STRING(lahettajat, ', ') as lahettajat_lista,
  has_newsletter,
  has_unsubscribe
FROM industry_stats
ORDER BY viesti_count DESC;

-- 3B. Industry news aihe-esimerkit
SELECT
  e.from_domain,
  ARRAY_AGG(SUBSTRING(e.subject, 1, 100) ORDER BY e.received_datetime DESC) FILTER (WHERE e.subject IS NOT NULL) as recent_subjects
FROM outlook.email_interest ei
JOIN outlook.emails_ingest e ON e.message_id = ei.message_id
WHERE ei.primary_category = 'industry_news'
  AND e.is_deleted = FALSE
GROUP BY e.from_domain
HAVING COUNT(*) >= 2
ORDER BY COUNT(*) DESC
LIMIT 20;


-- ==========================================
-- 4. REGULATORY ANALYYSI
-- ==========================================

-- 4A. Regulatory domainit ja lähettäjät
SELECT
  'REGULATORY' as kategoria,
  e.from_domain,
  e.from_address,
  COUNT(*) as viesti_count,
  ARRAY_AGG(e.subject ORDER BY e.received_datetime DESC) FILTER (WHERE e.subject IS NOT NULL) as subjects
FROM outlook.email_interest ei
JOIN outlook.emails_ingest e ON e.message_id = ei.message_id
WHERE ei.primary_category = 'regulatory'
  AND e.is_deleted = FALSE
GROUP BY e.from_domain, e.from_address
ORDER BY viesti_count DESC;

-- 4B. Regulatory avainsanat (TOP 50)
WITH words AS (
  SELECT
    LOWER(REGEXP_REPLACE(word, '[^a-zäöå0-9]', '', 'gi')) as cleaned_word
  FROM (
    SELECT unnest(string_to_array(LOWER(e.subject), ' ')) as word
    FROM outlook.email_interest ei
    JOIN outlook.emails_ingest e ON e.message_id = ei.message_id
    WHERE ei.primary_category = 'regulatory'
      AND e.subject IS NOT NULL
      AND e.is_deleted = FALSE
  ) raw_words
  WHERE LENGTH(word) > 3
)
SELECT
  cleaned_word as avainsana,
  COUNT(*) as esiintyy_viesteissa
FROM words
WHERE cleaned_word != ''
GROUP BY cleaned_word
ORDER BY esiintyy_viesteissa DESC
LIMIT 50;


-- ==========================================
-- 5. PERSONAL_COMMUNICATION ANALYYSI
-- ==========================================

-- 5A. Personal communication: kaikki lähettäjät
SELECT
  'PERSONAL_COMMUNICATION' as kategoria,
  e.from_domain,
  e.from_address,
  COUNT(*) as viesti_count,
  BOOL_OR(e.list_id IS NOT NULL) as has_list_id,
  BOOL_OR(e.unsubscribe_link IS NOT NULL) as has_unsubscribe,
  BOOL_OR(e.precedence = 'bulk') as is_bulk_precedence,
  BOOL_OR(e.auto_submitted IS NOT NULL) as has_auto_submitted,
  ROUND(AVG(ei.confidence)::numeric, 1) as avg_confidence
FROM outlook.email_interest ei
JOIN outlook.emails_ingest e ON e.message_id = ei.message_id
WHERE ei.primary_category = 'personal_communication'
  AND e.is_deleted = FALSE
GROUP BY e.from_domain, e.from_address
ORDER BY viesti_count DESC;

-- 5B. Personal: AIDOT henkilökohtaiset (ei bulk-merkkejä)
SELECT
  'PERSONAL (ei-bulk)' as tyyppi,
  e.from_domain,
  e.from_address,
  COUNT(*) as viesti_count,
  ROUND(AVG(ei.confidence)::numeric, 1) as avg_confidence,
  ARRAY_AGG(SUBSTRING(e.subject, 1, 80) ORDER BY e.received_datetime DESC) as subjects
FROM outlook.email_interest ei
JOIN outlook.emails_ingest e ON e.message_id = ei.message_id
WHERE ei.primary_category = 'personal_communication'
  AND e.list_id IS NULL
  AND e.unsubscribe_link IS NULL
  AND (e.precedence IS NULL OR e.precedence != 'bulk')
  AND e.is_deleted = FALSE
GROUP BY e.from_domain, e.from_address
HAVING COUNT(*) >= 2
ORDER BY viesti_count DESC;


-- ==========================================
-- 6. KATEGORIOIDEN YLEISKATSAUS
-- ==========================================

SELECT
  ei.primary_category,
  COUNT(DISTINCT e.from_domain) as uniikkeja_domaineja,
  COUNT(DISTINCT e.from_address) as uniikkeja_lahettajia,
  COUNT(*) as viesteja_yhteensa,
  ROUND(AVG(ei.confidence)::numeric, 1) as avg_confidence,
  -- Bulk-indikaattorit
  ROUND(100.0 * COUNT(*) FILTER (WHERE e.list_id IS NOT NULL) / COUNT(*), 1) as pct_has_list_id,
  ROUND(100.0 * COUNT(*) FILTER (WHERE e.unsubscribe_link IS NOT NULL) / COUNT(*), 1) as pct_has_unsubscribe,
  ROUND(100.0 * COUNT(*) FILTER (WHERE e.precedence = 'bulk') / COUNT(*), 1) as pct_bulk_precedence
FROM outlook.email_interest ei
JOIN outlook.emails_ingest e ON e.message_id = ei.message_id
WHERE ei.primary_category IS NOT NULL
  AND e.is_deleted = FALSE
GROUP BY ei.primary_category
ORDER BY viesteja_yhteensa DESC;


-- ==========================================
-- 7. NYKYISET CLASSIFICATION_RULES
-- ==========================================

SELECT
  target_category,
  feature,
  COUNT(*) as saantoja_maara,
  ARRAY_AGG(DISTINCT key_value) FILTER (WHERE key_value IS NOT NULL) as key_values
FROM outlook.classification_rules
WHERE is_active = TRUE
GROUP BY target_category, feature
ORDER BY target_category, feature;


-- ==========================================
-- 8. PUUTTUVAT SÄÄNNÖT
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
    ELSE '❌ EI SÄÄNTÖJÄ - kandidaatti uusille säännöille'
  END as saannot_status,
  (SELECT COUNT(*) FROM outlook.email_interest ei WHERE ei.primary_category = ciu.primary_category) as viesteja_kategoriassa
FROM categories_in_use ciu
LEFT JOIN categories_with_rules cwr ON cwr.target_category = ciu.primary_category
ORDER BY viesteja_kategoriassa DESC;


-- ==========================================
-- 9. EHDOTUKSET UUSIKSI SÄÄNNÖIKSI
-- ==========================================

-- 9A. Domain-kandidaatit (ei vielä sääntöä)
WITH candidate_domains AS (
  SELECT
    ei.primary_category,
    e.from_domain,
    COUNT(*) as msg_count,
    ROUND(AVG(ei.confidence)::numeric, 1) as avg_confidence,
    -- Onko jo from_domain sääntö?
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
  avg_confidence,
  CASE
    WHEN has_rule THEN '✓ Sääntö olemassa'
    ELSE '💡 EHDOKAS from_domain-säännöksi'
  END as status
FROM candidate_domains
WHERE msg_count >= 5
  AND avg_confidence >= 80
  AND has_rule = FALSE
ORDER BY primary_category, msg_count DESC;

-- 9B. From_address kandidaatit (tarkemmat säännöt)
WITH candidate_addresses AS (
  SELECT
    ei.primary_category,
    e.from_address,
    COUNT(*) as msg_count,
    ROUND(AVG(ei.confidence)::numeric, 1) as avg_confidence,
    EXISTS(
      SELECT 1 FROM outlook.classification_rules cr
      WHERE cr.is_active = TRUE
        AND cr.feature = 'from_address'
        AND cr.key_value = e.from_address
    ) as has_rule
  FROM outlook.email_interest ei
  JOIN outlook.emails_ingest e ON e.message_id = ei.message_id
  WHERE ei.primary_category IS NOT NULL
    AND e.from_address IS NOT NULL
    AND e.is_deleted = FALSE
  GROUP BY ei.primary_category, e.from_address
)
SELECT
  primary_category,
  from_address,
  msg_count,
  avg_confidence,
  '💡 EHDOKAS from_address-säännöksi' as status
FROM candidate_addresses
WHERE msg_count >= 3
  AND avg_confidence >= 90
  AND has_rule = FALSE
ORDER BY primary_category, msg_count DESC
LIMIT 50;


-- ==========================================
-- 10. YHTEENVETO PUUTTUVISTA KATEGORIOISTA
-- ==========================================

SELECT
  primary_category,
  COUNT(*) as viesteja,
  COUNT(DISTINCT e.from_domain) as domaineja,
  ROUND(AVG(confidence)::numeric, 1) as avg_confidence,
  CASE
    WHEN NOT EXISTS(
      SELECT 1 FROM outlook.classification_rules cr
      WHERE cr.is_active = TRUE AND cr.target_category = ei.primary_category
    )
    THEN '❌ EI YHTÄÄN SÄÄNTÖÄ'
    ELSE '✓ Sääntöjä olemassa'
  END as rule_status
FROM outlook.email_interest ei
JOIN outlook.emails_ingest e ON e.message_id = ei.message_id
WHERE ei.primary_category IS NOT NULL
  AND e.is_deleted = FALSE
GROUP BY ei.primary_category
ORDER BY viesteja DESC;
