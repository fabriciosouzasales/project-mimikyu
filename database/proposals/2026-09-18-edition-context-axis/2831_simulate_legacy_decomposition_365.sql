-- ============================================================================
-- Query 2831 — SIMULAÇÃO da decomposição do legado (READY_UNCONDITIONED)
--              card_variant + lineage, ATÔMICO (LINEAGE-STRATEGY Correção 6)
-- ESTE ARQUIVO NAO E MIGRATION. Termina em ROLLBACK por contrato.
-- A migration real sera numerada 2213 e escrita SOMENTE apos Gate A.
-- Status: PROPOSTA — NÃO EXECUTADA · Versão 3.0
--
-- v3.0 (BATCH13-2831-READINESS-CONTRACT-RECONCILIATION-01) — a v2.0 tinha
-- quatro defeitos reais contra o contrato vigente:
--   H6  LINEAGE AUSENTE. A v2.0 escrevia somente card_variant. A Correção 6
--       (LINEAGE-STRATEGY.md) exige card_variant + lineage na MESMA transação,
--       com as provas L1 (lineage reconciliado), L2 (zero híbrido), L3 (nada
--       fora das 285 tocado) e L4 (resulting_variant_id preservado). Nenhuma
--       delas existia; o cabeçalho afirmava "Preserva ... lineage", o que era
--       só comentário. A v2.0 produziria exatamente o híbrido que a Correção 5
--       proíbe, por omissão.
--   H7  PLANO SEM RECORTE READY. O plano da v2.0 era "toda Variant com lineage
--       fora do HOLD e do Pricing" (candidato C1 da medição B-5X, 23.166
--       Variants no LIVE de 2026-09-28), não as 365/285. O PASSO 2 abortaria
--       sempre em PLAN_COVERAGE_MISMATCH. A definição adjudicada de
--       READY_STRUCTURAL é C3 (harness/B5X-C3-ADJUDICATION-RECORD.md, decisão
--       de Fabrício 2026-09-28), reproduzida aqui literalmente.
--   H8  sim_params NASCIA NULL e abortava em SIM_PARAMS_UNSET: o arquivo não
--       era executável verbatim. Agora resolve Game e Fonte por code, com
--       preflight exatamente-um — o padrão canônico da 2212 v3.1.
--   H9  O gate de colisão usava o printing do RESOLVEDOR, mas o UPDATE preserva
--       o printing da Variant. A identidade testada não era a gravada. Agora a
--       colisão usa cv.printing_profile_id, e um gate exige que os dois sejam
--       iguais (PLAN_PRINTING_DRIFT).
--
-- CONTRATO
--   UPDATE puro em card_variant (variant_type_id, edition_context_profile_id).
--   Preserva id, printing_profile_id, variant_order, is_default.
--   UPDATE puro em catalog_variant_import_row.normalized_data, SOMENTE nas
--   chaves variant_type_id e edition_context_profile_id, SOMENTE nas rows com
--   resulting_variant_id ∈ plano. Mesmo padrão da 2219 (jsonb_set encadeado,
--   create_missing = true, UUID como string JSON). Nenhuma outra coluna, nenhuma
--   outra chave, nenhuma outra row. raw_data imutável.
--   NUNCA DELETE+INSERT. Nenhuma linha HOLD e nenhuma PRICING_CONDITIONED.
--   Collision gates rodam ANTES de qualquer UPDATE.
--   Nenhum trigger ou guard é desabilitado.
--
-- PRE-REQUISITO DE EXECUCAO
--   2203-2224 + 2233/2234 aplicados; 115 traits / 144 profiles / 122 mappings
--   semeados (LIVE já satisfaz). Execução só com mandato próprio, após
--   auditoria independente desta versão, com PRE JIT e L3 (concorrência).
--
-- BLOQUEIO SEMÂNTICO CONHECIDO (B-SEMANTIC — 2213-CRITICAL-PATH-DECISION.md)
--   Medido read-only no LIVE em 2026-10-04: das 285, 46 ainda não têm destino
--   determinístico (33 NEEDS_REVIEW_NO_EC_PROFILE · 11 RESOLVED_NO_EDITION_CONTEXT
--   · 2 finish_target NULL). Enquanto isso valer, este arquivo ABORTA no PASSO 2
--   (PLAN_NON_DETERMINISTIC_CONTEXT), e é o comportamento correto. O plano (285)
--   e a âncora NÃO são reduzidos para tornar o gate verde.
--
-- ORDEM DOS UPDATEs E GUARDS (prova em LINEAGE-STRATEGY.md, nota v3.0)
--   card_variant primeiro, lineage depois, na mesma transação. Nenhum guard
--   cruza as duas tabelas, então a ordem não altera aceitação; ela é a ordem
--   de LOCK (cv → cvir) e é fixa. Estados intermediários não são visíveis a
--   outras sessões (MVCC) e os guards por linha aceitam cada estado:
--     trg_card_variant_validate_game_consistency  finish do mesmo Game (gate P1)
--     trg_card_variant_edition_context_profile_game profile do mesmo Game
--     uq_card_variant_identity (imediata)         toda identidade nova tem EC
--         não-nulo e toda atual do plano tem EC nulo ⇒ sem colisão transitória
--     trg_cvir_normalized_shape (2214)            UUID string; VALID mantém
--         variant_type_id e a chave printing (gate LINEAGE_VALID_WITHOUT_PRINTING_KEY)
--     uq_cvir_row_identity (imediata)             token novo 'U:<ec>' não existe
--         em nenhuma row-alvo antes (gate) ⇒ sem colisão transitória
--     trg_*_set_updated_at                        updated_at muda (metadado)
--
-- ESTRUTURA (fail-loud; qualquer divergência aborta a transação inteira)
--   PASSO P    parâmetros por code (preflight exatamente-um)
--   PASSO 0    congelar HOLD (107)
--   PASSO 0B   congelar PRICING_CONDITIONED — derivado do LIVE
--   PASSO 0C   READY_STRUCTURAL = C3 adjudicado; plano = C3 ∖ Pricing
--   PASSO 0D   lock das Variants do plano + gates de cardinalidade e âncora
--   PASSO 1    evidência via lineage + eixos + destino de acabamento
--   PASSO 1B   lineage-alvo: lock, snapshot PRE, fingerprints L3
--   PASSO 2    GATES do plano e do lineage
--   PASSO 3    GATES de colisão (card_variant e staging), antes de escrever
--   PASSO 4A   UPDATE card_variant (contagem exata)
--   PASSO 4B   UPDATE lineage (contagem exata)
--   PASSO 5    POSTCHECK: L1, L2, L3, L4, L8, L9, HOLD, Pricing
-- ============================================================================

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ---------------------------------------------------------------- PASSO P ---
-- Padrão canônico da 2212 v3.1: referência por code, exatamente-um, sem UUID
-- no arquivo. 0 = ausente; >1 = ambíguo (multiplicaria o plano no CROSS JOIN).
DO $$
DECLARE v_game INT; v_src INT;
BEGIN
    SELECT COUNT(*) INTO v_game FROM public.game         WHERE code = 'POKEMON';
    IF v_game <> 1 THEN
        RAISE EXCEPTION 'SIM_GAME_REFERENCE (2831): esperado EXATAMENTE 1 Game com code=''POKEMON'', encontrado %.', v_game;
    END IF;
    SELECT COUNT(*) INTO v_src FROM public.asset_source WHERE code = 'TCGDEX';
    IF v_src <> 1 THEN
        RAISE EXCEPTION 'SIM_SOURCE_REFERENCE (2831): esperado EXATAMENTE 1 asset_source com code=''TCGDEX'', encontrado %.', v_src;
    END IF;
