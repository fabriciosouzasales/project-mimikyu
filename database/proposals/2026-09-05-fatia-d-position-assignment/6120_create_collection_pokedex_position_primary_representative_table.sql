/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 6120 - Create Collection Pokédex Position Primary Representative Table
Versão......: 1.0 (STAGING — NÃO EXECUTADO)
Status......: PROPOSTO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-05 (staging em COLLECTIONS-POKEDEX-FATIA-D-STAGING-01,
               após -PHYSICAL-MODELING-AUDIT-01, item F, e
               -PHYSICAL-MODELING-REVISION-01, item 3)

Descrição...:
Materializa LDM-180 ("Primary Representative") — dentre as Assignments
de uma Position (Query 6117), qual Physical Card é escolhido para
representá-la em telas de apresentação. Opcional, 0..1 por
(Collection, Position); nunca afeta completion (LDM-181, Fatia E).

Entidade separada, não boolean na Assignment (Audit-01, item F,
decisão confirmada): um índice único parcial sobre um boolean exigiria
denormalizar collection_id dentro da própria Assignment só para
viabilizar a expressão do índice (um índice parcial não pode
referenciar outra tabela) — mais uma coluna redundante e um trigger de
sincronização. A entidade separada obtém a cardinalidade "no máximo um
Primary por Collection+Position" diretamente da PK composta, sem
nenhuma coluna redundante.

PK (collection_id, pokedex_position_id) — mandato STAGING-01, item 2:
garante a cardinalidade por construção, sem trigger.

FKs explícitas (mandato STAGING-01, item 2 — divergência deliberada do
desenho inicial do Audit-01, que derivava collection_id/pokedex_
position_id só transitivamente via collection_allocation_id):
- collection_id -> collection(id) ON DELETE RESTRICT: mesma convenção
  de collection_allocation_collection_id_fkey (2C) — uma Collection só
  pode ser excluída quando já não tem nenhuma Allocation (delete_
  collection(), Query 5039, verifica isso explicitamente antes do
  DELETE); como Assignment/Primary só existem em cima de uma Allocation
  viva, esta FK nunca é de fato exercida em operação normal — é
  consistência de convenção com 2C, não um caminho vivo.
- pokedex_position_id -> pokedex_position(id) ON DELETE RESTRICT: mesma
  convenção de pokedex_position_species_id_fkey e de card_primary_
  species.pokemon_species_id (Query 6112) — catálogo de Position é
  permanente.
- collection_allocation_id -> collection_pokedex_position_assignment
  (collection_allocation_id) UNIQUE, ON DELETE CASCADE: a peça central
  da integridade de lifecycle (Revision-01 + STAGING-01, item 1) —
  remover OU mover uma Assignment (Query 6122: mover é sempre DELETE da
  linha antiga + INSERT de uma nova, nunca UPDATE) apaga a linha
  antiga; este CASCADE remove automaticamente o Primary Representative
  que apontava para ela, sem nenhum trigger de sincronização adicional.
  UNIQUE garante que uma mesma Assignment nunca é Primary de mais de um
  par (Collection, Position) — propriedade já trivial (uma Assignment
  pertence a exatamente uma Position), mas declarada explicitamente
  para permitir a FK apontar para uma chave candidata em vez da PK
  física de public.collection_allocation.

Trigger de integridade (Query 6121): mesmo com as FKs acima garantindo
que o collection_allocation_id referenciado É uma Assignment existente,
nada nas FKs sozinhas impede alguém de gravar um
(collection_id, pokedex_position_id) que NÃO bate com a Collection/
Position reais daquela Assignment (ex.: Primary de uma Position B
apontando para uma Assignment que na verdade pertence à Position A) —
essa checagem cruzada é responsabilidade do trigger, não desta Query.

Não auto-criado nesta Fatia: nenhuma Query desta rodada popula esta
tabela automaticamente — só existe via set_pokedex_position_primary_
representative() (Query 6125, renumerada de 6124 em
RENUMBER-FIX-STAGING-01), chamada explícita do usuário.

RLS: leitura restrita ao Owner (via collection_id direto, mais simples
que o padrão indireto de collection_pokedex_position_assignment, já
que aqui collection_id é uma coluna própria). REVOKE ALL de
anon/authenticated/service_role antes de conceder SELECT — mesma
disciplina de least privilege de 6112/6117.

Pré-requisitos:
- Query 6117 - Create Collection Pokédex Position Assignment Table.
================================================================
*/

BEGIN;

CREATE TABLE public.collection_pokedex_position_primary_representative (
    collection_id             UUID NOT NULL
                                REFERENCES public.collection(id)
                                ON UPDATE RESTRICT ON DELETE RESTRICT,
    pokedex_position_id       UUID NOT NULL
                                REFERENCES public.pokedex_position(id)
                                ON UPDATE RESTRICT ON DELETE RESTRICT,
    collection_allocation_id  UUID NOT NULL,
    created_at                TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at                TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT pk_collection_pokedex_position_primary_representative
        PRIMARY KEY (collection_id, pokedex_position_id),

    CONSTRAINT uq_collection_pokedex_position_primary_representative_assignment
        UNIQUE (collection_allocation_id),

    CONSTRAINT fk_collection_pokedex_position_primary_representative_assignment
        FOREIGN KEY (collection_allocation_id)
        REFERENCES public.collection_pokedex_position_assignment (collection_allocation_id)
        ON UPDATE RESTRICT ON DELETE CASCADE
);

COMMENT ON TABLE public.collection_pokedex_position_primary_representative IS
    'Ponteiro opcional (0..1 por Collection+Position) para qual Assignment representa a Position em telas de apresentação (LDM-180). Nunca afeta completion (LDM-181, Fatia E). Removido por CASCADE quando a Assignment apontada é removida ou movida (DELETE, Query 6122/6124 — 6124 é remove_pokedex_position_assignment(), renumerada de 6123).';

COMMENT ON COLUMN public.collection_pokedex_position_primary_representative.collection_id IS
    'RESTRICT: mesma convenção de collection_allocation_collection_id_fkey (2C) — delete_collection() (Query 5039) já bloqueia a exclusão de Collections com Allocations vivas antes desta FK ser exercida.';

COMMENT ON COLUMN public.collection_pokedex_position_primary_representative.pokedex_position_id IS
    'RESTRICT: catálogo de Position é permanente, mesma convenção de pokedex_position_species_id_fkey. Validado por trigger (Query 6121) contra a Position real da Assignment referenciada.';

COMMENT ON COLUMN public.collection_pokedex_position_primary_representative.collection_allocation_id IS
    'FK para a chave candidata (UNIQUE) collection_pokedex_position_assignment.collection_allocation_id. ON DELETE CASCADE é o mecanismo estrutural único que remove um Primary Representative órfão quando a Assignment apontada é removida ou movida — nenhum trigger de sincronização adicional (ver Query 6117/6118, header).';

ALTER TABLE public.collection_pokedex_position_primary_representative ENABLE ROW LEVEL SECURITY;

CREATE POLICY collection_pokedex_position_primary_representative_select_own
    ON public.collection_pokedex_position_primary_representative
    FOR SELECT USING (
        EXISTS (
            SELECT 1
              FROM public.collection col
             WHERE col.id = collection_pokedex_position_primary_representative.collection_id
               AND col.owner_user_id = (SELECT auth.uid())
        )
    );

REVOKE ALL ON public.collection_pokedex_position_primary_representative
    FROM anon, authenticated, service_role;

GRANT SELECT ON public.collection_pokedex_position_primary_representative TO authenticated;

COMMIT;
