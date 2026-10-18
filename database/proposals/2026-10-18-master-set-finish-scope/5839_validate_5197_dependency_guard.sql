/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5839 - Casos positivos e negativos do guarda de
              dependências do 5197 (v1.2) — SOMENTE AMBIENTE DESCARTÁVEL
Versão......: 1.0
Status......: PROPOSTO — NÃO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-18 (MASTER-SET-FINISH-SCOPE-AUDIT-CORRECTION-02)

NÃO EXECUTAR NO LIVE. Faz DDL real (schema, tabelas, índices, policy,
gatilhos, view, publicação, regra, funções) num schema sintético zz5197,
dentro de uma única transação desfeita no fim pela sentinela ZZ5197.
Exige opt-in explícito na mesma sessão, antes do script:
    set mmkyu.disposable_db = 'yes';
Sem o opt-in, devolve uma única linha FAIL e não cria nada (além das
funções pg_temp do próprio script, que somem com a sessão).
Privilégios: CREATE no banco (schema e publicação), TEMP (funções
pg_temp), dono das tabelas criadas. Ambiente indicado: branch descartável
ou PostgreSQL 17.x local vazio (o LIVE roda 17.6).

O bloco <dep-guard> abaixo é cópia literal do 5197 v1.2 (mesmas variáveis
v_rel, v_rowtype, v_arraytype, v_toast, v_funcs, v_list). A igualdade é
conferida estaticamente (ver README, verificação estática).

Fixture: zz5197.probe imita a tabela antiga e acrescenta todo tipo de
objeto PRÓPRIO que deve cair com o DROP sem bloquear: PK, FK, UNIQUE,
CHECK, default, identity (sequência), coluna text (TOAST), índice comum,
índice de expressão parcial, policy que cita a própria coluna (dependência
'n', como no LIVE), gatilho UPDATE OF coluna (dependência 'n', como o 2268
no LIVE), constraint trigger diferido e estatística estendida. As "funções
removidas" do teste são zz5197.trg_fn() e zz5197.trg_fn2().

Casos (resultado esperado):
  P1  fixture completa → guarda NULL (nenhum falso positivo)
  P2  depois de P1: DROP TABLE (RESTRICT) e DROP das 2 funções concluem
  P3  o guarda (f) da v1.1 (exclusão por classe) DISPARA com o índice
      comum — reprodução do BLOCKER 1
  N1  view sobre probe                          → bloqueia; RESTRICT também recusa
  N2  materialized view sobre probe             → bloqueia; RESTRICT também recusa
  N3  FK de outra tabela para probe             → bloqueia; RESTRICT também recusa
  N4  policy de outra tabela citando probe      → bloqueia; RESTRICT também recusa
  N5  probe numa publicação                     → bloqueia; RESTRICT removeria em silêncio
  N6  tabela filha (INHERITS probe)             → bloqueia; RESTRICT também recusa
  N7  função com parâmetro do tipo probe        → bloqueia; RESTRICT também recusa
  N8  função SQL-padrão (BEGIN ATOMIC) lendo probe → bloqueia; RESTRICT também recusa
  N9  regra (CREATE RULE) em probe              → bloqueia; RESTRICT removeria a regra junto
  N10 gatilho em OUTRA tabela usando trg_fn     → bloqueia (dependência na função removida)
  N11 coluna do tipo probe em outra tabela      → bloqueia; RESTRICT também recusa
  N12 função plpgsql que cita probe só no texto → guarda (f) NULL (limite
      conhecido: corpo em string não registra pg_depend); a busca textual
      equivalente ao guarda (c) do 5197 encontra
  99  resíduo zero: schema zz5197 e publicação inexistentes depois da sentinela
GATE: todas PASS e n = 16.
================================================================
*/

create or replace function pg_temp.zz5197_guard(p_rel oid, p_funcs oid[])
returns text
language plpgsql
stable
as $fn$
declare
    v_rel       oid := p_rel;
    v_rowtype   oid;
    v_arraytype oid;
    v_toast     oid;
    v_funcs     oid[] := p_funcs;
    v_list      text;
begin
    select c.reltype, t.typarray, nullif(c.reltoastrelid, 0)
      into v_rowtype, v_arraytype, v_toast
    from pg_catalog.pg_class c
    join pg_catalog.pg_type t on t.oid = c.reltype
    where c.oid = v_rel;
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
    return v_list;
end;
$fn$;

