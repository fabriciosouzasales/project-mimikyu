# RUNBOOK LIVE — Fichário compartilhado (5229 → 5230)

| Campo | Valor |
|---|---|
| Versão | 1.0 (2026-10-23, `P2-SHARED-BINDER-LIVE-READINESS-01`) |
| Status | **PREPARADO — NADA EXECUTADO.** |
| Governança | Sem ambiente isolado, staging ou banco de testes. No LIVE só o que é seguro lá. |
| Quem executa | Fabrício, ou o agente com autorização expressa **por etapa** |

## 1. Classes

| Classe | O quê | Arquivo | Autorização |
|---|---|---|---|
| **R1** | leitura de catálogo e contagens em `begin transaction read only` | `LIVE_00_precheck_readonly.sql`, `LIVE_90_postcheck_readonly.sql` | uma para o R1-pré, outra para o R1-pós |
| **W1** | DDL: `5229` → `5230` | arquivos da pasta, conteúdo integral | **expressa e separada**; aprovar R1 não aprova W1 |
| **R2** | sondas de leitura das RPCs com o usuário real (§7) | só neste runbook | opcional, separada |
| **W2** | associar ME5.5CC ao fichário da ME5.5 (ação de produto) | via app ou RPC `attach_my_collection_to_binder` | expressa; é a primeira escrita real do recurso |
| **PROIBIDO** | `5851` em qualquer modo; K1–K4; fixtures; carga | — | — |

O `5851` cria usuários, catálogo, coleções e fichários sintéticos. Rollback não muda a classe: grava, dispara gatilhos e trava tabelas de produção. Suas checagens estruturais foram extraídas para o `POST-1` do `LIVE_90`.

## 2. Pré-requisitos

1. P2-A1 aplicada no LIVE (5223–5228) — confirmada pelo `PRE-1`/`PRE-2`.
2. Arquivos 5229 v1.1 e 5230 v1.0 desta pasta, sem alteração depois da revisão; registrar SHA-256 de cada um.
3. Janela sem uso do app (o app atual chama `set_slot_expected_content`, `get_my_collection_binder*` e a desmontagem não é usada).
4. Ferramenta: Supabase MCP (`execute_sql` em R1/R2, `apply_migration` em W1) ou SQL Editor com o mesmo texto.

## 3. Ordem

| # | Etapa | Classe | Comando |
|---|---|---|---|
| 0 | `PRE-1`…`PRE-6` | R1 | `LIVE_00`, bloco a bloco, em `begin transaction read only; … rollback;` |
| — | **GATE** (§4) | — | — |
| 1 | `5229` | W1 | `apply_migration`, nome `p2sb_5229_create_collection_binder_sharing` |
| 2 | `5230` | W1 | `apply_migration`, nome `p2sb_5230_evolve_get_my_collection_binder_for_sharing` |
| 3 | `POST-1`…`POST-4` | R1 | `LIVE_90` + `get_advisors(security)` |
| 4 | Fechamento documental | — | promoção para `database/schema/`, 05d, HANDOFF, log |
| 5 | Frontend (associação, cartas disponíveis, desassociação) | — | rodada própria |
| 6 | Associar ME5.5CC | W2 | autorização própria |

Cada arquivo é uma transação com pré-checagem fail-loud: um erro desfaz o arquivo inteiro. Entre 5229 e 5230, ler a resposta e o ledger. **A 5230 só depois da 5229 com sucesso** (o precheck dela exige a tabela de convidadas).

Estado intermediário (5229 aplicada, 5230 não): coerente. Leituras antigas continuam; a desmontagem e o `assign` já usam as regras novas; não existe convidada até alguém chamar `attach`.

## 4. Gate de autorização (antes do W1)

