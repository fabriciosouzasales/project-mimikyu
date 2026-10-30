/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5311 - Create get_collections_shared_with_me()
Versão......: 1.0
Status......: EXECUTADA / CANÔNICA. Aplicada no LIVE mimikyu-core (V1-12, autorização
              expressa do proprietário; ledger 20261030142448 `5311_create_get_collections_shared_with_me_function`).
              Idêntica ao arquivo de database/proposals/2026-10-30-v1-12-collection-sharing/
              (só este bloco Status difere); texto do ledger ≡ arquivo da proposta inteiro (md5).
              Validação: 5861 v1.3 51/51 PASS.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-30

Descrição...:
"Compartilhadas comigo": coleções em que o usuário da sessão é
participante ACTIVE.

Regras de Negócio:
- Só participações ACTIVE do próprio auth.uid() (PENDING fica na caixa de
  convites, 5309).
- Por coleção: nome, tipo, Set, nome de exibição do titular, estado,
  quantas cartas e progresso (5310). Nenhum local, valor ou exemplar.
- No máximo 100, aceitas mais recentemente primeiro.
================================================================
*/

CREATE OR REPLACE FUNCTION public.get_collections_shared_with_me()
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT coalesce(jsonb_agg(row_to_json(x)::jsonb ORDER BY x.accepted_at DESC, x.collection_id), '[]'::jsonb)
    FROM (
        SELECT c.id                AS collection_id,
               c.name              AS name,
               c.mode              AS mode,
               c.completion_policy AS completion_policy,
               c.lifecycle_status  AS lifecycle_status,
               c.cover_finish      AS cover_finish,
               cs.code::text       AS card_set_code,
               cs.name::text       AS card_set_name,
               owner.display_name  AS owner_display_name,
               m.responded_at      AS accepted_at,
               (SELECT count(*) FROM public.collection_allocation ca WHERE ca.collection_id = c.id) AS copies_count,
               s.total_positions, s.satisfied_positions, s.progress_percentage, s.is_complete
        FROM public.collection_membership m
        JOIN public.collection c       ON c.id = m.collection_id
        JOIN public.user_profile owner ON owner.id = c.owner_user_id
        LEFT JOIN public.collection_reference cr            ON cr.collection_id = c.id
        LEFT JOIN public.collection_card_set_reference ccsr ON ccsr.collection_reference_id = cr.id
        LEFT JOIN public.card_set cs                        ON cs.id = ccsr.card_set_id
        LEFT JOIN LATERAL public.collection_completion_summary_shared(c.id) s ON true
        WHERE (select auth.uid()) IS NOT NULL
          AND m.user_id = (select auth.uid())
          AND m.status = 'ACTIVE'
        ORDER BY m.responded_at DESC, c.id
        LIMIT 100
    ) x;
$$;

REVOKE ALL ON FUNCTION public.get_collections_shared_with_me() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_collections_shared_with_me() TO authenticated;
