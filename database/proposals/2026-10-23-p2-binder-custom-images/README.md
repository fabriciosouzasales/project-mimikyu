# P2-BINDER-CUSTOM-IMAGES — Imagem personalizada no bolso do Fichário

| Campo | Valor |
|---|---|
| **Status** | **PROPOSTO — nada executado.** SQL escrito e verificado estaticamente; nenhum SQL rodado, LIVE intocado, harness 5852 não executado, frontend inalterado. |
| **Rodadas** | `P2-BINDER-CUSTOM-IMAGES-01` (desenho) → `P2-BINDER-CUSTOM-IMAGES-PROPOSAL-01` (contratos) → `P2-BINDER-CUSTOM-IMAGES-AUDIT-CORRECTION-01` (arquivo vinculado indelével; FOR SHARE no vínculo; concorrência revisada) — todas em 2026-10-23 |
| **Decisão conceitual** | C-198 (`docs/domain-modeling/collections/concept-decisions.md`) |
| **Decisões de Fabrício** | D1 limite **500 imagens por usuário** (ajustável; confirmado em 2026-10-23, substituindo a proposta de 100) · D2 o dono gerencia pelo fichário acessado por **qualquer coleção participante**, inclusive convidada · D3 imagem é **elemento visual do fichário, não colecionável** |

## 0. Pacote de implantação (LIVE-READINESS-01, preparado — nada executado)

`RUNBOOK-LIVE.md` (classes R1/W1/F, ordem, gate, PASS/STOP, conduta em erro, reversão, prova funcional F1–F7), `LIVE_00_precheck_readonly.sql` (PRE-1…PRE-8: ledger, ausência, dependências, corpos vivos, permissões do papel, políticas/RLS/gatilhos do Storage, baseline, janela) e `LIVE_90_postcheck_readonly.sql` (POST-1…POST-4). Condição eliminatória do pré-check: o papel dono das funções precisa ignorar RLS (`rolbypassrls`) e nenhuma política permissiva de escrita em `storage.objects` pode deixar de filtrar o bucket.

## 1. Arquivos e ordem de aplicação

| Ordem | Arquivo | O que faz |
|---|---|---|
| 1 | `5231_create_binder_slot_image_bucket_and_policies.sql` | Bucket privado `binder-slot-image` (512 KB, só `image/webp` e `image/jpeg`); políticas SELECT/INSERT da própria pasta; **sem UPDATE** (arquivos imutáveis); INSERT exige nome canônico e teto de 550 arquivos por usuário |
| 2 | `5232_create_collection_layout_slot_image_table.sql` | Tabela `collection_layout_slot_image` (PK bolso, dono, caminho UNIQUE, `focal_y` 0–100) + 6 gatilhos de integridade e exclusividade + política **DELETE** do bucket que recusa arquivo vinculado (`binder_slot_image_path_is_linked`) |
| 3 | `5233_create_binder_slot_image_write_functions.sql` | `set_my_binder_slot_image` (ADDED / REPLACED / UNCHANGED), `set_my_binder_slot_image_focus`, `clear_my_binder_slot_image` (REMOVED / ALREADY_ABSENT) + resolução/trava interna |
| 4 | `5234_create_binder_slot_image_read_functions.sql` | `get_my_collection_binder_slot_images` (1–4 páginas), `get_my_binder_slot_image_summary`, `list_my_unlinked_binder_slot_images` (limpeza) |
| 5 | `5235_update_remove_layout_page_for_custom_images.sql` | `remove_layout_page` passa a recusar página com imagem (mensagem explicativa) |
| 6 | `5236_update_binder_dismantle_for_custom_images.sql` | Prévia e desmontagem: removem imagens antes das páginas e devolvem `images_count` / `images_removed` / `image_paths` |
| — | `5852_validate_p2_binder_custom_images.sql` | Harness (39 verificações + GATE): cria dados sintéticos e se desfaz pela sentinela MS852 — **não executar no LIVE sem autorização**. As consultas da Seção 0 (somente leitura) servem de base ao LIVE_90 da rodada de aplicação |

Cada migration tem precheck que falha alto se a anterior não estiver aplicada ou se o objeto já existir.

## 2. Contratos e integridade

- **Uma imagem por bolso** (PK `slot_id`). Um arquivo serve um único bolso (UNIQUE `storage_path`).
- **Exclusividade, garantida no banco** (gatilhos de última linha, como a 5118) — não depende do frontend:

| Operação | Bolso com imagem | Imagem em bolso com… |
|---|---|---|
| Posicionar/mover carta (`assign`, `move`) | recusa `SLOT_HAS_IMAGE` | carta → `SLOT_OCCUPIED` |
| Reservar (`set_slot_expected_content`) | recusa `SLOT_HAS_IMAGE` | reserva → `SLOT_RESERVED` |
| Fixar (`set_slot_lock` true) | recusa `SLOT_HAS_IMAGE` | trava → `SLOT_LOCKED` |
| Mesclar (`merge_layout_region`) | recusa `SLOT_HAS_IMAGE` | mesclagem → `SLOT_IN_REGION` |

  Nenhuma dessas RPCs foi alterada: só ganham a recusa num caso novo. Destravar, remover carta, limpar reserva e desmesclar seguem iguais.
- **Concorrência:** toda escrita de imagem passa por `assert_collection_layout_mutable` (5122) — a mesma trava de fichário que carta, reserva, trava e mesclagem já usam — e trava o bolso. O limite por usuário é contado sob `pg_advisory_xact_lock` do usuário (fichários diferentes do mesmo usuário em paralelo não ultrapassam 500).
- **Idempotência:** repetir a inclusão com o mesmo caminho → `UNCHANGED`; repetir a remoção → `ALREADY_ABSENT`; reenquadrar com o mesmo valor não grava.
- **Fichário compartilhado:** imagem pertence ao bolso/fichário. Proprietária e convidadas leem as mesmas imagens; qualquer participante ativa gerencia (D2). Desassociar uma convidada não toca imagens.
- **Nada patrimonial muda:** a tabela não é lida por progresso, valor, acervo, alocação, reservas nem contagem de cartas. `get_my_collection_binder_pages` (5230) **não muda** — o bolso com imagem continua `EMPTY` para ela; o app sobrepõe a imagem lida pela 5234.
- **Página e desmontagem:** página com imagem não é removida (5235; FK RESTRICT como segunda barreira). A desmontagem remove imagens antes das páginas, confere a contagem lida sob trava e devolve os caminhos (5236). O token da prévia não inclui imagens: imagem incluída entre prévia e confirmação também é removida (aparência, não patrimônio).

## 3. Segurança dos arquivos

- Bucket **privado**; nenhuma URL pública. Exibição só por URL assinada de 1 h, emitida com a sessão do usuário (sem `service_role`).
- Pasta `<auth.uid()>/<layout>/<uuid>.(webp|jpg)`: as políticas exigem a pasta do próprio usuário; o INSERT exige o nome canônico completo; a RPC exige a pasta do **fichário do bolso** e o dono do objeto (`owner_id`/`owner`).
- **Tamanho e tipo no armazenamento**, não só no navegador: o bucket recusa > 512 KB e tipos fora de webp/jpeg; a RPC confere de novo os **metadados gravados pelo Storage** (`mimetype` coerente com a extensão, 1 ≤ `size` ≤ 524288).
- Sem UPDATE de objeto: ninguém sobrescreve um arquivo em uso (`upsert:true` também é recusado, pois exige UPDATE).
- **Arquivo vinculado é indelével:** a política DELETE só remove arquivo da própria pasta que não esteja vinculado a nenhum bolso. A API do Storage só apaga do armazenamento as linhas que o DELETE removeu, então limpeza, retry tardio ou bug do app não apagam imagem em uso.
- Teto de 550 arquivos por usuário no INSERT impede acumular arquivos sem vínculo para contornar o limite de 500.
- Tabela com RLS e sem privilégio para `anon`/`authenticated`; funções de gatilho e internas sem EXECUTE para a API; RPCs `SECURITY DEFINER`, `search_path` vazio, EXECUTE só `authenticated`, escrita com `lock_timeout` 5 s.
- Usuário B não lê, não inclui, não substitui nem remove nada de A; respostas não enumeram (coleção/bolso alheio = "não encontrado").

## 4. Substituição e limpeza

