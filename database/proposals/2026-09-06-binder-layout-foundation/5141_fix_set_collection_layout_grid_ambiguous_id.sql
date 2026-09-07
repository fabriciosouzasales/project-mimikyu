/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5141 - Fix set_collection_layout_grid(): coluna `id` ambígua
Versão......: 1.0
Status......: PROPOSTA — STAGING, NÃO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-07 (criado em
               COLLECTIONS-BINDER-LAYOUT-FOUNDATION-IMPLEMENTATION-01-FIX-02)

Descrição...:
MIGRATION INCREMENTAL CORRETIVA. `5137` NÃO é editado — permanece como
definição histórica aplicada, com o defeito descoberto em runtime.
Esta Query é a DEFINIÇÃO EFETIVA de public.set_collection_layout_grid().

DEFEITO REAL (descoberto na execução do 5818 v7.1, casos U01/U02/U03)
--------------------------------------------------------------------
A função declara

    RETURNS TABLE (id UUID, collection_id UUID,
                   grid_rows INTEGER, grid_columns INTEGER)

e, em PL/pgSQL, os nomes das colunas de saída de um RETURNS TABLE são
VARIÁVEIS visíveis em todo o corpo. O statement de mutação escrito em
`5137` era:

    UPDATE public.collection_layout
       SET grid_rows    = p_grid_rows,
           grid_columns = p_grid_columns
     WHERE id = p_layout_id;          -- <== `id` AMBÍGUO

`id` resolve simultaneamente para a coluna `collection_layout.id` e
para a variável de saída `id`. PostgreSQL aborta com

    42702  column reference "id" is ambiguous

Consequência real: `set_collection_layout_grid()` estava QUEBRADA em
produção — nenhuma alteração de grid era possível pela RPC. Os casos
U01 (owner com ZERO Pages altera o grid), U02 (1x1), U03 (10x10) e,
por consequência, U01b (persistência 2x5) FALHAVAM.

Precedente idêntico no projeto: `6109` (RETURNING ambíguo em
open_pokemon_catalog_sourcing_run) e `6126` (ON CONFLICT ambíguo em
primary representative). Mesma classe, mesma disciplina: migration
incremental nova, nunca edição da migration histórica.

O QUE MUDA
----------
EXCLUSIVAMENTE a qualificação da coluna de destino do UPDATE:

    UPDATE public.collection_layout AS l
       SET grid_rows    = p_grid_rows,
           grid_columns = p_grid_columns
     WHERE l.id = p_layout_id;

O QUE **NÃO** MUDA
------------------
- assinatura: (uuid, integer, integer);
- retorno: TABLE (id UUID, collection_id UUID, grid_rows INTEGER,
  grid_columns INTEGER);
- LANGUAGE plpgsql, SECURITY DEFINER, SET search_path = '';
- REVOKE de PUBLIC/anon + GRANT para authenticated;
- ordem canônica COLLECTION -> LAYOUT via helper 5122;
- validação de faixa 1..10 com mensagem de domínio;
- revalidação PÓS-LOCK da contagem de Pages;
- o trigger 5107 permanece como defesa estrutural.

Nenhuma regra de negócio, mensagem de erro ou contrato de segurança
foi alterado. O único efeito observável é que a RPC passa a funcionar.

Dependências:
- public.set_collection_layout_grid() (Query 5137) — já aplicada.
- public.assert_collection_layout_mutable() (Query 5122).
- public.collection_layout (Query 5105) + trigger 5107.

STATUS DESTA QUERY: PROPOSTA — NÃO EXECUTADO.
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
Como validar (estático):

SELECT p.proname, p.prosecdef, p.proconfig,
       pg_get_userbyid(p.proowner) AS owner,
       pg_get_function_result(p.oid) AS retorno,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') AS auth_exec,
       has_function_privilege('anon',          p.oid, 'EXECUTE') AS anon_exec,
       (position('UPDATE public.collection_layout AS l' in pg_get_functiondef(p.oid)) > 0) AS update_aliasado,
       (pg_get_functiondef(p.oid) ~ 'WHERE[[:space:]]+l\.id[[:space:]]*=[[:space:]]*p_layout_id') AS where_qualificado
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname='public' AND p.proname='set_collection_layout_grid';

Esperado: prosecdef=true, proconfig com search_path=, owner=postgres,
retorno TABLE(id uuid, collection_id uuid, grid_rows integer,
grid_columns integer), auth_exec=true, anon_exec=false,
update_aliasado=true, where_qualificado=true.

Prova comportamental: casos U01/U01b/U02/U03 do 5818 passam a PASS.
*/
