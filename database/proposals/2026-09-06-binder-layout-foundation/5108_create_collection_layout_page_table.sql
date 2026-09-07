/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5108 - Create Collection Layout Page Table
Versão......: 2.0
Status......: PROPOSTA — STAGING, NÃO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-06 (staging em
               COLLECTIONS-BINDER-LAYOUT-FOUNDATION-STAGING-01)

Descrição...:
Cria public.collection_layout_page — unidade estrutural do Layout
(C-39 / LDM-30). Pertence a exatamente um Layout.

Page identity != Page order (C-39, explícito). `id` é a identidade,
estável e imutável; `page_number` é atributo mutável de ordenação.
Reordenar NUNCA recria a Page, nem afeta identidade, row ou column
dos seus Slots.

DP-02 (congelado): mecanismo de ordenação = page_number INTEGER >= 1,
com UNIQUE (layout_id, page_number) DEFERRABLE INITIALLY DEFERRED.
NÃO existe rank/LexoRank/linked list. O DEFERRABLE é o que torna o
desenho viável: permite reorder em bloco (UPDATE ... FROM unnest) sem
colisão intermediária, com a unicidade verificada só no COMMIT.
Contiguidade 1..N é responsabilidade das RPCs (5125/5126/5127), que
lockam collection_layout FOR UPDATE para serializar add/remove/reorder
— não pode ser CHECK, porque é invariante de conjunto, não de linha.

Spread (par de Pages exibidas lado a lado) NÃO é conceito de domínio
(C-39) — é apresentação derivada, responsabilidade exclusiva da UX.
Nada nesta tabela representa spread.

Toda Page nasce estruturalmente completa (C-39): a RPC 5125 insere a
Page e os grid_rows × grid_columns Slots na MESMA transação. Cliente
nunca cria Slot diretamente. Não existe Page parcialmente estruturada.

FK layout_id ON DELETE RESTRICT: apagar um Layout com Pages é
recusado no nível estrutural, não só na RPC — nenhum DELETE
privilegiado pode apagar conteúdo silenciosamente.

Dependências:
- public.collection_layout (Query 5105).

CORREÇÃO CONSOLIDADA 01 (2026-09-06,
COLLECTIONS-BINDER-LAYOUT-FOUNDATION-CONSOLIDATED-CORRECTION-01):
§9 TABLE DML DEFENSE — REVOKE EXPLÍCITO de INSERT/UPDATE/DELETE
para PUBLIC, anon e authenticated. Antes, a ausência de DML dependia
apenas de default privileges (nenhum GRANT de DML foi emitido). Isso
é verdadeiro mas FRÁGIL: qualquer ALTER DEFAULT PRIVILEGES futuro, ou
um GRANT ALL acidental no schema, abriria escrita direta e contornaria
o caminho RPC. A garantia passa a ser explícita e verificável — o 5818
checa os TRÊS grantees (PUBLIC, anon, authenticated).

STATUS DESTA QUERY: PROPOSTA — NÃO EXECUTADO.
================================================================
*/

BEGIN;

CREATE TABLE public.collection_layout_page (
    id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    layout_id    UUID        NOT NULL
                 REFERENCES public.collection_layout(id)
                 ON UPDATE RESTRICT ON DELETE RESTRICT,
    page_number  INTEGER     NOT NULL,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT uq_collection_layout_page_number
        UNIQUE (layout_id, page_number) DEFERRABLE INITIALLY DEFERRED,

    CONSTRAINT chk_collection_layout_page_number_positive
        CHECK (page_number >= 1)
);

COMMENT ON TABLE public.collection_layout_page IS
    'Page do Collection Layout (C-39/LDM-30). Identidade (id) estável '
    'e independente de page_number. Nasce estruturalmente completa '
    '(todos os Slots do grid na mesma transação, Query 5125). Spread '
    'NÃO é domínio — é apresentação derivada.';

COMMENT ON COLUMN public.collection_layout_page.page_number IS
    'Ordem 1..N dentro do Layout (DP-02). Mutável; contiguidade '
    'garantida pelas RPCs 5125/5126/5127, que lockam o Layout FOR '
    'UPDATE. UNIQUE DEFERRABLE permite reorder em bloco.';

ALTER TABLE public.collection_layout_page ENABLE ROW LEVEL SECURITY;

CREATE POLICY collection_layout_page_select_own
    ON public.collection_layout_page FOR SELECT
    USING (EXISTS (
        SELECT 1
        FROM public.collection_layout l
        JOIN public.collection c ON c.id = l.collection_id
        WHERE l.id = collection_layout_page.layout_id
          AND c.owner_user_id = (select auth.uid())
    ));

GRANT SELECT ON public.collection_layout_page TO authenticated;

REVOKE TRUNCATE, REFERENCES, TRIGGER, MAINTAIN
    ON public.collection_layout_page FROM anon, authenticated;

-- §9 CORREÇÃO CONSOLIDADA 01 — DML nunca é concedido a cliente algum.
-- Explícito, não herdado de default privileges.
REVOKE INSERT, UPDATE, DELETE ON public.collection_layout_page
    FROM PUBLIC, anon, authenticated;

COMMIT;

/*
Como validar:

SELECT conname, pg_get_constraintdef(oid), condeferrable, condeferred
FROM pg_constraint
WHERE conrelid = 'public.collection_layout_page'::regclass
ORDER BY conname;

Esperado: uq_collection_layout_page_number com condeferrable=true e
condeferred=true.
*/
