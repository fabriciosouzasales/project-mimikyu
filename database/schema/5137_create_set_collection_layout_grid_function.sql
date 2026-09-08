/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5137 - Create set_collection_layout_grid() RPC
Versão......: 1.1 (corpo efetivo = Query 5141, foldada nesta
               definição canônica)
Status......: CONFIRMADO EXECUTADO / LIVE / PROMOVIDO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-06 (criado em
               COLLECTIONS-BINDER-LAYOUT-FOUNDATION-CONSOLIDATED-CORRECTION-01;
               aplicado em 2026-09-07,
               COLLECTIONS-BINDER-LAYOUT-FOUNDATION-IMPLEMENTATION-01;
               corrigido em 2026-09-07 pela Query 5141,
               -IMPLEMENTATION-01-FIX-02, aplicada ao banco real;
               5141 FOLDADA nesta definição canônica em
               SCHEMA-PROMOTION-RECONCILIATION-01, 2026-09-08)

Descrição...:
§5 GRID — RPC PÚBLICA QUE FALTAVA.

O PROBLEMA REAL
---------------
DP-03 permite alterar o Grid do Layout enquanto ele tiver ZERO Pages —
e o trigger 5107 foi escrito exatamente para permitir esse caso. Mas
não havia NENHUM caminho para o cliente exercer essa permissão: as seis
tabelas da Foundation não concedem DML a `authenticated` (e o §9 da
Correção Consolidada 01 passou a REVOGAR isso explicitamente), então o
único acesso de escrita é por RPC — e nenhuma das 13 RPCs originais
alterava o grid.

Resultado: uma regra de produto decidida e implementada no trigger era
inalcançável na prática. Esta RPC fecha a lacuna. Nada de novo é
decidido aqui: DP-03 permanece exatamente como está.

O QUE ESTA RPC **NÃO** FAZ
--------------------------
- NÃO cria um Layout novo.
- NÃO faz rebuild de Pages/Slots.
- NÃO faz Grid migration (redistribuir cartas ao mudar o grid continua
  DEFERRED, por consequência de DP-01 + DP-03).

CONTRATO
--------
- `authenticated` apenas; `PUBLIC` e `anon` revogados.
- Owner apenas, com a mesma mensagem uniforme de não-enumeração das
  demais RPCs: Layout inexistente e Layout alheio são indistinguíveis.
- Collection precisa estar ACTIVE.
- Ordem canônica de lock COLLECTION -> LAYOUT, via helper 5122.
- rows e columns entre 1 e 10 (mesma faixa dos CHECKs de 5105 —
  aqui a validação existe para devolver mensagem de domínio, não para
  substituir a constraint).
- Layout precisa ter ZERO Pages, contadas DEPOIS do lock.
- O trigger 5107 permanece como defesa estrutural: se esta RPC (ou
  qualquer caminho privilegiado) tentar alterar o grid com Pages
  existentes, o trigger rejeita.

Dependências:
- public.assert_collection_layout_mutable() (Query 5122 v2.0).
- public.collection_layout (Query 5105) + trigger 5107.

FOLD-IN DA QUERY 5141 — DEFINIÇÃO CANÔNICA EFETIVA
--------------------------------------------------
A definição de `5137` foi aplicada ao banco em 2026-09-07 com um defeito
real, descoberto EM RUNTIME pelo harness `5818` v7.1 (casos U01/U02/U03):
o `UPDATE ... WHERE id = p_layout_id` deixava `id` ambíguo entre a coluna
`collection_layout.id` e a variável de saída homônima do `RETURNS TABLE`,
abortando com `42702 column reference "id" is ambiguous`. A RPC estava
QUEBRADA em produção.

A Query `5141` (`CREATE OR REPLACE`, aplicada em 2026-09-07,
`-IMPLEMENTATION-01-FIX-02`) corrigiu EXCLUSIVAMENTE a qualificação da
coluna de destino:

    UPDATE public.collection_layout AS l
       SET grid_rows    = p_grid_rows,
           grid_columns = p_grid_columns
     WHERE l.id = p_layout_id;

Assinatura, retorno, `LANGUAGE`/`SECURITY DEFINER`/`search_path`, grants,
ordem canônica de lock, validação de faixa 1..10 e revalidação pós-lock
da contagem de Pages permanecem inalterados.

**O corpo executável deste arquivo é o da Query `5141`** — o estado final
efetivamente vivo no banco. `5137` v1.0 (com o defeito) e `5141`
permanecem INTACTOS em
`database/proposals/2026-09-06-binder-layout-foundation/` como registro
histórico do que foi aplicado e de como foi corrigido. Por decisão de
Fabrício em `SCHEMA-PROMOTION-RECONCILIATION-01`, **`5141` NÃO recebe
arquivo próprio em `database/schema/`**: a representação canônica é uma
definição por objeto, e o objeto `set_collection_layout_grid()` tem uma
só definição efetiva. Mesmo padrão já aplicado a `5039`×`5048`,
`5046`×`5064` e `5057`×`5092`.

