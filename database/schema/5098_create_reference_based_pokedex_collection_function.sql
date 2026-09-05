/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5098 - Create create_reference_based_pokedex_collection Function
Versão......: 1.1
Status......: CONFIRMADO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-05 (staging em COLLECTIONS-POKEDEX-FATIA-B-PHYSICAL-
               MODELING-AUDIT-01; corrigida em COLLECTIONS-POKEDEX-FATIA-B-
               PHYSICAL-MODELING-REVISION-01 — completion_policy passa de
               'NONE' para 'REFERENCE_POSITION'; aplicado em 2026-09-05 via
               COLLECTIONS-POKEDEX-FATIA-B-IMPLEMENTATION-01)

Descrição...:
Espelha create_reference_based_card_set_collection() (5065) para o
subtipo POKEDEX — única via de criação de uma Collection
REFERENCE_BASED/POKEDEX para authenticated. Cria collection ->
collection_reference (kind='POKEDEX') -> collection_pokedex_reference
-> (se p_scope_kind = GENERATION_FILTERED) N linhas de
collection_pokedex_scope_generation, tudo na mesma transação — os
constraint triggers diferidos (5057/5092/5093/5094/5096) só avaliam
consistência no COMMIT desta função.

CORREÇÃO OBRIGATÓRIA (REVISION-01) — completion_policy =
'REFERENCE_POSITION': a v1.0 desta função gravava 'NONE', com o
argumento de que 'REFERENCE_POSITION' era Fatia E. Fabrício identificou
que isso é um estado semanticamente falso — uma Collection Pokédex TEM
uma política de completude (REFERENCE_POSITION, LDM-181), mesmo que o
CÁLCULO ainda não esteja implementado; gravar 'NONE' mentiria sobre
qual é essa política. A Query 5086 (nesta mesma pasta) alarga
chk_collection_completion_policy para aceitar (REFERENCE_BASED,
REFERENCE_POSITION) — pré-requisito desta função.

ESCOPO EXPLICITAMENTE LIMITADO (não confundir com Fatia E): gravar
completion_policy = 'REFERENCE_POSITION' aqui NÃO implementa o cálculo
de completion — collection_completion_summary()/collection_completion_
positions() (5070/5071/5083) não têm nenhum ramo para
REFERENCE_POSITION nesta rodada; chamá-las contra uma Collection assim
hoje retorna resultado vazio (nenhum ramo do UNION ALL de CTEs bate),
não um erro. Fatia E é integralmente responsável por: cálculo de
completion, denominator/numerator, read models e status derivado — ver
README para o racional completo desta divisão de responsabilidade.

DECISÃO EXPLÍCITA — Game Gate (ver também cabeçalho de 5090): valida
cedo (mensagem amigável) que o Game é o Pokémon TCG (game.code =
'POKEMON') — a garantia estrutural de fundo é a Query 5090, disparada
de qualquer forma pelo INSERT em collection_pokedex_reference abaixo.

p_scope_kind DEFAULT 'FULL_REFERENCE' — cobre o caso mais comum
(adotar toda a Pokédex) sem exigir que o chamador sempre informe o
parâmetro. p_generation_ids só é relevante quando p_scope_kind =
'GENERATION_FILTERED'; deduplicado via DISTINCT (mesmo padrão de
apply_master_set_scope_diff(), 5079) e validado contra
pokemon_generation antes de qualquer INSERT.

owner_user_id NUNCA aceito como parâmetro — sempre auth.uid(), mesmo
padrão de 5034/5065. mode NÃO é parâmetro — sempre 'REFERENCE_BASED'.

EXECUTE revogado de PUBLIC/anon; concedido apenas a authenticated.

Aplicação real (COLLECTIONS-POKEDEX-FATIA-B-IMPLEMENTATION-01): aplicada
via apply_migration/MCP do Supabase (projeto qjfutqujxrbzgrtkpgkg), uma
Query por vez, na ordem exata 5085→5099, sem alteração de SQL. Postcheck
físico independente (COLLECTIONS-POKEDEX-FATIA-B-CANONICAL-PROMOTION-01)
confirmou a função presente com a assinatura completa, gravando
completion_policy = 'REFERENCE_POSITION' (não 'NONE'), EXECUTE revogado
de PUBLIC/anon e concedido a authenticated. Validado funcionalmente pela
criação de Collections Pokédex reais (FULL_REFERENCE e
GENERATION_FILTERED), em BEGIN/ROLLBACK, incluindo rejeição correta para
Game não-Pokémon (Lorcana). Zero resíduo.

