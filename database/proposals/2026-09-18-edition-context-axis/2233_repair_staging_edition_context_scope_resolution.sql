-- ============================================================================
-- Query 2233 — REPARO DO EIXO EDITION CONTEXT NO UNIVERSO OPERACIONAL
--               (forward-fix do defeito de ESCOPO da 2212 v3.1)
--
-- Status: *** PROPOSTA — NAO EXECUTADA ***
-- Versao: 1.0
-- Mandato: EDITION-CONTEXT-AXIS-BATCH6-SOURCE-SCOPE-IMPLEMENTATION-01
-- ============================================================================
--
-- ============================================================================
-- 1. POR QUE ESTA QUERY EXISTE
-- ============================================================================
-- A Query 2212 foi executada no LIVE (ledger version 20260920172947, 1x) na
-- versao v3.1, publicada no commit d07cbedf7c61830d748d92445f7e2aded9e373fa.
-- Aquela versao passava `cs.code` como 4o argumento de
-- internal.resolve_variant_row_axes().
--
-- O 4o argumento e `p_external_set_id`: o identificador do Card Set **NA FONTE
-- EXTERNA** (card_set_external_reference.external_set_id), comparado SEM
-- TRADUCAO contra card_edition_context_external_mapping.external_set_id.
-- `card_set.code` e o codigo INTERNO. Os dois divergem em valor e em caixa:
--     Fonte (TCGdex)   mfb   base2   dp1   dp4   dp5   dp6   dp7   svp   swsh9
--     card_set.code    MFB   BASE2   DP1   DP4   DP5   DP6   DP7   SVP   SWSH9
--
-- Consequencia medida no LIVE: os 14 mappings SOURCE_SET_SCOPED ficaram
-- INALCANCAVEIS (0 de 14 casam literalmente) e 66 rows do universo operacional
-- receberam JSON null onde deveriam ter recebido UUID.
--
-- O defeito e SILENCIOSO por construcao: o eixo e fail-closed, entao um token
-- que nao encontra mapping ATIVO no escopo permanece no residual de Finish e a
-- linha resolve como RESOLVED_NO_EDITION_CONTEXT — que a 2212 grava como JSON
-- null. Nenhuma excecao e levantada. As 8 pos-condicoes internas da 2212
-- passaram porque ela registrou fielmente o que a 2211 resolveu; o defeito
-- estava no que ela ENTREGOU a 2211. Por isso so foi encontrado por postcheck
-- EXTERNO, confrontando a particao semantica canonica.
--
-- ============================================================================
-- 2. POR QUE NAO BASTA REEXECUTAR A 2212
-- ============================================================================
--   (a) a 2212 ja consta no ledger 1x e o contrato de rollout exige EXATAMENTE
--       1x — reexecutar viola o contrato e destroi a rastreabilidade;
--   (b) `bf_operational` so inclui rows **SEM** a chave. Apos a v3.1 as 1.642
--       ja tem chave: uma reexecucao teria plano VAZIO e nao corrigiria nada.
--       A idempotencia que protege a Query e exatamente o que a torna incapaz
--       de se auto-reparar.
--
-- Logo: forward-fix. Esta Query e o UNICO mecanismo de reconciliacao do dado
-- ja gravado. A 2212 v3.2 corrige o ARQUIVO (para instalacao limpa e para o
-- proximo leitor), nunca o LIVE.
--
-- ============================================================================
-- 3. O QUE ESTA QUERY NAO FAZ
-- ============================================================================
--   * NAO altera a 2211. A funcao sempre comparou fielmente o valor recebido;
--     o defeito estava nos chamadores. Duplicar traducao dentro dela criaria
--     uma segunda autoridade sobre card_set_external_reference.
--   * NAO transforma mappings para card_set.code. A semantica de
--     external_set_id e "identificador na Fonte" e permanece intocada.
--   * NAO toca em row historica (job terminal ou persistence <> PENDING).
--   * NAO toca nas rows de job CANCELLED. CANCELLED e terminal (Correcao 3).
--   * NAO reabre o Batch 3. Os baselines 1.642 / 847 / 415 sao PRESERVADOS e
--     provados inalterados, nunca recalculados.
--
-- ============================================================================
-- 3-BIS. AS DUAS COLUNAS QUE MUDAM — updated_at NAO E OMITIDO
-- ============================================================================
-- Seria INCORRETO afirmar "somente edition_context_profile_id muda". A tabela
-- public.catalog_variant_import_row tem DOIS triggers BEFORE (Query 2139), e
-- um deles escreve outra coluna:
--
--   trg_catalog_variant_import_row_normalize    BEFORE INSERT OR UPDATE
--       -> public.normalize_catalog_variant_import_row()
--          UPPER(BTRIM(...)) nos quatro status + NULLIF(BTRIM(error_detail),'')
--
--   trg_catalog_variant_import_row_set_updated_at   BEFORE UPDATE
--       -> public.set_updated_at()
--          NEW.updated_at = CURRENT_TIMESTAMP
--
-- Logo o contrato REAL da escrita desta Query, nas 66 rows do delta, e:
--
--   COLUNA                     MUDA?   POR QUE
--   normalized_data            SIM     a chave edition_context_profile_id sai
--                                      de JSON null para string UUID. NENHUMA
--                                      outra chave do objeto muda.
--   updated_at                 SIM     efeito ESPERADO de set_updated_at().
--                                      E a UNICA outra coluna autorizada.
--   raw_data                   NAO
--   validation_status          NAO     ja normalizado; UPPER(BTRIM(x)) = x
--   match_status               NAO     idem
--   decision_status            NAO     idem
--   persistence_status         NAO     idem
--   error_detail               NAO     ja NULL ou ja trimado
--   matched_variant_id         NAO     lineage de staging
--   resulting_variant_id       NAO     lineage de staging
--   created_at                 NAO
--   id / job_id / card_id      NAO
--
-- O trigger de NORMALIZACAO e idempotente sobre dado ja normalizado, mas isso
-- e uma EXPECTATIVA, nao um fato garantido: se alguma row tiver status com
-- caixa/espaco divergente, ou error_detail com apenas espacos, o trigger vai
-- materializar essa mudanca agora — e ela seria atribuida erroneamente a este
-- reparo. Por isso o PASSO 6 prova os quatro status e error_detail coluna a
-- coluna contra o snapshot, e ABORTA se qualquer um mudar (`RP_P3_FAIL`).
-- Mudanca material de status vinda do trigger de normalizacao = STOP.
--
-- Nota de nomenclatura: NAO existe coluna `lineage` nesta tabela. O que cumpre
-- esse papel sao `matched_variant_id` e `resulting_variant_id` (ponteiros para
-- public.card_variant) — ambos provados inalterados em TODAS as rows.
--
-- ============================================================================
-- 4. CONTRATO NUMERICO (aprovado em SOURCE-SCOPE-IMPLEMENTATION-01)
-- ============================================================================
--   Universo operacional (job vivo + persistence PENDING) .......... 1.642
--
--   ESTADO ATUAL no LIVE (gravado pela v3.1 defeituosa):
--       UUID .................................................. 1.026
--       JSON null .............................................    616
--       AUSENTE ...............................................      0
--
--   ESTADO CORRETO (eixo resolvido com escopo canonico):
--       UUID .................................................. 1.092
--       JSON null .............................................    550
--       AUSENTE ...............................................      0
--
--   DELTA .................................... exatamente 66, TODOS NULL->UUID
--       UUID -> UUID diferente ................................      0
--       UUID -> NULL ..........................................      0
--       qualquer -> AUSENTE ...................................      0
--
--   AUSENTE = 0 e comportamento CORRETO da 2211, nao defeito: token
--   desconhecido e fail-closed e permanece no residual de Finish, produzindo
--   cardinality(v_ec_sig)=0 -> RESOLVED_NO_EDITION_CONTEXT. NEEDS_REVIEW_* so
--   ocorre para token CONHECIDO-mas-inativo ou perfil ausente.
--
--   AS 7 ROWS foil=LEAGUE + stamp=STAFF — NAO SAO DEFEITO (decisao fechada
--   por Fabricio). Elas permanecem INDETERMINATE pela pendencia do eixo de
--   ACABAMENTO (foil=league sem Variant Type), mas o eixo de CONTEXTO DE
--   EDICAO resolve legitimamente stamp=STAFF -> perfil de papel STAFF. Esta
--   Query PRESERVA o perfil delas byte a byte e prova que nenhuma das 7 esta
--   entre as 66. Os dois eixos sao independentes: indeterminacao no Finish
--   nao invalida resolucao no Edition Context.
--
-- ============================================================================
-- 5. DISCIPLINA DE EXECUCAO
-- ============================================================================
--   * Transacao unica. QUALQUER gate que falhar levanta excecao NOMEADA e
--     desfaz a transacao inteira — nao existe estado parcial.
--   * Todos os gates numericos sao PRE-WRITE. A escrita so acontece depois de
--     o plano inteiro ter sido provado contra o contrato da Secao 4.
--   * Os numeros da Secao 4 estao HARD-CODED de proposito nesta Query, e
--     apenas nela. Sao o contrato aprovado; divergencia significa que o LIVE
--     mudou desde a aprovacao (FREEZE violado) ou que a premissa estava
--     errada. Nos dois casos a resposta correta e PARAR, nunca adaptar.
--     Isso NAO contraria a Correcao 7 da 2212 ("sem cardinalidade hard-coded"):
--     la o objetivo era um backfill generico; aqui e um reparo pontual de um
--     conjunto JA MEDIDO, e a cardinalidade fixa e a propria prova.
--
-- PRE-CONDICOES:
--   2210, 2211, 2230/2231/2232, 2208, 2212 (v3.1) ja aplicadas.
--   FREEZE operacional vigente.
--
-- POS-EXECUCAO: rodar 2832 e 2833. So entao o Batch 6 fecha.
-- ============================================================================

