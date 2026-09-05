/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 6820 - Validate Pokemon Catalog Sourcing
Versão......: 2.3 (PROPOSTA — GATE 5 HOTFIX STAGING)
Status......: CONFIRMADO EXECUTADO — resultado PASS
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-04 (staging em POKEMON-CATALOG-SOURCING-INITIAL-LOAD-
               PHYSICAL-STAGING-01; revisado em ...-STAGING-REVISION-01 (item
               10), ...-STAGING-REVISION-02 (itens 3, 4, 5, 6 — NO-GO
               residual do segundo GATE 4), ...-VALIDATION-REVISION-03
               (itens 1 e 2 — GATE 4 FINAL AUDIT, 6104/6105 já PASS) e
               ...-GATE-5-HOTFIX-6110-STAGING-01 (Seção 9, achado runtime
               pós-execução real); executado por completo desde a Seção 0 em
               POKEMON-CATALOG-SOURCING-GATE-5-HOTFIX-6110-IMPLEMENTATION-01
               (2026-09-04), dentro de BEGIN...ROLLBACK — todas as 16 Seções
               PASS, zero resíduo confirmado)

*** ESTE SCRIPT FOI EXECUTADO EM POKEMON-CATALOG-SOURCING-GATE-5-HOTFIX-
6110-IMPLEMENTATION-01 (2026-09-04) *** — execução real dentro de transação
isolada (BEGIN...ROLLBACK), revertida ao final por desenho (zero resíduo
mesmo em execução real). Resultado: PASS em todas as 16 Seções. Este arquivo
permanece em `database/proposals/` como evidência histórica de validação —
NÃO promovido para `database/schema/` (script de validação, não objeto
canônico do catálogo — mesmo padrão de `6800`/`6810`).

REVISION-02 — o que mudou e por quê (NO-GO residual, restrito a
6104/6105/6820):

Item 3 (REMOVER SWAP DE ASSET_SOURCE.CODE): a v2.0 renomeava temporariamente
o asset_source POKEAPI real (`UPDATE ... SET code = 'POKEAPI_REAL_BACKUP_6820'`)
para liberar o code 'POKEAPI' para um fixture isolado. O GATE 4 apontou que
`asset_source.code` é imutável por desenho (Query 201) — mesmo estando dentro
de um BEGIN/ROLLBACK que reverte tudo, simular um UPDATE sobre um campo que o
próprio contrato trata como identidade estável é um antipadrão que este script
não deveria normalizar, e mascarava a Fonte real, real, atrás um code
temporário durante toda a execução. Corrigido: o script agora usa a linha
POKEAPI real diretamente (`v_real_pokeapi_id`, resolvida uma única vez na
Seção 0) para toda chamada às RPCs que resolvem a Fonte por `code = 'POKEAPI'`
internamente (open_run, heartbeat, PLAN, APPLY, close_failed) — nenhum
UPDATE/rename é feito sobre o asset_source real. Toda fixture de Pokémon
(Region/Generation/Species) usa external_id/natural keys exclusivos de teste
(prefixo TEST_, ordinal/dex number na faixa 999xxx), que nunca colidem com
dados reais trazidos por uma execução de sourcing genuína. Se o Pokédex
Nacional já possuir uma referência externa para a Fonte POKEAPI real, o script
REUTILIZA essa referência (não insere uma duplicata); só cria uma nova
referência quando nenhuma existir — e, como todo o script está dentro de
BEGIN/ROLLBACK, mesmo essa criação é 100% revertida ao final. Para a Fonte
auxiliar usada exclusivamente no teste de ASSET_SOURCE_MISMATCH (Seção 9, que
precisa ser uma Fonte genuinamente DIFERENTE de POKEAPI — seu code não precisa
e não deve ser 'POKEAPI'), o `source_order` deixou de ser um literal fixo
(99998) e passa a ser calculado dinamicamente (`MAX(source_order) + 1`), sem
assumir que essa faixa está livre.

Uma consequência direta de operar sobre a Fonte real: a Seção 0 agora inclui
uma pré-condição explícita — se já existir um run ATIVO real em POKEAPI no
momento da execução (sourcing genuíno em andamento), o script aborta com uma
mensagem clara, em vez de silenciosamente interferir com esse run (mesmo que
tecnicamente seguro sob ROLLBACK, produziria resultados de teste enganosos —
ex.: SOURCE_BUSY inesperado nas Seções 6-14).

