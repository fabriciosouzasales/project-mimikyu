# S4-c / 5396 v1.2 — Evidências da implantação no LIVE (2026-11-27) — PASS

Fonte: `Downloads\mmkyu-runs\run-20261127T152432Z`, fora do repositório, conferido arquivo a arquivo no fechamento (`S4-c/5396 PASS-LIVE CLOSEOUT + F3 READINESS-01`). Tentativa anterior: **STOP-LIVE** `run-20261127T151841Z` (v1.1, 22P02), registrada em `S4C_5396_STOP_LIVE_2026-11-27T151841Z.md`.

| Item | Valor | Confere |
|---|---|---|
| Projeto | `qjfutqujxrbzgrtkpgkg` (mimikyu-core · production, no stderr dos 3 passos) | ✔ |
| Papel | `postgres`; `--yes` em todos os passos; CLI supabase@3.2.0 | ✔ |
| Manifesto | `1d30bc7d4d4412a2817a30a6aa6de0a736a1cec83edd3e30b6bef051b1b5464c` = repositório | ✔ |
| Expectativas (por assinatura) | `485ce5a47b0bf1fc7a043d594adf017004558a64dd6a1dab994255601088694d` = repositório | ✔ |
| Passo 1 — PRE (`1b67221d…`) | exit 0, gate PASS; inventário 6 + 4 igual às expectativas | ✔ |
| Estado depois do STOP | o PRE exigiu os 10 corpos canônicos, o CHECK da 5341, a primitiva ausente e nenhum evento `SPECIES_*`: tudo true → nada persistiu da v1.1 | ✔ |
| Passo 2 — migration v1.2 (`d735734e…`) | exit 0, saída `[]` (transação única; precheck e postcheck internos sem erro) | ✔ |
| Passo 3 — POST (`761e3fa3…`) | exit 0, gate PASS | ✔ |
| Resultado | `PASS`, 15:24:32.069Z–15:24:48.283Z | ✔ |
| Rollback | não executado | ✔ |

## PRE

```json
{"atribuicao_5379": true, "ausente_5396": true, "barreira": "CLOSED", "dono_tabela_eventos": true, "escritores_preferencia": "public.apply_my_binder_species_references(uuid,text), public.editor_apply_binder_species_references(uuid,text), public.editor_set_binder_species_reference_visibility(uuid,boolean), public.set_my_binder_species_reference_visibility(uuid,boolean)", "escritores_referencias": "public.apply_my_binder_species_references(uuid,text), public.clear_my_binder_species_references(uuid,integer), public.editor_apply_binder_species_references(uuid,text), public.editor_clear_binder_species_references(uuid,integer), public.editor_remove_binder_page(uuid,integer,integer), public.remove_layout_page(uuid,integer)", "executor": "postgres", "funcoes_canonicas": true, "gatilho_editor_ativo": true, "identidades_teste": 0, "pode_criar_em_public": true, "privilegios_observaveis": {"rolbypassrls": true, "rolsuper": false}, "sem_eventos_especie": true, "tipos_5341": true}
```

## POST

```json
{"barreira": "CLOSED", "categoria_especie": true, "funcoes_instrumentadas": true, "gatilho_editor_ativo": true, "identidades_teste": 0, "inventario_preferencia_pos": true, "inventario_referencias_pos": true, "leituras_stable": true, "primitiva_interna": true, "privilegios_rpcs": true, "sem_eventos_especie": true, "tipos_5396": true}
```

## Estado final

- 5396 v1.2 **implantada no LIVE**. Cópia canônica em `database/schema/5396_audit_binder_species_references.sql`: o corpo é idêntico e só o bloco Status difere.
- **Funções:** as 10 estão com o texto instrumentado (`funcoes_instrumentadas`):
  - 3 do titular e 3 do EDITOR de referências de espécie;
  - categoria, gatilho do EDITOR, 5269 e 5388.
- **Privilégios:** as 8 RPCs seguem definer, com `search_path` vazio, só `authenticated` (`privilegios_rpcs`). As duas leituras seguem STABLE (`leituras_stable`).
- **Primitiva:** `binder_activity_record_species` é interna, sem EXECUTE para nenhum papel de cliente (`primitiva_interna`).
- **Regra de tipos:** `chk_bae_event_type` com 29 tipos (`tipos_5396`). Categoria `SPECIES` e gatilho do EDITOR ativos.
- **Inventário de escritores:** exatamente o anterior. Nenhum evento `SPECIES_*`. Barreira CLOSED, 0 identidades TEST.
- **S4 (D-E3-8) completa no servidor:** 5394, 5395 e 5396.
- **Não comprovado (fica para TEST e E4):** eventos reais, autoria, visibilidade do participante, filtro `SPECIES` em sessão real e desempenho.
