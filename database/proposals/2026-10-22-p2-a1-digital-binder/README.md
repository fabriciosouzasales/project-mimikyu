# P2-A1 — Fichário Digital: leitura, montagem automática e desmontagem (PROPOSTA)

| Campo | Valor |
|---|---|
| Rodada | P2-A1-PROPOSAL-01 (2026-10-22) → P2-A1-PROPOSAL-AUDIT-CORRECTION-01 → -FINAL-CONSOLIDATION-01 → P2-A1-LIVE-READINESS-01 (2026-10-23) |
| Status | **PROPOSTO — NADA EXECUTADO.** Nenhum SQL rodou no LIVE. Nenhuma migration aplicada, nenhuma RPC chamada. |
| Governança | **O projeto não usa ambiente isolado, staging ou banco de testes** (Fabrício, 2026-10-23). A execução segue `RUNBOOK-LIVE.md`. |
| Base | HEAD `54323de` (`main`), árvore limpa no início |
| Decisões | D1–D9 e R1–R5 (P2-A1 DISCOVERY-01, REFINEMENT-01/02, PROPOSAL-01) |
| Auditoria | 2026-10-23: STOP — não executar. Correções desta pasta respondem aos itens 1–5 da auditoria; ver "Auditoria — correções" abaixo. |
| Próximo passo | Pré-checagens SÓ LEITURA no LIVE (`LIVE_00`) → gate de autorização → seis contratos (W1) → pós-checagens SÓ LEITURA (`LIVE_90`) → fechamento documental → P2-B. Cada etapa com autorização própria. |

## Arquivos

| Ordem | Arquivo | O que faz |
|---|---|---|
| 1 | `5225_extend_slot_expected_content_variant_type.sql` | M3: `expected_variant_type_id` na reserva do bolso (carta + acabamento), FK RESTRICT, CHECK de exclusividade com `card_variant_id`, trigger de mesmo jogo, `set_slot_expected_content` com 4 argumentos (substitui a de 3; 5128 evolui) |
| 2 | `5223_create_get_my_collection_binder_functions.sql` | `get_my_collection_binder` (cabeçalho, elegibilidade, contagens) e `get_my_collection_binder_pages` (1–4 páginas; estados EMPTY / RESERVED_EMPTY / OCCUPIED_UNPLANNED / OCCUPIED_MATCH / OCCUPIED_MISMATCH por granularidade da reserva) |
| 3 | `5224_create_collection_binder_plan_preview_create.sql` | helper interno `collection_binder_plan` (plano determinístico + token do plano resultante), `preview_my_collection_binder`, `create_my_collection_binder` (transacional, uma vez) |
| 4 | `5226_create_collection_binder_dismantle_and_update_delete_collection.sql` | helper `collection_binder_dismantle_snapshot`, `preview_my_collection_binder_dismantle`, `dismantle_my_collection_binder` (confirmada, atômica, também em coleção arquivada) e `delete_collection` v1.4 (recusa com fichário, erro de domínio, sem cascata) |
| 5 | `5227_restrict_create_collection_layout_to_binder_assembly.sql` | **Decisão A aprovada como proposta (v1.1):** revoga EXECUTE de `create_collection_layout` (5123) de PUBLIC/anon/authenticated, preservando corpo e assinatura; pós-checagem da matriz efetiva |
| 6 | `5228_restrict_set_collection_layout_grid_to_seven_models.sql` | **Decisão B aprovada como proposta (nova):** `set_collection_layout_grid` (5137 v1.1 = 5141) aceita só os sete modelos; mesma assinatura/retorno/regras; 22023 INVALID_GRID sem gravar |
| — | `5850_validate_p2_a1_digital_binder.sql` | harness v1.2 — **NÃO EXECUTÁVEL NO LIVE em nenhum modo** (cria função em `pg_temp` e insere fixtures sintéticas da Seção F em diante). Mantido como especificação de comportamento; as checagens estruturais 0.1–0.10 viraram o `POST-1` do `LIVE_90` |
| — | `RUNBOOK-LIVE.md` | runbook enxuto: classes R1/W1/R2, ordem, gate, PASS/STOP, conduta em erro, reversão, evidência |
| — | `LIVE_00_precheck_readonly.sql` | pré-checagens R1 (`PRE-1`…`PRE-7`), só SELECT em `begin transaction read only` |
| — | `LIVE_90_postcheck_readonly.sql` | pós-checagens R1 (`POST-1`…`POST-4`) |
| — | `static_check_p2_a1.py` | verificação TEXTUAL sem banco (75 checks; não compila SQL) |