Item 4 (ROLE CHOREOGRAPHY): auditoria linha a linha encontrou uma violação
real na Seção 13 (v2.0): após a Seção 11 fazer `SET LOCAL ROLE service_role`
e nunca resetar antes de entrar na Seção 13, o fixture de "divergência
concorrente" fazia `INSERT INTO pokemon_region` e `SELECT COUNT(*) FROM
pokemon_region` diretamente enquanto a sessão ainda estava sob service_role —
que não possui NENHUM grant direto nas tabelas canônicas (Seção 13 do
contrato). Executado de verdade, isso teria falhado com erro de permissão
antes mesmo de chegar ao teste que importa. Corrigido: `RESET ROLE` inserido
ao final da Seção 11 (antes de qualquer DML de fixture) e a Seção 13
reestruturada para alternar explicitamente entre postgres/owner (fixtures e
inspeções diretas do catálogo) e service_role (exclusivamente as chamadas de
entrypoint), nunca os dois ao mesmo tempo. As demais seções (6, 7, 8, 9, 10,
12, 14) foram reauditadas e já seguiam o padrão correto.

Item 5 (SECURITY PROOF): a v2.0 verificava grants pontuais (Seção 2.10-2.12)
mas não cobria sistematicamente as 8 tabelas canônicas Pokémon/Pokédex nem a
matriz completa de EXECUTE das 6 funções de entrypoint/auxiliares e das 6
funções de trigger. Seção 2 reescrita com verificação programática (loop sobre
array de tabelas × privilégios) cobrindo exatamente o que o GATE 4 exigiu.

Item 6 (ASSERTIONS FINAIS): adicionadas provas reais para: colisão de chave
natural DENTRO do próprio snapshot (Seção 15, nova); numeric NULL (Seção 15);
metadata/source_url inválidos (Seção 15); ausência de dupla contagem no
primeiro APPLY (Seção 13, asserção adicional); segundo APPLY com inserted=0/
updated=0/unchanged=total em TODAS as famílias (Seção 14, asserções
estendidas para generations/species/pokedex, além de regions/positions já
cobertos).

VALIDATION REVISION-03 — GATE 4 FINAL AUDIT (6104 v2.1 e 6105 v2.1: PASS;
6090-6108 preservados sem alteração; ajustes restritos a 6820 e README.md):

Item 1 (SECURITY EXECUTE MATRIX): a Seção 2 (2.5/2.6) testava service_role=
true para as 6 RPCs client-facing, mas cobria anon/authenticated apenas em um
subconjunto de 4 e 2 funções respectivamente — não a matriz completa de 6
funções x 3 roles. Corrigido com dois novos arrays (`v_client_functions`,
`v_client_roles`) e um duplo `FOREACH`: para CADA uma das 6 funções, prova
`service_role EXECUTE = TRUE` e, para CADA role em `{anon, authenticated}`,
prova `EXECUTE = FALSE` — 18 combinações verificadas sem duplicação de
código. 6106 (helper interno, EXECUTE=false para todos os roles inclusive
service_role) e as 6 funções de trigger (EXECUTE=false client-side)
permanecem intocadas (Seções 2.7/2.8, já corretas).

Item 2 (GENERATION_CODE_INVALID): a Seção 15 provava REGION_CODE_INVALID
(15.5, categoria 14/18 do 6104) mas não tinha teste equivalente para
GENERATION_CODE_INVALID (categoria irmã, 15/18 do 6104) — apesar de 6104 já
validar as duas desde a REVISION-02. Adicionada Seção 15.6: snapshot com
`generations[].code = 'generation_lowercase'` (fora do formato
`^[A-Z][A-Z0-9_]*$`), demais campos válidos, provando via PLAN real
`outcome = VALIDATION_FAILURE` e `error_summary LIKE '%GENERATION_CODE_INVALID%'`.
15.5 (REGION_CODE_INVALID) foi preservado integralmente — os dois testes
coexistem, um não substitui o outro.

GATE 5 HOTFIX 6110 — achado runtime pós-execução real (restrito à Seção 9):
a execução real de 6820 v2.2 (pós-hotfix 6109) avançou até a Seção 9 e
abortou com `23514: ck_pokemon_catalog_sourcing_run_period` — o fixture desta
Seção fechava o DRY_RUN "emprestado" de outra Fonte com `finished_at =
NOW()` (hora de início da transação, congelada desde o BEGIN), enquanto o
trigger de governança (6101) preenche `started_at` com `CLOCK_TIMESTAMP()`
(hora real). Numa transação longa como esta (dezenas de instruções antes da
Seção 9), `started_at` (hora real, mais tarde) pode ficar à frente de
`finished_at` (hora de início de transação, mais cedo), violando a CHECK de
período. Corrigido nesta v2.3: a única linha do fixture da Seção 9 que fazia
`finished_at = NOW()` passa a `finished_at = CLOCK_TIMESTAMP()`, alinhando o
fixture ao mesmo padrão agora usado por 6110 em `plan`/`apply`/
`close_failed`. Nenhuma outra linha de `6820` foi tocada nesta rodada.
===============================================================================
*/

BEGIN;

DO $outer$
DECLARE
    v_real_pokeapi_id UUID;
    v_real_national_pokedex_id UUID;
    v_real_national_pokedex_name TEXT;
    v_national_xref_exists BOOLEAN;
    v_national_external_pokedex_id TEXT;
    v_expected_pokedex_outcome TEXT;
    v_national_pokedex_name TEXT;
    v_count INTEGER;
    v_hash1 TEXT;
    v_hash2 TEXT;
    v_run1 RECORD;
    v_run2 RECORD;
    v_open RECORD;
    v_plan RECORD;
    v_apply RECORD;
    v_snapshot JSONB;
    v_bad_snapshot JSONB;
    v_reconcile JSONB;
    v_test_region_id UUID;
    v_dry_run_id UUID;
    v_apply_run_id UUID;
    v_regions_before INTEGER;
    v_regions_after INTEGER;
    v_canonical_tables TEXT[] := ARRAY[
        'pokemon_region', 'pokemon_generation', 'pokemon_species', 'pokedex',
        'pokemon_region_external_reference', 'pokemon_generation_external_reference',
        'pokemon_species_external_reference', 'pokedex_external_reference'
    ];
    v_privileges TEXT[] := ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE'];
    v_trigger_functions TEXT[] := ARRAY[
        'public.normalize_pokemon_generation_external_reference()',
        'public.govern_pokemon_generation_external_reference()',
        'public.touch_pokemon_generation_external_reference_updated_at()',
        'public.normalize_pokemon_catalog_sourcing_run()',
        'public.govern_pokemon_catalog_sourcing_run()',
        'public.touch_pokemon_catalog_sourcing_run_updated_at()'
    ];
    -- REVISION-03 (item 1 do terceiro GATE 4): matriz completa das 6 RPCs
    -- client-facing (assinatura -> apelido curto para mensagens de erro).
    v_client_functions TEXT[] := ARRAY[
        'public.compute_pokemon_catalog_sourcing_snapshot_hash(jsonb)',
        'public.open_pokemon_catalog_sourcing_run(text, uuid)',
        'public.plan_pokemon_catalog_sourcing_run(uuid, jsonb)',
        'public.apply_pokemon_catalog_sourcing_run(uuid, jsonb)',
        'public.heartbeat_pokemon_catalog_sourcing_run(uuid)',
        'public.close_failed_pokemon_catalog_sourcing_run(uuid, text)'
    ];
    v_client_roles TEXT[] := ARRAY['anon', 'authenticated'];
    v_tbl TEXT;
    v_priv TEXT;
    v_fn TEXT;
    v_role TEXT;
BEGIN
    RAISE NOTICE '=== 6820 v2.3 - VALIDAÇÃO REAL (dentro de BEGIN/ROLLBACK -- zero resíduo garantido em qualquer desfecho) ===';

    -- =========================================================================
    -- SEÇÃO 0: Resolução da Fonte POKEAPI real (sem swap/rename -- Fix 3) e
    -- pré-condição de ambiente idle
    -- =========================================================================
    SELECT id INTO v_real_pokeapi_id FROM public.asset_source WHERE code = 'POKEAPI' AND is_active = TRUE;
    IF v_real_pokeapi_id IS NULL THEN
        RAISE EXCEPTION 'PRECONDITION_FAILED: asset_source POKEAPI real não encontrado ou inativo (Query 6700 deveria estar CONFIRMADO EXECUTADO).';
    END IF;

    PERFORM 1 FROM public.pokemon_catalog_sourcing_run
    WHERE asset_source_id = v_real_pokeapi_id
      AND status IN ('PENDING', 'ACQUIRING', 'PLANNING', 'APPLYING');
    IF FOUND THEN
        RAISE EXCEPTION 'PRECONDITION_FAILED: existe um run ATIVO real em asset_source POKEAPI no momento desta execução. 6820 opera sobre a linha POKEAPI real (Fix 3, REVISION-02 -- nunca mais renomeia/swapa o code) e exige ambiente idle para não produzir resultados de teste enganosos (ex.: SOURCE_BUSY inesperado). Rode 6820 apenas quando não houver sourcing real em andamento.';
    END IF;

    RAISE NOTICE 'OK: Seção 0 -- Fonte POKEAPI real resolvida (id=%), sem swap/rename, ambiente confirmado idle.', v_real_pokeapi_id;

    -- =========================================================================
    -- SEÇÃO 1: Estrutura — tabelas, colunas, constraints, FKs, índice parcial
    -- =========================================================================
    PERFORM 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'pokemon_generation_external_reference';
    IF NOT FOUND THEN RAISE EXCEPTION 'FAIL 1.1: pokemon_generation_external_reference não existe.'; END IF;

    PERFORM 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'pokemon_catalog_sourcing_run';
    IF NOT FOUND THEN RAISE EXCEPTION 'FAIL 1.2: pokemon_catalog_sourcing_run não existe.'; END IF;

    SELECT COUNT(*) INTO v_count FROM pg_constraint WHERE conrelid = 'public.pokemon_catalog_sourcing_run'::regclass AND contype = 'c';
    IF v_count < 10 THEN RAISE EXCEPTION 'FAIL 1.3: pokemon_catalog_sourcing_run com menos CHECK constraints do que o esperado (%, esperado >= 10 incluindo dry_run_never_applying).', v_count; END IF;

    PERFORM 1 FROM pg_constraint WHERE conrelid = 'public.pokemon_catalog_sourcing_run'::regclass AND conname = 'ck_pokemon_catalog_sourcing_run_dry_run_never_applying';
    IF NOT FOUND THEN RAISE EXCEPTION 'FAIL 1.4: CHECK ck_pokemon_catalog_sourcing_run_dry_run_never_applying ausente (REVISION-01, item 4).'; END IF;

    PERFORM 1 FROM pg_indexes WHERE schemaname = 'public' AND indexname = 'uq_pokemon_catalog_sourcing_run_active_source';
    IF NOT FOUND THEN RAISE EXCEPTION 'FAIL 1.5: índice UNIQUE parcial de run ativo ausente.'; END IF;

    RAISE NOTICE 'OK: Seção 1 -- estrutura (tabelas/constraints/índice parcial, incluindo a nova CHECK da REVISION-01) confirmada.';

    -- =========================================================================
    -- SEÇÃO 2: RLS / Grants / EXECUTE — prova programática completa (Fix 5)
    -- =========================================================================
    PERFORM 1 FROM pg_class WHERE oid = 'public.pokemon_catalog_sourcing_run'::regclass AND relrowsecurity = TRUE;
    IF NOT FOUND THEN RAISE EXCEPTION 'FAIL 2.1: RLS não habilitado em pokemon_catalog_sourcing_run.'; END IF;

    PERFORM 1 FROM pg_class WHERE oid = 'public.pokemon_generation_external_reference'::regclass AND relrowsecurity = TRUE;
    IF NOT FOUND THEN RAISE EXCEPTION 'FAIL 2.2: RLS não habilitado em pokemon_generation_external_reference.'; END IF;

    -- 2.3 -- zero DML direto de service_role nas 8 tabelas canônicas
    -- Pokémon/Pokédex (Seção 13 do contrato): SELECT/INSERT/UPDATE/DELETE
    -- todos FALSE, em cada uma das 8.
    FOREACH v_tbl IN ARRAY v_canonical_tables LOOP
        FOREACH v_priv IN ARRAY v_privileges LOOP
            IF has_table_privilege('service_role', format('public.%I', v_tbl), v_priv) THEN
                RAISE EXCEPTION 'FAIL 2.3: service_role possui % direto em % (deveria ser ZERO em qualquer das 8 tabelas canônicas Pokémon/Pokédex -- Seção 13 do contrato).', v_priv, v_tbl;
            END IF;
        END LOOP;
    END LOOP;
    RAISE NOTICE 'OK: Seção 2.3 -- service_role sem SELECT/INSERT/UPDATE/DELETE em nenhuma das 8 tabelas canônicas Pokémon/Pokédex.';

    -- 2.3b -- pokedex_position (nona tabela tocada pela escrita do APPLY,
    -- além das 8 explicitamente listadas pelo GATE 4): mesma prova.
    FOREACH v_priv IN ARRAY v_privileges LOOP
        IF has_table_privilege('service_role', 'public.pokedex_position', v_priv) THEN
            RAISE EXCEPTION 'FAIL 2.3b: service_role possui % direto em pokedex_position.', v_priv;
        END IF;
    END LOOP;
    RAISE NOTICE 'OK: Seção 2.3b -- service_role sem SELECT/INSERT/UPDATE/DELETE em pokedex_position (bônus, além das 8).';

    -- 2.4 -- run ledger: SELECT=true (grant mínimo explícito, Seção 14),
    -- INSERT/UPDATE/DELETE=false (toda escrita flui só pelas RPCs).
    IF NOT has_table_privilege('service_role', 'public.pokemon_catalog_sourcing_run', 'SELECT') THEN RAISE EXCEPTION 'FAIL 2.4a: service_role SEM SELECT no run ledger (grant mínimo explícito esperado).'; END IF;
    IF has_table_privilege('service_role', 'public.pokemon_catalog_sourcing_run', 'INSERT') THEN RAISE EXCEPTION 'FAIL 2.4b: service_role possui INSERT direto no run ledger (deveria escrever somente via RPCs).'; END IF;
    IF has_table_privilege('service_role', 'public.pokemon_catalog_sourcing_run', 'UPDATE') THEN RAISE EXCEPTION 'FAIL 2.4c: service_role possui UPDATE direto no run ledger (deveria escrever somente via RPCs).'; END IF;
    IF has_table_privilege('service_role', 'public.pokemon_catalog_sourcing_run', 'DELETE') THEN RAISE EXCEPTION 'FAIL 2.4d: service_role possui DELETE direto no run ledger.'; END IF;
    RAISE NOTICE 'OK: Seção 2.4 -- run ledger com SELECT=true, INSERT/UPDATE/DELETE=false para service_role.';

    -- 2.5/2.6 -- REVISION-03 (item 1 do terceiro GATE 4): matriz completa,
    -- para CADA uma das 6 RPCs client-facing, de EXECUTE nos 3 roles —
    -- service_role=TRUE, anon=FALSE, authenticated=FALSE — em vez da
    -- cobertura parcial anterior (cada role testado em só um subconjunto
    -- das 6 funções). Loop evita duplicação e garante as 18 combinações
    -- (6 funções x 3 roles).
    FOREACH v_fn IN ARRAY v_client_functions LOOP
        IF NOT has_function_privilege('service_role', v_fn, 'EXECUTE') THEN
            RAISE EXCEPTION 'FAIL 2.5: service_role SEM EXECUTE em % (esperado TRUE -- é uma das 6 RPCs client-facing).', v_fn;
        END IF;
        FOREACH v_role IN ARRAY v_client_roles LOOP
            IF has_function_privilege(v_role, v_fn, 'EXECUTE') THEN
                RAISE EXCEPTION 'FAIL 2.6: % possui EXECUTE em % (esperado FALSE para todo role client-side).', v_role, v_fn;
            END IF;
        END LOOP;
    END LOOP;
    RAISE NOTICE 'OK: Seção 2.5/2.6 -- matriz completa (6 funções x 3 roles = 18 combinações): service_role=true, anon=false, authenticated=false em TODAS as 6 RPCs client-facing.';

    -- 2.7 -- helper interno 6106: EXECUTE=false para TODOS os roles,
    -- inclusive service_role (só é chamado internamente por 6104/6105, que
    -- executam como owner via SECURITY DEFINER -- não depende de GRANT).
    IF has_function_privilege('service_role', 'public.reconcile_pokemon_catalog_sourcing_snapshot(uuid, jsonb)', 'EXECUTE') THEN RAISE EXCEPTION 'FAIL 2.7a: service_role possui EXECUTE no helper interno 6106 (não deveria).'; END IF;
    IF has_function_privilege('anon', 'public.reconcile_pokemon_catalog_sourcing_snapshot(uuid, jsonb)', 'EXECUTE') THEN RAISE EXCEPTION 'FAIL 2.7b: anon possui EXECUTE no helper interno 6106.'; END IF;
    IF has_function_privilege('authenticated', 'public.reconcile_pokemon_catalog_sourcing_snapshot(uuid, jsonb)', 'EXECUTE') THEN RAISE EXCEPTION 'FAIL 2.7c: authenticated possui EXECUTE no helper interno 6106.'; END IF;
    RAISE NOTICE 'OK: Seção 2.7 -- helper interno 6106 sem EXECUTE para nenhum role, inclusive service_role.';

    -- 2.8 -- as 6 funções de trigger (3 de 6091 + 3 de 6101): nenhum role
    -- client-side deve ter EXECUTE (são disparadas implicitamente pelo
    -- mecanismo de trigger, nunca chamadas diretamente).
    FOREACH v_fn IN ARRAY v_trigger_functions LOOP
        IF has_function_privilege('anon', v_fn, 'EXECUTE') THEN RAISE EXCEPTION 'FAIL 2.8: anon possui EXECUTE na função de trigger % (deveria ser ZERO -- disparada só implicitamente).', v_fn; END IF;
        IF has_function_privilege('authenticated', v_fn, 'EXECUTE') THEN RAISE EXCEPTION 'FAIL 2.8: authenticated possui EXECUTE na função de trigger %.', v_fn; END IF;
        IF has_function_privilege('service_role', v_fn, 'EXECUTE') THEN RAISE EXCEPTION 'FAIL 2.8: service_role possui EXECUTE na função de trigger %.', v_fn; END IF;
    END LOOP;
    RAISE NOTICE 'OK: Seção 2.8 -- as 6 funções de trigger (6091 + 6101) sem EXECUTE client-side para nenhum role.';

    RAISE NOTICE 'OK: Seção 2 -- RLS, EXECUTE restrito a service_role nas 6 RPCs client-facing, zero DML direto de service_role em 8+1 tabelas canônicas, grant mínimo SELECT-only no run ledger, zero EXECUTE em helper interno e funções de trigger.';

    -- =========================================================================
    -- SEÇÃO 3: Hash determinístico
    -- =========================================================================
    v_hash1 := public.compute_pokemon_catalog_sourcing_snapshot_hash('{"a":1}'::JSONB);
    v_hash2 := public.compute_pokemon_catalog_sourcing_snapshot_hash('{"a":1}'::JSONB);
    IF v_hash1 <> v_hash2 THEN RAISE EXCEPTION 'FAIL 3.1: hash não determinístico para entrada idêntica.'; END IF;
    IF v_hash1 !~ '^[0-9a-f]{64}$' THEN RAISE EXCEPTION 'FAIL 3.2: hash fora do formato esperado: %', v_hash1; END IF;
    IF public.compute_pokemon_catalog_sourcing_snapshot_hash('{"a":2}'::JSONB) = v_hash1 THEN RAISE EXCEPTION 'FAIL 3.3: hashes de entradas diferentes colidiram.'; END IF;
    RAISE NOTICE 'OK: Seção 3 -- hash determinístico, formato correto, sensível a diferenças.';

    -- =========================================================================
    -- SEÇÃO 4: Guard NULL/hash na tabela
    -- =========================================================================
    BEGIN
        INSERT INTO public.pokemon_catalog_sourcing_run (asset_source_id, run_type, snapshot_hash) VALUES (v_real_pokeapi_id, 'DRY_RUN', 'HASH_INVALIDO');
        RAISE EXCEPTION 'FAIL 4.1: snapshot_hash malformado foi aceito pela CHECK.';
    EXCEPTION WHEN check_violation THEN
        RAISE NOTICE 'OK: Seção 4 -- CHECK de formato de snapshot_hash rejeitou valor malformado.';
    END;

    -- =========================================================================
    -- SEÇÃO 5: Ciclo de vida — INSERT PENDING, transições inválidas rejeitadas,
    -- DRY_RUN nunca APPLYING, APPLY nunca ACQUIRING/PLANNING/CWD (REVISION-01)
    -- =========================================================================
    INSERT INTO public.pokemon_catalog_sourcing_run (asset_source_id, run_type) VALUES (v_real_pokeapi_id, 'DRY_RUN') RETURNING * INTO v_run1;
    IF v_run1.status <> 'PENDING' THEN RAISE EXCEPTION 'FAIL 5.1: INSERT não iniciou em PENDING.'; END IF;

    BEGIN
        UPDATE public.pokemon_catalog_sourcing_run SET status = 'APPLYING' WHERE id = v_run1.id;
        RAISE EXCEPTION 'FAIL 5.2: DRY_RUN PENDING -> APPLYING foi aceito (deveria ser impossível — item 4 da REVISION-01).';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM NOT LIKE '%INVALID_TRANSITION%' AND SQLERRM NOT LIKE '%dry_run_never_applying%' THEN RAISE; END IF;
        RAISE NOTICE 'OK: Seção 5.1 -- DRY_RUN nunca entra em APPLYING (bloqueado por %).', CASE WHEN SQLERRM LIKE '%INVALID_TRANSITION%' THEN 'trigger' ELSE 'CHECK constraint' END;
    END;

    UPDATE public.pokemon_catalog_sourcing_run SET status = 'FAILED', error_summary = 'fixture cleanup 5.1' WHERE id = v_run1.id;

    INSERT INTO public.pokemon_catalog_sourcing_run (asset_source_id, run_type, preflight_run_id)
    VALUES (v_real_pokeapi_id, 'APPLY', (
        SELECT id FROM public.pokemon_catalog_sourcing_run WHERE asset_source_id = v_real_pokeapi_id AND run_type = 'DRY_RUN' ORDER BY created_at DESC LIMIT 1
    )) RETURNING * INTO v_run2;
    -- Nota: este INSERT usa um preflight_run_id só para satisfazer a CHECK de
    -- shape (APPLY exige preflight NOT NULL) -- a validade SEMÂNTICA do
    -- preflight é testada à parte, via open_run, na Seção 8.
    BEGIN
        UPDATE public.pokemon_catalog_sourcing_run SET status = 'ACQUIRING' WHERE id = v_run2.id;
        RAISE EXCEPTION 'FAIL 5.3: APPLY PENDING -> ACQUIRING foi aceito (deveria ser impossível).';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM NOT LIKE '%INVALID_TRANSITION%' AND SQLERRM NOT LIKE '%apply_never_dry_states%' THEN RAISE; END IF;
        RAISE NOTICE 'OK: Seção 5.2 -- APPLY nunca entra em ACQUIRING/PLANNING/COMPLETED_WITH_DIVERGENCES.';
    END;

    UPDATE public.pokemon_catalog_sourcing_run SET status = 'FAILED', error_summary = 'fixture cleanup 5.2' WHERE id = v_run2.id;

    -- =========================================================================
    -- SEÇÃO 6: SOURCE_BUSY real (concorrência) + Seleção correta de constraint
    -- (Fix 6 -- só uq_pokemon_catalog_sourcing_run_active_source vira SOURCE_BUSY)
    -- =========================================================================
    EXECUTE 'SET LOCAL ROLE service_role';

    SELECT * INTO v_open FROM public.open_pokemon_catalog_sourcing_run('DRY_RUN') LIMIT 1;
    IF v_open.outcome <> 'CLAIMED' THEN RAISE EXCEPTION 'FAIL 6.1: open_run não retornou CLAIMED (retornou %).', v_open.outcome; END IF;
    v_dry_run_id := v_open.run_id;

    SELECT * INTO v_open FROM public.open_pokemon_catalog_sourcing_run('DRY_RUN') LIMIT 1;
    IF v_open.outcome <> 'SOURCE_BUSY' THEN RAISE EXCEPTION 'FAIL 6.2: segunda open_run concorrente não retornou SOURCE_BUSY (retornou %).', v_open.outcome; END IF;

    EXECUTE 'RESET ROLE';
    RAISE NOTICE 'OK: Seção 6 -- SOURCE_BUSY real confirmado via open_run com run ativo concorrente (run_id=%).', v_dry_run_id;

    -- =========================================================================
    -- SEÇÃO 7: Stale recovery (fixture corrigida -- heartbeat_at no INSERT,
    -- created_at NUNCA tocado)
    -- =========================================================================
    -- Fecha o run ativo da Seção 6 primeiro para não conflitar com o índice
    -- parcial durante a fixture de stale.
    EXECUTE 'SET LOCAL ROLE service_role';
    PERFORM public.close_failed_pokemon_catalog_sourcing_run(v_dry_run_id, 'fixture cleanup seção 6');
    EXECUTE 'RESET ROLE';

    INSERT INTO public.pokemon_catalog_sourcing_run (asset_source_id, run_type, heartbeat_at)
    VALUES (v_real_pokeapi_id, 'DRY_RUN', NOW() - INTERVAL '45 minutes')
    RETURNING id INTO v_test_region_id; -- reaproveitando variável como id genérico temporário

    EXECUTE 'SET LOCAL ROLE service_role';
    SELECT * INTO v_open FROM public.open_pokemon_catalog_sourcing_run('DRY_RUN') LIMIT 1;
    EXECUTE 'RESET ROLE';

    IF v_open.outcome <> 'CLAIMED' THEN RAISE EXCEPTION 'FAIL 7.1: open_run não reconciliou o run stale e/ou não conseguiu novo claim (outcome=%).', v_open.outcome; END IF;

    PERFORM 1 FROM public.pokemon_catalog_sourcing_run WHERE id = v_test_region_id AND status = 'FAILED' AND error_summary LIKE '%STALE_RUN_RECONCILED%';
    IF NOT FOUND THEN RAISE EXCEPTION 'FAIL 7.2: run stale não foi marcado FAILED/STALE_RUN_RECONCILED pelo Passo 0 de open_run.'; END IF;

    v_dry_run_id := v_open.run_id;
    RAISE NOTICE 'OK: Seção 7 -- stale recovery real confirmado (run antigo reconciliado, novo claim bem-sucedido).';

    -- =========================================================================
    -- SEÇÃO 8: Preflight inválido (real, via open_run como service_role)
    -- =========================================================================
    EXECUTE 'SET LOCAL ROLE service_role';

    BEGIN
        SELECT * INTO v_open FROM public.open_pokemon_catalog_sourcing_run('APPLY', NULL) LIMIT 1;
        RAISE EXCEPTION 'FAIL 8.1: open_run(APPLY, NULL) não rejeitou preflight ausente.';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM NOT LIKE '%MISSING_PREFLIGHT%' THEN RAISE; END IF;
        RAISE NOTICE 'OK: Seção 8.1 -- APPLY sem preflight_run_id rejeitado.';
    END;

    BEGIN
        SELECT * INTO v_open FROM public.open_pokemon_catalog_sourcing_run('DRY_RUN', v_dry_run_id) LIMIT 1;
        RAISE EXCEPTION 'FAIL 8.2: open_run(DRY_RUN, <preflight>) não rejeitou preflight inesperado.';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM NOT LIKE '%UNEXPECTED_PREFLIGHT%' THEN RAISE; END IF;
        RAISE NOTICE 'OK: Seção 8.2 -- DRY_RUN com preflight_run_id inesperado rejeitado.';
    END;

    -- v_dry_run_id ainda está em ACQUIRING (aberto na Seção 7, nunca chegou a
    -- PLAN) -- portanto seu status NÃO é COMPLETED -- válido para testar
    -- rejeição de preflight com status incorreto.
    BEGIN
        SELECT * INTO v_open FROM public.open_pokemon_catalog_sourcing_run('APPLY', v_dry_run_id) LIMIT 1;
        RAISE EXCEPTION 'FAIL 8.3: open_run(APPLY, <preflight não-COMPLETED>) não rejeitou.';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM NOT LIKE '%INVALID_PREFLIGHT_STATUS%' THEN RAISE; END IF;
        RAISE NOTICE 'OK: Seção 8.3 -- preflight com status <> COMPLETED rejeitado.';
    END;

    -- Fecha o run usado como fixture de preflight inválido (Seção 8) antes
    -- de prosseguir -- senão ele permanece ACTIVE (ACQUIRING) e bloqueia
    -- qualquer novo claim para a mesma Fonte via o índice parcial (as
    -- próximas seções precisam poder abrir novos runs).
    PERFORM public.close_failed_pokemon_catalog_sourcing_run(v_dry_run_id, 'fixture cleanup seção 8');
    EXECUTE 'RESET ROLE';

    -- =========================================================================
    -- SEÇÃO 9: Source mismatch (preflight de outra Fonte)
    -- =========================================================================
    -- Cria uma segunda Fonte de teste (code deliberadamente diferente de
    -- 'POKEAPI' -- é exatamente essa diferença que o teste exercita) e um
    -- DRY_RUN COMPLETED "emprestado" dela para simular um preflight de
    -- asset_source diferente. source_order calculado dinamicamente (Fix 3 --
    -- nunca assume 99998/99999 livres).
    DECLARE
        v_other_source_id UUID;
        v_other_dry_run_id UUID;
        v_next_source_order INTEGER;
    BEGIN
        SELECT COALESCE(MAX(source_order), 0) + 1 INTO v_next_source_order FROM public.asset_source;

        INSERT INTO public.asset_source (code, name, source_type, base_url, is_active, source_order)
        VALUES ('OTHER_SOURCE_6820', 'Outra Fonte (fixture 6820)', 'API', 'https://other.example.test', TRUE, v_next_source_order)
        RETURNING id INTO v_other_source_id;

        -- INSERT deve respeitar o trigger de governança (sempre começa
        -- PENDING) -- avança pela máquina de estados legítima até COMPLETED,
        -- nunca insere status terminal diretamente.
        INSERT INTO public.pokemon_catalog_sourcing_run (asset_source_id, run_type)
        VALUES (v_other_source_id, 'DRY_RUN')
        RETURNING id INTO v_other_dry_run_id;
        UPDATE public.pokemon_catalog_sourcing_run SET status = 'ACQUIRING' WHERE id = v_other_dry_run_id;
        UPDATE public.pokemon_catalog_sourcing_run SET status = 'PLANNING' WHERE id = v_other_dry_run_id;
        -- HOTFIX 6110: finished_at via CLOCK_TIMESTAMP() (hora real), não NOW()
        -- (hora de início da transação) -- alinhado ao trigger de governança
        -- (started_at também usa CLOCK_TIMESTAMP()), evita violar
        -- ck_pokemon_catalog_sourcing_run_period em transações longas como
        -- esta (achado runtime do GATE 5 HOTFIX 6110).
        UPDATE public.pokemon_catalog_sourcing_run SET status = 'COMPLETED', snapshot_hash = REPEAT('a', 64), finished_at = CLOCK_TIMESTAMP() WHERE id = v_other_dry_run_id;

        EXECUTE 'SET LOCAL ROLE service_role';
        BEGIN
            SELECT * INTO v_open FROM public.open_pokemon_catalog_sourcing_run('APPLY', v_other_dry_run_id) LIMIT 1;
            RAISE EXCEPTION 'FAIL 9.1: open_run(APPLY, <preflight de outra Fonte>) não rejeitou.';
        EXCEPTION WHEN OTHERS THEN
            IF SQLERRM NOT LIKE '%PREFLIGHT_ASSET_SOURCE_MISMATCH%' THEN RAISE; END IF;
            RAISE NOTICE 'OK: Seção 9 -- preflight de asset_source diferente rejeitado (ASSET_SOURCE_MISMATCH), source_order de teste calculado dinamicamente (%).', v_next_source_order;
        END;
        EXECUTE 'RESET ROLE';
    END;

    -- =========================================================================
    -- SEÇÃO 10: Conflito de chave natural -> DIVERGENT (nunca auto-bind)
    -- =========================================================================
    INSERT INTO public.pokemon_region (code, canonical_name) VALUES ('TEST_REGION_6820', 'Test Region 6820') RETURNING id INTO v_test_region_id;

    v_bad_snapshot := jsonb_build_object(
        'regions', jsonb_build_array(jsonb_build_object('external_region_id', '900101', 'code', 'TEST_REGION_6820', 'canonical_name', 'Test Region 6820'))
    );
    v_reconcile := public.reconcile_pokemon_catalog_sourcing_snapshot(v_real_pokeapi_id, v_bad_snapshot);
    IF (v_reconcile -> 'regions' ->> 'divergent')::INT <> 1 THEN RAISE EXCEPTION 'FAIL 10.1: colisão de chave natural sem referência externa não classificou DIVERGENT (%).', v_reconcile -> 'regions'; END IF;

    PERFORM 1 FROM public.pokemon_region_external_reference WHERE pokemon_region_id = v_test_region_id;
    IF FOUND THEN RAISE EXCEPTION 'FAIL 10.2: auto-bind ocorreu (reconcile deve ser read-only).'; END IF;

    -- Fix 2: colisão em UM ÚNICO eixo de Generation (code OU ordinal_number).
    INSERT INTO public.pokemon_region (code, canonical_name) VALUES ('TEST_REGION_6820_B', 'Test Region 6820 B');
    INSERT INTO public.pokemon_generation (code, canonical_name, ordinal_number, main_region_id)
    VALUES ('TEST_GEN_6820', 'Test Gen 6820', 999001, (SELECT id FROM public.pokemon_region WHERE code = 'TEST_REGION_6820_B'));

    -- colisão só no eixo `code` (ordinal diferente) -> deve ser DIVERGENT.
    v_bad_snapshot := jsonb_build_object(
        'generations', jsonb_build_array(jsonb_build_object(
            'external_generation_id', '900102', 'code', 'TEST_GEN_6820', 'canonical_name', 'X',
            'ordinal_number', 999002, 'main_region_external_id', '900999'
        ))
    );
    v_reconcile := public.reconcile_pokemon_catalog_sourcing_snapshot(v_real_pokeapi_id, v_bad_snapshot);
    IF (v_reconcile -> 'generations' ->> 'divergent')::INT <> 1 THEN RAISE EXCEPTION 'FAIL 10.3 (Fix 2): colisão de Generation apenas no eixo code não classificou DIVERGENT (%).', v_reconcile -> 'generations'; END IF;

    -- colisão só no eixo `ordinal_number` (code diferente) -> deve ser DIVERGENT.
    v_bad_snapshot := jsonb_build_object(
        'generations', jsonb_build_array(jsonb_build_object(
            'external_generation_id', '900103', 'code', 'TEST_GEN_6820_DIFF', 'canonical_name', 'X',
            'ordinal_number', 999001, 'main_region_external_id', '900999'
        ))
    );
    v_reconcile := public.reconcile_pokemon_catalog_sourcing_snapshot(v_real_pokeapi_id, v_bad_snapshot);
    IF (v_reconcile -> 'generations' ->> 'divergent')::INT <> 1 THEN RAISE EXCEPTION 'FAIL 10.4 (Fix 2): colisão de Generation apenas no eixo ordinal_number não classificou DIVERGENT (%).', v_reconcile -> 'generations'; END IF;

    RAISE NOTICE 'OK: Seção 10 -- natural-key collision (incluindo eixos independentes de Generation, Fix 2) classifica DIVERGENT, nunca auto-bind.';

    DELETE FROM public.pokemon_generation WHERE code = 'TEST_GEN_6820';
    DELETE FROM public.pokemon_region WHERE code IN ('TEST_REGION_6820', 'TEST_REGION_6820_B');

    -- =========================================================================
    -- SEÇÃO 11 + 12 + 13 + 14: CICLO COMPLETO REAL — Initial Load lockstep
    -- (5 famílias), cross-check S=P via PLAN real, rollback atômico em
    -- divergência de APPLY, idempotência.
    -- =========================================================================

    -- Resolve o Pokédex Nacional real (se existir) e REUTILIZA a referência
    -- externa para a Fonte POKEAPI real se ela já existir (Fix 3 -- nunca
    -- insere duplicata; só cria quando de fato ausente).
    SELECT id, canonical_name INTO v_real_national_pokedex_id, v_real_national_pokedex_name
    FROM public.pokedex WHERE code = 'NATIONAL';

    IF v_real_national_pokedex_id IS NOT NULL THEN
        SELECT external_pokedex_id INTO v_national_external_pokedex_id
        FROM public.pokedex_external_reference
        WHERE pokedex_id = v_real_national_pokedex_id AND asset_source_id = v_real_pokeapi_id;

        v_national_xref_exists := (v_national_external_pokedex_id IS NOT NULL);

        IF NOT v_national_xref_exists THEN
            v_national_external_pokedex_id := '1';
            INSERT INTO public.pokedex_external_reference (pokedex_id, asset_source_id, external_pokedex_id)
            VALUES (v_real_national_pokedex_id, v_real_pokeapi_id, v_national_external_pokedex_id);
            RAISE NOTICE 'INFO: Seção 11 -- Pokédex Nacional real existe (id=%) mas ainda sem referência externa para POKEAPI -- criada dentro desta transação de teste.', v_real_national_pokedex_id;
        ELSE
            RAISE NOTICE 'INFO: Seção 11 -- Pokédex Nacional real já possui referência externa para POKEAPI (external_pokedex_id=%) -- reutilizada, nenhuma duplicata criada.', v_national_external_pokedex_id;
        END IF;

        v_expected_pokedex_outcome := 'UNCHANGED';
        v_national_pokedex_name := v_real_national_pokedex_name;
    ELSE
        v_national_external_pokedex_id := '1';
        v_expected_pokedex_outcome := 'NEW';
        v_national_pokedex_name := 'National Pokédex (fixture 6820)';
        RAISE NOTICE 'INFO: Seção 11 -- nenhum Pokédex Nacional real encontrado -- família pokedex esperada NEW.';
    END IF;

    -- Snapshot "bom": Region/Generation/Species com identificadores
    -- exclusivos de teste (nunca colidem com dados reais) -- Initial Load
    -- lockstep (Fix 1): Generation referencia Region NEW no MESMO snapshot;
    -- Species referencia Generation NEW no MESMO snapshot.
    v_snapshot := jsonb_build_object(
        'regions', jsonb_build_array(jsonb_build_object('external_region_id', '900201', 'code', 'TEST_REGION_6820_GOOD', 'canonical_name', 'Test Region Good', 'source_url', 'https://pokeapi.example.test/region/900201', 'metadata', '{}'::JSONB)),
        'generations', jsonb_build_array(jsonb_build_object('external_generation_id', '900202', 'code', 'TEST_GEN_6820_GOOD', 'canonical_name', 'Test Gen Good', 'ordinal_number', 999011, 'main_region_external_id', '900201', 'source_url', 'https://pokeapi.example.test/generation/900202', 'metadata', '{}'::JSONB)),
        'species', jsonb_build_array(jsonb_build_object('external_species_id', '900203', 'national_dex_number', 999011, 'canonical_name', 'Test Species Good', 'generation_external_id', '900202', 'source_url', 'https://pokeapi.example.test/pokemon-species/900203', 'metadata', '{}'::JSONB)),
        'national_pokedex', jsonb_build_object('external_pokedex_id', v_national_external_pokedex_id, 'code', 'NATIONAL', 'canonical_name', v_national_pokedex_name, 'source_url', 'https://pokeapi.example.test/pokedex/1', 'metadata', '{}'::JSONB),
        'national_pokedex_entries', jsonb_build_array(jsonb_build_object('external_species_id', '900203', 'position_number', 999011))
    );

    -- ---- SEÇÃO 12: cross-check S=P via PLAN real (VALIDATION FAILURE) ------
    EXECUTE 'SET LOCAL ROLE service_role';
    SELECT * INTO v_open FROM public.open_pokemon_catalog_sourcing_run('DRY_RUN') LIMIT 1;
    IF v_open.outcome <> 'CLAIMED' THEN RAISE EXCEPTION 'FAIL 12.0: open_run não retornou CLAIMED para teste de S=P (outcome=%).', v_open.outcome; END IF;
    PERFORM public.heartbeat_pokemon_catalog_sourcing_run(v_open.run_id);

    v_bad_snapshot := v_snapshot || jsonb_build_object(
        'national_pokedex_entries', jsonb_build_array(jsonb_build_object('external_species_id', '900299', 'position_number', 999011))
        -- external_species_id "900299" não existe em species[] -> S<>P.
    );
    SELECT * INTO v_plan FROM public.plan_pokemon_catalog_sourcing_run(v_open.run_id, v_bad_snapshot) LIMIT 1;
    IF v_plan.outcome <> 'VALIDATION_FAILURE' THEN RAISE EXCEPTION 'FAIL 12.1: PLAN com S<>P não retornou VALIDATION_FAILURE (retornou %).', v_plan.outcome; END IF;
    PERFORM 1 FROM public.pokemon_catalog_sourcing_run WHERE id = v_open.run_id AND status = 'FAILED' AND error_summary LIKE '%SP_MISMATCH%';
    IF NOT FOUND THEN RAISE EXCEPTION 'FAIL 12.2: run não foi marcado FAILED/SP_MISMATCH após VALIDATION_FAILURE de PLAN.'; END IF;
    EXECUTE 'RESET ROLE';
    RAISE NOTICE 'OK: Seção 12 -- cross-check S=P real via PLAN (VALIDATION_FAILURE/SP_MISMATCH) confirmado.';

    -- ---- SEÇÃO 11: ciclo feliz — 5 famílias, zero DIVERGENT, PLAN COMPLETED
    EXECUTE 'SET LOCAL ROLE service_role';
    SELECT * INTO v_open FROM public.open_pokemon_catalog_sourcing_run('DRY_RUN') LIMIT 1;
    IF v_open.outcome <> 'CLAIMED' THEN RAISE EXCEPTION 'FAIL 11.0: open_run não retornou CLAIMED (outcome=%).', v_open.outcome; END IF;
    v_dry_run_id := v_open.run_id;
    PERFORM public.heartbeat_pokemon_catalog_sourcing_run(v_dry_run_id);

    SELECT * INTO v_plan FROM public.plan_pokemon_catalog_sourcing_run(v_dry_run_id, v_snapshot) LIMIT 1;
    IF v_plan.outcome <> 'COMPLETED' THEN RAISE EXCEPTION 'FAIL 11.1: PLAN do snapshot bom não retornou COMPLETED (retornou %, plan_summary=%).', v_plan.outcome, v_plan.plan_summary; END IF;
    IF (v_plan.plan_summary -> 'regions' ->> 'new')::INT <> 1 THEN RAISE EXCEPTION 'FAIL 11.2: regions.new <> 1 (%).', v_plan.plan_summary -> 'regions'; END IF;
    IF (v_plan.plan_summary -> 'generations' ->> 'new')::INT <> 1 THEN RAISE EXCEPTION 'FAIL 11.3: generations.new <> 1 (lockstep de Region NEW falhou -- Fix 1) (%).', v_plan.plan_summary -> 'generations'; END IF;
    IF (v_plan.plan_summary -> 'species' ->> 'new')::INT <> 1 THEN RAISE EXCEPTION 'FAIL 11.4: species.new <> 1 (lockstep de Generation NEW falhou -- Fix 1) (%).', v_plan.plan_summary -> 'species'; END IF;
    IF (v_plan.plan_summary -> 'pokedex' ->> LOWER(v_expected_pokedex_outcome))::INT <> 1 THEN
        RAISE EXCEPTION 'FAIL 11.5: pokedex.% <> 1, dado o ambiente detectado (%).', LOWER(v_expected_pokedex_outcome), v_plan.plan_summary -> 'pokedex';
    END IF;
    IF (v_plan.plan_summary -> 'pokedex' ->> 'divergent')::INT <> 0 THEN
        RAISE EXCEPTION 'FAIL 11.5b: pokedex.divergent <> 0 (%).', v_plan.plan_summary -> 'pokedex';
    END IF;
    IF (v_plan.plan_summary -> 'positions' ->> 'new')::INT <> 1 THEN RAISE EXCEPTION 'FAIL 11.6: positions.new <> 1 (%).', v_plan.plan_summary -> 'positions'; END IF;

    RAISE NOTICE 'OK: Seção 11 -- Initial Load lockstep real confirmado: regions/generations/species/positions NEW=1, pokedex=% (esperado), zero DIVERGENT em qualquer família.', v_expected_pokedex_outcome;

    -- Role choreography (Fix 4): RESET explícito antes de qualquer DML/SELECT
    -- direto sobre o catálogo fechado, que a Seção 13 precisa fazer a seguir
    -- como fixture (postgres/owner), nunca como service_role.
    EXECUTE 'RESET ROLE';

    -- ---- SEÇÃO 13: rollback atômico em divergência de APPLY ----------------
    EXECUTE 'SET LOCAL ROLE service_role';
    SELECT * INTO v_open FROM public.open_pokemon_catalog_sourcing_run('APPLY', v_dry_run_id) LIMIT 1;
    IF v_open.outcome <> 'CLAIMED' THEN RAISE EXCEPTION 'FAIL 13.0: open_run(APPLY) não retornou CLAIMED (outcome=%).', v_open.outcome; END IF;
    v_apply_run_id := v_open.run_id;
    EXECUTE 'RESET ROLE';

    -- Provoca divergência concorrente: cria uma Region física com o MESMO
    -- code do snapshot aprovado, SEM referência externa -- a fresh
    -- reconciliation do APPLY deve detectar isso e abortar. Fixture executada
    -- como postgres/owner (Fix 4) -- NUNCA sob service_role, que não possui
    -- nenhum grant direto em pokemon_region.
    INSERT INTO public.pokemon_region (code, canonical_name) VALUES ('TEST_REGION_6820_GOOD', 'Divergência concorrente 6820');
    SELECT COUNT(*) INTO v_regions_before FROM public.pokemon_region;

    EXECUTE 'SET LOCAL ROLE service_role';
    BEGIN
        SELECT * INTO v_apply FROM public.apply_pokemon_catalog_sourcing_run(v_apply_run_id, v_snapshot) LIMIT 1;
        RAISE EXCEPTION 'FAIL 13.1: APPLY com divergência concorrente não lançou exceção (retornou outcome=%).', v_apply.outcome;
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM NOT LIKE '%DIVERGENCE%' THEN RAISE; END IF;
        RAISE NOTICE 'OK: Seção 13.1 -- APPLY com divergência concorrente lançou exceção (%).', LEFT(SQLERRM, 80);
    END;
    EXECUTE 'RESET ROLE';

    -- Inspeção direta do catálogo (pokemon_region) e do run ledger, ambas
    -- como postgres/owner -- nunca sob service_role (Fix 4).
    SELECT COUNT(*) INTO v_regions_after FROM public.pokemon_region;
    IF v_regions_after <> v_regions_before THEN RAISE EXCEPTION 'FAIL 13.2: contagem de pokemon_region mudou após rollback de APPLY divergente (antes=%, depois=%) -- escrita parcial vazou.', v_regions_before, v_regions_after; END IF;

    PERFORM 1 FROM public.pokemon_catalog_sourcing_run WHERE id = v_apply_run_id AND status = 'PENDING';
    IF NOT FOUND THEN RAISE EXCEPTION 'FAIL 13.3: run de APPLY não permaneceu em PENDING após rollback total (esperado -- toda a transação, inclusive a transição para APPLYING, reverte).'; END IF;

    -- Fecha o run via closeout (item 5) em vez de deixar bloqueando a Fonte.
    EXECUTE 'SET LOCAL ROLE service_role';
    PERFORM public.close_failed_pokemon_catalog_sourcing_run(v_apply_run_id, 'FRESH_DIVERGENCE (fixture 6820, esperado)');
    EXECUTE 'RESET ROLE';

    PERFORM 1 FROM public.pokemon_catalog_sourcing_run WHERE id = v_apply_run_id AND status = 'FAILED';
    IF NOT FOUND THEN RAISE EXCEPTION 'FAIL 13.4: close_failed_pokemon_catalog_sourcing_run não marcou o run como FAILED.'; END IF;
    RAISE NOTICE 'OK: Seção 13 -- rollback atômico confirmado (zero escrita parcial) + closeout via 6108 liberou o guard de run ativo.';

    -- Remove a Region "divergente" fabricada para o teste (fixture, owner),
    -- e reabre um novo DRY_RUN+APPLY limpo para prosseguir ao teste real.
    DELETE FROM public.pokemon_region WHERE code = 'TEST_REGION_6820_GOOD' AND canonical_name = 'Divergência concorrente 6820';

    EXECUTE 'SET LOCAL ROLE service_role';
    SELECT * INTO v_open FROM public.open_pokemon_catalog_sourcing_run('DRY_RUN') LIMIT 1;
    IF v_open.outcome <> 'CLAIMED' THEN RAISE EXCEPTION 'FAIL 13.5: reabertura de DRY_RUN pós-closeout não retornou CLAIMED (outcome=%).', v_open.outcome; END IF;
    v_dry_run_id := v_open.run_id;
    PERFORM public.heartbeat_pokemon_catalog_sourcing_run(v_dry_run_id);
    SELECT * INTO v_plan FROM public.plan_pokemon_catalog_sourcing_run(v_dry_run_id, v_snapshot) LIMIT 1;
    IF v_plan.outcome <> 'COMPLETED' THEN RAISE EXCEPTION 'FAIL 13.6: PLAN de reabertura não retornou COMPLETED (%).', v_plan.outcome; END IF;

    SELECT * INTO v_open FROM public.open_pokemon_catalog_sourcing_run('APPLY', v_dry_run_id) LIMIT 1;
    IF v_open.outcome <> 'CLAIMED' THEN RAISE EXCEPTION 'FAIL 13.7: open_run(APPLY) de reabertura não retornou CLAIMED (%).', v_open.outcome; END IF;
    v_apply_run_id := v_open.run_id;

    SELECT * INTO v_apply FROM public.apply_pokemon_catalog_sourcing_run(v_apply_run_id, v_snapshot) LIMIT 1;
    IF v_apply.outcome <> 'COMPLETED' THEN RAISE EXCEPTION 'FAIL 13.8: APPLY real não retornou COMPLETED (%, apply_summary=%).', v_apply.outcome, v_apply.apply_summary; END IF;
    IF (v_apply.apply_summary -> 'regions' ->> 'inserted')::INT <> 1 THEN RAISE EXCEPTION 'FAIL 13.9: regions.inserted <> 1 no APPLY real (%).', v_apply.apply_summary -> 'regions'; END IF;
    IF (v_apply.apply_summary -> 'species' ->> 'inserted')::INT <> 1 THEN RAISE EXCEPTION 'FAIL 13.10: species.inserted <> 1 no APPLY real (%).', v_apply.apply_summary -> 'species'; END IF;

    -- Fix 2 (item 6 da REVISION-02): prova de que o primeiro APPLY NÃO
    -- produz dupla contagem. Como Region/Generation/Species/Position são
    -- todos NEW=1 e nada preexistia com esses natural keys, unchanged deve
    -- ser 0 em todas essas famílias -- se apply_summary.unchanged tivesse
    -- vindo de v_post (pós-escrita, bug da v2.0), apareceria 1 aqui em vez
    -- de 0, porque v_post já reclassifica a própria linha recém-escrita como
    -- UNCHANGED.
    IF (v_apply.apply_summary -> 'regions' ->> 'unchanged')::INT <> 0 THEN RAISE EXCEPTION 'FAIL 13.11 (Fix 2): regions.unchanged <> 0 no primeiro APPLY -- indício de dupla contagem (apply_summary=%).', v_apply.apply_summary -> 'regions'; END IF;
    IF (v_apply.apply_summary -> 'generations' ->> 'unchanged')::INT <> 0 THEN RAISE EXCEPTION 'FAIL 13.12 (Fix 2): generations.unchanged <> 0 no primeiro APPLY -- indício de dupla contagem (%).', v_apply.apply_summary -> 'generations'; END IF;
    IF (v_apply.apply_summary -> 'species' ->> 'unchanged')::INT <> 0 THEN RAISE EXCEPTION 'FAIL 13.13 (Fix 2): species.unchanged <> 0 no primeiro APPLY -- indício de dupla contagem (%).', v_apply.apply_summary -> 'species'; END IF;
    IF (v_apply.apply_summary -> 'positions' ->> 'unchanged')::INT <> 0 THEN RAISE EXCEPTION 'FAIL 13.14 (Fix 2): positions.unchanged <> 0 no primeiro APPLY -- indício de dupla contagem (%).', v_apply.apply_summary -> 'positions'; END IF;
    IF (v_apply.apply_summary -> 'regions' ->> 'inserted')::INT + (v_apply.apply_summary -> 'regions' ->> 'updated')::INT + (v_apply.apply_summary -> 'regions' ->> 'unchanged')::INT <> 1 THEN
        RAISE EXCEPTION 'FAIL 13.15 (Fix 2): regions inserted+updated+unchanged <> 1 (total processado) no primeiro APPLY (%).', v_apply.apply_summary -> 'regions';
    END IF;

    RAISE NOTICE 'OK: Seção 13 (continuação) -- APPLY real bem-sucedido, sem dupla contagem (inserted+updated+unchanged = total processado): apply_summary=%', v_apply.apply_summary;

    -- ---- SEÇÃO 14: idempotência — segundo ciclo DRY_RUN+APPLY, 100% unchanged
    EXECUTE 'SET LOCAL ROLE service_role';

    SELECT * INTO v_open FROM public.open_pokemon_catalog_sourcing_run('DRY_RUN') LIMIT 1;
    IF v_open.outcome <> 'CLAIMED' THEN RAISE EXCEPTION 'FAIL 14.0: open_run (2º ciclo) não retornou CLAIMED (%).', v_open.outcome; END IF;
    v_dry_run_id := v_open.run_id;
    PERFORM public.heartbeat_pokemon_catalog_sourcing_run(v_dry_run_id);
    SELECT * INTO v_plan FROM public.plan_pokemon_catalog_sourcing_run(v_dry_run_id, v_snapshot) LIMIT 1;
    IF v_plan.outcome <> 'COMPLETED' THEN RAISE EXCEPTION 'FAIL 14.1: PLAN do 2º ciclo não retornou COMPLETED (%).', v_plan.outcome; END IF;
    IF (v_plan.plan_summary -> 'regions' ->> 'unchanged')::INT <> 1
       OR (v_plan.plan_summary -> 'generations' ->> 'unchanged')::INT <> 1
       OR (v_plan.plan_summary -> 'species' ->> 'unchanged')::INT <> 1
       OR (v_plan.plan_summary -> 'positions' ->> 'unchanged')::INT <> 1
    THEN
        RAISE EXCEPTION 'FAIL 14.2: PLAN do 2º ciclo não é 100%% unchanged (%).', v_plan.plan_summary;
    END IF;

    SELECT * INTO v_open FROM public.open_pokemon_catalog_sourcing_run('APPLY', v_dry_run_id) LIMIT 1;
    IF v_open.outcome <> 'CLAIMED' THEN RAISE EXCEPTION 'FAIL 14.3: open_run(APPLY) do 2º ciclo não retornou CLAIMED (%).', v_open.outcome; END IF;
    v_apply_run_id := v_open.run_id;

    SELECT * INTO v_apply FROM public.apply_pokemon_catalog_sourcing_run(v_apply_run_id, v_snapshot) LIMIT 1;
    IF v_apply.outcome <> 'COMPLETED' THEN RAISE EXCEPTION 'FAIL 14.4: APPLY do 2º ciclo não retornou COMPLETED (%).', v_apply.outcome; END IF;

    -- Item 6 da REVISION-02: inserted=0, updated=0 e unchanged=total em
    -- TODAS as famílias com contagem fixa conhecida (regions/generations/
    -- species/positions=1; pokedex depende do ambiente detectado na Seção
    -- 11, mas seu total também é sempre 1 -- ou já preexistia, UNCHANGED, ou
    -- foi criado no 1º APPLY e agora está UNCHANGED no 2º).
    IF (v_apply.apply_summary -> 'regions' ->> 'inserted')::INT <> 0 OR (v_apply.apply_summary -> 'regions' ->> 'updated')::INT <> 0 OR (v_apply.apply_summary -> 'regions' ->> 'unchanged')::INT <> 1 THEN
        RAISE EXCEPTION 'FAIL 14.5: APPLY idempotente não é inserted=0/updated=0/unchanged=1 em regions (%).', v_apply.apply_summary -> 'regions';
    END IF;
    IF (v_apply.apply_summary -> 'generations' ->> 'inserted')::INT <> 0 OR (v_apply.apply_summary -> 'generations' ->> 'updated')::INT <> 0 OR (v_apply.apply_summary -> 'generations' ->> 'unchanged')::INT <> 1 THEN
        RAISE EXCEPTION 'FAIL 14.6: APPLY idempotente não é inserted=0/updated=0/unchanged=1 em generations (%).', v_apply.apply_summary -> 'generations';
    END IF;
    IF (v_apply.apply_summary -> 'species' ->> 'inserted')::INT <> 0 OR (v_apply.apply_summary -> 'species' ->> 'updated')::INT <> 0 OR (v_apply.apply_summary -> 'species' ->> 'unchanged')::INT <> 1 THEN
        RAISE EXCEPTION 'FAIL 14.7: APPLY idempotente não é inserted=0/updated=0/unchanged=1 em species (%).', v_apply.apply_summary -> 'species';
    END IF;
    IF (v_apply.apply_summary -> 'pokedex' ->> 'inserted')::INT <> 0 OR (v_apply.apply_summary -> 'pokedex' ->> 'updated')::INT <> 0 OR (v_apply.apply_summary -> 'pokedex' ->> 'unchanged')::INT <> 1 THEN
        RAISE EXCEPTION 'FAIL 14.8: APPLY idempotente não é inserted=0/updated=0/unchanged=1 em pokedex (%).', v_apply.apply_summary -> 'pokedex';
    END IF;
    IF (v_apply.apply_summary -> 'positions' ->> 'inserted')::INT <> 0 OR (v_apply.apply_summary -> 'positions' ->> 'unchanged')::INT <> 1 THEN
        RAISE EXCEPTION 'FAIL 14.9: APPLY idempotente não é inserted=0/unchanged=1 em positions (%).', v_apply.apply_summary -> 'positions';
    END IF;

    EXECUTE 'RESET ROLE';
    RAISE NOTICE 'OK: Seção 14 -- idempotência real confirmada: 2º DRY_RUN 100%% unchanged, 2º APPLY zero writes e unchanged=total em TODAS as famílias (regions/generations/species/pokedex/positions).';

    -- =========================================================================
    -- SEÇÃO 15: VALIDATION FAILURE dos itens 13-18 do 6104 REVISION-02/03
    -- (natural key duplicada NO PRÓPRIO snapshot, numeric NULL, códigos de
    -- region/generation fora do formato, source_url/metadata inválidos) —
    -- item 6 da REVISION-02, complementado pelo item 2 da REVISION-03
    -- (GENERATION_CODE_INVALID, 15.6 — REGION_CODE_INVALID de 15.5 preservado)
    -- =========================================================================

    -- 15.1 -- NATURAL_KEY_DUPLICATE_IN_SNAPSHOT: duas regions com o MESMO
    -- code dentro do mesmo snapshot (external_region_id diferentes -- não é
    -- EXTERNAL_ID_DUPLICATE, é colisão de chave natural).
    EXECUTE 'SET LOCAL ROLE service_role';
    SELECT * INTO v_open FROM public.open_pokemon_catalog_sourcing_run('DRY_RUN') LIMIT 1;
    IF v_open.outcome <> 'CLAIMED' THEN RAISE EXCEPTION 'FAIL 15.0: open_run não retornou CLAIMED para teste de natural key duplicada (outcome=%).', v_open.outcome; END IF;
    PERFORM public.heartbeat_pokemon_catalog_sourcing_run(v_open.run_id);

    v_bad_snapshot := v_snapshot || jsonb_build_object(
        'regions', jsonb_build_array(
            jsonb_build_object('external_region_id', '900201', 'code', 'TEST_REGION_6820_GOOD', 'canonical_name', 'Test Region Good', 'source_url', 'https://pokeapi.example.test/region/900201', 'metadata', '{}'::JSONB),
            jsonb_build_object('external_region_id', '900291', 'code', 'TEST_REGION_6820_GOOD', 'canonical_name', 'Duplicata de code', 'source_url', 'https://pokeapi.example.test/region/900291', 'metadata', '{}'::JSONB)
        )
    );
    SELECT * INTO v_plan FROM public.plan_pokemon_catalog_sourcing_run(v_open.run_id, v_bad_snapshot) LIMIT 1;
    IF v_plan.outcome <> 'VALIDATION_FAILURE' THEN RAISE EXCEPTION 'FAIL 15.1: PLAN com regions[].code duplicado no snapshot não retornou VALIDATION_FAILURE (retornou %).', v_plan.outcome; END IF;
    PERFORM 1 FROM public.pokemon_catalog_sourcing_run WHERE id = v_open.run_id AND status = 'FAILED' AND error_summary LIKE '%NATURAL_KEY_DUPLICATE_IN_SNAPSHOT%';
    IF NOT FOUND THEN RAISE EXCEPTION 'FAIL 15.1b: run não foi marcado FAILED/NATURAL_KEY_DUPLICATE_IN_SNAPSHOT.'; END IF;
    RAISE NOTICE 'OK: Seção 15.1 -- NATURAL_KEY_DUPLICATE_IN_SNAPSHOT (regions[].code) real via PLAN confirmado.';

    -- 15.2 -- NON_POSITIVE_NUMBER (NULL): generations[].ordinal_number NULL
    -- deve ser rejeitado (a v2.0 comparava só "<= 0", que deixava NULL
    -- passar -- Fix REVISION-02).
    SELECT * INTO v_open FROM public.open_pokemon_catalog_sourcing_run('DRY_RUN') LIMIT 1;
    IF v_open.outcome <> 'CLAIMED' THEN RAISE EXCEPTION 'FAIL 15.2.0: open_run não retornou CLAIMED para teste de numeric NULL (outcome=%).', v_open.outcome; END IF;
    PERFORM public.heartbeat_pokemon_catalog_sourcing_run(v_open.run_id);

    v_bad_snapshot := v_snapshot || jsonb_build_object(
        'generations', jsonb_build_array(jsonb_build_object('external_generation_id', '900202', 'code', 'TEST_GEN_6820_GOOD', 'canonical_name', 'Test Gen Good', 'ordinal_number', NULL, 'main_region_external_id', '900201', 'source_url', 'https://pokeapi.example.test/generation/900202', 'metadata', '{}'::JSONB))
    );
    SELECT * INTO v_plan FROM public.plan_pokemon_catalog_sourcing_run(v_open.run_id, v_bad_snapshot) LIMIT 1;
    IF v_plan.outcome <> 'VALIDATION_FAILURE' THEN RAISE EXCEPTION 'FAIL 15.2: PLAN com generations[].ordinal_number NULL não retornou VALIDATION_FAILURE (retornou %).', v_plan.outcome; END IF;
    PERFORM 1 FROM public.pokemon_catalog_sourcing_run WHERE id = v_open.run_id AND status = 'FAILED' AND error_summary LIKE '%NON_POSITIVE_NUMBER%';
    IF NOT FOUND THEN RAISE EXCEPTION 'FAIL 15.2b: run não foi marcado FAILED/NON_POSITIVE_NUMBER para ordinal_number NULL.'; END IF;
    RAISE NOTICE 'OK: Seção 15.2 -- NON_POSITIVE_NUMBER (ordinal_number NULL, não apenas <= 0) real via PLAN confirmado.';

    -- 15.3 -- SOURCE_URL_INVALID: source_url ausente em species[].
    SELECT * INTO v_open FROM public.open_pokemon_catalog_sourcing_run('DRY_RUN') LIMIT 1;
    IF v_open.outcome <> 'CLAIMED' THEN RAISE EXCEPTION 'FAIL 15.3.0: open_run não retornou CLAIMED para teste de source_url ausente (outcome=%).', v_open.outcome; END IF;
    PERFORM public.heartbeat_pokemon_catalog_sourcing_run(v_open.run_id);

    v_bad_snapshot := v_snapshot || jsonb_build_object(
        'species', jsonb_build_array(jsonb_build_object('external_species_id', '900203', 'national_dex_number', 999011, 'canonical_name', 'Test Species Good', 'generation_external_id', '900202', 'source_url', NULL, 'metadata', '{}'::JSONB))
    );
    SELECT * INTO v_plan FROM public.plan_pokemon_catalog_sourcing_run(v_open.run_id, v_bad_snapshot) LIMIT 1;
    IF v_plan.outcome <> 'VALIDATION_FAILURE' THEN RAISE EXCEPTION 'FAIL 15.3: PLAN com species[].source_url ausente não retornou VALIDATION_FAILURE (retornou %).', v_plan.outcome; END IF;
    PERFORM 1 FROM public.pokemon_catalog_sourcing_run WHERE id = v_open.run_id AND status = 'FAILED' AND error_summary LIKE '%SOURCE_URL_INVALID%';
    IF NOT FOUND THEN RAISE EXCEPTION 'FAIL 15.3b: run não foi marcado FAILED/SOURCE_URL_INVALID.'; END IF;
    RAISE NOTICE 'OK: Seção 15.3 -- SOURCE_URL_INVALID (ausente) real via PLAN confirmado.';

    -- 15.4 -- METADATA_INVALID: metadata como array (não-objeto) em regions[].
    SELECT * INTO v_open FROM public.open_pokemon_catalog_sourcing_run('DRY_RUN') LIMIT 1;
    IF v_open.outcome <> 'CLAIMED' THEN RAISE EXCEPTION 'FAIL 15.4.0: open_run não retornou CLAIMED para teste de metadata inválido (outcome=%).', v_open.outcome; END IF;
    PERFORM public.heartbeat_pokemon_catalog_sourcing_run(v_open.run_id);

    v_bad_snapshot := v_snapshot || jsonb_build_object(
        'regions', jsonb_build_array(jsonb_build_object('external_region_id', '900201', 'code', 'TEST_REGION_6820_GOOD', 'canonical_name', 'Test Region Good', 'source_url', 'https://pokeapi.example.test/region/900201', 'metadata', '[]'::JSONB))
    );
    SELECT * INTO v_plan FROM public.plan_pokemon_catalog_sourcing_run(v_open.run_id, v_bad_snapshot) LIMIT 1;
    IF v_plan.outcome <> 'VALIDATION_FAILURE' THEN RAISE EXCEPTION 'FAIL 15.4: PLAN com regions[].metadata como array não retornou VALIDATION_FAILURE (retornou %).', v_plan.outcome; END IF;
    PERFORM 1 FROM public.pokemon_catalog_sourcing_run WHERE id = v_open.run_id AND status = 'FAILED' AND error_summary LIKE '%METADATA_INVALID%';
    IF NOT FOUND THEN RAISE EXCEPTION 'FAIL 15.4b: run não foi marcado FAILED/METADATA_INVALID.'; END IF;
    RAISE NOTICE 'OK: Seção 15.4 -- METADATA_INVALID (não-objeto) real via PLAN confirmado.';

    -- 15.5 -- REGION_CODE_INVALID: code fora do formato ^[A-Z][A-Z0-9_]*$.
    SELECT * INTO v_open FROM public.open_pokemon_catalog_sourcing_run('DRY_RUN') LIMIT 1;
    IF v_open.outcome <> 'CLAIMED' THEN RAISE EXCEPTION 'FAIL 15.5.0: open_run não retornou CLAIMED para teste de code inválido (outcome=%).', v_open.outcome; END IF;
    PERFORM public.heartbeat_pokemon_catalog_sourcing_run(v_open.run_id);

    v_bad_snapshot := v_snapshot || jsonb_build_object(
        'regions', jsonb_build_array(jsonb_build_object('external_region_id', '900201', 'code', 'test_region_lowercase', 'canonical_name', 'Test Region Good', 'source_url', 'https://pokeapi.example.test/region/900201', 'metadata', '{}'::JSONB))
    );
    SELECT * INTO v_plan FROM public.plan_pokemon_catalog_sourcing_run(v_open.run_id, v_bad_snapshot) LIMIT 1;
    IF v_plan.outcome <> 'VALIDATION_FAILURE' THEN RAISE EXCEPTION 'FAIL 15.5: PLAN com regions[].code fora do formato não retornou VALIDATION_FAILURE (retornou %).', v_plan.outcome; END IF;
    PERFORM 1 FROM public.pokemon_catalog_sourcing_run WHERE id = v_open.run_id AND status = 'FAILED' AND error_summary LIKE '%REGION_CODE_INVALID%';
    IF NOT FOUND THEN RAISE EXCEPTION 'FAIL 15.5b: run não foi marcado FAILED/REGION_CODE_INVALID.'; END IF;
    RAISE NOTICE 'OK: Seção 15.5 -- REGION_CODE_INVALID (fora do formato ^[A-Z][A-Z0-9_]*$) real via PLAN confirmado.';

    -- 15.6 -- GENERATION_CODE_INVALID (item 1 do terceiro GATE 4, NO-GO
    -- residual): code fora do formato ^[A-Z][A-Z0-9_]*$ em generations[].
    -- Categoria irmã de REGION_CODE_INVALID (15.5) -- checagens distintas em
    -- 6104 (14/18 para regions, 15/18 para generations), ambas provadas aqui
    -- (uma não substitui a outra). ordinal_number/main_region_external_id
    -- mantidos válidos (999011/900201, iguais ao snapshot base) para que
    -- somente o campo code seja o gatilho da falha.
    SELECT * INTO v_open FROM public.open_pokemon_catalog_sourcing_run('DRY_RUN') LIMIT 1;
    IF v_open.outcome <> 'CLAIMED' THEN RAISE EXCEPTION 'FAIL 15.6.0: open_run não retornou CLAIMED para teste de generations[].code inválido (outcome=%).', v_open.outcome; END IF;
    PERFORM public.heartbeat_pokemon_catalog_sourcing_run(v_open.run_id);

    v_bad_snapshot := v_snapshot || jsonb_build_object(
        'generations', jsonb_build_array(jsonb_build_object('external_generation_id', '900202', 'code', 'generation_lowercase', 'canonical_name', 'Test Gen Good', 'ordinal_number', 999011, 'main_region_external_id', '900201', 'source_url', 'https://pokeapi.example.test/generation/900202', 'metadata', '{}'::JSONB))
    );
    SELECT * INTO v_plan FROM public.plan_pokemon_catalog_sourcing_run(v_open.run_id, v_bad_snapshot) LIMIT 1;
    IF v_plan.outcome <> 'VALIDATION_FAILURE' THEN RAISE EXCEPTION 'FAIL 15.6: PLAN com generations[].code fora do formato não retornou VALIDATION_FAILURE (retornou %).', v_plan.outcome; END IF;
    PERFORM 1 FROM public.pokemon_catalog_sourcing_run WHERE id = v_open.run_id AND status = 'FAILED' AND error_summary LIKE '%GENERATION_CODE_INVALID%';
    IF NOT FOUND THEN RAISE EXCEPTION 'FAIL 15.6b: run não foi marcado FAILED/GENERATION_CODE_INVALID.'; END IF;
    RAISE NOTICE 'OK: Seção 15.6 -- GENERATION_CODE_INVALID (fora do formato ^[A-Z][A-Z0-9_]*$) real via PLAN confirmado (REGION_CODE_INVALID de 15.5 preservado, não substituído).';

    EXECUTE 'RESET ROLE';
    RAISE NOTICE 'OK: Seção 15 -- 6 categorias novas/corrigidas do 6104 REVISION-02/REVISION-03 (itens 13-15 e 17-18 do header da Query, referentes a NON_POSITIVE_NUMBER, REGION_CODE_INVALID, GENERATION_CODE_INVALID, NATURAL_KEY_DUPLICATE_IN_SNAPSHOT, SOURCE_URL_INVALID, METADATA_INVALID) provadas via PLAN real.';

    -- =========================================================================
    -- SEÇÃO 16: Zero resíduo
    -- =========================================================================
    -- Não há limpeza manual necessária: o ROLLBACK final desfaz TUDO (runs,
    -- regions/generations/species/pokedex/positions/asset_source de teste).
    -- Diferente da v2.0, nenhuma renomeação de asset_source real precisa ser
    -- revertida -- a Fonte POKEAPI real nunca foi tocada em sua identidade
    -- (Fix 3). Esta seção apenas documenta a garantia estrutural.
    RAISE NOTICE 'OK: Seção 16 -- zero resíduo garantido estruturalmente pelo ROLLBACK final desta transação (não por limpeza manual). asset_source POKEAPI real jamais teve seu code alterado.';

    RAISE NOTICE '=== 6820 v2.3: TODAS AS 16 SEÇÕES EXECUTADAS DE VERDADE E PASS. SCRIPT NÃO FOI EXECUTADO EM PRODUÇÃO NESTA RODADA (GATE 3 STAGING) -- roda apenas quando o operador confirmar 6090-6110 aplicados. ===';
END;
$outer$;

ROLLBACK;
