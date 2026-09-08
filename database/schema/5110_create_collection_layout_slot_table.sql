/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5110 - Create Collection Layout Slot Table
Versão......: 2.0
Status......: CONFIRMADO EXECUTADO / LIVE / PROMOVIDO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-06 (staging em
               COLLECTIONS-BINDER-LAYOUT-FOUNDATION-STAGING-01)

Descrição...:
Cria public.collection_layout_slot — posição estrutural estável dentro
de uma Page (C-41 / LDM-32).

Slot identity != posição (C-41, explícito). `id` é a identidade;
`row_index`/`column_index` são atributos de posição. O Slot sobrevive
a Move, Swap e Replace sem ser recriado — nasce e morre apenas junto
com mudanças estruturais da Page.

Nomes de coluna: `row_index`/`column_index` em vez de `row`/`column`
porque ROW é palavra reservada em SQL e COLUMN é palavra-chave —
evita quoting obrigatório em toda query futura. A semântica é a de
LDM-32 (`row`/`column`, 1-based, absolutos).

Índice sequencial de exibição, se necessário no futuro, é SEMPRE
derivado de row_index/column_index e do grid (C-41) — nunca uma
segunda fonte de verdade persistida. Este arquivo não cria nenhum.

UNIQUE (page_id, row_index, column_index) — LDM-32, literal.

DECISÃO DE ÍNDICE (DP explicitamente congelada no MATERIALITY AUDIT):
NÃO existe índice isolado em (page_id). O UNIQUE acima já tem page_id
como leading prefix e atende integralmente "carregar os Slots de uma
Page" e "carregar um spread (2 Pages)". Criar um índice adicional
seria redundante. Zero índice de performance especulativo — o harness
de performance (5819) decidirá se algo mais é necessário, com plano
real na mão.

`locked` (C-43 / LDM-34): Lock é propriedade do SLOT, não da Physical
Card nem da Slot Assignment. Um Slot pode estar locked mesmo vazio,
sem Expected Content e sem ocupação. Enforcement em 5118 (Assignment)
e 5121 (Region); set/unset do próprio Lock por RPC 5130.

FK page_id ON DELETE CASCADE: Slot é parte estrutural da Page, não
conteúdo. Quando a RPC 5126 já provou que a Page está limpa (sem
Assignment, sem Expected Content, sem Region), os Slots podem sumir
com ela. Conteúdo continua protegido por RESTRICT nas suas próprias
FKs (5113/5115/5119) — este CASCADE nunca alcança conteúdo, apenas
estrutura vazia.

Dependências:
- public.collection_layout_page (Query 5108).

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

CREATE TABLE public.collection_layout_slot (
    id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    page_id        UUID        NOT NULL
                   REFERENCES public.collection_layout_page(id)
                   ON UPDATE RESTRICT ON DELETE CASCADE,
    row_index      INTEGER     NOT NULL,
    column_index   INTEGER     NOT NULL,
    locked         BOOLEAN     NOT NULL DEFAULT FALSE,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT uq_collection_layout_slot_position
        UNIQUE (page_id, row_index, column_index),

    CONSTRAINT chk_collection_layout_slot_row_positive
        CHECK (row_index >= 1),

    CONSTRAINT chk_collection_layout_slot_column_positive
        CHECK (column_index >= 1)
);

COMMENT ON TABLE public.collection_layout_slot IS
    'Slot do Collection Layout (C-41/LDM-32). Identidade (id) estável '
    'e independente de row_index/column_index. Sobrevive a '
    'Move/Swap/Replace. Nasce/morre só com mudanças estruturais da '
    'Page. locked (C-43) protege a POSIÇÃO, nunca a Physical Card.';

COMMENT ON COLUMN public.collection_layout_slot.row_index IS
    'Linha 1-based (LDM-32 "row"). Nome com sufixo _index porque ROW '
    'é palavra reservada em SQL. Limite superior validado contra o '
    'grid do Layout pelo trigger da Query 5112.';

COMMENT ON COLUMN public.collection_layout_slot.column_index IS
    'Coluna 1-based (LDM-32 "column"). Nome com sufixo _index porque '
    'COLUMN é palavra-chave em SQL.';

COMMENT ON COLUMN public.collection_layout_slot.locked IS
    'Lock do Slot (C-43/LDM-34). Bloqueia Move/Swap/Replace/Remove/'
    'Bandeja (trigger 5118) e Merge/Unmerge de Region (5121/5134/'
    '5135). NÃO bloqueia Expected Content nem o próprio set/unset.';

ALTER TABLE public.collection_layout_slot ENABLE ROW LEVEL SECURITY;

CREATE POLICY collection_layout_slot_select_own
    ON public.collection_layout_slot FOR SELECT
    USING (EXISTS (
        SELECT 1
        FROM public.collection_layout_page p
        JOIN public.collection_layout l ON l.id = p.layout_id
        JOIN public.collection c        ON c.id = l.collection_id
        WHERE p.id = collection_layout_slot.page_id
          AND c.owner_user_id = (select auth.uid())
    ));

GRANT SELECT ON public.collection_layout_slot TO authenticated;

REVOKE TRUNCATE, REFERENCES, TRIGGER, MAINTAIN
    ON public.collection_layout_slot FROM anon, authenticated;

-- §9 CORREÇÃO CONSOLIDADA 01 — DML nunca é concedido a cliente algum.
-- Explícito, não herdado de default privileges.
REVOKE INSERT, UPDATE, DELETE ON public.collection_layout_slot
    FROM PUBLIC, anon, authenticated;

COMMIT;

/*
Como validar:

-- Confirmar que NÃO existe índice isolado em page_id além do UNIQUE.
SELECT indexname, indexdef
FROM pg_indexes
WHERE schemaname='public' AND tablename='collection_layout_slot'
ORDER BY indexname;

Esperado: apenas a PK e uq_collection_layout_slot_position.
*/
