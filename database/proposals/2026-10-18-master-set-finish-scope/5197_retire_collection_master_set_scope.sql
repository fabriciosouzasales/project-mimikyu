/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5197 - Aposentar collection_master_set_scope (02F) e suas
              funções exclusivas
Versão......: 1.2
Status......: PROPOSTA — NÃO EXECUTADA
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-18 (MASTER-SET-DOCUMENTATION-AND-CONTRACT-PROPOSAL-01)

Por quê: a tabela guarda card_variant_id, granularidade incompatível
com LDM-191/LDM-192. A decisão da rodada é não preservar estrutura
incompatível só por já existir. Aplicar por ÚLTIMO, depois que 5188,
5189, 5194 e 5195 já não referenciam a tabela.

Remove:
  - tabela public.collection_master_set_scope (com seus gatilhos:
    5073 eligibility, 5074 reject update, 5077 presence on delete e o
    trg_guard_card_variant_active instalado por 2268);
  - funções exclusivas: validate_master_set_scope_eligibility() (5073),
    reject_collection_master_set_scope_update() (5074),
    enforce_scope_master_set_presence_on_delete() (5077),
    apply_master_set_scope_diff(uuid, jsonb) (5079).
Mantém (reaproveitadas): check_master_set_scope_presence (5186),
enforce_collection_master_set_scope_presence + gatilho em collection
(5076), set_collection_completion_policy_to_standard_set (5081, não
referencia a tabela), CHECK de completion_policy (5078).

Fail-closed (v1.2, AUDIT-CORRECTION-02 — tabela vazia NÃO é evidência
suficiente; a classificação é por DONO do objeto, não por deptype). Aborta se:
  (0) a tabela não existir ou não for tabela comum (partição/herança);
  (a) a tabela tiver qualquer linha;
  (b) existir coleção MASTER_SET sem acabamento;
  (c) algum corpo de função, fora das quatro removidas aqui, citar a tabela
      ou as funções antigas (\m…\M) — plpgsql/sql em string não registram
      pg_depend, por isso esta busca complementa (f);
  (d) alguma view/materialized view citar a tabela;
  (e) a tabela estiver em alguma publicação;
  (f) existir em pg_depend, sobre a tabela, seu tipo-linha, seu tipo array
      ou as quatro funções removidas, um objeto que NÃO pertença à própria
      tabela. Pertencem (e caem com o DROP): constraints (conrelid), gatilhos
      (tgrelid, ou gatilho RI de FK da própria tabela), policies (polrelid),
      defaults (adrelid), tipo-linha/array, índices (indrelid), TOAST,
      sequências de identity/serial e estatísticas estendidas (stxrelid).
      Todo o resto bloqueia — inclusive classes não previstas (regras,
      pg_publication_rel, funções com corpo SQL-padrão, tabelas filhas,
      colunas do tipo-linha em outra tabela, FKs e policies de outras tabelas).
v1.1 → v1.2: o guarda (f) anterior excluía por classe (constraint, gatilho,
policy, default, tipo) e não excluía índices. Disparava indevidamente com um
índice comum e escondia FK/policy de OUTRA tabela (estas ainda seriam barradas
pelo DROP RESTRICT, mas sem diagnóstico).
Backstop: o DROP TABLE sem CASCADE (RESTRICT) continua recusando qualquer
dependência normal não removível.
Evidência (LIVE só leitura, casos positivos/negativos e limites):
5197-DEPENDENCY-EVIDENCE.md e 5839_validate_5197_dependency_guard.sql.

Efeito colateral documentado: a consulta "Como validar" da migration
2268 esperava 4 gatilhos trg_guard_card_variant_active; passam a 3
(pricing_product, physical_card, collection_layout_slot_expected_content).
Como validar: 5836 seção 0 (objetos ausentes) e caso 8.x (regressão).
================================================================
*/

begin;

