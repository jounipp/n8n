// build_batch_prompt_cache — HYBRID VERSION with rule injection
// Fetches rules from cache or builds new snapshot

// Helper to fetch active rules snapshot from DB
async function getRulesSnapshot() {
  try {
    // This would be called via n8n's postgres node
    // For now, returning structure example
    const snapshot = await $('get_rules_snapshot').first();

    if (snapshot?.json?.rules_json) {
      return {
        version: snapshot.json.version,
        rules: snapshot.json.rules_json,
        dsl: snapshot.json.rules_dsl,
        expires_at: snapshot.json.expires_at,
        from_cache: true
      };
    }
  } catch (e) {
    console.log('No valid cache, building new snapshot');
  }

  return null;
}

// Helper to build new rules snapshot from classification_rules
async function buildNewSnapshot() {
  // Get active rules from classification_rules table
  const rulesData = await $('load_classification_rules').all();

  if (!rulesData || rulesData.length === 0) {
    return {
      version: 'default_v1',
      rules: [],
      dsl: '',
      from_cache: false
    };
  }

  // Sort by priority and support
  const rules = rulesData
    .map(r => r.json)
    .sort((a, b) => {
      if (a.priority !== b.priority) return a.priority - b.priority;
      return b.support - a.support;
    });

  // Build DSL format for prompt injection
  const dslLines = [];
  const rulesByCategory = {};

  rules.forEach(r => {
    if (!rulesByCategory[r.target_category]) {
      rulesByCategory[r.target_category] = [];
    }

    rulesByCategory[r.target_category].push({
      feature: r.feature,
      value: r.key_value,
      support: r.support,
      precision: r.precision_cat_pct,
      action: r.recommended_action
    });
  });

  // Create human-readable DSL
  for (const [category, categoryRules] of Object.entries(rulesByCategory)) {
    dslLines.push(`\n=== ${category.toUpperCase()} ===`);

    categoryRules.forEach(r => {
      const confidence = r.precision >= 95 ? 'KORKEA' : r.precision >= 80 ? 'HYVÄ' : 'KOHTALAINEN';
      dslLines.push(`- JOS ${r.feature}="${r.value}" → ${category} (${confidence} tarkkuus, ${r.support} osumaa, toimenpide: ${r.action})`);
    });
  }

  // Generate version based on timestamp and rule count
  const version = `hybrid_${new Date().toISOString().split('T')[0]}_r${rules.length}`;

  // Save to cache (this would be done via postgres node)
  const ttlHours = 24;
  const expiresAt = new Date(Date.now() + ttlHours * 60 * 60 * 1000).toISOString();

  await $('save_rules_snapshot').execute({
    version: version,
    rules_json: rules,
    rules_dsl: dslLines.join('\n'),
    expires_at: expiresAt,
    rules_count: rules.length,
    total_support: rules.reduce((sum, r) => sum + (r.support || 0), 0),
    avg_precision: rules.reduce((sum, r) => sum + (r.precision_cat_pct || 0), 0) / rules.length
  });

  return {
    version: version,
    rules: rules,
    dsl: dslLines.join('\n'),
    from_cache: false
  };
}

// Main function
async function buildPromptWithRules() {
  // Try to get from cache first
  let rulesData = await getRulesSnapshot();

  // Build new if cache miss
  if (!rulesData) {
    rulesData = await buildNewSnapshot();
  }

  // Log cache status
  console.log(`Rules loaded: version=${rulesData.version}, from_cache=${rulesData.from_cache}, count=${rulesData.rules?.length || 0}`);

  return rulesData;
}

// ========== MAIN EXECUTION ==========

function sanitizeText(s) {
  if (s == null) return '';
  let t = String(s);
  t = t.replace(/\uFEFF/g, '');
  t = t.replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/g, '');
  return t.trim();
}

function pickMinimalInputFields(x) {
  return {
    message_id: x.message_id,
    subject: sanitizeText(x.subject),
    from: x.from_address || x.from_domain || '',
    text: sanitizeText(x.body_text || '')
  };
}

