/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 2825 - Validate Card Printing Profile Creation Backfill
Versão......: 3.6
Status......: PROPOSTA — NÃO EXECUTADA
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-13
Mandato.....: CARD-VARIANTS — EDITORIAL-CONVERGENCE-10 /
              FIRST-EDITION-PROFILE-IMPLEMENTATION-01 /
              GATE-A-STAGING-01 → REV-01 → REV-02 → REV-03
              → GATE-B-EXECUTION-01 (STOP em §0)
              → GATE-B-CORRECTION-01 / HARNESS-CHANNEL-COMPATIBILITY
              → GATE-B-CORRECTION-02 / HARNESS-PRESERVATION-HARDENING
              → GATE-B-CORRECTION-03 / CASE-U-AFFECTED-JOB-SCOPE

-------------------------------------------------------------------------------
O QUE MUDOU NA v3.4 — CASO U VIRA PROVA DE ESCOPO
-------------------------------------------------------------------------------
A v3.3 removia total_rows, valid_rows e updated_at da comparação de TODOS os
jobs. Consequência: o worker poderia tocar contadores ou updated_at de um job
NÃO afetado e U continuaria verde. Além disso U via job desaparecido, mas não
job NOVO — e, como o MAIN reverte, um job indevido sumiria antes de o Z olhar.

A v3.4 transforma U em prova exata de escopo, sem hardcode de BASE3:

  1. o conjunto de jobs afetados é DERIVADO das linhas materializadas
     (DISTINCT job_id onde printing_profile_id = v_pid), e sua cardinalidade
     tem de bater com o jobs_affected devolvido pelo worker;
  2. TODOS os afetados têm total_rows/valid_rows conferidos contra a contagem
     real — não só o primeiro;
  3. nos afetados, a row inteira menos os três campos autorizados tem de estar
     idêntica;
  4. nos NÃO afetados, a row INTEIRA tem de estar idêntica — sem remover nada,
     nem updated_at: job fora do escopo não podia sequer ser tocado;
  5. nenhum job desaparecido (mantido);
  6. nenhum job NOVO, de qualquer status (novo).

_jobs_before passou a fotografar TODOS os jobs, não só os STAGED. O mandato
permitia manter só STAGED; fotografar todos é estritamente mais forte, custa o
mesmo e evita que a prova de "job novo" acuse falso positivo em job que já
existia fora de STAGED.

BASE3 continua sendo lido, mas só para o GABARITO informativo — saiu do
veredito de U.

-------------------------------------------------------------------------------
O QUE MUDOU NA v3.3 — PROVAS DE PRESERVAÇÃO POR ROW INTEIRA
-------------------------------------------------------------------------------
A v3.2 provava preservação enumerando colunas à mão. Toda enumeração manual é
uma lista de pontos cegos esperando uma coluna nova. A v3.3 troca isso por
to_jsonb(row) em cinco lugares — sem tocar na arquitetura transacional:

  N   _n_before passa a guardar to_jsonb(r) das linhas NÃO elegíveis e a
      comparação vira to_jsonb(r) IS DISTINCT FROM snapshot. Cobre raw_data,
      card_id, decision_status, persistence_status, resulting_variant_id,
      created_at, updated_at e o que vier depois. Linha que some também conta
      como alteração.

  U   ganha a prova B: _jobs_before guarda to_jsonb(j) dos jobs e U exige que
      to_jsonb(j) menos total_rows, valid_rows e updated_at continue idêntico.
      status, progress_step, rejected/inserted/unchanged/skipped/failed_rows,
      error_summary e initiated_by passam a ser protegidos explicitamente.
      >>> SUPERADO PELA v3.4: esta versão aplicava a remoção dos três campos a
      TODOS os jobs, o que permitia tocar job fora do escopo. Ver v3.4.

  T   deixa de olhar o estado geral de BASE3 e passa a escopar as linhas que
      ESTA operação materializou (printing_profile_id = v_pid), exigindo ainda
      que o escopo tenha exatamente rows_touched linhas.

  staged_rows_digest e o digest de jobs viram digest de ROW INTEIRA
      (id || to_jsonb(row)). O antigo jobs_counters_digest, que via três
      campos, virou jobs_rows_digest sobre TODOS os jobs.

  X   usa os mesmos digests integrais e passou a exigir que o digest dos JOBS
      também tenha MUDADO durante a escrita — antes só o de staging era
      conferido.

-------------------------------------------------------------------------------
POR QUE A v3.2 EXISTE
-------------------------------------------------------------------------------
A v3.1 dependia de: preâmbulo FORA da transação -> BEGIN -> ROLLBACK -> epílogo
pós-rollback. O canal operacional real (Supabase Management API / execute_sql)
não sustenta essa forma — foi PROVADO em 2026-09-13, contra o LIVE:

  - o payload já chega dentro de uma transação aberta: txid_current() antes e
    depois de um BEGIN interno é o MESMO valor (346245 = 346245). O BEGIN é
    no-op;
  - o ROLLBACK interno encerra a transação EXTERNA e leva junto tudo o que
    fora criado "antes" dele — inclusive TEMP TABLE ON COMMIT PRESERVE ROWS;
  - objetos TEMP não sobrevivem entre chamadas: to_regclass() devolve NULL na
    chamada seguinte, com txid e conexão diferentes.

A v3.2 abandona o controle transacional de topo e passa a isolar CADA cenário
mutável em SUBTRANSAÇÃO PL/pgSQL — um bloco BEGIN … EXCEPTION, que o PostgreSQL
implementa como savepoint implícito. O padrão, aplicado sem exceção:

    BEGIN
        <writes reais do caso>
        <PROVAS de que os writes aconteceram>     -- nunca depois da sentinela
        RAISE EXCEPTION 'HARNESS_<CASO>_ROLLBACK';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM = 'HARNESS_<CASO>_ROLLBACK' THEN <reverteu> ELSE <falhou> END IF;
    END;
    <PROVAS de que nada sobreviveu>

Variáveis PL/pgSQL NÃO são transacionais: sobrevivem ao rollback do sub-bloco.
TEMP TABLES são: por isso nenhum veredito é gravado em _r de dentro de um
sub-bloco — o resultado sai em variável e é registrado depois.

-------------------------------------------------------------------------------
FORMA DE EXECUÇÃO — UMA ÚNICA CHAMADA
-------------------------------------------------------------------------------
Executar o arquivo INTEIRO em UMA chamada execute_sql. Não há, e não pode
haver, BEGIN / COMMIT / ROLLBACK de topo neste arquivo: a transação é a que o
Management API já abriu.

Pré-requisitos: Queries 2188 e 2189 v2.1 aplicadas, e ao menos um administrador
em public.admin_user. A Seção 0 ABORTA se faltar qualquer um — nunca passa por
omissão.

Executar como owner/postgres: é o papel que enxerga internal.* e que, por não
ter sessão de aplicação, permite o teste negativo honesto do caso A.

-------------------------------------------------------------------------------
FIXTURES — NENHUMA GLOBAL
-------------------------------------------------------------------------------
A v3.1 criava Game e trait de fixture na Seção 0 e contava com o ROLLBACK de
topo para limpá-los. Sem ROLLBACK de topo isso viraria resíduo. Na v3.2:

  - a Seção 0 só LÊ (admin, game POKEMON, traits FIRST_EDITION/SHADOWLESS,
    próxima display_order livre). Não escreve nada;
  - o Game e o trait de outro jogo nascem e morrem DENTRO do caso E;
  - o trait inativo nasce e morre DENTRO do caso D;
  - Perfis de harness nascem e morrem dentro de H, L, X e do bloco MAIN.

-------------------------------------------------------------------------------
CAMADAS DE SEGURANÇA
-------------------------------------------------------------------------------
1ª — sentinela por caso: isola e reverte cada cenário mutável. É o mecanismo
     principal e o único de que o PASS depende.
2ª — caso Z: reexecuta o snapshot e compara com a baseline. Pega qualquer
     vazamento que a 1ª camada tenha deixado passar.
3ª — GATE: RAISE em qualquer FAIL. Como o payload roda dentro da transação do
     Management API, a exceção reverte a execução inteira.

A 3ª camada é rede, não método: um harness que só fica limpo porque abortou no
final não estaria provando isolamento nenhum.

-------------------------------------------------------------------------------
COBERTURA — 29 casos, todos no mesmo payload
-------------------------------------------------------------------------------
A   RPC pública sem sessão -> FORBIDDEN e zero efeito
AA  ACL: PUBLIC por aclexplode(grantee=0); roles reais por has_function_privilege
AB  prova estática do wrapper (is_admin + auth.uid + delegação, sem duplicação)
AC  guards de p_actor_id no worker (NULL / não-admin)
B   guards de array: NULL / vazio / multidimensional / NULL interno / duplicata
C   trait inexistente
D   trait inativo                      [fixture local + sentinela]
E   mixed-game                         [fixture local + sentinela]
F   code duplicado                     | G  display_order duplicado
H   composição vazia                   [write + sentinela implícita]
I   assinatura duplicada
J   selo falsificado                   | K  imutabilidade pós-selo
L   PROVA CRÍTICA do selo diferido     [write + sentinela]
X   PROVA DE ATOMICIDADE: worker escreve de fato e a subtransação aborta depois
M   selo restaurado para DEFERRED
N   não elegíveis intocadas em QUALQUER coluna (row inteira)
O   outcome A | P outcome B | Q outcome C / fail-closed
R   contrato NEW-only, prova positiva
S   invariante: nenhum MATCHED possível nesta operação
T   zero resulting_variant_id no escopo do Perfil novo
U   escopo exato de jobs: afetados derivados == jobs_affected, contadores
    corretos em todos, nada não autorizado neles, nada tocado fora deles,
    zero job desaparecido, zero job novo
V   action log (1 evento, actor = p_actor_id)
W   segunda composição idêntica falha  | Y  zero card_variant criada
    [M..V, W, Y rodam TODOS dentro de UMA subtransação — a do bloco MAIN]
Z   ISOLAMENTO: LIVE idêntico à baseline, zero resíduo HARNESS_*

-------------------------------------------------------------------------------
GABARITO FIRST_EDITION — informativo
-------------------------------------------------------------------------------
Medido em 2026-09-13 (reconfirmado contra o LIVE no GATE-B-EXECUTION-01):
  62 touched | 16 revalidated | 46 still pending | 1 job affected
  BASE3: 177 total / 64 VALID / 113 NEEDS_REVIEW  ->  177 / 80 / 97
  card_variant: 7413 -> 7413 (NÃO muda)
Divergência é INFO, não FAIL: número de base não é contrato de função.

-------------------------------------------------------------------------------
REVISION HISTORY
-------------------------------------------------------------------------------
| 1.0 | **Versão inicial (2026-09-13).** 26 casos A..Z. Usava impersonação via
        request.jwt.claims no caminho positivo. NÃO EXECUTADO. |
| 2.0 | **Impersonação removida (2026-09-13, GATE-A-REV-01).** Positivos passam
        a chamar o worker internal como owner com p_actor_id real; o negativo
        exercita a RPC pública sem sessão. +AA, +AB, +AC. NÃO EXECUTADO. |
| 3.0 | **Hardening de quatro provas fracas (2026-09-13, GATE-A-REV-02).** AA
        lê PUBLIC pela ACL (grantee=0); S exige MATCHED positivo e reprova alto
        quando não houver; X prova atomicidade abortando DEPOIS de o worker
        escrever; Z roda depois do ROLLBACK contra baseline capturada fora da
        transação. Gate dividido: 28 (A..Y) + Z. NÃO EXECUTADO. |
