/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5152 - Bulk B1: recusa explícita de Card Variant inativa
               (preview_fingerprint 5149 + register 5150 + preview 5151)
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO / LIVE / PROMOVIDO (2026-10-16,
              ledger 20261016234129). Aplicado via apply_migration do
              Supabase, que envolve a migration em transacao propria
              (BEGIN/COMMIT deste arquivo omitidos no envio); corpo
              conferido byte a byte com o LIVE (md5 de prosrc).
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-16 (COLLECTION-BULK-ACTIVE-VARIANT-HARDENING-01)
Baseline....: HEAD 2e3747062eedb89756647cd0a17521a25421a5cf.
              Corpos copiados de database/schema/5149, 5150 e 5151
              (CONFIRMADO EXECUTADO / PROMOVIDO), alterados SÓ nos
              trechos marcados "5152".
Diagnóstico.: COLLECTION-BULK-ACTIVE-VARIANT-CHECK-01 — CONFIRMED-GAP:
              o preview aceitava variante inativa; a confirmação só era
              barrada indiretamente pelo trigger da 2268 (MV001, um id,
              no meio da escrita).

O que muda (nada além disto)
  1. 5149 preview_fingerprint_register_physical_cards: cada entrada do
     catálogo resolvido ganha 'is_active'. Desativar ou reativar uma
     variante depois do preview muda o fingerprint → PREVIEW_STALE.
  2. 5150 register_physical_cards_bulk: passo 6.2b, validação explícita
     com LISTA antes de qualquer escrita (CARD_VARIANT_INACTIVE, 22023,
     contagem + 10 primeiros + DETAIL completo).
  3. 5151 preview_bulk_operation: passo 3.5b, issue BLOCKING
     CARD_VARIANT_INACTIVE com a lista completa em offenders.

O que NÃO muda
  - Assinaturas, envelope, chaves, teto 1000, SECURITY DEFINER/INVOKER,
    volatilidade, search_path, ACL (REVOKE/GRANT reafirmados iguais).
  - Idempotência: REPLAY retorna no claim (5150 passo 3) ANTES do
    fingerprint e da validação (D9). Uma operação já concluída continua
    devolvendo REPLAY mesmo que a variante tenha sido desativada depois.
  - Ordem de locks (I9): 5150 não ganha lock próprio. O trigger
    trg_guard_card_variant_active (2268) segue intacto como última
    barreira para desativação concorrente.
  - Variantes ativas: nenhuma regra nova as afeta.
  - request_hash (5147): não muda.

Compatibilidade
  - Fingerprints emitidos ANTES da aplicação ficam inválidos (o material
    hasheado ganhou a chave is_active): a confirmação correspondente
    recebe PREVIEW_STALE e basta refazer o preview. Não há consumidor de
    frontend destas RPCs no repositório (busca em web/ e
    supabase/functions sem ocorrências em 2026-10-16).
  - bulk_operation.preview_fingerprint já gravado não é revalidado por
    nada (replay ignora fingerprint) — nenhum dado persistido muda.

Como validar: harness 5824 (esta pasta) + reexecução de 5822 e 5823.
================================================================
*/

BEGIN;

