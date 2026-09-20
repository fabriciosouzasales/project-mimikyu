-- ============================================================================
-- Query 2212 — RESOLUÇÃO DO UNIVERSO OPERACIONAL (ex-backfill global)
-- Status: PROPOSTA — NÃO EXECUTADA · Versão 3.0
-- CORREÇÕES 4 e 7 da OPERATIONAL-BOUNDARY-CORRECTION-01
--
-- ============================================================================
-- O BACKFILL GLOBAL FOI ELIMINADO
-- ============================================================================
--   A v2.0 percorria TODA row sem a chave — 26.127 rows — e gravava UUID,
--   JSON null ou deixava ausente. A v3.0 opera SOMENTE sobre o universo
--   OPERACIONAL, e prova que o restante nao precisa ser tocado.
--
--   PROVA DE DESNECESSIDADE (Correcao 4). Nenhum requisito fisico REAL exige
--   edition_context_profile_id nas rows terminais:
--
--     * o guard (2214) so exige do universo operacional — por construcao;
--     * uq_cvir_row_identity aceita o token 'A' como valor legitimo; nao ha
--       colisao introduzida (ver PROVA DE NAO-COLISAO abaixo);
--     * 2216 (DROP dos indices antigos) tem pre-condicao OPERACIONAL;
--     * a Edge nova so produz rows novas — nao le as antigas;
--     * o confirm (2145:270) recusa job terminal: as rows terminais nao
--       chegam ao writer por caminho algum;
--     * nenhum read model exibe rows de staging terminal como pendencia.
--
--   Conclusao: reescrever ~23.957 rows VALID terminalizadas seria mutacao de
--   historico sem contrapartida fisica. **Removido do escopo.**
--
--   BASELINE (evidencia do momento, nao contrato):
--     VALID total ................................. 24.372
--     VALID + persistence PENDING ................. 415  (TODAS job CANCELLED)
--     OPERACIONAL (job vivo + PENDING) ............ 1.642  <- UNIVERSO DESTA QUERY
--     CONFIRMAVEL (+ APPROVED + VALID) ............ 0
--
--   As 1.642 sao NEEDS_REVIEW. Passarao majoritariamente por 'ABSENT'
--   enquanto o vocabulario nao existir — que e exatamente o que E1 destrava.
--
-- ============================================================================
-- ESCOPO — os quatro universos da Correcao 4
-- ============================================================================
--   A. ROWS OPERACIONAIS EXISTENTES ....... ESTA QUERY. Resolve pelo routing.
--   B. ROWS NOVAS pos-rollout ............. nascem pelo contrato Edge/DB.
--                                           Nao e backfill.
--   C. LINEAGE HISTORICO TERMINAL ......... INTOCADO. Snapshot historico.
--   D. LINEAGE das 365 legacy ............. fora daqui. Ver LINEAGE-STRATEGY.md
--                                           e a Correcao 5 (estado hibrido).
--
-- CANCELLED e terminal (Correcao 3): as 415 rows VALID+PENDING de jobs
-- cancelados NAO entram em A. Nao sao backlog, nao sao reativadas, nao
-- recebem JSON null.
--
-- SEM CARDINALIDADE HARD-CODED (Correcao 7): nenhum gate compara com
-- constante de staging. Baseline e capturado apos o FREEZE como evidencia.
-- ============================================================================

BEGIN;

-- ---------------------------------------------------------------- PASSO 0 ---
CREATE TEMP TABLE bf_params ON COMMIT DROP AS
SELECT NULL::UUID AS game_id, NULL::UUID AS asset_source_id;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM bf_params WHERE game_id IS NULL OR asset_source_id IS NULL) THEN
        RAISE EXCEPTION 'BF_PARAMS_UNSET: preencher bf_params.game_id e asset_source_id.';
    END IF;
END $$;