| 3.1 | **Contrato NEW-only (2026-09-13, GATE-A-REV-03).** Acompanha a Query
        2189 v2.1, que removeu o lookup em card_variant. R virou prova positiva
        de NEW-only; S virou prova de invariante; digests passaram a cobrir
        matched_variant_id, error_detail e updated_at. NÃO EXECUTADO. |
| 3.2 | **Compatibilidade de canal (2026-09-13, GATE-B-CORRECTION-01).** Sem
        BEGIN/COMMIT/ROLLBACK de topo: o isolamento passa a ser por
        subtransação PL/pgSQL com sentinela, caso a caso. Fixtures globais
        eliminadas (D e E criam as suas). M..V/W/Y migram para uma única
        subtransação (bloco MAIN) e seus vereditos saem em JSONB, registrados
        em _r só depois da reversão. Z deixa de provar ROLLBACK de topo e passa
        a provar ISOLAMENTO. Gate único: 29 PASS / 0 FAIL no mesmo payload.
        Nenhuma prova removida ou enfraquecida. NÃO EXECUTADO. |
| 3.3 | **Preservação por row inteira (2026-09-13, GATE-B-CORRECTION-02).**
        N compara to_jsonb(r) das linhas não elegíveis; U ganha prova de que
        nenhum campo não autorizado dos jobs mudou (to_jsonb(j) menos
        total_rows/valid_rows/updated_at); T passa a escopar direto as linhas
        materializadas pelo Perfil novo; staged_rows_digest e jobs_rows_digest
        viram digest de row inteira; X exige que o digest dos jobs também tenha
        mudado durante a escrita. Arquitetura transacional intocada. NÃO
        EXECUTADO. |
| 3.4 | **Caso U vira prova de escopo (2026-09-13, GATE-B-CORRECTION-03).** O
        conjunto de jobs afetados passa a ser derivado das linhas
        materializadas e confrontado com jobs_affected; contadores conferidos
        em TODOS os afetados; afetados comparados menos os três campos
        autorizados; NÃO afetados comparados por row INTEIRA, updated_at
        incluído; acrescentada a prova de job NOVO. _jobs_before passa a
        fotografar todos os jobs. BASE3 sai do veredito e fica só no gabarito.
        Nada além de U foi tocado. NÃO EXECUTADO. |
| 3.5 | **Correção do predicado de search_path no caso AB (2026-09-13,
        GATE-B-EXECUTION-02).** Defeito encontrado no postcheck da 2189, ANTES
        de executar o harness: o PostgreSQL grava proconfig como
        'search_path=""' (com aspas), e AB comparava com a literal
        'search_path='. O predicado reprovava funções corretas — medido no LIVE
        contra as duas funções novas E contra
        internal.compute_variant_residual_signature, canônica desde a 2176.
        AB passa a verificar o VALOR (btrim de aspas = ''), não a string.
        Defeito era do teste, não do artefato. Nenhuma outra mudança. |
| 3.6 | **Fixture de Game válida (2026-09-13, GATE-B-CORRECTION-04).** A v3.5
        foi EXECUTADA no LIVE e reprovou 12/29. Duas causas: C1, min(uuid) na
        Query 2189 (corrigida pela Query 2190, fora deste arquivo); e C2, code
        '_HARNESS_2825' recusado por ck_game_code_format = ^[A-Z][A-Z0-9_]*$,
        que reprovava o caso E. Code passa a ser 'HARNESS_GAME_2825' nos três
        pontos: INSERT da fixture, prova de resíduo do caso E e chave
        residuo_game_harness do snapshot. Semântica do caso E inalterada.
        Correção do caso AB (v3.5) preservada. |
===============================================================================
*/

-- =============================================================================
-- SEÇÃO 0 — INFRAESTRUTURA, PRÉ-REQUISITOS E BASELINE
--
-- Só leitura sobre o domínio. Nenhuma fixture de negócio é criada aqui.
-- =============================================================================

CREATE TEMP TABLE _r (
    caso     TEXT PRIMARY KEY,
    veredito TEXT NOT NULL,
    detalhe  TEXT
);

CREATE TEMP TABLE _ctx (k TEXT PRIMARY KEY, v TEXT);

CREATE OR REPLACE FUNCTION pg_temp._chk(p_caso TEXT, p_ok BOOLEAN, p_detalhe TEXT)
RETURNS VOID LANGUAGE plpgsql AS $f$
BEGIN
    INSERT INTO _r(caso, veredito, detalhe)
    VALUES (p_caso, CASE WHEN p_ok THEN 'PASS' ELSE 'FAIL' END, p_detalhe)
    ON CONFLICT (caso) DO UPDATE
       SET veredito = EXCLUDED.veredito, detalhe = EXCLUDED.detalhe;
END;
$f$;

-- Snapshot: UMA definição, usada para a baseline e para o caso Z. Ter uma só
-- elimina a chance de as duas leituras divergirem por edição desatenta.
CREATE OR REPLACE FUNCTION pg_temp._snapshot_2825()
RETURNS TABLE(k TEXT, v TEXT)
LANGUAGE sql AS $snap$
    SELECT 'profiles',
           (SELECT count(*)::TEXT FROM public.card_printing_profile)
    UNION ALL SELECT 'profile_traits',
           (SELECT count(*)::TEXT FROM public.card_printing_profile_trait)
    UNION ALL SELECT 'traits',
           (SELECT count(*)::TEXT FROM public.card_printing_trait)
    UNION ALL SELECT 'games',
           (SELECT count(*)::TEXT FROM public.game)
    UNION ALL SELECT 'card_variants',
           (SELECT count(*)::TEXT FROM public.card_variant)
    UNION ALL SELECT 'staging_rows',
           (SELECT count(*)::TEXT FROM public.catalog_variant_import_row)
    UNION ALL SELECT 'staging_valid',
           (SELECT count(*)::TEXT FROM public.catalog_variant_import_row
             WHERE validation_status = 'VALID')
    UNION ALL SELECT 'staging_needs_review',
           (SELECT count(*)::TEXT FROM public.catalog_variant_import_row
             WHERE validation_status = 'NEEDS_REVIEW')
    UNION ALL SELECT 'action_log',
           (SELECT count(*)::TEXT FROM public.catalog_admin_action_log)
    -- Digest da ROW INTEIRA das linhas de staging dos jobs STAGED.
    --
    -- to_jsonb(r) substitui a enumeração manual de colunas: cobre raw_data,
    -- card_id, decision_status, persistence_status, resulting_variant_id,
    -- normalized_data, validation_status, match_status, matched_variant_id,
    -- error_detail, created_at, updated_at — e qualquer coluna FUTURA, sem
    -- precisar editar este arquivo. Vazamento em qualquer campo faz X e Z
    -- reprovarem. jsonb normaliza a ordem das chaves, então o texto é
    -- determinístico; a comparação é sempre dentro da MESMA sessão, logo nem
    -- DateStyle nem TimeZone podem derivar entre as duas leituras.
    UNION ALL SELECT 'staged_rows_digest',
           (SELECT COALESCE(md5(string_agg(
                       r.id::TEXT || ':' || to_jsonb(r)::TEXT, '|' ORDER BY r.id)), 'VAZIO')
              FROM public.catalog_variant_import_row r
              JOIN public.catalog_variant_import_job j ON j.id = r.job_id
             WHERE j.status = 'STAGED')
    -- Digest da ROW INTEIRA de TODOS os jobs — não só contadores. Pega
    -- vazamento em status, progress_step, rejected/inserted/unchanged/skipped/
    -- failed_rows, error_summary, initiated_by, timestamps e o que vier depois.
    UNION ALL SELECT 'jobs_rows_digest',
           (SELECT COALESCE(md5(string_agg(
                       j.id::TEXT || ':' || to_jsonb(j)::TEXT, '|' ORDER BY j.id)), 'VAZIO')
              FROM public.catalog_variant_import_job j)
    -- Code da fixture de Game: HARNESS_GAME_2825. Precisa satisfazer
    -- ck_game_code_format = ^[A-Z][A-Z0-9_]*$ — a v3.5 usava '_HARNESS_2825',
    -- que começa com underscore e era recusado pela CHECK (GATE-B-EXECUTION-02).
    UNION ALL SELECT 'residuo_game_harness',
           (SELECT count(*)::TEXT FROM public.game WHERE code = 'HARNESS_GAME_2825')
    UNION ALL SELECT 'residuo_profile_harness',
           (SELECT count(*)::TEXT FROM public.card_printing_profile WHERE code LIKE 'HARNESS%')
    UNION ALL SELECT 'residuo_trait_harness',
           (SELECT count(*)::TEXT FROM public.card_printing_trait WHERE code LIKE 'HARNESS%')
$snap$;

CREATE TEMP TABLE _baseline_2825 AS SELECT k, v FROM pg_temp._snapshot_2825();

DO $s0$
DECLARE
    v_admin UUID; v_game UUID; v_fe UUID; v_sl UUID; v_src UUID;
    v_next INTEGER; v_expr TEXT; v_ok BOOLEAN; v_res TEXT;
BEGIN
    -- Resíduo pré-existente contaminaria o caso Z e várias fixtures.
    SELECT string_agg(k || '=' || v, ', ') INTO v_res
      FROM _baseline_2825 WHERE k LIKE 'residuo_%' AND v <> '0';
    IF v_res IS NOT NULL THEN
        RAISE EXCEPTION 'S0 ABORT: já existe resíduo de harness na base (%). Limpe antes de executar — o caso Z não consegue distinguir resíduo antigo de novo.', v_res;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                    WHERE n.nspname='internal' AND p.proname='create_card_printing_profile_with_backfill') THEN
        RAISE EXCEPTION 'S0 ABORT: internal.create_card_printing_profile_with_backfill() não existe. Query 2189 v2.1 não aplicada. NÃO registrar como PASS.';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                    WHERE n.nspname='public' AND p.proname='admin_create_card_printing_profile_with_backfill') THEN
        RAISE EXCEPTION 'S0 ABORT: public.admin_create_card_printing_profile_with_backfill() não existe. Query 2189 v2.1 não aplicada.';
    END IF;

    SELECT pg_get_expr(c.conbin, c.conrelid) INTO v_expr
      FROM pg_constraint c
     WHERE c.conrelid = 'public.catalog_admin_action_log'::regclass
       AND c.conname  = 'ck_catalog_admin_action_log_action_entity_match';

    EXECUTE format('SELECT (%s) FROM (SELECT %L::text AS entity_type, %L::text AS action) t',
                   v_expr, 'CARD_PRINTING_PROFILE', 'CARD_PRINTING_PROFILE_CREATED') INTO v_ok;

    IF v_ok IS NOT TRUE THEN
        RAISE EXCEPTION 'S0 ABORT: Query 2188 não aplicada — o par (CARD_PRINTING_PROFILE, CARD_PRINTING_PROFILE_CREATED) é recusado pela CHECK.';
    END IF;

    -- Administrador REAL, apenas LIDO. Serve de p_actor_id: parâmetro de
    -- auditoria, não identidade de sessão. Nenhum admin é criado.
    SELECT id INTO v_admin FROM public.admin_user ORDER BY id LIMIT 1;
    IF v_admin IS NULL THEN
        RAISE EXCEPTION 'S0 ABORT: nenhum administrador em public.admin_user. O contrato do worker NÃO PODE ser provado nesta base — FAIL HIGH.';
    END IF;

    SELECT id INTO v_game FROM public.game WHERE code = 'POKEMON';
    IF v_game IS NULL THEN RAISE EXCEPTION 'S0 ABORT: Game POKEMON não encontrado.'; END IF;

    SELECT id INTO v_fe FROM public.card_printing_trait WHERE game_id=v_game AND code='FIRST_EDITION';
    SELECT id INTO v_sl FROM public.card_printing_trait WHERE game_id=v_game AND code='SHADOWLESS';
    IF v_fe IS NULL OR v_sl IS NULL THEN
        RAISE EXCEPTION 'S0 ABORT: traits FIRST_EDITION e/ou SHADOWLESS não encontrados.';
    END IF;

    SELECT id INTO v_src FROM public.asset_source WHERE code = 'TCGDEX';
    IF v_src IS NULL THEN RAISE EXCEPTION 'S0 ABORT: asset_source TCGDEX não encontrado.'; END IF;

    SELECT COALESCE(max(display_order), 0) + 1 INTO v_next
      FROM public.card_printing_profile WHERE game_id = v_game;

    INSERT INTO _ctx VALUES
        ('admin', v_admin::TEXT), ('game', v_game::TEXT),
        ('fe', v_fe::TEXT), ('sl', v_sl::TEXT), ('src', v_src::TEXT),
        ('next_order', v_next::TEXT);
