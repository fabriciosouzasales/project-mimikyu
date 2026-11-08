/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5357-V1 - PRECHECK SOMENTE LEITURA (fase B) da Query 5357
Versão......: 0.2 (B2 — LIVE READONLY PROTOCOL AUDIT-01: blocos autocontidos,
              lock_timeout, objetos ausentes tratados sem erro, colunas e tipos
              completos da 5357, ACL padrão quando proacl é nulo)
              0.3 (B2 — V1 STRUCTURAL & INTEGRITY EXECUTION-01: V1.5c responde
              FALSE para função ausente; comentário no V1.7 sobre a unicidade
              de collection_allocation.physical_card_id). Demais blocos
              idênticos à v0.2.
Status......: PROPOSTO — NÃO EXECUTADO. Execução no ambiente existente exige
              autorização específica. Não cria, altera nem chama a 5357.
Data........: 2026-11-08

Forma de execução
  Cada bloco V1.x é AUTOCONTIDO: abre a própria transação READ ONLY, define
  os timeouts, roda UM único SELECT e encerra com ROLLBACK. Pode ser enviado
  bloco a bloco (cliente que só devolve o último resultado) ou pelo psql com
  ON_ERROR_STOP=1. Se um bloco falhar, a transação daquele bloco é abortada
  pelo servidor e encerrada pela conexão; nada fica aberto nem gravado.

Garantias da própria verificação
  - READ ONLY imposto pelo servidor (escrita → 25006). Nenhum INSERT, UPDATE,
    DELETE, MERGE, COPY, CREATE, ALTER, DROP, GRANT, REVOKE, SET ROLE, DO,
    chamada de RPC da aplicação ou função com efeito externo.
  - statement_timeout 5 s; lock_timeout 2 s (só AccessShareLock; não espera
    atrás de DDL); idle_in_transaction_session_timeout 30 s.
  - Saída: booleanos, contagens, nomes de objetos/papéis e listas de colunas
    ausentes. Nenhum id, nome, e-mail ou conteúdo de usuário.
  - Sem impersonação: nenhum claim, nenhuma troca de papel.

Critério: todo campo de bloco [GATE] deve sair TRUE (ou NULL onde indicado
como "ausentes"); qualquer divergência = STOP antes da aplicação. [INFO] só
registra.
================================================================
*/

-- V1.1 [GATE] ambiente e nome livre (catálogo; custo desprezível)
begin transaction isolation level repeatable read read only;
set local statement_timeout = '5s'; set local lock_timeout = '2s'; set local idle_in_transaction_session_timeout = '30s';
select current_setting('server_version_num')::int >= 160000 as pg16_ou_mais_generic_plan,
       not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                   where n.nspname = 'public' and p.proname = 'get_my_binder_value_groups') as nome_livre_sem_sobrecarga,
       current_setting('server_version') as versao_info;
rollback;

-- V1.2 [GATE] colunas e tipos usados pela 5357 (catálogo; custo desprezível)
-- "ausentes" e "tipo_divergente" devem sair NULL.
begin transaction isolation level repeatable read read only;
set local statement_timeout = '5s'; set local lock_timeout = '2s'; set local idle_in_transaction_session_timeout = '30s';
with esperado(t, c, tipo) as (values
  ('collection','id',null),('collection','owner_user_id',null),
  ('collection_layout','id',null),('collection_layout','collection_id',null),
  ('collection_layout_guest','collection_id',null),('collection_layout_guest','layout_id',null),
  ('collection_layout_page','id',null),('collection_layout_page','layout_id',null),
  ('collection_layout_slot','id',null),('collection_layout_slot','page_id',null),
  ('collection_layout_slot_assignment','slot_id',null),('collection_layout_slot_assignment','physical_card_id',null),
  ('physical_card','id','uuid'),('physical_card','card_variant_id','uuid'),('physical_card','language_id','uuid'),('physical_card','inventory_id',null),
  ('inventory','id',null),('inventory','owner_user_id','uuid'),
  ('card_variant','id','uuid'),('card_variant','card_id',null),('card_variant','variant_order',null),('card_variant','is_default','boolean'),
  ('card_variant','variant_type_id',null),('card_variant','printing_profile_id',null),('card_variant','edition_context_profile_id',null),
  ('card','id',null),('card','card_set_id',null),('card','collector_order',null),('card','name',null),
  ('card','collector_number',null),('card','collector_total','integer'),
  ('card_set','id',null),('card_set','release_date',null),('card_set','release_order',null),('card_set','code',null),('card_set','name',null),
  ('language','id',null),('language','language_order',null),('language','code',null),('language','name',null),
  ('card_variant_type','id',null),('card_variant_type','name',null),
  ('card_printing_profile','id',null),('card_printing_profile','name',null),
  ('card_edition_context_profile','id',null),('card_edition_context_profile','name',null),
  ('card_asset','card_id',null),('card_asset','asset_type_id',null),('card_asset','language_id',null),
  ('card_asset','is_primary',null),('card_asset','is_active',null),('card_asset','storage_path',null),
  ('card_asset_type','id',null),('card_asset_type','code',null))
