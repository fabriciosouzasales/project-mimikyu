/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5395 - Auditoria explícita das operações do titular na Pokédex e leitura do
              histórico por coleção (V1-13 · E3-6 / S4-b, D-E3-8)
Versão......: 1.1 (2026-11-27, `S4-b/5395 TRANSACTIONAL AUDIT MARKER REVIEW-01`; 1.0: PREPARATION-01)
Status......: PROPOSTA — NÃO EXECUTADA. GERADA por build_5395.py a partir do texto canônico
              implantado. Execução só com PRE aprovado, expectativas de escritores,
              auditoria independente e autorização expressa, pelo executor por arquivo.
Autor.......: Fabrício Sales / Claude
Substitui...: CREATE OR REPLACE das 4 funções do titular (6123 set_pokedex_position_assignment,
              6124 remove_pokedex_position_assignment, 6126 set_pokedex_position_primary_
              representative, 6125 clear_pokedex_position_primary_representative): mesmo
              corpo, mesma assinatura, mesmo retorno, mesmos privilégios, MAIS blocos
              marcados [5395+]…[5395-] que, com a capacidade aberta para a sessão
              (v1_13_capability_open), chamam collection_activity_open antes da escrita e
              collection_activity_record_pokedex depois da escrita efetiva. Com a barreira
              CLOSED o caminho é exatamente o de hoje (nenhum evento).
Cria........: get_collection_activity(uuid, bigint, integer) — histórico da coleção para o
              titular e participantes ACTIVE (C-241), sem identificadores patrimoniais.
Fora........: referências de espécie no histórico do fichário (5258/5383) → 5396 (fluxo do
              fichário, outro conjunto de funções; decisão registrada no README §10).
Reversão....: ROLLBACK_5395.sql (restaura o texto canônico das 4 funções e remove a leitura;
              não apaga eventos).
================================================================
*/

begin;
set local lock_timeout = '3s';

do $pre$
begin
  if (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.v1_13_assert_capability()')) is distinct from 'e4f710904f50e6e8c3f1d8e2337639e0'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.v1_13_capability_open()')) is distinct from '32e2f636361732b497e8401e50f0bbe0'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.collection_activity_open(uuid)')) is distinct from 'd5f52bf5a2a29f1a4d8279c560b97043'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.collection_activity_record_pokedex(uuid, text, uuid, uuid, uuid, uuid, text, boolean)')) is distinct from 'c7245940a39d7c2a3d0674deb3be06dd'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.collection_share_role(uuid)')) is distinct from 'efdb495b5b703e9f093eb0f49a1d0a5d' then
    raise exception 'PRECHECK 5395: barreira, primitivas da 5394 ou collection_share_role divergentes';
  end if;
  if (select s.mode from public.v1_13_barrier_state s where s.id = 1) is distinct from 'CLOSED'
     or (select count(*) from public.v1_13_barrier_identity) <> 0 then
    raise exception 'PRECHECK 5395: barreira não está CLOSED';
  end if;
  if (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.set_pokedex_position_assignment(uuid, uuid, boolean)')) is distinct from '8c572182a03025503e993e5ecc25e07a'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.remove_pokedex_position_assignment(uuid)')) is distinct from '26ef2d5da3312661111df0194dfc8ba2'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.set_pokedex_position_primary_representative(uuid)')) is distinct from '6353dffe6c3877967997033dcc2bfd4c'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.clear_pokedex_position_primary_representative(uuid, uuid)')) is distinct from 'eeede3a5b871fbf07f81eb59ecea932f' then
    raise exception 'PRECHECK 5395: ESTADO DIVERGENTE — funções do titular diferem do canônico (6123/6124/6126/6125)';
  end if;
  if to_regprocedure('public.editor_move_pokedex_copy(uuid, text, uuid, uuid, boolean)') is null
     or to_regclass('public.collection_activity_event') is null
     or to_regclass('public.user_profile') is null then
    raise exception 'PRECHECK 5395: dependência ausente (5392, 5394 ou user_profile)';
  end if;
  if to_regprocedure('public.get_collection_activity(uuid, bigint, integer)') is not null then
    raise exception 'PRECHECK 5395: JÁ APLICADA ou ESTADO DIVERGENTE';
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
-- [5395+]
    v_audit                    BOOLEAN := false;
    v_rep_cleared              BOOLEAN := false;
-- [5395-]
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

-- [5395+]
    v_audit := public.v1_13_capability_open();
    IF v_audit THEN
        IF v_existing_position_id IS NOT NULL THEN
            SELECT EXISTS (SELECT 1 FROM public.collection_pokedex_position_primary_representative r
                            WHERE r.collection_allocation_id = v_collection_allocation_id) INTO v_rep_cleared;
        END IF;
        PERFORM public.collection_activity_open(v_collection_id);
    END IF;