CREATE OR REPLACE FUNCTION public.preview_fingerprint_register_physical_cards(
    p_items                JSONB,
    p_collection_id        UUID DEFAULT NULL,
    p_storage_container_id UUID DEFAULT NULL
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY INVOKER
VOLATILE
SET search_path = ''
AS $$
DECLARE
    c_uuid_re CONSTANT TEXT :=
        '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';

    v_owner       UUID;
    v_inventory   UUID;
    -- Deliberadamente SQL NULL, NAO 'null'::jsonb. Se fossem
    -- inicializadas com 'null'::jsonb, um `SELECT ... INTO` sem linha
    -- deixaria a variavel intacta e o teste de "nao encontrado"
    -- passaria batido. A conversao para o JSON `null` acontece so na
    -- montagem do estado, no fim.
    v_collection  JSONB;
    v_storage     JSONB;
    v_catalog     JSONB;
    v_state       JSONB;
BEGIN
    v_owner := (select auth.uid());

    IF v_owner IS NULL THEN
        RAISE EXCEPTION 'authentication required' USING ERRCODE = '28000';
    END IF;

    -- Guard defensivo minimo. Os guards completos de contrato sao de
    -- `5150`; aqui basta garantir que o payload e navegavel.
    IF p_items IS NULL OR jsonb_typeof(p_items) IS DISTINCT FROM 'array' THEN
        RAISE EXCEPTION 'items deve ser um array JSON' USING ERRCODE = '22023';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM jsonb_array_elements(p_items) AS it(elem)
        WHERE jsonb_typeof(it.elem) IS DISTINCT FROM 'object'
           OR (it.elem ->> 'card_variant_id') !~* c_uuid_re
           OR (it.elem ->> 'language_id')     !~* c_uuid_re
    ) THEN
        RAISE EXCEPTION 'items contem elemento malformado ou UUID invalido'
            USING ERRCODE = '22023';
    END IF;

    SELECT inv.id INTO v_inventory
      FROM public.inventory inv
     WHERE inv.owner_user_id = v_owner;

    IF v_inventory IS NULL THEN
        RAISE EXCEPTION 'inventory not found for current user' USING ERRCODE = '22023';
    END IF;

    IF p_collection_id IS NOT NULL THEN
        SELECT jsonb_build_object(
                   'id',                     col.id::text,
                   'updated_at',             to_char(col.updated_at AT TIME ZONE 'UTC',
                                                     'YYYYMMDDHH24MISSUS'),
                   'lifecycle_status',       col.lifecycle_status,
                   'mode',                   col.mode,
                   'game_id',                col.game_id::text,
                   'reference_kind',         ref.reference_kind,
                   'reference_card_set_id',  ref.card_set_id::text
               )
          INTO v_collection
          FROM public.collection col
          LEFT JOIN LATERAL (
              SELECT cr.reference_kind, ccsr.card_set_id
                FROM public.collection_reference cr
                LEFT JOIN public.collection_card_set_reference ccsr
                       ON ccsr.collection_reference_id = cr.id
               WHERE cr.collection_id = col.id
          ) ref ON TRUE
         WHERE col.id = p_collection_id
           AND col.owner_user_id = v_owner;

        IF v_collection IS NULL THEN
            RAISE EXCEPTION 'collection not found or not owned by caller'
                USING ERRCODE = '22023';
        END IF;
    END IF;

    IF p_storage_container_id IS NOT NULL THEN
        SELECT jsonb_build_object(
                   'id',         sc.id::text,
                   'updated_at', to_char(sc.updated_at AT TIME ZONE 'UTC',
                                         'YYYYMMDDHH24MISSUS')
               )
          INTO v_storage
          FROM public.storage_container sc
         WHERE sc.id = p_storage_container_id
           AND sc.inventory_id = v_inventory;

        IF v_storage IS NULL THEN
            RAISE EXCEPTION 'storage container not found or not owned by caller'
                USING ERRCODE = '22023';
        END IF;
    END IF;

    -- Catalogo RESOLVIDO. Somente as tuplas que existem hoje entram.
    SELECT COALESCE(jsonb_agg(
               jsonb_build_object(
                   'card_variant_id', d.cv_id::text,
                   'language_id',     d.lang_id::text,
                   'card_set_id',     ca.card_set_id::text,
                   'game_id',         ex.game_id::text,
                   -- 5152: o estado de atividade da variante e estado do
                   -- mundo. Desativar (ou reativar) uma variante depois do
                   -- preview muda o fingerprint e a confirmacao cai em
                   -- PREVIEW_STALE.
                   'is_active',       cv.is_active
               )
           ), '[]'::jsonb)
      INTO v_catalog
      FROM (
          SELECT DISTINCT
                 (it.elem ->> 'card_variant_id')::uuid AS cv_id,
                 (it.elem ->> 'language_id')::uuid     AS lang_id
            FROM jsonb_array_elements(p_items) AS it(elem)
      ) d
      JOIN public.card_variant cv ON cv.id = d.cv_id
      JOIN public.card ca         ON ca.id = cv.card_id
      JOIN public.card_set cs     ON cs.id = ca.card_set_id
      JOIN public.expansion ex    ON ex.id = cs.expansion_id
      JOIN public.language l      ON l.id  = d.lang_id;

    -- COALESCE explicito: aqui, e so aqui, "ausente" vira o JSON `null`.
    v_state := jsonb_build_object(
        'operation',    'REGISTER_PHYSICAL_CARDS',
        'inventory_id', v_inventory::text,
        'collection',   COALESCE(v_collection, 'null'::jsonb),
        'storage',      COALESCE(v_storage,    'null'::jsonb),
        'catalog',      v_catalog
    );

    RETURN public.bulk_request_hash('PREVIEW:REGISTER_PHYSICAL_CARDS', v_state);
END;
$$;

COMMENT ON FUNCTION public.preview_fingerprint_register_physical_cards(JSONB, UUID, UUID) IS
    'FONTE UNICA do preview_fingerprint de B1. Helper INTERNO: EXECUTE revogado de PUBLIC/anon/authenticated/service_role. NAO e endpoint publico — a interface publica de Preview e BULK-03. VOLATILE, e nao STABLE: uma funcao STABLE usaria o snapshot do inicio da query chamadora e o recalculo poderia enxergar o estado ANTERIOR ao commit que liberou o lock de 5148, que e exatamente o que este fingerprint existe para detectar. SECURITY INVOKER: e chamada por 5150 (SECURITY DEFINER, owner postgres) e futuramente pela RPC SECURITY DEFINER de BULK-03; nao precisa de privilegio proprio. Cobre o ESTADO DO MUNDO que muda o resultado: Inventory, Collection (updated_at, lifecycle, mode, Game, Reference), Storage (updated_at) e o catalogo RESOLVIDO, incluindo card_variant.is_active (5152). quantity NAO entra: quantidade e intencao e mora no request_hash (D9). Somente leitura, sem lock.';

