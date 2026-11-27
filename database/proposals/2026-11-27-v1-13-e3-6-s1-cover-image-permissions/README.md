# V1-13 · E3-6 / S1 — Correção das permissões de imagem da capa (5390)

| Campo | Valor |
|---|---|
| **Rodada** | `E3-6 / S1-5390 — COVER IMAGE PERMISSION CORRECTION-01` (2026-11-27) |
| **Status** | **5390 EXECUTADA NO LIVE / CANÔNICA** (2026-11-27, `AUTHORIZED LIVE DEPLOYMENT RETRY-01`): PRE corrigido PASS, COMMIT, POST PASS; barreira CLOSED; `database/schema/5390_…`; evidências em `S1_DEPLOY_EVIDENCE_2026-11-27.md`. Tentativa 1: STOP no PRE, critério corrigido em `PRECHECK CORRECTION-01` (§10.4). Quatro vias I1–I4 bloqueadas (I1 sem EXECUTE para clientes, com o corpo preservado para o script de emergência; I2–I4 removidas). `ROLLBACK_S1.sql` disponível, não executado. **Não homologada funcionalmente**: as provas pela API e pelo Storage ficam para a E4. |
| **Decisão** | D-E3-6 — imagem da capa gerenciada exclusivamente pelo titular; P0-C — remoção controlada, com prova de dependências, privilégios e não regressão do titular. |
| **Independência** | Separado de S2 (5391–5392), S3 (5393, implantada) e S4. |
| **Base conferida** | Versões implantadas da E1 (`e1e-security-evidence/g1/protected/5376_…`, `…/5377_…`; manifesto `e1deploy/E1_DEPLOY_MANIFEST.txt`), titular `database/schema/5176_…`, `5177_…`, `5178_…`, `5328_…`, `5329_…`; `g1/EMERGENCY_STOP_V1_13.sql`. |

## 1. Causa raiz

A E1-B2 (2026-11-15) implementou o C-239 na leitura de então — "o EDITOR edita nome, descrição e capa" — incluindo a **imagem** da capa: uma RPC (5376) e três políticas de Storage com dois ajudantes (5377). A D-E3-6 (2026-11-24) restringiu a imagem ao titular só no produto; o contrato técnico implantado continuou concedendo a capacidade. Hoje ela está **inerte** porque a barreira 5389 está CLOSED (as funções e as políticas consultam a porta), mas reabriria com a barreira em TEST/OPEN.

## 2. Capacidades indevidas do EDITOR (todas as vias, não só a interface)

| # | Objeto implantado | Via de acesso | O que o EDITOR consegue (com a barreira aberta) |
|---|---|---|---|
| I1 | `public.editor_set_collection_cover_logo(uuid, text)` (5376; EXECUTE para `authenticated`) | RPC direta (PostgREST) | **definir** a imagem da capa com arquivo na pasta do titular enviado por ele ou pelo titular; **substituir** a atual; **remover** (`p_path = NULL`); receber de volta o arquivo anterior que ele enviou, para apagar |
| I2 | política `collection_cover_insert_editor` em `storage.objects` (5377) + `collection_cover_editor_can_upload(text)` (VOLATILE, EXECUTE `authenticated`) | API do Storage (upload) | **enviar** arquivos para `<titular>/<coleção>/` (até 3 não usados) — inclusive por `copy` (a cópia é um INSERT no destino) |
| I3 | política `collection_cover_select_editor` + `collection_cover_editor_folder_ok(text)` (STABLE, EXECUTE `authenticated`) | API do Storage (listar/baixar) | ver os próprios envios na pasta do titular |
| I4 | política `collection_cover_delete_editor` + `collection_cover_editor_folder_ok(text)` | API do Storage (remove) | **apagar** os próprios envios que não são a capa atual |

