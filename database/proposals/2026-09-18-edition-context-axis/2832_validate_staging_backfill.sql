-- ============================================================================
-- Query 2832 — VALIDAÇÃO do backfill SEMÂNTICO (gate de entrada do 2214)
-- Status: PROPOSTA — NÃO EXECUTADA · Versão 3.1
--
-- v3.1 (BATCH6-PROOF-PARAMS-CORRECTION-01): UNICA mudanca — bv_params deixa
-- de nascer NULL e passa a resolver 'POKEMON'/'TCGDEX' por code, com preflight
-- fail-loud de exatamente-um (BV_GAME_REFERENCE / BV_SOURCE_REFERENCE) antes
-- de montar a TEMP TABLE. O arquivo passa a ser executavel VERBATIM.
-- Os 14 casos, o routing, o universo operacional, a semantica de
-- historico/CANCELLED, o SAVEPOINT do V9 e a fronteira BEGIN...ROLLBACK
-- permanecem byte a byte os da v3.0.
--
-- v3.0 (OPERATIONAL-BOUNDARY-CORRECTION-01): o escopo deixou de ser global.
-- V1-V3 e V6 passam a medir SOMENTE o universo operacional (job vivo +
-- persistence PENDING); V4/V5 ficam job-aware; V13/V14 sao novos e provam
-- que o historico NAO foi tocado e que CANCELLED e terminal.
-- CORREÇÃO 8 da BACKFILL-SEMANTICS-CORRECTION-01
--
-- v2.0 reescreve a v1.0 inteira. A v1.0 provava a regra ERRADA:
--   "toda row VALID tem a chave" — que era o proprio defeito semantico.
-- Agora prova os TRES destinos e o escopo OPERACIONAL do guard.
--
-- SEM CARDINALIDADE FIXA. Nenhum caso compara com constante de staging.
-- Todas as provas sao invariantes/relacoes. Contagens sao EVIDENCIA.
--
-- Roda DEPOIS de 2212 e ANTES de 2214. Read-only fora de SAVEPOINT.
-- 14 casos.
-- ============================================================================

BEGIN;

-- Parametros: mesmos de 2212 (o recomputo do routing precisa deles).
--
-- PARAMETROS DETERMINISTICOS (BATCH6-PROOF-PARAMS-CORRECTION-01).
-- A v3.0 criava bv_params com game_id/asset_source_id NULL e abortava em
-- BV_PARAMS_UNSET. Mesma classe de defeito ja corrigida na 2212 v3.1: o
-- arquivo nao era executavel verbatim — exigia editar o SQL no meio da
-- execucao para colar dois UUID.
--
-- Correcao: resolver as duas referencias canonicas POR CODE, identico ao que
-- 2212/2230/2231/2232 fazem. Sem UUID hardcoded — o valor vem do banco.
-- O preflight roda ANTES de bv_params existir e exige EXATAMENTE UM de cada:
--   0  -> referencia ausente; o recomputo do routing correria com parametro
--         NULL e V1-V6 comparariam contra lixo, sem falhar alto;
--   >1 -> ambiguo; bv_params teria N linhas e o CROSS JOIN multiplicaria
--         bv_recheck por N. Por isso o teste e <> 1, nao > 0.
DO $$
DECLARE v_game INT; v_src INT;
BEGIN
    SELECT COUNT(*) INTO v_game FROM public.game         WHERE code = 'POKEMON';
    IF v_game <> 1 THEN
        RAISE EXCEPTION 'BV_GAME_REFERENCE (2832): esperado EXATAMENTE 1 Game com code=''POKEMON'', encontrado %. Abortado antes de montar bv_params.', v_game;
    END IF;

    SELECT COUNT(*) INTO v_src FROM public.asset_source WHERE code = 'TCGDEX';
    IF v_src <> 1 THEN
        RAISE EXCEPTION 'BV_SOURCE_REFERENCE (2832): esperado EXATAMENTE 1 asset_source com code=''TCGDEX'', encontrado %. Abortado antes de montar bv_params.', v_src;
    END IF;
END $$;

CREATE TEMP TABLE bv_params ON COMMIT DROP AS
SELECT (SELECT id FROM public.game         WHERE code = 'POKEMON') AS game_id,
       (SELECT id FROM public.asset_source WHERE code = 'TCGDEX')  AS asset_source_id;

