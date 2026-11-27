# S3 / 5393 — Evidências da implantação controlada no LIVE (2026-11-27)

Rodada: `E3-6 / S3-5393 — AUTHORIZED LIVE DEPLOYMENT-01`, autorização expressa do proprietário. Escopo: PRE → migration 5393 → POST. Barreira CLOSED do início ao fim; modo TEST não usado; nenhum dado criado ou alterado além da função.

## Projeto e canal

| Item | Valor |
|---|---|
| Projeto | `qjfutqujxrbzgrtkpgkg` — mimikyu-core, sa-east-1, ACTIVE_HEALTHY, PostgreSQL 17.6.1.147 (`get_project`) |
| Canal | Supabase Management API `database/query` (mesmo endpoint da E1: `db query --remote` faz `POST /v1/projects/qjfutqujxrbzgrtkpgkg/database/query`), chamado pelo conector Supabase da sessão; não grava `supabase_migrations` (como a E1) |
| Papel executor | `postgres` (`current_user`), igual ao dono da 5315 (`postgres`) |
| Credenciais | nenhuma exposta ou registrada |

**Diferença em relação à E1:** o cliente foi o conector da sessão, não o `E1_DEPLOY_CLI_executor.ps1` (CLI na máquina do proprietário). Endpoint, papel e transação única do arquivo são os mesmos; o executor da E1 adicionalmente contava POSTs e conferia o alvo no log — aqui o alvo foi conferido pelo `get_project` e por cada resposta.

## Artefatos (sha256)

| Arquivo | sha256 |
|---|---|
| `5393_create_get_shared_collection_binder_pages_with_species.sql` (proposta) | `ed8612cc19cec5dc8c09f137c0d20e65a8598a4cd426f34a08f13bc944e054d9` |
| `S3_DEPLOY_readonly_checks.sql` | `7e6780b6ccb91db939518e162a92ca93658aa5ac689f4a858a07156780accf5d` (bloco PRE: `c8f34e24…`) |
| `ROLLBACK_S3.sql` | `c762b27bddbcc732219997fc5051ebe18fcc5ec8e244a493ca7d8f714e8a4b8b` (não usado) |
| `database/schema/5393_…sql` (canônica; só o bloco Status difere) | `8be073629bc5b5a021622a03a00f0e53f85dfcc010d37ae69bf82c3bc43da0fc` |

Texto enviado: do `begin;` ao `commit;` do arquivo da proposta, sem alteração (o cabeçalho de comentário não foi enviado; ele tem um único `/* … */`).

## PRE (somente leitura) — 15/15

```json
{"executor":"postgres","dono_5315":"postgres","executor_e_dono":true,"barreira":"CLOSED","identidades_teste":0,
 "md5_5302":true,"md5_5315":true,"md5_5316":true,"md5_5318":true,"md5_5389_assert":true,"md5_5389_open":true,
 "dependencias_stable":true,"tabelas_5257":true,"indices_juncao":true,"ausente_5393":true}
```

## Aplicação

Uma chamada, transação única do arquivo (`begin; … commit;`): precheck interno, `create function`, `comment`, `revoke`/`grant`, postcheck interno. Resultado: **sem erro**, resposta vazia (`[]`) — confirmada.

## POST (somente leitura) — 11/11

```json
{"existe":true,"definer_stable_sp":true,"dono_igual_5315":true,"exec_authenticated":true,"sem_exec_anon":true,
 "sem_exec_public":true,"retorno_exato":true,"md5_5393_igual_arquivo":"34c87736937dd09b6495f435c80ccbe6",
 "v1_12_intacta":true,"barreira":"CLOSED","identidades_teste":0}
```

`md5_5393_igual_arquivo` = md5 do prosrc do arquivo (`34c87736937dd09b6495f435c80ccbe6`, calculado localmente): **igual**.

## Leituras compatíveis com produção (transações somente leitura, revertidas; identidade fictícia, nenhum dado)

| Verificação | Resultado |
|---|---|
| 5393 como `authenticated` (sub fictício) com a barreira CLOSED | `42501 CAPABILITY_NOT_ENABLED`, hint `V1_13_BARRIER` — recusa contratual |
| 5316 como `authenticated` (sub fictício, coleção inexistente) | `P0002 COLLECTION_NOT_FOUND` — resposta contratual da 5316, inalterada e sem dependência da barreira |

## Estado final

| Item | Valor |
|---|---|
| Barreira | CLOSED (`changed_at` 2026-11-18 01:49:36Z — inalterada) |
| Identidades TEST | 0 |
| 5393 | presente, conforme POST |
| 5315/5316/5318 | inalteradas (md5) |
| Rollback | não necessário, não executado |
| Harness 5897, 5897_C, 5897_P | **não executados** (cenários sintéticos não permitidos no LIVE); prova funcional de não inferência e matriz de papéis ficam para o gate de abertura (TEST/OPEN) |
| Instante da conferência final | 2026-11-27 01:34:06Z |

## Auditoria e fechamento (2026-11-27, `E3-6 / S3-5393 — DEPLOYMENT AUDIT & CLOSEOUT-01`)

- **Implantação aceita.** PRE 15/15, COMMIT sem erro, POST 11/11, md5 implantado = esperado (`34c87736937dd09b6495f435c80ccbe6`), barreira CLOSED, 0 identidades TEST, V1-12 intacta.
- **Canal:** o conector Supabase da sessão foi **aceito excepcionalmente** para esta implantação (mesmo endpoint `database/query` e mesmo papel `postgres` da E1; diferença de cliente registrada acima). Não vale como precedente automático.
- **Cópia canônica:** corpo do `begin;` ao `commit;` idêntico à proposta (conferido byte a byte); md5 do prosrc igual nos dois; única diferença documental = bloco `Status` do cabeçalho (13 linhas: 4 removidas, 9 incluídas).
- **5393 implantada, porém inerte** (barreira CLOSED). **Rollback** `ROLLBACK_S3.sql` disponível, não executado.
- **Pendentes, bloqueiam a abertura funcional:** G3 (não inferência e matriz de papéis), G4 (concorrência), G5 (desempenho) — **não executados**. Abertura funcional **não autorizada**. **F2 ainda não integrada** à 5393.
