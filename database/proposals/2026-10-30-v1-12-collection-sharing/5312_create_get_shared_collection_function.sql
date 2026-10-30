/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5312 - Create get_shared_collection()
Versão......: 1.1 (V1-12 PUBLIC BINDER EXPERIENCE: só participante)
Status......: PROPOSTA — NÃO EXECUTADA (V1-12) — depende de 5300–5302, 5310
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-30

Descrição...:
Cabeçalho da coleção para quem a vê sem ser titular: participante VIEWER
(C-145). Desde a v1.1 o visitante de coleção PUBLIC não usa esta leitura
(nem progresso nem galeria): a vitrine pública é o fichário (5317/5318).

Regras de Negócio:
- Acesso: collection_share_role() IN ('OWNER','VIEWER'); qualquer outro
  caso (PUBLIC sem participação, convite pendente/recusado, estranho) →
  NULL, indistinguível de coleção inexistente.
- Projeção mínima (C-157/C-158/C-159): nome, descrição, tipo, estado,
  visibilidade, Set, acabamento da capa, nome de exibição do titular,
  progresso (5310) e contagens. NUNCA: id/username/e-mail do titular,
  locais físicos, valores, aquisição, favoritos, wishlist, outras coleções,
  exemplares individuais.
- access: 'OWNER' | 'VIEWER' (a interface leva o titular para a página
  completa dele). membership_id só para VIEWER (botão "Sair").
- Só authenticated (anon sem EXECUTE).
================================================================
*/

CREATE OR REPLACE FUNCTION public.get_shared_collection(p_collection_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_role   TEXT;
    v_result JSONB;
BEGIN
    v_role := public.collection_share_role(p_collection_id);
    IF v_role IS NULL OR v_role NOT IN ('OWNER', 'VIEWER') THEN
        RETURN NULL;
    END IF;

    SELECT jsonb_build_object(
        'collection_id', c.id,
        'name', c.name,
        'description', c.description,
        'mode', c.mode,
        'completion_policy', c.completion_policy,
        'lifecycle_status', c.lifecycle_status,
        'visibility', c.visibility,
        'cover_finish', c.cover_finish,
        'card_set_code', cs.code,
        'card_set_name', cs.name,
        'card_set_logo_path', cs.logo_storage_path,
        'owner_display_name', owner.display_name,
        'access', v_role,
        'membership_id', CASE WHEN v_role = 'VIEWER' THEN (
            SELECT m.id FROM public.collection_membership m
            WHERE m.collection_id = c.id AND m.user_id = (select auth.uid()) AND m.status = 'ACTIVE'
        ) END,
        'copies_count', (SELECT count(*) FROM public.collection_allocation ca WHERE ca.collection_id = c.id),
        'total_positions', s.total_positions,
        'satisfied_positions', s.satisfied_positions,
        'progress_percentage', s.progress_percentage,
        'is_complete', s.is_complete
    )
    INTO v_result
    FROM public.collection c
    JOIN public.user_profile owner ON owner.id = c.owner_user_id
    LEFT JOIN public.collection_reference cr            ON cr.collection_id = c.id
    LEFT JOIN public.collection_card_set_reference ccsr ON ccsr.collection_reference_id = cr.id
    LEFT JOIN public.card_set cs                        ON cs.id = ccsr.card_set_id
    LEFT JOIN LATERAL public.collection_completion_summary_shared(c.id) s ON true
    WHERE c.id = p_collection_id;

    RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION public.get_shared_collection(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_shared_collection(UUID) TO authenticated;
