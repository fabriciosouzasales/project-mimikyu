# Fichário Digital × Catálogo — roteiro de aplicação controlada no LIVE (estratégia H-A)

| Campo | Valor |
|---|---|
| Rodada | `BINDER-CATALOG-RECONCILIATION-LIVE-READINESS-H-A-01` (2026-10-24) |
| Estratégia | **H-A** (decisão de Fabrício): aplicar no LIVE com pré-check LIVE_00, pós-check LIVE_90 e ensaio somente leitura. **Harness 5859 NÃO EXECUTADO** — 79 checagens sem resultado. Sem ambientes isolados, locais ou alternativos. |
| Objetos | `5263_create_binder_catalog_reconciliation_structures` (v2.1) → `5264_create_binder_catalog_reconciliation_internals` (v1.4) → `5265_create_binder_catalog_reconciliation_reads` (v1.3) → `5266_create_binder_catalog_reconciliation_apply` (v1.2) |
| Projeto | Supabase `qjfutqujxrbzgrtkpgkg` (mimikyu-core), PostgreSQL 17.6 |
| Status | **EXECUTADO em 2026-10-25** (`LIVE-EXECUTION-AUTHORIZATION-01`; resultado no README §16). Errata pós-execução em §6. |

Todas as consultas deste roteiro são **somente leitura** e devem rodar dentro de `begin transaction read only; set local statement_timeout = '30s'; … rollback;`. Os valores "referência 2026-10-24" foram lidos no LIVE nesta rodada (somente leitura); no dia da aplicação o LIVE_00 é refeito e a referência é **substituída** pelo que for lido, antes da primeira migration.

---

## 1. LIVE_00 — pré-check

### Q00.1 Estruturas e funções novas ausentes

```sql
select to_regclass('public.collection_layout_catalog_incorporation') is null as inc_ausente,
       to_regclass('public.collection_layout_catalog_marker')        is null as marco_ausente,
       (select count(*) from pg_proc
         where pronamespace = 'public'::regnamespace and proname in (
           'binder_catalog_marker_on_layout_insert','binder_catalog_marker_on_owner_change',
           'binder_catalog_marker_on_guest_insert','binder_catalog_marker_cleanup',
           'binder_catalog_context','binder_catalog_assert_eligible','binder_catalog_positions',
           'binder_catalog_novelties','binder_catalog_plan','get_my_binder_catalog_novelties',
           'preview_my_binder_catalog_reconciliation','apply_my_binder_catalog_reconciliation')) as funcoes_novas,
       (select count(*) from pg_trigger where tgname like 'trg\_cl\_catalog\_marker\_%') as gatilhos_novos,
       (select count(*) from supabase_migrations.schema_migrations where name ~ '^526[3-6]_') as no_ledger;
-- esperado: true | true | 0 | 0 | 0      (referência 2026-10-24: idem)
```

### Q00.2 Dependências canônicas presentes

```sql
select to_regprocedure('public.master_set_positions(uuid, uuid[])')            is not null as d5187,
       to_regprocedure('public.binder_layout_lock_for_collection(uuid)')        is not null as d5240,
       to_regprocedure('public.binder_gap_move_pocket(uuid, uuid)')             is not null as d5243,
       to_regprocedure('public.binder_slot_image_resolve_layout(uuid)')         is not null as d5234,
       to_regprocedure('public.add_layout_page(uuid)')                          is not null as d5125,
       to_regprocedure('public.transfer_my_binder_ownership(uuid, uuid)')       is not null as d5254,
       to_regclass('public.collection_layout_guest')                            is not null as t5229,
       to_regclass('public.collection_layout_slot_species_reference')           is not null as t5257,
       current_setting('server_version_num')::int >= 130000                     as tem_xid8,
       current_setting('check_function_bodies')                                 as cfb;
-- esperado: todos true; cfb = on      (referência 2026-10-24: idem, 170006)
```

### Q00.3 Estado atual (linha de base a preservar)