END $$;

CREATE TEMP TABLE sim_params ON COMMIT DROP AS
SELECT (SELECT id FROM public.game         WHERE code = 'POKEMON') AS game_id,
       (SELECT id FROM public.asset_source WHERE code = 'TCGDEX')  AS asset_source_id;

DO $$
DECLARE v_n INT;
BEGIN
    SELECT COUNT(*) INTO v_n FROM sim_params;
    IF v_n <> 1 OR EXISTS (SELECT 1 FROM sim_params WHERE game_id IS NULL OR asset_source_id IS NULL) THEN
        RAISE EXCEPTION 'SIM_PARAMS_INVALID: sim_params deveria ter exatamente 1 linha nao nula (linhas: %).', v_n;
    END IF;
END $$;

-- ---------------------------------------------------------------- PASSO 0 ---
-- Predicado inalterado desde a v2.0 (HOLD-MANIFEST H1).
CREATE TEMP TABLE hold_frozen ON COMMIT DROP AS
SELECT cv.id
  FROM public.card_variant cv
  JOIN public.card_variant_type vt ON vt.id = cv.variant_type_id
  JOIN public.card c  ON c.id  = cv.card_id
  JOIN public.card_set cs ON cs.id = c.card_set_id
 WHERE vt.code = 'PROMO_STAMPED'
    OR (vt.code LIKE 'SET_LOGO%'
        AND cs.code !~ '^EX(7|8|9|10|11|12|13|14|15|16)$'
        AND cs.code NOT IN ('DP1','SWSH9','SVP'));

DO $$
DECLARE v_n INT;
BEGIN
    SELECT COUNT(*) INTO v_n FROM hold_frozen;
    IF v_n <> 107 THEN
        RAISE EXCEPTION 'HOLD_FROZEN_MISMATCH: esperado 107, obtido %.', v_n;
    END IF;
END $$;

-- --------------------------------------------------------------- PASSO 0B ---
-- GUARD DE PRICING (HOLD-MANIFEST H6). Inalterado desde a v2.0. DERIVADO DO
-- LIVE: pricing_source_card_identity e pricing_source_variant_mapping são
-- testados SEPARADAMENTE e nunca somados.
CREATE TEMP TABLE pricing_conditioned ON COMMIT DROP AS
SELECT cv.id
  FROM public.card_variant cv
 WHERE EXISTS (SELECT 1 FROM public.pricing_source_card_identity x
                WHERE x.card_variant_type_id = cv.variant_type_id)
    OR EXISTS (SELECT 1 FROM public.pricing_source_variant_mapping x
                WHERE x.variant_type_id = cv.variant_type_id);

-- --------------------------------------------------------------- PASSO 0C ---
-- READY_STRUCTURAL = C3, ADJUDICADO (harness/B5X-C3-ADJUDICATION-RECORD.md).
-- Lista FINISH e predicado copiados literalmente do E15P (trechos
-- d5_finish/d5_c3, md5 de65… / e629…). O plano é C3 ∖ PRICING_CONDITIONED —
-- a mesma definição de d1_plan_derived do E15 (D1 2026-09-29), cuja
-- equivalência com o contrato nominal foi provada no LIVE.
CREATE TEMP TABLE finish_codes ON COMMIT DROP AS
SELECT code FROM (VALUES ('STANDARD'), ('HOLO'), ('COSMOS_HOLO'), ('REVERSE_HOLO'),
       ('ENERGY_REVERSE'), ('POKE_BALL_REVERSE'), ('LOVE_BALL_REVERSE'),
       ('FRIEND_BALL_REVERSE'), ('QUICK_BALL_REVERSE'), ('DUSK_BALL_REVERSE'),
       ('ROCKET_REVERSE'), ('MASTER_BALL_REVERSE'), ('GOLD_HOLO'), ('TINSEL_HOLO'),
       ('TINSEL_REVERSE'), ('CRACKED_ICE_HOLO'), ('GALAXY_HOLO'), ('RAINBOW_HOLO'),
       ('METAL'), ('METAL_GOLD'), ('LENTICULAR'), ('COSMOS_REVERSE'),
       ('MASTER_BALL_PATTERN'), ('POKE_BALL_PATTERN'), ('MASTER_BALL_HOLO'),
       ('SNOWFLAKE_COSMOS_HOLO'), ('STANDARDS_SNOWFLAKE'), ('SHOWFLAKE_HOLO')) f(code);

CREATE TEMP TABLE ready_structural ON COMMIT DROP AS
SELECT cv.id, vt.code AS legacy_type
  FROM public.card_variant cv
  JOIN public.card_variant_type vt ON vt.id = cv.variant_type_id
  JOIN public.card c  ON c.id  = cv.card_id
  JOIN public.card_set cs ON cs.id = c.card_set_id
 WHERE vt.code NOT IN (SELECT code FROM finish_codes)
   AND NOT (vt.code LIKE 'SET_LOGO%' AND cs.code ~ '^EX(7|8|9|10|11|12|13|14|15|16)$')
   AND NOT (vt.code LIKE 'SET_LOGO%' AND cs.code NOT IN ('DP1','SWSH9','SVP'))
   AND vt.code <> 'PROMO_STAMPED';

