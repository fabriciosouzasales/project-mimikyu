/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5210 - link_my_pokedex_copy(): vincular UM exemplar a uma
              posição da Pokédex — alocação (5046) e vínculo (6119/6122)
              numa única transação; exceção só com confirmação explícita
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO no LIVE em 2026-10-19 (autorização de
              Fabrício, PKX-03 LIVE) — ledger 20261019033754; 5846 v1.0
              27/27 PASS (GATE PASS, 99.1 resíduo zero).
              CANÔNICA em database/schema/. Corpo = LIVE (md5 de prosrc 9ab30eae162d6eca6331d18d42e4f6b4).
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-19 (POKEDEX-PKX-03-IMPLEMENTATION-01)

Por que existe: vincular um exemplar LIVRE a uma posição escolhida exige
duas escritas canônicas — alocar à coleção (5046, que dispara o vínculo
automático da 6119) e, quando a carta é de outra espécie, vincular à
posição com confirmação (6122, p_confirm_override). Em duas chamadas do
cliente, uma falha entre elas deixaria a carta na coleção sem a posição
escolhida (ou na posição da própria espécie). Esta função só compõe as
duas, na mesma transação, depois de validar tudo; não reimplementa
nenhuma regra de alocação ou de vínculo. Serve aos dois caminhos do
painel da posição:
  - vínculo normal (p_confirm_exception = false): só aceita carta cuja
    espécie principal é a da posição → SPECIES_MATCH (5046 + 6119; ou
    6122 se o exemplar já está nesta coleção sem posição);
  - vínculo excepcional (p_confirm_exception = true): aceita outra
    espécie → USER_OVERRIDE com o chamador como autor.
O lote continua usando a 5046 diretamente (só SPECIES_MATCH).

Contrato:
  link_my_pokedex_copy(p_collection_id uuid,
                            p_pokedex_position_id uuid,
                            p_physical_card_id uuid,
                            p_confirm_exception boolean)
  → collection_allocation_id, pokedex_position_id, assignment_basis,
    allocated_now, satisfied_positions, total_positions

  Ordem (falha antes de qualquer escrita):
  1. 28000 sem identidade; 22023 INVALID_INPUT com argumento nulo.
  2. Trava a coleção (FOR UPDATE, dono revalidado) — mesma ordem de
     domínio Collection → Allocation da 5046/6122/6124.
     Inexistente/alheia/não Pokédex → P0002 COLLECTION_NOT_FOUND
     (indistinguíveis); arquivada → 55000 COLLECTION_ARCHIVED.
  3. Posição desta Pokédex e do escopo vigente, senão 22023
     POSITION_NOT_IN_SCOPE (fora do escopo o vínculo não contaria).
  4. Exemplar do acervo do chamador, senão P0002 COPY_NOT_FOUND (alheio e
     inexistente indistinguíveis). Em outra coleção → 55000
     COPY_IN_OTHER_COLLECTION (alocação única; nada é movido). Nesta
     coleção já vinculado a OUTRA posição → 55000 COPY_ALREADY_LINKED
     (mover exige retirar o vínculo antes — nunca implícito).
  5. Confirmação explícita: se a carta não corresponde à espécie da
     posição, p_confirm_exception precisa ser TRUE literal, senão 55000
     EXCEPTION_CONFIRMATION_REQUIRED (NULL nunca confirma — fail-closed,
     como a 6122).
  6. Livre → public.allocate_physical_cards_to_collection (5046) com um
     único id (a 6119 pode vincular automaticamente à posição da própria
     espécie; o passo 7 move dentro da mesma transação, DELETE+INSERT).
  7. public.set_pokedex_position_assignment (6122) com
     p_confirm_override = (não corresponde) → USER_OVERRIDE com o
     chamador como autor, ou SPECIES_MATCH se a carta corresponde.
  8. Devolve o vínculo e o progresso da coleção (5102).

  Espécie principal da carta no catálogo: nunca alterada.
  Repetir a mesma chamada depois de sucesso: sem nova escrita
  (6122 no-op), allocated_now = false, mesmo vínculo.
  Concorrência: exemplar alocado por outra transação entre a leitura e a
  5046 → a 5046/UNIQUE recusa e tudo é desfeito.

Segurança: SECURITY DEFINER, VOLATILE, search_path '', objetos
qualificados; autorização revalidada aqui e de novo dentro da 5046/6122
(que leem auth.uid() da mesma requisição); EXECUTE só authenticated.
Como validar: 5846 v1.0.
Recuperação: drop function if exists public.link_my_pokedex_copy(uuid, uuid, uuid, boolean);
================================================================
*/

begin;

