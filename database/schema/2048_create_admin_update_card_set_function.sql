/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2048 - Create admin_update_card_set() Function
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-07-31

Descrição...:
Cria admin_update_card_set(), função pública SECURITY DEFINER —
única via de atualização de Card Set (ADR-023). Ver ADR-023,
emenda 2026-07-31 ("Card Set: atualização e exclusão real via
UI"), mesmo padrão já aplicado a admin_update_expansion() (Query
2034).

Regras de Negócio:
- Só um administrador pode chamar esta função (is_admin()).
- expansion_id e code são imutáveis por construção: a assinatura
  desta função não aceita nenhum dos dois — mudar a Expansion de
  um Card Set ou seu código muda a identidade do registro, mesmo
  princípio já aplicado a game_id/code em Expansion (Query 2034)
  e a card_set_id/collector_number em Card (ADR-023).
- set_type, base_set_size e total_set_size também não são
  aceitos — são campos estruturais (a combinação PROMO exige
  base_set_size = total_set_size, ck_card_set_promo_size),
  correção rara e deliberada fora desta função, mesmo espírito já
  registrado em ADR-023 para code/set_type ("nunca uma ação de
  botão").
- release_order é editável, mas continua único dentro da mesma
  Expansion (uq_card_set_expansion_release_order) — duplicidade
  verificada explicitamente antes do UPDATE, excluindo a própria
  linha.
- GET DIAGNOSTICS ... ROW_COUNT confirma que exatamente uma linha
  foi alterada.
- Toda atualização bem-sucedida grava uma linha em
  catalog_admin_action_log (CARD_SET_UPDATED) — ação já prevista
  no CHECK original da tabela (Query 2010), nenhuma migration de
  constraint necessária para esta Query.

Pré-requisitos:
- Query 120 - Create Card Set Table.
- Query 1060 - Create is_admin() Function.
- Query 2010 - Create Catalog Admin Action Log Table.
================================================================
*/

CREATE OR REPLACE FUNCTION public.admin_update_card_set(
    p_id UUID,
    p_name TEXT,
    p_release_order INTEGER
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_name TEXT;
    v_expansion_id UUID;
    v_rows_affected INTEGER;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'ADMIN_UPDATE_CARD_SET_FORBIDDEN: apenas administradores podem atualizar um Card Set.';
    END IF;

    IF p_id IS NULL THEN
        RAISE EXCEPTION 'ADMIN_UPDATE_CARD_SET_MISSING_ID: p_id é obrigatório.';
    END IF;

    SELECT expansion_id INTO v_expansion_id FROM public.card_set WHERE id = p_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'ADMIN_UPDATE_CARD_SET_NOT_FOUND: nenhum Card Set encontrado para o id informado (%).', p_id;
    END IF;

    v_name := btrim(coalesce(p_name, ''));

    IF v_name = '' THEN
        RAISE EXCEPTION 'ADMIN_UPDATE_CARD_SET_INVALID_NAME: o nome não pode ser vazio.';
    END IF;

    IF p_release_order IS NULL OR p_release_order <= 0 THEN
        RAISE EXCEPTION 'ADMIN_UPDATE_CARD_SET_INVALID_RELEASE_ORDER: a ordem de lançamento deve ser um número positivo.';
    END IF;

    IF EXISTS (
        SELECT 1 FROM public.card_set
        WHERE expansion_id = v_expansion_id AND release_order = p_release_order AND id <> p_id
    ) THEN
        RAISE EXCEPTION 'ADMIN_UPDATE_CARD_SET_DUPLICATE_RELEASE_ORDER: já existe outro Card Set com a ordem de lançamento % para esta Expansão.', p_release_order;
    END IF;

    UPDATE public.card_set
        SET name = v_name,
            release_order = p_release_order
        WHERE id = p_id;

    GET DIAGNOSTICS v_rows_affected = ROW_COUNT;

    IF v_rows_affected <> 1 THEN
        RAISE EXCEPTION 'ADMIN_UPDATE_CARD_SET_NOT_FOUND: nenhum Card Set encontrado para o id informado (%).', p_id;
    END IF;

    INSERT INTO public.catalog_admin_action_log (actor_id, action, entity_type, entity_id, metadata)
        VALUES (auth.uid(), 'CARD_SET_UPDATED', 'CARD_SET', p_id, jsonb_build_object('name', v_name, 'release_order', p_release_order));

    RETURN p_id;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_update_card_set(UUID, TEXT, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_update_card_set(UUID, TEXT, INTEGER) TO authenticated;
