# PR-04A · 5365 — execução controlada no LIVE (2026-11-14)

| Campo | Valor |
|---|---|
| Rodada | `PR-04A \| 5365 LIVE CONTROLLED EXECUTION-01` |
| Autorização | Expressa do proprietário: só REVOKE EXECUTE de `authenticated` nas 3 assinaturas legadas. **G-D (T0/T1) dispensado** por decisão expressa; aceitos o risco de consumidor externo não identificado, sua possível interrupção e a incompatibilidade dos harnesses 5800/5801/5803. |
| Projeto | Supabase LIVE `qjfutqujxrbzgrtkpgkg` (`mimikyu-core`) |
| Canal / executor | MCP `execute_sql`, uma chamada, `postgres` |
| Arquivo executado | `../5365_revoke_legacy_physical_card_writers_execute.sql` v1.1, integral, sha256 `747a1deace2f5e183632d2487c0b9dcb9d616477440aa09e6406ae2ca8bc92b0` (texto enviado comparado byte a byte com o arquivo antes do envio) |
| Horário (UTC) | antes 2026-11-14T17:31:45Z · depois 2026-11-14T17:32:19Z |
| Resultado do canal | Sem erro (resposta vazia). O canal não devolve NOTICE: o `5365 OK` não é visível; a confirmação vem do postcheck interno (que abortaria a transação) e da consulta 1 POST. |
| Ledger | Sem registro em `supabase_migrations.schema_migrations` (execute_sql, mesmo tratamento de S2–S4 na PR-01). |

## Gates

| Gate | Resultado |
|---|---|
| G-A auditoria | AUDIT-02 + FINAL STATIC AUDIT-01 + preflight operacional: PASS |
| G-B autorização | Expressa, com canal definido |
| G-C PRE | Consulta 1 PRE **byte a byte igual** à T0 (`../gd-evidence/T0-2026-11-14T0231Z/T0_consulta1.tool-payload.txt`) |
| G-D | **Dispensado** pelo proprietário. Controle compensatório (logs da API, 24 h até 2026-11-14T17:30Z): `/rpc/add_physical_cards` **0 chamadas**; `/rpc/organize_my_collection_storage` 0; `/rpc/set_physical_cards_storage` 4 POST 200 (15:55–15:58Z) — URL comum às duas sobrecargas, **não atribuídas** a nenhuma delas |
| G-E rollback | `../R5365_rollback_regrant_authenticated.sql` íntegro (MANIFEST 3/3), não executado |
| G-F executor | `postgres` |
| G-G harnesses | Incompatibilidade de 5800/5801/5803 aceita |

## Verificação (consulta 1 PRE × POST)

| Assinatura | Mudança |
|---|---|
| `add_physical_cards(jsonb)` | ACL `{postgres=X/postgres,authenticated=X/postgres}` → `{postgres=X/postgres}`; `authenticated` EXECUTE true → false |
| `organize_my_collection_storage(uuid,uuid,text,integer,text)` | idem |
| `set_physical_cards_storage(uuid,uuid[])` | idem |
| 5 vigentes (`set_physical_cards_storage(…,boolean)`, `organize_my_collection_storage(…,boolean)`, `set_my_physical_cards_condition`, `remove_my_physical_card`, `register_physical_cards_bulk`) | **nenhuma** (md5, dono, SECURITY DEFINER, config, ACL e EXECUTE idênticos) |

Nas 3 legadas, md5 do corpo, dono, SECURITY DEFINER e config iguais ao PRE; `anon`/`service_role` continuam sem EXECUTE; `postgres` mantém. Comparação feita por script: diferenças restritas a `acl` e `authenticated_x` nas 3 legadas.

## Limitações

- O NOTICE final não é exibido pelo canal; a evidência é a ausência de erro + consulta 1 POST.
- Verificação limitada às 8 assinaturas da consulta 1; outras permissões do banco não foram lidas (o script só contém os 3 REVOKE).
- Consumidor externo não identificado continua possível (G-D dispensado); efeito para ele: `42501 permission denied`.
- Smoke test funcional do app pendente do proprietário.
- PR-04B (R1, R2, R3, R5, R6 da 5364 sem prova dinâmica) continua aberta.

## Arquivos

| Arquivo | Conteúdo |
|---|---|
| `PRE_consulta1.tool-payload.txt` / `.json` | Consulta 1 antes (resposta integral / decodificada) |
| `POST_consulta1.tool-payload.txt` / `.json` | Consulta 1 depois |
| `SHA256SUMS` | Hashes deste diretório |
