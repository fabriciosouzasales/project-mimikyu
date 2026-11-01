/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5342 - Fichário (P2): plano determinístico da organização automática
Versão......: 1.2
Status......: EXECUTADA / CANÔNICA. Aplicada no LIVE mimikyu-core em 2026-11-01
              (P2 LIVE GATE 02, ledger 20261101140019 `p2_5342_create_binder_auto_arrange_plan`). Do `begin;` ao fim
              idêntica ao arquivo de database/proposals/2026-11-01-binder-auto-arrange/
              (só este bloco Status difere). md5 do corpo instalado = arquivo:
              990a31bb415ccad493a0e4aaad53dcee (GATE 04 SRC). Harness 5872 v1.5 54/54 PASS (GATE 03 RERUN-15);
              postcheck e medição ME3 PASS (GATE 04). Homologada em
              P2 SQL FOUNDATION CLOSEOUT-16. Ver README da proposta.
              Histórico da proposta: (FOUNDATION-06, 2026-11-01; v1.1 TARGETED SQL
              SAFETY AUDIT-07: graus agregados sem subconsulta correlata; token com
              época da última organização aplicada; v1.2 TOKEN & CONCURRENCY
              CLOSEOUT-08: época inclui o marco de cobertura do histórico)
Autor.......: Fabrício Sales / Claude
Data........: 2026-11-01

Objetivo
  Função INTERNA (sem grant a nenhum papel de API) que calcula, sem escrever
  nada, o plano da organização automática de um fichário para a sua coleção
  PROPRIETÁRIA. É a única fonte de verdade do plano: a prévia (5343) e a
  aplicação (5344) chamam esta mesma função — a aplicação, depois de travar,
  recalcula e compara o token (C-220..C-226).

Assinatura
  public.binder_auto_arrange_plan(p_collection_id uuid, p_layout_id uuid, p_container_id uuid)
  returns table (item_kind, ord, slot_id, physical_card_id, page_number,
                 row_index, column_index, card_id, card_variant_id, reason,
                 insert_count, plan_token)
  LANGUAGE sql · STABLE · SECURITY INVOKER · search_path ''.
  Só é chamada de dentro das funções SECURITY DEFINER 5343/5344, que já
  validaram sessão, titularidade, tipo, estado e fichário. Por isso não repete
  auth.uid(): roda com o papel dono das chamadoras.

Linhas devolvidas
  HEADER          exatamente 1 · insert_count e plan_token preenchidos.
  INSERT          par bolso ↔ exemplar a criar (1:1 estrito), ord 1..n na
                  ordem física página → linha → coluna → slot_id.
  EXCLUDED_CARD   exemplar elegível (alocado à proprietária, no local do
                  fichário, fora de qualquer bolso) que não será posicionado.
  UNFILLED_SLOT   bolso elegível (reservado, vazio, livre) que ficará vazio.

Bolso elegível (D4)
  · pertence a uma página do layout;
  · tem reserva (collection_layout_slot_expected_content) da PROPRIETÁRIA:
    e.collection_id is null (padrão do titular) ou = p_collection_id —
    reservas de convidadas (e.collection_id = convidada) ficam de fora (D2);
  · não está travado; não tem posição; não tem imagem personalizada;
  · não está coberto por mesclagem (collection_layout_region).

Exemplar candidato (D3)
  · alocado à coleção proprietária (collection_allocation.collection_id);
  · physical_card.storage_container_id = local do fichário;
  · inventário do mesmo titular da coleção (exemplar que saiu do acervo,
    inventory_id null, nunca entra);
  · fora de qualquer bolso (de qualquer fichário).

Compatibilidade (granularidade da reserva)
  card_variant.card_id = e.card_id
  e (e.card_variant_id is null or = pc.card_variant_id)           -- variante exata
  e (e.expected_variant_type_id is null or = cv.variant_type_id)  -- carta + acabamento

