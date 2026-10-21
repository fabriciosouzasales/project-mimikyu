# WHERE-02 — Plano de execução controlada no LIVE (GATE-01)

Status: **EXECUTADO — PASS (2026-10-21 UTC).** Fases 0–4 cumpridas: pré-check confirmado, 8 migrations sem erro, verificações de schema/permissões conformes, `5847` 26/26, integridade e resíduo zero, advisor sem achado inesperado. K1 não executada (dispensada pela auditoria). Nenhuma recuperação necessária.
Projeto Supabase: `mimikyu-core` (`qjfutqujxrbzgrtkpgkg`). Ledger atual: `20261019034933`.

## Fase 0 — Pré-check (somente leitura)

Executar e comparar com a linha de base capturada em 2026-10-20 (WHERE-02 GATE-01):

```sql
select
 (select max(version) from supabase_migrations.schema_migrations)            as last_migration,   -- 20261019034933
 to_regclass('public.storage_container_kind')                                 as kind_tbl,         -- null
 to_regclass('public.storage_container_creation_request')                     as req_tbl,          -- null
 (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname in ('create_my_storage_container','update_my_storage_container',
     'delete_my_storage_container','get_my_storage_locations','get_my_storage_summary')) as fn_conflicts, -- 0
 (select count(*) from information_schema.columns where table_schema='public'
   and table_name='storage_container' and column_name='kind_code')           as kind_col,         -- 0
 (select count(*) from public.storage_container sc
   where sc.name <> btrim(sc.name) or sc.name = '' or char_length(sc.name) > 60) as bad_names,     -- 0
 (select c.confdeltype from pg_constraint c
   where c.conname = 'collection_creation_request_storage_container_id_fkey') as ccr_fk_del,       -- 'c'
 (select is_nullable from information_schema.columns where table_schema='public'
   and table_name='collection_creation_request' and column_name='storage_container_id') as ccr_null, -- NO
 (select count(*) from public.storage_container)                              as sc,               -- 1
 (select count(*) from public.collection)                                     as co,               -- 10
 (select count(*) from public.collection_creation_request)                    as ccr,              -- 10
 (select count(*) from public.physical_card)                                  as pc,               -- 1351
 (select count(*) from public.physical_card where storage_container_id is not null) as pc_located, -- 0
 (select count(*) from public.collection_allocation)                          as ca,               -- 210
 (select count(*) from auth.users)                                            as users,            -- 3
 (select md5(string_agg(id::text||':'||collection_id::text||':'||storage_container_id::text||':'||storage_container_created, ',' order by id))
    from public.collection_creation_request)                                 as ccr_fp,           -- d13de726a8cbcd8e25455c0c23efae1d
 (select md5(string_agg(id::text||':'||default_storage_container_id::text, ',' order by id))
    from public.collection)                                                  as co_default_fp;    -- 264450ab182078ca80da575cb24f50ee
```

**STOP** se qualquer objeto novo já existir, `bad_names > 0`, ledger diferente sem explicação, ou FKs com definição diferente. Contagens de usuários/coleções/exemplares podem ter variado por uso normal — nesse caso, registrar a nova linha de base e seguir (não é STOP); o que importa é a comparação **antes × depois** da aplicação.

## Fase 1 — Aplicação (uma migration por arquivo, nesta ordem)

| # | Arquivo | Natureza | Bloqueio esperado |
|---|---|---|---|
| 1 | 5212 | CREATE TABLE + seed + RLS | nenhum |
| 2 | 5213 | ADD COLUMN (nullable, sem default), ADD CHECK, 2 índices | ACCESS EXCLUSIVE breve em `storage_container` (1 linha) e SHARE em `collection` (10 linhas) |
| 3 | 5214 | DROP NOT NULL + troca da FK | ACCESS EXCLUSIVE breve em `collection_creation_request` (10 linhas) |
| 4 | 5215 | CREATE TABLE | nenhum |
| 5 | 5216 | CREATE FUNCTION | nenhum |
| 6 | 5217 | CREATE FUNCTION | nenhum |
| 7 | 5218 | CREATE FUNCTION (pré-checagem exige 5214) | nenhum |
| 8 | 5219 | CREATE FUNCTION ×2 | nenhum |

Cada arquivo é atômico (`begin … commit`). Executor: Fabrício no SQL Editor, ou o agente via `apply_migration` **somente com autorização expressa**. Após cada arquivo, conferir que não houve erro antes de seguir; **STOP no primeiro erro** (os anteriores já aplicados permanecem — ver Recuperação).

## Fase 2 — Verificações de schema e permissões (somente leitura)