| Fluxo | Sequência | Se falhar no meio |
|---|---|---|
| Incluir | navegador reencoda (WebP/JPEG, remove EXIF) → `upload` em caminho **novo** (`upsert:false`) → `set` | `set` recusa → o app apaga o arquivo recém-enviado; a imagem existente nunca é tocada |
| Substituir | `upload` novo → `set` (REPLACED + `previous_path`) → app apaga o anterior | o anterior só sai **depois** do vínculo gravado; falha no envio não remove nada |
| Reenquadrar | `set_my_binder_slot_image_focus` | sem arquivo envolvido |
| Remover | `clear` (`previous_path`) → app apaga o arquivo | se apagar falhar, sobra arquivo sem vínculo |
| Desmontar | prévia (`images_count`) → desmontagem (`image_paths`) → app apaga os arquivos | idem |

**Contrato do app (frontend futuro):**
1. Sempre enviar com caminho novo (`<uid>/<layout>/<uuid>.<ext>`) e `upsert:false`.
2. Só chamar `remove` do caminho antigo depois de receber `REPLACED`/`REMOVED`/`DISMANTLED` com `previous_path`/`image_paths`; sem resposta (timeout), não apagar nada — a limpeza resolve depois.
3. Se o vínculo for recusado, apagar apenas o arquivo que acabou de enviar.
4. A limpeza apaga o que `list_my_unlinked_binder_slot_images` devolver; o banco recusa qualquer arquivo que esteja vinculado.

**Envios abandonados (estratégia simples):** `list_my_unlinked_binder_slot_images` devolve arquivos da própria pasta **sem vínculo e com mais de 1 hora** (a carência protege envios em curso). O app a chama ao abrir a escolha de imagem e apaga o que vier pela política DELETE da própria pasta. Sem rotina de servidor, sem `service_role`. O teto de 550 limita o pior caso enquanto a limpeza não roda.

## 4.1 Concorrência (AUDIT-CORRECTION-01)

Toda escrita de bolso do produto — `assign_card_to_slot`, `move_slot_assignment`, `set_slot_expected_content`, `set_slot_lock`, `merge_layout_region`, `remove_layout_page`, `add_layout_page` e as RPCs de imagem — passa por `assert_collection_layout_mutable` (5122: proprietária → fichário, FOR UPDATE); a desmontagem trava proprietária → fichário na mesma ordem; a desassociação trava proprietária → fichário → convidada, a mesma ordem das RPCs de imagem. Inventário conferido em `database/schema/` (nenhum escritor de posição/reserva/trava/mesclagem fora dessa trava; 5224 cria fichário novo, sem imagem possível). Os gatilhos da 5232 rodam DEPOIS dessa trava e leem com retrato novo.

| Corrida | Resultado |
|---|---|
| Adicionar imagem × posicionar carta | serializam na trava do fichário; a segunda recusa (`SLOT_OCCUPIED` ou `SLOT_HAS_IMAGE`) |
| Remover imagem × reservar | serializam; reserva antes → imagem já saiu ou `SLOT_HAS_IMAGE`; remoção antes → reserva entra normalmente |
| Substituir imagem × remover página | serializam; substituição antes → página recusada (`custom image(s)`); remoção antes → `SLOT_NOT_FOUND` (revalidação do bolso sob trava) |
| Desmontar × atualizar imagem | serializam; desmontagem antes → `SLOT_NOT_FOUND` (fichário some sob a trava); imagem antes → a desmontagem conta e remove a imagem nova e devolve o caminho |
| Limpeza (DELETE) × vincular o mesmo arquivo | vínculo trava o objeto FOR SHARE: DELETE antes → vínculo falha `IMAGE_FILE_NOT_FOUND`; vínculo antes → DELETE espera e, ao reavaliar, a política (função volátil) vê o vínculo e não apaga |
| Duas inclusões em fichários diferentes no limite | advisory lock por usuário; a segunda vê a contagem atualizada (`IMAGE_QUOTA_REACHED`) |

**Roteiro manual de duas sessões (homologação, fora do harness):** K1 imagem × carta no mesmo bolso; K2 remover imagem × reservar; K3 substituir × remover página; K4 desmontar × incluir imagem; K5 limpeza × vínculo do mesmo arquivo (sessão 1 vincula e não confirma; sessão 2 tenta apagar; sessão 1 confirma; o arquivo continua existindo e vinculado).

## 5. Verificações estáticas executadas (nenhuma execução SQL)

