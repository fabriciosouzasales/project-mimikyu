/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5158 - preview_bulk_operation (5151): braço B2 para
               REGISTER_CARD_SET (BULK-04)
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO / LIVE / PROMOVIDO (2026-10-16,
              ledger 20261016235910). Aplicado via apply_migration do
              Supabase, que envolve a migration em transacao propria
              (BEGIN/COMMIT deste arquivo omitidos no envio); corpo
              conferido byte a byte com o LIVE (md5 de prosrc).
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-16 (BULK04-B2-IMPLEMENTATION-PROPOSAL-01)
Pré-req.....: 5152, 5154, 5156.
Contrato....: BULK04-B2-MODELING-01 §5; decisões Q8 e I2/I3.

Base: corpo de 5151 na versão de 5152, preservado. Mudanças:
  1. c_supported passa a incluir 'REGISTER_CARD_SET'.
  2. Bloco 1.0 (logo após o guard de objeto JSON): quando
     operation_type é exatamente 'REGISTER_CARD_SET', o braço B2
     resolve o pedido e retorna. Qualquer outro pedido segue o caminho
     de REGISTER_PHYSICAL_CARDS, byte a byte igual ao de 5152.
  3. Variáveis v_b2_* declaradas.
  4. COMMENT atualizado.

Braço B2
  - Envelope fechado {operation_type, card_set_id, language_id,
    collection_id, storage_container_id}; guards -> exceção 22023.
  - Expansão via 5154; teto de 1000 -> exceção com a mesma mensagem
    da confirmação.
  - Issues próprias (BLOCKING): CARD_SET_NOT_FOUND, CARD_SET_EMPTY,
    CARD_DEFAULT_VARIANT_MISSING (offenders = card_id).
  - Demais issues: o próprio Preview do B1 chamado sobre os itens
    expandidos (sem duplicar checagens de Inventory, Collection,
    Storage, variante, idioma, Game e Reference).
  - Contrato binário mantido; fingerprint de B2 (5156) só no caminho
    limpo.
  - Sem escrita, sem lock, sem claim (como o B1).

Segurança, assinatura, volatilidade, search_path e ACL inalterados
(REVOKE/GRANT reafirmados iguais).
================================================================
*/