-- Defesa redundante: o preflight acima ja garante a resolucao. Mantida porque
-- e barata e porque prova, no proprio artefato, que bv_params tem UMA linha
-- REAL. BV_PARAMS_UNSET preservado como rede final.
DO $$
DECLARE v_n INT;
BEGIN
    SELECT COUNT(*) INTO v_n FROM bv_params;
    IF v_n <> 1 THEN
        RAISE EXCEPTION 'BV_PARAMS_CARDINALITY: bv_params deveria ter EXATAMENTE 1 linha, tem %.', v_n;
    END IF;
    IF EXISTS (SELECT 1 FROM bv_params WHERE game_id IS NULL OR asset_source_id IS NULL) THEN
        RAISE EXCEPTION 'BV_PARAMS_UNSET: bv_params.game_id ou asset_source_id resolveu NULL apesar do preflight.';
    END IF;
END $$;

-- Recomputa o routing para CONFERIR o que foi gravado. Se o backfill estiver
-- certo, o destino recomputado bate com o estado atual de cada row.
CREATE TEMP TABLE bv_recheck ON COMMIT DROP AS
SELECT r.id,
       j.status AS job_status,
       (j.status IN ('RECEIVED','PROCESSING','STAGED','CONFIRMING')
        AND r.persistence_status = 'PENDING') AS operacional,
       r.validation_status,
       r.persistence_status,
       ax.edition_context_state,
       ax.edition_context_profile_id                                   AS esperado_uuid,
       CASE ax.edition_context_state
           WHEN 'RESOLVED_WITH_EC_PROFILE'    THEN 'UUID'
           WHEN 'RESOLVED_NO_EDITION_CONTEXT' THEN 'NULL'
           ELSE                                    'ABSENT'
       END                                                             AS esperado,
       CASE WHEN NOT jsonb_exists(r.normalized_data,'edition_context_profile_id') THEN 'ABSENT'
            WHEN jsonb_typeof(r.normalized_data->'edition_context_profile_id') = 'null' THEN 'NULL'
            ELSE 'UUID' END                                            AS observado,
       r.normalized_data ->> 'edition_context_profile_id'              AS observado_uuid
  FROM public.catalog_variant_import_row r
  JOIN public.catalog_variant_import_job j ON j.id = r.job_id
  JOIN public.card c  ON c.id  = r.card_id
  CROSS JOIN bv_params pr
  -- ESCOPO CANONICO (SOURCE-SCOPE-CORRECTION-01). O recomputo precisa usar
  -- EXATAMENTE o mesmo escopo que a 2212/2233 usam para gravar, senao esta
  -- Query mede uma resolucao que ninguem produziu. Autoridade:
  -- internal.resolve_variant_mapping_scope(). NUNCA card_set.code.
  LEFT JOIN LATERAL internal.resolve_variant_mapping_scope(
       c.card_set_id, pr.asset_source_id) sc ON TRUE
  CROSS JOIN LATERAL internal.resolve_variant_row_axes(
       r.raw_data, pr.game_id, pr.asset_source_id, sc.external_set_id) ax;

