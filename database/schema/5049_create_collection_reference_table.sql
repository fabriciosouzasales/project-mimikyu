/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5049 - Create Collection Reference Table
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-02 (aplicado em 2026-09-02,
               COLLECTIONS-PHYSICAL-INCREMENT-02D-IMPLEMENTATION-01)

Descrição...:
Cria public.collection_reference — supertipo da hierarquia de
Collection Reference (LDM-06/LDM-13), entidade própria e não uma
coluna solta em collection. Rejeita deliberadamente um desenho
polimórfico solto (reference_type + reference_id sem FK forte) —
decisão já fechada em LDM-06, não reaberta aqui.

collection_id UNIQUE estrutura fisicamente a cardinalidade "0..1
Collection Reference por Collection" (LDM-13). reference_kind é
discriminador explícito, não FK a nenhuma tabela — o identificador
canônico concreto mora sempre no subtipo (collection_card_set_
reference nesta rodada; collection_pokedex_reference é futuro,
LDM-06/LDM-15).

chk_collection_reference_kind fisicamente só 'CARD_SET' nesta etapa
— mesmo padrão incremental já usado em chk_collection_mode (5030):
alargável por DROP+ADD CONSTRAINT quando collection_pokedex_reference
existir, nunca pré-declarando um valor sem tabela correspondente.

ON DELETE CASCADE em collection_id (não RESTRICT): decisão fechada em
COLLECTIONS-PHYSICAL-INCREMENT-02D-MODELING-REVISION-01, item 4 —
Collection Reference não tem existência independente da Collection
que a contém; excluir a Collection deve levar consigo sua Reference,
sem exigir um passo extra na RPC de delete. Diferente de collection_
allocation (ON DELETE RESTRICT), que aponta para um ativo patrimonial
externo (physical_card) que nunca deve desaparecer silenciosamente —
aqui não há nenhum ativo do Owner fora da própria Collection sendo
apagado.

A garantia de que toda Collection REFERENCE_BASED possui exatamente
uma linha aqui, e toda OPEN_CURATION possui zero, NÃO é feita por
nenhuma constraint desta Query — é responsabilidade dos constraint
triggers DEFERRABLE INITIALLY DEFERRED das Queries 5057/5059 (ver seus
cabeçalhos). Este arquivo só cria a estrutura; o enforcement
transacional mora em arquivos próprios, por clareza de leitura.

RLS: SELECT via join até collection.owner_user_id — mesmo padrão de
collection_allocation (5040), já que esta tabela não tem owner_user_id
próprio. Nenhuma policy de escrita para authenticated; toda escrita
passa por RPCs SECURITY DEFINER (Queries 5065/5066, ver seus
cabeçalhos) ou pelos triggers estruturais desta rodada.

STATUS DESTA QUERY: CONFIRMADO EXECUTADO.
================================================================
*/

CREATE TABLE public.collection_reference (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    collection_id  UUID NOT NULL UNIQUE
                      REFERENCES public.collection(id)
                      ON UPDATE RESTRICT ON DELETE CASCADE,
    reference_kind TEXT NOT NULL,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE public.collection_reference IS
    'Supertipo de Collection Reference (LDM-06/LDM-13) — universo canônico de uma Collection REFERENCE_BASED. collection_id UNIQUE = 0..1 por Collection. reference_kind fisicamente só CARD_SET nesta etapa.';

ALTER TABLE public.collection_reference
    ADD CONSTRAINT chk_collection_reference_kind
    CHECK (reference_kind IN ('CARD_SET'));

ALTER TABLE public.collection_reference ENABLE ROW LEVEL SECURITY;

CREATE POLICY collection_reference_select_own
    ON public.collection_reference FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.collection col
            WHERE col.id = collection_reference.collection_id
              AND col.owner_user_id = (select auth.uid())
        )
    );

GRANT SELECT ON public.collection_reference TO authenticated;

REVOKE TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON public.collection_reference FROM anon, authenticated;
