/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5224 - Fichário Digital (P2-A1): plano determinístico, prévia
              e montagem automática transacional
              collection_binder_plan(uuid, int, int, text)     — helper INTERNO
              preview_my_collection_binder(uuid, int, int, text)
              create_my_collection_binder(uuid, int, int, text, text)
Versão......: 1.1 (2026-10-23, P2-A1-PROPOSAL-AUDIT-CORRECTION-01: concorrência
              reescrita em A/B/C com referência aos contratos; 5218 corrigida
              — recusa, não atualiza; aliases explícitos no generate_series;
              erros completados)
Status......: EXECUTADA / CANÔNICA. Aplicada no LIVE em 2026-10-23 UTC
              (P2-A1-LIVE-APPLY-01, autorização expressa de Fabrício; ledger
              20261023120222 `5224_create_collection_binder_plan_preview_create`). Do `begin;` ao `commit;`
              byte a byte idêntica ao texto aplicado e ao arquivo da pasta
              database/proposals/2026-10-22-p2-a1-digital-binder/ (só este
              bloco Status difere). Pós-checagens estruturais 10/10 PASS;
              comportamento SEM prova comportamental; tetos provisórios.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-22 (P2-A1-PROPOSAL-01)

Dependências: 5225 (expected_variant_type_id), 5105–5137 (Layout), 5187
(master_set_positions), 5184 (collection_master_set_finish), 6040/6117/
6120/5091 (Pokédex), 5212/5213 (storage_container.kind_code).
Ordem do pacote: 5225 → 5223 → 5224 → 5226 → 5227 → 5228.

──────────────────────────────────────────────────────────────────────
DECISÕES APLICADAS (P2-A1 REFINEMENT-01/02, D1–D9, R1–R5)
  D1  Criar só com local padrão do tipo BINDER, validado NO SERVIDOR sob a
      trava da coleção. Depois de criado, o fichário independe do local.
  D2  Sete modelos Normal, convenção colunas × linhas:
      2×2 3×3 3×4 4×3 4×4 4×5 5×4 → grid_columns = 1º número,
      grid_rows = 2º número. Qualquer outro par → INVALID_GRID.
  D3  Montagem automática, uma única vez (ALREADY_EXISTS depois).
  R1  Cópia idêntica = mesma card_variant_id E mesmo language_id.
  R2  Exemplares adicionais: PRINCIPAL_ONLY (sem bolso) ou APPEND_PAGES
      (páginas próprias depois do checklist). Nenhum exemplar é
      desalocado, excluído ou alterado em nenhuma das duas.
  R5  A opção NÃO é persistida; integra a prévia, o plano e o token.

──────────────────────────────────────────────────────────────────────
TIPO DA COLEÇÃO (collection.mode / completion_policy — CHECK 5086)
  FREE        OPEN_CURATION / NONE
  SET         REFERENCE_BASED / STANDARD_SET        (reference CARD_SET)
  MASTER_SET  REFERENCE_BASED / MASTER_SET          (reference CARD_SET)
  POKEDEX     REFERENCE_BASED / REFERENCE_POSITION  (reference POKEDEX)

UNIVERSO DE POSIÇÕES — mesmas fontes do progresso (nenhuma regra paralela)
  SET         1 posição por carta do Card Set referenciado — mesma
              consulta da 5169/5071 (card.card_set_id = set; secretas
              incluídas; SEM filtro de is_active, como a 5169).
              Reserva = (carta, sem variante, sem acabamento).
  MASTER_SET  public.master_set_positions(set, acabamentos escolhidos)
              (5187 — a MESMA função usada pelo progresso 5198): carta
              ativa × acabamento escolhido com variante ativa; secreta sem
              acabamento escolhido → 1 posição só da carta (C-189).
              Reserva = (carta, acabamento) ou (carta) na secreta.
  POKEDEX     posições do Pokédex referenciado DENTRO do escopo da coleção
              (FULL_REFERENCE ou gerações em collection_pokedex_scope_
              generation — mesma regra da 5204) que têm exemplar vinculado
              (collection_pokedex_position_assignment). SEM reservas (não
              se inventam reservas de Set para a Pokédex).
  FREE        cada exemplar alocado é uma posição; sem reservas.

ORDEM DA SEQUÊNCIA PRINCIPAL
  SET         card.collector_order, collector_number, card.id (= 5169).
  MASTER_SET  card.collector_order, collector_number, card.id,
              card_variant_type.display_order (catálogo canônico 850:
              STANDARD 1, HOLO 2, COSMOS_HOLO 3, REVERSE_HOLO 4, reverses
              de bola 5–12, PROMO_STAMPED 13), variant_type_id; posição só
              da carta (secreta) por último dentro da carta.
              Normal → Holo → Reverse Holo resulta do display_order; nenhuma
              lista fixa de acabamentos é usada.
  POKEDEX     pokedex_position.position_number, position id (= 5204).
  FREE        collection_allocation.created_at (ordem de entrada na
              coleção). DESEMPATE DOCUMENTADO para exemplares que entraram
              no MESMO lote (created_at = horário da transação):
              card_set.code, card.collector_order, display_order do
              acabamento, card_variant.variant_order, language_order,
              physical_card.created_at, physical_card.id.

EXEMPLAR PRINCIPAL (um por posição; nenhuma alocação em duas posições)
  Candidatos do grupo da posição:
    SET        exemplares da mesma carta;
    MASTER_SET exemplares da mesma carta E do mesmo acabamento (posição só
               da carta: qualquer acabamento) — um acabamento NUNCA ocupa a
               reserva de outro, porque o filtro vem antes do desempate;
    POKEDEX    exemplares vinculados àquela posição;
    FREE       o próprio exemplar.
  Desempate (o primeiro vence):
    SET/MASTER display_order do acabamento, variant_order,
               language_order, physical_card.created_at, physical_card.id;
    POKEDEX    representante primário primeiro, assigned_at,
               collection_allocation.id (= 5204).
  A regra vale só para a montagem inicial.

