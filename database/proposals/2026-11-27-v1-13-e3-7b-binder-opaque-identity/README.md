# V1-13 · E3-7b — Identidade opaca no fichário compartilhado do EDITOR (P0) — 5397

| Campo | Valor |
|---|---|
| **Rodada** | `E3-7b — BINDER OPAQUE IDENTITY / P0 PRIVACY CORRECTION-01` (2026-11-27), rodada A (contrato e artefatos) |
| **Status** | **EXECUTADA NO LIVE / CANÔNICA (2026-11-27 18:36:37Z).** Executor v1.4, papel postgres, manifesto `7a55d309…f72d7`, expectativas `4b57d024…5f844`: PRE, migration (exit 0) e POST com PASS. Evidências em `E37B_5397_DEPLOY_EVIDENCE_2026-11-27.md`; cópia canônica em `database/schema/5397_binder_opaque_copy_identity.sql`. Barreira CLOSED. Provas funcionais pendentes (TEST/E4, §6). Preparada e auditada em `CORRECTION-01` e `FINAL RELEASE GATE-01`. |
| **Problema** | O EDITOR recebia o UUID físico do exemplar do titular de três formas: retorno da 5373 `get_shared_binder_placeable_cards`, JSON da prévia da 5386 `editor_preview_binder_auto_arrange` e entrada da 5374 `editor_place_card_in_binder` (colocar e "Desfazer"). O UUID não concede autoridade, mas é uma identidade patrimonial global e estável. |

## 1. Contrato opaco

É o **mesmo token da 5391**, `pc1.` + HMAC-SHA256(alocação | participação | época), resolvido pelo **mesmo ajudante interno da 5392** (`v1_13_resolve_pokedex_copy`, com `p_hint_position_id = null`, ou seja, todas as alocações de X).

- **Escopo:** coleção X e participação EDITOR ACTIVE do chamador (`v1_13_editor_membership`).
- **Invalidação:** muda quando a participação ou a época mudam. O servidor aceita apenas o token da época vigente.
- **Recusa:** token inválido, de outra coleção, de outra participação ou de época anterior recebe a recusa já existente `PHYSICAL_CARD_NOT_ELIGIBLE` (P0002). Isso não revela por que o token falhou, e o front já trata essa recusa.
- **Cobertura:**
  - vale para qualquer alocação de X, inclusive exemplares fora de bolso;
  - cobre colocar e desfazer;
  - arrastar e mover/trocar continuam por posição de bolso, sem identidade de exemplar;
  - a organização automática segue pelo token do plano.
- **Sem permissão nova:** autorização, travas e elegibilidade são as da 5374, executadas antes da resolução do token.
- **Sem infraestrutura nova:** nenhuma tabela, segredo ou sequência.

## 2. Mudanças (migration 5397, transação única, `lock_timeout` 3 s)

| Objeto | Mudança |
|---|---|
| `get_shared_binder_placeable_copies(uuid, integer, integer)` | **nova**: a mesma leitura da 5373, com `copy_token text` no lugar de `physical_card_id`; sem participação vigente devolve zero linhas |
| `editor_place_copy_in_binder(uuid, integer, integer, integer, text)` | **nova**: o mesmo comportamento da 5374 (`ADD`/`REPLACE`/`UNCHANGED`, travas, evento `CARD_PLACED`), com o exemplar resolvido pelo token |
| `editor_preview_binder_auto_arrange(uuid)` | `CREATE OR REPLACE`: os itens perdem `'physical_card_id'`. `card_id` e `card_variant_id` ficam, porque são catálogo público; plano e token do plano não mudam |
| 5373 e 5374 antigas | **EXECUTE revogado** de PUBLIC, anon, authenticated e service_role. As funções continuam no banco, para o STOP de emergência G1 e para a reversão |

- **Por que funções novas:** o PostgreSQL não muda o tipo de retorno (5373) nem o tipo de argumento (5374) com `CREATE OR REPLACE`.
- **Prova do diff mínimo:** as funções são geradas a partir do texto canônico (G1), com blocos `[5397+]…[5397-]` e linhas `[5397~]`. A verificação estática desfaz os dois e exige o md5 do LIVE.

## 3. Consumidores (front)

