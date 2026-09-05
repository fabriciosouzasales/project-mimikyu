/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 6113 - Create Card Primary Species Triggers
Versão......: 1.0 (CONFIRMADO EXECUTADO E PROMOVIDO)
Status......: CONFIRMADO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-05 (staging em
               COLLECTIONS-POKEDEX-FATIA-C-PHYSICAL-MODELING-AUDIT-01;
               executada no banco real em ...-IMPLEMENTATION-01-RESUME;
               promovida para database/schema/ em
               ...-CANONICAL-CLOSEOUT-01 — corpo SQL byte-idêntico ao
               executado, apenas cabeçalho Status/Versão/Data
               atualizados)

Descrição...:
Governança e integridade estrutural de card_primary_species (Query
6112). Mesmo padrão de três-triggers já usado por pokemon_species
(Query 6011): normalização (não aplicável aqui — nenhum campo textual
livre a normalizar), governança de imutabilidade e updated_at.
Diferença: esta tabela também precisa de uma checagem de integridade
de categoria (trg_010), sem precedente direto no projeto (auditado
nesta rodada — nenhum trigger equivalente encontrado em
database/schema/), justificada abaixo.

trg_010: card_category integrity. Rejeita INSERT quando a Card
referenciada não pertence a card_category.code = 'POKEMON' (join
card -> card_category). Evita o erro estrutural de atribuir uma
Primary Species a uma Trainer Card ou Energy Card. Roda apenas em
BEFORE INSERT — card_id é imutável após o INSERT (trg_020), então a
categoria da Card não pode "desviar" por uma mutação desta própria
linha. Risco residual (fora de escopo corrigir nesta rodada, ver
README): se card.category_id de uma Card já vinculada for alterado
depois via algum caminho futuro, esta tabela não é notificada — hoje
internal.write_card() (Query 2030) não expõe nenhum parâmetro/caminho
de UPDATE de category_id, então o risco é teórico no estado físico
atual.

trg_020: imutabilidade de card_id e created_at — identidade técnica,
mesmo raciocínio de govern_pokemon_species() (Query 6011).
pokemon_species_id, resolution_basis, source_evidence, resolved_at e
resolved_by_user_id permanecem deliberadamente CORRIGÍVEIS (não
protegidos por este trigger) — é exatamente o mecanismo de "correção
futura sem destruir rastreabilidade" pedido pelo mandato desta
rodada. A rastreabilidade da correção em si (quem/quando/de-para) é
responsabilidade de quem escrever a função de escrita (fora de
escopo), via public.catalog_admin_action_log (Query 2010) — não desta
tabela nem destes triggers.

trg_030: touch de updated_at, mesmo padrão de
touch_pokemon_species_updated_at() (Query 6011).

Pré-requisitos:
- Query 6112 - Create Card Primary Species Table.
================================================================
*/

BEGIN;

CREATE OR REPLACE FUNCTION public.enforce_card_primary_species_pokemon_category()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
    v_category_code TEXT;
BEGIN
    SELECT cc.code
      INTO v_category_code
      FROM public.card c
      JOIN public.card_category cc ON cc.id = c.category_id
     WHERE c.id = NEW.card_id;

    IF v_category_code IS DISTINCT FROM 'POKEMON' THEN
        RAISE EXCEPTION 'CARD_PRIMARY_SPECIES_REQUIRES_POKEMON_CATEGORY';
    END IF;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.govern_card_primary_species()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    IF NEW.card_id IS DISTINCT FROM OLD.card_id THEN
        RAISE EXCEPTION 'CARD_PRIMARY_SPECIES_CARD_ID_IMMUTABLE';
    END IF;
    IF NEW.created_at IS DISTINCT FROM OLD.created_at THEN
        RAISE EXCEPTION 'CARD_PRIMARY_SPECIES_CREATED_AT_IMMUTABLE';
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.touch_card_primary_species_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_010_enforce_card_primary_species_category
BEFORE INSERT
ON public.card_primary_species
FOR EACH ROW
EXECUTE FUNCTION public.enforce_card_primary_species_pokemon_category();

CREATE TRIGGER trg_020_govern_card_primary_species
BEFORE UPDATE
ON public.card_primary_species
FOR EACH ROW
EXECUTE FUNCTION public.govern_card_primary_species();

CREATE TRIGGER trg_030_touch_card_primary_species_updated_at
BEFORE UPDATE
ON public.card_primary_species
FOR EACH ROW
EXECUTE FUNCTION public.touch_card_primary_species_updated_at();

COMMIT;
