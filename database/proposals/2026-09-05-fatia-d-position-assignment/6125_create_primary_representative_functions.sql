/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 6125 - Create Primary Representative Functions
Versão......: 1.2 (STAGING — NÃO EXECUTADO — correção de
               PAUSE-SQL-DIRECT-AUDIT-01, itens 2 e 3, aplicada só a
               set_pokedex_position_primary_representative; renumerada
               de 6124 para 6125 em RENUMBER-FIX-STAGING-01, para abrir
               espaço para a migration incremental dos objetos já
               aplicados (6123) e para remove_pokedex_position_
               assignment() (6124))
Status......: PROPOSTO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-05 (staging em COLLECTIONS-POKEDEX-FATIA-D-STAGING-01;
               revisado em PAUSE-SQL-DIRECT-AUDIT-01 e
               RENUMBER-FIX-STAGING-01)

Correção v1.1 (PAUSE-SQL-DIRECT-AUDIT-01) — aplicada apenas a
set_pokedex_position_primary_representative:
- Item 2 (RETURNING ambíguo): a RETURNING do INSERT ... ON CONFLICT
  usava collection_id/pokedex_position_id/collection_allocation_id sem
  qualificação — ambíguo contra os OUT-parameters de mesmo nome do
  RETURNS TABLE, sob plpgsql.variable_conflict='error' (confirmado no
  projeto real). Corrigido qualificando pelo nome da tabela.
- Item 3 (lock/concorrência): a versão 1.0 travava a linha de
  collection_allocation (via FOR UPDATE OF ca) antes de qualquer lock em
  collection. Corrigido para travar Collection PRIMEIRO (ownership na
  própria WHERE do FOR UPDATE), só então revalidar e travar a Assignment/
  Allocation — ordem de domínio Collection -> Allocation.

clear_pokedex_position_primary_representative NÃO precisou de nenhuma
correção: já trava Collection diretamente por p_collection_id (parâmetro
de entrada, sem precisar descobrir a Collection por join primeiro) e já
qualifica sua RETURNING via alias (`pr.collection_id`, `pr.pokedex_
position_id`) — os dois pontos que motivaram esta rodada de correção já
estavam corretos aqui desde a v1.0.

Descrição...:
Duas funções de escrita para collection_pokedex_position_primary_
representative (Query 6120) — LDM-180. Opcional, nunca auto-criado por
nenhum outro caminho desta Fatia.

set_pokedex_position_primary_representative(p_collection_allocation_id):
resolve collection_id/pokedex_position_id a partir da Assignment
apontada (exigindo ownership), e faz UPSERT na PK (collection_id,
pokedex_position_id) — "replace" é o mesmo caminho que "set": se já
havia um Primary para aquela Position, ON CONFLICT DO UPDATE troca
qual Assignment é a Primary (dispara trg_010 da Query 6121 de novo,
que revalida a nova Assignment referenciada, e trg_020, que atualiza
updated_at).

clear_pokedex_position_primary_representative(p_collection_id,
p_pokedex_position_id): remove o Primary corrente, se houver. Não
exige que uma Assignment específica exista — só que o chamador seja
o Owner da Collection.

Ambas checam collection.lifecycle_status = 'ACTIVE' (LDM-185).

Pré-requisitos:
- Query 6117/6118 - Collection Pokédex Position Assignment + Triggers.
- Query 6120/6121 - Primary Representative Table + Trigger.
================================================================
*/

BEGIN;

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

    -- RETURNING qualificada pelo nome da tabela (PAUSE, item 2).
    RETURN QUERY
    INSERT INTO public.collection_pokedex_position_primary_representative
        (collection_id, pokedex_position_id, collection_allocation_id)
    VALUES (v_collection_id, v_pokedex_position_id, p_collection_allocation_id)
    ON CONFLICT (collection_id, pokedex_position_id)
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

COMMENT ON FUNCTION public.set_pokedex_position_primary_representative(UUID) IS
    'Define (ou substitui) o Primary Representative de uma Position, a partir de uma Assignment existente do chamador. UPSERT na PK (collection_id, pokedex_position_id) — replace é o mesmo caminho que set. Nunca afeta completion (LDM-181).';

COMMENT ON FUNCTION public.clear_pokedex_position_primary_representative(UUID, UUID) IS
    'Remove o Primary Representative corrente de uma Position, se houver. Não exige nenhuma Assignment específica — só ownership da Collection.';

REVOKE ALL ON FUNCTION public.set_pokedex_position_primary_representative(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.set_pokedex_position_primary_representative(UUID) FROM anon;
GRANT EXECUTE ON FUNCTION public.set_pokedex_position_primary_representative(UUID) TO authenticated;

REVOKE ALL ON FUNCTION public.clear_pokedex_position_primary_representative(UUID, UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.clear_pokedex_position_primary_representative(UUID, UUID) FROM anon;
GRANT EXECUTE ON FUNCTION public.clear_pokedex_position_primary_representative(UUID, UUID) TO authenticated;

COMMIT;
