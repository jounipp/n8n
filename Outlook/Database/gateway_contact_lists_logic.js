// ==========================================
// GATEWAY: Contact Lists + Classification Rules
// Käyttää contact_lists taulua VIP/personal/internal tunnistukseen
// ==========================================

// INPUT: Email object + Rules + Contact Lists
// OUTPUT: { matched: true/false, decision: {...} }

/**
 * PRIORITEETTI-JÄRJESTYS:
 *
 * 1. CONTACT_LISTS (dynaamiset):
 *    10: from_address (täysi match)
 *    15: from_address_contains (partial match)
 *    20: from_domain
 *    30: message_id_domain, list_domain, unsub_domain
 *
 * 2. CLASSIFICATION_RULES (staattiset):
 *    10: from_address, sender_address
 *    15: reply_to_address
 *    20: message_id_domain, list_domain, unsub_domain
 *    30: from_domain
 *
 * Contact lists tarkistetaan ENSIN (korkeampi prioriteetti)
 */

// ==========================================
// HELPER FUNCTIONS
// ==========================================

function normalizeEmail(addr) {
  if (!addr) return null;
  addr = String(addr).toLowerCase().trim();

  // Poista display name: "John Doe <john@example.com>" → "john@example.com"
  const emailMatch = addr.match(/<([^>]+)>/);
  if (emailMatch) addr = emailMatch[1];

  // Poista +tag: john+tag@example.com → john@example.com
  if (addr.includes('@')) {
    const [localPart, domain] = addr.split('@');
    const cleanLocal = localPart.split('+')[0];
    return `${cleanLocal}@${domain}`;
  }
  return addr;
}

function extractDomain(email) {
  if (!email) return null;
  const normalized = normalizeEmail(email);
  if (!normalized || !normalized.includes('@')) return null;
  return normalized.split('@')[1];
}

function extractMessageIdDomain(header) {
  if (!header) return null;
  const match = header.match(/@([^>]+)>?/);
  return match ? match[1].toLowerCase() : null;
}

function extractListDomain(listId) {
  if (!listId) return null;
  const match = listId.match(/<([^>]+)>/);
  return match ? match[1].toLowerCase() : null;
}

function extractUnsubDomain(unsubLink) {
  if (!unsubLink) return null;

  // Try HTTP/HTTPS first
  let match = unsubLink.match(/https?:\/\/([^\/>,;\s]+)/);
  if (match) return match[1].toLowerCase();

  // Try mailto
  match = unsubLink.match(/mailto:.*@([^>,;\s]+)/);
  if (match) return match[1].toLowerCase();

  // Try plain email
  match = unsubLink.match(/@([^>,;\s]+)/);
  if (match) return match[1].toLowerCase();

  return null;
}

// ==========================================
// EXTRACT EMAIL FEATURES
// ==========================================

function extractFeatures(email) {
  return {
    from_address: normalizeEmail(email.from_address),
    sender_address: normalizeEmail(email.sender_address),
    reply_to_address: normalizeEmail(email.reply_to_address),
    from_domain: email.from_domain?.toLowerCase() || extractDomain(email.from_address),
    message_id_domain: extractMessageIdDomain(email.message_id_header),
    list_domain: extractListDomain(email.list_id),
    unsub_domain: extractUnsubDomain(email.unsubscribe_link),
    precedence: email.precedence?.toLowerCase(),
    auto_submitted: email.auto_submitted?.toLowerCase()
  };
}

// ==========================================
// CHECK CONTACT_LISTS
// ==========================================

function checkContactLists(features, contactLists) {
  const matches = [];

  for (const contact of contactLists) {
    let isMatch = false;

    switch (contact.identifier_type) {
      case 'from_address':
        // Täysi match
        isMatch = features.from_address === contact.identifier_value;
        break;

      case 'from_address_contains':
        // Partial match: "pasi.penkkala" osuu kaikkiin pasi.penkkala@*.com
        isMatch = features.from_address?.includes(contact.identifier_value);
        break;

      case 'from_domain':
        isMatch = features.from_domain === contact.identifier_value;
        break;

      case 'message_id_domain':
        isMatch = features.message_id_domain === contact.identifier_value;
        break;

      case 'list_domain':
        isMatch = features.list_domain === contact.identifier_value;
        break;

      case 'unsub_domain':
        isMatch = features.unsub_domain === contact.identifier_value;
        break;
    }

    if (isMatch) {
      matches.push({
        source: 'contact_lists',
        list_type: contact.list_type,
        identifier_type: contact.identifier_type,
        identifier_value: contact.identifier_value,
        target_category: contact.target_category,
        recommended_action: contact.recommended_action,
        priority: contact.priority,
        notes: contact.notes
      });
    }
  }

  // Järjestä prioriteetin mukaan (pienempi numero = korkeampi prioriteetti)
  matches.sort((a, b) => a.priority - b.priority);

  return matches.length > 0 ? matches[0] : null;
}

// ==========================================
// CHECK CLASSIFICATION_RULES
// ==========================================

