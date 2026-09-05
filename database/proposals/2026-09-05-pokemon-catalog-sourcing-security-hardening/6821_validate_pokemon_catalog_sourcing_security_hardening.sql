/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 6821 - Validate Pokemon Catalog Sourcing Security Hardening
Versão......: 1.1 (CONFIRMADO EXECUTADO — resultado PASS)
Status......: CONFIRMADO EXECUTADO — resultado PASS (Seções A-E)
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-05 (staging em POKEMON-CATALOG-SOURCING-POST-APPLY-
               SECURITY-HARDENING-STAGING-01; revisado no mesmo dia via
               POKEMON-CATALOG-SOURCING-POST-APPLY-SECURITY-HARDENING-
               6821-REVISION-01 — GATE 4 físico: 6111 PASS/NÃO ALTERADO,
               correções restritas a este validador; executado por
               completo no banco real em POKEMON-CATALOG-SOURCING-POST-
               APPLY-SECURITY-HARDENING-EXECUTION-01 — Seções A-E PASS,
               confirmadas também por evidência SELECT independente
               correlacionada ao resultado do DO block)

*** ESTE SCRIPT FOI EXECUTADO EM POKEMON-CATALOG-SOURCING-POST-APPLY-
SECURITY-HARDENING-EXECUTION-01 (2026-09-05) *** — execução real contra o
banco de produção (`qjfutqujxrbzgrtkpgkg`), imediatamente após a Query
6111 (REVOKE), ambas confirmadas: 6111 aplicada com sucesso via
apply_migration; 6821 executada via execute_sql sem disparar nenhuma
RAISE EXCEPTION (nenhuma seção falhou) e re-confirmada por consultas SELECT
independentes cobrindo as mesmas asserções de cada Seção (A: 0/72
privilégios remanescentes; B: 0/20 divergências de EXECUTE; C: contagens
exatas 11/9/1025/1/1025; D: os dois runs nomeados COMPLETED, 0 active
runs; E: 0 divergências de RLS/policy/trigger/search_path). Este script
permanece em `database/proposals/2026-09-05-pokemon-catalog-sourcing-
security-hardening/` como evidência histórica de validação — mesmo padrão
já usado por `6800`/`6810`/`6820` (script de validação nunca promovido
para `database/schema/`, só as migrations estruturais o são).

Descrição...:
Script de validação, 100% READ-ONLY (nenhum INSERT/UPDATE/DELETE, nenhum
fixture, nenhum BEGIN...ROLLBACK necessário — a Query 6111 não altera dado
algum, só GRANT/REVOKE), que prova o resultado esperado da Query 6111
(Revoke Service Role Structural Privileges — Pokemon Catalog) nas 9 tabelas
canônicas do Pokémon Catalog Sourcing, e confirma que nada mais no domínio
foi afetado.

Cobre, nesta ordem, exatamente as 5 seções pedidas pela auditoria:
A. service_role: os 8 privilégios (SELECT/INSERT/UPDATE/DELETE/TRUNCATE/
   REFERENCES/TRIGGER/MAINTAIN) = false nas 9 tabelas.
B. As 5 RPCs de sourcing (assinaturas exatas — ver item 2 abaixo):
   service_role EXECUTE = true; anon/authenticated EXECUTE = false (via
   has_function_privilege()); PUBLIC (pseudo-role, grantee=0) sem EXECUTE
   no ACL efetivo, provado via aclexplode() (ver item 1 abaixo).
C. Contagens de dados preservadas (Regions=11, Generation=9, Species=1025,
   Pokédex=1, Positions=1025, e os 4 xrefs correspondentes).
D. Runs preservados: DRY_RUN RUN-20260905-00000101 = COMPLETED, APPLY
   RUN-20260905-00000121 = COMPLETED, zero active runs (definição
   canônica exata — ver item 3 abaixo).
E. Zero alteração em RLS (rowsecurity ainda true nas 9 tabelas), zero
   policy (baseline já era zero antes desta rodada — confirmado por
   auditoria física prévia), triggers HABILITADOS preservados (contagem
   exata por tabela, `tgenabled <> 'D'` — ver item 5 abaixo), e as 5 RPCs
   mantendo `SECURITY DEFINER` com search_path EXATAMENTE vazio (ver item
   4 abaixo) — nenhuma delas foi tocada por 6111, que só concede/revoga
   privilégio de TABELA, nunca de função.

