/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2820 - Validate Catalog Card Set Metrics Views
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO E VALIDADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-08

Descrição...:
Validação estrutural e de segurança das duas views criadas pela Query
2123 (catalog_card_set_metrics, catalog_card_set_image_coverage) —
existência/security_invoker, GRANTs, e os três papéis exigidos por
Fabrício na revisão de plano (admin lê; authenticated não-admin não
lê; anon não acessa), mais conferência dos números contra o que já é
exibido hoje em produção.

Nota de correção (mesmo ciclo): a primeira versão do bloco 3-5 continha
um falso positivo de segurança — SET LOCAL ROLE anon estava dentro de
um bloco BEGIN...EXCEPTION. Um bloco com EXCEPTION cria uma
subtransação; ao capturar insufficient_privilege no primeiro teste, o
rollback do savepoint desfez também o SET LOCAL ROLE, e o segundo
teste rodou como authenticated (não anon), lendo com sucesso e
disparando a mensagem de falha por engano (diagnosticado
corretamente por revisão externa de Fabrício, não pelo autor deste
script). Diagnóstico estrutural independente confirmou anon_select =
false em card, card_set e nas duas views novas — não havia gap real.
Corrigido movendo SET LOCAL ROLE anon para fora dos blocos protegidos
por EXCEPTION, e fazendo os três papéis (admin, authenticated
não-admin, anon) se autoafirmarem por RAISE EXCEPTION em caso de
resultado errado — o bloco 3-5 só retorna "Success" se os três
passarem, sem depender de ler texto de RAISE NOTICE (que não aparece
na aba Results do SQL Editor usado por Fabrício).

Resultado confirmado por Fabrício: blocos 1, 2 e 3-5 sem erro; bloco
6 (listagem completa) e bloco 7 (cobertura MEE) conferidos
visualmente contra a produção.
================================================================
*/

-- ================================================================
-- 1. As duas views existem, com security_invoker = true
-- ================================================================
SELECT c.relname, c.relkind, c.reloptions
FROM pg_class c
WHERE c.relname IN ('catalog_card_set_metrics', 'catalog_card_set_image_coverage')
ORDER BY c.relname;
-- Confirmado: 2 linhas, relkind = 'v', reloptions = {security_invoker=true} nas duas.

-- ================================================================
-- 2. GRANT: authenticated tem SELECT, anon não tem
-- ================================================================
SELECT
    has_table_privilege('authenticated', 'public.catalog_card_set_metrics', 'SELECT') AS auth_metrics,
    has_table_privilege('anon', 'public.catalog_card_set_metrics', 'SELECT') AS anon_metrics,
    has_table_privilege('authenticated', 'public.catalog_card_set_image_coverage', 'SELECT') AS auth_coverage,
    has_table_privilege('anon', 'public.catalog_card_set_image_coverage', 'SELECT') AS anon_coverage;
-- Confirmado: auth_* = true, anon_* = false.

-- ================================================================
-- 3-5. Simulação dos três papéis nas duas views, dentro de uma
--      transação com ROLLBACK. Cada papel se autoafirma por RAISE
--      EXCEPTION em caso de resultado incorreto — "Success. No rows
--      returned" já é prova suficiente dos três testes.
-- ================================================================
BEGIN;

DO $$
DECLARE
    v_admin_id uuid;
    v_count_admin_metrics integer;
    v_count_admin_coverage integer;
    v_count_non_admin_metrics integer;
    v_count_non_admin_coverage integer;
BEGIN
    SELECT id INTO v_admin_id FROM public.admin_user LIMIT 1;
    IF v_admin_id IS NULL THEN
        RAISE EXCEPTION 'Nenhum admin_user encontrado — não é possível simular sessão de admin.';
    END IF;

    -- ---- Papel ADMIN ----
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);

    EXECUTE 'SELECT count(*) FROM public.catalog_card_set_metrics' INTO v_count_admin_metrics;
    EXECUTE 'SELECT count(*) FROM public.catalog_card_set_image_coverage' INTO v_count_admin_coverage;

    IF v_count_admin_metrics = 0 THEN
        RAISE EXCEPTION 'FALHA: admin não conseguiu ler catalog_card_set_metrics (0 linhas)';
    END IF;
    IF v_count_admin_coverage = 0 THEN
        RAISE EXCEPTION 'FALHA: admin não conseguiu ler catalog_card_set_image_coverage (0 linhas)';
    END IF;

    -- ---- Papel AUTHENTICATED NÃO-ADMIN ----
    PERFORM set_config('request.jwt.claim.sub', gen_random_uuid()::text, true);

    EXECUTE 'SELECT count(*) FROM public.catalog_card_set_metrics' INTO v_count_non_admin_metrics;
    EXECUTE 'SELECT count(*) FROM public.catalog_card_set_image_coverage' INTO v_count_non_admin_coverage;

    IF v_count_non_admin_metrics <> 0 THEN
        RAISE EXCEPTION 'FALHA DE SEGURANÇA: authenticated não-admin leu % linha(s) de catalog_card_set_metrics', v_count_non_admin_metrics;
    END IF;
    IF v_count_non_admin_coverage <> 0 THEN
        RAISE EXCEPTION 'FALHA DE SEGURANÇA: authenticated não-admin leu % linha(s) de catalog_card_set_image_coverage', v_count_non_admin_coverage;
    END IF;

    -- ---- Papel ANON (fora dos blocos EXCEPTION — ver nota de correção acima) ----
    EXECUTE 'SET LOCAL ROLE anon';

    BEGIN
        PERFORM count(*) FROM public.catalog_card_set_metrics;
        RAISE EXCEPTION 'FALHA DE SEGURANÇA: anon conseguiu ler catalog_card_set_metrics';
    EXCEPTION
        WHEN insufficient_privilege THEN NULL;
    END;

    BEGIN
        PERFORM count(*) FROM public.catalog_card_set_image_coverage;
        RAISE EXCEPTION 'FALHA DE SEGURANÇA: anon conseguiu ler catalog_card_set_image_coverage';
    EXCEPTION
        WHEN insufficient_privilege THEN NULL;
    END;

    EXECUTE 'RESET ROLE';

    RAISE NOTICE 'GATE DE SEGURANÇA 2123: aprovado (admin=%/%, não-admin=0/0, anon bloqueado nas duas)', v_count_admin_metrics, v_count_admin_coverage;
END;
$$;

ROLLBACK;
-- Confirmado: "Success. No rows returned" — os três papéis passaram nas duas views.

-- ================================================================
-- 6. Conferência dos números de catalog_card_set_metrics contra o que
--    já é exibido hoje em /catalogo e /catalogo/card-sets.
-- ================================================================
SELECT
    card_set_code,
    total_set_size,
    cards_cadastradas,
    cards_ativas,
    cards_inativas,
    cards_pendentes_cadastro
FROM public.catalog_card_set_metrics
ORDER BY card_set_code;
-- Confirmado: 37 Card Sets, cards_inativas = 0 em todos (nenhuma Card
-- desativada em produção ainda), único pendente real é SVP (218/226,
-- 8 pendentes). SV1 (258/252) e SV3 (230/227) têm cards_cadastradas >
-- total_set_size por secret rares além da numeração oficial —
-- comportamento esperado, não um bug da view.

-- ================================================================
-- 7. Cobertura de imagem — Card Set MEE.
-- ================================================================
SELECT
    card_set_code,
    language_code,
    cards_com_imagem
FROM public.catalog_card_set_image_coverage
WHERE card_set_code = 'MEE'
ORDER BY language_code;
-- Confirmado: MEE 8/8 em en e em pt-BR.
