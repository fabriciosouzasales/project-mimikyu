/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5062 - Update Collection started_at/reference_locked_at Materializer Trigger (PROPOSTA)
Versão......: 1.1 (CREATE OR REPLACE sobre a função já CANÔNICA em
               database/schema/5045_create_collection_started_at_
               from_allocation_trigger.sql, hoje v1.0 — 5045
               permanece intocada; esta Query é uma correção
               posterior, mesmo padrão de 5044/5048)
Status......: PROPOSTA — NÃO EXECUTADA
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-02 (COLLECTIONS-PHYSICAL-INCREMENT-02D-
               MODELING-01/-REVISION-01/-FINAL-01)

Descrição...:
Estende materialize_collection_started_at() com o ramo de
reference_locked_at, preservando started_at sem nenhuma mudança de
comportamento (decisão fechada em -MODELING-FINAL-01, item 5:
"Preservar started_at").

Continua AFTER INSERT ... FOR EACH STATEMENT com transition table
(new_table) — mesmo padrão já em produção desde 2C, sem custo por
linha em lotes de até 500 (allocate_physical_cards_to_collection(),
Query 5046/5064).

reference_locked_at só é escrito quando: (a) mode = 'REFERENCE_BASED'
(OPEN_CURATION nunca recebe valor aqui — decisão fechada em
-MODELING-FINAL-01, item 6), e (b) ainda está NULL (nunca sobrescreve
um valor já consolidado — a trigger de 5061 reforça essa mesma regra
de forma independente, no UPDATE). Usa exatamente o mesmo
MIN(new_table.created_at) já calculado para started_at — nunca NOW()
arbitrário (decisão fechada em -MODELING-FINAL-01, item 6: "Não usar
NOW() arbitrário").

Deallocate parcial/total nunca toca nenhum dos dois campos — esta
trigger só existe em AFTER INSERT, nunca em DELETE (deallocate_
physical_cards_from_collection(), Query 5047, segue sem nenhuma
alteração nesta rodada).

STATUS DESTA QUERY: PROPOSTA — NÃO EXECUTADA.
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
