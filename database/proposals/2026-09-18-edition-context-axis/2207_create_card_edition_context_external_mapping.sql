-- ============================================================================
-- Query 2207 — card_edition_context_external_mapping (+ N:N de traits)
-- Status: PROPOSTA — NÃO EXECUTADA · Versão 1.0
--
-- CONTRATO DE ROUTING — FAIL CLOSED
--   Um token externo só alimenta Edition Context se existir mapping CANÔNICO
--   EXPLÍCITO para este eixo. Proibido, sem exceção:
--     · inferir por substring / regex / heurística;
--     · derivar `code` automaticamente do vocabulário TCGdex;
--     · consumir token indeterminado;
--     · "adivinhar" família por padrão de nome.
--   Token desconhecido NÃO vira contexto: permanece no residual de Finish e a
--   linha termina NEEDS_REVIEW. É o mesmo princípio de 2172.
--
-- RAW_FIELDS AUTORIZADOS — decisão explícita, medida
--   'stamp'   : autorizado. 1.145 ocorrências em A; principal alimentador.
--   'subtype' : autorizado. Necessário porque Printing já consome subtype e o
--               que sobra pode ser contexto (ex.: bordas promocionais).
--   'foil'    : **PROIBIDO** (BLOCKER 6 / CORRECTION-01). Ver nota abaixo.
--   'type'    : PROIBIDO. É o eixo de acabamento por definição.
--   'size'    : PROIBIDO. É escopo (2198), nunca identidade.
--
--   POR QUE `foil` FICOU FORA — decisao da CORRECTION-01
--   O campo e semanticamente misto na fonte: carrega padrao fisico (COSMOS,
--   CRACKED-ICE, ENERGY) E nome de programa (LEAGUE, PLAYER-REWARD,
--   PROFESSOR-PROGRAM). O legado JA materializou os tres ultimos como contexto
--   (STANDARDS_LEAGUE, PLAYER_REWARD_REVERSE, COSMOS_PROFESSOR_REVERSE), mas as
--   57 rows modernas equivalentes seguem INDETERMINADAS.
--   Autorizar raw_field='foil' aqui legitimaria no schema uma semantica ainda
--   nao decidida e abriria porta para classificacao futura acidental.
--   Decisao: dominio FECHADO em ('stamp','subtype'). O legado e tratado por
--   migracao via lineage (nao precisa de mapping externo). Se B3 for resolvido,
--   uma migration propria amplia o CHECK conscientemente.
-- ============================================================================

-- Fronteira transacional EXPLÍCITA (TRANSACTION-BOUNDARY-CORRECTION-01).
-- Paridade com as Queries 2172/2173. Este arquivo cria DUAS tabelas ligadas
-- por FK: aplicar só a primeira deixaria o mapping sem vínculo de traits.
-- Ver nota completa na Query 2203.
BEGIN;

CREATE TABLE public.card_edition_context_external_mapping (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id          UUID NOT NULL REFERENCES public.game (id)
                          ON UPDATE RESTRICT ON DELETE RESTRICT,
    asset_source_id  UUID NOT NULL REFERENCES public.asset_source (id)
                          ON UPDATE RESTRICT ON DELETE RESTRICT,
    -- Escopo por Set da fonte. NULL = GLOBAL. Mesmo contrato de 2140 v2.0:
    -- o mesmo token pode ter alvo distinto por era/Set (set-logo é o caso real).
    external_set_id  TEXT,
    raw_field        TEXT NOT NULL,
    normalized_token TEXT NOT NULL,
    is_active        BOOLEAN NOT NULL DEFAULT TRUE,
    traits_signature UUID[],
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- BLOCKER 6 (CORRECTION-01): dominio FECHADO em stamp/subtype.
    -- `foil` FORA. Legitimar foil no DDL permitiria classificacao futura
    -- acidental de uma semantica que segue INDETERMINADA (as 57 rows modernas
    -- continuam HOLD). O legado que ja carrega LEAGUE/PLAYER-REWARD/
    -- PROFESSOR-PROGRAM recebe Edition Context por MIGRACAO VIA LINEAGE, que
    -- nao passa por esta tabela. Ampliar o dominio exige migration propria e
    -- consciente, depois de B3 resolvido.
    CONSTRAINT ck_cecem_raw_field
        CHECK (raw_field IN ('stamp','subtype')),
    CONSTRAINT ck_cecem_token_not_blank
        CHECK (btrim(normalized_token) <> ''),
    CONSTRAINT ck_cecem_external_set_not_blank
        CHECK (external_set_id IS NULL OR btrim(external_set_id) <> ''),
    CONSTRAINT ck_cecem_signature_shape CHECK (
        traits_signature IS NULL OR (
            cardinality(traits_signature) > 0
            AND traits_signature = ARRAY(SELECT DISTINCT u FROM unnest(traits_signature) u ORDER BY u)
        )
    ),
    CONSTRAINT uq_cecem_id_game UNIQUE (id, game_id)
);