-- guarda (f) da v1.1, reproduzido só para P3 (exclusão por classe)
create or replace function pg_temp.zz5197_guard_v11(p_rel oid)
returns text
language sql
stable
as $fn$
    select string_agg(pg_catalog.pg_describe_object(d.classid, d.objid, d.objsubid), ', ')
    from pg_catalog.pg_depend d
    where d.refclassid = 'pg_catalog.pg_class'::regclass
      and d.refobjid = p_rel
      and d.classid not in ('pg_catalog.pg_constraint'::regclass, 'pg_catalog.pg_trigger'::regclass,
                            'pg_catalog.pg_policy'::regclass, 'pg_catalog.pg_attrdef'::regclass,
                            'pg_catalog.pg_type'::regclass);
$fn$;

create or replace function pg_temp.zz5197_run()
returns table (seq integer, check_id text, status text, detail text)
language plpgsql
volatile
as $fn$
declare
  res jsonb := '[]'::jsonb; r jsonb; n integer := 0; passes integer := 0;
  v_rel oid; v_funcs oid[]; v_g text; v_drop text; v_txt text;
  -- id | DDL do caso | RESTRICT esperado ('2BP01' recusa; 'dropped' removeria; 'n/a' não se aplica)
  c_cases text[] := array[
    'N1',  'create view zz5197.v1 as select id from zz5197.probe', '2BP01',
    'N2',  'create materialized view zz5197.mv1 as select id from zz5197.probe', '2BP01',
    'N3',  'create table zz5197.child_fk (pid bigint references zz5197.probe(id))', '2BP01',
    'N4',  'create policy p_other on zz5197.other using (exists (select 1 from zz5197.probe p where p.id = x))', '2BP01',
    'N5',  'create publication zz5197_pub for table zz5197.probe', 'dropped',
    'N6',  'create table zz5197.heir () inherits (zz5197.probe)', '2BP01',
    'N7',  'create function zz5197.f_rowtype(p zz5197.probe) returns bigint language sql as $b$ select 1::bigint $b$', '2BP01',
    'N8',  'create function zz5197.f_atomic() returns bigint language sql begin atomic select count(*) from zz5197.probe; end', '2BP01',
    'N9',  'create rule r_probe as on insert to zz5197.probe do also notify zz5197', 'dropped',
    'N10', 'create trigger t_other2 before insert on zz5197.other2 for each row execute function zz5197.trg_fn()', 'n/a',
    'N11', 'create table zz5197.holder (h zz5197.probe)', '2BP01'
  ];
  i integer;
