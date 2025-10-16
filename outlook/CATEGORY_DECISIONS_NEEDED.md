# Kategoria-päätökset: Tarvitaan vahvistus

**Luotu**: 2025-10-15
**Perustuu**: SQL-analyysi `category_analysis_v2.sql`
**Datapohja**: 8394 luokiteltua viestiä

---

## 📊 NYKYTILANNE

### Kategorioiden jakautuminen:

| Kategoria | Viestejä | % | Sääntöjä? | Domaineja |
|-----------|----------|---|-----------|-----------|
| financial_news | 6089 | 72.5% | ✅ | 17 |
| notifications | 846 | 10.1% | ✅ | 44 |
| industry_news | 574 | 6.8% | ❌ | 10 |
| marketing | 511 | 6.1% | ✅ | 23 |
| personal_communication | 173 | 2.1% | ❌ | 18 |
| business_critical | 147 | 1.8% | ✅ | 30 |
| uncategorized | 28 | 0.3% | ❌ | 4 |
| internal | 13 | 0.2% | ❌ | 4 |
| regulatory | 7 | 0.1% | ❌ | 6 |
| spam_low_value | 6 | 0.1% | ✅ | 3 |

---

## 🚨 PÄÄTÖKSET TARVITAAN (ennen sääntöjen luontia)

### 1. **BLOOMBERG & SEEKINGALPHA: Monimuotoisuus**

**Ongelma**: Samat domainit esiintyvät USEASSA kategoriassa.

#### SeekingAlpha (yhteensä 3968 viestiä):
- `financial_news`: 3159 (79.6%)
- `notifications`: 410 (10.3%)
- `marketing`: 350 (8.8%)
- `industry_news`: 49 (1.2%)

#### Bloomberg news.bloomberg.com (yhteensä 2154 viestiä):
- `financial_news`: 1642 (76.2%)
- `industry_news`: 486 (22.6%)
- `notifications`: 26 (1.2%)

**Kysymykset**:

**Q1.1**: Haluatko **yhden domain-tason säännön** per domain (yksinkertaisempi, mutta vähemmän tarkkaa)?
```
✅ VAIHTOEHTO A: seekingalpha.com → aina financial_news (yksinkertainen)
✅ VAIHTOEHTO B: Anna AI:n päättää tapauskohtaisesti (ei sääntöä)
```

**Q1.2**: Jos valitset vaihtoehdon A, mihin kategoriaan asetetaan?
```
seekingalpha.com → financial_news (enemmistö 79.6%)
news.bloomberg.com → financial_news (enemmistö 76.2%)
```

**Suositukseni**: ✅ **VAIHTOEHTO A** + enemmistökategoria
→ Yksinkertaisempi, kattaa 75%+ viesteistä oikein

---

### 2. **FINANCIAL_NEWS vs. INDUSTRY_NEWS: Raja**

**Ongelma**: Epäselvä raja kategorioiden välillä.

**Nykykäyttö datassa**:
- `financial_news`: Inderes, Bloomberg, SeekingAlpha, Nordnet, Nordea, Kauppalehti
- `industry_news`: Bloomberg (22%), SeekingAlpha (1%), Kauppalehti, KNX.org

**Kysymykset**:

**Q2.1**: Mikä on kategorioiden ero teille?

```
❓ VAIHTOEHTO A:
   financial_news = Sijoitusanalyysit, osakesuositukset, rahamarkkinat
   industry_news = Yleiset talousuutiset, yritys/toimialauutiset

❓ VAIHTOEHTO B:
   financial_news = KAIKKI rahoitukseen liittyvät uutiset
   industry_news = Teknologia, energia, IT-alan uutiset (ei-rahoitus)

❓ VAIHTOEHTO C:
   Yhdistetään molemmat → vain "financial_news"
```

