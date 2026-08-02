-- ============================================================
-- Migration 2091 - Widen admin_update_card_set() for `code`
-- Status: MIGRATION (histórica) — incorporada à versão canônica
-- de `2048 - Create admin_update_card_set() Function` a partir
-- da v3.0.
--
-- Amplia admin_update_card_set() de 5 para 6 parâmetros (adiciona
-- `code` como campo condicionalmente editável). Pedido explícito
-- de Fabrício (2026-08-01), ao perceber um erro de cadastro real
-- (Coleção "151" registrada com código SV4 em vez de MEW): "Na
-- tela de Edição deveremos permitir alterar o código. Só não será
-- permitido se já houver cartas cadastradas."
--
-- Isso reverte parcialmente a decisão original do ADR-023 ("code é
-- imutável por construção... correção rara, deliberada, nunca uma
-- ação de botão") — ver emenda correspondente no próprio ADR-023.
-- A trava não desaparece, só passa a ser condicional: enquanto o
-- Card Set não tem nenhuma Card cadastrada (ativa ou inativa —
-- `is_active` não importa aqui, qualquer linha em `card` já fixa a
-- identidade do Card Set), o código ainda não significa nada para
-- ninguém além de quem está cadastrando, e um erro de digitação
-- pode ser corrigido pela própria tela. Assim que a primeira Card
-- existe, a trava volta a ser absoluta — mesmo raciocínio já usado
-- para engatilhar regras de PROMO nesta mesma função.
--
-- A assinatura muda (novo parâmetro), então CREATE OR REPLACE
-- sozinho criaria uma segunda função sobrecarregada em vez de
-- substituir a existente — por isso a v2.0 (5 parâmetros) é
-- removida explicitamente antes de criar a nova versão, mesmo
-- padrão já usado pela Migration 2052.
--
-- Ver docs/05-modelo-de-dados.md, seção Coleções, e
-- docs/adr/ADR-023-catalog-editorial-write-authorization.md,
-- emenda "Card Set: código editável sem Cards cadastradas".
-- ============================================================

BEGIN;

DROP FUNCTION IF EXISTS public.admin_update_card_set(UUID, TEXT, TEXT, INTEGER, DATE);

CREATE FUNCTION public.admin_update_card_set(
    p_id UUID,
    p_code TEXT,
    p_name TEXT,
    p_set_type TEXT,
    p_release_order INTEGER,
    p_release_date DATE
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
    v_base_set_size INTEGER;
    v_total_set_size INTEGER;
    v_rows_affected INTEGER;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'ADMIN_UPDATE_CARD_SET_FORBIDDEN: apenas administradores podem atualizar um Card Set.';
    END IF;

    IF p_id IS NULL THEN
        RAISE EXCEPTION 'ADMIN_UPDATE_CARD_SET_MISSING_ID: p_id é obrigatório.';
    END IF;

    SELECT expansion_id, code, base_set_size, total_set_size
        INTO v_expansion_id, v_current_code, v_base_set_size, v_total_set_size
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

    IF v_set_type = 'PROMO' AND v_base_set_size <> v_total_set_size THEN
        RAISE EXCEPTION 'ADMIN_UPDATE_CARD_SET_PROMO_SIZE_MISMATCH: um Card Set do tipo PROMO deve ter quantidade base igual à quantidade total (ajuste as quantidades por correção manual antes de mudar o tipo).';
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
            release_date = p_release_date
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
                'release_order', p_release_order, 'release_date', p_release_date
            )
        );

    RETURN p_id;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_update_card_set(UUID, TEXT, TEXT, TEXT, INTEGER, DATE) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_update_card_set(UUID, TEXT, TEXT, TEXT, INTEGER, DATE) TO authenticated;

COMMIT;