CREATE TEMP TABLE plan_ids ON COMMIT DROP AS
SELECT r.id AS card_variant_id
  FROM ready_structural r
 WHERE r.id NOT IN (SELECT id FROM pricing_conditioned)
   AND r.id NOT IN (SELECT id FROM hold_frozen);

-- --------------------------------------------------------------- PASSO 0D ---
-- Lock das Variants do plano em ordem determinística (ordem de lock: cv → cvir).
DO $$
BEGIN
    PERFORM 1 FROM public.card_variant cv
      WHERE cv.id IN (SELECT card_variant_id FROM plan_ids)
      ORDER BY cv.id
        FOR UPDATE;
END $$;

-- Cardinalidades CONTRATUAIS, nunca reajustadas. A âncora md5 é a do D1 LIVE
-- (2026-09-29T01:43:25Z, md5_plan = md5_plan_derived): o MESMO conjunto de 285
-- ids, não só a mesma contagem. Divergência = STOP e adjudicação.
DO $$
DECLARE v_ready INT; v_cond INT; v_staff INT; v_slr INT; v_plan INT;
        v_hold INT; v_md5 TEXT; v_dup INT;
BEGIN
    SELECT COUNT(*) INTO v_dup FROM (SELECT code FROM public.card_variant_type GROUP BY code HAVING COUNT(*) > 1) z;
    IF v_dup <> 0 THEN
        RAISE EXCEPTION 'TYPE_CODE_NOT_UNIQUE: % codes de Variant Type duplicados; C3 exige code unico.', v_dup;
    END IF;

    SELECT COUNT(*) INTO v_ready FROM ready_structural;
    IF v_ready <> 365 THEN
        RAISE EXCEPTION 'READY_STRUCTURAL_MISMATCH: esperado 365, obtido %.', v_ready;
    END IF;

    SELECT COUNT(*),
           COUNT(*) FILTER (WHERE legacy_type = 'STAFF_HOLO'),
           COUNT(*) FILTER (WHERE legacy_type = 'SET_LOGO_REVERSE')
      INTO v_cond, v_staff, v_slr
      FROM ready_structural WHERE id IN (SELECT id FROM pricing_conditioned);
    IF v_cond <> 80 OR v_staff <> 40 OR v_slr <> 40 THEN
        RAISE EXCEPTION 'PRICING_CONDITIONED_MISMATCH: esperado 80 = STAFF_HOLO 40 + SET_LOGO_REVERSE 40, obtido % (% + %).', v_cond, v_staff, v_slr;
    END IF;

    SELECT COUNT(*) INTO v_hold FROM ready_structural WHERE id IN (SELECT id FROM hold_frozen);
    IF v_hold <> 0 THEN
        RAISE EXCEPTION 'READY_X_HOLD: % Variants READY tambem no HOLD.', v_hold;
    END IF;

    SELECT COUNT(*), md5(COALESCE(string_agg(card_variant_id::TEXT, ',' ORDER BY card_variant_id), ''))
      INTO v_plan, v_md5 FROM plan_ids;
    IF v_plan <> 285 THEN
        RAISE EXCEPTION 'PLAN_COVERAGE_MISMATCH: READY_UNCONDITIONED esperado 285, obtido %.', v_plan;
    END IF;
    IF v_md5 <> 'a53343fa38bbbe6f45fea7a4dba4bbdb' THEN
        RAISE EXCEPTION 'PLAN_IDENTITY_DRIFT: md5 do plano % <> ancora D1 a53343fa38bbbe6f45fea7a4dba4bbdb.', v_md5;
    END IF;
END $$;

-- ---------------------------------------------------------------- PASSO 1 ---
-- Evidência via lineage. Determinística (H5 da v2.0, mantido): linha mais
-- antiga por Variant. Cobertura provada ANTES de chamar o resolvedor: uma
-- Variant sem lineage aborta aqui, nunca é descartada em silêncio nem chega
-- ao resolvedor com raw_data NULL.
CREATE TEMP TABLE plan_evidence ON COMMIT DROP AS
WITH ev AS (
    SELECT DISTINCT ON (r.resulting_variant_id)
           r.resulting_variant_id AS card_variant_id,
           r.id       AS evidence_row_id,
           r.raw_data AS evidence_raw
      FROM public.catalog_variant_import_row r
     WHERE r.resulting_variant_id IN (SELECT card_variant_id FROM plan_ids)
     ORDER BY r.resulting_variant_id, r.created_at ASC, r.id ASC
)
SELECT p.card_variant_id, ev.evidence_row_id, ev.evidence_raw
  FROM plan_ids p
  LEFT JOIN ev ON ev.card_variant_id = p.card_variant_id;

DO $$
DECLARE v_n INT;
BEGIN
    SELECT COUNT(*) INTO v_n FROM plan_evidence WHERE evidence_row_id IS NULL;
    IF v_n <> 0 THEN
        RAISE EXCEPTION 'LINEAGE_COVERAGE: % Variants do plano sem row de lineage (resulting_variant_id).', v_n;
    END IF;
END $$;

CREATE TEMP TABLE plan_ready ON COMMIT DROP AS
SELECT p.card_variant_id,
       cv.card_id,
       c.card_set_id,
       cv.variant_type_id      AS legacy_variant_type_id,
       vt.code                 AS legacy_type,
       cv.printing_profile_id  AS cv_printing_profile_id,
       cv.edition_context_profile_id AS cv_edition_context_profile_id,
       cv.variant_order        AS pre_variant_order,
       cv.is_default           AS pre_is_default,
       e.game_id               AS card_game_id,
       p.evidence_row_id,
       ax.edition_context_state,
       ax.edition_context_profile_id,
       ax.printing_profile_id  AS axis_printing_profile_id,
       internal.lookup_variant_type_for_row(
           pr.game_id, pr.asset_source_id, c.card_set_id,
           ax.residual_type, ax.residual_foil, ax.residual_subtype, ax.residual_stamp
       ) AS finish_target_id
  FROM plan_evidence p
  JOIN public.card_variant cv      ON cv.id = p.card_variant_id
  JOIN public.card_variant_type vt ON vt.id = cv.variant_type_id
  JOIN public.card c               ON c.id  = cv.card_id
  JOIN public.card_set cs          ON cs.id = c.card_set_id
  JOIN public.expansion e          ON e.id  = cs.expansion_id
  CROSS JOIN sim_params pr
  -- ESCOPO CANONICO (SOURCE-SCOPE-CORRECTION-01): 4o argumento = external_set_id
  -- da Fonte, nunca card_set.code. Autoridade única: resolve_variant_mapping_scope().
  LEFT JOIN LATERAL internal.resolve_variant_mapping_scope(c.card_set_id, pr.asset_source_id) sc ON TRUE
  CROSS JOIN LATERAL internal.resolve_variant_row_axes(
       p.evidence_raw, pr.game_id, pr.asset_source_id, sc.external_set_id) ax;

