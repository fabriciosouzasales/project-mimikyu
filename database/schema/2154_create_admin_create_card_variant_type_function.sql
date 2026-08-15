/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2154 - Create admin_create_card_variant_type() Function
Versão......: 1.0
Status......: CANÔNICA — CONFIRMADO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-15

Descrição...:
Cria admin_create_card_variant_type(), cadastro administrativo de
Card Variant Type canônico — Incremento 1 do bloco de governança da
Taxonomia de Card Variant (ADR-028). Mesmo padrão de
admin_create_rarity() (Query 2099), sem symbol_code (não existe
nesta entidade) e com description (coluna já existente desde a
Query 150, editorial e opcional).

Regras de Negócio:
- code normalizado para maiúsculas, formato `^[A-Z0-9][A-Z0-9_]*$`
  (mesmo padrão de outros códigos do catálogo); único por Game
  (ADMIN_CREATE_CARD_VARIANT_TYPE_DUPLICATE_CODE,
  uq_card_variant_type_game_code, Query 150).
- display_order deve ser positivo E único por Game — diferente de
  Raridade (onde a ordem pode empatar): card_variant_type já tem
  uq_card_variant_type_game_display_order (Query 150) como
  constraint física; a checagem explícita aqui só converte o que
  seria um unique_violation genérico num erro de negócio claro
  (ADMIN_CREATE_CARD_VARIANT_TYPE_DUPLICATE_DISPLAY_ORDER).
- description é opcional — string vazia é normalizada para NULL
  (mesma regra do CHECK ck_card_variant_type_description_not_blank
  da Query 150: "NULL ou não-branco", nunca string vazia).
- is_active nasce sempre true (DEFAULT da coluna, Query 2152) —
  esta função não aceita esse parâmetro; um tipo recém-criado
  começa disponível para seleção.
- Grava catalog_admin_action_log (CARD_VARIANT_TYPE_CREATED) — ação
  habilitada pela Query 2153.
- SECURITY DEFINER com search_path endurecido, GRANT EXECUTE restrito
  a authenticated, REVOKE ALL explícito de PUBLIC/anon desde a
  criação (nunca herdar acesso implícito de PUBLIC).

Pré-requisitos:
- Query 150 - Create Card Variant Type Table.
- Query 2152 - Add is_active to Card Variant Type.
- Query 2153 - Widen Catalog Admin Action Log for Card Variant Type.
================================================================
*/

CREATE OR REPLACE FUNCTION public.admin_create_card_variant_type(
    p_game_id UUID,
    p_code TEXT,
    p_name TEXT,
    p_description TEXT,
    p_display_order INTEGER
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_code TEXT;
    v_name TEXT;
    v_description TEXT;
    v_id UUID;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'ADMIN_CREATE_CARD_VARIANT_TYPE_FORBIDDEN: apenas administradores podem cadastrar um Card Variant Type.';
    END IF;

    IF p_game_id IS NULL THEN
        RAISE EXCEPTION 'ADMIN_CREATE_CARD_VARIANT_TYPE_MISSING_GAME: p_game_id é obrigatório.';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.game WHERE id = p_game_id) THEN
        RAISE EXCEPTION 'ADMIN_CREATE_CARD_VARIANT_TYPE_GAME_NOT_FOUND: nenhum Game encontrado para o id informado (%).', p_game_id;
    END IF;

    v_code := upper(btrim(coalesce(p_code, '')));
    v_name := btrim(coalesce(p_name, ''));
    v_description := btrim(coalesce(p_description, ''));

    IF v_description = '' THEN
        v_description := NULL;
    END IF;

    IF v_code = '' OR v_code !~ '^[A-Z0-9][A-Z0-9_]*$' THEN
        RAISE EXCEPTION 'ADMIN_CREATE_CARD_VARIANT_TYPE_INVALID_CODE: o código deve começar com letra ou número e conter apenas letras maiúsculas, números e sublinhado.';
    END IF;

    IF v_name = '' THEN
        RAISE EXCEPTION 'ADMIN_CREATE_CARD_VARIANT_TYPE_INVALID_NAME: o nome não pode ser vazio.';
    END IF;

    IF p_display_order IS NULL OR p_display_order <= 0 THEN
        RAISE EXCEPTION 'ADMIN_CREATE_CARD_VARIANT_TYPE_INVALID_DISPLAY_ORDER: a ordem de exibição deve ser um número positivo.';
    END IF;

    IF EXISTS (SELECT 1 FROM public.card_variant_type WHERE game_id = p_game_id AND code = v_code) THEN
        RAISE EXCEPTION 'ADMIN_CREATE_CARD_VARIANT_TYPE_DUPLICATE_CODE: já existe um Card Variant Type com o código % para este Game.', v_code;
    END IF;

    IF EXISTS (SELECT 1 FROM public.card_variant_type WHERE game_id = p_game_id AND display_order = p_display_order) THEN
        RAISE EXCEPTION 'ADMIN_CREATE_CARD_VARIANT_TYPE_DUPLICATE_DISPLAY_ORDER: já existe um Card Variant Type com a ordem % para este Game.', p_display_order;
    END IF;

    INSERT INTO public.card_variant_type (game_id, code, name, description, display_order)
        VALUES (p_game_id, v_code, v_name, v_description, p_display_order)
        RETURNING id INTO v_id;

    INSERT INTO public.catalog_admin_action_log (actor_id, action, entity_type, entity_id, metadata)
        VALUES (
            auth.uid(), 'CARD_VARIANT_TYPE_CREATED', 'CARD_VARIANT_TYPE', v_id,
            jsonb_build_object(
                'game_id', p_game_id, 'code', v_code, 'name', v_name,
                'description', v_description, 'display_order', p_display_order
            )
        );

    RETURN v_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_create_card_variant_type(UUID, TEXT, TEXT, TEXT, INTEGER) TO authenticated;

REVOKE ALL ON FUNCTION public.admin_create_card_variant_type(UUID, TEXT, TEXT, TEXT, INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_create_card_variant_type(UUID, TEXT, TEXT, TEXT, INTEGER) FROM anon;

-- ================================================================
-- Confirmado executado e validado (2026-08-15, via execute_sql/MCP do
-- Supabase, projeto qjfutqujxrbzgrtkpgkg), depois de dry-run em
-- BEGIN...ROLLBACK. Validado contra a função real (também dentro de
-- BEGIN...ROLLBACK, sem persistir dado de teste): admin cria com
-- sucesso; não-admin (impersonado via request.jwt.claim.sub) recebe
-- ADMIN_CREATE_CARD_VARIANT_TYPE_FORBIDDEN; código duplicado rejeitado
-- (ADMIN_CREATE_CARD_VARIANT_TYPE_DUPLICATE_CODE); display_order
-- duplicado rejeitado (ADMIN_CREATE_CARD_VARIANT_TYPE_DUPLICATE_
-- DISPLAY_ORDER, contra a ordem 1 já ocupada por STANDARD);
-- has_function_privilege confirma authenticated=true, anon=false;
-- prosecdef=true, proconfig confirma search_path="" endurecido.
-- ================================================================
