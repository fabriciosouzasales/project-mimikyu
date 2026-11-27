# S4-b / 5395 v1.1 — Evidências da implantação no LIVE (2026-11-27) — PASS

Fonte: `Downloads\mmkyu-runs\run-20261127T143239Z`, fora do repositório, conferido arquivo a arquivo no fechamento (`S4-b/5395 PASS-LIVE CLOSEOUT + S4-c/5396 PREPARATION-01`). Executor v1.4 (`d0abd64f…e907f`, inalterado no repositório); o `run.json` não grava o hash do executor.

| Item | Valor | Confere |
|---|---|---|
| Projeto | `qjfutqujxrbzgrtkpgkg` (mimikyu-core · production, no stderr dos 3 passos) | ✔ |
| Papel | `postgres`; `--yes` em todos os passos; CLI supabase@3.2.0 | ✔ |
| Manifesto | `53ef47bedb9f498e4319ef6b6d5b390d31658824087e1d7adb55a94a18fe7b00` = repositório | ✔ |
| Expectativas (por assinatura) | `bb3a9fff596fa01b22cb03e71957e6883c27b60c8dc021ea938de6bed0391f21` = repositório | ✔ |
| Passo 1 — PRE (`77a3c814…`) | exit 0, gate PASS; inventário igual às expectativas (7 + 6) | ✔ |
| Passo 2 — migration 5395 v1.1 (`20f26b5a…`) | exit 0, saída `[]` (transação única; precheck e postcheck internos sem erro) | ✔ |
| Passo 3 — POST (`4c78ba22…`) | exit 0, gate PASS | ✔ |
| Resultado | `PASS`, 14:32:39.603Z–14:32:51.850Z | ✔ |
| Rollback | não executado | ✔ |

## PRE

```json
{"ausente_5395": true, "barreira": "CLOSED", "dependencia_5392": true, "dependencias_canonicas": true, "escritores_atribuicao": "public.auto_assign_pokedex_position_species_match(), public.editor_move_pokedex_copy(uuid,text,uuid,uuid,boolean), public.editor_remove_pokedex_position_assignment(uuid,uuid), public.editor_set_pokedex_position_assignment(uuid,uuid,uuid,boolean), public.editor_unassign_pokedex_copy(uuid,text,uuid), public.remove_pokedex_position_assignment(uuid), public.set_pokedex_position_assignment(uuid,uuid,boolean)", "escritores_representante": "public.clear_pokedex_position_primary_representative(uuid,uuid), public.editor_choose_pokedex_representative(uuid,text,uuid,text), public.editor_clear_pokedex_position_primary_representative(uuid,uuid), public.editor_restore_pokedex_automatic_representative(uuid,uuid,text), public.editor_set_pokedex_position_primary_representative(uuid,uuid), public.set_pokedex_position_primary_representative(uuid)", "executor": "postgres", "identidades_teste": 0, "perfil_publico_presente": true, "pode_criar_em_public": true, "privilegios_observaveis": {"rolbypassrls": true, "rolsuper": false}, "sem_eventos": true, "titular_canonico": true}
```

## POST

```json
{"barreira": "CLOSED", "dependencias_canonicas": true, "identidades_teste": 0, "inventario_atribuicao_pos": true, "inventario_representante_pos": true, "leitura_historico": true, "sem_eventos": true, "titular_instrumentado": true, "titular_privilegios": true}
```

## Estado final

- 5395 v1.1 **implantada no LIVE**. A cópia canônica está em `database/schema/5395_instrument_owner_pokedex_audit_and_activity_read.sql`: o corpo é idêntico e só o bloco Status difere.
- **Funções do titular:** as 4 estão instrumentadas, com md5 igual ao texto da v1.1 (`titular_instrumentado`). Seguem definer, com `search_path` vazio, EXECUTE só para `authenticated`, sem anon e sem PUBLIC (`titular_privilegios`).
- **Leitura:** `get_collection_activity` está presente: STABLE, definer, só `authenticated` (`leitura_historico`).
- **Inventário de escritores:** exatamente o anterior (`inventario_*_pos`). Nenhum evento gravado. Barreira CLOSED, 0 identidades TEST.
- **Emergência:** o complemento `EMERGENCY_STOP_V1_13_ADD_S4.sql` (E2c) está pronto, **não executado**.
- **Não comprovado (fica para o TEST autorizado e a E4):**
  - eventos explícitos do titular em sessão real;
  - ausência de duplicidade com a captura derivada;
  - persistência e desfazimento da marcação;
  - paginação e acesso por papel da leitura;
  - desempenho.