EXEMPLARES ADICIONAIS (todo alocado que não é principal) — categoria única:
  OUT_OF_OBJECTIVE  sem posição no objetivo (Master Set: acabamento não
                    escolhido; Pokédex: sem vínculo ou vínculo fora do
                    escopo de gerações).
  IDENTICAL_COPY    repete card_variant_id + language_id de um exemplar
                    ANTERIOR (na ordem de desempate) do mesmo grupo (R1).
  OTHER_LANGUAGE    mesma variante de um anterior do grupo, outro idioma.
  OTHER_VARIANT     variante diferente de todos os anteriores do grupo
                    (no Pokédex: outra carta/variante da mesma posição).
  Precedência: OUT_OF_OBJECTIVE > IDENTICAL_COPY > OTHER_LANGUAGE >
  OTHER_VARIANT. Cada exemplar conta em UMA categoria; a soma das quatro
  é extras_total. has_identical_duplicates ⇔ extras_identical > 0.
  Ordem dos adicionais: os do objetivo primeiro, pela ordem da posição;
  depois os fora do objetivo (SET/MASTER por número da carta; Pokédex por
  entrada na coleção); dentro do grupo, a mesma ordem de desempate.

COLOCAÇÃO
  capacidade = colunas × linhas. Item i (base 1) da sequência principal:
    página = (i − 1) / capacidade + 1
    linha  = ((i − 1) % capacidade) / colunas + 1
    coluna = ((i − 1) % capacidade) % colunas + 1      (leitura por linhas)
  APPEND_PAGES: o adicional j começa na página seguinte à última da
    sequência principal (páginas_principais = ⌈M / capacidade⌉), mesma
    fórmula; nunca intercalado no checklist; sem reserva.
  PRINCIPAL_ONLY: adicionais sem página (ficam sem bolso).
  páginas = max(1, ⌈M/cap⌉ + (APPEND ? ⌈E/cap⌉ : 0)). Coleção vazia → 1
  página vazia. Bolsos excedentes ficam vazios e sem reserva.

TOKEN DO PLANO ('v1:' + SHA-256, 64 hex)
  Serialização canônica do PLANO RESULTANTE — não dos insumos:
    versão do algoritmo | coleção | tipo | política | colunas×linhas |
    opção de adicionais | acabamentos escolhidos (ordenados) | páginas
    + uma linha por item, ordenada (tipo, ordem):
      POSITION|ordem|página|linha|coluna|carta esperada|acabamento esperado|alocação
      EXTRA   |ordem|página ou -|linha|coluna|-|-|alocação|categoria
  Qualquer mudança que altere a organização (alocação nova/removida,
  vínculo de Pokédex, objetivo do Master Set, catálogo — C-190 —,
  idioma ou data que mudem o principal, modelo, opção) muda o token;
  mudanças irrelevantes para a organização não mudam. Nunca contagem.

CONCORRÊNCIA (revisada na P2-A1-PROPOSAL-AUDIT-CORRECTION-01, 2026-10-23)
  O token NÃO dá isolamento transacional. Ele só prova que o plano
  recalculado sob a trava é idêntico ao que o usuário viu. A segurança vem
  de três mecanismos distintos:

  A. SERIALIZADO pela trava FOR UPDATE da linha de collection (verificado
     nos contratos canônicos; todos travam a coleção ANTES de escrever):
     - alocar/desalocar: 5046, 5047 (FOR UPDATE da coleção);
     - registro em lote com coleção: 5148 (inventory → collection), usado
       por 5150/5152/5153/5155/5157;
     - política e acabamentos do Master Set: 5194, 5195 (5193 é helper
       delas), 5081 (volta ao Set padrão), 5080 (versão anterior, mesma
       trava);
     - Pokédex: 6123 (vínculo, coleção primeiro), 6124 (remover vínculo),
       6125/6126 (representante), 5210 (vincular cópia → 5046 + 6123),
       5099/5203 (gerações; 6119 roda dentro da 5046);
     - arquivar/reativar/local padrão/metadados: 5037, 5038, 5036, 5035
       (UPDATE da própria linha = mesma trava de linha);
     - layout: toda edição passa por 5122 (coleção → layout); 5123 trava a
       coleção; 5124 (apagar layout) via 5122.
     Efeito: nenhuma escrita de usuário que altere o plano (alocações,
     vínculos, objetivo, gerações, lifecycle, layout) acontece entre o
     cálculo do plano e o commit da criação. Duas criações simultâneas: a
     segunda espera, relê (READ COMMITTED: novo snapshot por comando) e
     devolve ALREADY_EXISTS. UNIQUE(collection_id) (5105) é a barreira final.
     Identidade do exemplar (variante, idioma, created_at) não tem escritor
     algum (só storage_container_id muda, por 5024/5222, e não entra no
     plano); exclusão de exemplar (5165) exige que ele não esteja alocado.

  B. DETECTADO pelo token (mudou entre a prévia e a trava → PLAN_CHANGED,
     nada gravado):
     - tudo de A que ocorra ANTES da trava (alocação, desalocação, vínculo,
       acabamentos, gerações);
     - catálogo editorial (admin: 2116/2117 ativar carta, 2155–2157
       acabamento, 2048 Card Set — inclui base_set_size, que define
       secretas —, variantes, collector_order, language_order);
     - modelo (colunas × linhas) e opção de adicionais diferentes dos da
       prévia.

  C. PODE OCORRER entre o cálculo (sob a trava) e o commit — e por que é
     seguro:
     - edição de catálogo pelo admin (não trava coleções). O plano é
       calculado em UM comando (snapshot único) e é exatamente ele que se
       grava. Uma mudança concorrente não corrompe: as FKs de reserva e de
       posição são RESTRICT (exclusão de carta/variante/acabamento usado
       falha ou espera; se a exclusão já tiver commitado, o INSERT falha com
       23503 e TUDO é desfeito); desativação ou reordenação só faz o
       fichário refletir o catálogo do instante da prévia — o mesmo que
       aconteceria se o admin agisse um instante depois do commit;
     - troca do tipo do local (5217, trava só o local): D1 é avaliada no
       instante da criação; a ordem observável equivale a "criou, depois
       trocou o tipo", e D1 garante acesso depois da troca. O local NÃO é
       travado aqui de propósito (5148 trava coleção → local; 5217/5218
       travam só o local; uma trava extra só acrescentaria espera);
     - exclusão do local padrão (5218): recusada enquanto ele for padrão de
       alguma coleção (STORAGE_IS_COLLECTION_DEFAULT) — não há corrida;
     - caminho direto de criação de layout (5123): serializado (A), mas
       contornava D1 — fechado pela 5227.
     - troca de grade (5137/5141): serializada (A, via 5122); a 5228 a
       restringe aos sete modelos (D2).
  lock_timeout 5s: espera longa → erro 55P03, nada gravado.