-- ---------------------------------------------------------------- PASSO 1 ---
-- GATE: vocabulario semeado + routing disponivel.
DO $$
DECLARE v_t INT; v_p INT; v_m INT;
BEGIN
    SELECT COUNT(*) INTO v_t FROM public.card_edition_context_trait;
    SELECT COUNT(*) INTO v_p FROM public.card_edition_context_profile WHERE traits_signature IS NOT NULL;
    SELECT COUNT(*) INTO v_m FROM public.card_edition_context_external_mapping WHERE is_active;
    IF v_t = 0 OR v_p = 0 OR v_m = 0 THEN
        RAISE EXCEPTION 'VOCABULARY_MISSING: traits=% profiles=% mappings=%. Rode 2230/2231/2232 antes.', v_t, v_p, v_m;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                    WHERE n.nspname='internal' AND p.proname='resolve_variant_row_axes') THEN
        RAISE EXCEPTION 'ROUTING_MISSING: rode a Query 2211 antes.';
    END IF;
END $$;

-- ---------------------------------------------------------------- PASSO 2 ---
-- UNIVERSO OPERACIONAL. job_status entra no WHERE — era o que faltava.
CREATE TEMP TABLE bf_operational ON COMMIT DROP AS
SELECT r.id, r.job_id, r.validation_status, r.decision_status, r.persistence_status,
       j.status AS job_status,
       r.normalized_data - 'edition_context_profile_id' AS nd_sem_ec
  FROM public.catalog_variant_import_row r
  JOIN public.catalog_variant_import_job j ON j.id = r.job_id
 WHERE j.status IN ('RECEIVED','PROCESSING','STAGED','CONFIRMING')
   AND r.persistence_status = 'PENDING'
   AND NOT jsonb_exists(r.normalized_data, 'edition_context_profile_id');

-- Snapshot de TODO o universo, para provar que o resto ficou intacto.
CREATE TEMP TABLE bf_all_before ON COMMIT DROP AS
SELECT r.id, r.validation_status, r.decision_status, r.persistence_status,
       r.resulting_variant_id, r.matched_variant_id, r.raw_data,
       r.normalized_data
  FROM public.catalog_variant_import_row r;

DO $$
DECLARE v_op INT; v_hist INT;
BEGIN
    SELECT COUNT(*) INTO v_op FROM bf_operational;
    SELECT COUNT(*) INTO v_hist
      FROM public.catalog_variant_import_row r
      JOIN public.catalog_variant_import_job j ON j.id = r.job_id
     WHERE NOT jsonb_exists(r.normalized_data,'edition_context_profile_id')
       AND (j.status NOT IN ('RECEIVED','PROCESSING','STAGED','CONFIRMING')
            OR r.persistence_status <> 'PENDING');
    RAISE NOTICE 'ESCOPO: % rows OPERACIONAIS a resolver; % rows HISTORICAS deliberadamente FORA.', v_op, v_hist;

    IF v_op = 0 THEN
        RAISE NOTICE 'Universo operacional VAZIO — esta Query e no-op. E o estado esperado pela baseline atual.';
    END IF;
END $$;

-- ---------------------------------------------------------------- PASSO 3 ---
CREATE TEMP TABLE bf_plan ON COMMIT DROP AS
SELECT o.id, o.validation_status, o.persistence_status,
       ax.edition_context_state,
       ax.edition_context_profile_id,
       CASE ax.edition_context_state
           WHEN 'RESOLVED_WITH_EC_PROFILE'    THEN 'UUID'
           WHEN 'RESOLVED_NO_EDITION_CONTEXT' THEN 'NULL'
           ELSE                                    'ABSENT'
       END AS destino
  FROM bf_operational o
  JOIN public.catalog_variant_import_row r ON r.id = o.id
  JOIN public.card c  ON c.id  = r.card_id
  JOIN public.card_set cs ON cs.id = c.card_set_id
  CROSS JOIN bf_params pr
  CROSS JOIN LATERAL internal.resolve_variant_row_axes(
       r.raw_data, pr.game_id, pr.asset_source_id, cs.code) ax;

DO $$
DECLARE v_bad INT;
BEGIN
    SELECT COUNT(*) INTO v_bad FROM bf_plan
     WHERE (destino = 'UUID'  AND edition_context_profile_id IS NULL)
        OR (destino <> 'UUID' AND edition_context_profile_id IS NOT NULL);
    IF v_bad <> 0 THEN
        RAISE EXCEPTION 'PLAN_INCOHERENT: % rows com destino incompativel.', v_bad;
    END IF;
END $$;

-- ---------------------------------------------------------------- PASSO 4 ---
-- DISTRIBUIÇÃO — evidência do momento, nunca gate.
CREATE TEMP TABLE bf_distribution ON COMMIT DROP AS
SELECT 'por_destino' AS recorte, destino AS c1, NULL::TEXT AS c2, COUNT(*) AS rows
  FROM bf_plan GROUP BY destino
