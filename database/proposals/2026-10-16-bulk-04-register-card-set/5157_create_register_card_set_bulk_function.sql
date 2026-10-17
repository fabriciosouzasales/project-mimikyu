/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5157 - register_card_set_bulk (B2 / BULK-04, REGISTER_CARD_SET)
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO / LIVE / PROMOVIDO (2026-10-16,
              ledger 20261016235726). Aplicado via apply_migration do
              Supabase, que envolve a migration em transacao propria
              (BEGIN/COMMIT deste arquivo omitidos no envio); corpo
              conferido byte a byte com o LIVE (md5 de prosrc).
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-16 (BULK04-B2-IMPLEMENTATION-PROPOSAL-01)
Pré-req.....: 5142–5148 (família Bulk), 5152, 5153, 5154, 5156.
Contrato....: BULK04-B2-MODELING-01; decisões Q1–Q9 e I1.

Assinatura congelada: p_request jsonb -> jsonb.

Envelope (chaves fechadas)
  idempotency_key       UUID, obrigatório
  preview_fingerprint   string não vazia, obrigatório
  card_set_id           UUID, obrigatório
  language_id           UUID, obrigatório (um idioma por operação, Q5)
  collection_id         UUID ou null, opcional
  storage_container_id  UUID ou null, opcional

Sequência (mesma do B1, com a expansão entre locks e fingerprint)
  1. Guards estruturais do envelope — só exceção, nenhuma leitura.
  2. request_hash = bulk_request_hash('REGISTER_CARD_SET', intenção),
     intenção = {card_set_id, language_id, collection_id,
     storage_container_id} normalizados (5147). Cobre a intenção, não a
     expansão.
  3. Claim (5144): CONFLICT -> BULK_IDEMPOTENCY_CONFLICT; REPLAY devolve
     o resultado gravado, sem lock, sem fingerprint, sem validação (D9).
  4. Locks INVENTORY -> COLLECTION -> STORAGE (5148, I9).
  5. Expansão (5154), já com o escopo travado.
  6. Fingerprint recalculado (5156) e comparado -> PREVIEW_STALE,
     ANTES de qualquer validação de domínio (mesma ordem do B1).
  7. Validações próprias de B2 (22023): Card Set inexistente; Cards
     ativos sem variante padrão (com LISTA); Set sem Card ativo; teto
     de 1000 (mesma mensagem do B1).
  8. Validação de domínio e escrita do B1 via 5153 (fonte única):
     Collection arquivada, variante inexistente/inativa, idioma
     inexistente, Game, elegibilidade de Reference, INSERT set-based,
     alocação, guards de atomicidade.
  9. complete_bulk_operation (5145) e retorno
     {outcome 'CREATED', operation_id, result_summary}.

All-or-nothing: qualquer falha desfaz a transação inteira, claim
incluído. O trigger de 2268 continua sendo a última barreira contra
variante desativada em concorrência. Nenhum lock novo.

Segurança: SECURITY DEFINER, owner postgres, search_path vazio,
EXECUTE só para authenticated (mesma matriz de 5150).
================================================================
*/

BEGIN;

