-- ============================================================================
-- Query 2236 — FORWARD-FIX B-SEMANTIC: catálogo de Edition Context
-- Status: PROPOSTA — NÃO EXECUTADA · Versão 1.0
-- Mandato: BATCH13-2831-B-SEMANTIC-REMEDIATION-PREP-01
--
-- AUTORIDADE
--   Decisões formais de Fabrício (2026-10-04), sobre a adjudicação
--   BATCH13-2831-B-SEMANTIC-ADJUDICATION-01 (2213-CRITICAL-PATH-DECISION.md §8–§9):
--     D1(a′) PIKACHU-TAIL é Edition Context = CAMPAIGN_PIKACHU_WORLD_2000.
--            Aprovada a SEMÂNTICA. NÃO autoriza resolver BASEP #24 nem BASE2 #60.
--     D2     o raw_data imutável da lineage é prova de composição para o legado
--            B. Supera, NESTE escopo, a premissa DEFERRED / B_UNPROVEN da 2231
--            (que existia por insuficiência de prova, não por decisão contrária).
--
-- O QUE FAZ (delta mínimo, só INSERT)
--   1 trait   CAMPAIGN_PIKACHU_WORLD_2000 (família CAMPAIGN)
--   31 profiles = 1 (Pikachu, aridade 1) + 30 assinaturas D2
--                 (11 de aridade 1 + 19 compostas de aridade 2)
--   50 links profile→trait = 1 + 11 + 19×2
--
-- O QUE NÃO FAZ
--   - NENHUM external mapping. Em particular, NENHUM mapping PIKACHU-TAIL: o
--     token continua sem routing operacional, então BASEP #24 (holo, fonte
--     contraditória) e BASE2 #60 continuam exatamente como estão. O profile
--     existir não altera resolução: o resolvedor só chega a um profile a partir
--     de traits obtidos por mapping (2211/2233).
--   - Nenhum UPDATE, DELETE, ALTER, trigger desabilitado ou constraint relaxada.
--   - Não edita 2230/2231/2232 (históricas, executadas).
--   - Não cria mapping de raw_field='foil' (ck_cecem_raw_field intocado).
--
-- PROVA DE QUANTIDADE (D2) — medida no LIVE (read-only, 2026-10-04):
--   33 Variants NO_PROFILE = 14 de aridade 1 + 19 compostas
--   assinaturas ÚNICAS     = 30 = 11 de aridade 1 + 19 compostas
--   (3 assinaturas de aridade 1 são compartilhadas por 2 Variants cada:
--    CAMPAIGN_POKEMON_4EVER, CAMPAIGN_POKEMON_TOGETHER, CHANNEL_POKEMON_CENTER_NY)
--   O PASSO 1 reprova a premissa se o LIVE divergir.
--
-- IDEMPOTÊNCIA CONTROLADA
--   Fail-closed e NÃO idempotente por desenho (padrão 2216 v4.1): se qualquer
--   objeto-alvo já existir, o PASSO 1 aborta com 2236_ALREADY_APPLIED e nada é
--   escrito. Reexecução nunca duplica nem "completa pela metade".
--
-- UUID: gen_random_uuid() (DEFAULT das tabelas), mesmo padrão de 2230/2231.
-- Nomenclatura: a de 2231 — code = traits em ordem alfabética unidos por '__';
--   name = names PT-BR dos traits na mesma ordem unidos por ' · ';
--   description = frase com o termo editorial de origem (en), derivado do
--   próprio trait no banco (zero texto digitado à mão para os 30).
-- ============================================================================

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ---------------------------------------------------------------- PASSO 0 ---
DO $$
DECLARE v_game INT; v_src INT;
BEGIN
    SELECT COUNT(*) INTO v_game FROM public.game WHERE code = 'POKEMON';
    IF v_game <> 1 THEN
        RAISE EXCEPTION '2236_GAME_REFERENCE: esperado EXATAMENTE 1 Game POKEMON, encontrado %.', v_game;
    END IF;
    SELECT COUNT(*) INTO v_src FROM public.asset_source WHERE code = 'TCGDEX';
    IF v_src <> 1 THEN
        RAISE EXCEPTION '2236_SOURCE_REFERENCE: esperado EXATAMENTE 1 asset_source TCGDEX, encontrado %.', v_src;
    END IF;
END $$;

CREATE TEMP TABLE fx_params ON COMMIT DROP AS
SELECT (SELECT id FROM public.game         WHERE code = 'POKEMON') AS game_id,
       (SELECT id FROM public.asset_source WHERE code = 'TCGDEX')  AS src_id;