-- --------------------------------------------------------------- PASSO 1B ---
-- Lineage-alvo = rows com resulting_variant_id ∈ plano (escopo estrito da
-- Correção 6). Lock em ordem de id, depois do lock das Variants.
DO $$
BEGIN
    PERFORM 1 FROM public.catalog_variant_import_row r
      WHERE r.resulting_variant_id IN (SELECT card_variant_id FROM plan_ids)
      ORDER BY r.id
        FOR UPDATE;
END $$;

CREATE TEMP TABLE lineage_target ON COMMIT DROP AS
SELECT r.id                         AS row_id,
       r.job_id,
       r.card_id,
       r.resulting_variant_id,
       r.matched_variant_id,
       md5(r.raw_data::TEXT)        AS pre_raw_md5,
       r.validation_status          AS pre_validation_status,
       r.match_status               AS pre_match_status,
       r.decision_status            AS pre_decision_status,
       r.persistence_status         AS pre_persistence_status,
       r.error_detail               AS pre_error_detail,
       r.normalized_data            AS pre_normalized_data,
       (r.normalized_data - 'variant_type_id' - 'edition_context_profile_id') AS pre_nd_rest,
       r.raw_data                   AS raw_data
  FROM public.catalog_variant_import_row r
 WHERE r.resulting_variant_id IN (SELECT card_variant_id FROM plan_ids);

-- Resolução por ROW: cada row-alvo resolvida com o próprio raw_data. Só para o
-- gate de coerência — o destino gravado é sempre o da Variant (Correção 6).
CREATE TEMP TABLE lineage_axes ON COMMIT DROP AS
SELECT t.row_id,
       ax.edition_context_state,
       ax.edition_context_profile_id,
       internal.lookup_variant_type_for_row(
           pr.game_id, pr.asset_source_id, c.card_set_id,
           ax.residual_type, ax.residual_foil, ax.residual_subtype, ax.residual_stamp
       ) AS finish_target_id
  FROM lineage_target t
  JOIN public.card c ON c.id = t.card_id
  CROSS JOIN sim_params pr
  LEFT JOIN LATERAL internal.resolve_variant_mapping_scope(c.card_set_id, pr.asset_source_id) sc ON TRUE
  CROSS JOIN LATERAL internal.resolve_variant_row_axes(
       t.raw_data, pr.game_id, pr.asset_source_id, sc.external_set_id) ax;

-- Fingerprints PRE de tudo que NÃO pode mudar (L3). Hash por linha, agregado
-- por id: custo O(N) com ~32 bytes por linha.
CREATE TEMP TABLE fp_pre ON COMMIT DROP AS
SELECT (SELECT COUNT(*) FROM public.catalog_variant_import_row r
         WHERE r.id NOT IN (SELECT row_id FROM lineage_target))                      AS cvir_out_n,
       (SELECT md5(COALESCE(string_agg(md5(r::TEXT), '' ORDER BY r.id), ''))
          FROM public.catalog_variant_import_row r
         WHERE r.id NOT IN (SELECT row_id FROM lineage_target))                      AS cvir_out_md5,
       (SELECT COUNT(*) FROM public.card_variant cv
         WHERE cv.id NOT IN (SELECT card_variant_id FROM plan_ids))                  AS cv_out_n,
       (SELECT md5(COALESCE(string_agg(md5(cv::TEXT), '' ORDER BY cv.id), ''))
          FROM public.card_variant cv
         WHERE cv.id NOT IN (SELECT card_variant_id FROM plan_ids))                  AS cv_out_md5,
       (SELECT COUNT(*) FROM public.catalog_variant_import_row
         WHERE resulting_variant_id IS NOT NULL)                                     AS resulting_n,
       (SELECT COUNT(*) FROM public.catalog_variant_import_row
         WHERE matched_variant_id IS NOT NULL)                                       AS matched_n,
       (SELECT COUNT(*) FROM public.card_variant)                                    AS cv_total;

