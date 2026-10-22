/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5222 - organize_my_collection_storage(): organização física
              atômica dos exemplares de uma coleção no local padrão —
              WHERE-05A
Versão......: 1.1 (2026-10-22, WHERE-05A CONTRACT CONCURRENCY CORRECTION-01:
              trava TODO o universo do plan_token — todos os exemplares
              alocados — com FOR UPDATE NOWAIT, não só os elegíveis)
              1.2 (2026-10-22, WHERE-05A CONTRACT CORRECTION-02: D6 — teto
              de 10.000 também sobre o TOTAL alocado, antes de qualquer trava
              de exemplar; travas de exemplar adquiridas uma a uma, em laço
              sobre a lista ordenada por id — ordem determinística por
              construção, não dependente do plano do otimizador)
Status......: CONFIRMADO EXECUTADO no LIVE em 2026-10-22 UTC (v1.2;
              autorização de Fabrício, WHERE-05A LIVE CONTRACT EXECUTION) —
              ledger 20261022194352; corpo de organize_my_collection_storage
              idêntico ao arquivo; harness 5849 v1.4 50/50 PASS (GATE
              PASS_FUNCTIONAL_LIMIT_NOT_EXERCISED, 99.1 resíduo zero);
              desempenho NÃO medido; teto pela contagem real (L.1/L.2) e
              concorrência entre sessões (K1–K4) NÃO exercitados. CANÔNICA em
              database/schema/. Do "begin;" em diante, texto idêntico ao
              aplicado via apply_migration (só este cabeçalho mudou;
              WHERE-05A DATABASE CONTRACT CLOSEOUT).
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-22

Contrato:
  organize_my_collection_storage(
    p_collection_id        uuid,     -- coleção do usuário da sessão
    p_storage_container_id uuid,     -- destino; DEVE ser o local padrão vigente
    p_mode                 text,     -- 'UNLOCATED' | 'ALL'
    p_expected_count       integer,  -- quantidade que a prévia mostrou para p_mode
    p_plan_token           text      -- plan_token da 5221
  ) returns table (
    collection_id        uuid,
    storage_container_id uuid,
    mode                 text,
    moved_count          integer,    -- exemplares efetivamente movidos
    total_count          integer,    -- exemplares alocados à coleção (após)
    at_target_count      integer     -- desses, no destino (após)
  )

Semântica das modalidades (D1/D2 aprovadas):
  UNLOCATED — move só exemplares da coleção SEM localização; preserva os que
              estão em outros locais; não toca os que já estão no destino.
  ALL       — move todos os exemplares da coleção que AINDA NÃO estão no
              destino (sem localização + outros locais).
  Em ambas, só exemplares ALOCADOS à coleção (collection_allocation) — nunca
  catálogo, checklist, posições sem exemplar ou outras coleções.

O que muda: SOMENTE physical_card.storage_container_id (e updated_at, pelo
trigger 5011) dos exemplares elegíveis. NÃO muda: vínculo com coleção
(collection_allocation), variante, idioma, condição, quantidade, posições do
Master Set / Pokédex / fichário, demais coleções, demais exemplares. Não cria
nem remove exemplar. Sem histórico de movimentação (D5 — fora do escopo; a
5024 também não registra).