-- As 30 assinaturas D2 (pares profile→trait), literalmente as medidas no LIVE.
CREATE TEMP TABLE fx_d2_link (profile_code TEXT, trait_code TEXT) ON COMMIT DROP;
INSERT INTO fx_d2_link (profile_code, trait_code) VALUES
    -- aridade 1 — 11 assinaturas
    ('CAMPAIGN_POKEMON_4EVER', 'CAMPAIGN_POKEMON_4EVER'),
    ('CAMPAIGN_POKEMON_DAY_30TH', 'CAMPAIGN_POKEMON_DAY_30TH'),
    ('CAMPAIGN_POKEMON_TOGETHER', 'CAMPAIGN_POKEMON_TOGETHER'),
    ('CHANNEL_ASIA_2023_24', 'CHANNEL_ASIA_2023_24'),
    ('CHANNEL_POKEMON_CENTER_NY', 'CHANNEL_POKEMON_CENTER_NY'),
    ('EVENT_INTERNATIONALS_EUROPE', 'EVENT_INTERNATIONALS_EUROPE'),
    ('EVENT_INTERNATIONALS_NORTH_AMERICA', 'EVENT_INTERNATIONALS_NORTH_AMERICA'),
    ('EVENT_POKETOUR_99', 'EVENT_POKETOUR_99'),
    ('EVENT_WORLDS_2023', 'EVENT_WORLDS_2023'),
    ('EVENT_WORLDS_2025', 'EVENT_WORLDS_2025'),
    ('PROGRAM_LEAGUE_ULTRA_BALL', 'PROGRAM_LEAGUE_ULTRA_BALL'),
    -- aridade 2 — 19 assinaturas
    ('EVENT_INTERNATIONALS_NORTH_AMERICA__ROLE_STAFF', 'EVENT_INTERNATIONALS_NORTH_AMERICA'),
    ('EVENT_INTERNATIONALS_NORTH_AMERICA__ROLE_STAFF', 'ROLE_STAFF'),
    ('EVENT_WORLDS_2023__PLACEMENT_FINALIST', 'EVENT_WORLDS_2023'),
    ('EVENT_WORLDS_2023__PLACEMENT_FINALIST', 'PLACEMENT_FINALIST'),
    ('EVENT_WORLDS_2023__PLACEMENT_SEMI_FINALIST', 'EVENT_WORLDS_2023'),
    ('EVENT_WORLDS_2023__PLACEMENT_SEMI_FINALIST', 'PLACEMENT_SEMI_FINALIST'),
    ('EVENT_WORLDS_2023__PLACEMENT_TOP_16', 'EVENT_WORLDS_2023'),
    ('EVENT_WORLDS_2023__PLACEMENT_TOP_16', 'PLACEMENT_TOP_16'),
    ('EVENT_WORLDS_2023__PLACEMENT_TOP_32', 'EVENT_WORLDS_2023'),
    ('EVENT_WORLDS_2023__PLACEMENT_TOP_32', 'PLACEMENT_TOP_32'),
    ('EVENT_WORLDS_2023__PLACEMENT_TOP_8', 'EVENT_WORLDS_2023'),
    ('EVENT_WORLDS_2023__PLACEMENT_TOP_8', 'PLACEMENT_TOP_8'),
    ('EVENT_WORLDS_2023__ROLE_STAFF', 'EVENT_WORLDS_2023'),
    ('EVENT_WORLDS_2023__ROLE_STAFF', 'ROLE_STAFF'),
    ('EVENT_WORLDS_2024__PLACEMENT_FINALIST', 'EVENT_WORLDS_2024'),
    ('EVENT_WORLDS_2024__PLACEMENT_FINALIST', 'PLACEMENT_FINALIST'),
    ('EVENT_WORLDS_2024__PLACEMENT_SEMI_FINALIST', 'EVENT_WORLDS_2024'),
    ('EVENT_WORLDS_2024__PLACEMENT_SEMI_FINALIST', 'PLACEMENT_SEMI_FINALIST'),
    ('EVENT_WORLDS_2024__PLACEMENT_TOP_16', 'EVENT_WORLDS_2024'),
    ('EVENT_WORLDS_2024__PLACEMENT_TOP_16', 'PLACEMENT_TOP_16'),
    ('EVENT_WORLDS_2024__PLACEMENT_TOP_32', 'EVENT_WORLDS_2024'),
    ('EVENT_WORLDS_2024__PLACEMENT_TOP_32', 'PLACEMENT_TOP_32'),
    ('EVENT_WORLDS_2024__PLACEMENT_TOP_8', 'EVENT_WORLDS_2024'),
    ('EVENT_WORLDS_2024__PLACEMENT_TOP_8', 'PLACEMENT_TOP_8'),
    ('EVENT_WORLDS_2024__ROLE_STAFF', 'EVENT_WORLDS_2024'),
    ('EVENT_WORLDS_2024__ROLE_STAFF', 'ROLE_STAFF'),
    ('EVENT_WORLDS_2025__PLACEMENT_FINALIST', 'EVENT_WORLDS_2025'),
    ('EVENT_WORLDS_2025__PLACEMENT_FINALIST', 'PLACEMENT_FINALIST'),
    ('EVENT_WORLDS_2025__PLACEMENT_SEMI_FINALIST', 'EVENT_WORLDS_2025'),
    ('EVENT_WORLDS_2025__PLACEMENT_SEMI_FINALIST', 'PLACEMENT_SEMI_FINALIST'),
    ('EVENT_WORLDS_2025__PLACEMENT_TOP_16', 'EVENT_WORLDS_2025'),
    ('EVENT_WORLDS_2025__PLACEMENT_TOP_16', 'PLACEMENT_TOP_16'),
    ('EVENT_WORLDS_2025__PLACEMENT_TOP_32', 'EVENT_WORLDS_2025'),
    ('EVENT_WORLDS_2025__PLACEMENT_TOP_32', 'PLACEMENT_TOP_32'),
    ('EVENT_WORLDS_2025__PLACEMENT_TOP_8', 'EVENT_WORLDS_2025'),
    ('EVENT_WORLDS_2025__PLACEMENT_TOP_8', 'PLACEMENT_TOP_8'),
    ('EVENT_WORLDS_2025__ROLE_STAFF', 'EVENT_WORLDS_2025'),
    ('EVENT_WORLDS_2025__ROLE_STAFF', 'ROLE_STAFF');

