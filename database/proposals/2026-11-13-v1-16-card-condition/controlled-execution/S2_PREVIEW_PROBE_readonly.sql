/*
================================================================
V1-16 · S2 — prova FUNCIONAL SEM ESCRITA das regras de condição
(`S2 CONTROLLED EXECUTION READINESS-01`, 2026-11-13)
Status.....: PREPARADO, NÃO EXECUTADO.
Natureza...: UMA instrução (um DO) que:
             1. liga transaction_read_only no início — o servidor recusa
                qualquer INSERT/UPDATE/DELETE/DDL dali em diante (25006),
                inclusive dentro de funções SECURITY DEFINER;
             2. usa identidade SINTÉTICA: um UUID aleatório que NÃO existe
                em auth.users (conferido) — nenhuma conta real; sem
                inventário, sem coleção, sem local;
             3. chama só a Prévia (preview_bulk_operation, que não escreve
                nem trava por contrato) e as confirmações (B1/B2) APENAS com
                pedidos que falham nos guards estruturais, ANTES do claim de
                idempotência — nenhum caminho chega a uma escrita;
             4. lê do catálogo público uma variante ativa, um idioma e o
                menor Set com cartas ativas — nada é alterado no catálogo;
             5. entrega o relatório por RAISE EXCEPTION (55000), que aborta a
                transação.
             Não cria objeto temporário, não usa conta real, não altera
             variantes. Mensagens com UUID são mascaradas no relatório.
Estágio....: detecta S1 (antes da 5362) ou S2 (depois) e aplica a
             expectativa do estágio. Rodar ANTES (prova que o teste
             discrimina: as chaves de condição são recusadas) e DEPOIS.
Gate.......: S1 → 15/15 · S2 → 16/16 ("GATE_OK = true").
Cobre......: validação dos seis códigos e de código inexistente/caixa;
             ausente ≡ NM na duplicidade; duplicidade pelo trio; condição
             vazia/não-texto; B2 com condição no nível do pedido; prévia e
             confirmação com as mesmas regras estruturais; prefixos
             legados de mensagem; a validação interna isolada.
NÃO cobre..: escrita da condição, idempotência/hash histórico, REPLAY,
             fingerprint, travas — exigem teste mutável (harness 5887 B),
             não autorizado.
================================================================
*/
do $probe$
declare
  v_uid    uuid := gen_random_uuid();
  v_stage  text;
  v_cv     uuid;
  v_lang   uuid;
  v_set    uuid;
  v_r      jsonb;
  v_codes  text[];
  v_off    text[];
  v_state  text;
  v_msg    text;
  v_ok     boolean;
  v_lines  text := '';
  v_total  int := 0;
  v_pass   int := 0;
  v_want   int;
  v_item   jsonb;
  c_keys   constant text := 'aceita exatamente as chaves';
  c_empty  constant text := 'condition_code, quando informado, deve ser uma string nao vazia';
