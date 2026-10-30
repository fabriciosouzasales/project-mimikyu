# V1-12 — SHARED BINDER VISUAL ASSETS-01 (proposta)

| Campo | Valor |
|---|---|
| Status | **5325–5329 v1.1 APLICADAS NO LIVE (2026-10-30, LIVE ROLLOUT — VISUAL ASSETS & PUBLIC SET LOGO); VALIDAÇÃO PENDENTE.** Ledger `20261030200919`…`20261030201118`; corpos LIVE ≡ arquivos (md5 do corpo 5/5). **5863 v1.2 (vírgula do S.4 removida; 99.1 descrito como 10 contagens) EXECUTADA UMA VEZ — GATE FAIL 20/21 (esperado 37), 99.1 PASS (resíduo zero).** 19 casos PASS até C.3; abortou em SO.2 com `42501 permission denied for function is_admin`. Causa pré-existente (não introduzida por 5325–5329): as políticas `card_set_logo_admin_select` e `expansion_logo_admin_select` (papel `public`) avaliam `(SELECT is_admin())` e `anon` não tem EXECUTE em `is_admin()` → **todo SELECT de `anon` em `storage.objects` falha**, em qualquer bucket (provado read-only em avatars, binder-slot-image e card-set-logo). Consequência: a leitura pela vitrine (anon) prevista em 5329 e 5330 não funciona até a decisão do proprietário. **Resolvido por 5331 (STORAGE POLICY CORRECTION-01, alternativa A): `card_set_logo_admin_select` e `expansion_logo_admin_select` passam de `public` para `authenticated` via `ALTER POLICY ... TO` (USING inalterado; demais 24 políticas com assinatura idêntica; `is_admin()` sem EXECUTE para anon), ledger `20261030202408`. Reexecução única da 5863 v1.2: GATE PASS 37/37, 99.1 PASS (resíduo zero).** Pacote B (5330/5864) aguarda decisão separada. **Promovidas para `database/schema/` (5325–5329, 5331) em V1-12 FINAL SCHEMA RECONCILIATION & VISUAL HANDOFF** — ledger ≡ proposta (md5 6/6); só o bloco Status difere; estes arquivos permanecem como evidência histórica. Homologação visual: `../2026-10-30-v1-12-viewer-parity/HOMOLOGATION.md` §H. |
| Data | 2026-10-30 |
| Autoridade | C-198 (imagem pertence ao bolso/fichário), regra de identidade V1-12 (5321/5322: convidada não herda nada do fichário dono), C-157–C-162 (privacidade) |
| Frontend | implementado localmente, tolerante à ausência destas funções (sem elas: comportamento atual, bolsos vazios) |

## 1. Causa exata

1. **Leitura:** nenhum contrato do participante ou da vitrine devolve imagens. O núcleo mascarado (5315) só conhece carta/reserva/vazio; imagens de bolso (5232) e de mesclagem (5239) só saem por `get_my_collection_binder_slot_images`/`_region_images` (5234/5241), que exigem ser o dono da coleção. A capa enviada (`cover_logo_path`, 5177) não aparece em 5312/5317.
2. **Arquivo:** os buckets `binder-slot-image` e `collection-cover` são privados e só têm SELECT para a pasta do próprio dono (5231, 5176). Mesmo com o caminho, o participante/visitante não consegue gerar URL assinada.

(O projeto não usa `service_role` no app — a assinatura é sempre feita pela sessão do próprio leitor.)

## 2. Como as personalizações se ligam ao fichário e às coleções