BEGIN;

-- ---------------------------------------------------------------- PASSO 0 ---
-- PREFLIGHT DE REFERENCIAS + rp_params DETERMINISTICO.
-- Mesmo padrao da 2212 v3.1 e das seeds 2230/2231/2232: resolver por CODE,
-- exigir EXATAMENTE UM, nenhum UUID no arquivo.
DO $$
DECLARE v_game INT; v_src INT;
BEGIN
    SELECT COUNT(*) INTO v_game FROM public.game WHERE code = 'POKEMON';
    IF v_game <> 1 THEN
        RAISE EXCEPTION 'RP_GAME_REFERENCE: esperado EXATAMENTE 1 game com code=''POKEMON'', encontrado %.', v_game;
    END IF;

    SELECT COUNT(*) INTO v_src FROM public.asset_source WHERE code = 'TCGDEX';
    IF v_src <> 1 THEN
        RAISE EXCEPTION 'RP_SOURCE_REFERENCE: esperado EXATAMENTE 1 asset_source com code=''TCGDEX'', encontrado %.', v_src;
    END IF;
END $$;

CREATE TEMP TABLE rp_params ON COMMIT DROP AS
SELECT (SELECT g.id FROM public.game         g WHERE g.code = 'POKEMON') AS game_id,
       (SELECT s.id FROM public.asset_source s WHERE s.code = 'TCGDEX')  AS asset_source_id;

DO $$
DECLARE v_n INT;
BEGIN
    SELECT COUNT(*) INTO v_n FROM rp_params;
    IF v_n <> 1 THEN
        RAISE EXCEPTION 'RP_PARAMS_CARDINALITY: rp_params deveria ter EXATAMENTE 1 linha, tem %.', v_n;
    END IF;
    IF EXISTS (SELECT 1 FROM rp_params WHERE game_id IS NULL OR asset_source_id IS NULL) THEN
        RAISE EXCEPTION 'RP_PARAMS_UNSET: rp_params resolveu NULL apesar do preflight.';
    END IF;
END $$;

