/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5105 - Create Collection Layout Table
Versão......: 2.0
Status......: CONFIRMADO EXECUTADO / LIVE / PROMOVIDO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-06 (staging em
               COLLECTIONS-BINDER-LAYOUT-FOUNDATION-STAGING-01)

Descrição...:
Cria public.collection_layout — a organização visual/espacial de uma
Collection (C-38 / LDM-29). Independente de Storage: trocar o Storage
Container não destrói nem recria o Layout, e Layout nunca deriva
localização física (C-38 / Q do baseline).

DP-01 (congelado no MATERIALITY AUDIT): V1 = exatamente 0..1 Layout
por Collection. UNIQUE (collection_id) materializa a restrição.
NÃO existe is_primary. Múltiplos Layouts permanecem DEFERRED — C-38
permite conceitualmente no futuro, mas o mecanismo de distinção
(principal vs. alternativo) nunca foi decidido, e habilitar múltiplos
sem ele criaria perguntas sem resposta canônica.
Relaxar depois é DROP CONSTRAINT + a decisão de produto que falta.

DP-03 (congelado): Grid Configuration pertence ao Layout, nunca à
Page (C-40 / LDM-31). grid_rows e grid_columns entre 1 e 10.
capacity_per_page = grid_rows × grid_columns é SEMPRE DERIVADA —
jamais persistida como valor independente (C-40 é explícito).
Geometrias observadas no benchmark (2×2, 3×3, 4×3, 4×4, 4×5, 5×4)
cabem folgadamente; o teto 10×10 é guarda operacional, não regra de
domínio. O grid 3×3 dos spikes é implementação de protótipo, NÃO
regra de domínio — nada aqui o privilegia.

Mutabilidade do grid: permitida apenas enquanto o Layout tiver ZERO
Pages. Enforcement em Query 5107 (trigger dedicado), não aqui.

FK collection_id ON DELETE RESTRICT: apagar uma Collection com Layout
é recusado. Simetria com delete_collection() (Query 5039), que já
recusa apagar Collection com Allocations.

RLS: habilitada, uma única policy de SELECT próprio navegando até o
Owner da Collection. Zero INSERT/UPDATE/DELETE para cliente — toda
mutação passa por RPC SECURITY DEFINER (Queries 5123–5135), padrão
idêntico ao já vigente em collection/collection_allocation.

Dependências:
- public.collection (Query 5030).

CORREÇÃO CONSOLIDADA 01 (2026-09-06,
COLLECTIONS-BINDER-LAYOUT-FOUNDATION-CONSOLIDATED-CORRECTION-01):
§9 TABLE DML DEFENSE — REVOKE EXPLÍCITO de INSERT/UPDATE/DELETE
para PUBLIC, anon e authenticated. Antes, a ausência de DML dependia
apenas de default privileges (nenhum GRANT de DML foi emitido). Isso
é verdadeiro mas FRÁGIL: qualquer ALTER DEFAULT PRIVILEGES futuro, ou
um GRANT ALL acidental no schema, abriria escrita direta e contornaria
o caminho RPC. A garantia passa a ser explícita e verificável — o 5818
checa os TRÊS grantees (PUBLIC, anon, authenticated).

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

CREATE TABLE public.collection_layout (
    id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    collection_id  UUID        NOT NULL
                   REFERENCES public.collection(id)
                   ON UPDATE RESTRICT ON DELETE RESTRICT,
    grid_rows      INTEGER     NOT NULL,
    grid_columns   INTEGER     NOT NULL,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT uq_collection_layout_collection
        UNIQUE (collection_id),

    CONSTRAINT chk_collection_layout_grid_rows
        CHECK (grid_rows BETWEEN 1 AND 10),

    CONSTRAINT chk_collection_layout_grid_columns
        CHECK (grid_columns BETWEEN 1 AND 10)
);

COMMENT ON TABLE public.collection_layout IS
    'Collection Layout (C-38/LDM-29). 0..1 por Collection na V1 '
    '(DP-01, UNIQUE collection_id). Grid pertence ao Layout (C-40); '
    'capacity_per_page = grid_rows * grid_columns é derivada, nunca '
    'persistida.';

COMMENT ON COLUMN public.collection_layout.grid_rows IS
    'Linhas do grid. 1..10. Imutável a partir da primeira Page '
    '(Query 5107).';

COMMENT ON COLUMN public.collection_layout.grid_columns IS
    'Colunas do grid. 1..10. Imutável a partir da primeira Page '
    '(Query 5107).';

ALTER TABLE public.collection_layout ENABLE ROW LEVEL SECURITY;

CREATE POLICY collection_layout_select_own
    ON public.collection_layout FOR SELECT
    USING (EXISTS (
        SELECT 1 FROM public.collection c
        WHERE c.id = collection_layout.collection_id
          AND c.owner_user_id = (select auth.uid())
    ));

GRANT SELECT ON public.collection_layout TO authenticated;

REVOKE TRUNCATE, REFERENCES, TRIGGER, MAINTAIN
    ON public.collection_layout FROM anon, authenticated;

-- §9 CORREÇÃO CONSOLIDADA 01 — DML nunca é concedido a cliente algum.
-- Explícito, não herdado de default privileges.
REVOKE INSERT, UPDATE, DELETE ON public.collection_layout
    FROM PUBLIC, anon, authenticated;

COMMIT;

/*
Como validar:

SELECT
    (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname='public' AND c.relname='collection_layout' AND c.relkind='r')            AS tabela,
    (SELECT relrowsecurity FROM pg_class WHERE oid='public.collection_layout'::regclass)       AS rls,
    (SELECT count(*) FROM pg_policies WHERE schemaname='public' AND tablename='collection_layout') AS policies,
    (SELECT count(*) FROM pg_constraint WHERE conrelid='public.collection_layout'::regclass
       AND contype='u')                                                                        AS uniques,
    (SELECT count(*) FROM pg_constraint WHERE conrelid='public.collection_layout'::regclass
       AND contype='c')                                                                        AS checks;

Esperado: tabela=1, rls=true, policies=1, uniques=1, checks>=2.
*/
