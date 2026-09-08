/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5124 - Create delete_collection_layout()
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO / LIVE / PROMOVIDO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-06 (staging em
               COLLECTIONS-BINDER-LAYOUT-FOUNDATION-STAGING-01)

Descrição...:
Apaga o Layout. RECUSA se houver qualquer Page — simetria literal com
delete_collection() (Query 5039), que recusa apagar Collection com
Allocations. Nenhum conteúdo desaparece por efeito colateral.

Estruturalmente, a FK page -> layout já é ON DELETE RESTRICT (Query
5108): mesmo um DELETE privilegiado direto seria bloqueado. Esta RPC
existe para dar erro de domínio legível, não para ser a única barreira.

Dependências:
- public.assert_collection_layout_mutable() (Query 5122).
- public.collection_layout_page (Query 5108).

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

CREATE OR REPLACE FUNCTION public.delete_collection_layout(
    p_layout_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_page_count INTEGER;
BEGIN
    PERFORM public.assert_collection_layout_mutable(p_layout_id);

    SELECT count(*) INTO v_page_count
      FROM public.collection_layout_page p
     WHERE p.layout_id = p_layout_id;

    IF v_page_count > 0 THEN
        RAISE EXCEPTION
            'layout has % page(s) — remove all pages before deleting the layout', v_page_count;
    END IF;

    DELETE FROM public.collection_layout
     WHERE id = p_layout_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.delete_collection_layout(uuid)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_collection_layout(uuid)
    TO authenticated;

COMMIT;