-- Consumidores D2: Variant Type legado → nº de Variants e assinatura esperada.
-- Fonte da prova de cobertura (PASSO 1) e do POSTCHECK (PASSO 4).
-- STANDARDS_WORLDS_2026_TOP_8 é typo de catálogo (nome/raw/mapping = Worlds
-- 2025 · Top 8); a assinatura vem do raw, não do code — ver §9 do doc.
CREATE TEMP TABLE fx_d2_consumer (legacy_type TEXT, n INT, profile_code TEXT) ON COMMIT DROP;
INSERT INTO fx_d2_consumer (legacy_type, n, profile_code) VALUES
    ('STANDARD_POKEMON_4EVER', 2, 'CAMPAIGN_POKEMON_4EVER'),
    ('POKEDAY_HOLO', 1, 'CAMPAIGN_POKEMON_DAY_30TH'),
    ('STANDARDS_POKEMON_TOGETHER', 2, 'CAMPAIGN_POKEMON_TOGETHER'),
    ('STANDARDS_ASIA_2023_2024', 1, 'CHANNEL_ASIA_2023_24'),
    ('STANDARD_POKEMON_CENTER_NY', 2, 'CHANNEL_POKEMON_CENTER_NY'),
    ('INTERNATIONAL_CHAMPIONSHIPS_EUROPE_HOLO', 1, 'EVENT_INTERNATIONALS_EUROPE'),
    ('INTERNATIONAL_CHAMPIONSHIPS_NORTH_AMERICA_REVERSE', 1, 'EVENT_INTERNATIONALS_NORTH_AMERICA'),
    ('STANDARD_POKETOUR_1999', 1, 'EVENT_POKETOUR_99'),
    ('STANDARDS_WORLDS_2023', 1, 'EVENT_WORLDS_2023'),
    ('STANDARDS_WORLDS_2025', 1, 'EVENT_WORLDS_2025'),
    ('STANDARD_ULTRA_BALL_LEAGUE', 1, 'PROGRAM_LEAGUE_ULTRA_BALL'),
    ('INTL_CHAMPIONSHIPS_NORTH_AMERICA_REVERSE_STAFF', 1, 'EVENT_INTERNATIONALS_NORTH_AMERICA__ROLE_STAFF'),
    ('STANDARDS_WORLDS_2023_TOP_2', 1, 'EVENT_WORLDS_2023__PLACEMENT_FINALIST'),
    ('STANDARDS_WORLDS_2023_TOP_4', 1, 'EVENT_WORLDS_2023__PLACEMENT_SEMI_FINALIST'),
    ('STANDARDS_WORLDS_2023_TOP_16', 1, 'EVENT_WORLDS_2023__PLACEMENT_TOP_16'),
    ('STANDARDS_WORLDS_2023_TOP_32', 1, 'EVENT_WORLDS_2023__PLACEMENT_TOP_32'),
    ('STANDARDS_WORLDS_2023_TOP_8', 1, 'EVENT_WORLDS_2023__PLACEMENT_TOP_8'),
    ('STANDARDS_WORLDS_2023_STAFF', 1, 'EVENT_WORLDS_2023__ROLE_STAFF'),
    ('STANDARDS_WORLDS_2024_TOP_2', 1, 'EVENT_WORLDS_2024__PLACEMENT_FINALIST'),
    ('STANDARDS_WORLDS_2024_TOP_4', 1, 'EVENT_WORLDS_2024__PLACEMENT_SEMI_FINALIST'),
    ('STANDARDS_WORLDS_2024_TOP_16', 1, 'EVENT_WORLDS_2024__PLACEMENT_TOP_16'),
    ('STANDARDS_WORLDS_2024_TOP_32', 1, 'EVENT_WORLDS_2024__PLACEMENT_TOP_32'),
    ('STANDARDS_WORLDS_2024_TOP_8', 1, 'EVENT_WORLDS_2024__PLACEMENT_TOP_8'),
    ('STANDARDS_WORLDS_2024_STAFF', 1, 'EVENT_WORLDS_2024__ROLE_STAFF'),
    ('STANDARDS_WORLDS_2025_TOP_2', 1, 'EVENT_WORLDS_2025__PLACEMENT_FINALIST'),
    ('STANDARDS_WORLDS_2025_TOP_4', 1, 'EVENT_WORLDS_2025__PLACEMENT_SEMI_FINALIST'),
    ('STANDARDS_WORLDS_2025_TOP_16', 1, 'EVENT_WORLDS_2025__PLACEMENT_TOP_16'),
    ('STANDARDS_WORLDS_2025_TOP_32', 1, 'EVENT_WORLDS_2025__PLACEMENT_TOP_32'),
    ('STANDARDS_WORLDS_2026_TOP_8', 1, 'EVENT_WORLDS_2025__PLACEMENT_TOP_8'),
    ('STANDARDS_WORLDS_2025_STAFF', 1, 'EVENT_WORLDS_2025__ROLE_STAFF');

