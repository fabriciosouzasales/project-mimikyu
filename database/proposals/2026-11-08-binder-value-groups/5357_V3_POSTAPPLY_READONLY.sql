/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5357-V3 - VERIFICAÇÃO PÓS-APLICAÇÃO SOMENTE LEITURA (fase C)
Versão......: 0.2 (B2 — PHASE C FINAL READINESS-01). Corrige os quatro
              defeitos registrados da 0.1:
              V3-1 permissões efetivas: ACL explícita OU nula (acldefault),
                   privilégios efetivos por has_function_privilege (herança e
                   PUBLIC incluídos) para postgres/authenticated/anon/
                   service_role, comparados com a leitura irmã 5252, e ACL
                   exata esperada {authenticated, postgres};
              V3-2 cada bloco devolve UMA linha estruturada (jsonb) com
                   "status" e "pass"; nenhum resultado depende de NOTICE;
              V3-3 todo bloco: READ ONLY, statement_timeout, lock_timeout,
                   idle_in_transaction_session_timeout, ROLLBACK; só
                   configurações LOCAIS da transação;
              V3-4 C3b sem marcadores no arquivo: parâmetros recebidos na
                   execução e validados no bloco antes de qualquer teste.
              0.3 (PHASE C — FINAL EXECUTOR COMPATIBILITY CORRECTION): o
              executor usado no projeto (conector SQL do Supabase,
              execute_sql) não interpreta variáveis do psql. O C3b passa a
              receber os parâmetros por um PREFIXO montado na chamada
              (BEGIN READ ONLY + timeouts + set_config locais), concatenado
              ao bloco do arquivo sem alterá-lo; o bloco recusa executar se a
              transação, o isolamento ou os timeouts do prefixo divergirem.
              C2, C3a e C3c inalterados.
Status......: PROPOSTO — NÃO EXECUTADO. Só tem sentido DEPOIS da aplicação da
              5357 (C1), que exige autorização independente. C2, C3a e C3b
              integram a validação da aplicação; C3c é independente e
              BLOQUEADO (lê como cada titular).
Data........: 2026-11-08

Forma de execução
  Um bloco por chamada, na ordem C2 → C3a → C3b. Cada bloco abre a própria
  transação READ ONLY e termina em ROLLBACK; a escrita é impossível pelo
  servidor (25006) e a segurança não depende do ROLLBACK. Os blocos com DO
  gravam o resultado numa configuração LOCAL da transação e o SELECT final o
  devolve. Erro inesperado: só o SQLSTATE é exposto, nunca a mensagem.
  Troca de identidade só por SET LOCAL ROLE + claims locais; o sub anterior é
  limpo a cada troca; RESET ROLE ao fim de cada caso. A sessão precisa poder
  assumir anon e authenticated (V1.5a: TRUE).

Saída: booleanos, SQLSTATE e nomes de papéis. Nenhum id, nome, carta ou
contagem individual de usuário.

Reversão: procedimento separado em 5357_R1_ROLLBACK_PROCEDURE.sql (nunca
automático; exige autorização).
================================================================
*/

