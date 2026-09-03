/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5082 - Create replace_master_set_scope Function
Versão......: 1.1
Status......: PROPOSTA — NÃO EXECUTADA
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-02 (COLLECTIONS-PHYSICAL-INCREMENT-02F-STAGING-01 → -STAGING-REVISION-01)

Descrição...:
Única RPC de mutação de Scope enquanto a Collection já está
`MASTER_SET` (decisão fechada em MODELING-REVISION-01 item 5:
`add_master_set_variants()`/`remove_master_set_variants()` deferidos,
não implementados nesta rodada). Owner-only. Permitida SOMENTE quando
`completion_policy = 'MASTER_SET' AND lifecycle_status = 'ACTIVE'` —
contrato fechado em MODELING-REVISION-01 item 3: Scope de uma
Collection `STANDARD_SET` não é editável diretamente nesta V1 (para
isso, usar `set_collection_completion_policy_to_master_set()`, 5080,
que aceita o mesmo `p_card_variant_ids` e já aplica a mesma difusão).

Semântica obrigatória (MODELING-REVISION-01 item 1): VALIDATE ALL ->
KEEP -> ADD -> REMOVE, via `apply_master_set_scope_diff()` (5079) —
rotina compartilhada com `5080`, nunca duas implementações paralelas
do mesmo algoritmo. KEEP nunca sofre `UPDATE`/`DELETE`/`INSERT`.
Qualquer `card_variant_id` inválido (inexistente, fora do Card Set
referenciado, duplicado, malformado ou de formato errado) aborta a
chamada inteira, zero mudanças — validação acontece integralmente
antes de qualquer escrita, dentro de `5079`. Set-based, atômico.

Nota de esclarecimento (STAGING-REVISION-01 item 13): "VALIDATE ALL ->
KEEP -> ADD -> REMOVE" descreve a ORDEM SEMÂNTICA do contrato, não uma
ordem física obrigatória de statements dentro de `apply_master_set_
scope_diff()`. O `DELETE` de REMOVE roda fisicamente antes do `INSERT`
de ADD ali dentro — permitido porque os constraint triggers de `5076`/
`5077` são `DEFERRABLE INITIALLY DEFERRED`: o Scope nunca é checado
"vazio" nesse instante intermediário, só no momento da checagem
diferida (COMMIT). O único invariante real é: validação 100% completa
antes de qualquer escrita, e KEEP permanece intocado do início ao fim.

Não-enumeração: `SELECT ... FOR UPDATE WHERE owner_user_id =
(select auth.uid())` no `WHERE`.

SECURITY DEFINER, `SET search_path = ''`, `EXECUTE` revogado de
`PUBLIC`/`anon`, concedido só a `authenticated`.

STATUS DESTA QUERY: PROPOSTA — NÃO EXECUTADA.
================================================================
*/

CREATE OR REPLACE FUNCTION public.replace_master_set_scope(
    p_collection_id    UUID,
    p_card_variant_ids JSONB
)
RETURNS TABLE (
    collection_id        UUID,
    completion_policy     TEXT,
    scope_added_count     INTEGER,
    scope_removed_count   INTEGER,
    scope_kept_count      INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_collection    public.collection%ROWTYPE;
    v_added_count   INTEGER;
    v_removed_count INTEGER;
    v_kept_count    INTEGER;
BEGIN
    IF (select auth.uid()) IS NULL THEN
        RAISE EXCEPTION 'authentication required'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    SELECT c.* INTO v_collection
    FROM public.collection c
    WHERE c.id = p_collection_id
      AND c.owner_user_id = (select auth.uid())
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'collection not found'
            USING ERRCODE = 'no_data_found';
    END IF;

    IF v_collection.lifecycle_status <> 'ACTIVE' THEN
        RAISE EXCEPTION 'collection is archived — replace_master_set_scope is not permitted'
            USING ERRCODE = 'check_violation';
    END IF;

    IF v_collection.completion_policy <> 'MASTER_SET' THEN
        RAISE EXCEPTION 'replace_master_set_scope requires completion_policy = MASTER_SET (collection % is %); use set_collection_completion_policy_to_master_set() to activate it with a scope', p_collection_id, v_collection.completion_policy
            USING ERRCODE = 'check_violation';
    END IF;

    SELECT added_count, removed_count, kept_count
      INTO v_added_count, v_removed_count, v_kept_count
    FROM public.apply_master_set_scope_diff(p_collection_id, p_card_variant_ids);

    RETURN QUERY
    SELECT p_collection_id, v_collection.completion_policy, v_added_count, v_removed_count, v_kept_count;
END;
$$;

REVOKE ALL ON FUNCTION public.replace_master_set_scope(uuid, jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.replace_master_set_scope(uuid, jsonb) FROM anon;
GRANT EXECUTE ON FUNCTION public.replace_master_set_scope(uuid, jsonb) TO authenticated;
