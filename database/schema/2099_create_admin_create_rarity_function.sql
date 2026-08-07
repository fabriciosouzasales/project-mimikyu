/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2099 - Create admin_create_rarity() Function
Versão......: 1.0
Status......: CANÔNICA — CONFIRMADO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-07

Descrição...:
Cria admin_create_rarity(), cadastro administrativo de Raridade
canônica via UI (/catalogo/raridades) — parte do ciclo self-
service de Raridade (ADR-024, emenda). Chamada diretamente pela
tela ("Nova Raridade") e internamente por
admin_create_rarity_with_external_mapping() (Query 2103).

Regras de Negócio:
- code normalizado para maiúsculas, formato
  `^[A-Z0-9][A-Z0-9_]*$` (mesmo padrão de outros códigos do
  catálogo); único por Game (ADMIN_CREATE_RARITY_DUPLICATE_CODE).
- symbol_code no mesmo formato — não validado contra uma lista
  fechada aqui (a aplicação é responsável por convertê-lo num
  ativo visual, ver RaritySymbol/rarity-symbol.tsx e comentário
  original da Query 130).
- display_order deve ser positivo — não há checagem de unicidade
  (raridades podem empatar em ordem de exibição; a UI decide o
  desempate).
- Grava catalog_admin_action_log (RARITY_CREATED) — ação
  habilitada pela Query 2098 (executada antes desta, mesmo dia).

Pré-requisitos:
- Query 130 - Create Rarity Table.
- Query 2098 - Add Rarity Actions to Catalog Admin Action Log.
================================================================
*/

CREATE OR REPLACE FUNCTION public.admin_create_rarity(
    p_game_id UUID,
    p_code TEXT,
    p_name TEXT,
    p_symbol_code TEXT,
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
    v_symbol_code TEXT;
    v_id UUID;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'ADMIN_CREATE_RARITY_FORBIDDEN: apenas administradores podem cadastrar uma Raridade.';
    END IF;

    IF p_game_id IS NULL THEN
        RAISE EXCEPTION 'ADMIN_CREATE_RARITY_MISSING_GAME: p_game_id é obrigatório.';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.game WHERE id = p_game_id) THEN
        RAISE EXCEPTION 'ADMIN_CREATE_RARITY_GAME_NOT_FOUND: nenhum Game encontrado para o id informado (%).', p_game_id;
    END IF;

    v_code := upper(btrim(coalesce(p_code, '')));
    v_name := btrim(coalesce(p_name, ''));
    v_symbol_code := upper(btrim(coalesce(p_symbol_code, '')));

    IF v_code = '' OR v_code !~ '^[A-Z0-9][A-Z0-9_]*$' THEN
        RAISE EXCEPTION 'ADMIN_CREATE_RARITY_INVALID_CODE: o código deve começar com letra ou número e conter apenas letras maiúsculas, números e sublinhado.';
    END IF;

    IF v_name = '' THEN
        RAISE EXCEPTION 'ADMIN_CREATE_RARITY_INVALID_NAME: o nome não pode ser vazio.';
    END IF;

    IF v_symbol_code = '' OR v_symbol_code !~ '^[A-Z0-9][A-Z0-9_]*$' THEN
        RAISE EXCEPTION 'ADMIN_CREATE_RARITY_INVALID_SYMBOL_CODE: o código de símbolo deve começar com letra ou número e conter apenas letras maiúsculas, números e sublinhado.';
    END IF;

    IF p_display_order IS NULL OR p_display_order <= 0 THEN
        RAISE EXCEPTION 'ADMIN_CREATE_RARITY_INVALID_DISPLAY_ORDER: a ordem de exibição deve ser um número positivo.';
    END IF;

    IF EXISTS (SELECT 1 FROM public.rarity WHERE game_id = p_game_id AND code = v_code) THEN
        RAISE EXCEPTION 'ADMIN_CREATE_RARITY_DUPLICATE_CODE: já existe uma Raridade com o código % para este Game.', v_code;
    END IF;

    INSERT INTO public.rarity (game_id, code, name, symbol_code, display_order)
        VALUES (p_game_id, v_code, v_name, v_symbol_code, p_display_order)
        RETURNING id INTO v_id;

    INSERT INTO public.catalog_admin_action_log (actor_id, action, entity_type, entity_id, metadata)
        VALUES (
            auth.uid(), 'RARITY_CREATED', 'RARITY', v_id,
            jsonb_build_object(
                'game_id', p_game_id, 'code', v_code, 'name', v_name,
                'symbol_code', v_symbol_code, 'display_order', p_display_order
            )
        );

    RETURN v_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_create_rarity(UUID, TEXT, TEXT, TEXT, INTEGER) TO authenticated;

-- ================================================================
-- Confirmado executado (2026-08-07): definição em produção lida
-- via pg_get_functiondef() e conferida idêntica a este arquivo.
-- Usada em produção (RARE_HOLO, RARE_HOLO_V, RARE_SECRET,
-- RARE_HOLO_VMAX cadastradas via UI).
-- ================================================================