END;
$s0$;

-- =============================================================================
-- CASO A — RPC PÚBLICA SEM SESSÃO ADMINISTRATIVA
--
-- Negativo REAL, não simulado: como owner não há sessão de aplicação, logo
-- auth.uid() é NULL e is_admin() é FALSE. A ausência de contexto É a condição
-- do teste — nada é fabricado. A exceção FORBIDDEN já reverte o sub-bloco.
-- =============================================================================
DO $a$
DECLARE
    v_fe UUID; v_ord INTEGER; v_msg TEXT; v_raised BOOLEAN := FALSE;
    v_p0 INTEGER; v_p1 INTEGER; v_l0 INTEGER; v_l1 INTEGER;
BEGIN
    SELECT v::UUID    INTO v_fe  FROM _ctx WHERE k='fe';
    SELECT v::INTEGER INTO v_ord FROM _ctx WHERE k='next_order';

    SELECT count(*) INTO v_p0 FROM public.card_printing_profile;
    SELECT count(*) INTO v_l0 FROM public.catalog_admin_action_log;

    BEGIN
        PERFORM public.admin_create_card_printing_profile_with_backfill(
            'HARNESS_A', 'Harness A', NULL, v_ord, ARRAY[v_fe]);
    EXCEPTION WHEN OTHERS THEN v_raised := TRUE; v_msg := SQLERRM;
    END;

    SELECT count(*) INTO v_p1 FROM public.card_printing_profile;
    SELECT count(*) INTO v_l1 FROM public.catalog_admin_action_log;

    PERFORM pg_temp._chk('A',
        v_raised AND v_msg LIKE '%ADMIN_CREATE_CARD_PRINTING_PROFILE_FORBIDDEN%'
        AND v_p0 = v_p1 AND v_l0 = v_l1
        AND NOT EXISTS (SELECT 1 FROM public.card_printing_profile WHERE code='HARNESS_A'),
        format('exceção=%s | perfis %s->%s | log %s->%s (esperado FORBIDDEN e zero efeito)',
               COALESCE(v_msg,'<nenhuma>'), v_p0, v_p1, v_l0, v_l1));
END;
$a$;

-- =============================================================================
-- CASO AA — ACL
--
-- PUBLIC é grantee de ACL (oid 0), não role operacional: lido por aclexplode
-- sobre COALESCE(proacl, acldefault('f', proowner)) — o COALESCE importa,
-- porque proacl NULL significa "default", e o default de função CONCEDE
-- EXECUTE a PUBLIC. has_function_privilege fica só para roles reais.
-- =============================================================================
DO $aa$
DECLARE
    v_pub OID; v_int OID;
    v_pub_auth BOOLEAN; v_pub_anon BOOLEAN; v_pub_svc BOOLEAN; v_pub_pub BOOLEAN;
    v_int_auth BOOLEAN; v_int_anon BOOLEAN; v_int_svc BOOLEAN; v_int_pub BOOLEAN;
    v_fails TEXT := '';
BEGIN
    SELECT p.oid INTO v_pub FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='public' AND p.proname='admin_create_card_printing_profile_with_backfill';
    SELECT p.oid INTO v_int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='internal' AND p.proname='create_card_printing_profile_with_backfill';

    v_pub_auth := has_function_privilege('authenticated', v_pub, 'EXECUTE');
    v_pub_anon := has_function_privilege('anon',          v_pub, 'EXECUTE');
    v_pub_svc  := has_function_privilege('service_role',  v_pub, 'EXECUTE');
    v_int_auth := has_function_privilege('authenticated', v_int, 'EXECUTE');
    v_int_anon := has_function_privilege('anon',          v_int, 'EXECUTE');
    v_int_svc  := has_function_privilege('service_role',  v_int, 'EXECUTE');

    SELECT EXISTS (
        SELECT 1 FROM pg_proc p
        CROSS JOIN LATERAL aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a
         WHERE p.oid = v_pub AND a.grantee = 0 AND a.privilege_type = 'EXECUTE')
      INTO v_pub_pub;

    SELECT EXISTS (
        SELECT 1 FROM pg_proc p
        CROSS JOIN LATERAL aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a
         WHERE p.oid = v_int AND a.grantee = 0 AND a.privilege_type = 'EXECUTE')
      INTO v_int_pub;

    IF NOT v_pub_auth THEN v_fails := v_fails || 'public/authenticated SEM execute; '; END IF;
    IF v_pub_anon    THEN v_fails := v_fails || 'public/anon COM execute; ';           END IF;
    IF v_pub_svc     THEN v_fails := v_fails || 'public/service_role COM execute; ';   END IF;
    IF v_pub_pub     THEN v_fails := v_fails || 'public/PUBLIC(grantee=0) COM execute; '; END IF;
    IF v_int_auth    THEN v_fails := v_fails || 'internal/authenticated COM execute; ';   END IF;
    IF v_int_anon    THEN v_fails := v_fails || 'internal/anon COM execute; ';            END IF;
    IF v_int_svc     THEN v_fails := v_fails || 'internal/service_role COM execute; ';    END IF;
    IF v_int_pub     THEN v_fails := v_fails || 'internal/PUBLIC(grantee=0) COM execute; '; END IF;

    PERFORM pg_temp._chk('AA', v_fails = '',
        COALESCE(NULLIF(v_fails,''),
        'public: authenticated=SIM; anon/service_role/PUBLIC(acl)=NÃO | internal: authenticated/anon/service_role/PUBLIC(acl)=NÃO'));
END;
$aa$;

-- =============================================================================
-- CASO AB — PROVA ESTÁTICA DO WRAPPER
--
-- O caminho POSITIVO da RPC pública exige sessão administrativa real e NÃO é
-- simulado. Prova-se que o wrapper é fino e correto, por leitura do catálogo.
-- =============================================================================
DO $ab$
DECLARE v_src TEXT; v_def BOOLEAN; v_cfg TEXT[]; v_sp_ok BOOLEAN; v_fails TEXT := '';
BEGIN
    SELECT p.prosrc, p.prosecdef, p.proconfig INTO v_src, v_def, v_cfg
      FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='public' AND p.proname='admin_create_card_printing_profile_with_backfill';

    IF v_src NOT LIKE '%public.is_admin()%' THEN v_fails := v_fails || 'não chama public.is_admin(); '; END IF;
    IF v_src NOT LIKE '%auth.uid()%'        THEN v_fails := v_fails || 'não usa auth.uid(); ';          END IF;
    IF v_src NOT LIKE '%internal.create_card_printing_profile_with_backfill%'
        THEN v_fails := v_fails || 'não delega ao worker; '; END IF;
    IF NOT v_def THEN v_fails := v_fails || 'não é SECURITY DEFINER; '; END IF;

    -- search_path vazio, verificado por VALOR e não por string literal.
    -- Medido no LIVE em 2026-09-13: o PostgreSQL grava proconfig como
    -- 'search_path=""' (com aspas), não 'search_path='. Comparar com a
    -- literal 'search_path=' reprovava funções corretas — inclusive
    -- internal.compute_variant_residual_signature, canônica desde a 2176.
    -- Defeito era do predicado, não do artefato.
    SELECT EXISTS (
        SELECT 1 FROM unnest(COALESCE(v_cfg, '{}'::TEXT[])) AS c
         WHERE c LIKE 'search_path=%'
           AND btrim(split_part(c, '=', 2), '"') = ''
    ) INTO v_sp_ok;

    IF NOT v_sp_ok THEN
        v_fails := v_fails || format('search_path não está vazio (proconfig=%s); ', COALESCE(v_cfg::TEXT,'<null>'));
    END IF;

    IF v_src ~* 'INSERT\s+INTO\s+public\.card_printing_profile'
       OR v_src ~* 'UPDATE\s+public\.catalog_variant_import_row'
       OR v_src ~* 'SET\s+CONSTRAINTS'
       OR v_src ~* 'catalog_admin_action_log' THEN
        v_fails := v_fails || 'wrapper contém lógica de Profile/backfill/log (duplicação); ';
    END IF;

    PERFORM pg_temp._chk('AB', v_fails = '',
        COALESCE(NULLIF(v_fails,''),
        'wrapper fino: is_admin + auth.uid + delegação, SECURITY DEFINER, search_path vazio, zero lógica duplicada'));
END;
$ab$;

-- =============================================================================
-- CASO AC — GUARDS DE p_actor_id NO WORKER
-- =============================================================================
DO $ac$
DECLARE v_fe UUID; v_ord INTEGER; v_fails TEXT := '';
BEGIN
    SELECT v::UUID INTO v_fe FROM _ctx WHERE k='fe';
    SELECT v::INTEGER INTO v_ord FROM _ctx WHERE k='next_order';

    BEGIN
        PERFORM internal.create_card_printing_profile_with_backfill(
            NULL, 'HARNESS_AC1','AC1',NULL,v_ord, ARRAY[v_fe]);
        v_fails := v_fails || 'AC1(sem exceção) ';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM NOT LIKE '%MISSING_ACTOR%' THEN v_fails := v_fails || 'AC1(' || SQLERRM || ') '; END IF;
    END;

    BEGIN
        PERFORM internal.create_card_printing_profile_with_backfill(
            '00000000-0000-0000-0000-0000000000aa'::UUID,
            'HARNESS_AC2','AC2',NULL,v_ord, ARRAY[v_fe]);
        v_fails := v_fails || 'AC2(sem exceção) ';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM NOT LIKE '%ACTOR_NOT_ADMIN%' THEN v_fails := v_fails || 'AC2(' || SQLERRM || ') '; END IF;
    END;

    IF EXISTS (SELECT 1 FROM public.card_printing_profile WHERE code LIKE 'HARNESS_AC%') THEN
        v_fails := v_fails || 'AC(resíduo de Perfil) ';
    END IF;

    PERFORM pg_temp._chk('AC', v_fails = '',
        COALESCE(NULLIF(v_fails,''), 'AC1/AC2 abortaram com o código esperado, sem resíduo'));
END;
$ac$;