```sql
select (select count(*) from public.collection_layout)                         as fichários,
       (select count(*) from public.collection_layout_guest)                   as convidadas,
       (select count(*) from public.collection_layout_page)                    as páginas,
       (select count(*) from public.collection_layout_slot)                    as bolsos,
       (select count(*) from public.collection_layout_slot_assignment)         as posições,
       (select count(*) from public.collection_layout_slot_expected_content)   as reservas,
       (select count(*) from public.collection_layout_region)                  as mesclagens,
       (select count(*) from public.collection_layout_slot_species_reference)  as refs_espécie,
       (select max(version) from supabase_migrations.schema_migrations)        as último_ledger;
-- referência 2026-10-24: 3 | 1 | 146 | 1776 | 349 | 350 | 2 | 1025 | 20261024185943
```

Fichários na referência: `0d550088…` Celebração de 30 Anos (STANDARD_SET, 1 convidada), `bd2c0834…` Minha Pokédex (REFERENCE_POSITION), `3425193a…` **Escuridão Absoluta** (MASTER_SET, coleção `223eb120-39d1-423a-9278-8092f4181d18`, Set ME5, criado 2026-10-24 19:32:54.619369+00; 40 páginas, 360 bolsos, 165 livres, 194 posições do objetivo, 192 reservadas).

### Q00.4 Evidências históricas de transferência de propriedade

Ausência de indício **não** prova ausência de transferência; as duas consultas abaixo são complementares e nenhuma é prova absoluta.

```sql
-- a) indício direto (mesmo critério do precheck da 5263): convidada com reserva própria anterior à entrada
select count(*) as indicio_m6
from public.collection_layout_guest g
join public.collection_layout_page p on p.layout_id = g.layout_id
join public.collection_layout_slot s on s.page_id = p.id
join public.collection_layout_slot_expected_content e on e.slot_id = s.id
where e.collection_id = g.collection_id and e.created_at < g.created_at;
-- esperado: 0 (referência: 0). Diferente de 0 → a própria 5263 falha (fail-closed).

-- b) fichários alterados depois da instalação da 5254 (5106 grava updated_at em todo UPDATE;
--    antes da 5254 a 5136 proibia trocar collection_id)
select l.id, l.collection_id, l.created_at, l.updated_at
from public.collection_layout l
where l.updated_at <> l.created_at
  and l.updated_at >= (select to_timestamp(m.version, 'YYYYMMDDHH24MISS')::timestamp at time zone 'UTC'
                       from supabase_migrations.schema_migrations m where m.name like '5254%');
-- esperado: nenhuma linha (referência: nenhuma — L1 atualizado 00:34 antes do ledger 12:18:20; L2/L3 nunca).
-- Linha presente = alguma alteração depois da 5254 (transferência, nome, logomarca ou local físico):
-- decisão manual de Fabrício antes de aplicar.
```

Limite declarado: se o gatilho 5106 tiver sido desativado em algum momento (por exemplo `session_replication_role = replica`), b) não detecta; uma transferência seguida de desassociação da antiga dona não deixa o indício a).

### Q00.5 Permissões, gatilhos e contratos existentes

```sql
-- gatilhos atuais nas tabelas que recebem os gatilhos novos
select t.tgrelid::regclass::text, t.tgname, t.tgenabled
from pg_trigger t
where t.tgrelid in ('public.collection_layout'::regclass, 'public.collection_layout_guest'::regclass)
  and not t.tgisinternal order by 1, 2;
-- referência: 7 — collection_layout: trg_collection_layout_collection_id_immutable, _delete_without_guests,
--   _grid_immutability, _owner_not_guest, _storage_container, _updated_at; collection_layout_guest:
--   trg_collection_layout_guest_integrity (todos 'O')

-- definições das funções homologadas que os gatilhos novos tocam ou de que a 5264/5266 dependem
select p.oid::regprocedure::text as assinatura, md5(pg_get_functiondef(p.oid)) as md5_def
from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in
 ('create_my_collection_binder','attach_my_collection_to_binder','detach_my_collection_from_binder',
  'transfer_my_binder_ownership','dismantle_my_collection_binder','set_slot_expected_content',
  'clear_slot_expected_content','binder_gap_move_pocket','insert_my_binder_gap','master_set_positions',
  'binder_layout_lock_for_collection','binder_slot_image_resolve_layout','add_layout_page',
  'enforce_collection_layout_structural_fk_immutability','delete_collection')
order by 1;
```

Referência 2026-10-24 (md5 de `pg_get_functiondef`):

