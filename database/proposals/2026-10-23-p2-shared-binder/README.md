# P2-SHARED-BINDER — Fichário Digital compartilhado entre coleções

| Campo | Valor |
|---|---|
| **Rodada** | `P2-SHARED-BINDER-PROPOSAL-01` (2026-10-23); revisão `P2-SHARED-BINDER-AUDIT-CORRECTION-01` (2026-10-23) |
| **Status** | **5229 e 5230 CONFIRMADO EXECUTADO no LIVE (2026-10-23, `P2-SHARED-BINDER-LIVE-APPLY-01`).** Harness 5851 não executado (proibido no LIVE). Promoção para `database/schema/` pendente (fechamento documental). |
| **Decisões** | `concept-decisions.md` C-195–C-197 (emenda C-38/C-191) |
| **Depende de** | P2-A1 no LIVE (5223–5228) |
| **Ordem** | `5229` → `5230` → harness `5851` |

## Arquivos

| Arquivo | Conteúdo |
|---|---|
| `5229_create_collection_binder_sharing.sql` | tabela `collection_layout_guest`; coluna `expected_content.collection_id`; 4 gatilhos de integridade; evolução de 5117 (gatilho de posição), 5131 (`assign_card_to_slot`, mesma assinatura), 5225 (`set_slot_expected_content` + `p_collection_id`), 5226 (`delete_collection` + `BINDER_GUEST`); RPCs novas `attach_my_collection_to_binder`, `preview_my_collection_binder_detach`, `detach_my_collection_from_binder` (+ retrato interno) |
| `5230_evolve_get_my_collection_binder_for_sharing.sql` | cabeçalho e bolsos evoluídos (colunas novas só no fim); `list_my_binder_join_candidates`; `get_my_collection_binder_unplaced` |
| `5851_validate_p2_shared_binder.sql` | harness de um statement, 47 verificações + GATE, sentinela e resíduo zero — **não roda no LIVE** (cria dados) |
| `RUNBOOK-LIVE.md`, `LIVE_00_precheck_readonly.sql`, `LIVE_90_postcheck_readonly.sql` | aplicação controlada no LIVE: pré e pós-checagens só leitura, ordem 5229 → 5230, PASS/STOP |

Não mudam: `collection_layout` (5105/5136 — `collection_id` continua sendo a proprietária, UNIQUE e imutável), páginas, bolsos, `move_slot_assignment` (5132), `remove_slot_assignment` (5133), `clear_slot_expected_content` (5129), `set_slot_lock` (5130), montagem (5224), alocação/desalocação (5046/5047), progresso.

Desde a revisão `AUDIT-CORRECTION-01`, a 5229 também reescreve a desmontagem da 5226: `dismantle_my_collection_binder` recusa `BINDER_HAS_GUESTS` **antes** de remover qualquer coisa (e `COLLECTION_IS_BINDER_GUEST` quando quem chama é a convidada), e `preview_my_collection_binder_dismantle` ganha `guest_count` e `blocked_reason` (DROP+CREATE; o app ainda não usa a desmontagem). O gatilho de `DELETE` do layout continua como segunda barreira.

## Decisões aprovadas → onde estão

| # | Decisão | Tratamento |
|---|---|---|
| 1 | Associação explícita | só `attach_my_collection_to_binder` cria participação; nenhuma leitura ou escrita associa sozinha |
| 2 | Progresso e alocações independentes | nada toca `collection_allocation` nem os read models de completude; harness 3.8, 6.5 |
| 3 | Nada rearranjado | attach não escreve bolso/reserva (2.6) |
| 4 | Convidada posiciona manualmente | 5117/5131 aceitam alocação de participante; 5230 lista as cartas fora dos bolsos (3.1, 3.7) |
| 5 | Desassociar remove só o da convidada | detach apaga posições das alocações dela e reservas com `collection_id` dela (6.4, 6.5) |
| 6 | Fixados só com confirmação | `p_release_locks` obrigatório quando há bolso fixado afetado (6.2) |
| 7 | Desmontagem bloqueada | recusa na RPC antes de remover + prévia com `guest_count`/`blocked_reason`; gatilho e FK RESTRICT como segunda barreira (5.1, 5.4, 5.5) |
| 8 | Reserva registra a coleção | `collection_id` explícito, senão a da carta no bolso, senão a proprietária; NULL legado = proprietária (4.1–4.4) |
| 9 | Local identifica, não desfaz | attach exige mesmo fichário físico de algum participante; nada reage a mudança posterior de local |
| — | Participação única | PK da convidada + gatilhos dos dois lados (2.8, 2.11, 2.12) |

## Autorização

- Raiz inalterada: toda RPC resolve bolso/fichário pela **proprietária** com `owner_user_id = auth.uid()`; participantes são sempre do mesmo dono (gatilho), então nada passa a aceitar dado de outro usuário.
- Alocação de coleção não participante, inexistente ou de outro usuário → mesma mensagem (não enumera).
- Escrita na tabela de convidadas só pelas RPCs (sem DML para `anon`/`authenticated`); leitura direta por RLS do dono.
- Funções de gatilho e o retrato interno sem EXECUTE para a API.

