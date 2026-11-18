/* G1 (D-E1) — VERSÃO PROTEGIDA GERADA. Não editar à mão: g1/build_g1_protected.py.
   Base auditada: database/proposals/2026-11-15-v1-13-e1d-shared-reads/5388_create_get_shared_binder_activity_functions.sql
   sha256 da base: 5276f8d2d59c60c4a35e0d727dd9bda92ee4557bcc13e3d705e9b88dec631452
   Única mudança: porta 5389 consultada antes de qualquer leitura ou efeito em 2 função(ões); precheck da 5389.
   Status: PROPOSTA — NÃO EXECUTADA. Mecanismo não homologado (G1). */
/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5388 - Histórico do fichário para participantes:
              get_shared_binder_activity() e
              get_shared_binder_activity_status() (V1-13 · E1-D)
Versão......: 1.2 (2026-11-15, `D14 CONTRACT REFINEMENT AND MINIMAL CORRECTION-03`: D14 —
              eventos do titular sem coleção registrada, com itens atribuídos a X).
              1.1 (`SHARED READS PRIVACY AND CONTRACT REVIEW-02`: sinal de histórico
              parcial restrito aos tipos da lista de permissão). 1.0
Status......: PROPOSTA — NÃO EXECUTADA. Preparada em
              `V1-13 / E1-D | SECURE SHARED READS-01` (2026-11-15). Execução só
              com prova dinâmica sob protocolo controlado (C-244) e autorização
              expressa e específica.
Autor.......: Fabrício Sales / Claude
Data........: 2026-11-15
Contrato....: C-241 com D12, D13 e D14 (aprovadas em 2026-11-15), C-243, C-204,
              C-208, C-173, C-174, C-179; identidade do fichário da V1-12 (5321).
Depende de..: 5302 (nível de leitura), 5267/5341 (histórico e categoria),
              5263 (origem do L01), E1-B3 (5379: coleção por item e marca
              item_collection_recorded). Não toca a leitura do titular (5269),
              a gravação (5268/5372/5379) nem o gatilho de tipos (5381/5384).