| Função | md5 |
|---|---|
| add_layout_page(uuid) | d92526697fbb08c6439ad582adb5c333 |
| attach_my_collection_to_binder(uuid,uuid) | e7e9cd1e48e9834c146209a7cf22779d |
| binder_gap_move_pocket(uuid,uuid) | 9e1d9957a9bf872437904174676ba8ca |
| binder_layout_lock_for_collection(uuid) | ff7f1cf11ad6c20a2749a343525d6789 |
| binder_slot_image_resolve_layout(uuid) | b684694fca0a3c4caf153e8cbd11593f |
| clear_slot_expected_content(uuid[]) | b14713c6db62eeb98b5610c1a9014550 |
| create_my_collection_binder(uuid,integer,integer,text,text) | 07e69f954925ccb83650c71a5d8e2c10 |
| delete_collection(uuid) | 933c2a5a256da4685221bc52bfa9532b |
| detach_my_collection_from_binder(uuid,text,boolean) | e470ebd9aef16df680c172923dd1daf3 |
| dismantle_my_collection_binder(uuid,text) | 56483cdd3b9ba96d2e8b9394592dfee2 |
| enforce_collection_layout_structural_fk_immutability() | 03f0ab22e3edd1795b766e97d28cfd46 |
| insert_my_binder_gap(uuid,uuid,text,boolean,boolean) | 4849f006da0fd8af030d1067c9106aae |
| master_set_positions(uuid,uuid[]) | 72cadf587fb85276589e79138065c7f8 |
| set_slot_expected_content(uuid,uuid,uuid,uuid,uuid) | 2c6ae339b16d124827002bd2caf359f9 |
| transfer_my_binder_ownership(uuid,uuid) | 6dd6e3a306cc7b2c939e4a7e92f0d85a |

### Q00.6 Ensaio da detecção (somente leitura, sem objetos novos)

Reproduz a regra de `binder_catalog_novelties` para a Escuridão Absoluta com o marco que o preenchimento usará (`collection_layout.created_at`):

```sql
with pos as (
  select m.card_id::text || ':' || coalesce(m.variant_type_id::text, '*') k,
         greatest(c.created_at, (select min(cv.created_at) from public.card_variant cv
                                  where cv.card_id = m.card_id and cv.is_active
                                    and (m.variant_type_id is null or cv.variant_type_id = m.variant_type_id))) born
  from public.master_set_positions('3dab6b1f-27a9-4420-b80b-56d6bbf03ab6',
         (select array_agg(f.variant_type_id) from public.collection_master_set_finish f
           where f.collection_id = '223eb120-39d1-423a-9278-8092f4181d18')) m
  join public.card c on c.id = m.card_id),
res as (
  select distinct e.card_id::text || ':' || coalesce(e.expected_variant_type_id::text, ecv.variant_type_id::text, '*') k
  from public.collection_layout_page pg
  join public.collection_layout_slot s on s.page_id = pg.id
  join public.collection_layout_slot_expected_content e on e.slot_id = s.id
  left join public.card_variant ecv on ecv.id = e.card_variant_id
  where pg.layout_id = '3425193a-5c44-4930-8574-22909ffdca21'
    and coalesce(e.collection_id, '223eb120-39d1-423a-9278-8092f4181d18') = '223eb120-39d1-423a-9278-8092f4181d18')
select (select count(*) from pos) posições,
       (select json_agg(k) from pos
         where born > (select created_at from public.collection_layout where id = '3425193a-5c44-4930-8574-22909ffdca21')
           and k not in (select k from res)) novidades;
-- referência 2026-10-24: 194 | ["433d73eb-7f25-4488-9b51-7b6719bc46cc:b4c6000e-61e4-4fc3-8d58-cae137a7181a"]
--   (Chi-Yu 059 REVERSE_HOLO, variante criada 2026-10-24 20:02:22.822219+00)
```

### Critérios de STOP do LIVE_00