-- =============================================================================
-- CASO B — GUARDS DE ARRAY (5 sub-casos, todos precisam abortar)
-- =============================================================================
DO $b$
DECLARE v_ad UUID; v_fe UUID; v_ord INTEGER; v_fails TEXT := '';
BEGIN
    SELECT v::UUID INTO v_ad FROM _ctx WHERE k='admin';
    SELECT v::UUID INTO v_fe FROM _ctx WHERE k='fe';
    SELECT v::INTEGER INTO v_ord FROM _ctx WHERE k='next_order';

    BEGIN PERFORM internal.create_card_printing_profile_with_backfill(v_ad,'HARNESS_B1','B1',NULL,v_ord,NULL);
        v_fails := v_fails || 'B1(sem exceção) ';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM NOT LIKE '%MISSING_TRAITS%' THEN v_fails := v_fails||'B1('||SQLERRM||') '; END IF; END;

    BEGIN PERFORM internal.create_card_printing_profile_with_backfill(v_ad,'HARNESS_B2','B2',NULL,v_ord,ARRAY[]::UUID[]);
        v_fails := v_fails || 'B2(sem exceção) ';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM NOT LIKE '%MISSING_TRAITS%' THEN v_fails := v_fails||'B2('||SQLERRM||') '; END IF; END;

    BEGIN PERFORM internal.create_card_printing_profile_with_backfill(v_ad,'HARNESS_B3','B3',NULL,v_ord,ARRAY[ARRAY[v_fe],ARRAY[v_fe]]);
        v_fails := v_fails || 'B3(sem exceção) ';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM NOT LIKE '%INVALID_ARRAY_SHAPE%' THEN v_fails := v_fails||'B3('||SQLERRM||') '; END IF; END;

    BEGIN PERFORM internal.create_card_printing_profile_with_backfill(v_ad,'HARNESS_B4','B4',NULL,v_ord,ARRAY[v_fe,NULL]::UUID[]);
        v_fails := v_fails || 'B4(sem exceção) ';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM NOT LIKE '%NULL_TRAIT%' THEN v_fails := v_fails||'B4('||SQLERRM||') '; END IF; END;

    BEGIN PERFORM internal.create_card_printing_profile_with_backfill(v_ad,'HARNESS_B5','B5',NULL,v_ord,ARRAY[v_fe,v_fe]);
        v_fails := v_fails || 'B5(sem exceção) ';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM NOT LIKE '%DUPLICATE_TRAIT%' THEN v_fails := v_fails||'B5('||SQLERRM||') '; END IF; END;

    IF EXISTS (SELECT 1 FROM public.card_printing_profile WHERE code LIKE 'HARNESS_B%') THEN
        v_fails := v_fails || 'B(resíduo de Perfil) ';
    END IF;

    PERFORM pg_temp._chk('B', v_fails = '',
        COALESCE(NULLIF(v_fails,''), 'B1..B5 abortaram com o código esperado, sem resíduo'));
END;
$b$;

-- =============================================================================
-- CASO C — TRAIT INEXISTENTE (negativo puro, não escreve)
-- =============================================================================
DO $c$
DECLARE v_ad UUID; v_ord INTEGER; v_msg TEXT; v_raised BOOLEAN := FALSE;
BEGIN
    SELECT v::UUID INTO v_ad FROM _ctx WHERE k='admin';
    SELECT v::INTEGER INTO v_ord FROM _ctx WHERE k='next_order';
    BEGIN
        PERFORM internal.create_card_printing_profile_with_backfill(
            v_ad,'HARNESS_C','C',NULL,v_ord, ARRAY['00000000-0000-0000-0000-0000000000ff'::UUID]);
    EXCEPTION WHEN OTHERS THEN v_raised := TRUE; v_msg := SQLERRM; END;

    PERFORM pg_temp._chk('C',
        v_raised AND v_msg LIKE '%TRAIT_NOT_FOUND%'
        AND NOT EXISTS (SELECT 1 FROM public.card_printing_profile WHERE code='HARNESS_C'),
        COALESCE(v_msg,'sem exceção'));
END;
$c$;

-- =============================================================================
-- CASO D — TRAIT INATIVO   [fixture local, revertida por sentinela]
--
-- O trait inativo nasce e morre dentro deste sub-bloco. Nada de fixture global.
-- =============================================================================
DO $d$
DECLARE
    v_ad UUID; v_game UUID; v_ord INTEGER; v_t UUID;
    v_msg TEXT; v_raised BOOLEAN := FALSE; v_rolled BOOLEAN := FALSE; v_fails TEXT := '';
BEGIN
    SELECT v::UUID INTO v_ad   FROM _ctx WHERE k='admin';
    SELECT v::UUID INTO v_game FROM _ctx WHERE k='game';
    SELECT v::INTEGER INTO v_ord FROM _ctx WHERE k='next_order';

    BEGIN
        INSERT INTO public.card_printing_trait
            (id, game_id, code, name, display_order, is_active, created_at, updated_at)
        VALUES (gen_random_uuid(), v_game, 'HARNESS_INACTIVE', 'Inativo', 9001, FALSE, now(), now())
        RETURNING id INTO v_t;

        BEGIN
            PERFORM internal.create_card_printing_profile_with_backfill(
                v_ad,'HARNESS_D','D',NULL,v_ord, ARRAY[v_t]);
        EXCEPTION WHEN OTHERS THEN v_raised := TRUE; v_msg := SQLERRM;
        END;

        RAISE EXCEPTION 'HARNESS_D_ROLLBACK';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM = 'HARNESS_D_ROLLBACK' THEN v_rolled := TRUE;
        ELSE v_fails := v_fails || 'D(exceção inesperada: ' || SQLERRM || ') '; END IF;
    END;

    IF NOT v_raised OR v_msg NOT LIKE '%TRAIT_INACTIVE%' THEN
        v_fails := v_fails || 'D(esperado TRAIT_INACTIVE, obtido: ' || COALESCE(v_msg,'sem exceção') || ') ';
    END IF;
    IF NOT v_rolled THEN v_fails := v_fails || 'D(sentinela não disparou) '; END IF;
    IF EXISTS (SELECT 1 FROM public.card_printing_trait WHERE code='HARNESS_INACTIVE') THEN
        v_fails := v_fails || 'D(trait de fixture sobreviveu) ';
    END IF;

    PERFORM pg_temp._chk('D', v_fails = '',
        COALESCE(NULLIF(v_fails,''), 'TRAIT_INACTIVE levantado; trait de fixture criado e revertido'));
END;
$d$;

-- =============================================================================
-- CASO E — MIXED GAME   [Game + trait locais, revertidos por sentinela]
-- =============================================================================
DO $e$
DECLARE
    v_ad UUID; v_fe UUID; v_ord INTEGER; v_game2 UUID; v_other UUID;
    v_msg TEXT; v_raised BOOLEAN := FALSE; v_rolled BOOLEAN := FALSE; v_fails TEXT := '';
BEGIN
    SELECT v::UUID INTO v_ad FROM _ctx WHERE k='admin';
    SELECT v::UUID INTO v_fe FROM _ctx WHERE k='fe';
    SELECT v::INTEGER INTO v_ord FROM _ctx WHERE k='next_order';

    BEGIN
        INSERT INTO public.game (code, name) VALUES ('HARNESS_GAME_2825', 'Harness 2825')
        RETURNING id INTO v_game2;

        INSERT INTO public.card_printing_trait
            (id, game_id, code, name, display_order, is_active, created_at, updated_at)
        VALUES (gen_random_uuid(), v_game2, 'HARNESS_OTHER_GAME', 'Outro Game', 1, TRUE, now(), now())
        RETURNING id INTO v_other;

        BEGIN
            PERFORM internal.create_card_printing_profile_with_backfill(
                v_ad,'HARNESS_E','E',NULL,v_ord, ARRAY[v_fe, v_other]);
        EXCEPTION WHEN OTHERS THEN v_raised := TRUE; v_msg := SQLERRM;
        END;

        RAISE EXCEPTION 'HARNESS_E_ROLLBACK';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM = 'HARNESS_E_ROLLBACK' THEN v_rolled := TRUE;
        ELSE v_fails := v_fails || 'E(exceção inesperada: ' || SQLERRM || ') '; END IF;
    END;

    IF NOT v_raised OR v_msg NOT LIKE '%MIXED_GAME%' THEN
        v_fails := v_fails || 'E(esperado MIXED_GAME, obtido: ' || COALESCE(v_msg,'sem exceção') || ') ';
    END IF;
    IF NOT v_rolled THEN v_fails := v_fails || 'E(sentinela não disparou) '; END IF;
    IF EXISTS (SELECT 1 FROM public.game WHERE code='HARNESS_GAME_2825') THEN
        v_fails := v_fails || 'E(Game de fixture sobreviveu) ';
    END IF;
    IF EXISTS (SELECT 1 FROM public.card_printing_trait WHERE code='HARNESS_OTHER_GAME') THEN
        v_fails := v_fails || 'E(trait de fixture sobreviveu) ';
    END IF;

    PERFORM pg_temp._chk('E', v_fails = '',
        COALESCE(NULLIF(v_fails,''), 'MIXED_GAME levantado; Game e trait de fixture criados e revertidos'));
END;
$e$;

-- =============================================================================
-- CASOS F, G, H, I — DUPLICIDADES E COMPOSIÇÃO VAZIA
-- =============================================================================
DO $fghi$
DECLARE
    v_ad UUID; v_game UUID; v_fe UUID; v_ord INTEGER;
    v_sig UUID[]; v_id UUID; v_msg TEXT; v_raised BOOLEAN;
BEGIN
    SELECT v::UUID INTO v_ad FROM _ctx WHERE k='admin';
    SELECT v::UUID INTO v_game FROM _ctx WHERE k='game';
    SELECT v::UUID INTO v_fe FROM _ctx WHERE k='fe';
    SELECT v::INTEGER INTO v_ord FROM _ctx WHERE k='next_order';

    v_raised := FALSE;
    BEGIN PERFORM internal.create_card_printing_profile_with_backfill(v_ad,'UNLIMITED','Dup','x',v_ord, ARRAY[v_fe]);
    EXCEPTION WHEN OTHERS THEN v_raised := TRUE; v_msg := SQLERRM; END;
    PERFORM pg_temp._chk('F', v_raised AND v_msg LIKE '%DUPLICATE_CODE%', COALESCE(v_msg,'sem exceção'));

    v_raised := FALSE;
    BEGIN PERFORM internal.create_card_printing_profile_with_backfill(v_ad,'HARNESS_G','G','x',1, ARRAY[v_fe]);
    EXCEPTION WHEN OTHERS THEN v_raised := TRUE; v_msg := SQLERRM; END;
    PERFORM pg_temp._chk('G',
        v_raised AND v_msg LIKE '%DUPLICATE_DISPLAY_ORDER%'
        AND NOT EXISTS (SELECT 1 FROM public.card_printing_profile WHERE code='HARNESS_G'),
        COALESCE(v_msg,'sem exceção'));

    -- H: guard da própria tabela, sem passar pelo worker. O INSERT é real; a
    -- exceção do selo reverte o sub-bloco.
    v_raised := FALSE;
    BEGIN
        INSERT INTO public.card_printing_profile (game_id, code, name, display_order)
        VALUES (v_game, 'HARNESS_H', 'H', v_ord) RETURNING id INTO v_id;
        SET CONSTRAINTS public.trg_card_printing_profile_seal IMMEDIATE;
    EXCEPTION WHEN OTHERS THEN v_raised := TRUE; v_msg := SQLERRM; END;
    SET CONSTRAINTS public.trg_card_printing_profile_seal DEFERRED;
    PERFORM pg_temp._chk('H',
        v_raised AND v_msg LIKE '%EMPTY_COMPOSITION%'
        AND NOT EXISTS (SELECT 1 FROM public.card_printing_profile WHERE code='HARNESS_H'),
        COALESCE(v_msg,'sem exceção'));

    SELECT traits_signature INTO v_sig FROM public.card_printing_profile WHERE code='UNLIMITED';
    v_raised := FALSE;
    BEGIN PERFORM internal.create_card_printing_profile_with_backfill(v_ad,'HARNESS_I','I',NULL,v_ord, v_sig);
    EXCEPTION WHEN OTHERS THEN v_raised := TRUE; v_msg := SQLERRM; END;
    PERFORM pg_temp._chk('I',
        v_raised AND v_msg LIKE '%DUPLICATE_SIGNATURE%'
        AND NOT EXISTS (SELECT 1 FROM public.card_printing_profile WHERE code='HARNESS_I'),
        COALESCE(v_msg,'sem exceção'));