1. get_shared_binder_activity(coleção, categorias, cursor, limite)
   Quem lê: collection_share_role (5302) ∈ {OWNER, VIEWER} — EDITOR e VIEWER
     ativos de X (o EDITOR é VIEWER para leitura, E1-A); o titular também
     recebe a MESMA visão filtrada (o histórico integral dele continua na
     5269). Não membro, convite pendente ou recusado, membro removido, PUBLIC
     e sessão anônima → zero linhas, indistinguível de "sem histórico".
   Fichário: só o fichário ATUAL de X — o que ela ancora
     (collection_layout.collection_id) ou do qual é convidada
     (collection_layout_guest). Sem fichário → zero linhas: o histórico de
     fichário desmontado, removido ou do qual X saiu fica só com o titular
     (C-208). A chave do fichário vem do servidor, nunca do cliente.
   Eventos (lista de permissão; o resto fica oculto):
     a) titular do evento = titular de X; fichário = o atual; e uma de duas
        categorias:
        A — coleção registrada do evento = X;
        B (D14) — evento SEM coleção registrada, produzido pelo titular do
            evento: ator gravado = titular gravado (valores do instante da
            gravação). O titular gravado também precisa ser o titular de X
            (condição comum a A e B): o titular de coleção é imutável (5032) e
            o fichário tem um só dono (5229/5254), então isso nunca exclui
            evento legítimo e barra linha de outro titular (C-204, C-208).
            Ator nulo ou diferente → oculto
            (autoria não comprovada). O gatilho 5384 já recusa ator ≠ titular
            sem coleção;
        evento registrado para OUTRA coleção nunca entra;
     b) atribuição confiável (D12): item_collection_recorded = true;
     c) par tipo/origem: FICHARIO com CARD_PLACED, CARD_MOVED, CARDS_SWAPPED,
        CARDS_REMOVED (E02–E05), POCKET_RESERVED, RESERVATIONS_RELEASED,
        POCKETS_LOCKED, POCKETS_UNLOCKED (E08–E10), GAP_OPENED, GAP_CLOSED,
        PAGES_ADDED, PAGE_REMOVED, PAGES_REORDERED (E11–E15) e
        CARDS_AUTO_ARRANGED (E21, D13); CATALOGO com
        CATALOG_NOVELTIES_INCORPORATED (E16);
     d) ou L01 (D12, só categoria A): LEGACY_CATALOG_INCORPORATION de origem LEGADO, sem
        ator, coleção do evento = X E linha de origem presente em
        collection_layout_catalog_incorporation (mesmo fichário, X e a mesma
        chave). Sem a linha de origem → oculto. O item do L01 é só a cópia
        do catálogo (nome, número, Set, acabamento), sem exemplar;
     e) pelo menos um item visível (abaixo). Evento sem item visível de X
        (por exemplo, organização automática que só moveu cartas de outra
        coleção) fica oculto (D13). Na categoria B o item visível é sempre de
        conteúdo (carta, reserva, bolso) de X: evento só estrutural sem
        coleção nunca aparece.
     Ocultos sempre: E01, E06a, E06b, E07, E17–E20, eventos sem coleção ou de
     outra coleção, eventos não atribuídos (anteriores à 5379 ou gravados sem
     ela) e qualquer tipo futuro não listado.
     D14 (aprovada): o titular grava SEM coleção mover/trocar, retirar,
     liberar reservas, fixar/soltar, páginas e espaços (5273, 5274, 5277,
     5278, 5280–5286); pela categoria B esses eventos aparecem ao membro de X
     quando atribuídos (5379) e com item de conteúdo de X, só com os itens de X.
     Eventos sem coleção anteriores à 5379 continuam ocultos (D12).
     Transferência de âncora (5254/5292): a chave do fichário é preservada e a
     antiga proprietária vira convidada; os eventos de X anteriores continuam
     visíveis aos membros de X e nunca aos da nova proprietária (coleção do
     evento ≠). C-208 ("transferido para fora") não se aplica: o fichário
     continua do mesmo titular.
   Itens visíveis (mesma regra no filtro de existência e na lista):
     - L01: o item CARD/INCORPORATED;
     - CARD, RESERVATION, POCKET: só com binder_activity_item.collection_id = X
       (gravada no servidor pela 5379);
     - PAGE: só nos eventos de páginas e espaços (E11–E15) da categoria A;
       na categoria B nunca (página sem coleção é estrutura compartilhada);
     - COLLECTION, BINDER e qualquer outro: nunca.
   O que sai (nada além disto):
     event_id (cursor), occurred_at, event_type, category, source, is_legacy;
     actor_role: 'OWNER' (titular), 'PARTICIPANT' (outro ator — pela gravação,
       5372/5379, só um EDITOR ativo de X na época), NULL (sem ator: L01);
     actor_display_name: user_profile.display_name do ator (C-241: nome de
       exibição público, inclusive de quem já saiu; sem perfil → NULL e a
       interface usa o papel). Nunca e-mail, nome de usuário ou id do ator;
     item_count: itens VISÍVEIS (nunca o total do evento);
     items: até 50 itens visíveis, com ordinal RENUMERADO 1..n entre os
       visíveis (sem lacunas que revelem itens ocultos) e só os campos de
       catálogo e posição: kind, effect, card_id, card_name, collector_number,
       card_set_code, variant_type_code, variant_type_name, from_* e to_*;
     items_truncated: item_count > 50.
   NÃO sai: summary (contagens do evento inteiro, chaves e dados de outras
     coleções), detail (pode ter physical_card_id, collection_id,
     storage_container_id, condition_code, planos), collection_id,
     collection_name e binder_name gravados (a identidade do fichário segue a
     5321), owner_user_id, actor_user_id, layout_key, created_xact.
   Ordem e paginação: occurred_at desc, id desc (determinística); cursor
     (occurred_at, id) como na 5269; limite 1..50; categorias da 5269/5341.