```sql
select
 (select count(*) from public.storage_container_kind where is_active)                         as kinds,          -- 8
 (select c.confdeltype from pg_constraint c where c.conname='collection_creation_request_storage_container_id_fkey') as ccr_fk_del, -- 'n'
 (select is_nullable from information_schema.columns where table_schema='public'
   and table_name='collection_creation_request' and column_name='storage_container_id')       as ccr_null,       -- YES
 (select count(*) from public.collection_creation_request where storage_container_id is null)  as ccr_nulls,      -- 0
 (select md5(string_agg(id::text||':'||collection_id::text||':'||storage_container_id::text||':'||storage_container_created, ',' order by id))
    from public.collection_creation_request)                                                  as ccr_fp,         -- igual à Fase 0
 (select count(*) from public.storage_container where kind_code is not null)                   as typed,          -- 0
 to_regclass('public.ix_storage_container_inventory') is not null
   and to_regclass('public.ix_collection_default_storage') is not null                         as indexes_ok,     -- true
 (select bool_and(has_function_privilege('authenticated', p.oid, 'EXECUTE')
              and not has_function_privilege('anon', p.oid, 'EXECUTE')
              and p.prosecdef and p.proconfig = array['search_path=""'])
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname in ('create_my_storage_container','update_my_storage_container',
     'delete_my_storage_container','get_my_storage_locations','get_my_storage_summary'))      as fn_security_ok; -- true
```

Mais `get_advisors` (security): nenhum aviso novo referente aos objetos 5212–5219.

## Fase 3 — Harness 5847

Rodar `5847_validate_where_02_storage_locations.sql` inteiro, num único statement. **PASS = GATE 26/26** e linha `99.1` PASS. Qualquer `FAIL` ou `X.*` → STOP (o harness desfaz tudo pela sentinela; nada a limpar).

## Fase 4 — Integridade e resíduo zero (somente leitura)

Repetir a consulta da Fase 0: todas as contagens e os dois fingerprints iguais aos valores imediatamente anteriores à Fase 1; `ccr_fk_del = 'n'`, `ccr_null = YES`; `pc_located` inalterado. Isso prova que a aplicação não alterou coleções, pedidos de criação, exemplares nem alocações, e que o harness não deixou resíduo.

## Prova K1 — concorrência (separada, opcional, sem resíduo)

Não cabe no harness (exige duas conexões simultâneas; o SQL Editor não mantém transação aberta entre execuções). Procedimento com `psql` em dois terminais, **tudo em ROLLBACK**, sobre o local e um exemplar reais do mesmo acervo (só para observar travas — nada é gravado):

1. Sessão 1: `begin; select 1 from public.storage_container where id = '<local>' for update;` (a mesma trava que a 5218 toma).
2. Sessão 2: `begin; set lock_timeout = '3s'; update public.physical_card set storage_container_id = '<local>' where id = '<exemplar do mesmo acervo>';` → **esperado `55P03 lock_timeout`** (a checagem da FK precisa de `FOR KEY SHARE` no local). Repetir com `update public.collection set default_storage_container_id = '<local>' where id = '<coleção>'` trocando para um valor diferente → **55P03**.
3. `rollback;` nas duas sessões.
4. Inverso: sessão 2 faz o `update` primeiro (sem commit); sessão 1 `set lock_timeout='3s'; select … for update;` → **55P03**. `rollback` nas duas.

PASS: os 3 bloqueios ocorrem; nenhuma linha muda (conferir Fase 4).

## Critérios

**PASS do GATE de execução:** Fase 0 sem STOP; 8 migrations sem erro; Fase 2 com todos os valores esperados; 5847 GATE 26/26; Fase 4 idêntica; advisors sem achado novo. K1 recomendada, não bloqueante (a garantia é estrutural — ver evidências no relatório).

**STOP imediato:** qualquer erro de migration; qualquer valor divergente nas Fases 2/4; qualquer FAIL no 5847; `ccr_fp` diferente depois da 5214 (a 5214 nunca muda valores — só nulabilidade e FK).

## Recuperação (proporcional; nunca automática — diagnosticar antes)

| Situação | Ação mínima |
|---|---|
| Erro em 5212 | Nada aplicado (transação desfeita). Corrigir e reaplicar. |
| Erro em 5213 (ex.: pré-checagem de nome) | 5212 permanece (inofensiva, sem uso). Diagnosticar a linha; não forçar. |
| Erro em 5214 | 5212/5213 permanecem (aditivas). FK antiga continua (transação desfeita). Não aplicar 5218 sem 5214 (a própria 5218 recusa). |
| Erro em 5215–5219 | Objetos anteriores permanecem sem consumidor. Corrigir a função e reaplicar (`create or replace`). |
| 5847 FAIL funcional | Nenhum dado afetado (sentinela). Manter objetos, sem frontend; corrigir a função específica em nova migration. |
| Divergência na Fase 4 | STOP total; diagnosticar com o ledger e as linhas afetadas antes de qualquer reversão. |
| Reversão completa (último recurso, só com autorização) | Ordem inversa: `drop function` 5219→5216; `drop table storage_container_creation_request`; reverter 5214 só se `ccr_nulls = 0`; reverter 5213 (constraint, 2 índices, coluna); `drop table storage_container_kind`. |

## Depois do PASS (fora deste plano)

Promoção para `database/schema/` (5166 canônica recebe nota da 5214), `05d` (Revision History), `docs/log.md`, N24 da North Star. Frontend "Meus locais" em rodada própria.