-- ---------------------------------------------------------------- PASSO 2 ---
DO $$
DECLARE v_n INT; v_m INT;
BEGIN
    SELECT COUNT(*) INTO v_n FROM plan_ready;
    IF v_n <> 285 THEN
        RAISE EXCEPTION 'PLAN_READY_CARDINALITY: esperado 285, obtido %.', v_n;
    END IF;

    SELECT COUNT(*) INTO v_n FROM plan_ready p JOIN hold_frozen h ON h.id = p.card_variant_id;
    IF v_n <> 0 THEN
        RAISE EXCEPTION 'HOLD_LEAKED_INTO_PLAN: % linhas HOLD no plano.', v_n;
    END IF;

    SELECT COUNT(*) INTO v_n FROM plan_ready p JOIN pricing_conditioned x ON x.id = p.card_variant_id;
    IF v_n <> 0 THEN
        RAISE EXCEPTION 'PRICING_CONDITIONED_IN_PLAN: % linhas com dependencia de Pricing. Bloqueado ate PRICING-CATALOG-VARIANT-RECONCILIATION-01 fechar.', v_n;
    END IF;

    -- Game: o plano inteiro pertence ao Game resolvido por code.
    SELECT COUNT(*) INTO v_n FROM plan_ready p CROSS JOIN sim_params pr
     WHERE p.card_game_id IS DISTINCT FROM pr.game_id;
    IF v_n <> 0 THEN
        RAISE EXCEPTION 'PLAN_GAME_MISMATCH: % Variants do plano fora do Game POKEMON.', v_n;
    END IF;

    -- Lineage 100% (MIGRATION-MAP-365): toda Variant do plano tem evidência.
    SELECT COUNT(*) INTO v_n FROM plan_ready WHERE evidence_row_id IS NULL;
    IF v_n <> 0 THEN
        RAISE EXCEPTION 'LINEAGE_COVERAGE: % Variants do plano sem row de lineage (resulting_variant_id).', v_n;
    END IF;

    -- Pré-condição / idempotência: nada do plano já foi decomposto.
    SELECT COUNT(*) INTO v_n FROM plan_ready WHERE cv_edition_context_profile_id IS NOT NULL;
    IF v_n <> 0 THEN
        RAISE EXCEPTION 'PLAN_ALREADY_DECOMPOSED: % Variants do plano ja tem edition_context_profile_id.', v_n;
    END IF;

    -- Destino determinístico nos DOIS eixos. Nenhum NULL silencioso.
    SELECT COUNT(*) INTO v_n FROM plan_ready
     WHERE edition_context_state IS DISTINCT FROM 'RESOLVED_WITH_EC_PROFILE'
        OR edition_context_profile_id IS NULL;
    IF v_n <> 0 THEN
        RAISE EXCEPTION 'PLAN_NON_DETERMINISTIC_CONTEXT: % linhas sem Edition Context resolvido.', v_n;
    END IF;

    SELECT COUNT(*) INTO v_n FROM plan_ready WHERE finish_target_id IS NULL;
    IF v_n <> 0 THEN
        RAISE EXCEPTION 'PLAN_NON_DETERMINISTIC_FINISH: % linhas sem Variant Type de destino.', v_n;
    END IF;

    -- O destino é acabamento PURO (lista FINISH do C3), nunca outro tipo legado.
    SELECT COUNT(*) INTO v_n FROM plan_ready p
      JOIN public.card_variant_type t ON t.id = p.finish_target_id
     WHERE t.code NOT IN (SELECT code FROM finish_codes);
    IF v_n <> 0 THEN
        RAISE EXCEPTION 'PLAN_FINISH_NOT_PURE: % destinos fora da lista FINISH.', v_n;
    END IF;

    -- H9: o printing gravado é o da Variant; o resolvedor tem de concordar.
    SELECT COUNT(*) INTO v_n FROM plan_ready
     WHERE axis_printing_profile_id IS DISTINCT FROM cv_printing_profile_id;
    IF v_n <> 0 THEN
        RAISE EXCEPTION 'PLAN_PRINTING_DRIFT: % Variants cujo printing resolvido difere do printing atual.', v_n;
    END IF;

    -- -------- lineage --------
    -- Resolução por row total: exatamente uma linha de eixos por row-alvo.
    SELECT COUNT(*) INTO v_n FROM lineage_target;
    SELECT COUNT(DISTINCT row_id) INTO v_m FROM lineage_axes;
    IF v_m <> v_n OR (SELECT COUNT(*) FROM lineage_axes) <> v_n THEN
        RAISE EXCEPTION 'LINEAGE_AXES_CARDINALITY: % rows-alvo, % com eixos resolvidos (% linhas).', v_n, v_m, (SELECT COUNT(*) FROM lineage_axes);
    END IF;

    -- A row descreve a mesma Card da Variant que ela produziu.
    SELECT COUNT(*) INTO v_n FROM lineage_target t
      JOIN plan_ready p ON p.card_variant_id = t.resulting_variant_id
     WHERE t.card_id IS DISTINCT FROM p.card_id;
    IF v_n <> 0 THEN
        RAISE EXCEPTION 'LINEAGE_CARD_MISMATCH: % rows-alvo com card_id diferente da Variant.', v_n;
    END IF;

    -- Todas as rows de uma Variant têm de concordar com o destino da Variant;
    -- senão a escolha da evidência seria arbitrária. (LIVE 2026-10-04: 336
    -- rows-alvo, 51 Variants com >1 row, 0 Variants com destinos distintos
    -- entre as próprias rows. Hoje o gate só não zera por B-SEMANTIC — rows
    -- sem destino resolvido —, não por evidência contraditória; ele já é
    -- precedido por PLAN_NON_DETERMINISTIC_CONTEXT e converge a zero quando
    -- B-SEMANTIC fechar.)
    SELECT COUNT(*) INTO v_n
      FROM lineage_target t
      JOIN lineage_axes a ON a.row_id = t.row_id
      JOIN plan_ready p   ON p.card_variant_id = t.resulting_variant_id
     WHERE a.edition_context_state IS DISTINCT FROM 'RESOLVED_WITH_EC_PROFILE'
        OR a.edition_context_profile_id IS DISTINCT FROM p.edition_context_profile_id
        OR a.finish_target_id IS DISTINCT FROM p.finish_target_id;
    IF v_n <> 0 THEN
        RAISE EXCEPTION 'LINEAGE_EVIDENCE_DIVERGENT: % rows de lineage resolvem para destino diferente da Variant.', v_n;
    END IF;

    -- A Fonte do lineage é a mesma resolvida por code (job.source = asset_source.code,
    -- padrão da 2841) — nenhum join inventado.
    SELECT COUNT(*) INTO v_n FROM lineage_target t
      JOIN public.catalog_variant_import_job j ON j.id = t.job_id
     WHERE j.source IS DISTINCT FROM 'TCGDEX';
    IF v_n <> 0 THEN
        RAISE EXCEPTION 'LINEAGE_SOURCE_MISMATCH: % rows-alvo de job com source <> TCGDEX.', v_n;
    END IF;

    -- "Operacional" é ROW-LEVEL (contrato 2214/2216): job em
    -- RECEIVED/PROCESSING/STAGED/CONFIRMING **e** persistence_status = PENDING.
    -- Uma row INSERTED de job STAGED já é terminal (LIVE 2026-10-04: o predicado
    -- só por job.status dava 50 falsos positivos, todos STAGED/INSERTED/VALID/
    -- APPROVED). validation/decision NÃO filtram: um PENDING inesperado bloqueia.
    SELECT COUNT(*) INTO v_n FROM lineage_target t
      JOIN public.catalog_variant_import_job j ON j.id = t.job_id
     WHERE j.status IN ('RECEIVED','PROCESSING','STAGED','CONFIRMING')
       AND t.pre_persistence_status = 'PENDING';
    IF v_n <> 0 THEN
        RAISE EXCEPTION 'LINEAGE_TARGET_PENDING_OPERATIONAL: % rows-alvo PENDING em job operacional.', v_n;
    END IF;

    -- Nenhuma row PENDING operacional referencia o plano (matched ou resulting):
    -- um confirm posterior escreveria contra a identidade antiga.
    SELECT COUNT(*) INTO v_n FROM public.catalog_variant_import_row r
      JOIN public.catalog_variant_import_job j ON j.id = r.job_id
     WHERE j.status IN ('RECEIVED','PROCESSING','STAGED','CONFIRMING')
       AND r.persistence_status = 'PENDING'
       AND (r.matched_variant_id IN (SELECT card_variant_id FROM plan_ids)
            OR r.resulting_variant_id IN (SELECT card_variant_id FROM plan_ids));
    IF v_n <> 0 THEN
        RAISE EXCEPTION 'PENDING_OPERATIONAL_REFERENCE_TO_PLAN: % rows PENDING de job operacional apontam para o plano.', v_n;
    END IF;

    -- Guard 2214 G1: row VALID precisa manter a chave printing_profile_id.
    SELECT COUNT(*) INTO v_n FROM lineage_target
     WHERE pre_validation_status = 'VALID'
       AND NOT jsonb_exists(pre_normalized_data, 'printing_profile_id');
    IF v_n <> 0 THEN
        RAISE EXCEPTION 'LINEAGE_VALID_WITHOUT_PRINTING_KEY: % rows-alvo VALID sem a chave printing_profile_id; o guard 2214 rejeitaria o UPDATE.', v_n;
    END IF;

    -- Nenhuma row-alvo já carrega Edition Context (idempotência e prova de
    -- ausência de colisão transitória em uq_cvir_row_identity).
    SELECT COUNT(*) INTO v_n FROM lineage_target
     WHERE jsonb_typeof(pre_normalized_data -> 'edition_context_profile_id') = 'string';
    IF v_n <> 0 THEN
        RAISE EXCEPTION 'LINEAGE_ALREADY_RECONCILED: % rows-alvo ja tem edition_context_profile_id preenchido.', v_n;
    END IF;

    -- L2 PRE: o estado de partida já não pode ter híbrido.
    SELECT COUNT(*) INTO v_n
      FROM public.catalog_variant_import_row r
      JOIN public.card_variant cv ON cv.id = r.resulting_variant_id
     WHERE COALESCE(jsonb_typeof(r.normalized_data -> 'edition_context_profile_id') = 'string', false)
           <> (cv.edition_context_profile_id IS NOT NULL);
    IF v_n <> 0 THEN
        RAISE EXCEPTION 'L2_PRE_HYBRID: % rows ja estao em estado hibrido antes da simulacao.', v_n;
    END IF;

    -- Informativo (fora do escopo da Correção 6, que é resulting_variant_id):
    -- rows que apenas CASARAM com uma Variant do plano não são reconciliadas.
    SELECT COUNT(*) INTO v_m FROM public.catalog_variant_import_row r
     WHERE r.matched_variant_id IN (SELECT card_variant_id FROM plan_ids)
       AND r.id NOT IN (SELECT row_id FROM lineage_target);
    SELECT COUNT(*) INTO v_n FROM lineage_target;
    RAISE NOTICE 'LINEAGE_SCOPE: rows-alvo (resulting ∈ plano) = %; rows so com matched ∈ plano (nao tocadas) = %.', v_n, v_m;