Ordem de execução e travas (ver README §Locks):
  0. validações de forma (sessão, modalidade, argumentos, teto declarado);
  1. coleção do chamador FOR UPDATE — a MESMA trava, na mesma ordem, de 5036
     (UPDATE), 5037/5038, 5039, 5046, 5047, 5150/5153 (via 5148) e 5210:
     vínculos/desvínculos e troca do local padrão da coleção ficam em fila;
     ativa? senão COLLECTION_ARCHIVED;
  2. destino FOR KEY SHARE no acervo do chamador — bloqueia exclusão (5218,
     FOR UPDATE) enquanto a operação corre, sem bloquear outras leituras;
  3. destino = local padrão vigente? senão DEFAULT_CHANGED (D2);
  4. (v1.2, D6) conta o TOTAL alocado à coleção e os elegíveis da
     modalidade; qualquer um > 10.000 → COLLECTION_TOO_LARGE, ANTES de
     qualquer trava de exemplar (rollback integral, nada travado além de
     coleção e destino, nada gravado);
  5. (v1.1/v1.2) trava TODOS os exemplares alocados à coleção — exatamente o
     universo que o plan_token cobre, não só os elegíveis — um a um, FOR
     UPDATE NOWAIT, num laço FOREACH sobre o array ordenado por id (a ordem
     de aquisição É a ordem do array). Com a trava da coleção (passo 1) congelando a
     composição e a trava de linha congelando o local de cada exemplar,
     nenhuma entrada do token pode mudar até o fim da transação. NOWAIT: a
     5222 nunca ESPERA por linha de exemplar; se alguma estiver travada ou
     alterada por transação em curso (5024, 5165…), falha na hora com
     LOCK_BUSY (55P03) e nada é gravado — sem espera, não há ciclo possível
     com a 5024 (que trava linhas sem ordem e sem a trava da coleção);
  6. seleciona os elegíveis da modalidade DENTRO do conjunto travado e
     recalcula a prévia (helper 5221, VOLATILE, snapshot novo após as
     travas): plan_token, quantidade da modalidade, quantidade de elegíveis
     e quantidade travada (= total) precisam bater; senão PLAN_CHANGED —
     nada gravado;
  7. um único UPDATE set-based só sobre os elegíveis; ROW_COUNT ≠ esperado
     → PLAN_CHANGED (desfaz tudo).

Atomicidade: tudo ou nada — uma transação; qualquer erro (inclusive
lock_timeout, deadlock detectado, statement_timeout do papel) desfaz a
operação inteira. Não há estado parcial possível.

Idempotência e confirmação duplicada: depois de um sucesso, o estado da
coleção mudou, logo o plan_token antigo não confere mais: a repetição
recebe PLAN_CHANGED e NÃO move nada; a interface busca nova prévia, que
mostrará 0 a mover. Com prévia sem nada elegível (expected 0, token
válido), a chamada é um no-op que devolve moved_count = 0.

Erros (mensagem = código estável para a interface):
  28000 not_authenticated
  22023 INVALID_MODE | INVALID_ARGUMENT
  54000 COLLECTION_TOO_LARGE        (expected > 10.000, total alocado > 10.000
                                     — D6 — ou elegíveis > 10.000)
  P0002 COLLECTION_NOT_FOUND        (inexistente ou de outro usuário)
  P0002 STORAGE_NOT_FOUND           (inexistente ou de outro acervo)
  55000 COLLECTION_ARCHIVED
  P0001 DEFAULT_CHANGED             (destino deixou de ser o local padrão)
  P0001 PLAN_CHANGED                (composição/locais mudaram desde a prévia)
  55P03 LOCK_BUSY                   (v1.1: exemplar da coleção travado/alterado
                                     por outra transação em curso — tentar de novo)
  55P03 lock_not_available          (lock_timeout de 5 s na trava da coleção ou
                                     do destino — tentar de novo)

lock_timeout = 5s na própria função (SET): abaixo do statement_timeout de 8 s
do papel authenticated (pg_roles.rolconfig, registrado na 6128) — a espera
por trava nunca consome o orçamento inteiro e falha com erro claro.

Desempenho: NÃO MEDIDO (D4). O teto de 10.000 é limite de proposta, não
capacidade comprovada; ver README §Limite.
================================================================
*/

begin;

do $pre$
begin
  if to_regprocedure('public.organize_my_collection_storage(uuid, uuid, text, integer, text)') is not null then
    raise exception 'PRECHECK 5222: função já existe';
  end if;
  if to_regprocedure('public.collection_storage_plan_snapshot(uuid, uuid)') is null
     or to_regprocedure('public.get_my_collection_storage_plan(uuid, uuid)') is null then
    raise exception 'PRECHECK 5222: aplique a 5221 antes';
  end if;
