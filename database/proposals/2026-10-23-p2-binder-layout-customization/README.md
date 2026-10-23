# P2-BINDER-LAYOUT-CUSTOMIZATION — Inserir espaço e imagem em 2 bolsos

| Campo | Valor |
|---|---|
| Versão | 1.2 (2026-10-23, `…-LIVE-READINESS-01`: índice por página na 5238, POST-4 endurecido, procedimento de implantação §6) — 1.1 `…-REVIEW-01`; 1.0 `…-IMPLEMENTATION-PROPOSAL-01` |
| Status | **5238–5243 EXECUTADAS NO LIVE e CANÔNICAS** (2026-10-23; ledger `20261023221313`…`20261023221747`; cópias em `database/schema/` com bloco executável idêntico). R0/R9 PASS; **homologação funcional pela interface PASS** (§8). Itens não comprovados listados em §8. |
| Decisões | `P2-BINDER-LAYOUT-CUSTOMIZATION-DECISIONS-01`: D2–D10 aprovadas; D1 ajustada (barreiras); D3 com confirmação explícita; D9 provisória (sem decisão de monetização). |
| Depende de | 5104–5141, 5225–5237 canônicas |

## 1. Arquivos e ordem (uma migration por vez, cada uma uma transação com pré/pós-checagem fail-loud)

| # | Arquivo | O quê | Prioridade |
|---|---|---|---|
| 0 | `LIVE_00_precheck_readonly.sql` | R1-pré: ledger, ausência de objetos, 0 mesclagens, privilégios, política do bucket, md5 das funções substituídas | — |
| 1 | `5238_guard_binder_layout_regions.sql` | Proteções da mesclagem: `merge/unmerge_layout_region` fora de `authenticated`; bolso mesclado recusa carta, reserva e fixação; mesclagem recusa bolso com carta/reserva | **integridade** |
| 2 | `5239_create_collection_layout_region_image.sql` | Tabela da imagem da mesclagem; **proteção do Storage trocando só o corpo de `binder_slot_image_path_is_linked`** (política DELETE intocada); caminho exclusivo entre bolso e mesclagem; teto único de 500; limpeza e cota cientes | **Storage** |
| 3 | `5240_create_binder_region_image_write_functions.sql` | `merge_my_binder_slots_with_image`, `set_my_binder_region_image`, `…_focus`, `separate_my_binder_slots` | funcional |
| 4 | `5241_create_binder_region_image_read_functions.sql` | `get_my_collection_binder_region_images` (até 4 páginas) | funcional |
| 5 | `5242_update_binder_dismantle_for_region_images.sql` | Desmontagem remove imagens de mesclagem antes das mesclagens e devolve os caminhos (diff mínimo sobre a 5236) | integridade |
| 6 | `5243_create_binder_insert_gap_functions.sql` | `preview_my_binder_insert_gap`, `insert_my_binder_gap`, `close_my_binder_gap` | funcional |
| 7 | `LIVE_90_postcheck_readonly.sql` | R1-pós: grants, gatilhos, política intocada (fingerprint = PRE-5), ledger | — |

Frontend local (sem efeito até as migrations existirem — funções ausentes viram "ainda não disponível"): regra e contrato em `web/lib/colecoes/binder-insert.ts`, `binder-region.ts` (+ testes); server actions em `fichario/actions.ts`; envio/vínculo em `binder-image-io.ts`; interface em `binder-layout-tools.tsx`, `binder-slot.tsx` (`RegionPocketView`, `GapGutter`) e `binder-workspace.tsx`.

**Revisão estática (REVIEW-01) — correções aplicadas:** (a) 5239: corrida entre bolso e mesclagem pelo mesmo caminho de arquivo — as duas checagens cruzadas agora tomam a trava consultiva `binder-slot-image:<uid>` antes de ler; (b) 5243: `plan_token`/`undo_token` não capturavam a identidade da reserva — a cadeia passa a expor `reserve_sig` (md5 da reserva) e o token do desfazer inclui reserva e fixação.

## 2. Regras consolidadas

