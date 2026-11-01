/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5344 - Fichário (P2): aplicação da organização automática
Versão......: 1.3
Status......: PROPOSTO — NÃO EXECUTADO (FOUNDATION-06; v1.1 TARGETED SQL SAFETY AUDIT-07,
              2026-11-01: só documentação do protocolo — corpo inalterado; a
              correção de idempotência está no token da 5342 v1.1)
              v1.3 (P2 GATE 02 TARGETED CORRECTION-12): o bloco que envolve a
              trava da coleção (passo 2) capturava `when others` e devolvia
              BINDER_NOT_FOUND para qualquer erro, inclusive 55P03 do
              lock_timeout. Passa a capturar só `raise_exception` (P0001) e a
              traduzir apenas as duas mensagens de domínio da 5122; o resto é
              re-propagado com `raise;` (SQLSTATE preservado). Único trecho
              alterado do corpo.
Autor.......: Fabrício Sales / Claude
Data........: 2026-11-01

Objetivo
  Confirmação atômica do plano mostrado por preview_my_binder_auto_arrange
  (5343). Recalcula o plano sob travas e só escreve se o token for idêntico
  ao confirmado. Única escrita: INSERT em collection_layout_slot_assignment
  (+ histórico). Nunca substitui, remove ou move cartas; nunca cria/altera
  reservas; nunca toca Inventory, Collection Allocation ou Storage (D7–D9).

Assinatura
  public.apply_my_binder_auto_arrange(p_collection_id uuid, p_plan_token text) returns jsonb
  SECURITY DEFINER · VOLATILE · search_path '' · lock_timeout 5s ·
  EXECUTE só para authenticated.

Erros (todos abortam a transação inteira — zero escrita parcial)
  28000 not_authenticated
  22023 INVALID_ARGUMENT                 (nulo ou token fora do formato aa1:<64 hex>)
  P0002 COLLECTION_NOT_FOUND             (inexistente ou alheia — colapsadas)
  55000 COLLECTION_ARCHIVED
  22023 AUTO_ARRANGE_UNSUPPORTED_COLLECTION
  42501 AUTO_ARRANGE_NOT_BINDER_OWNER    (coleção convidada)
  P0002 BINDER_NOT_FOUND
  40001 AUTO_ARRANGE_PLAN_CHANGED        (plano recalculado ≠ token confirmado)
  54000 AUTO_ARRANGE_LIMIT_EXCEEDED      (plano válido com mais de 500 inserções)
  55P03 lock_not_available               (lock_timeout; nada escrito; propagado
                                          sem tradução desde a v1.3)
  Erro inesperado → propagado sem captura genérica; rollback total.

Retornos sem erro
  {"status":"APPLIED","inserted":n,"event_id":id,"pages":[…]}
  {"status":"NOTHING_TO_DO","inserted":0}            — plano vazio e token
                                                       igual: nenhum evento.
  {"status":"ALREADY_APPLIED","inserted":0,"event_id":id}
                                                     — token diverge do plano
                                                       atual, mas já existe
                                                       evento CARDS_AUTO_ARRANGED
                                                       deste fichário com este
                                                       token (repetição da mesma
                                                       confirmação). Nada escrito.
  Regra de identidade (v1.1): o token inclui a época (último evento
  CARDS_AUTO_ARRANGED do fichário), então um token aplicado nunca volta a ser
  recalculado. Logo: token = plano atual → aplicar; token ≠ plano atual e
  presente no resumo de um evento do fichário → ALREADY_APPLIED; senão →
  PLAN_CHANGED. Repetição imediata, resposta perdida e duas confirmações
  simultâneas (a segunda espera a trava da coleção) caem em ALREADY_APPLIED;
  o mesmo conjunto de pares reaparecendo após mudanças legítimas exige nova
  prévia (token novo). Limpeza do histórico (5270, v1.2 da 5342): a época
  inclui o marco binder_activity_coverage, regravado na mesma transação da
  limpeza; todo token anterior passa a divergir e, sem evento para provar a
  aplicação, recebe PLAN_CHANGED — nunca é tratado como nova autorização
  (perde-se apenas o ALREADY_APPLIED informativo daquela confirmação).
  Corpo inalterado da v1.0 à v1.2; a v1.3 altera só o handler do passo 2.