-- C2 [GATE] definição, configuração e privilégios efetivos da função aplicada
-- PASS: todos os campos booleanos TRUE ("pass" resume).
begin transaction isolation level repeatable read read only;
set local statement_timeout = '5s'; set local lock_timeout = '2s'; set local idle_in_transaction_session_timeout = '30s';
with f as (
  select to_regprocedure('public.get_my_binder_value_groups(uuid,integer,integer)') as oid
), irma as (
  select to_regprocedure('public.get_my_collection_binder(uuid)') as oid
), p as (
  select pr.* from pg_proc pr join f on pr.oid = f.oid
), acl as (
  select coalesce(nullif(a.grantee, 0)::regrole::text, 'PUBLIC') as grantee, a.privilege_type
  from p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
), papeis(r) as (
  values ('postgres'), ('authenticated'), ('anon'), ('service_role')
), efetivo as (
  select pp.r,
         case when (select oid from f) is null then null
              else has_function_privilege(pp.r, (select oid from f), 'execute') end as nova,
         case when (select oid from irma) is null then null
              else has_function_privilege(pp.r, (select oid from irma), 'execute') end as irma
  from papeis pp
  where exists (select 1 from pg_roles x where x.rolname = pp.r)
), chk as (
  select
    (select oid from f) is not null                                                        as existe,
    coalesce((select pg_get_function_identity_arguments(oid) = 'p_collection_id uuid, p_limit integer, p_offset integer' from p), false) as assinatura,
    coalesce((select pg_get_function_result(oid) = 'TABLE(card_variant_id uuid, language_code text, language_name text, card_name text, collector_number text, collector_total integer, card_set_code text, card_set_name text, is_default_variant boolean, variant_label text, image_path text, copies_count integer, total_count bigint, total_copies bigint)' from p), false) as retorno_14_colunas,
    coalesce((select prosecdef from p), false)                                             as security_definer,
    coalesce((select provolatile = 's' from p), false)                                     as stable,
    coalesce((select proconfig = array['search_path=""'] from p), false)                   as search_path_vazio,
    coalesce((select l.lanname = 'plpgsql' from p join pg_language l on l.oid = p.prolang), false) as linguagem_plpgsql,
    coalesce((select pg_get_userbyid(proowner) = 'postgres' from p), false)                as dono_postgres,
    coalesce((select md5(prosrc) = 'e6cdae3e7c48d6df06f3fba4836c5575' from p), false)      as corpo_igual_a_proposta,
    exists (select 1 from pg_description d
             where d.objoid = (select oid from f) and d.classoid = 'pg_proc'::regclass)    as comentario_presente,
    coalesce((select array_agg(grantee order by grantee) from acl where privilege_type = 'EXECUTE')
             = array['authenticated', 'postgres'], false)                                  as acl_exata,
    not exists (select 1 from acl where grantee = 'PUBLIC')                                as public_sem_execute,
    coalesce((select bool_and(nova is not distinct from irma) and count(*) = 4 from efetivo), false) as efetivos_iguais_a_5252,
    coalesce((select not nova from efetivo where r = 'anon'), false)                       as anon_sem_execute,
    coalesce((select nova from efetivo where r = 'authenticated'), false)                  as authenticated_com_execute
)
select jsonb_build_object(
         'bloco', 'C2',
         'status', case when (select existe from chk) then 'OK' else 'FUNCAO_AUSENTE' end,
         'pass', (select existe and assinatura and retorno_14_colunas and security_definer and stable
                         and search_path_vazio and linguagem_plpgsql and dono_postgres and corpo_igual_a_proposta
                         and comentario_presente and acl_exata and public_sem_execute and efetivos_iguais_a_5252
                         and anon_sem_execute and authenticated_com_execute from chk),
         'verificacoes', (select to_jsonb(chk) from chk),
         'acl_info', (select string_agg(grantee || ':' || privilege_type, ', ' order by grantee) from acl),
         'efetivos_info', (select jsonb_object_agg(r, jsonb_build_object('nova', nova, 'irma_5252', irma)) from efetivo)
       ) as resultado_c2;
rollback;

-- C3a [GATE] negativos de autenticação e autorização (identidade inexistente)
-- PASS: "pass" TRUE (anon 42501; sem sub 28000; parâmetros 22023; coleção
-- inexistente e coleção de outro titular P0002 com a MESMA mensagem).
begin transaction isolation level repeatable read read only;
set local statement_timeout = '5s'; set local lock_timeout = '2s'; set local idle_in_transaction_session_timeout = '30s';
do $c3a$
declare
  v_fn regprocedure := to_regprocedure('public.get_my_binder_value_groups(uuid,integer,integer)');
  v_any uuid; m_any text; m_none text; st text; r jsonb := '{}'::jsonb; v_res jsonb;