ATOMICIDADE
  Uma transação: layout, páginas, bolsos, reservas e posições. Qualquer
  erro (trigger, FK, contagem divergente) desfaz tudo. Nenhuma escrita em
  physical_card, collection_allocation ou storage_container.

VOLUME (NÃO MEDIDO — pendente do harness 5850, Seção P)
  c_max_allocations = 10.000 e c_max_slots = 20.000 são valores
  PROVISÓRIOS de proteção, não aprovados: o teto definitivo só depois da
  medição (500 / 2.000 / 10.000 alocações, Master Set grande, 2×2).

ERROS (SQLSTATE · mensagem)
  28000 not_authenticated · 22023 INVALID_ARGUMENT / INVALID_GRID /
  INVALID_EXTRA_POLICY / INVALID_PLAN_TOKEN · P0002 COLLECTION_NOT_FOUND
  (inexistente e alheia: mesma resposta) · 55000 COLLECTION_ARCHIVED /
  NOT_ELIGIBLE · 54000 COLLECTION_TOO_LARGE · P0001 PLAN_CHANGED /
  LAYOUT_ALREADY_EXISTS / BINDER_ASSEMBLY_INCONSISTENT /
  COLLECTION_REFERENCE_MISSING · 22023 COLLECTION_KIND_UNSUPPORTED (só se a
  coleção tiver combinação mode/política fora das quatro) · 23503 (catálogo
  removido entre cálculo e INSERT — tudo desfeito) · 55P03 (lock_timeout).
================================================================
*/

begin;

do $pre$
begin
  if to_regprocedure('public.collection_binder_plan(uuid, integer, integer, text)') is not null
     or to_regprocedure('public.preview_my_collection_binder(uuid, integer, integer, text)') is not null
     or to_regprocedure('public.create_my_collection_binder(uuid, integer, integer, text, text)') is not null then
    raise exception 'PRECHECK 5224: funções já existem';
  end if;
  if not exists (select 1 from information_schema.columns
                 where table_schema = 'public'
                   and table_name = 'collection_layout_slot_expected_content'
                   and column_name = 'expected_variant_type_id') then
    raise exception 'PRECHECK 5224: aplique a 5225 antes';
  end if;
  if to_regprocedure('public.master_set_positions(uuid, uuid[])') is null
     or to_regclass('public.collection_master_set_finish') is null
     or to_regclass('public.collection_pokedex_position_assignment') is null
     or to_regclass('public.collection_pokedex_position_primary_representative') is null
     or to_regclass('public.collection_pokedex_scope_generation') is null
     or to_regclass('public.collection_layout') is null then
    raise exception 'PRECHECK 5224: dependências ausentes (5187/5184/6117/6120/5091/5105)';
  end if;
  if not exists (select 1 from information_schema.columns
                 where table_schema = 'public' and table_name = 'storage_container'
                   and column_name = 'kind_code') then
    raise exception 'PRECHECK 5224: storage_container.kind_code ausente (5213)';
  end if;
end;
$pre$;

-- 1. Helper INTERNO: plano determinístico + token (fonte única) --------------------
create function public.collection_binder_plan(
  p_collection_id uuid,
  p_grid_columns  integer,
  p_grid_rows     integer,
  p_extra_policy  text
)
returns table (
  item_kind                text,     -- HEADER | POSITION | EXTRA
  item_ord                 integer,  -- 0 no HEADER; 1.. por tipo
  page_number              integer,  -- null: adicional sem bolso
  row_index                integer,
  column_index             integer,
  expected_card_id         uuid,
  expected_variant_type_id uuid,
  collection_allocation_id uuid,
  extra_category           text,
  main_count               integer,
  extra_count              integer,
  pages_total              integer,
  plan_token               text
)
language plpgsql
volatile
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  c_version  constant text := 'p2a1-plan-v1';
  v_cap      integer;
  v_mode     text;
  v_policy   text;
  v_kind     text;
  v_set      uuid;
  v_types    uuid[] := '{}';
  v_types_k  text := '';
  v_ref      uuid;
  v_dex      uuid;
  v_scope    text;
