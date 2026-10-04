# LIVE — aplicação da 2235 (ACL de `axis_identity_token`) · Registro

| Campo | Valor |
|---|---|
| **Mandatos** | `BATCH12-POST-UNFREEZE-CANARY-ACL-LIVE-APPLY-01` (execução) · `BATCH12-POST-UNFREEZE-CANARY-ACL-LIVE-CLOSEOUT-01` (registro) |
| **Autorização** | Fabrício: "Autorizo a aplicação da 2235 no LIVE." — cobre só PRE, aplicação única da 2235, POST, 2835 read-only e evidências. Não cobre retry do canary, `2831` ou `2213`. |
| **Baseline Git** | HEAD `b64480f8a8500d13ab197f995d813abfe2f47f7b` (`fix(batch12): prepare ACL correction after SVE canary stop`), parent `e40fc50c`, árvore e índice limpos |
| **Artefatos** | `../2235_grant_axis_identity_token_service_role.sql` blob `dd3cfc449bf86b8381b266e9ca67d3c4d277baec` (9.484 B, md5 `e6de4f4f…`) · `../2835_validate_staging_writer_acl.sql` blob `ef6d96c06c6964a83a32db4c84a03992dbfde783` (7.739 B, md5 `dee57d26…`) |
| **Canal** | MCP Supabase, projeto `qjfutqujxrbzgrtkpgkg`: `execute_sql` só SELECT; `apply_migration` uma única vez |
| **Resultado** | **PASS** — auditoria independente PASS. **ACL blocker CLOSED.** |

Os dois arquivos SQL foram submetidos byte a byte iguais aos blobs acima (conferido contra o registro do cliente). Eles permanecem inalterados no repositório, inclusive o cabeçalho "PROPOSTA — NÃO EXECUTADA" da 2235: o estado posterior vive neste registro, não na migration.

## 1. Sequência

| # | Passo | Momento (servidor, UTC) | Resultado |
|---|---|---|---|
| 1 | PRE JIT (SELECT) | `pre_at = 2026-10-04 18:28:03.182977` | PASS |
| 2 | 2835 — controle negativo | `checked_at = 18:28:41.959873` | `gate_pass = false`, só `g_sr_exec_token` e `g_writer_execs_all_index_fns` false — PASS |
| 3 | `apply_migration` `2235_grant_axis_identity_token_service_role` | ledger `20261004182941` | `{"success":true}`, sem retry |
| 4 | POST (SELECT) | `post_at = 18:29:58.154957` | PASS |
| 5 | 2835 — pós-aplicação | `checked_at = 18:30:27.431823` | `gate_pass = true`, 12/12 — PASS |

## 2. PRE

- Causa raiz presente: `service_role` INSERT na tabela de staging = true, EXECUTE em `axis_identity_token` = false; `authenticated` = true; `anon` = false; PUBLIC sem entrada.
- Função: 1 overload, owner `postgres`, md5(prosrc) `18682dce935281b0a4437628a6e8309a`, IMMUTABLE, não-STRICT, SECURITY INVOKER, `search_path=""`.
- Índice `uq_cvir_row_identity`: unique/valid/ready em `catalog_variant_import_row`; única dependência `axis_identity_token`; dois eixos; md5(indexdef) `ad46a9fedb3517431ecbbb0324d959c9`.
- Guards 2214 e 2224 habilitados (`O`).
- Dados: jobs 146 · in_flight 0 · staging 26.127 · card_variant 24.893 · EC 0 · job `3ec9c551…` FAILED / 0 rows · ledger 2235 = 0.
- Concorrência: 0 locks nos objetos tocados; 0 sessões cliente ativas ou em transação.

## 3. ACL de EXECUTE em `internal.axis_identity_token(jsonb,text)`

| Papel | Antes | Depois |
|---|---|---|
| postgres | true | true |
| authenticated | true | true |
| service_role | **false** | **true** |
| anon | false | false |
| PUBLIC | — | — |

ACL depois: `{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}`; grantees de EXECUTE = `{authenticated, postgres, service_role}`.

## 4. Integridade e dados (POST)

- Função e índice inalterados (mesmos md5, mesmo contrato, unique/valid/ready); guards habilitados.
- Dados idênticos ao PRE: jobs 146 · in_flight 0 · staging 26.127 · card_variant 24.893 · EC 0. Jobs criados depois do PRE = 0. Job `3ec9c551…` continua FAILED / 0 rows.
- Ledger: 1 registro, `20261004182941` / `2235_grant_axis_identity_token_service_role`.

## 5. Estado e próximo passo

- **ACL correction = PASS.** A causa do STOP do primeiro canary está corrigida.
- **O primeiro canary SVE continua STOP / FAILED** (`LIVE-CANARY-SVE-STOP-RECORD.md`, preservado). O eixo 3 numa importação real **ainda não está provado** depois da correção.
- Canary SVE **não** retentado; `2831` e `2213` **não** executadas.
- **NEXT:** auditar e preparar o retry único do canary SVE (PRE novo) → retry com mandato próprio → POSTCHECK completo → só então avaliar `2831` / `2213`.
