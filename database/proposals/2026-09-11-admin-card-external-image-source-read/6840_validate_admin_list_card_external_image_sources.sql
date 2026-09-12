/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 6840 - Validate admin_list_card_external_image_sources()
Versão......: 1.2
Status......: EXECUTADA — PASS
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-11

Descrição...:
Validação da RPC 6127. Duas seções:

  Seção 1 — ESTRUTURAL/SEGURANÇA (read-only, fora de transação).
            5 checagens: SECURITY DEFINER, search_path = '', ACL da
            function, que a fronteira de segurança de
            card_external_reference NÃO foi afrouxada, e que o cap
            não voltou a ser medido por array_length.

  Seção 2 — FUNCIONAL (BEGIN/ROLLBACK, zero resíduo).
            18 casos, incluindo admin allowed / non-admin denied
            e o vetor de bypass multidimensional.

Revisão 1.1 (HARDENING-CORRECTION-01): Casos 17 e 18 novos —
array multidimensional; Casos 13/14 passaram a afirmar a forma da
fixture (ndims/cardinality) em vez de assumi-la; checagem estática
1.5 impede a volta de array_length.

Revisão 1.2 (VALIDATION-HARNESS-CORRECTION-02): APENAS o bloco de
fixtures (2.1). Quatro colunas obrigatórias estavam ausentes ou
erradas nos INSERTs sintéticos; nenhum caso de teste, nenhuma
asserção e nenhuma checagem estrutural mudou. A RPC (6127) não foi
tocada.

Pré-requisitos:
- 6127 aplicada.
- Executar como postgres/owner (o SQL Editor do Supabase já é).
  A Seção 2 simula a sessão JWT de admin e, nos casos negativos,
  troca para a role `authenticated` sem claim de admin.

Critério de PASS:
Nenhum RAISE EXCEPTION. Cada caso emite RAISE NOTICE '<caso> OK'.
A Seção 2 termina em ROLLBACK — nada é persistido.
================================================================
*/

-- ================================================================
-- Seção 1 — Estrutural e de segurança (read-only)
-- ================================================================

-- 1.1 A function existe com a assinatura exata, é SECURITY DEFINER,
--     STABLE (não VOLATILE: não escreve) e tem search_path = ''.
DO $$
DECLARE
    v_secdef BOOLEAN;
    v_volatile "char";
    v_config TEXT[];
BEGIN
    SELECT p.prosecdef, p.provolatile, p.proconfig
      INTO v_secdef, v_volatile, v_config
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.proname = 'admin_list_card_external_image_sources'
       AND pg_get_function_identity_arguments(p.oid) = 'p_card_ids uuid[], p_language_code text, p_asset_source_code text';

    IF v_secdef IS NULL THEN
        RAISE EXCEPTION 'QUERY 6840 FALHOU (1.1): function não encontrada com a assinatura esperada.';
    END IF;
    IF v_secdef IS NOT TRUE THEN
        RAISE EXCEPTION 'QUERY 6840 FALHOU (1.1): function não é SECURITY DEFINER.';
    END IF;
    IF v_volatile <> 's' THEN
        RAISE EXCEPTION 'QUERY 6840 FALHOU (1.1): esperado STABLE, encontrado volatility %.', v_volatile;
    END IF;
    IF v_config IS NULL OR NOT ('search_path=""' = ANY (v_config)) THEN
        RAISE EXCEPTION 'QUERY 6840 FALHOU (1.1): search_path não está fixado em '''' (proconfig = %).', v_config;
    END IF;

    RAISE NOTICE '1.1 OK: SECURITY DEFINER + STABLE + search_path = ''''';
END;
$$;

-- 1.2 ACL da function: authenticated TEM EXECUTE; PUBLIC e anon NÃO.
DO $$
DECLARE
    v_sig TEXT := 'public.admin_list_card_external_image_sources(uuid[], text, text)';