begin
  if p_collection_id is null or p_grid_columns is null or p_grid_rows is null
     or p_grid_columns < 1 or p_grid_rows < 1 then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;
  if p_extra_policy is null or p_extra_policy not in ('PRINCIPAL_ONLY', 'APPEND_PAGES') then
    raise exception 'INVALID_EXTRA_POLICY' using errcode = '22023';
  end if;
  v_cap := p_grid_columns * p_grid_rows;

  select c.mode, c.completion_policy into v_mode, v_policy
  from public.collection c where c.id = p_collection_id;
  if not found then
    raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';
  end if;

  v_kind := case
    when v_mode = 'OPEN_CURATION' then 'FREE'
    when v_policy = 'STANDARD_SET' then 'SET'
    when v_policy = 'MASTER_SET' then 'MASTER_SET'
    when v_policy = 'REFERENCE_POSITION' then 'POKEDEX'
    else null end;
  if v_kind is null then
    raise exception 'COLLECTION_KIND_UNSUPPORTED' using errcode = '22023';
  end if;

  if v_kind in ('SET', 'MASTER_SET') then
    select ccsr.card_set_id into v_set
    from public.collection_reference cr
    join public.collection_card_set_reference ccsr on ccsr.collection_reference_id = cr.id
    where cr.collection_id = p_collection_id;
    if v_set is null then
      raise exception 'COLLECTION_REFERENCE_MISSING' using errcode = 'P0001';
    end if;
  end if;

  if v_kind = 'MASTER_SET' then
    select coalesce(array_agg(f.variant_type_id order by f.variant_type_id), '{}')
      into v_types
    from public.collection_master_set_finish f
    where f.collection_id = p_collection_id;
    v_types_k := array_to_string(v_types, ',');
  end if;

  if v_kind = 'POKEDEX' then
    select cr.id, cpr.pokedex_id, cpr.scope_kind into v_ref, v_dex, v_scope
    from public.collection_reference cr
    join public.collection_pokedex_reference cpr on cpr.collection_reference_id = cr.id
    where cr.collection_id = p_collection_id and cr.reference_kind = 'POKEDEX';
    if v_ref is null then
      raise exception 'COLLECTION_REFERENCE_MISSING' using errcode = 'P0001';
    end if;
  end if;

  return query
  with
  alloc as (
    select ca.id                as alloc_id,
           ca.created_at        as alloc_created,
           pc.id                as pc_id,
           pc.created_at        as pc_created,
           pc.language_id       as lang_id,
           l.language_order     as lord,
           cv.id                as var_id,
           cv.card_id           as card_id,
           cv.variant_type_id   as vt_id,
           cv.variant_order     as vord,
           coalesce(vt.display_order, 2147483647) as vt_ord,
           c.collector_order    as c_ord,
           cs.code::text        as set_code,
           pa.pokedex_position_id as link_pos,
           pa.assigned_at       as assigned_at,
           (pr.collection_allocation_id is not null) as is_rep
    from public.collection_allocation ca
    join public.physical_card pc on pc.id = ca.physical_card_id
    join public.card_variant cv  on cv.id = pc.card_variant_id
    join public.card c           on c.id = cv.card_id
    join public.card_set cs      on cs.id = c.card_set_id
    join public.language l       on l.id = pc.language_id
    left join public.card_variant_type vt on vt.id = cv.variant_type_id
    left join public.collection_pokedex_position_assignment pa
           on v_kind = 'POKEDEX' and pa.collection_allocation_id = ca.id
    left join public.collection_pokedex_position_primary_representative pr
           on v_kind = 'POKEDEX' and pr.collection_allocation_id = ca.id
          and pr.collection_id = p_collection_id
    where ca.collection_id = p_collection_id
  ),
  dex_pos as (
    select pp.id as pos_id, pp.position_number as pnum
    from public.pokedex_position pp
    join public.pokemon_species s on s.id = pp.species_id
    where v_kind = 'POKEDEX'
      and pp.pokedex_id = v_dex
      and pp.id in (select a.link_pos from alloc a where a.link_pos is not null)
      and (v_scope = 'FULL_REFERENCE'
           or exists (select 1 from public.collection_pokedex_scope_generation sg
                      where sg.collection_reference_id = v_ref
                        and sg.generation_id = s.generation_id))
  ),
  pos as (
    select c.id::text as pos_key, c.id as exp_card, null::uuid as exp_vt,
           (row_number() over (order by c.collector_order, c.collector_number, c.id))::integer as pos_ord
    from public.card c
    where v_kind = 'SET' and c.card_set_id = v_set
    union all
    select m.card_id::text || ':' || coalesce(m.variant_type_id::text, '*'),
           m.card_id, m.variant_type_id,
           (row_number() over (order by c.collector_order, c.collector_number, c.id,
                                        (m.variant_type_id is null),
                                        coalesce(t.display_order, 2147483647),
                                        m.variant_type_id))::integer
    from public.master_set_positions(case when v_kind = 'MASTER_SET' then v_set end, v_types) m
    join public.card c on c.id = m.card_id
    left join public.card_variant_type t on t.id = m.variant_type_id
    where v_kind = 'MASTER_SET'
    union all
    select d.pos_id::text, null::uuid, null::uuid,
           (row_number() over (order by d.pnum, d.pos_id))::integer
    from dex_pos d
    union all
    select a.alloc_id::text, null::uuid, null::uuid,
           (row_number() over (order by a.alloc_created, a.set_code, a.c_ord, a.vt_ord,
                                        a.vord, a.lord, a.pc_created, a.pc_id))::integer
    from alloc a
    where v_kind = 'FREE'
  ),
  grouped as (
    select a.*,
           case v_kind
             when 'SET'        then p_card.pos_key
             when 'MASTER_SET' then coalesce(p_type.pos_key, p_star.pos_key)
             when 'POKEDEX'    then p_dex.pos_key
             when 'FREE'       then a.alloc_id::text
           end as grp,
           case when v_kind = 'POKEDEX' then (case when a.is_rep then 0 else 1 end) else 0 end as k_rep,
           case when v_kind = 'POKEDEX' then a.assigned_at end                               as k_assigned,
           case when v_kind = 'POKEDEX' then 0 else a.vt_ord end                             as k_vt,
           case when v_kind = 'POKEDEX' then 0 else a.vord end                               as k_vord,
           case when v_kind = 'POKEDEX' then 0 else a.lord end                               as k_lord,
           case when v_kind = 'POKEDEX'
                then (case when a.link_pos is null then a.alloc_created end)
                else a.pc_created end                                                        as k_created,
           case when v_kind = 'POKEDEX' then a.alloc_id else a.pc_id end                      as k_tie
    from alloc a
    left join pos p_card on v_kind = 'SET'        and p_card.pos_key = a.card_id::text
    left join pos p_type on v_kind = 'MASTER_SET' and p_type.pos_key = a.card_id::text || ':' || a.vt_id::text
    left join pos p_star on v_kind = 'MASTER_SET' and p_star.pos_key = a.card_id::text || ':*'
    left join pos p_dex  on v_kind = 'POKEDEX'    and p_dex.pos_key  = a.link_pos::text
  ),
  ranked as (
    select g.*,
           row_number() over (partition by g.grp
                              order by g.k_rep, g.k_assigned nulls last, g.k_vt, g.k_vord, g.k_lord,
                                       g.k_created nulls last, g.k_tie) as rk,
           row_number() over (partition by g.grp, g.var_id, g.lang_id
                              order by g.k_rep, g.k_assigned nulls last, g.k_vt, g.k_vord, g.k_lord,
                                       g.k_created nulls last, g.k_tie) as rk_vl,
           row_number() over (partition by g.grp, g.var_id
                              order by g.k_rep, g.k_assigned nulls last, g.k_vt, g.k_vord, g.k_lord,
                                       g.k_created nulls last, g.k_tie) as rk_v
    from grouped g
  ),
  main as (
    select p.pos_ord as m_ord, p.exp_card, p.exp_vt, r.alloc_id
    from pos p
    left join ranked r on r.grp = p.pos_key and r.rk = 1
  ),
  extras as (
    select r.alloc_id,
           case when r.grp is null then 'OUT_OF_OBJECTIVE'
                when r.rk_vl > 1  then 'IDENTICAL_COPY'
                when r.rk_v  > 1  then 'OTHER_LANGUAGE'
                else 'OTHER_VARIANT' end as category,
           (row_number() over (order by (r.grp is null), p.pos_ord nulls last,
                                        case when v_kind in ('SET', 'MASTER_SET') then r.c_ord else 0 end,
                                        case when v_kind in ('SET', 'MASTER_SET') then r.card_id end,
                                        r.k_rep, r.k_assigned nulls last, r.k_vt, r.k_vord, r.k_lord,
                                        r.k_created nulls last, r.k_tie))::integer as x_ord
    from ranked r
    left join pos p on p.pos_key = r.grp
    where r.grp is null or r.rk > 1
  ),
  geo as (
    select d.m_cnt, d.e_cnt,
           ((d.m_cnt + v_cap - 1) / v_cap)::integer as main_pages,
           (case when p_extra_policy = 'APPEND_PAGES' then (d.e_cnt + v_cap - 1) / v_cap else 0 end)::integer as extra_pages
    from (select (select count(*) from main)::integer as m_cnt,
                 (select count(*) from extras)::integer as e_cnt) d
  ),
  placed as (
    select 'POSITION'::text as k,
           m.m_ord as o,
           ((m.m_ord - 1) / v_cap + 1)::integer as pg,
           (((m.m_ord - 1) % v_cap) / p_grid_columns + 1)::integer as rw,
           (((m.m_ord - 1) % v_cap) % p_grid_columns + 1)::integer as cl,
           m.exp_card as ec, m.exp_vt as ev, m.alloc_id as al, null::text as cat
    from main m
    union all
    select 'EXTRA'::text,
           x.x_ord,
           case when p_extra_policy = 'APPEND_PAGES'
                then (g.main_pages + (x.x_ord - 1) / v_cap + 1)::integer end,
           case when p_extra_policy = 'APPEND_PAGES'
                then (((x.x_ord - 1) % v_cap) / p_grid_columns + 1)::integer end,
           case when p_extra_policy = 'APPEND_PAGES'
                then (((x.x_ord - 1) % v_cap) % p_grid_columns + 1)::integer end,
           null::uuid, null::uuid, x.alloc_id, x.category
    from extras x
    cross join geo g
  ),
  tok as (
    select 'v1:' || encode(sha256(convert_to(
             c_version || '|' || p_collection_id::text || '|' || v_kind || '|' || coalesce(v_policy, '') || '|'
             || p_grid_columns::text || 'x' || p_grid_rows::text || '|' || p_extra_policy || '|' || v_types_k || '|'
             || (select greatest(1, g.main_pages + g.extra_pages)::text from geo g)
             || E'\n'
             || coalesce(string_agg(
                  concat_ws('|', pl.k, pl.o,
                            coalesce(pl.pg::text, '-'), coalesce(pl.rw::text, '-'), coalesce(pl.cl::text, '-'),
                            coalesce(pl.ec::text, '-'), coalesce(pl.ev::text, '-'),
                            coalesce(pl.al::text, '-'), coalesce(pl.cat, '-')),
                  E'\n' order by pl.k, pl.o), ''),
             'UTF8')), 'hex') as t
    from placed pl
  )
  select 'HEADER'::text, 0, null::integer, null::integer, null::integer, null::uuid, null::uuid, null::uuid, null::text,
         g.m_cnt, g.e_cnt, greatest(1, g.main_pages + g.extra_pages)::integer, t.t
  from geo g cross join tok t
  union all
  select pl.k, pl.o, pl.pg, pl.rw, pl.cl, pl.ec, pl.ev, pl.al, pl.cat,
         g.m_cnt, g.e_cnt, greatest(1, g.main_pages + g.extra_pages)::integer, t.t
  from placed pl cross join geo g cross join tok t;