| Condição | Ação |
|---|---|
| Q00.1 diferente do esperado (objeto novo já existe, ledger com 526x) | **STOP** — estado inesperado |
| Q00.2 com qualquer false ou `cfb` diferente de `on` | **STOP** |
| Q00.4 a) > 0 | **STOP** (a 5263 recusaria) — decisão de Fabrício |
| Q00.4 b) com linhas | **STOP** até decisão manual registrada |
| Q00.5: gatilhos diferentes dos 7 de referência ou md5 diferente | **STOP** — o LIVE mudou desde esta rodada; reavaliar compatibilidade |
| Q00.6 com novidades diferentes da Chi-Yu 059 REVERSE_HOLO | **STOP** para atualizar as expectativas do LIVE_90 (não é defeito, mas o esperado muda) |
| Q00.3 | não é critério de STOP; é a linha de base que o LIVE_90 compara |

---

## 2. Aplicação planejada

Uma `apply_migration` por arquivo, na ordem abaixo, com o corpo do arquivo **sem** as linhas `begin;`/`commit;` externas (convenção do projeto; o texto gravado no ledger fica igual ao corpo). Entre uma e outra, o pós-check mínimo indicado. Qualquer erro → **STOP**, não aplicar a seguinte, reportar. A versão do ledger é atribuída pelo Supabase no momento (timestamp UTC); o identificador esperado é o **nome**.

| # | Nome esperado no ledger | Pré-condições | Efeitos sobre objetos existentes | Sucesso | Interrupção |
|---|---|---|---|---|---|
| 1 | `5263_create_binder_catalog_reconciliation_structures` | LIVE_00 limpo | **Cria** 2 tabelas, 2 índices, 4 funções de gatilho e **5 gatilhos AFTER em `collection_layout` e `collection_layout_guest`** (ativos imediatamente: criação de fichário, associação, desassociação e transferência passam a escrever marcos). Trava as duas tabelas (SHARE ROW EXCLUSIVE, convidadas → fichários) durante a migration. Preenche 4 marcos (3 donas + 1 convidada). Nenhuma linha existente alterada. | `apply_migration` sem erro; Q90.1, Q90.3 e Q90.4 conformes | erro de precheck (indício de transferência), `lock_timeout` 5s, qualquer erro |
| 2 | `5264_create_binder_catalog_reconciliation_internals` | 5263 no ledger | Cria 5 funções internas (nenhum EXECUTE para clientes). Nenhum objeto existente alterado. | sem erro; Q90.2 (linhas internas) conforme | qualquer erro (precheck "aplique 5263 antes" etc.) |
| 3 | `5265_create_binder_catalog_reconciliation_reads` | 5264 no ledger | Cria 2 RPCs de leitura (EXECUTE só authenticated). | sem erro; Q90.2 (2 RPCs) conforme | qualquer erro |
| 4 | `5266_create_binder_catalog_reconciliation_apply` | 5265 no ledger | Cria a RPC de aplicação (EXECUTE só authenticated). Primeira e única função que escreve reservas e incorporações — não é chamada nesta rodada nem no LIVE_90. | sem erro; LIVE_90 completo conforme | qualquer erro |

As quatro devem ser aplicadas na mesma janela de trabalho (a 5263 ativa gatilhos em tabelas homologadas antes de as funções de leitura existirem).

**Reversão** (preparada, não executada; só por decisão de Fabrício e enquanto nenhuma incorporação real tiver sido gravada):
`drop function public.apply_my_binder_catalog_reconciliation(uuid, text[], text, boolean, boolean);` → `drop function` das 2 RPCs da 5265 → das 5 internas da 5264 → `drop trigger` dos 5 gatilhos → `drop function` das 4 funções de gatilho → `drop table public.collection_layout_catalog_marker; drop table public.collection_layout_catalog_incorporation;`. Depois de existirem incorporações, a reversão apaga o histórico W5 e exige decisão própria.

---

## 3. LIVE_90 — pós-check (somente leitura)

### Q90.1 Tabelas, chaves, índices, RLS, grants, owner

