/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5150 - register_physical_cards_bulk(p_request jsonb):
               B1 — registro em massa de Physical Cards
Versão......: 2.0
Status......: CONFIRMADO EXECUTADO (2026-09-09)
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-08 (COLLECTIONS-BULK-02-GATE-A-REVISION-01)

Descrição...:
RPC PÚBLICA. Primeira operação de negócio da frente Bulk (B1).
Reconciliada com `COLLECTIONS-BULK-OPERATIONS-MODELING-FINALIZATION-01`,
que permanece vinculante.

Uma operação lógica = uma transação. All-or-nothing, zero partial
success: ou tudo comita, ou nada é escrito e o próprio claim de
idempotência desaparece no ROLLBACK, liberando retry com a MESMA
`idempotency_key`.

================================================================
ASSINATURA CONGELADA
================================================================
    register_physical_cards_bulk(p_request JSONB) RETURNS JSONB

Envelope `p_request` — contrato FECHADO de chaves:

    {
      "idempotency_key":      "<uuid>",            -- obrigatorio
      "preview_fingerprint":  "<text nao-branco>", -- obrigatorio
      "items":                [ ... ],             -- obrigatorio
      "collection_id":        "<uuid>" | null,     -- opcional
      "storage_container_id": "<uuid>" | null      -- opcional
    }

Cada elemento de `items` — contrato FECHADO de chaves:

    { "card_variant_id": "<uuid>",
      "language_id":     "<uuid>",
      "quantity":        <int >= 1> }

Retorno:

    {
      "outcome":        "CREATED" | "REPLAY",
      "operation_id":   "<uuid>",
      "result_summary": {
        "operation_type":       "REGISTER_PHYSICAL_CARDS",
        "created_count":        <int>,
        "distinct_items":       <int>,
        "allocated_count":      <int>,
        "collection_id":        "<uuid>" | null,
        "storage_container_id": "<uuid>" | null,
        "physical_card_ids":    [ "<uuid>", ... ]
      }
    }

`CONFLICT` NÃO é um `outcome`: vira exceção `BULK_IDEMPOTENCY_CONFLICT`.
Sucesso e conflito não compartilham canal.

================================================================
CAMINHO NEW — ORDEM OBRIGATÓRIA
================================================================
    1. GUARDS estruturais do envelope e do payload
       (nada tocado no banco)
    2. request_hash canonico  ......... 5147, fonte unica
    3. CLAIM  ......................... 5144
         CONFLICT -> BULK_IDEMPOTENCY_CONFLICT
         REPLAY   -> RETORNA AQUI. Sem locks, sem fingerprint,
                     sem validacao, sem escrita.
    4. LOCKS  ......................... 5148, fonte unica
         INVENTORY -> COLLECTION -> STORAGE
    5. RECALCULO do preview_fingerprint DENTRO da transacao . 5149
         divergencia -> PREVIEW_STALE
    6. VALIDACAO de dominio
    7. ESCRITAS set-based
    8. complete_bulk_operation()  ..... 5145

Ordem canônica COMPLETA de locks, portanto:

    BULK_OPERATION -> INVENTORY -> COLLECTION -> STORAGE

================================================================
POR QUE O FINGERPRINT É CONFERIDO AQUI, E NÃO NA APLICAÇÃO
================================================================
TOCTOU. Conferir na aplicação, antes da chamada, deixa uma janela
entre a leitura e a transação em que o mundo pode mudar: a operação
escreveria sobre estado diferente do conferido e o `PREVIEW_STALE`
jamais dispararia.

Aqui a conferência é feita DEPOIS dos locks de `5148`. O estado
conferido é literalmente o estado travado sobre o qual se escreve — a
janela tem largura zero.

**REPLAY não confere fingerprint (D9).** O retorno acontece no passo 3,
antes do passo 5. Repetir uma intenção já concluída não pode falhar
porque o mundo andou depois. `claim_bulk_operation()` também nunca
consultou fingerprint — isso é coerência, não coincidência.

