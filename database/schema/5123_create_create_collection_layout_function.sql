/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5123 - Create create_collection_layout()
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO / LIVE / PROMOVIDO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-06 (staging em
               COLLECTIONS-BINDER-LAYOUT-FOUNDATION-STAGING-01)

Descrição...:
Cria o Layout de uma Collection. Nasce com ZERO Pages — C-38: "uma
Collection pode existir sem Layout", e nada exige Page na criação.

Não usa assert_collection_layout_mutable() porque o Layout ainda não
existe; a fronteira de autorização é feita aqui diretamente sobre a
Collection, na mesma ordem (auth -> ownership+lock -> ACTIVE), com a
mesma mensagem de não-enumeração usada por 5039.

DP-01: a UNIQUE (collection_id) da Query 5105 rejeita o segundo
Layout. Traduzimos a violação para mensagem de domínio em vez de
deixar vazar o erro de constraint.

DP-03: grid_rows/grid_columns obrigatórios, 1..10, validados pelos
CHECKs da tabela. Nenhum default — a geometria é decisão explícita do
usuário. O grid 3×3 dos spikes NÃO é privilegiado aqui.

Dependências:
- public.collection_layout (Query 5105).
- public.collection (Query 5030).

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

CREATE OR REPLACE FUNCTION public.create_collection_layout(
    p_collection_id UUID,
    p_grid_rows     INTEGER,
    p_grid_columns  INTEGER
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
    v_lifecycle_status TEXT;
    v_new_id           UUID;
BEGIN
    IF (select auth.uid()) IS NULL THEN
        RAISE EXCEPTION 'authentication required';
    END IF;

    SELECT c.lifecycle_status
      INTO v_lifecycle_status
      FROM public.collection c
     WHERE c.id = p_collection_id
       AND c.owner_user_id = (select auth.uid())
     FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'collection not found or not owned by caller';
    END IF;

    IF v_lifecycle_status <> 'ACTIVE' THEN
        RAISE EXCEPTION
            'collection is ARCHIVED — reactivate it before creating a layout';
    END IF;

    IF EXISTS (
        SELECT 1 FROM public.collection_layout l
        WHERE l.collection_id = p_collection_id
    ) THEN
        RAISE EXCEPTION
            'collection already has a layout — V1 admite exatamente um Layout por Collection (múltiplos Layouts é DEFERRED)';
    END IF;

    INSERT INTO public.collection_layout AS cl
        (collection_id, grid_rows, grid_columns)
    VALUES
        (p_collection_id, p_grid_rows, p_grid_columns)
    RETURNING cl.id INTO v_new_id;

    RETURN QUERY
    SELECT l.id, l.collection_id, l.grid_rows, l.grid_columns
      FROM public.collection_layout l
     WHERE l.id = v_new_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.create_collection_layout(uuid, integer, integer)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_collection_layout(uuid, integer, integer)
    TO authenticated;

COMMIT;
