-- ============================================================
-- Migration 2130 - Widen admin_update_card_set() for sizes
-- Status: MIGRATION — CONFIRMADO EXECUTADO. Incorporada à versão
-- canônica de `2048 - Create admin_update_card_set() Function` a
-- partir da v4.0.
--
-- Amplia admin_update_card_set() de 6 para 8 parâmetros (adiciona
-- `base_set_size`/`total_set_size` como campos editáveis). Pedido
-- explícito de Fabrício (2026-08-11), a partir de captura de tela
-- da tabela de Coleções: "A tela de edição das coleções deve
-- permitir alterar dois campos: base_set_size e total_set_size".
--
-- Sem trava condicional por Cards já cadastradas (ao contrário de
-- `code`, Migration 2091) — o próprio motivo do pedido é poder
-- corrigir um total oficial errado mesmo com o Card Set
-- parcialmente cadastrado, caso real já vivido com SVP (total
-- corrigido de 225 para 226 via SQL direto, por não existir ainda
-- esta via de UI). Validação mirra admin_create_card_set() (Query
-- 2051): base positiva, total >= base; a checagem de PROMO (base =
-- total) passa a usar os valores SENDO ENVIADOS nesta chamada, não
-- mais os já cadastrados na linha (diferença desta versão).
--
-- A assinatura muda (dois novos parâmetros), então CREATE OR
-- REPLACE sozinho criaria uma segunda função sobrecarregada em vez
-- de substituir a existente — por isso a v3.0 (6 parâmetros) é
-- removida explicitamente antes de criar a nova versão, mesmo
-- padrão já usado pela Migration 2091.
--
-- Ver docs/05e-catalogo-editorial.md.
-- ============================================================

BEGIN;

DROP FUNCTION IF EXISTS public.admin_update_card_set(UUID, TEXT, TEXT, TEXT, INTEGER, DATE);

