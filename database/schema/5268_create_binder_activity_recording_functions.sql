/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5268 - P3-B S1 · Histórico do Fichário — gravação interna
              binder_activity_begin(uuid, text, text, uuid, jsonb)
              binder_activity_add_item(text, text, uuid, uuid, uuid, uuid, integer, integer, jsonb)
              binder_activity_end()
Versão......: 1.2 (2026-10-25, P3-B-S1-LIVE-DRYRUN-STRUCTURAL-CORRECTION-02: W1 —
              folga de repetição de deslocamento e recálculo em PAGE_ADDED)
              1.1 (P3-B-S1-SECURITY-CORRECTION-01: W1 teto por capacidade)
Status......: EXECUTADA / CANÔNICA. Aplicada no LIVE mimikyu-core em 2026-10-27
              (P3-B S1, autorização expressa de Fabrício — G8; G5b/G5c dispensados
              sob H-A só para a S1; ledger 20261027024731 `5268_create_binder_activity_recording_functions`). Do `begin;` ao `commit;`
              idêntica ao arquivo de database/proposals/2026-10-25-p3b-binder-
              activity-history/ (só este bloco Status difere); enviada via
              apply_migration sem as linhas `begin;`/`commit;` externas — o texto
              gravado no ledger é igual ao corpo do arquivo da proposta (md5).
              LIVE_90 12/12. Harness 5860 NÃO EXECUTADO (H-A). Ver README §28.34.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-25
Autoridade..: C-205 (operação lógica), C-206 (atomicidade/idempotência);
              LDM-199–LDM-201; README v1.2 §7.2, §8.

Funções INTERNAS: SECURITY DEFINER, search_path vazio, EXECUTE revogado de
PUBLIC/anon/authenticated/service_role. Na S1 nenhuma função homologada as
chama — elas só passam a ser usadas nas fatias S2–S6, que recriam as funções
instrumentadas com diff mínimo (begin no início do caminho de sucesso,
add_item para cada efeito, end antes de cada RETURN).

Contrato de contexto (uma operação lógica por chamada do cliente, C-205):
  · Contexto guardado na configuração local da transação
    mmkyu.binder_activity_ctx (json). set_config(..., true): some no fim da
    transação e é desfeito com a subtransação que falhar.
  · begin em profundidade 0 abre a operação (parâmetros pendentes, sem linha
    gravada). begin com operação aberta só aumenta a profundidade: a função
    interna (ex.: add_layout_page chamada por insert_my_binder_gap) acrescenta
    ITENS ao evento externo e nunca cria evento próprio — sem duplicidade.
    Fichário diferente do da operação aberta → erro (nunca mistura).
  · add_item cria o cabeçalho do evento no PRIMEIRO item (gravação preguiçosa):
    operação sem efeito (repetição idempotente, lista vazia, UNCHANGED) não
    grava nada (C-206).
  · end diminui a profundidade; em 0 limpa o contexto, de modo que duas
    operações na mesma transação geram dois eventos.
  · Titular = dono do fichário no momento do primeiro item; precisa ser o
    usuário autenticado (V1: ator = titular). Sem sessão → erro.
  · Posições: add_item recebe os bolsos (slot) e os converte JÁ em página,
    linha e coluna (cópia, R3). Deve ser chamado antes de apagar ou
    renumerar o bolso/página de origem e depois de gravar o destino.
  · Carta: cópia de nome, número, código do Set e acabamento no momento.
  · Limite de itens DERIVADO DA CAPACIDADE do fichário (W1, v1.1), nunca
    um número fixo. Fundamento: cada item descreve um efeito distinto sobre
    um objeto distinto do fichário (contrato W3, regra I-7: nenhum objeto
    repete o mesmo efeito numa operação). Por bolso há no máximo 4 objetos
    capazes de gerar item — carta, reserva, trava e imagem do bolso — e cada
    um pode, numa mesma operação, sair (o ocupante anterior) e entrar (o
    novo): no máximo 8 itens por bolso. Por página, no máximo 2 efeitos
    (criada/removida e renumerada); por operação, no máximo 8 itens de
    coleção/fichário. Parcela de capacidade:
        páginas × (8 × linhas × colunas + 2) + 8
    (a grade é imutável, 5107; bolsos = páginas × linhas × colunas; 1 objeto
    de cada tipo por bolso: UNIQUE(slot_id) em assignment, expected_content e
    slot_image; locked é coluna do bolso — leitura LIVE 2026-10-25).
    Folga de repetição (v1.2): a reconciliação do Catálogo (E16) desloca o
    mesmo objeto várias vezes numa operação (uma vez por novidade); a
    própria 5264 limita a soma de linhas movidas a 500 e as novidades a
    100. A instrumentação aninhada gera um item por deslocamento (R5), o que
    pode exceder a parcela de capacidade num fichário pequeno. Por isso
        teto = parcela de capacidade + c_repeat_slack (600 = 500 + 100)
    e o static_check (S.14) exige c_repeat_slack ≥ c_row_limit + c_item_limit
    da 5264 e ≥ c_row_limit da 5243. Exemplo: o maior fichário do LIVE
    (1.056 bolsos) admite ≥ 9.048 itens; um 2×2 de 2 páginas, 676.
    O teto é calculado no primeiro item e guardado no contexto; é
    RECALCULADO (v1.2) em todo item PAGE/PAGE_ADDED — gravado depois de criar
    a página (I-10), então já inclui seus bolsos — e sempre que excedido. Só
    cresce (máximo observado — nunca diminui quando páginas/bolsos são
    apagados depois de registrados). Só então, se ainda excedido, erro explícito
    BINDER_ACTIVITY_ITEM_LIMIT: indica defeito de instrumentação (efeito
    duplicado ou laço), nunca uma operação legítima; nunca truncamento
    silencioso. Proteção contra crescimento excessivo: o histórico de uma
    operação fica linear no tamanho do fichário, que já é limitado pelos
    caps das próprias operações (500 por chamada, 10.000 alocações e 20.000
    bolsos na montagem, 100 novidades por reconciliação).