DO $$
DECLARE v_n INT; v_pass INT := 0;
BEGIN
    -- V1 — UUID em caso COM Edition Context. Existe pelo menos um, e todos
    -- carregam exatamente o UUID que o routing resolve.
    SELECT COUNT(*) INTO v_n FROM bv_recheck WHERE esperado = 'UUID';
    IF v_n = 0 THEN
        RAISE NOTICE 'V1: nenhuma row resolve para profile hoje. Esperado se o universo operacional estiver vazio (baseline atual) ou se o vocabulario ainda nao foi semeado.';
    END IF;
    -- Coerencia exigida SOMENTE no universo operacional: o historico nao
    -- foi reescrito e nao precisa bater com o recomputo.
    SELECT COUNT(*) INTO v_n FROM bv_recheck
     WHERE operacional AND esperado = 'UUID'
       AND observado_uuid IS DISTINCT FROM esperado_uuid::TEXT;
    IF v_n <> 0 THEN RAISE EXCEPTION 'V1_FAIL: % rows com UUID divergente do resolvido.', v_n; END IF;
    v_pass := v_pass + 1;

    -- V2 — JSON null SOMENTE onde o routing confirma ausencia de contexto.
    SELECT COUNT(*) INTO v_n FROM bv_recheck
     WHERE operacional AND observado = 'NULL' AND esperado <> 'NULL';
    IF v_n <> 0 THEN
        RAISE EXCEPTION 'V2_FAIL: % rows com JSON null sem RESOLVED_NO_EDITION_CONTEXT. Placeholder de migracao detectado.', v_n;
    END IF;
    v_pass := v_pass + 1;

    -- V3 — AUSENTE = routing de Edition Context NAO-TERMINAL.
    --
    -- CONTRATO RECONCILIADO (SOURCE-SCOPE-CORRECTION-01). A redacao anterior
    -- dizia "AUSENTE em HOLD/indeterminado", equivalendo chave ausente a
    -- "row indeterminada". Essa equivalencia esta SUPERADA e era enganosa.
    --
    -- AUSENTE significa UMA coisa so: o eixo de CONTEXTO DE EDICAO nao chegou
    -- a estado terminal para esta row. A classificacao GLOBAL da row e
    -- ORTOGONAL a isso — os tres eixos (Acabamento, Impressao, Contexto de
    -- Edicao) sao independentes, e cada um resolve ou nao resolve por conta
    -- propria.
    --
    -- No baseline atual, AUSENTE = 0: nenhuma row operacional esta com o eixo
    -- 3 em aberto. As 7 rows foil=LEAGUE + stamp=STAFF sao a ilustracao exata
    -- da ortogonalidade — permanecem GLOBALMENTE INDETERMINATE pela pendencia
    -- do foil (eixo de Acabamento), e ao mesmo tempo tem o eixo de Contexto de
    -- Edicao TERMINALMENTE resolvido por stamp=STAFF. Elas contam como UUID
    -- aqui, e isso e correto.
    --
    -- A LOGICA DESTE CASO NAO MUDOU — so a redacao. O predicado continua
    -- sendo "esperado = ABSENT implica observado = ABSENT".
    SELECT COUNT(*) INTO v_n FROM bv_recheck
     WHERE operacional AND esperado = 'ABSENT' AND observado <> 'ABSENT';
    IF v_n <> 0 THEN
        RAISE EXCEPTION 'V3_FAIL: % rows com eixo de Contexto de Edicao NAO-TERMINAL receberam chave. Semantica falsificada. (NAO confundir com classificacao global da row: os eixos sao ortogonais.)', v_n;
    END IF;
    v_pass := v_pass + 1;

    -- V4 — o guard 2214 pode entrar: zero VALID+PENDING sem chave.
    SELECT COUNT(*) INTO v_n FROM bv_recheck
     WHERE operacional AND validation_status = 'VALID' AND observado = 'ABSENT';
    IF v_n <> 0 THEN RAISE EXCEPTION 'V4_FAIL: % rows OPERACIONAIS VALID sem chave.', v_n; END IF;
    v_pass := v_pass + 1;

    -- V5 — historico terminal PODE permanecer VALID + chave ausente.
    -- Prova de EXISTENCIA: se nao houver nenhuma, o predicado operacional
    -- nao estaria sendo exercitado e a regra global teria bastado.
    SELECT COUNT(*) INTO v_n FROM bv_recheck
     WHERE NOT operacional AND validation_status = 'VALID' AND observado = 'ABSENT';
    IF v_n = 0 THEN
        RAISE EXCEPTION 'V5_FAIL: nenhuma row HISTORICA VALID sem chave. Ou o escopo vazou e reescreveu historico, ou alguem gravou null em HOLD.';
    END IF;
    RAISE NOTICE 'V5 OK — % rows HISTORICAS VALID legitimamente sem chave.', v_n;
    v_pass := v_pass + 1;

    -- V6 — coerencia total: observado = esperado para TODA row.
    SELECT COUNT(*) INTO v_n FROM bv_recheck WHERE operacional AND observado <> esperado;
    IF v_n <> 0 THEN
        RAISE EXCEPTION 'V6_FAIL: % rows OPERACIONAIS com destino divergente do recomputo.', v_n;
    END IF;
    v_pass := v_pass + 1;

    -- V8 — MULTIPLAS ROWS DE LINEAGE por Variant sao tratadas por ROW.
    -- Nao pode haver Variant cujas rows tenham destinos divergentes SEM que
    -- o raw_data delas tambem divirja: o destino vem da row, nao da Variant.
    SELECT COUNT(*) INTO v_n FROM (
        SELECT r.resulting_variant_id
          FROM public.catalog_variant_import_row r
          JOIN bv_recheck b ON b.id = r.id
         WHERE r.resulting_variant_id IS NOT NULL
         GROUP BY r.resulting_variant_id
        HAVING COUNT(DISTINCT b.observado) > 1
           AND COUNT(DISTINCT r.raw_data)  = 1) d;
    IF v_n <> 0 THEN
        RAISE EXCEPTION 'V8_FAIL: % Variants com rows de mesmo raw_data e destinos diferentes — backfill nao foi determinístico por row.', v_n;
    END IF;
    RAISE NOTICE 'V8 OK — lineage 1:N tratado por row, sem escolher uma row por Variant.';
    v_pass := v_pass + 1;

    RAISE NOTICE 'BACKFILL SEMANTICO: %/7 provas de destino OK.', v_pass;
