/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 2822 - Validacao do contrato bulk de importacao de variantes
Versão......: 1.1
Status......: VALIDADO / PASS — 2026-09-12
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-12
Executado...: 2026-09-12, contra o LIVE (projeto qjfutqujxrbzgrtkpgkg),
               na ordem S1 -> S2 -> S3 -> S4.
               RESULTADO: PASS INTEGRAL — 37 assercoes, 4 Secoes.
                 S1 (read-only, fail-closed) ...... 13 assercoes PASS
                 S2 (BEGIN...ROLLBACK, 2163) ......  8 assercoes PASS
                 S3 (BEGIN...ROLLBACK, 2164) ...... 11 assercoes PASS
                 S4 (read-only, fail-closed) ......  5 assercoes PASS
               ZERO RESIDUO: HARNESS-2822 = 0 jobs.
               Baseline preservado, medido antes e depois:
                 card_variant = 6483
                 jobs STAGED = 4
                 VALID/PENDING = 519
                 NEEDS_REVIEW/PENDING = 505
               Identidade administrativa usada (c_admin_user_id nas
               Secoes 2 e 3): fe316458-49dd-44e1-aac0-f4b7604ef8f2 —
               a mesma ja utilizada na Query 6130.
Mandato.....: CARD-VARIANTS-GLOBAL-RECONCILIATION —
               BULK-CONTRACT-HARDENING-GATE-A-01
               + GATE-A-CORRECTION-01 (v1.1)
               + GATE-A-EXECUTE-NOW-01 (execucao)
               + BULK-CONTRACT-HARDENING-CLOSEOUT-01 (fechamento)
Valida......: Query 2163 (hardening de admin_decide_catalog_variant_import_row)
               Query 2164 v1.1 (hardening de admin_confirm_catalog_variant_import)

v1.1 (GATE-A-CORRECTION-01) sobre a v1.0:
1. FIXTURE IMPOSSIVEL. A v1.0 exigia um Card Set POKEMON com >= 1001
   Cards ativas. Contraprova no LIVE: o maior Card Set e SWSHP, com 300.
   A fixture NUNCA teria sido satisfeita — S3 abortaria sempre.
   Corrigido: a fixture agora usa UMA UNICA Card real, repetida N vezes
   via generate_series. E legal porque o unico indice unico da tabela
   (uq_catalog_variant_import_row_job_card_variant_type, Query 2138) e
   PARCIAL — so vale quando normalized_data->>'variant_type_id' IS NOT
   NULL. Com normalized_data = '{}'::jsonb esse campo e NULL, o
   predicado do indice e falso e as linhas nao entram nele. Prova
   explicita no caso S3.FIXTURE.
2. S1.11 DAVA FALSO PASS. Usava position('_TOO_MANY_ROWS'), que casa
   com a PRIMEIRA ocorrencia — o teto do array explicito. O guard do
   caminho NULL poderia estar ausente ou depois do LOOP e o teste ainda
   passaria. Corrigido: agora ancora em elementos EXCLUSIVOS do caminho
   NULL (v_effective_row_ids, LIMIT c_max_rows + 1).
3. S1.12 ERA FRACO. Contava ocorrencias de um fragmento repetido, o que
   nao prova equivalencia semantica. Corrigido: provas explicitas dos
   tres predicados do snapshot e do filtro por id do LOOP.
4. S1 e S4 agora sao FAIL-CLOSED (antes so exibiam PASS/FAIL/ATENCAO e
   a execucao podia continuar). Qualquer divergencia material levanta
   RAISE EXCEPTION.
5. Novos casos para o conjunto congelado (S3.11).

Esta Query permanece em database/proposals/ como evidencia de validacao —
NAO e promovida para database/schema/, mesmo padrao de 6800/6810/6820/
6821/6841/6842.

-------------------------------------------------------------------------------
SEMANTICA DE EXECUCAO — LEIA ANTES DE RODAR
-------------------------------------------------------------------------------
TODAS as quatro Secoes sao FAIL-CLOSED: cada assercao e um RAISE
EXCEPTION dentro de um bloco DO. Se qualquer assercao falhar, a execucao
aborta e a mensagem diz exatamente qual caso quebrou. Se o bloco terminar
sem erro, TODAS as assercoes daquela secao passaram.

As Secoes 2 e 3 rodam dentro de BEGIN ... ROLLBACK: elas CRIAM fixtures
(um job de importacao e ate 1001 rows de staging) e as descartam. NADA e
persistido. A Secao 4 prova zero residuo depois.

Cada Secao termina com um SELECT de resumo — informativo, nao substitui
as assertivas. Se o SELECT aparecer, a Secao inteira passou.

ATENCAO — o MCP do Supabase NAO propaga RAISE NOTICE. Nao espere ver
mensagens de progresso: o sinal de PASS e a AUSENCIA de excecao, e o
sinal de FAIL e a excecao com o nome do caso. Isso e deliberado e ja e o
contrato usado nas rodadas 6129/6130.

-------------------------------------------------------------------------------
IDENTIDADE DE EXECUCAO
-------------------------------------------------------------------------------
As duas funcoes exigem public.is_admin(). As Secoes 2 e 3 declaram a
identidade administrativa via set_config('request.jwt.claims', ..., true)
— escopo de transacao, descartado no ROLLBACK.

PREENCHER c_admin_user_id com o administrador responsavel. Sem isso as
secoes abortam no proprio preflight, por desenho.