begin
  -- 1) Somente leitura a partir daqui (setar READ ONLY no meio da transação é permitido).
  set local transaction_read_only = on;

  -- 2) Identidade sintética, nunca uma conta real.
  if exists (select 1 from auth.users where id = v_uid) then
    raise exception 'S2-PROBE: UUID sintético colidiu com conta real — abortado';
  end if;
  perform set_config('request.jwt.claims',
          json_build_object('sub', v_uid::text, 'role', 'authenticated')::text, true);

  v_stage := case when to_regprocedure('public.physical_card_unknown_condition_codes(text[])') is null then 'S1' else 'S2' end;
  v_want  := case when v_stage = 'S1' then 15 else 16 end;

  -- 3) Catálogo público (só leitura).
  select cv.id into v_cv from public.card_variant cv where cv.is_active order by cv.id limit 1;
  select l.id into v_lang from public.language l order by l.id limit 1;
  -- menor Set com cartas ativas que tenham variante padrão ativa (a prévia B2
  -- só avalia a condição sobre a expansão, que exige variante padrão)
  select c.card_set_id into v_set
    from public.card c
    join public.card_variant dv on dv.card_id = c.id and dv.is_default and dv.is_active
   where c.is_active
   group by c.card_set_id
   order by count(*), c.card_set_id
   limit 1;
  if v_cv is null or v_lang is null or v_set is null then
    raise exception 'S2-PROBE: catálogo sem variante ativa, idioma ou Set com cartas ativas';
  end if;
  v_item := jsonb_build_object('card_variant_id', v_cv::text, 'language_id', v_lang::text, 'quantity', 1);

  ---------------------------------------------------------------------------
  -- T01 Prévia B1 sem condição (igual nos dois estágios)
  v_r := public.preview_bulk_operation(jsonb_build_object('operation_type', 'REGISTER_PHYSICAL_CARDS', 'items', jsonb_build_array(v_item)));
  v_codes := array(select e ->> 'code' from jsonb_array_elements(v_r -> 'issues') e);
  v_ok := 'INVENTORY_NOT_FOUND' = any(v_codes) and not 'CONDITION_NOT_FOUND' = any(v_codes) and not 'DUPLICATE_ITEM' = any(v_codes);
  v_total := v_total + 1; v_pass := v_pass + coalesce(v_ok, false)::int;
  v_lines := v_lines || format(E'T01 %s prévia B1 sem condição | issues=%s\n', case when coalesce(v_ok, false) then 'PASS' else 'FAIL' end, v_codes);

  ---------------------------------------------------------------------------
  -- T02 Prévia B1 com 'LP'
  v_state := 'ok'; v_msg := null; v_codes := null;
  begin
    v_r := public.preview_bulk_operation(jsonb_build_object('operation_type', 'REGISTER_PHYSICAL_CARDS',
             'items', jsonb_build_array(v_item || jsonb_build_object('condition_code', 'LP'))));
    v_codes := array(select e ->> 'code' from jsonb_array_elements(v_r -> 'issues') e);
  exception when others then v_state := sqlstate; v_msg := sqlerrm;
  end;
  v_ok := case when v_stage = 'S1' then v_state = '22023' and position(c_keys in v_msg) > 0
               else v_state = 'ok' and not 'CONDITION_NOT_FOUND' = any(v_codes) and not 'DUPLICATE_ITEM' = any(v_codes) end;
  v_total := v_total + 1; v_pass := v_pass + coalesce(v_ok, false)::int;
  v_lines := v_lines || format(E'T02 %s prévia B1 condição LP | estado=%s issues=%s msg=%s\n', case when coalesce(v_ok, false) then 'PASS' else 'FAIL' end, v_state, v_codes, left(coalesce(v_msg, '-'), 90));

  ---------------------------------------------------------------------------
  -- T03 Prévia B1 com os seis códigos, mesma variante e idioma (trio distinto)
  v_state := 'ok'; v_msg := null; v_codes := null;
  begin
    v_r := public.preview_bulk_operation(jsonb_build_object('operation_type', 'REGISTER_PHYSICAL_CARDS',
             'items', (select jsonb_agg(v_item || jsonb_build_object('condition_code', c)) from unnest(array['M','NM','LP','MP','HP','DMG']) as c)));
    v_codes := array(select e ->> 'code' from jsonb_array_elements(v_r -> 'issues') e);
  exception when others then v_state := sqlstate; v_msg := sqlerrm;
  end;
  v_ok := case when v_stage = 'S1' then v_state = '22023' and position(c_keys in v_msg) > 0
               else v_state = 'ok' and not 'CONDITION_NOT_FOUND' = any(v_codes) and not 'DUPLICATE_ITEM' = any(v_codes) end;
  v_total := v_total + 1; v_pass := v_pass + coalesce(v_ok, false)::int;
  v_lines := v_lines || format(E'T03 %s prévia B1 seis códigos (M,NM,LP,MP,HP,DMG) | estado=%s issues=%s msg=%s\n', case when coalesce(v_ok, false) then 'PASS' else 'FAIL' end, v_state, v_codes, left(coalesce(v_msg, '-'), 90));

  ---------------------------------------------------------------------------
  -- T04 Prévia B1 com código inexistente 'XX' e caixa errada 'nm'
  v_state := 'ok'; v_msg := null; v_codes := null; v_off := null;
  begin
    v_r := public.preview_bulk_operation(jsonb_build_object('operation_type', 'REGISTER_PHYSICAL_CARDS',
             'items', jsonb_build_array(v_item || jsonb_build_object('condition_code', 'XX'),
                                        v_item || jsonb_build_object('condition_code', 'nm'))));
    v_codes := array(select e ->> 'code' from jsonb_array_elements(v_r -> 'issues') e);
    v_off := array(select x from jsonb_array_elements(v_r -> 'issues') e, jsonb_array_elements_text(e -> 'offenders') x
                    where e ->> 'code' = 'CONDITION_NOT_FOUND' order by x);
  exception when others then v_state := sqlstate; v_msg := sqlerrm;
  end;
  v_ok := case when v_stage = 'S1' then v_state = '22023' and position(c_keys in v_msg) > 0
               else v_state = 'ok' and 'CONDITION_NOT_FOUND' = any(v_codes)
                    and v_off @> array['XX','nm'] and v_off <@ array['XX','nm'] end;
  v_total := v_total + 1; v_pass := v_pass + coalesce(v_ok, false)::int;
  v_lines := v_lines || format(E'T04 %s prévia B1 XX e nm → CONDITION_NOT_FOUND | estado=%s issues=%s offenders=%s msg=%s\n', case when coalesce(v_ok, false) then 'PASS' else 'FAIL' end, v_state, v_codes, v_off, left(coalesce(v_msg, '-'), 90));

  ---------------------------------------------------------------------------
  -- T05 Prévia B1: ausente + 'NM' na mesma variante/idioma = duplicidade (ausente ≡ NM)
  v_state := 'ok'; v_msg := null; v_codes := null;
  begin
    v_r := public.preview_bulk_operation(jsonb_build_object('operation_type', 'REGISTER_PHYSICAL_CARDS',
             'items', jsonb_build_array(v_item, v_item || jsonb_build_object('condition_code', 'NM'))));
    v_codes := array(select e ->> 'code' from jsonb_array_elements(v_r -> 'issues') e);
  exception when others then v_state := sqlstate; v_msg := sqlerrm;
  end;
  v_ok := case when v_stage = 'S1' then v_state = '22023' and position(c_keys in v_msg) > 0
               else v_state = 'ok' and 'DUPLICATE_ITEM' = any(v_codes) end;
  v_total := v_total + 1; v_pass := v_pass + coalesce(v_ok, false)::int;
  v_lines := v_lines || format(E'T05 %s prévia B1 ausente + NM → DUPLICATE_ITEM | estado=%s issues=%s msg=%s\n', case when coalesce(v_ok, false) then 'PASS' else 'FAIL' end, v_state, v_codes, left(coalesce(v_msg, '-'), 90));

  ---------------------------------------------------------------------------
  -- T06 Prévia B1 com condição vazia
  v_state := 'ok'; v_msg := null;
  begin
    v_r := public.preview_bulk_operation(jsonb_build_object('operation_type', 'REGISTER_PHYSICAL_CARDS',
             'items', jsonb_build_array(v_item || jsonb_build_object('condition_code', '  '))));
  exception when others then v_state := sqlstate; v_msg := sqlerrm;
  end;
  v_ok := v_state = '22023' and position(case when v_stage = 'S1' then c_keys else c_empty end in coalesce(v_msg, '')) > 0;
  v_total := v_total + 1; v_pass := v_pass + coalesce(v_ok, false)::int;
  v_lines := v_lines || format(E'T06 %s prévia B1 condição vazia → recusa | estado=%s msg=%s\n', case when coalesce(v_ok, false) then 'PASS' else 'FAIL' end, v_state, left(coalesce(v_msg, '-'), 90));

  ---------------------------------------------------------------------------
  -- T07 Prévia B1 com condição não-texto (número)
  v_state := 'ok'; v_msg := null;
  begin
    v_r := public.preview_bulk_operation(jsonb_build_object('operation_type', 'REGISTER_PHYSICAL_CARDS',
             'items', jsonb_build_array(v_item || jsonb_build_object('condition_code', 2))));
  exception when others then v_state := sqlstate; v_msg := sqlerrm;
  end;
  v_ok := v_state = '22023' and position(case when v_stage = 'S1' then c_keys else c_empty end in coalesce(v_msg, '')) > 0;
  v_total := v_total + 1; v_pass := v_pass + coalesce(v_ok, false)::int;
  v_lines := v_lines || format(E'T07 %s prévia B1 condição numérica → recusa | estado=%s msg=%s\n', case when coalesce(v_ok, false) then 'PASS' else 'FAIL' end, v_state, left(coalesce(v_msg, '-'), 90));

  ---------------------------------------------------------------------------
  -- T08 Prévia B2 com condição 'XX' no nível do pedido
  v_state := 'ok'; v_msg := null; v_codes := null;
  begin
    v_r := public.preview_bulk_operation(jsonb_build_object('operation_type', 'REGISTER_CARD_SET',
             'card_set_id', v_set::text, 'language_id', v_lang::text, 'condition_code', 'XX'));
    v_codes := array(select e ->> 'code' from jsonb_array_elements(v_r -> 'issues') e);
  exception when others then v_state := sqlstate; v_msg := sqlerrm;
  end;
  v_ok := case when v_stage = 'S1' then v_state = '22023' and position(c_keys in v_msg) > 0
               else v_state = 'ok' and 'CONDITION_NOT_FOUND' = any(v_codes) end;
  v_total := v_total + 1; v_pass := v_pass + coalesce(v_ok, false)::int;
  v_lines := v_lines || format(E'T08 %s prévia B2 condição XX → CONDITION_NOT_FOUND | estado=%s issues=%s msg=%s\n', case when coalesce(v_ok, false) then 'PASS' else 'FAIL' end, v_state, v_codes, left(coalesce(v_msg, '-'), 90));

  ---------------------------------------------------------------------------
  -- T09 Prévia B2 com condição vazia
  v_state := 'ok'; v_msg := null;
  begin
    v_r := public.preview_bulk_operation(jsonb_build_object('operation_type', 'REGISTER_CARD_SET',
             'card_set_id', v_set::text, 'language_id', v_lang::text, 'condition_code', ''));
  exception when others then v_state := sqlstate; v_msg := sqlerrm;
  end;
  v_ok := v_state = '22023' and position(case when v_stage = 'S1' then c_keys else c_empty end in coalesce(v_msg, '')) > 0;
  v_total := v_total + 1; v_pass := v_pass + coalesce(v_ok, false)::int;
  v_lines := v_lines || format(E'T09 %s prévia B2 condição vazia → recusa | estado=%s msg=%s\n', case when coalesce(v_ok, false) then 'PASS' else 'FAIL' end, v_state, left(coalesce(v_msg, '-'), 90));

  ---------------------------------------------------------------------------
  -- T10 Prévia B2 sem condição (igual nos dois estágios)
  v_state := 'ok'; v_msg := null; v_codes := null;
  begin
    v_r := public.preview_bulk_operation(jsonb_build_object('operation_type', 'REGISTER_CARD_SET',
             'card_set_id', v_set::text, 'language_id', v_lang::text));
    v_codes := array(select e ->> 'code' from jsonb_array_elements(v_r -> 'issues') e);
  exception when others then v_state := sqlstate; v_msg := sqlerrm;
  end;
  v_ok := v_state = 'ok' and not 'CONDITION_NOT_FOUND' = any(v_codes);
  v_total := v_total + 1; v_pass := v_pass + coalesce(v_ok, false)::int;
  v_lines := v_lines || format(E'T10 %s prévia B2 sem condição | estado=%s issues=%s msg=%s\n', case when coalesce(v_ok, false) then 'PASS' else 'FAIL' end, v_state, v_codes, left(coalesce(v_msg, '-'), 90));

  ---------------------------------------------------------------------------
  -- T11 Confirmação B1: ausente + 'NM' → duplicado (guard antes do claim)
  v_state := 'ok'; v_msg := null;
  begin
    v_r := public.register_physical_cards_bulk(jsonb_build_object('idempotency_key', gen_random_uuid()::text,
             'preview_fingerprint', 's2-probe', 'items', jsonb_build_array(v_item, v_item || jsonb_build_object('condition_code', 'NM'))));
  exception when others then v_state := sqlstate; v_msg := sqlerrm;
  end;
  v_ok := v_state = '22023' and position(case when v_stage = 'S1' then c_keys else 'duplicado(s)' end in coalesce(v_msg, '')) > 0;
  v_total := v_total + 1; v_pass := v_pass + coalesce(v_ok, false)::int;
  v_lines := v_lines || format(E'T11 %s confirmação B1 ausente + NM → duplicado | estado=%s msg=%s\n', case when coalesce(v_ok, false) then 'PASS' else 'FAIL' end, v_state, left(coalesce(v_msg, '-'), 60));

  ---------------------------------------------------------------------------
  -- T12 Confirmação B1 com condição vazia (guard antes do claim)
  v_state := 'ok'; v_msg := null;
  begin
    v_r := public.register_physical_cards_bulk(jsonb_build_object('idempotency_key', gen_random_uuid()::text,
             'preview_fingerprint', 's2-probe', 'items', jsonb_build_array(v_item || jsonb_build_object('condition_code', ''))));
  exception when others then v_state := sqlstate; v_msg := sqlerrm;
  end;
  v_ok := v_state = '22023' and position(case when v_stage = 'S1' then c_keys else c_empty end in coalesce(v_msg, '')) > 0;
  v_total := v_total + 1; v_pass := v_pass + coalesce(v_ok, false)::int;
  v_lines := v_lines || format(E'T12 %s confirmação B1 condição vazia → recusa | estado=%s msg=%s\n', case when coalesce(v_ok, false) then 'PASS' else 'FAIL' end, v_state, left(coalesce(v_msg, '-'), 90));

  ---------------------------------------------------------------------------
  -- T13 Confirmação B2 com condição vazia (guard antes do claim)
  v_state := 'ok'; v_msg := null;
  begin
    v_r := public.register_card_set_bulk(jsonb_build_object('idempotency_key', gen_random_uuid()::text,
             'preview_fingerprint', 's2-probe', 'card_set_id', v_set::text, 'language_id', v_lang::text, 'condition_code', ''));
  exception when others then v_state := sqlstate; v_msg := sqlerrm;
  end;
  v_ok := v_state = '22023' and position(case when v_stage = 'S1' then c_keys else c_empty end in coalesce(v_msg, '')) > 0;
  v_total := v_total + 1; v_pass := v_pass + coalesce(v_ok, false)::int;
  v_lines := v_lines || format(E'T13 %s confirmação B2 condição vazia → recusa | estado=%s msg=%s\n', case when coalesce(v_ok, false) then 'PASS' else 'FAIL' end, v_state, left(coalesce(v_msg, '-'), 90));

  ---------------------------------------------------------------------------
  -- T14 Confirmação B1 com chave desconhecida (prefixo legado preservado)
  v_state := 'ok'; v_msg := null;
  begin
    v_r := public.register_physical_cards_bulk(jsonb_build_object('idempotency_key', gen_random_uuid()::text,
             'preview_fingerprint', 's2-probe', 'items', jsonb_build_array(v_item || jsonb_build_object('condicao', 'NM'))));
  exception when others then v_state := sqlstate; v_msg := sqlerrm;
  end;
  v_ok := v_state = '22023' and position('cada item de items ' || c_keys in coalesce(v_msg, '')) > 0;
  v_total := v_total + 1; v_pass := v_pass + coalesce(v_ok, false)::int;
  v_lines := v_lines || format(E'T14 %s confirmação B1 chave desconhecida → prefixo legado | estado=%s msg=%s\n', case when coalesce(v_ok, false) then 'PASS' else 'FAIL' end, v_state, left(coalesce(v_msg, '-'), 90));

  ---------------------------------------------------------------------------
  -- T15 Prévia B1 com chave desconhecida (mesma regra da confirmação)
  v_state := 'ok'; v_msg := null;
  begin
    v_r := public.preview_bulk_operation(jsonb_build_object('operation_type', 'REGISTER_PHYSICAL_CARDS',
             'items', jsonb_build_array(v_item || jsonb_build_object('condicao', 'NM'))));
  exception when others then v_state := sqlstate; v_msg := sqlerrm;
  end;
  v_ok := v_state = '22023' and position('cada item de items ' || c_keys in coalesce(v_msg, '')) > 0;
  v_total := v_total + 1; v_pass := v_pass + coalesce(v_ok, false)::int;
  v_lines := v_lines || format(E'T15 %s prévia B1 chave desconhecida → prefixo legado | estado=%s msg=%s\n', case when coalesce(v_ok, false) then 'PASS' else 'FAIL' end, v_state, left(coalesce(v_msg, '-'), 90));

  ---------------------------------------------------------------------------
  -- T16 Validação interna isolada (só no estágio S2; chamada dinâmica)
  if v_stage = 'S2' then
    v_state := 'ok'; v_msg := null; v_off := null; v_codes := null;
    begin
      execute 'select public.physical_card_unknown_condition_codes($1)' into v_codes using array['M','NM','LP','MP','HP','DMG'];
      execute 'select public.physical_card_unknown_condition_codes($1)' into v_off  using array['XX','nm','NM',null]::text[];
    exception when others then v_state := sqlstate; v_msg := sqlerrm;
    end;
    v_ok := v_state = 'ok' and v_codes is null
            and v_off @> array['<null>','XX','nm'] and v_off <@ array['<null>','XX','nm'];
    v_total := v_total + 1; v_pass := v_pass + coalesce(v_ok, false)::int;
    v_lines := v_lines || format(E'T16 %s validação interna: seis códigos → NULL; {XX,nm,NM,null} → {<null>,XX,nm} | seis=%s outros=%s estado=%s\n',
                                 case when coalesce(v_ok, false) then 'PASS' else 'FAIL' end, coalesce(v_codes::text, 'NULL'), v_off, v_state);
  end if;

  ---------------------------------------------------------------------------
  v_lines := regexp_replace(v_lines, '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', '<uuid>', 'gi');
  raise exception using errcode = '55000', message = format(
    E'\n============== S2-PROBE (somente leitura, identidade sintética) ==============\n'
    'ESTÁGIO=%s  TOTAL=%s  PASS=%s  FAIL=%s  GATE ESPERADO=%s/%s  ->  GATE_OK = %s\n'
    'transaction_read_only=%s\n%s'
    'ROLLBACK GARANTIDO POR CONSTRUÇÃO (esta exceção aborta a transação).\n'
    '==============================================================================',
    v_stage, v_total, v_pass, v_total - v_pass, v_want, v_want, (v_total = v_want and v_pass = v_want),
    current_setting('transaction_read_only'), v_lines);
end;
$probe$;