| Arquivo | Mudança |
|---|---|
| `lib/colecoes/copy-token.ts` (novo) | `isCopyToken` e `hasForbiddenKey` num módulo neutro; `editor-pokedex.ts` reexporta sem mudança |
| `lib/colecoes/editor-binder.ts` | `parsePlaceableCards` lê `copy_token` e recusa qualquer chave patrimonial; `UndoRemoval.copyToken` |
| `lib/colecoes/editor-binder-arrange.ts` | a prévia do EDITOR não exige o id físico e recusa o item que ainda o trouxer |
| `lib/colecoes/binder-share.ts` | só documentação: no EDITOR, a chave da lista (`physicalCardId`) carrega o token opaco |
| `app/colecoes/compartilhada/[id]/fichario/actions.ts` | `readEditorPlaceableCards` → 5397; `editorPlaceCard({ copyToken })` valida o token e envia `p_copy_token` |
| `components/colecoes/sharing/shared-binder-editor.tsx` | colocar e desfazer por `copyToken` |

- **Sem mudança:** seleção, arrastar e soltar, lista elegível, prévia e aplicação da organização automática, mensagens e estados.
- **Fluxo do titular:** inalterado, segue com o próprio acervo por UUID.

## 4. Artefatos (sha256)

| Arquivo | sha256 |
|---|---|
| `5397_binder_opaque_copy_identity.sql` | `3aa4afc77c5fd7fb00fd325cb7c397918ab71f8da2a84bcaa3e2d65858a9ff9c` |
| `E37B_5397_PRE_readonly.sql` (gate) | `2626209535fa631fe997abe993e1b8c0a479f43032772d154953f150161e58b3` |
| `E37B_5397_POST_readonly.sql` (gate) | `0dac345595cf5997cf42420ecf1aebd475b25566983ff1fb61bb353a6c9c7afe` |
| `E37B_5397_EXPECTATIVAS.json` | `4b57d02408b6337938c798cd86387ab28402f6976f95af1de445208458f5f844` |
| `E37B_5397_MANIFEST.txt` | `7a55d30912f7e1ce40c0f703b2f029820de3184575c896fddc5cd563192f72d7` |
| `ROLLBACK_5397.sql` | `caa960027682b5626719d67d16a57efcb98568d21d0f274c3139f94d299b4478` |
| `RESTORE_5373_5374_EXCECAO_5397.sql` (exceção; reabre o P0) | `900f2b8631fea292855234a917744d84d0d9569711678545f1fee765414bcead` |
| `EMERGENCY_STOP_V1_13_ADD_E37B.sql` (E2d) | `87e91213b43097037c6d4ea1d3395f2697289b76b1b122ce3ab3d9277d05c0bb` |
| `build_5397.py` · `static_check_5397.py` | gerador · verificação estática (20/20, 19/19 mutações) |

- **PRE:**
  - barreira CLOSED e 0 identidades;
  - 3 corpos canônicos (md5 = `md5_protected` do G1);
  - 5 ajudantes canônicos (5389, 5391 e 5392);
  - contratos antigos ativos e as funções novas ausentes;
  - inventários por assinatura: `escritores_bolso` (4) e `escritores_exposicao_fisica` (3: 5373, 5374 e 5386).
- **POST:**
  - texto gerado e ajudantes intactos;
  - funções novas como definer, com `search_path` vazio e só para `authenticated`;
  - antigas sem EXECUTE para nenhum cliente;
  - prévia executável;
  - **exposição física vazia** e escritores = anteriores + `editor_place_copy_in_binder`;
  - barreira CLOSED.
- **Reversão segura:** remove as funções novas e restaura a prévia canônica. As antigas continuam revogadas, então o EDITOR fica sem colocar carta, sem reabrir o P0. A exceção que as reabre fica num arquivo separado.

## 5. Condições de implantação (cumpridas em 2026-11-27)

1. Auditoria independente deste pacote e do diff do front.
2. `-Simular` no Windows com o manifesto `7a55d309…` e as expectativas `4b57d024…`.
3. Autorização expressa citando esses hashes. Execução só pelo executor v1.4 (PRE → 5397 → POST), com STOP em qualquer divergência.
4. O front da 5397 é publicado junto. Com a barreira CLOSED e a configuração D1 desligada, nenhum EDITOR usa o fichário durante a troca.

## 6. Só comprovável em sessão real (TEST/E4)

- Recusa de:
  - token inválido;
  - token de outra coleção;
  - token de outra participação;
  - token de época anterior (troca de papel);
  - participação removida.
- VIEWER tentando escrever.
- Barreira CLOSED (`CAPABILITY_NOT_ENABLED`).
- Colocar e desfazer reais.
- A prévia real sem o id.
- O custo da resolução do token em coleções grandes: um HMAC por alocação de X, como na 5392.
