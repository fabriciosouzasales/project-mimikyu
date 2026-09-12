/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 2167 - Create Card Printing Profile Trait Table
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO / LIVE
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-12
Mandato.....: CARD-VARIANTS — PRINTING-MODEL-STAGING-01 — GATE-A-01

-------------------------------------------------------------------------------
EXECUÇÃO CONFIRMADA — 2026-09-12
-------------------------------------------------------------------------------
Executado via apply_migration no projeto Supabase qjfutqujxrbzgrtkpgkg.
Ordem de aplicacao: 2165 -> 2166 -> 2167 -> 2168 -> 2169 -> 2170 -> 2171.
Todas as sete aplicadas sem erro.
Estado final validado integralmente pela Query 2823 v1.2:
    12 PASS / 0 FAIL / 0 NOT PROVEN, zero residuo.
O SQL executavel permanece INTOCADO desde a execucao.
-------------------------------------------------------------------------------

Descrição resumida:
Cria public.card_printing_profile_trait — a N:N que e a FONTE DA VERDADE da
composicao de um Print Profile.

Descrição:
Esta tabela e a autoridade. Todo filtro por caracteristica ("todas as
Shadowless", "todas as 1a Edicao") passa por aqui, nunca por parse de code.

SAME-GAME ESTRUTURAL (mandato §9, §13):
Um Profile de POKEMON nao pode conter um Trait de outro Game. Isso NAO e
garantido por duas FKs simples. A garantia aqui e estrutural, sem trigger:
a tabela carrega game_id e usa duas FKs COMPOSTAS contra as UNIQUE
(id, game_id) declaradas em 2165 e 2166. O Postgres passa a exigir que os
tres concordem. E o mesmo mecanismo ja usado no projeto por
uq_card_variant_id_card.

Nenhum campo alem do necessario: sem display_order proprio (a ordem de
exibicao de um trait dentro do profile e a do proprio trait), sem
timestamps de atualizacao (a linha e imutavel por desenho — ver 2168).

Regras de Negócio:
- PK composta (profile_id, trait_id) impede repeticao do mesmo trait.
- FK composta garante same-Game entre Profile e Trait, sem trigger.
- ON DELETE RESTRICT nos dois lados: nada some por acidente.
- Composicao imutavel apos a transacao de criacao (Query 2168).
- Todo Profile precisa de >= 1 trait (Query 2168, deferido).
- RLS habilitado; leitura admin-only.

Pré-requisitos:
- Query 2165 - Create Card Printing Trait Table.
- Query 2166 - Create Card Printing Profile Table.
===============================================================================
*/

BEGIN;

CREATE TABLE public.card_printing_profile_trait (
    profile_id UUID NOT NULL,
    trait_id UUID NOT NULL,

    -- Redundante por desenho: e o que permite a FK composta provar same-Game.
    game_id UUID NOT NULL,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT pk_card_printing_profile_trait
        PRIMARY KEY (profile_id, trait_id),

    CONSTRAINT fk_card_printing_profile_trait_profile
        FOREIGN KEY (profile_id, game_id)
        REFERENCES public.card_printing_profile (id, game_id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    CONSTRAINT fk_card_printing_profile_trait_trait
        FOREIGN KEY (trait_id, game_id)
        REFERENCES public.card_printing_trait (id, game_id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT
);

COMMENT ON TABLE public.card_printing_profile_trait IS
    'FONTE DA VERDADE da composicao de um Print Profile. Filtro por caracteristica sempre passa por aqui — nunca por parse de code.';

COMMENT ON COLUMN public.card_printing_profile_trait.game_id IS
    'Redundante por desenho. Participa das duas FKs compostas e e o que torna o same-Game entre Profile e Trait uma garantia ESTRUTURAL do Postgres, sem trigger.';

-- Lookup trait -> profiles ("quais Profiles contem SHADOWLESS").
-- A PK ja cobre profile -> traits.
CREATE INDEX ix_card_printing_profile_trait_trait_id
    ON public.card_printing_profile_trait (trait_id);

COMMENT ON INDEX public.ix_card_printing_profile_trait_trait_id IS
    'Suporta a faceta independente: dado um Trait, encontrar todos os Profiles que o contem. E o indice que sustenta o filtro "todas as Shadowless" sem LIKE.';

ALTER TABLE public.card_printing_profile_trait ENABLE ROW LEVEL SECURITY;

CREATE POLICY catalog_admin_select
    ON public.card_printing_profile_trait
    FOR SELECT
    USING ((SELECT public.is_admin()));

REVOKE ALL ON public.card_printing_profile_trait FROM anon, authenticated, service_role;
GRANT SELECT ON public.card_printing_profile_trait TO authenticated;

COMMIT;

-- ============================================================================
-- Como validar:
--   Query 2823 - Validate Card Printing Model, Secoes 1, 2 e 4.
-- ============================================================================
