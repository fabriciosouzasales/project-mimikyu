/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5306 - Create leave_shared_collection()
Versão......: 1.0
Status......: PROPOSTA — NÃO EXECUTADA (V1-12)
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-30

Descrição...:
Participante sai voluntariamente de uma coleção compartilhada (C-154/C-155).

Regras de Negócio:
- Só a própria participação ACTIVE de auth.uid(). Titular nunca sai por
  aqui (não tem linha — C-156). Sem participação → NOT_A_MEMBER.
- DELETE: acesso revogado na mesma transação; para voltar, só um novo
  convite do titular.
================================================================
*/

CREATE OR REPLACE FUNCTION public.leave_shared_collection(p_collection_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_user UUID := auth.uid();
BEGIN
    IF v_user IS NULL THEN
        RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '28000';
    END IF;

    DELETE FROM public.collection_membership m
    WHERE m.collection_id = p_collection_id
      AND m.user_id = v_user
      AND m.status = 'ACTIVE';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'NOT_A_MEMBER' USING ERRCODE = 'P0002';
    END IF;

    RETURN jsonb_build_object('outcome', 'LEFT');
END;
$$;

REVOKE ALL ON FUNCTION public.leave_shared_collection(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.leave_shared_collection(UUID) TO authenticated;