Ordem obrigatória: **5225 → 5223 → 5224 → 5226 → 5227 → 5228**. A 5223 lê `expected_variant_type_id` (precisa da 5225); a 5224 grava reservas com acabamento; a 5226 inclui a coluna no token de desmontagem; a 5227 exige a 5224 (único caminho de criação depois dela); a 5228 não depende das demais no banco e fecha D2 por último. Cada arquivo tem precheck fail-loud; 5227 e 5228 têm também pós-checagem da matriz de EXECUTE.

## Dependências (todas CANÔNICAS e no LIVE)

5105–5137 (Layout Foundation), 5039 v1.3 / 5048, 5046/5047, 5070/5169 (Set), 5184/5187/5198 (Master Set), 6040/6117/6120/5091/5202/5204/5210 (Pokédex), 5212/5213/5216–5218 (tipo do local), 5220 (regra de imagem).

## Contrato resumido

**Tipos e universo** — FREE (OPEN_CURATION), SET (STANDARD_SET), MASTER_SET, POKEDEX (REFERENCE_POSITION). O universo de posições de cada tipo vem da MESMA fonte do progresso (5169 / `master_set_positions` / escopo da 5204); nenhuma regra paralela.

**Modelos (D2)** — 2×2, 3×3, 3×4, 4×3, 4×4, 4×5, 5×4 em **colunas × linhas**: "3×4" = `grid_columns = 3`, `grid_rows = 4`. Colocação por linhas.

**Exemplares adicionais (R1/R2/R5)** — idêntica = mesma `card_variant_id` **e** mesmo `language_id`. Categoria única por exemplar, precedência FORA DO OBJETIVO > IDÊNTICA > OUTRO IDIOMA > OUTRA VARIANTE. `PRINCIPAL_ONLY` deixa sem bolso; `APPEND_PAGES` põe em páginas próprias depois do checklist. A opção não é persistida; entra no token.

**Token do plano** — `v1:` + SHA-256 da serialização canônica do plano RESULTANTE (cabeçalho + uma linha por item). Não é contagem: desalocar o que foi alocado restaura o mesmo token (harness 10.2).

**Elegibilidade (D1)** — criar exige coleção ACTIVE e local padrão do próprio acervo com `kind_code = 'BINDER'`, lido no servidor sob a trava da coleção. Depois de criado, o fichário independe do local.

**Erros** — 28000, 22023 (INVALID_ARGUMENT / INVALID_GRID / INVALID_EXTRA_POLICY / INVALID_PLAN_TOKEN / INVALID_DISMANTLE_TOKEN / EXPECTED_CONTENT_VARIANT_AND_TYPE_EXCLUSIVE), P0002 COLLECTION_NOT_FOUND (alheia = inexistente), 55000 (COLLECTION_ARCHIVED / NOT_ELIGIBLE), 54000 COLLECTION_TOO_LARGE, P0001 (PLAN_CHANGED / LAYOUT_ALREADY_EXISTS / DISMANTLE_PLAN_CHANGED / *_INCONSISTENT), 23514 (EXPECTED_VARIANT_TYPE_GAME_MISMATCH), 55P03 (lock_timeout).

## Concorrência — A/B/C (revisada na auditoria)

O token **não** oferece isolamento transacional; detalhes com referência a cada contrato no cabeçalho da 5224.

