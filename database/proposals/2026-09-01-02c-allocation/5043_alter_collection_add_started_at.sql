/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5043 - Alter Collection: Add started_at (PROPOSTA)
Versão......: 1.0
Status......: PROPOSTA — NÃO EXECUTADA
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-01 (COLLECTIONS-PHYSICAL-INCREMENT-02C-MODELING-
               FINAL-01, item 3)

Descrição...:
Adiciona collection.started_at — deliberadamente excluído do skeleton
físico original (Query 5030, COLLECTIONS-PHYSICAL-INCREMENT-02B) por
"primeira alocação ainda não existe" (C-30/LDM-11). Agora que
Collection Allocation existe (Query 5040), o fato que started_at
representa passa a existir.

Semântica (LDM-11): created_at = criação da Collection no MMKYU;
started_at = primeira Collection Allocation efetivamente persistida.
Nulável — Collection nunca populada permanece started_at IS NULL
indefinidamente. Depois de definido, imutável (enforcement em 5044).
Nunca derivado de NOW() na RPC — materializado a partir do próprio
fato físico (MIN(collection_allocation.created_at)) por um trigger
dedicado (Query 5045), nunca escrito diretamente por
allocate_physical_cards_to_collection() (Query 5046).

CHECK chk_collection_started_at_not_before_created: defesa barata,
mesmo espírito de chk_collection_archived_at_consistency já existente
nesta tabela — started_at nunca pode preceder a própria criação da
Collection.

STATUS DESTA QUERY: PROPOSTA — NÃO EXECUTADA.
================================================================
*/

ALTER TABLE public.collection
    ADD COLUMN started_at TIMESTAMPTZ NULL;

ALTER TABLE public.collection
    ADD CONSTRAINT chk_collection_started_at_not_before_created
    CHECK (started_at IS NULL OR started_at >= created_at);
