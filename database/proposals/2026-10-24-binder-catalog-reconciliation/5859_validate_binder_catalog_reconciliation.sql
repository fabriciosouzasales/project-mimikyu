/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5859 - Harness BINDER-CATALOG-RECONCILIATION (5263–5266)
Versão......: 1.4 (2026-10-24, A7-FINAL-CORRECTION-01: 79 checagens — gatilhos
              de marco imediatos com ended_xact (sem SET CONSTRAINTS); T.0/T.2
              com controles positivos; T.5 transferência para coleção que não
              era convidada, com participação anterior encerrada; M.4
              participantes × marcos ativos; D.3 removido (redundante com D.2
              no modelo novo)). Anterior 1.3 (2026-10-24, A7-CORRECTION-01: 78 checagens — marco de
              participação (0.6, M.1–M.3), transferência de propriedade com
              preservação dos marcos (T.0–T.4), desassociação/reassociação
              (D.1–D.3), falha durante a gravação W5 (6.11), permissões da
              tabela de marcos (11.6)). Anterior 1.2 (2026-10-24, W5-FOUNDATION-01: 64 checagens; W5.1 deixa de
              falhar por construção e passa a provar persistência e não
              reaparecimento; estrutura, integridade, autorização e cascata da
              tabela 5263 — 0.5, I.1–I.9, W5.2, 11.5). Anterior 1.1
              (AUDIT-CORRECTION-01): 52 checagens.
Status......: PROPOSTA — NÃO EXECUTADA. NUNCA executar no LIVE (cria
              usuários, catálogo sintético, coleções e fichários — desfeitos
              pela sentinela, mas proibido no LIVE por convenção). Execução
              só com autorização expressa de Fabrício, DEPOIS de
              5263 → 5264 → 5265 → 5266.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-24

Protocolo (o mesmo da 5853/5857): um único statement, usuários efêmeros A e
B; a sentinela MS859 desfaz tudo; 99.1 prova resíduo zero.

  select * from pg_temp.wh_5859_validate();

Pré-requisitos de catálogo: jogo POKEMON; idioma pt-BR; acabamentos
STANDARD, HOLO, REVERSE_HOLO; Pokédex NATIONAL com GENERATION_VI (fichário
Pokédex da seção 2, mesma carga canônica das 6030–6051).

Fixture (RPCs canônicas; catálogo, exemplares e mesclagem de teste inseridos
com privilégio, como nas 5853/5857):
  Set RC, cartas 1–9 "antigas" (created_at = now() − 2 dias):
    STANDARD em 1–8; REVERSE_HOLO em 1, 2, 4, 5, 7, 8; HOLO só na 9.
  A — local BIN (Fichário): CM = coleção do Set RC, Master Set
      {STANDARD, HOLO, REVERSE_HOLO}; exemplares 5-STANDARD e 8-REVERSE
      guardados em BIN; fichário 3×3 → 15 posições, 2 páginas, 18 bolsos.
      Ajustes do usuário (iguais ao caso real): Inserir Espaço antes da 4
      (bolso 6 livre, como 13·1·3 da Chi-Yu); reserva da 2-REVERSE liberada
      (bolso 4, como a Chi-Yu Holo); convidada CG (Set RG, Master Set
      {STANDARD}) com reserva no bolso 17.
      Novidades (created_at = now() + 1 min): 3-REVERSE, 4-HOLO, 6-REVERSE.
      Estado inicial por bolso (ordem de leitura):
        1 1S · 2 1R · 3 2S · 4 — · 5 3S · 6 — · 7 4S · 8 4R · 9 5S* · 10 5R ·
        11 6S · 12 7S · 13 7R · 14 8S · 15 8R* · 16 9H · 17 G · 18 —   (*=carta)
  A — local BIN_P: CP = Pokédex GENERATION_VI com fichário 4×4; CH =
      coleção Master Set do Set RG convidada nesse fichário.
  B — local LB: CB = Set RB (base 521: cartas 1–520 STANDARD + 521 HOLO;
      secretas 522 e 523 só com um acabamento fora do objetivo → posições
      genéricas "carta:*"; tudo antigo), Master Set {STANDARD, HOLO}, fichário
      3×3 (59 páginas, 531 bolsos, 523 posições). Novidades: HOLO nas cartas
      1–102; 522 ganha HOLO (genérica → 1 acabamento); 523 ganha STANDARD e
      HOLO (genérica → 2 acabamentos). Total: 105 novidades.
  Depois da aplicação principal (seção 10): RG 2 (novidade da convidada),
      7-HOLO com exemplar colocado no bolso 1·2·1 (fora da ordem), 8-HOLO e
      9-REVERSE (seleção parcial e W5).

Seções (ordem de execução):
  0  estrutura e ACL
  1  equivalência da ordem com o planejamento original (CM e CB, 626 posições)
  2  detecção: novidades, regra 5, convidada, exclusão da Pokédex
  3  isolamento por usuário
  4  prévias (caso real Chi-Yu, mudança de página, página nova, última posição);
     4.6 W1: mesmo token em 3 combinações de TimeZone/DateStyle
  5  travamento e mesclagem (sem alteração parcial)
  6  token, confirmações; 6.10 falha provocada APÓS escritas parciais (gatilho
     de teste) → rollback total; aplicação em fuso diferente da prévia;
     resultado; idempotência; regra 5
  7  limites (itens e linhas); 7.4 W2: aplicação com >100 novidades
  9  W3: reserva genérica → específica (inequívoca: UPGRADE; ambígua: revisão)
  10 aplicação por convidada; W6 carta fora da ordem; seleção parcialmente
     aplicada; W5.1/W5.2 incorporada e liberada não reaparece
  11 argumentos inválidos, SELECTION_INVALID, anon, isolamento na convidada;
     11.5 tabela 5263 inacessível a authenticated/anon
  8  convidada arquivada; fichário com referências de espécie
  I  registro W5 (5263), intercalado onde o estado é observável:
     I.1 nada registrado por prévias, BLOCKED, PLAN_CHANGED, falta de
         confirmação e falha após escrita parcial (6.10);
     I.2 aplicação registra exatamente as 3 chaves, coleção real;
     I.9 integridade: CHECK de formato, PK, FKs;
     I.3 repetição não regrava (incorporated_at intacto);
     I.4 OVER_LIMIT não registra; I.5 UPGRADE registra, NEEDS_REVIEW não;
     I.6 convidada registra com a própria coleção; I.7 seleção parcial e
         W6 (só o aplicado é registrado);
     I.8 desmontagem do fichário B apaga o registro por cascata
  M  marco de participação (5263, A7): M.1 gatilhos de criação/associação
     preenchem os marcos da fixture; M.2 integridade (CHECK, PK, FK);
     M.3 sem marco → MARKER_MISSING (fail-closed)
  6.11 falha DURANTE a gravação W5 (gatilho de teste na tabela de
     incorporações) → rollback integral (reservas, deslocamentos, página)
  T  transferência CM → CG e volta: marcos preservados (T.1/T.4); reserva
     manual liberada de posição anterior à entrada da convidada não volta
     como novidade para a nova dona, com controle positivo (RG 4 nascida
     depois da entrada de CG aparece) (T.0/T.2); novidade ainda não
     incorporada da antiga dona continua detectável (T.3); transferência
     para CX, que não era convidada e tem participação anterior ENCERRADA
     em outra transação: marco novo, nada revive (T.5). Todos os gatilhos
     da 5263 são imediatos: T.1/T.4/T.5 já são o cenário "gatilhos
     antecipados" (não há gatilho diferido a antecipar; 0.6 prova).
  D  desassociação e reassociação da convidada CH: participação encerrada
     (ended_xact) sem marco ativo (D.1), marco novo na reassociação (D.2 —
     mesma regra em transação igual ou diferente: último papel GUEST)
  M.4 participantes × marcos ativos nos fichários da fixture, depois de T e D
  11.6 tabela de marcos inacessível a authenticated/anon
  99 resíduo zero (16 tabelas, incluindo as 2 da 5263)

Limitações declaradas:
  L1 SET LOCAL ROLE prova o banco, não o JWT do PostgREST.
  L2 Concorrência real (duas sessões) não é exercitada aqui. Prova
     equivalente: 6.2 (mudança entre prévia e execução → PLAN_CHANGED; volta
     ao estado → mesmo token). Protocolo manual de duas sessões no README §6.
  L3 Imagem de bolso no meio da cadeia não é exercitada (o deslocamento usa
     binder_gap_move_pocket da 5243 sem alteração; homologado na 5243).
  L4 RESERVE_PLACED (exemplar já no bolso natural) não tem fixture positiva;
     o caminho negativo (W6, fora da ordem) é coberto por 10.2/10.3.
  L5 SPECIES_REFERENCES_PRESENT com dona não-Pokédex é inalcançável pelo
     gatilho da 5257 (referência exige dona Pokédex); 8.2 cobre o caso real.
  L6 6.10/6.11 criam/removem gatilhos de teste em public (DDL desfeita pela sentinela).
  L7 Histórico simulado: dentro de uma transação todo now() é igual, então
     T e D ajustam com privilégio collection_layout.created_at e marker_at
     para datas passadas (fichário −1 dia; entrada da convidada −2 h; CH −3 h)
     e criam catálogo com created_at entre elas. É a forma de exercitar
     janelas de tempo sem esperar; os gatilhos da 5263 são exercitados pelas
     RPCs canônicas (criação, associação, desassociação, transferência).
  L8 (rev. 1.4) Sem gatilhos diferidos na 5263: nada a antecipar. "Outra
     transação" só importa para linhas de DONA encerradas (B2/B3 comparam
     ended_xact com pg_current_xact_id()); T.5 simula a participação
     anterior encerrada gravando com privilégio ended_xact = '1' (xid8 que
     nunca é o da transação do harness) — fixture, não resultado.
================================================================
*/

create or replace function pg_temp.wh_5859_labels(p_layout uuid, p_guest uuid)
returns text
language sql
stable
as $$
  select string_agg(
           case when e.slot_id is null then '-'
                else (case when e.collection_id = p_guest then 'G' else '' end)
                     || c.collector_number::text || coalesce(t.code::text, '*') end,
           ',' order by p.page_number, s.row_index, s.column_index)
  from public.collection_layout_slot s
  join public.collection_layout_page p on p.id = s.page_id
  left join public.collection_layout_slot_expected_content e on e.slot_id = s.id
  left join public.card c on c.id = e.card_id
  left join public.card_variant_type t on t.id = e.expected_variant_type_id
  where p.layout_id = p_layout
$$;

create or replace function pg_temp.wh_5859_sig(p_layout uuid)
returns text
language sql
stable
as $$
  select md5(coalesce(string_agg(
           concat_ws(':', p.page_number, s.row_index, s.column_index, s.locked,
                     coalesce(a.id::text, '-'), coalesce(a.physical_card_id::text, '-'),
                     coalesce(e.card_id::text, '-'), coalesce(e.expected_variant_type_id::text, '-'),
                     coalesce(e.collection_id::text, '-'), coalesce(i.storage_path, '-')),
           '|' order by p.page_number, s.row_index, s.column_index), ''))
         || ':' || (select count(*) from public.collection_layout_page p2 where p2.layout_id = p_layout)::text
  from public.collection_layout_slot s
  join public.collection_layout_page p on p.id = s.page_id
  left join public.collection_layout_slot_assignment a on a.slot_id = s.id
  left join public.collection_layout_slot_expected_content e on e.slot_id = s.id
  left join public.collection_layout_slot_image i on i.slot_id = s.id
  where p.layout_id = p_layout
$$;

create or replace function pg_temp.wh_5859_validate()
returns table (seq integer, check_id text, status text, detail text)
language plpgsql
volatile
as $fn$
#variable_conflict use_column
declare
  f_ctx  oid := to_regprocedure('public.binder_catalog_context(uuid)');
  f_ass  oid := to_regprocedure('public.binder_catalog_assert_eligible(uuid)');
  f_pos  oid := to_regprocedure('public.binder_catalog_positions(uuid, uuid[])');
  f_nov  oid := to_regprocedure('public.binder_catalog_novelties(uuid)');
  f_pl   oid := to_regprocedure('public.binder_catalog_plan(uuid, text[])');
  f_get  oid := to_regprocedure('public.get_my_binder_catalog_novelties(uuid)');
  f_prev oid := to_regprocedure('public.preview_my_binder_catalog_reconciliation(uuid, text[])');
  f_app  oid := to_regprocedure('public.apply_my_binder_catalog_reconciliation(uuid, text[], text, boolean, boolean)');
  t_inc  oid := to_regclass('public.collection_layout_catalog_incorporation');
  t_mk   oid := to_regclass('public.collection_layout_catalog_marker');
  v_t0 timestamptz; v_tg timestamptz; v_tch timestamptz; v_born3 timestamptz; v_old5 timestamptz;
  g3 uuid; g4 uuid; kg3 text; kg4 text; k1h text; sl_t uuid; v_dtok2 text; v_cx uuid; n3 integer;
  v_inc text; v_inc2 text; v_dtok text;
  u_a uuid := gen_random_uuid();
  u_b uuid := gen_random_uuid();
  v_sfx text := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
  v_old timestamptz := now() - interval '2 days';
  v_new timestamptz := now() + interval '1 minute';
  v_game uuid; v_pt uuid; v_rar uuid; v_cat uuid; v_std uuid; v_holo uuid; v_rev uuid;
  v_exp uuid; s_rc uuid; s_rg uuid; s_rb uuid;
  kc uuid[] := '{}'; g1 uuid; kb1 uuid;
  v_inv_a uuid; f5 uuid; f8 uuid;
  v_bin uuid; v_binp uuid; v_lb uuid;
  v_cm uuid; v_cg uuid; v_cp uuid; v_ch uuid; v_cb uuid;
  l_m uuid; l_p uuid; l_b uuid; v_reg uuid; v_pg uuid;
  sl_gap uuid; sl_clr uuid; sl_g17 uuid; sl_lock uuid;
  v_oth uuid; kb522 uuid; kb523 uuid; g2 uuid; f7h uuid;
  k522h text; k523s text; k523h text; kg2 text; k7h text; k8h text; k9r text;
  v_tz1 text; v_tz2 text; v_tz3 text; v_tok_a text; v_tok_b text; v_md5sr text;
  k3r text; k4h text; k6r text; kb1h text;
  v_tok text; v_tok2 text; v_lab text; v_sig text; v_sig2 text; v_asg text; v_asg2 text;
  p record; h record; w record; o record;
  v_ok boolean; v_err text; v_err2 text; v_err3 text; v_hint text; n integer; n2 integer;
  b_counts bigint[]; e_counts bigint[];
  res jsonb := '[]'::jsonb; r jsonb; cnt integer := 0; passes integer := 0;
  v_expected integer := 79;
  i integer;
  c_init text := '1STANDARD,1REVERSE_HOLO,2STANDARD,-,3STANDARD,-,4STANDARD,4REVERSE_HOLO,5STANDARD,5REVERSE_HOLO,6STANDARD,7STANDARD,7REVERSE_HOLO,8STANDARD,8REVERSE_HOLO,9HOLO,G1STANDARD,-';
  c_final text := '1STANDARD,1REVERSE_HOLO,2STANDARD,-,3STANDARD,3REVERSE_HOLO,4STANDARD,4HOLO,4REVERSE_HOLO,5STANDARD,5REVERSE_HOLO,6STANDARD,6REVERSE_HOLO,7STANDARD,7REVERSE_HOLO,8STANDARD,8REVERSE_HOLO,9HOLO,G1STANDARD,-,-,-,-,-,-,-,-';
