/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5256 - FASE B (contração): proteção D3 em qualquer caminho +
              remoção da leitura antiga de "Cartas disponíveis"
              gatilho trg_physical_card_binder_position_guard (physical_card)
              DROP get_my_collection_binder_unplaced(uuid, integer, integer)
Versão......: 1.0 (2026-10-24, BINDER-PHYSICAL-LOCATION-IMPLEMENTATION-READINESS-01)
Status......: PROPOSTA — NÃO EXECUTADA. Só DEPOIS do deploy do frontend novo
              e do LIVE_50 PASS (README §6). Nunca junto com a fase A.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-24

Por que separada: durante a fase A o frontend antigo ainda pode chamar a
5024/5222 originais e a leitura 5230 de 3 argumentos. Ligar a proteção
antes do deploy faria o frontend antigo receber erro ao mover carta
posicionada (janela de incompatibilidade); removê-la depois do deploy não
afeta ninguém, porque o frontend novo só usa as sobrecargas da 5249 e a
leitura de 4 argumentos da 5252.

Gatilho (sem configuração de sessão, sem bypass): exemplar com posição no
fichário não muda de local. Os escritores confirmados (5249) removem a
posição ANTES do UPDATE, então passam; qualquer outro caminho (5024 e 5222
originais, SQL futuro) recebe:
  - BINDER_POSITION_LOCKED (55000), se o bolso está travado;
  - BINDER_POSITION_CONFIRMATION_REQUIRED (55000), caso contrário.
Precheck: nenhuma posição atual fora do local físico do seu fichário (se o
frontend antigo moveu carta posicionada durante a janela da fase A, esta
query ABORTA e lista a quantidade — resolver com Fabrício antes; ver
README §5, LIVE_50 q05).
Dependências: 5247, 5248, 5249, 5252 + frontend novo publicado.
================================================================
*/

begin;

set local lock_timeout = '5s';

do $pre$
declare
  v_out integer;
begin
  if to_regprocedure('public.set_physical_cards_storage(uuid, uuid[], boolean)') is null
     or to_regprocedure('public.get_my_collection_binder_unplaced(uuid, integer, integer, text, uuid)') is null then
    raise exception 'PRECHECK 5256: fase A (5249/5252) não aplicada';
  end if;
  if exists (select 1 from pg_trigger where tgname = 'trg_physical_card_binder_position_guard') then
    raise exception 'PRECHECK 5256: gatilho já existe';
  end if;
  select count(*) into v_out
  from public.collection_layout_slot_assignment a
  join public.physical_card pc         on pc.id = a.physical_card_id
  join public.collection_layout_slot s on s.id = a.slot_id
  join public.collection_layout_page p on p.id = s.page_id
  join public.collection_layout l      on l.id = p.layout_id
  where pc.storage_container_id is distinct from l.storage_container_id;
  if v_out > 0 then
    raise exception 'PRECHECK 5256: % posição(ões) com exemplar fora do local do fichário — resolver antes (R0, README §5)', v_out;
  end if;
end;
$pre$;

create function public.binder_position_guard_on_storage_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_locked boolean;
begin
  if new.storage_container_id is not distinct from old.storage_container_id then
    return new;
  end if;
  select s.locked into v_locked
  from public.collection_layout_slot_assignment a
  join public.collection_layout_slot s on s.id = a.slot_id
  where a.physical_card_id = old.id;
  if not found then
    return new;
  end if;
  if v_locked then
    raise exception 'BINDER_POSITION_LOCKED'
      using errcode = '55000',
            hint = 'o exemplar está num bolso travado do fichário — destrave antes de mudar o local';
  end if;
  raise exception 'BINDER_POSITION_CONFIRMATION_REQUIRED'
    using errcode = '55000',
          hint = 'o exemplar está posicionado no fichário — use a mudança de local com confirmação';
end;
$$;

revoke all on function public.binder_position_guard_on_storage_change() from public, anon, authenticated;

create trigger trg_physical_card_binder_position_guard
  before update of storage_container_id on public.physical_card
  for each row execute function public.binder_position_guard_on_storage_change();

-- Contração: a leitura de 3 argumentos (5230) não tem mais chamador.
drop function public.get_my_collection_binder_unplaced(uuid, integer, integer);

notify pgrst, 'reload schema';

commit;

/*
Como validar (só leitura):
select tgname, tgenabled from pg_trigger where tgname = 'trg_physical_card_binder_position_guard';
select to_regprocedure('public.get_my_collection_binder_unplaced(uuid, integer, integer)') is null;
*/