END $$;

-- ---------------------------------------------------------------------------
-- V7 — ESTADOS E COUNTERS INALTERADOS (comparacao estrutural, nao numerica).
-- ---------------------------------------------------------------------------
DO $$
DECLARE v_n INT;
BEGIN
    -- Nenhuma row INSERTED/UNCHANGED perdeu lineage.
    SELECT COUNT(*) INTO v_n FROM public.catalog_variant_import_row
     WHERE persistence_status IN ('INSERTED','UNCHANGED')
       AND resulting_variant_id IS NULL AND matched_variant_id IS NULL;
    IF v_n <> 0 THEN RAISE EXCEPTION 'V7_FAIL: % rows terminais sem lineage.', v_n; END IF;

    -- Nenhuma row PENDING com lineage (state machine intacta).
    SELECT COUNT(*) INTO v_n FROM public.catalog_variant_import_row
     WHERE persistence_status = 'PENDING' AND resulting_variant_id IS NOT NULL;
    IF v_n <> 0 THEN RAISE EXCEPTION 'V7_FAIL: % rows PENDING com resulting_variant_id.', v_n; END IF;

    RAISE NOTICE 'V7 OK — state machine e lineage intactos.';
END $$;

-- ---------------------------------------------------------------------------
-- V9 — IDEMPOTENCIA: reexecutar o backfill afeta ZERO rows resolvidas.
-- ---------------------------------------------------------------------------
SAVEPOINT v9;
DO $$
DECLARE v_n INT;
BEGIN
    WITH upd AS (
        UPDATE public.catalog_variant_import_row r
           SET normalized_data = r.normalized_data
                               || jsonb_build_object('edition_context_profile_id', b.esperado_uuid)
          FROM bv_recheck b
         WHERE b.id = r.id AND b.esperado = 'UUID'
           AND NOT jsonb_exists(r.normalized_data,'edition_context_profile_id')
        RETURNING 1)
    SELECT COUNT(*) INTO v_n FROM upd;
    IF v_n <> 0 THEN
        RAISE EXCEPTION 'V9_FAIL: reexecucao afetaria % rows — backfill incompleto ou nao idempotente.', v_n;
    END IF;
    RAISE NOTICE 'V9 OK — backfill idempotente.';
END $$;
ROLLBACK TO SAVEPOINT v9;

-- ---------------------------------------------------------------------------
-- V10 — ORDEM: o guard ainda esta no estagio PERMISSIVO quando 2832 roda.
-- ---------------------------------------------------------------------------
DO $$
DECLARE v_estrito BOOLEAN;
BEGIN
    SELECT prosrc LIKE '%CVIR_PENDING_VALID_REQUIRES_EDITION_CONTEXT_KEY%' INTO v_estrito
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'internal' AND p.proname = 'guard_cvir_normalized_shape';
    IF v_estrito THEN
        RAISE EXCEPTION 'V10_FAIL: guard JA operacional (2214 rodou antes de 2832). Ordem do DAG violada.';
    END IF;
    RAISE NOTICE 'V10 OK — guard permissivo; 2214 pode ser promovida.';
END $$;