END $$;

-- ---------------------------------------------------------------- PASSO 3 ---
-- Identidade de staging NOVA de cada row-alvo. Tokens calculados pela PRÓPRIA
-- função do índice uq_cvir_row_identity (2210), não reimplementados.
CREATE TEMP TABLE lineage_new_identity ON COMMIT DROP AS
SELECT t.row_id, t.job_id, t.card_id,
       p.finish_target_id::TEXT AS vt,
       internal.axis_identity_token(t.pre_normalized_data, 'printing_profile_id') AS pp_tok,
       internal.axis_identity_token(
           jsonb_build_object('edition_context_profile_id', p.edition_context_profile_id::TEXT),
           'edition_context_profile_id') AS ec_tok
  FROM lineage_target t
  JOIN plan_ready p ON p.card_variant_id = t.resulting_variant_id;

DO $$
DECLARE v_col INT;
BEGIN
    -- card_variant: colisão contra a identidade NOVA de quatro componentes,
    -- com o printing EFETIVAMENTE gravado (o da Variant — H9).
    SELECT COUNT(*) INTO v_col
      FROM plan_ready p
     WHERE EXISTS (
         SELECT 1 FROM public.card_variant x
          WHERE x.card_id = p.card_id
            AND x.id NOT IN (SELECT card_variant_id FROM plan_ids)
            AND x.variant_type_id            IS NOT DISTINCT FROM p.finish_target_id
            AND x.printing_profile_id        IS NOT DISTINCT FROM p.cv_printing_profile_id
            AND x.edition_context_profile_id IS NOT DISTINCT FROM p.edition_context_profile_id
     );
    IF v_col <> 0 THEN
        RAISE EXCEPTION 'NEW_IDENTITY_COLLISION: % colisoes contra a identidade de 4 componentes.', v_col;
    END IF;

    SELECT COUNT(*) INTO v_col FROM (
        SELECT card_id, finish_target_id, cv_printing_profile_id, edition_context_profile_id
          FROM plan_ready
         GROUP BY 1,2,3,4 HAVING COUNT(*) > 1
    ) d;
    IF v_col <> 0 THEN
        RAISE EXCEPTION 'INTRA_PLAN_COLLISION: % identidades duplicadas dentro do plano.', v_col;
    END IF;

    -- staging (uq_cvir_row_identity): a identidade nova de cada row-alvo
    -- (lineage_new_identity, acima) não pode repetir outra row-alvo do mesmo job
    -- nem uma row não-alvo do mesmo job.
    SELECT COUNT(*) INTO v_col FROM (
        SELECT job_id, card_id, vt, pp_tok, ec_tok FROM lineage_new_identity
         GROUP BY 1,2,3,4,5 HAVING COUNT(*) > 1
    ) d;
    IF v_col <> 0 THEN
        RAISE EXCEPTION 'LINEAGE_INTRA_TARGET_COLLISION: % identidades de staging duplicadas entre rows-alvo.', v_col;
    END IF;

    SELECT COUNT(*) INTO v_col
      FROM lineage_new_identity n
     WHERE EXISTS (
         SELECT 1 FROM public.catalog_variant_import_row r
          WHERE r.job_id = n.job_id
            AND r.card_id = n.card_id
            AND r.id NOT IN (SELECT row_id FROM lineage_target)
            AND (r.normalized_data ->> 'variant_type_id') = n.vt
            AND internal.axis_identity_token(r.normalized_data, 'printing_profile_id') = n.pp_tok
            AND internal.axis_identity_token(r.normalized_data, 'edition_context_profile_id') = n.ec_tok
     );
    IF v_col <> 0 THEN
        RAISE EXCEPTION 'LINEAGE_STAGING_COLLISION: % rows-alvo colidiriam com row nao-alvo do mesmo job.', v_col;
    END IF;
