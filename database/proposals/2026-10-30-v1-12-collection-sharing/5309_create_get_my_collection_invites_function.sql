/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5309 - Create get_my_collection_invites()
Versão......: 1.0
Status......: PROPOSTA — NÃO EXECUTADA (V1-12)
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-30

Descrição...:
Caixa de convites do usuário da sessão (convites PENDING para ele), sem
infraestrutura de notificação (C-153: notificações fora de escopo).

Regras de Negócio:
- Só convites do próprio auth.uid().
- Antes do aceite, o convidado vê apenas o necessário para decidir: nome
  da coleção, tipo, Set (se houver), nome de exibição e username do
  titular e a data do convite. Nenhuma carta, progresso, local ou valor.
- No máximo 50, mais recentes primeiro.
================================================================
*/

CREATE OR REPLACE FUNCTION public.get_my_collection_invites()
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT coalesce(jsonb_agg(row_to_json(x)::jsonb ORDER BY x.invited_at DESC, x.membership_id), '[]'::jsonb)
    FROM (
        SELECT m.id                 AS membership_id,
               c.id                 AS collection_id,
               c.name               AS collection_name,
               c.mode               AS mode,
               c.completion_policy  AS completion_policy,
               cs.name::text        AS card_set_name,
               owner.display_name   AS owner_display_name,
               owner.username       AS owner_username,
               m.invited_at         AS invited_at
        FROM public.collection_membership m
        JOIN public.collection c         ON c.id = m.collection_id
        JOIN public.user_profile owner   ON owner.id = c.owner_user_id
        LEFT JOIN public.collection_reference cr            ON cr.collection_id = c.id
        LEFT JOIN public.collection_card_set_reference ccsr ON ccsr.collection_reference_id = cr.id
        LEFT JOIN public.card_set cs                        ON cs.id = ccsr.card_set_id
        WHERE (select auth.uid()) IS NOT NULL
          AND m.user_id = (select auth.uid())
          AND m.status = 'PENDING'
        ORDER BY m.invited_at DESC, m.id
        LIMIT 50
    ) x;
$$;

REVOKE ALL ON FUNCTION public.get_my_collection_invites() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_collection_invites() TO authenticated;