BEGIN
    IF NOT has_function_privilege('authenticated', v_sig, 'EXECUTE') THEN
        RAISE EXCEPTION 'QUERY 6840 FALHOU (1.2): authenticated não tem EXECUTE.';
    END IF;
    IF has_function_privilege('anon', v_sig, 'EXECUTE') THEN
        RAISE EXCEPTION 'QUERY 6840 FALHOU (1.2): anon NÃO deveria ter EXECUTE.';
    END IF;
    RAISE NOTICE '1.2 OK: EXECUTE apenas para authenticated (anon negado)';
END;
$$;

-- 1.3 REGRESSÃO DE FRONTEIRA — a tabela continua fechada.
--     Este é o caso que justifica a RPC existir. Se alguém "resolver"
--     o problema concedendo SELECT direto, esta checagem quebra.
DO $$
BEGIN
    IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.card_external_reference'::regclass) THEN
        RAISE EXCEPTION 'QUERY 6840 FALHOU (1.3): RLS foi desligado em card_external_reference.';
    END IF;

    IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'card_external_reference') THEN
        RAISE EXCEPTION 'QUERY 6840 FALHOU (1.3): surgiu policy em card_external_reference; a RPC deve ser a única via.';
    END IF;

    IF has_table_privilege('authenticated', 'public.card_external_reference', 'SELECT') THEN
        RAISE EXCEPTION 'QUERY 6840 FALHOU (1.3): authenticated ganhou SELECT direto na tabela.';
    END IF;
    IF has_table_privilege('anon', 'public.card_external_reference', 'SELECT') THEN
        RAISE EXCEPTION 'QUERY 6840 FALHOU (1.3): anon ganhou SELECT direto na tabela.';
    END IF;

    RAISE NOTICE '1.3 OK: card_external_reference segue RLS=true, sem policy, sem SELECT para authenticated/anon';
END;
$$;

-- 1.4 A function NÃO expõe external_set_id (garantia de desenho:
--     impede reconstrução de path de CDN a partir do código do Set).
DO $$
DECLARE
    v_src TEXT;
    v_cols TEXT;
BEGIN
    SELECT p.prosrc, pg_get_function_result(p.oid)
      INTO v_src, v_cols
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = 'admin_list_card_external_image_sources';

    IF v_cols ILIKE '%external_set_id%' THEN
        RAISE EXCEPTION 'QUERY 6840 FALHOU (1.4): external_set_id apareceu no RETURNS TABLE.';
    END IF;
    IF v_src ILIKE '%external_set_id%' THEN
        RAISE EXCEPTION 'QUERY 6840 FALHOU (1.4): external_set_id é referenciado no corpo da function.';
    END IF;
    IF v_src ~* '\m(insert|update|delete|truncate)\M' THEN
        RAISE EXCEPTION 'QUERY 6840 FALHOU (1.4): corpo da function contém DML.';
    END IF;

    RAISE NOTICE '1.4 OK: sem external_set_id e sem DML no corpo';
END;
$$;

-- 1.5 HARDENING-CORRECTION-01 — o cap NÃO pode voltar a ser medido por
--     array_length(). Prova estática no corpo da function.
DO $$
DECLARE
    v_src TEXT;
BEGIN
    SELECT p.prosrc INTO v_src
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = 'admin_list_card_external_image_sources';

    IF v_src ILIKE '%array_length(p_card_ids%' THEN
        RAISE EXCEPTION 'QUERY 6840 FALHOU (1.5): o cap voltou a usar array_length(p_card_ids, ...) — contornável por UUID[][].';
    END IF;
    IF v_src NOT ILIKE '%cardinality(p_card_ids)%' THEN
        RAISE EXCEPTION 'QUERY 6840 FALHOU (1.5): o corpo não mede o volume com cardinality(p_card_ids).';
    END IF;
    IF v_src NOT ILIKE '%array_ndims(p_card_ids)%' THEN
        RAISE EXCEPTION 'QUERY 6840 FALHOU (1.5): o corpo não valida array_ndims(p_card_ids).';
    END IF;

    RAISE NOTICE '1.5 OK: cap por cardinality + guard de ndims (sem array_length)';