REVOKE EXECUTE ON FUNCTION public.preview_fingerprint_register_physical_cards(JSONB, UUID, UUID)
    FROM PUBLIC, anon, authenticated, service_role;

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
    v_missing           TEXT[];

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
    -- 6) VALIDACAO DE DOMINIO — toda ANTES de qualquer escrita.
    -- ============================================================

    -- 6.1) Lifecycle da Collection (lido sob lock no passo 4).
    IF v_collection_id IS NOT NULL AND v_scope.collection_lifecycle_status <> 'ACTIVE' THEN
        RAISE EXCEPTION 'collection is archived — reactivate before registering'
            USING ERRCODE = '22023';
    END IF;

    -- 6.2) card_variant_id INEXISTENTE — com LISTA.
    SELECT array_agg(d.cv_id::text ORDER BY d.cv_id::text)
      INTO v_missing
      FROM (
          SELECT DISTINCT (it.elem ->> 'card_variant_id')::uuid AS cv_id
            FROM jsonb_array_elements(v_items) AS it(elem)
      ) d
      LEFT JOIN public.card_variant cv ON cv.id = d.cv_id
     WHERE cv.id IS NULL;

    IF v_missing IS NOT NULL THEN
        RAISE EXCEPTION
            '% card_variant_id inexistente(s): %',
            cardinality(v_missing), array_to_string(v_missing[1:10], ', ')
            USING ERRCODE = '22023',
                  DETAIL  = 'lista completa: ' || array_to_string(v_missing, ', ');
    END IF;

    -- 6.2b) card_variant_id INATIVA — com LISTA (5152).
    --       Variante desativada preserva historico, mas nao aceita
    --       vinculo novo (2268). Validacao EXPLICITA, antes de qualquer
    --       escrita, no formato do contrato (contagem + 10 primeiros +
    --       DETAIL com a lista completa). Sem lock proprio: a ordem de
    --       locks continua exclusivamente em 5148 (I9). Uma desativacao
    --       concorrente que comite entre esta leitura e o INSERT do
    --       passo 7 continua barrada pelo trigger de 2268
    --       (trg_guard_card_variant_active, lock compartilhado), que permanece a
    --       ultima barreira; a transacao inteira, claim incluido, volta.
    SELECT array_agg(d.cv_id::text ORDER BY d.cv_id::text)
      INTO v_missing
      FROM (
          SELECT DISTINCT (it.elem ->> 'card_variant_id')::uuid AS cv_id
            FROM jsonb_array_elements(v_items) AS it(elem)
      ) d
      JOIN public.card_variant cv ON cv.id = d.cv_id
     WHERE NOT cv.is_active;

    IF v_missing IS NOT NULL THEN
        RAISE EXCEPTION
            'CARD_VARIANT_INACTIVE: % card_variant_id inativa(s), sem novos vinculos: %',
            cardinality(v_missing), array_to_string(v_missing[1:10], ', ')
            USING ERRCODE = '22023',
                  DETAIL  = 'lista completa: ' || array_to_string(v_missing, ', ');
    END IF;

    -- 6.3) language_id INEXISTENTE — com LISTA.
    SELECT array_agg(d.lang_id::text ORDER BY d.lang_id::text)
      INTO v_missing
      FROM (
          SELECT DISTINCT (it.elem ->> 'language_id')::uuid AS lang_id
            FROM jsonb_array_elements(v_items) AS it(elem)
      ) d
      LEFT JOIN public.language l ON l.id = d.lang_id
     WHERE l.id IS NULL;

    IF v_missing IS NOT NULL THEN
        RAISE EXCEPTION
            '% language_id inexistente(s): %',
            cardinality(v_missing), array_to_string(v_missing[1:10], ', ')
            USING ERRCODE = '22023',
                  DETAIL  = 'lista completa: ' || array_to_string(v_missing, ', ');
    END IF;

    IF v_collection_id IS NOT NULL THEN
        -- 6.4) GAME — replicado literalmente de 5046, com LISTA.
        SELECT array_agg(d.cv_id::text ORDER BY d.cv_id::text)
          INTO v_missing
          FROM (
              SELECT DISTINCT (it.elem ->> 'card_variant_id')::uuid AS cv_id
                FROM jsonb_array_elements(v_items) AS it(elem)
          ) d
          JOIN public.card_variant cv ON cv.id = d.cv_id
          JOIN public.card ca         ON ca.id = cv.card_id
          JOIN public.card_set cs     ON cs.id = ca.card_set_id
          JOIN public.expansion ex    ON ex.id = cs.expansion_id
         WHERE ex.game_id IS DISTINCT FROM v_scope.collection_game_id;

        IF v_missing IS NOT NULL THEN
            RAISE EXCEPTION
                '% card_variant_id pertence(m) a um Game diferente do Game da Collection: %',
                cardinality(v_missing), array_to_string(v_missing[1:10], ', ')
                USING ERRCODE = '22023',
                      DETAIL  = 'lista completa: ' || array_to_string(v_missing, ', ');
        END IF;

        -- 6.5) ELEGIBILIDADE de Reference — so quando REFERENCE_BASED
        --      com reference_kind = 'CARD_SET'. Identico a 5046.
        IF v_scope.collection_mode = 'REFERENCE_BASED'
           AND v_scope.collection_reference_kind = 'CARD_SET' THEN

            SELECT array_agg(d.cv_id::text ORDER BY d.cv_id::text)
              INTO v_missing
              FROM (
                  SELECT DISTINCT (it.elem ->> 'card_variant_id')::uuid AS cv_id
                    FROM jsonb_array_elements(v_items) AS it(elem)
              ) d
              JOIN public.card_variant cv ON cv.id = d.cv_id
              JOIN public.card ca         ON ca.id = cv.card_id
             WHERE ca.card_set_id IS DISTINCT FROM v_scope.collection_reference_card_set_id;

            IF v_missing IS NOT NULL THEN
                RAISE EXCEPTION
                    '% card_variant_id nao pertence(m) ao Card Set referenciado pela Collection: %',
                    cardinality(v_missing), array_to_string(v_missing[1:10], ', ')
                    USING ERRCODE = '22023',
                          DETAIL  = 'lista completa: ' || array_to_string(v_missing, ', ');
            END IF;
        END IF;
    END IF;

    -- ============================================================
    -- 7) ESCRITAS — set-based, sem loop por Physical Card.
    -- ============================================================
    WITH normalized AS (
        SELECT (it.elem ->> 'card_variant_id')::uuid    AS card_variant_id,
               (it.elem ->> 'language_id')::uuid        AS language_id,
               ((it.elem ->> 'quantity')::numeric)::int AS quantity
          FROM jsonb_array_elements(v_items) AS it(elem)
    ),
    inserted AS (
        INSERT INTO public.physical_card
            (card_variant_id, language_id, inventory_id, storage_container_id)
        SELECT n.card_variant_id, n.language_id, v_scope.inventory_id, v_storage_id
          FROM normalized n
          CROSS JOIN LATERAL generate_series(1, n.quantity) AS g(n)
        RETURNING physical_card.id,
                  physical_card.card_variant_id,
                  physical_card.language_id
    )
    SELECT array_agg(i.id ORDER BY i.card_variant_id, i.language_id, i.id)
      INTO v_created_ids
      FROM inserted i;

    v_created_count := COALESCE(cardinality(v_created_ids), 0);

    -- GUARD DE ATOMICIDADE. Divergencia aqui e invariante interno
    -- quebrado — falha alto, nunca sucesso parcial.
    IF v_created_count <> v_total_expanded THEN
        RAISE EXCEPTION
            'estado inconsistente: esperado criar % Physical Cards, criadas %',
            v_total_expanded, v_created_count
            USING ERRCODE = '55000';
    END IF;

    v_allocated_count := 0;

    IF v_collection_id IS NOT NULL THEN
        INSERT INTO public.collection_allocation (physical_card_id, collection_id)
        SELECT x, v_collection_id
          FROM unnest(v_created_ids) AS x;

        GET DIAGNOSTICS v_allocated_count = ROW_COUNT;

        IF v_allocated_count <> v_created_count THEN
            RAISE EXCEPTION
                'estado inconsistente: esperado alocar % Physical Cards, alocadas %',
                v_created_count, v_allocated_count
                USING ERRCODE = '55000';
        END IF;
    END IF;

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
    'B1 — registro em massa de Physical Cards. Assinatura congelada: p_request jsonb -> jsonb. Uma operacao logica = uma transacao, all-or-nothing, zero partial success. Teto de 1000 Physical Cards, validado no payload BRUTO e no TOTAL EXPANDIDO antes de qualquer escrita. quantity >= 1; duplicidade de (card_variant_id, language_id) comparada SEMANTICAMENTE como tupla de uuid e rejeitada — multiplicidade e somente por quantity. IDs invalidos ou inexistentes abortam com LISTA dos ofensores; card_variant inativa idem, com CARD_VARIANT_INACTIVE (5152). Caminho NEW: guards -> request_hash (5147) -> claim (5144) -> locks INVENTORY/COLLECTION/STORAGE (5148, fonte unica, I9) -> RECALCULO do preview_fingerprint dentro da transacao (5149) -> PREVIEW_STALE se divergir -> validacao -> escritas set-based -> complete (5145). REPLAY retorna no claim e NAO valida fingerprint (D9). request_hash derivado server-side e independente da ordem do JSON. add_physical_cards() (5012) e allocate_physical_cards_to_collection() (5046) permanecem canonicas e intocadas, com teto de 500, ate BULK-05. EXECUTE: authenticated SIM; PUBLIC/anon/service_role NAO.';

