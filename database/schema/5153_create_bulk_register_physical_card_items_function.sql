/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5153 - Helper interno compartilhado B1/B2: validação de
               domínio e escrita de Physical Cards
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO / LIVE / PROMOVIDO (2026-10-16,
              ledger 20261016235518). Aplicado via apply_migration do
              Supabase, que envolve a migration em transacao propria
              (BEGIN/COMMIT deste arquivo omitidos no envio); corpo
              conferido byte a byte com o LIVE (md5 de prosrc).
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-16 (BULK04-B2-IMPLEMENTATION-PROPOSAL-01)
Pré-req.....: 5152 aplicada (corpo de 5150 com o passo 6.2b).
Decisão.....: I1 (aprovada) — a validação de domínio e a escrita de B1
              passam a ter UMA implementação, usada por B1 (5155) e B2
              (5157). Q9: sem segunda implementação.

Origem do corpo
  Passos 6 e 7 de register_physical_cards_bulk na versão de 5152,
  copiados LITERALMENTE. A única transformação é a troca de nomes de
  variáveis locais por parâmetros:
      v_items                                -> p_items
      v_collection_id                        -> p_collection_id
      v_storage_id                           -> p_storage_container_id
      v_scope.inventory_id                   -> p_inventory_id
      v_scope.collection_lifecycle_status    -> p_collection_lifecycle_status
      v_scope.collection_game_id             -> p_collection_game_id
      v_scope.collection_mode                -> p_collection_mode
      v_scope.collection_reference_kind      -> p_collection_reference_kind
      v_scope.collection_reference_card_set_id -> p_collection_reference_card_set_id
      v_total_expanded                       -> p_expected_total
      v_created_ids                          -> o_physical_card_ids
      v_allocated_count                      -> o_allocated_count
  Mensagens, SQLSTATE, ordem das validações e guards de atomicidade
  são os mesmos, caractere por caractere.

Contrato
  - Pré-condição (responsabilidade do chamador): p_items já passou pelos
    guards estruturais (array de objetos {card_variant_id, language_id,
    quantity}, UUIDs válidos, quantity inteiro >= 1, sem duplicidade,
    total <= 1000); claim feito; locks de 5148 tomados; fingerprint
    conferido. O helper NÃO revalida forma.
  - Não toma lock próprio (I9: ordem de locks só em 5148).
  - Falha => exceção; a transação do chamador é desfeita por inteiro,
    claim incluído. Nunca sucesso parcial.

Segurança
  SECURITY INVOKER, search_path vazio, owner postgres. EXECUTE revogado
  de PUBLIC, anon, authenticated e service_role: só é alcançável de
  dentro das RPCs SECURITY DEFINER (owner postgres) 5155 e 5157.
================================================================
*/

BEGIN;

CREATE FUNCTION public.bulk_register_physical_card_items(
    p_items                            JSONB,
    p_inventory_id                     UUID,
    p_collection_id                    UUID,
    p_storage_container_id             UUID,
    p_collection_lifecycle_status      TEXT,
    p_collection_game_id               UUID,
    p_collection_mode                  TEXT,
    p_collection_reference_kind        TEXT,
    p_collection_reference_card_set_id UUID,
    p_expected_total                   BIGINT,
    OUT o_physical_card_ids            UUID[],
    OUT o_allocated_count              INT
)
LANGUAGE plpgsql
SECURITY INVOKER
VOLATILE
SET search_path = ''
AS $$
DECLARE
    v_missing       TEXT[];
    v_created_count INT;