begin
  -- 0. Estrutura ------------------------------------------------------------------------------------
  res := res || jsonb_build_object('id','0.1','ok',
    f_ctx is not null and f_ass is not null and f_pos is not null and f_nov is not null and f_pl is not null
    and f_get is not null and f_prev is not null and f_app is not null and t_inc is not null and t_mk is not null,
    'detail','5263–5266 presentes: tabelas de incorporações e de marcos + 5 internas + 3 RPCs');
  if (res -> 0 ->> 'ok')::boolean is not true then
    res := res || jsonb_build_object('id','X.0','ok', false, 'detail','aplique 5263 → 5264 → 5265 → 5266 antes deste harness');
  else
  res := res || jsonb_build_object('id','0.2','ok',
    (select bool_and(q.prosecdef and q.proconfig @> array['search_path=""']
                     and has_function_privilege('authenticated', q.oid, 'EXECUTE')
                     and not has_function_privilege('anon', q.oid, 'EXECUTE'))
     from pg_proc q where q.oid in (f_get, f_prev, f_app))
    and not exists (select 1 from pg_proc q, aclexplode(q.proacl) x where q.oid in (f_get, f_prev, f_app) and x.grantee = 0)
    and (select q.proconfig @> array['lock_timeout=5s'] and q.provolatile = 'v' from pg_proc q where q.oid = f_app)
    and (select bool_and(q.provolatile = 's') from pg_proc q where q.oid in (f_get, f_prev)),
    'detail','RPCs: SECURITY DEFINER, search_path vazio, EXECUTE só authenticated (sem PUBLIC); leituras STABLE; aplicação VOLATILE com lock_timeout 5s');
  res := res || jsonb_build_object('id','0.3','ok',
    (select bool_and(q.prosecdef and q.proconfig @> array['search_path=""']
                     and not has_function_privilege('authenticated', q.oid, 'EXECUTE')
                     and not has_function_privilege('anon', q.oid, 'EXECUTE')
                     and not has_function_privilege('service_role', q.oid, 'EXECUTE'))
     from pg_proc q where q.oid in (f_ctx, f_ass, f_pos, f_nov, f_pl)),
    'detail','internas: SECURITY DEFINER, search_path vazio, sem EXECUTE para authenticated/anon/service_role');
  res := res || jsonb_build_object('id','0.4','ok',
    (select q.prosrc ~ 'c_row_limit\s+constant integer := 500' and q.prosrc ~ 'c_item_limit\s+constant integer := 100'
     from pg_proc q where q.oid = f_pl)
    and (select q.prosrc like '%^rc1:[0-9a-f]{64}$%' from pg_proc q where q.oid = f_app),
    'detail','limites 500 linhas movidas / 100 itens no plano; formato de token rc1 na aplicação');
  res := res || jsonb_build_object('id','0.5','ok',
    (select c.relrowsecurity from pg_class c where c.oid = t_inc)
    and not exists (select 1 from pg_policy pol where pol.polrelid = t_inc)
    and not exists (select 1 from pg_class c, aclexplode(c.relacl) x where c.oid = t_inc and x.grantee = 0)
    and not has_table_privilege('authenticated', t_inc, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
    and not has_table_privilege('anon', t_inc, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
    and not has_table_privilege('service_role', t_inc, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
    and (select array_agg(a.attname::text order by x.ord)
         from pg_constraint k cross join unnest(k.conkey) with ordinality x(attnum, ord)
         join pg_attribute a on a.attrelid = k.conrelid and a.attnum = x.attnum
         where k.conrelid = t_inc and k.contype = 'p') = array['layout_id', 'collection_id', 'item_key']
    and (select count(*) = 2 and bool_and(k.confdeltype = 'c')
                and bool_or(k.confrelid = 'public.collection_layout'::regclass)
                and bool_or(k.confrelid = 'public.collection'::regclass)
         from pg_constraint k where k.conrelid = t_inc and k.contype = 'f')
    and exists (select 1 from pg_constraint k where k.conrelid = t_inc and k.contype = 'c')
    and not exists (select 1 from pg_trigger tg where tg.tgrelid = t_inc and not tg.tgisinternal),
    'detail','5263: RLS ligada, sem políticas, sem gatilhos próprios, nenhum privilégio para PUBLIC/anon/authenticated/service_role; PK (fichário, coleção, chave); FKs fichário e coleção ON DELETE CASCADE; CHECK de formato');
  res := res || jsonb_build_object('id','0.6','ok',
    (select c.relrowsecurity from pg_class c where c.oid = t_mk)
    and not exists (select 1 from pg_policy pol where pol.polrelid = t_mk)
    and not exists (select 1 from pg_class c, aclexplode(c.relacl) x where c.oid = t_mk and x.grantee = 0)
    and not has_table_privilege('authenticated', t_mk, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
    and not has_table_privilege('anon', t_mk, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
    and not has_table_privilege('service_role', t_mk, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
    and (select array_agg(a.attname::text order by x.ord)
         from pg_constraint k cross join unnest(k.conkey) with ordinality x(attnum, ord)
         join pg_attribute a on a.attrelid = k.conrelid and a.attnum = x.attnum
         where k.conrelid = t_mk and k.contype = 'p') = array['layout_id', 'collection_id']
    and (select count(*) = 2 and bool_and(k.confdeltype = 'c')
                and bool_or(k.confrelid = 'public.collection_layout'::regclass)
                and bool_or(k.confrelid = 'public.collection'::regclass)
         from pg_constraint k where k.conrelid = t_mk and k.contype = 'f')
    and (select count(*) from pg_constraint k where k.conrelid = t_mk and k.contype = 'c') = 2
    and (select count(*) from pg_trigger tg where tg.tgname like 'trg\_cl\_catalog\_marker\_%' and not tg.tgisinternal) = 5
    and not exists (select 1 from pg_trigger tg where tg.tgname like 'trg\_cl\_catalog\_marker\_%'
                    and (tg.tgdeferrable or tg.tginitdeferred or tg.tgconstraint <> 0))
    and exists (select 1 from pg_attribute a where a.attrelid = t_mk and a.attname = 'ended_xact'
                and a.atttypid = 'xid8'::regtype and not a.attnotnull)
    and (select bool_and(q.prosecdef and q.proconfig @> array['search_path=""']
                         and not has_function_privilege('authenticated', q.oid, 'EXECUTE')
                         and not has_function_privilege('anon', q.oid, 'EXECUTE')
                         and not has_function_privilege('service_role', q.oid, 'EXECUTE'))
         from pg_proc q where q.pronamespace = 'public'::regnamespace and q.proname like 'binder\_catalog\_marker\_%')
    and (select count(*) from pg_proc q where q.pronamespace = 'public'::regnamespace and q.proname like 'binder\_catalog\_marker\_%') = 4,
    'detail','5263 marcos: RLS sem políticas, sem privilégio para PUBLIC/anon/authenticated/service_role; PK (fichário, coleção); FKs CASCADE; 2 CHECKs; 5 gatilhos AFTER imediatos (nenhum diferido ou de restrição); coluna ended_xact (xid8, nula); 4 funções de gatilho SECURITY DEFINER sem EXECUTE para clientes');

  select array[(select count(*) from auth.users), (select count(*) from public.collection),
               (select count(*) from public.collection_allocation), (select count(*) from public.physical_card),
               (select count(*) from public.storage_container), (select count(*) from public.collection_layout),
               (select count(*) from public.collection_layout_page), (select count(*) from public.collection_layout_slot),
               (select count(*) from public.collection_layout_slot_assignment),
               (select count(*) from public.collection_layout_slot_expected_content),
               (select count(*) from public.collection_layout_region),
               (select count(*) from public.collection_layout_slot_species_reference),
               (select count(*) from public.collection_layout_catalog_incorporation),
               (select count(*) from public.collection_layout_catalog_marker),
               (select count(*) from public.card), (select count(*) from public.card_variant)]
    into b_counts;

  begin
    -- F. Catálogo sintético e usuários -------------------------------------------------------------
    select g.id into v_game from public.game g where g.code = 'POKEMON';
    select l.id into v_pt from public.language l where l.code = 'pt-BR';
    select t.id into v_std  from public.card_variant_type t where t.game_id = v_game and t.code = 'STANDARD';
    select t.id into v_holo from public.card_variant_type t where t.game_id = v_game and t.code = 'HOLO';
    select t.id into v_rev  from public.card_variant_type t where t.game_id = v_game and t.code = 'REVERSE_HOLO';
    select c0.rarity_id, c0.category_id into v_rar, v_cat
    from public.card c0 join public.card_set cs0 on cs0.id = c0.card_set_id
    join public.expansion e0 on e0.id = cs0.expansion_id
    where e0.game_id = v_game limit 1;
    if v_game is null or v_pt is null or v_std is null or v_holo is null or v_rev is null or v_rar is null
       or not exists (select 1 from public.card_variant_type t where t.game_id = v_game and t.is_active
                      and t.code not in ('STANDARD', 'HOLO', 'REVERSE_HOLO'))
       or not exists (select 1 from public.pokemon_generation g where g.code = 'GENERATION_VI') then
      res := res || jsonb_build_object('id','F.0','ok', false, 'detail','pré-requisitos de catálogo ausentes');
      raise exception 'MS859' using errcode = 'P0001';
    end if;
    insert into public.expansion (game_id, code, name, release_order)
    values (v_game, 'BCR_' || v_sfx, 'BCR Harness ' || v_sfx,
            (select coalesce(max(x.release_order), 0) + 1000 from public.expansion x where x.game_id = v_game))
    returning id into v_exp;
    insert into public.card_set (expansion_id, code, name, set_type, release_order, base_set_size, total_set_size)
    values (v_exp, 'RC' || v_sfx, 'RC ' || v_sfx, 'REGULAR', 1, 9, 9) returning id into s_rc;
    insert into public.card_set (expansion_id, code, name, set_type, release_order, base_set_size, total_set_size)
    values (v_exp, 'RG' || v_sfx, 'RG ' || v_sfx, 'REGULAR', 2, 1, 1) returning id into s_rg;
    insert into public.card_set (expansion_id, code, name, set_type, release_order, base_set_size, total_set_size)
    values (v_exp, 'RB' || v_sfx, 'RB ' || v_sfx, 'REGULAR', 3, 521, 523) returning id into s_rb;
    -- acabamento fora do objetivo de CB (para as secretas genéricas 522/523)
    select t.id into v_oth from public.card_variant_type t
    where t.game_id = v_game and t.is_active and t.code not in ('STANDARD', 'HOLO', 'REVERSE_HOLO')
    order by t.display_order, t.code limit 1;

    for i in 1 .. 9 loop
      insert into public.card (card_set_id, rarity_id, category_id, collector_number, collector_order, name, is_active, created_at)
      values (s_rc, v_rar, v_cat, i::text, i, 'RC ' || i, true, v_old) returning id into kb1;
      kc := kc || kb1;
      if i <= 8 then
        insert into public.card_variant (card_id, variant_type_id, variant_order, is_default, created_at)
        values (kb1, v_std, 1, true, v_old);
      end if;
      if i in (1, 2, 4, 5, 7, 8) then
        insert into public.card_variant (card_id, variant_type_id, variant_order, is_default, created_at)
        values (kb1, v_rev, 3, false, v_old);
      end if;
      if i = 9 then
        insert into public.card_variant (card_id, variant_type_id, variant_order, is_default, created_at)
        values (kb1, v_holo, 2, true, v_old);
      end if;
    end loop;
    insert into public.card (card_set_id, rarity_id, category_id, collector_number, collector_order, name, is_active, created_at)
    values (s_rg, v_rar, v_cat, '1', 1, 'RG 1', true, v_old) returning id into g1;
    insert into public.card_variant (card_id, variant_type_id, variant_order, is_default, created_at)
    values (g1, v_std, 1, true, v_old);
    with c as (
      insert into public.card (card_set_id, rarity_id, category_id, collector_number, collector_order, name, is_active, created_at)
      select s_rb, v_rar, v_cat, g::text, g, 'RB ' || g, true, v_old from generate_series(1, 521) g
      returning id, collector_order
    )
    insert into public.card_variant (card_id, variant_type_id, variant_order, is_default, created_at)
    select c.id, case when c.collector_order = 521 then v_holo else v_std end, 1, true, v_old from c;
    select c.id into kb1 from public.card c where c.card_set_id = s_rb and c.collector_order = 1;
    -- Secretas 522 e 523 (> base 521) só com acabamento fora do objetivo → posição genérica "carta:*"
    insert into public.card (card_set_id, rarity_id, category_id, collector_number, collector_order, name, is_active, created_at)
    values (s_rb, v_rar, v_cat, '522', 522, 'RB 522', true, v_old) returning id into kb522;
    insert into public.card (card_set_id, rarity_id, category_id, collector_number, collector_order, name, is_active, created_at)
    values (s_rb, v_rar, v_cat, '523', 523, 'RB 523', true, v_old) returning id into kb523;
    insert into public.card_variant (card_id, variant_type_id, variant_order, is_default, created_at)
    values (kb522, v_oth, 1, true, v_old), (kb523, v_oth, 1, true, v_old);

    insert into auth.users (id, aud, role, email, raw_user_meta_data, created_at, updated_at)
    values (u_a, 'authenticated', 'authenticated', 'wh5859-a-'||lower(v_sfx)||'@example.invalid',
            jsonb_build_object('username', 'wh5859a_'||lower(v_sfx), 'display_name', 'WH 5859 A'), now(), now()),
           (u_b, 'authenticated', 'authenticated', 'wh5859-b-'||lower(v_sfx)||'@example.invalid',
            jsonb_build_object('username', 'wh5859b_'||lower(v_sfx), 'display_name', 'WH 5859 B'), now(), now());
    select i0.id into v_inv_a from public.inventory i0 where i0.owner_user_id = u_a;

    -- A: locais
    perform set_config('request.jwt.claim.sub', u_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    select x.storage_container_id into v_bin  from public.create_my_storage_container(gen_random_uuid(), 'BIN 5859', 'BINDER') x;
    select x.storage_container_id into v_binp from public.create_my_storage_container(gen_random_uuid(), 'BINP 5859', 'BINDER') x;
    execute 'reset role';

    -- Exemplares guardados no fichário físico (como nas 5853/5857)
    insert into public.physical_card (card_variant_id, language_id, inventory_id, storage_container_id)
    select cv.id, v_pt, v_inv_a, v_bin from public.card_variant cv where cv.card_id = kc[5] and cv.variant_type_id = v_std
    returning id into f5;
    insert into public.physical_card (card_variant_id, language_id, inventory_id, storage_container_id)
    select cv.id, v_pt, v_inv_a, v_bin from public.card_variant cv where cv.card_id = kc[8] and cv.variant_type_id = v_rev
    returning id into f8;

    execute 'set local role authenticated';
    select x.collection_id into v_cm from public.create_my_card_set_collection(gen_random_uuid(), s_rc, 'CM 5859', v_bin) x;
    perform count(*) from public.allocate_physical_cards_to_collection(v_cm, array[f5, f8]);
    perform count(*) from public.set_collection_completion_policy_to_master_set(v_cm, array[v_std, v_holo, v_rev]);
    select * into p from public.preview_my_collection_binder(v_cm, 3, 3, 'PRINCIPAL_ONLY');
    perform count(*) from public.create_my_collection_binder(v_cm, 3, 3, 'PRINCIPAL_ONLY', p.plan_token);
    execute 'reset role';
    select l.id into l_m from public.collection_layout l where l.collection_id = v_cm;

    -- Ids dos bolsos usados nos ajustes, lidos com privilégio (as leituras diretas
    -- de tabela não dependem das políticas do cliente).
    select s.id into sl_gap from public.collection_layout_slot s join public.collection_layout_page pg on pg.id = s.page_id
    where pg.layout_id = l_m and pg.page_number = 1 and s.row_index = 2 and s.column_index = 3;
    select s.id into sl_clr from public.collection_layout_slot s join public.collection_layout_page pg on pg.id = s.page_id
    where pg.layout_id = l_m and pg.page_number = 1 and s.row_index = 2 and s.column_index = 1;
    select s.id into sl_g17 from public.collection_layout_slot s join public.collection_layout_page pg on pg.id = s.page_id
    where pg.layout_id = l_m and pg.page_number = 2 and s.row_index = 3 and s.column_index = 2;
    select s.id into sl_lock from public.collection_layout_slot s join public.collection_layout_page pg on pg.id = s.page_id
    where pg.layout_id = l_m and pg.page_number = 2 and s.row_index = 2 and s.column_index = 1;

    -- Ajustes do usuário: Inserir Espaço antes da 4-STANDARD (bolso 6); liberar a reserva da 2-REVERSE (bolso 4)
    execute 'set local role authenticated';
    select * into p from public.preview_my_binder_insert_gap(v_cm, sl_gap);
    perform count(*) from public.insert_my_binder_gap(v_cm, sl_gap, p.plan_token, true, false);
    perform public.clear_slot_expected_content(array[sl_clr]);
    -- Convidada CG no mesmo fichário, com reserva no bolso 17 (p2 r3 c2)
    select x.collection_id into v_cg from public.create_my_card_set_collection(gen_random_uuid(), s_rg, 'CG 5859', v_bin) x;
    perform count(*) from public.set_collection_completion_policy_to_master_set(v_cg, array[v_std]);
    perform count(*) from public.attach_my_collection_to_binder(v_cg, l_m);
    perform count(*) from public.set_slot_expected_content(sl_g17, g1, null, v_std, v_cg);
    -- Pokédex: CP com fichário próprio; CH (Master Set) convidada nele
    select x.collection_id into v_cp from public.create_my_pokedex_collection(gen_random_uuid(), 'CP 5859', array['GENERATION_VI'], v_binp) x;
    select * into p from public.preview_my_collection_binder(v_cp, 4, 4, 'PRINCIPAL_ONLY');
    perform count(*) from public.create_my_collection_binder(v_cp, 4, 4, 'PRINCIPAL_ONLY', p.plan_token);
    select x.collection_id into v_ch from public.create_my_card_set_collection(gen_random_uuid(), s_rg, 'CH 5859', v_binp) x;
    perform count(*) from public.set_collection_completion_policy_to_master_set(v_ch, array[v_std]);
    execute 'reset role';
    select l.id into l_p from public.collection_layout l where l.collection_id = v_cp;
    execute 'set local role authenticated';
    perform count(*) from public.attach_my_collection_to_binder(v_ch, l_p);
    execute 'reset role';

    -- B: Set RB com fichário 2×2
    perform set_config('request.jwt.claim.sub', u_b::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    select x.storage_container_id into v_lb from public.create_my_storage_container(gen_random_uuid(), 'LB 5859', 'BINDER') x;
    select x.collection_id into v_cb from public.create_my_card_set_collection(gen_random_uuid(), s_rb, 'CB 5859', v_lb) x;
    perform count(*) from public.set_collection_completion_policy_to_master_set(v_cb, array[v_std, v_holo]);
    select * into p from public.preview_my_collection_binder(v_cb, 3, 3, 'PRINCIPAL_ONLY');
    perform count(*) from public.create_my_collection_binder(v_cb, 3, 3, 'PRINCIPAL_ONLY', p.plan_token);
    execute 'reset role';
    select l.id into l_b from public.collection_layout l where l.collection_id = v_cb;

    -- Novidades do Catálogo (depois da montagem e da associação)
    insert into public.card_variant (card_id, variant_type_id, variant_order, is_default, created_at)
    values (kc[3], v_rev, 3, false, v_new), (kc[4], v_holo, 2, false, v_new), (kc[6], v_rev, 3, false, v_new);
    insert into public.card_variant (card_id, variant_type_id, variant_order, is_default, created_at)
    select c.id, v_holo, 2, false, v_new from public.card c where c.card_set_id = s_rb and c.collector_order between 1 and 102;
    insert into public.card_variant (card_id, variant_type_id, variant_order, is_default, created_at)
    values (kb522, v_holo, 2, false, v_new),                                   -- 522: genérica → HOLO (inequívoca)
           (kb523, v_std, 2, false, v_new), (kb523, v_holo, 3, false, v_new); -- 523: genérica → 2 acabamentos (ambígua)
    k522h := kb522::text || ':' || v_holo::text;
    k523s := kb523::text || ':' || v_std::text;
    k523h := kb523::text || ':' || v_holo::text;
    k3r := kc[3]::text || ':' || v_rev::text;
    k4h := kc[4]::text || ':' || v_holo::text;
    k6r := kc[6]::text || ':' || v_rev::text;
    kb1h := kb1::text || ':' || v_holo::text;

    v_lab := pg_temp.wh_5859_labels(l_m, v_cg);
    select string_agg(x.k, ',' order by x.k) into v_asg
    from (select a.id::text || '@' || a.physical_card_id::text as k
          from public.collection_layout_slot_assignment a
          join public.collection_layout_slot s on s.id = a.slot_id
          join public.collection_layout_page pg on pg.id = s.page_id where pg.layout_id = l_m) x;
    res := res || jsonb_build_object('id','F.1','ok', v_lab = c_init
      and (select count(*) from public.collection_layout_slot s join public.collection_layout_page pg on pg.id = s.page_id
           where pg.layout_id = l_m) = 18
      and (select count(*) from public.collection_layout_slot_assignment a join public.collection_layout_slot s on s.id = a.slot_id
           join public.collection_layout_page pg on pg.id = s.page_id where pg.layout_id = l_m) = 2
      and (select count(*) from public.collection_layout_slot s join public.collection_layout_page pg on pg.id = s.page_id
           where pg.layout_id = l_b) = 531,
      'detail','fixture: CM 18 bolsos no estado inicial previsto, 2 cartas, convidada no 17; CB 3×3 com 531 bolsos (523 posições): ' || coalesce(v_lab, 'NULL'));

    -- M. Marcos de participação preenchidos pelos gatilhos da 5263 (A7) ------------------------------
    res := res || jsonb_build_object('id','M.1','ok',
      (select m.marker_at = l.created_at and m.marker_source = 'LAYOUT_CREATED' and m.role = 'OWNER'
       from public.collection_layout_catalog_marker m join public.collection_layout l on l.id = m.layout_id
       where m.layout_id = l_m and m.collection_id = v_cm)
      and (select m.marker_at = g.created_at and m.marker_source = 'GUEST_ATTACHED' and m.role = 'GUEST'
           from public.collection_layout_catalog_marker m join public.collection_layout_guest g
             on g.collection_id = m.collection_id and g.layout_id = m.layout_id
           where m.layout_id = l_m and m.collection_id = v_cg)
      and (select m.role = 'GUEST' and m.marker_source = 'GUEST_ATTACHED' from public.collection_layout_catalog_marker m
           where m.layout_id = l_p and m.collection_id = v_ch)
      and (select count(*) from public.collection_layout_catalog_marker m where m.layout_id in (l_m, l_p, l_b)) = 5
      and (select count(*) from public.collection_layout_catalog_marker m where m.layout_id = l_b and m.collection_id = v_cb and m.role = 'OWNER') = 1,
      'detail','criação de fichário (CM, CP, CB) e associação (CG, CH) pelas RPCs canônicas geram 5 marcos: dona = criação do fichário, convidada = entrada');
    v_err := null; begin
      insert into public.collection_layout_catalog_marker (layout_id, collection_id, marker_at, marker_source, role)
      values (l_b, v_cm, now(), 'BACKFILL_OWNER', 'BOSS');
    exception when check_violation then v_err := 'CHK'; end;
    v_err2 := null; begin
      insert into public.collection_layout_catalog_marker (layout_id, collection_id, marker_at, marker_source, role)
      values (l_m, v_cm, now(), 'LAYOUT_CREATED', 'OWNER');
    exception when unique_violation then v_err2 := 'PK'; end;
    v_err3 := null; begin
      insert into public.collection_layout_catalog_marker (layout_id, collection_id, marker_at, marker_source, role)
      values (gen_random_uuid(), v_cm, now(), 'LAYOUT_CREATED', 'OWNER');
    exception when foreign_key_violation then v_err3 := 'FK'; end;
    v_hint := null; begin
      insert into public.collection_layout_catalog_marker (layout_id, collection_id, marker_at, marker_source, role)
      values (l_b, v_cm, now(), 'INVENTADO', 'GUEST');
    exception when check_violation then v_hint := 'CHK'; end;
    res := res || jsonb_build_object('id','M.2','ok', v_err = 'CHK' and v_err2 = 'PK' and v_err3 = 'FK' and v_hint = 'CHK'
      and (select count(*) from public.collection_layout_catalog_marker m where m.layout_id in (l_m, l_p, l_b)) = 5,
      'detail','integridade dos marcos (escrita privilegiada): papel ou origem inválidos → 23514; repetido → 23505; fichário inexistente → 23503; nada gravado');

    -- 1. Ordem = planejamento original -------------------------------------------------------------
    select (select string_agg(p1.card_id::text || ':' || coalesce(p1.variant_type_id::text, '*'), ',' order by p1.pos_ord)
            from public.binder_catalog_positions(s_rc, (select array_agg(f.variant_type_id order by f.variant_type_id)
                                                        from public.collection_master_set_finish f where f.collection_id = v_cm)) p1)
         = (select string_agg(b1.expected_card_id::text || ':' || coalesce(b1.expected_variant_type_id::text, '*'), ',' order by b1.item_ord)
            from public.collection_binder_plan(v_cm, 3, 3, 'PRINCIPAL_ONLY') b1 where b1.item_kind = 'POSITION')
      into v_ok;
    res := res || jsonb_build_object('id','1.1','ok', coalesce(v_ok, false),
      'detail','CM: ordem de binder_catalog_positions idêntica às POSITION de collection_binder_plan (18 posições, com as 3 novidades)');
    select (select string_agg(p1.card_id::text || ':' || coalesce(p1.variant_type_id::text, '*'), ',' order by p1.pos_ord)
            from public.binder_catalog_positions(s_rb, (select array_agg(f.variant_type_id order by f.variant_type_id)
                                                        from public.collection_master_set_finish f where f.collection_id = v_cb)) p1)
         = (select string_agg(b1.expected_card_id::text || ':' || coalesce(b1.expected_variant_type_id::text, '*'), ',' order by b1.item_ord)
            from public.collection_binder_plan(v_cb, 3, 3, 'PRINCIPAL_ONLY') b1 where b1.item_kind = 'POSITION')
      into v_ok;
    res := res || jsonb_build_object('id','1.2','ok', coalesce(v_ok, false),
      'detail','CB: ordem idêntica em 626 posições (520 S + 102 H novas + 521 H + 522 H + 523 S/H)');

    -- 2. Detecção ------------------------------------------------------------------------------------
    perform set_config('request.jwt.claim.sub', u_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    select string_agg(x.item_key, ',' order by x.item_key), max(x.novelty_count), bool_and(x.eligible), bool_or(x.placed_in_binder)
      into v_err, n, v_ok, v_hint
    from public.get_my_binder_catalog_novelties(v_cm) x;
    res := res || jsonb_build_object('id','2.1','ok',
      v_err = (select string_agg(z, ',' order by z) from unnest(array[k3r, k4h, k6r]) z) and n = 3 and v_ok and v_hint = 'false',
      'detail','CM: exatamente 3 novidades (3-REVERSE, 4-HOLO, 6-REVERSE); a 2-REVERSE liberada (antiga) não aparece — regra 5');
    select * into o from public.get_my_binder_catalog_novelties(v_cg);
    res := res || jsonb_build_object('id','2.2','ok', o.eligible and o.novelty_count = 0 and o.item_key is null,
      'detail','convidada CG (Master Set em fichário de dona Master Set): elegível, 0 novidades');
    select * into o from public.get_my_binder_catalog_novelties(v_cp);
    v_err := null; begin perform count(*) from public.preview_my_binder_catalog_reconciliation(v_cp, null);
    exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','2.3','ok', not o.eligible and o.reason = 'NOT_MASTER_SET' and v_err = 'NOT_MASTER_SET',
      'detail','Pokédex CP: aviso inelegível (NOT_MASTER_SET); prévia → ' || coalesce(v_err, 'sem erro'));
    select * into o from public.get_my_binder_catalog_novelties(v_ch);
    v_err := null; v_hint := null;
    begin perform count(*) from public.preview_my_binder_catalog_reconciliation(v_ch, null);
    exception when others then v_err := sqlerrm; get stacked diagnostics v_hint = pg_exception_hint; end;
    res := res || jsonb_build_object('id','2.4','ok', not o.eligible and o.reason = 'BINDER_OWNER_POKEDEX'
      and v_err = 'BINDER_NOT_ELIGIBLE' and v_hint = 'BINDER_OWNER_POKEDEX',
      'detail','Master Set convidada em fichário de dona Pokédex: inelegível; prévia → ' || coalesce(v_err, 'sem erro') || ' / ' || coalesce(v_hint, '-'));
    execute 'reset role';

    -- 3. Isolamento ----------------------------------------------------------------------------------
    execute 'set local role anon';
    v_ok := false;
    begin perform count(*) from public.preview_my_binder_catalog_reconciliation(v_cm, null);
    exception when insufficient_privilege then v_ok := true; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','3.1','ok', v_ok, 'detail','anon não executa a prévia (42501)');
    perform set_config('request.jwt.claim.sub', u_b::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    v_err := null; begin perform count(*) from public.get_my_binder_catalog_novelties(v_cm); exception when others then v_err := sqlerrm; end;
    v_err2 := null; begin perform count(*) from public.preview_my_binder_catalog_reconciliation(v_cm, null); exception when others then v_err2 := sqlerrm; end;
    v_err3 := null; begin perform count(*) from public.apply_my_binder_catalog_reconciliation(v_cm, null, 'rc1:' || repeat('0', 64), true, true);
    exception when others then v_err3 := sqlerrm; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','3.2','ok', v_err = 'COLLECTION_NOT_FOUND' and v_err2 = 'COLLECTION_NOT_FOUND' and v_err3 = 'COLLECTION_NOT_FOUND',
      'detail','B em A (aviso/prévia/aplicação) → COLLECTION_NOT_FOUND: ' || concat_ws(' / ', v_err, v_err2, v_err3));

    -- 4. Prévias (W1: prévia calculada em outro fuso e outro DateStyle) ------------------------------
    v_sig := pg_temp.wh_5859_sig(l_m);
    perform set_config('TimeZone', 'America/Sao_Paulo', true);
    perform set_config('DateStyle', 'SQL, DMY', true);
    perform set_config('request.jwt.claim.sub', u_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    select * into h from public.preview_my_binder_catalog_reconciliation(v_cm, array[k6r]) x where x.row_kind = 'HEADER';
    select * into w from public.preview_my_binder_catalog_reconciliation(v_cm, array[k6r]) x where x.row_kind = 'ITEM';
    res := res || jsonb_build_object('id','4.1','ok',
      h.outcome = 'READY' and h.total_items = 1 and h.total_rows_moved = 7 and not h.requires_cross_page and not h.requires_add_page
      and h.pages_added = 0 and h.capacity_before = 18 and h.capacity_after = 18 and h.free_pockets_after = 2
      and w.kind = 'SHIFT' and (w.target_page, w.target_row, w.target_column) = (2, 1, 3)
      and (w.end_page, w.end_row, w.end_column) = (2, 3, 3) and w.pockets_moved = 6 and w.rows_moved = 7
      and w.other_reserves_moved = 1 and not w.crosses_page and not w.adds_page,
      'detail', format('seleção parcial [6-REVERSE]: %s, %s→%s, %s bolsos, %s linhas, %s da convidada',
        w.kind, w.target_page||'·'||w.target_row||'·'||w.target_column, w.end_page||'·'||w.end_row||'·'||w.end_column,
        w.pockets_moved, w.rows_moved, w.other_reserves_moved));

    select * into h from public.preview_my_binder_catalog_reconciliation(v_cm, null) x where x.row_kind = 'HEADER';
    v_tok := h.plan_token;
    res := res || jsonb_build_object('id','4.2','ok',
      h.outcome = 'READY' and h.total_items = 3 and h.total_rows_moved = 19 and h.requires_cross_page and h.requires_add_page
      and h.pages_added = 1 and h.added_page_numbers = array[3] and h.capacity_before = 18 and h.capacity_after = 27
      and h.free_pockets_after = 9 and h.row_limit = 500 and h.item_limit = 100 and v_tok ~ '^rc1:[0-9a-f]{64}$',
      'detail', format('prévia completa: %s, %s itens, %s linhas, páginas +%s %s, capacidade %s→%s, livres depois %s',
        h.outcome, h.total_items, h.total_rows_moved, h.pages_added, h.added_page_numbers, h.capacity_before, h.capacity_after, h.free_pockets_after));
    select * into w from public.preview_my_binder_catalog_reconciliation(v_cm, null) x where x.row_kind = 'ITEM' and x.step_no = 1;
    res := res || jsonb_build_object('id','4.3','ok',
      w.item_key = k3r and w.kind = 'IN_PLACE' and (w.target_page, w.target_row, w.target_column) = (1, 2, 3)
      and (w.anchor_page, w.anchor_row, w.anchor_column) = (1, 2, 2) and w.rows_moved = 0 and w.end_page is null,
      'detail','caso real (Chi-Yu Reversa): 3-REVERSE reservada no bolso livre 1·2·3 logo após a âncora 1·2·2, sem deslocamento');
    select * into w from public.preview_my_binder_catalog_reconciliation(v_cm, null) x where x.row_kind = 'ITEM' and x.step_no = 2;
    select * into o from public.preview_my_binder_catalog_reconciliation(v_cm, null) x where x.row_kind = 'ITEM' and x.step_no = 3;
    res := res || jsonb_build_object('id','4.4','ok',
      w.item_key = k4h and w.kind = 'SHIFT' and (w.target_page, w.target_row, w.target_column) = (1, 3, 2)
      and (w.end_page, w.end_row, w.end_column) = (2, 3, 3) and w.pockets_moved = 10 and w.rows_moved = 12
      and w.other_reserves_moved = 1 and w.crosses_page and not w.adds_page
      and o.item_key = k6r and o.kind = 'SHIFT' and (o.target_page, o.target_row, o.target_column) = (2, 2, 1)
      and (o.end_page, o.end_row, o.end_column) = (3, 1, 1) and o.pockets_moved = 6 and o.rows_moved = 7
      and o.other_reserves_moved = 1 and not o.crosses_page and o.adds_page,
      'detail','4-HOLO: abre 1·3·2 deslocando 10 bolsos até 2·3·3 (muda de página); 6-REVERSE: abre 2·2·1, cadeia sem bolso livre → página 3, a última posição (reserva da convidada) vai para 3·1·1');
    v_tz1 := v_tok;
    perform set_config('TimeZone', 'UTC', true);
    perform set_config('DateStyle', 'ISO, MDY', true);
    select x.plan_token into v_tz2 from public.preview_my_binder_catalog_reconciliation(v_cm, null) x where x.row_kind = 'HEADER';
    perform set_config('TimeZone', 'Asia/Tokyo', true);
    perform set_config('DateStyle', 'German', true);
    select x.plan_token into v_tz3 from public.preview_my_binder_catalog_reconciliation(v_cm, null) x where x.row_kind = 'HEADER';
    execute 'reset role';
    res := res || jsonb_build_object('id','4.6','ok', v_tz1 = v_tz2 and v_tz2 = v_tz3,
      'detail','W1: mesmo plan_token em America/Sao_Paulo+SQL/DMY, UTC+ISO/MDY e Asia/Tokyo+German');
    res := res || jsonb_build_object('id','4.5','ok', pg_temp.wh_5859_sig(l_m) = v_sig,
      'detail','prévias não alteram bolsos, cartas, reservas, imagens, travas nem páginas');

    -- 5. Travamento e mesclagem ----------------------------------------------------------------------
    execute 'set local role authenticated';
    perform public.set_slot_lock(array[sl_lock], true);
    select * into h from public.preview_my_binder_catalog_reconciliation(v_cm, null) x where x.row_kind = 'HEADER';
    select * into w from public.preview_my_binder_catalog_reconciliation(v_cm, null) x where x.row_kind = 'ITEM' and x.step_no = 2;
    select * into o from public.preview_my_binder_catalog_reconciliation(v_cm, null) x where x.row_kind = 'ITEM' and x.step_no = 3;
    execute 'reset role';
    v_sig2 := pg_temp.wh_5859_sig(l_m);
    res := res || jsonb_build_object('id','5.1','ok', h.outcome = 'BLOCKED' and w.kind = 'BLOCKED'
      and (w.barrier_page, w.barrier_row, w.barrier_column) = (2, 2, 1) and w.barrier_kind = 'LOCKED' and o.kind = 'NOT_EVALUATED',
      'detail','bolso travado 2·2·1 na cadeia da 4-HOLO → BLOCKED; 6-REVERSE não avaliada');
    execute 'set local role authenticated';
    v_err := null; v_hint := null;
    begin perform count(*) from public.apply_my_binder_catalog_reconciliation(v_cm, null, h.plan_token, true, true);
    exception when others then v_err := sqlerrm; get stacked diagnostics v_hint = pg_exception_hint; end;
    perform public.set_slot_lock(array[sl_lock], false);
    execute 'reset role';
    res := res || jsonb_build_object('id','5.2','ok', v_err = 'RECONCILE_BLOCKED' and v_hint like '%LOCKED%2%2%1%'
      and v_sig2 <> v_sig and pg_temp.wh_5859_sig(l_m) = v_sig,
      'detail','aplicar com o plano bloqueado → RECONCILE_BLOCKED (' || coalesce(v_hint, '-') || '); nada alterado (inclusive a 3-REVERSE, que seria no lugar)');

    insert into public.collection_layout_region (page_id, top_row, left_column, height, width)
    select pg.id, 1, 2, 1, 2 from public.collection_layout_page pg where pg.layout_id = l_b and pg.page_number = 59
    returning id into v_reg;
    perform set_config('request.jwt.claim.sub', u_b::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    select * into h from public.preview_my_binder_catalog_reconciliation(v_cb, array[kb1h]) x where x.row_kind = 'HEADER';
    select * into w from public.preview_my_binder_catalog_reconciliation(v_cb, array[kb1h]) x where x.row_kind = 'ITEM';
    execute 'reset role';
    delete from public.collection_layout_region where id = v_reg;
    res := res || jsonb_build_object('id','5.3','ok', h.outcome = 'BLOCKED' and w.kind = 'BLOCKED'
      and (w.barrier_page, w.barrier_row, w.barrier_column) = (59, 1, 2) and w.barrier_kind = 'REGION',
      'detail','mesclagem na cadeia (pág. 59, 1·2–1·3) → BLOCKED antes do primeiro bolso livre');

    -- 6. Token, confirmações, aplicação, idempotência ----------------------------------------------
    perform set_config('request.jwt.claim.sub', u_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    v_err := null; begin perform count(*) from public.apply_my_binder_catalog_reconciliation(v_cm, null, 'rc1:' || repeat('0', 64), true, true);
    exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','6.1','ok', v_err = 'RECONCILE_PLAN_CHANGED',
      'detail','token divergente → ' || coalesce(v_err, 'sem erro'));
    select x.id into v_pg from public.add_layout_page(l_m) x;
    v_err := null; begin perform count(*) from public.apply_my_binder_catalog_reconciliation(v_cm, null, v_tok, true, true);
    exception when others then v_err := sqlerrm; end;
    perform public.remove_layout_page(v_pg);
    select x.plan_token into v_tok2 from public.preview_my_binder_catalog_reconciliation(v_cm, null) x where x.row_kind = 'HEADER';
    res := res || jsonb_build_object('id','6.2','ok', v_err = 'RECONCILE_PLAN_CHANGED' and v_tok2 = v_tok,
      'detail','fichário mudou entre prévia e execução (página acrescentada) → ' || coalesce(v_err, 'sem erro') || '; de volta ao mesmo estado → mesmo token');
    v_err := null; v_hint := null;
    begin perform count(*) from public.apply_my_binder_catalog_reconciliation(v_cm, null, v_tok, false, false);
    exception when others then v_err := sqlerrm; get stacked diagnostics v_hint = pg_exception_hint; end;
    v_err2 := null; v_err3 := null;
    begin perform count(*) from public.apply_my_binder_catalog_reconciliation(v_cm, null, v_tok, true, false);
    exception when others then v_err2 := sqlerrm; get stacked diagnostics v_err3 = pg_exception_hint; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','6.3','ok', v_err = 'RECONCILE_CONFIRMATION_REQUIRED' and v_hint = 'CROSS_PAGE'
      and v_err2 = 'RECONCILE_CONFIRMATION_REQUIRED' and v_err3 = 'ADD_PAGE' and pg_temp.wh_5859_sig(l_m) = v_sig,
      'detail','sem confirmar outra página → CROSS_PAGE; sem confirmar página nova → ADD_PAGE; nada alterado');

    -- 6.10 Falha provocada DEPOIS de escritas parciais: gatilho de teste recusa a reserva da
    --      6-REVERSE (3º item), quando 3-REVERSE já foi reservada, a 4-HOLO já deslocou 10
    --      bolsos e a página 3 já foi criada. Tudo tem de voltar.
    execute format($ddl$create function public.wh_5859_fail() returns trigger language plpgsql as $t$
      begin
        if new.card_id = %L::uuid then raise exception 'WH5859_FAIL'; end if;
        return new;
      end $t$$ddl$, kc[6]);
    execute 'create trigger wh_5859_fail_trg before insert on public.collection_layout_slot_expected_content '
            'for each row execute function public.wh_5859_fail()';
    execute 'set local role authenticated';
    v_err := null; begin perform count(*) from public.apply_my_binder_catalog_reconciliation(v_cm, null, v_tok, true, true);
    exception when others then v_err := sqlerrm; end;
    execute 'reset role';
    execute 'drop trigger wh_5859_fail_trg on public.collection_layout_slot_expected_content';
    execute 'drop function public.wh_5859_fail()';
    res := res || jsonb_build_object('id','6.10','ok', v_err = 'WH5859_FAIL' and pg_temp.wh_5859_sig(l_m) = v_sig,
      'detail','falha no 3º item após reserva, deslocamento e página nova → ' || coalesce(v_err, 'sem erro') || '; fichário idêntico ao anterior (2 páginas, nada gravado)');
    -- 6.11 Falha DURANTE a gravação W5: reservas, deslocamentos e página já feitos; o INSERT
    --      no registro de incorporações é recusado por um gatilho de teste. Tudo tem de voltar.
    execute 'create function public.wh_5859_fail_w5() returns trigger language plpgsql as $t$ begin raise exception ''WH5859_FAIL_W5''; end $t$';
    execute 'create trigger wh_5859_fail_w5_trg before insert on public.collection_layout_catalog_incorporation '
            'for each row execute function public.wh_5859_fail_w5()';
    execute 'set local role authenticated';
    v_err := null; begin perform count(*) from public.apply_my_binder_catalog_reconciliation(v_cm, null, v_tok, true, true);
    exception when others then v_err := sqlerrm; end;
    execute 'reset role';
    execute 'drop trigger wh_5859_fail_w5_trg on public.collection_layout_catalog_incorporation';
    execute 'drop function public.wh_5859_fail_w5()';
    res := res || jsonb_build_object('id','6.11','ok', v_err = 'WH5859_FAIL_W5' and pg_temp.wh_5859_sig(l_m) = v_sig
      and not exists (select 1 from public.collection_layout_catalog_incorporation i where i.layout_id = l_m),
      'detail','falha na gravação W5 (depois de 3 reservas, 16 bolsos deslocados e página nova) → ' || coalesce(v_err, 'sem erro') || '; fichário idêntico e nenhum registro');
    res := res || jsonb_build_object('id','I.1','ok',
      not exists (select 1 from public.collection_layout_catalog_incorporation i where i.layout_id in (l_m, l_b, l_p)),
      'detail','W5: nenhum registro depois de prévias (4.x, 5.x), BLOCKED (5.2), PLAN_CHANGED (6.1/6.2), falta de confirmação (6.3) e falha após escrita parcial (6.10)');

    perform set_config('TimeZone', 'Asia/Tokyo', true);   -- aplicação em fuso diferente da prévia (W1)
    execute 'set local role authenticated';
    select * into w from public.apply_my_binder_catalog_reconciliation(v_cm, null, v_tok, true, true);
    execute 'reset role';
    res := res || jsonb_build_object('id','6.4','ok', w.outcome = 'APPLIED' and w.items_applied = 3 and w.reservations_created = 3
      and w.pockets_moved = 16 and w.rows_moved = 19 and w.pages_added = 1 and w.added_page_numbers = array[3],
      'detail', format('aplicação: %s, %s itens, %s reservas, %s bolsos, %s linhas, páginas %s',
        w.outcome, w.items_applied, w.reservations_created, w.pockets_moved, w.rows_moved, w.added_page_numbers));

    v_lab := pg_temp.wh_5859_labels(l_m, v_cg);
    select string_agg(x.k, ',' order by x.k) into v_asg2
    from (select a.id::text || '@' || a.physical_card_id::text as k
          from public.collection_layout_slot_assignment a
          join public.collection_layout_slot s on s.id = a.slot_id
          join public.collection_layout_page pg on pg.id = s.page_id where pg.layout_id = l_m) x;
    res := res || jsonb_build_object('id','6.5','ok', v_lab = c_final,
      'detail','sequência final do Master Set preservada (27 bolsos): ' || coalesce(v_lab, 'NULL'));
    res := res || jsonb_build_object('id','6.6','ok', v_asg2 = v_asg
      and exists (select 1 from public.collection_layout_slot_assignment a join public.collection_layout_slot s on s.id = a.slot_id
                  join public.collection_layout_page pg on pg.id = s.page_id
                  where a.physical_card_id = f5 and pg.layout_id = l_m and (pg.page_number, s.row_index, s.column_index) = (2, 1, 1))
      and exists (select 1 from public.collection_layout_slot_assignment a join public.collection_layout_slot s on s.id = a.slot_id
                  join public.collection_layout_page pg on pg.id = s.page_id
                  where a.physical_card_id = f8 and pg.layout_id = l_m and (pg.page_number, s.row_index, s.column_index) = (2, 3, 2)),
      'detail','cartas andaram com o bolso (5S → 2·1·1, 8R → 2·3·2), mesmas posições (id) e mesmos exemplares');
    res := res || jsonb_build_object('id','6.7','ok',
      exists (select 1 from public.collection_layout_slot_expected_content e join public.collection_layout_slot s on s.id = e.slot_id
              join public.collection_layout_page pg on pg.id = s.page_id
              where pg.layout_id = l_m and e.collection_id = v_cg and (pg.page_number, s.row_index, s.column_index) = (3, 1, 1))
      and (select count(*) from public.collection_layout_slot_expected_content e join public.collection_layout_slot s on s.id = e.slot_id
           join public.collection_layout_page pg on pg.id = s.page_id
           where pg.layout_id = l_m and e.collection_id is null and e.card_id in (kc[3], kc[4], kc[6])
             and e.expected_variant_type_id in (v_rev, v_holo) and e.card_variant_id is null) = 3,
      'detail','reserva da convidada preservada (coleção CG) na página nova 3·1·1; 3 reservas novas da dona com acabamento');
    select string_agg(i.collection_id::text || '/' || i.item_key || '@' || extract(epoch from i.incorporated_at)::text, ',' order by i.item_key)
      into v_inc from public.collection_layout_catalog_incorporation i where i.layout_id = l_m;
    res := res || jsonb_build_object('id','I.2','ok',
      (select count(*) from public.collection_layout_catalog_incorporation i where i.layout_id = l_m) = 3
      and (select array_agg(i.item_key order by i.item_key) from public.collection_layout_catalog_incorporation i
           where i.layout_id = l_m and i.collection_id = v_cm) = (select array_agg(x order by x) from unnest(array[k3r, k4h, k6r]) x)
      and not exists (select 1 from public.collection_layout_catalog_incorporation i where i.layout_id = l_m and i.collection_id is distinct from v_cm),
      'detail','W5: a aplicação registrou exatamente 3-REVERSE, 4-HOLO e 6-REVERSE para a coleção real da dona (CM, não NULL)');
    v_err := null; begin
      insert into public.collection_layout_catalog_incorporation (layout_id, collection_id, item_key) values (l_m, v_cm, 'abc');
    exception when check_violation then v_err := 'CHK'; end;
    v_err2 := null; begin
      insert into public.collection_layout_catalog_incorporation (layout_id, collection_id, item_key) values (l_m, v_cm, k3r);
    exception when unique_violation then v_err2 := 'PK'; end;
    v_err3 := null; begin
      insert into public.collection_layout_catalog_incorporation (layout_id, collection_id, item_key) values (gen_random_uuid(), v_cm, k9r);
    exception when foreign_key_violation then v_err3 := 'FK'; end;
    v_hint := null; begin
      insert into public.collection_layout_catalog_incorporation (layout_id, collection_id, item_key) values (l_m, gen_random_uuid(), k9r);
    exception when foreign_key_violation then v_hint := 'FK'; end;
    res := res || jsonb_build_object('id','I.9','ok', v_err = 'CHK' and v_err2 = 'PK' and v_err3 = 'FK' and v_hint = 'FK'
      and (select count(*) from public.collection_layout_catalog_incorporation i where i.layout_id = l_m) = 3,
      'detail','integridade (escrita privilegiada): chave malformada → 23514; chave repetida → 23505; fichário ou coleção inexistente → 23503; nada gravado');

    v_sig := pg_temp.wh_5859_sig(l_m);
    execute 'set local role authenticated';
    select * into w from public.apply_my_binder_catalog_reconciliation(v_cm, array[k3r, k4h, k6r], v_tok, true, true);
    select * into o from public.apply_my_binder_catalog_reconciliation(v_cm, null, v_tok, true, true);
    select x.novelty_count into n from public.get_my_binder_catalog_novelties(v_cm) x;
    execute 'reset role';
    res := res || jsonb_build_object('id','6.8','ok', w.outcome = 'ALREADY_APPLIED' and o.outcome = 'NOTHING_TO_DO'
      and n = 0 and pg_temp.wh_5859_sig(l_m) = v_sig,
      'detail','repetir com as mesmas chaves → ALREADY_APPLIED; sem chaves → NOTHING_TO_DO; nada gravado; 0 novidades');
    select string_agg(i.collection_id::text || '/' || i.item_key || '@' || extract(epoch from i.incorporated_at)::text, ',' order by i.item_key)
      into v_inc2 from public.collection_layout_catalog_incorporation i where i.layout_id = l_m;
    res := res || jsonb_build_object('id','I.3','ok', v_inc2 = v_inc,
      'detail','W5: repetição (ALREADY_APPLIED/NOTHING_TO_DO) não cria nem regrava registro (mesmas chaves, mesmo incorporated_at)');
    res := res || jsonb_build_object('id','6.9','ok', split_part(v_lab, ',', 4) = '-'
      and not exists (select 1 from public.collection_layout_slot_expected_content e join public.collection_layout_slot s on s.id = e.slot_id
                      join public.collection_layout_page pg on pg.id = s.page_id
                      where pg.layout_id = l_m and e.card_id = kc[2] and e.expected_variant_type_id = v_rev),
      'detail','regra 5: a reserva liberada da 2-REVERSE não foi restaurada (bolso 4 continua livre)');

    -- 7. Limites -------------------------------------------------------------------------------------
    v_sig := pg_temp.wh_5859_sig(l_b);
    perform set_config('request.jwt.claim.sub', u_b::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    select * into h from public.preview_my_binder_catalog_reconciliation(v_cb, null) x where x.row_kind = 'HEADER';
    res := res || jsonb_build_object('id','7.1','ok', h.outcome = 'OVER_LIMIT' and h.reason = 'ITEM_LIMIT' and h.total_items = 105
      and h.plan_token is null,
      'detail','105 novidades selecionadas > 100 → OVER_LIMIT/ITEM_LIMIT (sem token)');
    select * into h from public.preview_my_binder_catalog_reconciliation(v_cb, array[kb1h]) x where x.row_kind = 'HEADER';
    select * into w from public.preview_my_binder_catalog_reconciliation(v_cb, array[kb1h]) x where x.row_kind = 'ITEM';
    res := res || jsonb_build_object('id','7.2','ok', h.outcome = 'OVER_LIMIT' and h.reason = 'ROW_LIMIT'
      and h.total_rows_moved = 522 and w.pockets_moved = 522 and w.rows_moved = 522,
      'detail', format('1 novidade que desloca %s bolsos (%s linhas) > 500 → OVER_LIMIT/ROW_LIMIT', w.pockets_moved, h.total_rows_moved));
    v_err := null; v_hint := null;
    begin perform count(*) from public.apply_my_binder_catalog_reconciliation(v_cb, array[kb1h], h.plan_token, true, true);
    exception when others then v_err := sqlerrm; get stacked diagnostics v_hint = pg_exception_hint; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','7.3','ok', v_err = 'RECONCILE_OVER_LIMIT' and v_hint like 'ROW_LIMIT%'
      and pg_temp.wh_5859_sig(l_b) = v_sig,
      'detail','aplicar acima do limite → RECONCILE_OVER_LIMIT (' || coalesce(v_hint, '-') || '); nada alterado');

    execute 'set local role authenticated';
    v_err := null; v_hint := null;
    begin perform count(*) from public.apply_my_binder_catalog_reconciliation(v_cb, null, 'rc1:' || repeat('0', 64), true, true);
    exception when others then v_err := sqlerrm; get stacked diagnostics v_hint = pg_exception_hint; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','7.4','ok', v_err = 'RECONCILE_OVER_LIMIT' and v_hint like 'ITEM_LIMIT%'
      and pg_temp.wh_5859_sig(l_b) = v_sig,
      'detail','W2: aplicar com 105 novidades → RECONCILE_OVER_LIMIT/ITEM_LIMIT, não PLAN_CHANGED (' || coalesce(v_err, 'sem erro') || ')');
    res := res || jsonb_build_object('id','I.4','ok',
      not exists (select 1 from public.collection_layout_catalog_incorporation i where i.layout_id = l_b),
      'detail','W5: recusas por limite (7.3 ROW_LIMIT, 7.4 ITEM_LIMIT) e BLOCKED por mesclagem (5.3) não registram nada no fichário B');

    -- 9. W3: reserva genérica de secreta que ganhou acabamento ---------------------------------------
    execute 'set local role authenticated';
    select * into h from public.preview_my_binder_catalog_reconciliation(v_cb, array[k522h]) x where x.row_kind = 'HEADER';
    select * into w from public.preview_my_binder_catalog_reconciliation(v_cb, array[k522h]) x where x.row_kind = 'ITEM';
    res := res || jsonb_build_object('id','9.1','ok', h.outcome = 'READY' and h.total_rows_moved = 0 and h.pages_added = 0
      and w.kind = 'UPGRADE_RESERVATION' and (w.target_page, w.target_row, w.target_column) = (58, 3, 3),
      'detail','522 (genérica → HOLO, inequívoca): UPGRADE_RESERVATION no próprio bolso 58·3·3, nada anda');
    select * into o from public.apply_my_binder_catalog_reconciliation(v_cb, array[k522h], h.plan_token, false, false);
    execute 'reset role';
    res := res || jsonb_build_object('id','9.2','ok', o.outcome = 'APPLIED' and o.reservations_created = 0
      and o.reservations_upgraded = 1 and o.rows_moved = 0
      and (select count(*) from public.collection_layout_slot_expected_content e join public.collection_layout_slot s on s.id = e.slot_id
           join public.collection_layout_page pg on pg.id = s.page_id where pg.layout_id = l_b and e.card_id = kb522) = 1
      and exists (select 1 from public.collection_layout_slot_expected_content e join public.collection_layout_slot s on s.id = e.slot_id
                  join public.collection_layout_page pg on pg.id = s.page_id
                  where pg.layout_id = l_b and e.card_id = kb522 and e.expected_variant_type_id = v_holo
                    and (pg.page_number, s.row_index, s.column_index) = (58, 3, 3)),
      'detail','aplicação: 1 reserva convertida, 0 criada; a 522 continua com 1 única reserva, no mesmo bolso, agora HOLO');
    v_sig := pg_temp.wh_5859_sig(l_b);
    execute 'set local role authenticated';
    select * into h from public.preview_my_binder_catalog_reconciliation(v_cb, array[k523s, k523h]) x where x.row_kind = 'HEADER';
    select count(*) filter (where x.kind = 'REVIEW_REQUIRED' and x.barrier_kind = 'GENERIC_RESERVATION'
                            and (x.barrier_page, x.barrier_row, x.barrier_column) = (59, 1, 1))
      into n from public.preview_my_binder_catalog_reconciliation(v_cb, array[k523s, k523h]) x where x.row_kind = 'ITEM';
    res := res || jsonb_build_object('id','9.3','ok', h.outcome = 'NEEDS_REVIEW' and n = 2,
      'detail','523 (genérica → 2 acabamentos, ambígua): 2 itens REVIEW_REQUIRED apontando a reserva genérica 59·1·1');
    v_err := null; begin perform count(*) from public.apply_my_binder_catalog_reconciliation(v_cb, array[k523s, k523h], h.plan_token, true, true);
    exception when others then v_err := sqlerrm; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','9.4','ok', v_err = 'RECONCILE_NEEDS_REVIEW' and pg_temp.wh_5859_sig(l_b) = v_sig,
      'detail','aplicar o caso ambíguo → ' || coalesce(v_err, 'sem erro') || '; nenhuma reserva criada nem convertida');
    res := res || jsonb_build_object('id','I.5','ok',
      (select array_agg(i.collection_id::text || '/' || i.item_key) from public.collection_layout_catalog_incorporation i where i.layout_id = l_b)
        = array[v_cb::text || '/' || k522h],
      'detail','W5: conversão genérica → específica (9.2) registra a 522-HOLO; o caso ambíguo recusado (9.4) não registra 523');

    -- 10. Convidada, carta fora da ordem, seleção parcialmente aplicada e W5 ------------------------
    perform set_config('request.jwt.claim.sub', u_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    insert into public.card (card_set_id, rarity_id, category_id, collector_number, collector_order, name, is_active, created_at)
    values (s_rg, v_rar, v_cat, '2', 2, 'RG 2', true, v_new) returning id into g2;
    insert into public.card_variant (card_id, variant_type_id, variant_order, is_default, created_at)
    values (g2, v_std, 1, true, v_new);
    kg2 := g2::text || ':' || v_std::text;
    execute 'set local role authenticated';
    select * into h from public.preview_my_binder_catalog_reconciliation(v_cg, array[kg2]) x where x.row_kind = 'HEADER';
    select * into w from public.preview_my_binder_catalog_reconciliation(v_cg, array[kg2]) x where x.row_kind = 'ITEM';
    select * into o from public.apply_my_binder_catalog_reconciliation(v_cg, array[kg2], h.plan_token, false, false);
    execute 'reset role';
    res := res || jsonb_build_object('id','10.1','ok', w.kind = 'IN_PLACE' and (w.target_page, w.target_row, w.target_column) = (3, 1, 2)
      and (w.anchor_page, w.anchor_row, w.anchor_column) = (3, 1, 1) and o.outcome = 'APPLIED' and o.reservations_created = 1
      and exists (select 1 from public.collection_layout_slot_expected_content e join public.collection_layout_slot s on s.id = e.slot_id
                  join public.collection_layout_page pg on pg.id = s.page_id
                  where pg.layout_id = l_m and e.card_id = g2 and e.collection_id = v_cg
                    and (pg.page_number, s.row_index, s.column_index) = (3, 1, 2)),
      'detail','aplicação pela convidada CG: RG 2 reservada em 3·1·2 (após a âncora RG 1 em 3·1·1), reserva com a coleção da convidada');
    res := res || jsonb_build_object('id','I.6','ok',
      (select array_agg(i.item_key) from public.collection_layout_catalog_incorporation i where i.layout_id = l_m and i.collection_id = v_cg) = array[kg2]
      and (select count(*) from public.collection_layout_catalog_incorporation i where i.layout_id = l_m and i.collection_id = v_cm) = 3,
      'detail','W5: fichário compartilhado — a convidada registra RG 2 com a própria coleção (CG); os registros da dona continuam 3');

    -- W6: novidade 7-HOLO cujo exemplar já está colocado fora da ordem (bolso 1·2·1)
    insert into public.card_variant (card_id, variant_type_id, variant_order, is_default, created_at)
    values (kc[7], v_holo, 2, false, v_new);
    k7h := kc[7]::text || ':' || v_holo::text;
    insert into public.physical_card (card_variant_id, language_id, inventory_id, storage_container_id)
    select cv.id, v_pt, v_inv_a, v_bin from public.card_variant cv where cv.card_id = kc[7] and cv.variant_type_id = v_holo
    returning id into f7h;
    execute 'set local role authenticated';
    perform count(*) from public.allocate_physical_cards_to_collection(v_cm, array[f7h]);
    perform count(*) from public.place_my_physical_card_in_slot(v_cm, sl_clr, f7h);
    execute 'reset role';
    v_sig := pg_temp.wh_5859_sig(l_m);
    execute 'set local role authenticated';
    select * into h from public.preview_my_binder_catalog_reconciliation(v_cm, array[k7h]) x where x.row_kind = 'HEADER';
    select * into w from public.preview_my_binder_catalog_reconciliation(v_cm, array[k7h]) x where x.row_kind = 'ITEM';
    select x.placed_in_binder into v_ok from public.get_my_binder_catalog_novelties(v_cm) x where x.item_key = k7h;
    v_err := null; begin perform count(*) from public.apply_my_binder_catalog_reconciliation(v_cm, array[k7h], h.plan_token, true, true);
    exception when others then v_err := sqlerrm; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','10.2','ok', h.outcome = 'NEEDS_REVIEW' and w.kind = 'OUT_OF_ORDER'
      and w.barrier_kind = 'PLACED_OUT_OF_ORDER' and (w.barrier_page, w.barrier_row, w.barrier_column) = (1, 2, 1) and v_ok,
      'detail','W6: exemplar da 7-HOLO no bolso 1·2·1 (fora da ordem) → OUT_OF_ORDER/NEEDS_REVIEW; aviso marca placed_in_binder');
    res := res || jsonb_build_object('id','10.3','ok', v_err = 'RECONCILE_NEEDS_REVIEW' and pg_temp.wh_5859_sig(l_m) = v_sig
      and not exists (select 1 from public.collection_layout_slot_expected_content e join public.collection_layout_slot s on s.id = e.slot_id
                      join public.collection_layout_page pg on pg.id = s.page_id
                      where pg.layout_id = l_m and e.card_id = kc[7] and e.expected_variant_type_id = v_holo),
      'detail','aplicar → ' || coalesce(v_err, 'sem erro') || '; carta preservada em 1·2·1 e nenhuma reserva que legitime a posição');

    -- Seleção parcialmente aplicada: 8-HOLO e 9-REVERSE
    insert into public.card_variant (card_id, variant_type_id, variant_order, is_default, created_at)
    values (kc[8], v_holo, 2, false, v_new), (kc[9], v_rev, 3, false, v_new);
    k8h := kc[8]::text || ':' || v_holo::text;
    k9r := kc[9]::text || ':' || v_rev::text;
    execute 'set local role authenticated';
    select x.plan_token into v_tok_a from public.preview_my_binder_catalog_reconciliation(v_cm, array[k8h, k9r]) x where x.row_kind = 'HEADER';
    select x.plan_token into v_tok_b from public.preview_my_binder_catalog_reconciliation(v_cm, array[k8h]) x where x.row_kind = 'HEADER';
    select * into o from public.apply_my_binder_catalog_reconciliation(v_cm, array[k8h], v_tok_b, true, true);
    execute 'reset role';
    v_sig := pg_temp.wh_5859_sig(l_m);
    execute 'set local role authenticated';
    v_err := null; begin perform count(*) from public.apply_my_binder_catalog_reconciliation(v_cm, array[k8h, k9r], v_tok_a, true, true);
    exception when others then v_err := sqlerrm; end;
    select * into w from public.apply_my_binder_catalog_reconciliation(v_cm, array[k8h], v_tok_b, true, true);
    execute 'reset role';
    res := res || jsonb_build_object('id','10.4','ok', o.outcome = 'APPLIED' and v_err = 'RECONCILE_PLAN_CHANGED'
      and w.outcome = 'ALREADY_APPLIED' and pg_temp.wh_5859_sig(l_m) = v_sig,
      'detail','seleção [8-HOLO, 9-REVERSE] com a 8-HOLO já aplicada → ' || coalesce(v_err, 'sem erro')
               || ' (nada gravado); [8-HOLO] de novo → ALREADY_APPLIED');
    res := res || jsonb_build_object('id','I.7','ok',
      (select array_agg(i.item_key order by i.item_key) from public.collection_layout_catalog_incorporation i
       where i.layout_id = l_m and i.collection_id = v_cm) = (select array_agg(x order by x) from unnest(array[k3r, k4h, k6r, k8h]) x),
      'detail','W5: só o aplicado é registrado — 8-HOLO entra; 9-REVERSE (seleção recusada por PLAN_CHANGED) e 7-HOLO (W6, NEEDS_REVIEW) não');

    -- W5 (decisão de Fabrício; estrutura 5263): incorporada e depois liberada não reaparece.
    select e.slot_id into v_reg from public.collection_layout_slot_expected_content e
    join public.collection_layout_slot s on s.id = e.slot_id
    join public.collection_layout_page pg on pg.id = s.page_id
    where pg.layout_id = l_m and e.card_id = kc[8] and e.expected_variant_type_id = v_holo;
    select i.item_key || '@' || extract(epoch from i.incorporated_at)::text into v_inc
    from public.collection_layout_catalog_incorporation i where i.layout_id = l_m and i.collection_id = v_cm and i.item_key = k8h;
    execute 'set local role authenticated';
    perform public.clear_slot_expected_content(array[v_reg]);
    select count(*) into n from public.get_my_binder_catalog_novelties(v_cm) x where x.item_key = k8h;
    execute 'reset role';
    select i.item_key || '@' || extract(epoch from i.incorporated_at)::text into v_inc2
    from public.collection_layout_catalog_incorporation i where i.layout_id = l_m and i.collection_id = v_cm and i.item_key = k8h;
    res := res || jsonb_build_object('id','W5.1','ok', v_reg is not null and n = 0 and v_inc is not null and v_inc2 = v_inc
      and not exists (select 1 from public.collection_layout_slot_expected_content e
                      join public.collection_layout_slot s on s.id = e.slot_id
                      join public.collection_layout_page pg on pg.id = s.page_id
                      where pg.layout_id = l_m and e.card_id = kc[8] and e.expected_variant_type_id = v_holo),
      'detail','W5: reserva da 8-HOLO liberada pelo usuário; o registro persiste (mesmo incorporated_at) e o aviso não a oferece de novo (ocorrências: ' || n || ')');
    v_sig := pg_temp.wh_5859_sig(l_m);
    execute 'set local role authenticated';
    select count(*) into n from public.preview_my_binder_catalog_reconciliation(v_cm, null) x where x.row_kind = 'ITEM' and x.item_key = k8h;
    select count(*) into n2 from public.preview_my_binder_catalog_reconciliation(v_cm, null) x where x.row_kind = 'ITEM';
    v_err := null; begin perform count(*) from public.preview_my_binder_catalog_reconciliation(v_cm, array[k8h]);
    exception when others then v_err := sqlerrm; end;
    select * into w from public.apply_my_binder_catalog_reconciliation(v_cm, array[k8h], 'rc1:' || repeat('0', 64), true, true);
    execute 'reset role';
    res := res || jsonb_build_object('id','W5.2','ok', n = 0 and n2 > 0 and v_err = 'SELECTION_INVALID'
      and w.outcome = 'ALREADY_APPLIED' and pg_temp.wh_5859_sig(l_m) = v_sig
      and (select count(*) from public.collection_layout_catalog_incorporation i where i.layout_id = l_m and i.collection_id = v_cm) = 4,
      'detail', format('W5: prévia completa (%s itens) sem a 8-HOLO; selecioná-la na prévia → %s; aplicação [8-HOLO] → %s, sem restaurar a reserva nem gravar',
        n2, coalesce(v_err, 'sem erro'), w.outcome));

    -- T. Transferência de propriedade preserva os marcos (A7) ---------------------------------------
    --    Histórico simulado (L7): fichário criado há 1 dia; CG entrou há 2 h.
    v_t0 := now() - interval '1 day';
    v_tg := now() - interval '2 hours';
    v_born3 := now() - interval '12 hours';
    update public.collection_layout l set created_at = v_t0 where l.id = l_m;
    update public.collection_layout_catalog_marker m set marker_at = v_t0 where m.layout_id = l_m and m.collection_id = v_cm;
    update public.collection_layout_catalog_marker m set marker_at = v_tg where m.layout_id = l_m and m.collection_id = v_cg;
    -- RG 3 nasceu ENTRE a criação do fichário e a entrada de CG (posição antiga para CG)
    insert into public.card (card_set_id, rarity_id, category_id, collector_number, collector_order, name, is_active, created_at)
    values (s_rg, v_rar, v_cat, '3', 3, 'RG 3', true, v_born3) returning id into g3;
    insert into public.card_variant (card_id, variant_type_id, variant_order, is_default, created_at)
    values (g3, v_std, 1, true, v_born3);
    kg3 := g3::text || ':' || v_std::text;
    -- Controle positivo: RG 4 nasceu DEPOIS da entrada de CG (novidade legítima de CG)
    insert into public.card (card_set_id, rarity_id, category_id, collector_number, collector_order, name, is_active, created_at)
    values (s_rg, v_rar, v_cat, '4', 4, 'RG 4', true, now() - interval '1 hour') returning id into g4;
    insert into public.card_variant (card_id, variant_type_id, variant_order, is_default, created_at)
    values (g4, v_std, 1, true, now() - interval '1 hour');
    kg4 := g4::text || ':' || v_std::text;
    -- 1-HOLO nasceu depois do marco de CM e antes da transferência (novidade pendente de CM)
    insert into public.card_variant (card_id, variant_type_id, variant_order, is_default, created_at)
    values (kc[1], v_holo, 2, false, now() - interval '6 hours');
    k1h := kc[1]::text || ':' || v_holo::text;
    select s.id into sl_t
    from public.collection_layout_slot s join public.collection_layout_page pg on pg.id = s.page_id
    where pg.layout_id = l_m and not s.locked
      and not exists (select 1 from public.collection_layout_slot_expected_content e where e.slot_id = s.id)
      and not exists (select 1 from public.collection_layout_slot_assignment a0 where a0.slot_id = s.id)
      and not exists (select 1 from public.collection_layout_slot_image im where im.slot_id = s.id)
    order by pg.page_number desc, s.row_index desc, s.column_index desc
    limit 1;
    perform set_config('request.jwt.claim.sub', u_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    -- CG reserva manualmente a RG 3 e libera (regra 5: não pode voltar)
    perform count(*) from public.set_slot_expected_content(sl_t, g3, null, v_std, v_cg);
    perform public.clear_slot_expected_content(array[sl_t]);
    select count(*) into n from public.get_my_binder_catalog_novelties(v_cg) x where x.item_key = kg3;
    select count(*) into n2 from public.get_my_binder_catalog_novelties(v_cm) x where x.item_key = k1h;
    select count(*) into n3 from public.get_my_binder_catalog_novelties(v_cg) x where x.item_key = kg4;
    execute 'reset role';
    res := res || jsonb_build_object('id','T.0','ok', sl_t is not null and v_t0 < v_born3 and v_born3 < v_tg
      and (select l.created_at from public.collection_layout l where l.id = l_m) = v_t0
      and exists (select 1 from public.binder_catalog_positions(s_rg, array[v_std]) p
                  where p.pos_key = kg3 and p.born_at = v_born3)
      and n = 0 and n2 = 1 and n3 = 1
      and not exists (select 1 from public.collection_layout_slot_expected_content e where e.card_id = g3),
      'detail','pré-condição: RG 3 é posição do objetivo de CG (nascida depois da criação do fichário e antes da entrada de CG); reserva manual liberada; RG 3 não é novidade de CG, RG 4 (controle positivo) é; 1-HOLO é novidade de CM');

    execute 'set local role authenticated';
    select * into o from public.transfer_my_binder_ownership(v_cm, v_cg);
    execute 'reset role';
    res := res || jsonb_build_object('id','T.1','ok', o.outcome = 'TRANSFERRED'
      and (select l.collection_id from public.collection_layout l where l.id = l_m) = v_cg
      and exists (select 1 from public.collection_layout_guest g where g.collection_id = v_cm and g.layout_id = l_m)
      and (select m.marker_at = v_tg and m.role = 'OWNER' from public.collection_layout_catalog_marker m
           where m.layout_id = l_m and m.collection_id = v_cg)
      and (select m.marker_at = v_t0 and m.role = 'GUEST' from public.collection_layout_catalog_marker m
           where m.layout_id = l_m and m.collection_id = v_cm)
      and (select count(*) from public.collection_layout_catalog_marker m where m.layout_id = l_m) = 2,
      'detail','transferência CM → CG (5254 canônica): CG vira dona com o marco de quando entrou; CM vira convidada com o marco da criação do fichário; nenhum valor mudou');
    execute 'set local role authenticated';
    select count(*) into n from public.get_my_binder_catalog_novelties(v_cg) x where x.item_key = kg3;
    select count(*) into n3 from public.get_my_binder_catalog_novelties(v_cg) x where x.item_key = kg4;
    select bool_or(x.eligible) into v_ok from public.get_my_binder_catalog_novelties(v_cg) x;
    execute 'reset role';
    res := res || jsonb_build_object('id','T.2','ok', v_ok and n = 0 and n3 = 1
      and not exists (select 1 from public.collection_layout_slot_expected_content e where e.card_id = g3),
      'detail','CG agora dona e elegível: a RG 3 (reserva liberada, nascida antes da entrada de CG e depois da criação do fichário) NÃO volta; a RG 4 (controle positivo, depois da entrada) continua novidade; nenhuma reserva restaurada');
    execute 'set local role authenticated';
    select count(*) filter (where x.item_key in (k1h, k9r)),
           count(*) filter (where x.item_key in (k3r, k4h, k6r, k8h))
      into n, n2 from public.get_my_binder_catalog_novelties(v_cm) x;
    execute 'reset role';
    res := res || jsonb_build_object('id','T.3','ok', n = 2 and n2 = 0,
      'detail','CM agora convidada: 1-HOLO (nascida entre o marco de CM e a transferência) e 9-REVERSE continuam novidades; as já incorporadas não reaparecem');
    execute 'set local role authenticated';
    select * into o from public.transfer_my_binder_ownership(v_cg, v_cm);
    execute 'reset role';
    res := res || jsonb_build_object('id','T.4','ok', o.outcome = 'TRANSFERRED'
      and (select l.collection_id from public.collection_layout l where l.id = l_m) = v_cm
      and (select m.marker_at = v_t0 and m.role = 'OWNER' from public.collection_layout_catalog_marker m
           where m.layout_id = l_m and m.collection_id = v_cm)
      and (select m.marker_at = v_tg and m.role = 'GUEST' from public.collection_layout_catalog_marker m
           where m.layout_id = l_m and m.collection_id = v_cg)
      and (select count(*) from public.collection_layout_catalog_marker m where m.layout_id = l_m) = 2,
      'detail','transferência de volta CG → CM: marcos ainda iguais aos originais, papéis restaurados');

    -- T.5 Transferência para coleção que NÃO era convidada (permitida pela 5254: destino ativo,
    --     sem fichário próprio, não convidada de outro). CX participou deste fichário antes e
    --     saiu em OUTRA transação (fixture: linha encerrada com ended_xact = '1'): nada revive.
    v_old5 := now() - interval '5 days';
    execute 'set local role authenticated';
    select x.collection_id into v_cx from public.create_my_card_set_collection(gen_random_uuid(), s_rg, 'CX 5859', v_bin) x;
    execute 'reset role';
    insert into public.collection_layout_catalog_marker (layout_id, collection_id, marker_at, marker_source, role, ended_xact)
    values (l_m, v_cx, v_old5, 'GUEST_ATTACHED', 'GUEST', '1'::xid8);
    execute 'set local role authenticated';
    select * into o from public.transfer_my_binder_ownership(v_cm, v_cx);
    execute 'reset role';
    select (o.outcome = 'TRANSFERRED'
            and m.marker_at = now() and m.marker_source = 'OWNERSHIP_TRANSFER' and m.role = 'OWNER' and m.ended_xact is null)
      into v_ok
    from public.collection_layout_catalog_marker m where m.layout_id = l_m and m.collection_id = v_cx;
    execute 'set local role authenticated';
    select * into o from public.transfer_my_binder_ownership(v_cx, v_cm);
    execute 'reset role';
    res := res || jsonb_build_object('id','T.5','ok', coalesce(v_ok, false) and o.outcome = 'TRANSFERRED'
      and (select l.collection_id from public.collection_layout l where l.id = l_m) = v_cm
      and (select m.marker_at = v_t0 and m.role = 'OWNER' and m.ended_xact is null from public.collection_layout_catalog_marker m
           where m.layout_id = l_m and m.collection_id = v_cm)
      and (select m.marker_at = now() and m.role = 'GUEST' and m.ended_xact is null from public.collection_layout_catalog_marker m
           where m.layout_id = l_m and m.collection_id = v_cx),
      'detail','CM → CX (não convidada, participação anterior encerrada em outra transação): CX recebe marco = instante da transferência, não o antigo (−5 dias); de volta CX → CM: CM mantém o marco original e CX vira convidada com o marco da transferência');

    -- D. Desassociação e reassociação da convidada CH (fichário Pokédex de CP) -----------------------
    v_tch := now() - interval '3 hours';
    update public.collection_layout_catalog_marker m set marker_at = v_tch where m.layout_id = l_p and m.collection_id = v_ch;
    execute 'set local role authenticated';
    select x.detach_token into v_dtok2 from public.preview_my_collection_binder_detach(v_ch) x;
    perform count(*) from public.detach_my_collection_from_binder(v_ch, v_dtok2, false);
    execute 'reset role';
    res := res || jsonb_build_object('id','D.1','ok',
      not exists (select 1 from public.collection_layout_guest g where g.collection_id = v_ch)
      and not exists (select 1 from public.collection_layout_catalog_marker m where m.collection_id = v_ch and m.ended_xact is null)
      and exists (select 1 from public.collection_layout_catalog_marker m where m.collection_id = v_ch and m.ended_xact = pg_current_xact_id())
      and exists (select 1 from public.collection_layout_catalog_marker m where m.layout_id = l_p and m.collection_id = v_cp and m.ended_xact is null),
      'detail','desassociação (5253 canônica): participação de CH encerrada (ended_xact) ao fim do comando, sem marco ativo; marco da dona CP intacto');
    execute 'set local role authenticated';
    perform count(*) from public.attach_my_collection_to_binder(v_ch, l_p);
    execute 'reset role';
    res := res || jsonb_build_object('id','D.2','ok',
      (select m.marker_at = g.created_at and m.marker_at <> v_tch and m.marker_source = 'GUEST_ATTACHED'
              and m.role = 'GUEST' and m.ended_xact is null
       from public.collection_layout_catalog_marker m join public.collection_layout_guest g
         on g.collection_id = m.collection_id and g.layout_id = m.layout_id
       where m.layout_id = l_p and m.collection_id = v_ch)
      and (select count(*) from public.collection_layout_catalog_marker m where m.collection_id = v_ch) = 1,
      'detail','reassociação: marco novo = nova entrada (o antigo, −3 h, não é reaproveitado), uma única linha; regra igual em transação diferente (último papel GUEST)');

    -- M.4 Participantes × marcos ativos depois de T e D (mesmo critério do LIVE_90)
    res := res || jsonb_build_object('id','M.4','ok',
      not exists (
        select 1 from (select l.id as layout_id, l.collection_id from public.collection_layout l where l.id in (l_m, l_p, l_b)
                       union all
                       select g.layout_id, g.collection_id from public.collection_layout_guest g where g.layout_id in (l_m, l_p, l_b)) pp
        where not exists (select 1 from public.collection_layout_catalog_marker m
                          where m.layout_id = pp.layout_id and m.collection_id = pp.collection_id and m.ended_xact is null))
      and not exists (
        select 1 from public.collection_layout_catalog_marker m
        where m.layout_id in (l_m, l_p, l_b) and m.ended_xact is null
          and not exists (select 1 from public.collection_layout l where l.id = m.layout_id and l.collection_id = m.collection_id)
          and not exists (select 1 from public.collection_layout_guest g where g.layout_id = m.layout_id and g.collection_id = m.collection_id))
      and (select count(*) from public.collection_layout_catalog_marker m where m.layout_id in (l_m, l_p, l_b) and m.ended_xact is null) = 6,
      'detail','participantes = marcos ativos (CM, CG, CX, CP, CH, CB): nenhum participante sem marco, nenhum marco ativo sem participante');

    -- M.3 Sem marco → inelegível (fail-closed, nenhuma data substituta)
    delete from public.collection_layout_catalog_marker m where m.layout_id = l_b and m.collection_id = v_cb;
    perform set_config('request.jwt.claim.sub', u_b::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    select * into o from public.get_my_binder_catalog_novelties(v_cb);
    v_err := null; v_hint := null;
    begin perform count(*) from public.preview_my_binder_catalog_reconciliation(v_cb, null);
    exception when others then v_err := sqlerrm; get stacked diagnostics v_hint = pg_exception_hint; end;
    execute 'reset role';
    insert into public.collection_layout_catalog_marker (layout_id, collection_id, marker_at, marker_source, role)
    select l.id, l.collection_id, l.created_at, 'BACKFILL_OWNER', 'OWNER' from public.collection_layout l where l.id = l_b;
    perform set_config('request.jwt.claim.sub', u_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    res := res || jsonb_build_object('id','M.3','ok', not o.eligible and o.reason = 'MARKER_MISSING'
      and v_err = 'BINDER_NOT_ELIGIBLE' and v_hint = 'MARKER_MISSING',
      'detail','marco ausente: aviso inelegível (MARKER_MISSING) e prévia → BINDER_NOT_ELIGIBLE/MARKER_MISSING; nenhuma data alternativa');

    -- 11. Argumentos, autorização e isolamento ------------------------------------------------------
    execute 'set local role authenticated';
    v_err := null; begin perform count(*) from public.preview_my_binder_catalog_reconciliation(null, null); exception when others then v_err := sqlerrm; end;
    v_err2 := null; begin perform count(*) from public.preview_my_binder_catalog_reconciliation(v_cm, '{}'::text[]); exception when others then v_err2 := sqlerrm; end;
    v_err3 := null; begin perform count(*) from public.apply_my_binder_catalog_reconciliation(v_cm, null, 'abc', true, true); exception when others then v_err3 := sqlerrm; end;
    res := res || jsonb_build_object('id','11.1','ok', v_err = 'INVALID_ARGUMENT' and v_err2 = 'INVALID_ARGUMENT' and v_err3 = 'INVALID_ARGUMENT',
      'detail','coleção nula, seleção vazia e token malformado → INVALID_ARGUMENT: ' || concat_ws(' / ', v_err, v_err2, v_err3));
    v_err := null; begin perform count(*) from public.preview_my_binder_catalog_reconciliation(v_cm, array['00000000-0000-0000-0000-000000000000:*']);
    exception when others then v_err := sqlerrm; end;
    v_err2 := null; begin perform count(*) from public.apply_my_binder_catalog_reconciliation(v_cm, array['00000000-0000-0000-0000-000000000000:*'], 'rc1:' || repeat('0', 64), true, true);
    exception when others then v_err2 := sqlerrm; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','11.2','ok', v_err = 'SELECTION_INVALID' and v_err2 = 'SELECTION_INVALID',
      'detail','chave que não é novidade (prévia e aplicação) → SELECTION_INVALID');
    execute 'set local role anon';
    v_ok := true;
    begin perform count(*) from public.apply_my_binder_catalog_reconciliation(v_cm, null, 'rc1:' || repeat('0', 64), true, true); v_ok := false;
    exception when insufficient_privilege then null; end;
    begin perform count(*) from public.get_my_binder_catalog_novelties(v_cm); v_ok := false;
    exception when insufficient_privilege then null; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','11.3','ok', v_ok, 'detail','anon não executa aplicação nem aviso (42501)');
    perform set_config('request.jwt.claim.sub', u_b::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    v_err := null; begin perform count(*) from public.get_my_binder_catalog_novelties(v_cg); exception when others then v_err := sqlerrm; end;
    v_err2 := null; begin perform count(*) from public.preview_my_binder_catalog_reconciliation(v_cg, null); exception when others then v_err2 := sqlerrm; end;
    v_err3 := null; begin perform count(*) from public.apply_my_binder_catalog_reconciliation(v_cg, null, 'rc1:' || repeat('0', 64), true, true);
    exception when others then v_err3 := sqlerrm; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','11.4','ok', v_err = 'COLLECTION_NOT_FOUND' and v_err2 = 'COLLECTION_NOT_FOUND' and v_err3 = 'COLLECTION_NOT_FOUND',
      'detail','B na convidada CG de A (aviso/prévia/aplicação) → COLLECTION_NOT_FOUND: ' || concat_ws(' / ', v_err, v_err2, v_err3));
    perform set_config('request.jwt.claim.sub', u_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    v_ok := true;
    begin perform count(*) from public.collection_layout_catalog_incorporation; v_ok := false;
    exception when insufficient_privilege then null; end;
    begin insert into public.collection_layout_catalog_incorporation (layout_id, collection_id, item_key) values (l_m, v_cm, k9r); v_ok := false;
    exception when insufficient_privilege then null; end;
    begin update public.collection_layout_catalog_incorporation set incorporated_at = now(); v_ok := false;
    exception when insufficient_privilege then null; end;
    begin delete from public.collection_layout_catalog_incorporation; v_ok := false;
    exception when insufficient_privilege then null; end;
    execute 'reset role';
    execute 'set local role anon';
    begin perform count(*) from public.collection_layout_catalog_incorporation; v_ok := false;
    exception when insufficient_privilege then null; end;
    begin insert into public.collection_layout_catalog_incorporation (layout_id, collection_id, item_key) values (l_m, v_cm, k9r); v_ok := false;
    exception when insufficient_privilege then null; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','11.5','ok', v_ok
      and (select count(*) from public.collection_layout_catalog_incorporation i where i.layout_id = l_m) = 5,
      'detail','tabela 5263: o próprio dono (authenticated) não lê, insere, altera nem apaga; anon não lê nem insere (42501); registros intactos');
    execute 'set local role authenticated';
    v_ok := true;
    begin perform count(*) from public.collection_layout_catalog_marker; v_ok := false;
    exception when insufficient_privilege then null; end;
    begin insert into public.collection_layout_catalog_marker (layout_id, collection_id, marker_at, marker_source, role)
          values (l_b, v_cm, now(), 'GUEST_ATTACHED', 'GUEST'); v_ok := false;
    exception when insufficient_privilege then null; end;
    begin update public.collection_layout_catalog_marker set marker_at = now(); v_ok := false;
    exception when insufficient_privilege then null; end;
    begin delete from public.collection_layout_catalog_marker; v_ok := false;
    exception when insufficient_privilege then null; end;
    execute 'reset role';
    execute 'set local role anon';
    begin perform count(*) from public.collection_layout_catalog_marker; v_ok := false;
    exception when insufficient_privilege then null; end;
    begin update public.collection_layout_catalog_marker set marker_at = now(); v_ok := false;
    exception when insufficient_privilege then null; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','11.6','ok', v_ok
      and (select m.marker_at = v_t0 from public.collection_layout_catalog_marker m where m.layout_id = l_m and m.collection_id = v_cm),
      'detail','tabela de marcos: o dono (authenticated) não lê, insere, altera nem apaga; anon não lê nem altera (42501); marcos intactos');

    -- 8. Arquivada -----------------------------------------------------------------------------------
    perform set_config('request.jwt.claim.sub', u_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    perform count(*) from public.archive_collection(v_cg);
    select * into o from public.get_my_binder_catalog_novelties(v_cg);
    v_err := null; begin perform count(*) from public.preview_my_binder_catalog_reconciliation(v_cg, null);
    exception when others then v_err := sqlerrm; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','8.1','ok', not o.eligible and o.reason = 'COLLECTION_ARCHIVED' and v_err = 'COLLECTION_ARCHIVED',
      'detail','convidada arquivada: aviso inelegível; prévia → ' || coalesce(v_err, 'sem erro'));
    -- 8.2 Fichário COM referências de espécie (dona Pokédex CP) e a Master Set convidada CH
    execute 'set local role authenticated';
    select x.plan_token into v_tok2 from public.preview_my_binder_species_references(v_cp) x;
    perform count(*) from public.apply_my_binder_species_references(v_cp, v_tok2);
    execute 'reset role';
    select count(*), md5(coalesce(string_agg(r.slot_id::text || ':' || r.pokedex_position_id::text, '|' order by r.slot_id), ''))
      into n, v_md5sr from public.collection_layout_slot_species_reference r where r.layout_id = l_p;
    execute 'set local role authenticated';
    select * into o from public.get_my_binder_catalog_novelties(v_ch);
    v_err := null; begin perform count(*) from public.apply_my_binder_catalog_reconciliation(v_ch, null, 'rc1:' || repeat('0', 64), true, true);
    exception when others then v_err := sqlerrm; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','8.2','ok', n > 0 and not o.eligible and o.reason = 'BINDER_OWNER_POKEDEX'
      and v_err = 'BINDER_NOT_ELIGIBLE'
      and (select md5(coalesce(string_agg(r.slot_id::text || ':' || r.pokedex_position_id::text, '|' order by r.slot_id), ''))
           from public.collection_layout_slot_species_reference r where r.layout_id = l_p) = v_md5sr,
      'detail', format('fichário Pokédex com %s referências: CH (Master Set convidada, com novidade RG 2) inelegível; aplicação → %s; referências intactas', n, coalesce(v_err, 'sem erro')));

    -- I.8 Ciclo de vida: desmontagem do fichário B (RPC canônica 5226/5242) apaga o registro por cascata
    perform set_config('request.jwt.claim.sub', u_b::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    select x.dismantle_token into v_dtok from public.preview_my_collection_binder_dismantle(v_cb) x;
    perform count(*) from public.dismantle_my_collection_binder(v_cb, v_dtok);
    execute 'reset role';
    res := res || jsonb_build_object('id','I.8','ok',
      not exists (select 1 from public.collection_layout l where l.id = l_b)
      and not exists (select 1 from public.collection_layout_catalog_incorporation i where i.layout_id = l_b or i.collection_id = v_cb)
      and not exists (select 1 from public.collection_layout_catalog_marker m where m.layout_id = l_b or m.collection_id = v_cb)
      and (select count(*) from public.collection_layout_catalog_incorporation i where i.layout_id = l_m) = 5,
      'detail','W5/A7: desmontagem do fichário B (sem alteração na 5242) apaga o registro da 522-HOLO e o marco de CB por ON DELETE CASCADE; registros do fichário A intactos (5)');

    raise exception 'MS859' using errcode = 'P0001';
  exception when others then
    if sqlerrm <> 'MS859' then
      res := res || jsonb_build_object('id','X.1','ok', false, 'detail','erro inesperado: '||sqlstate||' '||sqlerrm);
    end if;
  end;

  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  select array[(select count(*) from auth.users), (select count(*) from public.collection),
               (select count(*) from public.collection_allocation), (select count(*) from public.physical_card),
               (select count(*) from public.storage_container), (select count(*) from public.collection_layout),
               (select count(*) from public.collection_layout_page), (select count(*) from public.collection_layout_slot),
               (select count(*) from public.collection_layout_slot_assignment),
               (select count(*) from public.collection_layout_slot_expected_content),
               (select count(*) from public.collection_layout_region),
               (select count(*) from public.collection_layout_slot_species_reference),
               (select count(*) from public.collection_layout_catalog_incorporation),
               (select count(*) from public.collection_layout_catalog_marker),
               (select count(*) from public.card), (select count(*) from public.card_variant)]
    into e_counts;
  res := res || jsonb_build_object('id','99.1','ok', b_counts = e_counts and current_user = session_user,
    'detail','resíduo zero (16 tabelas, incluindo as 2 da 5263) e papel restaurado');
  end if;

  for r in select * from jsonb_array_elements(res) loop
    cnt := cnt + 1;
    if (r ->> 'ok')::boolean then passes := passes + 1; end if;
    seq := cnt; check_id := r ->> 'id';
    status := case when (r ->> 'ok')::boolean then 'PASS' else 'FAIL' end;
    detail := r ->> 'detail';
    return next;
  end loop;
  seq := cnt + 1; check_id := 'GATE';
  status := case when passes = cnt and cnt = v_expected then 'PASS' else 'FAIL' end;
  detail := passes || '/' || cnt || ' PASS (esperado ' || v_expected || ')';
  return next;
end;
$fn$;
