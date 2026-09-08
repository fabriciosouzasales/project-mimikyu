/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5127 - Create reorder_layout_pages()
Versão......: 4.0
Status......: CONFIRMADO EXECUTADO / LIVE / PROMOVIDO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-06 (staging em
               COLLECTIONS-BINDER-LAYOUT-FOUNDATION-STAGING-01)

Descrição...:
Reordena as Pages de um Layout. Recebe o conjunto COMPLETO de page_ids
na nova ordem e atribui page_number = 1..N conforme a posição no array.

Exige o conjunto completo, e não um "mover a Page X para a posição Y",
por três razões: (1) torna a contiguidade 1..N verificável antes de
escrever; (2) elimina toda a aritmética de deslocamento e seus casos
de borda; (3) casa com o que a UX faria de qualquer forma (a tela
conhece a lista inteira).

Validações antes de escrever:
- nenhum id duplicado no array;
- cardinalidade igual ao total de Pages do Layout;
- todo id pertence ao Layout.
Divergência em qualquer uma delas rejeita a operação inteira.

Page identity != Page order (C-39): reordenar NUNCA recria a Page nem
afeta identidade, row ou column de seus Slots. Este UPDATE toca
exclusivamente page_number.

A UNIQUE (layout_id, page_number) DEFERRABLE INITIALLY DEFERRED (Query
5108) é o que permite o UPDATE em bloco: estados intermediários
colidentes são tolerados e a unicidade é verificada só no COMMIT.
Sem DEFERRABLE, seria preciso um passo de offset temporário.

Concorrência: assert_collection_layout_mutable() locka o Layout FOR
UPDATE, serializando reorder contra add/remove concorrentes.

Dependências:
- public.assert_collection_layout_mutable() (Query 5122).
- public.collection_layout_page (Query 5108).

CORREÇÃO CONSOLIDADA 01 (2026-09-06,
COLLECTIONS-BINDER-LAYOUT-FOUNDATION-CONSOLIDATED-CORRECTION-01):
§3 POST-LOCK REVALIDATION. A v1.0 chamava o helper (que lockava o
Layout) e em seguida contava/validava as Pages — mas nunca lockava as
Pages em si. Como a validação e a renumeração são statements
separados, uma remoção concorrente de Page entre a contagem e o
UPDATE deixaria a renumeração inconsistente. Agora as Pages do Layout
são lockadas em ordem determinística e TODAS as contagens
(total/pertencimento) são refeitas DEPOIS do lock.

CORREÇÃO CONSOLIDADA 02 (2026-09-06,
COLLECTIONS-BINDER-LAYOUT-FOUNDATION-CONSOLIDATED-CORRECTION-02):
§2 SHORT-CIRCUIT DE CARDINALIDADE ANTES DO unnest/DISTINCT.

Esta RPC NÃO recebe teto artificial de 500: o contrato de reorder é
"todas as Pages do Layout, na nova ordem", e um Binder legítimo pode
ter mais Pages do que isso. Impor 500 aqui quebraria produto.

O que estava errado era a ORDEM das validações. A v2.0 executava
`count(DISTINCT x) FROM unnest(p_page_ids_ordered)` — trabalho
proporcional ao payload — ANTES de comparar o tamanho do payload com
o total de Pages que o banco já conhece. Um `UUID[]` arbitrariamente
grande forçava sort/DISTINCT dentro de uma função SECURITY DEFINER
antes de ser rejeitado por uma cardinalidade trivialmente verificável.

Ordem correta, agora implementada:
 1. helper (auth + COLLECTION LOCK -> LAYOUT LOCK + ACTIVE);
 2. array não NULL / não vazio;
 3. v_input_count := cardinality(...)           — O(1);
 4. v_total_pages, com o Layout JÁ LOCKADO pelo helper;
 5. v_input_count <> v_total_pages -> FALHA IMEDIATA (short-circuit);
 6. só então count(DISTINCT ...) via unnest;
 7. duplicados;
 8. PAGE LOCK determinístico;
 9. REVALIDAÇÃO PÓS-LOCK de total e pertencimento (preservada da
    v2.0 — nenhuma garantia de concorrência foi perdida);
