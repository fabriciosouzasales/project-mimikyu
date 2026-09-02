/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5040 - Create Collection Allocation Table (PROPOSTA)
Versão......: 1.0
Status......: PROPOSTA — NÃO EXECUTADA
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-01 (COLLECTIONS-PHYSICAL-INCREMENT-02C-MODELING-01
               → -REVISION-01 → -FINAL-01)

Descrição...:
Cria public.collection_allocation — associa uma Physical Card a uma
Collection (C-04). Desenho preservado exatamente como aprovado em
COLLECTIONS-PHYSICAL-INCREMENT-02C-MODELING-01 e nunca reaberto nas
revisões seguintes: id próprio, physical_card_id NOT NULL UNIQUE
(Physical Card 0..1 Collection corrente — formalização física de
C-04), collection_id NOT NULL (Collection 0..N Physical Cards),
created_at/updated_at.

physical_card NÃO recebe collection_id — a associação vive
inteiramente nesta tabela (nota já registrada em delete_collection(),
Query 5039, confirmada aqui).

Autoridade conceitual: C-04 (exclusividade colecionável), C-05
(vínculo obrigatório com Game — enforcement em 5042), C-13 (exclusão
condicionada a zero Allocations — enforcement via FK RESTRICT abaixo
+ pre-check em 5048), C-37 (ARCHIVED não aceita mudança de
composição — enforcement em 5046/5047), C-141/LDM-02 (Owner
estrutural da Collection, distinto do Owner do Inventory).

Regras de Negócio (constraints):
- physical_card_id UNIQUE: garante estruturalmente 0..1 Collection
  corrente por Physical Card — não depende de nenhuma RPC;
- as duas FKs ON UPDATE RESTRICT ON DELETE RESTRICT, mesmo padrão
  STD-001 usado em todo o domínio Collections;
- collection_allocation.collection_id -> collection.id ON DELETE
  RESTRICT é a garantia estrutural real de C-13 (delete_collection()
  não pode excluir uma Collection com Allocations) — independente de
  qualquer pre-check em RPC;
- nenhum CHECK de valor/enum nesta tabela — diferente de collection,
  não há estado próprio aqui além da existência do vínculo.

Integridade Owner x Inventory x Game NÃO é responsabilidade desta
Query — é garantida por trigger dedicado (Query 5042), porque CHECK
não pode fazer JOIN a outras tabelas.

Índice: ix_collection_allocation_collection (collection_id) cobre
"listar conteúdo da Collection". "Em qual Collection está esta carta"
já é coberto pelo índice único implícito de physical_card_id — sem
índice composto adicional (deliberadamente mínimo, sem over-indexing
sem workload que o justifique).

RLS habilitado desde a criação; única policy é SELECT via join até
collection.owner_user_id (esta tabela não tem owner_user_id próprio).
Nenhuma policy de INSERT/UPDATE/DELETE para authenticated; toda
escrita passa pelas RPCs SECURITY DEFINER (Queries 5046/5047).

STATUS DESTA QUERY: PROPOSTA — NÃO EXECUTADA.
================================================================
*/

CREATE TABLE public.collection_allocation (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    physical_card_id UUID NOT NULL UNIQUE
                         REFERENCES public.physical_card(id)
                         ON UPDATE RESTRICT ON DELETE RESTRICT,
    collection_id    UUID NOT NULL
                         REFERENCES public.collection(id)
                         ON UPDATE RESTRICT ON DELETE RESTRICT,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE public.collection_allocation IS
    'Associa uma Physical Card a uma Collection (C-04). physical_card_id UNIQUE garante 0..1 Collection corrente por Physical Card. Integridade Owner/Inventory/Game garantida por trigger (5042), não por CHECK.';

CREATE INDEX ix_collection_allocation_collection
    ON public.collection_allocation (collection_id);

ALTER TABLE public.collection_allocation ENABLE ROW LEVEL SECURITY;

CREATE POLICY collection_allocation_select_own
    ON public.collection_allocation FOR SELECT
    USING (EXISTS (
        SELECT 1 FROM public.collection c
        WHERE c.id = collection_allocation.collection_id
          AND c.owner_user_id = (select auth.uid())
    ));

GRANT SELECT ON public.collection_allocation TO authenticated;

REVOKE TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON public.collection_allocation FROM anon, authenticated;