-- ---------------------------------------------------------------- PASSO 1 ---
-- GATE DE DEPENDENCIAS. As DUAS funcoes do contrato precisam existir: o
-- routing (2211) e a AUTORIDADE DE ESCOPO (resolve_variant_mapping_scope).
-- A segunda e a correcao inteira desta Query — sem ela nao ha o que reparar.
DO $$
DECLARE v_t INT; v_p INT; v_m INT; v_scoped INT; v_led INT;
BEGIN
    -- ------------------------------------------------------------------
    -- PROVENANCE DO LEDGER (PUBLICATION-GATE-CORRECTION-01).
    --
    -- Ate aqui a Secao 2 do cabecalho DOCUMENTAVA a provenance — 2212 uma
    -- unica vez, 2214 ainda nao executada — mas nada a VERIFICAVA. Prosa nao
    -- e gate. Se o LIVE divergir do que o cabecalho afirma, o reparo estaria
    -- operando sobre um mundo diferente do que a premissa descreve, e os
    -- gates numericos seguintes (1026/616/0, delta 66) poderiam ate passar
    -- por coincidencia sobre um estado de origem distinta.
    --
    -- Duas assercoes, ambas fail-closed, ambas ANTES de qualquer write.
    -- ------------------------------------------------------------------

    -- LEDGER-1 — a 2212 rodou EXATAMENTE 1x, e essa 1x foi a versao
    -- registrada. Sao DUAS condicoes, e uma nao implica a outra.
    --
    -- CORRECAO (PUBLICATION-GATE-CORRECTION-02). A versao anterior media
    -- apenas o par (version, name) e exigia = 1. Isso prova que a combinacao
    -- exata ocorreu uma vez, mas NAO prova unicidade da migration: uma
    -- SEGUNDA entrada com o MESMO name e OUTRA version — reexecucao
    -- reetiquetada, replay, aplicacao manual — passaria em silencio, que e
    -- exatamente o defeito que este gate existe para pegar.
    --
    -- 1a) CARDINALIDADE POR NAME. O universo e o name, nao o par. Aqui se
    --     prova "executada exatamente uma vez", qualquer que seja a version.
    SELECT COUNT(*) INTO v_led
      FROM supabase_migrations.schema_migrations m
     WHERE m.name = '2212_backfill_staging_edition_context_key';
    IF v_led <> 1 THEN
        RAISE EXCEPTION 'RP_LEDGER_2212_CARDINALITY: esperada EXATAMENTE 1 entrada no ledger com name=''2212_backfill_staging_edition_context_key'' (qualquer version); encontradas %. 0 = nao executada; >1 = executada mais de uma vez, violando o contrato de rollout de 1x. PARAR.', v_led;
    END IF;

    -- 1b) IDENTIDADE DA VERSION. Provada a unicidade, resta provar que a
    --     unica entrada e a versao que o contrato nomeia. Se for outra, o
    --     estado 1026/616/0 tem origem diferente da premissa deste reparo.
    SELECT COUNT(*) INTO v_led
      FROM supabase_migrations.schema_migrations m
     WHERE m.version = '20260920172947'
       AND m.name    = '2212_backfill_staging_edition_context_key';
    IF v_led <> 1 THEN
        RAISE EXCEPTION 'RP_LEDGER_2212_PROVENANCE: a unica entrada de ''2212_backfill_staging_edition_context_key'' NAO tem version=''20260920172947'' (encontradas % com esse par). A provenance do estado LIVE nao confere com a premissa deste reparo. PARAR.', v_led;
    END IF;

    -- LEDGER-2 — a 2214 NAO rodou. Redundante por desenho com
    -- RP_GUARD_ALREADY_PROMOTED (que inspeciona o prosrc do guard), e isso e
    -- deliberado: uma evidencia e o REGISTRO da execucao, a outra e o EFEITO
    -- dela no objeto. Se as duas discordarem, o ledger e o objeto estao
    -- fora de sincronia — condicao que tambem merece PARAR.
    SELECT COUNT(*) INTO v_led
      FROM supabase_migrations.schema_migrations m
     WHERE m.name = '2214_promote_valid_requires_edition_context_key';
    IF v_led <> 0 THEN
        RAISE EXCEPTION 'RP_LEDGER_2214_ALREADY_RUN: encontradas % entradas no ledger para ''2214_promote_valid_requires_edition_context_key''; esperado ZERO. O guard ESTRITO (Batch 8-BIS) ja foi promovido e este reparo do Batch 6 esta fora de ordem. PARAR.', v_led;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                    WHERE n.nspname='internal' AND p.proname='resolve_variant_row_axes') THEN
        RAISE EXCEPTION 'RP_ROUTING_MISSING: internal.resolve_variant_row_axes() ausente. Rode a Query 2211 antes.';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                    WHERE n.nspname='internal' AND p.proname='resolve_variant_mapping_scope') THEN
        RAISE EXCEPTION 'RP_SCOPE_AUTHORITY_MISSING: internal.resolve_variant_mapping_scope() ausente. E a autoridade canonica de external_set_id; sem ela esta Query nao tem como reparar nada.';
    END IF;

    -- INDICE DE IDENTIDADE: precisa existir E estar VALIDO. O UPDATE altera
    -- edition_context_profile_id, que participa da expressao
    -- internal.axis_identity_token(normalized_data, 'edition_context_profile_id')
    -- dentro de uq_cvir_row_identity. Escrever contra indice INVALIDO
    -- corromperia a identidade de staging em silencio.
    IF NOT EXISTS (
        SELECT 1 FROM pg_index i
          JOIN pg_class c ON c.oid = i.indexrelid
          JOIN pg_namespace n ON n.oid = c.relnamespace
         WHERE n.nspname = 'public' AND c.relname = 'uq_cvir_row_identity'
           AND i.indisvalid AND i.indisready
    ) THEN
        RAISE EXCEPTION 'RP_IDENTITY_INDEX_MISSING: uq_cvir_row_identity ausente ou INVALIDO. Rode a Query 2210 antes; escrever sem ele corrompe a identidade de staging.';
    END IF;

    -- ------------------------------------------------------------------
    -- GUARD: precisa existir, e precisa estar no ESTAGIO 1 (PERMISSIVO).
    --
    -- CORRECAO (AUDIT-CORRECTION-02). A versao anterior deste gate testava
    -- `prosrc LIKE '%edition_context_profile_id%'` e concluia "2214 promovida".
    -- Isso e SEMANTICAMENTE ERRADO: o guard PERMISSIVO da 2210 JA cita
    -- edition_context_profile_id em quatro lugares — jsonb_typeof, checagem de
    -- shape ('null' | 'string'), validacao de formato UUID, e as mensagens
    -- CVIR_SHAPE_INVALID_EDITION_CONTEXT. A presenca do NOME nao distingue
    -- nada, e o gate reprovaria o estado CORRETO.
    --
    -- A diferenca real entre os dois estagios NAO e conhecer o eixo, e sim
    -- EXIGIR a chave:
    --
    --   2210 PERMISSIVO  conhece e valida a FORMA de edition_context_profile_id;
    --                    NAO exige a presenca da chave para VALID. O bloco
    --                    `IF NEW.validation_status = 'VALID'` cobra apenas
    --                    variant_type_id e printing_profile_id.
    --
    --   2214 PROMOVIDO   acrescenta a EXIGENCIA OPERACIONAL da chave, com a
    --                    regra nomeada
    --                    CVIR_OPERATIONAL_VALID_REQUIRES_EDITION_CONTEXT_KEY
    --                    (e, junto, CVIR_EDITION_CONTEXT_KEY_REMOVAL_FORBIDDEN).
    --
    -- O discriminante correto e, portanto, a REGRA PROMOVIDA — um identificador
    -- que so existe na 2214 e em nenhuma outra versao do guard. E evidencia
    -- especifica, nao heuristica de substring generica.
    -- ------------------------------------------------------------------
    IF NOT EXISTS (
        SELECT 1 FROM pg_trigger
         WHERE tgrelid = 'public.catalog_variant_import_row'::REGCLASS
           AND tgname = 'trg_cvir_normalized_shape'
           AND NOT tgisinternal
    ) THEN
        RAISE EXCEPTION 'RP_GUARD_MISSING: trigger trg_cvir_normalized_shape ausente. Rode a Query 2210 antes.';
    END IF;

    -- FAIL-CLOSED em duas metades, para nao depender de uma so evidencia.

    -- (a) A REGRA PROMOVIDA nao pode estar presente. Se estiver, a 2214 ja foi
    --     aplicada e este reparo esta fora de ordem: com o guard estrito, a
    --     premissa (66 rows operacionais VALID/PENDING com a chave em JSON
    --     null sendo corrigidas antes do guard) nao e mais o estado do mundo.
    IF EXISTS (
        SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'internal' AND p.proname = 'guard_cvir_normalized_shape'
           AND p.prosrc LIKE '%CVIR_OPERATIONAL_VALID_REQUIRES_EDITION_CONTEXT_KEY%'
    ) THEN
        RAISE EXCEPTION 'RP_GUARD_ALREADY_PROMOTED: guard_cvir_normalized_shape contem CVIR_OPERATIONAL_VALID_REQUIRES_EDITION_CONTEXT_KEY — a Query 2214 (guard ESTRITO, Batch 8-BIS) ja foi promovida. Este reparo pertence ao Batch 6 e pressupoe o estagio PERMISSIVO da 2210. PARAR e reavaliar a ordem de rollout.';
    END IF;

    -- (b) O guard tem de ser reconhecivel como o da 2210: conhece o eixo
    --     (valida a FORMA) e cobra o eixo de Impressao para VALID. Ausencia
    --     disso significa que o objeto em producao nao e nem o permissivo nem
    --     o promovido — versao desconhecida, e fail-closed e PARAR.
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'internal' AND p.proname = 'guard_cvir_normalized_shape'
           AND p.prosrc LIKE '%CVIR_SHAPE_INVALID_EDITION_CONTEXT%'
           AND p.prosrc LIKE '%CVIR_VALID_REQUIRES_PRINTING_KEY%'
    ) THEN
        RAISE EXCEPTION 'RP_GUARD_UNRECOGNIZED: guard_cvir_normalized_shape nao apresenta as marcas do estagio PERMISSIVO da 2210 (CVIR_SHAPE_INVALID_EDITION_CONTEXT + CVIR_VALID_REQUIRES_PRINTING_KEY). Versao desconhecida do guard — PARAR.';
    END IF;

    -- DOIS TRIGGERS BEFORE da Query 2139 — precisam existir, porque o contrato
    -- de escrita desta Query depende do comportamento dos dois (ver Secao 3-BIS).
    IF NOT EXISTS (
        SELECT 1 FROM pg_trigger
         WHERE tgrelid = 'public.catalog_variant_import_row'::REGCLASS
           AND tgname = 'trg_catalog_variant_import_row_set_updated_at'
           AND NOT tgisinternal
    ) THEN
        RAISE EXCEPTION 'RP_UPDATED_AT_TRIGGER_MISSING: trg_catalog_variant_import_row_set_updated_at ausente. O contrato desta Query prova updated_at explicitamente e depende dele.';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_trigger
         WHERE tgrelid = 'public.catalog_variant_import_row'::REGCLASS
           AND tgname = 'trg_catalog_variant_import_row_normalize'
           AND NOT tgisinternal
    ) THEN
        RAISE EXCEPTION 'RP_NORMALIZE_TRIGGER_MISSING: trg_catalog_variant_import_row_normalize ausente.';
    END IF;

    SELECT COUNT(*) INTO v_t FROM public.card_edition_context_trait;
    SELECT COUNT(*) INTO v_p FROM public.card_edition_context_profile WHERE traits_signature IS NOT NULL;
    SELECT COUNT(*) INTO v_m FROM public.card_edition_context_external_mapping WHERE is_active;
    IF v_t = 0 OR v_p = 0 OR v_m = 0 THEN
        RAISE EXCEPTION 'RP_VOCABULARY_MISSING: traits=% profiles=% mappings=%. Rode 2230/2231/2232 antes.', v_t, v_p, v_m;
    END IF;

    -- Os 14 SCOPED sao o alvo do reparo. Se nao existirem, o defeito descrito
    -- nao e o que esta acontecendo e a premissa desta Query esta errada.
    SELECT COUNT(*) INTO v_scoped
      FROM public.card_edition_context_external_mapping
     WHERE is_active AND external_set_id IS NOT NULL;
    IF v_scoped <> 14 THEN
        RAISE EXCEPTION 'RP_SCOPED_MAPPINGS_BASELINE: esperados 14 mappings ATIVOS SOURCE_SET_SCOPED, encontrados %. O vocabulario divergiu do baseline aprovado.', v_scoped;
    END IF;