**Vias conferidas e já fechadas ao EDITOR (não mudam):**
- `set_my_collection_cover_logo` (5178): exige `collection.owner_user_id = auth.uid()` — só o titular.
- políticas do dono (5176): pasta inicial = `auth.uid()` — o EDITOR só grava na pasta **dele**, que nenhuma função usa como capa de coleção alheia (a 5178 exige pasta do titular da própria coleção; a I1 exige pasta do titular).
- escrita direta em `collection.cover_logo_path`: `public.collection` tem RLS com só a política de SELECT do próprio dono e `authenticated` só tem `SELECT` (5030: "GRANT mínimo"); a coluna só muda por funções `SECURITY DEFINER` — a 5178 (titular) e a I1. Conferido também: nenhum outro arquivo canônico grava `cover_logo_path` (5177 cria a coluna; 5328/5329 só leem).
- não há política de UPDATE do EDITOR em `storage.objects` (postcheck da 5377).
- leitura da capa atual por participantes (5328/5329 `collection_cover_select_shared`): leitura autorizada da V1-12, não é gerenciamento — **fica**.

## 3. Dependências reais

| Objeto | Dependentes | Consequência para a correção |
|---|---|---|
| `editor_set_collection_cover_logo` | nenhum objeto do banco; nenhum uso no frontend (o parcial da E3-4 foi revertido, `git grep` vazio em `web/`); **`g1/EMERGENCY_STOP_V1_13.sql` linha 45** faz `revoke execute on function public.editor_set_collection_cover_logo(uuid, text)` **sem guarda** | `DROP` da função faria o bloco E2 do script de emergência falhar inteiro (transação abortada: nenhuma das outras revogações aplicada). Por isso: **REVOKE**, não DROP (ou DROP + correção do script — alternativa B) |
| políticas `collection_cover_*_editor` | o script de emergência usa `drop policy if exists` (seguro) | `DROP POLICY` direto (não há como "revogar" uma política) |
| `collection_cover_editor_folder_ok` / `_can_upload` | **só** as três políticas (pg_depend); o script de emergência não os toca e alerta para **não** revogar EXECUTE enquanto as políticas existirem (a avaliação das políticas falharia para todos os usuários do bucket) | `DROP FUNCTION` **depois** dos `DROP POLICY`, na mesma transação |
| `assert_collection_editor`, `editor_update_collection_metadata`, `editor_set_collection_cover_finish`, `editor_set_collection_cover_code` (5376) | E3-3 (frontend) e a 5380 (`assert_collection_editor`) | **não mudam** |
| `E1_DEPLOY_STATE_readonly.sql` (verificação histórica da E1) | lista as 37 capacidades, incluindo I1–I4 | ferramenta do estado de 2026-11-18; depois da S1 esse retrato deixa de valer — registrar (não reexecutar como prova) |
| `storage.objects` | `DROP POLICY` pede ACCESS EXCLUSIVE na tabela (risco O2 já registrado no script de emergência) | `lock_timeout` curto + `lock table storage.objects in access exclusive mode nowait`; `55P03` → nada muda, repetir em janela |

## 4. Alternativas

| | **A — recomendada** | B | C |
|---|---|---|---|
| I1 RPC | `REVOKE EXECUTE … FROM PUBLIC, anon, authenticated, service_role` (função mantida, inacessível a clientes) | `DROP FUNCTION` + script de emergência regenerado com guarda | substituir o corpo por recusa fixa `OPERATION_RESERVED_TO_OWNER` |
| I2–I4 Storage | `DROP POLICY` das três políticas + `DROP FUNCTION` dos dois ajudantes | igual | igual |
| Prós | menor intervenção; script de emergência continua funcionando sem edição; reversão simples (GRANT) | remove o código | recusa explícita em vez de "permissão negada" |
| Contras | corpo antigo continua no catálogo (inalcançável; `service_role`/`postgres` ainda poderiam chamar — confiáveis) | toca um artefato de emergência gerado (G1) e o manifesto; mais superfície de revisão | `CREATE OR REPLACE` de função implantada; mantém EXECUTE para clientes |