begin
  if current_setting('mmkyu.disposable_db', true) is distinct from 'yes' then
    seq := 1; check_id := 'OPT-IN'; status := 'FAIL';
    detail := 'ambiente não declarado descartável (set mmkyu.disposable_db = ''yes''); nada foi criado';
    return next;
    return;
  end if;

  begin
    -- fixture -------------------------------------------------------------
    execute 'create schema zz5197';
    execute 'create table zz5197.parent (id uuid primary key default gen_random_uuid())';
    execute 'create function zz5197.trg_fn() returns trigger language plpgsql as $b$ begin return new; end $b$';
    execute 'create function zz5197.trg_fn2() returns trigger language plpgsql as $b$ begin return null; end $b$';
    execute 'create table zz5197.probe (
               id bigint generated always as identity primary key,
               parent_id uuid not null references zz5197.parent(id) on delete cascade,
               note text check (length(note) < 4000),
               adopted_at timestamptz not null default now(),
               constraint uq_probe unique (parent_id, note))';
    execute 'create index ix_probe_parent on zz5197.probe (parent_id)';
    execute 'create index ix_probe_note_lower on zz5197.probe (lower(note)) where note is not null';
    execute 'alter table zz5197.probe enable row level security';
    execute 'create policy p_probe on zz5197.probe for select using (exists (select 1 from zz5197.parent pa where pa.id = probe.parent_id))';
    execute 'create trigger t_probe_upd before update of note on zz5197.probe for each row execute function zz5197.trg_fn()';
    execute 'create constraint trigger t_probe_del after delete on zz5197.probe deferrable initially deferred for each row execute function zz5197.trg_fn2()';
    execute 'create statistics zz5197.st_probe on parent_id, note from zz5197.probe';
    -- tabelas auxiliares dos casos N4 e N10 (não dependem de probe)
    execute 'create table zz5197.other (x bigint)';
    execute 'alter table zz5197.other enable row level security';
    execute 'create table zz5197.other2 (x int)';
    v_rel := 'zz5197.probe'::regclass::oid;
    v_funcs := array['zz5197.trg_fn()'::regprocedure::oid, 'zz5197.trg_fn2()'::regprocedure::oid];

    -- P1 / P2 / P3 ---------------------------------------------------------
    v_g := pg_temp.zz5197_guard(v_rel, v_funcs);
    res := res || jsonb_build_object('id','P1','ok', v_g is null,
      'detail', 'fixture com todos os objetos próprios: ' || coalesce(v_g, 'nenhum bloqueio'));
    v_drop := null;
    begin
      execute 'drop table zz5197.probe';
      execute 'drop function zz5197.trg_fn()';
      execute 'drop function zz5197.trg_fn2()';
      v_drop := 'dropped';
      raise exception 'ZZSUB';
    exception when others then
      if sqlerrm <> 'ZZSUB' then v_drop := sqlstate || ' ' || sqlerrm; end if;
    end;
    res := res || jsonb_build_object('id','P2','ok', v_drop = 'dropped',
      'detail', 'DROP TABLE (RESTRICT) + DROP das funções depois do guarda limpo: ' || coalesce(v_drop, '-'));
    v_g := pg_temp.zz5197_guard_v11(v_rel);
    res := res || jsonb_build_object('id','P3','ok', coalesce(v_g like '%ix_probe_parent%', false),
      'detail', 'guarda (f) v1.1 dispara indevidamente: ' || coalesce(v_g, 'não disparou'));

    -- N1..N11 --------------------------------------------------------------
    for i in 0 .. (array_length(c_cases, 1) / 3) - 1 loop
      v_g := null; v_drop := null;
      begin
        execute c_cases[i * 3 + 2];
        v_g := pg_temp.zz5197_guard(v_rel, v_funcs);
        if c_cases[i * 3 + 3] <> 'n/a' then
          begin
            execute 'drop table zz5197.probe';
            v_drop := 'dropped';
          exception when others then
            v_drop := sqlstate;
          end;
        end if;
        raise exception 'ZZSUB';
      exception when others then
        if sqlerrm <> 'ZZSUB' then v_g := null; v_drop := 'ERRO ' || sqlstate || ' ' || sqlerrm; end if;
      end;
      res := res || jsonb_build_object('id', c_cases[i * 3 + 1],
        'ok', v_g is not null and (c_cases[i * 3 + 3] = 'n/a' or v_drop = c_cases[i * 3 + 3]),
        'detail', format('guarda: %s | RESTRICT: %s (esperado %s)',
                         coalesce(v_g, 'NÃO bloqueou'), coalesce(v_drop, '-'), c_cases[i * 3 + 3]));
    end loop;

    -- N12 limite conhecido + busca textual equivalente ao guarda (c) --------
    v_g := null; v_txt := null;
    begin
      execute 'create function zz5197.f_text() returns bigint language plpgsql as $b$ begin return (select count(*) from zz5197.probe); end $b$';
      v_g := pg_temp.zz5197_guard(v_rel, v_funcs);
      select string_agg(p.proname, ', ') into v_txt
      from pg_catalog.pg_proc p
      where p.pronamespace = 'zz5197'::regnamespace and p.prosrc ~ '\mprobe\M';
      raise exception 'ZZSUB';
    exception when others then
      if sqlerrm <> 'ZZSUB' then v_txt := 'ERRO ' || sqlstate || ' ' || sqlerrm; end if;
    end;
    res := res || jsonb_build_object('id','N12','ok', v_g is null and v_txt = 'f_text',
      'detail', format('guarda (f): %s (esperado NULL — limite conhecido); busca textual: %s',
                       coalesce(v_g, 'NULL'), coalesce(v_txt, 'nada')));

    raise exception 'ZZ5197';
  exception when others then
    if sqlerrm <> 'ZZ5197' then
      res := res || jsonb_build_object('id','X.1','ok', false, 'detail','erro inesperado: ' || sqlstate || ' ' || sqlerrm);
    end if;
  end;

  res := res || jsonb_build_object('id','99','ok',
    not exists (select 1 from pg_catalog.pg_namespace where nspname = 'zz5197')
    and not exists (select 1 from pg_catalog.pg_publication where pubname = 'zz5197_pub'),
    'detail','resíduo zero (schema e publicação inexistentes)');

  for r in select * from jsonb_array_elements(res) loop
    n := n + 1;
    if coalesce((r->>'ok')::boolean, false) then passes := passes + 1; end if;
    seq := n; check_id := r->>'id';
    status := case when coalesce((r->>'ok')::boolean, false) then 'PASS' else 'FAIL' end;
    detail := r->>'detail';
    return next;
  end loop;
  seq := 999; check_id := 'GATE';
  status := case when passes = n and n = 16 then 'PASS' else 'FAIL' end;
  detail := format('%s/%s PASS (esperado 16)', passes, n);
  return next;
end;
$fn$;

select * from pg_temp.zz5197_run();
