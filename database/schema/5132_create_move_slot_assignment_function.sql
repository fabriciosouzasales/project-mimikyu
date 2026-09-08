/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5132 - Create move_slot_assignment()
Versão......: 2.0
Status......: CONFIRMADO EXECUTADO / LIVE / PROMOVIDO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-06 (staging em
               COLLECTIONS-BINDER-LAYOUT-FOUNDATION-STAGING-01)

Descrição...:
Cobre MOVE e SWAP atomicamente, em uma assinatura.

- destino VAZIO   -> MOVE: UPDATE do slot_id DA MESMA LINHA.
  LDM-35 é explícito: "a mesma relação muda de slot_id (NÃO é
  encerrada e recriada)". Por isso jamais DELETE+INSERT — o `id` da
  Assignment é preservado, e o harness 5818 verifica exatamente isso.

- destino OCUPADO -> SWAP: as duas linhas existentes trocam slot_id
  na MESMA transação. "As duas cartas trocam de lugar atomicamente,
  nenhuma é criada/duplicada" (regra observada nos spikes; LDM-35:
  "duas relações existentes trocam mutuamente seu slot_id"). Os DOIS
  ids são preservados.

  O estado intermediário do SWAP viola momentaneamente
  UNIQUE (slot_id) — por isso ela é DEFERRABLE INITIALLY DEFERRED
  (Query 5115), verificada só no COMMIT. Sem isso seria preciso um
  slot_id temporário inexistente, que a FK rejeitaria.

Ordem determinística de lock (anti-deadlock): Layout -> Slots ORDER BY
id -> Assignments ORDER BY id. Duas transações que operem o mesmo par
de Slots em ordens opostas convergem para a mesma sequência.

Lock (C-43): origem OU destino locked rejeita — cobre MOVE e SWAP.
Antecipado aqui para mensagem legível; garantido pelo trigger 5118.

Mover para a Bandeja NÃO é esta operação: a Bandeja não persiste
(C-45/LDM-36), e "Slot A -> Bandeja -> Slot B" tem como único
resultado persistente "A -> B", ou seja, exatamente um MOVE.

Dependências:
- public.assert_collection_layout_mutable() (Query 5122).
- public.collection_layout_slot_assignment (Query 5115).

CORREÇÃO CONSOLIDADA 01 (2026-09-06,
COLLECTIONS-BINDER-LAYOUT-FOUNDATION-CONSOLIDATED-CORRECTION-01):
§4B NON-ENUMERATION EM MOVE + §3 POST-LOCK REVALIDATION.

A v1.0 resolvia origem e destino SEM filtro de ownership e comparava
`source_layout_id` vs `destination_layout_id` ANTES de provar
ownership dos dois Slots. Consequência: um Slot alheio EXISTENTE
produzia 'Slots ... pertencem a Layouts diferentes', enquanto um UUID
inexistente produzia 'not found' — oráculo de existência sobre objetos
de outro Owner.

Agora: os DOIS Slots são resolvidos owner-scoped primeiro; qualquer um
não visível ao caller produz a MESMA mensagem genérica; só depois
disso se compara o Layout, se adquire o lock e se revalida. `locked` e
as Assignments envolvidas são lidos DEPOIS do lock.

STATUS DESTA QUERY: CONFIRMADO EXECUTADO / LIVE / PROMOVIDO.

Aplicada ao banco real em 2026-09-07, na rodada
`COLLECTIONS-BINDER-LAYOUT-FOUNDATION-IMPLEMENTATION-01`. Validada por
`5818` v7.2 (196/196 runtime, FAIL 0) e por `5819` v3.0 (22/22 HEALTHY,
nenhum indice novo criado). Ledger e evidencia completa em
`database/proposals/2026-09-06-binder-layout-foundation/README.md`.

Promovida para `database/schema/` em `SCHEMA-PROMOTION-RECONCILIATION-01`
(2026-09-08). A copia historica permanece em
`database/proposals/2026-09-06-binder-layout-foundation/`, junto com os
harnesses `5818`/`5819`, o roteiro `CONCURRENCY-PROOF-C04-R18.sql` e o
`README.md` da rodada — esses quatro NAO sao promovidos, por convencao.
A promocao alterou apenas cabecalho/rodape: o corpo executavel
(`BEGIN;` .. `COMMIT;`) permanece byte-identico ao da copia em proposals.
================================================================
*/

BEGIN;

