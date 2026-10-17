/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5165 - remove_my_physical_card(): remove um exemplar
              cadastrado por engano em Meu acervo
              (INVENTORY-REMOVE-COPY-01)
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO no LIVE (mimikyu-core) em
              2026-10-17, autorizado por Fabrício — ledger
              20261017034435, prosrc md5 1322db0293d346dd1911240b44881e99;
              5829 v1.1 14/14 PASS
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-17

Contexto:
Pedido de Fabrício (2026-10-17): um ícone de lixeira por exemplar no
detalhe da carta, para corrigir cadastros feitos por engano. Hoje não
existe caminho: physical_card só tem policy de SELECT para o dono e
authenticated não tem DELETE.

Natureza da operação — CORREÇÃO DE CADASTRO, não Ownership Exit:
O registro nunca deveria ter existido (exemplar físico inexistente).
Ownership Exit (C-72: venda, troca, descarte de uma carta real) é outra
coisa e continua não implementado. Por isso a remoção só vale para um
exemplar SEM vínculos:
  - sem Collection Allocation (e portanto sem Slot Assignment nem
    Pokédex Assignment, que dependem dela);
  - Storage não bloqueia (é só localização corrente, C-55+).
Exemplar alocado → recusa explícita (o usuário retira da coleção antes).

Contrato:
  remove_my_physical_card(p_physical_card_id uuid) RETURNS boolean
    true  → o exemplar era do usuário e foi removido;
    false → não existe ou não é do usuário (mesma resposta: não enumera)
            — também torna a chamada idempotente (repetir após sucesso
            devolve false, sem erro).
Erros:
  28000  sem auth.uid()
  22023  INVALID_PHYSICAL_CARD (nulo)
  55000  PHYSICAL_CARD_ALLOCATED: o exemplar está em uma coleção.

Concorrência: a linha é travada (FOR UPDATE) antes da checagem de
alocação; uma alocação concorrente precisa de KEY SHARE na mesma linha e
espera. Se ainda assim existir alocação, a FK RESTRICT de
collection_allocation impede o DELETE (defesa em profundidade, 23503 →
mesma mensagem).

Segurança: SECURITY DEFINER, VOLATILE, search_path '', dono resolvido no
servidor (inventory.owner_user_id = auth.uid()), EXECUTE só para
authenticated. Nenhuma policy ou grant de tabela é alterado.

Como validar: Query 5829.
================================================================
*/

begin;

create or replace function public.remove_my_physical_card(p_physical_card_id uuid)
returns boolean
language plpgsql
security definer
volatile
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_id   uuid;
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  if p_physical_card_id is null then
    raise exception 'INVALID_PHYSICAL_CARD' using errcode = '22023';
  end if;

  select pc.id into v_id
  from public.physical_card pc
  join public.inventory i on i.id = pc.inventory_id
  where pc.id = p_physical_card_id
    and i.owner_user_id = v_user
  for update of pc;

  if v_id is null then
    return false;
  end if;

  if exists (select 1 from public.collection_allocation ca where ca.physical_card_id = v_id) then
    raise exception 'PHYSICAL_CARD_ALLOCATED: o exemplar está em uma coleção' using errcode = '55000';
  end if;

  begin
    delete from public.physical_card where id = v_id;
  exception when foreign_key_violation then
    raise exception 'PHYSICAL_CARD_ALLOCATED: o exemplar está em uma coleção' using errcode = '55000';
  end;

  return true;
end;
$$;

comment on function public.remove_my_physical_card(uuid) is
  'Meu acervo (Query 5165): remove um exemplar do próprio usuário cadastrado por engano. Só sem Collection Allocation (55000). Alheio/inexistente → false (não enumera; idempotente). Exige auth.uid().';

revoke all on function public.remove_my_physical_card(uuid) from public;
revoke all on function public.remove_my_physical_card(uuid) from anon;
grant execute on function public.remove_my_physical_card(uuid) to authenticated;

commit;