REVISION-01 — 5 correções obrigatórias aplicadas (GATE 4 físico: 6111
PASS e NÃO ALTERADO; correções restritas a este validador):

1. PUBLIC EXECUTE (Seção B): `has_function_privilege('public', ...)` foi
   REMOVIDO — PUBLIC não é uma role normal, e essa chamada seria
   resolvida como um nome de role literal "public" (inexistente),
   nunca a pseudo-role PUBLIC de fato. Substituído por
   `aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner)))`,
   provando ausência de qualquer entrada com `grantee = 0` (codificação
   canônica de PUBLIC em um `aclitem[]`) concedendo `EXECUTE`.
   `has_function_privilege()` continua sendo usado, sem alteração de
   abordagem, para os roles nomeados: `service_role = true`,
   `anon = false`, `authenticated = false`.

2. Assinaturas exatas das RPCs (Seção B): lookup por `proname` isolado
   substituído por `regprocedure` com assinatura completa —
   `open_pokemon_catalog_sourcing_run(text,uuid)`,
   `heartbeat_pokemon_catalog_sourcing_run(uuid)`,
   `plan_pokemon_catalog_sourcing_run(uuid,jsonb)`,
   `apply_pokemon_catalog_sourcing_run(uuid,jsonb)`,
   `close_failed_pokemon_catalog_sourcing_run(uuid,text)` — confirmadas
   como as assinaturas reais no banco físico antes desta revisão.

3. Active runs (Seção D): `status NOT IN ('COMPLETED','FAILED')`
   substituído pela definição canônica exata
   `status IN ('PENDING','ACQUIRING','PLANNING','APPLYING')` — a versão
   anterior contava incorretamente `COMPLETED_WITH_DIVERGENCES` e
   `CANCELLED` (ambos terminais) como "ativos".

4. search_path (Seção E): `cfg LIKE 'search_path=%'` (frouxo) substituído
   por igualdade EXATA `cfg = 'search_path=""'` — a forma real
   armazenada em `proconfig` por `SET search_path = ''` neste Postgres
   17, confirmada por auditoria física direta antes desta revisão.
   `prosecdef = true` continua exigido em conjunto.

5. Triggers (Seção E): adicionado `t.tgenabled <> 'D'` ao filtro de
   contagem — um trigger presente mas desabilitado não é mais contado
   como ativo. Baselines inalteradas: 3 triggers habilitados nas 8
   primeiras tabelas, 2 em `pokedex_position`.

Todas as contagens/baselines usadas abaixo (Seções C e E) foram auditadas
diretamente no banco físico ANTES desta proposta ser escrita — ver
diagnóstico da rodada POKEMON-CATALOG-SOURCING-POST-APPLY-SECURITY-
HARDENING-STAGING-01. Nenhum valor aqui é hipotético.

Pré-requisitos:
- Query 6111 (Revoke Service Role Structural Privileges — Pokemon
  Catalog), desta mesma pasta de staging, CONFIRMADO EXECUTADO.

IMPORTANTE — status desta versão: PROPOSTA de staging pura. NÃO executada
contra nenhum banco nesta rodada. Nenhuma alegação de PASS/FAIL real é
feita aqui — apenas a lógica de validação, pronta para execução futura
mediante autorização explícita, imediatamente após 6111.
===============================================================================
*/

-- ===================================================================
-- SEÇÃO A — service_role: ZERO privilégio (8/8) nas 9 tabelas
-- ===================================================================
DO $$
DECLARE
    v_tables TEXT[] := ARRAY[
        'pokemon_region',
        'pokemon_region_external_reference',
        'pokemon_generation',
        'pokemon_generation_external_reference',
        'pokemon_species',
        'pokemon_species_external_reference',
        'pokedex',
        'pokedex_external_reference',
        'pokedex_position'
    ];
    v_privileges TEXT[] := ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER', 'MAINTAIN'];
    v_table TEXT;
    v_priv TEXT;
    v_fail_count INTEGER := 0;
