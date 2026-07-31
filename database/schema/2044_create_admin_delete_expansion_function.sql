/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2044 - Create admin_delete_expansion() Function
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-07-31

Descrição...:
Cria admin_delete_expansion(), função pública SECURITY DEFINER —
via de exclusão real (não desativação) de Expansion. Ver ADR-023,
emenda 2026-07-31 ("Expansion: exclusão real via UI"), mesmo
padrão já aplicado a Game (Query 2042).

Regras de Negócio:
- Só um administrador pode chamar esta função (is_admin()).
- code/name são capturados por SELECT antes do DELETE — depois de
  excluída, não há mais como consultar esses dados para a
  auditoria.
- A FK fk_card_set_expansion (ON DELETE RESTRICT, Query 120) impede
  a exclusão de uma Expansion com Card Sets associados; esta função
  antecipa esse erro bruto (foreign_key_violation) com uma
  mensagem administrativa clara, mesmo padrão de "antecipar o
  erro" já usado em admin_delete_game().
- GET DIAGNOSTICS ... ROW_COUNT confirma o efeito real do DELETE.
- Toda exclusão bem-sucedida grava uma linha em
  catalog_admin_action_log (EXPANSION_DELETED) com code/name em
  metadata.
- Exclusão definitiva — sem "lixeira", sem forma de desfazer pela
  UI.

Pré-requisitos:
- Query 110 - Create Expansion Table.
- Query 120 - Create Card Set Table (fk_card_set_expansion).
- Query 1060 - Create is_admin() Function.
- Query 2043 - Add EXPANSION_DELETED to Catalog Admin Action Log.
================================================================
*/

CREATE OR REPLACE FUNCTION public.admin_delete_expansion(
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
        RAISE EXCEPTION 'ADMIN_DELETE_EXPANSION_FORBIDDEN: apenas administradores podem excluir uma Expansão.';
    END IF;

    IF p_id IS NULL THEN
        RAISE EXCEPTION 'ADMIN_DELETE_EXPANSION_MISSING_ID: p_id é obrigatório.';
    END IF;

    SELECT code, name INTO v_code, v_name FROM public.expansion WHERE id = p_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'ADMIN_DELETE_EXPANSION_NOT_FOUND: nenhuma Expansão encontrada para o id informado (%).', p_id;
    END IF;

    BEGIN
        DELETE FROM public.expansion WHERE id = p_id;
    EXCEPTION WHEN foreign_key_violation THEN
        RAISE EXCEPTION 'ADMIN_DELETE_EXPANSION_HAS_DEPENDENTS: não é possível excluir a Expansão % (%) porque já existem Card Sets cadastrados para ela.', v_name, v_code;
    END;

    GET DIAGNOSTICS v_rows_affected = ROW_COUNT;

    IF v_rows_affected <> 1 THEN
        RAISE EXCEPTION 'ADMIN_DELETE_EXPANSION_NOT_FOUND: nenhuma Expansão encontrada para o id informado (%).', p_id;
    END IF;

    INSERT INTO public.catalog_admin_action_log (actor_id, action, entity_type, entity_id, metadata)
        VALUES (auth.uid(), 'EXPANSION_DELETED', 'EXPANSION', p_id, jsonb_build_object('code', v_code, 'name', v_name));

    RETURN p_id;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_delete_expansion(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_delete_expansion(UUID) TO authenticated;
