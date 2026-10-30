/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5326 - Create get_shared_collection_binder_images() (porta do participante)
Versão......: 1.0
Status......: EXECUTADA / CANÔNICA. Aplicada no LIVE mimikyu-core (V1-12, autorização
              expressa do proprietário; ledger 20261030201046 `5326_create_get_shared_collection_binder_images_function`).
              Idêntica ao arquivo de database/proposals/2026-10-30-v1-12-shared-binder-visual-assets/
              (só este bloco Status difere); texto do ledger ≡ corpo após o cabeçalho (md5).
              Validação: 5863 v1.2 37/37 PASS, resíduo zero.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-30

Descrição...:
Imagens decorativas das páginas pedidas do fichário, para o titular e o
participante VIEWER ACTIVE — mesma fronteira e mesmo erro da 5316
(páginas mascaradas). Complementa a 5316 sem alterá-la.

Regras:
- collection_share_role (5302) ∈ {OWNER, VIEWER} ANTES de qualquer leitura;
  pendente, recusado, removido, estranho, PUBLIC sem participação →
  COLLECTION_NOT_FOUND (P0002), indistinguível de inexistente.
- Conteúdo = núcleo 5325 (só fichário da coleção dona; convidada → vazio).
- Devolve o caminho no bucket privado `binder-slot-image`; o app assina a
  URL com a sessão do próprio participante, autorizada pela política
  escopada da 5329. Sem política, a assinatura falha e o bolso fica vazio.

Segurança: SECURITY DEFINER, STABLE, search_path '', EXECUTE só
authenticated. Sem escrita.
Como validar: 5863 (seções S, I, N, R).
================================================================
*/

CREATE OR REPLACE FUNCTION public.get_shared_collection_binder_images(
    p_collection_id UUID,
    p_first_page    INTEGER,
    p_page_count    INTEGER
)
RETURNS TABLE (
    page_number  INTEGER,
    row_index    INTEGER,
    column_index INTEGER,
    height       INTEGER,
    width        INTEGER,
    is_region    BOOLEAN,
    storage_path TEXT,
    focal_x      SMALLINT,
    focal_y      SMALLINT,
    updated_at   TIMESTAMPTZ
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_role TEXT;
BEGIN
    v_role := public.collection_share_role(p_collection_id);
    IF v_role IS NULL OR v_role NOT IN ('OWNER', 'VIEWER') THEN
        RAISE EXCEPTION 'COLLECTION_NOT_FOUND' USING ERRCODE = 'P0002';
    END IF;
    RETURN QUERY SELECT * FROM public.collection_binder_shared_images(p_collection_id, p_first_page, p_page_count);
END;
$$;

COMMENT ON FUNCTION public.get_shared_collection_binder_images(UUID, INTEGER, INTEGER) IS
  'V1-12 (Query 5326): imagens decorativas (bolso e mesclagem) do fichário para titular/VIEWER ACTIVE (5302). Só fichário da coleção dona. Sem acesso → COLLECTION_NOT_FOUND.';

REVOKE ALL ON FUNCTION public.get_shared_collection_binder_images(UUID, INTEGER, INTEGER) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_shared_collection_binder_images(UUID, INTEGER, INTEGER) TO authenticated;
