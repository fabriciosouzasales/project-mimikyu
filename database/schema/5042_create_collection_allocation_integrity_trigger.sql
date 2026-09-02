/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5042 - Create Collection Allocation Integrity Trigger
Versão......: 1.2 (estendida em 2026-09-02, aplicada em 2026-09-02, via
               Query 5063, COLLECTIONS-PHYSICAL-INCREMENT-02D-
               IMPLEMENTATION-01)
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-01 (aplicado em 2026-09-02,
               COLLECTIONS-PHYSICAL-INCREMENT-02C-IMPLEMENTATION-01;
               estendida em 2026-09-02, via Query 5063, COLLECTIONS-
               PHYSICAL-INCREMENT-02D-IMPLEMENTATION-01)

Descrição...:
Garante estruturalmente, independente de qualquer RPC, que toda
Collection Allocation satisfaz simultaneamente:
1. a Physical Card possui Inventory corrente (inventory_id NOT NULL);
2. o Owner desse Inventory é o mesmo Owner da Collection (C-141);
3. o Game da Physical Card (via card_variant -> card -> card_set ->
   expansion -> game_id) é o mesmo Game da Collection (C-05 — "Todas
   as Physical Cards alocadas nela devem pertencer ao mesmo Game").

Statement-level com transition table (REFERENCING NEW TABLE, FOR EACH
STATEMENT) — evita FOR EACH ROW num lote de até 500 linhas
(allocate_physical_cards_to_collection(), Query 5046). Duas triggers
separadas (INSERT e UPDATE) chamando a mesma função — nenhuma RPC
desta rodada faz UPDATE em collection_allocation, mas a trigger de
UPDATE cobre defensivamente qualquer caminho futuro que venha a
fazê-lo (mesmo raciocínio de 5041).

CORREÇÃO (COLLECTIONS-PHYSICAL-INCREMENT-02C-MODELING-REVISION-01,
item 2). A v1.0 usava JOIN direto até inventory a partir de
new_table/physical_card — uma Physical Card com inventory_id IS NULL
(Ownership Exit já ocorrida, C-72) simplesmente não casava esse JOIN e
desaparecia silenciosamente do resultado, escapando da validação em
vez de falhar. Reescrita em três checagens sequenciais, cada uma
set-based: a checagem 1 usa só physical_card (sem JOIN a inventory),
detectando inventory_id IS NULL diretamente — nada pode "desaparecer"
de um JOIN que não existe. As checagens 2 e 3 só executam depois que a
checagem 1 já garantiu, para o statement inteiro, que nenhuma linha do
lote tem inventory_id NULL — a partir daí, o JOIN a inventory é seguro
por construção: physical_card.inventory_id -> inventory(id) é FK
ON UPDATE/DELETE RESTRICT, então inventory_id NOT NULL implica
inventory referenciado sempre existente.

Cada checagem levanta uma mensagem distinta (sem Inventory / Owner
incompatível / Game incompatível) — diagnóstico mais claro que uma
mensagem genérica única.

SECURITY DEFINER necessário: lê physical_card/inventory/collection,
todas sob RLS restrita ao próprio owner. EXECUTE revogado de
PUBLIC/anon/authenticated — o disparo via CREATE TRIGGER não depende
de EXECUTE concedido a nenhuma role (mesma correção de segurança já
aplicada em 5032/5033, COLLECTIONS-PHYSICAL-INCREMENT-02B-
IMPLEMENTATION-01, Fase 6).

EXTENSÃO (Query 5063, COLLECTIONS-PHYSICAL-INCREMENT-02D-
IMPLEMENTATION-01). Extensão de regra sobre esta função (CREATE OR
REPLACE, mesmas triggers já criadas abaixo — nenhum CREATE TRIGGER
adicional), não reabertura do Incremento 2C (-MODELING-FINAL-01, item
6: "Pode evoluir funções/triggers do 02C quando o 02D for
implementado. Isso é extensão de regra, não reabertura do 02C").
Adiciona uma quarta checagem sequencial, depois de Inventory-nulo (1),
Owner (2) e Game (3): elegibilidade de Reference (LDM-17) — quando a
Collection é REFERENCE_BASED com Card Set Reference, a Card de cada
Physical Card alocada deve pertencer ao card_set_id referenciado. O
JOIN INNER até collection_reference/collection_card_set_reference já
filtra naturalmente as Collections OPEN_CURATION (sem nenhuma linha em
collection_reference, o JOIN simplesmente não casa nenhuma linha de
new_table para elas) — a condição "col.mode = 'REFERENCE_BASED'" no
WHERE é redundante com esse filtro, mantida por clareza explícita,
mesmo estilo das checagens 1-3. Fail-closed preservado: qualquer
physical_card_id fora do Card Set referenciado reprova o lote inteiro
(-MODELING-FINAL-01, item 6: "Lote misto: 1 inelegível -> FAIL
TOTAL"). Segunda camada de defesa em profundidade: a mesma checagem já
existe como pré-validação amigável em allocate_physical_cards_to_
collection() (Query 5064, extensão de 5046) — esta trigger garante que
a regra vale mesmo contra um INSERT direto em collection_allocation,
bypassando a RPC. Validado em execução real (5808, Casos R/S).

STATUS DESTA QUERY: CONFIRMADO EXECUTADO.
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
    --    Checagem direta em physical_card.inventory_id, sem JOIN a
    --    inventory — nada pode "escapar" de um JOIN que não existe.
    IF EXISTS (
        SELECT 1
        FROM new_table nt
        JOIN public.physical_card pc ON pc.id = nt.physical_card_id
        WHERE pc.inventory_id IS NULL
    ) THEN
        RAISE EXCEPTION 'uma ou mais physical_card_ids não possuem Inventory corrente e não podem ser alocadas';
    END IF;

    -- 2) A partir daqui, garantido que toda physical_card_id do lote
    --    tem inventory_id NOT NULL — JOIN a inventory seguro por
    --    construção (FK RESTRICT garante que o Inventory referenciado
    --    sempre existe).
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

CREATE TRIGGER trg_collection_allocation_validate_insert
    AFTER INSERT ON public.collection_allocation
    REFERENCING NEW TABLE AS new_table
    FOR EACH STATEMENT
    EXECUTE FUNCTION public.validate_collection_allocation_integrity();

CREATE TRIGGER trg_collection_allocation_validate_update
    AFTER UPDATE ON public.collection_allocation
    REFERENCING NEW TABLE AS new_table
    FOR EACH STATEMENT
    EXECUTE FUNCTION public.validate_collection_allocation_integrity();

REVOKE EXECUTE ON FUNCTION public.validate_collection_allocation_integrity() FROM PUBLIC, anon, authenticated;