STATUS DESTA QUERY: CONFIRMADO EXECUTADO.
================================================================
*/

BEGIN;

CREATE FUNCTION public.create_reference_based_pokedex_collection(
    p_game_id                      UUID,
    p_name                         TEXT,
    p_description                  TEXT,
    p_default_storage_container_id UUID,
    p_pokedex_id                   UUID,
    p_scope_kind                   TEXT DEFAULT 'FULL_REFERENCE',
    p_generation_ids               UUID[] DEFAULT NULL
)
RETURNS TABLE (
    id                            UUID,
    name                          TEXT,
    mode                          TEXT,
    lifecycle_status              TEXT,
    visibility                    TEXT,
    default_storage_container_id  UUID,
    pokedex_id                    UUID,
    scope_kind                    TEXT,
    created_at                    TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_inventory_id     UUID;
    v_collection_id    UUID;
    v_reference_id     UUID;
    v_game_code        TEXT;
    v_created_at       TIMESTAMPTZ;
    v_lifecycle_status TEXT;
    v_visibility       TEXT;
    v_generation_ids   UUID[];
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'authentication required';
    END IF;

    IF p_name IS NULL OR btrim(p_name) = '' THEN
        RAISE EXCEPTION 'p_name não pode ser vazio';
    END IF;

    IF p_scope_kind NOT IN ('FULL_REFERENCE', 'GENERATION_FILTERED') THEN
        RAISE EXCEPTION 'p_scope_kind deve ser FULL_REFERENCE ou GENERATION_FILTERED';
    END IF;

    SELECT g.code INTO v_game_code
    FROM public.game g
    WHERE g.id = p_game_id;

    IF v_game_code IS NULL THEN
        RAISE EXCEPTION 'game not found';
    END IF;

    IF v_game_code IS DISTINCT FROM 'POKEMON' THEN
        RAISE EXCEPTION 'a Pokedex Reference só é permitida para Collections do Game Pokémon TCG (game.code = POKEMON)';
    END IF;

    SELECT inv.id INTO v_inventory_id
    FROM public.inventory inv
    WHERE inv.owner_user_id = auth.uid();

    IF v_inventory_id IS NULL THEN
        RAISE EXCEPTION 'inventory not found for current user';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.storage_container sc
        WHERE sc.id = p_default_storage_container_id
          AND sc.inventory_id = v_inventory_id
    ) THEN
        RAISE EXCEPTION 'default_storage_container_id does not belong to caller inventory';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.pokedex pd WHERE pd.id = p_pokedex_id) THEN
        RAISE EXCEPTION 'pokedex not found';
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

    -- completion_policy = 'REFERENCE_POSITION' (não 'NONE' — ver correção
    -- REVISION-01 no cabeçalho): identidade/policy correta da Collection
    -- Pokédex, ainda que o cálculo de completion seja responsabilidade
    -- integral da Fatia E.
    INSERT INTO public.collection (
        owner_user_id, game_id, name, description, default_storage_container_id, mode, completion_policy
    )
    VALUES (
        auth.uid(), p_game_id, btrim(p_name), p_description, p_default_storage_container_id, 'REFERENCE_BASED', 'REFERENCE_POSITION'
    )
    RETURNING collection.id, collection.created_at, collection.lifecycle_status, collection.visibility
    INTO v_collection_id, v_created_at, v_lifecycle_status, v_visibility;

    INSERT INTO public.collection_reference (collection_id, reference_kind)
    VALUES (v_collection_id, 'POKEDEX')
    RETURNING collection_reference.id INTO v_reference_id;

    INSERT INTO public.collection_pokedex_reference (collection_reference_id, pokedex_id, scope_kind)
    VALUES (v_reference_id, p_pokedex_id, p_scope_kind);

    IF p_scope_kind = 'GENERATION_FILTERED' THEN
        INSERT INTO public.collection_pokedex_scope_generation (collection_reference_id, generation_id)
        SELECT v_reference_id, gid FROM unnest(v_generation_ids) AS gid;
    END IF;

    RETURN QUERY
    SELECT v_collection_id, btrim(p_name), 'REFERENCE_BASED'::TEXT, v_lifecycle_status, v_visibility,
           p_default_storage_container_id, p_pokedex_id, p_scope_kind, v_created_at;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.create_reference_based_pokedex_collection(uuid, text, text, uuid, uuid, text, uuid[])
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_reference_based_pokedex_collection(uuid, text, text, uuid, uuid, text, uuid[])
    TO authenticated;

COMMIT;
