/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 6114 - Create admin_resolve_card_primary_species() Function
Versão......: 1.0
Status......: PROPOSTA — NÃO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-05 (staging em
               COLLECTIONS-POKEDEX-FATIA-C-PHYSICAL-MODELING-REVISION-01)

Descrição...:
Único caminho de escrita individual/editorial para card_primary_
species (Query 6112) — cobre tanto a PRIMEIRA resolução de uma Card
sem candidato automático (0 ou múltiplos dexIds, LDM-182) quanto a
CORREÇÃO de uma resolução já existente, automática ou editorial
(UPSERT por construção: INSERT se não existir linha, UPDATE se
existir). Mesmo padrão arquitetural de admin_create_card()/
admin_update_card() (ADR-023): função pública SECURITY DEFINER,
is_admin() verificado internamente, sem política de RLS de escrita.

Diferente de admin_create_card()/admin_update_card(), aqui uma única
função cobre create+update (em vez de duas) porque card_primary_
species é uma sub-entidade 1:1 sem contador de página nem formulário
"criar do zero" distinto de "editar" — do ponto de vista do
administrador, "resolver a Primary Species desta Card" é uma única
ação de tela, com ou sem valor anterior.

Sempre grava resolution_basis = 'EDITORIAL_RECONCILIATION' e
resolved_by_user_id = auth.uid() — nunca aceita p_resolution_basis
como parâmetro. Isso não é apenas uma escolha de design: mesmo que a
função tentasse gravar AUTOMATIC_DEXID, chk_card_primary_species_
basis_resolver_coupling (Query 6112) rejeitaria a linha, porque
resolved_by_user_id nunca é NULL numa chamada autenticada. A restrição
de negócio (só humano decide aqui) e a restrição estrutural (CHECK)
se reforçam mutuamente — defesa em profundidade real, não decorativa.

Rastreabilidade (mandato desta rodada, item 6): old/new Species e
basis vão em catalog_admin_action_log.metadata (Query 2010, ampliada
pela Query 2159) — old_* são NULL na primeira resolução (não havia
linha anterior) e populados com os valores efetivamente substituídos
numa correção. Nenhuma tabela de histórico dedicada é criada — esta
única linha de auditoria por chamada já é suficiente, mesmo raciocínio
de LDM-179 (evitar entidade de histórico dedicada quando um mecanismo
genérico já cobre o caso).

Regras de Negócio:
- Só administrador (is_admin()).
- p_card_id e p_pokemon_species_id obrigatórios.
- Card deve existir E pertencer a card_category.code = 'POKEMON' —
  antecipa o erro de trg_010_enforce_card_primary_species_category
  (Query 6113) com uma mensagem administrativa clara, mesmo padrão de
  "antecipar o erro" já usado em admin_create_card().
