/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5115 - Create Collection Layout Slot Assignment Table
Versão......: 2.0
Status......: PROPOSTA — STAGING, NÃO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-06 (staging em
               COLLECTIONS-BINDER-LAYOUT-FOUNDATION-STAGING-01)

Descrição...:
Cria public.collection_layout_slot_assignment — a relação que registra
que uma Physical Card está, AGORA, posicionada em um Slot do Layout
(C-44 / LDM-35).

Nomenclatura: SLOT ASSIGNMENT. O termo "Placement" é NÃO-CANÔNICO
desde COLLECTIONS-DOMAIN-REENTRY-01 e não deve reaparecer.

BINDER SLOT ASSIGNMENT != POKÉDEX POSITION ASSIGNMENT. São relações
de DOMÍNIOS DIFERENTES e não devem ser confundidas nem unificadas:
- collection_layout_slot_assignment (esta) = organização VISUAL/
  espacial dentro do Layout. NÃO participa de completion.
- collection_pokedex_position_assignment (Fatia D, Query 6117) =
  satisfação de uma Pokédex Position. É a ÚNICA que alimenta
  completion REFERENCE_POSITION (Fatia E, Queries 5100-5103).
Uma Physical Card pode ter as duas, uma, ou nenhuma. Elas não se
implicam, não se sincronizam e não compartilham constraint alguma.

DP-07 (congelado): a FK aponta para collection_allocation, NÃO para
physical_card. Três razões:
 1. É o que o invariante exige. C-44 diz "exige que a Physical Card já
    esteja alocada à mesma Collection". Referenciar a Allocation É
    referenciar o fato da alocação.
 2. Torna o invariante estruturalmente alcançável: a Collection da
    Assignment vem de assignment -> allocation -> collection_id, e a
    do Slot de slot -> page -> layout -> collection_id. Comparação
    determinística (trigger 5117).
 3. ON DELETE CASCADE resolve o ciclo de vida declarativamente:
    desalocar a Card da Collection remove a Assignment, porque uma
    Card fora da Collection não pode ocupar Slot do Layout dessa
    Collection. Precedente vivo e validado: a Fatia D usa exatamente
    este padrão (collection_pokedex_position_assignment ->
    collection_allocation, ON DELETE CASCADE).

LDM-35 escrevia a pré-condição como "physical_card_id.collection_id".
Esse campo NUNCA existiu fisicamente: physical_card não tem
collection_id — a alocação vive inteiramente em collection_allocation
desde a Fatia 02C (Query 5040). O texto do LDM descrevia um skeleton
anterior; a SEMÂNTICA de C-44 permanece intocada, apenas a
materialização foi traduzida para o modelo atual.

CARDINALIDADE:
- UNIQUE (slot_id) DEFERRABLE INITIALLY DEFERRED — "no máximo uma
  Physical Card por Slot" (C-44). O DEFERRABLE é o que viabiliza o
  SWAP: duas linhas trocam slot_id na mesma transação, com o estado
  intermediário colidente tolerado até o COMMIT.
- UNIQUE (collection_allocation_id) — "no máximo uma Assignment ativa
  por (Physical Card, Layout)" (C-44).

  RESTRIÇÃO V1, DECORRENTE DE DP-01: como a V1 admite exatamente
  0..1 Layout por Collection, e collection_allocation já impõe
  UNIQUE (physical_card_id) desde a Query 5040 (uma Physical Card
  pertence a no máximo UMA Collection), o par (Physical Card, Layout)
  degenera para a própria Allocation. QUANDO MÚLTIPLOS LAYOUTS FOREM
  FORMALMENTE HABILITADOS, ESTA CONSTRAINT PRECISARÁ SER REVISTA
  JUNTO DA CARDINALIDADE (Physical Card, Layout) — provavelmente
  virando UNIQUE (collection_allocation_id, layout_id) com layout_id
  denormalizado ou alcançado por FK composta. Registrado no README.

"Ativa" e "termina", no texto de LDM-35, significam EXCLUSIVAMENTE
"a linha existe" e "a linha foi apagada". Como C-44/LDM-35 fecham que
a relação NÃO tem identidade de negócio nem lifecycle próprio, NÃO
existe coluna status, NÃO existe ended_at, NÃO existe soft delete.