END $$;

-- ---------------------------------------------------------------- PASSO 2 ---
-- SNAPSHOT INTEGRAL (para a prova de historico intocado) + UNIVERSO.
--
-- ATENCAO A DIFERENCA PARA A 2212: la o universo era "job vivo + PENDING +
-- SEM a chave". Aqui a chave JA EXISTE em todas — foi a v3.1 que a gravou.
-- O universo e, portanto, "job vivo + PENDING", e o PASSO 3 exige que TODAS
-- tenham a chave (se alguma nao tiver, o estado do LIVE nao e o que o
-- contrato descreve e a Query para).
-- SNAPSHOT INTEGRAL — TODAS as colunas de negocio, mais created_at e
-- updated_at. updated_at entra de proposito: e a unica coluna, alem de
-- normalized_data, que o UPDATE pode alterar (via trg_..._set_updated_at), e a
-- prova precisa trata-la EXPLICITAMENTE, nunca ignora-la em silencio.
CREATE TEMP TABLE rp_all_before ON COMMIT DROP AS
SELECT r.id, r.job_id, r.card_id,
       r.raw_data, r.normalized_data,
       r.validation_status, r.match_status,
       r.decision_status, r.persistence_status,
       r.matched_variant_id, r.resulting_variant_id,
       r.error_detail,
       r.created_at, r.updated_at
  FROM public.catalog_variant_import_row r;

CREATE TEMP TABLE rp_operational ON COMMIT DROP AS
SELECT r.id, r.job_id, r.card_id, r.raw_data, r.normalized_data,
       r.validation_status, r.decision_status, r.persistence_status,
       j.status AS job_status,
       CASE
           WHEN NOT jsonb_exists(r.normalized_data, 'edition_context_profile_id') THEN 'ABSENT'
           WHEN jsonb_typeof(r.normalized_data -> 'edition_context_profile_id') = 'null' THEN 'NULL'
           ELSE 'UUID'
       END AS estado_atual,
       CASE
           WHEN jsonb_typeof(r.normalized_data -> 'edition_context_profile_id') = 'string'
           THEN (r.normalized_data ->> 'edition_context_profile_id')::UUID
           ELSE NULL::UUID
       END AS profile_atual
  FROM public.catalog_variant_import_row r
  JOIN public.catalog_variant_import_job j ON j.id = r.job_id
 WHERE j.status IN ('RECEIVED','PROCESSING','STAGED','CONFIRMING')
   AND r.persistence_status = 'PENDING';