-- Resolução atual (read-only) da evidência de lineage de cada Variant
-- consumidora: row mais antiga com resulting_variant_id (mesma regra da 2831).
CREATE TEMP TABLE fx_d2_variant ON COMMIT DROP AS
WITH v AS (
    SELECT cv.id AS card_variant_id, c.card_set_id, vt.code AS legacy_type, k.profile_code
      FROM public.card_variant cv
      JOIN public.card_variant_type vt ON vt.id = cv.variant_type_id
      JOIN public.card c ON c.id = cv.card_id
      JOIN fx_d2_consumer k ON k.legacy_type = vt.code
), ev AS (
    SELECT DISTINCT ON (r.resulting_variant_id) r.resulting_variant_id AS card_variant_id, r.raw_data
      FROM public.catalog_variant_import_row r
     WHERE r.resulting_variant_id IN (SELECT card_variant_id FROM v)
     ORDER BY r.resulting_variant_id, r.created_at, r.id
)
SELECT v.card_variant_id, v.legacy_type, v.profile_code, ev.raw_data
  FROM v LEFT JOIN ev ON ev.card_variant_id = v.card_variant_id;

-- ---------------------------------------------------------------- PASSO 1 ---
-- PRE fail-loud. Nenhuma escrita antes deste bloco passar.
DO $$
DECLARE v_n INT; v_m INT; v_txt TEXT; p fx_params%ROWTYPE;
BEGIN
    SELECT * INTO p FROM fx_params;

    -- Idempotência controlada: nada do alvo pode existir.
    SELECT COUNT(*) INTO v_n FROM public.card_edition_context_trait
     WHERE game_id = p.game_id AND code = 'CAMPAIGN_PIKACHU_WORLD_2000';
    SELECT COUNT(*) INTO v_m FROM public.card_edition_context_profile
     WHERE game_id = p.game_id
       AND code IN (SELECT DISTINCT profile_code FROM fx_d2_link UNION SELECT 'CAMPAIGN_PIKACHU_WORLD_2000');
    IF v_n <> 0 OR v_m <> 0 THEN
        RAISE EXCEPTION '2236_ALREADY_APPLIED: trait Pikachu=% / profiles-alvo existentes=%. Nada foi escrito.', v_n, v_m;
    END IF;

    -- Slots de ordenação livres (trait CAMPAIGN 140; profiles 1450–1750).
    IF EXISTS (SELECT 1 FROM public.card_edition_context_trait
                WHERE game_id = p.game_id AND family = 'CAMPAIGN' AND display_order = 140)
       OR EXISTS (SELECT 1 FROM public.card_edition_context_profile
                   WHERE game_id = p.game_id AND display_order BETWEEN 1450 AND 1750) THEN
        RAISE EXCEPTION '2236_ORDER_SLOT_TAKEN: display_order reservado já ocupado.';
    END IF;

    -- D2: 30 assinaturas = 11 de aridade 1 + 19 compostas; 49 links.
    SELECT COUNT(DISTINCT profile_code), COUNT(*) INTO v_n, v_m FROM fx_d2_link;
    IF v_n <> 30 OR v_m <> 49 THEN
        RAISE EXCEPTION '2236_D2_SEED_SHAPE: esperado 30 assinaturas / 49 links, obtido % / %.', v_n, v_m;
    END IF;
    SELECT COUNT(*) FILTER (WHERE c = 1), COUNT(*) FILTER (WHERE c = 2) INTO v_n, v_m
      FROM (SELECT profile_code, COUNT(*) c FROM fx_d2_link GROUP BY 1) z;
    IF v_n <> 11 OR v_m <> 19 THEN
        RAISE EXCEPTION '2236_D2_ARITY_SPLIT: esperado 11 de aridade 1 / 19 compostas, obtido % / %.', v_n, v_m;
    END IF;

    -- code == traits em ordem alfabética unidos por '__' (regra da 2231).
    SELECT COUNT(*) INTO v_n FROM (
        SELECT profile_code, string_agg(trait_code, '__' ORDER BY trait_code) AS rebuilt
          FROM fx_d2_link GROUP BY profile_code) z
     WHERE z.rebuilt <> z.profile_code;
    IF v_n <> 0 THEN
        RAISE EXCEPTION '2236_D2_CODE_RULE: % profiles com code fora da regra de composição.', v_n;
    END IF;

    -- Nenhuma composição duplicada dentro do seed.
    SELECT COUNT(*) INTO v_n FROM (
        SELECT sig FROM (SELECT profile_code, array_agg(trait_code ORDER BY trait_code) sig
                           FROM fx_d2_link GROUP BY 1) a GROUP BY sig HAVING COUNT(*) > 1) d;
    IF v_n <> 0 THEN
        RAISE EXCEPTION '2236_D2_SEED_SIGNATURE_DUPLICATE: %.', v_n;
    END IF;

    -- Todos os traits D2 existem, ativos, no Game, com termo (en) extraível.
    SELECT string_agg(DISTINCT l.trait_code, ', ') INTO v_txt
      FROM fx_d2_link l
     WHERE NOT EXISTS (SELECT 1 FROM public.card_edition_context_trait t
                        WHERE t.game_id = p.game_id AND t.code = l.trait_code AND t.is_active
                          AND substring(t.description from 'origem \(en\): "([^"]+)"') IS NOT NULL);
    IF v_txt IS NOT NULL THEN
        RAISE EXCEPTION '2236_D2_TRAIT_MISSING_OR_INACTIVE: %.', v_txt;
    END IF;

    -- Nenhuma assinatura-alvo já possui profile (comparação pelo selo real).
    SELECT COUNT(*) INTO v_n
      FROM (SELECT l.profile_code, array_agg(t.id ORDER BY t.id) AS sig
              FROM fx_d2_link l JOIN public.card_edition_context_trait t
                ON t.code = l.trait_code AND t.game_id = p.game_id
             GROUP BY l.profile_code) s
     WHERE EXISTS (SELECT 1 FROM public.card_edition_context_profile x
                    WHERE x.game_id = p.game_id AND x.traits_signature = s.sig);
    IF v_n <> 0 THEN
        RAISE EXCEPTION '2236_D2_SIGNATURE_ALREADY_HAS_PROFILE: %.', v_n;
    END IF;

    -- Cobertura: as 33 Variants consumidoras existem, têm lineage, resolvem
    -- HOJE como NEEDS_REVIEW_NO_EC_PROFILE e a composição do próprio raw é
    -- exatamente a assinatura esperada. 33 Variants -> 30 assinaturas.
    SELECT COUNT(*) INTO v_n FROM fx_d2_variant;
    SELECT SUM(n) INTO v_m FROM fx_d2_consumer;
    IF v_n <> 33 OR v_m <> 33 THEN
        RAISE EXCEPTION '2236_D2_COVERAGE_CARDINALITY: Variants consumidoras %, esperado 33 (seed declara %).', v_n, v_m;
    END IF;
    SELECT COUNT(*) INTO v_n FROM (
        SELECT k.legacy_type FROM fx_d2_consumer k
          LEFT JOIN fx_d2_variant v ON v.legacy_type = k.legacy_type
         GROUP BY k.legacy_type, k.n HAVING COUNT(v.card_variant_id) <> k.n) z;
    IF v_n <> 0 THEN
        RAISE EXCEPTION '2236_D2_COVERAGE_PER_TYPE: % Variant Types com contagem divergente.', v_n;
    END IF;
    IF EXISTS (SELECT 1 FROM fx_d2_variant WHERE raw_data IS NULL) THEN
        RAISE EXCEPTION '2236_D2_COVERAGE_NO_LINEAGE: Variant consumidora sem row de lineage.';
    END IF;
    SELECT COUNT(*) INTO v_n
      FROM fx_d2_variant v
      JOIN public.card_variant cv ON cv.id = v.card_variant_id
      JOIN public.card c ON c.id = cv.card_id
      LEFT JOIN LATERAL internal.resolve_variant_mapping_scope(c.card_set_id, p.src_id) sc ON TRUE
      CROSS JOIN LATERAL internal.resolve_variant_row_axes(v.raw_data, p.game_id, p.src_id, sc.external_set_id) ax
     WHERE ax.edition_context_state IS DISTINCT FROM 'NEEDS_REVIEW_NO_EC_PROFILE'
        OR (SELECT string_agg(t.code::TEXT, '__' ORDER BY t.code)
              FROM public.card_edition_context_trait t WHERE t.id = ANY(ax.edition_context_trait_ids))
           IS DISTINCT FROM v.profile_code;
    IF v_n <> 0 THEN
        RAISE EXCEPTION '2236_D2_COVERAGE_SIGNATURE: % Variants não resolvem hoje para NEEDS_REVIEW_NO_EC_PROFILE com a assinatura esperada.', v_n;
    END IF;
    SELECT COUNT(DISTINCT profile_code) INTO v_n FROM fx_d2_variant;
    IF v_n <> 30 THEN
        RAISE EXCEPTION '2236_D2_COVERAGE_UNIQUE: as 33 Variants cobrem % assinaturas, esperado 30.', v_n;
    END IF;

    -- D1 HOLD-safe (PRE): não existe mapping PIKACHU-TAIL e este arquivo não cria.
    SELECT COUNT(*) INTO v_n FROM public.card_edition_context_external_mapping
     WHERE upper(normalized_token) = 'PIKACHU-TAIL';
    IF v_n <> 0 THEN
        RAISE EXCEPTION '2236_D1_UNEXPECTED_PIKACHU_MAPPING: % mapping(s) PIKACHU-TAIL já existem — premissa D1 inválida.', v_n;
    END IF;