END;
$fghi$;

-- =============================================================================
-- CASOS J, K — SELO FALSIFICADO E IMUTABILIDADE PÓS-SELO
--
-- Todas as tentativas escrevem sobre um Perfil REAL (UNLIMITED). Cada uma vive
-- em seu sub-bloco e é revertida pela própria exceção do guard. Ao final,
-- confere-se que o Perfil real seguiu intacto.
-- =============================================================================
DO $jk$
DECLARE
    v_p UUID; v_sl UUID; v_msg TEXT; v_raised BOOLEAN; v_fails TEXT := '';
    v_sig_antes UUID[]; v_sig_depois UUID[]; v_comp_antes INTEGER; v_comp_depois INTEGER;
BEGIN
    SELECT id, traits_signature INTO v_p, v_sig_antes
      FROM public.card_printing_profile WHERE code='UNLIMITED';
    SELECT v::UUID INTO v_sl FROM _ctx WHERE k='sl';
    SELECT count(*) INTO v_comp_antes
      FROM public.card_printing_profile_trait WHERE profile_id = v_p;

    v_raised := FALSE;
    BEGIN UPDATE public.card_printing_profile SET traits_signature = ARRAY[v_sl] WHERE id = v_p;
    EXCEPTION WHEN OTHERS THEN v_raised := TRUE; v_msg := SQLERRM; END;
    PERFORM pg_temp._chk('J', v_raised AND v_msg LIKE '%SIGNATURE_IMMUTABLE%', COALESCE(v_msg,'sem exceção'));

    v_raised := FALSE;
    BEGIN
        INSERT INTO public.card_printing_profile_trait (profile_id, trait_id, game_id)
        SELECT v_p, v_sl, p.game_id FROM public.card_printing_profile p WHERE p.id = v_p;
    EXCEPTION WHEN OTHERS THEN v_raised := TRUE; v_msg := SQLERRM; END;
    IF NOT (v_raised AND v_msg LIKE '%COMPOSITION_SEALED%') THEN
        v_fails := v_fails || 'K1(' || COALESCE(v_msg,'sem exceção') || ') ';
    END IF;

    v_raised := FALSE;
    BEGIN DELETE FROM public.card_printing_profile_trait WHERE profile_id = v_p;
    EXCEPTION WHEN OTHERS THEN v_raised := TRUE; v_msg := SQLERRM; END;
    IF NOT (v_raised AND v_msg LIKE '%COMPOSITION_SEALED%') THEN
        v_fails := v_fails || 'K2(' || COALESCE(v_msg,'sem exceção') || ') ';
    END IF;

    v_raised := FALSE;
    BEGIN UPDATE public.card_printing_profile_trait SET trait_id = v_sl WHERE profile_id = v_p;
    EXCEPTION WHEN OTHERS THEN v_raised := TRUE; v_msg := SQLERRM; END;
    IF NOT (v_raised AND v_msg LIKE '%UPDATE_FORBIDDEN%') THEN
        v_fails := v_fails || 'K3(' || COALESCE(v_msg,'sem exceção') || ') ';
    END IF;

    SELECT traits_signature INTO v_sig_depois FROM public.card_printing_profile WHERE id = v_p;
    SELECT count(*) INTO v_comp_depois
      FROM public.card_printing_profile_trait WHERE profile_id = v_p;

    IF v_sig_depois IS DISTINCT FROM v_sig_antes THEN
        v_fails := v_fails || 'K(assinatura de UNLIMITED foi alterada) ';
    END IF;
    IF v_comp_depois <> v_comp_antes THEN
        v_fails := v_fails || format('K(composição de UNLIMITED %s->%s) ', v_comp_antes, v_comp_depois);
    END IF;

    PERFORM pg_temp._chk('K', v_fails = '',
        COALESCE(NULLIF(v_fails,''), 'K1/K2/K3 abortaram como esperado e UNLIMITED ficou intacto'));
END;
$jk$;

-- =============================================================================
-- CASO L — PROVA CRÍTICA DO SELO DIFERIDO   [write + sentinela]
--
-- L1: sem SET CONSTRAINTS IMMEDIATE, traits_signature é NULL e
--     compute_variant_residual_signature NÃO encontra o Perfil.
-- L2: depois do IMMEDIATE, a assinatura existe e a mesma linha resolve.
--
-- Prova de que o PASSO 3 da Query 2189 não é decorativo. O Perfil criado aqui
-- ocuparia a display_order e a assinatura que X e MAIN vão usar: a sentinela
-- devolve as duas.
-- =============================================================================
DO $l$
DECLARE
    v_game UUID; v_ord INTEGER; v_fe UUID; v_id UUID; v_src UUID; v_raw JSONB;
    v_sig_before UUID[]; v_sig_after UUID[];
    v_res_before UUID; v_res_after UUID;
    v_fails TEXT := ''; v_rolled BOOLEAN := FALSE;
BEGIN
    SELECT v::UUID INTO v_game FROM _ctx WHERE k='game';
    SELECT v::UUID INTO v_fe   FROM _ctx WHERE k='fe';
    SELECT v::UUID INTO v_src  FROM _ctx WHERE k='src';
    SELECT v::INTEGER INTO v_ord FROM _ctx WHERE k='next_order';

    SELECT r.raw_data INTO v_raw
      FROM public.catalog_variant_import_row r
      JOIN public.catalog_variant_import_job j ON j.id = r.job_id
      CROSS JOIN LATERAL internal.compute_variant_residual_signature(r.raw_data, v_game, v_src) s
     WHERE j.status = 'STAGED'
       AND s.printing_state = 'NEEDS_REVIEW_NO_PROFILE'
       AND s.trait_ids = ARRAY[v_fe]
     LIMIT 1;

    IF v_raw IS NULL THEN
        PERFORM pg_temp._chk('L', FALSE,
            'nenhuma linha com assinatura {FIRST_EDITION} encontrada — o caso L não pode ser provado nesta base');
        RETURN;
    END IF;

    BEGIN
        INSERT INTO public.card_printing_profile (game_id, code, name, display_order)
        VALUES (v_game, 'HARNESS_L', 'L', v_ord) RETURNING id INTO v_id;

        INSERT INTO public.card_printing_profile_trait (profile_id, trait_id, game_id)
        VALUES (v_id, v_fe, v_game);

        SELECT traits_signature INTO v_sig_before FROM public.card_printing_profile WHERE id = v_id;
        SELECT s.printing_profile_id INTO v_res_before
          FROM internal.compute_variant_residual_signature(v_raw, v_game, v_src) s;

        IF v_sig_before IS NOT NULL THEN
            v_fails := v_fails || 'L1(assinatura materializada ANTES do IMMEDIATE — premissa do desenho mudou) ';
        END IF;
        IF v_res_before IS NOT NULL THEN
            v_fails := v_fails || 'L1(resolvedor já encontrou Perfil antes do selo) ';
        END IF;

        SET CONSTRAINTS public.trg_card_printing_profile_seal IMMEDIATE;

        SELECT traits_signature INTO v_sig_after FROM public.card_printing_profile WHERE id = v_id;
        SELECT s.printing_profile_id INTO v_res_after
          FROM internal.compute_variant_residual_signature(v_raw, v_game, v_src) s;

        IF v_sig_after IS DISTINCT FROM ARRAY[v_fe] THEN
            v_fails := v_fails || 'L2(assinatura não materializada após IMMEDIATE) ';
        END IF;
        IF v_res_after IS DISTINCT FROM v_id THEN
            v_fails := v_fails || 'L2(resolvedor não encontrou o Perfil recém-selado) ';
        END IF;

        SET CONSTRAINTS public.trg_card_printing_profile_seal DEFERRED;
        RAISE EXCEPTION 'HARNESS_L_ROLLBACK';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM = 'HARNESS_L_ROLLBACK' THEN v_rolled := TRUE;
        ELSE v_fails := v_fails || 'L(exceção inesperada: ' || SQLERRM || ') '; END IF;
    END;

    SET CONSTRAINTS public.trg_card_printing_profile_seal DEFERRED;

    IF NOT v_rolled THEN v_fails := v_fails || 'L(sentinela não disparou) '; END IF;
    IF EXISTS (SELECT 1 FROM public.card_printing_profile WHERE code='HARNESS_L') THEN
        v_fails := v_fails || 'L(HARNESS_L sobreviveu ao sub-bloco) ';
    END IF;

    PERFORM pg_temp._chk('L', v_fails = '',
        COALESCE(NULLIF(v_fails,''),
        'antes do IMMEDIATE: signature NULL e profile NULL; depois: signature {FIRST_EDITION} e profile resolvido; tudo revertido'));
END;
$l$;

-- =============================================================================
-- CASO X — ATOMICIDADE COM ABORT DEPOIS DE ESCREVER
--
-- Roda ANTES do bloco MAIN e usa FIRST_EDITION de propósito: assim o worker
-- executa o caminho COMPLETO e COM EFEITO REAL (Perfil + composição + selo +
-- backfill das linhas + contadores de job + action log). Só DEPOIS de PROVAR
-- que escreveu é que a sentinela dispara.
--
-- O que se prova não é guard de entrada — é que o conjunto inteiro de writes
-- do worker desaparece junto quando a subtransação aborta.
--
-- Efeito colateral desejado: como X reverte, FIRST_EDITION volta a estar livre
-- para o bloco MAIN. Se X não revertesse, MAIN falharia com DUPLICATE_SIGNATURE
-- — ou seja, o sucesso do resto do harness depende de X ter revertido de fato.
-- =============================================================================
DO $x$
DECLARE
    v_ad UUID; v_fe UUID; v_ord INTEGER;
    v_pid UUID; v_touched INTEGER; v_wrote_rows INTEGER;
    v_wrote_log INTEGER; v_wrote_comp INTEGER;
    v_fails TEXT := ''; v_rolled BOOLEAN := FALSE;
    b RECORD; a RECORD;