```sql
select c.relname, pg_get_userbyid(c.relowner) owner, c.relrowsecurity rls, c.relforcerowsecurity force_rls,
       (select count(*) from pg_policy p where p.polrelid = c.oid) políticas,
       has_table_privilege('anon',          c.oid, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER') anon,
       has_table_privilege('authenticated', c.oid, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER') auth,
       has_table_privilege('service_role',  c.oid, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER') service,
       exists (select 1 from aclexplode(c.relacl) x where x.grantee = 0) public_acl,
       (select string_agg(k.conname::text || ':' || k.contype::text || case when k.contype = 'f' then ':' || k.confdeltype::text else '' end,
                          ',' order by k.conname) from pg_constraint k where k.conrelid = c.oid) restrições,
       (select string_agg(i.indexrelid::regclass::text, ',' order by i.indexrelid::regclass::text)
          from pg_index i where i.indrelid = c.oid) índices
from pg_class c
where c.oid in ('public.collection_layout_catalog_incorporation'::regclass, 'public.collection_layout_catalog_marker'::regclass);
-- esperado (2 linhas): owner postgres | rls true | force false | 0 | false | false | false | false
--   incorporation: chk_cl_ci_item_key:c,fk_cl_ci_collection:f:c,fk_cl_ci_layout:f:c,pk_cl_catalog_incorporation:p
--                  índices cl_ci_collection_idx, pk_cl_catalog_incorporation
--   marker:        chk_cl_cm_role:c,chk_cl_cm_source:c,fk_cl_cm_collection:f:c,fk_cl_cm_layout:f:c,pk_cl_catalog_marker:p
--                  índices cl_cm_collection_idx, pk_cl_catalog_marker
select atttypid::regtype, attnotnull from pg_attribute
where attrelid = 'public.collection_layout_catalog_marker'::regclass and attname = 'ended_xact';
-- esperado: xid8 | false
```

### Q90.2 Funções: owner, SECURITY DEFINER, search_path, volatilidade, EXECUTE

```sql
select p.proname, pg_get_userbyid(p.proowner) owner, p.prosecdef, p.proconfig, p.provolatile,
       has_function_privilege('anon',          p.oid, 'EXECUTE') anon,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') auth,
       has_function_privilege('service_role',  p.oid, 'EXECUTE') service,
       exists (select 1 from aclexplode(p.proacl) x where x.grantee = 0) public_acl
from pg_proc p
where p.pronamespace = 'public'::regnamespace and p.proname in (
  'binder_catalog_marker_on_layout_insert','binder_catalog_marker_on_owner_change',
  'binder_catalog_marker_on_guest_insert','binder_catalog_marker_cleanup',
  'binder_catalog_context','binder_catalog_assert_eligible','binder_catalog_positions',
  'binder_catalog_novelties','binder_catalog_plan','get_my_binder_catalog_novelties',
  'preview_my_binder_catalog_reconciliation','apply_my_binder_catalog_reconciliation')
order by 1;
-- esperado: 12 linhas; owner postgres; prosecdef true; proconfig contém search_path=""; public_acl false;
--   4 de gatilho + 5 internas: anon/auth/service false; provolatile 'v' (gatilho) / 's' (internas)
--   get_my_… e preview_…: auth true, anon false, 's'
--   apply_…: auth true, anon false, 'v', proconfig contém lock_timeout=5s
--   service nas 3 RPCs: registrar o valor (padrão do projeto revoga só de PUBLIC/anon)
```

### Q90.3 Gatilhos

```sql
select t.tgrelid::regclass::text tabela, t.tgname, t.tgenabled, t.tgdeferrable, t.tgconstraint <> 0 restrição,
       pg_get_triggerdef(t.oid) definição
from pg_trigger t
where t.tgrelid in ('public.collection_layout'::regclass, 'public.collection_layout_guest'::regclass)
  and not t.tgisinternal order by 1, 2;
-- esperado: 12 linhas = 7 de referência (Q00.5, inalterados) + 5 novos:
--   collection_layout: trg_cl_catalog_marker_layout_insert (AFTER INSERT), _owner_change e _owner_cleanup
--     (AFTER UPDATE OF collection_id, WHEN old ≠ new); collection_layout_guest: _guest_insert (AFTER INSERT),
--     _guest_cleanup (AFTER DELETE); todos tgenabled 'O', tgdeferrable false, restrição false
```

### Q90.4 Participantes × marcos ativos

