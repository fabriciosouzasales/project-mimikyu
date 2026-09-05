/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5090 - Create Collection Pokedex Reference Game and Lock Guard Trigger
Versão......: 1.0 (PROPOSTA — STAGING, NÃO EXECUTADO)
Status......: PROPOSTA
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-05 (staging em COLLECTIONS-POKEDEX-FATIA-B-PHYSICAL-
               MODELING-AUDIT-01, renumerada em REVISION-01)

Descrição...:
Espelha o papel da Query 5055 (Collection Card Set Reference Game and
Lock Guard Trigger) para o subtipo POKEDEX, com duas diferenças
estruturais deliberadas, ambas decorrentes de LDM-175/LDM-177:

1. GAME GATE: card_set_id herda Game transitivamente via
   card_set.expansion_id -> expansion.game_id (5055 usa essa cadeia).
   pokedex NÃO tem game_id — é entidade global do universo Pokémon
   (LDM-175, decisão congelada em COLLECTIONS-PHYSICAL-INCREMENT-02G).
   Sem nenhum vínculo, nada impediria uma Collection do Game Lorcana de
   declarar uma Pokédex Reference. Esta trigger fecha essa lacuna
   comparando collection.game_id contra o Game de code = 'POKEMON'
   (public.game.code, valor confirmado ao vivo em 2026-09-05:
   exatamente uma linha com code = 'POKEMON', a outra é 'LORCANA').

2. LOCK GATE ASSIMÉTRICO (diferente de 5055): pokedex_id segue a mesma
   disciplina de card_set_id (imutável quando reference_locked_at IS
   NOT NULL); scope_kind explicitamente NÃO é gated por
   reference_locked_at — apenas por lifecycle_status = 'ACTIVE' (LDM-177:
   "Scope mutation... recalcula completion... não remove Assignments";
   LDM-185: Scope só se torna imutável quando a Collection está
   ARCHIVED).

Mesma disciplina de defesa em profundidade de 5055/5056: valida tanto
INSERT (bypass direto do subtipo, pulando o supertipo) quanto UPDATE.

STATUS DESTA QUERY: PROPOSTA — NÃO EXECUTADO.
================================================================
*/

BEGIN;

CREATE FUNCTION public.validate_collection_pokedex_reference_game_and_lock()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_collection_id       UUID;
    v_collection_game_id  UUID;
    v_game_code           TEXT;
    v_reference_locked_at TIMESTAMPTZ;
    v_lifecycle_status    TEXT;
BEGIN
    SELECT cr.collection_id INTO v_collection_id
    FROM public.collection_reference cr
    WHERE cr.id = NEW.collection_reference_id;

    IF v_collection_id IS NULL THEN
        RAISE EXCEPTION 'collection_reference_id não corresponde a nenhum Collection Reference existente';
    END IF;

    SELECT col.game_id, col.reference_locked_at, col.lifecycle_status
    INTO v_collection_game_id, v_reference_locked_at, v_lifecycle_status
    FROM public.collection col
    WHERE col.id = v_collection_id;

    -- Gate de lifecycle: nenhuma escrita neste subtipo enquanto ARCHIVED
    -- (C-37/LDM-185) — vale tanto para pokedex_id quanto para scope_kind.
    IF v_lifecycle_status <> 'ACTIVE' THEN
        RAISE EXCEPTION 'collection is archived — reactivate before changing Pokedex Reference';
    END IF;

    IF TG_OP = 'INSERT' THEN
        IF v_reference_locked_at IS NOT NULL THEN
            RAISE EXCEPTION 'reference_locked_at already set — a Pokedex Reference must be created before the first Allocation, not after';
        END IF;
    END IF;

    IF TG_OP = 'UPDATE' AND NEW.pokedex_id IS DISTINCT FROM OLD.pokedex_id THEN
        IF v_reference_locked_at IS NOT NULL THEN
            RAISE EXCEPTION 'pokedex_id é imutável após reference_locked_at definido';
        END IF;
    END IF;

    -- scope_kind muda livremente (mesmo já com lock), desde que ACTIVE —
    -- já garantido pelo gate de lifecycle acima. Nenhuma checagem
    -- adicional de reference_locked_at para scope_kind (decisão LDM-177).

    SELECT g.code INTO v_game_code
    FROM public.game g
    WHERE g.id = v_collection_game_id;

    IF v_game_code IS DISTINCT FROM 'POKEMON' THEN
        RAISE EXCEPTION 'a Pokedex Reference só é permitida para Collections do Game Pokémon TCG (game.code = POKEMON)';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_collection_pokedex_reference_game_and_lock
    BEFORE INSERT OR UPDATE ON public.collection_pokedex_reference
    FOR EACH ROW
    EXECUTE FUNCTION public.validate_collection_pokedex_reference_game_and_lock();

REVOKE EXECUTE ON FUNCTION public.validate_collection_pokedex_reference_game_and_lock()
    FROM PUBLIC, anon, authenticated;

COMMIT;
