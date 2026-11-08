/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5357-P1 - PROTOCOLO DE DESEMPENHO da 5357 (EXPLAIN SEM ANALYZE)
Versão......: 0.2 (B2 STATIC AUDIT CORRECTION-01: critérios refeitos por
              cardinalidade e seletividade; custo deixa de ser gate; plano
              genérico incluído)
Status......: PROPOSTO — NÃO EXECUTADO. Execução (local ou LIVE) exige
              autorização própria; no LIVE, somente leitura.
Data........: 2026-11-08

Por que não "EXPLAIN select * from get_my_binder_value_groups(...)":
  o plano de uma função PL/pgSQL aparece só como "Function Scan". O protocolo
  explica a CONSULTA INTERNA com os dois parâmetros resolvidos pela função (o
  fichário e o titular). Como a função usa variáveis (v_layout, v_uid), o
  PL/pgSQL pode passar a usar um PLANO GENÉRICO depois de algumas execuções;
  por isso o P1.2 explica também o plano genérico (PREPARE + force_generic_plan).

Princípio
  Custo estimado NÃO é latência e não é gate: é registrado para comparação. O
  que se avalia é se o trabalho é proporcional ao fichário pedido (seletividade)
  e não ao tamanho global das tabelas. Seq Scan não reprova por si só: em tabela
  pequena é a escolha correta do planejador.

----------------------------------------------------------------
NÍVEL 1 — critérios estáticos (verificáveis sem banco; já conferidos na B2)
  ST1 Âncora única: o percurso começa em collection_layout_page.layout_id =
      fichário resolvido pela coleção autorizada; não há predicado que leia
      outro fichário (sem OR, sem LIKE, sem função sobre a coluna da âncora).
  ST2 Cada junção do percurso tem índice cuja coluna líder é a de junção:
      página uq_collection_layout_page_number (layout_id, page_number);
      bolso uq_collection_layout_slot_position (page_id, row_index, column_index);
      ocupação uq_collection_layout_slot_assignment_slot (slot_id);
      exemplar e inventário pela PK. (Os UNIQUE de página e ocupação são
      DEFERRABLE: o índice serve para varredura; só não serve para o planejador
      provar unicidade — irrelevante aqui.)
  ST3 Agregação sobre ≤ filled_count linhas; catálogo (variante, carta, Set,
      idioma) por PK só dos grupos; imagem (ix_card_asset_card_id) e etiqueta
      só das ≤ 200 linhas da página.
  ST4 Nada de SQL dinâmico; um statement de leitura; sem escrita.

----------------------------------------------------------------
NÍVEL 2 — critérios do EXPLAIN (sem ANALYZE)
  Entradas registradas no P1.0: ocupados (F) e bolsos (S) do fichário mais
  denso, e reltuples/relpages de collection_layout_page, collection_layout_slot,
  collection_layout_slot_assignment, physical_card e inventory. Uma tabela é
  "pequena" quando relpages ≤ 128 (≤ 1 MB) — varrê-la inteira custa menos que
  o percurso indexado típico.

  PASS (todos):
  E1 Seletividade: o nó de collection_layout_page tem a condição layout_id
     (Index Cond, ou Filter se a tabela for pequena) e estimativa ≤ páginas do
     fichário × 2.
  E2 Proporcionalidade: nenhum nó do percurso (página → bolso → ocupação →
     exemplar → inventário) estima mais linhas do que max(4 × S, 1.000).
  E3 Varredura completa só em tabela pequena; em tabela grande, o acesso é por
     índice (Index/Index Only/Bitmap) ou é o lado de BUILD de um Hash Join cujo
     lado de PROBE já está restrito ao fichário — e, nesse caso, a tabela
     varrida é registrada com reltuples para reavaliação no NÍVEL 3.
  E4 Agregação (HashAggregate/GroupAggregate) e Sort/WindowAgg sobre ≤ F
     linhas estimadas.
  E5 Plano genérico (P1.2) atende E1–E4 com a mesma âncora; se diferir do
     plano com literais, ambos são registrados.

  STOP (qualquer um; registrar o plano e voltar para auditoria, sem índice novo):
  X1 Seq Scan sem condição de layout em tabela grande (relpages > 128) cujo
     resultado alimenta o percurso por Nested Loop (trabalho global repetido).
  X2 Estimativa de algum nó do percurso > 10 × max(S, 1.000) — sinal de leitura
     fora do fichário pedido.
  X3 Plano genérico sem a âncora layout_id (E5 falhou).
  Informativo (não é gate): custo total, comparado com o do percurso do
  filled_count da 5252 (P1.3) — mesmo caminho, devem ficar na mesma ordem de
  grandeza; Sort acima de work_mem só é observável com ANALYZE (NÍVEL 3).