end;
$pre$;

create function public.organize_my_collection_storage(
  p_collection_id        uuid,
  p_storage_container_id uuid,
  p_mode                 text,
  p_expected_count       integer,
  p_plan_token           text
)
returns table (
  collection_id        uuid,
  storage_container_id uuid,
  mode                 text,
  moved_count          integer,
  total_count          integer,
  at_target_count      integer
)
language plpgsql
volatile
security definer
set search_path = ''
set lock_timeout = '5s'
as $$
#variable_conflict use_column
declare
  c_max_per_operation constant integer := 10000;   -- D3 (proposta); mesmo valor na 5221
  v_uid       uuid := auth.uid();
  v_mode      text := upper(btrim(coalesce(p_mode, '')));
  v_inventory uuid;
  v_status    text;
  v_default   uuid;
  v_eligible  integer;
  v_ids       uuid[];
  v_locked    integer;
  v_locked_all integer := 0;
  v_total     integer;
  v_all       uuid[];
  v_id        uuid;
  v_snap      record;
  v_snap_eligible integer;
  v_moved     integer := 0;
begin
  -- 0. Forma -----------------------------------------------------------------
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if v_mode not in ('UNLOCATED', 'ALL') then
    raise exception 'INVALID_MODE' using errcode = '22023';
  end if;
  if p_collection_id is null or p_storage_container_id is null
     or p_expected_count is null or p_expected_count < 0
     or p_plan_token is null or p_plan_token !~ '^v1:[0-9a-f]{32}$' then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;
  if p_expected_count > c_max_per_operation then
    raise exception 'COLLECTION_TOO_LARGE' using errcode = '54000';
  end if;

  select i.id into v_inventory from public.inventory i where i.owner_user_id = v_uid;

  -- 1. Coleção (trava comum a vínculo, desvínculo e local padrão) -----------
  select c.lifecycle_status, c.default_storage_container_id
    into v_status, v_default
  from public.collection c
  where c.id = p_collection_id and c.owner_user_id = v_uid
  for update;
  if not found or v_inventory is null then
    raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';
  end if;
  if v_status <> 'ACTIVE' then
    raise exception 'COLLECTION_ARCHIVED' using errcode = '55000';
  end if;

  -- 2. Destino no acervo do chamador (bloqueia exclusão concorrente) -------
  perform 1
  from public.storage_container sc
  where sc.id = p_storage_container_id and sc.inventory_id = v_inventory
  for key share;
  if not found then
    raise exception 'STORAGE_NOT_FOUND' using errcode = 'P0002';
  end if;

  -- 3. D2: o destino tem de ser o local padrão vigente ----------------------
  if v_default is distinct from p_storage_container_id then
    raise exception 'DEFAULT_CHANGED';
  end if;

  -- 4. Tetos antes de qualquer trava de exemplar --------------------------
  --    D6: teto sobre o total alocado à coleção (universo do plan_token).
  select count(*) into v_total
  from public.collection_allocation ca
  where ca.collection_id = p_collection_id;
  if v_total > c_max_per_operation then
    raise exception 'COLLECTION_TOO_LARGE' using errcode = '54000';
  end if;
  --    D3: teto sobre os elegíveis da modalidade (redundante com D6, mantido).
  select count(*) into v_eligible
  from public.collection_allocation ca
  join public.physical_card pc on pc.id = ca.physical_card_id
  where ca.collection_id = p_collection_id
    and pc.inventory_id = v_inventory
    and case when v_mode = 'UNLOCATED' then pc.storage_container_id is null
             else pc.storage_container_id is distinct from p_storage_container_id end;
  if v_eligible > c_max_per_operation then
    raise exception 'COLLECTION_TOO_LARGE' using errcode = '54000';
  end if;

  -- 5. Trava TODO o universo do plan_token, um a um, em ordem de id, sem
  --    esperar. A lista vem da composição já congelada pela trava da coleção
  --    (passo 1); a ordem de aquisição é a ordem do array (FOREACH), não a
  --    do plano. Exemplar ausente na hora da trava → PLAN_CHANGED.
  select coalesce(array_agg(ca.physical_card_id order by ca.physical_card_id), '{}')
    into v_all
  from public.collection_allocation ca
  where ca.collection_id = p_collection_id;

  begin
    foreach v_id in array v_all loop
      perform 1 from public.physical_card pc where pc.id = v_id for update nowait;
      if not found then
        raise exception 'PLAN_CHANGED';
      end if;
      v_locked_all := v_locked_all + 1;
    end loop;
  exception when lock_not_available then
    raise exception 'LOCK_BUSY' using errcode = '55P03';
  end;

  -- Elegíveis da modalidade, escolhidos dentro do conjunto já travado.
  select array_agg(pc.id order by pc.id) into v_ids
  from public.collection_allocation ca
  join public.physical_card pc on pc.id = ca.physical_card_id
  where ca.collection_id = p_collection_id
    and pc.inventory_id = v_inventory
    and case when v_mode = 'UNLOCATED' then pc.storage_container_id is null
             else pc.storage_container_id is distinct from p_storage_container_id end;
  v_locked := coalesce(cardinality(v_ids), 0);

  -- 6. Revalida o que foi autorizado (snapshot novo, após as travas) --------
  select * into v_snap
  from public.collection_storage_plan_snapshot(p_collection_id, p_storage_container_id);
  v_snap_eligible := case when v_mode = 'UNLOCATED' then v_snap.eligible_unlocated else v_snap.eligible_all end;

  if v_snap.plan_token <> p_plan_token
     or v_snap_eligible <> p_expected_count
     or v_locked <> p_expected_count
     or v_locked_all <> v_snap.total_count then
    raise exception 'PLAN_CHANGED';
  end if;

  -- 7. Escrita única, set-based, só sobre os elegíveis (todos travados) ----
  if v_locked > 0 then
    update public.physical_card pc
    set storage_container_id = p_storage_container_id
    where pc.id = any(v_ids)
      and pc.inventory_id = v_inventory;
    get diagnostics v_moved = row_count;
    if v_moved <> v_locked then
      raise exception 'PLAN_CHANGED';   -- desfaz a transação inteira
    end if;
  end if;

  return query
  select p_collection_id,
         p_storage_container_id,
         v_mode,
         v_moved,
         s.total_count,
         s.at_target_count
  from public.collection_storage_plan_snapshot(p_collection_id, p_storage_container_id) s;
