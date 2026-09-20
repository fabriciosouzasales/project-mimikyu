-- ============================================================================
-- Query 2831 — SIMULAÇÃO da decomposição do legado (READY_UNCONDITIONED)
-- ESTE ARQUIVO NAO E MIGRATION. Termina em ROLLBACK por contrato.
-- A migration real sera numerada 2213 e escrita SOMENTE apos Gate A.
-- Status: PROPOSTA — NÃO EXECUTADA · Versão 2.0
--
-- v2.0 (EDITION-CONTEXT-AXIS-GATE-A-01) — a v1.0 tinha CINCO defeitos reais:
--   H1  PASSO 4 referenciava p.finish_target_id e p.edition_context_profile_id,
--       colunas que NAO EXISTIAM em plan_365. O script abortaria no UPDATE.
--   H2  Dois `-- placeholder:` embutidos. O gate de colisao (PASSO 3) usava
--       o code 'STANDARD' fixo como destino de acabamento — ou seja, NAO
--       testava a colisao real. A cifra de "188 colisoes previstas" NAO era
--       produzida por este artefato.
--   H3  Os gates exigiam 365, mas a decisao de HOLD-MANIFEST H6 e que o plano
--       real sao 285 (365 menos 80 PRICING_CONDITIONED). O proprio rodape do
--       arquivo dizia que STAFF_HOLO fica fora — contradicao interna.
--   H4  O guard executavel de PRICING_CONDITIONED que HOLD-MANIFEST H6 afirma
--       existir "no 2831" NAO ESTAVA no arquivo.
--   H5  `DISTINCT ON (cv.id)` sem ORDER BY correspondente: escolha de linha de
--       evidencia NAO-DETERMINISTICA.
--
--   Corrigidos aqui. O destino de acabamento agora e derivado de verdade, pelo
--   mesmo caminho canonico da importacao:
--       internal.resolve_variant_row_axes()   (2211, eixos 1-2-3)
--     → internal.lookup_variant_type_for_row() (2192, residual -> Variant Type)
--   Nenhum destino vem do `code` do tipo contaminado.
--
-- CONTRATO
--   UPDATE puro. Preserva card_variant.id, variant_order, is_default e lineage.
--   NUNCA DELETE+INSERT. Nenhuma linha HOLD e nenhuma PRICING_CONDITIONED.
--   Collision gate roda ANTES e simula a identidade NOVA (4 componentes).
--
-- PRE-REQUISITO DE EXECUCAO
--   2203-2211 aplicados e os 115 traits / 173 profiles / mappings semeados.
--   Sem isso, resolve_variant_row_axes devolve UNRESOLVED e o PASSO 2 aborta —
--   o que e o comportamento desejado: fail-loud, nunca destino silencioso.
--
-- ESTRUTURA (fail-loud; qualquer divergência aborta a transação inteira)
--   PASSO 0    congelar HOLD (107)
--   PASSO 0B   congelar PRICING_CONDITIONED (80) — derivado do LIVE
--   PASSO 1    montar o plano determinístico a partir do LINEAGE (raw_data)
--   PASSO 2    GATE: cobertura 285/285, zero HOLD, zero Pricing, zero NULL
--   PASSO 3    GATE: colisão contra a identidade NOVA
--   PASSO 4    UPDATE
--   PASSO 5    POSTCHECK
-- ============================================================================

BEGIN;

-- Constantes de execucao. Preenchidas pelo operador a partir do LIVE no
-- momento da execucao — NAO derivadas por join adivinhado.
-- (catalog_variant_import_job nao expoe asset_source_id; inventar o join seria
--  exatamente o tipo de placeholder que a v2.0 esta removendo.)
CREATE TEMP TABLE sim_params ON COMMIT DROP AS
SELECT NULL::UUID AS game_id, NULL::UUID AS asset_source_id;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM sim_params WHERE game_id IS NULL OR asset_source_id IS NULL) THEN
        RAISE EXCEPTION 'SIM_PARAMS_UNSET: preencher sim_params.game_id e asset_source_id antes de executar.';
    END IF;
END $$;

-- ---------------------------------------------------------------- PASSO 0 ---
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
-- GUARD DE PRICING (HOLD-MANIFEST H6). DERIVADO DO LIVE, nao de lista estatica:
-- se um tipo ganhar dependencia de Pricing depois, ele bloqueia sozinho.
-- pricing_source_card_identity e pricing_source_variant_mapping sao contados
-- SEPARADAMENTE e NUNCA somados — sao conceitos distintos.
CREATE TEMP TABLE pricing_conditioned ON COMMIT DROP AS
SELECT cv.id
  FROM public.card_variant cv
 WHERE EXISTS (SELECT 1 FROM public.pricing_source_card_identity x
                WHERE x.card_variant_type_id = cv.variant_type_id)
    OR EXISTS (SELECT 1 FROM public.pricing_source_variant_mapping x
                WHERE x.variant_type_id = cv.variant_type_id);