BEGIN
    SELECT v::UUID INTO v_ad FROM _ctx WHERE k='admin';
    SELECT v::UUID INTO v_fe FROM _ctx WHERE k='fe';
    SELECT v::INTEGER INTO v_ord FROM _ctx WHERE k='next_order';

    SELECT
        (SELECT count(*) FROM public.card_printing_profile)              AS prof,
        (SELECT count(*) FROM public.card_printing_profile_trait)        AS comp,
        (SELECT count(*) FROM public.card_variant)                       AS cv,
        (SELECT count(*) FROM public.catalog_admin_action_log)           AS log,
        (SELECT count(*) FROM public.catalog_variant_import_row
          WHERE validation_status='VALID')                               AS valid,
        -- Digests de ROW INTEIRA, medidos AO VIVO aqui e não lidos da baseline:
        -- o caso X compara consigo mesmo e não pressupõe que os casos
        -- anteriores tenham revertido.
        (SELECT COALESCE(md5(string_agg(r.id::TEXT||':'||to_jsonb(r)::TEXT,'|' ORDER BY r.id)),'VAZIO')
           FROM public.catalog_variant_import_row r
           JOIN public.catalog_variant_import_job j ON j.id=r.job_id
          WHERE j.status='STAGED')                                       AS rows_digest,
        (SELECT COALESCE(md5(string_agg(j.id::TEXT||':'||to_jsonb(j)::TEXT,'|' ORDER BY j.id)),'VAZIO')
           FROM public.catalog_variant_import_job j)                     AS jobs_digest
      INTO b;

    BEGIN
        SELECT w.profile_id, w.rows_touched
          INTO v_pid, v_touched
          FROM internal.create_card_printing_profile_with_backfill(
                   v_ad, 'HARNESS_X', 'Harness X — atomicidade',
                   'Perfil criado só para provar rollback pós-escrita.',
                   v_ord, ARRAY[v_fe]) w;

        -- PROVA DE QUE ESCREVEU. Sem isto, "nada sobreviveu" seria trivial.
        IF v_pid IS NULL THEN v_fails := v_fails || 'X(worker não retornou profile_id) '; END IF;

        SELECT count(*) INTO v_wrote_comp
          FROM public.card_printing_profile_trait WHERE profile_id = v_pid;
        IF v_wrote_comp <> 1 THEN
            v_fails := v_fails || format('X(composição escrita=%s, esperado 1) ', v_wrote_comp);
        END IF;

        SELECT count(*) INTO v_wrote_log
          FROM public.catalog_admin_action_log
         WHERE action='CARD_PRINTING_PROFILE_CREATED' AND entity_id = v_pid;
        IF v_wrote_log <> 1 THEN
            v_fails := v_fails || format('X(eventos de log=%s, esperado 1) ', v_wrote_log);
        END IF;

        SELECT count(*) INTO v_wrote_rows
          FROM public.catalog_variant_import_row r
         WHERE jsonb_typeof(r.normalized_data->'printing_profile_id')='string'
           AND (r.normalized_data->>'printing_profile_id')::UUID = v_pid;
        IF v_touched = 0 THEN
            v_fails := v_fails || 'X(rows_touched=0 — o backfill não foi exercitado; a prova de atomicidade ficaria parcial) ';
        ELSIF v_wrote_rows <> v_touched THEN
            v_fails := v_fails || format('X(linhas materializadas=%s, rows_touched=%s) ', v_wrote_rows, v_touched);
        END IF;

        -- Staging e jobs precisam ter MUDADO neste ponto.
        IF (SELECT COALESCE(md5(string_agg(r.id::TEXT||':'||to_jsonb(r)::TEXT,'|' ORDER BY r.id)),'VAZIO')
              FROM public.catalog_variant_import_row r
              JOIN public.catalog_variant_import_job j ON j.id=r.job_id
             WHERE j.status='STAGED') = b.rows_digest THEN
            v_fails := v_fails || 'X(digest de staging NÃO mudou durante a escrita — o backfill não teve efeito) ';
        END IF;

        IF (SELECT COALESCE(md5(string_agg(j.id::TEXT||':'||to_jsonb(j)::TEXT,'|' ORDER BY j.id)),'VAZIO')
              FROM public.catalog_variant_import_job j) = b.jobs_digest THEN
            v_fails := v_fails || 'X(digest dos jobs NÃO mudou durante a escrita — os contadores não foram recalculados) ';
        END IF;

        RAISE EXCEPTION 'HARNESS_X_FORCED_ROLLBACK';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM = 'HARNESS_X_FORCED_ROLLBACK' THEN v_rolled := TRUE;
        ELSE v_fails := v_fails || 'X(exceção inesperada: ' || SQLERRM || ') '; END IF;
    END;

    SET CONSTRAINTS public.trg_card_printing_profile_seal DEFERRED;

    IF NOT v_rolled THEN v_fails := v_fails || 'X(sentinela não disparou) '; END IF;

    SELECT
        (SELECT count(*) FROM public.card_printing_profile)              AS prof,
        (SELECT count(*) FROM public.card_printing_profile_trait)        AS comp,
        (SELECT count(*) FROM public.card_variant)                       AS cv,
        (SELECT count(*) FROM public.catalog_admin_action_log)           AS log,
        (SELECT count(*) FROM public.catalog_variant_import_row
          WHERE validation_status='VALID')                               AS valid,
        (SELECT COALESCE(md5(string_agg(r.id::TEXT||':'||to_jsonb(r)::TEXT,'|' ORDER BY r.id)),'VAZIO')
           FROM public.catalog_variant_import_row r
           JOIN public.catalog_variant_import_job j ON j.id=r.job_id
          WHERE j.status='STAGED')                                       AS rows_digest,
        (SELECT COALESCE(md5(string_agg(j.id::TEXT||':'||to_jsonb(j)::TEXT,'|' ORDER BY j.id)),'VAZIO')
           FROM public.catalog_variant_import_job j)                     AS jobs_digest
      INTO a;

    IF a.prof        <> b.prof        THEN v_fails := v_fails || format('X(perfis %s->%s) ', b.prof, a.prof); END IF;
    IF a.comp        <> b.comp        THEN v_fails := v_fails || format('X(composições %s->%s) ', b.comp, a.comp); END IF;
    IF a.cv          <> b.cv          THEN v_fails := v_fails || format('X(card_variant %s->%s) ', b.cv, a.cv); END IF;
    IF a.log         <> b.log         THEN v_fails := v_fails || format('X(action log %s->%s) ', b.log, a.log); END IF;
    IF a.valid       <> b.valid       THEN v_fails := v_fails || format('X(staging VALID %s->%s) ', b.valid, a.valid); END IF;
    IF a.rows_digest <> b.rows_digest THEN v_fails := v_fails || 'X(digest das linhas de staging não voltou) '; END IF;
    IF a.jobs_digest <> b.jobs_digest THEN v_fails := v_fails || 'X(contadores de job não voltaram) '; END IF;

    IF EXISTS (SELECT 1 FROM public.card_printing_profile WHERE code='HARNESS_X') THEN
        v_fails := v_fails || 'X(HARNESS_X sobreviveu) ';
    END IF;

    PERFORM pg_temp._chk('X', v_fails = '',
        COALESCE(NULLIF(v_fails,''),
        format('worker escreveu de fato (profile + 1 composição + 1 log + %s linhas, digest de staging alterado) e NADA sobreviveu ao abort',
               v_touched)));
END;
$x$;

-- =============================================================================
-- BLOCO MAIN — CENÁRIO POSITIVO COMPLETO (M..V, W, Y) EM UMA SUBTRANSAÇÃO
--
-- O worker é chamado DIRETAMENTE, como owner, com p_actor_id = admin real lido
-- na Seção 0. Nenhum contexto de sessão é fabricado.
--
-- Todos os doze casos são avaliados DENTRO da subtransação; os vereditos saem
-- em variável JSONB (não transacional) e só são gravados em _r depois que a
-- sentinela reverteu tudo — gravar em _r lá dentro seria revertido junto.
--
-- Só é possível porque o caso X reverteu: FIRST_EDITION está livre de novo.
-- =============================================================================

-- Congela FORA do sub-bloco as fotos que precisam sobreviver à reversão.
--
-- _n_before (caso N): ROW INTEIRA das linhas NÃO elegíveis. to_jsonb(r) cobre
-- raw_data, card_id, decision_status, persistence_status, resulting_variant_id,
-- normalized_data, validation_status, match_status, matched_variant_id,
-- error_detail, created_at, updated_at e qualquer coluna futura — sem
-- enumeração manual e sem ponto cego.
CREATE TEMP TABLE _n_before AS
  SELECT r.id, to_jsonb(r) AS snapshot
    FROM public.catalog_variant_import_row r
    JOIN public.catalog_variant_import_job j ON j.id = r.job_id
   WHERE j.status = 'STAGED'
     AND NOT (r.decision_status='PENDING' AND r.persistence_status='PENDING');

-- _jobs_before (caso U): ROW INTEIRA de TODOS os jobs, sem filtro de status.
--
-- O mandato permitia fotografar só os STAGED. Fotografar TODOS é estritamente
-- mais forte e custa o mesmo: (a) a comparação de row inteira dos jobs NÃO
-- afetados passa a cobrir também os que não estão em STAGED; (b) a prova de
-- "job novo" fica exata para qualquer status, em vez de acusar falso positivo
-- para um job que já existisse fora de STAGED.
--
-- Campos autorizados a mudar, e SOMENTE nos jobs afetados: total_rows,
-- valid_rows (o worker recalcula) e updated_at (trigger legítimo
-- trg_catalog_variant_import_job_set_updated_at, Query 2137). Em job não
-- afetado nem esses três podem mudar — nem ser tocado ele pode.
CREATE TEMP TABLE _jobs_before AS
  SELECT j.id, to_jsonb(j) AS snapshot
    FROM public.catalog_variant_import_job j;

DO $main$
DECLARE
    v_ad UUID; v_game UUID; v_fe UUID; v_sl UUID; v_ord INTEGER; v_base3 UUID;
    v_pid UUID; v_t INTEGER; v_rv INTEGER; v_sp INTEGER; v_ja INTEGER;
    v_bv INTEGER; v_bn INTEGER; v_av INTEGER; v_an INTEGER;
    v_cv_base INTEGER; v_n INTEGER; v_matched INTEGER;
    v_out JSONB := '[]'::JSONB;
    v_rolled BOOLEAN := FALSE; v_erro TEXT := '';
    v_casos TEXT[] := ARRAY['M','N','O','P','Q','R','S','T','U','V','W','Y'];
    e JSONB;