| Personalização | Onde mora | Pertence a | Arquivo |
|---|---|---|---|
| Imagem de bolso | `collection_layout_slot_image` (1 por bolso, exclusiva com carta/reserva/fixação/mesclagem) | bolso → página → **fichário** (C-198) | `binder-slot-image/<dono>/<fichário>/<uuid>.(webp\|jpg)`, UNIQUE |
| Imagem em vários bolsos | `collection_layout_region` (retângulo; hoje 1×2) + `collection_layout_region_image` (focal x/y) | região → página → **fichário** | mesmo bucket e pasta, UNIQUE, exclusiva com imagem de bolso |
| Capa enviada | `collection.cover_logo_path` (+ `cover_code`) | **coleção** | `collection-cover/<dono>/<coleção>/<uuid>.(png\|jpg\|webp)` |

O fichário tem uma coleção **dona** (`collection_layout.collection_id`) e zero ou mais **convidadas** (`collection_layout_guest`, todas do mesmo titular). Imagens não registram coleção: pertencem ao fichário inteiro.

## 3. Regra de negócio (menor possível, sem fallback)

- **Coleção dona compartilhada/pública:** compartilhar a coleção compartilha a apresentação do seu fichário → imagens de bolso e mesclagens visíveis, com posição, recorte e enquadramento.
- **Coleção convidada compartilhada/pública:** o modelo não diz se uma imagem do fichário se refere à convidada ou a outra coleção → **nenhuma imagem** (bolso vazio, como hoje). Mesma regra já aprovada para nome e logomarca.
- **Capa:** sempre a da **própria** coleção autorizada (dona ou convidada); nunca a de outra.
- Cartas e reservas: mascaramento 5315 intacto.

**Extensão futura, se o produto quiser imagens na convidada** (não proposta aqui): atribuir a imagem a uma coleção (`collection_id` em 5232/5239, padrão = dona; escrita pela coleção que a inseriu) e filtrar por ela. Exige decisão de produto e migração dos dados existentes.

## 4. Arquivos

| Arquivo | O quê | Grants |
|---|---|---|
| `5325` | `collection_binder_shared_images(collection, página, n)` — núcleo interno: imagens das ≤ 4 páginas, só do fichário da coleção dona, sem ids internos | nenhum (interna) |
| `5326` | `get_shared_collection_binder_images` — porta do participante (OWNER/VIEWER ACTIVE, 5302); senão `COLLECTION_NOT_FOUND` | authenticated |
| `5327` | `get_public_collection_binder_images` — porta da vitrine (PUBLIC + ACTIVE); senão `COLLECTION_NOT_FOUND` | anon, authenticated |
| `5328` | `get_shared_collection_cover` — caminho e código da capa da própria coleção (OWNER/VIEWER ou PUBLIC+ACTIVE); senão zero linhas | anon, authenticated |
| `5329` v1.1 | `shared_visual_asset_readable(bucket, name)` (exige também que o arquivo esteja na pasta do titular) + 2 políticas SELECT escopadas (`binder_slot_image_select_shared`, `collection_cover_select_shared`) | função: anon, authenticated; políticas: anon, authenticated, só SELECT |
| `5863` v1.1 | harness: fixture efêmera + sentinela MS863, **37** verificações + GATE (inclui RLS real de `storage.objects`: listagem e escrita), resíduo zero | — |

Formato de saída de 5326/5327: `page_number, row_index, column_index, height, width, is_region, storage_path, focal_x, focal_y, updated_at` (bolso = 1×1 com `focal_x` 50).

## 5. Segurança