| Classe | O quê | Por que é seguro |
|---|---|---|
| **A. Serializado** (trava FOR UPDATE da coleção, tomada também por todos estes) | alocar/desalocar (5046/5047), lote com coleção (5148 → 5150/5152/5153/5155/5157), objetivo e acabamentos (5194/5195/5081), vínculos e representante da Pokédex (6123/6124/6125/6126/5210), gerações (5099/5203), arquivar/reativar/local padrão/metadados (5037/5038/5036/5035), toda edição de layout (5122 → 5124–5137), 5123 | não acontecem entre o cálculo do plano e o commit; criação concorrente → ALREADY_EXISTS + UNIQUE(collection_id) |
| **B. Detectado pelo token** | tudo de A que ocorra antes da trava; catálogo (2116/2117, 2155–2157, 2048 — inclui `base_set_size`), modelo e opção diferentes | PLAN_CHANGED, nada gravado |
| **C. Pode ocorrer entre cálculo e commit** | catálogo editado pelo admin; tipo do local trocado (5217) | plano calculado num único comando é o que se grava; FKs RESTRICT (exclusão concorrente → 23503 e rollback total); troca de tipo equivale a "criou, depois trocou" e D1 preserva o acesso; exclusão do local padrão é recusada pela 5218 |

Identidade do exemplar (variante, idioma, `created_at`) não tem escritor; só `storage_container_id` muda (5024/5222), e não entra no plano.

## Roteiro manual de DUAS SESSÕES (K1–K6) — fora do harness, NÃO executado

**Não executável**: o projeto não usa ambiente isolado e o roteiro exige catálogo, usuário e coleção sintéticos — gravação no LIVE. Fica como especificação. A concorrência permanece **sem prova comportamental** (ver `RUNBOOK-LIVE.md` §9).

**Preparação (uma vez, como dono do banco, COMMIT em transação própria):** criar o mesmo catálogo sintético e o usuário A da Seção F do `5850` (expansão `P2A1K_<sufixo>`, Set de 4 cartas, local `BINDER`, coleção Set `CK` com 2 exemplares alocados, exemplar livre `x`). Anotar `C = CK.id`, `x`.
**Em cada sessão, antes de cada passo:** `begin; select set_config('request.jwt.claims', json_build_object('sub', '<A>', 'role','authenticated')::text, true); set local role authenticated;`
**Observação obrigatória:** numa terceira conexão (dono), `select pid, pg_blocking_pids(pid), wait_event_type, left(query,60) from pg_stat_activity where datname = current_database() and state <> 'idle';` enquanto S2 espera — PASS exige `pg_blocking_pids(S2) = {S1}`.
**Limpeza:** script de remoção do catálogo/usuário de teste (mesma ordem inversa da Seção F) e conferência de resíduo zero com a consulta do 99.1.

| ID | S1 (sem commit) | S2 | Esperado (PASS) |
|---|---|---|---|
| K1 | `preview` → T; `select * from create_my_collection_binder(C,3,3,'PRINCIPAL_ONLY',T);` | mesma chamada com T | S2 bloqueada por S1; após `commit` de S1, S2 = `ALREADY_EXISTS`; 1 layout |
| K2 | `create_my_collection_binder(...)` | `allocate_physical_cards_to_collection(C, array[x])` | S2 bloqueada; após o commit de S1, S2 aloca; `x` sem bolso; contagens da 5223 coerentes |
| K3 | `allocate_physical_cards_to_collection(C, array[x])` | `create_my_collection_binder(C,..., T)` com T da prévia anterior | S2 bloqueada; após o commit de S1 → `PLAN_CHANGED`; nenhum layout |
| K4 | `dismantle_my_collection_binder(C, D)` | `assign_card_to_slot(<bolso de C>, <alocação>)` | S2 bloqueada (5122); após o commit de S1 → erro de layout inexistente; nada órfão |
| K5 | `dismantle_my_collection_binder(C, D)` | `delete_collection(C)` | S2 bloqueada; após o commit de S1 segue as regras normais (recusa por alocações) |
| K6 | `select 1 from public.collection where id = C for update;` (dono) e aguardar 6 s | `create_my_collection_binder(...)` | S2 falha com 55P03 em ~5 s; nada gravado |

## Volume — teto PROVISÓRIO, NÃO APROVADO

`c_max_allocations = 10 000` e `c_max_slots = 20 000` existem como proteção, sem medição. A Seção P do harness **não roda** (exige fixtures; nenhuma carga no LIVE). O teto segue provisório; revisão só com evidência de uso real.

## Riscos