CREATE FUNCTION public.register_card_set_bulk(p_request JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    c_operation_type CONSTANT TEXT := 'REGISTER_CARD_SET';
    c_max_total      CONSTANT INT  := 1000;
    c_uuid_re        CONSTANT TEXT :=
        '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';

    v_idempotency_key   UUID;
    v_fingerprint_in    TEXT;
    v_fingerprint_now   TEXT;
    v_card_set_id       UUID;
    v_language_id       UUID;
    v_collection_id     UUID;
    v_storage_id        UUID;
    v_intent            JSONB;
    v_request_hash      TEXT;
    v_claim             RECORD;
    v_scope             RECORD;
    v_exp               RECORD;
    v_items             JSONB;
    v_total             BIGINT;
    v_created_ids       UUID[];
    v_created_count     INT;
    v_allocated_count   INT;
    v_result            JSONB;
BEGIN
    -- ============================================================
    -- 1) GUARDS ESTRUTURAIS — nada e lido nem escrito no banco.
    -- ============================================================
    IF p_request IS NULL OR jsonb_typeof(p_request) IS DISTINCT FROM 'object' THEN
        RAISE EXCEPTION 'p_request deve ser um objeto JSON' USING ERRCODE = '22023';
    END IF;

    IF EXISTS (
        SELECT 1 FROM jsonb_object_keys(p_request) AS k(key)
        WHERE k.key NOT IN ('idempotency_key', 'preview_fingerprint', 'card_set_id',
                            'language_id', 'collection_id', 'storage_container_id')
    ) THEN
        RAISE EXCEPTION
            'p_request aceita exatamente as chaves idempotency_key, preview_fingerprint, card_set_id, language_id, collection_id e storage_container_id'
            USING ERRCODE = '22023';
    END IF;

    IF NOT (p_request ? 'idempotency_key')
       OR NOT (p_request ? 'preview_fingerprint')
       OR NOT (p_request ? 'card_set_id')
       OR NOT (p_request ? 'language_id') THEN
        RAISE EXCEPTION
            'p_request exige idempotency_key, preview_fingerprint, card_set_id e language_id'
            USING ERRCODE = '22023';
    END IF;

    IF (p_request ->> 'idempotency_key') IS NULL
       OR (p_request ->> 'idempotency_key') !~* c_uuid_re THEN
        RAISE EXCEPTION 'idempotency_key deve ser um UUID valido' USING ERRCODE = '22023';
    END IF;
    v_idempotency_key := (p_request ->> 'idempotency_key')::uuid;

    IF jsonb_typeof(p_request -> 'preview_fingerprint') IS DISTINCT FROM 'string'
       OR btrim(p_request ->> 'preview_fingerprint') = '' THEN
        RAISE EXCEPTION 'preview_fingerprint e obrigatorio e nao pode ser vazio'
            USING ERRCODE = '22023';
    END IF;
    v_fingerprint_in := p_request ->> 'preview_fingerprint';

    IF jsonb_typeof(p_request -> 'card_set_id') IS DISTINCT FROM 'string'
       OR (p_request ->> 'card_set_id') !~* c_uuid_re THEN
        RAISE EXCEPTION 'card_set_id deve ser um UUID valido' USING ERRCODE = '22023';
    END IF;
    v_card_set_id := (p_request ->> 'card_set_id')::uuid;

    IF jsonb_typeof(p_request -> 'language_id') IS DISTINCT FROM 'string'
       OR (p_request ->> 'language_id') !~* c_uuid_re THEN
        RAISE EXCEPTION 'language_id deve ser um UUID valido' USING ERRCODE = '22023';
    END IF;
    v_language_id := (p_request ->> 'language_id')::uuid;

    IF (p_request ->> 'collection_id') IS NOT NULL THEN
        IF (p_request ->> 'collection_id') !~* c_uuid_re THEN
            RAISE EXCEPTION 'collection_id deve ser um UUID valido ou null'
                USING ERRCODE = '22023';
        END IF;
        v_collection_id := (p_request ->> 'collection_id')::uuid;
    END IF;

    IF (p_request ->> 'storage_container_id') IS NOT NULL THEN
        IF (p_request ->> 'storage_container_id') !~* c_uuid_re THEN
            RAISE EXCEPTION 'storage_container_id deve ser um UUID valido ou null'
                USING ERRCODE = '22023';
        END IF;
        v_storage_id := (p_request ->> 'storage_container_id')::uuid;
    END IF;

    -- ============================================================
    -- 2) request_hash CANONICO — 5147. Intencao, nao expansao.
    -- ============================================================
    v_intent := jsonb_build_object(
        'card_set_id',          v_card_set_id::text,
        'language_id',          v_language_id::text,
        'collection_id',        v_collection_id::text,
        'storage_container_id', v_storage_id::text
    );

    v_request_hash := public.bulk_request_hash(c_operation_type, v_intent);

    -- ============================================================
    -- 3) CLAIM DE IDEMPOTENCIA — 5144.
    -- ============================================================
    SELECT * INTO v_claim
      FROM public.claim_bulk_operation(
               c_operation_type,
               v_idempotency_key,
               v_request_hash,
               v_fingerprint_in
           );

    IF v_claim.outcome = 'CONFLICT' THEN
        RAISE EXCEPTION
            'BULK_IDEMPOTENCY_CONFLICT: idempotency_key ja usada com uma requisicao diferente'
            USING ERRCODE = '22023';
    END IF;

    IF v_claim.outcome = 'REPLAY' THEN
        -- D9: replay e independente do estado do mundo.
        RETURN jsonb_build_object(
            'outcome',        'REPLAY',
            'operation_id',   v_claim.operation_id,
            'result_summary', v_claim.result_summary
        );
    END IF;

    IF v_claim.outcome <> 'CLAIMED' THEN
        RAISE EXCEPTION
            'estado inconsistente: outcome inesperado % de claim_bulk_operation', v_claim.outcome
            USING ERRCODE = '55000';
    END IF;

    -- ============================================================
    -- 4) LOCKS — 5148, fonte unica (I9).
    -- ============================================================
    SELECT * INTO v_scope
      FROM public.bulk_lock_operation_scope(v_collection_id, v_storage_id);

    -- ============================================================
    -- 5) EXPANSAO — 5154, sob o escopo ja travado.
    -- ============================================================
    SELECT e.o_items, e.o_cards_without_default
      INTO v_exp
      FROM public.bulk_expand_card_set(v_card_set_id, v_language_id) AS e;

    v_items := v_exp.o_items;
    v_total := jsonb_array_length(v_items);

    -- ============================================================
    -- 6) preview_fingerprint RECALCULADO — 5156. Antes de qualquer
    --    validacao de dominio, como no B1.
    -- ============================================================
    v_fingerprint_now := public.preview_fingerprint_register_card_set(
                             v_card_set_id, v_language_id, v_collection_id, v_storage_id
                         );

    IF v_fingerprint_now IS DISTINCT FROM v_fingerprint_in THEN
        RAISE EXCEPTION
            'PREVIEW_STALE: o estado mudou desde o preview — refaca o preview e confirme novamente'
            USING ERRCODE = '22023';
    END IF;

    -- ============================================================
    -- 7) VALIDACOES PROPRIAS DE B2 — todas antes de qualquer escrita.
    -- ============================================================
    IF NOT EXISTS (SELECT 1 FROM public.card_set cs WHERE cs.id = v_card_set_id) THEN
        RAISE EXCEPTION 'card set not found' USING ERRCODE = '22023';
    END IF;

    IF v_exp.o_cards_without_default IS NOT NULL THEN
        RAISE EXCEPTION
            'CARD_DEFAULT_VARIANT_MISSING: % card(s) sem variante padrao: %',
            cardinality(v_exp.o_cards_without_default),
            array_to_string(v_exp.o_cards_without_default[1:10], ', ')
            USING ERRCODE = '22023',
                  DETAIL  = 'lista completa: ' || array_to_string(v_exp.o_cards_without_default, ', ');
    END IF;

    IF v_total = 0 THEN
        RAISE EXCEPTION 'card set has no active cards' USING ERRCODE = '22023';
    END IF;

    IF v_total > c_max_total THEN
        RAISE EXCEPTION
            'a operacao criaria % Physical Cards e excede o limite de % por chamada',
            v_total, c_max_total
            USING ERRCODE = '22023';
    END IF;

    -- ============================================================
    -- 8) VALIDACAO DE DOMINIO + ESCRITAS — 5153, fonte unica B1/B2.
    -- ============================================================
    SELECT h.o_physical_card_ids, h.o_allocated_count
      INTO v_created_ids, v_allocated_count
      FROM public.bulk_register_physical_card_items(
               v_items,
               v_scope.inventory_id,
               v_collection_id,
               v_storage_id,
               v_scope.collection_lifecycle_status,
               v_scope.collection_game_id,
               v_scope.collection_mode,
               v_scope.collection_reference_kind,
               v_scope.collection_reference_card_set_id,
               v_total
           ) AS h;

    v_created_count := COALESCE(cardinality(v_created_ids), 0);

    -- ============================================================
    -- 9) FECHAMENTO DO CLAIM — 5145.
    -- ============================================================
    v_result := jsonb_build_object(
        'operation_type',       c_operation_type,
        'card_set_id',          v_card_set_id,
        'language_id',          v_language_id,
        'created_count',        v_created_count,
        'distinct_items',       v_total,
        'allocated_count',      v_allocated_count,
        'collection_id',        v_collection_id,
        'storage_container_id', v_storage_id,
        'physical_card_ids',    to_jsonb(v_created_ids)
    );

    PERFORM public.complete_bulk_operation(v_claim.operation_id, v_result);

    RETURN jsonb_build_object(
        'outcome',        'CREATED',
        'operation_id',   v_claim.operation_id,
        'result_summary', v_result
    );
END;
$$;

COMMENT ON FUNCTION public.register_card_set_bulk(JSONB) IS
    'B2 (BULK-04) — registra o Card Set inteiro: uma Physical Card por Card ATIVO, na variante padrao, inclusive Cards ja possuidos (Q3/Q4), num unico idioma (Q5). Assinatura congelada: p_request jsonb -> jsonb, envelope fechado {idempotency_key, preview_fingerprint, card_set_id, language_id, collection_id, storage_container_id}. Caminho: guards -> request_hash da intencao (5147) -> claim (5144, REGISTER_CARD_SET) -> locks (5148, I9) -> expansao (5154) -> fingerprint (5156) e PREVIEW_STALE -> validacoes de B2 (Card Set inexistente, Cards sem variante padrao com LISTA, Set vazio, teto 1000) -> validacao de dominio e escrita via 5153 (fonte unica B1/B2) -> complete (5145). All-or-nothing; REPLAY independente do mundo (D9). EXECUTE: authenticated SIM; PUBLIC/anon/service_role NAO.';

REVOKE EXECUTE ON FUNCTION public.register_card_set_bulk(JSONB)
    FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.register_card_set_bulk(JSONB)
    TO authenticated;

COMMIT;