BEGIN;

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
    c_supported  CONSTANT TEXT[] := ARRAY['REGISTER_PHYSICAL_CARDS',
                                          'REGISTER_CARD_SET'];

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

    -- Braco B2 (REGISTER_CARD_SET, BULK-04).
    v_b2_set          UUID;
    v_b2_lang         UUID;
    v_b2_col          UUID;
    v_b2_sto          UUID;
    v_b2_exp          RECORD;
    v_b2_total        INT;
    v_b2_issues       JSONB;
    v_b2_inner        JSONB;
    v_b2_summary      JSONB;
    v_b2_ok           BOOLEAN;
    v_b2_fp           TEXT;
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

    -- ============================================================
    -- 1.0) BRACO B2 — REGISTER_CARD_SET (BULK-04).
    --      Envelope proprio e fechado: {operation_type, card_set_id,
    --      language_id, collection_id, storage_container_id}.
    --      Todo pedido cujo operation_type NAO seja exatamente
    --      'REGISTER_CARD_SET' segue o caminho de
    --      REGISTER_PHYSICAL_CARDS abaixo, sem nenhuma alteracao.
    --      O braco reaproveita o proprio Preview do B1 sobre os itens
    --      expandidos (5154): as checagens de Inventory, Collection,
    --      Storage, variante, idioma, Game e Reference existem uma vez
    --      so. O fingerprint e o de B2 (5156).
    -- ============================================================
    IF jsonb_typeof(p_request -> 'operation_type') = 'string'
       AND (p_request ->> 'operation_type') = 'REGISTER_CARD_SET' THEN

        IF EXISTS (
            SELECT 1 FROM jsonb_object_keys(p_request) AS k(key)
            WHERE k.key NOT IN ('operation_type', 'card_set_id', 'language_id',
                                'collection_id', 'storage_container_id')
        ) THEN
            RAISE EXCEPTION
                'p_request aceita exatamente as chaves operation_type, card_set_id, language_id, collection_id e storage_container_id'
                USING ERRCODE = '22023';
        END IF;

        IF NOT (p_request ? 'card_set_id') OR NOT (p_request ? 'language_id') THEN
            RAISE EXCEPTION 'p_request exige operation_type, card_set_id e language_id'
                USING ERRCODE = '22023';
        END IF;

        IF jsonb_typeof(p_request -> 'card_set_id') IS DISTINCT FROM 'string'
           OR (p_request ->> 'card_set_id') !~* c_uuid_re THEN
            RAISE EXCEPTION 'card_set_id deve ser um UUID valido' USING ERRCODE = '22023';
        END IF;
        v_b2_set := (p_request ->> 'card_set_id')::uuid;

        IF jsonb_typeof(p_request -> 'language_id') IS DISTINCT FROM 'string'
           OR (p_request ->> 'language_id') !~* c_uuid_re THEN
            RAISE EXCEPTION 'language_id deve ser um UUID valido' USING ERRCODE = '22023';
        END IF;
        v_b2_lang := (p_request ->> 'language_id')::uuid;

        IF (p_request ->> 'collection_id') IS NOT NULL THEN
            IF (p_request ->> 'collection_id') !~* c_uuid_re THEN
                RAISE EXCEPTION 'collection_id deve ser um UUID valido ou null'
                    USING ERRCODE = '22023';
            END IF;
            v_b2_col := (p_request ->> 'collection_id')::uuid;
        END IF;

        IF (p_request ->> 'storage_container_id') IS NOT NULL THEN
            IF (p_request ->> 'storage_container_id') !~* c_uuid_re THEN
                RAISE EXCEPTION 'storage_container_id deve ser um UUID valido ou null'
                    USING ERRCODE = '22023';
            END IF;
            v_b2_sto := (p_request ->> 'storage_container_id')::uuid;
        END IF;

        -- Expansao (5154). Teto: excecao, mesma mensagem da confirmacao.
        SELECT e.o_items, e.o_cards_without_default
          INTO v_b2_exp
          FROM public.bulk_expand_card_set(v_b2_set, v_b2_lang) AS e;

        v_b2_total := jsonb_array_length(v_b2_exp.o_items);

        IF v_b2_total > c_max_total THEN
            RAISE EXCEPTION
                'a operacao criaria % Physical Cards e excede o limite de % por chamada',
                v_b2_total, c_max_total
                USING ERRCODE = '22023';
        END IF;

        v_b2_issues := '[]'::jsonb;

        IF NOT EXISTS (SELECT 1 FROM public.card_set cs WHERE cs.id = v_b2_set) THEN
            v_b2_issues := v_b2_issues || jsonb_build_array(jsonb_build_object(
                'code',      'CARD_SET_NOT_FOUND',
                'severity',  'BLOCKING',
                'message',   'card set nao encontrado',
                'offenders', jsonb_build_array(v_b2_set::text)
            ));
        ELSIF v_b2_total = 0 AND v_b2_exp.o_cards_without_default IS NULL THEN
            v_b2_issues := v_b2_issues || jsonb_build_array(jsonb_build_object(
                'code',      'CARD_SET_EMPTY',
                'severity',  'BLOCKING',
                'message',   'card set sem nenhum card ativo',
                'offenders', jsonb_build_array(v_b2_set::text)
            ));
        END IF;

        IF v_b2_exp.o_cards_without_default IS NOT NULL THEN
            v_b2_issues := v_b2_issues || jsonb_build_array(jsonb_build_object(
                'code',      'CARD_DEFAULT_VARIANT_MISSING',
                'severity',  'BLOCKING',
                'message',   format('%s card(s) ativo(s) sem variante padrao',
                                    cardinality(v_b2_exp.o_cards_without_default)),
                'offenders', to_jsonb(v_b2_exp.o_cards_without_default)
            ));
        END IF;

        IF v_b2_total > 0 THEN
            -- Preview do B1 sobre a expansao: mesmas issues, mesma
            -- nao-enumeracao, mesmo summary. Itens gerados pelo servidor
            -- nunca violam os guards estruturais do B1.
            v_b2_inner := public.preview_bulk_operation(jsonb_build_object(
                'operation_type',       'REGISTER_PHYSICAL_CARDS',
                'items',                v_b2_exp.o_items,
                'collection_id',        v_b2_col::text,
                'storage_container_id', v_b2_sto::text
            ));
            v_b2_issues  := v_b2_issues || (v_b2_inner -> 'issues');
            v_b2_summary := (v_b2_inner -> 'summary')
                            || jsonb_build_object('card_set_id', v_b2_set::text,
                                                  'language_id', v_b2_lang::text);
        ELSE
            v_b2_summary := jsonb_build_object(
                'distinct_items',       0,
                'total_quantity',       0,
                'will_create_count',    0,
                'will_allocate_count',  0,
                'collection_id',        v_b2_col::text,
                'storage_container_id', v_b2_sto::text,
                'card_set_id',          v_b2_set::text,
                'language_id',          v_b2_lang::text
            );
        END IF;

        -- Contrato binario, como no B1: fingerprint SO no caminho limpo.
        v_b2_ok := (jsonb_array_length(v_b2_issues) = 0);

        IF v_b2_ok THEN
            v_b2_fp := public.preview_fingerprint_register_card_set(
                           v_b2_set, v_b2_lang, v_b2_col, v_b2_sto
                       );
            IF v_b2_fp IS NULL OR btrim(v_b2_fp) = '' THEN
                RAISE EXCEPTION
                    'estado inconsistente: preview_fingerprint vazio no caminho sem impedimentos'
                    USING ERRCODE = '55000';
            END IF;
        END IF;

        RETURN jsonb_build_object(
            'operation_type',      'REGISTER_CARD_SET',
            'ok',                  v_b2_ok,
            'preview_fingerprint', v_b2_fp,
            'summary',             v_b2_summary,
            'issues',              v_b2_issues
        );
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
    'Interface PUBLICA de Preview da familia Bulk (BULK-03). Envelope fechado {operation_type, items, collection_id, storage_container_id}; SEM idempotency_key. Devolve {operation_type, ok, preview_fingerprint, summary, issues}. Contrato binario: ok=true => fingerprint NOT NULL e issues=[]; ok=false => fingerprint NULL e ao menos um issue BLOCKING — fingerprint de Preview reprovado nunca chega ao cliente. request_hash NAO e exposto (D-2/B4). Erros estruturais sao excecao; situacoes do usuario vao em issues[] com a lista completa de offenders (CARD_VARIANT_INACTIVE incluido em 5152). NAO escreve, NAO faz claim e NAO toma nenhum lock: e consultivo, e ok=true NAO e autorizacao — 5150 revalida tudo sob lock. SECURITY DEFINER e obrigatorio: 5149 le o catalogo, fechado a authenticated por RLS (ADR-022/ADR-030), e como INVOKER produziria fingerprint divergente do de 5150, quebrando 100% das execucoes com PREVIEW_STALE. REGISTER_CARD_SET (BULK-04, 5158): envelope proprio {operation_type, card_set_id, language_id, collection_id, storage_container_id}; expande o Card Set (5154), reaproveita o Preview do B1 sobre os itens expandidos, acrescenta CARD_SET_NOT_FOUND, CARD_SET_EMPTY e CARD_DEFAULT_VARIANT_MISSING, e emite o fingerprint de B2 (5156). Teto 1000 literal, igual ao de 5150, com equivalencia provada comportamentalmente em 5823.';

REVOKE EXECUTE ON FUNCTION public.preview_bulk_operation(JSONB)
    FROM PUBLIC, anon, service_role;

GRANT EXECUTE ON FUNCTION public.preview_bulk_operation(JSONB)
    TO authenticated;

COMMIT;
