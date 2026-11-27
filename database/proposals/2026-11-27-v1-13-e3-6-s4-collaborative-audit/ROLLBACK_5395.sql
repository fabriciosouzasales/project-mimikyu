/*
================================================================
Projeto.....: Project Mimikyu
Query.......: R5395 - Reversão da 5395 (GERADA por build_5395.py)
Versão......: 1.1 (2026-11-27; precheck com o md5 da 5395 v1.1)
Status......: PROPOSTA — NÃO EXECUTADA. Só com autorização específica e só com a 5395
              confirmada. Restaura o texto canônico (6123/6124/6126/6125) das 4 funções do
              titular e remove get_collection_activity. Não apaga eventos já gravados. A
              captura derivada da 5394 volta a cobrir as operações do titular (agregada).
================================================================
*/

begin;
set local lock_timeout = '3s';

do $pre$
begin
  if (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.set_pokedex_position_assignment(uuid, uuid, boolean)')) is distinct from 'ce63a458c1e79024dd512e60726a4004'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.remove_pokedex_position_assignment(uuid)')) is distinct from '2502eb25191383cc00aac62969b2671d'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.set_pokedex_position_primary_representative(uuid)')) is distinct from '1bbf1a6a5fe0bafedadbb7543f6d7951'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.clear_pokedex_position_primary_representative(uuid, uuid)')) is distinct from '2bf25d3d21e6ab06ccb50269bff1502b' then
    raise exception 'PRECHECK R5395: funções do titular não estão no texto da 5395 — diagnosticar';
  end if;
end;
$pre$;