UNION ALL SELECT 'destino_x_validation',  destino, validation_status,  COUNT(*) FROM bf_plan GROUP BY 2,3
UNION ALL SELECT 'destino_x_persistence', destino, persistence_status, COUNT(*) FROM bf_plan GROUP BY 2,3
UNION ALL SELECT 'destino_x_job_status',  p.destino, o.job_status,     COUNT(*)
     FROM bf_plan p JOIN bf_operational o ON o.id = p.id GROUP BY 2,3
UNION ALL SELECT 'estado_routing', edition_context_state, NULL, COUNT(*) FROM bf_plan GROUP BY 2;

-- ---------------------------------------------------------------- PASSO 5 ---
-- ESCRITA. Só UUID e NULL. ABSENT é no-op por construção.
UPDATE public.catalog_variant_import_row r
   SET normalized_data = r.normalized_data
                       || jsonb_build_object('edition_context_profile_id', p.edition_context_profile_id)
  FROM bf_plan p WHERE p.id = r.id AND p.destino = 'UUID';

UPDATE public.catalog_variant_import_row r
   SET normalized_data = r.normalized_data || '{"edition_context_profile_id": null}'::JSONB
  FROM bf_plan p WHERE p.id = r.id AND p.destino = 'NULL';

-- ---------------------------------------------------------------- PASSO 6 ---
-- PÓS-CONDIÇÕES. Invariantes, sem cardinalidade fixa.
DO $$
DECLARE v_n INT;
BEGIN
    -- P1 UUID exato.
    SELECT COUNT(*) INTO v_n FROM bf_plan p JOIN public.catalog_variant_import_row r ON r.id=p.id
     WHERE p.destino='UUID'
       AND (r.normalized_data->>'edition_context_profile_id') IS DISTINCT FROM p.edition_context_profile_id::TEXT;
    IF v_n<>0 THEN RAISE EXCEPTION 'P1_FAIL: % rows com UUID divergente.', v_n; END IF;

    -- P2 JSON null só onde o routing confirmou ausência de contexto.
    SELECT COUNT(*) INTO v_n FROM bf_plan p JOIN public.catalog_variant_import_row r ON r.id=p.id
     WHERE p.destino='NULL' AND jsonb_typeof(r.normalized_data->'edition_context_profile_id')<>'null';
    IF v_n<>0 THEN RAISE EXCEPTION 'P2_FAIL: % rows com valor nao-null.', v_n; END IF;

    -- P3 indeterminado permanece AUSENTE.
    SELECT COUNT(*) INTO v_n FROM bf_plan p JOIN public.catalog_variant_import_row r ON r.id=p.id
     WHERE p.destino='ABSENT' AND jsonb_exists(r.normalized_data,'edition_context_profile_id');
    IF v_n<>0 THEN RAISE EXCEPTION 'P3_FAIL: % rows indeterminadas receberam chave.', v_n; END IF;

    -- P4 universo operacional VALID pronto para o guard.
    SELECT COUNT(*) INTO v_n
      FROM public.catalog_variant_import_row r
      JOIN public.catalog_variant_import_job j ON j.id = r.job_id
     WHERE j.status IN ('RECEIVED','PROCESSING','STAGED','CONFIRMING')
       AND r.persistence_status='PENDING' AND r.validation_status='VALID'
       AND NOT jsonb_exists(r.normalized_data,'edition_context_profile_id');
    IF v_n<>0 THEN RAISE EXCEPTION 'P4_FAIL: % rows operacionais VALID sem chave.', v_n; END IF;

    -- P5 *** HISTORICO INTOCADO *** — a prova central da Correcao 4.
    -- Nenhuma row fora do universo operacional teve NADA alterado.
    SELECT COUNT(*) INTO v_n
      FROM bf_all_before b JOIN public.catalog_variant_import_row r ON r.id = b.id
     WHERE NOT EXISTS (SELECT 1 FROM bf_operational o WHERE o.id = b.id)
       AND (r.normalized_data     IS DISTINCT FROM b.normalized_data
         OR r.raw_data            IS DISTINCT FROM b.raw_data
         OR r.validation_status   IS DISTINCT FROM b.validation_status
         OR r.decision_status     IS DISTINCT FROM b.decision_status
         OR r.persistence_status  IS DISTINCT FROM b.persistence_status
         OR r.resulting_variant_id IS DISTINCT FROM b.resulting_variant_id
         OR r.matched_variant_id  IS DISTINCT FROM b.matched_variant_id);
    IF v_n<>0 THEN
        RAISE EXCEPTION 'P5_FAIL: % rows HISTORICAS foram alteradas. O escopo operacional vazou.', v_n;
    END IF;

    -- P6 CANCELLED intocado, explicitamente.
    SELECT COUNT(*) INTO v_n
      FROM bf_all_before b
      JOIN public.catalog_variant_import_row r ON r.id = b.id
      JOIN public.catalog_variant_import_job j ON j.id = r.job_id
     WHERE j.status = 'CANCELLED'
       AND r.normalized_data IS DISTINCT FROM b.normalized_data;
    IF v_n<>0 THEN RAISE EXCEPTION 'P6_FAIL: % rows de job CANCELLED alteradas.', v_n; END IF;

    -- P7 estados e lineage preservados no universo tocado.
    SELECT COUNT(*) INTO v_n
      FROM bf_all_before b JOIN public.catalog_variant_import_row r ON r.id=b.id
     WHERE r.validation_status   IS DISTINCT FROM b.validation_status
        OR r.decision_status     IS DISTINCT FROM b.decision_status
        OR r.persistence_status  IS DISTINCT FROM b.persistence_status
        OR r.resulting_variant_id IS DISTINCT FROM b.resulting_variant_id
        OR r.matched_variant_id  IS DISTINCT FROM b.matched_variant_id
        OR r.raw_data            IS DISTINCT FROM b.raw_data;
    IF v_n<>0 THEN RAISE EXCEPTION 'P7_FAIL: % rows com estado/raw_data alterado.', v_n; END IF;

    -- P8 normalized_data mudou apenas pela chave nova.
    SELECT COUNT(*) INTO v_n
      FROM bf_all_before b JOIN public.catalog_variant_import_row r ON r.id=b.id
     WHERE (r.normalized_data - 'edition_context_profile_id')
           IS DISTINCT FROM (b.normalized_data - 'edition_context_profile_id');
    IF v_n<>0 THEN RAISE EXCEPTION 'P8_FAIL: % rows com payload alterado alem da chave.', v_n; END IF;

    RAISE NOTICE 'RESOLUCAO OPERACIONAL OK — 8/8 pos-condicoes. Historico intacto.';
