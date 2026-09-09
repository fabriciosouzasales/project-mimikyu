/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5148 - bulk_lock_operation_scope(): ordem canônica de
               locks da família Bulk (INVENTORY -> COLLECTION -> STORAGE)
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO / LIVE / PROMOVIDO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-08 (COLLECTIONS-BULK-02-GATE-A-REVISION-01)

Descrição...:
FONTE ÚNICA E REUTILIZÁVEL da ordem de aquisição de locks para TODA a
família Bulk. Atende `I9` diretamente: a ordem deixa de ser um
comentário repetido em cada RPC e passa a ser UMA implementação
executável, compartilhada por `B1` e `B2`.

Ordem canônica COMPLETA de uma operação Bulk:

    BULK_OPERATION  (claim, 5144)
         -> INVENTORY
              -> COLLECTION
                   -> STORAGE

Esta função cobre os três últimos. O claim é anterior e fica na RPC
chamadora, porque é ele quem decide CREATED / REPLAY / CONFLICT antes
de qualquer recurso de negócio ser tocado.

Por que a ordem importa: duas operações Bulk concorrentes do MESMO
dono que toquem os mesmos recursos em ordens diferentes fecham um
ciclo de espera e o PostgreSQL aborta uma delas por deadlock. Uma
única fonte torna a inversão impossível por construção — não por
disciplina de revisão.

================================================================
O QUE ESTA FUNÇÃO FAZ E O QUE NÃO FAZ
================================================================
FAZ:
  - resolve o dono por `auth.uid()` — o chamador NUNCA informa dono;
  - trava a linha de `inventory` do dono (`FOR UPDATE`);
  - trava a Collection alvo, quando houver, com `owner_user_id` DENTRO
    do `WHERE` — não-enumeração: inexistente e de terceiro produzem a
    MESMA mensagem;
  - trava o Storage Container alvo, quando houver, com `inventory_id`
    DENTRO do `WHERE` — mesma não-enumeração, e sem NUNCA travar linha
    de outro Inventory;
  - devolve o estado LIDO SOB LOCK: lifecycle, mode, Game e a
    referência da Collection.

NÃO FAZ:
  - não valida lifecycle, Game, elegibilidade nem catálogo. Isso é
    validação de domínio e pertence à RPC chamadora, que a executa
    DEPOIS da checagem de `preview_fingerprint`. Esta função só
    responde "existe, é seu, e está travado".

A distinção é o que permite à RPC comparar o fingerprint contra o
estado JÁ PINADO pelos locks, antes de qualquer decisão de domínio —
fechando a janela TOCTOU que existiria se o fingerprint fosse
conferido na aplicação, antes da chamada.

================================================================
SEGURANÇA
================================================================
`SECURITY DEFINER`, `search_path = ''`, owner `postgres`, referências
qualificadas. `EXECUTE` revogado de `PUBLIC`, `anon`, `authenticated`
e `service_role` — helper INTERNO, alcançado só de dentro das RPCs
Bulk. Precedente: `5144`/`5145`.

`SECURITY DEFINER` é necessário aqui (ao contrário de `5147`): a
função lê e trava linhas de `inventory`, `collection` e
`storage_container`.

Dependências:
- public.inventory (5000);
- public.collection (5030/5060/5067/5078/5086);
- public.storage_container (5020);
- public.collection_reference / collection_card_set_reference (5049+).

STATUS DESTA QUERY: CONFIRMADO EXECUTADO / LIVE / PROMOVIDO.
================================================================
*/

BEGIN;