select (select count(*) from esperado) = 54 as lista_completa,
       string_agg(e.t || '.' || e.c, ', ') filter (where ic.column_name is null) as ausentes,
       string_agg(e.t || '.' || e.c || '=' || ic.data_type, ', ')
         filter (where e.tipo is not null and ic.data_type is distinct from e.tipo) as tipo_divergente,
       bool_and(ic.is_nullable = 'NO') filter (where e.t = 'collection_layout_slot_assignment' and e.c = 'physical_card_id') as pos_5248
from esperado e
left join information_schema.columns ic
  on ic.table_schema = 'public' and ic.table_name = e.t and ic.column_name = e.c;
rollback;

-- V1.3 [GATE] constraints, índices e gatilhos de que a 5357 depende (catálogo)
begin transaction isolation level repeatable read read only;
set local statement_timeout = '5s'; set local lock_timeout = '2s'; set local idle_in_transaction_session_timeout = '30s';
select exists (select 1 from pg_constraint where conname = 'uq_collection_layout_slot_assignment_physical_card') as uq_exemplar_unico,
       exists (select 1 from pg_constraint where conname = 'uq_collection_layout_slot_assignment_slot')          as uq_bolso_unico,
       exists (select 1 from pg_constraint where conname = 'uq_collection_layout_page_number')                   as uq_pagina,
       exists (select 1 from pg_constraint where conname = 'uq_collection_layout_slot_position')                 as uq_posicao,
       to_regclass('public.ix_collection_layout_guest_layout') is not null                                       as ix_convidada,
       to_regclass('public.ix_card_asset_card_id') is not null                                                   as ix_imagem,
       (select count(*) from pg_trigger t join pg_class c on c.oid = t.tgrelid
         where not t.tgisinternal and t.tgenabled = 'D'
           and c.relname in ('collection_layout_slot_assignment','collection_layout_guest','collection_layout')) = 0 as nenhum_gatilho_desabilitado,
       (select string_agg(c.relname || '.' || t.tgname, ', ' order by 1) from pg_trigger t join pg_class c on c.oid = t.tgrelid
         where not t.tgisinternal
           and c.relname in ('collection_layout_slot_assignment','collection_layout_guest','collection_layout')) as gatilhos_info;
-- gatilhos_info deve conter o de integridade da ocupação (5117/5248), o de
-- convidada (5229) e o de local do fichário (5247); conferência manual na auditoria.
rollback;

-- V1.4 [GATE] leituras usadas como referência na fase C (catálogo)
begin transaction isolation level repeatable read read only;
set local statement_timeout = '5s'; set local lock_timeout = '2s'; set local idle_in_transaction_session_timeout = '30s';
select coalesce(pg_get_function_result(to_regprocedure('public.get_my_collection_binder(uuid)')) like '%filled_count integer%', false) as r5252_filled_count,
       coalesce(pg_get_function_result(to_regprocedure('public.get_my_inventory_items(text,text,text,uuid,boolean,text,integer,integer,uuid,boolean)'))
         like 'TABLE(card_variant_id uuid, language_code text, language_name text, card_name text, collector_number text, collector_total integer, card_set_code text, card_set_name text, is_default_variant boolean, variant_label text, copies_count integer%', false) as r5261_mesmos_nomes_tipos;
rollback;