-- Baseline de CANCELLED capturado ANTES de qualquer escrita, para a prova de
-- preservacao do Batch 3 (B3.2).
CREATE TEMP TABLE rp_cancelled_before ON COMMIT DROP AS
SELECT COUNT(*) AS total,
       COUNT(*) FILTER (WHERE r.validation_status = 'VALID'
                          AND r.persistence_status = 'PENDING') AS valid_pending
  FROM public.catalog_variant_import_row r
  JOIN public.catalog_variant_import_job j ON j.id = r.job_id
 WHERE j.status = 'CANCELLED';

-- ---------------------------------------------------------------- PASSO 3 ---
-- PLANO. O eixo e RECALCULADO com o ESCOPO CANONICO.
--
-- Este e o unico ponto em que esta Query difere funcionalmente da 2212 v3.1:
-- o 4o argumento vem de internal.resolve_variant_mapping_scope(), nunca de
-- card_set.code. LEFT JOIN LATERAL: Card Set sem referencia ATIVA devolve
-- NULL, que a 2211 interpreta como "sem escopo" e restringe o universo aos
-- mappings GLOBAL — fail-closed, nunca vazamento cross-set.
CREATE TEMP TABLE rp_plan ON COMMIT DROP AS
SELECT o.id,
       o.estado_atual,
       o.profile_atual,
       sc.external_set_id AS escopo_canonico,
       ax.edition_context_state,
       ax.edition_context_profile_id AS profile_correto,
       ax.residual_foil,
       ax.residual_stamp,
       CASE ax.edition_context_state
           WHEN 'RESOLVED_WITH_EC_PROFILE'    THEN 'UUID'
           WHEN 'RESOLVED_NO_EDITION_CONTEXT' THEN 'NULL'
           ELSE                                    'ABSENT'
       END AS estado_correto
  FROM rp_operational o
  JOIN public.card c ON c.id = o.card_id
  CROSS JOIN rp_params pr
  LEFT JOIN LATERAL internal.resolve_variant_mapping_scope(
       c.card_set_id, pr.asset_source_id) sc ON TRUE
  CROSS JOIN LATERAL internal.resolve_variant_row_axes(
       o.raw_data, pr.game_id, pr.asset_source_id, sc.external_set_id) ax;

-- Coerencia interna do plano, antes de qualquer contagem.
DO $$
DECLARE v_bad INT;
BEGIN
    SELECT COUNT(*) INTO v_bad FROM rp_plan
     WHERE (estado_correto =  'UUID' AND profile_correto IS NULL)
        OR (estado_correto <> 'UUID' AND profile_correto IS NOT NULL);
    IF v_bad <> 0 THEN
        RAISE EXCEPTION 'RP_PLAN_INCOHERENT: % rows com estado_correto incompativel com profile_correto.', v_bad;
    END IF;
END $$;

-- As 66 rows a reparar. Definidas EXCLUSIVAMENTE por divergencia real.
-- ESTE E O CONJUNTO DE IDS CONGELADO ANTES DA ESCRITA: o PASSO 6 prova que
-- EXATAMENTE estes ids foram atualizados e que nenhum outro foi.
CREATE TEMP TABLE rp_delta ON COMMIT DROP AS
SELECT p.*
  FROM rp_plan p
 WHERE p.estado_atual IS DISTINCT FROM p.estado_correto
    OR p.profile_atual IS DISTINCT FROM p.profile_correto;

-- As 7 rows foil=LEAGUE + stamp=STAFF, identificadas ESTRUTURALMENTE pelo
-- raw_data — sem hard-code de codigo de perfil, para que o gate teste a
-- realidade e nao a minha lembranca dela.
CREATE TEMP TABLE rp_league_staff ON COMMIT DROP AS
SELECT p.*
  FROM rp_plan p
  JOIN rp_operational o ON o.id = p.id
 -- CAIXA (G8-NORMALIZATION-CORRECTION-01): public.normalize_external_catalog_value()
 -- devolve o dominio normalizado em MAIUSCULAS. A versao anterior comparava
 -- contra 'league'/'staff' minusculos — predicado insatisfazivel por
 -- construcao, que media 0 para qualquer dado e fez o RP_G8 abortar no LIVE.
 -- Probes read-only no universo operacional: foil='LEAGUE' -> 53 rows;
 -- stamp contendo 'STAFF' -> 46 rows; combinado -> 7 (o contrato).
 -- `'array'` e `'null'`/`'string'` seguem MINUSCULOS de proposito: sao
 -- retornos de jsonb_typeof(), nao da funcao de normalizacao.
 WHERE public.normalize_external_catalog_value(o.raw_data ->> 'foil') = 'LEAGUE'
   AND jsonb_typeof(o.raw_data -> 'stamp') = 'array'
   AND EXISTS (SELECT 1 FROM jsonb_array_elements_text(o.raw_data -> 'stamp') e
                WHERE public.normalize_external_catalog_value(e) = 'STAFF');

-- ---------------------------------------------------------------- PASSO 4 ---
-- GATES PRE-WRITE. NADA e escrito antes de todos passarem.
DO $$
DECLARE
    v_total INT; v_a_uuid INT; v_a_null INT; v_a_absent INT;
    v_c_uuid INT; v_c_null INT; v_c_absent INT;
    v_delta INT; v_n INT;
    v_canc_total INT; v_canc_vp INT;
