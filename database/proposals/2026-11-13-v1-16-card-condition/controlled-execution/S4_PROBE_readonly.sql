/*
================================================================
V1-16 · S4 — prova SEM ESCRITA dos guards de set_my_physical_cards_condition
(`S4 READINESS-01`, 2026-11-13)
Status.....: PREPARADO, NÃO EXECUTADO.
Natureza...: UMA instrução (um DO): transaction_read_only ligado antes de
             qualquer chamada; identidade SINTÉTICA (UUID aleatório
             conferido como inexistente em auth.users, sem inventário);
             IDs de exemplar aleatórios (não existem); relatório por
             RAISE EXCEPTION 55000 (aborta).
Por que não escreve: todos os casos param ANTES do FOR UPDATE e do UPDATE
             da função — nos guards de identidade, código e lote, ou em
             "inventory not found" (identidade sem inventário). Se algum
             caso chegasse à trava, o modo READ ONLY a recusaria (25006) e
             o caso seria FAIL; o RAISE final desfaz a instrução de qualquer
             forma.
Testes.....: K01 sem identidade → 28000 · K02 código nulo · K03 código em
             branco · K04 'XX' · K05 'nm' (caixa) → 22023 · K06 lote nulo ·
             K07 lote vazio · K08 lote 2D · K09 501 entradas → 22023 ·
             K10 500 entradas passam o limite e param no inventário ·
             K11 identidade sem inventário → 'inventory not found' ·
             K12 papel anon → 42501. Os seis códigos válidos passam a
             validação em K10/K11 (M e DMG) e em K13 (NM, LP, MP, HP).
Antes da 5364: relata "função ausente" e não testa nada.
Gate.......: 13/13, GATE_OK = true.
NÃO cobre..: atualização real, titularidade de exemplares reais (alheio ×
             próprio), idempotência (changed_count), updated_at,
             concorrência — exigem escrita (harness 5887 grupo D), não
             autorizado.
================================================================
*/
do $s4probe$
declare
  v_uid   uuid := gen_random_uuid();
  v_state text;
  v_msg   text;
  v_lines text := '';
  v_pass  int := 0;
  v_total int := 0;
  v_ok    boolean;
  v_one   uuid[] := array[gen_random_uuid()];
  v_code  text;