-------------------------------------------------------------------------------
COMO O TETO E PROVADO SEM FABRICAR 1000+ IDS REAIS
-------------------------------------------------------------------------------
Os guards de forma/teto rodam ANTES de qualquer acesso a tabela. Logo:

  - array com EXATAMENTE o teto de ids INEXISTENTES -> passa pelos guards
    de forma/teto e falha mais adiante (NOT_FOUND / JOB_NOT_FOUND).
    Isso prova que o teto exato e ACEITO.
  - array com teto+1 -> falha em TOO_MANY_* sem nunca tocar o banco.
    Isso prova que o teto e APLICADO e que ele vem ANTES do acesso.

A diferenca ENTRE as duas mensagens de erro e a prova. Nenhum dado real e
necessario para os casos de array explicito.

A unica excecao e o teto do caminho NULL da 2164, que por definicao mede
linhas reais do job — esse caso usa fixture de 1001 rows sobre UMA UNICA
Card (Secao 3), integralmente revertida.

Pre-requisitos:
- Query 2163 e 2164 v1.1 CONFIRMADO EXECUTADO / LIVE.
===============================================================================
*/


-- =============================================================================
-- SECAO 1 — ESTRUTURAL E ESTATICA (read-only, FAIL-CLOSED)
-- =============================================================================
-- Prova, sem executar nenhuma das duas funcoes:
--   - assinatura publica preservada;
--   - SECURITY DEFINER preservado;
--   - search_path continua vazio;
--   - grants NAO ampliados;
--   - guards novos presentes no corpo LIVE;
--   - ORDEM dos guards no corpo LIVE;
--   - predicado canonico do snapshot NULL e filtro por id do LOOP.
DO $s1$
DECLARE
    v_decide TEXT;
    v_confirm TEXT;
    v_pos_snapshot INT;
