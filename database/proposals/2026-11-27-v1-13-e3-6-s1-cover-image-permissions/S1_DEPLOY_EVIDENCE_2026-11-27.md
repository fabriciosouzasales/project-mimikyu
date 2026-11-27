# S1 / 5390 — Evidências da implantação no LIVE (2026-11-27)

**Resultado final: PASS (RETRY-01).** Tentativa 1: STOP no PRE (abaixo). Correção do critério do PRE: `PRECHECK CORRECTION-01`. Tentativa 2 (`AUTHORIZED LIVE DEPLOYMENT RETRY-01`): PRE corrigido PASS → COMMIT → POST PASS (seção final).

---

## Tentativa 1 — STOP no PRE

Rodada: `E3-6 / S1-5390 — AUTHORIZED LIVE DEPLOYMENT-01`, autorização expressa do proprietário (PRE → 5390 → POST). **Resultado: STOP no PRE.** A migration **não foi executada**; nada foi escrito no banco nem no Storage.

## Projeto e canal

| Item | Valor |
|---|---|
| Projeto | `qjfutqujxrbzgrtkpgkg` — mimikyu-core, sa-east-1, ACTIVE_HEALTHY, PostgreSQL 17.6.1.147 (`get_project`) |
| Canal | conector Supabase da sessão → Management API `database/query` (mesmo canal aceito excepcionalmente na S3) |
| Papel executor | `postgres` (`current_user`), igual ao dono da I1 |
| Chamadas ao LIVE | 1 (somente o bloco PRE, um SELECT) |
| Credenciais | nenhuma exposta ou registrada |

## Artefatos (sha256, conferidos antes da execução)

| Arquivo | sha256 |
|---|---|
| `5390_revoke_editor_cover_image_capabilities.sql` | `6202bb9876ab60c6753b19e61040f6d49b51ae645170a6f8cf3dba3899ec5212` (não enviado) |
| `S1_DEPLOY_readonly_checks.sql` | `b8034071b7e9dd537354950dfd5ff1bccc1600b73f989ac789ed379342c21fe0` (bloco PRE enviado: `df2b8a8e…`) |
| `ROLLBACK_S1.sql` | `01c719fd43cb0d23cddb68752bc6f05369e3440e9f3ca8a87db1121c697ec6b3` (não usado) |
| `static_check_s1.py` | 21/21 PASS (reexecutado antes do PRE) |

## PRE (somente leitura) — 2026-11-27 ~02:30Z

```json
{"executor":"postgres","dono_i1":"postgres","executor_e_dono_i1":true,"pode_alterar_objects":false,
 "barreira":"CLOSED","identidades_teste":0,"md5_i1":true,"md5_folder_ok":true,"md5_can_upload":true,
 "politicas_editor_3":true,"politicas_dono_e_5329":true,"keep_policies_md5":"ed949051c65bcb89301ecc77ae89c593",
 "ajudantes_so_politicas":true,"ajudantes_sem_outras_refs":true,
 "acl_i1":"authenticated=EXECUTE, postgres=EXECUTE","acl_i1_inesperado":"","herdeiros_dono_i1":"supabase_admin",
 "md5_titular_e_e33":true,"i1_presente":true,
 "arquivos_total":2,"arquivos_dono_comprovado":2,"arquivos_terceiros":0,"arquivos_sem_titularidade":0,"capas_atuais_de_terceiros":0}
```

| Item | Resultado |
|---|---|
| Barreira / identidades TEST | CLOSED / 0 |
| I1, `folder_ok`, `can_upload` (md5 canônico) | PASS |
| 3 políticas do EDITOR, só `authenticated` | PASS |
| 4 políticas do dono + 5329 | PASS (`keep_policies_md5` = `ed949051…`) |
| Ajudantes: só dependem as 3 políticas; nenhuma outra referência | PASS |
| ACL da I1 | `authenticated` + dono `postgres`; **sem `service_role`**; nada inesperado — PASS |
| Herdeiros do dono | `supabase_admin` (papel administrativo da plataforma, não cliente da API) |
| md5 titular + E3-3 | PASS |
| Arquivos históricos | 2 no bucket, 2 com titularidade comprovada, 0 de terceiros, 0 sem titularidade, 0 capas atuais de terceiros |
| **`pode_alterar_objects`** | **false — STOP** |

## Motivo do STOP