**Inserir espaço** — livre = sem carta, reserva, imagem, fixação e fora de mesclagem; barreira = fixado ou mesclado.
- Empurra X..(primeiro livre − 1) uma posição; o bolso inteiro anda (posição com id preservado, reserva, vínculo de imagem com o mesmo arquivo).
- **Barreira antes do primeiro livre → BLOCKED**, com página/linha/coluna da barreira para a mensagem.
- Mesma página → `SAME_PAGE`; outra → `CROSS_PAGE` (confirmação + páginas e total na prévia); nenhum livre até o fim → `NEEDS_PAGE` (confirmação explícita da página nova, criada na mesma transação).
- Execução do fim para o começo (destino sempre livre); plano conferido por `plan_token` sob trava do fichário.
- Desfazer por `undo_token`; expira se qualquer bolso de gap..end mudou. Remove a página criada só se continuar a última e inteiramente livre.

**Limite operacional — 500 itens movidos (posições + reservas + imagens) por operação.** Critérios, não número escolhido:
1. *Precedente medido*: é o teto por chamada já validado no fichário para lotes no mesmo desenho (trava do fichário + gatilhos por linha) — `remove_slot_assignment`/`set_slot_lock`/`clear_slot_expected_content`, hardening 5138–5140 validado por 5820.
2. *Segurança de concorrência*: as RPCs do fichário usam `lock_timeout = 5s`; a operação segura a trava do fichário inteiro, então precisa terminar com folga dentro desse orçamento para não fazer outras edições do mesmo usuário expirarem. **Meta na homologação: pior caso (500 itens) ≤ 1 s medido**; se não cumprir, diagnosticar antes de mexer no teto (constante única em `binder_gap_evaluate`).
3. *Compreensão*: 500 itens equivalem a 25 páginas cheias do maior modelo (5×4) — a prévia ainda consegue nomear as páginas envolvidas.

**Imagem em 2 bolsos** — só 2 bolsos livres lado a lado na mesma linha; criação atômica (mesclagem + vínculo); `UNCHANGED` na repetição; substituir devolve `previous_path`; separar desvincula e desfaz numa transação. Arquivo apagado pelo cliente só depois (mesma ordem homologada hoje).

## 3. Riscos novos

| # | Risco | Tratamento |
|---|---|---|
| R1 | **Primeira execução real do SQL será o LIVE** (P1: sem banco isolado). As funções de 5243 têm lógica não trivial. | Prechecks fail-loud, cada migration atômica, rollback por proposta; homologar primeiro em fichário com imagens descartáveis. |
| R2 | Revogar `merge/unmerge_layout_region` muda uma superfície existente. | Nenhum consumidor no app (busca no `web/`). Continuam chamáveis pelo dono do banco. |
| R3 | Mover imagem recria a linha de vínculo (o `slot_id` é imutável por desenho): `created_at` do vínculo passa a ser o do deslocamento. | Arquivo, caminho e enquadramento preservados; nenhuma janela sem vínculo visível a outra sessão. Aceitável. |
| R4 | `binder_gap_chain` varre o fichário a cada avaliação (algumas vezes por chamada). | Linear no nº de bolsos (fichário de 100 páginas × 20 = 2 000 linhas). Medir na homologação; se necessário, materializar a cadeia uma vez. Sem índice novo. |
| R5 | Gatilho de cota nas duas tabelas usa a mesma trava consultiva da 5233. | Mesma chave e mesma ordem → sem deadlock; a 5233 continua checando antes (mensagem amigável). |
| R6 | Desfazer remove página via `remove_layout_page`; se esta recusar por regra própria, o desfazer inteiro falha (rollback). | Pré-condições checadas antes; falha é segura (nada muda). |

## 4. Decisões (REVIEW-01)

| # | Decisão |
|---|---|
| P1 | **Sem ambiente ou branch adicional do Supabase.** Aplicação futura direto no LIVE, com prechecks fail-loud — só com autorização explícita. |
| P2 | **500 itens como teto provisório.** Meta: ≤ 1 s, sujeita a medição na homologação; **não reduzir automaticamente** sem diagnosticar a causa. |

## 5. Homologação proposta (pelo app, com baseline de patrimônio, imagens descartáveis)

Mesclagem: unir (desktop/teclado/celular) → enquadrar → substituir (arquivo anterior intacto até o vínculo) → separar (vínculo encerrado antes da exclusão) → tentar posicionar carta/fixar bolso mesclado (recusa) → remover página com mesclagem (recusa orientada) → apagar arquivo vinculado pela API (recusa).
Inserir: mesma página → outra página (prévia com páginas e total) → barreira fixada e mesclada (bloqueio com posição) → sem livre até o fim (confirmação de página) → desfazer → desfazer expirado → medir pior caso do limite.