REVOKE EXECUTE ON FUNCTION public.register_physical_cards_bulk(JSONB)
    FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.register_physical_cards_bulk(JSONB)
    TO authenticated;

CREATE OR REPLACE FUNCTION public.preview_bulk_operation(p_request JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
VOLATILE
SET search_path = ''
AS $$
DECLARE
    -- Vocabulario FECHADO de `bulk_operation` (5142). Manter alinhado
    -- com `chk_bulk_operation_type`.
    c_vocabulary CONSTANT TEXT[] := ARRAY['REGISTER_PHYSICAL_CARDS',
                                          'REGISTER_CARD_SET'];
    -- Subconjunto que ESTA frente implementa.
    c_supported  CONSTANT TEXT[] := ARRAY['REGISTER_PHYSICAL_CARDS'];

    -- Teto literal, igual ao de 5150. Ver cabecalho.
    c_max_total  CONSTANT INT  := 1000;

    c_uuid_re    CONSTANT TEXT :=
        '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';

    v_operation_type  TEXT;
    v_items           JSONB;
    v_collection_id   UUID;
    v_storage_id      UUID;

    v_owner           UUID;
    v_inventory       UUID;

    v_raw_count       INT;
    v_distinct_count  INT;
    v_total_expanded  BIGINT;
    v_bad_ids         TEXT[];
    v_dups            TEXT[];
    v_missing         TEXT[];

    -- Escopo lido SEM lock. Só leitura, só para validar e resumir.
    v_col_found       BOOLEAN := FALSE;
    v_col_life        TEXT;
    v_col_game        UUID;
    v_col_mode        TEXT;
    v_ref_kind        TEXT;
    v_ref_card_set    UUID;
    v_stg_found       BOOLEAN := FALSE;

    v_issues          JSONB := '[]'::jsonb;
    v_fingerprint     TEXT;
    v_ok              BOOLEAN;
    v_summary         JSONB;
BEGIN
    -- ============================================================
    -- 0) AUTENTICACAO
    -- ============================================================
    v_owner := (select auth.uid());

    IF v_owner IS NULL THEN
        RAISE EXCEPTION 'authentication required' USING ERRCODE = '28000';
    END IF;

    -- ============================================================
    -- 1) GUARDS ESTRUTURAIS DO ENVELOPE — excecao, nunca `issues`.
    --    Nada e lido no banco antes daqui.
    -- ============================================================
    IF p_request IS NULL OR jsonb_typeof(p_request) IS DISTINCT FROM 'object' THEN
        RAISE EXCEPTION 'p_request deve ser um objeto JSON' USING ERRCODE = '22023';
    END IF;

    IF EXISTS (
        SELECT 1 FROM jsonb_object_keys(p_request) AS k(key)
        WHERE k.key NOT IN ('operation_type', 'items',
                            'collection_id', 'storage_container_id')
    ) THEN
        RAISE EXCEPTION
            'p_request aceita exatamente as chaves operation_type, items, collection_id e storage_container_id'
            USING ERRCODE = '22023';
    END IF;

    IF NOT (p_request ? 'operation_type') OR NOT (p_request ? 'items') THEN
        RAISE EXCEPTION 'p_request exige operation_type e items'
            USING ERRCODE = '22023';
    END IF;

    -- 1.1) operation_type — TRES situacoes distintas.
    IF jsonb_typeof(p_request -> 'operation_type') IS DISTINCT FROM 'string' THEN
        RAISE EXCEPTION 'operation_type deve ser uma string' USING ERRCODE = '22023';
    END IF;
    v_operation_type := p_request ->> 'operation_type';

    IF NOT (v_operation_type = ANY (c_vocabulary)) THEN
        RAISE EXCEPTION
            'operation_type invalido: % — valores aceitos: %',
            v_operation_type, array_to_string(c_vocabulary, ', ')
            USING ERRCODE = '22023';
    END IF;

    IF NOT (v_operation_type = ANY (c_supported)) THEN
        RAISE EXCEPTION
            'operation_type % pertence ao vocabulario, mas ainda nao e suportado pelo Preview nesta versao',
            v_operation_type
            USING ERRCODE = '22023',
                  DETAIL  = 'suportados nesta versao: ' ||
                            array_to_string(c_supported, ', ');
    END IF;

    -- 1.2) ids opcionais do envelope
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
    -- 2) GUARDS ESTRUTURAIS DE `items` — replicam LITERALMENTE os
    --    passos 1.2 a 1.4 e 1.6 de `5150`. Mesma ordem, mesmas
    --    mensagens, mesmo ERRCODE: um payload que passa aqui passa
    --    la, e um que estoura aqui estoura la com o mesmo texto.
    -- ============================================================
    v_items := p_request -> 'items';

    IF jsonb_typeof(v_items) IS DISTINCT FROM 'array' THEN
        RAISE EXCEPTION 'items deve ser um array JSON' USING ERRCODE = '22023';
    END IF;

    v_raw_count := jsonb_array_length(v_items);

    IF v_raw_count = 0 THEN
        RAISE EXCEPTION 'items nao pode ser vazio' USING ERRCODE = '22023';
    END IF;

    -- TETO DO PAYLOAD BRUTO.
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

    -- UUID sintaticamente invalido — com LISTA.
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

    -- quantity: inteiro e >= 1.
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

    -- TETO DO TOTAL EXPANDIDO.
    SELECT sum((it.elem ->> 'quantity')::numeric)
      INTO v_total_expanded
      FROM jsonb_array_elements(v_items) AS it(elem);

    IF v_total_expanded > c_max_total THEN
        RAISE EXCEPTION
            'a operacao criaria % Physical Cards e excede o limite de % por chamada',
            v_total_expanded, c_max_total
            USING ERRCODE = '22023';
    END IF;

    SELECT count(*) INTO v_distinct_count
      FROM (
          SELECT DISTINCT
                 (it.elem ->> 'card_variant_id')::uuid AS cv_id,
                 (it.elem ->> 'language_id')::uuid     AS lang_id
            FROM jsonb_array_elements(v_items) AS it(elem)
      ) d;

    -- ============================================================
    -- 3) A PARTIR DAQUI: `issues[]`, nunca excecao. Todas as
    --    verificacoes rodam ATE O FIM — o usuario ve TUDO de uma vez.
    -- ============================================================

    -- 3.1) DUPLICIDADE SEMANTICA (uuid, uuid). Cast normaliza caixa:
    --      concatenacao textual deixaria 'A1B2...' e 'a1b2...' passar.
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

        v_issues := v_issues || jsonb_build_array(jsonb_build_object(
            'code',      'DUPLICATE_ITEM',
            'severity',  'BLOCKING',
            'message',   format('%s par(es) (card_variant_id, language_id) duplicado(s) — multiplicidade e expressa somente por quantity',
                                cardinality(v_dups)),
            'offenders', to_jsonb(v_dups)
        ));
    END IF;

    -- 3.2) INVENTORY do chamador. Sem lock (Preview nao trava nada).
    SELECT inv.id INTO v_inventory
      FROM public.inventory inv
     WHERE inv.owner_user_id = v_owner;

    IF v_inventory IS NULL THEN
        v_issues := v_issues || jsonb_build_array(jsonb_build_object(
            'code',      'INVENTORY_NOT_FOUND',
            'severity',  'BLOCKING',
            'message',   'inventory nao encontrado para o usuario atual',
            'offenders', '[]'::jsonb
        ));
    END IF;

    -- 3.3) COLLECTION — ownership DENTRO do WHERE.
    --      NAO-ENUMERACAO: inexistente e de terceiro produzem
    --      exatamente o mesmo code e a mesma message.
    IF v_collection_id IS NOT NULL THEN
        SELECT TRUE, col.lifecycle_status, col.game_id, col.mode
          INTO v_col_found, v_col_life, v_col_game, v_col_mode
          FROM public.collection col
         WHERE col.id = v_collection_id
           AND col.owner_user_id = v_owner;

        IF NOT COALESCE(v_col_found, FALSE) THEN
            v_issues := v_issues || jsonb_build_array(jsonb_build_object(
                'code',      'COLLECTION_NOT_ACCESSIBLE',
                'severity',  'BLOCKING',
                'message',   'collection nao encontrada ou nao pertence ao chamador',
                'offenders', jsonb_build_array(v_collection_id::text)
            ));
        ELSE
            SELECT cr.reference_kind, ccsr.card_set_id
              INTO v_ref_kind, v_ref_card_set
              FROM public.collection_reference cr
              LEFT JOIN public.collection_card_set_reference ccsr
                     ON ccsr.collection_reference_id = cr.id
             WHERE cr.collection_id = v_collection_id;

            IF v_col_life <> 'ACTIVE' THEN
                v_issues := v_issues || jsonb_build_array(jsonb_build_object(
                    'code',      'COLLECTION_ARCHIVED',
                    'severity',  'BLOCKING',
                    'message',   'collection is archived — reactivate before registering',
                    'offenders', jsonb_build_array(v_collection_id::text)
                ));
            END IF;
        END IF;
    END IF;

    -- 3.4) STORAGE CONTAINER — `inventory_id` DENTRO do WHERE.
    --      Mesma nao-enumeracao. Se o inventory nem existe, o
    --      container jamais seria acessivel: o issue de INVENTORY ja
    --      esta registrado e este seria ruido redundante.
    IF v_storage_id IS NOT NULL AND v_inventory IS NOT NULL THEN
        SELECT TRUE INTO v_stg_found
          FROM public.storage_container sc
         WHERE sc.id = v_storage_id
           AND sc.inventory_id = v_inventory;

        IF NOT COALESCE(v_stg_found, FALSE) THEN
            v_issues := v_issues || jsonb_build_array(jsonb_build_object(
                'code',      'STORAGE_NOT_ACCESSIBLE',
                'severity',  'BLOCKING',
                'message',   'storage container nao encontrado ou nao pertence ao chamador',
                'offenders', jsonb_build_array(v_storage_id::text)
            ));
        END IF;
    END IF;

    -- 3.5) card_variant_id INEXISTENTE — com LISTA.
    SELECT array_agg(d.cv_id::text ORDER BY d.cv_id::text)
      INTO v_missing
      FROM (
          SELECT DISTINCT (it.elem ->> 'card_variant_id')::uuid AS cv_id
            FROM jsonb_array_elements(v_items) AS it(elem)
      ) d
      LEFT JOIN public.card_variant cv ON cv.id = d.cv_id
     WHERE cv.id IS NULL;

    IF v_missing IS NOT NULL THEN
        v_issues := v_issues || jsonb_build_array(jsonb_build_object(
            'code',      'CARD_VARIANT_NOT_FOUND',
            'severity',  'BLOCKING',
            'message',   format('%s card_variant_id inexistente(s)', cardinality(v_missing)),
            'offenders', to_jsonb(v_missing)
        ));
    END IF;

    -- 3.5b) card_variant_id INATIVA — com LISTA (5152).
    --        Variante desativada nao aceita vinculo novo (2268). Sem
    --        isso o Preview devolveria ok=true para um registro que a
    --        confirmacao recusaria.
    SELECT array_agg(d.cv_id::text ORDER BY d.cv_id::text)
      INTO v_missing
      FROM (
          SELECT DISTINCT (it.elem ->> 'card_variant_id')::uuid AS cv_id
            FROM jsonb_array_elements(v_items) AS it(elem)
      ) d
      JOIN public.card_variant cv ON cv.id = d.cv_id
     WHERE NOT cv.is_active;

    IF v_missing IS NOT NULL THEN
        v_issues := v_issues || jsonb_build_array(jsonb_build_object(
            'code',      'CARD_VARIANT_INACTIVE',
            'severity',  'BLOCKING',
            'message',   format('%s card_variant_id inativa(s), sem novos vinculos', cardinality(v_missing)),
            'offenders', to_jsonb(v_missing)
        ));
    END IF;

    -- 3.6) language_id INEXISTENTE — com LISTA.
    SELECT array_agg(d.lang_id::text ORDER BY d.lang_id::text)
      INTO v_missing
      FROM (
          SELECT DISTINCT (it.elem ->> 'language_id')::uuid AS lang_id
            FROM jsonb_array_elements(v_items) AS it(elem)
      ) d
      LEFT JOIN public.language l ON l.id = d.lang_id
     WHERE l.id IS NULL;

    IF v_missing IS NOT NULL THEN
        v_issues := v_issues || jsonb_build_array(jsonb_build_object(
            'code',      'LANGUAGE_NOT_FOUND',
            'severity',  'BLOCKING',
            'message',   format('%s language_id inexistente(s)', cardinality(v_missing)),
            'offenders', to_jsonb(v_missing)
        ));
    END IF;

    -- 3.7 / 3.8) GAME e ELEGIBILIDADE — so fazem sentido com uma
    --            Collection ACESSIVEL. Se ela nao foi resolvida, o
    --            issue dela ja esta na lista e avaliar estes dois
    --            produziria ruido sem informacao.
    IF v_collection_id IS NOT NULL AND COALESCE(v_col_found, FALSE) THEN

        -- 3.7) GAME — replicado literalmente de `5046`/`5150`.
        SELECT array_agg(d.cv_id::text ORDER BY d.cv_id::text)
          INTO v_missing
          FROM (
              SELECT DISTINCT (it.elem ->> 'card_variant_id')::uuid AS cv_id
                FROM jsonb_array_elements(v_items) AS it(elem)
          ) d
          JOIN public.card_variant cv ON cv.id = d.cv_id
          JOIN public.card ca         ON ca.id = cv.card_id
          JOIN public.card_set cs     ON cs.id = ca.card_set_id
          JOIN public.expansion ex    ON ex.id = cs.expansion_id
         WHERE ex.game_id IS DISTINCT FROM v_col_game;

        IF v_missing IS NOT NULL THEN
            v_issues := v_issues || jsonb_build_array(jsonb_build_object(
                'code',      'GAME_MISMATCH',
                'severity',  'BLOCKING',
                'message',   format('%s card_variant_id pertence(m) a um Game diferente do Game da Collection',
                                    cardinality(v_missing)),
                'offenders', to_jsonb(v_missing)
            ));
        END IF;

        -- 3.8) ELEGIBILIDADE de Reference — so REFERENCE_BASED com
        --      reference_kind = 'CARD_SET'. Identico a `5046`/`5150`.
        IF v_col_mode = 'REFERENCE_BASED' AND v_ref_kind = 'CARD_SET' THEN
            SELECT array_agg(d.cv_id::text ORDER BY d.cv_id::text)
              INTO v_missing
              FROM (
                  SELECT DISTINCT (it.elem ->> 'card_variant_id')::uuid AS cv_id
                    FROM jsonb_array_elements(v_items) AS it(elem)
              ) d
              JOIN public.card_variant cv ON cv.id = d.cv_id
              JOIN public.card ca         ON ca.id = cv.card_id
             WHERE ca.card_set_id IS DISTINCT FROM v_ref_card_set;

            IF v_missing IS NOT NULL THEN
                v_issues := v_issues || jsonb_build_array(jsonb_build_object(
                    'code',      'NOT_ELIGIBLE_FOR_REFERENCE',
                    'severity',  'BLOCKING',
                    'message',   format('%s card_variant_id nao pertence(m) ao Card Set referenciado pela Collection',
                                        cardinality(v_missing)),
                    'offenders', to_jsonb(v_missing)
                ));
            END IF;
        END IF;
    END IF;

    -- ============================================================
    -- 4) RESUMO — sempre devolvido, mesmo com ok = false: o usuario
    --    precisa ver a dimensao do que tentou fazer.
    -- ============================================================
    v_summary := jsonb_build_object(
        'distinct_items',       v_distinct_count,
        'total_quantity',       v_total_expanded::int,
        'will_create_count',    v_total_expanded::int,
        'will_allocate_count',  CASE WHEN v_collection_id IS NULL
                                     THEN 0 ELSE v_total_expanded::int END,
        'collection_id',        v_collection_id::text,
        'storage_container_id', v_storage_id::text
    );

    -- ============================================================
    -- 5) FINGERPRINT — calculado SO no caminho limpo.
    --    Com qualquer BLOCKING, o token NAO EXISTE. Nao ha como o
    --    cliente confirmar por engano um Preview reprovado.
    -- ============================================================
    v_ok := (jsonb_array_length(v_issues) = 0);

    IF v_ok THEN
        v_fingerprint := public.preview_fingerprint_register_physical_cards(
                             v_items, v_collection_id, v_storage_id
                         );

        -- Invariante interno: `5149` nunca devolve NULL/branco no
        -- caminho limpo. Se devolvesse, entregar `ok = true` com token
        -- inutil seria pior que falhar. Falha alto.
        IF v_fingerprint IS NULL OR btrim(v_fingerprint) = '' THEN
            RAISE EXCEPTION
                'estado inconsistente: preview_fingerprint vazio no caminho sem impedimentos'
                USING ERRCODE = '55000';
        END IF;
    END IF;

    RETURN jsonb_build_object(
        'operation_type',      v_operation_type,
        'ok',                  v_ok,
        'preview_fingerprint', v_fingerprint,
        'summary',             v_summary,
        'issues',              v_issues
    );
