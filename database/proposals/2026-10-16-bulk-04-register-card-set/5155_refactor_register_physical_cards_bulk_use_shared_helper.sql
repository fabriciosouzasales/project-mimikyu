/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5155 - register_physical_cards_bulk (B1) delega validação
               de domínio e escrita ao helper 5153
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO / LIVE / PROMOVIDO (2026-10-16,
              ledger 20261016235631). Aplicado via apply_migration do
              Supabase, que envolve a migration em transacao propria
              (BEGIN/COMMIT deste arquivo omitidos no envio); corpo
              conferido byte a byte com o LIVE (md5 de prosrc).
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-16 (BULK04-B2-IMPLEMENTATION-PROPOSAL-01)
Pré-req.....: 5152 e 5153 aplicadas.
Decisão.....: I1 (aprovada).

O que muda em relação ao corpo de 5150 na versão de 5152
  - Os passos 6 (validação de domínio) e 7 (escritas) saem daqui e
    viram UMA chamada a public.bulk_register_physical_card_items (5153),
    cujo corpo é a cópia literal desses passos.
  - A declaração de v_missing, usada só nesses passos, sai.
  - COMMENT: acrescenta que validação e escrita estão em 5153.

O que NÃO muda
  Assinatura, envelope, guards estruturais (passo 1), request_hash
  (2), claim e REPLAY/CONFLICT (3), locks via 5148 (4), fingerprint e
  PREVIEW_STALE (5), result_summary e complete (8), mensagens,
  SQLSTATE, ordem, SECURITY DEFINER, search_path vazio, ACL
  (REVOKE/GRANT reafirmados iguais). Nenhum lock novo.

Regressão obrigatória: 5822 (64/64) e 5824 (ver README, item E02).
================================================================
*/

BEGIN;