## 6. Implantação no LIVE (LIVE-READINESS-01) — PREPARADO, NÃO EXECUTADO

**Baseline lido em 2026-10-23 (só leitura, papel `postgres`):** ledger termina em `20261023202009 5237_…`; nenhuma 5238–5243 aplicada; objetos novos ausentes; `collection_layout_region` = 0, `collection_layout_slot_image` = 0; 1 fichário, 20 páginas, 180 bolsos, 155 cartas, 158 reservas, 0 fixados; `merge/unmerge_layout_region` executáveis por `authenticated` (5238 fecha); `binder_slot_image_path_is_linked` auth=sim/anon=não; política DELETE delega à função; 24 políticas em `storage.objects`, fp `58af1d22e84b7956bd04cb286c43937d`; `postgres` com UPDATE em `storage.objects` (exigido pela 5240); sem transação longa. md5 das funções substituídas: `binder_slot_image_path_is_linked` 86e513e8…, `list_my_unlinked_binder_slot_images` 01e2f3ee…, `get_my_binder_slot_image_summary` f14b80ec…, `preview_my_collection_binder_dismantle` 1b45abf4…, `dismantle_my_collection_binder` 23a28f28… (tipos de retorno idênticos aos da proposta — `CREATE OR REPLACE` válido).

**Sequência (uma por vez; cada uma é uma transação com pré e pós-checagem fail-loud):**
R0 `LIVE_00` (+ salvar `pg_get_functiondef` das 5 funções acima = fonte do rollback) → W1 5238 → W2 5239 → W3 5240 → W4 5241 → W5 5242 → W6 5243 → R9 `LIVE_90` + Security Advisor → H homologação pelo app.
Envio pelo `apply_migration` (nome = arquivo sem `.sql`), **sem os `begin;`/`commit;` externos** (precedente 5237: o `apply_migration` já é uma transação). Dependências: 5239←5238; 5240←5239 (+5232–5234); 5241←5239+5234; 5242←5239+5236; 5243←5240 (+5125/5235).

**PASS/STOP:**
- R0: PASS só se PRE-1…PRE-7 = baseline acima (ledger, ausências, 0|0|0, privilégios, fp, md5, long_tx=0). Qualquer diferença → STOP e reportar (não reconciliar sozinho).
- W1–W6: PASS = migration conclui e o ledger ganha exatamente 1 linha com o nome esperado. Qualquer erro → STOP: a transação desfaz tudo daquela migration; as anteriores permanecem (são aditivas e coerentes isoladamente); não reaplicar sem diagnóstico.
- R9: POST-1 (3 colunas + índice) true; POST-2 fp = `58af1d22…` e `linked_covers_regions`; POST-3 rls_on, sem SELECT do cliente, vazia; POST-4 15 funções SECURITY DEFINER com `search_path=""`, 8 públicas com EXECUTE para authenticated, 7 internas sem, nenhuma para anon; POST-5 seis linhas 5238→5243 em ordem. Advisor: nenhum achado novo além de 0029 (funções SECURITY DEFINER expostas, esperado para as 8 RPCs).
- H (pelo app, fichário de homologação, imagens descartáveis): §5 completo + medição do pior caso do "Abrir espaço" (meta ≤ 1 s; não reduzir o teto sem diagnóstico). Baseline de patrimônio (cartas/reservas/alocações) idêntico antes/depois.

**Recuperação:** falha durante W* = rollback automático da própria migration. Reversão depois de COMMIT (só com autorização): (1) 5243/5241/5240 — `drop function` das funções novas; (2) 5242 — recriar as 2 funções de desmontagem com o corpo salvo no R0; (3) 5239 — exige 0 linhas em `collection_layout_region_image` (separar antes), recriar as 3 funções com o corpo do R0, `drop` dos gatilhos/funções novos e da tabela; (4) 5238 — `drop` dos 4 gatilhos, 3 funções e do índice; `grant execute` de `merge/unmerge_layout_region` a `authenticated` (estado 5134/5135). A política do bucket nunca é alterada, então não há rollback de Storage. O frontend tolera as funções ausentes ("ainda não disponível").

**Autorizações específicas necessárias:** (a) cada W1–W6 (escrita de schema no LIVE); (b) a homologação H, que grava no LIVE (cria/separa mesclagens, abre/fecha espaço, envia e apaga arquivos no bucket); (c) qualquer reversão pós-COMMIT; (d) promoção para `database/schema/` e commit/push depois do H.