BEGIN
    FOREACH v_table IN ARRAY v_tables LOOP
        FOREACH v_priv IN ARRAY v_privileges LOOP
            IF has_table_privilege('service_role', 'public.' || v_table, v_priv) THEN
                v_fail_count := v_fail_count + 1;
                RAISE NOTICE 'FAIL A: service_role AINDA possui % em public.%', v_priv, v_table;
            END IF;
        END LOOP;
    END LOOP;
    IF v_fail_count > 0 THEN
        RAISE EXCEPTION 'FAIL SEÇÃO A: % combinação(ões) tabela x privilégio de service_role NÃO foram revogadas (esperado 0/72)', v_fail_count;
    END IF;
    RAISE NOTICE 'PASS A: service_role tem ZERO privilégio (72/72 combinações 9 tabelas x 8 privilégios confirmadas false)';
END $$;

-- ===================================================================
-- SEÇÃO B — RPCs de sourcing: service_role EXECUTE=true,
-- anon/authenticated EXECUTE=false (has_function_privilege), e PUBLIC
-- (pseudo-role, grantee=0) sem EXECUTE via aclexplode do ACL efetivo.
-- ===================================================================
DO $$
DECLARE
    -- REVISION-01 (item 2): assinaturas EXATAS (regprocedure), nunca
    -- lookup por proname isolado — evita ambiguidade caso um overload
    -- futuro reutilize o mesmo nome com aridade/tipos diferentes.
    v_signatures TEXT[] := ARRAY[
        'public.open_pokemon_catalog_sourcing_run(text,uuid)',
        'public.heartbeat_pokemon_catalog_sourcing_run(uuid)',
        'public.plan_pokemon_catalog_sourcing_run(uuid,jsonb)',
        'public.apply_pokemon_catalog_sourcing_run(uuid,jsonb)',
        'public.close_failed_pokemon_catalog_sourcing_run(uuid,text)'
    ];
    v_sig TEXT;
    v_oid OID;
    v_proacl ACLITEM[];
    v_proowner OID;
    v_fail_count INTEGER := 0;
    v_public_has_execute BOOLEAN;