function checkClassificationRules(features, rules) {
  const matches = [];

  for (const rule of rules) {
    const featureValue = features[rule.feature];

    if (featureValue && featureValue === rule.key_value) {
      matches.push({
        source: 'classification_rules',
        rule_id: rule.rule_id,
        feature: rule.feature,
        key_value: rule.key_value,
        target_category: rule.target_category,
        recommended_action: rule.recommended_action || 'review',
        priority: rule.priority,
        precision: rule.precision_cat_pct,
        support: rule.support
      });
    }
  }

  // Järjestä prioriteetin mukaan
  matches.sort((a, b) => a.priority - b.priority);

  return matches.length > 0 ? matches[0] : null;
}

// ==========================================
// CALCULATE PRIORITY SCORE
// ==========================================

function calculatePriorityScore(priority, precision, relevance) {
  // Base score from priority level
  let score = priority === 10 ? 80 : priority === 20 ? 60 : 40;

  // Adjust based on precision (if available)
  if (precision >= 95) score += 10;
  else if (precision >= 90) score += 5;

  // Adjust based on relevance (if available)
  if (relevance >= 80) score += 5;

  return Math.min(100, score);
}

// ==========================================
// MAIN GATEWAY LOGIC
// ==========================================

function applyGateway(email, contactLists, classificationRules) {
  const features = extractFeatures(email);

  // 1. Tarkista CONTACT_LISTS ensin (korkein prioriteetti)
  const contactMatch = checkContactLists(features, contactLists);

  if (contactMatch) {
    // VIP/Personal/Internal osuma löytyi!

    // ERITYISTAPAUS: vip_finance + henkilön nimi
    // Jos vip_finance domain MUTTA lähettäjä näyttää henkilöltä (ei geneerinen)
    if (contactMatch.list_type === 'vip_finance') {
      // Tarkista onko geneerinen lähettäjä
      const genericPrefixes = ['noreply', 'no-reply', 'alerts', 'newsletter', 'info',
                               'support', 'notifications', 'news', 'updates', 'marketing'];

      const localPart = features.from_address?.split('@')[0] || '';
      const isGeneric = genericPrefixes.some(prefix => localPart.startsWith(prefix));

      if (!isGeneric && localPart.includes('.')) {
        // Näyttää henkilön nimeltä (esim. john.smith@)
        // Tarkista onko vip_personal listalla
        const vipPersonalMatch = contactLists.find(c =>
          c.list_type === 'vip_personal' &&
          c.identifier_value === features.from_address
        );

        if (vipPersonalMatch) {
          // Henkilökohtainen VIP-kontakti → business_critical
          return {
            matched: true,
            message_id: email.message_id,
            features_extracted: features,
            decision: {
              primary_category: 'business_critical',
              recommended_action: 'review',
              confidence: 95,
              priority_score: 90,
              requires_deep_analysis: false
            },
            match_details: {
              source: 'contact_lists',
              list_type: 'vip_personal',
              reason: 'VIP personal contact from finance domain'
            },
            classification_source: 'contact_lists_vip_personal'
          };
        }

        // Henkilön nimi MUTTA ei vip_personal listalla
        // → Jätä AI:lle päätettäväksi (ei sääntöä)
        return {
          matched: false,
          message_id: email.message_id,
          features_extracted: features,
          classification_source: 'needs_ai',
          reason: 'VIP finance domain but personal sender (not in vip_personal list)'
        };
      }
    }

    // Normaali contact_lists osuma
    return {
      matched: true,
      message_id: email.message_id,
      features_extracted: features,
      decision: {
        primary_category: contactMatch.target_category,
        recommended_action: contactMatch.recommended_action,
        confidence: 95, // Contact lists = korkea varmuus
        priority_score: calculatePriorityScore(contactMatch.priority, 95, 90),
        requires_deep_analysis: false
      },
      match_details: contactMatch,
      classification_source: `contact_lists_${contactMatch.list_type}`
    };
  }

  // 2. Tarkista CLASSIFICATION_RULES
  const ruleMatch = checkClassificationRules(features, classificationRules);

  if (ruleMatch) {
    return {
      matched: true,
      message_id: email.message_id,
      features_extracted: features,
      decision: {
        primary_category: ruleMatch.target_category,
        recommended_action: ruleMatch.recommended_action,
        confidence: ruleMatch.precision || 90,
        priority_score: calculatePriorityScore(
          ruleMatch.priority,
          ruleMatch.precision,
          ruleMatch.relevance
        ),
        requires_deep_analysis: false
      },
      match_details: ruleMatch,
      classification_source: 'classification_rules'
    };
  }

  // 3. Ei osumaa → AI päättää
  return {
    matched: false,
    message_id: email.message_id,
    features_extracted: features,
    classification_source: 'needs_ai',
    reason: 'no_matching_rules_or_contacts'
  };
}

// ==========================================
// EXPORT
// ==========================================

module.exports = {
  applyGateway,
  extractFeatures,
  checkContactLists,
  checkClassificationRules,
  normalizeEmail,
  extractDomain
};
