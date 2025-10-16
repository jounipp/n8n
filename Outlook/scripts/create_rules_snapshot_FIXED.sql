-- Rules snapshot table for prompt caching
-- Stores compiled rule sets for AI prompt injection

CREATE TABLE IF NOT EXISTS outlook.rules_snapshot (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    version TEXT NOT NULL UNIQUE,

    -- Snapshot metadata
    created_at TIMESTAMPTZ DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,

    -- Rules content
    rules_count INTEGER NOT NULL,
    rules_json JSONB NOT NULL,  -- Compiled rules for prompt
    rules_dsl TEXT NOT NULL,     -- Human-readable DSL format

    -- Source tracking
    source_version TEXT,         -- CDA version that generated these rules
    total_support INTEGER,       -- Total email matches across all rules
    avg_precision NUMERIC(5,2),  -- Average precision percentage

    -- Cache control
    ttl_hours INTEGER DEFAULT 24,
    invalidated_at TIMESTAMPTZ,
    invalidation_reason TEXT,

    -- Usage metrics
    usage_count INTEGER DEFAULT 0,
    last_used_at TIMESTAMPTZ
);

-- Create indexes separately
CREATE INDEX IF NOT EXISTS idx_snapshot_active_version
ON outlook.rules_snapshot (is_active, version);

CREATE INDEX IF NOT EXISTS idx_snapshot_expires
ON outlook.rules_snapshot (expires_at);

-- Function to get current active snapshot
CREATE OR REPLACE FUNCTION outlook.get_active_rules_snapshot()
RETURNS TABLE (
    version TEXT,
    rules_json JSONB,
    rules_dsl TEXT,
    expires_at TIMESTAMPTZ
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        rs.version,
        rs.rules_json,
        rs.rules_dsl,
        rs.expires_at
    FROM outlook.rules_snapshot rs
    WHERE rs.is_active = TRUE
      AND rs.expires_at > NOW()
      AND rs.invalidated_at IS NULL
    ORDER BY rs.created_at DESC
    LIMIT 1;
END;
$$ LANGUAGE plpgsql;

-- Function to invalidate old snapshots
CREATE OR REPLACE FUNCTION outlook.invalidate_rules_snapshots(reason TEXT DEFAULT 'New version available')
RETURNS INTEGER AS $$
DECLARE
    affected_rows INTEGER;
BEGIN
    UPDATE outlook.rules_snapshot
    SET
        is_active = FALSE,
        invalidated_at = NOW(),
        invalidation_reason = reason
    WHERE is_active = TRUE
      AND invalidated_at IS NULL;

    GET DIAGNOSTICS affected_rows = ROW_COUNT;
    RETURN affected_rows;
END;
$$ LANGUAGE plpgsql;

-- Trigger to auto-invalidate on new CDA rules
CREATE OR REPLACE FUNCTION outlook.on_classification_rules_change()
RETURNS TRIGGER AS $$
BEGIN
    -- When new rules are inserted, invalidate cache
    IF TG_OP = 'INSERT' THEN
        PERFORM outlook.invalidate_rules_snapshots('New CDA rules published');
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger separately
DROP TRIGGER IF EXISTS trigger_invalidate_snapshot ON outlook.classification_rules;
CREATE TRIGGER trigger_invalidate_snapshot
AFTER INSERT ON outlook.classification_rules
FOR EACH STATEMENT
EXECUTE FUNCTION outlook.on_classification_rules_change();

-- View for monitoring cache status
CREATE OR REPLACE VIEW outlook.rules_cache_status AS
SELECT
    version,
    is_active,
    created_at,
    expires_at,
    CASE
        WHEN invalidated_at IS NOT NULL THEN 'invalidated'
        WHEN expires_at <= NOW() THEN 'expired'
        WHEN is_active THEN 'active'
        ELSE 'inactive'
    END as status,
    rules_count,
    total_support,
    avg_precision,
    usage_count,
    last_used_at,
    invalidation_reason
FROM outlook.rules_snapshot
ORDER BY created_at DESC;

-- Grant permissions if needed
GRANT SELECT ON outlook.rules_snapshot TO PUBLIC;
GRANT EXECUTE ON FUNCTION outlook.get_active_rules_snapshot() TO PUBLIC;
GRANT EXECUTE ON FUNCTION outlook.invalidate_rules_snapshots(TEXT) TO PUBLIC;