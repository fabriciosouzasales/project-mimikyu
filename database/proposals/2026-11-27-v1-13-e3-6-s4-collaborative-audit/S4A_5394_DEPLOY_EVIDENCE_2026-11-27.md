# S4-a / 5394 — Evidências da implantação no LIVE (2026-11-27) — PASS

Fonte: `Downloads\mmkyu-runs\run-20261127T133515Z` (fora do repositório), conferido arquivo a arquivo no fechamento (`S4-a/5394 PASS-LIVE CLOSEOUT + S2/5392 IMPLEMENTATION PREPARATION-01`). O executor é a v1.4 (`d0abd64f…e907f`, inalterado no repositório); o `run.json` não grava o hash do executor.

| Item | Valor | Confere |
|---|---|---|
| Projeto | `qjfutqujxrbzgrtkpgkg` (mimikyu-core · production, no stderr dos 3 passos) | ✔ |
| Papel | `postgres`; `--yes` em todos os passos | ✔ |
| Manifesto | `24d7d8a628eb7d4fa40dbb1ccb48da2e8a0b42121157571d4fed923bf7bc17ad` = repositório | ✔ |
| Expectativas | `6351fb718a1e47c69da170507e04ee0a6e259426f466b4b82db2ce51185edd13` = repositório | ✔ |
| Passo 1 — PRE (`8b63e713…`) | exit 0, gate PASS | ✔ |
| Passo 2 — migration 5394 (`b43accc5…`) | exit 0, saída `[]` (transação única; precheck e postcheck internos sem erro) | ✔ |
| Passo 3 — POST (`ad50ef0f…`) | exit 0, gate PASS; `escritores_md5` = PRE (comparado pelo executor) | ✔ |
| Resultado | `PASS`, 13:35:15.363Z–13:35:27.532Z | ✔ |
| Rollback | não executado | ✔ |

## PRE

```json
{"ausente_5394":true,"barreira":"CLOSED","barreira_canonica":true,"dependencia_5391":true,
 "escritores_atribuicao":"auto_assign_pokedex_position_species_match, editor_remove_pokedex_position_assignment, editor_set_pokedex_position_assignment, remove_pokedex_position_assignment, set_pokedex_position_assignment",
 "escritores_md5":"534f7532ca8e47a3f3b7c31b8b48e3a7",
 "escritores_representante":"clear_pokedex_position_primary_representative, editor_clear_pokedex_position_primary_representative, editor_set_pokedex_position_primary_representative, set_pokedex_position_primary_representative",
 "executor":"postgres","executor_dono_tabelas":true,"identidades_teste":0,"pode_referenciar_usuarios":true,
 "sessoes_com_trava":0,"titular_canonico":true,"privilegios_observaveis":{"rolbypassrls":true,"rolsuper":false}}
```

Gatilhos preexistentes (relatório): 5 em `collection_allocation`, 3 em `collection_pokedex_position_assignment` e 2 em `collection_pokedex_position_primary_representative`. São os de 5041/5042/5045/6119, 6118 e 6121; nenhum conflita com `trg_900_*`.

## POST

```json
{"barreira":"CLOSED","escritores_md5":"534f7532ca8e47a3f3b7c31b8b48e3a7","funcoes_9":true,"funcoes_sem_api":true,
 "gatilhos_7":true,"gatilhos_instrucao":true,"identidades_teste":0,"sem_eventos":true,"tabela_interna":true,"titular_canonico":true}
```

## Estado final

- 5394 **implantada no LIVE**. Cópia canônica em `database/schema/5394_create_collection_activity_audit_infrastructure.sql` (sha256 `22f0f523…a476`); o corpo é idêntico e só o bloco Status difere.
- Infraestrutura criada: `collection_activity_event`, 9 funções internas, 7 gatilhos. Nenhum evento gravado; a captura fica inerte com a barreira CLOSED.
- `ROLLBACK_5394` disponível enquanto não houver eventos.
- **Não comprovado:** captura em TEST/OPEN, duplicidade, desempenho (critérios no README §9.7). Fica para o TEST autorizado e a E4.