1:1 estrito nos dois sentidos (D5/D6)
  Graus calculados sobre TODOS os pares compatíveis (inclusive os de variante
  inativa — um exemplar inativo continua sendo uma cópia física que torna a
  escolha ambígua). INSERT ⇔ grau do bolso = 1 ∧ grau do exemplar = 1 ∧
  variante ativa. Nenhum desempate arbitrário.

Motivos
  EXCLUDED_CARD: INACTIVE_VARIANT · NO_COMPATIBLE_RESERVATION ·
                 MULTIPLE_DESTINATIONS (grau do exemplar > 1) ·
                 COMPETING_CANDIDATES (único destino disputado por outro exemplar)
  UNFILLED_SLOT: NO_CANDIDATE · COMPETING_CANDIDATES (grau do bolso > 1) ·
                 MULTIPLE_DESTINATIONS (único candidato com mais de um destino) ·
                 INACTIVE_VARIANT (único par usa variante inativa)

Token ('aa1:' + SHA-256 hex) — v1.1
  Cobre: marcador de versão, coleção, layout, local, ÉPOCA, quantidade e a
  lista ordenada de pares INSERT (slot_id|physical_card_id). Exclusões e
  bolsos vazios NÃO entram: o usuário confirma exatamente o conjunto de
  inserções. Qualquer mudança desse conjunto (exemplar movido, bolso ocupado,
  reserva alterada, variante desativada, nova cópia que cria ambiguidade) muda
  o token.
  ÉPOCA (v1.2) = (id do último evento CARDS_AUTO_ARRANGED deste fichário e
  titular, 0 se nenhum) + (marco binder_activity_coverage do par titular ×
  fichário: motivo e updated_at em microssegundos UTC, '-' se não houver).
  Por que o marco: eventos só podem ser apagados pela exclusão definitiva
  (5270, porta única aberta pelo gatilho de imutabilidade 5267) ou pela
  exclusão da conta (titular deixa de existir). A 5270 apaga os eventos e,
  na MESMA transação, grava o marco com updated_at = now(); logo, depois de
  uma limpeza a época nunca volta a um valor anterior, mesmo que o id máximo
  regrida. Um token emitido antes da limpeza nunca coincide com um plano
  recalculado depois dela → PLAN_CHANGED (nunca reautorização silenciosa).
  Nenhuma infraestrutura nova: ambos os valores já existem (5267/5270). Toda aplicação bem-sucedida grava um evento novo e, portanto,
  muda a época: um token já aplicado nunca volta a ser recalculado, mesmo que
  o mesmo conjunto de pares reapareça depois de alterações legítimas. Isso dá
  à 5344 uma regra verificável: token divergente que consta do resumo de um
  evento deste fichário = confirmação repetida (ALREADY_APPLIED); qualquer
  outra divergência = PLAN_CHANGED. Nova intenção exige nova prévia.

Desempenho (v1.1)
  Bolsos: índice da página por layout → slots por (page_id, …) → reserva,
  posição, imagem por PK/UNIQUE de slot_id; mesclagem por ix_..._region_page.
  Candidatos: ix_collection_allocation_collection → physical_card, inventory,
  card_variant por PK; anti-junção pela UNIQUE de physical_card_id.
  Pares: junção hash por card_id; graus por GROUP BY (sdeg/cdeg) e motivos por
  junções hash — sem subconsulta correlata. Custo O(S + C + P), com P = Σ por
  carta (bolsos reservados × cópias); P só cresce além de S + C quando a mesma
  carta tem várias reservas e várias cópias, que é justamente o caso ambíguo.
  Época: ix_bae_owner_layout_time (owner_user_id, layout_key, …) e PK de
  binder_activity_coverage (owner_user_id, layout_key).
  Medição: harness 5872, P.6; plano real no LIVE só por EXPLAIN em leitura
  (ver README, critérios de entrada).

Resultado esperado: função criada, sem EXECUTE para PUBLIC/anon/authenticated/service_role.
Como validar: harness 5872, S0.1–S0.4.
================================================================
*/

begin;