BEGIN
    SELECT v::UUID INTO v_ad   FROM _ctx WHERE k='admin';
    SELECT v::UUID INTO v_game FROM _ctx WHERE k='game';
    SELECT v::UUID INTO v_fe   FROM _ctx WHERE k='fe';
    SELECT v::UUID INTO v_sl   FROM _ctx WHERE k='sl';
    SELECT v::INTEGER INTO v_ord FROM _ctx WHERE k='next_order';
    SELECT v::INTEGER INTO v_cv_base FROM _baseline_2825 WHERE k='card_variants';

    SELECT j.id INTO v_base3
      FROM public.catalog_variant_import_job j
      JOIN public.card_set cs ON cs.id = j.card_set_id
     WHERE j.status='STAGED' AND cs.code='BASE3'
     LIMIT 1;

    SELECT count(*) FILTER (WHERE validation_status='VALID'),
           count(*) FILTER (WHERE validation_status='NEEDS_REVIEW')
      INTO v_bv, v_bn
      FROM public.catalog_variant_import_row WHERE job_id = v_base3;

    -- Placeholders: garantem cobertura. Qualquer caso não sobrescrito reprova.
    PERFORM pg_temp._chk(t.c, FALSE, 'caso não registrado pelo bloco MAIN — cobertura incompleta')
      FROM unnest(v_casos) AS t(c);

    -- ===================== SUBTRANSAÇÃO =====================
    BEGIN
        SELECT w.profile_id, w.rows_touched, w.rows_revalidated,
               w.rows_still_pending, w.jobs_affected
          INTO v_pid, v_t, v_rv, v_sp, v_ja
          FROM internal.create_card_printing_profile_with_backfill(
              v_ad, 'HARNESS_FE', 'Harness 1ª Edição',
              'Perfil de harness com selo de 1ª Edição.', v_ord, ARRAY[v_fe]) w;

        -- ------------------------------------------------- M: modo DEFERRED
        -- Não há catálogo que exponha o modo corrente de um constraint trigger
        -- dentro da transação. A prova é COMPORTAMENTAL: um Perfil criado logo
        -- depois não pode ser selado antes do fim da transação.
        DECLARE v_tmp UUID; v_tmp_sig UUID[];
        BEGIN
            INSERT INTO public.card_printing_profile (game_id, code, name, display_order)
            VALUES (v_game, 'HARNESS_M', 'M', v_ord + 1) RETURNING id INTO v_tmp;
            INSERT INTO public.card_printing_profile_trait (profile_id, trait_id, game_id)
            VALUES (v_tmp, v_sl, v_game);
            SELECT traits_signature INTO v_tmp_sig FROM public.card_printing_profile WHERE id = v_tmp;
            v_out := v_out || jsonb_build_object('caso','M','ok', (v_tmp_sig IS NULL),
                'det', CASE WHEN v_tmp_sig IS NULL
                            THEN 'modo DEFERRED restaurado: Perfil posterior não foi selado'
                            ELSE 'FALHA: o worker deixou o selo IMMEDIATE para o resto da transação' END);
        END;

        -- ------------------- N: não elegíveis intocadas, ROW INTEIRA
        -- Comparação de row completa: nenhuma coluna das linhas não elegíveis
        -- pode ter mudado, nem as que ninguém pensou em enumerar.
        DECLARE v_nf INTEGER; v_nmiss INTEGER;
        BEGIN
            SELECT count(*) INTO v_n
              FROM _n_before nb JOIN public.catalog_variant_import_row r ON r.id = nb.id
             WHERE to_jsonb(r) IS DISTINCT FROM nb.snapshot;

            -- A foto precisa continuar cobrindo as mesmas linhas: sumiço também
            -- é alteração.
            SELECT count(*) INTO v_nmiss
              FROM _n_before nb
             WHERE NOT EXISTS (SELECT 1 FROM public.catalog_variant_import_row r WHERE r.id = nb.id);

            SELECT count(*) INTO v_nf FROM _n_before;

            v_out := v_out || jsonb_build_object('caso','N','ok',(v_n = 0 AND v_nmiss = 0),
                'det', format('%s de %s linha(s) NÃO elegíveis com QUALQUER coluna alterada (esperado 0); %s desaparecida(s) (esperado 0)',
                              v_n, v_nf, v_nmiss));
        END;

        -- ------------------------------------------------------ O: outcome A
        SELECT count(*) INTO v_n
          FROM public.catalog_variant_import_row r
         WHERE r.job_id = v_base3 AND r.validation_status='VALID'
           AND jsonb_typeof(r.normalized_data->'printing_profile_id')='string'
           AND (r.normalized_data->>'printing_profile_id')::UUID = v_pid
           AND r.normalized_data ? 'variant_type_id';
        v_out := v_out || jsonb_build_object('caso','O','ok',(v_n = v_rv),
            'det', format('outcome A: %s linhas VALID com as DUAS chaves e o novo Perfil (rows_revalidated=%s)', v_n, v_rv));

        -- ------------------------------------------------------ P: outcome B
        SELECT count(*) INTO v_n
          FROM public.catalog_variant_import_row r
         WHERE r.job_id = v_base3 AND r.validation_status='NEEDS_REVIEW'
           AND jsonb_typeof(r.normalized_data->'printing_profile_id')='string'
           AND (r.normalized_data->>'printing_profile_id')::UUID = v_pid
           AND NOT (r.normalized_data ? 'variant_type_id');
        v_out := v_out || jsonb_build_object('caso','P','ok',(v_n = v_sp),
            'det', format('outcome B: %s linhas NEEDS_REVIEW com Perfil e SEM variant_type_id (rows_still_pending=%s)', v_n, v_sp));

        -- ------------------------------- Q: outcome C / fail-closed
        SELECT count(*) INTO v_n
          FROM public.catalog_variant_import_row r
         WHERE r.job_id = v_base3
           AND NOT (r.normalized_data ? 'printing_profile_id')
           AND r.normalized_data ? 'variant_type_id';
        v_out := v_out || jsonb_build_object('caso','Q','ok',(v_n = 0),
            'det', format('%s linha(s) com variant_type_id sem chave de printing (esperado 0 — fail-closed)', v_n));

        -- ------------------------------------------ R: NEW, POSITIVAMENTE
        -- Prova afirmativa do contrato NEW-only da Query 2189 v2.1. Não basta
        -- "nenhum inválido": exige linhas efetivamente tocadas, todas NEW e
        -- todas com matched_variant_id nulo.
        DECLARE v_mat INTEGER; v_new INTEGER; v_notnull INTEGER; v_rf TEXT := '';
        BEGIN
            SELECT count(*),
                   count(*) FILTER (WHERE r.match_status = 'NEW'),
                   count(*) FILTER (WHERE r.matched_variant_id IS NOT NULL)
              INTO v_mat, v_new, v_notnull
              FROM public.catalog_variant_import_row r
             WHERE r.job_id = v_base3
               AND jsonb_typeof(r.normalized_data->'printing_profile_id')='string'
               AND (r.normalized_data->>'printing_profile_id')::UUID = v_pid;

            IF v_t = 0        THEN v_rf := v_rf || 'rows_touched=0 — contrato NEW-only não exercitado; '; END IF;
            IF v_mat <> v_t   THEN v_rf := v_rf || format('materializadas=%s vs rows_touched=%s; ', v_mat, v_t); END IF;
            IF v_new <> v_mat THEN v_rf := v_rf || format('NEW=%s de %s materializadas; ', v_new, v_mat); END IF;
            IF v_notnull <> 0 THEN v_rf := v_rf || format('%s com matched_variant_id NÃO nulo; ', v_notnull); END IF;

            v_out := v_out || jsonb_build_object('caso','R','ok',(v_rf = ''),
                'det', COALESCE(NULLIF(v_rf,''),
                    format('rows_touched=%s > 0; %s materializadas; todas NEW; zero matched_variant_id', v_t, v_mat)));
        END;

        -- ------------------------- S: INVARIANTE "NENHUM MATCHED AQUI"
        -- A Query 2189 v2.1 não tem mais ramo MATCHED: este caso NÃO cobre um
        -- caminho, prova uma INVARIANTE. Três condições, todas necessárias.
        DECLARE v_mv INTEGER; v_cv INTEGER; v_sf TEXT := '';
        BEGIN
            SELECT count(*) FILTER (WHERE r.match_status='MATCHED'),
                   count(*) FILTER (WHERE r.matched_variant_id IS NOT NULL)
              INTO v_matched, v_mv
              FROM public.catalog_variant_import_row r
             WHERE r.job_id = v_base3
               AND jsonb_typeof(r.normalized_data->'printing_profile_id')='string'
               AND (r.normalized_data->>'printing_profile_id')::UUID = v_pid;

            SELECT count(*) INTO v_cv
              FROM public.card_variant cv WHERE cv.printing_profile_id = v_pid;

            IF v_matched > 0 THEN v_sf := v_sf || format('%s tocadas com MATCHED; ', v_matched); END IF;
            IF v_mv > 0      THEN v_sf := v_sf || format('%s com matched_variant_id NOT NULL; ', v_mv); END IF;
            IF v_cv > 0      THEN v_sf := v_sf || format('%s card_variant referenciam o Perfil recém-criado — premissa estrutural do NEW-only não vale nesta base; ', v_cv); END IF;

            v_out := v_out || jsonb_build_object('caso','S','ok',(v_sf = ''),
                'det', COALESCE(NULLIF(v_sf,''),
                    'invariante confirmada: 0 MATCHED, 0 matched_variant_id, 0 card_variant referenciando o Perfil novo'));
        END;

        -- ------------------- T: zero resulting_variant_id, ESCOPO DIRETO
        -- Escopado às linhas que ESTA operação materializou (printing_profile_id
        -- = v_pid), não ao estado geral de BASE3: prova o que o worker fez, sem
        -- depender de linhas históricas não relacionadas.
        DECLARE v_tscope INTEGER;
        BEGIN
            SELECT count(*) FILTER (WHERE r.resulting_variant_id IS NOT NULL),
                   count(*)
              INTO v_n, v_tscope
              FROM public.catalog_variant_import_row r
             WHERE jsonb_typeof(r.normalized_data->'printing_profile_id')='string'
               AND (r.normalized_data->>'printing_profile_id')::UUID = v_pid;

            v_out := v_out || jsonb_build_object('caso','T',
                'ok', (v_n = 0 AND v_tscope = v_t),
                'det', format('escopo=%s linhas materializadas pelo Perfil novo (rows_touched=%s); %s com resulting_variant_id (esperado 0 — o worker nunca persiste)',
                              v_tscope, v_t, v_n));
        END;

        -- ------------------- U: ESCOPO EXATO DE JOBS
        --
        -- Seis provas, todas necessárias. O conjunto de jobs afetados é
        -- DERIVADO das linhas materializadas, nunca assumido — BASE3 é o
        -- corpus de hoje, não o contrato. Se amanhã um Perfil novo atingir
        -- vários jobs, esta prova continua correta sem edição.
        --
        --   1. affected = DISTINCT job_id das linhas com printing_profile_id
        --      = v_pid; cardinalidade tem de bater com jobs_affected;
        --   2. cada job AFETADO: total_rows/valid_rows == contagem real;
        --   3. cada job AFETADO: row inteira menos os três campos autorizados
        --      (total_rows, valid_rows, updated_at) tem de estar idêntica;
        --   4. cada job NÃO afetado: row INTEIRA idêntica, sem remover nada —
        --      job fora do escopo não podia nem ser tocado, então updated_at
        --      também é conferido;
        --   5. nenhum job desaparecido;
        --   6. nenhum job NOVO. O worker não cria jobs, e deixar isso só para
        --      o Z seria falso-verde: a reversão do MAIN apagaria o job
        --      indevido antes de Z olhar.
        DECLARE
            v_aff UUID[]; v_aff_n INTEGER;
            v_bad_counters INTEGER; v_bad_aff INTEGER; v_bad_unaff INTEGER;
            v_jmiss INTEGER; v_jnew INTEGER; v_uf TEXT := '';
        BEGIN
            -- 1 — derivação do escopo
            SELECT ARRAY(
                SELECT DISTINCT r.job_id
                  FROM public.catalog_variant_import_row r
                 WHERE jsonb_typeof(r.normalized_data->'printing_profile_id')='string'
                   AND (r.normalized_data->>'printing_profile_id')::UUID = v_pid
                 ORDER BY 1
            ) INTO v_aff;
            v_aff_n := COALESCE(cardinality(v_aff), 0);

            IF v_aff_n IS DISTINCT FROM v_ja THEN
                v_uf := v_uf || format('affected_jobs derivados=%s vs jobs_affected retornado=%s; ', v_aff_n, v_ja);
            END IF;

            -- 2 — contadores de TODOS os afetados, não só do primeiro
            SELECT count(*) INTO v_bad_counters
              FROM public.catalog_variant_import_job j
              CROSS JOIN LATERAL (
                  SELECT count(*) AS real_total,
                         count(*) FILTER (WHERE r.validation_status='VALID') AS real_valid
                    FROM public.catalog_variant_import_row r
                   WHERE r.job_id = j.id
              ) c
             WHERE j.id = ANY(v_aff)
               AND (j.total_rows IS DISTINCT FROM c.real_total
                 OR j.valid_rows IS DISTINCT FROM c.real_valid);

            -- 3 — afetados: só os três campos autorizados podem diferir
            SELECT count(*) INTO v_bad_aff
              FROM _jobs_before jb JOIN public.catalog_variant_import_job j ON j.id = jb.id
             WHERE jb.id = ANY(v_aff)
               AND (to_jsonb(j)  - 'total_rows' - 'valid_rows' - 'updated_at')
                IS DISTINCT FROM
                  (jb.snapshot   - 'total_rows' - 'valid_rows' - 'updated_at');

            -- 4 — não afetados: ROW INTEIRA, sem remover campo nenhum
            SELECT count(*) INTO v_bad_unaff
              FROM _jobs_before jb JOIN public.catalog_variant_import_job j ON j.id = jb.id
             WHERE NOT (jb.id = ANY(v_aff))
               AND to_jsonb(j) IS DISTINCT FROM jb.snapshot;

            -- 5 — desaparecidos
            SELECT count(*) INTO v_jmiss
              FROM _jobs_before jb
             WHERE NOT EXISTS (SELECT 1 FROM public.catalog_variant_import_job j WHERE j.id = jb.id);

            -- 6 — novos (qualquer status)
            SELECT count(*) INTO v_jnew
              FROM public.catalog_variant_import_job j
             WHERE NOT EXISTS (SELECT 1 FROM _jobs_before jb WHERE jb.id = j.id);

            IF v_bad_counters > 0 THEN v_uf := v_uf || format('%s job(s) afetado(s) com contadores divergentes da contagem real; ', v_bad_counters); END IF;
            IF v_bad_aff      > 0 THEN v_uf := v_uf || format('%s job(s) afetado(s) com campo NÃO autorizado alterado; ', v_bad_aff); END IF;
            IF v_bad_unaff    > 0 THEN v_uf := v_uf || format('%s job(s) NÃO afetado(s) alterado(s) em alguma coluna; ', v_bad_unaff); END IF;
            IF v_jmiss        > 0 THEN v_uf := v_uf || format('%s job(s) desaparecido(s); ', v_jmiss); END IF;
            IF v_jnew         > 0 THEN v_uf := v_uf || format('%s job(s) NOVO(s) criado(s) — o worker não cria jobs; ', v_jnew); END IF;

            v_out := v_out || jsonb_build_object('caso','U','ok',(v_uf = ''),
                'det', COALESCE(NULLIF(v_uf,''),
                    format('affected_jobs=%s (== jobs_affected); contadores corretos em %s/%s; 0 campos não autorizados nos afetados; 0 alterações nos %s job(s) não afetados; 0 desaparecidos; 0 novos',
                           v_aff_n, v_aff_n, v_aff_n,
                           (SELECT count(*) FROM _jobs_before) - v_aff_n)));
        END;

        -- Leitura de BASE3 apenas para o GABARITO informativo (Seção 13).
        -- Não participa do veredito de U: o contrato de U é genérico.
        SELECT count(*) FILTER (WHERE validation_status='VALID'),
               count(*) FILTER (WHERE validation_status='NEEDS_REVIEW')
          INTO v_av, v_an
          FROM public.catalog_variant_import_row WHERE job_id = v_base3;

        -- ------------------------------------------------------ V: action log
        DECLARE v_log INTEGER; v_meta JSONB; v_actor UUID;
        BEGIN
            SELECT count(*) INTO v_log
              FROM public.catalog_admin_action_log
             WHERE action='CARD_PRINTING_PROFILE_CREATED' AND entity_id = v_pid;

            SELECT metadata, actor_id INTO v_meta, v_actor
              FROM public.catalog_admin_action_log
             WHERE action='CARD_PRINTING_PROFILE_CREATED' AND entity_id = v_pid LIMIT 1;

            v_out := v_out || jsonb_build_object('caso','V',
                'ok', (v_log = 1 AND v_actor = v_ad
                       AND (v_meta->>'rows_touched')::INTEGER       = v_t
                       AND (v_meta->>'rows_revalidated')::INTEGER   = v_rv
                       AND (v_meta->>'rows_still_pending')::INTEGER = v_sp
                       AND (v_meta->>'jobs_affected')::INTEGER      = v_ja
                       AND v_meta ? 'game_id' AND v_meta ? 'code' AND v_meta ? 'name'
                       AND v_meta ? 'display_order' AND v_meta ? 'trait_ids'
                       AND v_meta ? 'traits_signature'),
                'det', format('%s evento(s); actor=%s (esperado %s); metadata=%s',
                              v_log, COALESCE(v_actor::TEXT,'<null>'), v_ad, COALESCE(v_meta::TEXT,'<null>')));
        END;

        -- ------------------- W: segunda composição idêntica precisa falhar
        DECLARE v_msg TEXT; v_raised BOOLEAN := FALSE;
        BEGIN
            BEGIN
                PERFORM internal.create_card_printing_profile_with_backfill(
                    v_ad,'HARNESS_W','W',NULL, v_ord + 5, ARRAY[v_fe]);
            EXCEPTION WHEN OTHERS THEN v_raised := TRUE; v_msg := SQLERRM;
            END;
            v_out := v_out || jsonb_build_object('caso','W',
                'ok', (v_raised AND v_msg LIKE '%DUPLICATE_SIGNATURE%'),
                'det', COALESCE(v_msg,'sem exceção — composição duplicada foi aceita'));
        END;

        -- ------------------------------------------- Y: zero card_variant
        SELECT count(*) INTO v_n FROM public.card_variant;
        v_out := v_out || jsonb_build_object('caso','Y','ok',(v_n = v_cv_base),
            'det', format('card_variant durante a operação=%s, baseline=%s (esperado idêntico)', v_n, v_cv_base));

        RAISE EXCEPTION 'HARNESS_MAIN_ROLLBACK';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM = 'HARNESS_MAIN_ROLLBACK' THEN v_rolled := TRUE;
        ELSE v_erro := SQLERRM; END IF;
    END;
    -- ===================== FIM DA SUBTRANSAÇÃO =====================

    SET CONSTRAINTS public.trg_card_printing_profile_seal DEFERRED;

    IF v_rolled THEN
        FOR e IN SELECT value FROM jsonb_array_elements(v_out) LOOP
            PERFORM pg_temp._chk(e->>'caso', (e->>'ok')::BOOLEAN, e->>'det');
        END LOOP;
    ELSE
        PERFORM pg_temp._chk(t.c, FALSE,
            COALESCE(NULLIF(v_erro,''),
                     'sentinela MAIN não disparou — os efeitos do cenário positivo podem ter sobrevivido'))
          FROM unnest(v_casos) AS t(c);
    END IF;

    -- Resíduo do próprio bloco não é conferido aqui de propósito: o caso Z
    -- cobre todos os HARNESS_* de uma vez, contra a baseline. Duplicar a
    -- checagem aqui sobrescreveria o veredito de um caso alheio.

    -- Gabarito (informativo; sai no SELECT final porque NOTICE não trafega
    -- neste canal).
    INSERT INTO _ctx VALUES
        ('gab_touched',     COALESCE(v_t::TEXT,'<null>')),
        ('gab_revalidated', COALESCE(v_rv::TEXT,'<null>')),
        ('gab_pending',     COALESCE(v_sp::TEXT,'<null>')),
        ('gab_jobs',        COALESCE(v_ja::TEXT,'<null>')),
        ('gab_base3_antes', v_bv::TEXT || '/' || v_bn::TEXT),
        ('gab_base3_depois', COALESCE(v_av::TEXT,'?') || '/' || COALESCE(v_an::TEXT,'?')),
        ('gab_esperado_2026_09_13', 'touched=62 revalidated=16 pending=46 jobs=1 | BASE3 64/113 -> 80/97'),
        ('gab_status', CASE WHEN v_t=62 AND v_rv=16 AND v_sp=46 AND v_ja=1
                            THEN 'CONFERE com o gabarito de 2026-09-13'
                            ELSE 'DIVERGENTE — a base mudou; recalibrar o esperado antes do EXECUTE (isto é INFO, não FAIL)' END);
