/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5072 - Create Collection Master Set Scope Table
Versão......: 1.0
Status......: PROPOSTA — NÃO EXECUTADA
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-02 (COLLECTIONS-PHYSICAL-INCREMENT-02F-STAGING-01)

Descrição...:
Materializa fisicamente o Master Set Adopted Scope (LDM-21, C-23) —
o conjunto de Card Variants explicitamente adotadas pelo Owner como
requisito de completude de uma Collection `REFERENCE_BASED`/`CARD_SET`
sob `completion_policy = 'MASTER_SET'`. Autoridade conceitual fechada
em `COLLECTIONS-MASTER-SET-MODELING-01` até `-FINAL-FIX-02` — nenhuma
decisão de domínio é tomada aqui, só materialização física.

PK NATURAL COMPOSTA `(collection_id, card_variant_id)`, não UUID
próprio + UNIQUE (decisão fechada em MODELING-01, item 2, reafirmada
em toda revisão seguinte): a invariante "uma Variant aparece no máximo
uma vez no Scope de uma Collection" é exatamente o que esta PK
declara; nenhuma outra tabela do domínio precisa referenciar uma
linha de Scope pelo próprio id (diferente de `collection_allocation`,
onde o UUID próprio existe porque a invariante real mora em
`physical_card_id UNIQUE`, um caso estruturalmente diferente). Efeito
colateral desejado: a PK, liderada por `collection_id`, já serve como
índice para "todo o Scope desta Collection" sem exigir índice
secundário (ver `5813`).

Sem `updated_at` — decisão fechada em MODELING-01/FINAL-FIX-01: cada
linha é um fato de inclusão (adoção), nunca um registro editável.
Mudança de Scope é sempre REMOVE + ADD (`DELETE` de uma linha, `INSERT`
de outra), nunca `UPDATE` de uma linha existente — `adopted_at`/
`adopted_by_user_id` descrevem a adoção atual daquela Variant
especificamente e não podem ser resetados por nenhuma operação que
preserve a Variant no Scope (ver Query `5074`, que bloqueia todo
`UPDATE` estruturalmente).

`ON DELETE CASCADE` em `collection_id` — Scope não tem existência
independente da Collection que o contém, mesmo padrão de
`collection_reference`/`collection_card_set_reference` (02D). `ON
DELETE RESTRICT` em `card_variant_id` — excluir uma Collection nunca
cascateia até o catálogo, mesmo padrão universal do domínio.
`adopted_by_user_id` referencia `auth.users` com o mesmo tratamento
`ON UPDATE RESTRICT ON DELETE RESTRICT` já usado para `owner_user_id`
em `collection` e para `created_by_user_id`/`updated_by_user_id`
noutros pontos do domínio — hoje sempre igual a
`collection.owner_user_id` (Scope é Owner-only, C item 3 de
MODELING-01), mas mantido como coluna própria por fidelidade a LDM-21
e por extensibilidade futura (Collaboration/Permissions, ainda não
modelada fisicamente).

RLS: mesmo padrão de `collection_allocation`/`collection_reference` —
única policy é `SELECT` do próprio Owner via join até
`collection.owner_user_id` (esta tabela não tem `owner_user_id`
próprio). Nenhuma policy de escrita para `authenticated` — toda
escrita passa exclusivamente pelas RPCs `SECURITY DEFINER` desta
mesma pasta (`5080`-`5082`).

STATUS DESTA QUERY: PROPOSTA — NÃO EXECUTADA.
================================================================
*/

CREATE TABLE public.collection_master_set_scope (
    collection_id      UUID NOT NULL
                          REFERENCES public.collection(id)
                          ON UPDATE RESTRICT ON DELETE CASCADE,
    card_variant_id    UUID NOT NULL
                          REFERENCES public.card_variant(id)
                          ON UPDATE RESTRICT ON DELETE RESTRICT,
    adopted_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    adopted_by_user_id UUID NOT NULL
                          REFERENCES auth.users(id)
                          ON UPDATE RESTRICT ON DELETE RESTRICT,

    CONSTRAINT pk_collection_master_set_scope
        PRIMARY KEY (collection_id, card_variant_id)
);

COMMENT ON TABLE public.collection_master_set_scope IS
    'Master Set Adopted Scope (LDM-21/C-23) — Card Variants explicitamente adotadas como requisito de completude quando collection.completion_policy = MASTER_SET. Insert/Delete-only: UPDATE bloqueado estruturalmente (Query 5074). PK composta é a própria invariante de unicidade.';

ALTER TABLE public.collection_master_set_scope ENABLE ROW LEVEL SECURITY;

CREATE POLICY collection_master_set_scope_select_own
    ON public.collection_master_set_scope FOR SELECT
    USING (EXISTS (
        SELECT 1 FROM public.collection c
        WHERE c.id = collection_master_set_scope.collection_id
          AND c.owner_user_id = (select auth.uid())
    ));

GRANT SELECT ON public.collection_master_set_scope TO authenticated;

-- Nenhuma policy de INSERT/UPDATE/DELETE para authenticated — toda
-- escrita passa pelas RPCs SECURITY DEFINER (5080-5082). anon: nenhum
-- privilégio (nem GRANT SELECT).