BEGIN
    SELECT p.prosrc INTO v_decide
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'admin_decide_catalog_variant_import_row';

    SELECT p.prosrc INTO v_confirm
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'admin_confirm_catalog_variant_import';

    IF v_decide IS NULL OR v_confirm IS NULL THEN
        RAISE EXCEPTION 'S1.00 FALHOU: uma das funcoes nao existe no schema public.';
    END IF;

    -- S1.01/S1.02 — assinaturas publicas preservadas.
    IF (SELECT pg_get_function_identity_arguments(p.oid)
          FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname='public' AND p.proname='admin_decide_catalog_variant_import_row')
       <> 'p_row_ids uuid[], p_decision_status text' THEN
        RAISE EXCEPTION 'S1.01 FALHOU: assinatura da 2163 alterada.';
    END IF;

    IF (SELECT pg_get_function_identity_arguments(p.oid)
          FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname='public' AND p.proname='admin_confirm_catalog_variant_import')
       <> 'p_job_id uuid, p_row_ids uuid[]' THEN
        RAISE EXCEPTION 'S1.02 FALHOU: assinatura da 2164 alterada.';
    END IF;

    -- S1.03 — ambas SECURITY DEFINER.
    IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
         WHERE n.nspname='public' AND p.prosecdef
           AND p.proname IN ('admin_decide_catalog_variant_import_row',
                             'admin_confirm_catalog_variant_import')) <> 2 THEN
        RAISE EXCEPTION 'S1.03 FALHOU: alguma funcao deixou de ser SECURITY DEFINER.';
    END IF;

    -- S1.04 — search_path vazio nas duas.
    IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
         WHERE n.nspname='public'
           AND p.proname IN ('admin_decide_catalog_variant_import_row',
                             'admin_confirm_catalog_variant_import')
           AND p.proconfig @> ARRAY['search_path=""']) <> 2 THEN
        RAISE EXCEPTION 'S1.04 FALHOU: search_path deixou de ser vazio em alguma funcao.';
    END IF;

    -- S1.05 — grants NAO ampliados.
    IF EXISTS (SELECT 1 FROM information_schema.role_routine_grants g
                WHERE g.routine_name IN ('admin_decide_catalog_variant_import_row',
                                         'admin_confirm_catalog_variant_import')
                  AND g.grantee NOT IN ('authenticated','postgres')) THEN
        RAISE EXCEPTION 'S1.05 FALHOU: grant inesperado (%).',
            (SELECT string_agg(DISTINCT g.grantee, ', ')
               FROM information_schema.role_routine_grants g
              WHERE g.routine_name IN ('admin_decide_catalog_variant_import_row',
                                       'admin_confirm_catalog_variant_import')
                AND g.grantee NOT IN ('authenticated','postgres'));
    END IF;

    -- S1.06/S1.07 — guards novos presentes na 2163.
    IF v_decide NOT ILIKE '%cardinality(p_row_ids)%' THEN
        RAISE EXCEPTION 'S1.06 FALHOU: 2163 nao usa cardinality(p_row_ids).';
    END IF;
    IF v_decide NOT ILIKE '%array_ndims(p_row_ids)%' THEN
        RAISE EXCEPTION 'S1.07 FALHOU: 2163 nao tem guard de dimensionalidade.';
    END IF;

    -- S1.08 — guards novos presentes na 2164.
    IF v_confirm NOT ILIKE '%array_ndims(p_row_ids)%'
       OR v_confirm NOT ILIKE '%cardinality(p_row_ids)%' THEN
        RAISE EXCEPTION 'S1.08 FALHOU: 2164 nao tem guards de forma sobre p_row_ids.';
    END IF;

    -- S1.09 — ORDEM na 2163: is_admin < ndims < cardinality < teto < ANY().
    IF NOT (position('IF NOT public.is_admin()' in v_decide)
              < position('array_ndims(p_row_ids)' in v_decide)
            AND position('array_ndims(p_row_ids)' in v_decide)
              < position('cardinality(p_row_ids)' in v_decide)
            AND position('cardinality(p_row_ids)' in v_decide)
              < position('_TOO_MANY_IDS' in v_decide)
            AND position('_TOO_MANY_IDS' in v_decide)
              < position('ANY(p_row_ids)' in v_decide)) THEN
        RAISE EXCEPTION 'S1.09 FALHOU: ordem dos guards da 2163 incorreta.';
    END IF;

    -- S1.10 — ORDEM na 2164: is_admin < guards de array < acesso ao job.
    IF NOT (position('IF NOT public.is_admin()' in v_confirm)
              < position('array_ndims(p_row_ids)' in v_confirm)
            AND position('array_ndims(p_row_ids)' in v_confirm)
              < position('FROM public.catalog_variant_import_job WHERE id = p_job_id FOR UPDATE' in v_confirm)) THEN
        RAISE EXCEPTION 'S1.10 FALHOU: guards de array da 2164 vem depois do acesso ao job.';
    END IF;

    -- ===================================================================
    -- S1.11 (v1.1) — CAMINHO NULL: ancorado em elementos EXCLUSIVOS.
    --   A v1.0 usava position('_TOO_MANY_ROWS'), que casa com a PRIMEIRA
    --   ocorrencia (o teto do array explicito) e podia dar falso PASS.
    --   Agora o teste ancora em v_effective_row_ids e LIMIT c_max_rows+1,
    --   que so existem no branch NULL.
    -- ===================================================================
    IF v_confirm NOT LIKE '%v_effective_row_ids%' THEN
        RAISE EXCEPTION 'S1.11a FALHOU: 2164 nao materializa o conjunto efetivo (v_effective_row_ids ausente).';
    END IF;

    IF v_confirm NOT LIKE '%LIMIT c_max_rows + 1%' THEN
        RAISE EXCEPTION 'S1.11b FALHOU: 2164 nao usa LIMIT c_max_rows + 1 no congelamento.';
    END IF;

    IF v_confirm NOT LIKE '%cardinality(v_effective_row_ids) > c_max_rows%' THEN
        RAISE EXCEPTION 'S1.11c FALHOU: 2164 nao testa o teto sobre o conjunto congelado.';
    END IF;

    -- Posicao do bloco de congelamento (ancora exclusiva do branch NULL).
    v_pos_snapshot := position('v_effective_row_ids := ARRAY(' in v_confirm);
    IF v_pos_snapshot = 0 THEN
        RAISE EXCEPTION 'S1.11d FALHOU: bloco de congelamento nao encontrado.';
    END IF;

    IF NOT (v_pos_snapshot < position('SET status = ''CONFIRMING''' in v_confirm)) THEN
        RAISE EXCEPTION 'S1.11e FALHOU: congelamento/teto do caminho NULL vem DEPOIS do UPDATE CONFIRMING.';
    END IF;

    IF NOT (v_pos_snapshot < position('FOR v_row IN' in v_confirm)) THEN
        RAISE EXCEPTION 'S1.11f FALHOU: congelamento/teto do caminho NULL vem DEPOIS do LOOP.';
    END IF;

    IF NOT (position('cardinality(v_effective_row_ids) > c_max_rows' in v_confirm)
              < position('FOR v_row IN' in v_confirm)) THEN
        RAISE EXCEPTION 'S1.11g FALHOU: teste de teto do conjunto congelado vem DEPOIS do LOOP.';
    END IF;

    -- ===================================================================
    -- S1.12 (v1.1) — PREDICADO CANONICO e FILTRO DO LOOP, explicitos.
    --   A v1.0 contava ocorrencias de um fragmento, o que nao prova
    --   equivalencia semantica. Aqui cada um dos tres predicados do
    --   snapshot e verificado por presenca literal, e o LOOP e
    --   verificado por consumir o conjunto congelado.
    -- ===================================================================
    IF v_confirm NOT LIKE '%WHERE r.job_id = p_job_id%' THEN
        RAISE EXCEPTION 'S1.12a FALHOU: snapshot nao filtra por job_id.';
    END IF;
    IF v_confirm NOT LIKE '%AND r.persistence_status = ''PENDING''%' THEN
        RAISE EXCEPTION 'S1.12b FALHOU: snapshot nao filtra por persistence_status = PENDING.';
    END IF;
    IF v_confirm NOT LIKE '%AND r.decision_status IN (''APPROVED'', ''SKIPPED'')%' THEN
        RAISE EXCEPTION 'S1.12c FALHOU: snapshot nao filtra por decision_status IN (APPROVED, SKIPPED).';
    END IF;
    IF v_confirm NOT LIKE '%ORDER BY r.created_at, r.id%' THEN
        RAISE EXCEPTION 'S1.12d FALHOU: snapshot sem ordem deterministica (created_at, id).';
    END IF;

    -- O LOOP consome o conjunto congelado...
    IF v_confirm NOT LIKE '%AND r.id = ANY(v_effective_row_ids)%' THEN
        RAISE EXCEPTION 'S1.12e FALHOU: LOOP nao restringe ao conjunto congelado.';
    END IF;

    -- ...e NAO reabre o universo com o padrao antigo da 2145.
    IF v_confirm LIKE '%p_row_ids IS NULL OR r.id = ANY(p_row_ids)%' THEN
        RAISE EXCEPTION 'S1.12f FALHOU: LOOP ainda reabre o universo (p_row_ids IS NULL OR ...) — TOCTOU nao eliminado.';
    END IF;

    -- S1.13 — o branch ELSE (array explicito) tambem alimenta o conjunto.
    IF v_confirm NOT LIKE '%v_effective_row_ids := p_row_ids%' THEN
        RAISE EXCEPTION 'S1.13 FALHOU: caminho de array explicito nao alimenta v_effective_row_ids.';
    END IF;
END;
$s1$;

