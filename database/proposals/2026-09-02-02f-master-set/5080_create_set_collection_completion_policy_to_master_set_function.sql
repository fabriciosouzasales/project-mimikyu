/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5080 - Create set_collection_completion_policy_to_master_set Function
Versão......: 2.0
Status......: PROPOSTA — NÃO EXECUTADA
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-02 (COLLECTIONS-PHYSICAL-INCREMENT-02F-STAGING-01 → -STAGING-REVISION-01)

Descrição...:
RPC de transição `STANDARD_SET -> MASTER_SET` (C-23/LDM-22). Owner-only,
`ACTIVE`-only (`ARCHIVED` bloqueia — decisão fechada em
MODELING-REVISION-01 item 4). Dois caminhos, fechados em
MODELING-01/-REVISION-01 e corrigidos em MODELING-FINAL-FIX-02 (item
2):

A. `p_card_variant_ids` fornecido — aplica `apply_master_set_scope_diff()`
   (5079) comparando SEMPRE contra o Scope efetivamente PERSISTIDO
   para esta Collection, MESMO que `completion_policy` atual seja
   `STANDARD_SET` (correção de FINAL-FIX-02: nunca presumir "Scope
   atual vazio / tudo ADD" só porque a policy corrente não é
   `MASTER_SET` — um Scope de um ciclo `MASTER_SET` anterior pode
   estar persistido e inativo). KEEP/ADD/REMOVE aplicado; `adopted_at`/
   `adopted_by_user_id` de linhas KEEP nunca tocados.
B. `p_card_variant_ids` omitido (`NULL`) — reaproveita o Scope já
   persistido sem tocar nenhuma linha; exige que já exista >= 1 linha
   (checagem amigável aqui; o gate estrutural diferido de `5076` é o
   backstop final independente desta RPC).

`completion_policy` só é atualizado DEPOIS (mesma transação) — a
função sempre grava a mudança de Scope e a mudança de policy juntas,
atômico por ser uma única função `plpgsql`. `MASTER_SET` ativo nunca
pode terminar vazio: garantido estruturalmente por `5076` mesmo se
esta RPC tiver algum bug — o COMMIT falharia de qualquer forma.

