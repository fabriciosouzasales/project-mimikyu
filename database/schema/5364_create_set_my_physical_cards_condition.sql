/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5364 - set_my_physical_cards_condition (V1-16 · S4)
Versão......: 1.1 (2026-11-13, INDEPENDENT AUDIT CORRECTIONS-01: trava antes de contar)
Status......: EXECUTADA / CANÔNICA. Aplicada no LIVE mimikyu-core em 2026-11-13
              (V1-16, `5364 CONTROLLED LIVE EXECUTION-01`), arquivo integral numa
              chamada única de execute_sql (MCP). Texto idêntico a database/proposals/
              2026-11-13-v1-16-card-condition/ no commit b51dcc4, exceto este bloco
              Status (promovido em `PR-01 | CANONICAL RECONCILIATION IMPLEMENTATION-01`).
              md5(prosrc) no LIVE = corpos deste arquivo (G1, leitura): set_my_physical_cards_condition b569ecdb.
              SEM registro no ledger supabase_migrations; reconstrução limpa NÃO comprovada.
Autor.......: Fabrício Sales / Claude
Data........: 2026-11-13
Contrato....: concept-decisions C-227–C-233 (C-108 substituída por C-228);
              05d v3.01, seção "Condição física por exemplar (V1-16)".
Objetivo....: O usuário altera a condição de exemplares SEUS, um ou vários
              de uma vez (C-232), no detalhe do Meu acervo.

Contrato
  set_my_physical_cards_condition(p_physical_card_ids uuid[], p_condition_code text)
    returns table (requested_count int, changed_count int)
  - SECURITY DEFINER, owner postgres, search_path vazio, objetos
    qualificados, lock_timeout 5s (como 5287);
  - autenticação obrigatória (28000);
  - código obrigatório e existente em card_condition (validação única de
    5362; sensível a caixa — 'nm' é recusado);
  - lote: não nulo, não vazio, unidimensional, até 500 entradas brutas,
    deduplicado;
  - TODOS os ids no inventário do chamador ou NENHUM (id nulo, alheio ou
    inexistente reprova o lote inteiro, sem efeito parcial);
  - trava (FOR UPDATE, ordem de id) ANTES de conferir titularidade e
    quantidade: a contagem é sobre o conjunto efetivamente travado, então
    remoção concorrente reprova o lote em vez de virar sucesso parcial
    (correção MINOR-1 de `INDEPENDENT SQL AUDIT-01`);
  - grava SÓ onde a condição muda —
    idempotente: repetir devolve changed_count = 0 e não toca updated_at;
  - altera apenas condition_code; sem histórico (C-113), sem evento de
    fichário, sem efeito em completude, reservas, Favoritos, Lista de
    desejos, local ou preço (C-233);
  - EXECUTE: authenticated; revogado de PUBLIC e anon.
Pré-condições: 5361 e 5362 aplicadas; função ainda inexistente
  (existente com o mesmo corpo → 'JÁ APLICADA'; outro corpo → divergente).
Como validar: harness 5887, grupo D.
Recuperação: drop function public.set_my_physical_cards_condition(uuid[], text);
  (condições já gravadas permanecem — a coluna é de 5361).
================================================================
*/

begin;

do $pre$
declare v_oid oid := to_regprocedure('public.set_my_physical_cards_condition(uuid[], text)');
begin
  if to_regprocedure('public.physical_card_unknown_condition_codes(text[])') is null then
    raise exception 'PRECHECK 5364: 5362 não aplicada';
  end if;
  if v_oid is not null then
    if (select md5(prosrc) from pg_proc where oid = v_oid) = 'b569ecdbe202428a6bdc9461c6d62e37' then
      raise exception 'PRECHECK 5364: JÁ APLICADA — não reaplicar';
    end if;
    raise exception 'PRECHECK 5364: set_my_physical_cards_condition existe com outro corpo — ESTADO DIVERGENTE';
  end if;
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname = 'public' and p.proname = 'set_my_physical_cards_condition') then
    raise exception 'PRECHECK 5364: há sobrecarga inesperada de set_my_physical_cards_condition';
  end if;
end;
$pre$;

create function public.set_my_physical_cards_condition(
    p_physical_card_ids uuid[],
    p_condition_code    text
)
returns table (
    requested_count integer,
    changed_count   integer
)
language plpgsql
security definer
volatile
set search_path = ''
set lock_timeout = '5s'
as $$
declare
    v_inventory_id  uuid;
    v_distinct_ids  uuid[];
    v_raw_count     int;
    v_owned_count   int;
    v_changed       int;
