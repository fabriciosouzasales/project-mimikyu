/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5045 - Create Collection started_at/reference_locked_at From First Allocation Trigger
Versão......: 1.1 (estendida em 2026-09-02, aplicada em 2026-09-02, via
               Query 5062, COLLECTIONS-PHYSICAL-INCREMENT-02D-
               IMPLEMENTATION-01)
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-01 (aplicado em 2026-09-02,
               COLLECTIONS-PHYSICAL-INCREMENT-02C-IMPLEMENTATION-01;
               estendida em 2026-09-02, via Query 5062, COLLECTIONS-
               PHYSICAL-INCREMENT-02D-IMPLEMENTATION-01)

Descrição...:
Materializa collection.started_at a partir do fato físico real — a
primeira Collection Allocation efetivamente persistida — em vez de
qualquer RPC escrever NOW() diretamente. Statement-level (AFTER
INSERT ... REFERENCING NEW TABLE ... FOR EACH STATEMENT), mesmo
padrão de transition table já usado em 5042.

started_at = MIN(collection_allocation.created_at) por Collection,
calculado sobre new_table (o lote recém-inserido), aplicado só quando
collection.started_at ainda é NULL. Sob a invariante mantida por esta
própria trigger e por 5044/5032 (started_at só é NULL enquanto a
Collection não tem nenhuma Collection Allocation, e nunca volta a NULL
depois de definido — 5047 nunca reseta), MIN sobre new_table é
equivalente a MIN sobre toda collection_allocation da Collection nesse
momento: se started_at está NULL, este é necessariamente o primeiro
lote de Allocations dela.

Atomicidade: esta trigger executa dentro da mesma transação do INSERT
que a disparou (AFTER STATEMENT — mesma transação de
allocate_physical_cards_to_collection(), Query 5046). Se
trg_collection_allocation_validate_insert (Query 5042) já rodou e
aprovou o lote, ou se ainda vai rodar e reprovar, o resultado final é
sempre consistente: qualquer RAISE EXCEPTION em qualquer trigger AFTER
do mesmo statement desfaz o INSERT inteiro e todos os efeitos de
outras triggers AFTER já executadas na mesma transação — não existe
ordem de disparo entre 5042 e esta trigger que produza estado parcial
(a garantia é da transação, não da ordem). O UPDATE que esta trigger
faz em collection dispara, por sua vez, a trigger BEFORE UPDATE de
5044/5032 (validate_collection_structural_identity()), que reconfirma
independentemente o valor antes de aceitar a escrita.

SECURITY DEFINER necessário: escreve em collection, sob RLS restrita
ao próprio owner.

EXTENSÃO (Query 5062, COLLECTIONS-PHYSICAL-INCREMENT-02D-
IMPLEMENTATION-01). Estende esta função (CREATE OR REPLACE, mesma
trigger já criada abaixo — nenhum CREATE TRIGGER adicional) com o ramo
de reference_locked_at, preservando started_at sem nenhuma mudança de
comportamento (-MODELING-FINAL-01, item 5: "Preservar started_at").
reference_locked_at só é escrito quando: (a) mode = 'REFERENCE_BASED'
(OPEN_CURATION nunca recebe valor aqui — -MODELING-FINAL-01, item 6),
e (b) ainda está NULL (nunca sobrescreve um valor já consolidado — a
trigger de 5061/5032 reforça essa mesma regra de forma independente,
no UPDATE). Usa exatamente o mesmo MIN(new_table.created_at) já
calculado para started_at — nunca NOW() arbitrário. Deallocate
parcial/total nunca toca nenhum dos dois campos — esta trigger só
existe em AFTER INSERT, nunca em DELETE. Validado em execução real
(5808, Caso N: reference_locked_at materializado corretamente).

STATUS DESTA QUERY: CONFIRMADO EXECUTADO.
================================================================
*/

CREATE OR REPLACE FUNCTION public.materialize_collection_started_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    UPDATE public.collection col SET
        started_at = COALESCE(col.started_at, sub.first_allocated_at),
        reference_locked_at = CASE
            WHEN col.mode = 'REFERENCE_BASED' AND col.reference_locked_at IS NULL
            THEN sub.first_allocated_at
            ELSE col.reference_locked_at
        END
    FROM (
        SELECT collection_id, MIN(created_at) AS first_allocated_at
        FROM new_table
        GROUP BY collection_id
    ) sub
    WHERE col.id = sub.collection_id
      AND (
          col.started_at IS NULL
          OR (col.mode = 'REFERENCE_BASED' AND col.reference_locked_at IS NULL)
      );

    RETURN NULL;
END;
$$;

CREATE TRIGGER trg_collection_allocation_started_at_insert
    AFTER INSERT ON public.collection_allocation
    REFERENCING NEW TABLE AS new_table
    FOR EACH STATEMENT
    EXECUTE FUNCTION public.materialize_collection_started_at();

REVOKE EXECUTE ON FUNCTION public.materialize_collection_started_at() FROM PUBLIC, anon, authenticated;