10. reorder.

CORREÇÃO CONSOLIDADA 03 (2026-09-06,
COLLECTIONS-BINDER-LAYOUT-FOUNDATION-CONSOLIDATED-CORRECTION-03):
§1 CARDINALIDADE REAL DE UUID[] — BLOCKER DA FINAL MATERIAL AUDIT.

A CORREÇÃO 02 media o payload com `array_length(p_page_ids_ordered, 1)`,
que enxerga APENAS a primeira dimensão. Um payload multidimensional
`ARRAY[[a,b],[c,d]]` tem `array_length(x,1) = 2` mas `cardinality(x) = 4`
e `unnest()` de 4 linhas: o short-circuit de cardinalidade podia ser
enganado — bastava que a PRIMEIRA DIMENSÃO coincidisse com o total de
Pages para o payload atravessar o gate e chegar ao `unnest`/`DISTINCT`.

Corrigido:
  1. NULL                   -> 'não pode ser vazio';
  2. cardinality(...) = 0   -> 'não pode ser vazio';
  3. array_ndims(...) <> 1  -> 'deve ser um array unidimensional'
                               (ANTES de qualquer unnest/DISTINCT);
  4. v_input_count := cardinality(...) — quantidade REAL;
  5. short-circuit de cardinalidade contra v_total_pages, ainda ANTES
     do unnest/DISTINCT.

Continua SEM teto artificial: o contrato de reorder é "todas as Pages
do Layout", e um cap fixo quebraria produto num Binder grande. O
bounded work vem do próprio short-circuit: o payload só chega ao
`unnest` se a cardinalidade REAL já bater com o total de Pages que o
banco conhece — e esse total é, por construção, limitado pelo Layout.

Page locks e revalidação pós-lock preservados integralmente.

STATUS DESTA QUERY: CONFIRMADO EXECUTADO / LIVE / PROMOVIDO.

Aplicada ao banco real em 2026-09-07, na rodada
`COLLECTIONS-BINDER-LAYOUT-FOUNDATION-IMPLEMENTATION-01`. Validada por
`5818` v7.2 (196/196 runtime, FAIL 0) e por `5819` v3.0 (22/22 HEALTHY,
nenhum indice novo criado). Ledger e evidencia completa em
`database/proposals/2026-09-06-binder-layout-foundation/README.md`.

Promovida para `database/schema/` em `SCHEMA-PROMOTION-RECONCILIATION-01`
(2026-09-08). A copia historica permanece em
`database/proposals/2026-09-06-binder-layout-foundation/`, junto com os
harnesses `5818`/`5819`, o roteiro `CONCURRENCY-PROOF-C04-R18.sql` e o
`README.md` da rodada — esses quatro NAO sao promovidos, por convencao.
A promocao alterou apenas cabecalho/rodape: o corpo executavel
(`BEGIN;` .. `COMMIT;`) permanece byte-identico ao da copia em proposals.
================================================================
*/

BEGIN;

