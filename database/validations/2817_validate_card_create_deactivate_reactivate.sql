/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2817 - Validate Card Create/Deactivate/Reactivate
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO E VALIDADO FUNCIONALMENTE
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-07

Descrição...:
Validação estrutural e funcional de admin_create_card() (Query
2115), admin_deactivate_card() (Query 2116) e admin_reactivate_card()
(Query 2117) — fecha o subciclo Card (criação/desativação/
reativação) do ADR-023.

A parte funcional (bloco 3) roda inteiramente dentro de uma
transação com fixtures sintéticas (dois Games — um real, um
sintético para os cenários de Game divergente — mais Expansion/Card
Set/Rarity/Card Category/Card Variant Type próprios, códigos
ZZTEST) e termina em ROLLBACK — não deixa nenhum resíduo no banco.
Mesma técnica de simulação de sessão administrativa já usada na
Query 2814 (set_config de request.jwt.claim.sub/claims, escopo
local à transação).

14 cenários cobertos: estrutura das 3 funções; privilégios
(authenticated=true, anon=false) das 3 funções; criação válida com
auditoria única (CARD_CREATED); collector_number duplicado
bloqueado; collector_order duplicado bloqueado; Rarity de outro
Game bloqueada; Category de outro Game bloqueada; desativação válida
com auditoria única (CARD_DEACTIVATED); desativar já inativa
bloqueado; preservação de card_variant após desativação (nenhuma
cascata — admin_deactivate_card() só toca public.card); filtro
operacional (is_active = true) oculta a Card inativa; reativação
válida com auditoria única (CARD_REACTIVATED); reativar já ativa
bloqueado; filtro operacional volta a mostrar a Card reativada;
auditoria total = exatamente 3 linhas por Card, uma por operação.
================================================================
*/

-- 1. Estrutura das três funções
SELECT p.proname, p.prosecdef, p.proconfig
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('admin_create_card', 'admin_deactivate_card', 'admin_reactivate_card');

-- 2. Privilégios: authenticated tem EXECUTE, anon/PUBLIC não
SELECT
    has_function_privilege('authenticated', 'public.admin_create_card(uuid,text,integer,integer,uuid,uuid,text)', 'EXECUTE') AS auth_create,
    has_function_privilege('anon', 'public.admin_create_card(uuid,text,integer,integer,uuid,uuid,text)', 'EXECUTE') AS anon_create,
    has_function_privilege('authenticated', 'public.admin_deactivate_card(uuid)', 'EXECUTE') AS auth_deactivate,
    has_function_privilege('anon', 'public.admin_deactivate_card(uuid)', 'EXECUTE') AS anon_deactivate,
    has_function_privilege('authenticated', 'public.admin_reactivate_card(uuid)', 'EXECUTE') AS auth_reactivate,
    has_function_privilege('anon', 'public.admin_reactivate_card(uuid)', 'EXECUTE') AS anon_reactivate;

-- ================================================================
-- 3. Validação funcional (fixtures sintéticas, ROLLBACK ao final).
-- ================================================================

BEGIN;

DO $$
DECLARE
    v_admin_id UUID;
    v_game_id UUID;
    v_other_game_id UUID;
    v_expansion_id UUID;
    v_card_set_id UUID;
    v_rarity_id UUID;
    v_category_id UUID;
    v_rarity_other_id UUID;
    v_category_other_id UUID;
    v_variant_type_id UUID;
    v_suffix TEXT := UPPER(SUBSTRING(gen_random_uuid()::TEXT, 1, 8));
    v_order_base INTEGER := (FLOOR(RANDOM() * 900000) + 100000)::INTEGER;

    v_card_id UUID;
    v_variant_id UUID;
    v_blocked BOOLEAN;
    v_audit_count INTEGER;