-- V1.5a [GATE] papéis (catálogo)
begin transaction isolation level repeatable read read only;
set local statement_timeout = '5s'; set local lock_timeout = '2s'; set local idle_in_transaction_session_timeout = '30s';
select string_agg(r.rolname || ' super=' || r.rolsuper || ' bypassrls=' || r.rolbypassrls
                  || ' assumivel=' || pg_has_role(current_user, r.oid, 'member'), '; ' order by r.rolname) as papeis_info,
       bool_and(not r.rolsuper and not r.rolbypassrls) filter (where r.rolname in ('anon','authenticated')) as anon_auth_sem_bypass,
       bool_and(pg_has_role(current_user, r.oid, 'member')) filter (where r.rolname in ('anon','authenticated')) as sessao_assume_anon_auth,
       bool_or(r.rolbypassrls or r.rolsuper) filter (where r.rolname = 'postgres') as postgres_ignora_rls,
       count(*) filter (where r.rolname in ('anon','authenticated')) = 2 as papeis_presentes
from pg_roles r
where r.rolname in ('postgres','anon','authenticated','service_role');
rollback;

-- V1.5b [INFO + base do GATE C2] privilégios padrão de funções novas em public
begin transaction isolation level repeatable read read only;
set local statement_timeout = '5s'; set local lock_timeout = '2s'; set local idle_in_transaction_session_timeout = '30s';
select string_agg(pg_get_userbyid(d.defaclrole) || '→' || coalesce(nullif(a.grantee, 0)::regrole::text, 'PUBLIC') || ':' || a.privilege_type,
                  ', ' order by 1) as default_acl_funcoes_public
from pg_default_acl d
join pg_namespace n on n.oid = d.defaclnamespace and n.nspname = 'public'
cross join lateral aclexplode(d.defaclacl) a
where d.defaclobjtype = 'f';
rollback;

-- V1.5c [GATE] ACL real das leituras irmãs (padrão que a 5357 deve repetir)
-- proacl nulo = ACL padrão (inclui EXECUTE a PUBLIC) → tratado por acldefault.
begin transaction isolation level repeatable read read only;
set local statement_timeout = '5s'; set local lock_timeout = '2s'; set local idle_in_transaction_session_timeout = '30s';
select f.nome,
       f.oid is not null as existe,
       (select string_agg(coalesce(nullif(a.grantee, 0)::regrole::text, 'PUBLIC') || ':' || a.privilege_type, ', ' order by 1)
          from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
         where p.oid = f.oid) as acl_info,
       -- v0.3: função ausente (oid nulo) responde FALSE, nunca NULL.
       case when f.oid is null then false
            else coalesce(not has_function_privilege('anon', f.oid, 'execute'), false) end as anon_sem_execute
from (values ('get_my_collection_binder(uuid)', to_regprocedure('public.get_my_collection_binder(uuid)')),
             ('get_my_favorite_cards_by_card_set(uuid,integer,integer)', to_regprocedure('public.get_my_favorite_cards_by_card_set(uuid,integer,integer)'))
     ) f(nome, oid);
rollback;

-- V1.5d [GATE] auth.uid() lê os claims e é executável por authenticated
begin transaction isolation level repeatable read read only;
set local statement_timeout = '5s'; set local lock_timeout = '2s'; set local idle_in_transaction_session_timeout = '30s';
select coalesce(pg_get_functiondef(to_regprocedure('auth.uid()')) ~ 'request\.jwt\.claim', false) as auth_uid_le_claims,
       coalesce(has_function_privilege('authenticated', to_regprocedure('auth.uid()'), 'execute'), false) as authenticated_executa_uid;
rollback;

-- V1.6 [GATE] invariantes de dados (PERCORRE TODOS OS FICHÁRIOS; só contagens)
-- Custo: varre collection_layout_slot_assignment, os bolsos/páginas
-- correspondentes e junta exemplar/inventário/coleção por PK (tipicamente
-- Hash Join). Tamanho real conhecido só pelo V1.8 — rodar V1.8 ANTES e só
-- seguir se as tabelas do percurso tiverem até ~1 milhão de linhas.
begin transaction isolation level repeatable read read only;
set local statement_timeout = '5s'; set local lock_timeout = '2s'; set local idle_in_transaction_session_timeout = '30s';
with occ as (
  select l.id as layout_id, l.storage_container_id as l_sc, oc.owner_user_id as l_owner,
         a.id as a_id, pc.storage_container_id as pc_sc, i.owner_user_id as pc_owner
  from public.collection_layout l
  join public.collection oc                      on oc.id = l.collection_id
  join public.collection_layout_page p           on p.layout_id = l.id
  join public.collection_layout_slot s           on s.page_id = p.id
  left join public.collection_layout_slot_assignment a on a.slot_id = s.id
  left join public.physical_card pc              on pc.id = a.physical_card_id
  left join public.inventory i                   on i.id = pc.inventory_id
), per_layout as (
  select layout_id, count(a_id) as filled, count(a_id) filter (where pc_owner = l_owner) as pelo_dono
  from occ group by layout_id
)
select (select count(*) from occ where a_id is not null and pc_owner is distinct from l_owner) = 0 as a_ocupacao_mesmo_dono,
       (select count(*) from occ where a_id is not null and pc_sc is distinct from l_sc) = 0        as b_ocupacao_no_local_do_fichario,
       (select count(*) from public.collection_layout_guest g
          join public.collection gc       on gc.id = g.collection_id
          join public.collection_layout l on l.id = g.layout_id
          join public.collection oc       on oc.id = l.collection_id
         where gc.owner_user_id is distinct from oc.owner_user_id
            or exists (select 1 from public.collection_layout l2 where l2.collection_id = g.collection_id)) = 0 as c_convidada_mesmo_dono_e_nao_proprietaria,
       (select count(*) from per_layout where filled <> pelo_dono) = 0 as d_filled_igual_ao_percurso_5357;