| # | Severidade | Risco | Tratamento |
|---|---|---|---|
| R-1 | Média | Teto de volume sem medição | Provisório, aceito como proteção; sem benchmark no LIVE |
| R-2 | Média | `create_my_collection_binder` com 10 000 posições dispara triggers por linha (5112/5117/5118) | Não medido; set-based evita N+1 de RPC; `lock_timeout` 5s limita a espera |
| R-3 | Média | A 5225 faz DROP da `set_slot_expected_content` de 3 argumentos | Precheck de `pg_depend` **e** busca textual em `prosrc`; nenhum caller no repositório; ACL recriada com a mesma matriz |
| R-9 | Alta → fechada pela 5227 (proposta) | `create_collection_layout` (5123) criava fichário sem D1/D2/D3 | 5227 aprovada como proposta; prova estrutural: `POST-1` 0.8/0.10; comportamental: sonda R2 S1 (42501) |
| R-10 | Média → fechada pela 5228 (proposta) | `set_collection_layout_grid` aceitava grade fora dos 7 modelos com zero páginas | 5228; prova estrutural: `POST-1` 0.9/0.10; comportamental: SEM PROVA (a recusa depende de trava, impossível em `read only`) |
| R-11 | Informativa | Layouts já existentes no LIVE não verificados | `PRE-6` lê contagem e distribuição de grades antes do gate; `> 0` é decisão de Fabrício, não falha |
| R-4 | Média | Desmontagem ignora travas de bolso (C-45) | Intencional e confirmado: a prévia mostra os travados e eles entram no token |
| R-5 | Baixa | Prévia calcula o plano completo (CTE materializada) | Uma execução por chamada; mesmo custo da criação |
| R-6 | Baixa | Pokédex: só posições com vínculo; sem reservas | Decisão D3; documentado |
| R-7 | Baixa | `delete_collection` muda de corpo (5039 v1.4) | Mesma assinatura e retorno; precheck exige o corpo v1.3 vivo |
| R-8 | Média | Concorrência sem prova comportamental (K1–K6 não executáveis) | Desenho revisado (A/B/C); travas e token por inspeção; declarado como limitação |

## Sequência recomendada

Substituída em 2026-10-23 (`P2-A1-LIVE-READINESS-01`): ver `RUNBOOK-LIVE.md` §3. Resumo: auditoria estática → R1 pré no LIVE → gate → W1 (5225 → 5223 → 5224 → 5226 → 5227 → 5228) → R1 pós → fechamento documental → P2-B. Nenhuma etapa usa ambiente isolado; `5850`, Seção P e K1–K6 não rodam.

## Auditoria — correções (2026-10-23, P2-A1-PROPOSAL-AUDIT-CORRECTION-01)

| Arquivo | Versão | Correção |
|---|---|---|
| 5227 | 1.0 (nova) | Fecha a 5123 para `authenticated` (bloqueador 5123 × D1) |
| 5224 | 1.1 | Concorrência reescrita em A/B/C; afirmação falsa sobre a 5218 corrigida (ela recusa, não atualiza); aliases explícitos no `generate_series`; erros completados |
| 5223 | 1.1 | `can_create` falso para tipo `UNKNOWN` |
| 5225 | 1.1 | Precheck textual de chamadores; semântica do upsert e privilégios documentados |
| 5226 | 1.1 | Só a ordem do pacote |
| 5850 | 1.1 | **Defeito real:** a Seção P alocava até 10 000 por chamada — a 5046 recusa > 500, a v1.0 abortaria. Lotes de 500. Função de falha da 11.1 fora de `pg_temp`, removida e conferida. Precheck fail-loud da Pokédex. GATE exige IDs distintos. Novos 0.8 e 1.7 (5227). 59 funcionais |
| static check | — | 61 checks; perfis S10–S13; mutações negativas detectadas |

Na rodada de correção a documentação canônica não foi alterada; ela é reconciliada na consolidação final abaixo.

## Consolidação final (2026-10-23, P2-A1-PROPOSAL-FINAL-CONSOLIDATION-01)

**Decisões de Fabrício:** A — 5227 (alternativa A) aprovada **como proposta**; B — alteração de grade preservada, restrita aos sete modelos. Nenhuma das duas autoriza aplicar em banco.

**Matriz de EXECUTE pretendida (depois do pacote):**

