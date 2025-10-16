-- ==========================================
-- CONTACT LISTS -TAULU
-- Ylläpidetään VIP-lähteet, henkilökohtaiset kontaktit, sisäiset domainit
-- ==========================================

CREATE TABLE IF NOT EXISTS outlook.contact_lists (
  id SERIAL PRIMARY KEY,

  -- Lista-tyyppi
  list_type TEXT NOT NULL CHECK (list_type IN (
    'vip_finance',        -- VIP rahoituslähteet (domain)
    'vip_personal',       -- VIP-lähteistä henkilökohtaiset kontaktit (address)
    'personal',           -- Henkilökohtaiset kontaktit (address partial match)
    'business_critical',  -- Tärkeät kumppanit/asiakkaat (domain)
    'internal'            -- Oma yritys (domain)
  )),

  -- Tunnistustyyppi
  identifier_type TEXT NOT NULL CHECK (identifier_type IN (
    'from_domain',              -- Koko domain (esim. 'seekingalpha.com')
    'from_address',             -- Täysi sähköpostiosoite (esim. 'john.smith@bloomberg.com')
    'from_address_contains',    -- Partial match (esim. 'pasi.penkkala')
    'message_id_domain',        -- Message-ID header domain
    'list_domain',              -- List-ID header domain
    'unsub_domain'              -- Unsubscribe link domain
  )),

  -- Tunniste-arvo
  identifier_value TEXT NOT NULL,

  -- Mihin kategoriaan ohjataan
  target_category TEXT NOT NULL CHECK (target_category IN (
    'business_critical',
    'personal_communication',
    'financial_news',
    'marketing',
    'notifications',
    'industry_news',
    'internal',
    'regulatory',
    'spam_low_value',
    'uncategorized'
  )),

  -- Suositeltu toimenpide
  recommended_action TEXT DEFAULT 'review' CHECK (recommended_action IN (
    'none', 'read', 'review', 'follow_up', 'urgent', 'archive', 'delete'
  )),

  -- Prioriteetti (10=korkein, 40=matalin)
  priority INT DEFAULT 20 CHECK (priority BETWEEN 10 AND 40),

  -- Lisätiedot
  notes TEXT,

  -- Aktiivisuus
  is_active BOOLEAN DEFAULT TRUE,

  -- Aikaleima
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  created_by TEXT,

  -- Uniikki rajoite
  UNIQUE(list_type, identifier_type, identifier_value)
);

-- Indeksit
CREATE INDEX IF NOT EXISTS idx_contact_lists_active
  ON outlook.contact_lists(is_active)
  WHERE is_active = TRUE;

CREATE INDEX IF NOT EXISTS idx_contact_lists_type
  ON outlook.contact_lists(list_type, identifier_type);

CREATE INDEX IF NOT EXISTS idx_contact_lists_lookup
  ON outlook.contact_lists(identifier_type, identifier_value)
  WHERE is_active = TRUE;

-- Update timestamp trigger
CREATE OR REPLACE FUNCTION outlook.update_contact_lists_timestamp()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER contact_lists_update_timestamp
  BEFORE UPDATE ON outlook.contact_lists
  FOR EACH ROW
  EXECUTE FUNCTION outlook.update_contact_lists_timestamp();

-- Kommentit
COMMENT ON TABLE outlook.contact_lists IS
  'Ylläpidetään VIP-lähteet, henkilökohtaiset kontaktit ja sisäiset domainit. Käytetään Gateway-vaiheessa ennen AI-analyysiä.';

COMMENT ON COLUMN outlook.contact_lists.list_type IS
  'Lista-tyyppi: vip_finance (VIP-rahoitus), vip_personal (VIP-henkilöt), personal (henkilökohtaiset), business_critical (tärkeät kumppanit), internal (oma yritys)';

COMMENT ON COLUMN outlook.contact_lists.identifier_type IS
  'Miten tunnistetaan: from_domain (koko domain), from_address (täysi osoite), from_address_contains (partial match)';

COMMENT ON COLUMN outlook.contact_lists.identifier_value IS
  'Tunniste-arvo: esim. "seekingalpha.com", "john.smith@bloomberg.com", "pasi.penkkala"';

COMMENT ON COLUMN outlook.contact_lists.priority IS
  'Prioriteetti: 10=from_address (korkein), 15=address_contains, 20=domain-taso, 30=message_id/list/unsub domain';
