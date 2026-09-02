/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5039 - Create delete_collection Function
Versão......: 1.3
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-31 (aplicado em 2026-09-01,
               COLLECTIONS-PHYSICAL-INCREMENT-02B-IMPLEMENTATION-01;
               estendida em 2026-09-01, aplicada em 2026-09-02, via
               Query 5048, COLLECTIONS-PHYSICAL-INCREMENT-02C-
               IMPLEMENTATION-01)

Descrição...:
Cria delete_collection(p_collection_id) — Owner-only, DELETE físico.

C-13 exige zero Physical Cards associadas para permitir exclusão.
Correção documental explícita (COLLECTIONS-PHYSICAL-INCREMENT-02B-
MODELING-FINAL-01, item 7): a nota original desta proposta mencionava
incorretamente uma futura coluna physical_card.collection_id — ESSA
COLUNA NUNCA VAI EXISTIR. A associação Collection<->Physical Card,
quando Collection Allocation (Incremento 2C, ainda não modelado
fisicamente) existir, será representada por uma entidade própria
(collection_allocation), não por uma coluna em physical_card. C-13
será protegido no 2C por collection_allocation.collection_id — via
FK ... REFERENCES collection(id) ON DELETE RESTRICT (garantia
estrutural declarativa) e/ou checagem explícita na própria RPC de
delete, a decidir na rodada do 2C. Nenhuma menção a physical_card.
collection_id deve ser registrada como pendência futura.

Neste incremento (2B), sem collection_allocation existente, a
exclusão é incondicional para o próprio Owner — a pré-condição de
C-13 está vacuamente satisfeita porque a entidade que a tornaria
relevante ainda não existe. Não é um workaround: é a ausência real da
dependência.

CORREÇÃO DE REFERÊNCIA AMBÍGUA (COLLECTIONS-PHYSICAL-INCREMENT-02B-
IMPLEMENTATION-01). Mesmo problema de update_collection_metadata()
(Query 5035, ver seu cabeçalho): `RETURNS TABLE (id UUID)` cria uma
variável PL/pgSQL `id` que colide com `collection.id` no WHERE do
DELETE. Qualificado com `collection.`. Nenhuma mudança de
comportamento.

Regras de Negócio:
- SET search_path = '', referências totalmente qualificadas;
- auth.uid() IS NULL rejeitado explicitamente;
- DELETE ... WHERE collection.id = p_collection_id AND
  collection.owner_user_id = auth.uid();
- 0 linhas afetadas -> RAISE EXCEPTION 'collection not found or not
  owned by caller' (não distingue "não existe" de "não é sua");
- retorno explícito (id) — confirma qual Collection foi removida;
- EXECUTE revogado de PUBLIC/anon; concedido apenas a authenticated.

EXTENSÃO (Query 5048, COLLECTIONS-PHYSICAL-INCREMENT-02C-
IMPLEMENTATION-01) — cumpre a revisão obrigatória acima. A garantia
estrutural real de C-13 já existe de forma declarativa desde a Query
5040 (collection_allocation.collection_id REFERENCES collection(id)
ON DELETE RESTRICT); esta extensão adiciona um pré-check amigável
antes do DELETE, para que o Owner receba uma mensagem de domínio
compreensível em vez do erro cru de violação de FK. Mensagem
deliberadamente NÃO sugere archive_collection() como alternativa —
Collections ARCHIVED preservam todas as suas Allocations (C-37), então
arquivar não resolve o bloqueio; a única saída real é
deallocate_physical_cards_from_collection() (Query 5047) até zerar as
Allocations. Ownership é confirmada primeiro, via PERFORM ... FOR
UPDATE com owner_user_id = auth.uid() já no WHERE (mesmo padrão de
não-enumeração de 5046/5047) — só depois desse gate roda o pré-check
de C-13, já garantidamente sobre uma Collection do próprio caller. Uma
Collection inexistente e uma Collection de outro Owner (com ou sem
Allocations) produzem exatamente a mesma mensagem genérica, na mesma
etapa — nenhuma distinção observável entre os dois casos.

STATUS DESTA QUERY: CONFIRMADO EXECUTADO.
================================================================
*/

CREATE OR REPLACE FUNCTION public.delete_collection(p_collection_id UUID)
RETURNS TABLE (id UUID)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'authentication required';
    END IF;

    PERFORM 1
    FROM public.collection col
    WHERE col.id = p_collection_id
      AND col.owner_user_id = auth.uid()
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'collection not found or not owned by caller';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.collection_allocation ca
        WHERE ca.collection_id = p_collection_id
    ) THEN
        RAISE EXCEPTION 'collection has allocated physical cards — deallocate them before deleting';
    END IF;

    RETURN QUERY
    DELETE FROM public.collection
    WHERE collection.id = p_collection_id AND collection.owner_user_id = auth.uid()
    RETURNING collection.id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'collection not found or not owned by caller';
    END IF;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.delete_collection(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_collection(uuid) TO authenticated;