O critério 10.3 do README exige todos os booleanos do PRE verdadeiros. `pode_alterar_objects` verifica se `postgres` é membro do dono de `storage.objects` (`supabase_storage_admin`), e **não é**.

Esse critério **repete um defeito já conhecido**: em 2026-10-23, `P2-BINDER-IMAGE-UPLOAD-RLS-FIX-CORRECTION-01/02`, a mesma verificação falhou. Naquele dia, `postgres` comprovadamente criava e alterava políticas em `storage.objects` pelo mesmo canal: a 5176, a 5377 e o `ALTER POLICY` da 5237. O critério foi então removido e substituído por evidência de capacidade.

Ainda assim, um booleano falso é uma divergência material pelo contrato desta rodada. Por isso:

- **não executei a migration;**
- **não alterei o critério;**
- **não fiz consultas de diagnóstico adicionais**, porque a autorização era "exclusivamente o bloco PRE".

A migration 5390 em si **não** contém essa verificação de vínculo com o dono. O defeito está só no bloco PRE de `S1_DEPLOY_readonly_checks.sql`.

## Estado final

| Item | Valor |
|---|---|
| Migration 5390 | **não executada** |
| Banco / Storage | inalterados (só leitura) |
| Barreira | CLOSED; 0 identidades TEST |
| Rollback | não aplicável (nada foi alterado) |
| Cópia em `database/schema/` | não criada (só após implantação confirmada) |

## Correção aplicada (2026-11-27, `PRECHECK CORRECTION-01`, local, sem acesso ao LIVE)

- `pode_alterar_objects` foi removido do PRE e substituído por três itens:
  - `privilegios_observaveis`: relatório;
  - `pode_travar_objects`: critério;
  - `precedente_5377_mesmo_papel`: evidência histórica, não garantia.
- Justificativa e precedentes 5377 e 5237 conferidos: README §10.4.
- `S1_DEPLOY_readonly_checks.sql`: sha256 passou de `b8034071…` para `7f21360f24cb860a7712f32c9618329675c581624bb2c25a0e3258817d01e7c1`.
- `static_check_s1.py`: **24/24 PASS**. Testes de mutação confirmados: uma escrita no PRE derruba o K1, uma segunda instrução derruba o K1 e o critério antigo derruba o K4.
- 5390 e ROLLBACK_S1 **inalterados**, conferidos pelo sha256 no K6.
- O PRE corrigido ainda **não foi executado**. Ele exige nova autorização.

---

## Tentativa 2 — `E3-6 / S1-5390 — AUTHORIZED LIVE DEPLOYMENT RETRY-01` (2026-11-27 ~02:40Z) — PASS

### Projeto, canal, artefatos

| Item | Valor |
|---|---|
| Projeto | `qjfutqujxrbzgrtkpgkg` (mimikyu-core), conferido no PRE (mesma conexão) |
| Canal | conector Supabase da sessão → Management API `database/query` (como a S3); não grava `supabase_migrations` |
| Executor | `postgres` (`current_user`), dono da I1 |
| HEAD de referência | `605124209a8aa0c71c3a5c59c880a2187d1e7b79` |
| `5390_…sql` | `6202bb98…5ec5212`, inalterado; texto enviado do `begin;` ao `commit;` (sha256 `1f50c92e…`, 14.346 bytes; o cabeçalho é um único comentário `/* … */`, não foi enviado) |
| `S1_DEPLOY_readonly_checks.sql` | `7f21360f…01e7c1`; bloco PRE enviado `14d85bec…`, bloco POST enviado `802c0e0c…` |
| `ROLLBACK_S1.sql` | `01c719fd…ec6b3`, não usado |
| `static_check_s1.py` | 24/24 PASS antes do PRE |
| Chamadas ao LIVE | 3: PRE (SELECT), 5390 (uma transação), POST (SELECT) |

### PRE corrigido — PASS

```json
{"executor":"postgres","dono_i1":"postgres","executor_e_dono_i1":true,"barreira":"CLOSED","identidades_teste":0,
 "md5_i1":true,"md5_folder_ok":true,"md5_can_upload":true,"politicas_editor_3":true,"politicas_dono_e_5329":true,
 "keep_policies_md5":"ed949051c65bcb89301ecc77ae89c593","ajudantes_so_politicas":true,"ajudantes_sem_outras_refs":true,
 "acl_i1":"authenticated=EXECUTE, postgres=EXECUTE","acl_i1_inesperado":"","herdeiros_dono_i1":"supabase_admin",
 "md5_titular_e_e33":true,"i1_presente":true,"pode_travar_objects":true,"precedente_5377_mesmo_papel":true,
 "privilegios_observaveis":{"rolsuper":false,"rolbypassrls":true,"dono_objects":"supabase_storage_admin","membro_dono_objects":false,
                            "update":true,"delete":true,"truncate":true,"maintain":true},
 "arquivos_total":2,"arquivos_dono_comprovado":2,"arquivos_terceiros":0,"arquivos_sem_titularidade":0,"capas_atuais_de_terceiros":0}
```

