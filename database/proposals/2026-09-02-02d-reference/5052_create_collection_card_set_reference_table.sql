/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5052 - Create Collection Card Set Reference Table (PROPOSTA)
Versão......: 1.0
Status......: PROPOSTA — NÃO EXECUTADA
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-02 (COLLECTIONS-PHYSICAL-INCREMENT-02D-
               MODELING-01/-REVISION-01/-FINAL-01)

Descrição...:
Cria public.collection_card_set_reference — primeiro (e único, nesta
rodada) subtipo físico de Collection Reference, correspondendo a
reference_kind = 'CARD_SET' (LDM-14). collection_pokedex_reference
(reference_kind = 'POKEDEX', LDM-15/LDM-16) permanece deliberadamente
fora de escopo — Pokédex/Pokédex Position nem existem fisicamente
ainda, e o desenho supertipo/subtipo já acomoda essa extensão futura
sem exigir nenhuma migration destrutiva sobre esta tabela.

PK = FK do supertipo (collection_reference_id), padrão clássico de
subtipo 1:1 — nunca um id próprio duplicando identidade. card_set_id é
FK forte (LDM-14: "not a loose polymorphic reference"); nenhum
metadado de card_set é duplicado aqui (nome, códigos, tamanho do set
seguem existindo só em public.card_set).

card_set_id NÃO é UNIQUE nesta tabela — C-32 ("múltiplas Collections
para a mesma referência... a referência canônica não é exclusiva por
usuário") permite que o mesmo Card Set seja referenciado por
Collections diferentes, inclusive do mesmo Owner.

ON DELETE CASCADE em collection_reference_id: mesma decisão de 5049
(item 4 da rodada -MODELING-FINAL-01) — subtipo não tem existência
independente do supertipo. ON DELETE RESTRICT em card_set_id:
preservado deliberadamente — excluir uma Collection (e cascatear até
aqui) nunca pode excluir catálogo.

A garantia de que todo Collection Reference de kind CARD_SET possui
exatamente uma linha aqui — e vice-versa, que toda linha aqui aponta
para um Collection Reference de kind CARD_SET — é responsabilidade dos
constraint triggers das Queries 5057/5058, não desta Query.

Integridade de Game (card_set_id deve pertencer ao mesmo Game da
Collection) e imutabilidade de card_set_id após reference_locked_at
são responsabilidade da Query 5055 (trigger dedicado) — não uma FK
composta possível aqui (card_set não tem game_id direto, só via
card_set.expansion_id -> expansion.game_id, mesma limitação já
enfrentada por collection x storage_container em 5033).

RLS: mesmo padrão de collection_reference (5049) — SELECT via join
duplo até collection.owner_user_id. Nenhuma policy de escrita para
authenticated.

STATUS DESTA QUERY: PROPOSTA — NÃO EXECUTADA.
================================================================
*/

CREATE TABLE public.collection_card_set_reference (
    collection_reference_id UUID PRIMARY KEY
                                REFERENCES public.collection_reference(id)
                                ON UPDATE RESTRICT ON DELETE CASCADE,
    card_set_id               UUID NOT NULL
                                REFERENCES public.card_set(id)
                                ON UPDATE RESTRICT ON DELETE RESTRICT,
    created_at                TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at                TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE public.collection_card_set_reference IS
    'Subtipo de Collection Reference para reference_kind = CARD_SET (LDM-14). card_set_id é a única fonte canônica desta Collection (C-22) — imutável após reference_locked_at (ver Query 5055).';

-- Nenhum índice adicional em card_set_id nesta rodada: nenhum padrão de
-- acesso "todas as Collections que referenciam este Card Set" foi
-- identificado nos workloads pedidos (COLLECTIONS-PHYSICAL-INCREMENT-
-- 02D-MODELING-01, item 12) — adicionar por especulação seria
-- over-indexing. A PK (collection_reference_id) já cobre o único
-- padrão de leitura conhecido hoje (Collection -> Reference -> subtipo).

ALTER TABLE public.collection_card_set_reference ENABLE ROW LEVEL SECURITY;

CREATE POLICY collection_card_set_reference_select_own
    ON public.collection_card_set_reference FOR SELECT
    USING (
        EXISTS (
            SELECT 1
            FROM public.collection_reference cr
            JOIN public.collection col ON col.id = cr.collection_id
            WHERE cr.id = collection_card_set_reference.collection_reference_id
              AND col.owner_user_id = (select auth.uid())
        )
    );

GRANT SELECT ON public.collection_card_set_reference TO authenticated;

REVOKE TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON public.collection_card_set_reference FROM anon, authenticated;