-- Dois índices parciais disjuntos, espelhando 2140 v2.0: GLOBAL e SOURCE_SET.
-- Precedência de UM nível: scoped > global > residual. Sem desempate.
CREATE UNIQUE INDEX uq_cecem_global
    ON public.card_edition_context_external_mapping
       (game_id, asset_source_id, raw_field, normalized_token)
    WHERE external_set_id IS NULL;

CREATE UNIQUE INDEX uq_cecem_scoped
    ON public.card_edition_context_external_mapping
       (game_id, asset_source_id, external_set_id, raw_field, normalized_token)
    WHERE external_set_id IS NOT NULL;

CREATE TABLE public.card_edition_context_external_mapping_trait (
    mapping_id UUID NOT NULL,
    trait_id   UUID NOT NULL,
    game_id    UUID NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT pk_cecemt PRIMARY KEY (mapping_id, trait_id),
    CONSTRAINT fk_cecemt_mapping
        FOREIGN KEY (mapping_id, game_id)
        REFERENCES public.card_edition_context_external_mapping (id, game_id)
        ON UPDATE RESTRICT ON DELETE RESTRICT,
    CONSTRAINT fk_cecemt_trait
        FOREIGN KEY (trait_id, game_id)
        REFERENCES public.card_edition_context_trait (id, game_id)
        ON UPDATE RESTRICT ON DELETE RESTRICT
);

COMMENT ON TABLE public.card_edition_context_external_mapping IS
'Unica ponte entre vocabulario da fonte externa e o eixo Edition Context. Fail-closed: token sem mapping ativo NAO vira contexto, permanece no residual de Finish. raw_field FECHADO em (stamp, subtype) — foil, type e size estao FORA do dominio por CHECK. foil ficou fora deliberadamente (CORRECTION-01/Blocker 6): e semanticamente misto na fonte e legitima-lo no schema permitiria classificacao futura acidental das 57 rows que seguem INDETERMINADAS. Ampliar o dominio exige migration propria.';

-- ----------------------------------------------------------------------------
-- SEGURANÇA — paridade EXATA com as Queries 2172 e 2173
-- ----------------------------------------------------------------------------
-- Corrigido em SECURITY-SEED-HARDENING-01 (B3): as duas tabelas tinham
-- GRANT sem RLS, e a de cabeçalho ainda concedia INSERT/UPDATE ao
-- service_role. Ver comentário completo na 2203.
ALTER TABLE public.card_edition_context_external_mapping       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.card_edition_context_external_mapping_trait ENABLE ROW LEVEL SECURITY;

CREATE POLICY catalog_admin_select
    ON public.card_edition_context_external_mapping
    FOR SELECT
    USING ((SELECT public.is_admin()));

CREATE POLICY catalog_admin_select
    ON public.card_edition_context_external_mapping_trait
    FOR SELECT
    USING ((SELECT public.is_admin()));

REVOKE ALL ON public.card_edition_context_external_mapping       FROM anon, authenticated, service_role;
REVOKE ALL ON public.card_edition_context_external_mapping_trait FROM anon, authenticated, service_role;
GRANT SELECT ON public.card_edition_context_external_mapping       TO authenticated;
GRANT SELECT ON public.card_edition_context_external_mapping_trait TO authenticated;
-- service_role: SELECT e SÓ, e SÓ no cabeçalho — é dele que a Edge resolve
-- token -> traits_signature + is_active, igual ao recorte da Query 2182 para
-- card_printing_external_mapping. A tabela de vínculo fica SEM grant, mesma
-- decisão da Query 2173.
GRANT SELECT ON public.card_edition_context_external_mapping TO service_role;

COMMIT;