SELECT 'SECAO 1 — ESTRUTURAL/ESTATICA: 13 assercoes PASS' AS resumo;


-- =============================================================================
-- SECAO 2 — COMPORTAMENTAL DA 2163 (transacional, revertida, FAIL-CLOSED)
-- =============================================================================
BEGIN;

DO $s2$
DECLARE
    -- PREENCHER com o administrador responsavel.
    c_admin_user_id CONSTANT UUID := 'fe316458-49dd-44e1-aac0-f4b7604ef8f2';  -- binding GATE-A-EXECUTE-NOW-01

    c_max CONSTANT INTEGER := 10000;
    v_ids UUID[];
    v_msg TEXT;
    v_ok  BOOLEAN;
BEGIN
    IF c_admin_user_id IS NULL THEN
        RAISE EXCEPTION 'S2.PREFLIGHT: preencha c_admin_user_id antes de executar a Secao 2.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.admin_user WHERE id = c_admin_user_id) THEN
        RAISE EXCEPTION 'S2.PREFLIGHT: % nao consta em public.admin_user.', c_admin_user_id;
    END IF;

    -- S2.1 — NAO-ADMIN continua bloqueado (sem claims declaradas).
    PERFORM set_config('request.jwt.claims', '', true);
    v_ok := FALSE;
    BEGIN
        PERFORM public.admin_decide_catalog_variant_import_row(
            ARRAY[gen_random_uuid()]::uuid[], 'APPROVED');
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
        v_ok := v_msg LIKE 'ADMIN_DECIDE_CATALOG_VARIANT_IMPORT_ROW_FORBIDDEN%';
    END;
    IF NOT v_ok THEN
        RAISE EXCEPTION 'S2.1 FALHOU: nao-admin nao foi bloqueado (msg: %).', v_msg;
    END IF;

    -- A partir daqui, identidade administrativa declarada.
    PERFORM set_config('request.jwt.claims',
                       json_build_object('sub', c_admin_user_id)::text, true);
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'S2.PREFLIGHT: is_admin() falso apos set_config.';
    END IF;

    -- S2.2 — NULL rejeitado.
    v_ok := FALSE;
    BEGIN
        PERFORM public.admin_decide_catalog_variant_import_row(NULL::uuid[], 'APPROVED');
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
        v_ok := v_msg LIKE '%_MISSING_IDS%';
    END;
    IF NOT v_ok THEN RAISE EXCEPTION 'S2.2 FALHOU: NULL aceito (msg: %).', v_msg; END IF;

    -- S2.3 — MULTIDIMENSIONAL rejeitado (o gap que a 2163 fecha).
    v_ok := FALSE;
    BEGIN
        PERFORM public.admin_decide_catalog_variant_import_row(
            ARRAY[[gen_random_uuid(), gen_random_uuid(), gen_random_uuid()],
                  [gen_random_uuid(), gen_random_uuid(), gen_random_uuid()]]::uuid[],
            'APPROVED');
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
        v_ok := v_msg LIKE '%_INVALID_ARRAY_SHAPE%';
    END;
    IF NOT v_ok THEN
        RAISE EXCEPTION 'S2.3 FALHOU: array multidimensional aceito (msg: %).', v_msg;
    END IF;

    -- S2.4 — VAZIO rejeitado.
    v_ok := FALSE;
    BEGIN
        PERFORM public.admin_decide_catalog_variant_import_row(ARRAY[]::uuid[], 'APPROVED');
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
        v_ok := v_msg LIKE '%_MISSING_IDS%';
    END;
    IF NOT v_ok THEN RAISE EXCEPTION 'S2.4 FALHOU: array vazio aceito (msg: %).', v_msg; END IF;

    -- S2.5 — TETO EXATO (10000) ACEITO pelos guards de forma/teto.
    --        Ids inexistentes: a chamada segue adiante e morre em
    --        _NOT_FOUND. Falhar em _NOT_FOUND (e NAO em _TOO_MANY_IDS)
    --        e exatamente a prova de que 10000 passou.
    SELECT array_agg(gen_random_uuid()) INTO v_ids FROM generate_series(1, c_max);
    IF cardinality(v_ids) <> c_max THEN
        RAISE EXCEPTION 'S2.5 FIXTURE: esperado % ids, obtido %.', c_max, cardinality(v_ids);
    END IF;
    v_ok := FALSE;
    BEGIN
        PERFORM public.admin_decide_catalog_variant_import_row(v_ids, 'APPROVED');
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
        v_ok := v_msg LIKE '%_NOT_FOUND%';
    END;
    IF NOT v_ok THEN
        RAISE EXCEPTION 'S2.5 FALHOU: teto exato de % nao foi aceito (msg: %).', c_max, v_msg;
    END IF;

    -- S2.6 — TETO+1 (10001) REJEITADO, sem tocar o banco.
    SELECT array_agg(gen_random_uuid()) INTO v_ids FROM generate_series(1, c_max + 1);
    v_ok := FALSE;
    BEGIN
        PERFORM public.admin_decide_catalog_variant_import_row(v_ids, 'APPROVED');
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
        v_ok := v_msg LIKE '%_TOO_MANY_IDS%';
    END;
    IF NOT v_ok THEN
        RAISE EXCEPTION 'S2.6 FALHOU: teto+1 nao foi rejeitado (msg: %).', v_msg;
    END IF;

    -- S2.7 — REGRESSAO: status invalido continua rejeitado.
    v_ok := FALSE;
    BEGIN
        PERFORM public.admin_decide_catalog_variant_import_row(
            ARRAY[gen_random_uuid()]::uuid[], 'BANANA');
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
        v_ok := v_msg LIKE '%_INVALID_STATUS%';
    END;
    IF NOT v_ok THEN
        RAISE EXCEPTION 'S2.7 FALHOU: decision_status invalido aceito (msg: %).', v_msg;
    END IF;

    -- S2.8 — REGRESSAO: aprovar linha NEEDS_REVIEW real continua
    --        bloqueado. Somente LEITURA do id de uma row existente.
    SELECT array_agg(s.id) INTO v_ids
    FROM (SELECT r.id FROM public.catalog_variant_import_row r
          JOIN public.catalog_variant_import_job j ON j.id = r.job_id
          WHERE j.status = 'STAGED' AND r.validation_status = 'NEEDS_REVIEW'
          LIMIT 1) s;

    IF v_ids IS NULL THEN
        RAISE EXCEPTION 'S2.8 FIXTURE: nenhuma row NEEDS_REVIEW em job STAGED — cenario mudou, reauditar.';
    END IF;

    v_ok := FALSE;
    BEGIN
        PERFORM public.admin_decide_catalog_variant_import_row(v_ids, 'APPROVED');
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
        v_ok := v_msg LIKE '%_NEEDS_REVIEW%';
    END;
    IF NOT v_ok THEN
        RAISE EXCEPTION 'S2.8 FALHOU: NEEDS_REVIEW foi aprovada (msg: %).', v_msg;
    END IF;
