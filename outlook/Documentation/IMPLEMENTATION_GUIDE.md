# Toteutusohje: Contact Lists + Classification Rules

**Luotu**: 2025-10-15
**Perustuu**: SQL-analyysi + päätöskeskustelu

---

## 📦 LUODUT TIEDOSTOT:

### 1. **Tietokanta**:
- `create_contact_lists_table.sql` - Luo contact_lists taulu
- `populate_contact_lists.sql` - Alkudata (VIP, personal, internal)
- `classification_rules_FINAL.sql` - Päivitetyt classification_rules

### 2. **Logiikka**:
- `gateway_contact_lists_logic.js` - Gateway-logiikka (käyttää contact_lists)

### 3. **Dokumentaatio**:
- `CATEGORY_DECISIONS_NEEDED.md` - Päätösdokumentti (täytetty)
- `IMPLEMENTATION_GUIDE.md` - Tämä tiedosto

---

## 🎯 HYBRID-JÄRJESTELMÄ:

### Prioriteetti-järjestys:

```
1. CONTACT_LISTS (dynaamiset, ylläpidettävät)
   ├─ 10: from_address (täysi match)
   ├─ 15: from_address_contains (partial: "pasi.penkkala")
   ├─ 20: from_domain
   └─ 30: message_id_domain, list_domain, unsub_domain

2. CLASSIFICATION_RULES (staattiset, louhitut)
   ├─ 10: from_address, sender_address
   ├─ 15: reply_to_address
   ├─ 20: message_id_domain, list_domain, unsub_domain
   └─ 30: from_domain

3. AI-ANALYYSI (ei osumaa)
   └─ AI päättää primary_category
```

---

## 📊 CONTACT_LISTS TYYPIT:

### `vip_finance` (15 domainia):
```
seekingalpha.com, news.bloomberg.com, inderes.fi, nordnet.fi,
nordea.com, alandsbanken.fi, redeye.se, kauppalehti.fi jne.
```
- **EI domain-sääntöä** classification_rules:iin
- AI päättää: financial_news, marketing vai notifications

### `vip_personal` (tyhjä aluksi):
```
Lisää kun VIP-lähteistä tulee henkilökohtaisia kontakteja
Esim: john.analyst@bloomberg.com → business_critical
```

### `personal` (11 henkilöä):
```
pasi.penkkala, outi.penkkala, janne.maliranta, sara.saksi,
kalle.saksi, heidi.pappila, marjo.pappila, hannu.helander,
lauri.vähämäki, henri.pappila, marcus.edenwall
```
- Partial match: `pasi.penkkala` osuu kaikkiin `pasi.penkkala@*.com`
- → `personal_communication`

### `business_critical` (2 domainia):
```
kaivonporaus.com, cactos.fi
```
- → `business_critical`

### `internal` (3 domainia):
```
repoxcapital.fi, corenum.fi, sharkaccount.fi
```
- → `internal`

---

## 🚀 KÄYTTÖÖNOTTO-OHJE:

### VAIHE 1: Luo contact_lists taulu

```bash
psql -U <user> -d <database> -f db_outlook/create_contact_lists_table.sql
```

**Tarkista**:
```sql
\d outlook.contact_lists
SELECT COUNT(*) FROM outlook.contact_lists;  -- Pitäisi olla 0
```

---

### VAIHE 2: Populoi alkudata

```bash
psql -U <user> -d <database> -f db_outlook/populate_contact_lists.sql
```

**Tarkista**:
```sql
-- Yhteenveto tyypeittäin
SELECT list_type, COUNT(*) as count
FROM outlook.contact_lists
WHERE is_active = TRUE
GROUP BY list_type;

-- Odotettu tulos:
-- vip_finance: 15
-- personal: 11
-- business_critical: 2
-- internal: 3
-- vip_personal: 0
```

---

### VAIHE 3: Päivitä classification_rules

```bash
psql -U <user> -d <database> -f db_outlook/classification_rules_FINAL.sql
```

**Tarkista**:
```sql
-- Uudet säännöt
SELECT target_category, COUNT(*) as count
FROM outlook.classification_rules
WHERE version = 'cda_2025-10-15T14-00-00'
  AND is_active = TRUE
GROUP BY target_category;

-- Odotettu: ~20-25 uutta sääntöä
```

---

### VAIHE 4: Päivitä Gateway workflow

#### A) Lataa contact_lists + classification_rules

Lisää SQL-node `Outlook Validate Select` workflowiin ENNEN Gateway-nodea:

```sql
-- Node: load_contact_lists
SELECT
  list_type,
  identifier_type,
  identifier_value,
  target_category,
  recommended_action,
  priority,
  notes
FROM outlook.contact_lists
WHERE is_active = TRUE
ORDER BY priority ASC, list_type;
```

#### B) Korvaa Gateway-logiikka

Kopioi `gateway_contact_lists_logic.js` sisältö → Gateway Code nodeen

**HUOM**: Muuta input-muuttujat:
```javascript
// Vanhat:
const email = $input.item.json.email || $input.item.json;
const rules = $('load_active_rules').all().map(r => r.json);

// Uudet:
const email = $input.item.json.email || $input.item.json;
const contactLists = $('load_contact_lists').all().map(r => r.json);
const classificationRules = $('load_classification_rules').all().map(r => r.json);

// Kutsu
const result = applyGateway(email, contactLists, classificationRules);
return result;
```

---

### VAIHE 5: Päivitä AI-prompti

**Tiedosto**: `Outlook Validate Analyse` workflow → `build_batch_prompt_cache` node

#### Muutos 1: Financial vs. Industry määritelmät

**Vanha**:
```javascript
const system_prompt_categories = `
PRIMARY_CATEGORY LUOKITTELU (PAKOLLINEN):

1. business_critical
2. personal_communication
3. financial_news
4. marketing
5. notifications
6. industry_news
7. internal
8. regulatory
9. spam_low_value
10. uncategorized
`;
```

**Uusi**:
```javascript
const system_prompt_categories = `
PRIMARY_CATEGORY LUOKITTELU (PAKOLLINEN):

1. business_critical
   - Kriittiset yhteistyökumppanit, tärkeät asiakkaat
   - Vaatii toimenpiteitä tai vastausta

2. personal_communication
   - Henkilökohtaiset 1:1 viestit
   - EI list_id, EI unsubscribe_link
   - Nimetyt kontaktit

3. financial_news
   - KAIKKI rahoitukseen/talouteen liittyvät uutiset
   - Sijoitusanalyysit, osakesuositukset, markkinauutiset
   - Pankki/välittäjäviestit
   - Bloomberg, SeekingAlpha, Inderes, Nordnet jne.

4. industry_news
   - Teknologia, energia, IT-alan uutiset (EI rahoitus)
   - Alakohtaiset uutiset jotka EIVÄT liity rahoitukseen
   - Esim: KNX-standardi, IoT, teollisuus

5. marketing
   - Mainokset, kampanjat, myynninedistäminen
   - Upsell-viestit, tarjoukset

6. notifications
   - Järjestelmäilmoitukset, tilin päivitykset
   - Microsoft, LinkedIn, teknologia-palvelut

7. internal
   - Oman yrityksen sisäiset viestit
   - repoxcapital.fi, corenum.fi, sharkaccount.fi

8. regulatory
   - Regulatory/compliance-AIHEISIA uutisia ja analyysejä
   - EI viranomaisviestejä (niitä ei tule sähköpostilla)
   - FINMA, EBA, EU-direktiivit, sääntelymuutokset

9. spam_low_value
   - Roskaposti, ei-toivotut viestit

10. uncategorized
   - Vain jos mikään muu ei sovi
`;
```

#### Muutos 2: Regulatory-ohje

Lisää promptiin:
```javascript
HUOM REGULATORY-KATEGORIA:
- Käytä VAIN kun aihe liittyy regulatory/compliance-asioihin
- Esim: "Uusi EU-direktiivi", "FINMA päätös", "Compliance-muutos"
- ÄLÄ käytä viranomaisten lähettämille viesteille (niitä ei tule)
```

---

### VAIHE 6: Testaa järjestelmä

#### Test 1: Contact Lists - Personal
```sql
-- Lähetä testimiesti:
-- From: pasi.penkkala@gmail.com
-- Odotettu: personal_communication (contact_lists match)
```

#### Test 2: Contact Lists - VIP Finance
```sql
-- Lähetä testimiesti:
-- From: noreply@seekingalpha.com
-- Odotettu: AI päättää (ei sääntöä, mutta vip_finance listalla)
```

#### Test 3: Contact Lists - Internal
```sql
-- Lähetä testimiesti:
-- From: anyone@repoxcapital.fi
-- Odotettu: internal (contact_lists + classification_rules)
```

#### Test 4: Classification Rules
```sql
-- Lähetä testimiesti:
-- From: notifications@microsoft.com
-- Odotettu: notifications (classification_rules match)
```

---

## 📈 ODOTETUT TULOKSET:

### Gateway-osuma%:
```
Ennen: ~20% (vain classification_rules)
Jälkeen: ~85% (contact_lists + classification_rules)
```

### Kategoriajakauma (arvio):
```
financial_news: 70% (VIP-lähteet pääosin AI:n kautta)
notifications: 12%
industry_news: 7%
marketing: 5%
personal_communication: 2%
business_critical: 2%
internal: 1%
regulatory: <1%
```

---

## 🔧 YLLÄPITO:

### Lisää uusi henkilökohtainen kontakti:
```sql
INSERT INTO outlook.contact_lists
  (list_type, identifier_type, identifier_value, target_category, recommended_action, priority)
VALUES
  ('personal', 'from_address_contains', 'uusi.henkilö', 'personal_communication', 'review', 15);
```

### Lisää VIP-henkilö (finance-lähteestä):
```sql
INSERT INTO outlook.contact_lists
  (list_type, identifier_type, identifier_value, target_category, recommended_action, priority, notes)
VALUES
  ('vip_personal', 'from_address', 'john.analyst@bloomberg.com', 'business_critical', 'review', 10, 'Bloomberg henkilökohtainen kontakti');
```

### Lisää uusi VIP Finance -lähde:
```sql
INSERT INTO outlook.contact_lists
  (list_type, identifier_type, identifier_value, target_category, recommended_action, priority)
VALUES
  ('vip_finance', 'from_domain', 'uusilahde.com', 'financial_news', 'review', 30);
```

### Lisää internal-domain:
```sql
INSERT INTO outlook.contact_lists
  (list_type, identifier_type, identifier_value, target_category, recommended_action, priority)
VALUES
  ('internal', 'from_domain', 'uusiyritys.fi', 'internal', 'review', 30);
```

---

## 🐛 VIANMÄÄRITYS:

### Ongelma: Contact lists ei osu
```sql
-- Tarkista onko contact listalla:
SELECT * FROM outlook.contact_lists
WHERE identifier_value ILIKE '%haettu_arvo%'
  AND is_active = TRUE;

-- Tarkista email-featuren normalisointi:
SELECT normalizeEmail('Test User <pasi.penkkala@gmail.com>');
-- Pitäisi palauttaa: pasi.penkkala@gmail.com
```

### Ongelma: VIP-henkilö menee financial_news (ei business_critical)
```sql
-- Tarkista onko vip_personal listalla:
SELECT * FROM outlook.contact_lists
WHERE list_type = 'vip_personal'
  AND identifier_value = 'john.analyst@bloomberg.com';

-- Jos ei, lisää:
INSERT INTO outlook.contact_lists
  (list_type, identifier_type, identifier_value, target_category, recommended_action, priority)
VALUES
  ('vip_personal', 'from_address', 'john.analyst@bloomberg.com', 'business_critical', 'review', 10);
```

### Ongelma: AI luokittelee väärin financial vs. industry
```
→ Päivitä AI-prompti (VAIHE 5)
→ Tarkenna kategoriamääritelmät
→ Lisää esimerkkejä promptiin
```

---

## ✅ CHECKLIST:

- [ ] 1. Luo contact_lists taulu
- [ ] 2. Populoi alkudata (31 riviä)
- [ ] 3. Lisää classification_rules (~25 sääntöä)
- [ ] 4. Päivitä Gateway workflow (contact_lists + logic)
- [ ] 5. Päivitä AI-prompti (financial vs. industry)
- [ ] 6. Testaa henkilökohtainen kontakti
- [ ] 7. Testaa VIP Finance -lähde
- [ ] 8. Testaa Internal-domain
- [ ] 9. Monitoroi osuma-% (tavoite 85%+)
- [ ] 10. Dokumentoi muutokset DECISIONS_FI.md:ään

---

## 📞 SEURAAVAT VAIHEET:

1. **Backfill-korjaus** (deterministiset säännöt):
   - Korjaa olemassa olevat luokitukset contact_lists + classification_rules perusteella
   - Erillinen projekti (ei sekoita tähän)

2. **Rules Discovery** (jatkuva):
   - Aja Category Discovery Analysis uudelleen 1-2 viikon välein
   - Tunnista uusia domain/address -kandidaatteja
   - Lisää contact_lists / classification_rules tauluihin

3. **Monitorointi**:
   - Gateway-osuma% (tavoite 85%+)
   - AI-kustannukset (tavoite -60%)
   - Kategoria-tarkkuus (validoi satunnaisia viestejä)

---

**Valmis käyttöönotolle! 🚀**