**Escolha: A.** Cumpre o P0-C (remoção controlada das capacidades: as políticas e os ajudantes deixam de existir; a RPC deixa de ser executável por qualquer cliente), sem tocar o titular, a E3-3, a 5380 nem o procedimento de emergência.

## 5. Desenho da 5390 (a escrever só depois da auditoria)

Uma transação (`begin; … commit;`), padrão STD-001 §10, sem a porta 5389 (não cria capacidade):

1. **Precheck** (aborta se qualquer item falhar):
   - barreira CLOSED e 0 identidades TEST;
   - md5 do prosrc implantado = artefato da E1: `editor_set_collection_cover_logo` `8d211f8fa20bb064fc7085038281ab24`; `collection_cover_editor_folder_ok` `5e9fdc4b2dec92663594ddd2cc427711`; `collection_cover_editor_can_upload` `abce88d6802c00982735bc286a3edfc3`;
   - as 3 políticas do EDITOR existem; as 4 do dono (5176) existem; a 5329 `collection_cover_select_shared` existe;
   - nenhuma outra política e nenhum `prosrc` de função fora do conjunto I1–I4 referencia os dois ajudantes;
   - **nenhum objeto no bucket `collection-cover` enviado por quem não é o dono da pasta** (`owner_id <> (storage.foldername(name))[1]`) — evidência de que nenhum EDITOR usou a capacidade; se houver, STOP (decisão sobre os arquivos antes);
   - md5 das funções que ficam: titular `set_my_collection_cover_logo` `5868fb1c8de760787d1128ac20a09507`, `set_my_collection_cover_finish` `4f48d9161b4a29ecb23e7443e31d1806`, `set_my_collection_cover_code` `d0d8cbfa517b9da3728a55af47de21cb`, `update_collection_metadata` `a581235db9cabaf7043707a290f963b7`; E3-3 `editor_update_collection_metadata` `81da7a37…`, `editor_set_collection_cover_finish` `8fc815a4…`, `editor_set_collection_cover_code` `4feb35ab…`, `assert_collection_editor` `9a748258…`;
   - assinatura (hash) da definição das 4 políticas do dono e da 5329 (`qual`/`with_check` de `pg_policies`) registrada para o postcheck.
2. `set local lock_timeout = '5s'; lock table storage.objects in access exclusive mode nowait;`
3. `drop policy collection_cover_insert_editor on storage.objects;` (idem `select_editor`, `delete_editor`) — sem `if exists` (o precheck já garantiu a presença; ausência = estado divergente).
4. `drop function public.collection_cover_editor_can_upload(text); drop function public.collection_cover_editor_folder_ok(text);`
5. `revoke execute on function public.editor_set_collection_cover_logo(uuid, text) from public, anon, authenticated, service_role;` + comentário da função atualizado ("D-E3-6/S1: sem EXECUTE para clientes").
6. **Postcheck**: as 3 políticas e os 2 ajudantes ausentes; `has_function_privilege(authenticated|anon|service_role, editor_set_collection_cover_logo, EXECUTE)` = false; funções que ficam com o mesmo md5 e os mesmos grants (E3-3 continua EXECUTE para `authenticated`); 4 políticas do dono e a 5329 com a mesma definição do precheck; barreira CLOSED.

**Rollback R5390** (só emergência; reintroduz a incompatibilidade): recriar os 2 ajudantes e as 3 políticas com o texto exato da 5377 protegida e `grant execute … editor_set_collection_cover_logo … to authenticated`.

## 6. Matriz de autorização esperada (depois da 5390)

