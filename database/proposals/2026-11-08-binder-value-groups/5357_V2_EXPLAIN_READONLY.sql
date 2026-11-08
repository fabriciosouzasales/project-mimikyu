/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5357-V2 - PLANO SEM ANALYZE (fase B) da consulta interna da 5357
Versão......: 0.2 (B2 — LIVE READONLY PROTOCOL AUDIT-01: consulta interna
              COMPLETA, igual à da 5357; ids mascarados; resultado como linha;
              lock_timeout)
              0.3 (B2 — V1 CLOSEOUT & V2 READINESS-01): V2.1 inalterado no SQL,
              com critérios objetivos ancorados no V1.8; V2.2 reescrito — o
              plano customizado é analisado DENTRO do bloco (EXPLAIN FORMAT
              JSON) e só saem booleanos, tipos de nó, tabelas, índices e uma
              FAIXA de tamanho do fichário; nenhum id, nenhuma contagem exata,
              nenhum texto de plano com estimativas do fichário; erro devolve só
              SQLSTATE.
              0.4 (B2 — V2.1 G3 CORRECTION & INDEX DIAGNOSIS-01): G3 dividido
              em G3-A (seletividade do percurso, medida nas junções depois da
              âncora) e G3-B (varreduras globais permitidas em tabela pequena,
              com 128 páginas como gatilho de reavaliação). O SQL do V2.1 não
              mudou; no V2.2 só a verificação de linhas mudou
              (linhas_percurso_ok → g3a_juncoes_proporcionais +
              g3b_varreduras_globais).
Status......: V2.1 EXECUTADO no LIVE em 2026-11-08 (v0.3, plano genérico; G3
              original STOP, reavaliado PASS pelos critérios da v0.4 — ver
              VALIDATION-STRATEGY-01.md §12 e EVIDENCE-V2.1-2026-11-08.txt).
              V2.2 e V2.3: PROPOSTOS — NÃO EXECUTADOS; cada um exige
              autorização própria.
Data........: 2026-11-08

Forma de execução: blocos autocontidos (transação READ ONLY própria, um
resultado por bloco, ROLLBACK). Nenhum bloco usa ANALYZE: a consulta explicada
NÃO é executada. A 5357 não existe e não é chamada.

Equivalência com a 5357 (conferida por comparação de tokens na B2 V1 CLOSEOUT):
o texto do V2.1 é o "return query" da função com v_layout → $1::uuid,
v_uid → $2::uuid, p_offset → $3::integer, p_limit → $4::integer. Fica de fora
só o prólogo da função (autorização e resolução do fichário: buscas por
PK/UNIQUE de uma linha).

Leitura efetiva de dados: EXPLAIN sem ANALYZE não lê linhas das tabelas; o
planejador usa estatísticas do catálogo (e, em desigualdades sobre colunas
indexadas, pode consultar extremos de índice — não há esse caso no V2.1).
O V2.2 EXECUTA uma consulta auxiliar (escolha do fichário mais cheio, percorre
páginas/bolsos/ocupações — mesmo custo do V1.6, comprovado viável no V1.8).

Base de cardinalidade (V1.8, estimativas): bolsos ≈ 3,2 mil; páginas ≈ 300;
ocupações ≈ 1,15 mil; exemplares ≈ 3,6 mil; inventários ≈ 3; card_variant ≈
37,9 mil (1.027 páginas); card_asset ≈ 28,8 mil (982); card ≈ 20,2 mil (462);
language e collection_layout_guest sem estatística (−1).

