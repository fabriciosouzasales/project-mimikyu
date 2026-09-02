/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5063 - Update Collection Allocation Integrity Trigger (PROPOSTA)
Versão......: 1.2 (CREATE OR REPLACE sobre a função já CANÔNICA em
               database/schema/5042_create_collection_allocation_
               integrity_trigger.sql, hoje v1.1 — 5042 permanece
               intocada; esta Query é uma correção posterior, mesmo
               padrão de 5044/5048)
Status......: PROPOSTA — NÃO EXECUTADA
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-02 (COLLECTIONS-PHYSICAL-INCREMENT-02D-
               MODELING-01/-REVISION-01/-FINAL-01)

Descrição...:
Extensão de regra sobre validate_collection_allocation_integrity()
(Query 5042), não reabertura do Incremento 2C — mesma instrução
explícita de COLLECTIONS-PHYSICAL-INCREMENT-02D-MODELING-FINAL-01,
item 6: "Pode evoluir funções/triggers do 02C quando o 02D for
implementado. Isso é extensão de regra, não reabertura do 02C."

Adiciona uma quarta checagem sequencial, depois de Inventory-nulo (1),
Owner (2) e Game (3) já existentes — mesmo estilo set-based sobre
new_table, sem custo por linha:

4. Elegibilidade de Reference (LDM-17): quando a Collection é
   REFERENCE_BASED com Card Set Reference, a Card de cada Physical
   Card alocada deve pertencer ao card_set_id referenciado. O JOIN
   INNER até collection_reference/collection_card_set_reference já
   filtra naturalmente as Collections OPEN_CURATION (sem nenhuma linha
   em collection_reference, o JOIN simplesmente não casa nenhuma linha
   de new_table para elas) — a condição "col.mode = 'REFERENCE_BASED'"
   no WHERE é redundante com esse filtro, mantida por clareza
   explícita, mesmo estilo de comentário já usado nas checagens 1-3.

Fail-closed preservado: qualquer physical_card_id fora do Card Set
referenciado reprova o lote inteiro (decisão fechada em -MODELING-
FINAL-01, item 6: "Lote misto: 1 inelegível -> FAIL TOTAL") — mesma
semântica de EXISTS + RAISE EXCEPTION já usada nas três checagens
anteriores, nenhuma mudança de padrão.

Segunda camada de defesa em profundidade: a mesma checagem já existe
como pré-validação amigável em allocate_physical_cards_to_collection()
(Query 5064, extensão de 5046) — esta trigger garante que a regra vale
mesmo contra um INSERT direto em collection_allocation, bypassando a
RPC (mesmo padrão de defesa das checagens 1-3, já validadas dessa
forma em 5806, Casos I/J/K, no Incremento 2C).

STATUS DESTA QUERY: PROPOSTA — NÃO EXECUTADA.
================================================================
*/

CREATE OR REPLACE FUNCTION public.validate_collection_allocation_integrity()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    -- 1) Physical Card sem Inventory corrente nunca pode ser alocada.
    IF EXISTS (
        SELECT 1
        FROM new_table nt
        JOIN public.physical_card pc ON pc.id = nt.physical_card_id
        WHERE pc.inventory_id IS NULL
    ) THEN
        RAISE EXCEPTION 'uma ou mais physical_card_ids não possuem Inventory corrente e não podem ser alocadas';
    END IF;

    -- 2) Owner do Inventory deve ser o mesmo Owner da Collection.
    IF EXISTS (
        SELECT 1
        FROM new_table nt
        JOIN public.physical_card pc ON pc.id = nt.physical_card_id
        JOIN public.inventory inv ON inv.id = pc.inventory_id
        JOIN public.collection col ON col.id = nt.collection_id
        WHERE inv.owner_user_id IS DISTINCT FROM col.owner_user_id
    ) THEN
        RAISE EXCEPTION 'uma ou mais physical_card_ids não pertencem ao Owner da Collection';
    END IF;

    -- 3) Game da Physical Card deve coincidir com collection.game_id
    --    (C-05).
    IF EXISTS (
        SELECT 1
        FROM new_table nt
        JOIN public.physical_card pc ON pc.id = nt.physical_card_id
        JOIN public.card_variant cv ON cv.id = pc.card_variant_id
        JOIN public.card ca ON ca.id = cv.card_id
        JOIN public.card_set cs ON cs.id = ca.card_set_id
        JOIN public.expansion ex ON ex.id = cs.expansion_id
        JOIN public.collection col ON col.id = nt.collection_id
        WHERE ex.game_id IS DISTINCT FROM col.game_id
    ) THEN
        RAISE EXCEPTION 'uma ou mais physical_card_ids pertencem a um Game diferente do Game da Collection';
    END IF;

    -- 4) Collection REFERENCE_BASED + CARD_SET: Card deve pertencer ao
    --    card_set_id referenciado (LDM-17). O INNER JOIN até
    --    collection_reference/collection_card_set_reference já exclui
    --    naturalmente Collections OPEN_CURATION (sem linha em
    --    collection_reference).
    IF EXISTS (
        SELECT 1
        FROM new_table nt
        JOIN public.physical_card pc ON pc.id = nt.physical_card_id
        JOIN public.card_variant cv ON cv.id = pc.card_variant_id
        JOIN public.card ca ON ca.id = cv.card_id
        JOIN public.collection col ON col.id = nt.collection_id
        JOIN public.collection_reference cr ON cr.collection_id = col.id
        JOIN public.collection_card_set_reference ccsr ON ccsr.collection_reference_id = cr.id
        WHERE col.mode = 'REFERENCE_BASED'
          AND cr.reference_kind = 'CARD_SET'
          AND ca.card_set_id IS DISTINCT FROM ccsr.card_set_id
    ) THEN
        RAISE EXCEPTION 'uma ou mais physical_card_ids não pertencem ao Card Set referenciado pela Collection';
    END IF;

    RETURN NULL;
END;
$$;