END $$;

-- Contagens PRE para os deltas exatos do POST.
CREATE TEMP TABLE fx_pre ON COMMIT DROP AS
SELECT (SELECT COUNT(*) FROM public.card_edition_context_trait)                 AS traits,
       (SELECT COUNT(*) FROM public.card_edition_context_profile)               AS profiles,
       (SELECT COUNT(*) FROM public.card_edition_context_profile_trait)         AS links,
       (SELECT COUNT(*) FROM public.card_edition_context_external_mapping)      AS mappings,
       (SELECT COUNT(*) FROM public.card_edition_context_external_mapping_trait) AS mapping_links;

-- ---------------------------------------------------------------- PASSO 2 ---
-- D1: trait (só existência semântica; nenhum mapping).
INSERT INTO public.card_edition_context_trait (game_id, family, code, name, description, display_order)
SELECT p.game_id, 'CAMPAIGN', 'CAMPAIGN_PIKACHU_WORLD_2000', 'Pikachu World Collection 2000',
       'Traço de Contexto de Edição da família Campanha. Termo editorial de origem (en): "Pikachu World Collection 2000".',
       140
  FROM fx_params p;

-- Todos os links que este arquivo grava: 1 (D1) + 49 (D2) = 50.
CREATE TEMP TABLE fx_link ON COMMIT DROP AS
SELECT 'CAMPAIGN_PIKACHU_WORLD_2000'::TEXT AS profile_code, 'CAMPAIGN_PIKACHU_WORLD_2000'::TEXT AS trait_code
UNION ALL
SELECT profile_code, trait_code FROM fx_d2_link;

