# V1-16 — Condição física por exemplar · proposta SQL (S1–S4)

| Campo | Valor |
|---|---|
| **Estado** | **S1–S4 APLICADAS NO LIVE em 2026-11-13** (projeto `qjfutqujxrbzgrtkpgkg`), STRUCTURAL PASS em cada etapa; **sem registro no ledger de migrations do Supabase** (ver "Execução no LIVE"). Frontend homologado pelo proprietário (6/6 cenários). Ainda **não promovidas** para `database/schema/` — promoção só por decisão posterior. Histórico da preparação: `SQL PREPARATION-01`, `INDEPENDENT SQL AUDIT-01`, `INDEPENDENT AUDIT CORRECTIONS-01`. |
| **Contrato** | `docs/domain-modeling/collections/concept-decisions.md` C-227–C-233 (C-108 substituída por C-228); `docs/05d-colecoes-e-usuarios.md` v3.01, seção "Condição física por exemplar (V1-16) — contrato". |
| **Plano** | `V1-16 \| DATABASE IMPLEMENTATION PLAN-01` (aprovado) e decisões de `SQL PREPARATION-01`. |
| **Execução** | Pelo proprietário, **uma etapa por vez**, só depois do GO da etapa anterior (STD-001 §10). Comandos, canais, STOP/GO, classificação dos testes e recuperação: `CONTROLLED-EXECUTION-PROTOCOL.md` (prevalece sobre as seções "Ordem de execução" e "Recuperação" abaixo). |

## Arquivos

| Arquivo | Etapa | O que faz |
|---|---|---|
| `5361_add_physical_card_condition_code.sql` | S1 | `physical_card.condition_code text NOT NULL DEFAULT 'NM'` + FK `card_condition(code)` (NOT VALID → VALIDATE). Inicializa todos os exemplares como NM sem reescrever linhas. **v1.1** (2026-11-13): a etapa inteira é um único `DO`, sem tabela temporária nem `begin`/`commit`. A v1.0 falhou no SQL Editor com 42P01 `_v116_s1_before`; ver protocolo §11. |
| `5362_extend_bulk_registration_with_condition.sql` | S2 | Validação única `physical_card_unknown_condition_codes(text[])` (nova, interna) + `CREATE OR REPLACE` de 5153, 5155, 5157 e 5158 com a condição. Uma migration só (prévia e confirmação nunca divergem). |
| `5363_evolve_get_my_inventory_item_copies_condition.sql` | S3 | `DROP + CREATE` de `get_my_inventory_item_copies` (padrão da 5262): mesmas 20 colunas + `condition_code` ao final. |
| `5364_create_set_my_physical_cards_condition.sql` | S4 | Nova `set_my_physical_cards_condition(uuid[], text)`: edição individual/em lote (≤ 500) dos exemplares do próprio usuário, todos ou nenhum, idempotente. v1.1: trava antes de conferir titularidade e quantidade (remoção concorrente reprova o lote). |
| `5887_validate_physical_card_condition_HARNESS.sql` | S1–S4 | Harness de três chamadas (BEGIN…SELECT; ROLLBACK; postcheck). Gate com as quatro etapas: **66/66/0/0**. **Não roda diretamente** no ambiente autorizado: usar os recortes de chamada única derivados. |
| `CONTROLLED-EXECUTION-PROTOCOL.md` | S0–S4 | Protocolo definitivo de execução controlada (substitui `OFFLINE-VALIDATION-RUNBOOK.md`, preservado como histórico). |
| `controlled-execution/` | S0–S4 | `S0_readonly_precheck.sql` e `POSTCHECK_readonly.sql` (leitura, uma instrução cada); `5887_S1…S4_singlecall.sql`, `5822_singlecall.sql`, `5826_singlecall.sql` (harness de chamada única, sem COMMIT, relatório por `RAISE EXCEPTION`); `R4…R1_rollback_*.sql` (recuperação derivada dos corpos canônicos); `derive_singlecall.py` (gerador e verificador); `MANIFEST.sha256`. |
| `CONCURRENCY-5364-TWO-SESSIONS.sql` | S4 | Prova de duas sessões. **Não executar** no ambiente autorizado: comita fixtures em dados reais (protocolo §6.3). |

## Decisões refletidas no SQL

1. Mesma variante e idioma com **condições diferentes** = linhas legítimas no mesmo pedido.
2. Proibida a duplicação do **trio** `(card_variant_id, language_id, condition_code)`; condição ausente ≡ `NM` também na duplicidade.
3. Condição ausente ≡ `NM` na validação e na idempotência: a intenção do `request_hash` só recebe `condition_code` quando ≠ `NM` → **hashes históricos de pedidos NM preservados** (harness B07/B08/B23).
4. Set inteiro (B2): `condition_code` **no nível do pedido**, aplicado a todos os exemplares criados.
5. A condição é **intenção** (mora no `request_hash`, como `quantity` — D9), **não** estado do mundo: `preview_fingerprint` (5149/5156) **não muda** (harness B05).