begin
  if v_fn is null then
    v_res := jsonb_build_object('bloco', 'C3a', 'status', 'FUNCAO_AUSENTE', 'pass', false);
  else
    -- uma coleção com fichário qualquer, escolhida aqui dentro (nunca exibida)
    select c.id into v_any from public.collection c
    where exists (select 1 from public.collection_layout l where l.collection_id = c.id)
    order by c.id limit 1;

    -- 1) anon → 42501
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claims', '{"role":"anon"}', true);
    set local role anon;
    begin perform 1 from public.get_my_binder_value_groups(gen_random_uuid(), 10, 0); st := 'EXECUTOU';
    exception when others then st := sqlstate; end;
    reset role;
    r := r || jsonb_build_object('c3a_1_anon', st);

    -- 2) authenticated sem sub → 28000
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claims', '{"role":"authenticated"}', true);
    set local role authenticated;
    begin perform 1 from public.get_my_binder_value_groups(gen_random_uuid(), 10, 0); st := 'EXECUTOU';
    exception when others then st := sqlstate; end;
    reset role;
    r := r || jsonb_build_object('c3a_2_sem_sub', st);

    -- 3–7) identidade inexistente (uuid aleatório, sem conta)
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claims', json_build_object('sub', gen_random_uuid(), 'role', 'authenticated')::text, true);
    set local role authenticated;
    begin perform 1 from public.get_my_binder_value_groups(null, 10, 0); st := 'EXECUTOU';
    exception when others then st := sqlstate; end;
    r := r || jsonb_build_object('c3a_3_colecao_nula', st);
    begin perform 1 from public.get_my_binder_value_groups(gen_random_uuid(), 201, 0); st := 'EXECUTOU';
    exception when others then st := sqlstate; end;
    r := r || jsonb_build_object('c3a_4_limite_201', st);
    begin perform 1 from public.get_my_binder_value_groups(gen_random_uuid(), 10, -1); st := 'EXECUTOU';
    exception when others then st := sqlstate; end;
    r := r || jsonb_build_object('c3a_5_offset_negativo', st);
    begin perform 1 from public.get_my_binder_value_groups(gen_random_uuid(), 10, 0); st := 'EXECUTOU';
    exception when others then st := sqlstate; m_none := sqlerrm; end;
    r := r || jsonb_build_object('c3a_6_colecao_inexistente', st);
    if v_any is not null then
      begin perform 1 from public.get_my_binder_value_groups(v_any, 10, 0); st := 'EXECUTOU';
      exception when others then st := sqlstate; m_any := sqlerrm; end;
      r := r || jsonb_build_object('c3a_7_colecao_de_outro_titular', st,
                                   'c3a_7_mesma_mensagem', m_any is not distinct from m_none);
    else
      r := r || jsonb_build_object('c3a_7_colecao_de_outro_titular', 'NAO_EXECUTADO');
    end if;
    reset role;

    v_res := jsonb_build_object(
      'bloco', 'C3a', 'status', 'OK', 'resultados', r,
      'pass', r ->> 'c3a_1_anon' = '42501'
              and r ->> 'c3a_2_sem_sub' = '28000'
              and r ->> 'c3a_3_colecao_nula' = '22023'
              and r ->> 'c3a_4_limite_201' = '22023'
              and r ->> 'c3a_5_offset_negativo' = '22023'
              and r ->> 'c3a_6_colecao_inexistente' = 'P0002'
              and r ->> 'c3a_7_colecao_de_outro_titular' = 'P0002'
              and coalesce((r ->> 'c3a_7_mesma_mensagem')::boolean, false));
  end if;
  perform set_config('v3.res', v_res::text, true);
end;
$c3a$;
select current_setting('v3.res')::jsonb as resultado_c3a;
rollback;

-- C3b [GATE] positivo numa coleção do proprietário do produto, autorizada por ele
-- Executor: qualquer cliente que envie texto SQL (conector execute_sql do
-- Supabase, SQL Editor ou psql). Nenhuma variável de cliente é usada.
--
-- CHAMADA = PREFIXO (montado pelo executor, só na chamada) + este bloco, do
-- "do $c3b$" até o "rollback;" final, copiado SEM alteração.
-- PREFIXO — três linhas, exatamente nesta forma; os valores são uuids indicados
-- e autorizados pelo proprietário e NUNCA são gravados neste arquivo, no
-- docs/log.md nem nas evidências (colecao_convidada vazia quando não houver):
--   begin transaction isolation level repeatable read read only;
--   set local statement_timeout = '20s'; set local lock_timeout = '2s'; set local idle_in_transaction_session_timeout = '30s';
--   select set_config('v3.colecao_propria', '<uuid>', true), set_config('v3.colecao_convidada', '<uuid ou vazio>', true);
-- O terceiro argumento "true" é obrigatório (configuração local da transação).
--
-- Validação no bloco, ANTES de qualquer teste:
--   PREFIXO_INVALIDO  — transação não é READ ONLY/REPEATABLE READ ou os timeouts
--                       diferem de 20 s / 2 s / 30 s (ex.: prefixo esquecido);
--   PARAM_*           — parâmetro ausente, fora do formato uuid, coleção que não é
--                       proprietária de um fichário ou convidada de outro fichário.
-- PASS: status OK e "pass" TRUE. LIMITE_OFFSET = INCONCLUSIVO.
do $c3b$
declare
  re constant text := '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';
  v_raw_p text := btrim(coalesce(current_setting('v3.colecao_propria', true), ''));
  v_raw_g text := btrim(coalesce(current_setting('v3.colecao_convidada', true), ''));
  v_fn regprocedure := to_regprocedure('public.get_my_binder_value_groups(uuid,integer,integer)');
  v_col uuid; v_guest uuid; v_layout uuid; v_owner uuid;
  v_filled int; v_tc bigint; v_tcp bigint; v_totals_ok boolean := true;
  v_list50 text := ''; v_list200 text := ''; v_glist text := '';
  v_keys text[] := '{}'; v_bin jsonb := '{}'::jsonb; v_sum bigint := 0; v_rows bigint := 0; v_min_copies int;
  v_off int; v_n int; v_limit_hit boolean := false; r record;
  v_inv jsonb := '{}'::jsonb; v_inv_total bigint := 0; v_bad int; v_past_end int; v_err text; v_res jsonb;
