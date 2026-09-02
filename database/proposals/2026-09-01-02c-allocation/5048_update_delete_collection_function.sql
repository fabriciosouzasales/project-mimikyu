/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5048 - Update delete_collection Function (PROPOSTA)
Versão......: 1.3 (CREATE OR REPLACE sobre a função criada em 5039,
               já CONFIRMADO EXECUTADO/CANÔNICA em database/schema —
               5039 permanece intocada; esta Query é uma correção
               posterior, mesmo padrão de 5044 e de
               5035_fix_ambiguous_id_reference/
               5036_fix_ambiguous_id_reference)
Status......: PROPOSTA — NÃO EXECUTADA
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-01 (COLLECTIONS-PHYSICAL-INCREMENT-02C-MODELING-
               REVISION-01, item 6 → -FINAL-01, item 7 →
               -STAGING-REVISION-01, item 2 — pre-check owner-scoped)

Descrição...:
Cumpre a revisão obrigatória já anunciada no próprio cabeçalho de 5039
("Revisão obrigatória no Incremento 2C: adicionar guarda de C-13 via
collection_allocation antes de qualquer promoção de 2C a CANÔNICA").

A garantia estrutural real de C-13 ("Collection só pode ser excluída
com zero Physical Cards associadas") já existe de forma declarativa
desde a Query 5040 — collection_allocation.collection_id REFERENCES
collection(id) ON UPDATE RESTRICT ON DELETE RESTRICT. Um DELETE em
collection com Allocations existentes falharia de qualquer forma, com
o erro cru do Postgres (violação de FK). Esta Query NÃO substitui essa
garantia — apenas adiciona um pré-check amigável antes do DELETE, para
que o Owner receba uma mensagem de domínio compreensível em vez de um
erro de FK. "Integridade não pode depender da RPC" (COLLECTIONS-
PHYSICAL-INCREMENT-02C-MODELING-REVISION-01, item 6) — a RPC é
conveniência de UX, o RESTRICT é a fonte real da garantia.

Mensagem deliberadamente NÃO sugere archive_collection() como
alternativa — Collections ARCHIVED preservam todas as suas Allocations
(C-37), então arquivar não resolve o bloqueio de exclusão; sugerir
isso induziria o Owner a um caminho sem saída. A única saída real é
deallocate_physical_cards_from_collection() (Query 5047) até zerar as
Allocations, e só então delete_collection().

CORREÇÃO (COLLECTIONS-PHYSICAL-INCREMENT-02C-STAGING-REVISION-01, item
2 — pre-check owner-scoped). A v1.2 consultava collection_allocation
ANTES de comprovar que a Collection pertencia ao caller — um caller
autenticado podia chamar delete_collection(<uuid de Collection alheia>)
e, pela mensagem de erro recebida, inferir se aquela Collection tinha
ou não Physical Cards alocadas ('collection has allocated physical
cards...' revela existência+composição; 'collection not found or not
owned by caller' não revela nada). Um vazamento de informação sobre um
recurso que não pertence ao caller, mesmo sem nunca expor os dados em
si. Corrigido: a ownership agora é confirmada primeiro, via
PERFORM ... FOR UPDATE com owner_user_id = auth.uid() já no WHERE
(mesmo padrão de não-enumeração aplicado em 5046/5047) — só depois de
passar por esse gate é que o pré-check de C-13 roda, e nesse ponto ele
só pode estar operando sobre uma Collection que já se provou ser do
próprio caller. Uma Collection inexistente e uma Collection de outro
Owner (com ou sem Allocations) produzem exatamente a mesma mensagem
genérica, na mesma etapa.

Regras de Negócio (idênticas a 5039 + guarda de ownership antecipada +
pré-check de C-13 owner-scoped):
- SET search_path = '', referências totalmente qualificadas;
- auth.uid() IS NULL rejeitado explicitamente;
- PERFORM 1 FROM collection WHERE id = p_collection_id AND
  owner_user_id = auth.uid() FOR UPDATE — confirma ownership e trava a
  linha antes de qualquer outra checagem; NOT FOUND -> RAISE EXCEPTION
  'collection not found or not owned by caller' (mesma mensagem para
  inexistente e para alheia);
- só então, pré-check: IF EXISTS (SELECT 1 FROM collection_allocation
  WHERE collection_id = p_collection_id) THEN RAISE EXCEPTION — já
  garantidamente sobre uma Collection do próprio caller;
- DELETE ... WHERE id = p_collection_id AND owner_user_id = auth.uid()
  — filtro duplicado por defesa em profundidade (a linha já está
  travada e confirmada pelo PERFORM acima; owner_user_id é imutável
  por 5032, então não pode ter mudado sob o lock); NOT FOUND nesse
  ponto seria inesperado, mas ainda cai na mesma mensagem genérica;
- retorno explícito (id) — inalterado;
- EXECUTE revogado de PUBLIC/anon; concedido apenas a authenticated
  (grants já existentes em 5039, não reemitidos aqui pois GRANT/REVOKE
  não são afetados por CREATE OR REPLACE FUNCTION).

STATUS DESTA QUERY: PROPOSTA — NÃO EXECUTADA.
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
