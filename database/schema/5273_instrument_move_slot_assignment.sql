/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5273 - P3-B S2 · Histórico do Fichário — instrumentação E03/E04 (Carta movida / Cartas trocadas)
              move_slot_assignment(uuid, uuid)
Versão......: 1.0 (2026-10-27, P3-B S2 — instrumentação E02–E05)
Status......: EXECUTADA / CANÔNICA. Aplicada no LIVE mimikyu-core em 2026-10-27
              (P3-B S2, autorização expressa de Fabrício; harness dispensado sob H-A
              só para a S2; ledger 20261027030813 `5273_instrument_move_slot_assignment`). Do `begin;` ao `commit;`
              idêntica ao arquivo de database/proposals/2026-10-25-p3b-binder-
              activity-history/ (só este bloco Status difere); enviada via
              apply_migration sem as linhas `begin;`/`commit;` externas — o texto
              gravado no ledger é igual ao corpo do arquivo da proposta (md5).
              LIVE_S2_90 bloco A 7/7, bloco B B.1–B.7 PASS. ADD pela interface não
              comprovado; REPLACE não testado; desempenho não medido. README §29.9–§29.11.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-27
Base........: 5132 (LIVE = canônico: md5(prosrc) 4e71adc22e4ee9c88e1fa21a0ddf4738, conferido em 2026-10-27).
Autoridade..: README da proposta §4.1 (E03/E04 (Carta movida / Cartas trocadas)), §7.2, §20 (W3), §29 (S2).

Diff mínimo: o corpo é o da 5132, byte a byte, mais as linhas marcadas com
"-- P3B-S2" (só begin/add_item/end e o necessário para elas). Removidas essas linhas e
trocado o delimitador $fn$ → $$, o corpo volta a ter o md5 acima
(static_check_p3b_s2.py, S2.2). Assinatura, retorno, SET, mensagens, códigos de erro,
ordem de travas e permissões inalterados (CREATE OR REPLACE preserva o ACL; REVOKE/GRANT
originais reaplicados de forma idempotente).

  · MOVE → evento CARD_MOVED com 1 item CARD/MOVED (origem → destino);
  · SWAP → evento CARDS_SWAPPED com 2 itens CARD/SWAPPED (A: origem → destino;
           B: destino → origem). Os dois bolsos existem antes e depois, então as cópias
           de posição são estáveis; os itens vêm depois das escritas, já com o estado
           final (I-10), e o estado intermediário do SWAP nunca é observado (§7.2.2).
  · Todos os erros (mesmo bolso, vazio, travado, alheio) saem antes do begin.

Precheck: recusa se a função LIVE divergir da base (md5) ou se 5268/5271 faltarem.
================================================================
*/

begin;

do $pre$
begin
  if to_regprocedure('public.binder_activity_add_card_item(text, uuid, uuid, uuid)') is null then
    raise exception 'PRECHECK 5273: aplique 5268 e 5271 antes';
  end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('public.move_slot_assignment(uuid, uuid)')) is distinct from '4e71adc22e4ee9c88e1fa21a0ddf4738' then
    raise exception 'PRECHECK 5273: move_slot_assignment no LIVE diverge da base 5132 (md5)';
  end if;
end;
$pre$;

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
AS $fn$
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

    -- E03/E04: um evento por chamada; itens com origem e destino depois da escrita (I-10).  -- P3B-S2
    PERFORM public.binder_activity_begin(v_layout_id, CASE v_operation WHEN 'SWAP' THEN 'CARDS_SWAPPED' ELSE 'CARD_MOVED' END, 'FICHARIO');  -- P3B-S2
    PERFORM public.binder_activity_add_card_item(CASE v_operation WHEN 'SWAP' THEN 'SWAPPED' ELSE 'MOVED' END,  -- P3B-S2
        (SELECT a.physical_card_id FROM public.collection_layout_slot_assignment a WHERE a.id = v_from_assignment),  -- P3B-S2
        p_from_slot_id, p_to_slot_id);  -- P3B-S2
    IF v_operation = 'SWAP' THEN  -- P3B-S2
        PERFORM public.binder_activity_add_card_item('SWAPPED',  -- P3B-S2
            (SELECT a.physical_card_id FROM public.collection_layout_slot_assignment a WHERE a.id = v_to_assignment),  -- P3B-S2
            p_to_slot_id, p_from_slot_id);  -- P3B-S2
    END IF;  -- P3B-S2
  -- P3B-S2
    RETURN QUERY
    SELECT v_operation,
           v_from_assignment,
           p_to_slot_id,
           v_to_assignment,
           CASE WHEN v_to_assignment IS NULL THEN NULL ELSE p_from_slot_id END;
    PERFORM public.binder_activity_end();  -- P3B-S2
END;
$fn$;

REVOKE EXECUTE ON FUNCTION public.move_slot_assignment(uuid, uuid)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.move_slot_assignment(uuid, uuid)
    TO authenticated;

commit;