**Q2.2**: Mihin kuuluvat:
- Bloomberg talousuutiset? → `financial_news` vai `industry_news`?
- Kauppalehti? → `financial_news` vai `industry_news`?
- KNX.org (teknologia-standardi)? → `industry_news` vai `marketing`?

**Suositukseni**:
```
financial_news: Kaikki rahoitus/talous (Bloomberg, Inderes, Nordea, Kauppalehti)
industry_news: Teknologia/ei-rahoitus (KNX.org)

→ Yksinkertaisempi jako, selkeämpi AI:lle
```

---

### 3. **REPOXCAPITAL.FI: Monimuotoinen käyttö**

**Ongelma**: Yksi domain, **5 eri kategoriaa**!

| Kategoria | Viestejä | % |
|-----------|----------|---|
| personal_communication | 115 | 51.8% |
| business_critical | 67 | 30.2% |
| notifications | 22 | 9.9% |
| internal | 10 | 4.5% |
| marketing | 9 | 4.1% |

**Kysymykset**:

**Q3.1**: Onko `repoxcapital.fi` oma yrityksesi/holding/kumppani?
```
❓ Kyllä → Jätä ilman domain-sääntöä (AI päättää sisällön mukaan)
❓ Ei → Luo sääntö enemmistökategoriaan (personal_communication)
```

**Q3.2**: Jos oma yritys, haluatko erottaa lähettäjät?
```
esim:
- johtaja@repoxcapital.fi → personal_communication
- info@repoxcapital.fi → notifications
- newsletter@repoxcapital.fi → marketing
```

**Suositukseni**:
- Jos oma yritys: ❌ **EI domain-sääntöä** (liian monimuotoinen)
- Lisää **address-tason säännöt** myöhemmin kun tiedät tärkeät lähettäjät

---

### 4. **PERSONAL_COMMUNICATION: Määrittely**

**Datasta**: 173 viestiä, 18 domainia

**Top domainit**:
- `repoxcapital.fi`: 115 (monet bulk-merkit)
- `kaivonporaus.com`: 20 (93.6% varmuus)
- `gmail.com`: 7 (tasapeli notifications/personal)
- `alandsbanken.fi`: 6 (mutta 30 financial_news)
- `corenum.fi`: 5

**Kysymykset**:

**Q4.1**: Mitä "personal_communication" tarkoittaa teille?
```
❓ VAIHTOEHTO A: Henkilökohtaiset 1:1 viestit (ei list_id, ei unsubscribe)
❓ VAIHTOEHTO B: Tärkeät yhteistyökumppanit (vaikka olisi newsletter)
❓ VAIHTOEHTO C: Kaikki jotka eivät ole bulk-viestejä
```

**Q4.2**: Pitäisikö `kaivonporaus.com` olla personal vai business_critical?
```
- Nyt: 20 personal, 8 business_critical
- Suositus: business_critical (jos yritysyhteistyö)
```

**Suositukseni**:
```
personal_communication: Vain AIDOT henkilökohtaiset viestit
  → Ei list_id, ei unsubscribe_link, ei bulk precedence
  → Gmail-kontaktit, yksittäiset liikekumppanit

business_critical: Tärkeät yhteistyökumppanit/asiakkaat
  → kaivonporaus.com, corenum.fi, cactos.fi
```

---

### 5. **INTERNAL: Tarpeellisuus?**

**Datasta**: Vain 13 viestiä, 4 domainia
- `repoxcapital.fi`: 10

**Kysymykset**:

**Q5.1**: Tarvitaanko "internal" erillisenä kategoriana?
```
❓ Kyllä → Pidä kategoria ja lisää säännöt myöhemmin
❓ Ei → Yhdistä "business_critical"-kategoriaan
```

**Q5.2**: Jos pidetään, mikä erottaa "internal" ja "business_critical"?
```
internal = Yrityksen sisäiset viestit (HR, IT, hallinto)?
business_critical = Ulkoiset kriittiset viestit (asiakkaat, kumppanit)?
```