Critérios do V2.1 (plano GENÉRICO, texto; custo é informativo, não gate)
  PASS (todos):
  G1 o nó de collection_layout_page tem a condição layout_id = $1 (Index Cond,
     Recheck Cond ou Filter);
  G2 card_variant, card e card_asset (> 128 páginas) não aparecem em Seq Scan;
     são acessados por índice (PK ou ix_card_asset_card_id);
  G3 (v0.3, SUBSTITUÍDO — mantido como histórico) "nenhum nó sobre as tabelas
     do percurso estima mais de 1.000 linhas": conflitava com a aceitação de
     Seq Scan em tabela pequena (a estimativa de um Seq Scan é a tabela
     inteira). Resultado no V2.1 executado: STOP pelo texto literal.
  G3-A seletividade do percurso: as junções que ficam entre a âncora
     (collection_layout_page por layout_id) e a agregação por variante/idioma
     estimam no máximo max(4 × bolsos do fichário, 1.000) linhas e não crescem
     ao longo do percurso (página → bolso → ocupação → exemplar → grupo). No
     plano genérico, "bolsos do fichário" não é conhecido: vale 1.000.
  G3-B varreduras globais: Seq Scan em tabela do percurso é aceito quando a
     tabela tem até 128 páginas (V1.8). Seq Scan NÃO é falha automática; 128
     páginas é GATILHO DE REAVALIAÇÃO (repetir o V2), não garantia de
     desempenho. Varredura global cresce com a base inteira, não com o
     fichário: é risco residual registrado, e a decisão sobre escala futura
     exige nova evidência. Tabela acima de 128 páginas em Seq Scan → STOP para
     reavaliação (não para criar índice).
  G4 a busca de imagem (card_asset) fica acima do filtro de página
     (o nó com Filter sobre ord está ABAIXO do Nested Loop do lateral).
  STOP: G1, G2, G3-A, G3-B ou G4 falso; Seq Scan em card_variant/card/card_asset;
  ausência da âncora layout_id. Em STOP: nenhum índice novo; nenhuma mudança na
  SQL da 5357 para forçar índice; plano volta para auditoria.

Critérios do V2.2 (plano CUSTOMIZADO do fichário mais cheio, analisado no bloco)
  PASS: status OK; ancora_layout, catalogo_grande_por_indice,
  agregacao_encontrada, g3a_juncoes_proporcionais e g3b_varreduras_globais
  TRUE. STOP: qualquer FALSE, status ERRO (SQLSTATE) ou
  timeout. A lista "nos" é informativa.
================================================================
*/

-- V2.1 [GATE] plano GENÉRICO da consulta interna completa (sem valores, sem ids)
begin transaction read only;
set local statement_timeout = '10s'; set local lock_timeout = '2s'; set local idle_in_transaction_session_timeout = '30s';
explain (generic_plan, costs, format text)
with pocketed as (
  select pc.card_variant_id, pc.language_id
  from public.collection_layout_page p
  join public.collection_layout_slot s            on s.page_id = p.id
  join public.collection_layout_slot_assignment a on a.slot_id = s.id
  join public.physical_card pc                    on pc.id = a.physical_card_id
  join public.inventory i                         on i.id = pc.inventory_id
                                                 and i.owner_user_id = $2::uuid
  where p.layout_id = $1::uuid
),
grouped as (
  select pk.card_variant_id, pk.language_id, count(*)::integer as n
  from pocketed pk
  group by pk.card_variant_id, pk.language_id
),
ordered as (
  select gr.card_variant_id, gr.language_id, gr.n,
         count(*) over ()  as total,
         sum(gr.n) over () as copies_sum,
         row_number() over (order by
           cs.release_date  desc nulls last,
           cs.release_order desc nulls last,
           cs.code          asc,
           c.collector_order asc,
           cv.variant_order asc,
           l.language_order asc,
           gr.card_variant_id asc,
           gr.language_id     asc) as ord
  from grouped gr
  join public.card_variant cv on cv.id = gr.card_variant_id
  join public.card c          on c.id = cv.card_id
  join public.card_set cs     on cs.id = c.card_set_id
  join public.language l      on l.id = gr.language_id
)
select
  o.card_variant_id, l.code::text, l.name::text, c.name::text, c.collector_number::text, c.collector_total,
  cs.code::text, cs.name::text, cv.is_default, nullif(concat_ws(' · ', vt.name, pp.name, ec.name), '')::text,
  img.storage_path::text, o.n, o.total, o.copies_sum
from ordered o
join public.card_variant cv on cv.id = o.card_variant_id
join public.card c          on c.id = cv.card_id
join public.card_set cs     on cs.id = c.card_set_id
join public.language l      on l.id = o.language_id
left join public.card_variant_type vt            on vt.id = cv.variant_type_id
left join public.card_printing_profile pp        on pp.id = cv.printing_profile_id
left join public.card_edition_context_profile ec on ec.id = cv.edition_context_profile_id
left join lateral (
  select ca.storage_path
  from public.card_asset ca
  join public.card_asset_type cat on cat.id = ca.asset_type_id and cat.code = 'CARD_FRONT'
  join public.language al         on al.id = ca.language_id
  where ca.card_id = c.id and ca.is_primary and ca.is_active and ca.storage_path is not null
  order by (ca.language_id = o.language_id) desc, (al.code = 'pt-BR') desc, (al.code = 'en') desc, al.language_order asc
  limit 1
) img on true
where o.ord > $3::integer and o.ord <= $3::integer + $4::integer
order by o.ord;
rollback;

