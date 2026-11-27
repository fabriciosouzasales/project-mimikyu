# E3-7b / 5397 — Evidências da implantação no LIVE (2026-11-27) — PASS

Fonte: `Downloads\mmkyu-runs\run-20261127T183633Z`, fora do repositório. Cada arquivo foi conferido no fechamento (`E3-7b / 5397 — PASS-LIVE CLOSEOUT & E4 HANDOFF-01`).

| Item | Valor | Confere |
|---|---|---|
| Projeto | `qjfutqujxrbzgrtkpgkg` (mimikyu-core · production, no stderr dos 3 passos) | ✔ |
| Papel | `postgres` (`executor` do PRE = `-Papel`); `--yes` em todos os passos; CLI supabase@3.2.0 | ✔ |
| Manifesto | `7a55d30912f7e1ce40c0f703b2f029820de3184575c896fddc5cd563192f72d7` = repositório = auditado | ✔ |
| Expectativas (por assinatura) | `4b57d02408b6337938c798cd86387ab28402f6976f95af1de445208458f5f844` = repositório = auditado | ✔ |
| Passo 1 — PRE (`2626209535fa631fe997abe993e1b8c0a479f43032772d154953f150161e58b3`) | exit 0; gate PASS sem motivos; inventários 4 + 3 iguais às expectativas | ✔ |
| Passo 2 — migration (`3aa4afc77c5fd7fb00fd325cb7c397918ab71f8da2a84bcaa3e2d65858a9ff9c`) | exit 0, saída `[]`: transação única, precheck e postcheck internos sem erro | ✔ |
| Passo 3 — POST (`0dac345595cf5997cf42420ecf1aebd475b25566983ff1fb61bb353a6c9c7afe`) | exit 0; gate PASS sem motivos | ✔ |
| Resultado | `PASS (todos os passos concluídos e gates aprovados)`, 18:36:33.821Z–18:36:46.010Z | ✔ |
| Rollback | não executado | ✔ |

## PRE

```json
{"ajudantes_canonicos": true, "ausente_5397": true, "barreira": "CLOSED", "contratos_antigos_ativos": true, "escritores_bolso": "public.editor_apply_binder_auto_arrange(uuid,text), public.editor_move_binder_card(uuid,integer,integer,integer,integer,integer,integer), public.editor_place_card_in_binder(uuid,integer,integer,integer,uuid), public.editor_remove_binder_card(uuid,integer,integer,integer)", "escritores_exposicao_fisica": "public.editor_place_card_in_binder(uuid,integer,integer,integer,uuid), public.editor_preview_binder_auto_arrange(uuid), public.get_shared_binder_placeable_cards(uuid,integer,integer)", "executor": "postgres", "funcoes_canonicas": true, "identidades_teste": 0, "pode_criar_em_public": true, "privilegios_observaveis": {"rolbypassrls": true, "rolsuper": false}}
```

## POST

```json
{"ajudantes_canonicos": true, "barreira": "CLOSED", "contratos_antigos_revogados": true, "funcoes_5397": true, "identidades_teste": 0, "inventario_bolso_pos": true, "inventario_exposicao_pos": true, "previa_executavel": true, "rpcs_novas": true}
```

## Estado final

- **5397 implantada no LIVE.** A cópia canônica está em `database/schema/5397_binder_opaque_copy_identity.sql`. Do `begin;` ao `commit;` ela é idêntica à proposta; só o bloco Status difere.
- **`funcoes_5397`:** `get_shared_binder_placeable_copies`, `editor_place_copy_in_binder` e a prévia 5386 estão com o texto gerado.
- **`ajudantes_canonicos`:** as funções de apoio 5389, 5391 e 5392 continuam intactas.
- **`rpcs_novas`:** as duas RPCs novas são definer, com `search_path` vazio, executáveis por `authenticated` e não por `anon` nem `service_role`.
- **`contratos_antigos_revogados`:** a 5373 e a 5374 antigas ficaram sem EXECUTE para anon, authenticated, service_role e authenticator.
- **`previa_executavel`:** a prévia continua executável pelo EDITOR.
- **`inventario_exposicao_pos`:** nenhuma RPC do EDITOR sob a barreira continua executável com `physical_card_id`.
- **`inventario_bolso_pos`:** os escritores de bolso são os 4 anteriores mais `editor_place_copy_in_binder`.
- **Barreira:** CLOSED, com 0 identidades TEST.
- **Não comprovado (fica para TEST e E4):**
  - recusa de token de outra coleção, de outra participação ou de época anterior;
  - participação removida;
  - VIEWER tentando escrever;
  - colocar e desfazer reais;
  - a prévia real sem o id;
  - o desempenho do token em coleções grandes.
