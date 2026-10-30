/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5329 - Leitura escopada de imagens do fichário e capa enviada
              (Storage) para participante VIEWER e vitrine pública
Versão......: 1.1 (SECURITY READINESS-01: exige que o arquivo esteja na pasta
              do titular da coleção autorizada — defesa em profundidade além
              dos gatilhos/RPCs que já impedem vincular arquivo alheio)
Status......: EXECUTADA / CANÔNICA. Aplicada no LIVE mimikyu-core (V1-12, autorização
              expressa do proprietário; ledger 20261030201118 `5329_create_shared_visual_asset_storage_policies`).
              Idêntica ao arquivo de database/proposals/2026-10-30-v1-12-shared-binder-visual-assets/
              (só este bloco Status difere); texto do ledger ≡ corpo após o cabeçalho (md5).
              Validação: 5863 v1.2 37/37 PASS (após 5331), resíduo zero.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-30

Descrição...:
Os buckets `binder-slot-image` e `collection-cover` são privados e só têm
SELECT para a pasta do próprio dono (5231, 5176). O participante e o
visitante não conseguem gerar URL assinada → as imagens não aparecem.
Esta migration acrescenta UMA política SELECT por bucket, escopada objeto
a objeto por uma função de decisão; as políticas do dono ficam intactas.

Regra (deny by default; um objeto por vez):
  binder-slot-image — o objeto só é legível se for o arquivo VINCULADO a
    um bolso (5232) ou a uma mesclagem (5239) de um fichário cuja coleção
    DONA (`collection_layout.collection_id`) é:
      a) compartilhada com o leitor (collection_membership ACTIVE), ou
      b) PUBLIC e ACTIVE.
    Coleção convidada não abre nada (mesma regra da 5325). Arquivo solto
    (envio abandonado, ainda não vinculado) nunca é legível por terceiros.
  collection-cover — o objeto só é legível se for exatamente o
    `cover_logo_path` atual da coleção indicada no próprio caminho
    (`<dono>/<coleção>/<arquivo>`) e essa coleção satisfizer a) ou b).
    Capa antiga substituída deixa de ser legível na hora.

Não concede: INSERT, UPDATE, DELETE, listagem de arquivos não vinculados,
leitura de outros buckets, leitura por convite PENDING/DECLINED, por
participante removido ou por estranho. Listagem (storage list) devolve só
objetos que passariam pela mesma regra — nunca o conteúdo privado.

Função de decisão `shared_visual_asset_readable(bucket, name)`:
SECURITY DEFINER (lê tabelas sem política para API), STABLE,
search_path '', EXECUTE para anon e authenticated (exigido para a
avaliação da política no papel do leitor — mesmo padrão de
binder_slot_image_path_is_linked, 5232). Devolve só booleano: como
oráculo, responde "sim" apenas para o que o próprio leitor já pode ver.
COST alto para o planejador avaliar `bucket_id = …` antes.

Revogação: decidida a cada assinatura. Remover participante, despublicar,
arquivar a coleção pública, trocar/remover a capa ou retirar a imagem do
bolso → a próxima assinatura falha. URLs já assinadas valem até expirar
(o app usa 10 min para terceiros) e o navegador pode manter a imagem em
cache — limite documentado no README §6.

Custo: caminho de bolso/mesclagem via UNIQUE(storage_path) (5232/5239);
capa via PK da coleção (uuid extraído do caminho validado por regex) +
comparação exata; participação via PK/índice de collection_membership.
Como validar: 5863 (seções ST, N, R).
Reversão: DROP POLICY ×2 + DROP FUNCTION (ROLLBACK no README §8).
================================================================
*/

CREATE OR REPLACE FUNCTION public.shared_visual_asset_readable(p_bucket TEXT, p_name TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
COST 1000
AS $$
    WITH owner_collection AS (
        -- binder-slot-image: coleção DONA do fichário onde o arquivo está vinculado
        SELECT l.collection_id
        FROM public.collection_layout_slot_image i
        JOIN public.collection_layout_slot s  ON s.id = i.slot_id
        JOIN public.collection_layout_page pg ON pg.id = s.page_id
        JOIN public.collection_layout l       ON l.id = pg.layout_id
        WHERE p_bucket = 'binder-slot-image'
          AND i.storage_path = p_name
        UNION ALL
        SELECT l.collection_id
        FROM public.collection_layout_region_image ri
        JOIN public.collection_layout_region rg ON rg.id = ri.region_id
        JOIN public.collection_layout_page pg   ON pg.id = rg.page_id
        JOIN public.collection_layout l         ON l.id = pg.layout_id
        WHERE p_bucket = 'binder-slot-image'
          AND ri.storage_path = p_name
        UNION ALL
        -- collection-cover: a coleção do próprio caminho, se a capa ATUAL for este arquivo
        SELECT c.id
        FROM public.collection c
        WHERE p_bucket = 'collection-cover'
          AND c.id = CASE
                       WHEN p_name ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(png|jpg|webp)$'
                       THEN split_part(p_name, '/', 2)::UUID
                     END
          AND c.cover_logo_path = p_name
    )
    SELECT EXISTS (
        SELECT 1
        FROM owner_collection oc
        JOIN public.collection c ON c.id = oc.collection_id
        WHERE split_part(p_name, '/', 1) = c.owner_user_id::TEXT   -- defesa: só arquivo na pasta do próprio titular
          AND (
               (c.visibility = 'PUBLIC' AND c.lifecycle_status = 'ACTIVE')
           OR ((SELECT auth.uid()) IS NOT NULL AND EXISTS (
                SELECT 1 FROM public.collection_membership m
                WHERE m.collection_id = c.id
                  AND m.user_id = (SELECT auth.uid())
                  AND m.status = 'ACTIVE'))
          )
    );
$$;

COMMENT ON FUNCTION public.shared_visual_asset_readable(TEXT, TEXT) IS
  'V1-12 (Query 5329): decide, objeto a objeto, se o leitor (VIEWER ACTIVE ou visitante de coleção PUBLIC+ACTIVE) pode ler uma imagem vinculada ao fichário da coleção DONA ou a capa atual da coleção. Usada só pelas políticas SELECT escopadas de storage.objects.';

REVOKE ALL ON FUNCTION public.shared_visual_asset_readable(TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.shared_visual_asset_readable(TEXT, TEXT) TO anon, authenticated;

CREATE POLICY binder_slot_image_select_shared
  ON storage.objects
  FOR SELECT
  TO anon, authenticated
  USING (
    bucket_id = 'binder-slot-image'
    AND public.shared_visual_asset_readable(bucket_id, name)
  );

CREATE POLICY collection_cover_select_shared
  ON storage.objects
  FOR SELECT
  TO anon, authenticated
  USING (
    bucket_id = 'collection-cover'
    AND public.shared_visual_asset_readable(bucket_id, name)
  );