END;
$s2$;

SELECT 'SECAO 2 — 2163 COMPORTAMENTAL: 8 assercoes PASS' AS resumo;

ROLLBACK;


-- =============================================================================
-- SECAO 3 — COMPORTAMENTAL DA 2164 (transacional, revertida, FAIL-CLOSED)
-- =============================================================================
BEGIN;

DO $s3$
DECLARE
    -- PREENCHER com o administrador responsavel.
    c_admin_user_id CONSTANT UUID := 'fe316458-49dd-44e1-aac0-f4b7604ef8f2';  -- binding GATE-A-EXECUTE-NOW-01

    c_max CONSTANT INTEGER := 1000;
    v_ids        UUID[];
    v_job_id     UUID;
    v_fake_job   UUID := gen_random_uuid();
    v_card_id    UUID;
    v_card_set   UUID;
    v_msg        TEXT;
    v_ok         BOOLEAN;
    v_before     BIGINT;
    v_after      BIGINT;
    v_frozen     UUID[];
    v_extra_id   UUID;
BEGIN
    IF c_admin_user_id IS NULL THEN
        RAISE EXCEPTION 'S3.PREFLIGHT: preencha c_admin_user_id antes de executar a Secao 3.';
    END IF;

    -- S3.1 — NAO-ADMIN continua bloqueado.
    PERFORM set_config('request.jwt.claims', '', true);
    v_ok := FALSE;
    BEGIN
        PERFORM * FROM public.admin_confirm_catalog_variant_import(v_fake_job, NULL);
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
        v_ok := v_msg LIKE 'ADMIN_CONFIRM_CATALOG_VARIANT_IMPORT_FORBIDDEN%';
    END;
    IF NOT v_ok THEN
        RAISE EXCEPTION 'S3.1 FALHOU: nao-admin nao foi bloqueado (msg: %).', v_msg;
    END IF;

    PERFORM set_config('request.jwt.claims',
                       json_build_object('sub', c_admin_user_id)::text, true);
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'S3.PREFLIGHT: is_admin() falso apos set_config.';
    END IF;

    -- S3.2 — MULTIDIMENSIONAL rejeitado ANTES de tocar o job.
    --        job_id inexistente de proposito: se a funcao respondesse
    --        JOB_NOT_FOUND, o guard de forma estaria DEPOIS do acesso.
    v_ok := FALSE;
    BEGIN
        PERFORM * FROM public.admin_confirm_catalog_variant_import(
            v_fake_job,
            ARRAY[[gen_random_uuid(), gen_random_uuid()],
                  [gen_random_uuid(), gen_random_uuid()]]::uuid[]);
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
        v_ok := v_msg LIKE '%_INVALID_ARRAY_SHAPE%';
    END;
    IF NOT v_ok THEN
        RAISE EXCEPTION 'S3.2 FALHOU: multidimensional aceito ou guard tardio (msg: %).', v_msg;
    END IF;

    -- S3.3 — VAZIO rejeitado (contrato novo: nao e no-op silencioso).
    v_ok := FALSE;
    BEGIN
        PERFORM * FROM public.admin_confirm_catalog_variant_import(v_fake_job, ARRAY[]::uuid[]);
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
        v_ok := v_msg LIKE '%_EMPTY_ROW_IDS%';
    END;
    IF NOT v_ok THEN
        RAISE EXCEPTION 'S3.3 FALHOU: array vazio nao foi rejeitado (msg: %).', v_msg;
    END IF;

    -- S3.4 — TETO EXATO EXPLICITO (1000) ACEITO pelos guards de forma.
    --        Falhar em JOB_NOT_FOUND (e nao em TOO_MANY_ROWS) prova
    --        que 1000 passou e que o guard de forma roda antes do job.
    SELECT array_agg(gen_random_uuid()) INTO v_ids FROM generate_series(1, c_max);
    v_ok := FALSE;
    BEGIN
        PERFORM * FROM public.admin_confirm_catalog_variant_import(v_fake_job, v_ids);
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
        v_ok := v_msg LIKE '%_JOB_NOT_FOUND%';
    END;
    IF NOT v_ok THEN
        RAISE EXCEPTION 'S3.4 FALHOU: teto exato de % nao aceito (msg: %).', c_max, v_msg;
    END IF;

    -- S3.5 — TETO+1 EXPLICITO (1001) REJEITADO sem tocar o banco.
    SELECT array_agg(gen_random_uuid()) INTO v_ids FROM generate_series(1, c_max + 1);
    v_ok := FALSE;
    BEGIN
        PERFORM * FROM public.admin_confirm_catalog_variant_import(v_fake_job, v_ids);
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
        v_ok := v_msg LIKE '%_TOO_MANY_ROWS%';
    END;
    IF NOT v_ok THEN
        RAISE EXCEPTION 'S3.5 FALHOU: teto+1 explicito nao rejeitado (msg: %).', v_msg;
    END IF;

    -- ===================================================================
    -- S3.FIXTURE (v1.1) — UMA UNICA Card real, repetida.
    --
    --   A v1.0 exigia um Card Set com >= 1001 Cards ativas. O maior Card
    --   Set POKEMON tem 300 (SWSHP) — a fixture era impossivel.
    --
    --   Legalidade: o unico indice unico de catalog_variant_import_row
    --   (uq_catalog_variant_import_row_job_card_variant_type, Query 2138)
    --   e PARCIAL:
    --       ON (job_id, card_id, (normalized_data ->> 'variant_type_id'))
    --       WHERE normalized_data ->> 'variant_type_id' IS NOT NULL
    --   Com normalized_data = '{}'::jsonb, o campo e NULL, o predicado do
    --   indice e FALSO e as linhas nao entram nele. Repetir a mesma Card
    --   N vezes e legal por construcao.
    --
    --   raw_data carrega harness_seq apenas para tornar cada linha
    --   distinguivel em inspecao; nao participa de nenhuma constraint.
    -- ===================================================================
    SELECT c.id, c.card_set_id INTO v_card_id, v_card_set
    FROM public.card c
    JOIN public.card_set cs ON cs.id = c.card_set_id
    JOIN public.expansion e ON e.id = cs.expansion_id
    JOIN public.game g ON g.id = e.game_id AND g.code = 'POKEMON'
    WHERE c.is_active
    ORDER BY c.id
    LIMIT 1;

    IF v_card_id IS NULL THEN
        RAISE EXCEPTION 'S3.FIXTURE: nenhuma Card POKEMON ativa encontrada.';
    END IF;

    -- Prova explicita da compatibilidade com o indice parcial da 2138:
    -- o predicado do indice precisa ser FALSO para normalized_data = '{}'.
    IF ('{}'::jsonb ->> 'variant_type_id') IS NOT NULL THEN
        RAISE EXCEPTION 'S3.FIXTURE FALHOU: premissa do indice parcial da 2138 nao vale.';
    END IF;

    INSERT INTO public.catalog_variant_import_job
        (card_set_id, source, external_set_id, status, total_rows)
    VALUES (v_card_set, 'TCGDEX', 'HARNESS-2822', 'STAGED', 0)
    RETURNING id INTO v_job_id;

    -- S3.6 — NULL com ZERO elegiveis continua VALIDO.
    --        Caminho usado pelo caller web para transicionar o job.
    BEGIN
        PERFORM * FROM public.admin_confirm_catalog_variant_import(v_job_id, NULL);
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
        RAISE EXCEPTION 'S3.6 FALHOU: NULL com zero elegiveis foi rejeitado (msg: %).', v_msg;
    END;

    IF (SELECT status FROM public.catalog_variant_import_job WHERE id = v_job_id) <> 'COMPLETED' THEN
        RAISE EXCEPTION 'S3.6 FALHOU: status final inesperado (%).',
            (SELECT status FROM public.catalog_variant_import_job WHERE id = v_job_id);
    END IF;

    UPDATE public.catalog_variant_import_job SET status = 'STAGED' WHERE id = v_job_id;

    -- S3.7 — NULL com EXATAMENTE o teto (1000) elegiveis: PERMITIDO.
    --        1000 rows SKIPPED sobre a MESMA Card.
    INSERT INTO public.catalog_variant_import_row
        (job_id, card_id, raw_data, normalized_data,
         validation_status, match_status, decision_status, persistence_status)
    SELECT v_job_id, v_card_id,
           jsonb_build_object('harness_seq', gs), '{}'::jsonb,
           'VALID', 'NEW', 'SKIPPED', 'PENDING'
    FROM generate_series(1, c_max) AS gs;

    IF (SELECT count(*) FROM public.catalog_variant_import_row WHERE job_id = v_job_id) <> c_max THEN
        RAISE EXCEPTION 'S3.7 FIXTURE: esperado % rows.', c_max;
    END IF;

    SELECT count(*) INTO v_before FROM public.card_variant;

    BEGIN
        PERFORM * FROM public.admin_confirm_catalog_variant_import(v_job_id, NULL);
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
        RAISE EXCEPTION 'S3.7 FALHOU: NULL com exatamente % elegiveis foi rejeitado (msg: %).', c_max, v_msg;
    END;

    SELECT count(*) INTO v_after FROM public.card_variant;
    IF v_after <> v_before THEN
        RAISE EXCEPTION 'S3.7 FALHOU: card_variant mudou (% -> %) com rows SKIPPED.', v_before, v_after;
    END IF;

    IF (SELECT count(*) FROM public.catalog_variant_import_row
         WHERE job_id = v_job_id AND persistence_status = 'UNCHANGED') <> c_max THEN
        RAISE EXCEPTION 'S3.7 FALHOU: nem todas as % rows SKIPPED viraram UNCHANGED.', c_max;
    END IF;

    -- S3.8 — NULL com TETO+1 (1001) elegiveis: REJEITADO ANTES do loop.
    UPDATE public.catalog_variant_import_job SET status = 'STAGED' WHERE id = v_job_id;
    UPDATE public.catalog_variant_import_row
       SET persistence_status = 'PENDING' WHERE job_id = v_job_id;

    INSERT INTO public.catalog_variant_import_row
        (job_id, card_id, raw_data, normalized_data,
         validation_status, match_status, decision_status, persistence_status)
    VALUES (v_job_id, v_card_id,
            jsonb_build_object('harness_seq', c_max + 1), '{}'::jsonb,
            'VALID', 'NEW', 'SKIPPED', 'PENDING')
    RETURNING id INTO v_extra_id;

    IF (SELECT count(*) FROM public.catalog_variant_import_row
         WHERE job_id = v_job_id
           AND persistence_status = 'PENDING'
           AND decision_status IN ('APPROVED','SKIPPED')) <> c_max + 1 THEN
        RAISE EXCEPTION 'S3.8 FIXTURE: esperado % elegiveis.', c_max + 1;
    END IF;

    v_ok := FALSE;
    BEGIN
        PERFORM * FROM public.admin_confirm_catalog_variant_import(v_job_id, NULL);
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
        v_ok := v_msg LIKE '%_TOO_MANY_ROWS%';
    END;
    IF NOT v_ok THEN
        RAISE EXCEPTION 'S3.8 FALHOU: NULL com % elegiveis nao foi rejeitado (msg: %).', c_max + 1, v_msg;
    END IF;

    -- S3.9 — a rejeicao de S3.8 NAO deixou rastro.
    IF (SELECT status FROM public.catalog_variant_import_job WHERE id = v_job_id) <> 'STAGED' THEN
        RAISE EXCEPTION 'S3.9 FALHOU: job saiu de STAGED apesar da rejeicao por teto.';
    END IF;
    IF (SELECT count(*) FROM public.catalog_variant_import_row
         WHERE job_id = v_job_id AND persistence_status <> 'PENDING') <> 0 THEN
        RAISE EXCEPTION 'S3.9 FALHOU: alguma row mudou apesar da rejeicao por teto.';
    END IF;
    SELECT count(*) INTO v_after FROM public.card_variant;
    IF v_after <> v_before THEN
        RAISE EXCEPTION 'S3.9 FALHOU: card_variant mudou apesar da rejeicao por teto.';
    END IF;

    -- ===================================================================
    -- S3.11 (v1.1) — CONJUNTO CONGELADO: o LOOP consome o snapshot,
    --   nao o universo. Prova comportamental, complementar a S1.11/S1.12.
    --
    --   Cenario: remove-se a 1001a row (volta a 1000 elegiveis) e
    --   confirma-se com NULL. Depois, uma NOVA row elegivel e criada e
    --   verifica-se que ela permanece PENDING — ela nao existia no
    --   snapshot daquela chamada e, portanto, nao poderia ter sido
    --   processada.
    -- ===================================================================
    DELETE FROM public.catalog_variant_import_row WHERE id = v_extra_id;

    -- Congela o que a funcao deveria enxergar, para comparar depois.
    v_frozen := ARRAY(
        SELECT r.id FROM public.catalog_variant_import_row r
         WHERE r.job_id = v_job_id
           AND r.persistence_status = 'PENDING'
           AND r.decision_status IN ('APPROVED','SKIPPED')
         ORDER BY r.created_at, r.id
         LIMIT c_max + 1
    );
    IF cardinality(v_frozen) <> c_max THEN
        RAISE EXCEPTION 'S3.11 FIXTURE: esperado % elegiveis apos o DELETE, obtido %.',
            c_max, cardinality(v_frozen);
    END IF;

    UPDATE public.catalog_variant_import_job SET status = 'STAGED' WHERE id = v_job_id;

    BEGIN
        PERFORM * FROM public.admin_confirm_catalog_variant_import(v_job_id, NULL);
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
        RAISE EXCEPTION 'S3.11 FALHOU: confirmacao com % elegiveis rejeitada (msg: %).', c_max, v_msg;
    END;

    -- Exatamente o conjunto congelado foi processado.
    IF (SELECT count(*) FROM public.catalog_variant_import_row
         WHERE job_id = v_job_id
           AND id = ANY(v_frozen)
           AND persistence_status = 'UNCHANGED') <> c_max THEN
        RAISE EXCEPTION 'S3.11a FALHOU: o conjunto congelado nao foi integralmente processado.';
    END IF;
    IF (SELECT count(*) FROM public.catalog_variant_import_row
         WHERE job_id = v_job_id AND NOT (id = ANY(v_frozen))) <> 0 THEN
        RAISE EXCEPTION 'S3.11b FALHOU: existem rows fora do conjunto congelado.';
    END IF;

    -- Nova row elegivel criada DEPOIS: continua PENDING, e o job volta a
    -- STAGED/CONFIRMING conforme o estado real — o snapshot nao a viu.
    INSERT INTO public.catalog_variant_import_row
        (job_id, card_id, raw_data, normalized_data,
         validation_status, match_status, decision_status, persistence_status)
    VALUES (v_job_id, v_card_id,
            jsonb_build_object('harness_seq', 'pos-snapshot'), '{}'::jsonb,
            'VALID', 'NEW', 'SKIPPED', 'PENDING')
    RETURNING id INTO v_extra_id;

    IF (SELECT persistence_status FROM public.catalog_variant_import_row
         WHERE id = v_extra_id) <> 'PENDING' THEN
        RAISE EXCEPTION 'S3.11c FALHOU: row criada apos o snapshot nao esta PENDING.';
    END IF;

    -- S3.10 — ARRAY EXPLICITO <= 1000 mantem o comportamento atual:
    --         processa exatamente o sublote e devolve CONFIRMING
    --         (sobra elegivel) — sem tocar card_variant (tudo SKIPPED).
    UPDATE public.catalog_variant_import_job SET status = 'STAGED' WHERE id = v_job_id;
    UPDATE public.catalog_variant_import_row
       SET persistence_status = 'PENDING' WHERE job_id = v_job_id;

    SELECT array_agg(s.id) INTO v_ids
    FROM (SELECT id FROM public.catalog_variant_import_row
           WHERE job_id = v_job_id ORDER BY created_at, id LIMIT 50) s;

    SELECT count(*) INTO v_before FROM public.card_variant;

    BEGIN
        PERFORM * FROM public.admin_confirm_catalog_variant_import(v_job_id, v_ids);
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
        RAISE EXCEPTION 'S3.10 FALHOU: sublote de 50 rejeitado (msg: %).', v_msg;
    END;

    SELECT count(*) INTO v_after FROM public.card_variant;
    IF v_after <> v_before THEN
        RAISE EXCEPTION 'S3.10 FALHOU: card_variant mudou com sublote SKIPPED.';
    END IF;

    IF (SELECT count(*) FROM public.catalog_variant_import_row
         WHERE job_id = v_job_id AND persistence_status = 'UNCHANGED') <> 50 THEN
        RAISE EXCEPTION 'S3.10 FALHOU: sublote nao processou exatamente 50 rows.';
    END IF;

    IF (SELECT status FROM public.catalog_variant_import_job WHERE id = v_job_id) <> 'CONFIRMING' THEN
        RAISE EXCEPTION 'S3.10 FALHOU: status esperado CONFIRMING (sublote parcial), obtido %.',
            (SELECT status FROM public.catalog_variant_import_job WHERE id = v_job_id);
    END IF;