```sql
with p as (select l.id layout_id, l.collection_id from public.collection_layout l
           union all select g.layout_id, g.collection_id from public.collection_layout_guest g),
     m as (select m.layout_id, m.collection_id from public.collection_layout_catalog_marker m where m.ended_xact is null)
select (select count(*) from p where not exists (select 1 from m where m.layout_id = p.layout_id and m.collection_id = p.collection_id)) participante_sem_marco,
       (select count(*) from m where not exists (select 1 from p where p.layout_id = m.layout_id and p.collection_id = m.collection_id)) marco_sem_participante,
       (select count(*) from public.collection_layout_catalog_marker where ended_xact is not null) encerrados,
       (select string_agg(marker_source || '/' || role, ',' order by marker_source, role) from public.collection_layout_catalog_marker) origens,
       (select marker_at from public.collection_layout_catalog_marker
         where layout_id = '3425193a-5c44-4930-8574-22909ffdca21' and collection_id = '223eb120-39d1-423a-9278-8092f4181d18') marco_escuridão;
-- esperado: 0 | 0 | 0 | BACKFILL_GUEST/GUEST,BACKFILL_OWNER/OWNER,BACKFILL_OWNER/OWNER,BACKFILL_OWNER/OWNER
--           | 2026-10-24 19:32:54.619369+00
select count(*) from public.collection_layout_catalog_incorporation;   -- esperado: 0
```

### Q90.5 Preservação

Repetir **Q00.3** (contagens idênticas à linha de base do dia, exceto `último_ledger`) e **Q00.5** (7 gatilhos antigos inalterados; os 15 md5 idênticos aos do dia).

### Q90.6 Ledger

```sql
select version, name from supabase_migrations.schema_migrations where name ~ '^526[3-6]_' order by version;
-- esperado: 4 linhas, na ordem 5263 → 5264 → 5265 → 5266, nomes exatos da §2, versões > último_ledger da linha de base
```

### Q90.7 Detecção da Chi-Yu 059 Holográfica Reversa

```sql
select eligible, reason, marker_at from public.binder_catalog_context('223eb120-39d1-423a-9278-8092f4181d18');
-- esperado: true | null | 2026-10-24 19:32:54.619369+00
select item_key, born_at, is_reserved, is_novelty, is_incorporated
from public.binder_catalog_novelties('223eb120-39d1-423a-9278-8092f4181d18');
-- esperado: 1 linha — 433d73eb-7f25-4488-9b51-7b6719bc46cc:b4c6000e-61e4-4fc3-8d58-cae137a7181a
--           | 2026-10-24 20:02:22.822219+00 | false | true | false
```

### Q90.8 Prévia de incorporação sem escrita

Dentro da transação somente leitura (qualquer tentativa de escrita falharia):

```sql
select row_kind, step_no, item_key, kind, target_page, target_row, target_column,
       anchor_page, anchor_row, anchor_column, pockets_moved, rows_moved, crosses_page, adds_page,
       outcome, total_items, total_rows_moved, requires_cross_page, requires_add_page, pages_added,
       capacity_before, capacity_after, free_pockets_after, plan_token is not null as tem_token
from public.binder_catalog_plan('223eb120-39d1-423a-9278-8092f4181d18', null)
order by (row_kind = 'HEADER') desc, step_no;
-- esperado (derivado do estado de referência: 13·1·2 tem a Chi-Yu Holo da coleção sem reserva; 13·1·3 livre):
--   HEADER: READY | 1 item | 0 linhas | sem outra página | sem página nova | 0 | 360 → 360 | 164 livres | token
--   ITEM 1: Chi-Yu 059 REVERSE_HOLO | IN_PLACE | destino 13·1·3 | âncora 13·1·2 | 0 bolsos | 0 linhas
```

A RPC pública `preview_my_binder_catalog_reconciliation` exige sessão (`auth.uid()`), portanto não é exercitável por SQL administrativo; fica para a homologação pela interface.

### Q90.9 Regressões observáveis

- Security Advisor e Performance Advisor: achados novos esperados — "RLS habilitada sem política" (INFO) nas 2 tabelas novas e `authenticated_security_definer_function_executable` (WARN) nas 3 RPCs `SECURITY DEFINER` com `EXECUTE` para `authenticated` (desenho aprovado; mesmo padrão das demais RPCs do projeto); `unused_index` (INFO) nos 2 índices novos. Qualquer outro achado novo é desvio. *(Texto corrigido pela errata §6.)*
- Q90.5 conforme (nenhuma contagem nem definição homologada mudou).
- Nenhuma escrita ocorreu nesta rodada além das 4 migrations: `select count(*) from public.collection_layout_catalog_incorporation` = 0 e os 4 marcos de Q90.4.