END $$;

-- ============================================================================
-- PROVA DE NÃO-COLISÃO (Correcao 5 da BACKFILL-SEMANTICS, reconfirmada)
--   uq_cvir_row_identity ja existe quando esta Query roda (2210). Logo, para
--   cada (job, card, vt, token_pp) existe NO MAXIMO UMA row com token 'A'.
--   Esta Query so move rows de 'A' para 'N' ou 'U:<uuid>' — nunca o inverso,
--   nunca funde duas. Mover uma unica row de um balde para outro nao pode
--   criar duplicata. O tri-state A/N/U permanece integro, e rows historicas
--   com token 'A' continuam representaveis.
--
-- IDEMPOTÊNCIA
--   bf_operational so inclui rows SEM a chave. Reexecucao: plano vazio,
--   zero UPDATE. Rows 'ABSENT' seguem elegiveis — se o vocabulario crescer,
--   reexecutar passa a resolve-las. Reentrancia, nao efeito colateral.
--
-- ROLLBACK (so antes de 2214)
--   UPDATE public.catalog_variant_import_row r
--      SET normalized_data = r.normalized_data - 'edition_context_profile_id'
--     FROM bf_operational o WHERE o.id = r.id;
--
-- ARMADO PARA ROLLOUT (ROLLOUT-EXECUTION-READINESS-01). Terminador COMMIT.
-- Corpo auditado PRESERVADO byte a byte; a unica alteracao de armamento foi
-- ROLLBACK; -> COMMIT;. A protecao contra execucao prematura e GOVERNANCA
-- (autorizacao de Fabricio + ordem de batches), nao o terminador — mesma
-- decisao ja aceita em R1 para 2203-2211.
-- ============================================================================
COMMIT;