return items.map(async item => {
  const j = item.json || {};
  const arr = Array.isArray(j.batch_items) ? j.batch_items : [];
  const message_count = arr.length;

  const inputItems = arr.map(pickMinimalInputFields);
  const batch_prompt = JSON.stringify(inputItems, null, 2);

  // GET RULES FOR INJECTION
  const rulesData = await buildPromptWithRules();
  const hasRules = rulesData.rules && rulesData.rules.length > 0;

  // ========== ENHANCED SYSTEM PROMPT WITH RULES ==========
  let system_prompt_base = `Olet rahoituskäyttöön koulutettu sähköpostiluokittelun asiantuntija. Teet kolme tehtävää jokaiselle viestille: (1) luokittelet ja ehdotat sääntöjä, (2) tuotat tiiviin sisältöanalyysin, (3) tuotat päätösehdotuksen (priority, toimenpide, mahdollinen määräaika). Palauta VAIN JSON-taulukko ilman selityksiä.

RULES VERSION: ${rulesData.version}
RULES COUNT: ${rulesData.rules?.length || 0}`;

  // Add dynamic rules section if we have rules
  let rules_section = '';
  if (hasRules) {
    rules_section = `

═══════════════════════════════════════════════
TUNNETUT LÄHETTÄJÄT JA SÄÄNNÖT (${rulesData.version})
═══════════════════════════════════════════════

Käytä näitä tunnettuja sääntöjä apuna luokittelussa. Jos sähköposti osuu tunnettuun sääntöön, luokittele ensisijaisesti sen mukaan.

${rulesData.dsl}

HUOM: Nämä säännöt perustuvat ${rulesData.rules?.length || 0} tunnettuun lähettäjään historiadatasta. Jos osuma löytyy, käytä korkeaa confidence-arvoa.

═══════════════════════════════════════════════
`;
  }

  // Original category definitions continue...
  const system_prompt_categories = `

PRIMARY_CATEGORY LUOKITTELU (PAKOLLINEN):

Valitse YKSI seuraavista 10 kategoriasta jokaiselle viestille. Käytä täsmälleen näitä nimiä (pienet kirjaimet, alaviivat):

1. business_critical
   SISÄLTÖ: Sopimukset, laskut, tarjouspyynnöt, juridiset asiat, kriittinen päätöksenteko
   TUNNISTEET: "sopimus", "lasku", "eräpäivä", "allekirjoitus", "maksu", "tarjous", "neuvottelu"
   LÄHETTÄJÄ: Lakitoimistot, toimittajat, asiakkaat, kumppanit (ei massajakelu)
   PRIORITEETTI: KORKEA (vaatii välitöntä toimenpidettä)
   ESIMERKKI: "Sijoitussopimus allekirjoitettavaksi 5.2.", "Lasku #1234 eräpäivä 7 päivää"

2. personal_communication
   SISÄLTÖ: Henkilökohtainen viestintä kollegoiden/kumppaneiden kanssa, epävirallinen keskustelu
   TUNNISTEET: "hei", "kiitos", "keskustellaan", "kahvilla", "moi" (ei virallisuutta)
   LÄHETTÄJÄ: Yksittäiset henkilöt (ei massajakelu, ei automaatio)
   PRIORITEETTI: Keskitaso (kontekstista riippuen)
   ESIMERKKI: "Hei! Sopiiko keskustella projektista huomenna?", "Kiitos palaverista"

3. financial_news
   SISÄLTÖ: Sijoitukset, pörssit, osakekurssit, markkinauutiset, talousmedia, analyysit, tulokset
   TUNNISTEET: "osake", "pörssi", "kurssi", "Q4 tulokset", "suositus", "osta/myy", "sijoitus"
   LÄHETTÄJÄ: Talousmedia (kauppalehti.fi, bloomberg.com, ft.com), analyysitalot (Inderes, Nordea Markets)
   PRIORITEETTI: Keskitaso (luetaan säännöllisesti, ei akuutti)
   ESIMERKKI: "Nordea Q4 tulokset ylittivät odotukset", "Inderes: Nokia - Osta", "S&P 500 nousi 2%"

4. marketing
   SISÄLTÖ: Mainokset, tarjoukset, myyntiviestit, kampanjat, promootiot
   TUNNISTEET: "tilaa nyt", "erikoistarjous", "alennus", "ilmainen", "webinaari" (myynti-intent)
   LÄHETTÄJÄ: Yritykset (massajakelu), markkinointiosastot
   PRIORITEETTI: Matala (voidaan arkistoida/poistaa)
   ESIMERKKI: "Tilaa Premium-tili 50% alennuksella!", "Webinaari: Opi sijoittamaan - Osta kurssi nyt"

5. notifications
   SISÄLTÖ: Automaattiset järjestelmäilmoitukset, tilausvahvistukset, kuljetusseurannat, tekniset viestit
   TUNNISTEET: "salasana vaihdettu", "tilaus vahvistettu", "paketti toimitettu", "auto-reply"
   LÄHETTÄJÄ: Järjestelmät (no-reply, automaatio), palvelut (GitHub, AWS, Stripe)
   PRIORITEETTI: Matala-keskitaso (tiedoksi, harvoin toimenpiteitä)
   ESIMERKKI: "Salasanasi on vaihdettu", "GitHub: New pull request", "Paketti saapuu huomenna"

6. industry_news
   SISÄLTÖ: Toimiala-artikkelit, kilpailija-analyysit, trendit, tutkimus (EI sijoitussuosituksia)
   TUNNISTEET: "toimialan kasvu", "markkina-asema", "teknologia", "trendi", "tulevaisuus"
   LÄHETTÄJÄ: Toimialajärjestöt, konsulttitoimistot, media (yleiset uutiset)
   PRIORITEETTI: Keskitaso (pitkäjänteinen seuranta)
   ESIMERKKI: "Fintech-ala kasvaa 15% vuodessa", "5G-verkon käyttöönotto Suomessa"

7. internal
   SISÄLTÖ: Sisäinen yritysviestintä, tiimin viestit, organisaation ilmoitukset (virallinen)
   TUNNISTEET: "tiimi", "organisaatio", "vuosipalaveri", "HR", "sisäinen ohje"
   LÄHETTÄJÄ: Oma organisaatio, HR, johto
   PRIORITEETTI: Keskitaso-korkea (organisaatiosta riippuen)
   ESIMERKKI: "Vuosipalaverikutsu 15.3.", "HR: Uusi lomaohje", "Tiimin Q1-tavoitteet"

8. regulatory
   SISÄLTÖ: Viranomaisviestit, compliance, säädökset, lakimuutokset
   TUNNISTEET: "viranomainen", "säädös", "compliance", "GDPR", "MiFID", "veroilmoitus"
   LÄHETTÄJÄ: Viranomaiset (verohallinto, finanssivalvonta), lakitoimistot
   PRIORITEETTI: KORKEA (lakisääteinen)
   ESIMERKKI: "GDPR-päivitys: Toimenpiteet 30 päivässä", "Veroilmoitusohje 2025"

9. spam_low_value
   SISÄLTÖ: Roskaposti, ei-relevantti sisältö, huijausviestit
   TUNNISTEET: "olet voittanut", "klikkaa tästä", phishing
   LÄHETTÄJÄ: Tuntemattomat lähettäjät, epäilyttävät domainit
   PRIORITEETTI: Ei prioriteettia
   ESIMERKKI: "Olet voittanut 1M€", "Nigerian prince scam"

10. uncategorized
    SISÄLTÖ: Epäselvät tapaukset, ei sovi muihin kategorioihin
    KÄYTTÖ: Vain jos TODELLA epävarma (confidence <40%)
    ESIMERKKI: Viestit joissa puuttuu sisältö, kieli tuntematon`;

  // Combine all parts
  const system_prompt = system_prompt_base + rules_section + system_prompt_categories + `

SISÄLTÖRAKENTEEN ARVIOINTI (content_structure):
[... rest of original prompt ...]

analyzer_version = "claude-sonnet-4-5-20250929"
decision.status = "proposed"
rules_version = "${rulesData.version}"`;

  // User prompt remains the same...
  const user_prompt = `[... original user prompt ...]`;

  // System prompt cache-muodossa (top-level parameter)
  const system = [
    {
      type: "text",
      text: system_prompt,
      cache_control: { type: "ephemeral" }
    }
  ];

  // Messages array (VAIN user role!)
  const messages = [
    {
      role: 'user',
      content: user_prompt
    }
  ];

  return {
    json: {
      batch_items: j.batch_items,
      batch_size: j.batch_size,
      batch_number: j.batch_number,
      message_count,
      system_prompt,      // Debug: raw string with rules
      user_prompt,        // Debug: raw string
      system,             // API: cache-enabled system with rules
      messages,           // API: user messages only
      batch_prompt,
      rules_version: rulesData.version,  // Track which rules version was used
      rules_count: rulesData.rules?.length || 0,
      rules_from_cache: rulesData.from_cache
    }
  };
});