================================================================
POR QUE B1 NÃO CHAMA add_physical_cards() / allocate_...()
================================================================
Correção da justificativa anterior, que estava ERRADA: várias chamadas
internas dentro da MESMA transação **não** quebrariam atomicidade por
si só — tudo cairia junto no ROLLBACK. Aquele argumento não se
sustenta e foi descartado.

Os motivos reais, todos verificáveis no código canônico:

  1. TETO. `add_physical_cards()` (`5012`) rejeita array com mais de
     500 elementos; `allocate_physical_cards_to_collection()` (`5046`)
     rejeita mais de 500 ids. O contrato novo de B1 é 1000 Physical
     Cards criados. Fatiar em duas chamadas por helper só para caber
     é contorcer o helper, não reusá-lo.
  2. `quantity`. `add_physical_cards()` não tem multiplicidade: 1000
     cartas exigiriam 1000 elementos no array — que ela rejeita. A
     expansao teria de acontecer no cliente, jogando para fora do
     banco a validacao do total expandido que o contrato manda fazer
     ANTES das escritas.
  3. PERFORMANCE. O caminho de B1 é um `INSERT ... SELECT` com
     `generate_series`; passar por dois helpers acrescenta parsing,
     revalidacao e materializacao de arrays intermediarios sem
     ganho algum.
  4. PRESERVAÇÃO. `add_physical_cards()` e
     `allocate_physical_cards_to_collection()` seguem canônicas, com
     teto de 500 e todos os seus callers, **até BULK-05**. Nenhuma
     delas é alterada, removida ou migrada nesta frente.

As garantias estruturais continuam valendo como defesa em
profundidade: os triggers `5042` (integridade de allocation) e `5045`
(materializacao de `started_at`) são `FOR EACH STATEMENT` e disparam
normalmente sobre as escritas daqui — uma vez, não uma por carta.

================================================================
IDs INVÁLIDOS OU INEXISTENTES — LISTA, NÃO BOOLEANO
================================================================
Contrato congelado: abortar com a LISTA dos itens ofensores, ANTES das
escritas. Vale para as três classes:

  - UUID sintaticamente invalido  (passo 1, antes do claim);
  - `card_variant_id` inexistente (passo 6);
  - `language_id` inexistente     (passo 6).

A mensagem carrega a contagem e os 10 primeiros; o `DETAIL` carrega a
lista completa. Nunca uma violação crua de FK vinda do meio da escrita.

================================================================
DUPLICIDADE — SEMÂNTICA, NÃO TEXTUAL
================================================================
A comparação é de tuplas `(card_variant_id::uuid, language_id::uuid)`.
Concatenação de texto cru consideraria `A1B2...` e `a1b2...` valores
diferentes e deixaria passar uma duplicata real, porque UUID é
case-insensitive. O cast normaliza antes de comparar — e o mesmo cast
alimenta o `request_hash`, então intenção e validação enxergam
exatamente as mesmas tuplas.

Não há deduplicação silenciosa: multiplicidade é SOMENTE por
`quantity`, então repetir a tupla é ambiguidade de intenção e vira
erro.

================================================================
SEGURANÇA
================================================================
`SECURITY DEFINER`, `search_path = ''`, owner `postgres`, referências
qualificadas.

    PUBLIC .......... sem EXECUTE
    anon ............ sem EXECUTE
    service_role .... sem EXECUTE
    authenticated ... COM EXECUTE

`auth.uid()` é o único determinante de ownership — resolvido dentro de
`5148`/`5149`, nunca informado pelo chamador. Não-enumeração:
Collection e Storage inexistentes ou de terceiro produzem a MESMA
mensagem, e nenhuma linha alheia chega a ser travada.

`bulk_operation` segue sem caminho de acesso direto para papel algum.
Esta RPC roda como `postgres` e por isso alcança os helpers internos
(`5144`/`5145`/`5147`/`5148`/`5149`), cujo `EXECUTE` está revogado de
todos os papéis de aplicação.

`5149` é `SECURITY INVOKER`: chamada de dentro desta função, o usuário
efetivo já é `postgres` (owner), então ela alcança catálogo e
patrimônio sem privilégio próprio. **Ela NÃO é endpoint público** — a
interface pública de Preview será `BULK-03`.