| Operação | OWNER | EDITOR | VIEWER |
|---|---|---|---|
| Adicionar imagem da capa (upload na própria pasta + 5178) | Permitido | **Negado** — sem política de envio na pasta do titular; 5178 recusa coleção alheia | Negado |
| Substituir imagem da capa | Permitido (5178) | **Negado** — RPC sem EXECUTE (`permission denied`); 5178 recusa | Negado |
| Remover imagem da capa | Permitido (5178 com nulo; apagar arquivo pela 5176) | **Negado** — RPC sem EXECUTE; sem política de exclusão na pasta do titular | Negado |
| Ver a capa atual | Permitido | Permitido (5328/5329, sem mudança) | Permitido |
| Alterar nome, descrição, cor e código da capa | Permitido | Permitido (5376, E3-3, atrás da barreira) | Negado |

Chamadas diretas: as vias da seção 2 deixam de existir ou ficam sem EXECUTE; as vias do titular não mudam.

## 7. Validação (diretriz vigente: sem ambiente isolado, sem testes sintéticos no LIVE)

| Etapa | Conteúdo | Quando |
|---|---|---|
| Inspeção estática | script local: forma da migration, md5 do precheck = artefatos, nenhum objeto do titular/E3-3 no texto de `drop`/`revoke`, rollback literal | ao escrever a 5390 |
| PRE somente leitura | os itens do precheck como uma `select` de relatório (inclui a contagem de objetos de terceiros no bucket) | antes da autorização de aplicar |
| Migration transacional | só com autorização específica; barreira continua CLOSED | depois do PRE |
| POST somente leitura | itens do postcheck como relatório | logo depois |
| Provas funcionais | EDITOR recusado em RPC/upload/remove pela API real; titular envia, troca e remove; E3-3 funciona | homologação (TEST com identidades reais), não agora |

**PASS:** precheck sem divergência, transação confirmada, postcheck com todas as condições, barreira CLOSED. **FAIL/STOP:** qualquer md5 divergente, objeto de terceiro no bucket, `55P03` (nada muda; nova janela), qualquer diferença nas políticas do dono, na 5329 ou nos grants da E3-3.

## 8. Impacto

- **Titular:** nenhum (5176, 5177, 5178, 5328, 5329 intactas e conferidas por hash).
- **EDITOR:** perde só I1–I4 (nunca expostos na interface; inertes hoje). Mantém E3-3 (nome, descrição, cor, código).
- **VIEWER / vitrine:** nenhum.
- **D-E3-6:** com a 5390 aplicada, a restrição passa a ser **garantida pelo servidor**; o bloqueador "5376/5377 permitem imagem pelo EDITOR" é encerrado. Continuam G3/G4/G5 da 5393, S4 e S2 para a abertura funcional.

## 9. Riscos residuais

- Corpo da `editor_set_collection_cover_logo` permanece no catálogo (sem EXECUTE para clientes); remoção definitiva fica para quando o script de emergência for regenerado (alternativa B), se desejado.
- `DROP POLICY` precisa de ACCESS EXCLUSIVE em `storage.objects`: janela curta, `NOWAIT`.
- Verificação do bucket depende de `owner_id` refletir quem enviou (comportamento da API do Storage); objetos antigos sem `owner_id` contam como "não comprovados" e entram no relatório do PRE.
- Provas funcionais pela API real só na homologação.

---

## 10. Artefatos (2026-11-27, `SQL PREPARATION-01`) — 5390 EXECUTADA NO LIVE / CANÔNICA (`RETRY-01`)

