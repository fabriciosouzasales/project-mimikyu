/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5308 - Create get_my_collection_sharing()
Versão......: 1.0
Status......: PROPOSTA — NÃO EXECUTADA (V1-12)
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-30

Descrição...:
Painel "Compartilhar" do titular: visibilidade e participações da coleção.

Regras de Negócio:
- Só o titular; qualquer outro caso → NULL (não distingue inexistente de
  alheia).
- Por participante: só username, display_name, papel, estado e datas — nada
  de id de usuário, e-mail ou outra informação de conta.
- Ordem: participantes, convites pendentes, recusados; mais recentes
  primeiro. Limite natural de 50 PENDING+ACTIVE (5303) + recusados.
================================================================
*/

CREATE OR REPLACE FUNCTION public.get_my_collection_sharing(p_collection_id UUID)
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT jsonb_build_object(
        'visibility', c.visibility,
        'lifecycle_status', c.lifecycle_status,
        'members', coalesce((
            SELECT jsonb_agg(jsonb_build_object(
                       'membership_id', m.id,
                       'username', up.username,
                       'display_name', up.display_name,
                       'role', m.role,
                       'status', m.status,
                       'invited_at', m.invited_at,
                       'responded_at', m.responded_at
                   ) ORDER BY CASE m.status WHEN 'ACTIVE' THEN 0 WHEN 'PENDING' THEN 1 ELSE 2 END,
                              coalesce(m.responded_at, m.invited_at) DESC, m.id)
            FROM public.collection_membership m
            JOIN public.user_profile up ON up.id = m.user_id
            WHERE m.collection_id = c.id
        ), '[]'::jsonb)
    )
    FROM public.collection c
    WHERE c.id = p_collection_id
      AND (select auth.uid()) IS NOT NULL
      AND c.owner_user_id = (select auth.uid());
$$;

REVOKE ALL ON FUNCTION public.get_my_collection_sharing(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_collection_sharing(UUID) TO authenticated;