-- V2.2 [GATE] plano CUSTOMIZADO da MESMA consulta do V2.1, no fichário mais
-- cheio (offset 0, limite 200), analisado DENTRO do bloco.
-- Executa de fato só a escolha do fichário (consulta auxiliar, sem saída).
-- Sai uma única linha jsonb com: status, faixa de bolsos (≤100 / 101–500 /
-- 501–1000 / >1000), tipos de nó + tabela + índice distintos, e três
-- booleanos. Não saem ids, contagens exatas, estimativas de linhas nem texto
-- de condições do plano. Em erro, só o SQLSTATE (SQLERRM não é exposto).
begin transaction read only;
set local statement_timeout = '10s'; set local lock_timeout = '2s'; set local idle_in_transaction_session_timeout = '30s';
do $v22$
declare v_layout uuid; v_uid uuid; v_slots bigint; v_plan jsonb; v_res jsonb;
begin
  begin
    select p.layout_id, oc.owner_user_id, count(s.id)
      into v_layout, v_uid, v_slots
    from public.collection_layout_page p
    join public.collection_layout l            on l.id = p.layout_id
    join public.collection oc                  on oc.id = l.collection_id
    join public.collection_layout_slot s       on s.page_id = p.id
    left join public.collection_layout_slot_assignment a on a.slot_id = s.id
    group by p.layout_id, oc.owner_user_id
    order by count(a.id) desc, count(s.id) desc
    limit 1;

    if v_layout is null then
      v_res := jsonb_build_object('status', 'SEM_FICHARIOS');
    else
      execute
        'explain (costs, format json)
         with pocketed as (
           select pc.card_variant_id, pc.language_id
           from public.collection_layout_page p
           join public.collection_layout_slot s            on s.page_id = p.id
           join public.collection_layout_slot_assignment a on a.slot_id = s.id
           join public.physical_card pc                    on pc.id = a.physical_card_id
           join public.inventory i                         on i.id = pc.inventory_id
                                                          and i.owner_user_id = $2::uuid
           where p.layout_id = $1::uuid
         ),
         grouped as (
           select pk.card_variant_id, pk.language_id, count(*)::integer as n
           from pocketed pk
           group by pk.card_variant_id, pk.language_id
         ),
         ordered as (
           select gr.card_variant_id, gr.language_id, gr.n,
                  count(*) over ()  as total,
                  sum(gr.n) over () as copies_sum,
                  row_number() over (order by
                    cs.release_date  desc nulls last,
                    cs.release_order desc nulls last,
                    cs.code          asc,
                    c.collector_order asc,
                    cv.variant_order asc,
                    l.language_order asc,
                    gr.card_variant_id asc,
                    gr.language_id     asc) as ord
           from grouped gr
           join public.card_variant cv on cv.id = gr.card_variant_id
           join public.card c          on c.id = cv.card_id
           join public.card_set cs     on cs.id = c.card_set_id
           join public.language l      on l.id = gr.language_id
         )
         select
           o.card_variant_id, l.code::text, l.name::text, c.name::text, c.collector_number::text, c.collector_total,
           cs.code::text, cs.name::text, cv.is_default, nullif(concat_ws('' · '', vt.name, pp.name, ec.name), '''')::text,
           img.storage_path::text, o.n, o.total, o.copies_sum
         from ordered o
         join public.card_variant cv on cv.id = o.card_variant_id
         join public.card c          on c.id = cv.card_id
         join public.card_set cs     on cs.id = c.card_set_id
         join public.language l      on l.id = o.language_id
         left join public.card_variant_type vt            on vt.id = cv.variant_type_id
         left join public.card_printing_profile pp        on pp.id = cv.printing_profile_id
         left join public.card_edition_context_profile ec on ec.id = cv.edition_context_profile_id
         left join lateral (
           select ca.storage_path
           from public.card_asset ca
           join public.card_asset_type cat on cat.id = ca.asset_type_id and cat.code = ''CARD_FRONT''
           join public.language al         on al.id = ca.language_id
           where ca.card_id = c.id and ca.is_primary and ca.is_active and ca.storage_path is not null
           order by (ca.language_id = o.language_id) desc, (al.code = ''pt-BR'') desc, (al.code = ''en'') desc, al.language_order asc
           limit 1
         ) img on true
         where o.ord > $3::integer and o.ord <= $3::integer + $4::integer
         order by o.ord' into v_plan using v_layout, v_uid, 0, 200;
      v_layout := null; v_uid := null;  -- ids descartados antes de montar a saída

      with recursive n(node) as (
        select v_plan -> 0 -> 'Plan'
        union all
        select c from n cross join lateral jsonb_array_elements(coalesce(n.node -> 'Plans', '[]'::jsonb)) c
      ),
      agg(node) as (
        -- agregação por variante/idioma (fim do percurso G3-A)
        select node from n
        where node ->> 'Node Type' = 'Aggregate' and (node -> 'Group Key')::text like '%card_variant_id%'
        limit 1
      ),
      sub(node) as (
        -- tudo o que fica abaixo da agregação: o percurso a partir da âncora
        select node from agg
        union all
        select c from sub cross join lateral jsonb_array_elements(coalesce(sub.node -> 'Plans', '[]'::jsonb)) c
      )
      select jsonb_build_object(
        'status', 'OK',
        'faixa_bolsos', case when v_slots <= 100 then '<=100' when v_slots <= 500 then '101-500'
                             when v_slots <= 1000 then '501-1000' else '>1000' end,
        'nos', (select jsonb_agg(distinct jsonb_build_object('tipo', node ->> 'Node Type',
                                                            'tabela', node ->> 'Relation Name',
                                                            'indice', node ->> 'Index Name')) from n),
        'ancora_layout', exists (
          select 1 from n
          where (node ->> 'Relation Name' = 'collection_layout_page' or node ->> 'Index Name' = 'uq_collection_layout_page_number')
            and concat_ws(' ', node ->> 'Index Cond', node ->> 'Recheck Cond', node ->> 'Filter') like '%layout_id%'),
        'catalogo_grande_por_indice', not exists (
          select 1 from n
          where node ->> 'Node Type' = 'Seq Scan' and node ->> 'Relation Name' in ('card_variant', 'card', 'card_asset')),
        'agregacao_encontrada', exists (select 1 from agg),
        'g3a_juncoes_proporcionais', exists (select 1 from agg) and not exists (
          select 1 from sub
          where node ->> 'Node Type' in ('Hash Join', 'Nested Loop', 'Merge Join')
            and (node ->> 'Plan Rows')::numeric > greatest(4 * v_slots, 1000)),
        'g3b_varreduras_globais', not exists (
          select 1 from n
          where node ->> 'Node Type' = 'Seq Scan'
            and node ->> 'Relation Name' in ('collection_layout_page', 'collection_layout_slot',
                                             'collection_layout_slot_assignment', 'physical_card', 'inventory')
            and coalesce((select c.relpages from pg_class c
                            join pg_namespace ns on ns.oid = c.relnamespace and ns.nspname = 'public'
                           where c.relname = node ->> 'Relation Name'), 0) > 128))
        into v_res
      from (select 1) x;
    end if;
  exception when others then
    v_res := jsonb_build_object('status', 'ERRO', 'sqlstate', sqlstate);
  end;
  perform set_config('v2.res', v_res::text, true);
end;
$v22$;
select current_setting('v2.res')::jsonb as resultado_v22;
rollback;

-- V2.3 [INFO] referência: percurso do filled_count (5252), plano genérico
begin transaction read only;
set local statement_timeout = '10s'; set local lock_timeout = '2s'; set local idle_in_transaction_session_timeout = '30s';
explain (generic_plan, costs, format text)
select count(a.id)
from public.collection_layout_page p
join public.collection_layout_slot s on s.page_id = p.id
left join public.collection_layout_slot_assignment a on a.slot_id = s.id
where p.layout_id = $1::uuid;
rollback;