CREATE OR REPLACE FUNCTION public.set_pokedex_position_assignment(
    p_physical_card_id UUID,
    p_pokedex_position_id UUID,
    p_confirm_override BOOLEAN DEFAULT false
)
RETURNS TABLE (
    collection_allocation_id UUID,
    pokedex_position_id UUID,
    assignment_basis TEXT,
    assigned_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_collection_allocation_id UUID;
    v_collection_id            UUID;
    v_lifecycle_status         TEXT;
    v_pokedex_id_from_col      UUID;
    v_pokedex_id_from_pos      UUID;
    v_species_id_from_pos      UUID;
    v_card_id                  UUID;
    v_category_code            TEXT;
    v_resolved_species_id      UUID;
    v_existing_position_id     UUID;
    v_basis                    TEXT;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'authentication required';
    END IF;

    IF p_physical_card_id IS NULL OR p_pokedex_position_id IS NULL THEN
        RAISE EXCEPTION 'SET_POKEDEX_POSITION_ASSIGNMENT_MISSING_PARAMETER: p_physical_card_id e p_pokedex_position_id são obrigatórios.';
    END IF;

    -- Leitura inicial (sem lock) só para descobrir qual Collection travar
    -- primeiro (PAUSE, item 3 — ordem de domínio Collection -> Allocation,
    -- padrão 5046/5047).
    SELECT ca.id, ca.collection_id
      INTO v_collection_allocation_id, v_collection_id
      FROM public.collection_allocation ca
      JOIN public.collection col ON col.id = ca.collection_id
     WHERE ca.physical_card_id = p_physical_card_id
       AND col.owner_user_id = auth.uid();

    IF NOT FOUND THEN
        RAISE EXCEPTION 'SET_POKEDEX_POSITION_ASSIGNMENT_NOT_ALLOCATED: physical_card não está alocado a uma Collection do chamador.';
    END IF;

    -- Lock real de Collection PRIMEIRO — ownership revalidada na própria
    -- WHERE do FOR UPDATE. Serializa contra archive_collection()/
    -- reactivate_collection() concorrente (PAUSE, item 3).
    SELECT col.lifecycle_status
      INTO v_lifecycle_status
      FROM public.collection col
     WHERE col.id = v_collection_id
       AND col.owner_user_id = auth.uid()
     FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'SET_POKEDEX_POSITION_ASSIGNMENT_NOT_ALLOCATED: physical_card não está alocado a uma Collection do chamador.';
    END IF;

    IF v_lifecycle_status <> 'ACTIVE' THEN
        RAISE EXCEPTION 'SET_POKEDEX_POSITION_ASSIGNMENT_COLLECTION_ARCHIVED: collection is archived — reactivate before assigning.';
    END IF;

    -- Só DEPOIS do lock de Collection, trava e revalida a própria
    -- Allocation (ordem: Collection -> Allocation, nunca invertida).
    SELECT ca.id
      INTO v_collection_allocation_id
      FROM public.collection_allocation ca
     WHERE ca.physical_card_id = p_physical_card_id
       AND ca.collection_id = v_collection_id
     FOR UPDATE OF ca;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'SET_POKEDEX_POSITION_ASSIGNMENT_NOT_ALLOCATED: physical_card não está mais alocado a esta Collection (removido concorrentemente).';
    END IF;

    -- NO-OP CHECK (STAGING-AUDIT-01 item 3, preservado sem mudança de
    -- comportamento): resolvido antes de qualquer validação de Pokédex/
    -- Position/Species. Já usa alias "a." — nunca foi ambíguo.
    SELECT a.pokedex_position_id INTO v_existing_position_id
      FROM public.collection_pokedex_position_assignment a
     WHERE a.collection_allocation_id = v_collection_allocation_id;

    IF FOUND AND v_existing_position_id = p_pokedex_position_id THEN
        RETURN QUERY
        SELECT a.collection_allocation_id, a.pokedex_position_id, a.assignment_basis, a.assigned_at
          FROM public.collection_pokedex_position_assignment a
         WHERE a.collection_allocation_id = v_collection_allocation_id;
        RETURN;
    END IF;

    -- Collection precisa ser Pokédex E REFERENCE_BASED, explícito (PAUSE,
    -- item 4 — mesma defesa em profundidade já aplicada em 6119/trigger 1
    -- acima).
    SELECT cpr.pokedex_id INTO v_pokedex_id_from_col
      FROM public.collection col
      JOIN public.collection_reference cr ON cr.collection_id = col.id
      JOIN public.collection_pokedex_reference cpr ON cpr.collection_reference_id = cr.id
     WHERE col.id = v_collection_id
       AND col.mode = 'REFERENCE_BASED'
       AND cr.reference_kind = 'POKEDEX';

    IF v_pokedex_id_from_col IS NULL THEN
        RAISE EXCEPTION 'SET_POKEDEX_POSITION_ASSIGNMENT_NOT_POKEDEX_COLLECTION: collection não é uma Collection Pokédex REFERENCE_BASED.';
    END IF;

    SELECT pp.pokedex_id, pp.species_id
      INTO v_pokedex_id_from_pos, v_species_id_from_pos
      FROM public.pokedex_position pp
     WHERE pp.id = p_pokedex_position_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'SET_POKEDEX_POSITION_ASSIGNMENT_POSITION_NOT_FOUND: pokedex_position_id inexistente.';
    END IF;

    IF v_pokedex_id_from_pos IS DISTINCT FROM v_pokedex_id_from_col THEN
        RAISE EXCEPTION 'SET_POKEDEX_POSITION_ASSIGNMENT_WRONG_POKEDEX: a Position pertence a um Pokédex diferente do referenciado pela Collection.';
    END IF;

    SELECT c.id, cc.code
      INTO v_card_id, v_category_code
      FROM public.physical_card pc
      JOIN public.card_variant cv ON cv.id = pc.card_variant_id
      JOIN public.card c ON c.id = cv.card_id
      JOIN public.card_category cc ON cc.id = c.category_id
     WHERE pc.id = p_physical_card_id;

    SELECT cps.pokemon_species_id INTO v_resolved_species_id
      FROM public.card_primary_species cps
     WHERE cps.card_id = v_card_id;

    IF v_category_code = 'POKEMON'
       AND v_resolved_species_id IS NOT NULL
       AND v_resolved_species_id = v_species_id_from_pos
    THEN
        v_basis := 'SPECIES_MATCH';
    ELSE
        -- Fail-closed (PAUSE, item 1): NULL nunca é tratado como
        -- confirmação — só p_confirm_override = TRUE literal libera
        -- USER_OVERRIDE. "IF NOT p_confirm_override" original tratava
        -- NULL como falso-negativo (NOT NULL = NULL, IF NULL não entra),
        -- permitindo bypass silencioso da confirmação.
        IF p_confirm_override IS DISTINCT FROM TRUE THEN
            RAISE EXCEPTION 'SET_POKEDEX_POSITION_ASSIGNMENT_CONFIRMATION_REQUIRED: Card não corresponde à Species da Position (ou não é Pokémon/sem Species resolvida) — confirme explicitamente com p_confirm_override = true.';
        END IF;
        v_basis := 'USER_OVERRIDE';
    END IF;

    IF v_existing_position_id IS NOT NULL THEN
        -- MOVE: DELETE + INSERT, nunca UPDATE. WHERE qualificado pelo
        -- nome da tabela (PAUSE, item 2 — achado mais amplo que o
        -- mandato original: a mesma ambiguidade também existia aqui, não
        -- só na RETURNING do INSERT abaixo).
        DELETE FROM public.collection_pokedex_position_assignment
         WHERE collection_pokedex_position_assignment.collection_allocation_id = v_collection_allocation_id;
    END IF;

    -- RETURNING qualificada pelo nome da tabela (PAUSE, item 2).
    RETURN QUERY
    INSERT INTO public.collection_pokedex_position_assignment
        (collection_allocation_id, pokedex_position_id, assignment_basis, assigned_at, assigned_by_user_id)
    VALUES (
        v_collection_allocation_id,
        p_pokedex_position_id,
        v_basis,
        NOW(),
        CASE WHEN v_basis = 'USER_OVERRIDE' THEN auth.uid() ELSE NULL END
    )
    RETURNING
        collection_pokedex_position_assignment.collection_allocation_id,
        collection_pokedex_position_assignment.pokedex_position_id,
        collection_pokedex_position_assignment.assignment_basis,
        collection_pokedex_position_assignment.assigned_at;
END;
$$;

CREATE OR REPLACE FUNCTION public.remove_pokedex_position_assignment(
    p_physical_card_id UUID
)
RETURNS TABLE (
    collection_allocation_id UUID,
    pokedex_position_id UUID
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_collection_allocation_id UUID;
    v_collection_id            UUID;
    v_lifecycle_status         TEXT;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'authentication required';
    END IF;

    IF p_physical_card_id IS NULL THEN
        RAISE EXCEPTION 'REMOVE_POKEDEX_POSITION_ASSIGNMENT_MISSING_PARAMETER: p_physical_card_id é obrigatório.';
    END IF;

    -- Leitura inicial (sem lock) só para descobrir qual Collection travar
    -- primeiro (PAUSE, item 3 — ordem de domínio Collection -> Allocation).
    SELECT ca.id, ca.collection_id
      INTO v_collection_allocation_id, v_collection_id
      FROM public.collection_allocation ca
      JOIN public.collection col ON col.id = ca.collection_id
     WHERE ca.physical_card_id = p_physical_card_id
       AND col.owner_user_id = auth.uid();

    IF NOT FOUND THEN
        RAISE EXCEPTION 'REMOVE_POKEDEX_POSITION_ASSIGNMENT_NOT_ALLOCATED: physical_card não está alocado a uma Collection do chamador.';
    END IF;

    -- Lock real de Collection PRIMEIRO — ownership revalidada na própria
    -- WHERE do FOR UPDATE (padrão 5046/5047). Serializa contra
    -- archive_collection()/reactivate_collection() concorrente.
    SELECT col.lifecycle_status
      INTO v_lifecycle_status
      FROM public.collection col
     WHERE col.id = v_collection_id
       AND col.owner_user_id = auth.uid()
     FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'REMOVE_POKEDEX_POSITION_ASSIGNMENT_NOT_ALLOCATED: physical_card não está alocado a uma Collection do chamador.';
    END IF;

    IF v_lifecycle_status <> 'ACTIVE' THEN
        RAISE EXCEPTION 'REMOVE_POKEDEX_POSITION_ASSIGNMENT_COLLECTION_ARCHIVED: collection is archived — reactivate before removing assignment.';
    END IF;

    -- Só DEPOIS do lock de Collection, trava e revalida a própria
    -- Allocation (ordem: Collection -> Allocation, nunca invertida).
    SELECT ca.id
      INTO v_collection_allocation_id
      FROM public.collection_allocation ca
     WHERE ca.physical_card_id = p_physical_card_id
       AND ca.collection_id = v_collection_id
     FOR UPDATE OF ca;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'REMOVE_POKEDEX_POSITION_ASSIGNMENT_NOT_ALLOCATED: physical_card não está mais alocado a esta Collection (removido concorrentemente).';
    END IF;

    -- WHERE e RETURNING qualificados pelo nome da tabela (PAUSE, item 2):
    -- collection_allocation_id/pokedex_position_id bare colidiriam com os
    -- OUT-parameters do RETURNS TABLE sob plpgsql.variable_conflict='error'.
    RETURN QUERY
    DELETE FROM public.collection_pokedex_position_assignment
     WHERE collection_pokedex_position_assignment.collection_allocation_id = v_collection_allocation_id
    RETURNING
        collection_pokedex_position_assignment.collection_allocation_id,
        collection_pokedex_position_assignment.pokedex_position_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'REMOVE_POKEDEX_POSITION_ASSIGNMENT_NOT_FOUND: nenhuma Assignment existente para este physical_card.';
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_pokedex_position_primary_representative(
    p_collection_allocation_id UUID
)
RETURNS TABLE (
    collection_id UUID,
    pokedex_position_id UUID,
    collection_allocation_id UUID
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_collection_id       UUID;
    v_pokedex_position_id UUID;
    v_lifecycle_status    TEXT;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'authentication required';
    END IF;

    IF p_collection_allocation_id IS NULL THEN
        RAISE EXCEPTION 'SET_POKEDEX_POSITION_PRIMARY_REPRESENTATIVE_MISSING_PARAMETER: p_collection_allocation_id é obrigatório.';
    END IF;

    -- Leitura inicial (sem lock) só para descobrir qual Collection travar
    -- primeiro (PAUSE, item 3).
    SELECT ca.collection_id
      INTO v_collection_id
      FROM public.collection_pokedex_position_assignment a
      JOIN public.collection_allocation ca ON ca.id = a.collection_allocation_id
      JOIN public.collection col ON col.id = ca.collection_id
     WHERE a.collection_allocation_id = p_collection_allocation_id
       AND col.owner_user_id = auth.uid();

    IF NOT FOUND THEN
        RAISE EXCEPTION 'SET_POKEDEX_POSITION_PRIMARY_REPRESENTATIVE_ASSIGNMENT_NOT_FOUND: nenhuma Assignment do chamador para este collection_allocation_id.';
    END IF;

    -- Lock real de Collection PRIMEIRO — ownership revalidada na própria
    -- WHERE do FOR UPDATE (padrão 5046/5047).
    SELECT col.lifecycle_status
      INTO v_lifecycle_status
      FROM public.collection col
     WHERE col.id = v_collection_id
       AND col.owner_user_id = auth.uid()
     FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'SET_POKEDEX_POSITION_PRIMARY_REPRESENTATIVE_ASSIGNMENT_NOT_FOUND: nenhuma Assignment do chamador para este collection_allocation_id.';
    END IF;

    IF v_lifecycle_status <> 'ACTIVE' THEN
        RAISE EXCEPTION 'SET_POKEDEX_POSITION_PRIMARY_REPRESENTATIVE_COLLECTION_ARCHIVED: collection is archived.';
    END IF;

    -- Só DEPOIS do lock de Collection, revalida e trava a própria
    -- Assignment/Allocation (ordem: Collection -> Allocation).
    SELECT a.pokedex_position_id
      INTO v_pokedex_position_id
      FROM public.collection_pokedex_position_assignment a
      JOIN public.collection_allocation ca ON ca.id = a.collection_allocation_id
     WHERE a.collection_allocation_id = p_collection_allocation_id
       AND ca.collection_id = v_collection_id
     FOR UPDATE OF ca;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'SET_POKEDEX_POSITION_PRIMARY_REPRESENTATIVE_ASSIGNMENT_NOT_FOUND: Assignment removida concorrentemente.';
    END IF;

    -- RETURNING qualificada pelo nome da tabela (PAUSE, item 2, 6125 v1.2 —
    -- mantida sem mudança). ÚNICA correção desta migration: ON CONFLICT
    -- passa a referenciar o PK pelo nome da constraint em vez da lista de
    -- colunas sem qualificação, eliminando a ambiguidade 42702 contra os
    -- OUT-parameters de mesmo nome do RETURNS TABLE (6126).
    RETURN QUERY
    INSERT INTO public.collection_pokedex_position_primary_representative
        (collection_id, pokedex_position_id, collection_allocation_id)
    VALUES (v_collection_id, v_pokedex_position_id, p_collection_allocation_id)
    ON CONFLICT ON CONSTRAINT pk_collection_pokedex_position_primary_representative
    DO UPDATE SET collection_allocation_id = EXCLUDED.collection_allocation_id
    RETURNING
        collection_pokedex_position_primary_representative.collection_id,
        collection_pokedex_position_primary_representative.pokedex_position_id,
        collection_pokedex_position_primary_representative.collection_allocation_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.clear_pokedex_position_primary_representative(
    p_collection_id UUID,
    p_pokedex_position_id UUID
)
RETURNS TABLE (
    collection_id UUID,
    pokedex_position_id UUID
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_lifecycle_status TEXT;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'authentication required';
    END IF;

    IF p_collection_id IS NULL OR p_pokedex_position_id IS NULL THEN
        RAISE EXCEPTION 'CLEAR_POKEDEX_POSITION_PRIMARY_REPRESENTATIVE_MISSING_PARAMETER: p_collection_id e p_pokedex_position_id são obrigatórios.';
    END IF;

    SELECT col.lifecycle_status INTO v_lifecycle_status
      FROM public.collection col
     WHERE col.id = p_collection_id
       AND col.owner_user_id = auth.uid()
     FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'CLEAR_POKEDEX_POSITION_PRIMARY_REPRESENTATIVE_NOT_OWNED: collection not found or not owned by caller.';
    END IF;

    IF v_lifecycle_status <> 'ACTIVE' THEN
        RAISE EXCEPTION 'CLEAR_POKEDEX_POSITION_PRIMARY_REPRESENTATIVE_COLLECTION_ARCHIVED: collection is archived.';
    END IF;

    RETURN QUERY
    DELETE FROM public.collection_pokedex_position_primary_representative pr
     WHERE pr.collection_id = p_collection_id
       AND pr.pokedex_position_id = p_pokedex_position_id
    RETURNING pr.collection_id, pr.pokedex_position_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'CLEAR_POKEDEX_POSITION_PRIMARY_REPRESENTATIVE_NOT_FOUND: nenhum Primary Representative existente para esta Position.';
    END IF;
END;
$$;

drop function public.get_collection_activity(uuid, bigint, integer);

do $post$
begin
  if (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.set_pokedex_position_assignment(uuid, uuid, boolean)')) is distinct from '8c572182a03025503e993e5ecc25e07a'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.remove_pokedex_position_assignment(uuid)')) is distinct from '26ef2d5da3312661111df0194dfc8ba2'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.set_pokedex_position_primary_representative(uuid)')) is distinct from '6353dffe6c3877967997033dcc2bfd4c'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.clear_pokedex_position_primary_representative(uuid, uuid)')) is distinct from 'eeede3a5b871fbf07f81eb59ecea932f' then
    raise exception 'POSTCHECK R5395: funções do titular não voltaram ao canônico';
  end if;
  if to_regprocedure('public.get_collection_activity(uuid, bigint, integer)') is not null then
    raise exception 'POSTCHECK R5395: leitura ainda presente';
  end if;
end;
$post$;

commit;