## O que NÃO muda

5147, 5148, 5149, 5154, 5156, 5012, Pricing (`card_condition`, `pricing_condition_mapping`), completude, reservas, Favoritos, Lista de desejos, fichário, superfícies compartilhadas/públicas. O frontend publicado continua funcionando depois de cada etapa (todas só acrescentam).

## S0 — pré-checagem só leitura (antes de S1)

```sql
-- 1) Escala canônica
select string_agg(code || ':' || condition_order, ',' order by condition_order) from public.card_condition;
--    esperado: M:1,NM:2,LP:3,MP:4,HP:5,DMG:6

-- 2) Corpos vigentes = canônicos (os prechecks de 5362/5363 recusam qualquer divergência)
select p.proname, md5(p.prosrc) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname in ('bulk_register_physical_card_items','register_physical_cards_bulk',
       'register_card_set_bulk','preview_bulk_operation','get_my_inventory_item_copies') order by 1;
--    esperado: a5fd5107cc008b68a6d598a1a0501a6e (5153) · 0b7221b6a2485ad75e2918365f515e0a (5155)
--              1526fd4d633f29f91ddc5c49141eef59 (5157) · 8dcf2656676739b5417b94b4882bd26c (5158)
--              d8cce43b511856a5e25f061e75a7cede (5262); uma linha por função.

-- 3) Retorno vigente de get_my_inventory_item_copies (5363 compara literalmente)
select pg_get_function_result(to_regprocedure('public.get_my_inventory_item_copies(uuid, text)'));
--    esperado: as 18 colunas da 5162 + ", variant_type_code text, rarity_code text)"

-- 4) Contagens de referência (anotar)
select (select count(*) from public.physical_card) as physical_card,
       (select count(*) from public.collection_allocation) as collection_allocation,
       (select count(*) from public.physical_card where storage_container_id is not null) as with_storage;
```

**STOP** se qualquer resultado divergir — reportar antes de seguir.

> Os md5 "vigentes" foram calculados dos arquivos canônicos de `database/schema` pelo mesmo método já usado na 5262 (o método reproduz o md5 `0835268e…` registrado para a 5162). A conferência 2) no LIVE é o que confirma.

## Ordem de execução — uma etapa por vez

> **Substituída** pelo §5 de `CONTROLLED-EXECUTION-PROTOCOL.md`. A ordem continua a mesma; mudam o canal (psql), os arquivos de harness (recortes de chamada única) e os critérios de evidência. A tabela abaixo é mantida como registro da preparação.

| # | Executar | GO (todos) | STOP |
|---|---|---|---|
| 1 | S0 acima | Todos os esperados conferem | Qualquer divergência |
| 2 | `5361` | Sem exceção; postcheck interno OK; `select count(*) filter (where condition_code <> 'NM') from public.physical_card` = 0; contagens = S0; frontend publicado funcionando | Exceção (`lock_timeout` → repetir fora de uso; `PRECHECK`/`POSTCHECK` → reportar) |
| 3 | `5887` só X01, F e A (comentar B, C, D e X02 — sem escrita real neste recorte; total esperado 9) | gate OK; CALL 3 = baseline | Qualquer FAIL |
| 4 | `5362` | Sem exceção; postcheck de md5/ACL OK | Exceção |
| 5 | `5887` grupos X, F, A, B (comentar C e D; total 34) **e** reexecução de `5822`, `5823` (2026-10-16), `5824`, `5826` com os gates originais | Todos os gates OK; resíduo zero | Qualquer FAIL (ver "Recuperação") |
| 6 | `5363` | Sem exceção; postcheck OK | Exceção |
| 7 | `5887` grupos X, F, A, B, C (comentar D; total 41) | gate OK | FAIL |
| 8 | `5364` | Sem exceção; postcheck OK | Exceção |
| 9 | `5887` completo (66) | **66/66/0/0**; CALL 3 = baseline | FAIL |

Depois do passo 9: frontend do V1-16 (fora desta pasta), homologação e publicação. Promover para `database/schema/` só os arquivos **confirmadamente executados**.

**Aplicação pelo `apply_migration` do Supabase:** como nas propostas anteriores, enviar sem as linhas `begin;`/`commit;` externas (a ferramenta já envolve em transação) — o corpo das funções é idêntico.

## Recuperação

> **Correção (2026-11-13, `CONTROLLED EXECUTION READINESS-01`):** a tabela abaixo não funcionaria como escrita. Reaplicar `database/schema/5153` e `5157` falha porque usam `CREATE FUNCTION`. Reaplicar a `5262` falha porque o PRECHECK dela exige o corpo da `5162`. A recuperação válida está em `controlled-execution/R4…R1_rollback_*.sql`, na ordem R4 → R1 e só por decisão do proprietário (protocolo §7). A tabela fica como registro da intenção.