CREATE FUNCTION public.admin_update_card_set(
    p_id UUID,
    p_code TEXT,
    p_name TEXT,
    p_set_type TEXT,
    p_release_order INTEGER,
    p_release_date DATE,
    p_base_set_size INTEGER,
    p_total_set_size INTEGER
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_code TEXT;
    v_current_code TEXT;
    v_name TEXT;
    v_set_type TEXT;
    v_expansion_id UUID;
    v_rows_affected INTEGER;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'ADMIN_UPDATE_CARD_SET_FORBIDDEN: apenas administradores podem atualizar um Card Set.';
    END IF;

    IF p_id IS NULL THEN
        RAISE EXCEPTION 'ADMIN_UPDATE_CARD_SET_MISSING_ID: p_id é obrigatório.';
    END IF;

    SELECT expansion_id, code
        INTO v_expansion_id, v_current_code
        FROM public.card_set WHERE id = p_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'ADMIN_UPDATE_CARD_SET_NOT_FOUND: nenhum Card Set encontrado para o id informado (%).', p_id;
    END IF;

    v_code := upper(btrim(coalesce(p_code, '')));
    v_name := btrim(coalesce(p_name, ''));
    v_set_type := upper(btrim(coalesce(p_set_type, '')));

    IF v_code = '' THEN
        RAISE EXCEPTION 'ADMIN_UPDATE_CARD_SET_INVALID_CODE: o código não pode ser vazio.';
    END IF;

    IF v_code !~ '^[A-Z0-9][A-Z0-9._-]*$' THEN
        RAISE EXCEPTION 'ADMIN_UPDATE_CARD_SET_INVALID_CODE: o código deve começar com letra ou número e conter apenas letras maiúsculas, números, ponto, hífen e sublinhado.';
    END IF;

    IF v_name = '' THEN
        RAISE EXCEPTION 'ADMIN_UPDATE_CARD_SET_INVALID_NAME: o nome não pode ser vazio.';
    END IF;

    IF v_set_type NOT IN ('REGULAR', 'SPECIAL', 'PROMO', 'ENERGY') THEN
        RAISE EXCEPTION 'ADMIN_UPDATE_CARD_SET_INVALID_SET_TYPE: o tipo deve ser REGULAR, SPECIAL, PROMO ou ENERGY.';
    END IF;

    IF p_release_order IS NULL OR p_release_order <= 0 THEN
        RAISE EXCEPTION 'ADMIN_UPDATE_CARD_SET_INVALID_RELEASE_ORDER: a ordem de lançamento deve ser um número positivo.';
    END IF;

    IF p_base_set_size IS NULL OR p_base_set_size <= 0 THEN
        RAISE EXCEPTION 'ADMIN_UPDATE_CARD_SET_INVALID_BASE_SIZE: a quantidade base deve ser um número positivo.';
    END IF;

    IF p_total_set_size IS NULL OR p_total_set_size < p_base_set_size THEN
        RAISE EXCEPTION 'ADMIN_UPDATE_CARD_SET_INVALID_TOTAL_SIZE: a quantidade total deve ser maior ou igual à quantidade base.';
    END IF;

    -- `code` só é travado quando já existe pelo menos uma Card
    -- cadastrada para este Card Set (ativa ou inativa) — enquanto
    -- não existir nenhuma, o código pode ser corrigido livremente.
    IF v_code <> v_current_code AND EXISTS (
        SELECT 1 FROM public.card WHERE card_set_id = p_id
    ) THEN
        RAISE EXCEPTION 'ADMIN_UPDATE_CARD_SET_CODE_LOCKED: o código não pode mais ser alterado porque este Card Set já tem Cards cadastradas.';
    END IF;

    IF v_code <> v_current_code AND EXISTS (
        SELECT 1 FROM public.card_set WHERE expansion_id = v_expansion_id AND code = v_code AND id <> p_id
    ) THEN
        RAISE EXCEPTION 'ADMIN_UPDATE_CARD_SET_DUPLICATE_CODE: já existe outro Card Set com o código % para esta Expansão.', v_code;
    END IF;

    IF v_set_type = 'PROMO' AND p_base_set_size <> p_total_set_size THEN
        RAISE EXCEPTION 'ADMIN_UPDATE_CARD_SET_PROMO_SIZE_MISMATCH: um Card Set do tipo PROMO deve ter quantidade base igual à quantidade total.';
    END IF;

    IF v_set_type = 'PROMO' AND EXISTS (
        SELECT 1 FROM public.card_set WHERE expansion_id = v_expansion_id AND set_type = 'PROMO' AND id <> p_id
    ) THEN
        RAISE EXCEPTION 'ADMIN_UPDATE_CARD_SET_DUPLICATE_PROMO: esta Expansão já possui outro Card Set do tipo PROMO.';
    END IF;

    IF EXISTS (
        SELECT 1 FROM public.card_set
        WHERE expansion_id = v_expansion_id AND release_order = p_release_order AND id <> p_id
    ) THEN
        RAISE EXCEPTION 'ADMIN_UPDATE_CARD_SET_DUPLICATE_RELEASE_ORDER: já existe outro Card Set com a ordem de lançamento % para esta Expansão.', p_release_order;
    END IF;

    UPDATE public.card_set
        SET code = v_code,
            name = v_name,
            set_type = v_set_type,
            release_order = p_release_order,
            release_date = p_release_date,
            base_set_size = p_base_set_size,
            total_set_size = p_total_set_size
        WHERE id = p_id;

    GET DIAGNOSTICS v_rows_affected = ROW_COUNT;

    IF v_rows_affected <> 1 THEN
        RAISE EXCEPTION 'ADMIN_UPDATE_CARD_SET_NOT_FOUND: nenhum Card Set encontrado para o id informado (%).', p_id;
    END IF;

    INSERT INTO public.catalog_admin_action_log (actor_id, action, entity_type, entity_id, metadata)
        VALUES (
            auth.uid(), 'CARD_SET_UPDATED', 'CARD_SET', p_id,
            jsonb_build_object(
                'code', v_code, 'name', v_name, 'set_type', v_set_type,
                'release_order', p_release_order, 'release_date', p_release_date,
                'base_set_size', p_base_set_size, 'total_set_size', p_total_set_size
            )
        );

    RETURN p_id;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_update_card_set(UUID, TEXT, TEXT, TEXT, INTEGER, DATE, INTEGER, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_update_card_set(UUID, TEXT, TEXT, TEXT, INTEGER, DATE, INTEGER, INTEGER) TO authenticated;

COMMIT;

-- ================================================================
-- CONFIRMADO EXECUTADO (2026-08-11): assinatura validada por
-- Fabrício via pg_get_function_identity_arguments() — "p_id uuid,
-- p_code text, p_name text, p_set_type text, p_release_order
-- integer, p_release_date date, p_base_set_size integer,
-- p_total_set_size integer".
-- ================================================================