**Suositukseni**:
- Jos erottelulla **ei merkitystä** → ❌ **Poista "internal"** kategoria
- Jos erottelu **tärkeää** → ✅ **Pidä**, lisää address-säännöt

---

### 6. **REGULATORY: Odotukset?**

**Datasta**: Vain 7 viestiä, 6 domainia (92.4% varmuus)

**Liian vähän dataa** → Ei voi luoda luotettavia sääntöjä.

**Kysymykset**:

**Q6.1**: Odotatko tulevaisuudessa regulatory-viestejä?
```
✅ Kyllä → Pidä kategoria, odota lisää dataa
❌ Ei → Poista kategoria AI-promptista
```

**Q6.2**: Mitä "regulatory" pitäisi sisältää?
```
❓ Viranomaisviestit (Verohallinto, PRH, Finlex)?
❓ Alakohtaiset sääntelyviestit (FINMA, EBA, EU-direktiivit)?
❓ Compliance/audit-viestit?
```

**Suositukseni**:
- ✅ **Pidä kategoria** varalta
- ❌ **Ei sääntöjä** vielä (liian vähän dataa)
- ✅ **Monitoroi** kun kerääntyy 20+ viestiä

---

## ✅ PÄÄTÖSYHTEENVETO (täytä tämä)

### 1. Bloomberg & SeekingAlpha
- [ ] VAIHTOEHTO A: Yksi sääntö per domain (enemmistökategoria)
- [ ] VAIHTOEHTO B: Ei sääntöä, AI päättää

### 2. Financial vs. Industry News
- [ ] financial_news = Sijoitus/rahamarkkinat, industry_news = Teknologia/ei-rahoitus
- [ ] financial_news = Kaikki talous, industry_news = Ei käytössä
- [ ] Muu (täsmennä): ___________

### 3. RepoxCapital.fi
- [ ] Jätä ilman sääntöä (monimuotoinen)
- [ ] Luo personal_communication sääntö
- [ ] Luo address-tason säännöt (listaa): ___________

### 4. Personal Communication
- [ ] Vain aidot henkilökohtaiset (ei bulk-merkkejä)
- [ ] Tärkeät yhteistyökumppanit (voi olla newsletter)
- [ ] Kaivonporaus.com → personal vai business_critical?

### 5. Internal-kategoria
- [ ] Pidä erillisenä
- [ ] Yhdistä business_critical-kategoriaan
- [ ] Poista kokonaan

### 6. Regulatory-kategoria
- [ ] Pidä varalta (odota lisää dataa)
- [ ] Poista (ei tarvetta)

---

## 📝 LISÄTIEDOT

### VIP Finance -lähteet (vahvistettu):
```
✅ seekingalpha.com (3825 viestiä)
✅ news.bloomberg.com (2070 viestiä)
✅ inderes.fi / notifications.inderes.com (1739 viestiä)
✅ mail.nordnet.fi (109 viestiä)
✅ nordea.com (37 viestiä)
✅ alandsbanken.fi (40 viestiä)
✅ redeye.se (30 viestiä)
✅ kauppalehti.fi (26 viestiä)
```

### Seuraavat vaiheet päätösten jälkeen:
1. ✅ Tarkista päätösdokumentti (tämä)
2. ⏳ Vahvista classification_rules ehdotukset
3. ⏳ Aja `new_classification_rules_proposal.sql`
4. ⏳ Päivitä `rules_snapshot` (Category Discovery Analysis)
5. ⏳ Testaa Gateway muutamalla uudella viestillä
6. ⏳ Monitoroi osuma-% (tavoite 85%+)

---

## 📞 TOIMENPIDE

**Vastaa Q-kysymyksiin** (merkitse ✅ valitut vaihtoehdot) ja lähetä takaisin.
Luon päivitetyt SQL-säännöt päätöstesi perusteella.