- Estrutura dos 7 arquivos: aspas, `$…$`, parênteses, `begin/commit`, `if/end if`, `loop/end loop`, `begin+case/end` por corpo e `search_path = ''` em toda função criada — **7/7 OK** (o mesmo verificador passa nos arquivos já aplicados da 5229/5230, como controle).
- 5235: diff do bloco executável contra a 5126 LIVE = só o precheck e a contagem de imagens.
- 5236: diff contra o bloco 7b da 5229 LIVE = só as linhas marcadas "5236" (colunas novas, contagem sob trava, remoção de imagens antes das páginas, conferência, comentário).
- Harness: 39 identificadores de verificação, iguais a `v_expected`.

Sem parser PostgreSQL disponível no ambiente: compilação real só na aplicação.

## 6. Riscos remanescentes

1. **Conteúdo real do arquivo não é inspecionado pelo banco** — só tipo declarado/metadados. Mitigado por reencode no navegador, lista fechada, exibição em `<img>` e só ao próprio dono.
2. **Teto de 550 pode ser excedido por poucos arquivos** sob envios simultâneos (contagem sem trava na política). Aceito: folga existe para isso.
3. **Arquivos órfãos** entre falhas e a próxima limpeza (custo pequeno, limitado pelo teto). Um arquivo enviado e deixado sem vínculo por mais de 1 h numa aba aberta pode ser limpo por outra aba; o vínculo então falha com `IMAGE_FILE_NOT_FOUND` e o usuário reenvia — a imagem atual nunca é afetada.
8. **Dependências do ambiente Storage (verificar no pré-check de leitura):** `postgres` com UPDATE em `storage.objects` (exigido pelo FOR SHARE — a 5233 falha alto sem ele); a API do Storage apagar do armazenamento só as linhas efetivamente removidas pelo DELETE (comportamento a confirmar na homologação); nome do GUC que libera DELETE direto (só afeta o harness).
4. **Exclusão de conta** não limpa o Storage — dívida já existente para `avatars`/`collection-cover`, não agravada.
5. **Custo:** ~60–180 KB por imagem; pior caso ≈ 90 MB por usuário (500 × ~180 KB); uso realista de poucos MB. URLs assinadas reduzem cache do navegador — mitigar reaproveitando a URL por sessão.
6. **Provas não cobertas pelo harness** (declaradas nele): JWT/PostgREST e API do Storage reais, duas sessões concorrentes, teto de 550 em volume. Exigem homologação manual na aplicação.
7. `set_slot_lock` em lote que inclua um bolso com imagem falha inteiro (atômico). O frontend só seleciona bolsos com carta para travar; registrado para o desenho da UI.

## 7. Próxima etapa recomendada

`P2-BINDER-CUSTOM-IMAGES-LIVE-PRECHECK-01` (somente leitura: bucket e políticas ausentes, numeração livre no ledger, corpos LIVE de 5126/5229-7b iguais à base dos diffs, privilégio UPDATE de `postgres` em `storage.objects`, gatilhos existentes em `storage.objects`) → aplicação 5231→5236 com autorização expressa, pós-checagem LIVE_90 (derivada da Seção 0 do 5852, somente leitura) + Advisor → promoção para `database/schema/` → frontend (aba **Imagem** no diálogo do bolso).

## Execução no LIVE — R1-pré (`P2-BINDER-CUSTOM-IMAGES-LIVE-PRECHECK-01`, 2026-10-23 ~18:40 UTC)

Autorização de Fabrício: "AUTORIZO EXCLUSIVAMENTE AS PRÉ-CHECAGENS DE LEITURA NO LIVE `mimikyu-core`". Executor `postgres` (current_user = session_user), PostgreSQL 17.6; cada bloco de `LIVE_00` (SHA-256 `2153a91a…1eb4`, inalterado) em `begin transaction read only; … rollback;` (`transaction_read_only = on` confirmado). Nada escrito; nenhuma migration, harness, arquivo ou frontend.