begin
  if current_setting('transaction_read_only') <> 'on'
     or current_setting('transaction_isolation') <> 'repeatable read'
     or current_setting('statement_timeout') <> '20s'
     or current_setting('lock_timeout') <> '2s'
     or current_setting('idle_in_transaction_session_timeout') <> '30s' then
    v_res := jsonb_build_object('status', 'PREFIXO_INVALIDO');
  elsif v_fn is null then
    v_res := jsonb_build_object('status', 'FUNCAO_AUSENTE');
  elsif v_raw_p !~ re then
    v_res := jsonb_build_object('status', 'PARAM_PROPRIA_AUSENTE_OU_INVALIDO');
  elsif v_raw_g <> '' and v_raw_g !~ re then
    v_res := jsonb_build_object('status', 'PARAM_CONVIDADA_INVALIDO');
  else
    v_col := v_raw_p::uuid;
    v_guest := nullif(v_raw_g, '')::uuid;
    select l.id, oc.owner_user_id into v_layout, v_owner
    from public.collection_layout l join public.collection oc on oc.id = l.collection_id
    where l.collection_id = v_col;
    if v_layout is null then
      v_res := jsonb_build_object('status', 'PARAM_PROPRIA_SEM_FICHARIO');
    elsif v_guest is not null and not exists (
            select 1 from public.collection_layout_guest g where g.collection_id = v_guest and g.layout_id = v_layout) then
      v_res := jsonb_build_object('status', 'PARAM_CONVIDADA_NAO_E_DESTE_FICHARIO');
    else
      perform set_config('request.jwt.claim.sub', '', true);
      perform set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
      set local role authenticated;
      begin
        if auth.uid() is distinct from v_owner then
          raise exception using errcode = 'P0001', message = 'C3B_IDENTIDADE';
        end if;
        select b.filled_count into v_filled from public.get_my_collection_binder(v_col) b;

        -- páginas de 50: lista, chaves, soma, totais constantes
        v_off := 0;
        loop
          v_n := 0;
          for r in select g.card_variant_id, g.language_code, g.copies_count, g.total_count, g.total_copies
                   from public.get_my_binder_value_groups(v_col, 50, v_off) g loop
            v_n := v_n + 1; v_rows := v_rows + 1; v_sum := v_sum + r.copies_count;
            v_keys := v_keys || (r.card_variant_id::text || '|' || r.language_code);
            v_bin := v_bin || jsonb_build_object(r.card_variant_id::text || '|' || r.language_code, r.copies_count);
            v_list50 := v_list50 || r.card_variant_id::text || '|' || r.language_code || '|' || r.copies_count || ';';
            v_min_copies := least(coalesce(v_min_copies, r.copies_count), r.copies_count);
            if v_tc is null then v_tc := r.total_count; v_tcp := r.total_copies;
            elsif r.total_count <> v_tc or r.total_copies <> v_tcp then v_totals_ok := false; end if;
          end loop;
          exit when v_n < 50;
          if v_off + 50 > 10000 then v_limit_hit := true; exit; end if;
          v_off := v_off + 50;
        end loop;

        -- páginas de 200: mesma lista
        v_off := 0;
        loop
          v_n := 0;
          for r in select g.card_variant_id, g.language_code, g.copies_count
                   from public.get_my_binder_value_groups(v_col, 200, v_off) g loop
            v_n := v_n + 1;
            v_list200 := v_list200 || r.card_variant_id::text || '|' || r.language_code || '|' || r.copies_count || ';';
          end loop;
          exit when v_n < 200;
          if v_off + 200 > 10000 then v_limit_hit := true; exit; end if;
          v_off := v_off + 200;
        end loop;

        -- além do fim → vazio
        select count(*) into v_past_end
        from public.get_my_binder_value_groups(v_col, 10, least(coalesce(v_tc, 0), 10000)::integer);

        -- convidada (opcional): mesma lista pela coleção convidada
        if v_guest is not null then
          v_off := 0;
          loop
            v_n := 0;
            for r in select g.card_variant_id, g.language_code, g.copies_count
                     from public.get_my_binder_value_groups(v_guest, 200, v_off) g loop
              v_n := v_n + 1;
              v_glist := v_glist || r.card_variant_id::text || '|' || r.language_code || '|' || r.copies_count || ';';
            end loop;
            exit when v_n < 200;
            if v_off + 200 > 10000 then v_limit_hit := true; exit; end if;
            v_off := v_off + 200;
          end loop;
        end if;

        -- referência do Acervo: 5261 SEM filtro de coleção (inclui exemplares sem coleção)
        v_off := 0;
        loop
          v_n := 0;
          for r in select x.card_variant_id, x.language_code, x.copies_count, x.total_copies
                   from public.get_my_inventory_items(null, null, null, null, false, 'SET_NUMBER', 96, v_off, null, false) x loop
            v_n := v_n + 1;
            v_inv := v_inv || jsonb_build_object(r.card_variant_id::text || '|' || r.language_code, r.copies_count);
            v_inv_total := r.total_copies;
          end loop;
          exit when v_n < 96;
          if v_off + 96 > 100000 then v_limit_hit := true; exit; end if;
          v_off := v_off + 96;
        end loop;
        select count(*) into v_bad
        from jsonb_each_text(v_bin) b
        where coalesce((v_inv ->> b.key)::int, 0) < b.value::int;
      exception when others then
        v_err := sqlstate;
      end;
      reset role;

      if v_err is not null then
        v_res := jsonb_build_object('status', 'ERRO', 'sqlstate', v_err);
      else
        v_res := jsonb_build_object(
          'status', case when v_limit_hit then 'LIMITE_OFFSET' else 'OK' end,
          'fichario_vazio', v_tc is null,
          'c3b_1_soma_total_filled', (v_sum = coalesce(v_tcp, 0) and coalesce(v_tcp, 0) = v_filled),
          'c3b_2_linhas_total_count', v_rows = coalesce(v_tc, 0),
          'c3b_3_totais_constantes', v_totals_ok,
          'c3b_4_sem_grupo_repetido', (select count(*) = count(distinct k) from unnest(v_keys) k),
          'c3b_5_paginacao_50_igual_200', v_list50 = v_list200,
          'c3b_6_alem_do_fim_vazio', v_past_end = 0,
          'c3b_7_copias_positivas', coalesce(v_min_copies, 1) >= 1,
          'c3b_8_subconjunto_acervo', (v_bad = 0 and coalesce(v_tcp, 0) <= v_inv_total),
          'c3b_9_convidada_igual', case when v_guest is null then to_jsonb('NAO_EXECUTADO'::text)
                                         else to_jsonb(v_glist = v_list50) end);
      end if;
    end if;
  end if;
  v_res := jsonb_build_object('bloco', 'C3b') || v_res;
  v_res := v_res || jsonb_build_object('pass',
             v_res ->> 'status' = 'OK'
             and coalesce((v_res ->> 'c3b_1_soma_total_filled')::boolean, false)
             and coalesce((v_res ->> 'c3b_2_linhas_total_count')::boolean, false)
             and coalesce((v_res ->> 'c3b_3_totais_constantes')::boolean, false)
             and coalesce((v_res ->> 'c3b_4_sem_grupo_repetido')::boolean, false)
             and coalesce((v_res ->> 'c3b_5_paginacao_50_igual_200')::boolean, false)
             and coalesce((v_res ->> 'c3b_6_alem_do_fim_vazio')::boolean, false)
             and coalesce((v_res ->> 'c3b_7_copias_positivas')::boolean, false)
             and coalesce((v_res ->> 'c3b_8_subconjunto_acervo')::boolean, false)
             and coalesce(v_res ->> 'c3b_9_convidada_igual', 'NAO_EXECUTADO') in ('true', 'NAO_EXECUTADO'));
  perform set_config('v3.res', v_res::text, true);