end;
$$;

comment on function public.collection_binder_plan(uuid, integer, integer, text) is
  'Fichário Digital (Query 5224): FONTE ÚNICA do plano de montagem (posições, reservas, principais, adicionais classificados, colocação por colunas × linhas) e do plan_token (SHA-256 do plano resultante). Helper INTERNO: EXECUTE revogado de PUBLIC/anon/authenticated/service_role; chamado só por preview_my_collection_binder e create_my_collection_binder (SECURITY DEFINER), que já validaram dono, grade e opção. VOLATILE: a criação recalcula sob a trava. Somente leitura.';

revoke all on function public.collection_binder_plan(uuid, integer, integer, text) from public;
revoke all on function public.collection_binder_plan(uuid, integer, integer, text) from anon;
revoke all on function public.collection_binder_plan(uuid, integer, integer, text) from authenticated;
revoke all on function public.collection_binder_plan(uuid, integer, integer, text) from service_role;

-- 2. Prévia ------------------------------------------------------------------------
create function public.preview_my_collection_binder(
  p_collection_id uuid,
  p_grid_columns  integer,
  p_grid_rows     integer,
  p_extra_policy  text
)
returns table (
  collection_id            uuid,
  collection_kind          text,
  completion_policy        text,
  lifecycle_active         boolean,
  binder_exists            boolean,
  eligible                 boolean,
  grid_columns             integer,
  grid_rows                integer,
  capacity_per_page        integer,
  extra_policy             text,
  too_large                boolean,
  max_allocations          integer,
  allocations_total        integer,
  positions_total          integer,
  positions_owned          integer,
  positions_reserved       integer,
  extras_total             integer,
  extras_identical         integer,
  extras_other_language    integer,
  extras_other_variant     integer,
  extras_out_of_objective  integer,
  extras_placed            integer,
  extras_unplaced          integer,
  has_identical_duplicates boolean,
  pages_total              integer,
  slots_total              integer,
  slots_empty_trailing     integer,
  sample                   jsonb,
  plan_token               text
)
language plpgsql
volatile
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  c_max_allocations constant integer := 10000;   -- PROVISÓRIO: pendente de medição (5850 Seção P)
  c_max_slots       constant integer := 20000;   -- PROVISÓRIO: pendente de medição (5850 Seção P)
  v_uid      uuid := auth.uid();
  v_policy_x text := upper(btrim(coalesce(p_extra_policy, '')));
  v_mode     text;
  v_policy   text;
  v_status   text;
  v_default  uuid;
  v_kind     text;
  v_kind_sc  text;
  v_exists   boolean;
  v_allocs   integer;
  v_cap      integer;
  r          record;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_collection_id is null or p_grid_columns is null or p_grid_rows is null then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;
  if (p_grid_columns, p_grid_rows) not in ((2,2), (3,3), (3,4), (4,3), (4,4), (4,5), (5,4)) then
    raise exception 'INVALID_GRID' using errcode = '22023';
  end if;
  if v_policy_x not in ('PRINCIPAL_ONLY', 'APPEND_PAGES') then
    raise exception 'INVALID_EXTRA_POLICY' using errcode = '22023';
  end if;
  v_cap := p_grid_columns * p_grid_rows;

  select c.mode, c.completion_policy, c.lifecycle_status, c.default_storage_container_id
    into v_mode, v_policy, v_status, v_default
  from public.collection c
  where c.id = p_collection_id and c.owner_user_id = v_uid;
  if not found then
    raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';
  end if;

  v_kind := case
    when v_mode = 'OPEN_CURATION' then 'FREE'
    when v_policy = 'STANDARD_SET' then 'SET'
    when v_policy = 'MASTER_SET' then 'MASTER_SET'
    when v_policy = 'REFERENCE_POSITION' then 'POKEDEX'
    else 'UNKNOWN' end;

  if v_default is not null then
    select sc.kind_code::text into v_kind_sc
    from public.storage_container sc
    join public.inventory i on i.id = sc.inventory_id
    where sc.id = v_default and i.owner_user_id = v_uid;
  end if;

  v_exists := exists (select 1 from public.collection_layout l where l.collection_id = p_collection_id);

  select count(*)::integer into v_allocs
  from public.collection_allocation ca where ca.collection_id = p_collection_id;

  collection_id     := p_collection_id;
  collection_kind   := v_kind;
  completion_policy := v_policy;
  lifecycle_active  := v_status = 'ACTIVE';
  binder_exists     := v_exists;
  eligible          := coalesce(v_kind_sc = 'BINDER', false);
  grid_columns      := p_grid_columns;
  grid_rows         := p_grid_rows;
  capacity_per_page := v_cap;
  extra_policy      := v_policy_x;
  max_allocations   := c_max_allocations;
  allocations_total := v_allocs;
  too_large         := v_allocs > c_max_allocations;

  -- Fichário já existe, coleção grande demais ou tipo desconhecido: sem plano.
  if v_exists or too_large or v_kind = 'UNKNOWN' then
    return next;
    return;
  end if;

  -- Plano calculado UMA vez (CTE materializada): contagens e amostra saem da
  -- mesma execução — a prévia nunca mostra números de um plano e amostra de outro.
  with h as materialized (
    select * from public.collection_binder_plan(p_collection_id, p_grid_columns, p_grid_rows, v_policy_x)
  ),
  agg as (
    select
      max(h.plan_token)                                                               as tok,
      max(h.pages_total)                                                              as pages,
      (count(*) filter (where h.item_kind = 'POSITION'))::integer                     as pos_total,
      (count(*) filter (where h.item_kind = 'POSITION' and h.collection_allocation_id is not null))::integer as pos_owned,
      (count(*) filter (where h.item_kind = 'POSITION' and h.collection_allocation_id is null
                          and h.expected_card_id is not null))::integer               as pos_reserved,
      (count(*) filter (where h.item_kind = 'EXTRA'))::integer                        as x_total,
      (count(*) filter (where h.extra_category = 'IDENTICAL_COPY'))::integer          as x_ident,
      (count(*) filter (where h.extra_category = 'OTHER_LANGUAGE'))::integer          as x_lang,
      (count(*) filter (where h.extra_category = 'OTHER_VARIANT'))::integer           as x_var,
      (count(*) filter (where h.extra_category = 'OUT_OF_OBJECTIVE'))::integer        as x_ooo,
      (count(*) filter (where h.item_kind = 'EXTRA' and h.page_number is not null))::integer as x_placed
    from h
  ),
  smp as (
    -- Amostra visual: bolsos da página 1 (≤ 25), com nome, número, acabamento e arte.
    select coalesce(jsonb_agg(jsonb_build_object(
             'row', s.row_index, 'column', s.column_index,
             'state', case when s.collection_allocation_id is not null and s.item_kind = 'POSITION' then 'ASSIGNED'
                           when s.collection_allocation_id is not null then 'EXTRA'
                           else 'RESERVED' end,
             'card_name', coalesce(pc_card.name, ex_card.name),
             'collector_number', coalesce(pc_card.collector_number, ex_card.collector_number),
             'variant_type_code', coalesce(pvt.code, evt.code),
             'image_path', img.storage_path)
           order by s.row_index, s.column_index), '[]'::jsonb) as js
    from h s
    left join public.collection_allocation ca on ca.id = s.collection_allocation_id
                                              and ca.collection_id = p_collection_id
    left join public.physical_card pc  on pc.id = ca.physical_card_id
    left join public.card_variant cv   on cv.id = pc.card_variant_id
    left join public.card pc_card      on pc_card.id = cv.card_id
    left join public.card_variant_type pvt on pvt.id = cv.variant_type_id
    left join public.card ex_card      on ex_card.id = s.expected_card_id
    left join public.card_variant_type evt on evt.id = s.expected_variant_type_id
    left join lateral (
      select ast.storage_path
      from public.card_asset ast
      join public.card_asset_type cat on cat.id = ast.asset_type_id and cat.code = 'CARD_FRONT'
      join public.language al         on al.id = ast.language_id
      where ast.card_id = coalesce(pc_card.id, ex_card.id)
        and ast.is_primary and ast.is_active and ast.storage_path is not null
      order by (ast.language_id = pc.language_id) desc nulls last,
               (al.code = 'pt-BR') desc, (al.code = 'en') desc, al.language_order asc
      limit 1
    ) img on true
    where s.item_kind <> 'HEADER' and s.page_number = 1
  )
  select agg.*, smp.js as sample_js into r
  from agg cross join smp;

  positions_total          := r.pos_total;
  positions_owned          := r.pos_owned;
  positions_reserved       := r.pos_reserved;
  extras_total             := r.x_total;
  extras_identical         := r.x_ident;
  extras_other_language    := r.x_lang;
  extras_other_variant     := r.x_var;
  extras_out_of_objective  := r.x_ooo;
  extras_placed            := r.x_placed;
  extras_unplaced          := r.x_total - r.x_placed;
  has_identical_duplicates := r.x_ident > 0;
  pages_total              := r.pages;
  slots_total              := r.pages * v_cap;
  slots_empty_trailing     := r.pages * v_cap - r.pos_total - r.x_placed;

  if slots_total > c_max_slots then
    too_large := true;
    pages_total := null; slots_total := null; slots_empty_trailing := null;
    return next;
    return;
  end if;

  sample     := r.sample_js;
  plan_token := r.tok;
  return next;
