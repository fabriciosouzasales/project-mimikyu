# V1-12 VIEWER PARITY — proposta de leitura (5320, 5321, 5862)

**Status (2026-10-30, LIVE ROLLOUT 5321 + 5322 + 5862):** 5320, 5321 v1.2 e 5322 **CONFIRMADAS APLICADAS** no LIVE; 5862 v2.1 **EXECUTADA uma vez — GATE PASS 33/33, 99.1 PASS (resíduo zero)**. A 5861 (51/51 PASS) continua sendo a evidência dos contratos 5300–5319; a 5862 é a evidência de 5320–5322. **Promovidas para `database/schema/` em 2026-10-30 (`V1-12 SCHEMA RECONCILIATION & VISUAL HANDOFF-01`)**, junto com 5300–5319 — só o bloco Status difere; corpos efetivos das 18 funções do V1-12 no LIVE ≡ último arquivo canônico de cada uma (md5 18/18). A 5862 permanece só aqui, inalterada desde a execução (sha256 abaixo). Roteiro de homologação visual: [`HOMOLOGATION.md`](HOMOLOGATION.md). **V1-12 não publicado nem encerrado.**

| Migration | Ledger LIVE | md5 do corpo LIVE (`prosrc`) ≡ arquivo | sha256 do arquivo |
|---|---|---|---|
| 5320 | `20261030184647` | `e30dba80d83a478d2cd8c3dfbf41d648` | `461ccb35…` (rodada anterior) |
| 5321 v1.2 | `20261030192228` | `cfce8495bbbba3342e6566ee3e41ba63` | `c34b27fbdd8b879f9acdf21328ce25861281bbfa4961888b9093b03fbed48947` |
| 5322 | `20261030192249` | `d81891c7ab54e1a66c07016ba43613ff` | `7041609382923f6ab6743efca0a2c5e4f3195d2f5aa72aa4d952674fc737be40` |
| 5862 v2.1 | — (validação, sem ledger) | — | `f6f7dd4e6c3184a861dbf05785c0dc003324c68cde8fabd95668645b0108a260` |

Corpos substituídos (para rollback manual, se decidido): 5314 md5 `af4d9bf77dd840d6d6538e9a31b6576c`, 5317 md5 `989f749b9fe5eec4dae437c446967f18`.

## 1. Arquivos

| Arquivo | O quê | Natureza |
|---|---|---|
| `5320_create_get_shared_collection_positions_function.sql` | Grade Todas · Tenho · Faltam da coleção de Set para OWNER/VIEWER | função **nova**, só leitura |
| `5321_replace_get_shared_collection_binder_identity.sql` (v1.2) | Acrescenta `binder_name` e `show_brand_mark` à 5314; convidada → nome NULL e logomarca `true` | substitui o corpo da 5314, **mesma assinatura**, chaves aditivas |
| `5322_fix_public_collection_binder_guest_identity.sql` | Vitrine (5317): convidada → logomarca `true` (nome já era NULL) | nova migration que substitui o corpo da 5317, **mesma assinatura, mesmas chaves e grants** |
| `5862_validate_viewer_parity.sql` (v2.1) | Harness com fixture efêmera + sentinela MS862 + resíduo zero — gate 33 | validação |

**Regra de identidade (decisão aprovada):** coleção autorizada **dona** do fichário → nome próprio e preferência real de logomarca; coleção **convidada** → `binder_name = NULL` (cliente usa o nome da coleção autorizada) e `show_brand_mark = true` (padrão MMKYU), sem ler nem alterar a configuração do fichário dono. Preferência visual não autoriza leitura de imagens privadas.

Diff da 5321 em relação à 5314 (só isto muda): três variáveis novas; os dois `SELECT` do fichário passam a ler `display_name` (somente no ramo da coleção **dona**; no ramo convidada é `NULL::TEXT`) e `show_brand_mark`; `v_own := v_layout IS NOT NULL` após o ramo dono; duas chaves no `jsonb_build_object` final. Acesso, contagem e demais chaves idênticos. Mesma regra já aprovada na vitrine pública (5317: `binder_name` só com `v_own`).

## 2. Revisão objetiva

| Critério | 5320 | 5321 |
|---|---|---|
| Autorização interna | `collection_share_role()` (5302) ∈ {OWNER, VIEWER ACTIVE} antes de qualquer leitura | idem (inalterado da 5314) |
| Estranho / pendente / recusado / removido / anon | zero linhas; anon sem EXECUTE (42501) | NULL; anon 42501 |
| Patrimônio privado | não devolve `copies_available` (acervo), local, condição, valor, datas, ids de exemplar | nenhuma chave privada; id da coleção dona nunca lido |
| Tenho/Faltam | mesma regra canônica da 5071/5169: posição satisfeita por **qualquer variante** da carta alocada a esta coleção; ordem `collector_order, number, id` | — |
| Master Set | fora do recorte (só `STANDARD_SET`, como a 5169) → zero linhas; o frontend não chama a grade para Master Set | — |
| Nome do fichário | — | só quando a coleção compartilhada é a **dona** do fichário; convidada → NULL |
| Identidade de fichário de outra coleção | — | nunca exposta (nome NULL para convidada) |
| Performance | mesmo plano da 5169 sem o CTE `available`: alocações da coleção (índice por `collection_id`) + cartas do Set (índice por `card_set_id`) + 1 asset por linha; `p_limit` 1..500, `p_offset` ≤ 100.000 | 2 contagens já existentes, sem custo novo |
| Revogação | checada a cada chamada; 5862 R.1 prova corte imediato | idem |