## Concorrência

Ordem canônica (compatível com 5122/5224/5226): **proprietária → layout → convidada → bolso → alocação → posição**. Toda escrita no fichário passa pela trava do layout (5122), logo duas coleções participantes nunca escrevem no mesmo fichário ao mesmo tempo. Nenhum mecanismo novo: só travas de linha já usadas.

| Corrida | Resultado |
|---|---|
| associar × desmontar | ambas travam a proprietária primeiro; quem chegar depois vê o estado final (desmontagem → `BINDER_HAS_GUESTS`; associação → `BINDER_NOT_FOUND`) |
| associar × montar fichário próprio da mesma coleção | ambas travam a linha da coleção; o gatilho do lado perdedor recusa (`COLLECTION_IS_BINDER_GUEST` ou `COLLECTION_HAS_OWN_BINDER`) |
| desassociar × mover/posicionar | ambas travam o layout antes; o token da prévia muda se algo da convidada mudou (`DETACH_PLAN_CHANGED`) |
| duas coleções posicionando no mesmo fichário | serializadas pelo layout; o bolso continua com UNIQUE adiado |
| arquivar convidada × posicionar carta dela | `assign` trava a convidada (FOR SHARE) **antes** da alocação; arquivar trava só a coleção — sem ciclo |
| desalocar carta da convidada (5047) × posicionar/mover | 5047: coleção → alocação → posição (cascata), sem trava de layout. `assign` trava convidada antes da alocação (mesma ordem); o gatilho de posição **não** trava coleção (lê o estado) — o ciclo `move` (posição) × `5047` (coleção → posição) da v1.0 foi removido |
| desalocar × desassociar | 5047 pega a convidada primeiro e não precisa do layout; detach espera pela convidada segurando proprietária+layout — sem ciclo |

### Roteiro manual de duas sessões (não coberto pelo harness)

- **K1** S1: `attach(CG, L)` sem commit · S2: `dismantle(CO)` → espera; S1 commit → S2 `BINDER_HAS_GUESTS`.
- **K2** S1: `create_my_collection_binder(CG)` sem commit · S2: `attach(CG, L)` → espera; S1 commit → S2 `COLLECTION_HAS_OWN_BINDER`.
- **K3** S1: `move_slot_assignment` de carta da convidada sem commit · S2: `detach(CG, token)` → espera; S1 commit → S2 `DETACH_PLAN_CHANGED`.
- **K4** S1: `assign_card_to_slot` (CG) · S2: `assign_card_to_slot` (CO) no mesmo fichário → S2 espera e conclui depois; sem deadlock.

## Experiência (frontend, próxima rodada — preserva o workspace atual)

Vocabulário: **Cartas disponíveis** = exemplares da coleção ainda não posicionados (persistente, vem de `get_my_collection_binder_unplaced`); **Bandeja** = transporte temporário entre páginas, sem persistência. Não confundir as duas na interface.

1. **Detectar:** o cabeçalho traz `join_candidate_count`; com valor > 0 e sem fichário, a entrada "Fichário digital" passa a ser "Usar o fichário de ME5.5" (secundário: "Montar um novo").
2. **Prévia:** `list_my_binder_join_candidates` dá modelo, páginas, bolsos livres e participantes; texto: nada da ME5.5 será movido, as cartas da ME5.5CC começam fora dos bolsos.
3. **Confirmar:** `attach_my_collection_to_binder`.
4. **Abrir:** qualquer participante abre o mesmo fichário (cabeçalho e bolsos resolvem pela convidada).
5. **Organizar:** um painel "Cartas disponíveis" lista as cartas de `get_my_collection_binder_unplaced`; arrastar/escolher bolso usa as ações existentes. A Bandeja continua só para mover entre páginas. `present_collection_id` permite atenuar cartas de outra coleção ("Só desta coleção").
6. **Desassociar:** em Ajustes, prévia (`preview_my_collection_binder_detach`) com contagens e bolsos fixados; confirmação; o progresso não muda.

## Retrocompatibilidade

- Assinaturas de entrada preservadas; `set_slot_expected_content` ganha um parâmetro opcional no fim (chamadas nomeadas atuais continuam válidas).
- Cabeçalho e bolsos só ganham colunas no fim; para quem não compartilha, as colunas antigas mantêm o mesmo valor.
- Reserva do app atual ("reservar para a carta que está no bolso") passa a ser atribuída automaticamente à coleção dessa carta.

## Verificações estáticas realizadas (2026-10-23)

- Dollar-quotes pareados e `begin;`/`commit;` 1:1 em 5229 e 5230; parênteses balanceados no código.
- Colunas referenciadas conferidas contra `database/schema` (`kind_code`, `default_storage_container_id`, `collector_order`, `variant_order`, `printing_profile_id`, `edition_context_profile_id`).
- 47 verificações no harness, ids únicos (F.1 aparece em dois ramos exclusivos), `v_expected` consistente.
- Nenhuma função criada duas vezes no mesmo arquivo; `git diff --check` limpo.
- **Não** feito: execução em banco (sem ambiente; nada no LIVE).