| Arquivo | Conteúdo |
|---|---|
| `5390_revoke_editor_cover_image_capabilities.sql` | uma transação: precheck (barreira CLOSED, 0 identidades; md5 de I1 `8d211f8f…`, folder_ok `5e9fdc4b…`, can_upload `abce88d6…`; 3 políticas do EDITOR; dependentes dos ajudantes = só as 3 políticas, nenhuma função/política fora do conjunto os cita; ACL da I1 só com dono/`authenticated`/`service_role`, senão STOP; md5 do titular e da E3-3; 5 políticas que ficam) → retrato das políticas e ACLs que ficam em GUC local → `lock_timeout 3s` + `lock table storage.objects in access exclusive mode nowait` → 3 `drop policy` → verificação de dependentes → 2 `drop function` → `revoke all` da I1 de `public, anon, authenticated, service_role` + comentário → postcheck |
| `ROLLBACK_S1.sql` | R5390: recria ajudantes e políticas com o texto exato da 5377 implantada e devolve EXECUTE da I1 a `authenticated` (`service_role` só se constava no ACL do PRE). **Reintroduz as capacidades indevidas**; nunca automático; não toca arquivos |
| `S1_DEPLOY_readonly_checks.sql` | PRE e POST, um `select` cada, só contagens e nomes de papéis do banco |
| `static_check_s1.py` | verificação estática do texto — **24/24 PASS** (21 da preparação + K4–K6 da `PRECHECK CORRECTION-01`; K1 passou a ignorar literais) |

### 10.1 Privilégios efetivos considerados (I1)

- **PRE:** ACL completo (`acl_i1`); qualquer EXECUTE fora de {dono, `authenticated`, `service_role`} — inclusive `PUBLIC` ou concessão direta a outro papel — aparece em `acl_i1_inesperado` e o precheck da migration aborta (STOP para análise). `herdeiros_dono_i1` lista os papéis que herdam do dono (administrativos; não são autorização funcional).
- **POST (e postcheck interno):** ACL da I1 só com o dono; `has_function_privilege` falso para `anon`, `authenticated`, `service_role` e `authenticator` (inclui herança); `login_sem_execute` lista os papéis com login, não superusuários, que ainda executam — esperado: só o dono/papéis administrativos que herdam dele; qualquer papel de cliente ali = STOP.
- O privilégio do **dono** (e de quem herda dele) é administrativo: chamar a função exige uma sessão com esse papel, que nenhum cliente da API recebe.

### 10.2 Arquivos históricos do bucket `collection-cover` (PRE, só contagens; nada é alterado)

| Classe | Regra | Tratamento |
|---|---|---|
| Titularidade comprovada | `owner_id` (ou `owner`) = dono da pasta | nenhum |
| Enviados por terceiros | `owner_id` presente e ≠ dono da pasta | relatório; com a barreira CLOSED desde a implantação da E1, o esperado é 0. Depois da 5390 o terceiro perde ver/apagar (I3/I4) e o titular continua gerenciando pela 5176 (pasta dele) — **não há acesso residual**; não bloqueia sozinho |
| Sem titularidade comprovável | `owner_id` e `owner` nulos | relatório; não bloqueia sozinho |
| Capa atual de terceiro | `cover_logo_path` aponta para arquivo de outro dono | relatório; a 5390 impede novas trocas, mas a capa vigente continua; se > 0, é **bloqueador específico de produto** (decisão do titular sobre manter ou trocar a capa), não da migration |

Registros históricos nunca alteram a migration automaticamente.

### 10.3 Critérios

> **2026-11-27 — STOP no PRE** (`AUTHORIZED LIVE DEPLOYMENT-01`): `pode_alterar_objects = false`; demais itens PASS; 5390 não executada (`S1_DEPLOY_EVIDENCE_2026-11-27.md`). Critério corrigido em `PRECHECK CORRECTION-01` (§10.4).

> **2026-11-27 — PASS** (`AUTHORIZED LIVE DEPLOYMENT RETRY-01`): PRE corrigido PASS → transação única com COMMIT (sem recusa de `DROP POLICY`, sem 55P03) → POST PASS: I1 só com o dono, I2–I4 removidas, titular, E3-3 e 5329 intactos, 2 arquivos (= PRE), barreira CLOSED. Canônica em `database/schema/5390_…`. Provas funcionais pela API e pelo Storage pendentes (E4).