================================================================
PERFORMANCE
================================================================
Sem loop por Physical Card. A expansão de `quantity` é
`CROSS JOIN LATERAL generate_series(1, quantity)` dentro de um único
`INSERT ... SELECT`; a alocação é um segundo `INSERT ... SELECT` sobre
o array de ids retornado. Duas escritas set-based, sejam 1 ou 1000
cartas. Nenhuma TEMP TABLE — precedente `5079`.

Dependências:
- public.bulk_canonical_json / bulk_request_hash (5147);
- public.bulk_lock_operation_scope (5148);
- public.preview_fingerprint_register_physical_cards (5149);
- public.bulk_operation (5142) + trigger 5143 + CHECK 5146;
- public.claim_bulk_operation (5144) / complete_bulk_operation (5145);
- public.inventory (5000), public.physical_card (5010/5023);
- public.storage_container (5020);
- public.collection (5030/5060/5067/5078/5086);
- public.collection_allocation (5040) + triggers 5042/5045;
- public.collection_reference / collection_card_set_reference (5049+);
- catálogo: card_variant, card, card_set, expansion, language.

STATUS DESTA QUERY: CONFIRMADO EXECUTADO (2026-09-09). Ledger e
equivalencia com a copia canonica em database/schema/ registrados no
README.md desta pasta.
================================================================
*/

BEGIN;

CREATE FUNCTION public.register_physical_cards_bulk(p_request JSONB)
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
    'B1 — registro em massa de Physical Cards. Assinatura congelada: p_request jsonb -> jsonb. Uma operacao logica = uma transacao, all-or-nothing, zero partial success. Teto de 1000 Physical Cards, validado no payload BRUTO e no TOTAL EXPANDIDO antes de qualquer escrita. quantity >= 1; duplicidade de (card_variant_id, language_id) comparada SEMANTICAMENTE como tupla de uuid e rejeitada — multiplicidade e somente por quantity. IDs invalidos ou inexistentes abortam com LISTA dos ofensores. Caminho NEW: guards -> request_hash (5147) -> claim (5144) -> locks INVENTORY/COLLECTION/STORAGE (5148, fonte unica, I9) -> RECALCULO do preview_fingerprint dentro da transacao (5149) -> PREVIEW_STALE se divergir -> validacao -> escritas set-based -> complete (5145). REPLAY retorna no claim e NAO valida fingerprint (D9). request_hash derivado server-side e independente da ordem do JSON. add_physical_cards() (5012) e allocate_physical_cards_to_collection() (5046) permanecem canonicas e intocadas, com teto de 500, ate BULK-05. EXECUTE: authenticated SIM; PUBLIC/anon/service_role NAO.';

REVOKE EXECUTE ON FUNCTION public.register_physical_cards_bulk(JSONB)
    FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.register_physical_cards_bulk(JSONB)
    TO authenticated;

COMMIT;

/*
Como validar (APÓS aplicar): harness `5822`, protocolo de três chamadas
de BULK-01 (BEGIN..relatório / ROLLBACK / postcheck externo
baseline-relativo).

Verificação estrutural rápida:

SELECT p.prosecdef,
       p.proconfig,
       pg_get_userbyid(p.proowner)                               AS owner,
       pg_get_function_identity_arguments(p.oid)                 AS args,
       pg_get_function_result(p.oid)                             AS ret,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') AS auth_exec,
       has_function_privilege('anon',          p.oid, 'EXECUTE') AS anon_exec,
       has_function_privilege('service_role',  p.oid, 'EXECUTE') AS svc_exec,
       (SELECT count(*) FROM aclexplode(p.proacl) a WHERE a.grantee = 0) AS public_grants
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'register_physical_cards_bulk';

Esperado: prosecdef=t, proconfig={search_path=}, owner=postgres,
args='p_request jsonb', ret='jsonb',
auth_exec=t, anon_exec=f, svc_exec=f, public_grants=0.
*/
