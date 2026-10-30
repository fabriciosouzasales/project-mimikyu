/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5304 - Create respond_collection_invite()
Versão......: 1.0
Status......: PROPOSTA — NÃO EXECUTADA (V1-12)
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-30

Descrição...:
O convidado aceita (PENDING → ACTIVE) ou recusa (PENDING → DECLINED) um
convite seu (C-153: aceitação explícita, nunca silenciosa).

Regras de Negócio:
- Só o próprio convidado (m.user_id = auth.uid()). Convite alheio,
  inexistente, cancelado ou removido → INVITE_NOT_FOUND (indistinguíveis).
- Idempotente: aceitar o que já está ACTIVE → UNCHANGED; recusar o que já
  está DECLINED → UNCHANGED. Aceitar um DECLINED não reabre (só um novo
  convite do titular reabre) → INVITE_NOT_FOUND.
- UPDATE condicionado ao estado (WHERE status = 'PENDING'): duas abas
  respondendo ao mesmo tempo produzem um único efeito.
================================================================
*/

CREATE OR REPLACE FUNCTION public.respond_collection_invite(
    p_membership_id UUID,
    p_accept BOOLEAN
)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_user    UUID := auth.uid();
    v_target  TEXT := CASE WHEN p_accept THEN 'ACTIVE' ELSE 'DECLINED' END;
    v_row     public.collection_membership%ROWTYPE;
BEGIN
    IF v_user IS NULL THEN
        RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '28000';
    END IF;
    IF p_accept IS NULL THEN
        RAISE EXCEPTION 'INVALID_RESPONSE' USING ERRCODE = '22023';
    END IF;

    UPDATE public.collection_membership m
    SET status = v_target,
        responded_at = now()
    WHERE m.id = p_membership_id
      AND m.user_id = v_user
      AND m.status = 'PENDING'
    RETURNING * INTO v_row;

    IF FOUND THEN
        RETURN jsonb_build_object('outcome', v_target, 'membership_id', v_row.id, 'collection_id', v_row.collection_id);
    END IF;

    SELECT * INTO v_row
    FROM public.collection_membership m
    WHERE m.id = p_membership_id
      AND m.user_id = v_user;

    IF FOUND AND v_row.status = v_target THEN
        RETURN jsonb_build_object('outcome', 'UNCHANGED', 'membership_id', v_row.id, 'collection_id', v_row.collection_id);
    END IF;

    RAISE EXCEPTION 'INVITE_NOT_FOUND' USING ERRCODE = 'P0002';
END;
$$;

REVOKE ALL ON FUNCTION public.respond_collection_invite(UUID, BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.respond_collection_invite(UUID, BOOLEAN) TO authenticated;
