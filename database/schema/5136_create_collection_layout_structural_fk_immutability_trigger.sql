/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5136 - Create Collection Layout Structural FK Immutability Triggers
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO / LIVE / PROMOVIDO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-06 (criado em
               COLLECTIONS-BINDER-LAYOUT-FOUNDATION-CONSOLIDATED-CORRECTION-01)

Descrição...:
§7 FKs ESTRUTURAIS PAI -> FILHO IMUTÁVEIS.

BYPASS ESTRUTURAL QUE ESTE ARQUIVO FECHA
----------------------------------------
O trigger 5117 valida que a Physical Card da Assignment está alocada à
MESMA Collection dona do Layout. Mas essa validação acontece no momento
do INSERT/UPDATE da Assignment. Depois disso, um UPDATE privilegiado
sobre a CADEIA DE PAIS mudava a Collection efetiva do Slot sem
disparar 5117 nenhuma vez:

    collection_layout.collection_id       -> troca a Collection do Layout
    collection_layout_page.layout_id      -> move a Page para outro Layout
    collection_layout_slot.page_id        -> move o Slot para outra Page

Qualquer um dos três deixaria Assignments válidas apontando para uma
Collection à qual as Physical Cards NÃO estão alocadas — exatamente a
invariante que 5117 existe para proteger.

DECISÃO V1
----------
Esses três vínculos são IMUTÁVEIS. Não existe operação de produto que
os altere: um Layout pertence a uma Collection para sempre (DP-01), uma
Page pertence a um Layout para sempre, um Slot pertence a uma Page para
sempre. Reparentar é sempre delete + create.

O QUE **NÃO** FICA IMUTÁVEL (deliberadamente)
---------------------------------------------
- `collection_layout_page.page_number` — muda em reorder/remove.
- `collection_layout.grid_rows` / `grid_columns` — mutáveis dentro da
  regra de DP-03 (zero Pages), agora via RPC 5137; a defesa estrutural
  continua sendo o trigger 5107.
- `collection_layout_slot.row_index` / `column_index` — esta decisão
  não os congela; o enforcement deles é 5112 (bounds) + a UNIQUE.
- `collection_layout_slot.locked` — é justamente o atributo mutável.
- `collection_layout_slot_assignment.slot_id` — MOVE e SWAP dependem
  dele. O que é imutável na Assignment é `collection_allocation_id`
  (ver 5117).
- `collection_layout_region.page_id` — também imutável, mas o
  enforcement fica na defesa de Region (5121), junto do lock da Page.

IMPLEMENTAÇÃO
-------------
UMA função genérica, três triggers. A coluna protegida chega por
TG_ARGV[0] e a comparação usa `to_jsonb(OLD/NEW) ->> coluna`, de modo
que não há três cópias da mesma lógica para divergirem no futuro.

Os triggers são `BEFORE UPDATE OF <coluna>`: só são avaliados quando a
coluna aparece no SET, e ainda assim a mudança real é confirmada por
IS DISTINCT FROM — um UPDATE que apenas repete o mesmo valor passa.

Dependências:
- public.collection_layout (Query 5105).
- public.collection_layout_page (Query 5108).
- public.collection_layout_slot (Query 5110).

STATUS DESTA QUERY: CONFIRMADO EXECUTADO / LIVE / PROMOVIDO.

Aplicada ao banco real em 2026-09-07, na rodada
`COLLECTIONS-BINDER-LAYOUT-FOUNDATION-IMPLEMENTATION-01`. Validada por
`5818` v7.2 (196/196 runtime, FAIL 0) e por `5819` v3.0 (22/22 HEALTHY,
nenhum indice novo criado). Ledger e evidencia completa em
`database/proposals/2026-09-06-binder-layout-foundation/README.md`.

Promovida para `database/schema/` em `SCHEMA-PROMOTION-RECONCILIATION-01`
(2026-09-08). A copia historica permanece em
`database/proposals/2026-09-06-binder-layout-foundation/`, junto com os
harnesses `5818`/`5819`, o roteiro `CONCURRENCY-PROOF-C04-R18.sql` e o
`README.md` da rodada — esses quatro NAO sao promovidos, por convencao.
A promocao alterou apenas cabecalho/rodape: o corpo executavel
(`BEGIN;` .. `COMMIT;`) permanece byte-identico ao da copia em proposals.
================================================================
*/

BEGIN;

CREATE OR REPLACE FUNCTION public.enforce_collection_layout_structural_fk_immutability()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_column TEXT := TG_ARGV[0];
    v_old    TEXT;
    v_new    TEXT;
BEGIN
    v_old := to_jsonb(OLD) ->> v_column;
    v_new := to_jsonb(NEW) ->> v_column;

    IF v_new IS DISTINCT FROM v_old THEN
        RAISE EXCEPTION
            '%.% é IMUTÁVEL na V1 — reparentar objetos do Layout mudaria a Collection efetiva do Slot sem revalidar as Slot Assignments; a operação suportada é remover e recriar',
            TG_TABLE_NAME, v_column;
    END IF;

    RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.enforce_collection_layout_structural_fk_immutability()
    FROM PUBLIC, anon, authenticated;

CREATE TRIGGER trg_collection_layout_collection_id_immutable
    BEFORE UPDATE OF collection_id ON public.collection_layout
    FOR EACH ROW
    EXECUTE FUNCTION public.enforce_collection_layout_structural_fk_immutability('collection_id');

CREATE TRIGGER trg_collection_layout_page_layout_id_immutable
    BEFORE UPDATE OF layout_id ON public.collection_layout_page
    FOR EACH ROW
    EXECUTE FUNCTION public.enforce_collection_layout_structural_fk_immutability('layout_id');

CREATE TRIGGER trg_collection_layout_slot_page_id_immutable
    BEFORE UPDATE OF page_id ON public.collection_layout_slot
    FOR EACH ROW
    EXECUTE FUNCTION public.enforce_collection_layout_structural_fk_immutability('page_id');

COMMIT;

/*
Como validar:

SELECT c.relname AS tabela, t.tgname, pg_get_triggerdef(t.oid)
FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
WHERE NOT t.tgisinternal
  AND t.tgname IN ('trg_collection_layout_collection_id_immutable',
                   'trg_collection_layout_page_layout_id_immutable',
                   'trg_collection_layout_slot_page_id_immutable')
ORDER BY c.relname;

Esperado: 3 linhas, uma por tabela, todas BEFORE UPDATE OF ... FOR EACH ROW.

Prova comportamental (5818, grupo F): UPDATE privilegiado de cada uma
das três colunas deve FALHAR.
*/
