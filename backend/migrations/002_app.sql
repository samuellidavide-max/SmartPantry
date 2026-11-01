-- Estensioni dello schema per l'MVP: utenti anonimi, sessioni di spesa,
-- serie settimanali scontrini, dettagli promo multi-acquisto.

ALTER TABLE users ALTER COLUMN email DROP NOT NULL;
ALTER TABLE users ADD COLUMN device_id        TEXT UNIQUE;
ALTER TABLE users ADD COLUMN streak_weeks     INT NOT NULL DEFAULT 0;
ALTER TABLE users ADD COLUMN last_receipt_at  TIMESTAMPTZ;

ALTER TABLE store_prices ADD COLUMN promo_details JSONB;   -- {"buy":3,"pay":2}

-- Una "sessione di spesa" è un optimization_run avviato dall'utente
ALTER TABLE optimization_runs ADD COLUMN user_id          UUID REFERENCES users(id) ON DELETE CASCADE;
ALTER TABLE optimization_runs ADD COLUMN chosen_stores    BIGINT[];
ALTER TABLE optimization_runs ADD COLUMN estimated_saving NUMERIC(10,2);
ALTER TABLE optimization_runs ADD COLUMN started_at       TIMESTAMPTZ;
ALTER TABLE optimization_runs ADD COLUMN closed_at        TIMESTAMPTZ;
CREATE INDEX optimization_runs_active ON optimization_runs (user_id) WHERE started_at IS NOT NULL AND closed_at IS NULL;

ALTER TABLE receipts ADD COLUMN optimization_run_id UUID REFERENCES optimization_runs(id) ON DELETE SET NULL;
ALTER TABLE receipts ADD COLUMN credits_awarded INT NOT NULL DEFAULT 0;

ALTER TABLE receipt_lines ADD COLUMN candidates JSONB;      -- [{product_id,name,score}] per righe incerte

CREATE INDEX receipts_user_day ON receipts (user_id, created_at DESC);
