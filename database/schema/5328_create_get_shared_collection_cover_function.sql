/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5328 - Create get_shared_collection_cover() (capa enviada)
Versão......: 1.0
Status......: EXECUTADA / CANÔNICA. Aplicada no LIVE mimikyu-core (V1-12, autorização
              expressa do proprietário; ledger 20261030201100 `5328_create_get_shared_collection_cover_function`).
              Idêntica ao arquivo de database/proposals/2026-10-30-v1-12-shared-binder-visual-assets/
              (só este bloco Status difere); texto do ledger ≡ corpo após o cabeçalho (md5).
              Validação: 5863 v1.2 37/37 PASS, resíduo zero.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-30

Descrição...:
Capa personalizada da PRÓPRIA coleção autorizada: imagem enviada
(`cover_logo_path`, bucket privado `collection-cover`, 5176/5177) e código
da capa (`cover_code`, 5179). É personalização da coleção, não do fichário
— vale para coleção dona ou convidada (nunca lê a capa de outra coleção).

Acesso (uma linha ou nenhuma, nunca erro — a capa é decorativa):
- titular ou VIEWER ACTIVE (collection_share_role ∈ {OWNER, VIEWER});
- visitante: coleção PUBLIC e ACTIVE.
Qualquer outro caso → zero linhas (indistinguível de "sem capa").

Segurança: SECURITY DEFINER, STABLE, search_path '', EXECUTE para anon e
authenticated. Sem escrita. A URL é assinada pelo próprio leitor,
autorizada pela política escopada da 5329.
Como validar: 5863 (seção C).
================================================================
*/

CREATE OR REPLACE FUNCTION public.get_shared_collection_cover(p_collection_id UUID)
RETURNS TABLE (
    cover_logo_path TEXT,
    cover_code      TEXT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT c.cover_logo_path::TEXT, c.cover_code::TEXT
    FROM public.collection c
    WHERE c.id = p_collection_id
      AND (
            public.collection_share_role(c.id) IN ('OWNER', 'VIEWER')
         OR (c.visibility = 'PUBLIC' AND c.lifecycle_status = 'ACTIVE')
      );
$$;

COMMENT ON FUNCTION public.get_shared_collection_cover(UUID) IS
  'V1-12 (Query 5328): capa enviada e código da capa da própria coleção, para titular/VIEWER ACTIVE ou visitante de coleção PUBLIC e ACTIVE. Sem acesso → zero linhas.';

REVOKE ALL ON FUNCTION public.get_shared_collection_cover(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_shared_collection_cover(UUID) TO anon, authenticated;