| Bloco | Resultado |
|---|---|
| PRE-1 | PASS — P1.1 (nenhuma 5231–5236) e P1.2 (5229 `20261023160611`, 5230 `20261023160800`) |
| PRE-2 | PASS 6/6 — pacote ausente |
| PRE-3 | PASS 5/5 — dependências, colunas do Storage, unicidade (bucket_id, name) |
| PRE-4 | PASS — P4.1–P4.4 ok com **md5 vivo = canônico** nos 4 corpos; P4.5 dois `true`; P4.6/P4.7 sem dependentes nem chamadores; P4.8: todos os escritores usam a trava do fichário, exceto `create_my_collection_binder` (exceção prevista: fichário novo) |
| PRE-5 | PASS — `postgres`: `rolbypassrls = true`, não superusuário; SELECT/INSERT/UPDATE/DELETE em `storage.objects`; INSERT em `storage.buckets`; dono de `storage.objects` = `supabase_storage_admin` (não membro), mas P5.2 = true (4 políticas `collection_cover_*` criadas por este caminho) e P5.3 = true |
| PRE-6 | PASS — RLS ligada (sem FORCE); 21 políticas, todas permissivas com `bucket_id = '<literal>'` em AND (revisão manual: nenhuma negação/lista; nenhuma alcança `binder-slot-image`); P6.3 = true; gatilhos `protect_objects_delete` (BEFORE DELETE, por statement, exige GUC `storage.allow_delete_query`) e `update_objects_updated_at` |
| PRE-7 | Baseline: collections 10 · allocations 211 · physical_cards 1352 · layouts 1 · guests 1 · pages 20 · slots 180 · assignments 155 · reservations 158 · locked 0 · regions 0 · buckets 6 · storage_objects 33805 · storage policies 21. fp_assignments `70626b64…ac8c0`, fp_reservations `c472fe7d…19a2`, fp_locked `d41d8cd9…427e` (vazio), fp_pages `61396f32…1e02`, fp_allocations `a180e923…73c0`, fp_storage_policies `39d876a9…4b8e` |
| PRE-8 | Sem sessões ativas nem travas de outras sessões nas tabelas listadas |

Parecer: **GO** para pedir a autorização do W1 (5231 → 5236). Nenhuma migration aplicada.

## Execução no LIVE — W1 (`P2-BINDER-CUSTOM-IMAGES-LIVE-APPLY-01`, 2026-10-23 18:50–18:55 UTC)

Autorização de Fabrício: "AUTORIZO EXPRESSAMENTE a aplicação das migrations 5231–5236 no LIVE `mimikyu-core`, exclusivamente conforme este protocolo."

**Gate (18:50:59 UTC, read only, `postgres`):** SHA-256 dos 6 arquivos = RUNBOOK; 5231–5236 ausentes do ledger; 0 sessões ativas e 0 travas de outras sessões; baseline idêntico ao PRE-7 (contagens e 6 md5).

**W1** — `apply_migration` com o bloco `begin;…commit;` integral de cada arquivo, um por vez, ledger conferido após cada um:

| Migration | Ledger | Resultado |
|---|---|---|
| 5231 | `20261023185120` | sucesso — bucket privado + 2 políticas |
| 5232 | `20261023185205` | sucesso — tabela, 6 gatilhos, política DELETE protegida |
| 5233 | `20261023185300` | sucesso — 4 funções (precheck de UPDATE em storage.objects passou) |
| 5234 | `20261023185331` | sucesso — 4 funções |
| 5235 | `20261023185359` | sucesso — `remove_layout_page` conta imagens |
| 5236 | `20261023185439` | sucesso — prévia/desmontagem com colunas novas |

**Pós-checagem (LIVE_90, read only):** POST-1 13/13 `ok`. POST-2: collections 10, allocations 211, physical_cards 1352, layouts 1, guests 1, pages 20, slots 180, assignments 155, reservations 158, locked 0, regions 0, storage_objects 33805 — **iguais ao PRE-7**; buckets 6→7 e políticas de `storage.objects` 21→24 (as 3 esperadas); images 0; objetos no bucket novo 0; os 5 md5 de dados e o md5 das 21 políticas preexistentes **idênticos** ao baseline. POST-3: 6 entradas na ordem. POST-4 (Advisor security): achados novos só nos objetos novos — `rls_enabled_no_policy` (INFO) na tabela nova, intencional (sem acesso direto; só RPC); `authenticated_security_definer_function_executable` (0029) nas 6 RPCs novas e em `binder_slot_image_path_is_linked` (necessária à política DELETE; responde só sobre a própria pasta). `remove_layout_page`/prévia/desmontagem já constavam antes. Nenhuma classe nova; nenhum achado `anon`.

Não executado: harness 5852, prova funcional F1–F7, frontend, promoção para `database/schema/`.
