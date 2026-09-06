/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 6124 - Create remove_pokedex_position_assignment() Function
Versão......: 1.2 (STAGING — NÃO EXECUTADO — correção de
               PAUSE-SQL-DIRECT-AUDIT-01, itens 2 e 3; renumerada de
               6123 para 6124 em RENUMBER-FIX-STAGING-01, para abrir
               espaço para a migration incremental de correção dos
               objetos já aplicados, que passa a ser 6123)
Status......: PROPOSTO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-05 (staging em COLLECTIONS-POKEDEX-FATIA-D-STAGING-01;
               revisado em PAUSE-SQL-DIRECT-AUDIT-01 e
               RENUMBER-FIX-STAGING-01)

Correção v1.1 (PAUSE-SQL-DIRECT-AUDIT-01):
- Item 2 (RETURNING ambíguo): confirmado que plpgsql.variable_conflict =
  'error' está ativo no projeto real. O DELETE original referenciava
  collection_allocation_id de forma NÃO qualificada tanto na WHERE quanto
  na RETURNING — ambíguo contra os OUT-parameters do RETURNS TABLE, que
  têm exatamente os mesmos nomes. Corrigido qualificando pelo NOME DA
  TABELA (padrão canônico de 5046/5047), tanto na WHERE quanto na
  RETURNING.
- Item 3 (lock/concorrência): a versão 1.0 travava a linha de
  collection_allocation ANTES de qualquer lock em collection — nenhuma
  proteção real contra archive_collection() concorrente. Corrigido para
  travar Collection PRIMEIRO (FOR UPDATE, ownership na própria WHERE,
  padrão 5046/5047), só then travar e revalidar a Allocation — ordem de
  domínio Collection -> Allocation, nunca invertida.

Descrição...:
Remove a Pokédex Position Assignment de um Physical Card sem desalocá-
lo da Collection — distinto de deallocate_physical_cards_from_
collection() (2C), que remove a Allocation inteira (e por CASCADE,
Query 6117, a Assignment junto). Aqui a Allocation permanece; só o
vínculo com a Position é desfeito.

CASCADE já cobre a limpeza de um Primary Representative que apontasse
para esta Assignment (Query 6120) — nenhuma lógica adicional necessária
nesta função.

Pré-requisitos:
- Query 6117/6118 - Collection Pokédex Position Assignment + Triggers.
================================================================
*/

BEGIN;

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

COMMENT ON FUNCTION public.remove_pokedex_position_assignment(UUID) IS
    'Remove a Pokédex Position Assignment de um Physical Card sem desalocá-lo da Collection. CASCADE (Query 6120) remove um Primary Representative órfão automaticamente. Ownership via auth.uid(); Collection precisa estar ACTIVE.';

REVOKE ALL ON FUNCTION public.remove_pokedex_position_assignment(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.remove_pokedex_position_assignment(UUID) FROM anon;
GRANT EXECUTE ON FUNCTION public.remove_pokedex_position_assignment(UUID) TO authenticated;

COMMIT;
