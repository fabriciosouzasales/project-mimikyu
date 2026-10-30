/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5317 - Create get_public_collection_binder()
Versão......: 1.0
Status......: EXECUTADA / CANÔNICA. Aplicada no LIVE mimikyu-core (V1-12, autorização
              expressa do proprietário; ledger 20261030142653 `5317_create_get_public_collection_binder_function`).
              Idêntica ao arquivo de database/proposals/2026-10-30-v1-12-collection-sharing/
              (só este bloco Status difere); texto do ledger ≡ arquivo da proposta inteiro (md5).
              Validação: 5861 v1.3 51/51 PASS.
              Corpo SUBSTITUÍDO no LIVE pela 5322 (mesma assinatura);
              este arquivo registra a versão de origem (md5 prosrc 989f749b…).
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-30

Descrição...:
Vitrine pública do Fichário Digital: capa, identidade visual e grade de
uma coleção PUBLICADA — sem sessão, por link compartilhável. Não é a
leitura do participante aberta para anon: autorização própria, pela
visibilidade, e resposta sanitizada para a vitrine.

Regras de Negócio:
- Autoriza SOMENTE coleção com visibility = 'PUBLIC' e lifecycle_status =
  'ACTIVE' (arquivar tira da vitrine sem precisar despublicar). Qualquer
  outro caso → NULL: privada, arquivada, inexistente — indistinguíveis
  (nenhuma enumeração por id revela existência).
- Não depende de auth.uid(): titular, participante e estranho recebem a
  mesma vitrine.
- Projeção (só o que a capa e a navegação precisam): nome da coleção,
  nome de exibição do titular, acabamento da capa, Set de referência
  (catálogo público: nome, código, logo), tipo (para o emblema Pokédex),
  nome próprio do fichário e marca MMKYU na contracapa, grade e número de
  páginas.
- NUNCA: progresso, contagens de cartas, galeria, descrição, username/id do
  titular, local físico, outras coleções do fichário (nem nome nem
  quantidade), participantes, ids de layout/página/bolso.
- Nome próprio do fichário só quando o fichário é DESTA coleção; em
  fichário de outra coleção (convidada) não sai nome de fichário — evita
  revelar o nome que o titular deu ao fichário de uma coleção não
  publicada.
- Sem fichário → has_binder = false (a interface mostra estado vazio; a
  galeria não é usada como substituta).
================================================================
*/

CREATE OR REPLACE FUNCTION public.get_public_collection_binder(p_collection_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_col     RECORD;
    v_layout  RECORD;
    v_own     BOOLEAN := false;
    v_pages   INTEGER := 0;
BEGIN
    IF p_collection_id IS NULL THEN
        RETURN NULL;
    END IF;

    SELECT c.id, c.name, c.completion_policy, c.cover_finish, owner.display_name AS owner_display_name
      INTO v_col
    FROM public.collection c
    JOIN public.user_profile owner ON owner.id = c.owner_user_id
    WHERE c.id = p_collection_id
      AND c.visibility = 'PUBLIC'
      AND c.lifecycle_status = 'ACTIVE';
    IF NOT FOUND THEN
        RETURN NULL;
    END IF;

    SELECT l.id, l.grid_columns, l.grid_rows, l.display_name, l.show_brand_mark INTO v_layout
    FROM public.collection_layout l
    WHERE l.collection_id = p_collection_id;
    IF FOUND THEN
        v_own := true;
    ELSE
        SELECT l.id, l.grid_columns, l.grid_rows, NULL::TEXT AS display_name, l.show_brand_mark INTO v_layout
        FROM public.collection_layout_guest g
        JOIN public.collection_layout l ON l.id = g.layout_id
        WHERE g.collection_id = p_collection_id;
    END IF;

    IF v_layout.id IS NOT NULL THEN
        SELECT count(*)::INTEGER INTO v_pages FROM public.collection_layout_page p WHERE p.layout_id = v_layout.id;
    END IF;

    RETURN jsonb_build_object(
        'collection_id', v_col.id,
        'name', v_col.name,
        'completion_policy', v_col.completion_policy,
        'cover_finish', v_col.cover_finish,
        'owner_display_name', v_col.owner_display_name,
        'card_set_code', (SELECT cs.code FROM public.collection_reference cr
                          JOIN public.collection_card_set_reference ccsr ON ccsr.collection_reference_id = cr.id
                          JOIN public.card_set cs ON cs.id = ccsr.card_set_id
                          WHERE cr.collection_id = v_col.id),
        'card_set_name', (SELECT cs.name FROM public.collection_reference cr
                          JOIN public.collection_card_set_reference ccsr ON ccsr.collection_reference_id = cr.id
                          JOIN public.card_set cs ON cs.id = ccsr.card_set_id
                          WHERE cr.collection_id = v_col.id),
        'card_set_logo_path', (SELECT cs.logo_storage_path FROM public.collection_reference cr
                          JOIN public.collection_card_set_reference ccsr ON ccsr.collection_reference_id = cr.id
                          JOIN public.card_set cs ON cs.id = ccsr.card_set_id
                          WHERE cr.collection_id = v_col.id),
        'has_binder', v_layout.id IS NOT NULL,
        'binder_name', CASE WHEN v_own THEN v_layout.display_name END,
        'show_brand_mark', coalesce(v_layout.show_brand_mark, true),
        'grid_columns', v_layout.grid_columns,
        'grid_rows', v_layout.grid_rows,
        'page_count', v_pages
    );
END;
$$;

REVOKE ALL ON FUNCTION public.get_public_collection_binder(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_public_collection_binder(UUID) TO anon, authenticated;