do $pre$
begin
  if to_regprocedure('public.binder_auto_arrange_plan(uuid,uuid,uuid)') is not null then
    raise exception 'PRECHECK 5342: função já existe';
  end if;
  if not exists (select 1 from information_schema.columns
                 where table_schema = 'public' and table_name = 'collection_layout_slot_expected_content'
                   and column_name in ('expected_variant_type_id','collection_id')
                 having count(*) = 2) then
    raise exception 'PRECHECK 5342: expected_content sem expected_variant_type_id/collection_id (5225/5229)';
  end if;
  if not exists (select 1 from information_schema.columns
                 where table_schema = 'public' and table_name = 'collection_layout_slot_assignment'
                   and column_name = 'physical_card_id') then
    raise exception 'PRECHECK 5342: assignment sem physical_card_id (5248)';
  end if;
  if to_regclass('public.binder_activity_event') is null or to_regclass('public.binder_activity_coverage') is null then
    raise exception 'PRECHECK 5342: histórico do fichário (5267) ausente — a época do token depende dele';
  end if;
end;
$pre$;

create function public.binder_auto_arrange_plan(
  p_collection_id uuid,
  p_layout_id     uuid,
  p_container_id  uuid
)
returns table (
  item_kind        text,     -- HEADER | INSERT | EXCLUDED_CARD | UNFILLED_SLOT
  ord              integer,
  slot_id          uuid,
  physical_card_id uuid,
  page_number      integer,
  row_index        integer,
  column_index     integer,
  card_id          uuid,
  card_variant_id  uuid,
  reason           text,
  insert_count     integer,
  plan_token       text
)
language sql
stable
security invoker
set search_path = ''
as $fn$
  with
  owner_ as (
    select c.owner_user_id as uid
    from public.collection c
    where c.id = p_collection_id
  ),
  slots as (
    select s.id as sid, p.page_number as pg, s.row_index as rw, s.column_index as cl,
           e.card_id as e_card, e.card_variant_id as e_var, e.expected_variant_type_id as e_vt
    from public.collection_layout_page p
    join public.collection_layout_slot s on s.page_id = p.id
    join public.collection_layout_slot_expected_content e on e.slot_id = s.id
    where p.layout_id = p_layout_id
      and (e.collection_id is null or e.collection_id = p_collection_id)
      and not s.locked
      and not exists (select 1 from public.collection_layout_slot_assignment a where a.slot_id = s.id)
      and not exists (select 1 from public.collection_layout_slot_image im where im.slot_id = s.id)
      and not exists (
        select 1 from public.collection_layout_region r
        where r.page_id = p.id
          and s.row_index    between r.top_row     and r.top_row     + r.height - 1
          and s.column_index between r.left_column and r.left_column + r.width  - 1)
  ),
  cands as (
    select pc.id as pid, pc.card_variant_id as var, cv.card_id as card, cv.variant_type_id as vt,
           cv.is_active as active
    from public.collection_allocation ca
    join public.physical_card pc on pc.id = ca.physical_card_id
    join public.inventory i on i.id = pc.inventory_id
    join owner_ o on o.uid = i.owner_user_id
    join public.card_variant cv on cv.id = pc.card_variant_id
    where ca.collection_id = p_collection_id
      and pc.storage_container_id = p_container_id
      and not exists (select 1 from public.collection_layout_slot_assignment a where a.physical_card_id = pc.id)
  ),
  pairs as (
    select s.sid, c.pid, c.active
    from slots s
    join cands c
      on c.card = s.e_card
     and (s.e_var is null or s.e_var = c.var)
     and (s.e_vt  is null or s.e_vt  = c.vt)
  ),
  sdeg as (select pr.sid, count(*) as n from pairs pr group by pr.sid),
  cdeg as (select pr.pid, count(*) as n from pairs pr group by pr.pid),
  ins as (
    select s.sid, c.pid, s.pg, s.rw, s.cl, c.card, c.var,
           row_number() over (order by s.pg, s.rw, s.cl, s.sid)::integer as o
    from pairs pr
    join sdeg sd on sd.sid = pr.sid and sd.n = 1
    join cdeg cd on cd.pid = pr.pid and cd.n = 1
    join slots s on s.sid = pr.sid
    join cands c on c.pid = pr.pid
    where pr.active
  ),
  slot_peer as (   -- maior grau entre os exemplares compatíveis com cada bolso
    select pr.sid, max(cd.n) as mx from pairs pr join cdeg cd on cd.pid = pr.pid group by pr.sid
  ),
  card_reason as (
    select c.pid, c.card, c.var,
           case
             when not c.active then 'INACTIVE_VARIANT'
             when cd.n is null then 'NO_COMPATIBLE_RESERVATION'
             when cd.n > 1     then 'MULTIPLE_DESTINATIONS'
             else 'COMPETING_CANDIDATES'
           end as why
    from cands c
    left join cdeg cd on cd.pid = c.pid
    where not exists (select 1 from ins x where x.pid = c.pid)
  ),
  slot_reason as (
    select s.sid, s.pg, s.rw, s.cl, s.e_card, s.e_var,
           case
             when sd.n is null then 'NO_CANDIDATE'
             when sd.n > 1     then 'COMPETING_CANDIDATES'
             when sp.mx > 1    then 'MULTIPLE_DESTINATIONS'
             else 'INACTIVE_VARIANT'
           end as why
    from slots s
    left join sdeg sd on sd.sid = s.sid
    left join slot_peer sp on sp.sid = s.sid
    where not exists (select 1 from ins x where x.sid = s.sid)
  ),
  epoch as (
    select coalesce((select max(e.id)
                     from public.binder_activity_event e
                     join owner_ o on o.uid = e.owner_user_id
                     where e.layout_key = p_layout_id
                       and e.event_type = 'CARDS_AUTO_ARRANGED'), 0)::text
           || '/'
           || coalesce((select cv.reason || '@' || (extract(epoch from cv.updated_at) * 1000000)::bigint::text
                        from public.binder_activity_coverage cv
                        join owner_ o on o.uid = cv.owner_user_id
                        where cv.layout_key = p_layout_id), '-') as v
  ),
  tok as (
    select (select count(*) from ins)::integer as n,
           'aa1:' || encode(sha256(convert_to(
             'aa1.2|' || p_collection_id::text || '|' || p_layout_id::text || '|'
             || coalesce(p_container_id::text, '-') || '|e=' || (select v from epoch)
             || '|' || (select count(*) from ins)::text
             || E'\n'
             || coalesce((select string_agg(x.sid::text || '|' || x.pid::text, E'\n' order by x.o) from ins x), ''),
             'UTF8')), 'hex') as t
  )
  select 'HEADER'::text, 0, null::uuid, null::uuid, null::integer, null::integer, null::integer,
         null::uuid, null::uuid, null::text, t.n, t.t
  from tok t
  union all
  select 'INSERT', x.o, x.sid, x.pid, x.pg, x.rw, x.cl, x.card, x.var, null, t.n, t.t
  from ins x cross join tok t
  union all
  select 'EXCLUDED_CARD', (row_number() over (order by r.why, r.pid))::integer, null, r.pid,
         null, null, null, r.card, r.var, r.why, t.n, t.t
  from card_reason r cross join tok t
  union all
  select 'UNFILLED_SLOT', (row_number() over (order by r.pg, r.rw, r.cl, r.sid))::integer, r.sid, null,
         r.pg, r.rw, r.cl, r.e_card, r.e_var, r.why, t.n, t.t
  from slot_reason r cross join tok t
$fn$;

revoke all on function public.binder_auto_arrange_plan(uuid, uuid, uuid) from public, anon, authenticated, service_role;

comment on function public.binder_auto_arrange_plan(uuid, uuid, uuid) is
  'P2 5342 (C-220..C-226): plano determinístico e somente leitura da organização automática (proprietária, bolsos reservados vazios e livres, exemplares alocados no local do fichário fora de bolsos, 1:1 estrito sem desempate, token aa1). Interna: chamada só por 5343/5344.';

commit;