-- Profiles: name/description DERIVADOS dos traits (regra 2231 P5/P7).
-- Ordem: Pikachu 1450; os 30 D2 em ordem de code, 1460..1750, passo 10.
INSERT INTO public.card_edition_context_profile (game_id, code, name, description, display_order)
SELECT p.game_id, s.profile_code, s.name, s.description, s.display_order
  FROM fx_params p
  CROSS JOIN LATERAL (
      SELECT l.profile_code,
             string_agg(t.name, ' ' || chr(183) || ' ' ORDER BY t.code) AS name,
             CASE WHEN COUNT(*) = 1
                  THEN 'Contexto de Edição de traço único. Termo editorial de origem (en): "'
                  ELSE 'Composição de ' || COUNT(*) || ' traços de Contexto de Edição. Termo editorial de origem (en): "'
             END
             || string_agg(substring(t.description from 'origem \(en\): "([^"]+)"'), ' ' || chr(183) || ' ' ORDER BY t.code)
             || '".' AS description,
             CASE WHEN l.profile_code = 'CAMPAIGN_PIKACHU_WORLD_2000' THEN 1450
                  ELSE 1450 + 10 * (DENSE_RANK() OVER (ORDER BY (l.profile_code = 'CAMPAIGN_PIKACHU_WORLD_2000'), l.profile_code))::INT
             END AS display_order
        FROM fx_link l
        JOIN public.card_edition_context_trait t ON t.code = l.trait_code AND t.game_id = p.game_id
       GROUP BY l.profile_code
  ) s;