create or replace function public.link_my_pokedex_copy(
  p_collection_id       uuid,
  p_pokedex_position_id uuid,
  p_physical_card_id    uuid,
  p_confirm_exception   boolean
)
returns table (
  collection_allocation_id uuid,
  pokedex_position_id      uuid,
  assignment_basis         text,
  allocated_now            boolean,
  satisfied_positions      bigint,
  total_positions          bigint
)
language plpgsql
volatile
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_user       uuid := auth.uid();
  v_status     text;
  v_ref        uuid;
  v_dex        uuid;
  v_kind       text;
  v_species    uuid;
  v_inventory  uuid;
  v_alloc      uuid;
  v_alloc_coll uuid;
  v_linked_pos uuid;
  v_match      boolean;
  v_now        boolean := false;
  v_row        record;
  v_sum        record;
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  if p_collection_id is null or p_pokedex_position_id is null or p_physical_card_id is null then
    raise exception 'INVALID_INPUT' using errcode = '22023';
  end if;

  select c.lifecycle_status, cr.id, cpr.pokedex_id, cpr.scope_kind
    into v_status, v_ref, v_dex, v_kind
  from public.collection c
  join public.collection_reference cr
    on cr.collection_id = c.id and cr.reference_kind = 'POKEDEX'
  join public.collection_pokedex_reference cpr
    on cpr.collection_reference_id = cr.id
  where c.id = p_collection_id
    and c.owner_user_id = v_user
    and c.mode = 'REFERENCE_BASED'
    and c.completion_policy = 'REFERENCE_POSITION'
  for update of c;

  if v_ref is null then
    raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';
  end if;

  if v_status <> 'ACTIVE' then
    raise exception 'COLLECTION_ARCHIVED' using errcode = '55000';
  end if;

  select pp.species_id into v_species
  from public.pokedex_position pp
  join public.pokemon_species s on s.id = pp.species_id
  where pp.id = p_pokedex_position_id
    and pp.pokedex_id = v_dex
    and (v_kind = 'FULL_REFERENCE'
         or exists (select 1 from public.collection_pokedex_scope_generation sg
                    where sg.collection_reference_id = v_ref and sg.generation_id = s.generation_id));

  if v_species is null then
    raise exception 'POSITION_NOT_IN_SCOPE' using errcode = '22023';
  end if;

  select i.id into v_inventory
  from public.inventory i
  where i.owner_user_id = v_user;

  select (cc.code = 'POKEMON' and cps.pokemon_species_id is not distinct from v_species and cps.pokemon_species_id is not null)
    into v_match
  from public.physical_card pc
  join public.card_variant cv  on cv.id = pc.card_variant_id
  join public.card c           on c.id = cv.card_id
  join public.card_category cc on cc.id = c.category_id
  left join public.card_primary_species cps on cps.card_id = c.id
  where pc.id = p_physical_card_id
    and pc.inventory_id = v_inventory;

  if v_match is null then
    raise exception 'COPY_NOT_FOUND' using errcode = 'P0002';
  end if;

  select ca.id, ca.collection_id, a.pokedex_position_id
    into v_alloc, v_alloc_coll, v_linked_pos
  from public.collection_allocation ca
  left join public.collection_pokedex_position_assignment a on a.collection_allocation_id = ca.id
  where ca.physical_card_id = p_physical_card_id;

  if v_alloc is not null and v_alloc_coll <> p_collection_id then
    raise exception 'COPY_IN_OTHER_COLLECTION' using errcode = '55000';
  end if;

  if v_linked_pos is not null and v_linked_pos <> p_pokedex_position_id then
    raise exception 'COPY_ALREADY_LINKED' using errcode = '55000';
  end if;

  if not v_match and p_confirm_exception is distinct from true then
    raise exception 'EXCEPTION_CONFIRMATION_REQUIRED' using errcode = '55000';
  end if;

  if v_alloc is null then
    perform public.allocate_physical_cards_to_collection(p_collection_id, array[p_physical_card_id]);
    v_now := true;
  end if;

  select s.collection_allocation_id as alloc_id, s.pokedex_position_id as pos_id, s.assignment_basis as basis
    into v_row
  from public.set_pokedex_position_assignment(p_physical_card_id, p_pokedex_position_id, not v_match) s;

  select cs.satisfied_positions as sat, cs.total_positions as tot
    into v_sum
  from public.collection_completion_summary(p_collection_id) cs;

  collection_allocation_id := v_row.alloc_id;
  pokedex_position_id      := v_row.pos_id;
  assignment_basis         := v_row.basis;
  allocated_now            := v_now;
  satisfied_positions      := v_sum.sat;
  total_positions          := v_sum.tot;
  return next;
end;
$$;

comment on function public.link_my_pokedex_copy(uuid, uuid, uuid, boolean) is
  'Pokédex (Query 5210): vincula UM exemplar do próprio acervo a uma posição — compõe 5046 (alocação, se livre; 6119 vincula SPECIES_MATCH) e 6122 numa única transação. Carta de outra espécie exige p_confirm_exception = true (USER_OVERRIDE). Nunca move exemplar de outra coleção nem de outra posição; espécie principal da carta inalterada.';

revoke all on function public.link_my_pokedex_copy(uuid, uuid, uuid, boolean) from public, anon;
grant execute on function public.link_my_pokedex_copy(uuid, uuid, uuid, boolean) to authenticated;

commit;