END;
$main$;

-- =============================================================================
-- CASO Z — ISOLAMENTO
--
-- Aqui Z NÃO prova um ROLLBACK de topo (não existe mais). Prova que TODOS os
-- cenários mutáveis do harness foram corretamente isolados e revertidos pelas
-- suas subtransações: o LIVE precisa estar idêntico à baseline capturada na
-- Seção 0, chave por chave, e sem nenhum resíduo HARNESS_*.
-- =============================================================================
DO $z$
DECLARE v_div TEXT;
BEGIN
    SELECT string_agg(format('%s: baseline=%s agora=%s', COALESCE(b.k, s.k), b.v, s.v), ' | ')
      INTO v_div
      FROM _baseline_2825 b
      FULL JOIN pg_temp._snapshot_2825() s ON s.k = b.k
     WHERE b.v IS DISTINCT FROM s.v;

    PERFORM pg_temp._chk('Z', v_div IS NULL,
        COALESCE(v_div,
        'isolamento confirmado: perfis, composições, traits, games, card_variant, staging, VALID/NR, digests de linha e de contadores, action log e resíduos HARNESS_* idênticos à baseline'));
END;
$z$;

-- =============================================================================
-- GATE — 29 PASS / 0 FAIL, tudo no mesmo payload
--
-- Não há COMMIT nem ROLLBACK aqui. Se qualquer caso reprovar, o RAISE aborta a
-- transação que o Management API abriu — camada final de segurança, não o
-- mecanismo do qual o PASS depende.
-- =============================================================================
DO $gate$
DECLARE v_pass INTEGER; v_fail INTEGER; v_falhas TEXT;
BEGIN
    SELECT count(*) FILTER (WHERE veredito='PASS'),
           count(*) FILTER (WHERE veredito='FAIL')
      INTO v_pass, v_fail FROM _r;

    SELECT string_agg(caso || ': ' || detalhe, E'\n') INTO v_falhas
      FROM _r WHERE veredito='FAIL';

    IF v_fail > 0 OR v_pass <> 29 THEN
        RAISE EXCEPTION 'GATE_2825_FAILED: % PASS / % FAIL (esperado 29/0).%',
            v_pass, v_fail, E'\n' || COALESCE(v_falhas, '(cobertura incompleta — algum caso não registrou veredito)');
    END IF;
END;
$gate$;

-- Saída final: vereditos + gabarito. É o último statement de propósito — é o
-- resultado que o canal devolve.
SELECT 'CASO'::TEXT AS tipo, caso AS chave, veredito AS valor, detalhe
  FROM _r
UNION ALL
SELECT 'INFO', k, v, NULL FROM _ctx WHERE k LIKE 'gab_%'
 ORDER BY tipo, chave;