2. get_shared_binder_activity_status(coleção)
   Mesmo acesso e mesmo fichário. Uma linha (ou zero sem acesso):
     has_binder — X participa hoje de um fichário;
     history_may_be_partial — existe neste fichário evento das mesmas
       categorias da leitura (A: registrado para X; B: sem coleção e do
       titular), de um tipo da lista de permissão, que a leitura omite SÓ por
       falta de atribuição (D12: não atribuído, ou L01 sem origem comprovada).
       Na categoria B não atribuída não se sabe se havia item de X: o sinal
       acende por cautela ("pode haver"). Estrutura, acervo e eventos
       registrados para outras coleções nunca acendem o sinal. É conservador: indica que PODE haver registro anterior
       não exibido, não conta nem prova eventos ocultos e não revela tipo, data
       ou quantidade. Serve ao aviso discreto de histórico parcial (D12).

Concorrência: as duas funções são STABLE e de uma única consulta de dados após
  a autorização; dentro de uma chamada, autorização e leitura veem o mesmo
  instantâneo. Uma revogação gravada depois do início da chamada não afeta
  essa chamada e vale na próxima (mesmo modelo da V1-12). Sem prova
  concorrente (S8 concorrente, pendente).
Desempenho: índice ix_bae_owner_layout_time (titular, fichário, occurred_at
  desc, id desc) percorre os eventos do fichário em ordem; filtros de coleção,
  tipo e atribuição são da própria linha; itens pela PK (event_id, ordinal).
  Pior caso: fichário com muitas coleções e poucos eventos de X percorre mais
  eventos para encher a página. Nenhum índice novo nesta etapa; candidato
  registrado para a E1-E se a medição pedir: (owner_user_id, layout_key,
  collection_id, occurred_at desc, id desc). Não medido.
Canal.......: psql. Precheck: dependências e colunas da 5379 presentes;
              funções ausentes.
Reversão....: R5388 em ROLLBACK_E1D.sql (DROP FUNCTION; não toca o histórico).
Como validar: harness 5894, seções 4–6.
================================================================
*/

begin;
set local lock_timeout = '5s';

do $pre$
begin
  if to_regprocedure('public.v1_13_assert_capability()') is null or to_regprocedure('public.v1_13_capability_open()') is null then raise exception 'PRECHECK G1: barreira 5389 ausente'; end if;  -- G1 (D-E1)
  if to_regprocedure('public.collection_share_role(uuid)') is null
     or to_regprocedure('public.binder_activity_category(text)') is null
     or to_regclass('public.binder_activity_event') is null
     or to_regclass('public.binder_activity_item') is null
     or to_regclass('public.collection_layout_guest') is null
     or to_regclass('public.collection_layout_catalog_incorporation') is null
     or to_regclass('public.user_profile') is null then
    raise exception 'PRECHECK 5388: dependências ausentes (5302, 5267/5341, 5229, 5263, 1000)';
  end if;
  if not exists (select 1 from information_schema.columns c
                 where c.table_schema = 'public' and c.table_name = 'binder_activity_item'
                   and c.column_name = 'collection_id' and c.data_type = 'uuid')
     or not exists (select 1 from information_schema.columns c
                    where c.table_schema = 'public' and c.table_name = 'binder_activity_event'
                      and c.column_name = 'item_collection_recorded' and c.data_type = 'boolean') then
    raise exception 'PRECHECK 5388: colunas da 5379 (E1-B3) ausentes';
  end if;
  if public.binder_activity_category('CARDS_AUTO_ARRANGED') is distinct from 'CARDS' then
    raise exception 'PRECHECK 5388: categoria de CARDS_AUTO_ARRANGED (5341) ausente';
  end if;
  if exists (select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
             where n.nspname = 'public'
               and p.proname in ('get_shared_binder_activity', 'get_shared_binder_activity_status')) then
    raise exception 'PRECHECK 5388: JÁ APLICADA ou ESTADO DIVERGENTE — leitura compartilhada do histórico já existe';
  end if;
end;
$pre$;

