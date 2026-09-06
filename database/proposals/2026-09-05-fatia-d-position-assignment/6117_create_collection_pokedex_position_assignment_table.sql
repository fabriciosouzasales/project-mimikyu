/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 6117 - Create Collection Pokédex Position Assignment Table
Versão......: 1.0 (STAGING — NÃO EXECUTADO)
Status......: PROPOSTO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-05 (staging em
               COLLECTIONS-POKEDEX-FATIA-D-STAGING-01, após
               -PHYSICAL-MODELING-AUDIT-01 e -PHYSICAL-MODELING-
               REVISION-01, ambas read-only)

Descrição...:
Materializa fisicamente LDM-179 ("Pokédex Position Assignment") —
o vínculo explícito entre um Physical Card já alocado a uma Collection
Pokédex (public.collection_allocation) e uma public.pokedex_position
específica. Allocation sozinha NUNCA satisfaz uma Position (LDM-179) —
esta tabela é a diferença estrutural entre "o Physical Card está na
Collection" e "o Physical Card representa esta Position".

Cardinalidade — decisão central (Fatia D, Physical Modeling Audit-01,
item A): PK/FK compartilhada em collection_allocation_id, não um par
(physical_card_id, collection_id) duplicado. Como
collection_allocation.physical_card_id já é UNIQUE (um Physical Card
só pode estar alocado a uma única Collection em todo o sistema), usar
collection_allocation_id como PK entrega de graça as duas invariantes
de LDM-179 sem constraint adicional: "1 Allocation, no máximo 1
Assignment" (é a própria PK) e "1 Physical Card, no máximo 1 Assignment
por Collection Pokédex" (trivial, já que 1 Physical Card = 1 Allocation
no sistema inteiro). Mesmo padrão supertipo/subtipo de PK compartilhada
já usado em collection_reference/collection_pokedex_reference (02D,
Query 5052/5087).

"N Assignments por Position" (LDM-179): nenhuma UNIQUE em
pokedex_position_id sozinho — múltiplos Physical Cards distintos (logo,
múltiplas Allocations, múltiplas PKs distintas nesta tabela) podem
apontar para a mesma Position.

assignment_basis distingue como o vínculo foi criado (LDM-178):
- SPECIES_MATCH: Primary Species da Card (card_primary_species,
  Fatia C) corresponde exatamente à Species da Position — criado
  automaticamente pelo trigger da Query 6119, nunca por confirmação
  humana. assigned_by_user_id é NULL para estas linhas.
- USER_OVERRIDE: mismatch, Species ausente, ou Card Trainer/Energy —
  exige confirmação explícita via set_pokedex_position_assignment()
  (Query 6122, p_confirm_override = true). assigned_by_user_id é o
  auth.uid() do chamador no momento da confirmação.

Deliberadamente SEM CHECK de acoplamento assignment_basis <->
assigned_by_user_id (diferente de card_primary_species, Query 6112,
chk_card_primary_species_basis_resolver_coupling): a Revision-01 desta
Fatia introduziu ON DELETE SET NULL em assigned_by_user_id (abaixo) —
se um usuário for excluído, uma linha USER_OVERRIDE precisa poder
transicionar para assigned_by_user_id = NULL sem violar nenhum CHECK.
Um CHECK de acoplamento quebraria exatamente essa ação referencial.
A ausência de assigned_by_user_id numa linha USER_OVERRIDE após essa
transição é lida como "confirmado por um usuário que não existe mais",
não como dado inconsistente.

IMUTABILIDADE (Physical Modeling Revision-01 + esta rodada): a linha é
semanticamente imutável — só existe INSERT e DELETE em operação normal.
"Mover" uma Assignment para outra Position é sempre DELETE da linha
antiga + INSERT de uma linha nova (mesma PK física, linha nova) dentro
da mesma chamada de RPC — nunca um UPDATE de pokedex_position_id. A
ÚNICA exceção tecnicamente necessária é a consequência de
ON DELETE SET NULL em assigned_by_user_id quando o auth.users referido
é excluído — essa é uma ação referencial do próprio Postgres, não uma
escrita de aplicação, e é a única forma de UPDATE que o trigger da
Query 6118 permite (ver header daquela Query). Nenhum GRANT de UPDATE é
concedido a nenhum papel nesta Query — a ação referencial do Postgres
não depende de GRANT de tabela para o papel que originou a exclusão em
auth.users.

Scope (LDM-177): esta tabela NUNCA referencia
collection_pokedex_scope_generation nem scope_kind. Uma Assignment pode
existir fora do Scope corrente da Collection — permanece preservada,
apenas não conta para completion (responsabilidade de uma futura
Fatia E, não desta Query).