### Critérios de STOP do LIVE_90

Qualquer desvio em Q90.1–Q90.8 → **STOP**: registrar o valor obtido, não iniciar homologação, decisão de Fabrício entre corrigir à frente ou reverter (§2). Q90.8 com resultado diferente do derivado → STOP para análise (o estado do fichário pode ter mudado entre o LIVE_00 e o LIVE_90).

---

## 4. Evidências necessárias para homologação

1. Saídas literais de LIVE_00 (Q00.1–Q00.6) no dia, antes da primeira migration.
2. Retorno de cada `apply_migration` e as 4 linhas do ledger (Q90.6).
3. Saídas literais de LIVE_90 (Q90.1–Q90.9).
4. Registro explícito: "Harness 5859 não executado (H-A)".
5. Homologação funcional posterior, pela interface, quando o frontend existir (rodada própria): aviso da Chi-Yu, prévia, aplicação, repetição (ALREADY_APPLIED), liberação e não reaparecimento — com prints e as consultas Q90.4/Q90.7 antes e depois.
6. Promoção para `database/schema/` só após 1–3 conformes, com o mesmo procedimento das rodadas anteriores (proposta = canônica = ledger).

---

## 5. Limitações aceitas na estratégia H-A

Nenhum destes itens é PASS; ficam registrados como **não comprovados**:

| Limitação | Situação |
|---|---|
| Harness 5859 | **não executado** — 79 checagens sem resultado (estrutura, detecção, prévia, aplicação, idempotência, W1–W6, W5, A7, isolamento, resíduo) |
| Concorrência real | **não testada** (duas sessões; trava 5240; deadlock com a trava da migration) |
| Desempenho | **não medido** (novidades, plano e aplicação em fichários grandes; custo dos gatilhos) |
| Comportamento transacional complexo | **não homologado por execução**: transferência com encerramento/reativação de marcos (`ended_xact`, `pg_current_xact_id()`), desassociação/reassociação, falha no meio da aplicação com rollback, ON CONFLICT + contagem |
| Gatilhos novos em tabelas homologadas | risco de uma falha neles abortar criação de fichário, associação, desassociação ou transferência; nenhum caminho conhecido, mas não exercitado |
| Sintaxe | só validada pelo próprio `apply_migration` (corpos PL/pgSQL só falham quando executados) |
| Detecção temporal | não cobre variante/carta reativada, mesclagem editorial, acabamento acrescentado depois ao objetivo, corrida no marco; reserva de novidade feita à mão fora da operação não entra no registro W5 |
| Histórico de transferências | ausência de indício não é prova (Q00.4) |
| Reativação indevida de marco | composição manual de desassociação + transferência numa só transação; restauração lógica em outro cluster (README §13) |

---

## 6. Errata pós-execução (`BINDER-CATALOG-RECONCILIATION-FINAL-CLOSEOUT-01`, 2026-10-25)

A execução de 2026-10-25 (README §16) seguiu este roteiro na forma original e revelou duas falhas **do roteiro**, não do SQL aplicado nem dos dados. O texto acima já está corrigido; a forma original fica registrada aqui.

| # | Onde | Forma original | Correção | Efeito na execução de 2026-10-25 |
|---|---|---|---|---|
| E1 | Q90.1, coluna `restrições` | `k.conname \|\| ':' \|\| k.contype \|\| case when k.contype = 'f' then ':' \|\| k.confdeltype else '' end` | casts `k.conname::text`, `k.contype::text`, `k.confdeltype::text` | a consulta original falhou com `42725 operator is not unique: text \|\| "char"` (as colunas são do tipo `"char"`); foi reexecutada com os casts, mesma semântica, resultado conforme |
| E2 | Q90.9, expectativa do Security Advisor | só "RLS habilitada sem política" (INFO) nas 2 tabelas | acrescentados o WARN `authenticated_security_definer_function_executable` nas 3 RPCs e o INFO `unused_index` dos 2 índices novos | o Advisor apontou os achados acrescentados; todos esperados pelo desenho (EXECUTE só para `authenticated`, autorização interna por `auth.uid()`), sem permissão a mais |

Nenhum outro item do LIVE_00/LIVE_90 foi alterado.