create function public.get_shared_binder_activity(
  p_collection_id      uuid,
  p_categories         text[]      default null,
  p_before_occurred_at timestamptz default null,
  p_before_id          bigint      default null,
  p_limit              integer     default 20
)
returns table (
  event_id           bigint,
  occurred_at        timestamptz,
  event_type         text,
  category           text,
  source             text,
  is_legacy          boolean,
  actor_role         text,
  actor_display_name text,
  item_count         integer,
  items              jsonb,
  items_truncated    boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $fn$
#variable_conflict use_column
declare
  v_limit  integer := least(greatest(coalesce(p_limit, 20), 1), 50);
  v_role   text;
  v_owner  uuid;
  v_layout uuid;
begin
  if not public.v1_13_capability_open() then return; end if;  -- G1 (D-E1)
  if (p_before_occurred_at is null) <> (p_before_id is null) then
    raise exception 'cursor must have occurred_at and id together' using errcode = '22023', hint = 'BINDER_ACTIVITY_CURSOR';
  end if;
  if p_categories is not null and not (p_categories <@ array['CARDS','RESERVATIONS','LOCKS','PAGES','CATALOG','BINDER']) then
    raise exception 'unknown category' using errcode = '22023', hint = 'BINDER_ACTIVITY_CATEGORY';
  end if;
  if p_collection_id is null then
    return;
  end if;

  -- Fronteira de autorização antes de qualquer leitura do histórico (padrão 5320/5321).
  v_role := public.collection_share_role(p_collection_id);
  if v_role is null or v_role not in ('OWNER', 'VIEWER') then
    return;
  end if;

  select c.owner_user_id into v_owner from public.collection c where c.id = p_collection_id;
  -- Fichário ATUAL de X: o que ela ancora, senão o do qual é convidada (5321).
  select l.id into v_layout from public.collection_layout l where l.collection_id = p_collection_id;
  if v_layout is null then
    select g.layout_id into v_layout from public.collection_layout_guest g where g.collection_id = p_collection_id;
  end if;
  if v_owner is null or v_layout is null then
    return;
  end if;

  return query
  with page as (
    select e.id, e.occurred_at, e.event_type, e.source, e.actor_user_id, e.collection_id,
           (e.source = 'LEGADO') as legacy
    from public.binder_activity_event e
    where e.owner_user_id = v_owner
      and e.layout_key = v_layout
      -- Categoria A: evento registrado para X. Categoria B (D14): evento SEM coleção
      -- registrada, produzido pelo titular do evento (ator gravado = titular gravado).
      -- Evento registrado para outra coleção nunca entra.
      and (e.collection_id = p_collection_id
           or (e.collection_id is null and e.actor_user_id = e.owner_user_id))
      and (
        -- C-241 + D13: lista de permissão por par tipo/origem, só com atribuição confiável (D12)
        (e.item_collection_recorded
         and ((e.source = 'FICHARIO'
               and e.event_type in ('CARD_PLACED','CARD_MOVED','CARDS_SWAPPED','CARDS_REMOVED',
                                    'POCKET_RESERVED','RESERVATIONS_RELEASED','POCKETS_LOCKED','POCKETS_UNLOCKED',
                                    'GAP_OPENED','GAP_CLOSED','PAGES_ADDED','PAGE_REMOVED','PAGES_REORDERED',
                                    'CARDS_AUTO_ARRANGED'))
              or (e.source = 'CATALOGO' and e.event_type = 'CATALOG_NOVELTIES_INCORPORATED')))
        -- D12: L01 só com a origem comprovada (linha de origem desta coleção neste fichário)
        or (e.collection_id = p_collection_id
            and e.event_type = 'LEGACY_CATALOG_INCORPORATION' and e.source = 'LEGADO' and e.actor_user_id is null
            and exists (select 1 from public.collection_layout_catalog_incorporation ci
                        where ci.layout_id = e.layout_key
                          and ci.collection_id = p_collection_id
                          and ci.item_key = e.summary ->> 'item_key'))
      )
      and (p_categories is null or public.binder_activity_category(e.event_type) = any (p_categories))
      and (p_before_id is null or (e.occurred_at, e.id) < (p_before_occurred_at, p_before_id))
      and exists (
        select 1 from public.binder_activity_item i
        where i.event_id = e.id
          -- VISIBLE-ITEM-RULE (idêntica abaixo)
          and (case
                 when e.source = 'LEGADO' then i.item_kind = 'CARD' and i.effect = 'INCORPORATED'
                 when i.item_kind in ('CARD','RESERVATION','POCKET') then i.collection_id is not distinct from p_collection_id
                 when i.item_kind = 'PAGE' then e.collection_id is not distinct from p_collection_id
                                               and e.event_type in ('GAP_OPENED','GAP_CLOSED','PAGES_ADDED','PAGE_REMOVED','PAGES_REORDERED')
                 else false
               end))
    order by e.occurred_at desc, e.id desc
    limit v_limit
  ),
  vis as (
    select i.event_id, i.ordinal, i.item_kind, i.effect, i.card_id, i.card_name, i.collector_number,
           i.card_set_code, i.variant_type_code, i.variant_type_name,
           i.from_page, i.from_row, i.from_col, i.to_page, i.to_row, i.to_col,
           row_number() over (partition by i.event_id order by i.ordinal) as rn
    from page e
    join public.binder_activity_item i on i.event_id = e.id
    where
      -- VISIBLE-ITEM-RULE (idêntica acima)
      (case
         when e.source = 'LEGADO' then i.item_kind = 'CARD' and i.effect = 'INCORPORATED'
         when i.item_kind in ('CARD','RESERVATION','POCKET') then i.collection_id is not distinct from p_collection_id
         when i.item_kind = 'PAGE' then e.collection_id is not distinct from p_collection_id
                                               and e.event_type in ('GAP_OPENED','GAP_CLOSED','PAGES_ADDED','PAGE_REMOVED','PAGES_REORDERED')
         else false
       end)
  ),
  agg as (
    select v.event_id,
           count(*)::integer as n,
           jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
             'ordinal', v.rn, 'kind', v.item_kind, 'effect', v.effect,
             'card_id', v.card_id, 'card_name', v.card_name, 'collector_number', v.collector_number,
             'card_set_code', v.card_set_code, 'variant_type_code', v.variant_type_code,
             'variant_type_name', v.variant_type_name,
             'from_page', v.from_page, 'from_row', v.from_row, 'from_col', v.from_col,
             'to_page', v.to_page, 'to_row', v.to_row, 'to_col', v.to_col))
             order by v.rn) filter (where v.rn <= 50) as items
    from vis v
    group by v.event_id
  )
  select pg.id, pg.occurred_at, pg.event_type, public.binder_activity_category(pg.event_type), pg.source,
         pg.legacy,
         case when pg.actor_user_id is null then null
              when pg.actor_user_id = v_owner then 'OWNER'
              else 'PARTICIPANT' end,
         case when pg.actor_user_id is null then null
              else (select up.display_name::text from public.user_profile up where up.id = pg.actor_user_id) end,
         a.n,
         coalesce(a.items, '[]'::jsonb),
         a.n > 50
  from page pg
  join agg a on a.event_id = pg.id
  order by pg.occurred_at desc, pg.id desc;
