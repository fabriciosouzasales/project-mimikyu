# S2 / 5392 — Evidências da implantação no LIVE (2026-11-27) — PASS

Fonte: `Downloads\mmkyu-runs\run-20261127T140233Z`, fora do repositório, conferido arquivo a arquivo no fechamento (`S2/5392 PASS-LIVE CLOSEOUT + S4-b/5395 PREPARATION-01`). Executor v1.4 (`d0abd64f…e907f`, inalterado no repositório); o `run.json` não grava o hash do executor.

| Item | Valor | Confere |
|---|---|---|
| Projeto | `qjfutqujxrbzgrtkpgkg` (mimikyu-core · production, no stderr dos 3 passos) | ✔ |
| Papel | `postgres`; `--yes` em todos os passos | ✔ |
| Manifesto | `88bc25623308ea2028ab80b53aa53a5b737ce01124a9d89a8d5e9dcedbad5a07` = repositório | ✔ |
| Expectativas (por assinatura) | `10d2f706929641c64564bd8e3ef5a4879795f63a027fe9c24124402732e37c68` = repositório | ✔ |
| Passo 1 — PRE (`db79d31a…`) | exit 0, gate PASS (inventário igual às expectativas) | ✔ |
| Passo 2 — migration 5392 v1.1 (`fa92d9d5…`) | exit 0, saída `[]` (transação única; precheck e postcheck internos sem erro) | ✔ |
| Passo 3 — POST (`44cc4229…`) | exit 0, gate PASS | ✔ |
| Resultado | `PASS`, 14:02:33.910Z–14:02:49.938Z | ✔ |
| Rollback | não executado | ✔ |

## PRE

```json
{"acl_5380":"editor_clear_pokedex_position_primary_representative:authenticated, editor_remove_pokedex_position_assignment:authenticated, editor_set_pokedex_position_assignment:authenticated, editor_set_pokedex_position_primary_representative:authenticated",
 "ausente_5392":true,"barreira":"CLOSED","barreira_canonica":true,"dependencias_canonicas":true,"escopo_geracoes_presente":true,
 "escritas_5380_canonicas":true,
 "escritores_atribuicao":"public.auto_assign_pokedex_position_species_match(), public.editor_remove_pokedex_position_assignment(uuid,uuid), public.editor_set_pokedex_position_assignment(uuid,uuid,uuid,boolean), public.remove_pokedex_position_assignment(uuid), public.set_pokedex_position_assignment(uuid,uuid,boolean)",
 "escritores_representante":"public.clear_pokedex_position_primary_representative(uuid,uuid), public.editor_clear_pokedex_position_primary_representative(uuid,uuid), public.editor_set_pokedex_position_primary_representative(uuid,uuid), public.set_pokedex_position_primary_representative(uuid)",
 "executor":"postgres","identidades_teste":0,"pode_criar_em_public":true,"sem_eventos":true,"titular_canonico":true,
 "privilegios_observaveis":{"rolbypassrls":true,"rolsuper":false}}
```

`acl_5380` mostra que, antes da 5392, as 4 escritas da 5380 eram executáveis só por `authenticated`; `service_role` não aparecia. Essa é a referência do `RESTORE_5380_EXCECAO_5392.sql`, caso ele algum dia seja autorizado.

## POST

```json
{"ajudantes_internos":true,"barreira":"CLOSED","dependencias_canonicas":true,"escritas_5380_revogadas":true,"identidades_teste":0,
 "inventario_atribuicao_pos":true,"inventario_representante_pos":true,"rpcs_4":true,"sem_eventos":true,"titular_canonico":true}
```

## Estado final

- 5392 v1.1 **implantada no LIVE**. Cópia canônica em `database/schema/5392_create_editor_pokedex_copy_writes.sql` (sha256 `e076ed53…7c84`); o corpo é idêntico e só o bloco Status difere.
- As 4 RPCs do EDITOR e os 2 ajudantes internos estão presentes. As 4 escritas da 5380 estão revogadas para todo papel de cliente.
- O inventário de escritores depois da migration é exatamente o anterior mais as 4 RPCs. Nenhum evento gravado. Barreira CLOSED, 0 identidades TEST.
- O complemento de emergência `EMERGENCY_STOP_V1_13_ADD_S2.sql` está pronto, **não executado**.
- **Não comprovado:**
  - matriz de papéis;
  - invalidação O1;
  - `STATE_CHANGED`/`UNCHANGED` em sessão real;
  - concorrência entre duas sessões;
  - desempenho da resolução do identificador;
  - auditoria explícita em TEST/OPEN.

  Ficam para o TEST autorizado e a E4.
