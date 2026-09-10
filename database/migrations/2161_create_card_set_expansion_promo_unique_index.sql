/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 2161 - Create Card Set Expansion Promo Unique Index
Arquivo.....: 2161_create_card_set_expansion_promo_unique_index.sql
Versão......: 1.1
Status......: **CONFIRMADO EXECUTADO** — ledger 20260910025017
Criado em...: 2026-09-09, em CATALOG-HISTORICAL-BOOTSTRAP-02-CARD-SETS-FINALIZATION-CORRECTION-01
Executado em: 2026-09-10, em CATALOG-HISTORICAL-BOOTSTRAP-02-CARD-SETS-FINALIZATION-IMPLEMENTATION-02

Histórico de execução:
  - IMPLEMENTATION-01 (v1.0): ABORTOU no pós-check, com rollback total e zero
    resíduo. Defeito EXCLUSIVO da assertiva, nunca do DDL: o pós-check casava
    `indexdef ILIKE '%WHERE (set_type%'`, mas `pg_get_indexdef()` injeta cast
    para coluna `character varying` e renderiza
    `WHERE ((set_type)::text = 'PROMO'::text)` — DOIS parênteses. Uma coluna
    `boolean` renderiza `WHERE (is_default = true)` — UM. Medido no schema
    `public`: 31 índices com um parêntese, 6 com dois.
  - IMPLEMENTATION-02 (v1.1): pós-check trocado por consulta ESTRUTURAL ao
    catálogo (`pg_index`/`pg_class`/`pg_namespace`/`pg_attribute`/
    `pg_get_expr`). Executado com sucesso. DDL, pré-flights e definição do
    índice permaneceram inalterados entre v1.0 e v1.1.

Estado após execução (medido):
  `uq_card_set_expansion_promo` presente; `card_set` com 4 índices;
  predicado real `((set_type)::text = 'PROMO'::text)`; 10 PROMO em 10
  Expansions; zero Expansion com mais de um PROMO.

Objetivo....:
Reconciliar o banco físico com a definição canônica: criar o índice único
parcial `uq_card_set_expansion_promo`, que garante no máximo um Card Set
promocional por Expansion (ADR-015).

Natureza da divergência (medida em 2026-09-09):

  - Definição canônica: CORRETA. `database/schema/120_create_card_set_table.sql`
    está na Versão 2.2 e JÁ contém o `CREATE UNIQUE INDEX` (linhas 117-119).
    O próprio arquivo registra o item aberto: "o banco físico atual foi
    construído pelo caminho antigo (120 v1.0 + migration 122), que não incluía
    o índice uq_card_set_expansion_promo. Não presumir que esse índice já
    existe no Supabase real até confirmação."
  - Banco físico: DIVERGENTE. `pg_class` confirma que o índice NÃO existe.
    `public.card_set` tem exatamente 3 índices: `card_set_pkey`,
    `uq_card_set_expansion_code`, `uq_card_set_expansion_release_order`.

Portanto esta Query NÃO altera a Query 120 — o canônico já está certo. Ela
existe só para trazer a instância física ao mesmo estado, exatamente como a
migration `122` fez em 2026-07-26 para o `set_type = 'PROMO'`.

Numeração....:
`2161` é livre e inequívoca. NÃO foi reutilizado `122`, que já existe
historicamente em `database/migrations/122_adapt_card_set_for_promo.sql`.
`2160` também foi evitado: é o número da Query one-shot de `release_order`
de Expansion, executada em 2026-09-09 (ledger `20260909231838`).

Promoção....:
Após execução confirmada, este arquivo vai para `database/migrations/`
(mesma classe de `122`: reconciliação de banco existente), NUNCA para
`database/schema/` — o objeto canônico já vive em `120` v2.2.

Atomicidade.:
Pré-flight, criação e pós-check vivem em UM ÚNICO bloco `DO`. Um bloco `DO`
é um único statement e, portanto, sua própria transação: qualquer
`RAISE EXCEPTION` desfaz a criação do índice por construção. Medido no canal
MCP em rodadas anteriores desta frente.

`CREATE UNIQUE INDEX` simples, NÃO `CONCURRENTLY`: a tabela tem 199 linhas,
não há justificativa de lock, e `CONCURRENTLY` impediria rodar dentro de
transação — perdendo justamente a atomicidade acima.

Resultado esperado:
  NOTICE  2161 OK: indice uq_card_set_expansion_promo criado. PROMO=10 em 10 Expansions.

Como validar:
  database/proposals/2026-09-09-card-sets-finalization/921_validate_card_set_finalization.sql