end;
$fn$;

comment on function public.get_shared_binder_activity(uuid, text[], timestamptz, bigint, integer) is
  'V1-13 E1-D (5388): histórico do fichário atual da coleção para participantes (OWNER/VIEWER pela 5302; EDITOR lê como VIEWER). C-241 + D12 + D13 + D14: só eventos atribuídos, registrados para X ou (D14) sem coleção e do titular com item de X, na lista de permissão (E02–E05, E08–E16, E21; L01 só com origem comprovada), só itens de X, contagem recalculada, ordinal renumerado, sem summary/detail/ids/nomes gravados. Ator: papel e nome de exibição público. Histórico integral do titular segue na 5269.';

revoke all on function public.get_shared_binder_activity(uuid, text[], timestamptz, bigint, integer) from public, anon;
grant execute on function public.get_shared_binder_activity(uuid, text[], timestamptz, bigint, integer) to authenticated;

create function public.get_shared_binder_activity_status(p_collection_id uuid)
returns table (
  has_binder             boolean,
  history_may_be_partial boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $fn$
#variable_conflict use_column
declare
  v_role   text;
  v_owner  uuid;
  v_layout uuid;
begin
  if not public.v1_13_capability_open() then return; end if;  -- G1 (D-E1)
  if p_collection_id is null then
    return;
  end if;
  v_role := public.collection_share_role(p_collection_id);
  if v_role is null or v_role not in ('OWNER', 'VIEWER') then
    return;
  end if;

  select c.owner_user_id into v_owner from public.collection c where c.id = p_collection_id;
  select l.id into v_layout from public.collection_layout l where l.collection_id = p_collection_id;
  if v_layout is null then
    select g.layout_id into v_layout from public.collection_layout_guest g where g.collection_id = p_collection_id;
  end if;
  if v_owner is null or v_layout is null then
    return query select false, false;
    return;
  end if;

  return query
  select true,
         exists (
           select 1 from public.binder_activity_event e
           where e.owner_user_id = v_owner
             and e.layout_key = v_layout
             -- mesmas categorias da leitura: registrado para X, ou sem coleção e do
             -- titular (D14). Evento de outra coleção nunca acende o sinal.
             and (e.collection_id = p_collection_id
                  or (e.collection_id is null and e.actor_user_id = e.owner_user_id))
             -- só eventos que a leitura MOSTRARIA se estivessem atribuídos (mesma lista de
             -- permissão): estrutura, acervo e tipos ocultos nunca acendem o aviso
             and ((not e.item_collection_recorded
                   and ((e.source = 'FICHARIO'
                         and e.event_type in ('CARD_PLACED','CARD_MOVED','CARDS_SWAPPED','CARDS_REMOVED',
                                              'POCKET_RESERVED','RESERVATIONS_RELEASED','POCKETS_LOCKED','POCKETS_UNLOCKED',
                                              'GAP_OPENED','GAP_CLOSED','PAGES_ADDED','PAGE_REMOVED','PAGES_REORDERED',
                                              'CARDS_AUTO_ARRANGED'))
                        or (e.source = 'CATALOGO' and e.event_type = 'CATALOG_NOVELTIES_INCORPORATED')))
                  or (e.collection_id = p_collection_id
                      and e.event_type = 'LEGACY_CATALOG_INCORPORATION' and e.source = 'LEGADO'
                      and not exists (select 1 from public.collection_layout_catalog_incorporation ci
                                      where ci.layout_id = e.layout_key
                                        and ci.collection_id = p_collection_id
                                        and ci.item_key = e.summary ->> 'item_key'))));
end;
$fn$;

comment on function public.get_shared_binder_activity_status(uuid) is
  'V1-13 E1-D (5388): estado do histórico compartilhado da coleção (mesmo acesso da get_shared_binder_activity). has_binder; history_may_be_partial = há evento de X, de tipo da lista de permissão, omitido só por falta de atribuição ou de origem (D12) — sinal conservador, não contagem. Só booleanos; nada de outras coleções.';

revoke all on function public.get_shared_binder_activity_status(uuid) from public, anon;
grant execute on function public.get_shared_binder_activity_status(uuid) to authenticated;

do $post$
declare
  f oid;
begin
  foreach f in array array[
    to_regprocedure('public.get_shared_binder_activity(uuid, text[], timestamptz, bigint, integer)'),
    to_regprocedure('public.get_shared_binder_activity_status(uuid)')]
  loop
    if f is null
       or (select p.prosecdef from pg_catalog.pg_proc p where p.oid = f) is not true
       or (select p.proconfig from pg_catalog.pg_proc p where p.oid = f) is distinct from array['search_path=""']
       or (select p.provolatile from pg_catalog.pg_proc p where p.oid = f) is distinct from 's'
       or pg_catalog.has_function_privilege('authenticated', f, 'EXECUTE') is not true
       or pg_catalog.has_function_privilege('anon', f, 'EXECUTE') is not false
       or exists (select 1 from pg_catalog.pg_proc p cross join lateral pg_catalog.aclexplode(p.proacl) a
                  where p.oid = f and a.grantee = 0 and a.privilege_type = 'EXECUTE') then
      raise exception 'POSTCHECK 5388: leitura compartilhada do histórico fora do estado esperado (%)', f;
    end if;
  end loop;
end;
$post$;

commit;
