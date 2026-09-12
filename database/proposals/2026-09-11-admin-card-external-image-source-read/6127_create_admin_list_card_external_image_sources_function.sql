/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 6127 - Create admin_list_card_external_image_sources() Function
Versão......: 1.1
Status......: CANÔNICA — CONFIRMADO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-11

Descrição...:
Function SECURITY DEFINER, READ-ONLY e ADMIN-ONLY que expõe o
MÍNIMO de `card_external_reference` necessário para a auditoria
de CDN (SOURCE-404-CDN-PROOF-04): a URL-base autoritativa da
imagem, por Card, no idioma solicitado.

Motivação (incidente real):
O smoke de XYP abortou com

    FALHA_LER_EXTERNAL_REFERENCE:
    permission denied for table card_external_reference

`card_external_reference` tem RLS = true, NENHUMA policy, e
SELECT concedido apenas a postgres/service_role. Isso é uma
fronteira de segurança CORRETA — a tabela carrega identidade de
origem de todo o catálogo. A correção NÃO é conceder SELECT a
`authenticated`, nem criar policy ampla, nem usar service_role
num script local: é uma via de leitura estreita e governada,
seguindo o padrão `admin_*` já consolidado no projeto
(ver 1061_create_admin_list_users_function.sql).

Regras de Negócio:
- Verifica public.is_admin() internamente; não-admin recebe
  RAISE EXCEPTION, NÃO uma lista vazia. Lista vazia seria pior
  que negar: o auditor interpretaria "sem identidade" e
  produziria INCONCLUSIVO silencioso em vez de erro.
- Nenhuma escrita. Nenhum DML. Nenhum bypass genérico da
  tabela — a function é a única superfície nova, e devolve
  apenas 3 colunas.
- Colunas retornadas e por quê:
    card_id          — chave de correlação com o universo do auditor;
    image_source_url — a URL-base autoritativa (o objetivo);
    external_card_id — evidência de diagnóstico. É o campo que
                       revela a divergência catálogo↔CDN dos
                       subsets (SWSH4.5SV/SWSH12.5GG/Trainer
                       Galleries). Sem ele, um achado de
                       `accessible_not_imported` não é
                       rastreável até a carta na origem.
  external_set_id é DELIBERADAMENTE OMITIDO. Expô-lo criaria a
  tentação de reconstruir o path da CDN a partir do código do
  Set — exatamente o erro que a evidência dos subsets prova ser
  falso (`swsh4.5sv` nunca existiu como diretório de assets).
  Omitindo-o, o auditor fica FISICAMENTE incapaz de derivar URL.
- Filtra referência ativa (is_active) e o idioma solicitado.
- Linhas com image_source_url NULL são omitidas: para o auditor,
  "existe linha sem URL" e "não existe linha" têm o mesmo
  significado — identidade insuficiente.
- Filtro por fonte: `p_asset_source_code` (default 'TCGDEX').
  Hoje 100% das 31.793 linhas são TCGDEX, mas image_source_url
  é específico da fonte; sem o filtro, uma segunda fonte futura
  devolveria URL de outro CDN para o mesmo Card. É filtro, não
  ampliação de exposição.
- Cap de lote: c_max_card_ids = 500, com RAISE EXCEPTION acima
  disso. O consumidor usa lotes de 200. Truncar em silêncio
  seria fail-closed no veredito (mais identity_insufficient =>
  INCONCLUSIVO), mas mentiria sobre a causa; falhar alto é
  preferível.
- p_card_ids NULL ou vazio devolve zero linhas, sem erro.

HARDENING-CORRECTION-01 — cap medido por cardinality(), não por
array_length(arr, 1):
  array_length() devolve o tamanho da PRIMEIRA dimensão. Num
  UUID[] multidimensional o cap era contornável — ARRAY[a, b]
  com 400 elementos cada tem array_length(.,1) = 2 (passa no
  teto de 500) e cardinality() = 800 (o custo real do
  `= ANY (...)`). Mesma classe já endurecida antes no projeto.
  Ordem canônica dos guards, TODA antes do SELECT/ANY:
    1. NULL ou cardinality = 0            -> RETURN (sem erro);
    2. array_ndims <> 1                   -> RAISE (ARRAY_NDIMS);
    3. v_count := cardinality(p_card_ids);
    4. v_count > c_max_card_ids           -> RAISE (BULK_LIMIT).
  O passo 1 precede o 2 de propósito: array vazio não tem
  dimensão, e array_ndims('{}') devolve NULL — checar ndims
  primeiro transformaria o caso legítimo "lote vazio" em erro.