| Função | PUBLIC | anon | authenticated | Observação |
|---|---|---|---|---|
| `create_collection_layout` (5123) | não | não | **não** (5227) | dono executa; service_role inalterado (não usado pelo app) |
| `set_collection_layout_grid` (5137/5141→5228) | não | não | sim | só os sete modelos |
| `create_my_collection_binder`, `preview_my_collection_binder` (5224) | não | não | sim | único caminho de criação |
| `get_my_collection_binder`, `get_my_collection_binder_pages` (5223) | não | não | sim | leitura |
| `preview_my_collection_binder_dismantle`, `dismantle_my_collection_binder` (5226) | não | não | sim | |
| `set_slot_expected_content(uuid,uuid,uuid,uuid)` (5225) | não | não | sim | substitui a de 3 argumentos |
| `delete_collection` (5039 v1.4 via 5226) | não | não | sim | inalterado |
| `collection_binder_plan`, `collection_binder_dismantle_snapshot` | não | não | não | helpers internos; também sem service_role |
| `enforce_expected_content_variant_type_game` | não | não | não | função de trigger |

**Sem caminho alternativo:** criação de layout executável por `authenticated` = só `create_my_collection_binder` (valida D1, D2, D3); alteração de grade executável = só `set_collection_layout_grid`, que valida D2. Conferido no LIVE, depois da aplicação, pelo `POST-1` 0.10 (busca textual + privilégio efetivo) — pendente de execução.

**Contagens:** harness 67 funcionais (especificação; não executável no LIVE); verificador 75/75; 18 mutações negativas detectadas (uma mutação inefetiva — N08, que trocava só um texto — foi substituída por N08b/N08c). Nada executado.

## Execução no LIVE — pré-checagens R1 (2026-10-23, `P2-A1-LIVE-PRECHECK-01`)

Autorização de Fabrício, literal: "GO exclusivamente para pré-checagens de leitura no LIVE." Projeto `qjfutqujxrbzgrtkpgkg` (`mimikyu-core`), PostgreSQL 17.6, usuário `postgres`. Cada bloco rodou em `begin transaction read only; … rollback;` (confirmado `transaction_read_only = on`). Janela: 11:52–11:54 UTC. Nenhuma escrita, migration, RPC, harness ou fixture.

| Bloco | Resultado |
|---|---|
| PRE-1 | ledger termina em `20261022194352` `5222_create_organize_my_collection_storage_function`; nenhuma entrada do pacote |
| PRE-2 | P2.01–P2.10 todas `ok` |
| PRE-3 | P3.1–P3.3 `ok`; md5 vivo = canônico: `delete_collection` `0be52e91…` (5039 v1.3), `set_collection_layout_grid` `c0023d1a…` (5137 v1.1); `create_collection_layout` `eb1782ff…` |
| PRE-4 | P4.1–P4.3 `ok` (sem dependentes nem chamadores) |
| PRE-5 | 5123, 5137, 5128 (3 args), 5039: `auth_exec` sim; `anon_exec`, `svc_exec`, `public_grant`, `acl_is_default` não; ACL `authenticated:EXECUTE, postgres:EXECUTE`. `anon`/`authenticated` sem superuser/bypassrls e sem pertença a outros papéis; `authenticator` membro de `anon`/`authenticated`/`service_role` (`noinherit`). Default ACL de funções em `public`: `supabase_admin` → postgres/anon/authenticated/service_role; `postgres` → só postgres |
| PRE-6 | baseline: collections 10, allocations 211, physical_cards 1352, storage_containers 2, layouts 0, pages 0, slots 0, expected_content 0, assignments 0, regions 0; distribuição de grades vazia |
| PRE-7 | nenhuma sessão não ociosa visível além da própria; nenhuma trava nas tabelas-alvo |
| Security Advisor | lint 0029 (`authenticated_security_definer_function_executable`) = **180** (inclui 5123, 5137, 5128, 5039); 0028 anon = 1 (`username_available`, preexistente); `function_search_path_mutable` 1 (`enforce_user_profile_invariants`, preexistente); `extension_in_public` 1 (`pg_net`); `auth_leaked_password_protection` 1; 0008 INFO 31. Esperado depois do pacote: 0029 = 185 (+6 RPCs novas, −1 `create_collection_layout`; 4 args no lugar de 3 args) |