CREATE OR REPLACE FUNCTION public.reorder_layout_pages(
    p_layout_id        UUID,
    p_page_ids_ordered UUID[]
)
RETURNS TABLE (
    id          UUID,
    page_number INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_total_pages    INTEGER;
    v_input_count    INTEGER;
    v_distinct_count INTEGER;
    v_belong_count   INTEGER;
BEGIN
    -- COLLECTION LOCK -> LAYOUT LOCK + ACTIVE (helper 5122).
    PERFORM public.assert_collection_layout_mutable(p_layout_id);

    IF p_page_ids_ordered IS NULL THEN
        RAISE EXCEPTION 'p_page_ids_ordered não pode ser vazio';
    END IF;

    -- (2b) §1 CORREÇÃO CONSOLIDADA 03 — CARDINALIDADE REAL, O(1).
    -- cardinality() conta TODOS os elementos em qualquer número de
    -- dimensões; array_length(x,1) contaria apenas a primeira e
    -- permitiria bypass multidimensional do short-circuit.
    v_input_count := cardinality(p_page_ids_ordered);

    IF v_input_count = 0 THEN
        RAISE EXCEPTION 'p_page_ids_ordered não pode ser vazio';
    END IF;

    -- (2c) CONTRATO DE FORMA: somente array unidimensional. Avaliado
    -- ANTES de qualquer unnest/DISTINCT.
    IF array_ndims(p_page_ids_ordered) <> 1 THEN
        RAISE EXCEPTION
            'p_page_ids_ordered deve ser um array unidimensional (recebido array com % dimensões)',
            array_ndims(p_page_ids_ordered);
    END IF;

    -- (4) Total de Pages, com o Layout JÁ LOCKADO pelo helper acima.
    SELECT count(*) INTO v_total_pages
      FROM public.collection_layout_page p
     WHERE p.layout_id = p_layout_id;

    -- (5) SHORT-CIRCUIT (§2 CORREÇÃO CONSOLIDADA 02): rejeita ANTES de
    -- qualquer unnest/DISTINCT. Nenhum trabalho proporcional ao payload
    -- é executado por uma chamada que já se sabe inválida.
    IF v_input_count <> v_total_pages THEN
        RAISE EXCEPTION
            'p_page_ids_ordered deve conter todas as % Pages do Layout (recebidas %)',
            v_total_pages, v_input_count;
    END IF;

    -- (6) SOMENTE DEPOIS do short-circuit: unnest + DISTINCT.
    SELECT count(DISTINCT x) INTO v_distinct_count
      FROM unnest(p_page_ids_ordered) AS x;

    -- (7) Duplicados.
    IF v_distinct_count <> v_input_count THEN
        RAISE EXCEPTION 'p_page_ids_ordered contém ids duplicados';
    END IF;

    -- (8) PAGE LOCK em ordem determinística.
    PERFORM 1
       FROM public.collection_layout_page p
      WHERE p.layout_id = p_layout_id
      ORDER BY p.id
      FOR UPDATE;

    -- (9) REVALIDAÇÃO PÓS-LOCK — preservada integralmente da v2.0.
    -- O total é RECONTADO depois de esperar o lock: a leitura do
    -- passo (4) serviu apenas para o short-circuit e NUNCA é reusada
    -- como decisão final.
    SELECT count(*) INTO v_total_pages
      FROM public.collection_layout_page p
     WHERE p.layout_id = p_layout_id;

    IF v_input_count <> v_total_pages THEN
        RAISE EXCEPTION
            'p_page_ids_ordered deve conter todas as % Pages do Layout (recebidas %)',
            v_total_pages, v_input_count;
    END IF;

    SELECT count(*) INTO v_belong_count
      FROM public.collection_layout_page p
     WHERE p.layout_id = p_layout_id
       AND p.id = ANY (p_page_ids_ordered);

    IF v_belong_count <> v_input_count THEN
        RAISE EXCEPTION
            'p_page_ids_ordered contém Page(s) que não pertencem a este Layout';
    END IF;

    UPDATE public.collection_layout_page p
       SET page_number = src.new_number
      FROM (
            SELECT u.page_id, u.ord AS new_number
              FROM unnest(p_page_ids_ordered) WITH ORDINALITY AS u(page_id, ord)
           ) AS src
     WHERE p.id = src.page_id
       AND p.layout_id = p_layout_id;

    RETURN QUERY
    SELECT p.id, p.page_number
      FROM public.collection_layout_page p
     WHERE p.layout_id = p_layout_id
     ORDER BY p.page_number;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.reorder_layout_pages(uuid, uuid[])
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reorder_layout_pages(uuid, uuid[])
    TO authenticated;

COMMIT;
