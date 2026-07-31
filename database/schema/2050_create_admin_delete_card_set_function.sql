/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2050 - Create admin_delete_card_set() Function
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-07-31

Descrição...:
Cria admin_delete_card_set(), função pública SECURITY DEFINER —
via de exclusão real (não desativação) de Card Set. Ver ADR-023,
emenda 2026-07-31 ("Card Set: atualização e exclusão real via
UI"), mesmo padrão já aplicado a Game (Query 2042) e Expansion
(Query 2044).

Regras de Negócio:
- Só um administrador pode chamar esta função (is_admin()).
- code/name são capturados por SELECT antes do DELETE — depois de
  excluído, não há mais como consultar esses dados para a
  auditoria.
- A FK fk_card_card_set (ON DELETE RESTRICT, Query 140) impede a
  exclusão de um Card Set com Cards associadas; esta função
  antecipa esse erro bruto (foreign_key_violation) com uma
  mensagem administrativa clara, mesmo padrão de "antecipar o
  erro" já usado em admin_delete_expansion().
- GET DIAGNOSTICS ... ROW_COUNT confirma o efeito real do DELETE.
- Toda exclusão bem-sucedida grava uma linha em
  catalog_admin_action_log (CARD_SET_DELETED) com code/name em
  metadata.
- Exclusão definitiva — sem "lixeira", sem forma de desfazer pela
  UI.

Pré-requisitos:
- Query 120 - Create Card Set Table.
- Query 140 - Create Card Table (fk_card_card_set).
- Query 1060 - Create is_admin() Function.
- Query 2049 - Add CARD_SET_DELETED to Catalog Admin Action Log.
================================================================
*/

CREATE OR REPLACE FUNCTION public.admin_delete_card_set(
    p_id UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_code TEXT;
    v_name TEXT;
    v_rows_affected INTEGER;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'ADMIN_DELETE_CARD_SET_FORBIDDEN: apenas administradores podem excluir um Card Set.';
    END IF;

    IF p_id IS NULL THEN
        RAISE EXCEPTION 'ADMIN_DELETE_CARD_SET_MISSING_ID: p_id é obrigatório.';
    END IF;

    SELECT code, name INTO v_code, v_name FROM public.card_set WHERE id = p_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'ADMIN_DELETE_CARD_SET_NOT_FOUND: nenhum Card Set encontrado para o id informado (%).', p_id;
    END IF;

    BEGIN
        DELETE FROM public.card_set WHERE id = p_id;
    EXCEPTION WHEN foreign_key_violation THEN
        RAISE EXCEPTION 'ADMIN_DELETE_CARD_SET_HAS_DEPENDENTS: não é possível excluir o Card Set % (%) porque já existem Cards cadastradas para ele.', v_name, v_code;
    END;

    GET DIAGNOSTICS v_rows_affected = ROW_COUNT;

    IF v_rows_affected <> 1 THEN
        RAISE EXCEPTION 'ADMIN_DELETE_CARD_SET_NOT_FOUND: nenhum Card Set encontrado para o id informado (%).', p_id;
    END IF;

    INSERT INTO public.catalog_admin_action_log (actor_id, action, entity_type, entity_id, metadata)
        VALUES (auth.uid(), 'CARD_SET_DELETED', 'CARD_SET', p_id, jsonb_build_object('code', v_code, 'name', v_name));

    RETURN p_id;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_delete_card_set(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_delete_card_set(UUID) TO authenticated;