end;
$$;

comment on function public.preview_my_collection_binder(uuid, integer, integer, text) is
  'Fichário Digital (Query 5224): prévia da montagem automática da coleção do usuário da sessão para um dos sete modelos (colunas × linhas) e uma opção de adicionais (PRINCIPAL_ONLY | APPEND_PAGES) — tipo, política, elegível (BINDER), posições previstas/atendidas/reservadas, adicionais por categoria (cópias idênticas, outro idioma, outra variante, fora do objetivo), posicionados × sem bolso, páginas e bolsos, amostra da página 1 e plan_token. Não grava nada. Exige auth.uid(); não enumera.';

revoke all on function public.preview_my_collection_binder(uuid, integer, integer, text) from public;
revoke all on function public.preview_my_collection_binder(uuid, integer, integer, text) from anon;
grant execute on function public.preview_my_collection_binder(uuid, integer, integer, text) to authenticated;

-- 3. Criação transacional -----------------------------------------------------------
create function public.create_my_collection_binder(
  p_collection_id uuid,
  p_grid_columns  integer,
  p_grid_rows     integer,
  p_extra_policy  text,
  p_plan_token    text
)
returns table (
  outcome              text,     -- CREATED | ALREADY_EXISTS
  layout_id            uuid,
  grid_columns         integer,
  grid_rows            integer,
  pages_created        integer,
  slots_created        integer,
  reservations_created integer,
  assignments_created  integer,
  extras_unplaced      integer
)
language plpgsql
volatile
security definer
set search_path = ''
set lock_timeout = '5s'
as $$
#variable_conflict use_column
declare
  c_max_allocations constant integer := 10000;   -- PROVISÓRIO: mesmo valor da prévia
  c_max_slots       constant integer := 20000;   -- PROVISÓRIO: mesmo valor da prévia
  v_uid       uuid := auth.uid();
  v_policy_x  text := upper(btrim(coalesce(p_extra_policy, '')));
  v_status    text;
  v_default   uuid;
  v_kind_sc   text;
  v_layout    uuid;
  v_ex_cols   integer;
  v_ex_rows   integer;
  v_allocs    integer;
  v_cap       integer;
  v_token     text;
  v_pages     integer;
  v_unplaced  integer;
  a_pg        integer[];
  a_rw        integer[];
  a_cl        integer[];
  a_ec        uuid[];
  a_ev        uuid[];
  a_al        uuid[];
  v_exp_resv  integer;
  v_exp_asg   integer;
  v_n_pages   integer;
  v_n_slots   integer;
  v_n_resv    integer;
  v_n_asg     integer;
