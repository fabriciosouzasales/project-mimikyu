/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5044 - Update Collection Structural Identity Trigger (PROPOSTA)
Versão......: 1.2 (CREATE OR REPLACE sobre a função criada em 5032,
               já CONFIRMADO EXECUTADO/CANÔNICA em database/schema —
               5032 permanece intocada; esta Query é uma correção
               posterior, mesmo padrão já usado por
               5035_fix_ambiguous_id_reference/
               5036_fix_ambiguous_id_reference no incremento anterior)
Status......: PROPOSTA — NÃO EXECUTADA
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-01 (COLLECTIONS-PHYSICAL-INCREMENT-02C-MODELING-
               FINAL-01, item 2)

Descrição...:
Estende validate_collection_structural_identity() (Query 5032) com a
proteção de started_at (Query 5043), em vez de criar uma trigger nova
e isolada — a função já é BEFORE UPDATE ... FOR EACH ROW genérica em
collection (dispara em qualquer UPDATE, não só nos campos que já
protege), então basta adicionar a cláusula; nenhum CREATE TRIGGER
adicional.

Duas regras, semanticamente distintas de owner_user_id/game_id (que
são sempre imutáveis desde a criação) porque started_at é mutável
exatamente uma vez:

1. Já definido, tentativa de mudar -> FAIL. OLD.started_at IS NOT NULL
   e NEW.started_at diferente de OLD.started_at é sempre rejeitado —
   cobre tanto "mudar para outro valor" quanto "voltar a NULL"
   (deallocate total nunca reseta started_at, ver 5047).

2. Ainda NULL, tentativa de definir -> só é válida se: (a) existir
   pelo menos uma Collection Allocation real para esta Collection, e
   (b) o valor proposto corresponder exatamente a
   MIN(collection_allocation.created_at) para ela. Isso impede
   preencher started_at arbitrariamente numa Collection sem nenhuma
   Allocation, e impede qualquer valor que não seja o fato real —
   nenhuma RPC pode escrever NOW() ou qualquer timestamp inventado
   aqui, só o materializador (5045) escreve, e mesmo esse escritor é
   reauditado por esta trigger no momento do UPDATE.

Esta é a segunda camada de defesa em profundidade da mesma garantia:
a Query 5045 materializa o valor correto por construção (lê
new_table, ainda mais barato); esta trigger reconfirma o valor contra
a fonte de verdade real (collection_allocation) toda vez que
collection sofre UPDATE — inclusive contra um eventual bug futuro no
materializador.

STATUS DESTA QUERY: PROPOSTA — NÃO EXECUTADA.
================================================================
*/

CREATE OR REPLACE FUNCTION public.validate_collection_structural_identity()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_min_allocated_at TIMESTAMPTZ;
BEGIN
    IF NEW.owner_user_id IS DISTINCT FROM OLD.owner_user_id THEN
        RAISE EXCEPTION 'owner_user_id é imutável';
    END IF;

    IF NEW.game_id IS DISTINCT FROM OLD.game_id THEN
        RAISE EXCEPTION 'game_id é imutável';
    END IF;

    IF OLD.started_at IS NOT NULL AND NEW.started_at IS DISTINCT FROM OLD.started_at THEN
        RAISE EXCEPTION 'started_at é imutável após definido';
    END IF;

    IF OLD.started_at IS NULL AND NEW.started_at IS NOT NULL THEN
        SELECT MIN(ca.created_at) INTO v_min_allocated_at
        FROM public.collection_allocation ca
        WHERE ca.collection_id = NEW.id;

        IF v_min_allocated_at IS NULL THEN
            RAISE EXCEPTION 'started_at não pode ser definido sem nenhuma Collection Allocation existente';
        END IF;

        IF NEW.started_at IS DISTINCT FROM v_min_allocated_at THEN
            RAISE EXCEPTION 'started_at deve corresponder exatamente à primeira Collection Allocation (MIN(created_at))';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;