BEGIN
    -- G1 — CARDINALIDADE DO UNIVERSO. Preserva o baseline do Batch 3.
    SELECT COUNT(*) INTO v_total FROM rp_operational;
    IF v_total <> 1642 THEN
        RAISE EXCEPTION 'RP_G1_UNIVERSE: universo operacional deveria ser 1642 rows, e %. O baseline do Batch 3 mudou — FREEZE violado ou premissa errada. PARAR.', v_total;
    END IF;

    -- G2 — TODAS ja tem a chave. Se alguma nao tiver, a 2212 v3.1 nao produziu
    -- o estado que este reparo pressupoe.
    SELECT COUNT(*) INTO v_n FROM rp_operational WHERE estado_atual = 'ABSENT';
    IF v_n <> 0 THEN
        RAISE EXCEPTION 'RP_G2_KEY_MISSING: % rows operacionais SEM a chave edition_context_profile_id. A 2212 deveria te-la gravado em todas. PARAR.', v_n;
    END IF;

    -- G3 — ESTADO ATUAL exato: 1026 / 616 / 0.
    SELECT COUNT(*) FILTER (WHERE estado_atual='UUID'),
           COUNT(*) FILTER (WHERE estado_atual='NULL'),
           COUNT(*) FILTER (WHERE estado_atual='ABSENT')
      INTO v_a_uuid, v_a_null, v_a_absent
      FROM rp_operational;
    IF v_a_uuid <> 1026 OR v_a_null <> 616 OR v_a_absent <> 0 THEN
        RAISE EXCEPTION 'RP_G3_CURRENT_STATE: estado atual medido UUID=% NULL=% ABSENT=%; contrato aprovado 1026/616/0. PARAR.', v_a_uuid, v_a_null, v_a_absent;
    END IF;

    -- G4 — ESTADO CORRETO exato: 1092 / 550 / 0.
    SELECT COUNT(*) FILTER (WHERE estado_correto='UUID'),
           COUNT(*) FILTER (WHERE estado_correto='NULL'),
           COUNT(*) FILTER (WHERE estado_correto='ABSENT')
      INTO v_c_uuid, v_c_null, v_c_absent
      FROM rp_plan;
    IF v_c_uuid <> 1092 OR v_c_null <> 550 OR v_c_absent <> 0 THEN
        RAISE EXCEPTION 'RP_G4_TARGET_STATE: estado correto calculado UUID=% NULL=% ABSENT=%; contrato aprovado 1092/550/0. PARAR.', v_c_uuid, v_c_null, v_c_absent;
    END IF;

    -- G5 — DELTA = exatamente 66.
    SELECT COUNT(*) INTO v_delta FROM rp_delta;
    IF v_delta <> 66 THEN
        RAISE EXCEPTION 'RP_G5_DELTA_SIZE: delta de % rows; contrato aprovado 66. PARAR.', v_delta;
    END IF;

    -- G6 — DIRECAO DO DELTA: TODOS NULL -> UUID. Nenhuma outra transicao.
    SELECT COUNT(*) INTO v_n FROM rp_delta
     WHERE NOT (estado_atual = 'NULL' AND estado_correto = 'UUID');
    IF v_n <> 0 THEN
        RAISE EXCEPTION 'RP_G6_DELTA_DIRECTION: % rows do delta NAO sao NULL->UUID. Este reparo so esta autorizado a preencher contexto que a v3.1 perdeu por escopo, nunca a reinterpretar contexto ja resolvido. PARAR.', v_n;
    END IF;

    -- G6b — provas negativas explicitas das transicoes proibidas, para que o
    -- relatorio de execucao registre CADA uma como zero, e nao so a agregada.
    SELECT COUNT(*) INTO v_n FROM rp_plan
     WHERE estado_atual='UUID' AND estado_correto='UUID'
       AND profile_atual IS DISTINCT FROM profile_correto;
    IF v_n <> 0 THEN
        RAISE EXCEPTION 'RP_G6B_UUID_REINTERPRET: % rows teriam o perfil TROCADO por outro. PARAR.', v_n;
    END IF;

    SELECT COUNT(*) INTO v_n FROM rp_plan
     WHERE estado_atual='UUID' AND estado_correto IN ('NULL','ABSENT');
    IF v_n <> 0 THEN
        RAISE EXCEPTION 'RP_G6C_UUID_LOST: % rows perderiam contexto ja resolvido. PARAR.', v_n;
    END IF;

    SELECT COUNT(*) INTO v_n FROM rp_plan WHERE estado_correto = 'ABSENT';
    IF v_n <> 0 THEN
        RAISE EXCEPTION 'RP_G6D_TO_ABSENT: % rows cairiam para INDETERMINADO. PARAR.', v_n;
    END IF;

    -- G7 — AS 66 VEM DO ESCOPO. Cada uma tem escopo canonico resolvido, e esse
    -- escopo e de fato um dos external_set_id dos mappings SCOPED ATIVOS. Esta
    -- e a prova de que a causa reparada e a causa diagnosticada.
    SELECT COUNT(*) INTO v_n FROM rp_delta WHERE escopo_canonico IS NULL;
    IF v_n <> 0 THEN
        RAISE EXCEPTION 'RP_G7_SCOPE_NULL: % rows do delta sem escopo canonico. Se o escopo e NULL, o universo e so GLOBAL e a v3.1 teria acertado — a causa seria OUTRA. PARAR.', v_n;
    END IF;

    SELECT COUNT(*) INTO v_n
      FROM rp_delta d
     WHERE NOT EXISTS (
        SELECT 1 FROM public.card_edition_context_external_mapping m
         WHERE m.is_active AND m.external_set_id = d.escopo_canonico);
    IF v_n <> 0 THEN
        RAISE EXCEPTION 'RP_G7B_SCOPE_UNMAPPED: % rows do delta com escopo que nao corresponde a nenhum mapping SCOPED ativo. PARAR.', v_n;
    END IF;

    -- G8 — AS 7 LEAGUE+STAFF. Decisao fechada: NAO sao defeito. O gate prova
    -- que permanecem exatamente como estao.
    SELECT COUNT(*) INTO v_n FROM rp_league_staff;
    IF v_n <> 7 THEN
        RAISE EXCEPTION 'RP_G8_LEAGUE_STAFF_COUNT: esperadas 7 rows foil=LEAGUE + stamp=STAFF, encontradas %. PARAR.', v_n;
    END IF;

    SELECT COUNT(*) INTO v_n FROM rp_league_staff WHERE estado_atual <> 'UUID';
    IF v_n <> 0 THEN
        RAISE EXCEPTION 'RP_G8B_LEAGUE_STAFF_NOT_UUID: % das 7 rows nao estao em UUID hoje. O contrato aprovado afirma que o eixo ja as resolvia. PARAR.', v_n;
    END IF;

    SELECT COUNT(*) INTO v_n FROM rp_league_staff
     WHERE estado_correto <> 'UUID' OR profile_correto IS DISTINCT FROM profile_atual;
    IF v_n <> 0 THEN
        RAISE EXCEPTION 'RP_G8C_LEAGUE_STAFF_CHANGED: % das 7 rows teriam o perfil alterado. Decisao fechada: preservar. PARAR.', v_n;
    END IF;

    SELECT COUNT(*) INTO v_n FROM rp_league_staff l
     WHERE EXISTS (SELECT 1 FROM rp_delta d WHERE d.id = l.id);
    IF v_n <> 0 THEN
        RAISE EXCEPTION 'RP_G8D_LEAGUE_STAFF_IN_DELTA: % das 7 rows estao entre as 66. Nao deveriam estar. PARAR.', v_n;
    END IF;

    -- G8e — o residual de ACABAMENTO das 7 continua carregando o foil pendente.
    -- E o que mantem a linha INDETERMINATE no eixo de Finish, que e o estado
    -- correto e NAO deve ser mascarado por esta Query.
    -- CAIXA (G8-NORMALIZATION-CORRECTION-01): residual_foil chega do routing
    -- ja normalizado em MAIUSCULAS. Probe read-only nas 7 rows: 7/7 com
    -- residual_foil = 'LEAGUE', 0 com 'league'.
    SELECT COUNT(*) INTO v_n FROM rp_league_staff
     WHERE residual_foil IS DISTINCT FROM 'LEAGUE';
    IF v_n <> 0 THEN
        RAISE EXCEPTION 'RP_G8E_LEAGUE_RESIDUAL: % das 7 rows perderam o foil pendente do residual de acabamento. PARAR.', v_n;
    END IF;

    -- G9 — NENHUMA ROW HISTORICA NO PLANO. Por construcao do universo, mas
    -- provado explicitamente.
    SELECT COUNT(*) INTO v_n
      FROM rp_plan p
      JOIN public.catalog_variant_import_row r ON r.id = p.id
      JOIN public.catalog_variant_import_job j ON j.id = r.job_id
     WHERE j.status NOT IN ('RECEIVED','PROCESSING','STAGED','CONFIRMING')
        OR r.persistence_status <> 'PENDING';
    IF v_n <> 0 THEN
        RAISE EXCEPTION 'RP_G9_HISTORY_IN_PLAN: % rows historicas entraram no plano. PARAR.', v_n;
    END IF;

    -- G10 — BASELINE CANCELLED (B3.2) intacto ANTES da escrita.
    SELECT total, valid_pending INTO v_canc_total, v_canc_vp FROM rp_cancelled_before;
    IF v_canc_total <> 847 OR v_canc_vp <> 415 THEN
        RAISE EXCEPTION 'RP_G10_CANCELLED_BASELINE: CANCELLED medido total=% valid_pending=%; baseline B3.2 aprovado 847/415. PARAR.', v_canc_total, v_canc_vp;
    END IF;

    RAISE NOTICE 'GATES PRE-WRITE OK. Universo=% | atual %/%/% -> correto %/%/% | delta=% (todos NULL->UUID) | 7 LEAGUE+STAFF preservadas | CANCELLED %/% intacto.',
        v_total, v_a_uuid, v_a_null, v_a_absent, v_c_uuid, v_c_null, v_c_absent, v_delta, v_canc_total, v_canc_vp;
