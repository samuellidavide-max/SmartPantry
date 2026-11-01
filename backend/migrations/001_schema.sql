-- =====================================================================
-- SmartPantry - SpesaOttimizzata :: Schema PostgreSQL 16 + PostGIS 3
-- Tabelle core: stores, products, store_prices, shopping_lists
-- + tabelle di supporto (catene, prodotti generici, ledger osservazioni,
--   scontrini, utenti, crediti).
-- =====================================================================

CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pg_trgm;   -- ricerca fuzzy nomi prodotto
CREATE EXTENSION IF NOT EXISTS unaccent;

-- ---------- Enum ----------------------------------------------------
CREATE TYPE price_source     AS ENUM ('online', 'flyer', 'receipt');
CREATE TYPE promo_condition  AS ENUM ('none', 'flyer', 'loyalty_card', 'multi_buy', 'app_coupon');
CREATE TYPE measure_unit     AS ENUM ('g', 'ml', 'pz');
CREATE TYPE list_status      AS ENUM ('draft', 'ready', 'optimized', 'archived');
CREATE TYPE receipt_status   AS ENUM ('uploaded', 'ocr_done', 'matched', 'validated', 'rejected');
CREATE TYPE plan_tier        AS ENUM ('free', 'premium');

-- ---------- Catene e punti vendita ----------------------------------
CREATE TABLE chains (
    id                  SMALLSERIAL PRIMARY KEY,
    name                TEXT NOT NULL UNIQUE,          -- 'Esselunga', 'Eurospin'
    slug                TEXT NOT NULL UNIQUE,
    loyalty_card_name   TEXT,                          -- 'Fidaty', 'Carta Insieme'
    online_portal_url   TEXT,
    is_discount         BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE TABLE stores (
    id                  BIGSERIAL PRIMARY KEY,
    chain_id            SMALLINT NOT NULL REFERENCES chains(id),
    external_store_id   TEXT,                          -- id negozio sul portale della catena
    name                TEXT NOT NULL,                 -- 'Esselunga Viale Piave'
    address             TEXT NOT NULL,
    cap                 CHAR(5) NOT NULL,
    city                TEXT NOT NULL,
    province            CHAR(2),
    location            GEOGRAPHY(Point, 4326) NOT NULL,
    has_click_collect   BOOLEAN NOT NULL DEFAULT FALSE,
    has_online_prices   BOOLEAN NOT NULL DEFAULT FALSE, -- prezzi da portale per questo store
    price_zone          TEXT,                          -- le catene spesso prezzano per zona, non per store
    opening_hours       JSONB,                         -- {"mon":[["08:00","21:00"]], ...}
    is_active           BOOLEAN NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (chain_id, external_store_id)
);
CREATE INDEX stores_location_gix ON stores USING GIST (location);
CREATE INDEX stores_cap_idx      ON stores (cap);

-- ---------- Catalogo prodotti ---------------------------------------
CREATE TABLE categories (
    id          SERIAL PRIMARY KEY,
    parent_id   INT REFERENCES categories(id),
    name        TEXT NOT NULL,                         -- 'Latte e derivati' > 'Latte UHT'
    icon        TEXT
);

-- Concetto generico ("Olio EVO", "Latte parz. scremato"): nodo a cui
-- si agganciano i prodotti di marca equivalenti.
CREATE TABLE generic_products (
    id              SERIAL PRIMARY KEY,
    name            TEXT NOT NULL UNIQUE,
    category_id     INT NOT NULL REFERENCES categories(id),
    base_unit       measure_unit NOT NULL,             -- unità di confronto prezzo (€/kg, €/l, €/pz)
    default_qty     NUMERIC(10,2) NOT NULL,            -- confezione tipica: 1000 ml, 500 g
    allowed_variants JSONB NOT NULL DEFAULT '{}'       -- {"formato":["1L","500ml"],"bio":[true,false]}
);

CREATE TABLE products (
    id                  BIGSERIAL PRIMARY KEY,
    ean                 VARCHAR(14) UNIQUE,            -- NULL per sfusi / private label senza EAN noto
    name                TEXT NOT NULL,                 -- 'Pasta De Cecco Penne Rigate n.41'
    brand               TEXT,                          -- NULL = sconosciuta
    is_private_label    BOOLEAN NOT NULL DEFAULT FALSE,
    private_label_chain SMALLINT REFERENCES chains(id), -- es. 'Esselunga Smart' -> Esselunga
    category_id         INT NOT NULL REFERENCES categories(id),
    generic_product_id  INT REFERENCES generic_products(id),
    net_qty             NUMERIC(10,2) NOT NULL,        -- 500
    net_unit            measure_unit NOT NULL,         -- g
    pieces              SMALLINT NOT NULL DEFAULT 1,   -- multipack: 6 x 1L
    attributes          JSONB NOT NULL DEFAULT '{}',   -- {"formato":"n.12","bio":false,"senza_lattosio":false}
    image_url           TEXT,
    search_vector       TSVECTOR GENERATED ALWAYS AS (
                          to_tsvector('italian', coalesce(name,'') || ' ' || coalesce(brand,''))
                        ) STORED,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (NOT is_private_label OR private_label_chain IS NOT NULL)
);
CREATE INDEX products_search_gin  ON products USING GIN (search_vector);
CREATE INDEX products_name_trgm   ON products USING GIN (name gin_trgm_ops);
CREATE INDEX products_generic_idx ON products (generic_product_id);

-- Alias testuali per il matching OCR / scraping:
-- 'LATTE PS GRANAR 1L' (scontrino Esselunga) -> product_id
CREATE TABLE product_aliases (
    id          BIGSERIAL PRIMARY KEY,
    product_id  BIGINT NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    chain_id    SMALLINT REFERENCES chains(id),        -- NULL = valido per tutte
    source      price_source NOT NULL,
    alias_text  TEXT NOT NULL,                         -- normalizzato: upper, senza accenti, spazi singoli
    confidence  REAL NOT NULL DEFAULT 1.0,
    confirmed_by_users INT NOT NULL DEFAULT 0,
    UNIQUE (chain_id, source, alias_text)
);
CREATE INDEX product_aliases_trgm ON product_aliases USING GIN (alias_text gin_trgm_ops);

-- ---------- Prezzi --------------------------------------------------
-- Ledger append-only: ogni prezzo visto da qualunque sorgente.
CREATE TABLE price_observations (
    id               BIGSERIAL PRIMARY KEY,
    store_id         BIGINT NOT NULL REFERENCES stores(id),
    product_id       BIGINT NOT NULL REFERENCES products(id),
    source           price_source NOT NULL,
    source_ref       TEXT,                             -- scrape_run_id / flyer_id / receipt_id
    price_regular    NUMERIC(10,2) CHECK (price_regular > 0),
    price_promo      NUMERIC(10,2) CHECK (price_promo > 0),
    promo_condition  promo_condition NOT NULL DEFAULT 'none',
    promo_details    JSONB,                            -- {"tipo":"3x2"} / {"min_qty":2}
    valid_from       DATE,
    valid_to         DATE,
    observed_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    reported_by      UUID,                             -- utente (solo source='receipt')
    is_outlier       BOOLEAN NOT NULL DEFAULT FALSE,   -- marcato dal rilevamento anomalie
    CHECK (price_regular IS NOT NULL OR price_promo IS NOT NULL),
    CHECK (valid_to IS NULL OR valid_from IS NULL OR valid_to >= valid_from)
);
CREATE INDEX price_obs_lookup ON price_observations (store_id, product_id, observed_at DESC);
CREATE INDEX price_obs_recent ON price_observations (observed_at) WHERE NOT is_outlier;

-- Prezzo corrente "risolto" per (store, prodotto): è la tabella letta
-- dall'algoritmo. Ricalcolata dai worker di ingestion a partire dal ledger.
CREATE TABLE store_prices (
    store_id           BIGINT NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
    product_id         BIGINT NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    price_regular      NUMERIC(10,2) NOT NULL CHECK (price_regular > 0),
    price_promo        NUMERIC(10,2) CHECK (price_promo > 0 AND price_promo <= price_regular),
    promo_condition    promo_condition NOT NULL DEFAULT 'none',
    promo_valid_from   DATE,
    promo_valid_to     DATE,
    unit_price_regular NUMERIC(10,4) NOT NULL,         -- €/kg, €/l o €/pz per confronti tra formati
    primary_source     price_source NOT NULL,          -- sorgente che ha "vinto" la risoluzione
    confidence         REAL NOT NULL CHECK (confidence BETWEEN 0 AND 1),
    observations_30d   INT NOT NULL DEFAULT 0,
    last_observed_at   TIMESTAMPTZ NOT NULL,
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (store_id, product_id),
    CHECK (price_promo IS NULL OR promo_valid_to IS NOT NULL)
);
CREATE INDEX store_prices_product ON store_prices (product_id);

-- Prezzo effettivo per un utente in una data: la promo vale solo se attiva
-- e, se richiede carta fedeltà, solo se l'utente possiede quella carta.
CREATE OR REPLACE FUNCTION effective_price(
    sp store_prices, on_day DATE, user_has_card BOOLEAN
) RETURNS NUMERIC LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE
        WHEN sp.price_promo IS NOT NULL
         AND on_day BETWEEN coalesce(sp.promo_valid_from, on_day) AND sp.promo_valid_to
         AND (sp.promo_condition <> 'loyalty_card' OR user_has_card)
         AND sp.promo_condition <> 'multi_buy'      -- 3x2 ecc. gestite a parte dall'algoritmo
        THEN sp.price_promo
        ELSE sp.price_regular
    END
$$;

-- ---------- Utenti --------------------------------------------------
CREATE TABLE users (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email             TEXT UNIQUE NOT NULL,
    plan              plan_tier NOT NULL DEFAULT 'free',
    premium_until     TIMESTAMPTZ,
    credits           INT NOT NULL DEFAULT 0 CHECK (credits >= 0),
    home_location     GEOGRAPHY(Point, 4326),
    home_cap          CHAR(5),
    search_radius_m   INT NOT NULL DEFAULT 5000 CHECK (search_radius_m BETWEEN 500 AND 20000),
    trust_score       REAL NOT NULL DEFAULT 0.5 CHECK (trust_score BETWEEN 0 AND 1), -- affidabilità scontrini
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE user_loyalty_cards (
    user_id   UUID REFERENCES users(id) ON DELETE CASCADE,
    chain_id  SMALLINT REFERENCES chains(id),
    PRIMARY KEY (user_id, chain_id)
);

-- Store preferiti / esclusi dall'utente
CREATE TABLE user_store_prefs (
    user_id   UUID REFERENCES users(id) ON DELETE CASCADE,
    store_id  BIGINT REFERENCES stores(id) ON DELETE CASCADE,
    pref      SMALLINT NOT NULL CHECK (pref IN (-1, 1)),   -- -1 escluso, 1 preferito
    PRIMARY KEY (user_id, store_id)
);

-- ---------- Liste della spesa ---------------------------------------
CREATE TABLE shopping_lists (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name            TEXT NOT NULL DEFAULT 'Spesa',
    status          list_status NOT NULL DEFAULT 'draft',
    search_center   GEOGRAPHY(Point, 4326),            -- NULL = home_location utente
    radius_m        INT CHECK (radius_m BETWEEN 500 AND 20000),
    max_stores      SMALLINT NOT NULL DEFAULT 2 CHECK (max_stores BETWEEN 1 AND 3),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX shopping_lists_user ON shopping_lists (user_id, updated_at DESC);

CREATE TABLE shopping_list_items (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    list_id             UUID NOT NULL REFERENCES shopping_lists(id) ON DELETE CASCADE,
    position            SMALLINT NOT NULL,
    -- Esattamente uno tra prodotto specifico e prodotto generico:
    product_id          BIGINT REFERENCES products(id),          -- 'Pasta De Cecco n.12 500g'
    generic_product_id  INT REFERENCES generic_products(id),     -- 'Olio EVO'
    quantity            NUMERIC(8,2) NOT NULL DEFAULT 1 CHECK (quantity > 0),
    quantity_unit       measure_unit NOT NULL DEFAULT 'pz',      -- 2 pz, oppure 1000 g di generico
    variant_filters     JSONB NOT NULL DEFAULT '{}',             -- {"bio":true,"formato":"1L"}
    brand_lock          BOOLEAN NOT NULL DEFAULT FALSE,          -- generico ma "solo marche note"
    note                TEXT,
    is_checked          BOOLEAN NOT NULL DEFAULT FALSE,          -- spuntato in negozio
    CHECK ((product_id IS NULL) <> (generic_product_id IS NULL)),
    UNIQUE (list_id, position)
);

-- Risultato ottimizzazione salvato (per storico risparmi e dashboard Home)
CREATE TABLE optimization_runs (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    list_id         UUID NOT NULL REFERENCES shopping_lists(id) ON DELETE CASCADE,
    computed_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    scenario_single JSONB NOT NULL,                    -- {store_id, coverage, total, ...}
    scenario_multi  JSONB,                             -- {stores:[...], assignment:{item->store}, total}
    reference_total NUMERIC(10,2) NOT NULL,            -- totale a prezzi medi locali
    chosen_scenario CHAR(1) CHECK (chosen_scenario IN ('A','B')),
    realized_saving NUMERIC(10,2)                      -- confermato da scontrino, alimenta la dashboard
);

-- ---------- Scontrini e gamification --------------------------------
CREATE TABLE receipts (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    store_id        BIGINT REFERENCES stores(id),      -- risolto da P.IVA / indirizzo in testata
    status          receipt_status NOT NULL DEFAULT 'uploaded',
    image_key       TEXT NOT NULL,                     -- object storage, cancellato dopo 30 gg
    image_sha256    CHAR(64) NOT NULL UNIQUE,          -- anti-duplicato
    purchased_at    TIMESTAMPTZ,
    total_printed   NUMERIC(10,2),
    total_parsed    NUMERIC(10,2),                     -- somma righe: deve combaciare con total_printed
    ocr_raw         JSONB,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE receipt_lines (
    id              BIGSERIAL PRIMARY KEY,
    receipt_id      UUID NOT NULL REFERENCES receipts(id) ON DELETE CASCADE,
    line_no         SMALLINT NOT NULL,
    raw_text        TEXT NOT NULL,                     -- 'LATTE PS GRANAR 1L'
    qty             NUMERIC(8,3) NOT NULL DEFAULT 1,
    unit_price      NUMERIC(10,2),
    line_total      NUMERIC(10,2) NOT NULL,
    discount        NUMERIC(10,2) NOT NULL DEFAULT 0,  -- righe 'SCONTO' agganciate alla riga sopra
    product_id      BIGINT REFERENCES products(id),
    match_confidence REAL,
    UNIQUE (receipt_id, line_no)
);

CREATE TABLE credit_ledger (
    id          BIGSERIAL PRIMARY KEY,
    user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    delta       INT NOT NULL,                          -- +10 scontrino validato, -100 riscatto 7gg Premium
    reason      TEXT NOT NULL,                         -- 'receipt_validated' | 'streak_bonus' | 'redeem_premium'
    receipt_id  UUID REFERENCES receipts(id),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------- Query tipo: store nel raggio ----------------------------
-- SELECT s.id, s.name, ST_Distance(s.location, :p) AS dist_m
-- FROM stores s
-- WHERE s.is_active AND ST_DWithin(s.location, :p, :radius_m)
-- ORDER BY s.location <-> :p;
