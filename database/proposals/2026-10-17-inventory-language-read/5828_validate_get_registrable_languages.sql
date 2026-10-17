/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5828 - Validate get_registrable_languages (5164)
Versão......: 1.0
Status......: PROPOSTO — NÃO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-17 (INVENTORY-LANGUAGE-READ-01)

Somente leitura. Mesmo protocolo de 5827: o teste inteiro roda num
único statement (SELECT da função pg_temp); trocas de papel e claims
são SET LOCAL dentro dela e os resultados ficam em variáveis (nada é
lido de tabela temporária depois de trocar de papel — classe de
defeito já registrada em 5808). Único objeto criado: a função pg_temp,
local da sessão.

Execução (1 chamada, por Fabrício), com 5164 aplicada:
  SELECT * FROM pg_temp.li_5828_validate('<UUID de usuário NÃO admin>');

Esperado: 9 linhas PASS + GATE = PASS (9/9).
================================================================
*/

create or replace function pg_temp.li_5828_validate(p_user uuid)
returns table (seq integer, check_id text, status text, detail text)
language plpgsql
volatile
as $fn$
#variable_conflict use_column
declare
  v_fn       oid := to_regprocedure('public.get_registrable_languages()');
  v_cfg      text[];
  v_acl      text;
  v_secdef   boolean;
  v_vol      "char";
  v_expected text;
  v_got      text;
  v_direct   bigint;
  v_state    text;
  res        jsonb := '[]'::jsonb;
  ok         boolean;
  r          jsonb;
  n          integer := 0;
  passes     integer := 0;
begin
  -- 1. Estrutura e privilégios (como administrador)
  res := res || jsonb_build_object('id','1.1','ok', v_fn is not null,'detail','função existe');
  if v_fn is not null then
    select p.prosecdef, p.provolatile, p.proconfig, array_to_string(p.proacl::text[], ',')
      into v_secdef, v_vol, v_cfg, v_acl
    from pg_proc p where p.oid = v_fn;
  end if;
  res := res || jsonb_build_object('id','1.2','ok', coalesce(v_secdef and v_vol = 's', false),
           'detail', format('security definer=%s volatile=%s', v_secdef, v_vol));
  res := res || jsonb_build_object('id','1.3','ok', coalesce(v_cfg = array['search_path=""'], false),
           'detail', format('proconfig=%s', v_cfg));
  ok := v_fn is not null
        and has_function_privilege('authenticated', v_fn, 'EXECUTE')
        and not has_function_privilege('anon', v_fn, 'EXECUTE')
        and coalesce(v_acl, '') !~ '(^|,)=X';
  res := res || jsonb_build_object('id','1.4','ok', ok, 'detail', format('acl=%s', v_acl));
  ok := exists (select 1 from auth.users u where u.id = p_user)
        and not exists (select 1 from public.admin_user a where a.id = p_user);
  res := res || jsonb_build_object('id','1.5','ok', ok, 'detail','usuário de teste existe e não é administrador');

  select string_agg(l.code, ',' order by l.language_order, l.code) into v_expected
  from public.language l where l.is_active;

  -- 2. anon: sem EXECUTE (42501)
  perform set_config('request.jwt.claims', '', true);
  execute 'set local role anon';
  begin
    perform public.get_registrable_languages();
    v_state := 'executou';
  exception when others then
    v_state := sqlstate;
  end;
  execute 'reset role';
  res := res || jsonb_build_object('id','2.1','ok', v_state = '42501', 'detail', 'anon: '||v_state);

  -- 3. authenticated sem auth.uid(): 28000
  execute 'set local role authenticated';
  begin
    perform public.get_registrable_languages();
    v_state := 'executou';
  exception when others then
    v_state := sqlstate;
  end;
  execute 'reset role';
  res := res || jsonb_build_object('id','3.1','ok', v_state = '28000', 'detail', 'sem auth.uid(): '||v_state);

  -- 4. authenticated NÃO admin: RLS da tabela intacta e função devolve os ativos, na ordem
  perform set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  select count(*) into v_direct from public.language;
  select string_agg(g.code, ',' order by g.language_order, g.code) into v_got
  from public.get_registrable_languages() g;
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);

  res := res || jsonb_build_object('id','4.1','ok', v_direct = 0,
           'detail', format('leitura direta de public.language pelo não-admin = %s linhas (RLS admin-only intacta)', v_direct));
  res := res || jsonb_build_object('id','4.2','ok', v_got is not null and v_got = v_expected,
           'detail', format('função=%s esperado=%s', v_got, v_expected));

  -- 5. Papel restaurado
  res := res || jsonb_build_object('id','5.1','ok', current_user = session_user,
           'detail', format('current_user=%s', current_user));

  for r in select * from jsonb_array_elements(res) loop
    n := n + 1;
    if (r->>'ok')::boolean then passes := passes + 1; end if;
    seq := n; check_id := r->>'id';
    status := case when coalesce((r->>'ok')::boolean, false) then 'PASS' else 'FAIL' end;
    detail := r->>'detail';
    return next;
  end loop;
  seq := 99; check_id := 'GATE';
  status := case when passes = 9 and n = 9 then 'PASS' else 'FAIL' end;
  detail := format('%s/%s PASS', passes, n);
  return next;
end;
$fn$;

-- SELECT * FROM pg_temp.li_5828_validate('<UUID de usuário NÃO admin>');