begin
    if auth.uid() is null then
        raise exception 'authentication required' using errcode = '28000';
    end if;

    -- Código: obrigatório e da escala canônica (C-229) — validação única.
    if p_condition_code is null or btrim(p_condition_code) = '' then
        raise exception 'condition_code é obrigatório' using errcode = '22023';
    end if;
    if public.physical_card_unknown_condition_codes(array[p_condition_code]) is not null then
        raise exception 'CONDITION_NOT_FOUND: condition_code inexistente na escala canônica: %', p_condition_code
            using errcode = '22023';
    end if;

    -- Lote: mesmo contrato de set_physical_cards_storage (5024/5287).
    if p_physical_card_ids is null then
        raise exception 'p_physical_card_ids não pode ser vazio' using errcode = '22023';
    end if;
    v_raw_count := cardinality(p_physical_card_ids);
    if v_raw_count = 0 then
        raise exception 'p_physical_card_ids não pode ser vazio' using errcode = '22023';
    end if;
    if array_ndims(p_physical_card_ids) <> 1 then
        raise exception
            'p_physical_card_ids deve ser um array unidimensional (recebido array com % dimensões)',
            array_ndims(p_physical_card_ids)
            using errcode = '22023';
    end if;
    if v_raw_count > 500 then
        raise exception 'lote excede o limite de 500 itens por chamada' using errcode = '22023';
    end if;

    select array_agg(distinct x) into v_distinct_ids
    from unnest(p_physical_card_ids) as x;

    select inv.id into v_inventory_id
    from public.inventory inv
    where inv.owner_user_id = auth.uid();
    if v_inventory_id is null then
        raise exception 'inventory not found for current user' using errcode = '22023';
    end if;

    -- Trava PRIMEIRO (ordem de id, a mesma de 5249/5287) e conta SÓ as linhas
    -- efetivamente travadas: um exemplar removido por outra transação entre o
    -- início desta chamada e a trava não é travado (FOR UPDATE espera o commit
    -- alheio e pula a linha que deixou de existir) e reprova o lote. Daqui até
    -- o fim da transação, o conjunto travado não pode ser removido nem alterado
    -- por terceiros. Todos do chamador ou nenhum (id nulo, alheio ou
    -- inexistente reprova o lote inteiro).
    select count(*) into v_owned_count
    from (
        select 1
        from public.physical_card pc
        where pc.id = any(v_distinct_ids)
          and pc.inventory_id = v_inventory_id
        order by pc.id
        for update
    ) as locked;
    if v_owned_count <> cardinality(v_distinct_ids) then
        raise exception 'um ou mais physical_card_ids não pertencem ao inventory do chamador'
            using errcode = '22023';
    end if;

    -- Só as linhas que de fato mudam: repetir não toca nada (updated_at
    -- preservado). Só condition_code — identidade, variante, idioma,
    -- inventário, local, alocação e bolso intocados (C-114/C-232).
    update public.physical_card pc
       set condition_code = p_condition_code
     where pc.id = any(v_distinct_ids)
       and pc.inventory_id = v_inventory_id
       and pc.condition_code is distinct from p_condition_code;
    get diagnostics v_changed = row_count;

    requested_count := cardinality(v_distinct_ids);
    changed_count   := v_changed;
    return next;
end;
$$;

comment on function public.set_my_physical_cards_condition(uuid[], text) is
  'V1-16 (5364, C-232): altera a condição física de exemplares do PRÓPRIO usuário — um ou vários (até 500, deduplicados), todos ou nenhum, código obrigatório da escala canônica (validação única physical_card_unknown_condition_codes). Idempotente: grava só onde muda (changed_count); só condition_code; sem histórico (C-113). EXECUTE: authenticated; PUBLIC/anon NÃO.';

revoke all on function public.set_my_physical_cards_condition(uuid[], text) from public;
revoke all on function public.set_my_physical_cards_condition(uuid[], text) from anon;
grant execute on function public.set_my_physical_cards_condition(uuid[], text) to authenticated;

do $post$
declare v_oid oid := to_regprocedure('public.set_my_physical_cards_condition(uuid[], text)');
begin
  if (select md5(prosrc) from pg_proc where oid = v_oid) <> 'b569ecdbe202428a6bdc9461c6d62e37' then
    raise exception 'POSTCHECK 5364: corpo gravado difere do proposto';
  end if;
  if not (select prosecdef from pg_proc where oid = v_oid)
     or not has_function_privilege('authenticated', v_oid, 'EXECUTE')
     or has_function_privilege('anon', v_oid, 'EXECUTE') then
    raise exception 'POSTCHECK 5364: atributos ou ACL divergentes';
  end if;
end;
$post$;

notify pgrst, 'reload schema';

commit;