STATUS DESTA QUERY: CONFIRMADO EXECUTADO / LIVE / PROMOVIDO.

Aplicada ao banco real em 2026-09-07 (`5137` v1.0) e corrigida no mesmo
dia por `5141`. Validada por `5818` v7.2 (196/196 runtime, FAIL 0 — os
casos U01/U01b/U02/U03 passam com esta definição) e por `5819` v3.0
(22/22 HEALTHY). Ledger e evidência completa em
`database/proposals/2026-09-06-binder-layout-foundation/README.md`.

Promovida para `database/schema/` em `SCHEMA-PROMOTION-RECONCILIATION-01`
(2026-09-08). Harnesses `5818`/`5819`, roteiro `CONCURRENCY-PROOF-C04-R18.sql`
e `README.md` da rodada NÃO são promovidos, por convenção.
================================================================
*/

BEGIN;

CREATE OR REPLACE FUNCTION public.set_collection_layout_grid(
    p_layout_id    UUID,
    p_grid_rows    INTEGER,
    p_grid_columns INTEGER
)
RETURNS TABLE (
    id            UUID,
    collection_id UUID,
    grid_rows     INTEGER,
    grid_columns  INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_collection_id UUID;
    v_page_count    INTEGER;
BEGIN
    IF (select auth.uid()) IS NULL THEN
        RAISE EXCEPTION 'authentication required';
    END IF;

    -- 1) COLLECTION LOCK -> LAYOUT LOCK + ACTIVE + ownership, com a
    -- mensagem uniforme de não-enumeração vinda do helper.
    v_collection_id := public.assert_collection_layout_mutable(p_layout_id);

    -- 2) Domínio do grid.
    IF p_grid_rows IS NULL OR p_grid_columns IS NULL THEN
        RAISE EXCEPTION 'p_grid_rows e p_grid_columns são obrigatórios';
    END IF;

    IF p_grid_rows < 1 OR p_grid_rows > 10
       OR p_grid_columns < 1 OR p_grid_columns > 10 THEN
        RAISE EXCEPTION
            'grid inválido: rows e columns devem estar entre 1 e 10 (recebido % x %)',
            p_grid_rows, p_grid_columns;
    END IF;

    -- 3) REVALIDAÇÃO PÓS-LOCK: a contagem de Pages é feita DEPOIS de
    -- adquirir o lock do Layout. Uma add_layout_page() concorrente que
    -- tenha vencido a corrida é vista aqui, não ignorada.
    SELECT count(*) INTO v_page_count
      FROM public.collection_layout_page p
     WHERE p.layout_id = p_layout_id;

    IF v_page_count > 0 THEN
        RAISE EXCEPTION
            'grid do Layout não pode ser alterado enquanto existirem Pages — remova as % Page(s) primeiro (Grid Change com Pages existentes é DEFERRED)',
            v_page_count;
    END IF;

    -- 4) MUTAÇÃO. O trigger 5107 revalida estruturalmente.
    --
    -- §1 FIX-02: a tabela é ALIASADA e a coluna de destino QUALIFICADA.
    -- Sem `AS l` / `l.id`, o `id` do WHERE colide com a variável de
    -- saída homônima do RETURNS TABLE e o PostgreSQL aborta com
    -- 42702 column reference "id" is ambiguous.
    UPDATE public.collection_layout AS l
       SET grid_rows    = p_grid_rows,
           grid_columns = p_grid_columns
     WHERE l.id = p_layout_id;

    RETURN QUERY
    SELECT l.id, l.collection_id, l.grid_rows, l.grid_columns
      FROM public.collection_layout l
     WHERE l.id = p_layout_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.set_collection_layout_grid(uuid, integer, integer)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_collection_layout_grid(uuid, integer, integer)
    TO authenticated;

COMMIT;

/*
Como validar:

SELECT p.proname, p.prosecdef, p.proconfig,
       pg_get_userbyid(p.proowner) AS owner,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') AS auth_exec,
       has_function_privilege('anon',          p.oid, 'EXECUTE') AS anon_exec
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname='public' AND p.proname='set_collection_layout_grid';

Esperado: prosecdef=true, proconfig com search_path=, owner=postgres,
auth_exec=true, anon_exec=false.

Prova comportamental (5818, grupo G): owner com zero Pages altera o
grid; 1x1 e 10x10 aceitos; 0 e 11 rejeitados; Page existente rejeita;
Collection ARCHIVED rejeita; Layout alheio e Layout inexistente
produzem a MESMA mensagem.
*/