end;
$$;

comment on function public.organize_my_collection_storage(uuid, uuid, text, integer, text) is
  'WHERE-05A (Query 5222): organiza fisicamente, numa transação só (tudo ou nada), os exemplares ALOCADOS a uma coleção do usuário da sessão no local padrão vigente dela. Modalidades UNLOCATED (só sem localização) e ALL (todos que ainda não estão no destino). Exige o plan_token e a quantidade da prévia 5221: qualquer mudança material desde a prévia → PLAN_CHANGED sem gravar; destino que deixou de ser o padrão → DEFAULT_CHANGED. Só muda physical_card.storage_container_id. Trava todo o universo do plan_token (todos os exemplares alocados), um a um em ordem de id, com FOR UPDATE NOWAIT — LOCK_BUSY se algum estiver em uso por outra transação. Teto 10.000 sobre o total alocado (D6) e sobre os elegíveis, antes das travas de exemplar. lock_timeout 5 s.';

revoke all on function public.organize_my_collection_storage(uuid, uuid, text, integer, text) from public;
revoke all on function public.organize_my_collection_storage(uuid, uuid, text, integer, text) from anon;
grant execute on function public.organize_my_collection_storage(uuid, uuid, text, integer, text) to authenticated;

notify pgrst, 'reload schema';

commit;
