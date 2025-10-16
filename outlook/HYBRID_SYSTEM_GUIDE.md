# Hybridi-järjestelmä: Dynaaminen AI-promptti + Välimuisti

## Yleiskatsaus

Hybridi-järjestelmä yhdistää dynaamiset säännöt ja tehokkaan välimuistin. AI "oppii" sääntöjen evoluution kautta.

## Arkkitehtuuri

```
┌─────────────────────────────────────────────────────────────┐
│                    Category Discovery Analysis               │
│                  (Viikottain/Päivittäin)                    │
└────────────────────────┬─────────────────────────────────────┘
                         ▼
              ┌──────────────────────┐
              │ classification_rules  │
              │  (34+ sääntöä)        │
              └──────────┬───────────┘
                         │
        ┌────────────────┴────────────────┐
        ▼                                  ▼
┌──────────────────┐            ┌──────────────────────┐
│  rules_snapshot  │            │      Gateway         │
│   (välimuisti)   │            │  (reaaliaikainen)    │
└────────┬─────────┘            └──────────────────────┘
         │
         ▼
┌──────────────────────┐
│  Validate Analyse    │
│  (AI + säännöt)      │
└──────────────────────┘
```

## Komponentit

### 1. Rules Snapshot (Välimuisti)

**Taulu:** `outlook.rules_snapshot`

**Kentät:**
- `version`: Uniikki versiotunniste (esim. `hybrid_2025-10-14_r34`)
- `rules_json`: Säännöt JSON-muodossa
- `rules_dsl`: Ihmisluettava DSL promptille
- `expires_at`: Välimuistin vanhenemisaika (TTL 24h)
- `is_active`: Onko aktiivinen

**Päivitys:**
- Automaattinen invalidointi kun CDA ajaa
- TTL-pohjainen vanheneminen (24h)
- Manuaalinen invalidointi tarvittaessa

### 2. Build Batch Prompt (Dynaaminen)

**Logiikka:**
1. Tarkista välimuisti (`rules_snapshot`)
2. Jos vanhentunut/puuttuu → luo uusi:
   - Hae säännöt `classification_rules`
   - Luo DSL-muoto
   - Tallenna snapshot
3. Injektoi säännöt system promptiin
4. Lisää versiotunniste

**DSL-esimerkki:**
```
=== FINANCIAL_NEWS ===
- JOS from_domain="inderes.fi" → financial_news (KORKEA tarkkuus, 1097 osumaa, toimenpide: review)
- JOS message_id_domain="newsletter.inderes.fi" → financial_news (KORKEA tarkkuus, 233 osumaa, toimenpide: review)

=== BUSINESS_CRITICAL ===
- JOS from_address="niina.vuorinen@sharkaccount.fi" → business_critical (KORKEA tarkkuus, 10 osumaa, toimenpide: review)
```

### 3. Gateway (Reaaliaikainen)

**Toiminta:**
- Lukee AINA tuoreimmat säännöt
- Ei käytä välimuistia (nopeus tärkeä)
- Tallentaa `rules_version` päätökseen

### 4. Versiointi ja jäljitettävyys

**Tallennettavat tiedot:**
- `email_interest.rule_conditions`: Käytetty sääntö
- `process_log.metadata.rules_version`: Versio
- `ai_analysis_log.raw_analysis`: Koko AI-vastaus

## Käyttöönotto

### 1. Luo tietokantataulut

```sql
-- Aja create_rules_snapshot.sql
```

### 2. Päivitä Validate Analyse workflow

Korvaa `build_batch_prompt_cache` solmu hybrid-versiolla:
- Lisää postgres-node: `get_rules_snapshot`
- Lisää postgres-node: `load_classification_rules`
- Lisää postgres-node: `save_rules_snapshot`
- Päivitä code-node: käytä `build_batch_prompt_cache_HYBRID.js`

### 3. Päivitä Gateway

Lisää version tallennus:
```javascript
// gateway_apply_rules solmussa
const currentVersion = await getCurrentRulesVersion();
// ...
decision.rules_version = currentVersion;
```

## Hyödyt

### 1. Tehokkuus
- Välimuisti vähentää tietokantakutsuja
- Prompt caching vähentää AI-kustannuksia
- TTL tasapainottaa tuoreuden ja tehokkuuden

### 2. Oppiminen
- Viikko 1: 34 sääntöä
- Viikko 2: 50 sääntöä (CDA löytää lisää)
- Viikko 3: 65 sääntöä
- AI saa aina päivitetyt säännöt

### 3. Jäljitettävyys
- Jokainen päätös sisältää version
- Voidaan analysoida mikä versio toimi parhaiten
- Mahdollistaa A/B-testauksen

## Monitorointi

### Cache-status
```sql
SELECT * FROM outlook.rules_cache_status;
```

### Versiohistoria
```sql
SELECT
    version,
    rules_count,
    avg_precision,
    usage_count,
    created_at
FROM outlook.rules_snapshot
ORDER BY created_at DESC;
```

### Sääntöjen käyttö per versio
```sql
SELECT
    ei.rules_version,
    COUNT(*) as decisions,
    AVG(ei.confidence) as avg_confidence
FROM outlook.email_interest ei
WHERE ei.model_name = 'claude'
GROUP BY ei.rules_version
ORDER BY 1 DESC;
```

## Ylläpito

### Välimuistin tyhjennys
```sql
SELECT outlook.invalidate_rules_snapshots('Manual refresh');
```

### TTL:n säätö
```sql
UPDATE outlook.rules_snapshot
SET ttl_hours = 12  -- Vaihda 24h → 12h
WHERE is_active = TRUE;
```

### Pakota uusi snapshot
1. Invalidoi vanha
2. Seuraava Analyse-ajo luo uuden

## Tulevaisuuden parannukset

1. **A/B testaus**: Aja osa emaileista eri säännöillä
2. **Automaattinen optimointi**: Poista heikot säännöt
3. **Kontekstuaaliset säännöt**: Aika/päivä-pohjaisia sääntöjä
4. **Feedback loop**: Käyttäjän korjaukset → uudet säännöt

---
Päivitetty: 2025-10-14
Versio: 1.0 Hybrid