`id` técnico existe apenas como identificador de implementação — "um
identificador técnico de implementação, se existir, não constitui
identidade de domínio" (C-44, literal). Ele torna MOVE um UPDATE de
coluna comum em vez de UPDATE da própria PK, e permite ao harness
provar que MOVE/SWAP preservam a linha em vez de recriá-la.

Timestamps mínimos conforme convenção física vigente (created_at/
updated_at), espelhando o que a Fatia D já usa. NÃO é audit trail —
Audit/Undo-Redo permanecem DEFERRED (DP-10), pertencendo à frente
Activity History/Audit (LDM-154–174).

FK slot_id ON DELETE RESTRICT: Assignment é CONTEÚDO. Apagar a Page é
bloqueado enquanto houver Assignment em seus Slots (C-39).

Dependências:
- public.collection_layout_slot (Query 5110).
- public.collection_allocation (Query 5040).

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

CREATE TABLE public.collection_layout_slot_assignment (
    id                       UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    slot_id                  UUID        NOT NULL
                             REFERENCES public.collection_layout_slot(id)
                             ON UPDATE RESTRICT ON DELETE RESTRICT,
    collection_allocation_id UUID        NOT NULL
                             REFERENCES public.collection_allocation(id)
                             ON UPDATE RESTRICT ON DELETE CASCADE,
    created_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at               TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT uq_collection_layout_slot_assignment_slot
        UNIQUE (slot_id) DEFERRABLE INITIALLY DEFERRED,

    CONSTRAINT uq_collection_layout_slot_assignment_allocation
        UNIQUE (collection_allocation_id)
);

COMMENT ON TABLE public.collection_layout_slot_assignment IS
    'Slot Assignment (C-44/LDM-35): Physical Card posicionada em um '
    'Slot do Layout. FK para collection_allocation (DP-07), nunca '
    'para physical_card. Sem status, sem ended_at, sem identidade de '
    'domínio. NÃO é Pokédex Position Assignment — domínios distintos, '
    'nunca unificar. NÃO participa de completion.';

COMMENT ON CONSTRAINT uq_collection_layout_slot_assignment_slot
    ON public.collection_layout_slot_assignment IS
    'Máximo 1 Physical Card por Slot (C-44). DEFERRABLE para permitir '
    'o estado intermediário do SWAP dentro da transação.';

COMMENT ON CONSTRAINT uq_collection_layout_slot_assignment_allocation
    ON public.collection_layout_slot_assignment IS
    'RESTRIÇÃO V1 (DP-01): 1 Assignment por Allocation. Deve ser '
    'revista junto da cardinalidade (Physical Card, Layout) quando '
    'múltiplos Layouts por Collection forem habilitados.';

ALTER TABLE public.collection_layout_slot_assignment
    ENABLE ROW LEVEL SECURITY;

CREATE POLICY collection_layout_slot_assignment_select_own
    ON public.collection_layout_slot_assignment FOR SELECT
    USING (EXISTS (
        SELECT 1
        FROM public.collection_layout_slot s
        JOIN public.collection_layout_page p ON p.id = s.page_id
        JOIN public.collection_layout l      ON l.id = p.layout_id
        JOIN public.collection c             ON c.id = l.collection_id
        WHERE s.id = collection_layout_slot_assignment.slot_id
          AND c.owner_user_id = (select auth.uid())
    ));

GRANT SELECT ON public.collection_layout_slot_assignment TO authenticated;

REVOKE TRUNCATE, REFERENCES, TRIGGER, MAINTAIN
    ON public.collection_layout_slot_assignment FROM anon, authenticated;

-- §9 CORREÇÃO CONSOLIDADA 01 — DML nunca é concedido a cliente algum.
-- Explícito, não herdado de default privileges.
REVOKE INSERT, UPDATE, DELETE ON public.collection_layout_slot_assignment
    FROM PUBLIC, anon, authenticated;

COMMIT;

/*
Como validar:

SELECT conname, pg_get_constraintdef(oid), condeferrable, condeferred
FROM pg_constraint
WHERE conrelid = 'public.collection_layout_slot_assignment'::regclass
ORDER BY contype, conname;

Esperado: UNIQUE(slot_id) DEFERRABLE/deferred, UNIQUE(collection_allocation_id)
NÃO deferrable, FK para collection_allocation com ON DELETE CASCADE,
FK para collection_layout_slot com ON DELETE RESTRICT.
*/