Unicidade:
`uq_card_external_reference_card_source_language` UNIQUE
(card_id, asset_source_id, language_id) garante no máximo uma
linha por (Card, fonte, idioma) — não há necessidade de
DISTINCT ON nem de critério de desempate.

Tipos:
Todas as colunas de origem são TEXT/UUID nativos (verificado em
information_schema) — não há o risco de 42804 que exigiu o cast
explícito na revisão 1.1 da 1061.
================================================================
*/

CREATE OR REPLACE FUNCTION public.admin_list_card_external_image_sources(
    p_card_ids UUID[],
    p_language_code TEXT,
    p_asset_source_code TEXT DEFAULT 'TCGDEX'
)
RETURNS TABLE (
    card_id UUID,
    image_source_url TEXT,
    external_card_id TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    c_max_card_ids CONSTANT INT := 500;
    v_count INT;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'acesso restrito a administradores.';
    END IF;

    IF p_language_code IS NULL OR btrim(p_language_code) = '' THEN
        RAISE EXCEPTION 'ADMIN_LIST_CARD_EXTERNAL_IMAGE_SOURCES_LANGUAGE_REQUIRED: p_language_code é obrigatório.';
    END IF;

    IF p_asset_source_code IS NULL OR btrim(p_asset_source_code) = '' THEN
        RAISE EXCEPTION 'ADMIN_LIST_CARD_EXTERNAL_IMAGE_SOURCES_SOURCE_REQUIRED: p_asset_source_code é obrigatório.';
    END IF;

    -- HARDENING-CORRECTION-01 — guards de forma e de volume, nesta ordem,
    -- integralmente ANTES de qualquer SELECT/ANY sobre p_card_ids.

    -- (1) NULL ou vazio: caso legítimo, zero linhas, sem erro.
    --     Precede o teste de dimensão porque array_ndims('{}') é NULL.
    IF p_card_ids IS NULL OR COALESCE(cardinality(p_card_ids), 0) = 0 THEN
        RETURN;
    END IF;

    -- (2) Forma: exatamente unidimensional. Um UUID[] multidimensional
    --     contornaria o teto medido por array_length(.,1).
    IF array_ndims(p_card_ids) <> 1 THEN
        RAISE EXCEPTION
            'ADMIN_LIST_CARD_EXTERNAL_IMAGE_SOURCES_ARRAY_NDIMS: p_card_ids deve ser unidimensional (recebido ndims = %).',
            array_ndims(p_card_ids);
    END IF;

    -- (3) Volume real (cardinality, não array_length).
    v_count := cardinality(p_card_ids);

    -- (4) Teto.
    IF v_count > c_max_card_ids THEN
        RAISE EXCEPTION
            'ADMIN_LIST_CARD_EXTERNAL_IMAGE_SOURCES_BULK_LIMIT: % Card(s) recebidos; o teto por chamada é %.',
            v_count, c_max_card_ids;
    END IF;

    RETURN QUERY
    SELECT
        cer.card_id,
        cer.image_source_url,
        cer.external_card_id
    FROM public.card_external_reference cer
    JOIN public.language lang       ON lang.id = cer.language_id
    JOIN public.asset_source src    ON src.id  = cer.asset_source_id
    WHERE cer.card_id = ANY (p_card_ids)
      AND cer.is_active IS TRUE
      AND cer.image_source_url IS NOT NULL
      AND lang.code = p_language_code
      AND src.code  = p_asset_source_code;
END;
$$;

COMMENT ON FUNCTION public.admin_list_card_external_image_sources(UUID[], TEXT, TEXT) IS
'READ-ONLY, ADMIN-ONLY. Única via governada de leitura de card_external_reference.image_source_url. Não expõe external_set_id, por desenho: impede reconstrução de path de CDN a partir do código do Set. Ver SOURCE-404-CDN-PROOF-04.';

REVOKE ALL ON FUNCTION public.admin_list_card_external_image_sources(UUID[], TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_list_card_external_image_sources(UUID[], TEXT, TEXT) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_list_card_external_image_sources(UUID[], TEXT, TEXT) TO authenticated;