----------------------------------------------------------------
NÍVEL 3 — medições reais futuras (cada uma com autorização própria)
  M1 Local isolado: EXPLAIN (ANALYZE, BUFFERS) em fichários SINTÉTICOS de
     1.000 e 5.000 bolsos ocupados, no fixture do 5885 ampliado. Referência:
     ≤ 50 ms (1.000) e crescimento ~linear até 5.000; Sort em memória; sem
     leitura de disco relevante após aquecimento.
  M2 Pós-aplicação no LIVE: tempo de servidor da chamada no log da aplicação
     (mesmo padrão do acervo.render) e, se disponível, pg_stat_statements
     (mean/max) nas primeiras semanas. Referência: p95 de servidor ≤ 150 ms com
     o volume real; nenhum 57014.
  M3 Concorrência com a tela do fichário (5252 + páginas): a leitura é chamada
     uma vez por abertura do relatório, não por página do fichário.
================================================================
*/

begin transaction read only;
set local statement_timeout = '10s';

-- P1.0 — fichário mais denso e o titular (só contagens; não registrar ids no relatório)
select p.layout_id, oc.owner_user_id as uid,
       count(distinct p.id) as paginas, count(s.id) as bolsos, count(a.id) as ocupados
from public.collection_layout_page p
join public.collection_layout l                  on l.id = p.layout_id
join public.collection oc                        on oc.id = l.collection_id
join public.collection_layout_slot s             on s.page_id = p.id
left join public.collection_layout_slot_assignment a on a.slot_id = s.id
group by p.layout_id, oc.owner_user_id
order by ocupados desc
limit 1;

select c.relname, c.reltuples::bigint, c.relpages
from pg_class c
join pg_namespace n on n.oid = c.relnamespace and n.nspname = 'public'
where c.relname in ('collection_layout_page', 'collection_layout_slot', 'collection_layout_slot_assignment',
                    'physical_card', 'inventory')
order by c.relname;

-- P1.1 — plano com literais (psql: \set layout_id '...' e \set uid '...')
explain (costs, verbose off, format text)
with pocketed as (
  select pc.card_variant_id, pc.language_id
  from public.collection_layout_page p
  join public.collection_layout_slot s            on s.page_id = p.id
  join public.collection_layout_slot_assignment a on a.slot_id = s.id
  join public.physical_card pc                    on pc.id = a.physical_card_id
  join public.inventory i                         on i.id = pc.inventory_id
                                                 and i.owner_user_id = :'uid'::uuid
  where p.layout_id = :'layout_id'::uuid
),
grouped as (
  select pk.card_variant_id, pk.language_id, count(*)::integer as n
  from pocketed pk
  group by pk.card_variant_id, pk.language_id
)
select gr.card_variant_id, gr.language_id, gr.n,
       count(*) over () as total, sum(gr.n) over () as copies_sum,
       row_number() over (order by cs.release_date desc nulls last, cs.release_order desc nulls last, cs.code,
                                   c.collector_order, cv.variant_order, l.language_order,
                                   gr.card_variant_id, gr.language_id) as ord
from grouped gr
join public.card_variant cv on cv.id = gr.card_variant_id
join public.card c          on c.id = cv.card_id
join public.card_set cs     on cs.id = c.card_set_id
join public.language l      on l.id = gr.language_id;

-- P1.2 — plano GENÉRICO (o que o PL/pgSQL pode usar após algumas execuções)
prepare q5357_generic(uuid, uuid) as
with pocketed as (
  select pc.card_variant_id, pc.language_id
  from public.collection_layout_page p
  join public.collection_layout_slot s            on s.page_id = p.id
  join public.collection_layout_slot_assignment a on a.slot_id = s.id
  join public.physical_card pc                    on pc.id = a.physical_card_id
  join public.inventory i                         on i.id = pc.inventory_id
                                                 and i.owner_user_id = $2
  where p.layout_id = $1
)
select pk.card_variant_id, pk.language_id, count(*)::integer as n
from pocketed pk
group by pk.card_variant_id, pk.language_id;
set local plan_cache_mode = force_generic_plan;
explain (costs, verbose off, format text) execute q5357_generic(:'layout_id'::uuid, :'uid'::uuid);
deallocate q5357_generic;

-- P1.3 — referência: percurso do filled_count da 5252 no mesmo fichário (informativo)
explain (costs, verbose off, format text)
select count(a.id)
from public.collection_layout_page p
join public.collection_layout_slot s on s.page_id = p.id
left join public.collection_layout_slot_assignment a on a.slot_id = s.id
where p.layout_id = :'layout_id'::uuid;

rollback;