begin
  set local transaction_read_only = on;

  if to_regprocedure('public.set_my_physical_cards_condition(uuid[],text)') is null then
    raise exception using errcode = '55000', message =
      E'\n====== S4-PROBE ======\nset_my_physical_cards_condition AUSENTE (antes da 5364) — nada testado.\n======================';
  end if;
  if exists (select 1 from auth.users where id = v_uid) then
    raise exception 'S4-PROBE: UUID sintético colidiu com conta real — abortado';
  end if;

  -- K01 sem identidade
  perform set_config('request.jwt.claims', '{}', true);
  v_state := 'ok'; v_msg := null;
  begin perform * from public.set_my_physical_cards_condition(v_one, 'LP');
  exception when others then v_state := sqlstate; v_msg := sqlerrm; end;
  v_ok := v_state = '28000'; v_total := v_total + 1; v_pass := v_pass + coalesce(v_ok, false)::int;
  v_lines := v_lines || format(E'K01 %s sem identidade → 28000 | %s\n', case when coalesce(v_ok,false) then 'PASS' else 'FAIL' end, v_state);

  perform set_config('request.jwt.claims', json_build_object('sub', v_uid::text, 'role', 'authenticated')::text, true);

  -- K02..K05 código
  foreach v_code in array array['<NULL>', '   ', 'XX', 'nm'] loop
    v_state := 'ok'; v_msg := null;
    begin perform * from public.set_my_physical_cards_condition(v_one, nullif(v_code, '<NULL>'));
    exception when others then v_state := sqlstate; v_msg := sqlerrm; end;
    v_ok := v_state = '22023' and position(case when v_code in ('<NULL>', '   ') then 'condition_code é obrigatório' else 'CONDITION_NOT_FOUND' end in coalesce(v_msg, '')) > 0;
    v_total := v_total + 1; v_pass := v_pass + coalesce(v_ok, false)::int;
    v_lines := v_lines || format(E'K%s %s código %s → recusa | %s %s\n', lpad((v_total)::text, 2, '0'),
                                 case when coalesce(v_ok,false) then 'PASS' else 'FAIL' end, quote_literal(v_code), v_state, left(coalesce(v_msg, '-'), 70));
  end loop;

  -- K06 lote nulo
  v_state := 'ok'; v_msg := null;
  begin perform * from public.set_my_physical_cards_condition(null, 'LP');
  exception when others then v_state := sqlstate; v_msg := sqlerrm; end;
  v_ok := v_state = '22023' and position('não pode ser vazio' in coalesce(v_msg, '')) > 0;
  v_total := v_total + 1; v_pass := v_pass + coalesce(v_ok, false)::int;
  v_lines := v_lines || format(E'K06 %s lote nulo → recusa | %s %s\n', case when coalesce(v_ok,false) then 'PASS' else 'FAIL' end, v_state, left(coalesce(v_msg, '-'), 60));

  -- K07 lote vazio
  v_state := 'ok'; v_msg := null;
  begin perform * from public.set_my_physical_cards_condition('{}'::uuid[], 'LP');
  exception when others then v_state := sqlstate; v_msg := sqlerrm; end;
  v_ok := v_state = '22023' and position('não pode ser vazio' in coalesce(v_msg, '')) > 0;
  v_total := v_total + 1; v_pass := v_pass + coalesce(v_ok, false)::int;
  v_lines := v_lines || format(E'K07 %s lote vazio → recusa | %s %s\n', case when coalesce(v_ok,false) then 'PASS' else 'FAIL' end, v_state, left(coalesce(v_msg, '-'), 60));

  -- K08 lote bidimensional
  v_state := 'ok'; v_msg := null;
  begin perform * from public.set_my_physical_cards_condition(array[[gen_random_uuid()], [gen_random_uuid()]], 'LP');
  exception when others then v_state := sqlstate; v_msg := sqlerrm; end;
  v_ok := v_state = '22023' and position('unidimensional' in coalesce(v_msg, '')) > 0;
  v_total := v_total + 1; v_pass := v_pass + coalesce(v_ok, false)::int;
  v_lines := v_lines || format(E'K08 %s lote 2D → recusa | %s %s\n', case when coalesce(v_ok,false) then 'PASS' else 'FAIL' end, v_state, left(coalesce(v_msg, '-'), 60));

  -- K09 501 entradas
  v_state := 'ok'; v_msg := null;
  begin perform * from public.set_my_physical_cards_condition(array_fill(gen_random_uuid(), array[501]), 'LP');
  exception when others then v_state := sqlstate; v_msg := sqlerrm; end;
  v_ok := v_state = '22023' and position('limite de 500' in coalesce(v_msg, '')) > 0;
  v_total := v_total + 1; v_pass := v_pass + coalesce(v_ok, false)::int;
  v_lines := v_lines || format(E'K09 %s 501 entradas → recusa | %s %s\n', case when coalesce(v_ok,false) then 'PASS' else 'FAIL' end, v_state, left(coalesce(v_msg, '-'), 60));

  -- K10 500 entradas passam o limite (para no inventário), código M
  v_state := 'ok'; v_msg := null;
  begin perform * from public.set_my_physical_cards_condition(array_fill(gen_random_uuid(), array[500]), 'M');
  exception when others then v_state := sqlstate; v_msg := sqlerrm; end;
  v_ok := v_state = '22023' and position('inventory not found' in coalesce(v_msg, '')) > 0;
  v_total := v_total + 1; v_pass := v_pass + coalesce(v_ok, false)::int;
  v_lines := v_lines || format(E'K10 %s 500 entradas aceitas pelo limite → inventory not found | %s %s\n', case when coalesce(v_ok,false) then 'PASS' else 'FAIL' end, v_state, left(coalesce(v_msg, '-'), 60));

  -- K11 identidade sem inventário, código DMG
  v_state := 'ok'; v_msg := null;
  begin perform * from public.set_my_physical_cards_condition(v_one, 'DMG');
  exception when others then v_state := sqlstate; v_msg := sqlerrm; end;
  v_ok := v_state = '22023' and position('inventory not found' in coalesce(v_msg, '')) > 0;
  v_total := v_total + 1; v_pass := v_pass + coalesce(v_ok, false)::int;
  v_lines := v_lines || format(E'K11 %s identidade sem inventário → inventory not found | %s %s\n', case when coalesce(v_ok,false) then 'PASS' else 'FAIL' end, v_state, left(coalesce(v_msg, '-'), 60));

  -- K12 papel anon sem EXECUTE
  v_state := 'ok'; v_msg := null;
  begin
    set local role anon;
    perform * from public.set_my_physical_cards_condition(v_one, 'LP');
  exception when others then v_state := sqlstate; v_msg := sqlerrm; end;
  reset role;
  v_ok := v_state = '42501'; v_total := v_total + 1; v_pass := v_pass + coalesce(v_ok, false)::int;
  v_lines := v_lines || format(E'K12 %s papel anon → 42501 | %s\n', case when coalesce(v_ok,false) then 'PASS' else 'FAIL' end, v_state);

  -- K13 NM, LP, MP, HP passam a validação de código (param no inventário)
  v_ok := true;
  foreach v_code in array array['NM', 'LP', 'MP', 'HP'] loop
    v_state := 'ok'; v_msg := null;
    begin perform * from public.set_my_physical_cards_condition(v_one, v_code);
    exception when others then v_state := sqlstate; v_msg := sqlerrm; end;
    v_ok := v_ok and v_state = '22023' and position('inventory not found' in coalesce(v_msg, '')) > 0;
  end loop;
  v_total := v_total + 1; v_pass := v_pass + coalesce(v_ok, false)::int;
  v_lines := v_lines || format(E'K13 %s NM, LP, MP, HP aceitos pela validação → inventory not found\n', case when coalesce(v_ok,false) then 'PASS' else 'FAIL' end);

  v_lines := regexp_replace(v_lines, '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', '<uuid>', 'gi');
  raise exception using errcode = '55000', message = format(
    E'\n====== S4-PROBE (somente leitura, identidade sintética) ======\n'
    'TOTAL=%s  PASS=%s  FAIL=%s  GATE ESPERADO=13/13  ->  GATE_OK = %s\n'
    'transaction_read_only=%s\n%s'
    'ROLLBACK GARANTIDO POR CONSTRUÇÃO (esta exceção aborta a transação).\n'
    '==============================================================',
    v_total, v_pass, v_total - v_pass, (v_total = 13 and v_pass = 13), current_setting('transaction_read_only'), v_lines);
end;
$s4probe$;
