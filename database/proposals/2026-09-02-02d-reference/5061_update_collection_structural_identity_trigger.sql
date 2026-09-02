/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5061 - Update Collection Structural Identity Trigger (PROPOSTA)
Versão......: 1.3 (CREATE OR REPLACE sobre a função já CANÔNICA em
               database/schema/5032_create_collection_structural_
               identity_trigger.sql, hoje v1.2 — 5032 permanece
               intocada; esta Query é uma correção posterior, mesmo
               padrão já usado por 5044/5048 no incremento 2C)
Status......: PROPOSTA — NÃO EXECUTADA
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-02 (COLLECTIONS-PHYSICAL-INCREMENT-02D-
               MODELING-01/-REVISION-01/-FINAL-01)

Descrição...:
Estende validate_collection_structural_identity() com duas novas
regras, sobre a mesma trigger BEFORE UPDATE ... FOR EACH ROW já
existente (nenhum CREATE TRIGGER adicional — mesmo padrão de fold-in-
place já usado em 5044):

1. mode é imutável após a criação (decisão fechada em COLLECTIONS-
   PHYSICAL-INCREMENT-02D-MODELING-FINAL-01, item 1: "No V1:
   Collection.mode é imutável após criação... Não suportar conversão").
   Mesma forma das regras já existentes para owner_user_id/game_id —
   sempre imutável, sem exceção condicional.

2. reference_locked_at, mesmo padrão já usado para started_at
   (extensão de 5044), com uma regra adicional que started_at não
   precisava: como uma Collection OPEN_CURATION também acumula
   collection_allocation normalmente, "bater com MIN(created_at)"
   sozinho não basta para distinguir "não deveria ter sido setado" —
   é necessário barrar explicitamente por mode. Três casos:
   (a) mode <> 'REFERENCE_BASED' e reference_locked_at sendo definido
       -> FAIL (só Collections REFERENCE_BASED têm esse campo
       aplicável — decisão fechada em -MODELING-FINAL-01, item 6:
       "OPEN_CURATION: reference_locked_at permanece NULL");
   (b) já definido, qualquer tentativa de mudar (inclusive voltar a
       NULL) -> FAIL;
   (c) ainda NULL, só pode ser definido se corresponder exatamente a
       MIN(collection_allocation.created_at) da Collection — mesma
       fonte de verdade e mesmo raciocínio de started_at, nunca NOW()
       arbitrário.

Para uma Collection REFERENCE_BASED, na prática, started_at e
reference_locked_at recebem o mesmo valor no mesmo evento (a primeira
Allocation é o mesmo instante para os dois marcos) — consequência
direta de a Reference já existir antes de qualquer Allocation ser
possível (decisão 1 da rodada -REVISION-01: "REFERENCE_BASED deve
nascer já com sua Reference, antes de qualquer Allocation"), não uma
coincidência a ser tratada como redundância a remover.

Esta é a mesma segunda camada de defesa em profundidade já usada para
started_at: o materializador (Query 5062, extensão de 5045) escreve o
valor correto por construção; esta trigger reconfirma contra a fonte
de verdade real toda vez que collection sofre UPDATE, inclusive contra
um eventual bug futuro no materializador.

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

    IF NEW.mode IS DISTINCT FROM OLD.mode THEN
        RAISE EXCEPTION 'mode é imutável';
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

    IF NEW.mode <> 'REFERENCE_BASED' AND NEW.reference_locked_at IS NOT NULL THEN
        RAISE EXCEPTION 'reference_locked_at só é aplicável a Collections REFERENCE_BASED';
    END IF;

    IF OLD.reference_locked_at IS NOT NULL AND NEW.reference_locked_at IS DISTINCT FROM OLD.reference_locked_at THEN
        RAISE EXCEPTION 'reference_locked_at é imutável após definido';
    END IF;

    IF OLD.reference_locked_at IS NULL AND NEW.reference_locked_at IS NOT NULL THEN
        SELECT MIN(ca.created_at) INTO v_min_allocated_at
        FROM public.collection_allocation ca
        WHERE ca.collection_id = NEW.id;

        IF v_min_allocated_at IS NULL THEN
            RAISE EXCEPTION 'reference_locked_at não pode ser definido sem nenhuma Collection Allocation existente';
        END IF;

        IF NEW.reference_locked_at IS DISTINCT FROM v_min_allocated_at THEN
            RAISE EXCEPTION 'reference_locked_at deve corresponder exatamente à primeira Collection Allocation (MIN(created_at))';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;