Ordem de travas (mesma família de place_my_physical_card_in_slot, 5272)
  1. assert_collection_layout_mutable(layout) — trava a coleção proprietária
     FOR UPDATE (5122) e serializa com todo escritor do fichário que passa
     por ela (posicionar, mover, reservar, travar, mesclar, páginas, outra
     organização automática).
  2. Recalcula o plano (1ª vez) e compara o token. Plano calculado só
     duas vezes no total (passos 2 e 5).
  3. Bolsos do plano FOR UPDATE, ordem por id.
  4. Exemplares do plano FOR UPDATE, ordem por id (mesma ordem dos
     escritores de local/alocação 5249, que travam exemplares por id).
  5. Recalcula o plano (2ª vez) e compara o token — cobre escritores que
     não passam pela trava da coleção (mudança de local/alocação) e que
     confirmaram entre os passos 2 e 4.
  6. INSERTs (sem ON CONFLICT: qualquer colisão é PLAN_CHANGED).
  Sem ciclo: coleção → bolsos → exemplares, sempre nessa ordem.

Isolamento e escritores concorrentes (auditado em TARGETED SQL SAFETY AUDIT-07)
  · Requer READ COMMITTED (padrão do PostgREST): cada comando vê os commits
    anteriores à trava. Sob REPEATABLE READ o 2º recálculo usaria o snapshot
    antigo; a integridade continua garantida pelas UNIQUE (colisão → 40001 ou
    23505 no COMMIT), mas ALREADY_APPLIED deixaria de ser devolvido.
  · Escritores que podem INVALIDAR um par do plano serializam conosco:
    pela coleção proprietária (assert 5122 ou binder_layout_lock_for_collection:
    posicionar/mover/remover, reservas, travas, mesclagem, imagem, páginas,
    lacunas, novidades do catálogo, convidadas, desmontagem, transferência;
    allocate/deallocate travam a coleção-alvo FOR UPDATE) ou pelo exemplar
    (set_physical_cards_storage, organize_my_collection_storage NOWAIT,
    remove_my_physical_card). Nenhum deles pede trava que já seguramos antes
    de pedir a nossa ⇒ sem ciclo.
  · purge_my_binder_activity (5270) não trava nada em comum; se confirmar
    entre os dois recálculos, a época muda e a aplicação recebe PLAN_CHANGED
    (rejeição conservadora); se confirmar depois, o evento recém-gravado não
    é visto pelo DELETE dela (snapshot) e sobrevive.
  · Escritores que só ACRESCENTAM candidatos ou liberam bolsos (cadastro em
    lote no local do fichário, entrada de outro exemplar no local, saída de
    exemplar não planejado, desativação de variante pelo catálogo) não
    bloqueiam; se confirmarem depois do 2º recálculo, o resultado equivale à
    ordem serial "organizar, depois a outra operação". Nenhum invalida as
    posições criadas (dono e local revalidados pelo gatilho 5248 sob a trava
    do exemplar).

Notas de integridade
  · uq_collection_layout_slot_assignment_slot é DEFERRABLE INITIALLY DEFERRED
    (5115): colisão de bolso só apareceria no COMMIT. Ela é impossível aqui
    porque todo escritor de bolso trava o bolso FOR UPDATE antes de inserir
    e os bolsos do plano estão travados (passo 3) e vazios (passo 5).
  · uq_collection_layout_slot_assignment_physical_card é imediata: colisão
    vira AUTO_ARRANGE_PLAN_CHANGED.

Histórico (C-205 / D13)
  Um evento CARDS_AUTO_ARRANGED (source FICHARIO, collection_id da
  proprietária) com summary {plan_token, inserted} e um item CARD/PLACED por
  carta (bolso de destino). Teto de itens da 5268 (≥ capacidade + 600) cobre
  500. Evento aberto só depois de todas as validações — plano vazio, limite
  ou divergência não deixam evento.

Resultado esperado: função criada; EXECUTE apenas authenticated.
Como validar: harness 5872 (B.*, C.*, D.*, E.*, H.*, K.*, R.*).
================================================================
*/

begin;

do $pre$
begin
  if to_regprocedure('public.binder_auto_arrange_plan(uuid,uuid,uuid)') is null then
    raise exception 'PRECHECK 5344: 5342 ausente';
  end if;
  if to_regprocedure('public.assert_collection_layout_mutable(uuid)') is null
     or to_regprocedure('public.binder_activity_begin(uuid,text,text,uuid,jsonb)') is null
     or to_regprocedure('public.binder_activity_add_card_item(text,uuid,uuid,uuid)') is null
     or to_regprocedure('public.binder_activity_end()') is null then
    raise exception 'PRECHECK 5344: dependências 5122/5268/5271 ausentes';
  end if;
  if position('CARDS_AUTO_ARRANGED' in pg_get_constraintdef(
       (select oid from pg_constraint where conrelid = 'public.binder_activity_event'::regclass
          and conname = 'chk_bae_event_type'))) = 0 then
    raise exception 'PRECHECK 5344: 5341 não aplicada (tipo CARDS_AUTO_ARRANGED ausente)';
  end if;
  if to_regprocedure('public.apply_my_binder_auto_arrange(uuid,text)') is not null then
    raise exception 'PRECHECK 5344: função já existe';
  end if;
