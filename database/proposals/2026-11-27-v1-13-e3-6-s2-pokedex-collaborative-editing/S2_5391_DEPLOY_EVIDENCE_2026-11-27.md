# S2 / 5391 — Evidências da implantação no LIVE (2026-11-27) — PASS

Fonte: registros do executor por arquivo em `Downloads\mmkyu-runs\` (fora do repositório), conferidos arquivo a arquivo no fechamento (`S2/5391 — PASS-LIVE CLOSEOUT & PUBLICATION-01`). O executor **não** grava o próprio sha256 no `run.json`. A versão em uso, v1.4 (`d0abd64f…e907f`), é inferida pelos campos `expectativas*`, que só existem nessa versão, e pelo arquivo do repositório inalterado desde a prova no Windows.

## Tentativas (todas preservadas em `run-*`)

| Registro | Manifesto | Resultado | Escrita |
|---|---|---|---|
| `run-20261127T122008Z` | `b4f253c1…` (antigo) | STOP no PRE: papel `supabase_read_only_user` (gate com `--read-only`) | nenhuma |
| `run-20261127T123851Z` | `119b1871…` | STOP no PRE: exit 1, CLI exigiu `--yes` ("Nothing was changed") | nenhuma |
| `run-20261127T124650Z` | `2ce0ccb1…` (só PRE, fase 1) | **PASS** | nenhuma (só leitura) |
| `run-20261127T130024Z` | `119b1871…` + expectativas `6351fb71…` | **PASS** | migration 5391 |

A trava da tentativa de 12:38Z (`lock-119b1871a73d8999`) **não foi preservada**: o arquivo atual tem a marca de 13:00:24Z. O registro `run-20261127T123851Z` dessa tentativa continua intacto.

## Execução de 13:00:24Z — conferência

| Item | Valor | Confere |
|---|---|---|
| Projeto | `qjfutqujxrbzgrtkpgkg` (mimikyu-core · production, no stderr de cada passo) | ✔ |
| Papel | `postgres` (PRE `executor`); `--yes` em todos os passos (stderr "Confirmed by --yes") | ✔ |
| Manifesto | `119b1871a73d899932837c42cf87cd63fdca8a95541629a3f52d00e29c962b08` = repositório | ✔ |
| Expectativas | `6351fb718a1e47c69da170507e04ee0a6e259426f466b4b82db2ce51185edd13` = repositório | ✔ |
| Passo 1, PRE (`1e1630f6…`) | exit 0, gate PASS, sem motivos | ✔ |
| Passo 2, migration 5391 (`4a971e89…`) | exit 0, saída `[]` (transação única; precheck e postcheck internos sem erro) | ✔ |
| Passo 3, POST (`f6b8ddf4…`) | exit 0, gate PASS, sem motivos | ✔ |
| Resultado | `PASS (todos os passos concluídos e gates aprovados)`, 13:00:24.583Z–13:00:36.826Z | ✔ |
| Rollback | não executado | ✔ |

### PRE (passo 1)

```json
{"ausente_5391":true,"barreira":"CLOSED","barreira_canonica":true,"dependencias_pokedex":true,
 "escritores_atribuicao":"auto_assign_pokedex_position_species_match, editor_remove_pokedex_position_assignment, editor_set_pokedex_position_assignment, remove_pokedex_position_assignment, set_pokedex_position_assignment",
 "escritores_representante":"clear_pokedex_position_primary_representative, editor_clear_pokedex_position_primary_representative, editor_set_pokedex_position_primary_representative, set_pokedex_position_primary_representative",
 "executor":"postgres","executor_dono_membership":true,"identidades_teste":0,"indices_caminho":true,
 "membership_sem_gatilho":true,"participacao_canonica":true,"participacoes":1,"pgcrypto_extensions":true,
 "pode_travar_membership":true,"privilegios_observaveis":{"rolbypassrls":true,"rolsuper":false}}
```

O inventário de escritores é igual às expectativas auditadas: 5 e 4 nomes, sem repetição. O mesmo valor apareceu na fase 1 (12:46:50Z).

### POST (passo 3)

```json
{"ajudantes_internos":true,"barreira":"CLOSED","epocas":1,"epocas_completas":true,"epocas_unicas":true,
 "gatilho_habilitado":true,"identidades_teste":0,"participacao_canonica":true,"participacoes":1,
 "rpc_presente":true,"rpc_seguranca":true,"rpc_so_authenticated":true,"segredo_presente":true,"tabelas_internas":true}
```

## Estado final

- 5391 **implantada no LIVE**. Cópia canônica em `database/schema/5391_create_editor_pokedex_copy_identity_and_read.sql` (sha256 `bb6289dc…1c00`); só o bloco Status difere e o corpo é idêntico.
- Barreira CLOSED, 0 identidades TEST. A leitura do EDITOR é inerte para clientes.
- 1 participação, com 1 época, valor único.
- **Não comprovado:** matriz de papéis, invalidação O1 dos identificadores, privacidade das colunas, desempenho (p95 ≤ 300 ms em até 5 000 exemplares). Ficam para o TEST autorizado e a E4.
