/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5287 - P3-B S5 · Histórico do Fichário — instrumentação E06a (Cartas saíram por mudança de local)
              set_physical_cards_storage(uuid, uuid[], boolean) — a sobrecarga de 2 argumentos (5024) não muda
Versão......: 1.0 (2026-10-28, P3-B S5 — instrumentação E06a, E06b, E07)
Status......: PROPOSTA — NÃO EXECUTADA. Exige autorização própria para o LIVE.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-28
Base........: 5249 (md5(prosrc) LIVE c68a460ce75a7384f521aee751e50335, conferido em 2026-10-28;
              idêntico ao corpo canônico de database/schema/5249_binder_storage_change_writers.sql).
Autoridade..: README da proposta §4.1, §5.3, §7.2, §20 (W3), §32 (S5).

Diff mínimo: o corpo é o da base LIVE, byte a byte, mais as linhas marcadas com
"-- P3B-S5". Removidas essas linhas e trocado o delimitador $fn$ → $$, o corpo volta a
ter o md5 acima (static_check_p3b_s5.py). Assinatura, retorno, SET, mensagens, códigos de
erro, ordem de travas e permissões inalterados (REVOKE/GRANT originais reaplicados).

Evento CARDS_LEFT_BY_STORAGE, origem ACERVO (Meu acervo: mover exemplares / local do exemplar):
  · só quando exemplares posicionados realmente saem dos bolsos (confirmação dada, v_pos > 0);
  · um evento por fichário afetado (o evento pertence a um fichário — 5268 recusa operação
    aninhada em outro fichário; begin/end por fichário, em sequência, na mesma transação);
  · 1 item CARD/LEFT por exemplar, origem = bolso, ordem página/linha/coluna, lido ANTES do
    DELETE com o mesmo predicado dele (I-10), sobre posições já travadas pela função;
  · resumo: destino copiado no momento (storage_container_id, storage_container_name; nulos
    quando o exemplar fica sem local);
  · nada sai do fichário (sem posição, recusa por bolso fixado, falta de confirmação) →
    nenhum evento (I-8); erro depois do begin desfaz evento e mudança juntos (I-3).
================================================================
*/

begin;

do $pre$
begin
  if to_regprocedure('public.binder_activity_add_card_item(text, uuid, uuid, uuid)') is null
     or to_regprocedure('public.binder_activity_begin(uuid, text, text, uuid, jsonb)') is null
     or to_regprocedure('public.binder_activity_end()') is null then
    raise exception 'PRECHECK 5287: dependências ausentes (5268/5271)';
  end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('public.set_physical_cards_storage(uuid, uuid[], boolean)')) is distinct from 'c68a460ce75a7384f521aee751e50335' then
    raise exception 'PRECHECK 5287: função no LIVE diverge da base 5249 (md5)';
  end if;
end;
$pre$;

CREATE OR REPLACE FUNCTION public.set_physical_cards_storage(
    p_storage_container_id uuid,
    p_physical_card_ids    uuid[],
    p_unplace_from_binder  boolean      -- sem DEFAULT (não colide com a 5024)
)
returns table (
    id                    uuid,
    storage_container_id  uuid,
    updated_at            timestamptz
)
language plpgsql
security definer
set search_path = ''
set lock_timeout = '5s'
as $fn$
declare
    v_inventory_id           uuid;
    v_container_inventory_id uuid;
    v_distinct_ids           uuid[];
    v_raw_count              int;
    v_owned_count            int;
    v_pos                    int := 0;
    v_pos_lock               int := 0;
    v_act_layout             uuid;  -- P3B-S5
    v_act                    record;  -- P3B-S5
    v_act_summary            jsonb;  -- P3B-S5