INSERT INTO public.card_edition_context_profile_trait (profile_id, trait_id, game_id)
SELECT pr.id, t.id, pr.game_id
  FROM fx_link l
  JOIN fx_params p ON TRUE
  JOIN public.card_edition_context_profile pr ON pr.code = l.profile_code AND pr.game_id = p.game_id
  JOIN public.card_edition_context_trait   t  ON t.code  = l.trait_code   AND t.game_id  = p.game_id;

-- ---------------------------------------------------------------- PASSO 3 ---
-- Força o selo deferido (trg_cecp_seal) agora, como na 2231 PASSO 3: sem isto
-- os gates abaixo leriam traits_signature NULL.
SET CONSTRAINTS ALL IMMEDIATE;

-- ---------------------------------------------------------------- PASSO 4 ---
-- POST fail-loud.
DO $$
DECLARE v_n INT; v_m INT; f fx_pre%ROWTYPE; p fx_params%ROWTYPE;
BEGIN
    SELECT * INTO f FROM fx_pre;
    SELECT * INTO p FROM fx_params;

    -- Deltas exatos.
    IF (SELECT COUNT(*) FROM public.card_edition_context_trait) <> f.traits + 1 THEN
        RAISE EXCEPTION '2236_POST_TRAIT_DELTA: esperado +1.'; END IF;
    IF (SELECT COUNT(*) FROM public.card_edition_context_profile) <> f.profiles + 31 THEN
        RAISE EXCEPTION '2236_POST_PROFILE_DELTA: esperado +31 (1 D1 + 30 D2).'; END IF;
    IF (SELECT COUNT(*) FROM public.card_edition_context_profile_trait) <> f.links + 50 THEN
        RAISE EXCEPTION '2236_POST_LINK_DELTA: esperado +50.'; END IF;

    -- Zero external mapping criado (D1 HOLD-safe e escopo do arquivo).
    IF (SELECT COUNT(*) FROM public.card_edition_context_external_mapping) <> f.mappings
       OR (SELECT COUNT(*) FROM public.card_edition_context_external_mapping_trait) <> f.mapping_links THEN
        RAISE EXCEPTION '2236_POST_MAPPING_TOUCHED: external mapping alterado.'; END IF;
    IF EXISTS (SELECT 1 FROM public.card_edition_context_external_mapping WHERE upper(normalized_token) = 'PIKACHU-TAIL') THEN
        RAISE EXCEPTION '2236_POST_PIKACHU_MAPPING_CREATED: proibido por D1(a′).'; END IF;

    -- Selo = N:N para os 31 novos; aridade correta; nenhuma assinatura duplicada.
    SELECT COUNT(*) INTO v_n
      FROM public.card_edition_context_profile pr
     WHERE pr.code IN (SELECT DISTINCT profile_code FROM fx_link)
       AND (pr.traits_signature IS NULL
            OR pr.traits_signature IS DISTINCT FROM ARRAY(
                 SELECT x.trait_id FROM public.card_edition_context_profile_trait x
                  WHERE x.profile_id = pr.id ORDER BY x.trait_id)
            OR cardinality(pr.traits_signature) <> (SELECT COUNT(*) FROM fx_link l WHERE l.profile_code = pr.code));
    IF v_n <> 0 THEN
        RAISE EXCEPTION '2236_POST_SIGNATURE: % profiles novos com selo/aridade divergente.', v_n; END IF;
    SELECT COUNT(*) INTO v_n FROM (
        SELECT game_id, traits_signature FROM public.card_edition_context_profile
         GROUP BY 1, 2 HAVING COUNT(*) > 1) d;
    IF v_n <> 0 THEN
        RAISE EXCEPTION '2236_POST_SIGNATURE_DUPLICATE: %.', v_n; END IF;

    -- name = composição (P5) e description com termo de origem (P7), nos 31.
    SELECT COUNT(*) INTO v_n
      FROM public.card_edition_context_profile pr
      JOIN LATERAL (SELECT string_agg(t.name, ' ' || chr(183) || ' ' ORDER BY t.code) AS expected
                      FROM public.card_edition_context_profile_trait x
                      JOIN public.card_edition_context_trait t ON t.id = x.trait_id
                     WHERE x.profile_id = pr.id) c ON TRUE
     WHERE pr.code IN (SELECT DISTINCT profile_code FROM fx_link)
       AND (c.expected IS DISTINCT FROM pr.name
            OR pr.description IS NULL OR pr.description = pr.name
            OR pr.description NOT LIKE '%Termo editorial de origem (en):%'
            OR length(pr.name) > 200);
    IF v_n <> 0 THEN
        RAISE EXCEPTION '2236_POST_LABEL_SHAPE: % profiles fora da regra P5/P6/P7.', v_n; END IF;

    -- Efeito D2: as 33 Variants agora resolvem RESOLVED_WITH_EC_PROFILE no
    -- profile esperado — pelo resolvedor OPERACIONAL vigente, sem alterá-lo.
    SELECT COUNT(*) INTO v_n
      FROM fx_d2_variant v
      JOIN public.card_variant cv ON cv.id = v.card_variant_id
      JOIN public.card c ON c.id = cv.card_id
      LEFT JOIN LATERAL internal.resolve_variant_mapping_scope(c.card_set_id, p.src_id) sc ON TRUE
      CROSS JOIN LATERAL internal.resolve_variant_row_axes(v.raw_data, p.game_id, p.src_id, sc.external_set_id) ax
      LEFT JOIN public.card_edition_context_profile pr ON pr.id = ax.edition_context_profile_id
     WHERE ax.edition_context_state IS DISTINCT FROM 'RESOLVED_WITH_EC_PROFILE'
        OR pr.code IS DISTINCT FROM v.profile_code;
    IF v_n <> 0 THEN
        RAISE EXCEPTION '2236_POST_D2_NOT_RESOLVED: % das 33 Variants não resolvem para o profile esperado.', v_n; END IF;

    -- D1 HOLD-safe (POST): nenhuma row com stamp pikachu-tail passa a resolver
    -- Edition Context — nem as 6 de lineage, nem BASEP #24, nem BASE2 #60.
    -- Medido no LIVE (2026-10-04): 8 rows (6 lineage + BASEP #24 holo +
    -- BASE2 #60), todas RESOLVED_NO_EDITION_CONTEXT com residual_stamp
    -- {PIKACHU-TAIL}. Tem de continuar EXATAMENTE assim.
    SELECT COUNT(*),
           COUNT(*) FILTER (WHERE ax.edition_context_state IS DISTINCT FROM 'RESOLVED_NO_EDITION_CONTEXT'
                               OR ax.edition_context_profile_id IS NOT NULL
                               OR ax.residual_stamp IS DISTINCT FROM ARRAY['PIKACHU-TAIL']::TEXT[])
      INTO v_n, v_m
      FROM public.catalog_variant_import_row r
      JOIN public.catalog_variant_import_job j ON j.id = r.job_id
      LEFT JOIN LATERAL internal.resolve_variant_mapping_scope(j.card_set_id, p.src_id) sc ON TRUE
      CROSS JOIN LATERAL internal.resolve_variant_row_axes(r.raw_data, p.game_id, p.src_id, sc.external_set_id) ax
     WHERE jsonb_typeof(r.raw_data -> 'stamp') = 'array'
       AND (r.raw_data -> 'stamp') ? 'pikachu-tail';
    IF v_n <> 8 OR v_m <> 0 THEN
        RAISE EXCEPTION '2236_POST_D1_HOLD_BROKEN: rows pikachu-tail=% (esperado 8), fora de RESOLVED_NO_EDITION_CONTEXT/{PIKACHU-TAIL}=% (esperado 0).', v_n, v_m; END IF;

    RAISE NOTICE '2236 OK — +1 trait, +31 profiles (1 D1 + 11 + 19), +50 links, 0 mappings; 33 Variants D2 resolvidas; % rows pikachu-tail seguem sem routing.', v_n;
END $$;

-- Terminador COMMIT, como as seeds 2230–2232 e a 2235: a proteção contra
-- execução prematura é GOVERNANÇA (mandato próprio de Fabrício), não o
-- terminador. Qualquer gate acima aborta a transação inteira.
COMMIT;