rollback;

-- V1.7 [INFO] cobertura real dos cenários (PERCORRE TODOS OS FICHÁRIOS; só contagens)
-- Contagens agregadas de toda a base; nenhuma por usuário. Mesmo custo do V1.6.
-- O left join com collection_allocation não multiplica bolsos:
-- collection_allocation.physical_card_id é UNIQUE na definição versionada
-- (5040). A presença dessa unicidade no banco real é verificada à parte, por
-- consulta de catálogo a autorizar; o V1.3 v0.3 não a inclui.
begin transaction isolation level repeatable read read only;
set local statement_timeout = '5s'; set local lock_timeout = '2s'; set local idle_in_transaction_session_timeout = '30s';
with occ as (
  select p.layout_id, l.collection_id as owner_col, a.id as a_id, ca.collection_id as alloc_col, c.lifecycle_status as alloc_status
  from public.collection_layout l
  join public.collection_layout_page p           on p.layout_id = l.id
  join public.collection_layout_slot s           on s.page_id = p.id
  left join public.collection_layout_slot_assignment a on a.slot_id = s.id
  left join public.collection_allocation ca      on ca.physical_card_id = a.physical_card_id
  left join public.collection c                  on c.id = ca.collection_id
), per_layout as (
  select layout_id, count(*) as bolsos, count(a_id) as ocupados from occ group by layout_id
)
select (select count(*) from public.collection_layout)                                         as ficharios,
       (select count(*) from public.collection_layout_guest)                                   as convidadas,
       (select count(*) from occ where a_id is not null)                                       as bolsos_ocupados,
       (select count(*) from occ where a_id is not null and alloc_col is null)                 as posicionados_sem_colecao,
       (select count(*) from occ where a_id is not null and alloc_status is distinct from 'ACTIVE' and alloc_col is not null) as posicionados_de_colecao_nao_ativa,
       (select count(*) from occ o where o.a_id is not null and o.alloc_col is not null and o.alloc_col <> o.owner_col
          and not exists (select 1 from public.collection_layout_guest g where g.layout_id = o.layout_id and g.collection_id = o.alloc_col)) as posicionados_de_nao_participante,
       (select count(*) from public.collection_membership where status = 'ACTIVE')             as compartilhamentos_ativos,
       (select max(ocupados) from per_layout)                                                  as max_ocupados_por_fichario,
       (select max(bolsos) from per_layout)                                                    as max_bolsos_por_fichario;
rollback;

-- V1.8 [INFO, rodar PRIMEIRO] tamanho das tabelas (estatística do catálogo; custo desprezível)
begin transaction isolation level repeatable read read only;
set local statement_timeout = '5s'; set local lock_timeout = '2s'; set local idle_in_transaction_session_timeout = '30s';
select string_agg(c.relname || ' linhas≈' || c.reltuples::bigint || ' paginas=' || c.relpages, '; ' order by c.relname) as tamanhos
from pg_class c join pg_namespace n on n.oid = c.relnamespace and n.nspname = 'public'
where c.relkind = 'r'
  and c.relname in ('collection','collection_layout','collection_layout_guest','collection_layout_page','collection_layout_slot',
                    'collection_layout_slot_assignment','collection_allocation','physical_card','inventory',
                    'card_variant','card','card_set','language','card_asset');
rollback;
