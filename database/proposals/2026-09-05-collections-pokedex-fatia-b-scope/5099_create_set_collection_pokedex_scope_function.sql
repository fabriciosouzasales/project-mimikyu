/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5099 - Create set_collection_pokedex_scope Function
Versão......: 1.0 (PROPOSTA — STAGING, NÃO EXECUTADO)
Status......: PROPOSTA
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-05 (staging em COLLECTIONS-POKEDEX-FATIA-B-PHYSICAL-
               MODELING-AUDIT-01, renumerada em REVISION-01)

Descrição...:
Única via de troca do Scope declarado (scope_kind + conjunto de
Generations) de uma Collection Pokedex Reference — espelha
set_collection_card_set_reference() (5066) na estrutura de não-
enumeração e early checks, mas diverge deliberadamente em dois pontos,
ambos decorrentes de LDM-177:

1. NENHUM gate de reference_locked_at: card_set_id trava para sempre
   após a primeira Allocation (5066 rejeita a troca quando
   reference_locked_at IS NOT NULL); Scope de Pokédex é explicitamente
   mutável a qualquer momento enquanto ACTIVE, mesmo depois de
   Assignments existirem (LDM-177: "recalcula completion... não remove
   Assignments"). Esta RPC não checa reference_locked_at em nenhum
   momento — só lifecycle_status. Não afetada pela correção de
   completion_policy da REVISION-01 (esta função nunca toca essa
   coluna).

2. Semântica de troca é DELETE total + INSERT total do conjunto de
   Generations, não um diff KEEP/ADD/REMOVE como
   apply_master_set_scope_diff() (5079): collection_pokedex_scope_
   generation não carrega adopted_at/adopted_by_user_id (ver cabeçalho
   de 5091) — não há proveniência por linha a preservar, então
   substituir o conjunto inteiro é seguro e mais simples.

Sequência dentro da transação (importa para a Query 5095, eligibility
trigger imediata em collection_pokedex_scope_generation): (1) DELETE de
todas as linhas de Generation existentes para esta Reference — sempre
seguro, independente do scope_kind atual; (2) UPDATE de
collection_pokedex_reference.scope_kind; (3) se GENERATION_FILTERED,
INSERT do novo conjunto — neste ponto scope_kind já é
GENERATION_FILTERED na mesma transação, satisfazendo a Query 5095. A
Query 5096 (presence, diferida) confirma a invariante completa no
COMMIT.

SELECT ... FOR UPDATE na linha de collection, com owner_user_id =
auth.uid() já no WHERE — mesmo padrão de não-enumeração de 5046/5047/
5039/5066: Collection inexistente e Collection de outro Owner produzem
a mesma mensagem genérica.

Early checks amigáveis, todas antes de qualquer escrita: mode deve ser
REFERENCE_BASED; reference_kind da Reference deve ser POKEDEX (não faz
sentido chamar esta RPC numa Collection CARD_SET); lifecycle deve ser
ACTIVE (C-37/LDM-185). A garantia estrutural de fundo para o mode/kind
mistura RPC errada é a FK de collection_pokedex_reference
(collection_reference_id) — se a Reference não é POKEDEX, esta RPC
simplesmente não encontra v_reference_id.

EXECUTE revogado de PUBLIC/anon; concedido apenas a authenticated.

STATUS DESTA QUERY: PROPOSTA — NÃO EXECUTADO.
================================================================
*/

BEGIN;

CREATE FUNCTION public.set_collection_pokedex_scope(
    p_collection_id  UUID,
    p_scope_kind     TEXT,
    p_generation_ids UUID[] DEFAULT NULL
)
RETURNS TABLE (
    collection_id  UUID,
    scope_kind      TEXT,
    updated_at       TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_mode              TEXT;
    v_lifecycle_status  TEXT;
    v_reference_id      UUID;
    v_reference_kind    TEXT;
    v_generation_ids    UUID[];
    v_updated_at        TIMESTAMPTZ;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'authentication required';
    END IF;

    IF p_scope_kind NOT IN ('FULL_REFERENCE', 'GENERATION_FILTERED') THEN
        RAISE EXCEPTION 'p_scope_kind deve ser FULL_REFERENCE ou GENERATION_FILTERED';
    END IF;

    SELECT col.mode, col.lifecycle_status
    INTO v_mode, v_lifecycle_status
    FROM public.collection col
    WHERE col.id = p_collection_id
      AND col.owner_user_id = auth.uid()
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'collection not found or not owned by caller';
    END IF;

    IF v_mode <> 'REFERENCE_BASED' THEN
        RAISE EXCEPTION 'collection is not REFERENCE_BASED';
    END IF;

    IF v_lifecycle_status <> 'ACTIVE' THEN
        RAISE EXCEPTION 'collection is archived — reactivate before changing the Pokedex Scope';
    END IF;

    SELECT cr.id, cr.reference_kind INTO v_reference_id, v_reference_kind
    FROM public.collection_reference cr
    WHERE cr.collection_id = p_collection_id;

    IF v_reference_id IS NULL THEN
        RAISE EXCEPTION 'collection has no Collection Reference';
    END IF;

    IF v_reference_kind <> 'POKEDEX' THEN
        RAISE EXCEPTION 'collection Reference is not of kind POKEDEX';
    END IF;

    IF p_scope_kind = 'GENERATION_FILTERED' THEN
        IF p_generation_ids IS NULL OR array_length(p_generation_ids, 1) IS NULL THEN
            RAISE EXCEPTION 'p_generation_ids é obrigatório e não pode ser vazio quando p_scope_kind = GENERATION_FILTERED';
        END IF;

        SELECT array_agg(DISTINCT gid) INTO v_generation_ids
        FROM unnest(p_generation_ids) AS gid;

        IF EXISTS (
            SELECT 1 FROM unnest(v_generation_ids) AS gid
            WHERE NOT EXISTS (SELECT 1 FROM public.pokemon_generation pg WHERE pg.id = gid)
        ) THEN
            RAISE EXCEPTION 'p_generation_ids contém um generation_id inexistente';
        END IF;
    ELSE
        IF p_generation_ids IS NOT NULL AND array_length(p_generation_ids, 1) IS NOT NULL THEN
            RAISE EXCEPTION 'p_generation_ids deve ser NULL/vazio quando p_scope_kind = FULL_REFERENCE';
        END IF;
        v_generation_ids := NULL;
    END IF;

    DELETE FROM public.collection_pokedex_scope_generation
    WHERE collection_pokedex_scope_generation.collection_reference_id = v_reference_id;

    UPDATE public.collection_pokedex_reference
    SET scope_kind = p_scope_kind,
        updated_at = NOW()
    WHERE collection_pokedex_reference.collection_reference_id = v_reference_id
    RETURNING collection_pokedex_reference.updated_at INTO v_updated_at;

    IF p_scope_kind = 'GENERATION_FILTERED' THEN
        INSERT INTO public.collection_pokedex_scope_generation (collection_reference_id, generation_id)
        SELECT v_reference_id, gid FROM unnest(v_generation_ids) AS gid;
    END IF;

    RETURN QUERY
    SELECT p_collection_id, p_scope_kind, v_updated_at;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.set_collection_pokedex_scope(uuid, text, uuid[])
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_collection_pokedex_scope(uuid, text, uuid[])
    TO authenticated;

COMMIT;