END $$;

-- --------------------------------------------------------------- PASSO 4A ---
-- variant_order, is_default e printing_profile_id deliberadamente AUSENTES do SET.
DO $$
DECLARE v_n INT;
BEGIN
    UPDATE public.card_variant cv
       SET variant_type_id            = p.finish_target_id,
           edition_context_profile_id = p.edition_context_profile_id,
           updated_at                 = now()
      FROM plan_ready p
     WHERE cv.id = p.card_variant_id
       AND cv.id NOT IN (SELECT id FROM hold_frozen)
       AND cv.id NOT IN (SELECT id FROM pricing_conditioned)
       AND cv.edition_context_profile_id IS NULL;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    IF v_n <> 285 THEN
        RAISE EXCEPTION 'CV_UPDATE_COUNT: esperado 285 Variants atualizadas, obtido %.', v_n;
    END IF;
END $$;

-- --------------------------------------------------------------- PASSO 4B ---
-- Só as duas chaves autorizadas; demais chaves preservadas por jsonb_set.
-- resulting_variant_id, raw_data e os quatro status fora do SET.
DO $$
DECLARE v_n INT; v_expected INT;
BEGIN
    SELECT COUNT(*) INTO v_expected FROM lineage_target;
    UPDATE public.catalog_variant_import_row r
       SET normalized_data =
               jsonb_set(
                 jsonb_set(r.normalized_data,
                           '{variant_type_id}',
                           to_jsonb(p.finish_target_id::TEXT), true),
                 '{edition_context_profile_id}',
                 to_jsonb(p.edition_context_profile_id::TEXT), true)
      FROM lineage_target t
      JOIN plan_ready p ON p.card_variant_id = t.resulting_variant_id
     WHERE r.id = t.row_id
       AND r.resulting_variant_id = t.resulting_variant_id;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    IF v_n <> v_expected THEN
        RAISE EXCEPTION 'LINEAGE_UPDATE_COUNT: esperado % rows reconciliadas, obtido %.', v_expected, v_n;
    END IF;
END $$;

