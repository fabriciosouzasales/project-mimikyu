/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5289 - P3-B S5 · Histórico do Fichário — instrumentação E07 (Carta saiu do fichário ao deixar o acervo)
              remove_my_physical_card(uuid)
Versão......: 1.0 (2026-10-28, P3-B S5 — instrumentação E06a, E06b, E07)
Status......: EXECUTADA / CANÔNICA. Aplicada no LIVE mimikyu-core (P3-B S5, autorização
              operacional do proprietário; harness dispensado sob H-A; ledger 20261028005621 `5289_instrument_remove_my_physical_card`).
              Do `begin;` ao `commit;` idêntica ao arquivo de database/proposals/2026-10-25-
              p3b-binder-activity-history/ (só este bloco Status difere); enviada via
              apply_migration sem as linhas `begin;`/`commit;` externas — texto do ledger = corpo (md5).
              LIVE_S5_90 bloco A 7/7; E07 NÃO exercitado dinamicamente (sem exclusão real elegível).
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-28
Base........: 5165 (md5(prosrc) LIVE 1322db0293d346dd1911240b44881e99, conferido em 2026-10-28;
              idêntico ao corpo canônico de database/schema/5165_create_remove_my_physical_card_function.sql).
Autoridade..: README da proposta §4.1, §5.3, §7.2, §20 (W3), §32 (S5).

Diff mínimo: o corpo é o da base LIVE, byte a byte, mais as linhas marcadas com
"-- P3B-S5". Removidas essas linhas e trocado o delimitador $fn$ → $$, o corpo volta a
ter o md5 acima (static_check_p3b_s5.py). Assinatura, retorno, SET, mensagens, códigos de
erro, ordem de travas e permissões inalterados (REVOKE/GRANT originais reaplicados).

Evento CARD_LEFT_BY_INVENTORY_EXIT, origem ACERVO (Meu acervo: remover exemplar):
  · a função só remove exemplar sem alocação; um exemplar assim ainda pode estar num bolso
    (a alocação sai e o bolso fica — 5248; 8 bolsos nessa situação no LIVE em 2026-10-28);
  · o bolso cai por FK em cascata: posição lida e travada (for update of a) ANTES da
    exclusão — mesma ordem de travas da cascata (exemplar → posição);
  · 1 item CARD/LEFT, origem = bolso; begin/add/end condicionados por WHERE (sem bolso →
    nenhuma chamada, nenhum evento; I-2 satisfeito: end imediatamente antes do RETURN);
  · bolso fixado não impede a saída (trava aceita a cascata do acervo, 5248) e é registrado.
================================================================
*/

begin;

do $pre$
begin
  if to_regprocedure('public.binder_activity_add_card_item(text, uuid, uuid, uuid)') is null
     or to_regprocedure('public.binder_activity_begin(uuid, text, text, uuid, jsonb)') is null
     or to_regprocedure('public.binder_activity_end()') is null then
    raise exception 'PRECHECK 5289: dependências ausentes (5268/5271)';
  end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('public.remove_my_physical_card(uuid)')) is distinct from '1322db0293d346dd1911240b44881e99' then
    raise exception 'PRECHECK 5289: função no LIVE diverge da base 5165 (md5)';
  end if;
end;
$pre$;

CREATE OR REPLACE FUNCTION public.remove_my_physical_card(p_physical_card_id uuid)
returns boolean
language plpgsql
security definer
volatile
set search_path = ''
as $fn$
declare
  v_user uuid := auth.uid();
  v_id   uuid;
  v_act_layout uuid;  -- P3B-S5
  v_act_slot   uuid;  -- P3B-S5
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

  -- E07: o bolso cai por FK em cascata junto com o exemplar (5248). A posição é lida e  -- P3B-S5
  -- travada ANTES da exclusão (I-10); o exemplar ainda existe para a cópia da carta.  -- P3B-S5
  -- Exemplar fora do fichário → nenhuma chamada (WHERE falso), nenhum evento (I-8).  -- P3B-S5
  -- Bolso fixado não impede: a trava aceita a cascata de saída do acervo (5248) — o item registra.  -- P3B-S5
  select a.slot_id, p.layout_id into v_act_slot, v_act_layout  -- P3B-S5
  from public.collection_layout_slot_assignment a  -- P3B-S5
  join public.collection_layout_slot s on s.id = a.slot_id  -- P3B-S5
  join public.collection_layout_page p on p.id = s.page_id  -- P3B-S5
  where a.physical_card_id = v_id  -- P3B-S5
  for update of a;  -- P3B-S5
  perform public.binder_activity_begin(v_act_layout, 'CARD_LEFT_BY_INVENTORY_EXIT', 'ACERVO') where v_act_layout is not null;  -- P3B-S5
  perform public.binder_activity_add_card_item('LEFT', v_id, v_act_slot, null) where v_act_layout is not null;  -- P3B-S5
  -- P3B-S5
  begin
    delete from public.physical_card where id = v_id;
  exception when foreign_key_violation then
    raise exception 'PHYSICAL_CARD_ALLOCATED: o exemplar está em uma coleção' using errcode = '55000';
  end;

  perform public.binder_activity_end() where v_act_layout is not null;  -- P3B-S5
  return true;
end;
$fn$;

revoke all on function public.remove_my_physical_card(uuid) from public;
revoke all on function public.remove_my_physical_card(uuid) from anon;
grant execute on function public.remove_my_physical_card(uuid) to authenticated;

commit;

/*
Resultado esperado: remove_my_physical_card(uuid) recriada com o mesmo contrato; nenhum evento gravado pela
instalação (o histórico só registra quando a função é chamada e tira carta de um bolso).
Como validar (só leitura): LIVE_S5_90_postcheck_readonly.sql, bloco A.
*/