| Etapa | Como desfazer |
|---|---|
| 5364 | `drop function public.set_my_physical_cards_condition(uuid[], text);` |
| 5363 | `drop function public.get_my_inventory_item_copies(uuid, text);` e reaplicar `database/schema/5262` (corpo + ACL). |
| 5362 | Reaplicar os corpos canônicos de `5153`, `5155`, `5157`, `5158` (database/schema) e `drop function public.physical_card_unknown_condition_codes(text[]);` |
| 5361 | **Só antes de existir edição real de condição:** `alter table public.physical_card drop constraint fk_physical_card_condition_code; alter table public.physical_card drop column condition_code;` Depois de 5364 em uso, desfazer apaga condições declaradas — exige decisão explícita do proprietário. |

## Reaplicação

Todas as etapas recusam reaplicação com mensagem explícita (`PRECHECK …: JÁ APLICADA`) e distinguem estado parcial/divergente (`ESTADO DIVERGENTE`). Nenhuma etapa aceita silenciosamente uma estrutura diferente da esperada.

## Harnesses legados

- `5822`, `5823`, `5824`, `5826`: **sem alteração de arquivo**. Os trechos que eles verificam foram preservados de propósito: prefixos `p_request aceita exatamente as chaves…`, `cada item de items aceita exatamente as chaves`, `duplicado(s)`; `CARD_VARIANT_INACTIVE` antes de `INSERT INTO public.physical_card` (5153); Preview sem `insert/update/delete/merge/truncate/for update` e sem lock/claim (5158); `FOR UPDATE` ausente de 5155. Reexecutar no passo 5.
- `5858`: o cabeçalho da 5262 cita uma "Query 5858" como validação, mas **nenhum arquivo 5858 foi encontrado no repositório** — não há harness legado da leitura a reexecutar ou adaptar. A evolução da leitura em S3 (retorno de 21 colunas, md5, ACL, leitura do dono com condição, isolamento entre usuários, anônimo) é coberta pelo **grupo C do `5887`**. O comentário de cabeçalho da `5363` ainda menciona o 5858 nos termos antigos; não foi editado nesta rodada (restrição de não alterar 5361–5363 sem defeito comprovado — é só comentário, fora do corpo da função e do md5).

## Execução no LIVE (rastreabilidade — `RELEASE PACKAGE READINESS-01`, 2026-11-13)

| Artefato | Executado no LIVE? | Canal | Evidência |
|---|---|---|---|
| `5361` **v1.0** | **Sim** (DDL persistida — caso D2) | SQL Editor | Falhou no postcheck (42P01); `S1_FAILURE_DIAGNOSIS_readonly.sql` + `POSTCHECK` classificaram D2: coluna e FK íntegras, todos os exemplares NM (protocolo §11, "Resolução"). O texto exato da v1.0 não está nesta pasta. |
| `5361` **v1.1** (arquivo atual) | **Não** | — | Reescrita como um único `DO` depois da falha; DDL textualmente igual à v1.0 (protocolo §11). Referência para a promoção futura. |
| `5362` | Sim, arquivo integral e inalterado | MCP `execute_sql`, chamada única | md5 dos corpos no LIVE = 5153 `86426fc0…`, 5155 `d08dcc25…`, 5157 `83cd76fc…`, 5158 `99f7b2e2…`, validação `df223290…` (protocolo §12; reconferido somente leitura em 2026-11-13). |
| `5363` | Sim, integral | MCP `execute_sql`, chamada única | `get_my_inventory_item_copies` md5 `77abbb9a…` (§13). |
| `5364` **v1.1** | Sim, integral | MCP `execute_sql`, chamada única | `set_my_physical_cards_condition` md5 `b569ecdb…` (§14). |
| Leituras `S0`, `POSTCHECK`, `S1_FAILURE_DIAGNOSIS`, `S2_TX_PROBE`, `S2_STATE`, `S2_PREVIEW_PROBE` (16/16), `S3_STATE`, `S3_PROBE` (4/4), `S4_STATE`, `S4_PROBE` (13/13) | Sim, somente leitura | MCP `execute_sql` / SQL Editor | Protocolo §11–§14. |
| `5887` harness e recortes `5887_S1…S4_singlecall`, `5822_singlecall`, `5826_singlecall` | **Não** (produção sem harness autorizado) | — | — |
| `R1…R4_rollback_*` | **Não** | — | Recuperação preparada, nunca usada. |
| `CONCURRENCY-5364-TWO-SESSIONS.sql` | **Não** | — | Comita fixtures; proibido no LIVE (§6.3). |
| `derive_singlecall.py` | Ferramenta local (gera os recortes) | — | — |

**Ledger de migrations.** Nenhuma das quatro etapas está em `supabase_migrations.schema_migrations` (último registro: `20261110010926 pokedex_binder_auto_arrange`). Divergência conhecida e aceita; não corrigida automaticamente. Registrar ou promover exige decisão própria do proprietário.

**Integridade.** `controlled-execution/MANIFEST.sha256` confere 29/29 arquivos (20 derivados + 9 fontes, incluindo 5361 v1.1–5364).