END;
$$;

-- ================================================================
-- Seção 2 — Funcional (fixtures sintéticas, ROLLBACK ao final)
-- ================================================================

BEGIN;

DO $$
DECLARE
    v_admin_id UUID;
    v_game_id UUID;
    v_expansion_id UUID;
    v_card_set_id UUID;
    v_rarity_id UUID;
    v_category_id UUID;
    v_source_id UUID;
    v_lang_pt UUID;
    v_lang_en UUID;
    v_card_a UUID;
    v_card_b UUID;
    v_card_c UUID;
    v_suffix TEXT := UPPER(SUBSTRING(gen_random_uuid()::TEXT, 1, 8));
    v_release_order INTEGER := (FLOOR(RANDOM() * 900000) + 100000)::INTEGER;
    v_n INT;
    v_url TEXT;
    v_ext TEXT;
    v_denied BOOLEAN;
    v_msg TEXT;
    v_big UUID[];
    v_row1 UUID[];
    v_row2 UUID[];
    v_multi UUID[];
BEGIN
    -- ------------------------------------------------------------
    -- 2.0 Simula a sessão JWT de administrador (local à transação).
    -- ------------------------------------------------------------
    SELECT id INTO v_admin_id FROM public.admin_user LIMIT 1;
    IF v_admin_id IS NULL THEN
        RAISE EXCEPTION 'QUERY 6840 FALHOU (2.0): nenhum administrador em admin_user.';
    END IF;
    PERFORM set_config('request.jwt.claim.sub', v_admin_id::TEXT, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin_id, 'role', 'authenticated')::TEXT, true);
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'QUERY 6840 FALHOU (2.0): is_admin() false após simular a sessão.';
    END IF;
    RAISE NOTICE '2.0 OK: sessão simulada como admin %', v_admin_id;

    -- ------------------------------------------------------------
    -- 2.1 Fixtures. Três Cards no mesmo Card Set sintético:
    --       A — ativo,  pt-BR, COM image_source_url
    --       B — ativo,  pt-BR, image_source_url NULL
    --       C — INATIVO, pt-BR, COM image_source_url
    --     A também ganha uma referência en, para provar o filtro de idioma.
    -- ------------------------------------------------------------
    SELECT id INTO v_game_id FROM public.game LIMIT 1;
    SELECT id INTO v_source_id FROM public.asset_source WHERE code = 'TCGDEX';
    SELECT id INTO v_lang_pt FROM public.language WHERE code = 'pt-BR';
    SELECT id INTO v_lang_en FROM public.language WHERE code = 'en';
    IF v_game_id IS NULL OR v_source_id IS NULL OR v_lang_pt IS NULL OR v_lang_en IS NULL THEN
        RAISE EXCEPTION 'QUERY 6840 FALHOU (2.1): fixture base ausente (game/asset_source/language).';
    END IF;

    INSERT INTO public.expansion (game_id, code, name, release_order)
        VALUES (v_game_id, 'ZZ6840_' || v_suffix, 'Expansion de Teste 6840', v_release_order)
        RETURNING id INTO v_expansion_id;

    -- VALIDATION-HARNESS-CORRECTION-02 — card_set exige, sem default:
    --   set_type (CHECK IN REGULAR/SPECIAL/PROMO/ENERGY),
    --   base_set_size (CHECK > 0),
    --   total_set_size (CHECK >= base_set_size).
    -- Valores mínimos válidos. Não há constraint física ligando a contagem
    -- de Cards a total_set_size, então as 3 cartas sintéticas convivem com
    -- total_set_size = 1 — a fixture é deliberadamente mínima.
    INSERT INTO public.card_set (
        expansion_id, code, name, set_type, release_order, base_set_size, total_set_size
    ) VALUES (
        v_expansion_id, 'ZZ6840S_' || v_suffix, 'Card Set de Teste 6840',
        'REGULAR', v_release_order, 1, 1
    ) RETURNING id INTO v_card_set_id;

    -- A categoria PRECISA ser do mesmo Game do Card Set: o trigger
    -- trg_card_validate_game_consistency valida card_set_id/rarity_id/
    -- category_id na mesma partida. Um LIMIT 1 sem filtro abortaria aqui.
    SELECT id INTO v_rarity_id   FROM public.rarity        WHERE game_id = v_game_id LIMIT 1;
    SELECT id INTO v_category_id FROM public.card_category WHERE game_id = v_game_id LIMIT 1;
    IF v_rarity_id IS NULL OR v_category_id IS NULL THEN
        RAISE EXCEPTION 'QUERY 6840 FALHOU (2.1): rarity/card_category ausentes para o Game %.', v_game_id;
    END IF;

    -- card: a coluna é `category_id` (não `card_category_id`) e
    -- `collector_order` é NOT NULL sem default (CHECK > 0).
    INSERT INTO public.card (card_set_id, collector_number, collector_order, name, rarity_id, category_id)
        VALUES (v_card_set_id, '001', 1, 'Carta A 6840', v_rarity_id, v_category_id)
        RETURNING id INTO v_card_a;
    INSERT INTO public.card (card_set_id, collector_number, collector_order, name, rarity_id, category_id)
        VALUES (v_card_set_id, '002', 2, 'Carta B 6840', v_rarity_id, v_category_id)
        RETURNING id INTO v_card_b;
    INSERT INTO public.card (card_set_id, collector_number, collector_order, name, rarity_id, category_id)
        VALUES (v_card_set_id, '003', 3, 'Carta C 6840', v_rarity_id, v_category_id)
        RETURNING id INTO v_card_c;

    INSERT INTO public.card_external_reference
        (card_id, asset_source_id, language_id, external_card_id, external_set_id, image_source_url, is_active)
    VALUES
        (v_card_a, v_source_id, v_lang_pt, 'zz6840-001', 'zz6840', 'https://assets.tcgdex.net/pt/zz/zz6840/001', TRUE),
        (v_card_a, v_source_id, v_lang_en, 'zz6840-001-en', 'zz6840', 'https://assets.tcgdex.net/en/zz/zz6840/001', TRUE),
        (v_card_b, v_source_id, v_lang_pt, 'zz6840-002', 'zz6840', NULL, TRUE),
        (v_card_c, v_source_id, v_lang_pt, 'zz6840-003', 'zz6840', 'https://assets.tcgdex.net/pt/zz/zz6840/003', FALSE);

    RAISE NOTICE '2.1 OK: fixtures criadas (sufixo %)', v_suffix;

    -- ------------------------------------------------------------
    -- CASOS
    -- ------------------------------------------------------------

    -- Caso 1 — ADMIN ALLOWED: devolve a URL do Card A em pt-BR.
    SELECT count(*) INTO v_n
      FROM public.admin_list_card_external_image_sources(ARRAY[v_card_a], 'pt-BR');
    IF v_n <> 1 THEN
        RAISE EXCEPTION 'QUERY 6840 FALHOU (Caso 1): esperado 1 linha, veio %.', v_n;
    END IF;
    SELECT image_source_url, external_card_id INTO v_url, v_ext
      FROM public.admin_list_card_external_image_sources(ARRAY[v_card_a], 'pt-BR');
    IF v_url <> 'https://assets.tcgdex.net/pt/zz/zz6840/001' THEN
        RAISE EXCEPTION 'QUERY 6840 FALHOU (Caso 1): URL inesperada: %.', v_url;
    END IF;
    IF v_ext <> 'zz6840-001' THEN
        RAISE EXCEPTION 'QUERY 6840 FALHOU (Caso 1): external_card_id inesperado: %.', v_ext;
    END IF;
    RAISE NOTICE 'Caso 1 OK: admin allowed, URL e external_card_id corretos';

    -- Caso 2 — FILTRO DE IDIOMA: a referência en NÃO vaza em pt-BR.
    IF EXISTS (
        SELECT 1 FROM public.admin_list_card_external_image_sources(ARRAY[v_card_a], 'pt-BR')
         WHERE image_source_url LIKE '%/en/%'
    ) THEN
        RAISE EXCEPTION 'QUERY 6840 FALHOU (Caso 2): URL de outro idioma vazou.';
    END IF;
    SELECT image_source_url INTO v_url
      FROM public.admin_list_card_external_image_sources(ARRAY[v_card_a], 'en');
    IF v_url <> 'https://assets.tcgdex.net/en/zz/zz6840/001' THEN
        RAISE EXCEPTION 'QUERY 6840 FALHOU (Caso 2): idioma en não resolveu corretamente (%).', v_url;
    END IF;
    RAISE NOTICE 'Caso 2 OK: filtro de idioma exato nos dois sentidos';

    -- Caso 3 — image_source_url NULL é OMITIDO (Card B).
    SELECT count(*) INTO v_n
      FROM public.admin_list_card_external_image_sources(ARRAY[v_card_b], 'pt-BR');
    IF v_n <> 0 THEN
        RAISE EXCEPTION 'QUERY 6840 FALHOU (Caso 3): linha com URL NULL não foi omitida (%).', v_n;
    END IF;
    RAISE NOTICE 'Caso 3 OK: URL NULL omitida (identidade insuficiente)';

    -- Caso 4 — referência INATIVA é omitida (Card C).
    SELECT count(*) INTO v_n
      FROM public.admin_list_card_external_image_sources(ARRAY[v_card_c], 'pt-BR');
    IF v_n <> 0 THEN
        RAISE EXCEPTION 'QUERY 6840 FALHOU (Caso 4): referência inativa retornada (%).', v_n;
    END IF;
    RAISE NOTICE 'Caso 4 OK: is_active = false omitido';

    -- Caso 5 — lote misto: 3 Cards entram, só A sai.
    SELECT count(*) INTO v_n
      FROM public.admin_list_card_external_image_sources(ARRAY[v_card_a, v_card_b, v_card_c], 'pt-BR');
    IF v_n <> 1 THEN
        RAISE EXCEPTION 'QUERY 6840 FALHOU (Caso 5): esperado 1 de 3, veio %.', v_n;
    END IF;
    RAISE NOTICE 'Caso 5 OK: lote misto filtra corretamente';

    -- Caso 6 — array vazio => zero linhas, SEM erro.
    SELECT count(*) INTO v_n
      FROM public.admin_list_card_external_image_sources(ARRAY[]::UUID[], 'pt-BR');
    IF v_n <> 0 THEN
        RAISE EXCEPTION 'QUERY 6840 FALHOU (Caso 6): array vazio devolveu % linha(s).', v_n;
    END IF;
    RAISE NOTICE 'Caso 6 OK: array vazio => 0 linhas, sem erro';

    -- Caso 7 — NULL => zero linhas, SEM erro.
    SELECT count(*) INTO v_n
      FROM public.admin_list_card_external_image_sources(NULL, 'pt-BR');
    IF v_n <> 0 THEN
        RAISE EXCEPTION 'QUERY 6840 FALHOU (Caso 7): NULL devolveu % linha(s).', v_n;
    END IF;
    RAISE NOTICE 'Caso 7 OK: p_card_ids NULL => 0 linhas, sem erro';

    -- Caso 8 — idioma inexistente => zero linhas (não erro, não vazamento).
    SELECT count(*) INTO v_n
      FROM public.admin_list_card_external_image_sources(ARRAY[v_card_a], 'zz-ZZ');
    IF v_n <> 0 THEN
        RAISE EXCEPTION 'QUERY 6840 FALHOU (Caso 8): idioma inexistente devolveu % linha(s).', v_n;
    END IF;
    RAISE NOTICE 'Caso 8 OK: idioma inexistente => 0 linhas';

    -- Caso 9 — idioma NULL/vazio => EXCEPTION (não silêncio).
    v_denied := FALSE;
    BEGIN
        PERFORM * FROM public.admin_list_card_external_image_sources(ARRAY[v_card_a], NULL);
    EXCEPTION WHEN OTHERS THEN
        v_denied := TRUE; v_msg := SQLERRM;
    END;
    IF NOT v_denied OR v_msg NOT LIKE '%LANGUAGE_REQUIRED%' THEN
        RAISE EXCEPTION 'QUERY 6840 FALHOU (Caso 9): idioma NULL não levantou LANGUAGE_REQUIRED (msg=%).', v_msg;
    END IF;
    RAISE NOTICE 'Caso 9 OK: idioma NULL => LANGUAGE_REQUIRED';

    -- Caso 10 — fonte inexistente => zero linhas.
    SELECT count(*) INTO v_n
      FROM public.admin_list_card_external_image_sources(ARRAY[v_card_a], 'pt-BR', 'FONTE_INEXISTENTE');
    IF v_n <> 0 THEN
        RAISE EXCEPTION 'QUERY 6840 FALHOU (Caso 10): fonte inexistente devolveu % linha(s).', v_n;
    END IF;
    RAISE NOTICE 'Caso 10 OK: filtro de asset_source ativo';

    -- Caso 11 — default de fonte é TCGDEX (chamada de 2 args == 3 args).
    IF (SELECT count(*) FROM public.admin_list_card_external_image_sources(ARRAY[v_card_a], 'pt-BR'))
       <> (SELECT count(*) FROM public.admin_list_card_external_image_sources(ARRAY[v_card_a], 'pt-BR', 'TCGDEX')) THEN
        RAISE EXCEPTION 'QUERY 6840 FALHOU (Caso 11): default de p_asset_source_code não é TCGDEX.';
    END IF;
    RAISE NOTICE 'Caso 11 OK: default TCGDEX';

    -- Caso 12 — LOTE DE 200 (o tamanho real usado pelo auditor) passa.
    SELECT array_agg(gen_random_uuid()) INTO v_big FROM generate_series(1, 199);
    v_big := v_big || v_card_a;
    SELECT count(*) INTO v_n
      FROM public.admin_list_card_external_image_sources(v_big, 'pt-BR');
    IF v_n <> 1 THEN
        RAISE EXCEPTION 'QUERY 6840 FALHOU (Caso 12): lote de 200 devolveu % linha(s), esperado 1.', v_n;
    END IF;
    RAISE NOTICE 'Caso 12 OK: lote de 200 aceito';

    -- Caso 13 — CAP: 501 ids unidimensionais => EXCEPTION explícita
    --   (não truncamento silencioso).
    SELECT array_agg(gen_random_uuid()) INTO v_big FROM generate_series(1, 501);
    IF array_ndims(v_big) <> 1 OR cardinality(v_big) <> 501 THEN
        RAISE EXCEPTION 'QUERY 6840 FALHOU (Caso 13): fixture inválida (ndims=%, card=%).',
            array_ndims(v_big), cardinality(v_big);
    END IF;
    v_denied := FALSE;
    BEGIN
        PERFORM * FROM public.admin_list_card_external_image_sources(v_big, 'pt-BR');
    EXCEPTION WHEN OTHERS THEN
        v_denied := TRUE; v_msg := SQLERRM;
    END;
    IF NOT v_denied OR v_msg NOT LIKE '%BULK_LIMIT%' THEN
        RAISE EXCEPTION 'QUERY 6840 FALHOU (Caso 13): 501 ids não levantou BULK_LIMIT (msg=%).', v_msg;
    END IF;
    RAISE NOTICE 'Caso 13 OK: cap de 500 falha alto';

    -- Caso 14 — CAP no limite exato: 500 ids unidimensionais passa.
    SELECT array_agg(gen_random_uuid()) INTO v_big FROM generate_series(1, 500);
    IF array_ndims(v_big) <> 1 OR cardinality(v_big) <> 500 THEN
        RAISE EXCEPTION 'QUERY 6840 FALHOU (Caso 14): fixture inválida (ndims=%, card=%).',
            array_ndims(v_big), cardinality(v_big);
    END IF;
    PERFORM * FROM public.admin_list_card_external_image_sources(v_big, 'pt-BR');
    RAISE NOTICE 'Caso 14 OK: 500 ids unidimensionais (limite exato) aceito';

    -- Caso 15 — NON-ADMIN DENIED: sessão authenticated sem claim de admin.
    --   Usa um UUID que não está em admin_user. is_admin() = false =>
    --   RAISE EXCEPTION, e NÃO lista vazia (a distinção importa: vazio
    --   viraria "identidade insuficiente" silenciosa no auditor).
    PERFORM set_config('request.jwt.claim.sub', gen_random_uuid()::TEXT, true);
    PERFORM set_config('request.jwt.claims',
        json_build_object('sub', gen_random_uuid(), 'role', 'authenticated')::TEXT, true);
    IF public.is_admin() THEN
        RAISE EXCEPTION 'QUERY 6840 FALHOU (Caso 15): is_admin() ainda true após trocar o sub.';
    END IF;

    v_denied := FALSE;
    BEGIN
        PERFORM * FROM public.admin_list_card_external_image_sources(ARRAY[v_card_a], 'pt-BR');
    EXCEPTION WHEN OTHERS THEN
        v_denied := TRUE; v_msg := SQLERRM;
    END;
    IF NOT v_denied THEN
        RAISE EXCEPTION 'QUERY 6840 FALHOU (Caso 15): não-admin NÃO foi negado.';
    END IF;
    IF v_msg NOT LIKE '%administradores%' THEN
        RAISE EXCEPTION 'QUERY 6840 FALHOU (Caso 15): negado, mas com mensagem inesperada: %.', v_msg;
    END IF;
    RAISE NOTICE 'Caso 15 OK: não-admin recebe EXCEPTION, não lista vazia';

    -- Caso 16 — restaura a sessão de admin e confirma que volta a funcionar
    --   (prova que a negação foi pelo guard, não por efeito colateral).
    PERFORM set_config('request.jwt.claim.sub', v_admin_id::TEXT, true);
    PERFORM set_config('request.jwt.claims',
        json_build_object('sub', v_admin_id, 'role', 'authenticated')::TEXT, true);
    SELECT count(*) INTO v_n
      FROM public.admin_list_card_external_image_sources(ARRAY[v_card_a], 'pt-BR');
    IF v_n <> 1 THEN
        RAISE EXCEPTION 'QUERY 6840 FALHOU (Caso 16): admin restaurado devolveu % linha(s).', v_n;
    END IF;
    RAISE NOTICE 'Caso 16 OK: admin restaurado volta a ler (guard é a única causa da negação)';

    -- ------------------------------------------------------------
    -- HARDENING-CORRECTION-01 — bypass do cap por array multidimensional
    -- ------------------------------------------------------------

    -- Caso 17 — multidimensional PEQUENO já é rejeitado pela FORMA.
    --   Nenhum uso legítimo passa UUID[][]; rejeitar por forma é mais
    --   estreito (e mais honesto) do que só contar elementos.
    v_multi := ARRAY[ARRAY[gen_random_uuid(), gen_random_uuid(), gen_random_uuid()],
                     ARRAY[gen_random_uuid(), gen_random_uuid(), gen_random_uuid()]];
    IF array_ndims(v_multi) <> 2 THEN
        RAISE EXCEPTION 'QUERY 6840 FALHOU (Caso 17): fixture não ficou 2-D (ndims=%).', array_ndims(v_multi);
    END IF;
    v_denied := FALSE;
    BEGIN
        PERFORM * FROM public.admin_list_card_external_image_sources(v_multi, 'pt-BR');
    EXCEPTION WHEN OTHERS THEN
        v_denied := TRUE; v_msg := SQLERRM;
    END;
    IF NOT v_denied OR v_msg NOT LIKE '%ARRAY_NDIMS%' THEN
        RAISE EXCEPTION 'QUERY 6840 FALHOU (Caso 17): 2-D pequeno não levantou ARRAY_NDIMS (msg=%).', v_msg;
    END IF;
    RAISE NOTICE 'Caso 17 OK: UUID[][] rejeitado por forma (ARRAY_NDIMS)';

    -- Caso 18 — O VETOR DE BYPASS EXATO.
    --   2 x 400 = 800 elementos reais, mas array_length(.,1) = 2.
    --   O guard antigo (array_length) teria APROVADO; o novo (cardinality
    --   + ndims) rejeita. O teste prova as duas coisas explicitamente.
    SELECT array_agg(gen_random_uuid()) INTO v_row1 FROM generate_series(1, 400);
    SELECT array_agg(gen_random_uuid()) INTO v_row2 FROM generate_series(1, 400);
    v_multi := ARRAY[v_row1, v_row2];

    IF array_length(v_multi, 1) > 500 THEN
        RAISE EXCEPTION 'QUERY 6840 FALHOU (Caso 18): fixture não reproduz o bypass — array_length(.,1) = % já excede o teto.',
            array_length(v_multi, 1);
    END IF;
    IF cardinality(v_multi) <> 800 OR array_ndims(v_multi) <> 2 THEN
        RAISE EXCEPTION 'QUERY 6840 FALHOU (Caso 18): fixture inválida (card=%, ndims=%).',
            cardinality(v_multi), array_ndims(v_multi);
    END IF;
    RAISE NOTICE 'Caso 18: fixture confirma o bypass — array_length(.,1)=% (<=500) mas cardinality=%',
        array_length(v_multi, 1), cardinality(v_multi);

    v_denied := FALSE;
    BEGIN
        PERFORM * FROM public.admin_list_card_external_image_sources(v_multi, 'pt-BR');
    EXCEPTION WHEN OTHERS THEN
        v_denied := TRUE; v_msg := SQLERRM;
    END;
    IF NOT v_denied THEN
        RAISE EXCEPTION 'QUERY 6840 FALHOU (Caso 18): BYPASS DO CAP — 800 elementos aceitos porque array_length(.,1) = 2.';
    END IF;
    IF v_msg NOT LIKE '%ARRAY_NDIMS%' AND v_msg NOT LIKE '%BULK_LIMIT%' THEN
        RAISE EXCEPTION 'QUERY 6840 FALHOU (Caso 18): rejeitado, mas por motivo inesperado (msg=%).', v_msg;
    END IF;
    RAISE NOTICE 'Caso 18 OK: bypass 2x400 bloqueado (%)', v_msg;

    RAISE NOTICE '=== 6840: 18/18 casos OK — ROLLBACK a seguir ===';
END;
$$;

ROLLBACK;

-- ================================================================
-- Seção 3 — Zero resíduo (executar APÓS o ROLLBACK)
-- ================================================================
SELECT
    (SELECT count(*) FROM public.expansion WHERE code LIKE 'ZZ6840\_%')  AS expansions_residuais,
    (SELECT count(*) FROM public.card_set  WHERE code LIKE 'ZZ6840S\_%') AS card_sets_residuais,
    (SELECT count(*) FROM public.card_external_reference
      WHERE external_card_id LIKE 'zz6840-%')                            AS refs_residuais;
-- Esperado: 0 | 0 | 0