end;
$pre$;

create function public.apply_my_binder_auto_arrange(
  p_collection_id uuid,
  p_plan_token    text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
set lock_timeout = '5s'
as $fn$
declare
  c_limit     constant integer := 500;
  v_uid       uuid := auth.uid();
  v_mode      text;
  v_policy    text;
  v_status    text;
  v_layout    uuid;
  v_container uuid;
  v_n         integer;
  v_token     text;
  v_event     bigint;
  v_rows      integer;
  v_slots     uuid[];
  v_cards     uuid[];
  v_pages     jsonb;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_collection_id is null or p_plan_token is null or p_plan_token !~ '^aa1:[0-9a-f]{64}$' then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;

  -- 1. Fronteira de dono e tipo, sem trava (mesmas regras e ordem da prévia).
  select c.mode, c.completion_policy, c.lifecycle_status
    into v_mode, v_policy, v_status
  from public.collection c
  where c.id = p_collection_id and c.owner_user_id = v_uid;
  if not found then
    raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';
  end if;
  if v_status <> 'ACTIVE' then
    raise exception 'COLLECTION_ARCHIVED' using errcode = '55000';
  end if;
  if v_mode is distinct from 'REFERENCE_BASED'
     or v_policy is null or v_policy not in ('STANDARD_SET', 'MASTER_SET') then
    raise exception 'AUTO_ARRANGE_UNSUPPORTED_COLLECTION' using errcode = '22023';
  end if;

  select l.id into v_layout from public.collection_layout l where l.collection_id = p_collection_id;
  if v_layout is null then
    if exists (select 1 from public.collection_layout_guest g where g.collection_id = p_collection_id) then
      raise exception 'AUTO_ARRANGE_NOT_BINDER_OWNER' using errcode = '42501';
    end if;
    raise exception 'BINDER_NOT_FOUND' using errcode = 'P0002';
  end if;

  -- 2. Proprietária → layout (5122: dono, ACTIVE; trava a coleção FOR UPDATE).
  --    v1.3: só os dois RAISE de domínio da 5122 (P0001) são traduzidos; trava
  --    ocupada (55P03), deadlock, permissão e demais erros propagam intactos.
  begin
    perform public.assert_collection_layout_mutable(v_layout);
  exception
    when raise_exception then
      if sqlerrm like 'collection is ARCHIVED%' then
        raise exception 'COLLECTION_ARCHIVED' using errcode = '55000';
      elsif sqlerrm = 'collection layout not found or not owned by caller' then
        raise exception 'BINDER_NOT_FOUND' using errcode = 'P0002';
      end if;
      raise;
  end;

  -- Revalida sob a trava (arquivamento, troca de objetivo ou transferência concorrentes).
  select c.mode, c.completion_policy, c.lifecycle_status
    into v_mode, v_policy, v_status
  from public.collection c
  where c.id = p_collection_id and c.owner_user_id = v_uid;
  if not found then
    raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';
  end if;
  if v_status <> 'ACTIVE' then
    raise exception 'COLLECTION_ARCHIVED' using errcode = '55000';
  end if;
  if v_mode is distinct from 'REFERENCE_BASED'
     or v_policy is null or v_policy not in ('STANDARD_SET', 'MASTER_SET') then
    raise exception 'AUTO_ARRANGE_UNSUPPORTED_COLLECTION' using errcode = '22023';
  end if;
  select l.storage_container_id into v_container
  from public.collection_layout l
  where l.id = v_layout and l.collection_id = p_collection_id;
  if not found then
    raise exception 'BINDER_NOT_FOUND' using errcode = 'P0002';
  end if;

  -- 3. Primeiro recálculo + comparação (uma passada: token, contagem e pares).
  select max(h.plan_token), max(h.insert_count),
         array_agg(h.slot_id order by h.slot_id) filter (where h.item_kind = 'INSERT'),
         array_agg(h.physical_card_id order by h.physical_card_id) filter (where h.item_kind = 'INSERT')
    into v_token, v_n, v_slots, v_cards
  from public.binder_auto_arrange_plan(p_collection_id, v_layout, v_container) h;

  if v_token is distinct from p_plan_token then
    -- Repetição de uma confirmação que já foi aplicada? (idempotência)
    select e.id into v_event
    from public.binder_activity_event e
    where e.layout_key = v_layout
      and e.owner_user_id = v_uid
      and e.event_type = 'CARDS_AUTO_ARRANGED'
      and e.summary ->> 'plan_token' = p_plan_token
    order by e.id desc
    limit 1;
    if v_event is not null then
      return jsonb_build_object('status', 'ALREADY_APPLIED', 'inserted', 0, 'event_id', v_event);
    end if;
    raise exception 'AUTO_ARRANGE_PLAN_CHANGED' using errcode = '40001',
      hint = 'o fichário mudou desde a prévia — gere uma nova prévia';
  end if;

  if v_n = 0 then
    return jsonb_build_object('status', 'NOTHING_TO_DO', 'inserted', 0);
  end if;
  if v_n > c_limit then
    raise exception 'AUTO_ARRANGE_LIMIT_EXCEEDED' using errcode = '54000',
      detail = format('%s inserções planejadas; limite %s por confirmação', v_n, c_limit);
  end if;

  -- 4. Travas dos bolsos e dos exemplares do plano (ordem por id, sem ciclo).
  perform 1 from public.collection_layout_slot s
  where s.id = any(v_slots)
  order by s.id
  for update of s;

  perform 1 from public.physical_card pc
  where pc.id = any(v_cards)
  order by pc.id
  for update of pc;

  -- 5. Segundo recálculo sob todas as travas; os pares a gravar vêm DESTE cálculo.
  select max(h.plan_token),
         array_agg(h.slot_id order by h.ord) filter (where h.item_kind = 'INSERT'),
         array_agg(h.physical_card_id order by h.ord) filter (where h.item_kind = 'INSERT'),
         coalesce(jsonb_agg(distinct h.page_number order by h.page_number)
                    filter (where h.item_kind = 'INSERT'), '[]'::jsonb)
    into v_token, v_slots, v_cards, v_pages
  from public.binder_auto_arrange_plan(p_collection_id, v_layout, v_container) h;
  if v_token is distinct from p_plan_token then
    raise exception 'AUTO_ARRANGE_PLAN_CHANGED' using errcode = '40001',
      hint = 'o fichário mudou desde a prévia — gere uma nova prévia';
  end if;

  -- 6. Escrita + histórico (evento aberto só agora, depois de toda validação).
  perform public.binder_activity_begin(v_layout, 'CARDS_AUTO_ARRANGED', 'FICHARIO', p_collection_id,
                                       jsonb_build_object('plan_token', p_plan_token, 'inserted', v_n));
  v_rows := 0;
  for i in 1 .. coalesce(array_length(v_slots, 1), 0) loop
    begin
      insert into public.collection_layout_slot_assignment (slot_id, physical_card_id)
      values (v_slots[i], v_cards[i]);
    exception
      when unique_violation then
        raise exception 'AUTO_ARRANGE_PLAN_CHANGED' using errcode = '40001',
          hint = 'o fichário mudou desde a prévia — gere uma nova prévia';
    end;
    perform public.binder_activity_add_card_item('PLACED', v_cards[i], null, v_slots[i]);
    v_rows := v_rows + 1;
  end loop;

  if v_rows <> v_n then
    raise exception 'AUTO_ARRANGE_PLAN_CHANGED' using errcode = '40001';
  end if;

  v_event := (nullif(current_setting('mmkyu.binder_activity_ctx', true), '')::jsonb ->> 'event_id')::bigint;
  perform public.binder_activity_end();

  return jsonb_build_object('status', 'APPLIED', 'inserted', v_rows, 'event_id', v_event, 'pages', v_pages);
end;
$fn$;

revoke all on function public.apply_my_binder_auto_arrange(uuid, text) from public, anon;
grant execute on function public.apply_my_binder_auto_arrange(uuid, text) to authenticated;

comment on function public.apply_my_binder_auto_arrange(uuid, text) is
  'P2 5344 (C-220..C-226): confirma a organização automática do fichário (proprietária, Set/Master Set). Recalcula o plano sob travas (coleção → bolsos → exemplares), exige o mesmo token aa1 (senão AUTO_ARRANGE_PLAN_CHANGED 40001), limite 500 (AUTO_ARRANGE_LIMIT_EXCEEDED 54000), só INSERT de posições, um evento CARDS_AUTO_ARRANGED com um item PLACED por carta. Repetição do token já aplicado → ALREADY_APPLIED.';

notify pgrst, 'reload schema';

commit;
