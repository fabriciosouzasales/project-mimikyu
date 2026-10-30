/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5305 - Create remove_collection_member()
Versão......: 1.0
Status......: PROPOSTA — NÃO EXECUTADA (V1-12)
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-30

Descrição...:
Titular encerra uma participação da sua coleção (C-154/C-155): cancela
convite PENDING, remove participante ACTIVE ou limpa um DECLINED.

Regras de Negócio:
- Só o titular. Participação de coleção alheia ou inexistente →
  MEMBERSHIP_NOT_FOUND (não enumera).
- Permitido também em coleção ARCHIVED: revogar acesso nunca deve
  depender de reativar a coleção.
- DELETE: o acesso cai na mesma transação (5302 deixa de devolver VIEWER).
- Idempotente pela ótica do cliente: segunda chamada → MEMBERSHIP_NOT_FOUND,
  que a interface trata como "já não estava mais aqui".
- Nada além da linha de participação muda (C-155): exemplares, coleção,
  fichário, favoritos, wishlist — intocados.
================================================================
*/

CREATE OR REPLACE FUNCTION public.remove_collection_member(
    p_collection_id UUID,
    p_membership_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_user    UUID := auth.uid();
    v_status  TEXT;
BEGIN
    IF v_user IS NULL THEN
        RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '28000';
    END IF;

    DELETE FROM public.collection_membership m
    USING public.collection c
    WHERE m.id = p_membership_id
      AND m.collection_id = p_collection_id
      AND c.id = m.collection_id
      AND c.owner_user_id = v_user
    RETURNING m.status INTO v_status;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'MEMBERSHIP_NOT_FOUND' USING ERRCODE = 'P0002';
    END IF;

    RETURN jsonb_build_object('outcome', 'REMOVED', 'previous_status', v_status);
END;
$$;

REVOKE ALL ON FUNCTION public.remove_collection_member(UUID, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.remove_collection_member(UUID, UUID) TO authenticated;