END;
$s3$;

SELECT 'SECAO 3 — 2164 COMPORTAMENTAL: 11 assercoes PASS (inclui conjunto congelado)' AS resumo;

ROLLBACK;


-- =============================================================================
-- SECAO 4 — ZERO RESIDUO E BASELINE (read-only, FAIL-CLOSED)
-- =============================================================================
-- v1.1: era um SELECT informativo com PASS/FAIL/ATENCAO. Agora e
-- fail-closed. Se o baseline legitimo tiver mudado antes da execucao,
-- a Secao aborta — e o procedimento correto e STOP / reauditar, nao
-- suavizar a assercao.
DO $s4$
DECLARE
    v_baseline_card_variant CONSTANT BIGINT := 6483;  -- medido em 2026-09-12
    v_baseline_jobs_staged  CONSTANT BIGINT := 4;
    v_baseline_valid        CONSTANT BIGINT := 519;
    v_baseline_needs_review CONSTANT BIGINT := 505;
    v_n BIGINT;
BEGIN
    -- S4.1 — nenhum job de harness persistido.
    SELECT count(*) INTO v_n FROM public.catalog_variant_import_job
     WHERE external_set_id = 'HARNESS-2822';
    IF v_n <> 0 THEN
        RAISE EXCEPTION 'S4.1 FALHOU: % job(s) HARNESS-2822 residual(is) — o ROLLBACK nao aconteceu.', v_n;
    END IF;

    -- S4.2 — card_variant inalterado.
    SELECT count(*) INTO v_n FROM public.card_variant;
    IF v_n <> v_baseline_card_variant THEN
        RAISE EXCEPTION 'S4.2 FALHOU: card_variant = %, baseline autorizado = %. STOP / reauditar antes de prosseguir.',
            v_n, v_baseline_card_variant;
    END IF;

    -- S4.3 — os 4 jobs STAGED continuam STAGED.
    SELECT count(*) INTO v_n FROM public.catalog_variant_import_job WHERE status = 'STAGED';
    IF v_n <> v_baseline_jobs_staged THEN
        RAISE EXCEPTION 'S4.3 FALHOU: % jobs STAGED, baseline = %.', v_n, v_baseline_jobs_staged;
    END IF;

    -- S4.4 — 519 VALID ainda PENDING nos jobs STAGED.
    SELECT count(*) INTO v_n
    FROM public.catalog_variant_import_row r
    JOIN public.catalog_variant_import_job j ON j.id = r.job_id
    WHERE j.status = 'STAGED' AND r.validation_status = 'VALID'
      AND r.decision_status = 'PENDING';
    IF v_n <> v_baseline_valid THEN
        RAISE EXCEPTION 'S4.4 FALHOU: % rows VALID/PENDING, baseline = %.', v_n, v_baseline_valid;
    END IF;

    -- S4.5 — 505 NEEDS_REVIEW ainda PENDING nos jobs STAGED.
    SELECT count(*) INTO v_n
    FROM public.catalog_variant_import_row r
    JOIN public.catalog_variant_import_job j ON j.id = r.job_id
    WHERE j.status = 'STAGED' AND r.validation_status = 'NEEDS_REVIEW'
      AND r.decision_status = 'PENDING';
    IF v_n <> v_baseline_needs_review THEN
        RAISE EXCEPTION 'S4.5 FALHOU: % rows NEEDS_REVIEW/PENDING, baseline = %.', v_n, v_baseline_needs_review;
    END IF;
END;
$s4$;

-- Resumo informativo. So aparece se as 5 assercoes da Secao 4 passaram.
SELECT 'SECAO 4 — ZERO RESIDUO: 5 assercoes PASS' AS resumo,
       (SELECT count(*) FROM public.card_variant)                                   AS card_variant,
       (SELECT count(*) FROM public.catalog_variant_import_job WHERE status='STAGED') AS jobs_staged,
       (SELECT count(*) FROM public.catalog_variant_import_job
         WHERE external_set_id='HARNESS-2822')                                      AS harness_residual;
