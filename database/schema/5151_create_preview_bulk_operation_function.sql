/*
================================================================
Query 5151 — preview_bulk_operation()
================================================================
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO / LIVE / PROMOVIDO
Frente......: COLLECTIONS-BULK-03 — Preview
Rodada......: COLLECTIONS-BULK-03-MODELING-FINALIZATION-01
Baseline....: HEAD 07e2ba474a16f50b5f08a960debda7dec05b56e0
Depende de..: 5142-5146 (BULK-01), 5147-5150 (BULK-02), todos LIVE

Objetivo:
Interface PÚBLICA de Preview da família Bulk. Produz o
`preview_fingerprint` que a execução (`5150`) consome, e devolve ao
cliente, em UMA chamada, o resumo do que aconteceria e a LISTA
COMPLETA de impedimentos — sem escrever nada e sem tomar lock algum.

================================================================
ENVELOPE — CONTRATO FECHADO DE CHAVES
================================================================
    {
      "operation_type":       "REGISTER_PHYSICAL_CARDS",  -- obrigatorio
      "items":                [ ... ],                    -- obrigatorio
      "collection_id":        "<uuid>" | null,            -- opcional
      "storage_container_id": "<uuid>" | null             -- opcional
    }

Cada elemento de `items` — contrato FECHADO, IDÊNTICO ao de `5150`:

    { "card_variant_id": "<uuid>",
      "language_id":     "<uuid>",
      "quantity":        <int >= 1> }

SEM `idempotency_key`. Preview não faz claim, não escreve em
`bulk_operation`, não reserva nada. A assimetria com o envelope de
`5150` é DELIBERADA: quem lê os dois lado a lado precisa entender por
que um tem a chave e o outro não.

================================================================
RETORNO
================================================================
    {
      "operation_type":      "REGISTER_PHYSICAL_CARDS",
      "ok":                  true | false,
      "preview_fingerprint": "<text>" | null,
      "summary": {
        "distinct_items":       <int>,
        "total_quantity":       <int>,
        "will_create_count":    <int>,
        "will_allocate_count":  <int>,
        "collection_id":        "<uuid>" | null,
        "storage_container_id": "<uuid>" | null
      },
      "issues": [
        { "code": "<TEXT>", "severity": "BLOCKING",
          "message": "<pt-BR>", "offenders": [ "<uuid>", ... ] }
      ]
    }

CONTRATO BINÁRIO, sem estado intermediário:

  - `ok = true`   -> `preview_fingerprint` NOT NULL e nao-branco;
                     `issues` = `[]`.
  - `ok = false`  -> `preview_fingerprint` = JSON `null`;
                     `issues` com pelo menos um BLOCKING.

Fingerprint de um Preview invalido NUNCA e entregue ao cliente. Se
houver qualquer impedimento, o token simplesmente nao existe — nao ha
como o cliente confirmar por engano uma operacao que o Preview
reprovou. Essa e a razao de `preview_fingerprint` ser calculado DEPOIS
das validacoes, e nao antes.

`request_hash` NAO e devolvido. Ele e derivado server-side por `5150`
(decisao D-2 de BULK-02, que fechou o risco B4). Devolve-lo aqui nao
serviria a nenhum uso legitimo do cliente e so o convidaria a
manda-lo de volta — reabrindo B4 pela porta dos fundos.

================================================================
VOCABULÁRIO DE `operation_type`
================================================================
`bulk_operation` (`5142`) tem vocabulário FECHADO por
`chk_bulk_operation_type`: `REGISTER_PHYSICAL_CARDS` (B1) e
`REGISTER_CARD_SET` (B2).

Esta funcao distingue TRES situacoes, com mensagens diferentes:

  1. fora do vocabulario           -> 'operation_type invalido'
  2. no vocabulario, sem suporte   -> 'ainda nao suportado pelo Preview
                                       nesta versao'   (REGISTER_CARD_SET)
  3. suportado                     -> executa

A distincao entre (1) e (2) e exigencia explicita da rodada: um
cliente que mande `REGISTER_CARD_SET` esta usando um valor LEGITIMO do
dominio que esta frente ainda nao implementa — dizer-lhe que o valor e
"invalido" seria mentira e mandaria o desenvolvedor cacar o bug no
lugar errado.

================================================================
POR QUE `SECURITY DEFINER` — E NAO PREFERENCIA
================================================================
`5149` le `card_variant -> card -> card_set -> expansion` e `language`
para montar o array `catalog` do fingerprint. O Catalogo Editorial
(`ADR-022`) fecha essas tabelas ao `authenticated` comum: `public.card`
tem RLS habilitado SEM NENHUMA policy e `public.card_variant` tem so
`catalog_admin_select`, gated por `is_admin()`. Um `authenticated`
comum le ZERO linhas — fato confirmado por teste real e registrado em
`ADR-030` e no cabecalho de `5070`, que teve exatamente este bug
(`SECURITY INVOKER` -> resultado sempre 0) e foi corrigido para
`SECURITY DEFINER`.

Se esta funcao fosse `SECURITY INVOKER`, seu `catalog` viria VAZIO
para todo usuario real, enquanto `5150` — `SECURITY DEFINER` como
`postgres` — montaria o array CHEIO. Os dois fingerprints jamais
bateriam e **100% das execucoes falhariam com `PREVIEW_STALE`**. A
frente inteira nasceria morta, com o sintoma apontando para o lugar
errado.

`SECURITY DEFINER` troca o PRIVILEGIO, nunca a IDENTIDADE:
`auth.uid()` continua devolvendo o usuario real do JWT, entao
ownership, `inventory` e nao-enumeracao seguem corretos. E exatamente
o arranjo que `5150` ja usa.

`5149` e `SECURITY INVOKER`; chamada de dentro desta funcao, roda com
o privilegio efetivo do DEFINER (`postgres`) — o mesmo que tem quando
`5150` a chama. Igualdade de fingerprint por construcao.

`VOLATILE`: mesma disciplina de `5149`. Preview e uma leitura do
mundo AGORA; nao pode ser cacheado dentro da query chamadora.

================================================================
POR QUE NENHUM LOCK
================================================================
Preview NAO chama `5148`. Duas razoes:

  1. E um caminho de LEITURA, chamado a cada alteracao do payload na
     UI (com debounce). Travar `INVENTORY` a cada Preview serializaria
     a interface contra ela mesma.
  2. Preview e CONSULTIVO por definicao. Travar nao o tornaria
     autoritativo: entre o Preview e a confirmacao o mundo pode andar
     de qualquer jeito. O fingerprint e justamente o token que torna
     esse "andar" DETECTAVEL — e quem detecta e `5150`, sob lock.

Corolario que precisa estar escrito: **`ok = true` NAO e autorizacao.**
`5150` revalida tudo, sob lock, e continua sendo a unica autoridade.

================================================================
EXCECAO versus `issues[]`
================================================================
  - BUG DE CLIENTE      -> excecao (mesmos ERRCODE de `5150`).
    Envelope malformado, chave desconhecida, tipo errado, UUID
    sintaticamente invalido, `quantity` nao-inteira, teto estourado.
    O cliente nao deveria ter enviado isso; nao ha o que o usuario
    corrija na tela.

  - SITUACAO DO USUARIO -> `issues[]` com `ok = false`.
    Carta inexistente, Collection arquivada, Game divergente,
    duplicata. O usuario CONSEGUE corrigir, e precisa ver TUDO de uma
    vez: estourar no primeiro problema faz quem tem 300 cartas
    descobrir um erro por round-trip. Isso e um Preview inutil.

Assimetria deliberada com `5150`: la, duplicata e guard estrutural que
aborta. Aqui e `issues[]`. Nao ha contradicao — Preview e consultivo e
`5150` continua abortando. O contrato de seguranca nao depende do
Preview em nenhum ponto.

================================================================
NAO-ENUMERACAO
================================================================
Respostas estruturadas sao mais informativas que excecoes genericas —
e e exatamente ai que mora o risco. `5148`/`5149`/`5150` colapsam
deliberadamente "nao existe" e "e de terceiro" na MESMA mensagem.
`issues[]` preserva isso: `COLLECTION_NOT_ACCESSIBLE` e
`STORAGE_NOT_ACCESSIBLE` cobrem os dois casos, com mensagem identica e
sem nada que os distinga. Sem isso, o Preview viraria um oraculo de
enumeracao de recursos alheios — regressao de seguranca em relacao ao
que BULK-02 protegeu.

`offenders` traz apenas ids que o PROPRIO chamador enviou. Nao ha
vazamento: ele ja os conhecia.

================================================================
TETO DE CARDINALIDADE
================================================================
`c_max_total = 1000`, LITERAL, identico ao de `5150`.

`5150` esta `CLOSED / PROMOTED` e nao pode ser reaberto nesta frente,
entao nao ha helper compartilhado por ora — a constante e duplicada de
proposito. A garantia de que os dois tetos coincidem e
COMPORTAMENTAL, no harness `5823` (casos `T01`-`T04`): 1000 aceito e
1001 rejeitado, aqui e la. Nao se parseia o source de `5150`.

Registro honesto: duas fontes de verdade para o mesmo numero e divida,
nao virtude. A forma correta — `bulk_max_items(operation_type)` — fica
para quando `5150` for tocado por outro motivo legitimo.

================================================================
DEPENDENCIAS
================================================================
- public.preview_fingerprint_register_physical_cards (5149) — interna;
- public.inventory (5000), public.collection (5030+),
  public.storage_container (5020);
- public.collection_reference / collection_card_set_reference (5049+);
- catalogo: card_variant, card, card_set, expansion, language.

NAO depende de: `5147` (nao calcula hash), `5148` (nao trava nada),
`5144`/`5145` (nao faz claim), `bulk_operation` (nao escreve).

RESULTADO ESPERADO:
`CREATE FUNCTION`. Uma sobrecarga unica de
`public.preview_bulk_operation(jsonb)`, `SECURITY DEFINER`,
`VOLATILE`, `search_path` vazio, owner `postgres`, `EXECUTE` apenas
para `authenticated`.

COMO VALIDAR: harness `5823` (arquivo irmao desta pasta).

STATUS DESTA QUERY: CONFIRMADO EXECUTADO / LIVE / PROMOVIDO.
================================================================
*/