CREATE FUNCTION public.bulk_lock_operation_scope(
    p_collection_id        UUID DEFAULT NULL,
    p_storage_container_id UUID DEFAULT NULL
)
RETURNS TABLE (
    owner_user_id                    UUID,
    inventory_id                     UUID,
    collection_id                    UUID,
    collection_updated_at            TIMESTAMPTZ,
    collection_game_id               UUID,
    collection_mode                  TEXT,
    collection_lifecycle_status      TEXT,
    collection_reference_kind        TEXT,
    collection_reference_card_set_id UUID,
    storage_container_id             UUID,
    storage_updated_at               TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_owner        UUID;
    v_inventory    UUID;
    v_col_updated  TIMESTAMPTZ;
    v_col_game     UUID;
    v_col_mode     TEXT;
    v_col_life     TEXT;
    v_ref_kind     TEXT;
    v_ref_card_set UUID;
    v_stg_updated  TIMESTAMPTZ;
BEGIN
    v_owner := (select auth.uid());

    IF v_owner IS NULL THEN
        RAISE EXCEPTION 'authentication required' USING ERRCODE = '28000';
    END IF;

    -- ============================================================
    -- LOCK 1 — INVENTORY
    -- ============================================================
    SELECT inv.id
      INTO v_inventory
      FROM public.inventory inv
     WHERE inv.owner_user_id = v_owner
       FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'inventory not found for current user' USING ERRCODE = '22023';
    END IF;

    -- ============================================================
    -- LOCK 2 — COLLECTION (opcional)
    -- `owner_user_id` no WHERE: nao-enumeracao, e jamais travamos a
    -- linha de uma Collection de terceiro.
    -- ============================================================
    IF p_collection_id IS NOT NULL THEN
        SELECT col.updated_at, col.game_id, col.mode, col.lifecycle_status
          INTO v_col_updated, v_col_game, v_col_mode, v_col_life
          FROM public.collection col
         WHERE col.id = p_collection_id
           AND col.owner_user_id = v_owner
           FOR UPDATE;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'collection not found or not owned by caller'
                USING ERRCODE = '22023';
        END IF;

        -- Referencia lida SOB o lock da Collection. Nao ha lock proprio:
        -- a Collection e o ponto de serializacao do seu proprio
        -- Reference, e `reference_locked_at` vive na propria linha
        -- travada acima.
        SELECT cr.reference_kind, ccsr.card_set_id
          INTO v_ref_kind, v_ref_card_set
          FROM public.collection_reference cr
          LEFT JOIN public.collection_card_set_reference ccsr
                 ON ccsr.collection_reference_id = cr.id
         WHERE cr.collection_id = p_collection_id;
    END IF;

    -- ============================================================
    -- LOCK 3 — STORAGE CONTAINER (opcional)
    -- `inventory_id` no WHERE: nao-enumeracao, e jamais travamos a
    -- linha de um Storage de outro Inventory.
    -- ============================================================
    IF p_storage_container_id IS NOT NULL THEN
        SELECT sc.updated_at
          INTO v_stg_updated
          FROM public.storage_container sc
         WHERE sc.id = p_storage_container_id
           AND sc.inventory_id = v_inventory
           FOR UPDATE;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'storage container not found or not owned by caller'
                USING ERRCODE = '22023';
        END IF;
    END IF;

    RETURN QUERY
    SELECT v_owner, v_inventory,
           p_collection_id, v_col_updated, v_col_game, v_col_mode, v_col_life,
           v_ref_kind, v_ref_card_set,
           p_storage_container_id, v_stg_updated;
END;
$$;

COMMENT ON FUNCTION public.bulk_lock_operation_scope(UUID, UUID) IS
    'FONTE UNICA da ordem canonica de locks da familia Bulk: INVENTORY -> COLLECTION -> STORAGE (o claim de bulk_operation e anterior e fica na RPC). Atende I9. Resolve o dono por auth.uid(); nao-enumeracao com ownership DENTRO do WHERE, de modo que recurso inexistente e recurso de terceiro produzem a MESMA mensagem e nenhuma linha alheia e travada. Devolve o estado lido SOB LOCK (lifecycle, mode, Game, Reference, updated_at) para a RPC comparar o preview_fingerprint contra um estado ja pinado. NAO valida dominio. Helper INTERNO: EXECUTE revogado de todos os papeis.';

REVOKE EXECUTE ON FUNCTION public.bulk_lock_operation_scope(UUID, UUID)
    FROM PUBLIC, anon, authenticated, service_role;

COMMIT;

/*
Como validar (APÓS aplicar): harness `5822`, grupos `R` e `S`.

Prova estática esperada do corpo:
- a primeira ocorrência de `FOR UPDATE` está no bloco de `inventory`;
- a segunda, no bloco de `collection`;
- a terceira, no bloco de `storage_container`.
Ou seja, a ordem textual das três é INVENTORY, COLLECTION, STORAGE.
*/