- **Deny by default, objeto a objeto.** A política só libera um arquivo se ele for exatamente o vinculado a um bolso/mesclagem do fichário de uma coleção dona autorizada ao leitor (membership ACTIVE ou PUBLIC+ACTIVE), ou a capa **atual** da coleção autorizada. Arquivo solto (envio abandonado), capa antiga, outro bucket, caminho inventado → negado.
- **Listagem:** `storage.search`, `search_v2` e `list_objects_with_delimiter` são SECURITY INVOKER (conferido no LIVE) e não há tabela `storage.prefixes` → a listagem passa pela mesma RLS: o leitor lista **somente** os objetos que já pode ler (exatamente bolso + mesclagem + capa atual autorizados — provado em 5863 SO.1/SO.4); arquivos soltos, capas antigas e pastas de outros fichários não aparecem. A assinatura de URL lê **um objeto específico** (SELECT por `bucket_id` + `name`); não depende de permissão de listagem. Não há como restringir "assinar sim, listar não" com uma política SELECT; o escopo mínimo seguro é o atual (listar = ver os mesmos objetos autorizados).
- **Escrita:** nenhuma política nova de INSERT/UPDATE/DELETE. RLS real provada: VIEWER faz UPDATE 0 linhas, DELETE 0 linhas (com a trava `protect_delete` desligada para isolar a RLS) e INSERT na pasta da titular → 42501 (5863 SO.3). Toda política de escrita dos dois buckets exige a pasta do próprio usuário (5863 S.4).
- **Arquivo alheio:** além dos gatilhos/RPCs que já impedem vincular arquivo de outro usuário (5232/5239/5178), a 5329 v1.1 exige que o arquivo esteja na pasta do titular da coleção autorizada (dados LIVE conferidos: 2/2 mesclagens e 2/2 capas já satisfazem).
- **Nenhum acesso genérico:** sem INSERT/UPDATE/DELETE novos; políticas do dono intactas (5863 S.4).
- **Negados:** convite pendente, recusado, participante removido, estranho, anon em coleção privada (5863 N.*, C.2, C.3).
- **Fichário com várias coleções:** ser VIEWER de uma convidada nunca abre imagens do fichário dono (5863 I.2, R.2, PB.2).
- **Caminhos expostos:** a URL assinada contém o caminho (`<dono>/<fichário>/<uuid>`). O caminho sozinho não dá acesso a nada (a política decide por objeto); não há ids de bolso/região/coleção dona no retorno das portas (5863 S.5).
- **Oráculo:** `shared_visual_asset_readable` é executável por anon/authenticated (exigido para a política). Responde só "posso ler este objeto?" — "sim" apenas para o que o leitor já pode ver.

## 6. Revogação, URLs assinadas e cache (limite documentado)

- Autorização decidida **a cada assinatura**: remover participante, despublicar, arquivar a coleção pública, trocar/remover a capa ou retirar a imagem do layout → a próxima assinatura falha na hora (5863 R.1, PB.3, PB.4, RM.1).
- **URL já entregue continua válida até expirar.** O app passa a usar **10 min** para terceiros (`SHARED_VISUAL_URL_TTL`; o titular segue com 1 h). Assinaturas da Supabase não são revogáveis individualmente.
- **Cache do navegador:** os arquivos foram enviados com `cacheControl: 3600` (LIVE: 4/4 objetos `max-age=3600`). Uma imagem já baixada pode continuar no cache local por até 1 h. Não há promessa de revogação instantânea do que já chegou ao navegador.
- **Proporcional ao risco:** imagens decorativas, não patrimônio. Reduzir o `cacheControl` de envios futuros (ex.: 600) é opcional e só afeta arquivos novos; não proposto nesta rodada.

## 7. Performance

- Uma chamada de imagens por lote de **4 páginas**, em paralelo com a leitura das páginas (sem latência serial); uma única chamada `createSignedUrls` por lote (não por bolso).
- Banco: bolsos/regiões das ≤ 4 páginas (índices por `page_id`), PK das tabelas de imagem; política por `UNIQUE(storage_path)` e PK da coleção (uuid tirado do caminho). Nada lê o Storage para montar a tela.
- Imagens `loading="lazy"` (exceto as prioritárias), mesmo componente do titular; paginação e carregamento sob demanda inalterados.
- `COST 1000` na função da política para o planejador avaliar `bucket_id = …` primeiro.

## 8. Procedimento LIVE (somente após autorização explícita)

**Sequência exata (pacote A — personalizações):**