do $$
declare
    c_old_names constant text :=
        '\m(collection_master_set_scope|collection_master_set_scope_positions|apply_master_set_scope_diff|'
        || 'replace_master_set_scope|validate_master_set_scope_eligibility|'
        || 'reject_collection_master_set_scope_update|enforce_scope_master_set_presence_on_delete)\M';
    v_rel       oid := to_regclass('public.collection_master_set_scope');
    v_rowtype   oid;
    v_arraytype oid;
    v_toast     oid;
    v_funcs     oid[];
    v_list      text;
begin
    -- (0) a tabela existe e é uma tabela comum, sem partição nem herança
    if v_rel is null then
        raise exception 'collection_master_set_scope not found — abort retirement';
    end if;
    select c.reltype, t.typarray, nullif(c.reltoastrelid, 0)
      into v_rowtype, v_arraytype, v_toast
    from pg_catalog.pg_class c
    join pg_catalog.pg_type t on t.oid = c.reltype
    where c.oid = v_rel and c.relkind = 'r' and not c.relispartition;
    if not found or exists (select 1 from pg_catalog.pg_inherits i where i.inhparent = v_rel or i.inhrelid = v_rel) then
        raise exception 'collection_master_set_scope is not a plain table (kind/partition/inheritance) — abort retirement';
    end if;
    v_funcs := array_remove(array[
        to_regprocedure('public.validate_master_set_scope_eligibility()')::oid,
        to_regprocedure('public.reject_collection_master_set_scope_update()')::oid,
        to_regprocedure('public.enforce_scope_master_set_presence_on_delete()')::oid,
        to_regprocedure('public.apply_master_set_scope_diff(uuid,jsonb)')::oid], null);

    -- (a)
    if exists (select 1 from public.collection_master_set_scope) then
        raise exception 'collection_master_set_scope is not empty — abort retirement';
    end if;
    -- (b)
    if exists (
        select 1 from public.collection c
        where c.completion_policy = 'MASTER_SET'
          and not exists (select 1 from public.collection_master_set_finish f where f.collection_id = c.id)
    ) then
        raise exception 'MASTER_SET collection without finishes found — abort retirement';
    end if;
    -- (c) corpos de função que citam objetos antigos (plpgsql/sql em string não
    --     registram pg_depend; complementa (f), não a substitui)
    select string_agg(n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')', ', ')
      into v_list
    from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
    where n.nspname not in ('pg_catalog', 'information_schema')
      and p.prosrc ~ c_old_names
      and not (p.oid = any (v_funcs));
    if v_list is not null then
        raise exception 'functions still reference retired 02F objects: % — abort retirement', v_list;
    end if;
    -- (d) views / materialized views (mensagem específica; também cobertas por (f))
    select string_agg(n.nspname || '.' || c.relname, ', ') into v_list
    from pg_catalog.pg_class c join pg_catalog.pg_namespace n on n.oid = c.relnamespace
    where c.relkind in ('v', 'm')
      and pg_catalog.pg_get_viewdef(c.oid) ~ '\mcollection_master_set_scope\M';
    if v_list is not null then
        raise exception 'views still reference collection_master_set_scope: % — abort retirement', v_list;
    end if;
    -- (e) publicações (DROP TABLE removeria a publicação em silêncio; também coberta por (f))
    select string_agg(pr.prpubid::text, ', ') into v_list
    from pg_catalog.pg_publication_rel pr
    where pr.prrelid = v_rel;
    if v_list is not null then
        raise exception 'collection_master_set_scope is published (publication oids: %) — abort retirement', v_list;
    end if;
    -- (f) dependências de catálogo: tudo o que não pertence à própria tabela bloqueia
    -- <dep-guard v1.2> (bloco idêntico em 5839; conferido por comparação textual)
    -- Classifica pelo DONO do objeto dependente, não pelo deptype: no LIVE a
    -- policy e o gatilho da própria tabela têm dependência 'n' (coluna citada
    -- na expressão / UPDATE OF), e um índice comum tem 'a' em pg_class.
    select string_agg(format('%s [%s/%s]',
                             pg_catalog.pg_describe_object(x.classid, x.objid, x.objsubid),
                             x.classid::regclass, x.deptype), '; ')
      into v_list
    from (
        -- dependências registradas sobre a tabela, seu tipo-linha e o tipo array
        select d.classid, d.objid, d.objsubid, d.deptype
        from pg_catalog.pg_depend d
        where (d.refclassid = 'pg_catalog.pg_class'::regclass and d.refobjid = v_rel)
           or (d.refclassid = 'pg_catalog.pg_type'::regclass and d.refobjid in (v_rowtype, v_arraytype))
        union
        -- dependências registradas sobre as funções que serão removidas
        select d.classid, d.objid, d.objsubid, d.deptype
        from pg_catalog.pg_depend d
        where d.refclassid = 'pg_catalog.pg_proc'::regclass and d.refobjid = any (v_funcs)
    ) x
    where not (
           -- constraint da própria tabela (PK, FK, CHECK, constraint trigger)
           (x.classid = 'pg_catalog.pg_constraint'::regclass and exists (
                select 1 from pg_catalog.pg_constraint o where o.oid = x.objid and o.conrelid = v_rel))
           -- gatilho da própria tabela, ou gatilho RI de uma FK da própria tabela
        or (x.classid = 'pg_catalog.pg_trigger'::regclass and exists (
                select 1 from pg_catalog.pg_trigger o
                where o.oid = x.objid
                  and (o.tgrelid = v_rel
                       or exists (select 1 from pg_catalog.pg_constraint k
                                  where k.oid = o.tgconstraint and k.conrelid = v_rel))))
           -- policy da própria tabela
        or (x.classid = 'pg_catalog.pg_policy'::regclass and exists (
                select 1 from pg_catalog.pg_policy o where o.oid = x.objid and o.polrelid = v_rel))
           -- default de coluna da própria tabela
        or (x.classid = 'pg_catalog.pg_attrdef'::regclass and exists (
                select 1 from pg_catalog.pg_attrdef o where o.oid = x.objid and o.adrelid = v_rel))
           -- tipo-linha e tipo array da própria tabela
        or (x.classid = 'pg_catalog.pg_type'::regclass and x.objid in (v_rowtype, v_arraytype))
           -- índice da própria tabela (comum, de expressão ou parcial)
        or (x.classid = 'pg_catalog.pg_class'::regclass and x.deptype in ('a', 'i') and exists (
                select 1 from pg_catalog.pg_index o where o.indexrelid = x.objid and o.indrelid = v_rel))
           -- tabela TOAST da própria tabela
        or (x.classid = 'pg_catalog.pg_class'::regclass and x.deptype = 'i' and x.objid = v_toast)
           -- sequência de coluna identity/serial da própria tabela (a dependência é o OWNED BY)
        or (x.classid = 'pg_catalog.pg_class'::regclass and x.deptype in ('a', 'i') and exists (
                select 1 from pg_catalog.pg_class o where o.oid = x.objid and o.relkind = 'S'))
           -- estatística estendida da própria tabela
        or (x.classid = 'pg_catalog.pg_statistic_ext'::regclass and exists (
                select 1 from pg_catalog.pg_statistic_ext o where o.oid = x.objid and o.stxrelid = v_rel))
    );
    -- </dep-guard>
    if v_list is not null then
        raise exception 'external dependencies on retired 02F objects: % — abort retirement', v_list;
    end if;
end;
$$;

drop table public.collection_master_set_scope;

drop function if exists public.validate_master_set_scope_eligibility();
drop function if exists public.reject_collection_master_set_scope_update();
drop function if exists public.enforce_scope_master_set_presence_on_delete();
drop function if exists public.apply_master_set_scope_diff(uuid, jsonb);

commit;
