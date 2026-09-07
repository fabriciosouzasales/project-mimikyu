/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5118 - Create Slot Lock Enforcement Trigger
Versão......: 1.0
Status......: PROPOSTA — STAGING, NÃO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-06 (staging em
               COLLECTIONS-BINDER-LAYOUT-FOUNDATION-STAGING-01)

Descrição...:
DP-08, enforcement estrutural. C-43 fecha que Lock bloqueia as
operações que alterariam a ocupação da posição protegida. As RPCs
fazem precheck para produzir erro amigável, MAS Lock não pode
depender apenas de RPC — este trigger é a garantia de última linha.

MATRIZ DE ENFORCEMENT sobre collection_layout_slot_assignment:

  INSERT          -> destino locked                    => REJEITAR
  UPDATE (MOVE)   -> origem locked OU destino locked    => REJEITAR
  DELETE (REMOVE) -> origem locked                      => REJEITAR

Isso cobre, de uma vez: Move, Swap (dois UPDATEs), Replace (DELETE +
INSERT), Remove, Drop/mover para Bandeja, e todas as versões Bulk —
porque todas elas são, fisicamente, alguma combinação dessas três
operações. Nenhuma escapa.

O QUE LOCK **NÃO** BLOQUEIA (C-43, por omissão deliberada):
- Expected Content: definir/limpar continua permitido em Slot locked.
  C-43 lista as operações bloqueadas e Expected Content não está lá.
- O próprio set/unset do Lock (Query 5130), que opera em
  collection_layout_slot, não nesta tabela.
- Criar/remover Page ou Layout — bloqueados por dependência (RESTRICT),
  não por Lock.

EXCEÇÃO DELIBERADA E DOCUMENTADA — CASCADE DE DESALOCAÇÃO:
quando a Physical Card é DESALOCADA da Collection
(deallocate_physical_cards_from_collection(), Query 5047), o
ON DELETE CASCADE de 5115 apaga a Assignment. Esse DELETE **não** deve
ser bloqueado por Lock: desalocação é operação de COLLECTION (Fatia
02C), não de Layout, e C-43 NÃO a lista entre as operações protegidas.
Bloqueá-la faria o Lock de um Slot impedir uma operação de outro
agregado — efeito colateral que nenhuma decisão autoriza.

Detecção: em um DELETE cascateado, a linha-pai de collection_allocation
já foi removida quando o trigger da filha dispara. Portanto
`NOT EXISTS (SELECT 1 FROM collection_allocation WHERE id = OLD...)`
distingue com precisão "cascade da desalocação" de "REMOVE pelo
Layout". O harness 5818 valida ESTE COMPORTAMENTO EXPLICITAMENTE
(caso LOCK-CASCADE) — se a premissa não se confirmar na execução real,
é um achado a reportar, não a contornar.

Dependências:
- public.collection_layout_slot_assignment (Query 5115).
- public.collection_layout_slot (Query 5110).
- public.collection_allocation (Query 5040).

STATUS DESTA QUERY: PROPOSTA — NÃO EXECUTADO.
================================================================
*/

BEGIN;

CREATE OR REPLACE FUNCTION public.enforce_collection_layout_slot_lock()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_locked BOOLEAN;
BEGIN
    -- ---------------------------------------------------------------
    -- DELETE: origem locked bloqueia, EXCETO cascade de desalocação.
    -- ---------------------------------------------------------------
    IF TG_OP = 'DELETE' THEN

        IF NOT EXISTS (
            SELECT 1
            FROM public.collection_allocation ca
            WHERE ca.id = OLD.collection_allocation_id
        ) THEN
            -- A Allocation já não existe: este DELETE é o CASCADE da
            -- desalocação da Physical Card da Collection. Lock não se
            -- aplica (C-43 não lista desalocação).
            RETURN OLD;
        END IF;

        SELECT s.locked INTO v_locked
          FROM public.collection_layout_slot s
         WHERE s.id = OLD.slot_id;

        IF COALESCE(v_locked, FALSE) THEN
            RAISE EXCEPTION
                'Slot bloqueado (locked) — Remove/Bandeja não permitido enquanto o Lock estiver ativo';
        END IF;

        RETURN OLD;
    END IF;

    -- ---------------------------------------------------------------
    -- UPDATE (MOVE/SWAP): origem OU destino locked bloqueia.
    -- ---------------------------------------------------------------
    IF TG_OP = 'UPDATE' THEN

        IF NEW.slot_id IS DISTINCT FROM OLD.slot_id THEN

            SELECT s.locked INTO v_locked
              FROM public.collection_layout_slot s
             WHERE s.id = OLD.slot_id;

            IF COALESCE(v_locked, FALSE) THEN
                RAISE EXCEPTION
                    'Slot de origem bloqueado (locked) — Move/Swap não permitido';
            END IF;

            SELECT s.locked INTO v_locked
              FROM public.collection_layout_slot s
             WHERE s.id = NEW.slot_id;

            IF COALESCE(v_locked, FALSE) THEN
                RAISE EXCEPTION
                    'Slot de destino bloqueado (locked) — Move/Swap não permitido';
            END IF;

        END IF;

        RETURN NEW;
    END IF;

    -- ---------------------------------------------------------------
    -- INSERT (ADD/REPLACE): destino locked bloqueia.
    -- ---------------------------------------------------------------
    SELECT s.locked INTO v_locked
      FROM public.collection_layout_slot s
     WHERE s.id = NEW.slot_id;

    IF COALESCE(v_locked, FALSE) THEN
        RAISE EXCEPTION
            'Slot bloqueado (locked) — Add/Replace não permitido enquanto o Lock estiver ativo';
    END IF;

    RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.enforce_collection_layout_slot_lock()
    FROM PUBLIC, anon, authenticated;

CREATE TRIGGER trg_collection_layout_slot_assignment_lock
    BEFORE INSERT OR UPDATE OR DELETE
    ON public.collection_layout_slot_assignment
    FOR EACH ROW
    EXECUTE FUNCTION public.enforce_collection_layout_slot_lock();

COMMIT;