1. Pré-checagem só leitura — STOP se qualquer item falhar:
   - ledger com 5300–5322 e sem 5325+;
   - `get_shared_collection_binder` md5(prosrc) `cfce8495…`, `get_public_collection_binder` `d81891c7…` (5321/5322 intactas);
   - tabelas `collection_layout_slot_image`, `collection_layout_region_image`, `collection_membership`; colunas `cover_logo_path`, `cover_code`;
   - nenhuma das funções/políticas 5325–5329 existe; políticas nos dois buckets = 7; `postgres` com BYPASSRLS (fixture do 5863);
   - sha256 dos arquivos = §10.
2. Aplicar, uma migration por arquivo (corpo após o cabeçalho), nesta ordem: `5325` → `5326` → `5327` → `5328` → `5329`. Falha em qualquer uma → STOP (sem correção nem rollback automático).
3. Pós-checagem só leitura: 5 funções com definer/search_path vazio e grants da §4; 2 políticas novas só SELECT para anon/authenticated; políticas dos dois buckets = 9.
4. Executar `5863` v1.1 **uma vez**. Critério de PASS: `GATE PASS 37/37` **e** `99.1 PASS` (10 contagens iguais, inclusive `storage.objects` dos dois buckets). Qualquer FAIL → STOP, reportar, sem reexecução nem rollback automático.
5. Homologação visual H.1–H.6 (`../2026-10-30-v1-12-viewer-parity/HOMOLOGATION.md`).

**Pacote B — logo do Set na vitrine** (`../2026-10-30-card-set-logo-public-read/`), independente, autorização própria: `5330` → `5864` (`GATE PASS 7/7`).

**Interrupção:** divergência no precheck; erro em qualquer migration; gate ≠ N/N; 99.1 FAIL; qualquer erro inesperado (X.1) no harness.

**Rollback manual, se decidido:** `DROP POLICY binder_slot_image_select_shared ON storage.objects; DROP POLICY collection_cover_select_shared ON storage.objects; DROP FUNCTION public.shared_visual_asset_readable(text,text), public.get_shared_collection_cover(uuid), public.get_public_collection_binder_images(uuid,integer,integer), public.get_shared_collection_binder_images(uuid,integer,integer), public.collection_binder_shared_images(uuid,integer,integer);` O frontend volta sozinho ao estado atual (bolsos vazios).

## 9. Fora do escopo (achados)

- **Logo do Set na vitrine:** proposta independente em `../2026-10-30-card-set-logo-public-read/` (5330 + 5864) — não incluída em 5325–5329.
- Bolso de imagem/mesclagem no modo leitura continua focável com "Enter para ver" sem abrir nada (mesmo comportamento já homologado dos bolsos vazios do VIEWER). Visualização ampliada para terceiros é incremento próprio.
- Wrappers 5323/5324, EDITOR (V1-13): não tocados.

## 10. Integridade dos arquivos (sha256)

| Arquivo | sha256 |
|---|---|
| 5325 | `7c322bc56cd31c43eaf0ce6d5413097bedcb0bf479ab0a7acf3eec5d2f18308c` |
| 5326 | `d364319419a2008080bda7b58293d7284b8384560cc60c011f073a4b7ec83cf9` |
| 5327 | `75c1cb6d92939bef1a976096e9a226bbc6f1dbd32d009f0b1e3a3ae15f0c6ede` |
| 5328 | `06918e636f1d20139024330fe393a4c9d75217a773d37612d90aca0936a848e5` |
| 5329 v1.1 | `317180b3e3ccb0b88e364eeeb09ddfa79de43faef46b62890d1ba8bb97c97367` |
| 5863 v1.2 | `ec5e8da7064385ac219310c906a700dbf7156893b4600f0e302e8b3a9819f170` |
| 5330 (pacote B) | `9eeab6a328fe236531bdb6407e40ae7b8a637d54cc9d3b15d6a51915e5118945` |
| 5864 (pacote B) | `47e96959e15447dcd3821ea2f1a887f07be99fff4b057eda53370f57c65a449e` |
