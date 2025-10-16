# Gateway Integration Guide

## Yleiskatsaus

Gateway-workflow on nyt valmis käyttöön. Se toteuttaa sääntöpohjaisen luokittelun ennen AI-analyysiä.

## Valmiit Workflowt

### 1. **Outlook_Gateway_Rules.json** (Perusversio)
- Yksinkertainen toteutus testaukseen
- Manuaalinen triggeri
- Sisältää testidatan

### 2. **Outlook_Gateway_Enhanced.json** (Tuotantoversio)
- Webhook-pohjainen
- Batch-käsittely
- Metriikoiden tallennus
- Integroitu AI-fallback

## Tietokannan tila

### Aktiiviset säännöt (34 kpl)
- **Financial News**: Inderes, Ålandsbanken, Nordea (korkea volyymi)
- **Business Critical**: SharkAccount (100% tarkkuus)
- **Notifications**: Microsoft, Thermia, Solarweb
- **Marketing**: Microsoft Store
- **Spam**: Squarespace forms

### Kattavuus
- Arvioitu: ~23% sähköposteista osuu sääntöihin
- Inderes yksin: 1097 osumaa (suurin yksittäinen)
- AWS SES: 908 osumaa

## Integraatio-ohjeet

### Vaihe 1: Import n8n:ään

1. Avaa n8n UI
2. Go to Workflows → Import
3. Tuo `Outlook_Gateway_Enhanced.json`
4. Tallenna workflow

### Vaihe 2: Muokkaa Outlook Validate Select

Etsi `Outlook Validate Select.json` workflowsta kohta jossa valitaan analysoitavat emailit ja lisää Gateway-kutsu:

```javascript
// VANHA: Suoraan AI:lle
// prepare_for_ai → call_ai_workflow

// UUSI: Ensin Gateway, sitten AI tarvittaessa
// prepare_emails → call_gateway → [rule_match TAI ai_needed]
```

Lisää uusi Execute Workflow node:
- Name: `call_gateway`
- Workflow: `Outlook Gateway Enhanced`
- Pass email data as input

### Vaihe 3: Testaus

#### A. Yksikkötestaus Gatewayssä
1. Käytä Manual Test triggeriä
2. Tarkista tulokset:
   - Inderes → financial_news
   - SharkAccount → business_critical
   - Bloomberg → needs_ai (ei sääntöä)

#### B. Integraatiotestaus
1. Aja muutama email Validate Select kautta
2. Tarkista lokista:
```sql
SELECT * FROM outlook.process_log
WHERE process_name = 'gateway_rule_application'
ORDER BY created_at DESC LIMIT 5;
```

### Vaihe 4: Monitorointi

#### Päivittäinen seuranta
```sql
-- Sääntöjen käyttö tänään
SELECT
  DATE(decided_at) as date,
  COUNT(*) FILTER (WHERE model_name = 'rule_engine') as rule_classifications,
  COUNT(*) FILTER (WHERE model_name LIKE 'claude%') as ai_classifications,
  ROUND(100.0 * COUNT(*) FILTER (WHERE model_name = 'rule_engine') / COUNT(*), 1) as rule_percentage
FROM outlook.email_interest
WHERE decided_at >= CURRENT_DATE
GROUP BY 1;
```

#### Sääntökohtainen tehokkuus
```sql
-- Top 10 käytetyintä sääntöä
SELECT
  rule_conditions,
  primary_category,
  COUNT(*) as usage_count,
  AVG(confidence) as avg_confidence
FROM outlook.email_interest
WHERE model_name = 'rule_engine'
  AND decided_at >= NOW() - INTERVAL '7 days'
GROUP BY 1, 2
ORDER BY 3 DESC
LIMIT 10;
```

## Suorituskyky

### Ennen Gatewaytä
- Kaikki emailit → AI
- Keskimäärin 3-5s per email
- Kustannus: ~$0.001 per email

### Gatewayn kanssa
- 23% emaileista → Säännöt (50ms)
- 77% emaileista → AI (3-5s)
- Säästö: ~25% AI-kustannuksissa
- Nopeutus: 23% emaileista 60x nopeammin

## Seuraavat askeleet

### Välittömät (Tänään)
1. ✅ Tuo Gateway n8n:ään
2. ⏳ Testaa manuaalisesti
3. ⏳ Integroi Validate Select workflowiin

### Lähipäivät
1. Lisää Bloomberg-säännöt:
```sql
INSERT INTO outlook.classification_rules (version, feature, key_value, target_category, priority)
VALUES
  ('manual_2025-10-14', 'from_address', 'noreply@news.bloomberg.com', 'financial_news', 10),
  ('manual_2025-10-14', 'from_domain', 'bloomberg.com', 'financial_news', 30);
```

2. Seuraa metriikoita viikon ajan
3. Optimoi sääntöjä tarpeen mukaan

### Viikottainen ylläpito
1. Aja Category Discovery Analysis uusien sääntöjen louhintaan
2. Tarkista false positive -raportit
3. Päivitä säännöt tarvittaessa

## Rollback-suunnitelma

Jos ongelmia ilmenee:

```sql
-- Deaktivoi kaikki säännöt
UPDATE outlook.classification_rules
SET is_active = FALSE
WHERE version = 'cda_2025-10-13T10-55-08';

-- TAI poista Gateway-kutsu Validate Select workflowsta
```

## Yhteystiedot ja tuki

- Dokumentaatio: Tämä tiedosto + CLAUDE.md
- Tietokanta: PostgreSQL `outlook` schema
- n8n workflowt: `c:\Coding\n8n\wf\n8n_outlook\`

## Versionhallinta

- Gateway v1.0: Perustoiminnallisuus
- Gateway Enhanced v1.0: Tuotantovalmis batch-käsittelyllä
- Rules version: cda_2025-10-13T10-55-08 (34 sääntöä)

---
Päivitetty: 2025-10-14
Tekijä: Gateway Implementation