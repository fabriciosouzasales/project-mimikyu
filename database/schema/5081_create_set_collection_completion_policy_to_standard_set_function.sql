/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5081 - Create set_collection_completion_policy_to_standard_set Function
Versão......: 2.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-02 (aplicado em 2026-09-02,
               COLLECTIONS-PHYSICAL-INCREMENT-02F-STAGING-01 →
               -STAGING-REVISION-01 → -IMPLEMENTATION-01)

Descrição...:
RPC de transição `MASTER_SET -> STANDARD_SET` (C-23/LDM-22). Owner-only,
`ACTIVE`-only. Preserva o Scope persistido INTEGRALMENTE — nenhum
`DELETE` em `collection_master_set_scope` nesta função. Nenhuma
alteração em Physical Card, Collection Allocation, Storage ou
Collection Reference (fora do escopo desta RPC por desenho — só
`collection.completion_policy` é escrito).

CORREÇÃO v2.0 (STAGING-REVISION-01, item 4 — BLOCKER): a v1.0 tratava
QUALQUER Collection `ACTIVE` como candidata a "idempotência" — o
`UPDATE` com guard `WHERE completion_policy = 'MASTER_SET'` afetava
zero linhas tanto para uma Collection já `STANDARD_SET` (idempotência
genuína, comportamento correto) quanto para uma Collection
`OPEN_CURATION`/`NONE` (elegibilidade ERRADA — essa Collection nunca
deveria ter completion policy alterada por esta RPC, mas a v1.0
retornava sucesso silencioso em vez de falhar). A v2.0 valida
explicitamente, ANTES do `UPDATE`:
  - `mode IS NOT DISTINCT FROM 'REFERENCE_BASED'` (NULL-safe);
  - `reference_kind IS NOT DISTINCT FROM 'CARD_SET'` (NULL-safe —
    cobre tanto ausência de `collection_reference` quanto um futuro
    `REFERENCE_POSITION`/Pokédex, que NÃO deve ser aceito
    silenciosamente por esta RPC);
  - `completion_policy` atual `IN ('MASTER_SET', 'STANDARD_SET')` —
    as duas únicas policies válidas para esta RPC (a segunda cobre o
    caso de idempotência genuína).
Qualquer Collection fora dessa elegibilidade (`OPEN_CURATION`/`NONE`,
ou um futuro `REFERENCE_POSITION`) agora FALHA explicitamente, nunca
"passa" sem escrita. Idempotência continua significando apenas:
Collection elegível já em `STANDARD_SET` -> nova chamada -> retorna o
estado atual sem `UPDATE` novo (mesmo padrão de `archive_collection()`/
`reactivate_collection()`, 2B) — não "qualquer Collection ACTIVE é
tratada como no-op válido".

Não-enumeração: `SELECT ... FOR UPDATE WHERE owner_user_id =
(select auth.uid())` no `WHERE`, mesmo padrão do domínio.

SECURITY DEFINER, `SET search_path = ''`, `EXECUTE` revogado de
`PUBLIC`/`anon`, concedido só a `authenticated`.

Aplicação real (COLLECTIONS-PHYSICAL-INCREMENT-02F-IMPLEMENTATION-01):
aplicada via apply_migration; postcheck físico confirmou assinatura,
GRANTs e corpo idênticos a esta definição. Validado funcionalmente em
5812 (114/114 PASS, zero resíduo).

STATUS DESTA QUERY: CONFIRMADO EXECUTADO.
================================================================
*/

CREATE OR REPLACE FUNCTION public.set_collection_completion_policy_to_standard_set(
    p_collection_id UUID
)
RETURNS TABLE (
    id                 UUID,
    completion_policy  TEXT,
    updated_at         TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_collection     public.collection%ROWTYPE;
    v_reference_kind TEXT;
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
        RAISE EXCEPTION 'collection is archived — reactivate before changing completion policy'
            USING ERRCODE = 'check_violation';
    END IF;

    SELECT cr.reference_kind INTO v_reference_kind
    FROM public.collection_reference cr
    WHERE cr.collection_id = p_collection_id;

    -- Elegibilidade explícita, NULL-safe (correção STAGING-REVISION-01
    -- item 4/5 — BLOCKER): só REFERENCE_BASED/CARD_SET com policy
    -- atual MASTER_SET ou STANDARD_SET é aceito. OPEN_CURATION/NONE e
    -- um futuro REFERENCE_POSITION (Pokédex) devem FALHAR
    -- explicitamente, nunca ser tratados como "já idempotente" só
    -- porque nenhuma escrita ocorreria de qualquer forma.
    IF v_collection.mode IS DISTINCT FROM 'REFERENCE_BASED'
       OR v_reference_kind IS DISTINCT FROM 'CARD_SET'
       OR v_collection.completion_policy NOT IN ('MASTER_SET', 'STANDARD_SET') THEN
        RAISE EXCEPTION 'set_collection_completion_policy_to_standard_set requires a REFERENCE_BASED/CARD_SET collection currently in MASTER_SET or STANDARD_SET (collection % is mode=%, completion_policy=%)', p_collection_id, v_collection.mode, v_collection.completion_policy
            USING ERRCODE = 'check_violation';
    END IF;

    -- Idempotente: guard no WHERE, zero linhas afetadas quando já STANDARD_SET.
    UPDATE public.collection
       SET completion_policy = 'STANDARD_SET'
     WHERE public.collection.id = p_collection_id
       AND public.collection.completion_policy = 'MASTER_SET';

    RETURN QUERY
    SELECT c.id, c.completion_policy, c.updated_at
    FROM public.collection c
    WHERE c.id = p_collection_id;
END;
$$;

REVOKE ALL ON FUNCTION public.set_collection_completion_policy_to_standard_set(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.set_collection_completion_policy_to_standard_set(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.set_collection_completion_policy_to_standard_set(uuid) TO authenticated;