-- [5395-]
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
-- [5395+]
    IF v_audit THEN
        PERFORM public.collection_activity_record_pokedex(v_collection_id,
            CASE WHEN v_existing_position_id IS NULL THEN 'POKEDEX_POSITION_ASSIGNED' ELSE 'POKEDEX_POSITION_MOVED' END,
            v_collection_allocation_id, v_existing_position_id, p_pokedex_position_id, NULL, v_basis,
            CASE WHEN v_existing_position_id IS NULL THEN NULL ELSE v_rep_cleared END);
    END IF;
-- [5395-]
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
-- [5395+]
    v_audit                    BOOLEAN := false;
    v_from                     UUID;
    v_rep_cleared              BOOLEAN := false;
-- [5395-]
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
-- [5395+]
    v_audit := public.v1_13_capability_open();
    IF v_audit THEN
        SELECT a.pokedex_position_id INTO v_from
          FROM public.collection_pokedex_position_assignment a
         WHERE a.collection_allocation_id = v_collection_allocation_id;
        SELECT EXISTS (SELECT 1 FROM public.collection_pokedex_position_primary_representative r
                        WHERE r.collection_allocation_id = v_collection_allocation_id) INTO v_rep_cleared;
        PERFORM public.collection_activity_open(v_collection_id);
    END IF;
-- [5395-]
    RETURN QUERY
    DELETE FROM public.collection_pokedex_position_assignment
     WHERE collection_pokedex_position_assignment.collection_allocation_id = v_collection_allocation_id
    RETURNING
        collection_pokedex_position_assignment.collection_allocation_id,
        collection_pokedex_position_assignment.pokedex_position_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'REMOVE_POKEDEX_POSITION_ASSIGNMENT_NOT_FOUND: nenhuma Assignment existente para este physical_card.';
    END IF;
-- [5395+]
    IF v_audit THEN
        PERFORM public.collection_activity_record_pokedex(v_collection_id, 'POKEDEX_POSITION_REMOVED',
            v_collection_allocation_id, v_from, NULL, NULL, NULL, v_rep_cleared);
    END IF;
-- [5395-]
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
-- [5395+]
    v_audit               BOOLEAN := false;
    v_prev                UUID;
-- [5395-]
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
-- [5395+]
    v_audit := public.v1_13_capability_open();
    IF v_audit THEN
        SELECT r.collection_allocation_id INTO v_prev
          FROM public.collection_pokedex_position_primary_representative r
         WHERE r.collection_id = v_collection_id AND r.pokedex_position_id = v_pokedex_position_id
         FOR UPDATE;
        -- Sem mudança efetiva: nenhuma escrita, nenhuma marcação, nenhum evento (como o UNCHANGED da 5392).
        -- Evita a marcação residual na transação e o evento derivado do UPDATE do upsert.
        IF v_prev IS NOT DISTINCT FROM p_collection_allocation_id THEN
            RETURN QUERY SELECT v_collection_id, v_pokedex_position_id, p_collection_allocation_id;
            RETURN;
        END IF;
        PERFORM public.collection_activity_open(v_collection_id);
    END IF;
-- [5395-]
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
-- [5395+]
    IF v_audit AND v_prev IS DISTINCT FROM p_collection_allocation_id THEN
        PERFORM public.collection_activity_record_pokedex(v_collection_id,
            CASE WHEN v_prev IS NULL THEN 'POKEDEX_REPRESENTATIVE_SET' ELSE 'POKEDEX_REPRESENTATIVE_REPLACED' END,
            p_collection_allocation_id, NULL, v_pokedex_position_id, v_prev, NULL, NULL);
    END IF;
-- [5395-]
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
-- [5395+]
    v_audit            BOOLEAN := false;
    v_prev             UUID;
-- [5395-]
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

-- [5395+]
    v_audit := public.v1_13_capability_open();
    IF v_audit THEN
        SELECT r.collection_allocation_id INTO v_prev
          FROM public.collection_pokedex_position_primary_representative r
         WHERE r.collection_id = p_collection_id AND r.pokedex_position_id = p_pokedex_position_id
         FOR UPDATE;
        PERFORM public.collection_activity_open(p_collection_id);
    END IF;
-- [5395-]
    RETURN QUERY
    DELETE FROM public.collection_pokedex_position_primary_representative pr
     WHERE pr.collection_id = p_collection_id
       AND pr.pokedex_position_id = p_pokedex_position_id
    RETURNING pr.collection_id, pr.pokedex_position_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'CLEAR_POKEDEX_POSITION_PRIMARY_REPRESENTATIVE_NOT_FOUND: nenhum Primary Representative existente para esta Position.';
    END IF;
-- [5395+]
    IF v_audit THEN
        PERFORM public.collection_activity_record_pokedex(p_collection_id, 'POKEDEX_REPRESENTATIVE_RESTORED',
            NULL, NULL, p_pokedex_position_id, v_prev, NULL, NULL);
    END IF;
-- [5395-]
END;
$$;

create function public.get_collection_activity(
  p_collection_id uuid,
  p_before_id     bigint  default null,
  p_limit         integer default 50
)
returns table (
  event_id           bigint,
  occurred_at        timestamptz,
  event_type         text,
  origin             text,
  actor_role         text,
  actor_display_name text,
  summary            jsonb
)
language plpgsql
stable
security definer
set search_path = ''
as $fn$
#variable_conflict use_column
declare
  v_role text;
  v_at   timestamptz;
  v_id   bigint;
