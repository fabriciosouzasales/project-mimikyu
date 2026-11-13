/*
================================================================
V1-16 · S3 — prova SEM ESCRITA dos guards de get_my_inventory_item_copies
(`S3 READINESS-01`, 2026-11-13)
Status.....: PREPARADO.
Natureza...: UMA instrução (um DO) em transação READ ONLY, identidade
             SINTÉTICA (UUID aleatório conferido como inexistente em
             auth.users), relatório por RAISE EXCEPTION 55000 (aborta).
             Só chama a função de leitura; nenhuma conta real; nenhum dado
             de usuário sai no relatório.
Testes.....: G1 sem identidade → 28000 · G2 item inválido → 22023 ·
             G3 identidade sintética, variante real → executa sem erro e
             devolve 0 linhas (sem inventário) · G4 papel anon → 42501.
             Mesmas expectativas antes (S2) e depois (S3) da 5363.
Limite.....: com identidade sintética a função retorna antes do RETURN
             QUERY (sem inventário) — a montagem das 21 colunas com dados
             reais NÃO é exercida aqui; as colunas são provadas por
             catálogo (S3_STATE G-04/G-05) e a leitura real fica para o
             uso do proprietário no app (Meu acervo → detalhe).
Gate.......: 4/4, GATE_OK = true.
================================================================
*/
do $s3probe$
declare
  v_uid   uuid := gen_random_uuid();
  v_cv    uuid;
  v_state text;
  v_n     bigint;
  v_lines text := '';
  v_pass  int := 0;
  v_ok    boolean;
begin
  set local transaction_read_only = on;
  if exists (select 1 from auth.users where id = v_uid) then
    raise exception 'S3-PROBE: UUID sintético colidiu com conta real — abortado';
  end if;
  select cv.id into v_cv from public.card_variant cv where cv.is_active order by cv.id limit 1;

  -- G1 sem identidade
  perform set_config('request.jwt.claims', '{}', true);
  v_state := 'ok';
  begin
    perform * from public.get_my_inventory_item_copies(v_cv, 'pt-BR');
  exception when others then v_state := sqlstate;
  end;
  v_ok := v_state = '28000'; v_pass := v_pass + coalesce(v_ok, false)::int;
  v_lines := v_lines || format(E'G1 %s sem identidade → 28000 | estado=%s\n', case when v_ok then 'PASS' else 'FAIL' end, v_state);

  -- identidade sintética a partir daqui
  perform set_config('request.jwt.claims', json_build_object('sub', v_uid::text, 'role', 'authenticated')::text, true);

  -- G2 item inválido
  v_state := 'ok';
  begin
    perform * from public.get_my_inventory_item_copies(null, 'pt-BR');
  exception when others then v_state := sqlstate;
  end;
  v_ok := v_state = '22023'; v_pass := v_pass + coalesce(v_ok, false)::int;
  v_lines := v_lines || format(E'G2 %s item inválido → 22023 | estado=%s\n', case when v_ok then 'PASS' else 'FAIL' end, v_state);

  -- G3 identidade sintética, variante real → 0 linhas, sem erro
  v_state := 'ok'; v_n := null;
  begin
    select count(*) into v_n from public.get_my_inventory_item_copies(v_cv, 'pt-BR');
  exception when others then v_state := sqlstate;
  end;
  v_ok := v_state = 'ok' and v_n = 0; v_pass := v_pass + coalesce(v_ok, false)::int;
  v_lines := v_lines || format(E'G3 %s identidade sem inventário → 0 linhas | estado=%s linhas=%s\n', case when coalesce(v_ok, false) then 'PASS' else 'FAIL' end, v_state, coalesce(v_n::text, '-'));

  -- G4 papel anon sem EXECUTE
  v_state := 'ok';
  begin
    set local role anon;
    perform * from public.get_my_inventory_item_copies(v_cv, 'pt-BR');
  exception when others then v_state := sqlstate;
  end;
  reset role;
  v_ok := v_state = '42501'; v_pass := v_pass + coalesce(v_ok, false)::int;
  v_lines := v_lines || format(E'G4 %s papel anon → 42501 | estado=%s\n', case when v_ok then 'PASS' else 'FAIL' end, v_state);

  raise exception using errcode = '55000', message = format(
    E'\n====== S3-PROBE (somente leitura, identidade sintética) ======\n'
    'ESTÁGIO=%s  TOTAL=4  PASS=%s  FAIL=%s  ->  GATE_OK = %s\n'
    'transaction_read_only=%s\n%s'
    'ROLLBACK GARANTIDO POR CONSTRUÇÃO (esta exceção aborta a transação).\n'
    '==============================================================',
    case md5((select prosrc from pg_proc where oid = to_regprocedure('public.get_my_inventory_item_copies(uuid,text)')))
         when 'd8cce43b511856a5e25f061e75a7cede' then '5262 (antes da 5363)'
         when '77abbb9a33f2cb46280925bade22dee5' then '5363' else 'DIVERGENTE' end,
    v_pass, 4 - v_pass, v_pass = 4, current_setting('transaction_read_only'), v_lines);
end;
$s3probe$;