-- ---------------------------------------------------------------- PASSO 1 ---
-- O plano NASCE do lineage. Nenhum destino é lido do `code` do tipo legado.
CREATE TEMP TABLE plan_ready ON COMMIT DROP AS
WITH src AS (
    SELECT DISTINCT ON (cv.id)
           cv.id            AS card_variant_id,
           cv.card_id,
           cv.variant_type_id AS legacy_variant_type_id,
           c.card_set_id,
           vt.code          AS legacy_type,
           cs.code          AS set_code,
           r.id             AS evidence_row_id,
           r.raw_data       AS evidence_raw
      FROM public.card_variant cv
      JOIN public.card_variant_type vt ON vt.id = cv.variant_type_id
      JOIN public.card c  ON c.id  = cv.card_id
      JOIN public.card_set cs ON cs.id = c.card_set_id
      JOIN public.catalog_variant_import_row r ON r.resulting_variant_id = cv.id
     WHERE cv.id NOT IN (SELECT id FROM hold_frozen)
       AND cv.id NOT IN (SELECT id FROM pricing_conditioned)
     -- DETERMINISMO (H5): o DISTINCT ON exige ORDER BY correspondente.
     -- Sem ele, a linha de evidencia escolhida varia entre execucoes.
     ORDER BY cv.id, r.created_at ASC, r.id ASC
)
SELECT s.card_variant_id,
       s.card_id,
       s.legacy_variant_type_id,
       s.legacy_type,
       s.set_code,
       s.evidence_row_id,
       ax.edition_context_state,
       ax.edition_context_profile_id,
       ax.printing_profile_id,
       -- DESTINO DE ACABAMENTO REAL: residual pos-dois-eixos -> Variant Type.
       internal.lookup_variant_type_for_row(
           pr.game_id, pr.asset_source_id, s.card_set_id,
           ax.residual_type, ax.residual_foil, ax.residual_subtype, ax.residual_stamp
       ) AS finish_target_id
  FROM src s
  CROSS JOIN sim_params pr
  CROSS JOIN LATERAL internal.resolve_variant_row_axes(
       s.evidence_raw, pr.game_id, pr.asset_source_id, s.set_code) ax;

-- ---------------------------------------------------------------- PASSO 2 ---
DO $$
DECLARE v_total INT; v_hold INT; v_pricing INT; v_sem_ctx INT; v_sem_fin INT;
BEGIN
    SELECT COUNT(*) INTO v_total FROM plan_ready;
    IF v_total <> 285 THEN
        RAISE EXCEPTION 'PLAN_COVERAGE_MISMATCH: READY_UNCONDITIONED esperado 285, obtido %.', v_total;
    END IF;

    SELECT COUNT(*) INTO v_hold
      FROM plan_ready p JOIN hold_frozen h ON h.id = p.card_variant_id;
    IF v_hold <> 0 THEN
        RAISE EXCEPTION 'HOLD_LEAKED_INTO_PLAN: % linhas HOLD no plano.', v_hold;
    END IF;

    SELECT COUNT(*) INTO v_pricing
      FROM plan_ready p JOIN pricing_conditioned x ON x.id = p.card_variant_id;
    IF v_pricing <> 0 THEN
        RAISE EXCEPTION 'PRICING_CONDITIONED_IN_PLAN: % linhas com dependencia de Pricing. Bloqueado ate PRICING-CATALOG-VARIANT-RECONCILIATION-01 fechar.', v_pricing;
    END IF;

    -- Destino determinístico nos DOIS eixos. Nenhum NULL silencioso.
    SELECT COUNT(*) INTO v_sem_ctx FROM plan_ready
     WHERE edition_context_state <> 'RESOLVED_WITH_EC_PROFILE'
        OR edition_context_profile_id IS NULL;
    IF v_sem_ctx <> 0 THEN
        RAISE EXCEPTION 'PLAN_NON_DETERMINISTIC_CONTEXT: % linhas sem Edition Context resolvido.', v_sem_ctx;
    END IF;

    SELECT COUNT(*) INTO v_sem_fin FROM plan_ready WHERE finish_target_id IS NULL;
    IF v_sem_fin <> 0 THEN
        RAISE EXCEPTION 'PLAN_NON_DETERMINISTIC_FINISH: % linhas sem Variant Type de destino.', v_sem_fin;
    END IF;
END $$;