END $$;

-- ---------------------------------------------------------------- PASSO 5 ---
-- ESCRITA. SOMENTE as 66 rows do delta, somente a chave
-- edition_context_profile_id, somente de JSON null para UUID.
--
-- O predicado repete `estado_atual='NULL' AND estado_correto='UUID'` mesmo
-- sendo redundante apos o G6: se algum dia o gate for afrouxado, o UPDATE
-- continua incapaz de fazer qualquer outra transicao.
UPDATE public.catalog_variant_import_row r
   SET normalized_data = r.normalized_data
                       || jsonb_build_object('edition_context_profile_id', d.profile_correto)
  FROM rp_delta d
 WHERE d.id = r.id
   AND d.estado_atual = 'NULL'
   AND d.estado_correto = 'UUID';

-- NOTA DELIBERADA sobre a contagem de linhas escritas: NAO ha bloco
-- GET DIAGNOSTICS aqui. Em PL/pgSQL, GET DIAGNOSTICS dentro de um bloco DO
-- posterior leria o ROW_COUNT do proprio bloco, nao o do UPDATE acima — seria
-- um numero sempre correto e sempre irrelevante, exatamente o tipo de prova
-- falsa que este pacote vem evitando. A contagem REAL e provada no PASSO 6,
-- que compara o estado GRAVADO contra o plano (P1) e contra o snapshot
-- integral (P2/P3).

-- ---------------------------------------------------------------- PASSO 6 ---
-- POSTCHECK INTEGRAL. Qualquer divergencia desfaz a transacao inteira.
DO $$
DECLARE
    v_n INT; v_uuid INT; v_null INT; v_absent INT;
    v_canc_total INT; v_canc_vp INT;