END;
$$;

COMMENT ON FUNCTION public.preview_bulk_operation(JSONB) IS
    'Interface PUBLICA de Preview da familia Bulk (BULK-03). Envelope fechado {operation_type, items, collection_id, storage_container_id}; SEM idempotency_key. Devolve {operation_type, ok, preview_fingerprint, summary, issues}. Contrato binario: ok=true => fingerprint NOT NULL e issues=[]; ok=false => fingerprint NULL e ao menos um issue BLOCKING — fingerprint de Preview reprovado nunca chega ao cliente. request_hash NAO e exposto (D-2/B4). Erros estruturais sao excecao; situacoes do usuario vao em issues[] com a lista completa de offenders (CARD_VARIANT_INACTIVE incluido em 5152). NAO escreve, NAO faz claim e NAO toma nenhum lock: e consultivo, e ok=true NAO e autorizacao — 5150 revalida tudo sob lock. SECURITY DEFINER e obrigatorio: 5149 le o catalogo, fechado a authenticated por RLS (ADR-022/ADR-030), e como INVOKER produziria fingerprint divergente do de 5150, quebrando 100% das execucoes com PREVIEW_STALE. Vocabulario 5142: REGISTER_CARD_SET e reconhecido mas ainda nao suportado, com mensagem propria. Teto 1000 literal, igual ao de 5150, com equivalencia provada comportamentalmente em 5823.';

REVOKE EXECUTE ON FUNCTION public.preview_bulk_operation(JSONB)
    FROM PUBLIC, anon, service_role;

GRANT EXECUTE ON FUNCTION public.preview_bulk_operation(JSONB)
    TO authenticated;

COMMIT;