-- ---------------------------------------------------------------------------
-- V11 — IDENTIDADE nao degradada: o token A/N/U continua distinguindo.
-- Prova de que o backfill nao criou colisao: ele so vai de A para N ou U,
-- e o indice ja existia antes — logo havia no maximo UMA row com token A por
-- (job, card, vt, token_pp). Migrar essa unica row nao pode colidir.
-- ---------------------------------------------------------------------------
DO $$
DECLARE v_n INT;
BEGIN
    SELECT COUNT(*) INTO v_n FROM (
        SELECT job_id, card_id,
               (normalized_data ->> 'variant_type_id') vt,
               internal.axis_identity_token(normalized_data,'printing_profile_id') tp,
               internal.axis_identity_token(normalized_data,'edition_context_profile_id') te
          FROM public.catalog_variant_import_row
         WHERE (normalized_data ->> 'variant_type_id') IS NOT NULL
         GROUP BY 1,2,3,4,5 HAVING COUNT(*) > 1) d;
    IF v_n <> 0 THEN RAISE EXCEPTION 'V11_FAIL: % identidades de staging duplicadas.', v_n; END IF;

    -- Os tres tokens seguem representaveis e distintos.
    IF internal.axis_identity_token('{}'::JSONB,'k') <> 'A'
       OR internal.axis_identity_token('{"k":null}'::JSONB,'k') <> 'N'
       OR internal.axis_identity_token('{"k":"11111111-1111-4111-8111-111111111111"}'::JSONB,'k')
          <> 'U:11111111-1111-4111-8111-111111111111' THEN
        RAISE EXCEPTION 'V11_FAIL: tri-state A/N/U degradado.';
    END IF;
    RAISE NOTICE 'V11 OK — A/N/U intactos; rows terminais com token A convivem sem colisao.';
END $$;

-- ---------------------------------------------------------------------------
-- V12 — EVIDENCIA DO MOMENTO (nao e contrato). Distribuicao para o relatorio.
-- ---------------------------------------------------------------------------
--   SELECT observado, validation_status, persistence_status, COUNT(*)
--     FROM bv_recheck GROUP BY 1,2,3 ORDER BY 1,2,3;
--   SELECT edition_context_state, COUNT(*) FROM bv_recheck GROUP BY 1 ORDER BY 2 DESC;

-- ---------------------------------------------------------------------------
-- V13 — HISTORICO INTOCADO. A prova central da Correcao 4.
-- ---------------------------------------------------------------------------
DO $$
DECLARE v_n INT;
BEGIN
    -- Nenhuma row historica pode ter destino divergente do que ja tinha —
    -- porque nenhuma foi escrita. Se alguma bate com o recomputo por acaso,
    -- tudo bem; o que NAO pode e o escopo ter vazado e reescrito historico.
    -- Prova operacional: zero row historica com chave que o routing NAO
    -- resolveria como tal (assinatura de escrita indevida).
    SELECT COUNT(*) INTO v_n FROM bv_recheck
     WHERE NOT operacional AND observado = 'NULL' AND esperado = 'ABSENT';
    IF v_n <> 0 THEN
        RAISE EXCEPTION 'V13_FAIL: % rows HISTORICAS com JSON null onde o routing diz indeterminado — placeholder gravado em historico.', v_n;
    END IF;
    RAISE NOTICE 'V13 OK — nenhum placeholder estrutural em row historica.';
END $$;

-- ---------------------------------------------------------------------------
-- V14 — CANCELLED e TERMINAL (Correcao 3). Fixture real: VALID + PENDING +
-- chave AUSENTE em job cancelado e HISTORICO PERMITIDO, nao row invalida.
-- ---------------------------------------------------------------------------
DO $$
DECLARE v_n INT; v_op INT;
BEGIN
    SELECT COUNT(*) INTO v_n FROM bv_recheck
     WHERE job_status = 'CANCELLED' AND validation_status = 'VALID'
       AND persistence_status = 'PENDING';
    RAISE NOTICE 'V14 — % rows CANCELLED VALID+PENDING (as 415 da baseline).', v_n;

    -- Nenhuma delas pode estar classificada como operacional.
    SELECT COUNT(*) INTO v_op FROM bv_recheck
     WHERE job_status = 'CANCELLED' AND operacional;
    IF v_op <> 0 THEN
        RAISE EXCEPTION 'V14_FAIL: % rows de job CANCELLED classificadas como operacionais.', v_op;
    END IF;

    -- E nenhuma pode ter recebido chave por efeito do backfill.
    SELECT COUNT(*) INTO v_op FROM bv_recheck
     WHERE job_status = 'CANCELLED' AND observado <> 'ABSENT' AND esperado = 'ABSENT';
    IF v_op <> 0 THEN
        RAISE EXCEPTION 'V14_FAIL: % rows CANCELLED indeterminadas receberam chave.', v_op;
    END IF;
    RAISE NOTICE 'V14 OK — CANCELLED tratado como historico terminal.';
END $$;

-- ============================================================================
-- GATE: 14/14. Qualquer FAIL bloqueia a Query 2214.
-- ============================================================================
ROLLBACK;