BEGIN
    -- P1 — as 66 gravaram EXATAMENTE o perfil planejado.
    SELECT COUNT(*) INTO v_n
      FROM rp_delta d JOIN public.catalog_variant_import_row r ON r.id = d.id
     WHERE (r.normalized_data ->> 'edition_context_profile_id') IS DISTINCT FROM d.profile_correto::TEXT;
    IF v_n <> 0 THEN
        RAISE EXCEPTION 'RP_P1_FAIL: % das 66 rows com UUID divergente do plano.', v_n;
    END IF;

    -- P1B — CONJUNTO ATUALIZADO == CONJUNTO PLANEJADO, pelos DOIS lados.
    -- A identificacao do que foi de fato tocado usa updated_at: e a assinatura
    -- deixada pelo trigger, e a unica evidencia fisica de escrita disponivel.
    SELECT COUNT(*) INTO v_n
      FROM rp_all_before b JOIN public.catalog_variant_import_row r ON r.id = b.id
     WHERE r.updated_at IS DISTINCT FROM b.updated_at
       AND NOT EXISTS (SELECT 1 FROM rp_delta d WHERE d.id = b.id);
    IF v_n <> 0 THEN
        RAISE EXCEPTION 'RP_P1B_FAIL: % rows FORA do delta foram atualizadas (updated_at mudou). Escrita vazou do conjunto planejado.', v_n;
    END IF;

    SELECT COUNT(*) INTO v_n
      FROM rp_delta d
      JOIN rp_all_before b ON b.id = d.id
      JOIN public.catalog_variant_import_row r ON r.id = d.id
     WHERE r.updated_at IS NOT DISTINCT FROM b.updated_at;
    IF v_n <> 0 THEN
        RAISE EXCEPTION 'RP_P1C_FAIL: % das 66 rows planejadas NAO foram atualizadas (updated_at inalterado). Escrita incompleta.', v_n;
    END IF;

    -- P2 — normalized_data: nenhuma row FORA do delta mudou; e DENTRO do delta
    -- mudou SOMENTE a chave edition_context_profile_id. A prova de "somente"
    -- e por REMOCAO da chave nos dois lados: se o resto do objeto for igual
    -- apos remove-la, nenhuma outra chave foi tocada.
    SELECT COUNT(*) INTO v_n
      FROM rp_all_before b JOIN public.catalog_variant_import_row r ON r.id = b.id
     WHERE NOT EXISTS (SELECT 1 FROM rp_delta d WHERE d.id = b.id)
       AND r.normalized_data IS DISTINCT FROM b.normalized_data;
    IF v_n <> 0 THEN
        RAISE EXCEPTION 'RP_P2_FAIL: % rows fora do delta tiveram normalized_data alterado.', v_n;
    END IF;

    SELECT COUNT(*) INTO v_n
      FROM rp_delta d
      JOIN rp_all_before b ON b.id = d.id
      JOIN public.catalog_variant_import_row r ON r.id = d.id
     WHERE (r.normalized_data - 'edition_context_profile_id')
           IS DISTINCT FROM (b.normalized_data - 'edition_context_profile_id');
    IF v_n <> 0 THEN
        RAISE EXCEPTION 'RP_P2B_FAIL: % das 66 rows tiveram OUTRA chave de normalized_data alterada alem de edition_context_profile_id.', v_n;
    END IF;

    -- P3 — TODAS as colunas de negocio inalteradas, em TODAS as rows,
    -- delta incluido. `updated_at` esta DELIBERADAMENTE FORA desta lista: e a
    -- unica outra coluna autorizada a mudar, e ja foi tratada em P1B/P1C.
    -- `created_at` esta DENTRO: nada justifica que mude.
    --
    -- Os quatro status e error_detail entram aqui EXPLICITAMENTE por causa do
    -- trigger de NORMALIZACAO (trg_..._normalize). Ele e idempotente sobre
    -- dado ja normalizado, mas se alguma row tiver caixa/espaco divergente ele
    -- materializa a mudanca AGORA, sob o nome deste reparo. Isso e STOP.
    SELECT COUNT(*) INTO v_n
      FROM rp_all_before b JOIN public.catalog_variant_import_row r ON r.id = b.id
     WHERE r.raw_data             IS DISTINCT FROM b.raw_data
        OR r.validation_status    IS DISTINCT FROM b.validation_status
        OR r.match_status         IS DISTINCT FROM b.match_status
        OR r.decision_status      IS DISTINCT FROM b.decision_status
        OR r.persistence_status   IS DISTINCT FROM b.persistence_status
        OR r.error_detail         IS DISTINCT FROM b.error_detail
        OR r.matched_variant_id   IS DISTINCT FROM b.matched_variant_id
        OR r.resulting_variant_id IS DISTINCT FROM b.resulting_variant_id
        OR r.job_id               IS DISTINCT FROM b.job_id
        OR r.card_id              IS DISTINCT FROM b.card_id
        OR r.created_at           IS DISTINCT FROM b.created_at;
    IF v_n <> 0 THEN
        RAISE EXCEPTION 'RP_P3_FAIL: % rows com coluna de negocio alterada. Se forem status ou error_detail, o trigger de normalizacao produziu mudanca MATERIAL — investigar antes de qualquer nova tentativa.', v_n;
    END IF;

    -- P3B — updated_at: mudou SO nas 66, e para FRENTE. Contrato explicito, e
    -- nao uma omissao silenciosa.
    SELECT COUNT(*) INTO v_n
      FROM rp_delta d
      JOIN rp_all_before b ON b.id = d.id
      JOIN public.catalog_variant_import_row r ON r.id = d.id
     WHERE r.updated_at <= b.updated_at;
    IF v_n <> 0 THEN
        RAISE EXCEPTION 'RP_P3B_FAIL: % das 66 rows com updated_at que nao avancou. set_updated_at() nao se comportou como esperado.', v_n;
    END IF;

    -- P4 — nenhuma row sumiu nem apareceu.
    SELECT COUNT(*) INTO v_n FROM public.catalog_variant_import_row;
    IF v_n <> (SELECT COUNT(*) FROM rp_all_before) THEN
        RAISE EXCEPTION 'RP_P4_FAIL: cardinalidade total de catalog_variant_import_row mudou.';
    END IF;

    -- P5 — DISTRIBUICAO FINAL = 1092 / 550 / 0.
    SELECT COUNT(*) FILTER (WHERE NOT jsonb_exists(r.normalized_data,'edition_context_profile_id')),
           COUNT(*) FILTER (WHERE jsonb_typeof(r.normalized_data->'edition_context_profile_id')='null'),
           COUNT(*) FILTER (WHERE jsonb_typeof(r.normalized_data->'edition_context_profile_id')='string')
      INTO v_absent, v_null, v_uuid
      FROM public.catalog_variant_import_row r
      JOIN public.catalog_variant_import_job j ON j.id = r.job_id
     WHERE j.status IN ('RECEIVED','PROCESSING','STAGED','CONFIRMING')
       AND r.persistence_status = 'PENDING';
    IF v_uuid <> 1092 OR v_null <> 550 OR v_absent <> 0 THEN
        RAISE EXCEPTION 'RP_P5_FAIL: distribuicao final UUID=% NULL=% ABSENT=%; esperado 1092/550/0.', v_uuid, v_null, v_absent;
    END IF;

    -- P6 — as 7 LEAGUE+STAFF continuam com o MESMO perfil de antes.
    SELECT COUNT(*) INTO v_n
      FROM rp_league_staff l
      JOIN rp_all_before b ON b.id = l.id
      JOIN public.catalog_variant_import_row r ON r.id = l.id
     WHERE r.normalized_data -> 'edition_context_profile_id'
           IS DISTINCT FROM b.normalized_data -> 'edition_context_profile_id';
    IF v_n <> 0 THEN
        RAISE EXCEPTION 'RP_P6_FAIL: % das 7 rows LEAGUE+STAFF tiveram o perfil alterado.', v_n;
    END IF;

    -- P7 — BASELINE CANCELLED inalterado depois da escrita.
    SELECT COUNT(*),
           COUNT(*) FILTER (WHERE r.validation_status='VALID' AND r.persistence_status='PENDING')
      INTO v_canc_total, v_canc_vp
      FROM public.catalog_variant_import_row r
      JOIN public.catalog_variant_import_job j ON j.id = r.job_id
     WHERE j.status = 'CANCELLED';
    IF v_canc_total <> (SELECT total FROM rp_cancelled_before)
       OR v_canc_vp <> (SELECT valid_pending FROM rp_cancelled_before) THEN
        RAISE EXCEPTION 'RP_P7_FAIL: baseline CANCELLED mudou (%/% -> %/%).',
            (SELECT total FROM rp_cancelled_before), (SELECT valid_pending FROM rp_cancelled_before),
            v_canc_total, v_canc_vp;
    END IF;

    -- P8 — IDEMPOTENCIA. Recalcular o eixo agora nao produz mais nenhuma
    -- divergencia: o reparo e completo, nao parcial.
    SELECT COUNT(*) INTO v_n
      FROM rp_plan p JOIN public.catalog_variant_import_row r ON r.id = p.id
     WHERE (p.estado_correto = 'UUID'
            AND (r.normalized_data ->> 'edition_context_profile_id') IS DISTINCT FROM p.profile_correto::TEXT)
        OR (p.estado_correto = 'NULL'
            AND jsonb_typeof(r.normalized_data -> 'edition_context_profile_id') <> 'null');
    IF v_n <> 0 THEN
        RAISE EXCEPTION 'RP_P8_FAIL: % rows ainda divergem do eixo recalculado. Reparo incompleto.', v_n;
    END IF;

    RAISE NOTICE 'POSTCHECK OK. 66 rows reparadas NULL->UUID (exatamente os ids planejados, nenhum a mais). Colunas alteradas: normalized_data (so a chave edition_context_profile_id) e updated_at (efeito esperado do trigger). Universo operacional em 1092/550/0. Status, error_detail, lineage (matched/resulting_variant_id), raw_data, created_at, historico, CANCELLED e as 7 LEAGUE+STAFF intocados.';
END $$;

COMMIT;

-- ============================================================================
-- APOS O COMMIT
-- ============================================================================
--   1. Registrar a execucao no ledger de migrations.
--   2. Rodar 2832 (14 gates, BEGIN/ROLLBACK) — deve passar integralmente.
--   3. Rodar 2833 (auditoria da maquina de estados).
--   4. So entao o Batch 6 fecha. O FREEZE permanece ate o Batch 12.
-- ============================================================================