-- ---------------------------------------------------------------- PASSO 3 ---
-- Colisão contra a identidade NOVA de quatro componentes, com os destinos
-- REAIS do plano (a v1.0 usava 'STANDARD' fixo e nao testava nada).
DO $$
DECLARE v_col INT;
BEGIN
    SELECT COUNT(*) INTO v_col
      FROM plan_ready p
     WHERE EXISTS (
         SELECT 1 FROM public.card_variant x
          WHERE x.card_id = p.card_id
            AND x.id <> p.card_variant_id
            AND x.id NOT IN (SELECT card_variant_id FROM plan_ready)
            AND x.variant_type_id            IS NOT DISTINCT FROM p.finish_target_id
            AND x.printing_profile_id        IS NOT DISTINCT FROM p.printing_profile_id
            AND x.edition_context_profile_id IS NOT DISTINCT FROM p.edition_context_profile_id
     );
    IF v_col <> 0 THEN
        RAISE EXCEPTION 'NEW_IDENTITY_COLLISION: % colisoes contra a identidade de 4 componentes.', v_col;
    END IF;

    -- Colisão DENTRO do próprio plano: duas linhas convergindo para a mesma
    -- identidade nova. Sob a identidade ANTIGA isso passava; agora nao pode.
    SELECT COUNT(*) INTO v_col FROM (
        SELECT card_id, finish_target_id, printing_profile_id, edition_context_profile_id
          FROM plan_ready
         GROUP BY 1,2,3,4 HAVING COUNT(*) > 1
    ) d;
    IF v_col <> 0 THEN
        RAISE EXCEPTION 'INTRA_PLAN_COLLISION: % identidades duplicadas dentro do plano.', v_col;
    END IF;
END $$;

-- ---------------------------------------------------------------- PASSO 4 ---
-- variant_order e is_default deliberadamente AUSENTES do SET.
UPDATE public.card_variant cv
   SET variant_type_id            = p.finish_target_id,
       edition_context_profile_id = p.edition_context_profile_id,
       updated_at                 = now()
  FROM plan_ready p
 WHERE cv.id = p.card_variant_id
   AND cv.id NOT IN (SELECT id FROM hold_frozen)
   AND cv.id NOT IN (SELECT id FROM pricing_conditioned);

-- ---------------------------------------------------------------- PASSO 5 ---
DO $$
DECLARE v_ctx INT; v_hold_tocado INT; v_pric_tocado INT; v_id_perdido INT;
BEGIN
    -- Escopado ao plano, nao contagem global (a v1.0 contava a tabela inteira).
    SELECT COUNT(*) INTO v_ctx
      FROM public.card_variant cv JOIN plan_ready p ON p.card_variant_id = cv.id
     WHERE cv.edition_context_profile_id IS NOT NULL;
    IF v_ctx <> 285 THEN
        RAISE EXCEPTION 'POSTCHECK_CONTEXT_MISMATCH: esperado 285, obtido %.', v_ctx;
    END IF;

    SELECT COUNT(*) INTO v_id_perdido
      FROM plan_ready p
     WHERE NOT EXISTS (SELECT 1 FROM public.card_variant cv WHERE cv.id = p.card_variant_id);
    IF v_id_perdido <> 0 THEN
        RAISE EXCEPTION 'ID_NAO_PRESERVADO: % card_variant.id desapareceram (UPDATE virou DELETE+INSERT?).', v_id_perdido;
    END IF;

    SELECT COUNT(*) INTO v_hold_tocado
      FROM public.card_variant cv JOIN hold_frozen h ON h.id = cv.id
     WHERE cv.edition_context_profile_id IS NOT NULL;
    IF v_hold_tocado <> 0 THEN
        RAISE EXCEPTION 'HOLD_VIOLADO: % linhas HOLD receberam contexto.', v_hold_tocado;
    END IF;

    SELECT COUNT(*) INTO v_pric_tocado
      FROM public.card_variant cv JOIN pricing_conditioned x ON x.id = cv.id
     WHERE cv.edition_context_profile_id IS NOT NULL;
    IF v_pric_tocado <> 0 THEN
        RAISE EXCEPTION 'PRICING_CONDITIONED_VIOLADO: % linhas condicionadas receberam contexto.', v_pric_tocado;
    END IF;
END $$;

-- READY_PRICING_CONDITIONED (80) fica FORA por guard executavel do PASSO 0B:
--   STAFF_HOLO       40  (17 pricing_source_card_identity + 1 pricing_source_variant_mapping)
--   SET_LOGO_REVERSE 40  ( 1 pricing_source_card_identity + 0 pricing_source_variant_mapping)
-- Os dois conceitos NUNCA sao somados. Liberacao so em
-- PRICING-CATALOG-VARIANT-RECONCILIATION-01.

ROLLBACK;  -- SIMULACAO. A migration real sera 2213 e terminara em COMMIT.