**Verificação:** compilados e aplicados no LIVE sem erro (5320 em `20261030184647`, 5321 v1.2 e 5322 em `20261030192228`/`20261030192249`); comportamento provado pela 5862 v2.1 (33/33 PASS).

## 3. Cobertura dos quatro tipos de coleção (participante)

| Tipo | Titular hoje | Participante hoje | Lacuna e menor extensão |
|---|---|---|---|
| **Set (STANDARD_SET)** | grade do Set, Todas/Tenho/Faltam, ordem do Set (5169) | galeria de cartas alocadas (5313) até a 5320; frontend pronto | **5320** (esta proposta) |
| **Livre** | cartas da coleção, mais recentes primeiro, paginado, sem filtros | 5313: mesmas cartas, mesma ordem, paginado | **paridade já existe** — nenhum contrato novo |
| **Master Set** | grade por posição (carta + acabamento, secretas), Todas/Tenho/Faltam (5189/5198) | galeria 5313 | wrapper participante da 5198 **sem** `copies_available` (5323, a escrever após aprovar o padrão 5320) |
| **Pokédex** | posições nacionais por geração, representante (5204) | galeria 5313 | wrapper participante da 5204 **sem** `copies_available`, `copies_elsewhere` e `acervo_state` (5324); o representante já vem só das alocações desta coleção, então pode ser exposto |

Não se propõe solução genérica: cada wrapper replica o recorte canônico do seu tipo, remove só as colunas de acervo e troca a checagem de dono por `collection_share_role`.

## 4. Personalização visual — o que o participante e a vitrine veem

| Elemento | Titular | VIEWER (com 5321) | Vitrine pública | Como compartilhar com segurança |
|---|---|---|---|---|
| Material, cor, acabamento | sim | sim (`cover_finish`, 5312) | sim (5317) | — |
| Couro, zíper, lombada, contracapa, bolsos | sim | sim (mesma camada `BinderObjectFrame` + `PageGrid`) | sim (migrada para a mesma camada) | — |
| Nome próprio do fichário | sim | sim se a coleção é a dona; convidada → nome da coleção | sim (mesma regra, 5317) | 5321 |
| Logomarca | sim | sim | sim | 5321 / 5317 |
| Capa de Set (logo do Set) | sim | sim | sim | — |
| Capa enviada (coleção livre / Pokédex, bucket privado `collection-cover`) e código da capa | sim | **não** | **não** | ver §5 |
| Imagens personalizadas de bolso e de 2 bolsos (bucket privado `binder-slot-image`) | sim | **não** (bolso vazio pela 5315) | **não** | ver §5 |
| Cartas e reservas de **outras** coleções do mesmo fichário | sim | nunca (bolso vazio) | nunca | permanece mascarado — não é personalização autorizada |

## 5. Proposta mínima para capa enviada e imagens de bolso (decisão separada)

Nenhuma política genérica de armazenamento. Duas peças por bucket, ambas restritas a um objeto por vez:

1. **Leitura do caminho** por porta do participante (e da vitrine): função SECURITY DEFINER que devolve os caminhos das imagens **só** das páginas pedidas de um fichário cuja coleção compartilhada é a **dona** (convidada → nenhuma imagem, como o nome) e, para a capa, o `cover_logo_path`/`cover_code` da própria coleção.
2. **Política SELECT escopada** em `storage.objects`: permite ler o objeto `name` somente se existe a linha correspondente (`collection_layout_slot_image.storage_path = name` ou `collection.cover_logo_path = name`) cuja coleção dona tem o usuário como participante ACTIVE (`collection_membership`) — ou, para a vitrine, cuja coleção está PUBLIC e ACTIVE (papel anon). Sem listagem de pastas; URL assinada de curta duração gerada pelo próprio usuário.

Efeitos: revogação/privatização cortam a leitura na próxima assinatura; nenhum outro arquivo do titular fica legível. Exige migração de política em `storage` → **não aplicar sem decisão separada**.

## 6. Procedimento LIVE (somente após autorização explícita)

A 5320 **já está aplicada — não reaplicar**.

1. Pré-checagem só leitura: ledger com 5300–5320; `get_shared_collection_binder` ≡ 5314 (md5 `af4d9bf7…`); `get_public_collection_binder` ≡ 5317 (md5 `989f749b…`); `get_shared_collection_positions` ≡ 5320 (md5 `e30dba80…`). Divergência → STOP sem escrita.
2. Aplicar `5321_…` v1.2 (uma migration).
3. Aplicar `5322_…` (uma migration).
4. Executar a 5862 v2.1 **uma vez**: criar a função temporária (arquivo inteiro) e rodar `select * from pg_temp.wh_5862_validate();`. Gate: `GATE PASS 33/33` e `99.1 PASS` (resíduo zero).
5. Qualquer FAIL → STOP, sem correção nem rollback automático; reportar.
6. Rollback manual, se decidido: reaplicar o corpo da 5314 (desfaz 5321) e o da 5317 (desfaz 5322). A 5320 é independente. O frontend tolera os dois estados.
7. Homologação com contas reais (titular + VIEWER): Todas/Tenho/Faltam e ordem iguais às do titular; contracapa com nome/logomarca na coleção dona; coleção convidada com o nome da coleção e logomarca padrão; remover a participação e confirmar que grade e fichário deixam de abrir.