BEGIN
    -- ============================================================
    -- 6) VALIDACAO DE DOMINIO — toda ANTES de qualquer escrita.
    -- ============================================================

    -- 6.1) Lifecycle da Collection (lido sob lock no passo 4).
    IF p_collection_id IS NOT NULL AND p_collection_lifecycle_status <> 'ACTIVE' THEN
        RAISE EXCEPTION 'collection is archived — reactivate before registering'
            USING ERRCODE = '22023';
    END IF;

    -- 6.2) card_variant_id INEXISTENTE — com LISTA.
    SELECT array_agg(d.cv_id::text ORDER BY d.cv_id::text)
      INTO v_missing
      FROM (
          SELECT DISTINCT (it.elem ->> 'card_variant_id')::uuid AS cv_id
            FROM jsonb_array_elements(p_items) AS it(elem)
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
            FROM jsonb_array_elements(p_items) AS it(elem)
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
            FROM jsonb_array_elements(p_items) AS it(elem)
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

    IF p_collection_id IS NOT NULL THEN
        -- 6.4) GAME — replicado literalmente de 5046, com LISTA.
        SELECT array_agg(d.cv_id::text ORDER BY d.cv_id::text)
          INTO v_missing
          FROM (
              SELECT DISTINCT (it.elem ->> 'card_variant_id')::uuid AS cv_id
                FROM jsonb_array_elements(p_items) AS it(elem)
          ) d
          JOIN public.card_variant cv ON cv.id = d.cv_id
          JOIN public.card ca         ON ca.id = cv.card_id
          JOIN public.card_set cs     ON cs.id = ca.card_set_id
          JOIN public.expansion ex    ON ex.id = cs.expansion_id
         WHERE ex.game_id IS DISTINCT FROM p_collection_game_id;

        IF v_missing IS NOT NULL THEN
            RAISE EXCEPTION
                '% card_variant_id pertence(m) a um Game diferente do Game da Collection: %',
                cardinality(v_missing), array_to_string(v_missing[1:10], ', ')
                USING ERRCODE = '22023',
                      DETAIL  = 'lista completa: ' || array_to_string(v_missing, ', ');
        END IF;

        -- 6.5) ELEGIBILIDADE de Reference — so quando REFERENCE_BASED
        --      com reference_kind = 'CARD_SET'. Identico a 5046.
        IF p_collection_mode = 'REFERENCE_BASED'
           AND p_collection_reference_kind = 'CARD_SET' THEN

            SELECT array_agg(d.cv_id::text ORDER BY d.cv_id::text)
              INTO v_missing
              FROM (
                  SELECT DISTINCT (it.elem ->> 'card_variant_id')::uuid AS cv_id
                    FROM jsonb_array_elements(p_items) AS it(elem)
              ) d
              JOIN public.card_variant cv ON cv.id = d.cv_id
              JOIN public.card ca         ON ca.id = cv.card_id
             WHERE ca.card_set_id IS DISTINCT FROM p_collection_reference_card_set_id;

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
          FROM jsonb_array_elements(p_items) AS it(elem)
    ),
    inserted AS (
        INSERT INTO public.physical_card
            (card_variant_id, language_id, inventory_id, storage_container_id)
        SELECT n.card_variant_id, n.language_id, p_inventory_id, p_storage_container_id
          FROM normalized n
          CROSS JOIN LATERAL generate_series(1, n.quantity) AS g(n)
        RETURNING physical_card.id,
                  physical_card.card_variant_id,
                  physical_card.language_id
    )
    SELECT array_agg(i.id ORDER BY i.card_variant_id, i.language_id, i.id)
      INTO o_physical_card_ids
      FROM inserted i;

    v_created_count := COALESCE(cardinality(o_physical_card_ids), 0);

    -- GUARD DE ATOMICIDADE. Divergencia aqui e invariante interno
    -- quebrado — falha alto, nunca sucesso parcial.
    IF v_created_count <> p_expected_total THEN
        RAISE EXCEPTION
            'estado inconsistente: esperado criar % Physical Cards, criadas %',
            p_expected_total, v_created_count
            USING ERRCODE = '55000';
    END IF;

    o_allocated_count := 0;

    IF p_collection_id IS NOT NULL THEN
        INSERT INTO public.collection_allocation (physical_card_id, collection_id)
        SELECT x, p_collection_id
          FROM unnest(o_physical_card_ids) AS x;

        GET DIAGNOSTICS o_allocated_count = ROW_COUNT;

        IF o_allocated_count <> v_created_count THEN
            RAISE EXCEPTION
                'estado inconsistente: esperado alocar % Physical Cards, alocadas %',
                v_created_count, o_allocated_count
                USING ERRCODE = '55000';
        END IF;
    END IF;

END;
$$;

COMMENT ON FUNCTION public.bulk_register_physical_card_items(JSONB, UUID, UUID, UUID, TEXT, UUID, TEXT, TEXT, UUID, BIGINT) IS
    'FONTE UNICA da validacao de dominio e da escrita de Physical Cards da familia Bulk (B1 5155, B2 5157). Corpo = passos 6 e 7 de 5150 na versao de 5152, literal. Pre-condicao: guards estruturais, claim, locks (5148) e fingerprint ja feitos pelo chamador. Sem lock proprio (I9). Falha = excecao, all-or-nothing. Helper INTERNO: EXECUTE revogado de PUBLIC/anon/authenticated/service_role.';

REVOKE EXECUTE ON FUNCTION public.bulk_register_physical_card_items(JSONB, UUID, UUID, UUID, TEXT, UUID, TEXT, TEXT, UUID, BIGINT)
    FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
