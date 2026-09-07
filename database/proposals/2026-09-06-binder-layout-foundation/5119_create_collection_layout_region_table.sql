/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5119 - Create Collection Layout Region Table
Versão......: 2.0
Status......: PROPOSTA — STAGING, NÃO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-06 (staging em
               COLLECTIONS-BINDER-LAYOUT-FOUNDATION-STAGING-01)

Descrição...:
Cria public.collection_layout_region — mesclagem visual persistente de
2+ Slots contíguos ("Merge", C-46 / LDM-37). NUNCA destrói, recria ou
altera a identidade dos Slots envolvidos.

DP-04 (congelado): representação por BOUNDING BOX
(top_row, left_column, height, width). NÃO existe junction
Region <-> Slot.

Por que bounding box é EXATO e não aproximação: C-46 fecha que a
Region é obrigatoriamente um RETÂNGULO COMPLETO — sem buracos, sem
formas em L, sem regiões arbitrárias. Sob essa restrição o bbox É a
representação, e ela prova as invariantes de graça:
- retângulo completo  -> por construção;
- mesma Page          -> page_id único na própria linha;
- mínimo 2 Slots      -> CHECK (height * width >= 2);
- sem sobreposição    -> trigger 5121.

NÃO USAR GiST/EXCLUDE: exigiria a extensão btree_gist, e o MATERIALITY
AUDIT congelou "nenhuma nova PostgreSQL extension". Overlap e bounds
são garantidos por trigger (Query 5121) + lock de Page nas RPCs
(5134/5135).

DP-05: ARTWORK FORA DA FOUNDATION. Nenhuma coluna de imagem, nenhum
Storage asset, nenhum tipo VISUAL_ELEMENT. C-46 é explícito: "artwork
não é modelado nesta rodada"; C-42 reforça que Expected Content é
exclusivamente editorial. A Region nasce ESTRUTURAL.

Criar ou remover uma Region NÃO altera Slot Assignments nem Expected
Content dos Slots envolvidos (C-46, literal) — nada nesta tabela
referencia nem toca essas relações.

Lock: se qualquer Slot do bounding box estiver locked, Merge e Unmerge
ficam bloqueados (C-43/C-46). Enforcement em 5121 (INSERT/UPDATE) e
nas RPCs 5134/5135.

FK page_id ON DELETE RESTRICT: Region é CONTEÚDO. Apagar a Page é
bloqueado enquanto houver Region (C-39).

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

STATUS DESTA QUERY: PROPOSTA — NÃO EXECUTADO.
================================================================
*/

BEGIN;

CREATE TABLE public.collection_layout_region (
    id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    page_id       UUID        NOT NULL
                  REFERENCES public.collection_layout_page(id)
                  ON UPDATE RESTRICT ON DELETE RESTRICT,
    top_row       INTEGER     NOT NULL,
    left_column   INTEGER     NOT NULL,
    height        INTEGER     NOT NULL,
    width         INTEGER     NOT NULL,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT chk_collection_layout_region_top_row_positive
        CHECK (top_row >= 1),

    CONSTRAINT chk_collection_layout_region_left_column_positive
        CHECK (left_column >= 1),

    CONSTRAINT chk_collection_layout_region_height_positive
        CHECK (height >= 1),

    CONSTRAINT chk_collection_layout_region_width_positive
        CHECK (width >= 1),

    CONSTRAINT chk_collection_layout_region_min_two_slots
        CHECK (height * width >= 2)
);

COMMENT ON TABLE public.collection_layout_region IS
    'Layout Region (C-46/LDM-37): mesclagem visual de 2+ Slots '
    'contíguos, retângulo completo, uma Page, sem overlap. '
    'Representação por BOUNDING BOX (DP-04) — sem junction. '
    'ARTWORK/conteúdo visual está FORA da Foundation (DP-05). '
    'Não altera Slot Assignment nem Expected Content.';

COMMENT ON CONSTRAINT chk_collection_layout_region_min_two_slots
    ON public.collection_layout_region IS
    'Mínimo 2 Slots (C-46). Uma Region 1x1 não é mesclagem.';

ALTER TABLE public.collection_layout_region ENABLE ROW LEVEL SECURITY;

CREATE POLICY collection_layout_region_select_own
    ON public.collection_layout_region FOR SELECT
    USING (EXISTS (
        SELECT 1
        FROM public.collection_layout_page p
        JOIN public.collection_layout l ON l.id = p.layout_id
        JOIN public.collection c        ON c.id = l.collection_id
        WHERE p.id = collection_layout_region.page_id
          AND c.owner_user_id = (select auth.uid())
    ));

GRANT SELECT ON public.collection_layout_region TO authenticated;

REVOKE TRUNCATE, REFERENCES, TRIGGER, MAINTAIN
    ON public.collection_layout_region FROM anon, authenticated;

-- §9 CORREÇÃO CONSOLIDADA 01 — DML nunca é concedido a cliente algum.
-- Explícito, não herdado de default privileges.
REVOKE INSERT, UPDATE, DELETE ON public.collection_layout_region
    FROM PUBLIC, anon, authenticated;

COMMIT;

/*
Como validar:

SELECT count(*) FROM pg_extension WHERE extname = 'btree_gist';
Esperado: 0 — nenhuma extensão nova foi adicionada.

SELECT count(*) FROM pg_constraint
WHERE conrelid='public.collection_layout_region'::regclass AND contype='x';
Esperado: 0 — nenhuma EXCLUDE constraint.
*/