Dependências: 5267; collection_layout, collection, collection_layout_page,
collection_layout_slot, card, card_set, card_variant_type.
================================================================
*/
begin;

do $pre$
begin
  if to_regclass('public.binder_activity_event') is null then
    raise exception 'PRECHECK 5268: aplique a 5267 antes';
  end if;
  if to_regprocedure('public.binder_activity_begin(uuid, text, text, uuid, jsonb)') is not null
     or to_regprocedure('public.binder_activity_end()') is not null then
    raise exception 'PRECHECK 5268: funções de gravação já existem';
  end if;
end;
$pre$;

-- begin ----------------------------------------------------------------------------------
create function public.binder_activity_begin(
  p_layout_id     uuid,
  p_event_type    text,
  p_source        text,
  p_collection_id uuid  default null,
  p_summary       jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_ctx jsonb := nullif(current_setting('mmkyu.binder_activity_ctx', true), '')::jsonb;
begin
  if p_layout_id is null or p_event_type is null or p_source is null then
    raise exception 'binder activity: layout, type and source are required' using errcode = '22004';
  end if;
  if v_ctx is not null and (v_ctx ->> 'depth')::integer > 0 then
    if (v_ctx ->> 'layout')::uuid <> p_layout_id then
      raise exception 'binder activity: nested operation on another binder' using errcode = 'P0001',
        hint = 'BINDER_ACTIVITY_NESTED_LAYOUT';
    end if;
    v_ctx := jsonb_set(v_ctx, '{depth}', to_jsonb((v_ctx ->> 'depth')::integer + 1));
  else
    v_ctx := jsonb_build_object(
      'depth', 1, 'layout', p_layout_id, 'type', p_event_type, 'source', p_source,
      'collection', p_collection_id, 'summary', coalesce(p_summary, '{}'::jsonb),
      'event_id', null, 'n', 0, 'cap', 0);
  end if;
  perform set_config('mmkyu.binder_activity_ctx', v_ctx::text, true);
end;
$fn$;

-- add_item -------------------------------------------------------------------------------
create function public.binder_activity_add_item(
  p_kind            text,
  p_effect          text,
  p_card_id         uuid    default null,
  p_variant_type_id uuid    default null,
  p_from_slot_id    uuid    default null,
  p_to_slot_id      uuid    default null,
  p_from_page       integer default null,
  p_to_page         integer default null,
  p_detail          jsonb   default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_ctx      jsonb := nullif(current_setting('mmkyu.binder_activity_ctx', true), '')::jsonb;
  v_uid      uuid  := (select auth.uid());
  v_layout   uuid;
  v_event    bigint;
  v_n        integer;
  v_cap      bigint;
  v_cap_now  bigint;
  c_repeat_slack constant integer := 600;   -- ≥ 5264 c_row_limit (500) + c_item_limit (100); ≥ 5243 c_row_limit (500)
  v_owner    uuid;
  v_binder   text;
  v_coll     uuid;
  v_collname text;
  f_page int; f_row int; f_col int;
  t_page int; t_row int; t_col int;
  c_name text; c_num text; c_set text; vt_code text; vt_name text;
begin
  if v_ctx is null or (v_ctx ->> 'depth')::integer < 1 then
    raise exception 'binder activity: no open operation' using errcode = 'P0001', hint = 'BINDER_ACTIVITY_NO_CONTEXT';
  end if;
  if v_uid is null then
    raise exception 'binder activity requires an authenticated actor' using errcode = '28000';
  end if;
  v_layout := (v_ctx ->> 'layout')::uuid;
  v_event  := (v_ctx ->> 'event_id')::bigint;
  v_n      := (v_ctx ->> 'n')::integer + 1;
  v_cap    := coalesce((v_ctx ->> 'cap')::bigint, 0);

  -- W1: teto derivado da capacidade + folga de repetição (ver cabeçalho). Calculado no
  -- primeiro item (cap = 0), em todo PAGE_ADDED e quando excedido; guarda o máximo observado.
  if v_n > v_cap or (p_kind = 'PAGE' and p_effect = 'PAGE_ADDED') then
    select count(p.id) * (8::bigint * l.grid_rows * l.grid_columns + 2) + 8 + c_repeat_slack
      into v_cap_now
    from public.collection_layout l
    left join public.collection_layout_page p on p.layout_id = l.id
    where l.id = v_layout
    group by l.grid_rows, l.grid_columns;
    v_cap := greatest(v_cap, coalesce(v_cap_now, 8 + c_repeat_slack));
    if v_n > v_cap then
      raise exception 'binder activity: item limit exceeded (% > %)', v_n, v_cap using errcode = 'P0001',
        hint = 'BINDER_ACTIVITY_ITEM_LIMIT';
    end if;
    v_ctx := jsonb_set(v_ctx, '{cap}', to_jsonb(v_cap));
  end if;

  if v_event is null then
    -- Cabeçalho no primeiro item: titular e nomes copiados agora.
    select c.owner_user_id, coalesce(nullif(l.display_name, ''), c.name)
      into v_owner, v_binder
    from public.collection_layout l
    join public.collection c on c.id = l.collection_id
    where l.id = v_layout;
    if v_owner is null then
      raise exception 'binder activity: binder not found' using errcode = 'P0002', hint = 'BINDER_ACTIVITY_LAYOUT_NOT_FOUND';
    end if;
    if v_owner <> v_uid then
      raise exception 'binder activity: actor is not the binder owner' using errcode = '42501',
        hint = 'BINDER_ACTIVITY_NOT_OWNER';
    end if;
    v_coll := nullif(v_ctx ->> 'collection', '')::uuid;
    if v_coll is not null then
      select c.name into v_collname from public.collection c where c.id = v_coll and c.owner_user_id = v_owner;
    end if;
    insert into public.binder_activity_event
      (owner_user_id, layout_key, actor_user_id, event_type, source,
       collection_id, collection_name, binder_name, summary)
    values
      (v_owner, v_layout, v_uid, v_ctx ->> 'type', v_ctx ->> 'source',
       case when v_collname is not null then v_coll end, left(v_collname, 200), left(v_binder, 200),
       coalesce(v_ctx -> 'summary', '{}'::jsonb))
    returning id into v_event;
    v_ctx := jsonb_set(v_ctx, '{event_id}', to_jsonb(v_event));
  end if;

  -- Posições copiadas agora (R3); bolso de outro fichário → erro.
  if p_from_slot_id is not null then
    select p.page_number, s.row_index, s.column_index into f_page, f_row, f_col
    from public.collection_layout_slot s join public.collection_layout_page p on p.id = s.page_id
    where s.id = p_from_slot_id and p.layout_id = v_layout;
    if f_page is null then
      raise exception 'binder activity: origin pocket not in binder' using errcode = 'P0001', hint = 'BINDER_ACTIVITY_SLOT';
    end if;
  else
    f_page := p_from_page;
  end if;
  if p_to_slot_id is not null then
    select p.page_number, s.row_index, s.column_index into t_page, t_row, t_col
    from public.collection_layout_slot s join public.collection_layout_page p on p.id = s.page_id
    where s.id = p_to_slot_id and p.layout_id = v_layout;
    if t_page is null then
      raise exception 'binder activity: target pocket not in binder' using errcode = 'P0001', hint = 'BINDER_ACTIVITY_SLOT';
    end if;
  else
    t_page := p_to_page;
  end if;

  -- Cópia da carta e do acabamento.
  if p_card_id is not null then
    select k.name, k.collector_number, cs.code into c_name, c_num, c_set
    from public.card k join public.card_set cs on cs.id = k.card_set_id
    where k.id = p_card_id;
    if c_name is null then
      raise exception 'binder activity: card not found' using errcode = 'P0002', hint = 'BINDER_ACTIVITY_CARD';
    end if;
  end if;
  if p_variant_type_id is not null then
    select t.code, t.name into vt_code, vt_name from public.card_variant_type t where t.id = p_variant_type_id;
  end if;

  insert into public.binder_activity_item
    (event_id, ordinal, item_kind, effect, card_id, card_name, collector_number, card_set_code,
     variant_type_code, variant_type_name, from_page, from_row, from_col, to_page, to_row, to_col, detail)
  values
    (v_event, v_n, p_kind, p_effect, p_card_id, left(c_name, 200), left(c_num, 40), left(c_set, 40),
     left(vt_code, 60), left(vt_name, 120), f_page, f_row, f_col, t_page, t_row, t_col, p_detail);

  v_ctx := jsonb_set(v_ctx, '{n}', to_jsonb(v_n));
  perform set_config('mmkyu.binder_activity_ctx', v_ctx::text, true);
end;
$fn$;

-- end ------------------------------------------------------------------------------------
create function public.binder_activity_end()
returns void
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_ctx jsonb := nullif(current_setting('mmkyu.binder_activity_ctx', true), '')::jsonb;
  v_depth integer;
begin
  if v_ctx is null or (v_ctx ->> 'depth')::integer < 1 then
    raise exception 'binder activity: no open operation' using errcode = 'P0001', hint = 'BINDER_ACTIVITY_NO_CONTEXT';
  end if;
  v_depth := (v_ctx ->> 'depth')::integer - 1;
  if v_depth = 0 then
    perform set_config('mmkyu.binder_activity_ctx', '', true);
  else
    perform set_config('mmkyu.binder_activity_ctx', jsonb_set(v_ctx, '{depth}', to_jsonb(v_depth))::text, true);
  end if;
end;
$fn$;

revoke all on function public.binder_activity_begin(uuid, text, text, uuid, jsonb) from public, anon, authenticated, service_role;
revoke all on function public.binder_activity_add_item(text, text, uuid, uuid, uuid, uuid, integer, integer, jsonb) from public, anon, authenticated, service_role;
revoke all on function public.binder_activity_end() from public, anon, authenticated, service_role;

comment on function public.binder_activity_begin(uuid, text, text, uuid, jsonb) is
  'P3-B 5268 (interna): abre a operação lógica ou entra numa já aberta (C-205). Sem gravação até o primeiro item.';
comment on function public.binder_activity_add_item(text, text, uuid, uuid, uuid, uuid, integer, integer, jsonb) is
  'P3-B 5268 (interna): acrescenta um efeito à operação aberta; cria o cabeçalho no primeiro item; copia carta e posições no momento (R3).';
comment on function public.binder_activity_end() is
  'P3-B 5268 (interna): fecha um nível da operação; em profundidade 0 limpa o contexto.';

commit;