CREATE OR REPLACE FUNCTION public.register_physical_cards_bulk(p_request JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    c_operation_type CONSTANT TEXT := 'REGISTER_PHYSICAL_CARDS';
    c_max_total      CONSTANT INT  := 1000;
    c_uuid_re        CONSTANT TEXT :=
        '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';

    v_idempotency_key   UUID;
    v_fingerprint_in    TEXT;
    v_fingerprint_now   TEXT;
    v_items             JSONB;
    v_collection_id     UUID;
    v_storage_id        UUID;

    v_raw_count         INT;
    v_distinct_count    INT;
    v_total_expanded    BIGINT;
    v_bad_ids           TEXT[];
    v_dups              TEXT[];

    v_intent            JSONB;
    v_request_hash      TEXT;
    v_claim             RECORD;
    v_scope             RECORD;

    v_created_ids       UUID[];
    v_created_count     INT;
    v_allocated_count   INT;
    v_result            JSONB;
BEGIN
    -- ============================================================
    -- 1) GUARDS ESTRUTURAIS — nada e lido nem escrito no banco.
    --    Todos ANTES do claim e, por consequencia, ANTES de
    --    qualquer escrita.
    -- ============================================================

    -- 1.1) ENVELOPE
    IF p_request IS NULL OR jsonb_typeof(p_request) IS DISTINCT FROM 'object' THEN
        RAISE EXCEPTION 'p_request deve ser um objeto JSON' USING ERRCODE = '22023';
    END IF;

    IF EXISTS (
        SELECT 1 FROM jsonb_object_keys(p_request) AS k(key)
        WHERE k.key NOT IN ('idempotency_key', 'preview_fingerprint', 'items',
                            'collection_id', 'storage_container_id')
    ) THEN
        RAISE EXCEPTION
            'p_request aceita exatamente as chaves idempotency_key, preview_fingerprint, items, collection_id e storage_container_id'
            USING ERRCODE = '22023';
    END IF;

    IF NOT (p_request ? 'idempotency_key')
       OR NOT (p_request ? 'preview_fingerprint')
       OR NOT (p_request ? 'items') THEN
        RAISE EXCEPTION
            'p_request exige idempotency_key, preview_fingerprint e items'
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

    -- 1.2) ITEMS — forma
    v_items := p_request -> 'items';

    IF jsonb_typeof(v_items) IS DISTINCT FROM 'array' THEN
        RAISE EXCEPTION 'items deve ser um array JSON' USING ERRCODE = '22023';
    END IF;

    v_raw_count := jsonb_array_length(v_items);

    IF v_raw_count = 0 THEN
        RAISE EXCEPTION 'items nao pode ser vazio' USING ERRCODE = '22023';
    END IF;

    -- TETO DO PAYLOAD BRUTO. Como quantity >= 1, o numero de itens
    -- distintos nunca pode passar do teto de Physical Cards.
    IF v_raw_count > c_max_total THEN
        RAISE EXCEPTION
            'items excede o limite de % itens por chamada (recebido %)',
            c_max_total, v_raw_count
            USING ERRCODE = '22023';
    END IF;

    IF EXISTS (
        SELECT 1 FROM jsonb_array_elements(v_items) AS it(elem)
        WHERE jsonb_typeof(it.elem) IS DISTINCT FROM 'object'
    ) THEN
        RAISE EXCEPTION 'cada item de items deve ser um objeto JSON'
            USING ERRCODE = '22023';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM jsonb_array_elements(v_items) AS it(elem),
             LATERAL jsonb_object_keys(it.elem) AS k(key)
        WHERE k.key NOT IN ('card_variant_id', 'language_id', 'quantity')
    ) THEN
        RAISE EXCEPTION
            'cada item de items aceita exatamente as chaves card_variant_id, language_id e quantity'
            USING ERRCODE = '22023';
    END IF;

    IF EXISTS (
        SELECT 1 FROM jsonb_array_elements(v_items) AS it(elem)
        WHERE NOT (it.elem ? 'card_variant_id')
           OR NOT (it.elem ? 'language_id')
           OR NOT (it.elem ? 'quantity')
    ) THEN
        RAISE EXCEPTION
            'cada item de items exige card_variant_id, language_id e quantity'
            USING ERRCODE = '22023';
    END IF;

    IF EXISTS (
        SELECT 1 FROM jsonb_array_elements(v_items) AS it(elem)
        WHERE jsonb_typeof(it.elem -> 'card_variant_id') IS DISTINCT FROM 'string'
           OR jsonb_typeof(it.elem -> 'language_id')     IS DISTINCT FROM 'string'
           OR jsonb_typeof(it.elem -> 'quantity')        IS DISTINCT FROM 'number'
    ) THEN
        RAISE EXCEPTION
            'tipos invalidos em items: card_variant_id e language_id devem ser string e quantity deve ser number'
            USING ERRCODE = '22023';
    END IF;

    -- 1.3) UUID SINTATICAMENTE INVALIDO — com LISTA
    SELECT array_agg(DISTINCT s.bad ORDER BY s.bad)
      INTO v_bad_ids
      FROM (
          SELECT (it.elem ->> 'card_variant_id') AS bad
            FROM jsonb_array_elements(v_items) AS it(elem)
           WHERE (it.elem ->> 'card_variant_id') !~* c_uuid_re
          UNION ALL
          SELECT (it.elem ->> 'language_id')
            FROM jsonb_array_elements(v_items) AS it(elem)
           WHERE (it.elem ->> 'language_id') !~* c_uuid_re
      ) s;

    IF v_bad_ids IS NOT NULL THEN
        RAISE EXCEPTION
            '% identificador(es) invalido(s) em items: %',
            cardinality(v_bad_ids),
            array_to_string(v_bad_ids[1:10], ', ')
            USING ERRCODE = '22023',
                  DETAIL  = 'lista completa: ' || array_to_string(v_bad_ids, ', ');
    END IF;

    -- 1.4) quantity: inteiro e >= 1. `numeric` cobre 2.5 e -1.
    IF EXISTS (
        SELECT 1 FROM jsonb_array_elements(v_items) AS it(elem)
        WHERE (it.elem ->> 'quantity')::numeric <> trunc((it.elem ->> 'quantity')::numeric)
           OR (it.elem ->> 'quantity')::numeric < 1
    ) THEN
        RAISE EXCEPTION 'quantity deve ser um inteiro maior ou igual a 1'
            USING ERRCODE = '22023';
    END IF;

    IF EXISTS (
        SELECT 1 FROM jsonb_array_elements(v_items) AS it(elem)
        WHERE (it.elem ->> 'quantity')::numeric > c_max_total
    ) THEN
        RAISE EXCEPTION
            'quantity de um item nao pode exceder % (multiplicidade e somente por quantity, mas o teto total continua valendo)',
            c_max_total
            USING ERRCODE = '22023';
    END IF;

    -- 1.5) DUPLICIDADE SEMANTICA de (card_variant_id::uuid, language_id::uuid)
    SELECT count(*) INTO v_distinct_count
      FROM (
          SELECT DISTINCT
                 (it.elem ->> 'card_variant_id')::uuid AS cv_id,
                 (it.elem ->> 'language_id')::uuid     AS lang_id
            FROM jsonb_array_elements(v_items) AS it(elem)
      ) d;

    IF v_distinct_count <> v_raw_count THEN
        SELECT array_agg(s.dup ORDER BY s.dup)
          INTO v_dups
          FROM (
              SELECT (it.elem ->> 'card_variant_id')::uuid::text || ' / ' ||
                     (it.elem ->> 'language_id')::uuid::text AS dup
                FROM jsonb_array_elements(v_items) AS it(elem)
               GROUP BY 1
              HAVING count(*) > 1
          ) s;

        RAISE EXCEPTION
            'items contem % par(es) (card_variant_id, language_id) duplicado(s): % — multiplicidade e expressa somente por quantity',
            cardinality(v_dups),
            array_to_string(v_dups[1:10], '; ')
            USING ERRCODE = '22023',
                  DETAIL  = 'lista completa: ' || array_to_string(v_dups, '; ');
    END IF;

    -- 1.6) TETO DO TOTAL EXPANDIDO
    SELECT sum((it.elem ->> 'quantity')::numeric)
      INTO v_total_expanded
      FROM jsonb_array_elements(v_items) AS it(elem);

    IF v_total_expanded > c_max_total THEN
        RAISE EXCEPTION
            'a operacao criaria % Physical Cards e excede o limite de % por chamada',
            v_total_expanded, c_max_total
            USING ERRCODE = '22023';
    END IF;

    -- ============================================================
    -- 2) request_hash CANONICO — 5147, fonte unica. Derivado aqui,
    --    NUNCA recebido do cliente. Independente da ordem do JSON.
    -- ============================================================
    SELECT jsonb_build_object(
               'collection_id',        v_collection_id::text,
               'storage_container_id', v_storage_id::text,
               'items', COALESCE(jsonb_agg(
                   jsonb_build_object(
                       'card_variant_id', ((it.elem ->> 'card_variant_id')::uuid)::text,
                       'language_id',     ((it.elem ->> 'language_id')::uuid)::text,
                       'quantity',        ((it.elem ->> 'quantity')::numeric)::bigint
                   )
               ), '[]'::jsonb)
           )
      INTO v_intent
      FROM jsonb_array_elements(v_items) AS it(elem);

    v_request_hash := public.bulk_request_hash(c_operation_type, v_intent);

    -- ============================================================
    -- 3) CLAIM DE IDEMPOTENCIA — 5144.
    --    Serializa sessoes concorrentes pelo indice unico. Falha
    --    posterior derruba tambem este claim: a chave NUNCA e
    --    consumida por uma operacao que nao commitou.
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
        -- RETORNO AQUI. Sem locks, sem fingerprint, sem validacao,
        -- sem escrita. D9: replay e independente do estado do mundo.
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
    --    INVENTORY -> COLLECTION -> STORAGE.
    -- ============================================================
    SELECT * INTO v_scope
      FROM public.bulk_lock_operation_scope(v_collection_id, v_storage_id);

    -- ============================================================
    -- 5) preview_fingerprint RECALCULADO DENTRO DA TRANSACAO,
    --    sobre o estado JA PINADO pelos locks do passo 4 — 5149.
    -- ============================================================
    v_fingerprint_now := public.preview_fingerprint_register_physical_cards(
                             v_items, v_collection_id, v_storage_id
                         );

    IF v_fingerprint_now IS DISTINCT FROM v_fingerprint_in THEN
        RAISE EXCEPTION
            'PREVIEW_STALE: o estado mudou desde o preview — refaca o preview e confirme novamente'
            USING ERRCODE = '22023';
    END IF;

    -- ============================================================
    -- 6) e 7) VALIDACAO DE DOMINIO + ESCRITAS — 5153, fonte unica
    --    B1/B2 (I1). Corpo literal dos antigos passos 6 e 7 desta
    --    funcao (versao 5152): mesmas mensagens, mesmos SQLSTATE,
    --    mesma ordem, mesmos guards de atomicidade. Nenhuma escrita
    --    acontece fora do helper.
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
               v_total_expanded
           ) AS h;

    v_created_count := COALESCE(cardinality(v_created_ids), 0);

    -- ============================================================
    -- 8) FECHAMENTO DO CLAIM — 5145. `result_summary` e um JSON
    --    object, exigencia do CHECK de 5146 e do guard do helper.
    -- ============================================================
    v_result := jsonb_build_object(
        'operation_type',       c_operation_type,
        'created_count',        v_created_count,
        'distinct_items',       v_raw_count,
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

COMMENT ON FUNCTION public.register_physical_cards_bulk(JSONB) IS
    'B1 — registro em massa de Physical Cards. Assinatura congelada: p_request jsonb -> jsonb. Uma operacao logica = uma transacao, all-or-nothing, zero partial success. Teto de 1000 Physical Cards, validado no payload BRUTO e no TOTAL EXPANDIDO antes de qualquer escrita. quantity >= 1; duplicidade de (card_variant_id, language_id) comparada SEMANTICAMENTE como tupla de uuid e rejeitada — multiplicidade e somente por quantity. IDs invalidos ou inexistentes abortam com LISTA dos ofensores; card_variant inativa idem, com CARD_VARIANT_INACTIVE (5152). Caminho NEW: guards -> request_hash (5147) -> claim (5144) -> locks INVENTORY/COLLECTION/STORAGE (5148, fonte unica, I9) -> RECALCULO do preview_fingerprint dentro da transacao (5149) -> PREVIEW_STALE se divergir -> validacao -> escritas set-based (ambas em 5153, fonte unica B1/B2) -> complete (5145). REPLAY retorna no claim e NAO valida fingerprint (D9). request_hash derivado server-side e independente da ordem do JSON. add_physical_cards() (5012) e allocate_physical_cards_to_collection() (5046) permanecem canonicas e intocadas, com teto de 500, ate BULK-05. EXECUTE: authenticated SIM; PUBLIC/anon/service_role NAO.';

REVOKE EXECUTE ON FUNCTION public.register_physical_cards_bulk(JSONB)
    FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.register_physical_cards_bulk(JSONB)
    TO authenticated;

COMMIT;