CREATE OR REPLACE FUNCTION public.move_slot_assignment(
    p_from_slot_id UUID,
    p_to_slot_id   UUID
)
RETURNS TABLE (
    operation         TEXT,
    assignment_id     UUID,
    new_slot_id       UUID,
    swapped_assignment_id UUID,
    swapped_new_slot_id   UUID
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_layout_id       UUID;
    v_layout_id_to    UUID;
    v_locked_count    INTEGER;
    v_visible_count   INTEGER;
    v_from_assignment UUID;
    v_to_assignment   UUID;
    v_operation       TEXT;
BEGIN
    IF (select auth.uid()) IS NULL THEN
        RAISE EXCEPTION 'authentication required';
    END IF;

    IF p_from_slot_id = p_to_slot_id THEN
        RAISE EXCEPTION 'no-op: Slot de origem e destino são o mesmo';
    END IF;

    -- 1) RESOLVE OWNER-SCOPED DA ORIGEM.
    SELECT p.layout_id INTO v_layout_id
      FROM public.collection_layout_slot s
      JOIN public.collection_layout_page p ON p.id = s.page_id
      JOIN public.collection_layout l      ON l.id = p.layout_id
      JOIN public.collection c             ON c.id = l.collection_id
     WHERE s.id = p_from_slot_id
       AND c.owner_user_id = (select auth.uid());

    IF NOT FOUND THEN
        RAISE EXCEPTION 'layout slot not found or not owned by caller';
    END IF;

    -- 2) RESOLVE OWNER-SCOPED DO DESTINO. Só depois de AMBOS estarem
    -- provados como visíveis ao caller é que a comparação de Layout
    -- pode acontecer.
    SELECT p.layout_id INTO v_layout_id_to
      FROM public.collection_layout_slot s
      JOIN public.collection_layout_page p ON p.id = s.page_id
      JOIN public.collection_layout l      ON l.id = p.layout_id
      JOIN public.collection c             ON c.id = l.collection_id
     WHERE s.id = p_to_slot_id
       AND c.owner_user_id = (select auth.uid());

    IF NOT FOUND THEN
        RAISE EXCEPTION 'layout slot not found or not owned by caller';
    END IF;

    -- 3) SOMENTE AGORA: mesmo Layout.
    IF v_layout_id IS DISTINCT FROM v_layout_id_to THEN
        RAISE EXCEPTION 'Slots de origem e destino pertencem a Layouts diferentes';
    END IF;

    -- 4) COLLECTION LOCK -> LAYOUT LOCK + ACTIVE.
    BEGIN
        PERFORM public.assert_collection_layout_mutable(v_layout_id);
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLERRM LIKE 'collection layout not found%' THEN
                RAISE EXCEPTION 'layout slot not found or not owned by caller';
            END IF;
            RAISE;
    END;

    -- 5) SLOT LOCK dos dois, ordem determinística.
    PERFORM 1
       FROM public.collection_layout_slot s
      WHERE s.id IN (p_from_slot_id, p_to_slot_id)
      ORDER BY s.id
      FOR UPDATE;

    -- 6) REVALIDAÇÃO PÓS-LOCK: os dois Slots continuam existindo, no
    -- mesmo Layout e sob o mesmo Owner?
    SELECT count(*) INTO v_visible_count
      FROM public.collection_layout_slot s
      JOIN public.collection_layout_page p ON p.id = s.page_id
      JOIN public.collection_layout l      ON l.id = p.layout_id
      JOIN public.collection c             ON c.id = l.collection_id
     WHERE s.id IN (p_from_slot_id, p_to_slot_id)
       AND p.layout_id = v_layout_id
       AND c.owner_user_id = (select auth.uid());

    IF v_visible_count <> 2 THEN
        RAISE EXCEPTION 'layout slot not found or not owned by caller';
    END IF;

    -- 7) `locked` lido PÓS-LOCK.
    SELECT count(*) INTO v_locked_count
      FROM public.collection_layout_slot s
     WHERE s.id IN (p_from_slot_id, p_to_slot_id)
       AND s.locked;

    IF v_locked_count > 0 THEN
        RAISE EXCEPTION
            'Slot de origem e/ou destino bloqueado (locked) — Move/Swap não permitido';
    END IF;

    -- 8) Lock das Assignments envolvidas, ordem determinística.
    PERFORM 1
       FROM public.collection_layout_slot_assignment a
      WHERE a.slot_id IN (p_from_slot_id, p_to_slot_id)
      ORDER BY a.id
      FOR UPDATE;

    -- 9) Estado das Assignments lido PÓS-LOCK.
    SELECT a.id INTO v_from_assignment
      FROM public.collection_layout_slot_assignment a
     WHERE a.slot_id = p_from_slot_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Slot de origem está vazio — nada a mover';
    END IF;

    SELECT a.id INTO v_to_assignment
      FROM public.collection_layout_slot_assignment a
     WHERE a.slot_id = p_to_slot_id;

    IF FOUND THEN
        -- SWAP: as duas linhas trocam slot_id. UNIQUE(slot_id)
        -- DEFERRABLE tolera o estado intermediário até o COMMIT.
        -- Nenhum collection_allocation_id é alterado (ver 5117).
        v_operation := 'SWAP';

        UPDATE public.collection_layout_slot_assignment
           SET slot_id = p_to_slot_id
         WHERE id = v_from_assignment;

        UPDATE public.collection_layout_slot_assignment
           SET slot_id = p_from_slot_id
         WHERE id = v_to_assignment;
    ELSE
        -- MOVE: a MESMA linha muda de slot_id (LDM-35).
        v_operation     := 'MOVE';
        v_to_assignment := NULL;

        UPDATE public.collection_layout_slot_assignment
           SET slot_id = p_to_slot_id
         WHERE id = v_from_assignment;
    END IF;

    RETURN QUERY
    SELECT v_operation,
           v_from_assignment,
           p_to_slot_id,
           v_to_assignment,
           CASE WHEN v_to_assignment IS NULL THEN NULL ELSE p_from_slot_id END;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.move_slot_assignment(uuid, uuid)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.move_slot_assignment(uuid, uuid)
    TO authenticated;

COMMIT;