RLS: leitura restrita ao Owner da Collection (via
collection_allocation -> collection.owner_user_id), mesmo padrão de
collection_allocation_select_own. Nenhuma policy de escrita — toda
escrita passa exclusivamente pelas funções SECURITY DEFINER das
Queries 6119 (automática), 6122 e 6124 (RPCs — 6124 é remove_pokedex_
position_assignment(), renumerada de 6123 para 6124 em
RENUMBER-FIX-STAGING-01), que escrevem com os
privilégios do dono da função. REVOKE explícito de ALL de
anon/authenticated/service_role antes de conceder SELECT — mesma
lição de least privilege já aplicada em 6112 (Query 6111: privilégio
herdado por pg_default_acl do role postgres).

Pré-requisitos:
- Query 6040/6041 - Create Pokedex Position Table.
- Query 5040-5048 (2C) - Create Collection Allocation Table.
- Query 6112 - Create Card Primary Species Table (usada por 6119/6122).
================================================================
*/

BEGIN;

CREATE TABLE public.collection_pokedex_position_assignment (
    collection_allocation_id UUID PRIMARY KEY
                                REFERENCES public.collection_allocation(id)
                                ON UPDATE RESTRICT ON DELETE CASCADE,
    pokedex_position_id      UUID NOT NULL
                                REFERENCES public.pokedex_position(id)
                                ON UPDATE RESTRICT ON DELETE RESTRICT,
    assignment_basis         TEXT NOT NULL,
    assigned_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    assigned_by_user_id      UUID,

    CONSTRAINT fk_collection_pokedex_position_assignment_assigned_by_user_id
        FOREIGN KEY (assigned_by_user_id)
        REFERENCES auth.users (id)
        ON DELETE SET NULL,

    CONSTRAINT chk_collection_pokedex_position_assignment_basis
        CHECK (assignment_basis IN ('SPECIES_MATCH', 'USER_OVERRIDE'))
);

COMMENT ON TABLE public.collection_pokedex_position_assignment IS
    'Vínculo explícito Physical Card alocado -> Pokédex Position (LDM-179). PK/FK compartilhada em collection_allocation_id (1:1 com a Allocation). Linha imutável (INSERT/DELETE only, salvo ON DELETE SET NULL técnico de assigned_by_user_id, Query 6118). Scope (LDM-177) nunca participa desta integridade.';

COMMENT ON COLUMN public.collection_pokedex_position_assignment.collection_allocation_id IS
    'PK=FK 1:1 para collection_allocation. ON DELETE CASCADE: desalocar o Physical Card (deallocate_physical_cards_from_collection) remove a Assignment operacional correspondente, estruturalmente, sem código adicional na RPC de deallocate.';

COMMENT ON COLUMN public.collection_pokedex_position_assignment.pokedex_position_id IS
    'Position representada. RESTRICT: catálogo de Position é permanente. Validado por trigger (Query 6118) contra o Pokédex referenciado pela Collection da Allocation — nunca contra o Scope adotado.';

COMMENT ON COLUMN public.collection_pokedex_position_assignment.assignment_basis IS
    'SPECIES_MATCH (automático, trigger da Query 6119, assigned_by_user_id sempre NULL) ou USER_OVERRIDE (confirmação explícita via Query 6122). Vocabulário distinto de resolution_basis de card_primary_species (Query 6112) — responsabilidades diferentes (LDM-178 vs LDM-182).';

COMMENT ON COLUMN public.collection_pokedex_position_assignment.assigned_by_user_id IS
    'Usuário que confirmou um USER_OVERRIDE; sempre NULL para SPECIES_MATCH. Anulável (ON DELETE SET NULL) para sobreviver à exclusão futura do usuário sem apagar a Assignment nem seu histórico. Único caminho de UPDATE permitido pelo trigger da Query 6118.';

CREATE INDEX idx_collection_pokedex_position_assignment_position_id
    ON public.collection_pokedex_position_assignment (pokedex_position_id);

COMMENT ON INDEX public.idx_collection_pokedex_position_assignment_position_id IS
    'Suporta lookup Position -> Assignments (ex.: contar quantos exemplares representam uma Position, futuro read model de completion/Fatia E). FK não é indexada automaticamente pelo Postgres.';

ALTER TABLE public.collection_pokedex_position_assignment ENABLE ROW LEVEL SECURITY;

CREATE POLICY collection_pokedex_position_assignment_select_own
    ON public.collection_pokedex_position_assignment
    FOR SELECT USING (
        EXISTS (
            SELECT 1
              FROM public.collection_allocation ca
              JOIN public.collection col ON col.id = ca.collection_id
             WHERE ca.id = collection_pokedex_position_assignment.collection_allocation_id
               AND col.owner_user_id = (SELECT auth.uid())
        )
    );

REVOKE ALL ON public.collection_pokedex_position_assignment
    FROM anon, authenticated, service_role;

GRANT SELECT ON public.collection_pokedex_position_assignment TO authenticated;

COMMIT;