begin
  -- 0. Forma ------------------------------------------------------------------------
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_collection_id is null or p_grid_columns is null or p_grid_rows is null then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;
  if (p_grid_columns, p_grid_rows) not in ((2,2), (3,3), (3,4), (4,3), (4,4), (4,5), (5,4)) then
    raise exception 'INVALID_GRID' using errcode = '22023';
  end if;
  if v_policy_x not in ('PRINCIPAL_ONLY', 'APPEND_PAGES') then
    raise exception 'INVALID_EXTRA_POLICY' using errcode = '22023';
  end if;
  if p_plan_token is null or p_plan_token !~ '^v1:[0-9a-f]{64}$' then
    raise exception 'INVALID_PLAN_TOKEN' using errcode = '22023';
  end if;
  v_cap := p_grid_columns * p_grid_rows;

  -- 1. Coleção: trava comum a toda escrita de usuário que altera o plano --------
  select c.lifecycle_status, c.default_storage_container_id
    into v_status, v_default
  from public.collection c
  where c.id = p_collection_id and c.owner_user_id = v_uid
  for update;
  if not found then
    raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';
  end if;

  -- 2. Idempotência: fichário existente → ALREADY_EXISTS, nada muda ------------
  select l.id, l.grid_columns, l.grid_rows into v_layout, v_ex_cols, v_ex_rows
  from public.collection_layout l
  where l.collection_id = p_collection_id;
  if v_layout is not null then
    outcome := 'ALREADY_EXISTS';
    layout_id := v_layout;
    grid_columns := v_ex_cols;
    grid_rows := v_ex_rows;
    pages_created := 0; slots_created := 0; reservations_created := 0;
    assignments_created := 0; extras_unplaced := 0;
    return next;
    return;
  end if;

  -- 3. Coleção ativa ----------------------------------------------------------------
  if v_status <> 'ACTIVE' then
    raise exception 'COLLECTION_ARCHIVED' using errcode = '55000';
  end if;

  -- 4. D1: local padrão do próprio acervo, do tipo BINDER (lido sob a trava) ----
  if v_default is not null then
    select sc.kind_code::text into v_kind_sc
    from public.storage_container sc
    join public.inventory i on i.id = sc.inventory_id
    where sc.id = v_default and i.owner_user_id = v_uid;
  end if;
  if v_kind_sc is distinct from 'BINDER' then
    raise exception 'NOT_ELIGIBLE' using errcode = '55000';
  end if;

  -- 5. Volume (provisório) antes do plano -----------------------------------------
  select count(*)::integer into v_allocs
  from public.collection_allocation ca where ca.collection_id = p_collection_id;
  if v_allocs > c_max_allocations then
    raise exception 'COLLECTION_TOO_LARGE' using errcode = '54000';
  end if;

  -- 6. Plano: calculado UMA vez, sob a trava; é exatamente o que será gravado ----
  select max(h.plan_token),
         max(h.pages_total),
         array_agg(h.page_number order by h.item_kind, h.item_ord)
           filter (where h.item_kind <> 'HEADER' and h.page_number is not null),
         array_agg(h.row_index order by h.item_kind, h.item_ord)
           filter (where h.item_kind <> 'HEADER' and h.page_number is not null),
         array_agg(h.column_index order by h.item_kind, h.item_ord)
           filter (where h.item_kind <> 'HEADER' and h.page_number is not null),
         array_agg(h.expected_card_id order by h.item_kind, h.item_ord)
           filter (where h.item_kind <> 'HEADER' and h.page_number is not null),
         array_agg(h.expected_variant_type_id order by h.item_kind, h.item_ord)
           filter (where h.item_kind <> 'HEADER' and h.page_number is not null),
         array_agg(h.collection_allocation_id order by h.item_kind, h.item_ord)
           filter (where h.item_kind <> 'HEADER' and h.page_number is not null),
         (count(*) filter (where h.item_kind = 'EXTRA' and h.page_number is null))::integer,
         (count(*) filter (where h.item_kind <> 'HEADER' and h.page_number is not null
                             and h.expected_card_id is not null))::integer,
         (count(*) filter (where h.item_kind <> 'HEADER' and h.page_number is not null
                             and h.collection_allocation_id is not null))::integer
    into v_token, v_pages, a_pg, a_rw, a_cl, a_ec, a_ev, a_al, v_unplaced, v_exp_resv, v_exp_asg
  from public.collection_binder_plan(p_collection_id, p_grid_columns, p_grid_rows, v_policy_x) h;

  if v_pages is null or v_pages < 1 then
    raise exception 'BINDER_ASSEMBLY_INCONSISTENT';
  end if;
  if v_pages * v_cap > c_max_slots then
    raise exception 'COLLECTION_TOO_LARGE' using errcode = '54000';
  end if;

  -- 7. O usuário autoriza exatamente o que viu --------------------------------------
  if v_token is distinct from p_plan_token then
    raise exception 'PLAN_CHANGED';
  end if;

  -- 8. Escrita atômica, set-based ----------------------------------------------------
  begin
    insert into public.collection_layout (collection_id, grid_rows, grid_columns)
    values (p_collection_id, p_grid_rows, p_grid_columns)
    returning id into v_layout;
  exception when unique_violation then
    raise exception 'LAYOUT_ALREADY_EXISTS';
  end;

  insert into public.collection_layout_page (layout_id, page_number)
  select v_layout, g from generate_series(1, v_pages) g;
  get diagnostics v_n_pages = row_count;

  insert into public.collection_layout_slot (page_id, row_index, column_index)
  select p.id, gr.n, gc.n
  from public.collection_layout_page p
  cross join generate_series(1, p_grid_rows) as gr(n)
  cross join generate_series(1, p_grid_columns) as gc(n)
  where p.layout_id = v_layout;
  get diagnostics v_n_slots = row_count;

  insert into public.collection_layout_slot_expected_content
    (slot_id, card_id, card_variant_id, expected_variant_type_id)
  select s.id, u.ec, null, u.ev
  from unnest(coalesce(a_pg, '{}'), coalesce(a_rw, '{}'), coalesce(a_cl, '{}'),
              coalesce(a_ec, '{}'), coalesce(a_ev, '{}')) as u(pg, rw, cl, ec, ev)
  join public.collection_layout_page p on p.layout_id = v_layout and p.page_number = u.pg
  join public.collection_layout_slot s on s.page_id = p.id and s.row_index = u.rw and s.column_index = u.cl
  where u.ec is not null;
  get diagnostics v_n_resv = row_count;

  insert into public.collection_layout_slot_assignment (slot_id, collection_allocation_id)
  select s.id, u.al
  from unnest(coalesce(a_pg, '{}'), coalesce(a_rw, '{}'), coalesce(a_cl, '{}'),
              coalesce(a_al, '{}')) as u(pg, rw, cl, al)
  join public.collection_layout_page p on p.layout_id = v_layout and p.page_number = u.pg
  join public.collection_layout_slot s on s.page_id = p.id and s.row_index = u.rw and s.column_index = u.cl
  where u.al is not null;
  get diagnostics v_n_asg = row_count;

  -- 9. Conferência: qualquer divergência desfaz TUDO ------------------------------
  if v_n_pages <> v_pages
     or v_n_slots <> v_pages * v_cap
     or v_n_resv <> v_exp_resv
     or v_n_asg <> v_exp_asg then
    raise exception 'BINDER_ASSEMBLY_INCONSISTENT';
  end if;

  outcome              := 'CREATED';
  layout_id            := v_layout;
  grid_columns         := p_grid_columns;
  grid_rows            := p_grid_rows;
  pages_created        := v_n_pages;
  slots_created        := v_n_slots;
  reservations_created := v_n_resv;
  assignments_created  := v_n_asg;
  extras_unplaced      := v_unplaced;
  return next;
end;
$$;

comment on function public.create_my_collection_binder(uuid, integer, integer, text, text) is
  'Fichário Digital (Query 5224): montagem automática, atômica e única do fichário da coleção do usuário da sessão. Trava a coleção (mesma trava de alocação, desalocação, objetivo, vínculos da Pokédex e edição de layout), exige ACTIVE e local padrão BINDER (D1), modelo entre os sete (colunas × linhas), recalcula o plano sob a trava e grava SÓ se o plan_token for o da prévia (PLAN_CHANGED caso contrário). Fichário existente → ALREADY_EXISTS sem alterar nada. Nunca altera exemplares, alocações ou localização física.';

revoke all on function public.create_my_collection_binder(uuid, integer, integer, text, text) from public;
revoke all on function public.create_my_collection_binder(uuid, integer, integer, text, text) from anon;
grant execute on function public.create_my_collection_binder(uuid, integer, integer, text, text) to authenticated;

notify pgrst, 'reload schema';

commit;