- `PRE-2`, `PRE-3`, `PRE-4`: todas as linhas `ok = true` (em `PRE-4`, as duas colunas).
- `PRE-3` `md5_live` diferente do esperado com marcadores `ok`: registrar, **não** é STOP (diferença de espaço).
- `PRE-5` registrado como baseline; inventário dos fichários e candidatos anexado.
- `PRE-6`: nenhuma transação aberta há mais de 1 min e nenhuma trava concedida a outra sessão nas tabelas listadas (a 5229 faz `ALTER TABLE` em `collection_layout_slot_expected_content` e cria gatilhos em `collection_layout`).
- Mensagem expressa de Fabrício autorizando o W1.

## 5. PASS / STOP

| Ponto | PASS | STOP |
|---|---|---|
| `PRE-2` | 8/8 `ok` | qualquer `false`: o LIVE difere do pressuposto (pacote já aplicado em parte, ou dependência ausente) |
| `PRE-3` | 8/8 `ok` + `P3.9` três colunas `true` | marcador ausente: corpo vivo ≠ canônico — auditar antes, nada no LIVE |
| `PRE-4` | 4/4 nas duas colunas + `P4.5` | dependente/chamador de função que será recriada |
| `PRE-5` | — (baseline) | `layouts` com proprietária de outro usuário **não** é problema; inventário só informa |
| `PRE-6` | sem bloqueio | transação longa ou trava: esperar |
| W1 5229 / 5230 | sucesso + entrada nova no ledger | qualquer erro: §6 |
| `POST-1` | 14/14 `ok` | qualquer `false` |
| `POST-2` | contagens = `PRE-5`; `guests = 0`; `reservations_with_collection = 0` | qualquer diferença |
| `POST-3` | 5229 e 5230, nessa ordem | ausente, duplicada, fora de ordem |
| `POST-4` | nenhum achado novo de outra classe | achado novo |

## 6. Conduta em erro

1. **Parar.** Não reaplicar nem editar no LIVE. Guardar SQLSTATE e texto integrais.
2. Rodar `POST-1`/`POST-2`/`POST-3` para fotografar: o arquivo que falhou não deixou nada.
3. Reportar. Correção só como nova proposta, com nova autorização.

Reversão (só com autorização, como proposta): rodapé da 5230 e depois da 5229. Segura enquanto `guests = 0` e `reservations_with_collection = 0`.

## 7. R2 — sondas de leitura (opcional, autorização própria)

`begin transaction read only;` + claims do usuário real + `set local role authenticated;` + uma chamada + `rollback;`. O Postgres recusa qualquer escrita (25006). `<ME55>`/`<ME55CC>` = ids do inventário `PRE-5`.

| Sonda | Chamada | Esperado |
|---|---|---|
| S1 | `get_my_collection_binder('<ME55>')` | `binder_role = OWNER`, `participant_count = 1` |
| S2 | `get_my_collection_binder('<ME55CC>')` | `has_binder = false`, `join_candidate_count ≥ 1` se o local padrão for o mesmo fichário |
| S3 | `list_my_binder_join_candidates('<ME55CC>')` | uma linha com o fichário da ME5.5 |
| S4 | `preview_my_collection_binder_dismantle('<ME55>')` | `guest_count = 0`, `blocked_reason` nulo |
| S5 | `get_my_collection_binder_unplaced('<ME55>', 48, 0)` | lista (ou vazio) sem erro |
| S6 | `get_my_collection_binder(gen_random_uuid())` | P0002 `COLLECTION_NOT_FOUND` |

**Não sondáveis sem gravar:** `attach`, `detach`, `assign_card_to_slot`, `set_slot_expected_content`, `dismantle`, `delete_collection` e qualquer concorrência. A prova comportamental real é o W2 (associação da ME5.5CC), seguido da leitura S1/S2 de novo.

## 8. Evidência a registrar

Saídas integrais de `PRE-*`/`POST-*` com hora UTC; SHA-256 e resposta de cada W1; `PRE-5` × `POST-2` campo a campo; advisors antes × depois; autorizações citadas literalmente. Destino: seção "Execução no LIVE" do `README.md`, `docs/log.md` e 05d, no mesmo ciclo.