Divergências em relação ao runbook (não materiais): (1) o ledger usa o nome do arquivo sem prefixo (`5222_create_…`); o prefixo `p2a1_` sugerido no §3 do runbook não segue a convenção — usar o nome do arquivo sem `.sql`. (2) `service_role` não tem EXECUTE nas funções-base (a 5227 diz "inalterado", o que continua verdadeiro). (3) Funções criadas por `postgres` não recebem grants automáticos para `anon`/`authenticated`; os arquivos já revogam e concedem explicitamente. (4) PRE-7 reflete o que a conexão consegue ver em `pg_stat_activity`.

## Execução no LIVE — aplicação W1 (2026-10-23, `P2-A1-LIVE-APPLY-01`)

Autorização de Fabrício, literal: "AUTORIZAÇÃO EXPRESSA DO PROPRIETÁRIO PARA APLICAÇÃO DAS SEIS MIGRATIONS NO LIVE." Reconfirmação antes da primeira aplicação (11:58 UTC, `read only`): ledger, contagens, corpos 5039/5137 (md5) e `auth_exec` da 5123 idênticos aos PRE-1…PRE-7; nenhuma sessão ativa. Cada arquivo foi aplicado por `apply_migration`, uma vez, com o texto do arquivo de `begin;` a `commit;` (o comentário final de cada arquivo não foi enviado). Nenhum erro, nenhuma repetição.

| # | Ledger | Resultado | md5 dos corpos no banco = arquivo |
|---|---|---|---|
| 1 | `20261023115904` `5225_extend_slot_expected_content_variant_type` | success | trigger `2efe9bbc…`, `set_slot_expected_content` (4 args) `cb9fd887…` |
| 2 | `20261023120014` `5223_create_get_my_collection_binder_functions` | success | `0edb4bce…`, `2d69e4d1…` |
| 3 | `20261023120222` `5224_create_collection_binder_plan_preview_create` | success | `e98b5598…`, `936f2155…`, `5ba7941f…` |
| 4 | `20261023120339` `5226_create_collection_binder_dismantle_and_update_delete_collection` | success | `49350360…`, `ee7445c0…`, `39406cb4…`, `delete_collection` v1.4 `9885f638…` |
| 5 | `20261023120426` `5227_restrict_create_collection_layout_to_binder_assembly` | success (pós-checagem embutida passou) | corpo da 5123 inalterado `eb1782ff…`; `authenticated`/`anon` sem EXECUTE |
| 6 | `20261023120522` `5228_restrict_set_collection_layout_grid_to_seven_models` | success (pós-checagem embutida passou) | `fe2d801d…` |

Pós-checagens (`LIVE_90`, `read only`, 12:06 UTC): POST-1 0.1–0.10 **10/10 PASS**. POST-2: collections 10, allocations 211, physical_cards 1352, storage_containers 2, layouts/pages/slots/expected_content/assignments/regions 0, `expected_with_type` 0 — idênticos ao baseline; md5 do conteúdo integral de `physical_card` (`8a980711…`), `collection_allocation` (`7453358e…`), `storage_container` (`7a73c8e8…`) e `collection` (`784501b4…`) iguais antes e depois — nenhuma carta física, alocação, local ou coleção modificada. POST-3: seis entradas, na ordem. POST-4 (Security Advisor): lint 0029 180 → **185** (+ `get_my_collection_binder`, `get_my_collection_binder_pages`, `preview_my_collection_binder`, `create_my_collection_binder`, `preview_my_collection_binder_dismantle`, `dismantle_my_collection_binder`; `set_slot_expected_content` trocou de assinatura; − `create_collection_layout`); demais achados idênticos aos preexistentes; helpers e função de trigger fora da lista.

Não executado: harness `5850`, fixtures, sondas R2, carga. Comportamento das RPCs novas segue **sem prova comportamental** (ver `RUNBOOK-LIVE.md` §9). Pendentes (fechamento documental, com autorização própria): promoção para `database/schema/` e reconciliação de 05d/ROADMAP/HANDOFF/INDEX.