BEGIN;

CREATE FUNCTION public.preview_bulk_operation(p_request JSONB)
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
    'Interface PUBLICA de Preview da familia Bulk (BULK-03). Envelope fechado {operation_type, items, collection_id, storage_container_id}; SEM idempotency_key. Devolve {operation_type, ok, preview_fingerprint, summary, issues}. Contrato binario: ok=true => fingerprint NOT NULL e issues=[]; ok=false => fingerprint NULL e ao menos um issue BLOCKING — fingerprint de Preview reprovado nunca chega ao cliente. request_hash NAO e exposto (D-2/B4). Erros estruturais sao excecao; situacoes do usuario vao em issues[] com a lista completa de offenders. NAO escreve, NAO faz claim e NAO toma nenhum lock: e consultivo, e ok=true NAO e autorizacao — 5150 revalida tudo sob lock. SECURITY DEFINER e obrigatorio: 5149 le o catalogo, fechado a authenticated por RLS (ADR-022/ADR-030), e como INVOKER produziria fingerprint divergente do de 5150, quebrando 100% das execucoes com PREVIEW_STALE. Vocabulario 5142: REGISTER_CARD_SET e reconhecido mas ainda nao suportado, com mensagem propria. Teto 1000 literal, igual ao de 5150, com equivalencia provada comportamentalmente em 5823.';

REVOKE EXECUTE ON FUNCTION public.preview_bulk_operation(JSONB)
    FROM PUBLIC, anon, service_role;

GRANT EXECUTE ON FUNCTION public.preview_bulk_operation(JSONB)
    TO authenticated;

COMMIT;

/*
Como validar (APÓS aplicar): harness `5823`, todos os grupos.

Prova estática esperada:
- `prosecdef = true` (DEFINER) e `provolatile = 'v'` (VOLATILE);
- `proconfig` com `search_path` efetivamente vazio;
- exatamente UMA sobrecarga de `public.preview_bulk_operation`;
- `authenticated` com EXECUTE; `anon`, `service_role` e PUBLIC sem;
- corpo SEM `FOR UPDATE`, SEM `INSERT`, SEM `UPDATE`, SEM `DELETE`,
  SEM `bulk_lock_operation_scope` e SEM `claim_bulk_operation`.
*/