## 7. Execução no LIVE (LIVE-EXECUTION-01) — 2026-10-23

- **R0 (só leitura):** idêntico ao baseline da §6 (ledger em 5237; objetos ausentes; 0 mesclagens/0 imagens/0 objetos no bucket; fp `58af1d22…`, 24 políticas; md5 das 5 funções iguais). Definições originais salvas em `R0_original_functions_rollback_source.sql` (fonte do rollback).
- **W1–W6** via `apply_migration`, corpo sem `begin;`/`commit;` externos, uma por vez, cada uma com pré/pós-checagem interna: `5238` → `20261023221313`, `5239` → `…221400`, `5240` → `…221458`, `5241` → `…221529`, `5242` → `…221630`, `5243` → `…221747`. Nenhum erro, nenhuma reaplicação; exatamente 1 linha nova no ledger a cada passo.
- **R9 (LIVE_90):** merge/unmerge sem EXECUTE para authenticated/anon; 4 gatilhos de proteção + 5 de imagem ativos; índice `ix_collection_layout_region_page` presente; fp das políticas do Storage **inalterado** (`58af1d22…`, 24); função de vínculo cobre mesclagens, authenticated sim/anon não; tabela nova com RLS, sem SELECT para clientes, vazia; 26 funções do pacote com SECURITY DEFINER e `search_path=""`; 13 com EXECUTE para authenticated (8 novas + 5 já existentes), 13 internas/gatilho sem; nenhuma para anon/PUBLIC. Patrimônio idêntico (20 páginas, 180 bolsos, 155 cartas, 158 reservas, 0 fixados).
- **Security Advisor:** só achados da mesma classe dos existentes — 0008 (`collection_layout_region_image`, igual a `collection_layout_slot_image`: acesso só por RPC) e 0029 para as 8 RPCs novas (esperado). `merge/unmerge_layout_region` saíram do 0029. Nenhum 0028 novo; nenhuma função interna exposta.
- **Ponto a observar na homologação:** o deslocamento de imagem no "Abrir espaço" reinsere o vínculo (DELETE+INSERT); confirmar que o gatilho de cota não recusa quando o usuário está exatamente no teto de 500.

## 8. Encerramento (FINAL-CLOSEOUT-01) — 2026-10-23

**Promoção:** os 6 arquivos foram copiados para `database/schema/` mudando só o bloco Status. sha256 (16) do trecho `begin;`…`commit;`, igual em proposta e canônica: 5238 `eed32fb3711bef7e`, 5239 `44840dcd81595b9c`, 5240 `78c83988d847149a`, 5241 `cfaff03e0f9a6572`, 5242 `063fec04487b78c3`, 5243 `ba15ef1c3aa1c3ba`. Equivalência com o LIVE: corpo de cada uma das 26 funções criadas/substituídas, sem comentários `--` e com espaços normalizados, tem o mesmo md5 no arquivo e em `pg_proc.prosrc` (26/26); tabela, constraints, índices e os 9 gatilhos conferidos no catálogo. Nada foi reexecutado.

**Homologado:**
- Interface (Fabrício): inserir espaço entre cartas, deslocamento automático, desfazer, mesclar 2 bolsos vazios na horizontal, imagem contínua, persistência da mesclagem, ajuste de enquadramento, substituição e separação — PASS. Experiência visual aprovada.
- Frontend: typecheck, testes do fichário 59/59, `npm run lint`, `npm run build` — PASS.
- Banco: 5238–5243 aplicadas com pré/pós-checagem internas, R0 = baseline, R9 (`LIVE_90`) PASS, Advisor sem divergência inesperada, patrimônio preservado.

**Não comprovado (sem evidência de execução — não declarar PASS):** concorrência real entre sessões; deslocamentos extensos e entre páginas, incluindo página nova e desfazer com remoção da página; comportamento perto do teto de 500 itens por operação e do teto de 500 imagens (reinserção do vínculo no deslocamento de imagem); limpeza dos arquivos anteriores no Storage após substituir/separar, não conferida diretamente no bucket; desempenho do pior caso (meta ≤ 1 s); desmontagem de fichário com mesclagem; recusa de carta/fixação em bolso mesclado pela interface; não há harness dedicado.