- Species deve existir em public.pokemon_species.
- p_source_evidence é opcional (nullable) — forma livre, sem CHECK de
  schema (chk_card_primary_species_automatic_evidence_shape só se
  aplica a AUTOMATIC_DEXID); um administrador pode anexar contexto
  (ex.: "dois dexIds candidatos, escolhido por conferência manual da
  arte") sem obrigação de formato.
- UPSERT por SELECT ... FOR UPDATE seguido de branch INSERT/UPDATE
  explícito (não ON CONFLICT): permite capturar v_existing ANTES da
  escrita, necessário para montar old_* na auditoria — ON CONFLICT DO
  UPDATE não exporia a linha antiga na mesma instrução com a mesma
  clareza.
- GET DIAGNOSTICS confirma o efeito real do UPDATE, mesmo padrão de
  internal.write_card().

Pré-requisitos:
- Query 6112/6113 - Create Card Primary Species Table/Triggers.
- Query 2159 - Widen Catalog Admin Action Log for Card Primary Species.
- Query 1060 - Create is_admin() Function.
===============================================================================
*/

BEGIN;

CREATE OR REPLACE FUNCTION public.admin_resolve_card_primary_species(
    p_card_id UUID,
    p_pokemon_species_id UUID,
    p_source_evidence JSONB DEFAULT NULL
)
RETURNS public.card_primary_species
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_category_code TEXT;
    v_existing public.card_primary_species%ROWTYPE;
    v_result public.card_primary_species%ROWTYPE;
    v_rows_affected INTEGER;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'ADMIN_RESOLVE_CARD_PRIMARY_SPECIES_FORBIDDEN: apenas administradores podem resolver a Primary Species de uma Card.';
    END IF;

    IF p_card_id IS NULL THEN
        RAISE EXCEPTION 'ADMIN_RESOLVE_CARD_PRIMARY_SPECIES_MISSING_CARD: p_card_id é obrigatório.';
    END IF;

    IF p_pokemon_species_id IS NULL THEN
        RAISE EXCEPTION 'ADMIN_RESOLVE_CARD_PRIMARY_SPECIES_MISSING_SPECIES: p_pokemon_species_id é obrigatório.';
    END IF;

    SELECT cc.code INTO v_category_code
    FROM public.card c
    JOIN public.card_category cc ON cc.id = c.category_id
    WHERE c.id = p_card_id;

    IF v_category_code IS NULL THEN
        RAISE EXCEPTION 'ADMIN_RESOLVE_CARD_PRIMARY_SPECIES_CARD_NOT_FOUND: nenhuma Card encontrada para o id informado (%).', p_card_id;
    END IF;

    IF v_category_code <> 'POKEMON' THEN
        RAISE EXCEPTION 'ADMIN_RESOLVE_CARD_PRIMARY_SPECIES_REQUIRES_POKEMON_CATEGORY: a Card informada não é da categoria POKEMON.';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.pokemon_species WHERE id = p_pokemon_species_id) THEN
        RAISE EXCEPTION 'ADMIN_RESOLVE_CARD_PRIMARY_SPECIES_SPECIES_NOT_FOUND: nenhuma Species encontrada para o id informado (%).', p_pokemon_species_id;
    END IF;

    SELECT * INTO v_existing
    FROM public.card_primary_species
    WHERE card_id = p_card_id
    FOR UPDATE;

    IF NOT FOUND THEN
        INSERT INTO public.card_primary_species (
            card_id, pokemon_species_id, resolution_basis,
            source_evidence, resolved_at, resolved_by_user_id
        ) VALUES (
            p_card_id, p_pokemon_species_id, 'EDITORIAL_RECONCILIATION',
            p_source_evidence, NOW(), auth.uid()
        )
        RETURNING * INTO v_result;

        INSERT INTO public.catalog_admin_action_log (actor_id, action, entity_type, entity_id, metadata)
            VALUES (
                auth.uid(), 'CARD_PRIMARY_SPECIES_RESOLVED', 'CARD_PRIMARY_SPECIES', p_card_id,
                jsonb_build_object(
                    'old_pokemon_species_id', NULL,
                    'old_resolution_basis', NULL,
                    'old_source_evidence', NULL,
                    'new_pokemon_species_id', p_pokemon_species_id,
                    'new_resolution_basis', 'EDITORIAL_RECONCILIATION',
                    'new_source_evidence', p_source_evidence
                )
            );
    ELSE
        UPDATE public.card_primary_species
            SET pokemon_species_id = p_pokemon_species_id,
                resolution_basis = 'EDITORIAL_RECONCILIATION',
                source_evidence = p_source_evidence,
                resolved_at = NOW(),
                resolved_by_user_id = auth.uid()
            WHERE card_id = p_card_id
        RETURNING * INTO v_result;

        GET DIAGNOSTICS v_rows_affected = ROW_COUNT;
        IF v_rows_affected <> 1 THEN
            RAISE EXCEPTION 'ADMIN_RESOLVE_CARD_PRIMARY_SPECIES_UPDATE_FAILED: nenhuma linha afetada para card_id (%).', p_card_id;
        END IF;

        INSERT INTO public.catalog_admin_action_log (actor_id, action, entity_type, entity_id, metadata)
            VALUES (
                auth.uid(), 'CARD_PRIMARY_SPECIES_CORRECTED', 'CARD_PRIMARY_SPECIES', p_card_id,
                jsonb_build_object(
                    'old_pokemon_species_id', v_existing.pokemon_species_id,
                    'old_resolution_basis', v_existing.resolution_basis,
                    'old_source_evidence', v_existing.source_evidence,
                    'new_pokemon_species_id', p_pokemon_species_id,
                    'new_resolution_basis', 'EDITORIAL_RECONCILIATION',
                    'new_source_evidence', p_source_evidence
                )
            );
    END IF;

    RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.admin_resolve_card_primary_species(UUID, UUID, JSONB) IS
    'Resolução/correção editorial individual de Card Primary Species. Sempre EDITORIAL_RECONCILIATION. UPSERT (insere se ausente, atualiza se existente). Grava old/new em catalog_admin_action_log. is_admin() only.';

GRANT EXECUTE ON FUNCTION public.admin_resolve_card_primary_species(UUID, UUID, JSONB) TO authenticated;

REVOKE ALL ON FUNCTION public.admin_resolve_card_primary_species(UUID, UUID, JSONB) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_resolve_card_primary_species(UUID, UUID, JSONB) FROM anon;

COMMIT;