begin
  perform public.v1_13_assert_capability();  -- barreira: CLOSED → CAPABILITY_NOT_ENABLED (42501)
  if p_limit is null or p_limit < 1 or p_limit > 100 then
    raise exception 'INVALID_PAGE' using errcode = '22023';
  end if;
  if p_collection_id is null then
    return;
  end if;
  -- Titular ou participante ACTIVE (EDITOR lê como VIEWER, 5302); removido, recusado ou pendente → zero linhas.
  v_role := public.collection_share_role(p_collection_id);
  if v_role is null or v_role not in ('OWNER', 'VIEWER') then
    return;
  end if;
  if p_before_id is not null then
    select e.occurred_at, e.id into v_at, v_id
    from public.collection_activity_event e
    where e.id = p_before_id and e.collection_id = p_collection_id;
    if v_id is null then
      return;
    end if;
  end if;
  return query
  select e.id, e.occurred_at, e.event_type, e.origin, e.actor_role,
         case when e.actor_user_id is null then null
              else (select up.display_name::text from public.user_profile up where up.id = e.actor_user_id) end,
         e.summary
  from public.collection_activity_event e
  where e.collection_id = p_collection_id
    and (v_id is null or (e.occurred_at, e.id) < (v_at, v_id))
  order by e.occurred_at desc, e.id desc
  limit p_limit;
end;
$fn$;

comment on function public.get_collection_activity(uuid, bigint, integer) is
  'V1-13 E3-6/S4-b (5395): histórico da coleção (Pokédex) para o titular e participantes ACTIVE (C-241); nome público do autor resolvido na leitura; sem exemplar, alocação, local, condição ou valores. Sem acesso → zero linhas.';
revoke all on function public.get_collection_activity(uuid, bigint, integer) from public, anon, service_role;
grant execute on function public.get_collection_activity(uuid, bigint, integer) to authenticated;

do $post$
declare
  f oid;
begin
  if (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.set_pokedex_position_assignment(uuid, uuid, boolean)')) is distinct from 'ce63a458c1e79024dd512e60726a4004'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.remove_pokedex_position_assignment(uuid)')) is distinct from '2502eb25191383cc00aac62969b2671d'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.set_pokedex_position_primary_representative(uuid)')) is distinct from '1bbf1a6a5fe0bafedadbb7543f6d7951'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.clear_pokedex_position_primary_representative(uuid, uuid)')) is distinct from '2bf25d3d21e6ab06ccb50269bff1502b' then
    raise exception 'POSTCHECK 5395: funções do titular fora do texto instrumentado';
  end if;
  foreach f in array array[to_regprocedure('public.set_pokedex_position_assignment(uuid, uuid, boolean)'),
                           to_regprocedure('public.remove_pokedex_position_assignment(uuid)'),
                           to_regprocedure('public.set_pokedex_position_primary_representative(uuid)'),
                           to_regprocedure('public.clear_pokedex_position_primary_representative(uuid, uuid)')] loop
    if (select p.prosecdef from pg_catalog.pg_proc p where p.oid = f) is not true
       or (select p.proconfig from pg_catalog.pg_proc p where p.oid = f) is distinct from array['search_path=""']
       or pg_catalog.has_function_privilege('authenticated', f, 'EXECUTE') is not true
       or pg_catalog.has_function_privilege('anon', f, 'EXECUTE') is not false
       or exists (select 1 from pg_catalog.pg_proc p cross join lateral pg_catalog.aclexplode(p.proacl) a
                  where p.oid = f and a.grantee = 0) then
      raise exception 'POSTCHECK 5395: privilégios ou segurança de função do titular alterados (%)', f::regprocedure;
    end if;
  end loop;
  f := to_regprocedure('public.get_collection_activity(uuid, bigint, integer)');
  if f is null
     or (select p.prosecdef from pg_catalog.pg_proc p where p.oid = f) is not true
     or (select p.proconfig from pg_catalog.pg_proc p where p.oid = f) is distinct from array['search_path=""']
     or (select p.provolatile from pg_catalog.pg_proc p where p.oid = f) is distinct from 's'
     or pg_catalog.has_function_privilege('authenticated', f, 'EXECUTE') is not true
     or pg_catalog.has_function_privilege('anon', f, 'EXECUTE') is not false
     or pg_catalog.has_function_privilege('service_role', f, 'EXECUTE') is not false then
    raise exception 'POSTCHECK 5395: leitura do histórico fora do estado esperado';
  end if;
  if exists (select 1 from public.collection_activity_event) then
    raise exception 'POSTCHECK 5395: a migration não deveria gerar eventos';
  end if;
  if (select s.mode from public.v1_13_barrier_state s where s.id = 1) is distinct from 'CLOSED'
     or (select count(*) from public.v1_13_barrier_identity) <> 0 then
    raise exception 'POSTCHECK 5395: barreira não está CLOSED';
  end if;
end;
$post$;

commit;