BEGIN
    FOREACH v_sig IN ARRAY v_signatures LOOP
        BEGIN
            v_oid := v_sig::regprocedure::oid;
        EXCEPTION WHEN undefined_function OR invalid_text_representation THEN
            RAISE EXCEPTION 'FAIL B: assinatura % não corresponde a nenhuma função existente', v_sig;
        END;

        SELECT p.proacl, p.proowner INTO v_proacl, v_proowner
        FROM pg_proc p WHERE p.oid = v_oid;

        -- has_function_privilege(): correto para roles NOMEADOS
        -- (service_role/anon/authenticated) — cada um herda
        -- automaticamente qualquer grant feito a PUBLIC, então este
        -- teste sozinho não isola "PUBLIC especificamente" (item 1).
        IF NOT has_function_privilege('service_role', v_oid, 'EXECUTE') THEN
            v_fail_count := v_fail_count + 1;
            RAISE NOTICE 'FAIL B: service_role NÃO tem EXECUTE em %', v_sig;
        END IF;
        IF has_function_privilege('anon', v_oid, 'EXECUTE') THEN
            v_fail_count := v_fail_count + 1;
            RAISE NOTICE 'FAIL B: anon AINDA tem EXECUTE em % (esperado false)', v_sig;
        END IF;
        IF has_function_privilege('authenticated', v_oid, 'EXECUTE') THEN
            v_fail_count := v_fail_count + 1;
            RAISE NOTICE 'FAIL B: authenticated AINDA tem EXECUTE em % (esperado false)', v_sig;
        END IF;

        -- REVISION-01 (item 1): PUBLIC não é uma role normal — não pode
        -- ser testada via has_function_privilege('public', ...) (essa
        -- string seria resolvida como um NOME DE ROLE literal chamado
        -- "public", que não existe/não é a pseudo-role PUBLIC). A prova
        -- correta é explodir o ACL efetivo da função (ou o ACL padrão
        -- via acldefault() quando proacl IS NULL — significa "nenhum GRANT/
        -- REVOKE explícito ainda, herda o default do dono") e confirmar
        -- ausência de qualquer entrada com grantee = 0 (grantee = 0 é,
        -- por convenção do catálogo do Postgres, a codificação de PUBLIC
        -- dentro de um aclitem[]) concedendo 'EXECUTE'.
        SELECT NOT EXISTS (
            SELECT 1
            FROM aclexplode(COALESCE(v_proacl, acldefault('f', v_proowner))) AS a
            WHERE a.grantee = 0 AND a.privilege_type = 'EXECUTE'
        ) INTO v_public_has_execute;
        IF NOT v_public_has_execute THEN
            v_fail_count := v_fail_count + 1;
            RAISE NOTICE 'FAIL B: PUBLIC (grantee=0) AINDA tem EXECUTE em % (esperado ausente)', v_sig;
        END IF;
    END LOOP;
    IF v_fail_count > 0 THEN
        RAISE EXCEPTION 'FAIL SEÇÃO B: % divergência(s) na matriz de EXECUTE das 5 RPCs de sourcing', v_fail_count;
    END IF;
    RAISE NOTICE 'PASS B: as 5 RPCs de sourcing (assinaturas exatas) mantêm service_role EXECUTE=true, anon/authenticated EXECUTE=false, e PUBLIC (grantee=0) sem EXECUTE no ACL efetivo (20/20 combinações confirmadas)';
END $$;

-- ===================================================================
-- SEÇÃO C — Contagens de dados preservadas
-- ===================================================================
DO $$
DECLARE
    v_regions INTEGER;
    v_regions_xref INTEGER;
    v_generations INTEGER;
    v_generations_xref INTEGER;
    v_species INTEGER;
    v_species_xref INTEGER;
    v_pokedex INTEGER;
    v_pokedex_xref INTEGER;
    v_positions INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_regions FROM public.pokemon_region;
    SELECT COUNT(*) INTO v_regions_xref FROM public.pokemon_region_external_reference;
    SELECT COUNT(*) INTO v_generations FROM public.pokemon_generation;
    SELECT COUNT(*) INTO v_generations_xref FROM public.pokemon_generation_external_reference;
    SELECT COUNT(*) INTO v_species FROM public.pokemon_species;
    SELECT COUNT(*) INTO v_species_xref FROM public.pokemon_species_external_reference;
    SELECT COUNT(*) INTO v_pokedex FROM public.pokedex;
    SELECT COUNT(*) INTO v_pokedex_xref FROM public.pokedex_external_reference;
    SELECT COUNT(*) INTO v_positions FROM public.pokedex_position;

    IF v_regions <> 11 THEN RAISE EXCEPTION 'FAIL C.1: pokemon_region = % (esperado 11)', v_regions; END IF;
    IF v_regions_xref <> 11 THEN RAISE EXCEPTION 'FAIL C.2: pokemon_region_external_reference = % (esperado 11)', v_regions_xref; END IF;
    IF v_generations <> 9 THEN RAISE EXCEPTION 'FAIL C.3: pokemon_generation = % (esperado 9)', v_generations; END IF;
    IF v_generations_xref <> 9 THEN RAISE EXCEPTION 'FAIL C.4: pokemon_generation_external_reference = % (esperado 9)', v_generations_xref; END IF;
    IF v_species <> 1025 THEN RAISE EXCEPTION 'FAIL C.5: pokemon_species = % (esperado 1025)', v_species; END IF;
    IF v_species_xref <> 1025 THEN RAISE EXCEPTION 'FAIL C.6: pokemon_species_external_reference = % (esperado 1025)', v_species_xref; END IF;
    IF v_pokedex <> 1 THEN RAISE EXCEPTION 'FAIL C.7: pokedex = % (esperado 1)', v_pokedex; END IF;
    IF v_pokedex_xref <> 1 THEN RAISE EXCEPTION 'FAIL C.8: pokedex_external_reference = % (esperado 1)', v_pokedex_xref; END IF;
    IF v_positions <> 1025 THEN RAISE EXCEPTION 'FAIL C.9: pokedex_position = % (esperado 1025)', v_positions; END IF;

    RAISE NOTICE 'PASS C: contagens preservadas — Regions=11/11(xref), Generation=9/9(xref), Species=1025/1025(xref), Pokédex=1/1(xref), Positions=1025';
END $$;

-- ===================================================================
-- SEÇÃO D — Runs preservados + zero active run
-- ===================================================================
DO $$
DECLARE
    v_dry_run_status TEXT;
    v_apply_status TEXT;
    v_active_runs INTEGER;
BEGIN
    SELECT status INTO v_dry_run_status
    FROM public.pokemon_catalog_sourcing_run
    WHERE run_code = 'RUN-20260905-00000101';
    IF v_dry_run_status IS NULL THEN
        RAISE EXCEPTION 'FAIL D.1: run RUN-20260905-00000101 não encontrado';
    END IF;
    IF v_dry_run_status <> 'COMPLETED' THEN
        RAISE EXCEPTION 'FAIL D.1: RUN-20260905-00000101 está em % (esperado COMPLETED)', v_dry_run_status;
    END IF;

    SELECT status INTO v_apply_status
    FROM public.pokemon_catalog_sourcing_run
    WHERE run_code = 'RUN-20260905-00000121';
    IF v_apply_status IS NULL THEN
        RAISE EXCEPTION 'FAIL D.2: run RUN-20260905-00000121 não encontrado';
    END IF;
    IF v_apply_status <> 'COMPLETED' THEN
        RAISE EXCEPTION 'FAIL D.2: RUN-20260905-00000121 está em % (esperado COMPLETED)', v_apply_status;
    END IF;

    -- REVISION-01 (item 3): definição canônica exata de "active run" —
    -- PENDING/ACQUIRING/PLANNING/APPLYING (os 4 status transitórios do
    -- lifecycle, Seção 7.1 do contrato). A CHECK física
    -- ck_pokemon_catalog_sourcing_run_status permite 8 valores no total:
    -- os 4 acima MAIS COMPLETED, COMPLETED_WITH_DIVERGENCES, FAILED e
    -- CANCELLED (os 4 terminais). A versão anterior desta Query
    -- (`status NOT IN ('COMPLETED','FAILED')`) contava incorretamente
    -- COMPLETED_WITH_DIVERGENCES e CANCELLED como "ativos", quando ambos
    -- são terminais.
    SELECT COUNT(*) INTO v_active_runs
    FROM public.pokemon_catalog_sourcing_run
    WHERE status IN ('PENDING', 'ACQUIRING', 'PLANNING', 'APPLYING');
    IF v_active_runs <> 0 THEN
        RAISE EXCEPTION 'FAIL D.3: % run(s) ativo(s) encontrado(s) (esperado 0)', v_active_runs;
    END IF;

    RAISE NOTICE 'PASS D: DRY_RUN RUN-20260905-00000101 e APPLY RUN-20260905-00000121 = COMPLETED, zero active runs';
END $$;

-- ===================================================================
-- SEÇÃO E — Zero alteração em RLS/policy/função/trigger/dado
-- ===================================================================
DO $$
DECLARE
    v_tables TEXT[] := ARRAY[
        'pokemon_region',
        'pokemon_region_external_reference',
        'pokemon_generation',
        'pokemon_generation_external_reference',
        'pokemon_species',
        'pokemon_species_external_reference',
        'pokedex',
        'pokedex_external_reference',
        'pokedex_position'
    ];
    v_expected_triggers INTEGER[] := ARRAY[3, 3, 3, 3, 3, 3, 3, 3, 2]; -- mesma ordem de v_tables (pokedex_position=2, demais=3)
    v_table TEXT;
    v_idx INTEGER;
    v_rowsecurity BOOLEAN;
    v_trigger_count INTEGER;
    v_policy_count INTEGER;
    v_fail_count INTEGER := 0;
BEGIN
    FOR v_idx IN 1 .. array_length(v_tables, 1) LOOP
        v_table := v_tables[v_idx];

        SELECT relrowsecurity INTO v_rowsecurity
        FROM pg_class WHERE relnamespace = 'public'::regnamespace AND relname = v_table;
        IF v_rowsecurity IS DISTINCT FROM TRUE THEN
            v_fail_count := v_fail_count + 1;
            RAISE NOTICE 'FAIL E: RLS não está mais habilitado em public.%', v_table;
        END IF;

        SELECT COUNT(*) INTO v_policy_count
        FROM pg_policies WHERE schemaname = 'public' AND tablename = v_table;
        IF v_policy_count <> 0 THEN
            v_fail_count := v_fail_count + 1;
            RAISE NOTICE 'FAIL E: public.% agora tem % policy(ies) (baseline era 0)', v_table, v_policy_count;
        END IF;

        -- REVISION-01 (item 5): contar apenas triggers HABILITADOS
        -- (tgenabled <> 'D' — 'D'=disabled; 'O'=origin/always-on,
        -- 'R'=replica, 'A'=always são todos "habilitados" em algum
        -- modo de sessão). Sem este filtro, um trigger presente mas
        -- desabilitado seria contado como ativo incorretamente.
        SELECT COUNT(*) INTO v_trigger_count
        FROM pg_trigger t
        JOIN pg_class c ON c.oid = t.tgrelid
        WHERE c.relnamespace = 'public'::regnamespace AND c.relname = v_table
          AND NOT t.tgisinternal AND t.tgenabled <> 'D';
        IF v_trigger_count <> v_expected_triggers[v_idx] THEN
            v_fail_count := v_fail_count + 1;
            RAISE NOTICE 'FAIL E: public.% tem % trigger(s) habilitado(s) (baseline era %)', v_table, v_trigger_count, v_expected_triggers[v_idx];
        END IF;
    END LOOP;

    -- As 5 RPCs de sourcing (assinaturas exatas) continuam SECURITY
    -- DEFINER com search_path EXATAMENTE vazio (6111 nunca toca função
    -- nenhuma — só GRANT/REVOKE de tabela). REVISION-01 (item 4): exige
    -- o elemento EXATO 'search_path=""' em proconfig (confirmado por
    -- auditoria física ser a forma real armazenada por
    -- `SET search_path = ''` no Postgres 17 deste projeto) — não apenas
    -- um LIKE 'search_path=%' frouxo, que aceitaria qualquer valor não
    -- vazio configurado para search_path.
    IF EXISTS (
        SELECT 1 FROM (
            SELECT unnest(ARRAY[
                'public.open_pokemon_catalog_sourcing_run(text,uuid)',
                'public.heartbeat_pokemon_catalog_sourcing_run(uuid)',
                'public.plan_pokemon_catalog_sourcing_run(uuid,jsonb)',
                'public.apply_pokemon_catalog_sourcing_run(uuid,jsonb)',
                'public.close_failed_pokemon_catalog_sourcing_run(uuid,text)'
            ])::regprocedure AS sig
        ) sigs
        JOIN pg_proc p ON p.oid = sigs.sig::oid
        WHERE p.prosecdef IS NOT TRUE
           OR NOT EXISTS (
               SELECT 1 FROM unnest(COALESCE(p.proconfig, ARRAY[]::TEXT[])) AS cfg
               WHERE cfg = 'search_path=""'
           )
    ) THEN
        v_fail_count := v_fail_count + 1;
        RAISE NOTICE 'FAIL E: alguma das 5 RPCs de sourcing perdeu SECURITY DEFINER ou o search_path exato ''search_path=""''';
    END IF;

    IF v_fail_count > 0 THEN
        RAISE EXCEPTION 'FAIL SEÇÃO E: % divergência(s) de RLS/policy/trigger/função encontrada(s) além do REVOKE esperado', v_fail_count;
    END IF;
    RAISE NOTICE 'PASS E: RLS habilitado (9/9), zero policy (9/9, baseline preservado), contagem de triggers HABILITADOS preservada por tabela (tgenabled<>''D''), as 5 RPCs mantêm SECURITY DEFINER com search_path exato vazio (''search_path=""'') — nenhuma alteração além do REVOKE de 6111';
END $$;

-- ===================================================================
-- RESUMO
-- ===================================================================
DO $$
BEGIN
    RAISE NOTICE '=== 6821: TODAS AS SEÇÕES (A-E) PASS — hardening de service_role nas 9 tabelas do Pokemon Catalog Sourcing confirmado, zero efeito colateral ===';
END $$;
