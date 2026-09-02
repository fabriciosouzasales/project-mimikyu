/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5055 - Create Collection Card Set Reference Game and Lock Guard Trigger (PROPOSTA)
Versão......: 1.1 (endurecida em COLLECTIONS-PHYSICAL-INCREMENT-02D-
               STAGING-REVISION-01, item 1 — arquivo nunca foi
               CANÔNICO, revisão do próprio staging)
Status......: PROPOSTA — NÃO EXECUTADA
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-02 (COLLECTIONS-PHYSICAL-INCREMENT-02D-
               MODELING-01/-REVISION-01/-FINAL-01/-STAGING-REVISION-01)

Descrição...:
Duas garantias estruturais independentes de qualquer RPC, no mesmo
trigger BEFORE INSERT OR UPDATE (mesmo padrão de
validate_collection_default_storage_owner(), Query 5033):

1. Game integrity (C-05/LDM-14): card_set_id deve pertencer ao mesmo
   game_id da Collection dona da Reference. card_set não tem game_id
   direto — só via card_set.expansion_id -> expansion.game_id (mesma
   cadeia de 2 saltos já usada em allocate_physical_cards_to_
   collection(), Query 5046) — por isso não existe FK composta
   possível aqui, exige trigger. Validada tanto em INSERT quanto em
   UPDATE (decisão fechada em -MODELING-FINAL-01, item 7: "Game
   validation obrigatória em INSERT E UPDATE").

2. Lock/lifecycle guard sobre card_set_id (LDM-07/C-11, decisão
   fechada em -MODELING-FINAL-01, item 7): trocar card_set_id só é
   aceito quando reference_locked_at IS NULL (referência ainda não
   consolidada por nenhuma Allocation efetiva) E lifecycle_status =
   'ACTIVE' (C-37 — ARCHIVED não aceita mudança de configuração).
   Depois do lock, ou com a Collection ARCHIVED, o UPDATE falha
   estruturalmente — não depende de nenhuma RPC se comportar bem.

Esta trigger NÃO cobre o caso "criar Reference com a Collection
ARCHIVED" (isso é responsabilidade da Query 5056, sobre
collection_reference, não sobre este subtipo) — mas cobre o INSERT
desta linha especificamente quando a Collection já está ARCHIVED no
mesmo instante (defesa em profundidade adicional, redundante com 5056
por desenho, não por acidente).

BLOCKER (-STAGING-REVISION-01, item 1): mesmo raciocínio da extensão
em 5056 — INSERT desta linha (o subtipo) também precisa falhar se
reference_locked_at já estiver definido no momento do INSERT, não
apenas o INSERT do supertipo (5056). Redundante por desenho: em fluxo
normal (Query 5065), as duas linhas nascem na mesma transação, então
se 5056 já bloqueou o INSERT do supertipo, esta linha nunca seria
alcançada — mas um bypass direto que pulasse o supertipo e tentasse
inserir só o subtipo (cenário artificial, mas nada nesta camada deve
depender de "a RPC nunca faria isso") precisa do mesmo guard aqui,
independente do outro lado.

STATUS DESTA QUERY: PROPOSTA — NÃO EXECUTADA.
================================================================
*/

CREATE FUNCTION public.validate_collection_card_set_reference_game_and_lock()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_collection_id       UUID;
    v_collection_game     UUID;
    v_reference_locked_at TIMESTAMPTZ;
    v_lifecycle_status    TEXT;
    v_card_set_game       UUID;
BEGIN
    SELECT cr.collection_id INTO v_collection_id
    FROM public.collection_reference cr
    WHERE cr.id = NEW.collection_reference_id;

    IF v_collection_id IS NULL THEN
        RAISE EXCEPTION 'collection_reference_id não corresponde a nenhum Collection Reference existente';
    END IF;

    SELECT col.game_id, col.reference_locked_at, col.lifecycle_status
    INTO v_collection_game, v_reference_locked_at, v_lifecycle_status
    FROM public.collection col
    WHERE col.id = v_collection_id;

    IF TG_OP = 'UPDATE' AND NEW.card_set_id IS DISTINCT FROM OLD.card_set_id THEN
        IF v_reference_locked_at IS NOT NULL THEN
            RAISE EXCEPTION 'card_set_id é imutável após reference_locked_at definido';
        END IF;

        IF v_lifecycle_status <> 'ACTIVE' THEN
            RAISE EXCEPTION 'collection is archived — reactivate before changing Card Set Reference';
        END IF;
    END IF;

    IF TG_OP = 'INSERT' THEN
        IF v_lifecycle_status <> 'ACTIVE' THEN
            RAISE EXCEPTION 'collection is archived — reactivate before creating Card Set Reference';
        END IF;

        IF v_reference_locked_at IS NOT NULL THEN
            RAISE EXCEPTION 'reference_locked_at already set — a Card Set Reference must be created before the first Allocation, not after';
        END IF;
    END IF;

    SELECT ex.game_id INTO v_card_set_game
    FROM public.card_set cs
    JOIN public.expansion ex ON ex.id = cs.expansion_id
    WHERE cs.id = NEW.card_set_id;

    IF v_card_set_game IS NULL THEN
        RAISE EXCEPTION 'card_set not found';
    END IF;

    IF v_card_set_game IS DISTINCT FROM v_collection_game THEN
        RAISE EXCEPTION 'card_set_id must belong to the same Game as the Collection';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_collection_card_set_reference_game_and_lock
    BEFORE INSERT OR UPDATE ON public.collection_card_set_reference
    FOR EACH ROW
    EXECUTE FUNCTION public.validate_collection_card_set_reference_game_and_lock();

REVOKE EXECUTE ON FUNCTION public.validate_collection_card_set_reference_game_and_lock() FROM PUBLIC, anon, authenticated;