| Classe | Itens | Resultado |
|---|---|---|
| Critérios PASS/STOP | todos os booleanos de primeiro nível; `acl_i1_inesperado` vazio | **PASS**; `keep_policies_md5` e ACL iguais aos da tentativa 1 |
| Privilégios observáveis (relatório) | `privilegios_observaveis` | `postgres` não é superusuário, tem BYPASSRLS e UPDATE/DELETE/TRUNCATE/MAINTAIN; não pertence a `supabase_storage_admin` |
| Precedente histórico (evidência, não garantia) | `precedente_5377_mesmo_papel` | true; a capacidade de `DROP POLICY` só se confirmou na execução (abaixo) |
| Arquivos históricos | `arquivos_*` | 2 arquivos, ambos com titularidade comprovada; 0 de terceiros, 0 sem titularidade, 0 capas atuais de terceiros: **nenhum bloqueador** |

### Transação 5390 — COMMIT

Uma chamada, transação única do arquivo:
1. precheck interno;
2. `lock_timeout 3s` e `LOCK … NOWAIT`;
3. três `DROP POLICY` e a verificação de dependentes;
4. dois `DROP FUNCTION`;
5. `REVOKE ALL` da I1 e o comentário;
6. postcheck interno.

Resultado: **sem erro**, resposta `[]`, **COMMIT confirmado**. Não houve recusa de `DROP POLICY` nem conflito de trava (55P03). Nenhuma repetição.

### POST — PASS

```json
{"politicas_editor_ausentes":true,"ajudantes_ausentes":true,"i1_presente_intacta":true,"acl_i1":"postgres=EXECUTE",
 "i1_so_dono":true,"clientes_sem_execute":true,"login_sem_execute":"postgres","keep_policies_md5":"ed949051c65bcb89301ecc77ae89c593",
 "e33_titular_execute":true,"md5_titular_e_e33":true,"emergency_stop_compat":true,"barreira":"CLOSED","identidades_teste":0,"arquivos_total":2}
```

| # | Verificação | Resultado |
|---|---|---|
| 1 | 3 políticas do EDITOR ausentes | PASS |
| 2 | 2 ajudantes removidos | PASS |
| 3 | I1 presente, corpo canônico (`8d211f8f…`) | PASS |
| 4 | `anon`, `authenticated`, `service_role` e `authenticator` sem EXECUTE efetivo, inclusive por herança | PASS; o único papel com login que executa é o dono `postgres`, administrativo |
| 5 | políticas do titular e da 5329 | PASS (`keep_policies_md5` = PRE) |
| 6 | E3-3 e titular: corpos e EXECUTE de `authenticated` | PASS (o postcheck interno também comparou as ACLs ao retrato do PRE) |
| 7 | compatibilidade com o `EMERGENCY_STOP_V1_13.sql` (I1 existe) | PASS |
| 8 | arquivos do bucket | 2 = PRE |
| 9–10 | barreira e identidades | CLOSED / 0 |

### Privilégios da I1: antes × depois

| | Antes | Depois |
|---|---|---|
| ACL | `authenticated=EXECUTE, postgres=EXECUTE` | `postgres=EXECUTE` (só o dono) |
| Clientes da API | `authenticated` executava; a barreira CLOSED recusava | nenhum executa |
| Vias I2–I4 (Storage) | 3 políticas + 2 ajudantes | ausentes |

### Estado final

- S1/5390 **implantada no LIVE**. Cópia canônica em `database/schema/5390_revoke_editor_cover_image_capabilities.sql`: só o bloco Status difere, e o corpo do `begin;` ao `commit;` é idêntico.
- Rollback não necessário, não executado.
- Barreira CLOSED; 0 identidades TEST.
- **Não comprovado:** provas funcionais pela API do Storage e pelo PostgREST (EDITOR recusado em RPC, envio, listagem e exclusão; titular envia, troca e remove; E3-3 funcionando). Ficam para a homologação E4.