begin
    if auth.uid() is null then
        raise exception 'authentication required';
    end if;

    if p_physical_card_ids is null then
        raise exception 'p_physical_card_ids não pode ser vazio';
    end if;
    if p_unplace_from_binder is null then
        raise exception 'INVALID_ARGUMENT' using errcode = '22023';
    end if;

    v_raw_count := cardinality(p_physical_card_ids);
    if v_raw_count = 0 then
        raise exception 'p_physical_card_ids não pode ser vazio';
    end if;
    if array_ndims(p_physical_card_ids) <> 1 then
        raise exception
            'p_physical_card_ids deve ser um array unidimensional (recebido array com % dimensões)',
            array_ndims(p_physical_card_ids);
    end if;
    if v_raw_count > 500 then
        raise exception 'lote excede o limite de 500 itens por chamada';
    end if;

    select array_agg(distinct x) into v_distinct_ids
    from unnest(p_physical_card_ids) as x;

    select inv.id into v_inventory_id
    from public.inventory inv
    where inv.owner_user_id = auth.uid();
    if v_inventory_id is null then
        raise exception 'inventory not found for current user';
    end if;

    if p_storage_container_id is not null then
        select sc.inventory_id into v_container_inventory_id
        from public.storage_container sc
        where sc.id = p_storage_container_id;
        if v_container_inventory_id is null then
            raise exception 'storage container not found';
        end if;
        if v_container_inventory_id is distinct from v_inventory_id then
            raise exception 'storage container does not belong to caller inventory';
        end if;
    end if;

    select count(*) into v_owned_count
    from public.physical_card pc
    where pc.id = any(v_distinct_ids)
      and pc.inventory_id = v_inventory_id;
    if v_owned_count <> cardinality(v_distinct_ids) then
        raise exception 'um ou mais physical_card_ids não pertencem ao inventory do chamador';
    end if;

    -- 5249: trava os exemplares (ordem de id) antes de contar posições e decidir.
    perform 1
    from public.physical_card pc
    where pc.id = any(v_distinct_ids)
      and pc.inventory_id = v_inventory_id
    order by pc.id
    for update;

    -- 5249 (D3): posições de exemplares que realmente mudam de local.
    perform 1
    from public.collection_layout_slot_assignment a
    join public.physical_card pc on pc.id = a.physical_card_id
    where pc.id = any(v_distinct_ids)
      and pc.storage_container_id is distinct from p_storage_container_id
    order by a.id
    for update of a;
    select count(*) filter (where not s.locked)::int, count(*) filter (where s.locked)::int
      into v_pos, v_pos_lock
    from public.collection_layout_slot_assignment a
    join public.collection_layout_slot s on s.id = a.slot_id
    join public.physical_card pc on pc.id = a.physical_card_id
    where pc.id = any(v_distinct_ids)
      and pc.storage_container_id is distinct from p_storage_container_id;
    if v_pos_lock > 0 then
        raise exception 'BINDER_POSITION_LOCKED' using errcode = '55000',
          hint = v_pos_lock::text || ' exemplar(es) em bolso travado do fichário — destrave antes de mudar o local';
    end if;
    if v_pos > 0 and not p_unplace_from_binder then
        raise exception 'BINDER_POSITION_CONFIRMATION_REQUIRED' using errcode = '55000',
          hint = v_pos::text || ' exemplar(es) sairão dos bolsos do fichário — confirme';
    end if;
    if v_pos > 0 then
        -- E06a: um evento por fichário afetado (o evento pertence a um fichário, 5268);  -- P3B-S5
        -- itens de origem ANTES do DELETE (I-10), com o mesmo predicado do DELETE e sobre  -- P3B-S5
        -- as posições já travadas acima (for update of a). Destino copiado no resumo (R3).  -- P3B-S5
        v_act_summary := jsonb_build_object('storage_container_id', p_storage_container_id,  -- P3B-S5
            'storage_container_name', (select left(sc.name, 200) from public.storage_container sc where sc.id = p_storage_container_id));  -- P3B-S5
        for v_act_layout in  -- P3B-S5
            select distinct p.layout_id  -- P3B-S5
            from public.collection_layout_slot_assignment a  -- P3B-S5
            join public.collection_layout_slot s on s.id = a.slot_id  -- P3B-S5
            join public.collection_layout_page p on p.id = s.page_id  -- P3B-S5
            join public.physical_card pc on pc.id = a.physical_card_id  -- P3B-S5
            where pc.id = any(v_distinct_ids)  -- P3B-S5
              and pc.storage_container_id is distinct from p_storage_container_id  -- P3B-S5
            order by p.layout_id  -- P3B-S5
        loop  -- P3B-S5
            perform public.binder_activity_begin(v_act_layout, 'CARDS_LEFT_BY_STORAGE', 'ACERVO', null, v_act_summary);  -- P3B-S5
            for v_act in  -- P3B-S5
                select a.physical_card_id, a.slot_id  -- P3B-S5
                from public.collection_layout_slot_assignment a  -- P3B-S5
                join public.collection_layout_slot s on s.id = a.slot_id  -- P3B-S5
                join public.collection_layout_page p on p.id = s.page_id  -- P3B-S5
                join public.physical_card pc on pc.id = a.physical_card_id  -- P3B-S5
                where p.layout_id = v_act_layout  -- P3B-S5
                  and pc.id = any(v_distinct_ids)  -- P3B-S5
                  and pc.storage_container_id is distinct from p_storage_container_id  -- P3B-S5
                order by p.page_number, s.row_index, s.column_index  -- P3B-S5
            loop  -- P3B-S5
                perform public.binder_activity_add_card_item('LEFT', v_act.physical_card_id, v_act.slot_id, null);  -- P3B-S5
            end loop;  -- P3B-S5
            perform public.binder_activity_end();  -- P3B-S5
        end loop;  -- P3B-S5
        delete from public.collection_layout_slot_assignment a
        using public.physical_card pc
        where pc.id = a.physical_card_id
          and pc.id = any(v_distinct_ids)
          and pc.storage_container_id is distinct from p_storage_container_id;
    end if;

    return query
    update public.physical_card
    set storage_container_id = p_storage_container_id
    where physical_card.id = any(v_distinct_ids)
      and physical_card.inventory_id = v_inventory_id
    returning physical_card.id, physical_card.storage_container_id, physical_card.updated_at;
end;
$fn$;

revoke all on function public.set_physical_cards_storage(uuid, uuid[], boolean) from public, anon;
grant execute on function public.set_physical_cards_storage(uuid, uuid[], boolean) to authenticated;

commit;

/*
Resultado esperado: set_physical_cards_storage(uuid, uuid[], boolean) recriada com o mesmo contrato; nenhum evento gravado pela
instalação (o histórico só registra quando a função é chamada e tira carta de um bolso).
Como validar (só leitura): LIVE_S5_90_postcheck_readonly.sql, bloco A.
*/