- **PASS:** PRE com todos os booleanos verdadeiros e `acl_i1_inesperado` vazio; transação confirmada; POST com todos os booleanos verdadeiros, `acl_i1` só com o dono, `keep_policies_md5` igual ao do PRE, `arquivos_total` igual ao do PRE, barreira CLOSED, 0 identidades.
- **STOP:** qualquer booleano falso; privilégio inesperado; dependente inesperado; `55P03` (trava ocupada — nada persiste; nova janela por decisão do operador, sem repetição automática); qualquer erro na transação (nada persiste; diagnosticar antes de qualquer reversão — o rollback **não** se aplica a transação abortada).
- **Capacidade sobre `storage.objects`:** ver §10.4. PRE com `pode_travar_objects` e `precedente_5377_mesmo_papel` verdadeiros; `privilegios_observaveis` é relatório.
- **Provas funcionais** (EDITOR recusado pela API real em RPC/upload/listar/apagar; titular envia, troca e remove; E3-3 funciona): homologação E4, com autorização própria.

### 10.4 Capacidade sobre `storage.objects` (2026-11-27, `PRECHECK CORRECTION-01`)

O `pode_alterar_objects` exigia que o executor pertencesse ao dono de `storage.objects` (`supabase_storage_admin`). **Esse critério gerou o falso bloqueio.** O `postgres` não pertence a esse papel e mesmo assim já criou e alterou políticas nessa tabela, pelo mesmo canal. A 5237 viveu o mesmo defeito em 2026-10-23 e teve o critério removido na `CORRECTION-02`. O item saiu do PRE e foi substituído por três itens separados:

| Item | Natureza | O que mostra | O que não mostra |
|---|---|---|---|
| `privilegios_observaveis` | relatório | `rolsuper`, `rolbypassrls`, dono da tabela, pertencimento a ele (esperado: `false`), UPDATE, DELETE, TRUNCATE e MAINTAIN | DML e `rolbypassrls` **não** comprovam, sozinhos, autorização para `DROP POLICY` |
| `pode_travar_objects` | critério | o executor pode emitir `LOCK TABLE … ACCESS EXCLUSIVE`; no PG 17, isso exige UPDATE, DELETE, TRUNCATE ou MAINTAIN | `DROP POLICY` |
| `precedente_5377_mesmo_papel` | **evidência histórica**, critério de coerência | os dois ajudantes pertencem ao executor atual; eles foram criados na **mesma transação** da 5377 que criou as três políticas a remover | **não é garantia.** `DROP POLICY` exige ser dono da tabela, e nenhum booleano de catálogo prova isso |

**Precedentes conferidos no repositório:**
- **5377**, recuperação R1 da E1, 2026-11-18 02:03:40Z (`e1e/e1e2/README.md` §15):
  - projeto `qjfutqujxrbzgrtkpgkg`, canal `db query --remote`, a mesma Management API `database/query` da S3 e da S1;
  - executor `postgres` (exigido pela S0, item T6);
  - DDL: `CREATE POLICY` × 3 em `storage.objects` (`badd1f54…`), `CONFIRMADA`, estado final 26/26.
- **5237**, 2026-10-23 (`2026-10-23-p2-binder-image-upload-rls-fix/README.md`):
  - canal `apply_migration`, ledger `20261023202009`; R1-pré executado como `postgres`;
  - DDL: `ALTER POLICY` em `storage.objects`; POST-1 8/8, POST-2 igual ao PRE-5, e F1–F6 PASS depois;
  - critério aceito: `rolbypassrls` ou `rolsuper`, sem exigir pertencimento ao dono; as políticas preexistentes foram tratadas como evidência de compatibilidade, não como prova de autorização;
  - **canal diferente do da S1**; o executor do `apply_migration` não foi registrado à parte.

**Garantia final:** é a própria transação. Se `DROP POLICY` for recusado (42501, falta de dono), a 5390 aborta inteira e nada persiste. Nesse caso: STOP, sem repetição e sem rollback, porque não há o que reverter.
