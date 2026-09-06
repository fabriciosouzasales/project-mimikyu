/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 6118 - Create Collection Pokédex Position Assignment Triggers
Versão......: 1.1 (CONFIRMADO EXECUTADO E PROMOVIDO)
Status......: CONFIRMADO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-05 (staging em COLLECTIONS-POKEDEX-FATIA-D-STAGING-01;
               revisado em ...-STAGING-AUDIT-01, item 1: trg_005 novo;
               fix adicional em GATE 4 (trigger USER_OVERRIDE actor);
               executada no banco real em IMPLEMENTATION-RESUME-02;
               promovida para database/schema/ em COLLECTIONS-POKEDEX-
               FATIA-D-PROMOTION-CLOSEOUT-01 — corpo SQL byte-idêntico
               ao executado, apenas cabeçalho Status/Versão/Data
               atualizados)

Correção v1.1 (STAGING-AUDIT-01, item 1) — GAP real encontrado: nada
impedia estruturalmente que uma linha USER_OVERRIDE fosse criada com
assigned_by_user_id NULL — só a lógica da RPC (Query 6122) garantia
isso, e um CHECK constraint clássico foi deliberadamente descartado no
header da Query 6117 (quebraria a ação ON DELETE SET NULL). trg_005
fecha esse gap sem reabrir esse problema: valida a regra só em BEFORE
INSERT (nunca em UPDATE), then a exigência "USER_OVERRIDE implica ator"
vale apenas no momento da criação — depois que a linha existe, a
transição NOT NULL -> NULL continua livre via trg_020 (inalterado),
exatamente como o mandato pediu ("não usar CHECK que impeça futuro
ON DELETE SET NULL", "implementar a regra no trigger de INSERT/
governança").

Descrição...:
Integridade estrutural de collection_pokedex_position_assignment
(Query 6117). Três triggers:

trg_005: assignment_basis = 'USER_OVERRIDE' exige assigned_by_user_id
NOT NULL no momento do INSERT (LDM-178 — uma confirmação humana precisa
ter um humano identificável). Symmetricamente, SPECIES_MATCH nunca é
IMPEDIDO de ter um ator (a RPC de hoje, Query 6122/6119, sempre grava
NULL para SPECIES_MATCH por decisão de design, não por proibição
estrutural) — este trigger não valida nada para SPECIES_MATCH, só para
USER_OVERRIDE. BEFORE INSERT apenas, mesma razão de trg_010 abaixo (a
linha é imutável; a única UPDATE permitida por trg_020 é a transição
técnica NOT NULL -> NULL, que por definição só ocorre em linhas que já
passaram por esta checagem no INSERT — não precisa ser revalidada).

trg_010: pokedex_position_id pertence ao mesmo Pokédex referenciado
pela Collection da Allocation (item B da auditoria física, LDM-179).
BEFORE INSERT apenas — a linha é imutável (trg_020 abaixo bloqueia
qualquer tentativa de mudar pokedex_position_id depois), então esta
checagem nunca precisa rodar de novo em UPDATE. Roda por linha
(FOR EACH ROW) porque, diferente de collection_allocation (que aceita
lotes de até 500 via allocate_physical_cards_to_collection), toda
escrita nesta tabela é sempre de uma linha por vez (Queries 6119/6122).
Deliberadamente NÃO valida Game nem Owner: ambos já são garantidos
transitivamente antes de uma linha aqui poder existir — Owner pela RLS
e pela RPC (Query 6122), Game porque a Allocation já é Game-validada
(validate_collection_allocation_integrity, 2C) e o Pokédex da Collection
já é Game-validado (validate_collection_pokedex_reference_game_and_lock,
Fatia B). Deliberadamente NÃO valida Scope (LDM-177) — ver header da
Query 6117.

trg_020: imutabilidade com uma única exceção técnica (Physical Modeling
Revision-01 + STAGING-01, item 1). Rejeita todo UPDATE, EXCETO
exatamente o caso em que assigned_by_user_id transiciona de NOT NULL
para NULL (a ação referencial ON DELETE SET NULL da FK para auth.users,
Query 6117) e nenhum outro campo muda. Qualquer outra tentativa de
UPDATE — inclusive mudar pokedex_position_id (o caso que motivou a
Revision-01: "mover" é DELETE+INSERT, nunca UPDATE) — é rejeitada.
Nenhuma trigger de "sincronização" com
collection_pokedex_position_primary_representative (Query 6120) é
necessária: como mover é DELETE+INSERT, o ON DELETE CASCADE já existente
a partir do Primary Representative (Query 6120) resolve a limpeza do
Primary antigo de forma puramente estrutural — ver header da Query 6120.

Nenhum GRANT de UPDATE é concedido a nenhum papel nesta tabela (Query
6117) — a única UPDATE que este trigger permite é disparada pela ação
referencial do próprio Postgres ao excluir uma linha de auth.users,
que não passa pelo sistema de GRANT de tabela do papel chamador daquela
exclusão.

Pré-requisitos:
- Query 6117 - Create Collection Pokédex Position Assignment Table.
================================================================
*/

BEGIN;

CREATE OR REPLACE FUNCTION public.enforce_pokedex_position_assignment_user_override_actor()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    IF NEW.assignment_basis = 'USER_OVERRIDE' AND NEW.assigned_by_user_id IS NULL THEN
        RAISE EXCEPTION 'COLLECTION_POKEDEX_POSITION_ASSIGNMENT_USER_OVERRIDE_REQUIRES_ACTOR: assignment_basis = USER_OVERRIDE exige assigned_by_user_id preenchido no momento da criação.';
    END IF;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.enforce_pokedex_position_assignment_pokedex_match()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
    v_pokedex_id_from_collection UUID;
    v_pokedex_id_from_position   UUID;
BEGIN
    SELECT cpr.pokedex_id
      INTO v_pokedex_id_from_collection
      FROM public.collection_allocation ca
      JOIN public.collection_reference cr ON cr.collection_id = ca.collection_id
      JOIN public.collection_pokedex_reference cpr ON cpr.collection_reference_id = cr.id
     WHERE ca.id = NEW.collection_allocation_id
       AND cr.reference_kind = 'POKEDEX';

    IF v_pokedex_id_from_collection IS NULL THEN
        RAISE EXCEPTION 'COLLECTION_POKEDEX_POSITION_ASSIGNMENT_REQUIRES_POKEDEX_COLLECTION';
    END IF;

    SELECT pp.pokedex_id
      INTO v_pokedex_id_from_position
      FROM public.pokedex_position pp
     WHERE pp.id = NEW.pokedex_position_id;

    IF v_pokedex_id_from_position IS DISTINCT FROM v_pokedex_id_from_collection THEN
        RAISE EXCEPTION 'COLLECTION_POKEDEX_POSITION_ASSIGNMENT_WRONG_POKEDEX';
    END IF;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.govern_collection_pokedex_position_assignment()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    -- Única exceção técnica permitida: ON DELETE SET NULL de
    -- assigned_by_user_id (Query 6117), e nenhum outro campo muda junto.
    IF OLD.assigned_by_user_id IS NOT NULL
       AND NEW.assigned_by_user_id IS NULL
       AND NEW.collection_allocation_id IS NOT DISTINCT FROM OLD.collection_allocation_id
       AND NEW.pokedex_position_id IS NOT DISTINCT FROM OLD.pokedex_position_id
       AND NEW.assignment_basis IS NOT DISTINCT FROM OLD.assignment_basis
       AND NEW.assigned_at IS NOT DISTINCT FROM OLD.assigned_at
    THEN
        RETURN NEW;
    END IF;

    RAISE EXCEPTION 'COLLECTION_POKEDEX_POSITION_ASSIGNMENT_IMMUTABLE: linha imutável — mover é DELETE + INSERT (Query 6122), nunca UPDATE.';
END;
$$;

CREATE TRIGGER trg_005_enforce_pokedex_position_assignment_user_override_actor
BEFORE INSERT
ON public.collection_pokedex_position_assignment
FOR EACH ROW
EXECUTE FUNCTION public.enforce_pokedex_position_assignment_user_override_actor();

CREATE TRIGGER trg_010_enforce_pokedex_position_assignment_pokedex_match
BEFORE INSERT
ON public.collection_pokedex_position_assignment
FOR EACH ROW
EXECUTE FUNCTION public.enforce_pokedex_position_assignment_pokedex_match();

CREATE TRIGGER trg_020_govern_collection_pokedex_position_assignment
BEFORE UPDATE
ON public.collection_pokedex_position_assignment
FOR EACH ROW
EXECUTE FUNCTION public.govern_collection_pokedex_position_assignment();

COMMIT;