Não idempotente para o caso "já é MASTER_SET" — rejeitada com mensagem
de domínio explícita ("já é MASTER_SET, use replace_master_set_scope()
para alterar o Scope"), porque esta RPC é uma TRANSIÇÃO, não uma
mutação de Scope em curso (decisão fechada em MODELING-REVISION-01
item 3: essas são operações conceitualmente distintas, com contratos
separados).

Não-enumeração: `SELECT ... FOR UPDATE WHERE owner_user_id =
(select auth.uid())` no `WHERE`, mesmo padrão de todo o domínio —
Collection alheia e inexistente produzem a mesma mensagem genérica.

CORREÇÃO v2.0 (STAGING-REVISION-01, item 3): no Caminho B (reaproveitar
Scope persistido, `p_card_variant_ids IS NULL`), `scope_kept_count` era
retornado como `0` na v1.0 — semanticamente enganoso, já que 100% do
Scope persistido é reaproveitado como KEEP nesse caminho. A v2.0
retorna a contagem REAL de linhas do Scope persistido reaproveitado
(`added_count = 0`, `removed_count = 0`, `kept_count = <linhas reais>`).

CORREÇÃO v2.0 (STAGING-REVISION-01, item 5): a comparação
`v_reference_kind <> 'CARD_SET'` era NULL-unsafe — se
`collection_reference` não tivesse linha correspondente (v_reference_kind
IS NULL), `NULL <> 'CARD_SET'` avalia para `NULL`, e `FALSE OR NULL`
(quando `mode = 'REFERENCE_BASED'`) também é `NULL`, que o `IF` do
PL/pgSQL trata como falso — a exceção NUNCA seria levantada, deixando
passar uma Collection `REFERENCE_BASED` sem subtype de Reference
resolvido. Corrigido para `IS DISTINCT FROM`, que trata `NULL`
corretamente como "diferente de CARD_SET" (dispara a exceção).

SECURITY DEFINER, `SET search_path = ''`, `EXECUTE` revogado de
`PUBLIC`/`anon`, concedido só a `authenticated`.

STATUS DESTA QUERY: PROPOSTA — NÃO EXECUTADA.
================================================================
*/

CREATE OR REPLACE FUNCTION public.set_collection_completion_policy_to_master_set(
    p_collection_id         UUID,
    p_card_variant_ids      JSONB DEFAULT NULL
)
RETURNS TABLE (
    id                 UUID,
    completion_policy  TEXT,
    updated_at         TIMESTAMPTZ,
    scope_added_count   INTEGER,
    scope_removed_count INTEGER,
    scope_kept_count    INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_collection        public.collection%ROWTYPE;
    v_reference_kind    TEXT;
    v_added_count       INTEGER := 0;
    v_removed_count     INTEGER := 0;
    v_kept_count        INTEGER := 0;
BEGIN
    IF (select auth.uid()) IS NULL THEN
        RAISE EXCEPTION 'authentication required'
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    -- Ownership + lock, não-enumerável: Collection alheia/inexistente -> mesma mensagem.
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

    -- NULL-safe (correção STAGING-REVISION-01 item 5): IS DISTINCT FROM
    -- garante que um v_reference_kind NULL (nenhuma collection_reference
    -- correspondente) também dispara a exceção, em vez de deslizar por
    -- um IF que a comparação `<>` avaliaria como NULL/falso.
    IF v_collection.mode IS DISTINCT FROM 'REFERENCE_BASED' OR v_reference_kind IS DISTINCT FROM 'CARD_SET' THEN
        RAISE EXCEPTION 'master set completion policy requires a REFERENCE_BASED/CARD_SET collection'
            USING ERRCODE = 'check_violation';
    END IF;

    IF v_collection.completion_policy = 'MASTER_SET' THEN
        RAISE EXCEPTION 'collection % is already MASTER_SET — use replace_master_set_scope() to change its scope', p_collection_id
            USING ERRCODE = 'check_violation';
    END IF;

    IF p_card_variant_ids IS NOT NULL THEN
        -- Caminho A: compara contra o Scope PERSISTIDO atual, mesmo com policy = STANDARD_SET.
        SELECT added_count, removed_count, kept_count
          INTO v_added_count, v_removed_count, v_kept_count
        FROM public.apply_master_set_scope_diff(p_collection_id, p_card_variant_ids);
    ELSE
        -- Caminho B: reaproveitar Scope persistido — exige >= 1 linha já
        -- existente. kept_count = contagem REAL do Scope persistido
        -- reaproveitado (correção STAGING-REVISION-01 item 3 — v1.0
        -- retornava 0, semanticamente enganoso: 100% do Scope é KEEP
        -- neste caminho, não "nenhuma linha considerada").
        SELECT count(*) INTO v_kept_count
        FROM public.collection_master_set_scope s
        WHERE s.collection_id = p_collection_id;

        IF v_kept_count = 0 THEN
            RAISE EXCEPTION 'cannot activate MASTER_SET without a scope: no p_card_variant_ids provided and no persisted scope exists for collection %', p_collection_id
                USING ERRCODE = 'check_violation';
        END IF;
        -- Nenhuma escrita em collection_master_set_scope neste caminho — 100% KEEP.
    END IF;

    UPDATE public.collection
       SET completion_policy = 'MASTER_SET'
     WHERE public.collection.id = p_collection_id
       AND public.collection.lifecycle_status = 'ACTIVE';

    RETURN QUERY
    SELECT c.id, c.completion_policy, c.updated_at, v_added_count, v_removed_count, v_kept_count
    FROM public.collection c
    WHERE c.id = p_collection_id;
END;
$$;

REVOKE ALL ON FUNCTION public.set_collection_completion_policy_to_master_set(uuid, jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.set_collection_completion_policy_to_master_set(uuid, jsonb) FROM anon;
GRANT EXECUTE ON FUNCTION public.set_collection_completion_policy_to_master_set(uuid, jsonb) TO authenticated;