===============================================================================
*/

DO $$
DECLARE
    v_indice_existe   boolean;
    v_expansions_ruins integer;
    v_promo_total     integer;
    v_promo_expansions integer;
    v_indices_depois  integer;
BEGIN
    ---------------------------------------------------------------------------
    -- PRÉ-FLIGHT 1 — o índice ainda NÃO pode existir.
    -- Se já existir, alguém o criou fora deste caminho: parar e reavaliar,
    -- nunca sobrescrever silenciosamente.
    ---------------------------------------------------------------------------
    SELECT EXISTS (
        SELECT 1
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public'
          AND c.relname = 'uq_card_set_expansion_promo'
          AND c.relkind = 'i'
    ) INTO v_indice_existe;

    IF v_indice_existe THEN
        RAISE EXCEPTION
            '2161_PREFLIGHT_INDICE_JA_EXISTE: uq_card_set_expansion_promo já existe no banco físico. Nada a fazer — reavaliar a premissa desta Query antes de qualquer ação.';
    END IF;

    ---------------------------------------------------------------------------
    -- PRÉ-FLIGHT 2 — zero Expansion com mais de um PROMO.
    -- Escopo deliberadamente GLOBAL (todos os Games): o índice será global,
    -- então a pré-condição também precisa ser.
    ---------------------------------------------------------------------------
    SELECT count(*) INTO v_expansions_ruins
    FROM (
        SELECT expansion_id
        FROM public.card_set
        WHERE set_type = 'PROMO'
        GROUP BY expansion_id
        HAVING count(*) > 1
    ) v;

    IF v_expansions_ruins > 0 THEN
        RAISE EXCEPTION
            '2161_PREFLIGHT_PROMO_DUPLICADO: % Expansion(s) com mais de um Card Set PROMO. O índice não pode ser criado antes de resolver o dado.',
            v_expansions_ruins;
    END IF;

    SELECT count(*), count(DISTINCT expansion_id)
      INTO v_promo_total, v_promo_expansions
    FROM public.card_set
    WHERE set_type = 'PROMO';

    ---------------------------------------------------------------------------
    -- CRIAÇÃO — definição byte-idêntica à da Query 120 v2.2.
    ---------------------------------------------------------------------------
    EXECUTE $ddl$
        CREATE UNIQUE INDEX uq_card_set_expansion_promo
            ON public.card_set (expansion_id)
            WHERE set_type = 'PROMO'
    $ddl$;

    ---------------------------------------------------------------------------
    -- PÓS-CHECK — dentro da mesma transação. Falha aqui desfaz a criação.
    ---------------------------------------------------------------------------
    -- Assertiva ESTRUTURAL, via catálogo — não por casamento de string sobre
    -- pg_get_indexdef(). Corrigido em IMPLEMENTATION-02 após defeito medido:
    -- o Postgres injeta cast no predicado quando a coluna não é do tipo do
    -- literal, então `set_type` (character varying) renderiza como
    -- `WHERE ((set_type)::text = 'PROMO'::text)` — DOIS parênteses — enquanto
    -- uma coluna boolean renderiza `WHERE (is_default = true)` — UM. A
    -- assertiva anterior exigia um parêntese e reprovava um índice correto.
    SELECT count(*) INTO v_indices_depois
    FROM pg_index i
    JOIN pg_class ic ON ic.oid = i.indexrelid
    JOIN pg_class tc ON tc.oid = i.indrelid
    JOIN pg_namespace n ON n.oid = tc.relnamespace
    WHERE n.nspname   = 'public'
      AND tc.relname  = 'card_set'
      AND ic.relname  = 'uq_card_set_expansion_promo'
      AND i.indisunique
      AND i.indpred IS NOT NULL
      AND i.indnkeyatts = 1
      AND i.indkey[0] = (
          SELECT attnum FROM pg_attribute
          WHERE attrelid = tc.oid AND attname = 'expansion_id' AND NOT attisdropped
      )
      AND pg_get_expr(i.indpred, i.indrelid) ILIKE '%set_type%PROMO%';

    IF v_indices_depois <> 1 THEN
        RAISE EXCEPTION
            '2161_POSTCHECK_INDICE_NAO_CONFERE: esperado exatamente 1 índice único parcial sobre (expansion_id) WHERE set_type = PROMO, encontrado %.',
            v_indices_depois;
    END IF;

    RAISE NOTICE
        '2161 OK: indice uq_card_set_expansion_promo criado. PROMO=% em % Expansions.',
        v_promo_total, v_promo_expansions;
END
$$;