-- ---------------------------------------------------------------- PASSO 5 ---
DO $$
DECLARE v_n INT; f fp_pre%ROWTYPE; v_md5 TEXT; v_cnt BIGINT;
BEGIN
    SELECT * INTO f FROM fp_pre;

    -- L8 — card_variant.id preservado em 285/285.
    SELECT COUNT(*) INTO v_n FROM plan_ready p
     WHERE NOT EXISTS (SELECT 1 FROM public.card_variant cv WHERE cv.id = p.card_variant_id);
    IF v_n <> 0 THEN
        RAISE EXCEPTION 'L8_ID_NAO_PRESERVADO: % card_variant.id desapareceram.', v_n;
    END IF;
    SELECT COUNT(*) INTO v_cnt FROM public.card_variant;
    IF v_cnt <> f.cv_total THEN
        RAISE EXCEPTION 'L8_CV_TOTAL: card_variant % -> %.', f.cv_total, v_cnt;
    END IF;

    -- Variant decomposta = destino do plano; printing, order e default intactos (L9).
    SELECT COUNT(*) INTO v_n FROM plan_ready p JOIN public.card_variant cv ON cv.id = p.card_variant_id
     WHERE cv.variant_type_id            IS DISTINCT FROM p.finish_target_id
        OR cv.edition_context_profile_id IS DISTINCT FROM p.edition_context_profile_id
        OR cv.printing_profile_id        IS DISTINCT FROM p.cv_printing_profile_id
        OR cv.variant_order              IS DISTINCT FROM p.pre_variant_order
        OR cv.is_default                 IS DISTINCT FROM p.pre_is_default;
    IF v_n <> 0 THEN
        RAISE EXCEPTION 'L9_POSTCHECK_VARIANT: % Variants do plano fora do estado esperado.', v_n;
    END IF;

    -- L1 — toda row-alvo descreve a Variant decomposta.
    SELECT COUNT(*) INTO v_n
      FROM lineage_target t
      JOIN public.catalog_variant_import_row r ON r.id = t.row_id
      JOIN public.card_variant cv ON cv.id = t.resulting_variant_id
     WHERE (r.normalized_data ->> 'variant_type_id') IS DISTINCT FROM cv.variant_type_id::TEXT
        OR jsonb_typeof(r.normalized_data -> 'edition_context_profile_id') IS DISTINCT FROM 'string'
        OR (r.normalized_data ->> 'edition_context_profile_id') IS DISTINCT FROM cv.edition_context_profile_id::TEXT;
    IF v_n <> 0 THEN
        RAISE EXCEPTION 'L1_LINEAGE_NOT_RECONCILED: % rows-alvo nao descrevem a Variant decomposta.', v_n;
    END IF;

    -- L2 — zero híbrido, GLOBAL, nos dois sentidos, e valor igual quando ambos preenchidos.
    SELECT COUNT(*) INTO v_n
      FROM public.catalog_variant_import_row r
      JOIN public.card_variant cv ON cv.id = r.resulting_variant_id
     WHERE COALESCE(jsonb_typeof(r.normalized_data -> 'edition_context_profile_id') = 'string', false)
           <> (cv.edition_context_profile_id IS NOT NULL)
        OR (jsonb_typeof(r.normalized_data -> 'edition_context_profile_id') = 'string'
            AND (r.normalized_data ->> 'edition_context_profile_id') <> cv.edition_context_profile_id::TEXT);
    IF v_n <> 0 THEN
        RAISE EXCEPTION 'L2_HYBRID: % rows em estado hibrido apos a simulacao.', v_n;
    END IF;

    -- L3 — nada fora do escopo mudou: rows não-alvo e Variants fora do plano
    -- byte a byte (inclui HOLD, PRICING_CONDITIONED e updated_at).
    SELECT md5(COALESCE(string_agg(md5(r::TEXT), '' ORDER BY r.id), '')), COUNT(*)
      INTO v_md5, v_cnt
      FROM public.catalog_variant_import_row r
     WHERE r.id NOT IN (SELECT row_id FROM lineage_target);
    IF v_md5 <> f.cvir_out_md5 OR v_cnt <> f.cvir_out_n THEN
        RAISE EXCEPTION 'L3_ROW_OUT_OF_SCOPE_CHANGED: rows nao-alvo mudaram (% -> % rows).', f.cvir_out_n, v_cnt;
    END IF;
    SELECT md5(COALESCE(string_agg(md5(cv::TEXT), '' ORDER BY cv.id), '')), COUNT(*)
      INTO v_md5, v_cnt
      FROM public.card_variant cv
     WHERE cv.id NOT IN (SELECT card_variant_id FROM plan_ids);
    IF v_md5 <> f.cv_out_md5 OR v_cnt <> f.cv_out_n THEN
        RAISE EXCEPTION 'L3_VARIANT_OUT_OF_SCOPE_CHANGED: Variants fora do plano mudaram (% -> %).', f.cv_out_n, v_cnt;
    END IF;

    -- L3 nas rows-alvo: só as duas chaves mudaram (updated_at muda pelo trigger).
    SELECT COUNT(*) INTO v_n
      FROM lineage_target t
      JOIN public.catalog_variant_import_row r ON r.id = t.row_id
     WHERE (r.normalized_data - 'variant_type_id' - 'edition_context_profile_id') IS DISTINCT FROM t.pre_nd_rest
        OR md5(r.raw_data::TEXT)  IS DISTINCT FROM t.pre_raw_md5
        OR r.validation_status    IS DISTINCT FROM t.pre_validation_status
        OR r.match_status         IS DISTINCT FROM t.pre_match_status
        OR r.decision_status      IS DISTINCT FROM t.pre_decision_status
        OR r.persistence_status   IS DISTINCT FROM t.pre_persistence_status
        -- trg_catalog_variant_import_row_normalize reescreve error_detail e os
        -- status em todo UPDATE: a prova é estrutural, não depende do dado atual.
        OR r.error_detail         IS DISTINCT FROM t.pre_error_detail
        OR r.job_id               IS DISTINCT FROM t.job_id
        OR r.card_id              IS DISTINCT FROM t.card_id
        OR r.matched_variant_id   IS DISTINCT FROM t.matched_variant_id;
    IF v_n <> 0 THEN
        RAISE EXCEPTION 'L3_TARGET_EXTRA_CHANGE: % rows-alvo com mudanca alem das duas chaves autorizadas.', v_n;
    END IF;

    -- L4 — resulting_variant_id preservado em 100%.
    SELECT COUNT(*) INTO v_n
      FROM lineage_target t
      JOIN public.catalog_variant_import_row r ON r.id = t.row_id
     WHERE r.resulting_variant_id IS DISTINCT FROM t.resulting_variant_id;
    IF v_n <> 0 THEN
        RAISE EXCEPTION 'L4_RESULTING_NOT_PRESERVED: % rows-alvo perderam resulting_variant_id.', v_n;
    END IF;
    SELECT COUNT(*) INTO v_n FROM lineage_target t
     WHERE NOT EXISTS (SELECT 1 FROM public.catalog_variant_import_row r WHERE r.id = t.row_id);
    IF v_n <> 0 THEN
        RAISE EXCEPTION 'L4_ROW_LOST: % rows-alvo desapareceram.', v_n;
    END IF;
    SELECT COUNT(*) INTO v_cnt FROM public.catalog_variant_import_row WHERE resulting_variant_id IS NOT NULL;
    IF v_cnt <> f.resulting_n THEN
        RAISE EXCEPTION 'L4_RESULTING_TOTAL: % -> %.', f.resulting_n, v_cnt;
    END IF;
    SELECT COUNT(*) INTO v_cnt FROM public.catalog_variant_import_row WHERE matched_variant_id IS NOT NULL;
    IF v_cnt <> f.matched_n THEN
        RAISE EXCEPTION 'L4_MATCHED_TOTAL: % -> %.', f.matched_n, v_cnt;
    END IF;

    -- HOLD e PRICING_CONDITIONED sem contexto (redundante com L3; mantido da v2.0).
    SELECT COUNT(*) INTO v_n FROM public.card_variant cv JOIN hold_frozen h ON h.id = cv.id
     WHERE cv.edition_context_profile_id IS NOT NULL;
    IF v_n <> 0 THEN
        RAISE EXCEPTION 'HOLD_VIOLADO: % linhas HOLD receberam contexto.', v_n;
    END IF;
    SELECT COUNT(*) INTO v_n FROM public.card_variant cv JOIN pricing_conditioned x ON x.id = cv.id
     WHERE cv.edition_context_profile_id IS NOT NULL;
    IF v_n <> 0 THEN
        RAISE EXCEPTION 'PRICING_CONDITIONED_VIOLADO: % linhas condicionadas receberam contexto.', v_n;
    END IF;

    SELECT COUNT(*) INTO v_n FROM lineage_target;
    RAISE NOTICE '2831_SIMULATION_PASS: 285 Variants + % rows de lineage reconciliadas; L1 L2 L3 L4 L8 L9 PASS. ROLLBACK a seguir.', v_n;
END $$;

-- READY_PRICING_CONDITIONED (80) fica FORA por guard executavel do PASSO 0B:
--   STAFF_HOLO       40  (17 pricing_source_card_identity + 1 pricing_source_variant_mapping)
--   SET_LOGO_REVERSE 40  ( 1 pricing_source_card_identity + 0 pricing_source_variant_mapping)
-- Os dois conceitos NUNCA sao somados. Liberacao so em
-- PRICING-CATALOG-VARIANT-RECONCILIATION-01. O lineage delas tambem nao e tocado.

ROLLBACK;  -- SIMULACAO. A migration real sera 2213 e so ela sera definitiva.
