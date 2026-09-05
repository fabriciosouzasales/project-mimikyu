/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5092 - Extensão do check_collection_reference_subtype_consistency() (dobra em 5057)
Versão......: 1.1 (PROPOSTA — STAGING, NÃO EXECUTADO)
Status......: PROPOSTA
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-05 (staging em COLLECTIONS-POKEDEX-FATIA-B-PHYSICAL-
               MODELING-AUDIT-01, renumerada em REVISION-01)

Descrição...:
Preenche exatamente o ELSIF que o cabeçalho e o corpo de 5057 já
deixavam reservado: "-- ELSIF v_kind = 'POKEDEX' THEN ... (futuro,
quando o subtipo existir)". CREATE OR REPLACE FUNCTION apenas — mesmo
padrão de correção-em-linha já usado repetidamente no domínio (5032
v1.2/v1.3, 5042 v1.1/v1.2, 5045 v1.1, 5046 v1.2). Nenhum trigger novo
aqui: os dois triggers que já chamam esta função (trg_collection_
reference_consistency, 5057; e o novo trg_collection_pokedex_reference_
consistency, Query 5093) passam a cobrir POKEDEX automaticamente assim
que esta função for substituída — nenhuma alteração adicional nos
triggers em si.

Garante, no COMMIT (a função continua sendo chamada só por CONSTRAINT
TRIGGER DEFERRABLE INITIALLY DEFERRED), que todo Collection Reference
de kind POKEDEX possui exatamente 1 linha em
collection_pokedex_reference — espelho exato da checagem já existente
para CARD_SET/collection_card_set_reference.

Conteúdo incorporado ao arquivo canônico
database/schema/5057_create_collection_reference_consistency_trigger.sql
(v1.1) quando promovido — não um arquivo 5092 isolado no schema final,
mesmo padrão de dobra já usado no domínio.

STATUS DESTA QUERY: PROPOSTA — NÃO EXECUTADO.
================================================================
*/

BEGIN;

CREATE OR REPLACE FUNCTION public.check_collection_reference_subtype_consistency(p_collection_reference_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_kind           TEXT;
    v_subtype_count  INT;
BEGIN
    SELECT cr.reference_kind INTO v_kind
    FROM public.collection_reference cr
    WHERE cr.id = p_collection_reference_id;

    IF NOT FOUND THEN
        -- O próprio Collection Reference já não existe (DELETE CASCADE
        -- da Collection, ou removido nesta mesma transação) — nada a
        -- checar.
        RETURN;
    END IF;

    IF v_kind = 'CARD_SET' THEN
        SELECT count(*) INTO v_subtype_count
        FROM public.collection_card_set_reference ccsr
        WHERE ccsr.collection_reference_id = p_collection_reference_id;

        IF v_subtype_count <> 1 THEN
            RAISE EXCEPTION 'Collection Reference of kind CARD_SET must have exactly one Collection Card Set Reference (found %)', v_subtype_count;
        END IF;
    ELSIF v_kind = 'POKEDEX' THEN
        SELECT count(*) INTO v_subtype_count
        FROM public.collection_pokedex_reference cpr
        WHERE cpr.collection_reference_id = p_collection_reference_id;

        IF v_subtype_count <> 1 THEN
            RAISE EXCEPTION 'Collection Reference of kind POKEDEX must have exactly one Collection Pokedex Reference (found %)', v_subtype_count;
        END IF;
    END IF;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.check_collection_reference_subtype_consistency(uuid)
    FROM PUBLIC, anon, authenticated;

COMMIT;