BEGIN
    -- 3.0 Simula sessão de administrador (mesma técnica da Query 2814)
    SELECT id INTO v_admin_id FROM public.admin_user LIMIT 1;
    IF v_admin_id IS NULL THEN
        RAISE EXCEPTION 'QUERY 2817 FALHOU (3.0): nenhum administrador encontrado em admin_user.';
    END IF;

    PERFORM set_config('request.jwt.claim.sub', v_admin_id::TEXT, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_id, 'role', 'authenticated')::TEXT, true);

    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'QUERY 2817 FALHOU (3.0): is_admin() retornou false após simular a sessão.';
    END IF;

    RAISE NOTICE '3.0 OK: sessão simulada como administrador %', v_admin_id;

    -- 3.1 Fixtures
    SELECT id INTO v_game_id FROM public.game LIMIT 1;
    IF v_game_id IS NULL THEN
        RAISE EXCEPTION 'QUERY 2817 FALHOU (3.1): nenhum Game encontrado.';
    END IF;

    INSERT INTO public.game (code, name)
        VALUES ('ZZTEST_' || v_suffix, 'Game de Teste 2817')
        RETURNING id INTO v_other_game_id;

    INSERT INTO public.expansion (game_id, code, name, release_order)
        VALUES (v_game_id, 'ZZTEST_' || v_suffix, 'Expansion de Teste 2817', v_order_base)
        RETURNING id INTO v_expansion_id;

    INSERT INTO public.card_set (expansion_id, code, name, set_type, release_order, base_set_size, total_set_size)
        VALUES (v_expansion_id, 'ZZT_' || v_suffix, 'Card Set de Teste 2817', 'REGULAR', 1, 10, 10)
        RETURNING id INTO v_card_set_id;

    INSERT INTO public.rarity (game_id, code, name, symbol_code, display_order)
        VALUES (v_game_id, 'ZZTEST_' || v_suffix, 'Raridade de Teste', 'BLACK_CIRCLE', v_order_base)
        RETURNING id INTO v_rarity_id;

    INSERT INTO public.card_category (game_id, code, name, display_order)
        VALUES (v_game_id, 'ZZTEST_' || v_suffix, 'Categoria de Teste', v_order_base)
        RETURNING id INTO v_category_id;

    INSERT INTO public.rarity (game_id, code, name, symbol_code, display_order)
        VALUES (v_other_game_id, 'ZZTEST_' || v_suffix, 'Raridade de Outro Game', 'BLACK_CIRCLE', 1)
        RETURNING id INTO v_rarity_other_id;

    INSERT INTO public.card_category (game_id, code, name, display_order)
        VALUES (v_other_game_id, 'ZZTEST_' || v_suffix, 'Categoria de Outro Game', 1)
        RETURNING id INTO v_category_other_id;

    INSERT INTO public.card_variant_type (game_id, code, name, display_order)
        VALUES (v_game_id, 'ZZTEST_' || v_suffix, 'Variante de Teste', v_order_base)
        RETURNING id INTO v_variant_type_id;

    RAISE NOTICE '3.1 OK: fixtures criadas (game=%, other_game=%, card_set=%)', v_game_id, v_other_game_id, v_card_set_id;

    -- 3.2 Criação válida
    v_card_id := public.admin_create_card(v_card_set_id, '001', 10, 1, v_rarity_id, v_category_id, 'Carta de Teste 2817');

    IF NOT EXISTS (SELECT 1 FROM public.card WHERE id = v_card_id AND is_active = true) THEN
        RAISE EXCEPTION 'QUERY 2817 FALHOU (3.2): Card criada não encontrada ou não está ativa.';
    END IF;

    SELECT COUNT(*) INTO v_audit_count FROM public.catalog_admin_action_log WHERE entity_id = v_card_id AND action = 'CARD_CREATED';
    IF v_audit_count <> 1 THEN
        RAISE EXCEPTION 'QUERY 2817 FALHOU (3.2): esperava 1 linha CARD_CREATED, encontrado %.', v_audit_count;
    END IF;

    RAISE NOTICE '3.2 OK: criação válida, Card %, auditoria única confirmada', v_card_id;

    -- 3.3 collector_number duplicado
    v_blocked := FALSE;
    BEGIN
        PERFORM public.admin_create_card(v_card_set_id, '001', 10, 2, v_rarity_id, v_category_id, 'Duplicata de Número');
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE 'ADMIN_CREATE_CARD_DUPLICATE_COLLECTOR_NUMBER%' THEN
            v_blocked := TRUE;
        ELSE
            RAISE;
        END IF;
    END;
    IF NOT v_blocked THEN
        RAISE EXCEPTION 'QUERY 2817 FALHOU (3.3): collector_number duplicado deveria ter sido bloqueado.';
    END IF;
    RAISE NOTICE '3.3 OK: collector_number duplicado bloqueado corretamente';

    -- 3.4 collector_order duplicado
    v_blocked := FALSE;
    BEGIN
        PERFORM public.admin_create_card(v_card_set_id, '002', 10, 1, v_rarity_id, v_category_id, 'Duplicata de Ordem');
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE 'ADMIN_CREATE_CARD_DUPLICATE_COLLECTOR_ORDER%' THEN
            v_blocked := TRUE;
        ELSE
            RAISE;
        END IF;
    END;
    IF NOT v_blocked THEN
        RAISE EXCEPTION 'QUERY 2817 FALHOU (3.4): collector_order duplicado deveria ter sido bloqueado.';
    END IF;
    RAISE NOTICE '3.4 OK: collector_order duplicado bloqueado corretamente';

    -- 3.5 Rarity de outro Game
    v_blocked := FALSE;
    BEGIN
        PERFORM public.admin_create_card(v_card_set_id, '002', 10, 2, v_rarity_other_id, v_category_id, 'Rarity de Outro Game');
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE 'ADMIN_CREATE_CARD_RARITY_MISMATCH%' THEN
            v_blocked := TRUE;
        ELSE
            RAISE;
        END IF;
    END;
    IF NOT v_blocked THEN
        RAISE EXCEPTION 'QUERY 2817 FALHOU (3.5): Rarity de outro Game deveria ter sido bloqueada.';
    END IF;
    RAISE NOTICE '3.5 OK: Rarity de outro Game bloqueada corretamente';

    -- 3.6 Category de outro Game
    v_blocked := FALSE;
    BEGIN
        PERFORM public.admin_create_card(v_card_set_id, '002', 10, 2, v_rarity_id, v_category_other_id, 'Category de Outro Game');
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE 'ADMIN_CREATE_CARD_CATEGORY_MISMATCH%' THEN
            v_blocked := TRUE;
        ELSE
            RAISE;
        END IF;
    END;
    IF NOT v_blocked THEN
        RAISE EXCEPTION 'QUERY 2817 FALHOU (3.6): Category de outro Game deveria ter sido bloqueada.';
    END IF;
    RAISE NOTICE '3.6 OK: Category de outro Game bloqueada corretamente';

    -- 3.7 Fixture de dependente (card_variant) para o teste de preservação
    INSERT INTO public.card_variant (card_id, variant_type_id, variant_order, is_default)
        VALUES (v_card_id, v_variant_type_id, 1, true)
        RETURNING id INTO v_variant_id;

    RAISE NOTICE '3.7 OK: card_variant de fixture criado (%)', v_variant_id;

    -- 3.8 Desativação válida
    PERFORM public.admin_deactivate_card(v_card_id);

    IF EXISTS (SELECT 1 FROM public.card WHERE id = v_card_id AND is_active = true) THEN
        RAISE EXCEPTION 'QUERY 2817 FALHOU (3.8): Card deveria estar inativa após admin_deactivate_card().';
    END IF;

    SELECT COUNT(*) INTO v_audit_count FROM public.catalog_admin_action_log WHERE entity_id = v_card_id AND action = 'CARD_DEACTIVATED';
    IF v_audit_count <> 1 THEN
        RAISE EXCEPTION 'QUERY 2817 FALHOU (3.8): esperava 1 linha CARD_DEACTIVATED, encontrado %.', v_audit_count;
    END IF;

    RAISE NOTICE '3.8 OK: desativação válida, auditoria única confirmada';

    -- 3.9 Desativar já inativa
    v_blocked := FALSE;
    BEGIN
        PERFORM public.admin_deactivate_card(v_card_id);
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE 'ADMIN_DEACTIVATE_CARD_ALREADY_INACTIVE%' THEN
            v_blocked := TRUE;
        ELSE
            RAISE;
        END IF;
    END;
    IF NOT v_blocked THEN
        RAISE EXCEPTION 'QUERY 2817 FALHOU (3.9): desativar uma Card já inativa deveria ter sido bloqueado.';
    END IF;
    RAISE NOTICE '3.9 OK: desativar já inativa bloqueado corretamente';

    -- 3.10 Preservação: card_variant intacto após desativação
    IF NOT EXISTS (SELECT 1 FROM public.card_variant WHERE id = v_variant_id AND card_id = v_card_id) THEN
        RAISE EXCEPTION 'QUERY 2817 FALHOU (3.10): card_variant de fixture deveria continuar intacto após a desativação.';
    END IF;
    RAISE NOTICE '3.10 OK: card_variant preservado após desativação (nenhuma cascata — admin_deactivate_card() só toca public.card)';

    -- 3.11 Galeria normal (is_active = true) oculta a Card inativa
    IF EXISTS (SELECT 1 FROM public.card WHERE id = v_card_id AND is_active = true) THEN
        RAISE EXCEPTION 'QUERY 2817 FALHOU (3.11): a Card inativa não deveria aparecer sob o filtro is_active = true usado por getCartasCompletas().';
    END IF;
    RAISE NOTICE '3.11 OK: filtro operacional (is_active = true) oculta a Card inativa corretamente';

    -- 3.12 Reativação válida
    PERFORM public.admin_reactivate_card(v_card_id);

    IF NOT EXISTS (SELECT 1 FROM public.card WHERE id = v_card_id AND is_active = true) THEN
        RAISE EXCEPTION 'QUERY 2817 FALHOU (3.12): Card deveria estar ativa após admin_reactivate_card().';
    END IF;

    SELECT COUNT(*) INTO v_audit_count FROM public.catalog_admin_action_log WHERE entity_id = v_card_id AND action = 'CARD_REACTIVATED';
    IF v_audit_count <> 1 THEN
        RAISE EXCEPTION 'QUERY 2817 FALHOU (3.12): esperava 1 linha CARD_REACTIVATED, encontrado %.', v_audit_count;
    END IF;

    RAISE NOTICE '3.12 OK: reativação válida, auditoria única confirmada';

    -- 3.13 Reativar já ativa
    v_blocked := FALSE;
    BEGIN
        PERFORM public.admin_reactivate_card(v_card_id);
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE 'ADMIN_REACTIVATE_CARD_ALREADY_ACTIVE%' THEN
            v_blocked := TRUE;
        ELSE
            RAISE;
        END IF;
    END;
    IF NOT v_blocked THEN
        RAISE EXCEPTION 'QUERY 2817 FALHOU (3.13): reativar uma Card já ativa deveria ter sido bloqueado.';
    END IF;
    RAISE NOTICE '3.13 OK: reativar já ativa bloqueado corretamente';

    -- 3.14 Galeria normal volta a mostrar a Card reativada
    IF NOT EXISTS (SELECT 1 FROM public.card WHERE id = v_card_id AND is_active = true) THEN
        RAISE EXCEPTION 'QUERY 2817 FALHOU (3.14): a Card reativada deveria voltar a aparecer sob is_active = true.';
    END IF;
    RAISE NOTICE '3.14 OK: Card reativada volta a aparecer no filtro operacional';

    -- 3.15 Auditoria total: exatamente 3 linhas para esta Card (CREATED/DEACTIVATED/REACTIVATED), nenhuma duplicada
    SELECT COUNT(*) INTO v_audit_count FROM public.catalog_admin_action_log WHERE entity_id = v_card_id;
    IF v_audit_count <> 3 THEN
        RAISE EXCEPTION 'QUERY 2817 FALHOU (3.15): esperava exatamente 3 linhas de auditoria para a Card (1 por operação), encontrado %.', v_audit_count;
    END IF;
    RAISE NOTICE '3.15 OK: auditoria total = 3 linhas, uma por operação, nenhuma duplicada';

    RAISE NOTICE 'QUERY 2817 CONCLUÍDA: TODOS OS 14 CENÁRIOS PASSARAM (ROLLBACK a seguir, nenhum dado de teste persiste)';
END;
$$;

ROLLBACK;

-- ================================================================
-- Confirmado executado e validado funcionalmente (2026-08-07):
-- bloco 1 (estrutura) e bloco 2 (privilégios) confirmados via
-- captura de tela dos resultados; bloco 3 (funcional, 14 cenários)
-- confirmado por Fabrício — "Success. No rows returned", sem
-- nenhum erro `QUERY 2817 FALHOU` interrompendo a execução do
-- BEGIN/DO/ROLLBACK. Nenhum dado ZZTEST residual no banco.
-- ================================================================
