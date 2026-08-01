/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2814 - Validate Catalog Import Functions
Versão......: 1.0
Status......: PROPOSTA (aguardando execução/confirmação de Fabrício)
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-01

Descrição...:
Validação estrutural e funcional de admin_start_catalog_import()
(Query 2080), admin_decide_catalog_import_row() (Query 2081) e
admin_confirm_catalog_import() (Query 2082) — Ciclo 1 do fluxo de
ingestão de Cards (ADR-024).

A parte funcional (bloco 4) roda inteiramente dentro de uma
transação com fixtures sintéticas (Game/Expansion/Card Set/Rarity/
Card Category próprios, com códigos ZZTEST) e termina em ROLLBACK —
não deixa nenhum resíduo no banco. É necessária porque, neste Ciclo
1, ainda não existe nenhum processador (TCGdex/PDF, Ciclos 2–4) que
alimente catalog_import_row pela UI real; simula manualmente o que
um processador produziria, para validar as três funções antes de
qualquer processador existir.

Correção pós-primeira tentativa (2026-08-01): a primeira versão
deste bloco chamava admin_start_catalog_import() diretamente no SQL
Editor e falhou com ADMIN_START_CATALOG_IMPORT_FORBIDDEN — is_admin()
lê auth.uid(), que só resolve com uma sessão JWT real; o SQL Editor
roda como postgres, sem esse contexto (mesma limitação já registrada
na Query 1860, "auth.uid() inexistente no SQL Editor... validação
funcional acontece a partir do app"). Diferente de 1860, este bloco
não pode esperar por uma tela real (ainda não existe nenhuma, é
exatamente essa a lacuna que a Query simula) — corrigido simulando a
sessão do primeiro administrador real encontrado via
set_config('request.jwt.claim.sub', ...) e
set_config('request.jwt.claims', ...), com is_local = true (escopo
só desta transação, desfeito automaticamente no ROLLBACK).
================================================================
*/

-- 1. Estrutura das três funções
SELECT p.proname, p.prosecdef, p.proconfig
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('admin_start_catalog_import', 'admin_decide_catalog_import_row', 'admin_confirm_catalog_import');

-- 2. Privilégios: authenticated tem EXECUTE, anon não
SELECT
    has_function_privilege('anon', 'public.admin_start_catalog_import(uuid, text, text, text)', 'EXECUTE') AS anon_start,
    has_function_privilege('authenticated', 'public.admin_start_catalog_import(uuid, text, text, text)', 'EXECUTE') AS auth_start,
    has_function_privilege('anon', 'public.admin_decide_catalog_import_row(uuid[], text, jsonb)', 'EXECUTE') AS anon_decide,
    has_function_privilege('authenticated', 'public.admin_decide_catalog_import_row(uuid[], text, jsonb)', 'EXECUTE') AS auth_decide,
    has_function_privilege('anon', 'public.admin_confirm_catalog_import(uuid, uuid[])', 'EXECUTE') AS anon_confirm,
    has_function_privilege('authenticated', 'public.admin_confirm_catalog_import(uuid, uuid[])', 'EXECUTE') AS auth_confirm;

-- 3. internal.write_card() continua inacessível a anon/authenticated (nenhuma das três
--    funções deve tê-lo exposto por engano)
SELECT
    has_function_privilege('anon', 'internal.write_card(text, uuid, uuid, uuid, uuid, text, integer, integer, text)', 'EXECUTE') AS anon_write_card,
    has_function_privilege('authenticated', 'internal.write_card(text, uuid, uuid, uuid, uuid, text, integer, integer, text)', 'EXECUTE') AS auth_write_card;

-- ================================================================
-- 4. Validação funcional (fixtures sintéticas, ROLLBACK ao final).
--    Execute como usuário com sessão de administrador (is_admin() = true) e
--    com privilégio para BYPASSRLS ou owner das tabelas, já que os INSERTs
--    de fixture abaixo não passam pelas funções administrativas.
-- ================================================================

BEGIN;

DO $$
DECLARE
    v_admin_id UUID;
    v_game_id UUID;
    v_expansion_id UUID;
    v_card_set_id UUID;
    v_rarity_id UUID;
    v_category_pokemon_id UUID;
    v_category_trainer_id UUID;
    v_suffix TEXT := UPPER(SUBSTRING(gen_random_uuid()::TEXT, 1, 8));
    v_release_order INTEGER := (FLOOR(RANDOM() * 900000) + 100000)::INTEGER;

    v_job_id UUID;
    v_job_id_dup UUID;
    v_row_new_id UUID;
    v_row_conflict_id UUID;
    v_row_skip_id UUID;
    v_existing_card_id UUID;

    v_dup_blocked BOOLEAN := FALSE;
    v_result RECORD;
    v_row_status TEXT;
BEGIN
    -- 4.0 Simula uma sessão JWT real de administrador (o SQL Editor roda como postgres,
    --     sem auth.uid() — is_admin() nunca resolveria true sem isto). Escopo local à
    --     transação (is_local = true): desfeito automaticamente no ROLLBACK final.
    SELECT id INTO v_admin_id FROM public.admin_user LIMIT 1;
    IF v_admin_id IS NULL THEN
        RAISE EXCEPTION 'QUERY 2814 FALHOU (4.0): nenhum administrador encontrado em admin_user para simular a sessão.';
    END IF;

    PERFORM set_config('request.jwt.claim.sub', v_admin_id::TEXT, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_id, 'role', 'authenticated')::TEXT, true);

    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'QUERY 2814 FALHOU (4.0): is_admin() ainda retornou false após simular a sessão do administrador %.', v_admin_id;
    END IF;

    RAISE NOTICE '4.0 OK: sessão simulada como administrador %, is_admin() = true', v_admin_id;

    -- 4.1 Fixtures: um Game real (o primeiro existente) + Expansion/Card Set/Rarity/
    --     Card Category sintéticos, isolados por código ZZTEST + sufixo aleatório.
    SELECT id INTO v_game_id FROM public.game LIMIT 1;
    IF v_game_id IS NULL THEN
        RAISE EXCEPTION 'QUERY 2814 FALHOU: nenhum Game encontrado para montar a fixture de teste.';
    END IF;

    INSERT INTO public.expansion (game_id, code, name, release_order)
        VALUES (v_game_id, 'ZZTEST_' || v_suffix, 'Expansion de Teste 2814', v_release_order)
        RETURNING id INTO v_expansion_id;

    INSERT INTO public.card_set (expansion_id, code, name, set_type, release_order, base_set_size, total_set_size)
        VALUES (v_expansion_id, 'ZZT_' || v_suffix, 'Card Set de Teste 2814', 'REGULAR', 1, 10, 10)
        RETURNING id INTO v_card_set_id;

    INSERT INTO public.rarity (game_id, code, name, symbol_code, display_order)
        VALUES (v_game_id, 'ZZTEST_' || v_suffix, 'Raridade de Teste', 'BLACK_CIRCLE', v_release_order)
        RETURNING id INTO v_rarity_id;

    INSERT INTO public.card_category (game_id, code, name, display_order)
        VALUES (v_game_id, 'ZZTEST_POKEMON_' || v_suffix, 'Categoria Pokémon de Teste', v_release_order)
        RETURNING id INTO v_category_pokemon_id;

    INSERT INTO public.card_category (game_id, code, name, display_order)
        VALUES (v_game_id, 'ZZTEST_TRAINER_' || v_suffix, 'Categoria Treinador de Teste', v_release_order + 1)
        RETURNING id INTO v_category_trainer_id;

    -- Uma Card já existente no Card Set, para gerar o cenário MATCHED/CONFLICT
    INSERT INTO public.card (card_set_id, rarity_id, category_id, collector_number, collector_total, collector_order, name)
        VALUES (v_card_set_id, v_rarity_id, v_category_pokemon_id, '001', 10, 1, 'Nome Antigo de Teste')
        RETURNING id INTO v_existing_card_id;

    RAISE NOTICE '4.1 OK: fixtures criadas (game=%, card_set=%, card existente=%)', v_game_id, v_card_set_id, v_existing_card_id;

    -- 4.2 admin_start_catalog_import: abre o job
    v_job_id := public.admin_start_catalog_import(v_card_set_id, 'TCGDEX', NULL, 'ZZTEST-EXTERNAL-' || v_suffix);

    IF v_job_id IS NULL THEN
        RAISE EXCEPTION 'QUERY 2814 FALHOU (4.2): admin_start_catalog_import não retornou id.';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.catalog_import_job WHERE id = v_job_id AND status = 'RECEIVED'
    ) THEN
        RAISE EXCEPTION 'QUERY 2814 FALHOU (4.2): job não está em RECEIVED após admin_start_catalog_import.';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.catalog_admin_action_log
        WHERE entity_id = v_job_id AND action = 'CATALOG_IMPORT_JOB'
    ) THEN
        RAISE EXCEPTION 'QUERY 2814 FALHOU (4.2): auditoria CATALOG_IMPORT_JOB não foi gravada.';
    END IF;

    RAISE NOTICE '4.2 OK: job % aberto em RECEIVED, auditoria gravada', v_job_id;

    -- 4.3 Fingerprint ativo duplicado deve ser bloqueado
    BEGIN
        v_job_id_dup := public.admin_start_catalog_import(v_card_set_id, 'TCGDEX', NULL, 'ZZTEST-EXTERNAL-' || v_suffix);
    EXCEPTION WHEN OTHERS THEN
        v_dup_blocked := TRUE;
    END;

    IF NOT v_dup_blocked THEN
        RAISE EXCEPTION 'QUERY 2814 FALHOU (4.3): uma segunda importação ativa com o mesmo fingerprint deveria ter sido bloqueada.';
    END IF;

    RAISE NOTICE '4.3 OK: fingerprint ativo duplicado bloqueado corretamente';

    -- 4.4 Simula o processador: popula 3 linhas e leva o job para STAGED
    --     (fora do escopo desta Query — normalmente feito pela Edge Function do Ciclo 2/4)
    INSERT INTO public.catalog_import_row (job_id, raw_data, normalized_data, validation_status, match_status)
        VALUES (
            v_job_id, '{"collector_number":"002"}'::JSONB,
            jsonb_build_object(
                'collector_number', '002', 'collector_total', 10, 'collector_order', 2, 'name', 'Carta Nova de Teste',
                'rarity_id', v_rarity_id, 'category_id', v_category_pokemon_id, 'category', 'POKEMON',
                'category_source', 'POKEMON_MATCH', 'category_confidence', 'HIGH'
            ),
            'VALID', 'NEW'
        )
        RETURNING id INTO v_row_new_id;

    INSERT INTO public.catalog_import_row (job_id, raw_data, normalized_data, validation_status, match_status)
        VALUES (
            v_job_id, '{"collector_number":"001"}'::JSONB,
            jsonb_build_object(
                'collector_number', '001', 'collector_total', 10, 'collector_order', 1, 'name', 'Nome Corrigido de Teste',
                'rarity_id', v_rarity_id, 'category_id', v_category_pokemon_id, 'category', 'POKEMON',
                'category_source', 'API', 'category_confidence', 'HIGH'
            ),
            'VALID', 'CONFLICT'
        )
        RETURNING id INTO v_row_conflict_id;

    INSERT INTO public.catalog_import_row (job_id, raw_data, normalized_data, validation_status, match_status)
        VALUES (
            v_job_id, '{"collector_number":"003"}'::JSONB,
            jsonb_build_object(
                'collector_number', '003', 'collector_total', 10, 'collector_order', 3, 'name', 'Carta a Pular',
                'rarity_id', v_rarity_id, 'category_id', v_category_trainer_id, 'category', 'TRAINER',
                'category_source', 'TRAINER_FALLBACK', 'category_confidence', 'LOW'
            ),
            'NEEDS_REVIEW', 'NEW'
        )
        RETURNING id INTO v_row_skip_id;

    UPDATE public.catalog_import_job SET status = 'STAGED' WHERE id = v_job_id;

    RAISE NOTICE '4.4 OK: 3 linhas de staging simuladas (NEW=%, CONFLICT=%, a pular=%), job em STAGED', v_row_new_id, v_row_conflict_id, v_row_skip_id;

    -- 4.5 admin_decide_catalog_import_row: aprova NEW e CONFLICT, pula a terceira
    PERFORM public.admin_decide_catalog_import_row(ARRAY[v_row_new_id, v_row_conflict_id], 'APPROVED');
    PERFORM public.admin_decide_catalog_import_row(ARRAY[v_row_skip_id], 'SKIPPED');

    SELECT decision_status INTO v_row_status FROM public.catalog_import_row WHERE id = v_row_new_id;
    IF v_row_status <> 'APPROVED' THEN
        RAISE EXCEPTION 'QUERY 2814 FALHOU (4.5): decision_status da linha NEW deveria ser APPROVED (obtido: %).', v_row_status;
    END IF;

    RAISE NOTICE '4.5 OK: decisões gravadas (2 aprovadas, 1 pulada)';

    -- 4.6 admin_confirm_catalog_import: processa as 3 linhas
    SELECT * INTO v_result FROM public.admin_confirm_catalog_import(v_job_id);

    IF v_result.inserted_count <> 1 THEN
        RAISE EXCEPTION 'QUERY 2814 FALHOU (4.6): inserted_count deveria ser 1 (obtido: %).', v_result.inserted_count;
    END IF;

    IF v_result.updated_count <> 1 THEN
        RAISE EXCEPTION 'QUERY 2814 FALHOU (4.6): updated_count deveria ser 1 (obtido: %).', v_result.updated_count;
    END IF;

    IF v_result.unchanged_count <> 1 THEN
        RAISE EXCEPTION 'QUERY 2814 FALHOU (4.6): unchanged_count (linha pulada) deveria ser 1 (obtido: %).', v_result.unchanged_count;
    END IF;

    IF v_result.job_status <> 'COMPLETED' THEN
        RAISE EXCEPTION 'QUERY 2814 FALHOU (4.6): job_status deveria ser COMPLETED (obtido: %).', v_result.job_status;
    END IF;

    -- Confere que a Card existente foi realmente atualizada (nome novo) e que a nova Card existe
    IF NOT EXISTS (
        SELECT 1 FROM public.card WHERE id = v_existing_card_id AND name = 'Nome Corrigido de Teste'
    ) THEN
        RAISE EXCEPTION 'QUERY 2814 FALHOU (4.6): a Card existente não foi atualizada pelo caminho CONFLICT aprovado.';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.card WHERE card_set_id = v_card_set_id AND collector_number = '002' AND name = 'Carta Nova de Teste'
    ) THEN
        RAISE EXCEPTION 'QUERY 2814 FALHOU (4.6): a Card nova não foi criada pelo caminho NEW aprovado.';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.catalog_admin_action_log WHERE entity_id = v_job_id AND action = 'CATALOG_IMPORT_CONFIRMED'
    ) THEN
        RAISE EXCEPTION 'QUERY 2814 FALHOU (4.6): auditoria CATALOG_IMPORT_CONFIRMED não foi gravada.';
    END IF;

    RAISE NOTICE '4.6 OK: confirmação processou 1 INSERTED / 1 UPDATED / 1 UNCHANGED, job COMPLETED, auditoria agregada gravada';

    -- 4.7 Reexecutar a confirmação no mesmo job (idempotência): nada mais deveria acontecer
    BEGIN
        PERFORM public.admin_confirm_catalog_import(v_job_id);
        RAISE EXCEPTION 'QUERY 2814 FALHOU (4.7): confirmar um job já COMPLETED deveria ter sido rejeitado.';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE 'QUERY 2814 FALHOU%' THEN
            RAISE;
        END IF;
        RAISE NOTICE '4.7 OK: reconfirmar um job já COMPLETED foi corretamente rejeitado (%).', SQLERRM;
    END;

    RAISE NOTICE 'QUERY 2814 CONCLUÍDA: TODOS OS CENÁRIOS FUNCIONAIS PASSARAM (ROLLBACK a seguir, nenhum dado de teste persiste)';
END;
$$;

ROLLBACK;

-- ================================================================
-- Validação estrutural (blocos 1–3): PENDENTE — aguardando execução
-- das Queries 2080/2081/2082 por Fabrício no Supabase.
--
-- Validação funcional (bloco 4): PENDENTE — aguardando execução do
-- script acima (autocontido, termina em ROLLBACK). Cobre o caminho
-- feliz completo com dados sintéticos: abertura de job, bloqueio de
-- fingerprint duplicado, decisão de linhas, confirmação com os três
-- desfechos de persistência (INSERTED/UPDATED/UNCHANGED) e bloqueio
-- de reconfirmação de job já concluído.
--
-- Cenário de sessão não-administrativa (is_admin() = false): não
-- exercitado aqui — inalcançável por um usuário comum através da UI
-- normal, mesmo critério já aplicado a admin_delete_expansion() e
-- às demais funções administrativas deste projeto (fica como
-- cobertura teórica, garantida pela primeira verificação de cada
-- função).
-- ================================================================