end;
$c3b$;
select current_setting('v3.res')::jsonb as resultado_c3b;
rollback;

-- C3c [BLOQUEADO — AUTORIZAÇÃO EXPLÍCITA E INDEPENDENTE] todos os fichários,
-- lendo como cada titular; só contagens agregadas de divergência.
-- NÃO integra a autorização padrão de aplicação.
begin transaction isolation level repeatable read read only;
set local statement_timeout = '60s'; set local lock_timeout = '2s'; set local idle_in_transaction_session_timeout = '30s';
do $c3c$
declare
  r record; v_bad_total int := 0; v_bad_guest int := 0; v_bad_sum int := 0; v_checked int := 0;
  v_sum bigint; v_tcp bigint; v_tc bigint; v_list text; v_glist text; v_err text; v_res jsonb;
begin
  if to_regprocedure('public.get_my_binder_value_groups(uuid,integer,integer)') is null then
    v_res := jsonb_build_object('bloco', 'C3c', 'status', 'FUNCAO_AUSENTE', 'pass', false);
  else
    begin
      for r in
        select l.collection_id, oc.owner_user_id,
               (select count(a.id) from public.collection_layout_page p
                  join public.collection_layout_slot s on s.page_id = p.id
                  left join public.collection_layout_slot_assignment a on a.slot_id = s.id
                 where p.layout_id = l.id) as filled,
               (select g.collection_id from public.collection_layout_guest g where g.layout_id = l.id order by g.collection_id limit 1) as guest_id
        from public.collection_layout l
        join public.collection oc on oc.id = l.collection_id
      loop
        perform set_config('request.jwt.claim.sub', '', true);
        perform set_config('request.jwt.claims', json_build_object('sub', r.owner_user_id, 'role', 'authenticated')::text, true);
        set local role authenticated;
        select coalesce(sum(g.copies_count), 0), coalesce(max(g.total_copies), 0), coalesce(max(g.total_count), 0),
               string_agg(g.card_variant_id::text || '|' || g.language_code || '|' || g.copies_count, ';' order by ord)
          into v_sum, v_tcp, v_tc, v_list
        from public.get_my_binder_value_groups(r.collection_id, 200, 0) with ordinality g(card_variant_id, language_code, language_name, card_name, collector_number, collector_total, card_set_code, card_set_name, is_default_variant, variant_label, image_path, copies_count, total_count, total_copies, ord);
        v_glist := null;
        if r.guest_id is not null then
          select string_agg(g.card_variant_id::text || '|' || g.language_code || '|' || g.copies_count, ';' order by ord) into v_glist
          from public.get_my_binder_value_groups(r.guest_id, 200, 0) with ordinality g(card_variant_id, language_code, language_name, card_name, collector_number, collector_total, card_set_code, card_set_name, is_default_variant, variant_label, image_path, copies_count, total_count, total_copies, ord);
          if v_glist is distinct from v_list then v_bad_guest := v_bad_guest + 1; end if;
        end if;
        reset role;
        if v_tcp <> r.filled then v_bad_total := v_bad_total + 1; end if;
        if v_tc <= 200 and v_sum <> v_tcp then v_bad_sum := v_bad_sum + 1; end if;
        v_checked := v_checked + 1;
      end loop;
    exception when others then
      v_err := sqlstate;
    end;
    reset role;
    if v_err is not null then
      v_res := jsonb_build_object('bloco', 'C3c', 'status', 'ERRO', 'sqlstate', v_err, 'pass', false);
    else
      v_res := jsonb_build_object('bloco', 'C3c', 'status', 'OK',
                 'ficharios_verificados', v_checked,
                 'total_copies_diferente_de_filled', v_bad_total,
                 'soma_diferente_de_total_copies', v_bad_sum,
                 'convidada_diferente_da_proprietaria', v_bad_guest,
                 'pass', v_bad_total = 0 and v_bad_sum = 0 and v_bad_guest = 0);
    end if;
  end if;
  perform set_config('v3.res', v_res::text, true);
end;
$c3c$;
select current_setting('v3.res')::jsonb as resultado_c3c;
rollback;