## Revisão AUDIT-CORRECTION-01 (2026-10-23)

| Risco | Achado | Correção |
|---|---|---|
| A. Desmontagem | v1.0 só barrava no `DELETE` do layout, depois de apagar posições/reservas (revertido, mas tarde) e sem aviso na prévia | recusa no início da RPC sob as mesmas travas; prévia com convidadas; convidada recebe `COLLECTION_IS_BINDER_GUEST` em vez de `ALREADY_ABSENT` |
| B. Desalocação | 5047 apaga a alocação e a posição sai por `ON DELETE CASCADE` (5115; 5118 permite) — sem órfã; a reserva fica com a coleção da convidada, que segue participante (coerente; some na desassociação); autorização por dono na própria 5047 | nenhuma no contrato; harness 5.6 |
| C. Concorrência | **ciclo real na v1.0**: gatilho de posição travava a convidada (`FOR SHARE`) depois da posição/alocação, enquanto 5047 trava convidada → alocação → posição | gatilho lê sem trava; `assign` trava a convidada antes da alocação; harness 5.7 (entrada e movimento recusados com convidada arquivada) |
| D. Participação exclusiva | PK da convidada + gatilho na inserção de convidada (não pode ter layout próprio, mesmo dono) + gatilho na criação de layout (não pode ser convidada); ambos sob a trava da linha da coleção (5224 e attach a pegam `FOR UPDATE`) | nenhuma; harness 2.4, 2.8, 2.11, 2.12, 1.2–1.4 |

## Riscos remanescentes

- **Arquivar convidada × mover carta dela — concluído em `LIVE-READINESS-01`, sem violação.** `archive_collection` (5037) é um único `UPDATE … WHERE lifecycle_status = 'ACTIVE'`; não lê nem escreve posições. O gatilho de posição lê o status sem trava. Se o arquivamento ainda não estiver confirmado quando o gatilho lê, o movimento conclui; os dois commits equivalem à ordem serial "mover → arquivar" (nenhuma escrita conflitante, nenhuma leitura do arquivamento sobre posições). Não há instante em que uma coleção já arquivada (commit visível) aceite movimento: depois do commit do arquivamento, o próximo movimento é recusado. C-37 preservado. Forçar a espera (`FOR SHARE`/`FOR KEY SHARE`) reintroduziria o ciclo com a 5047 ou não bloquearia o `UPDATE` — não vale a troca.

## Execução no LIVE (2026-10-23, projeto `mimikyu-core`)

Autorizações: R1-pré em `P2-SHARED-BINDER-LIVE-PRECHECK-01`; W1 em `P2-SHARED-BINDER-LIVE-APPLY-01` ("AUTORIZO EXPRESSAMENTE A APLICAÇÃO DAS MIGRATIONS 5229 E 5230 NO LIVE `mimikyu-core`").

| Etapa | Resultado |
|---|---|
| PRE-1…PRE-6 (15:33–15:36 UTC) | PASS; P3.7/P3.8 `false` só por defeito do precheck (marcadores existem apenas em RETURNS TABLE; md5 vivo = canônico) |
| Gate (16:02 UTC) | sem sessões/travas; ledger sem 5229/5230; SHA-256 conferidos (5229 `ac957bb2…7a90`, 5230 `0a6cc1f3…f1038`) |
| W1 5229 | sucesso — ledger `20261023160611 5229_create_collection_binder_sharing` |
| W1 5230 | sucesso — ledger `20261023160800 5230_evolve_get_my_collection_binder_for_sharing` |
| POST-1 | 14/14 `ok` |
| POST-2 | layouts 1, páginas 18, bolsos 162, posições 148, reservas 158, fixados 0, regiões 0, alocações 211 = PRE-5; convidadas 0; reservas com coleção 0 |
| Impressões digitais (md5 das linhas) | idênticas antes/depois: layout, páginas, bolsos, posições, reservas (sem a coluna nova), alocações, cartas físicas (1352), locais (2), coleções (10) |
| POST-4 Advisor | mesmas 6 classes; novos itens só em `authenticated_security_definer_function_executable` (as 5 RPCs novas — lint 0029 esperado); `collection_layout_guest` fora de `rls_enabled_no_policy`; nada novo para `anon` |

Inventário: proprietária "Celebração de 30 Anos" (ME5.5, fichário 3×3, local F001); única candidata "Coleção Clássica" (ME5.5CC, mesmo local, 7 cartas) — **não associada** (W2 exige autorização própria).

Defeitos conhecidos do `LIVE_00` (não corrigidos, não executáveis no LIVE): P3.7/P3.8 procuram marcadores no `prosrc`; a busca do PRE-5 por `ilike '%ME5.5%'` no nome da coleção não encontra nada (os nomes são em português; usar `card_set.code`).

## Reversão

Ver o rodapé de cada arquivo (5230 antes da 5229). Segura enquanto `guests = 0` e `reservations_with_collection = 0`.
