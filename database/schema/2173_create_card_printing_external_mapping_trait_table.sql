/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 2173 - Create Card Printing External Mapping Trait Table
Versão......: 1.0
Status......: CANÔNICA — CONFIRMADO EXECUTADO / LIVE / PROMOVIDO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-12
Promovida...: 2026-09-13 — TECHNICAL-CLOSEOUT-PROMOTION-01
Origem......: database/proposals/2026-09-12-card-variants-printing-routing/
              2173_create_card_printing_external_mapping_trait_table.sql
Mandato.....: CARD-VARIANTS — PRINTING-ROUTING — STAGING-GATE-A-01 (§5)

Descrição resumida:
Cria public.card_printing_external_mapping_trait — a N:N que e a FONTE DA
VERDADE da composicao de um mapping de Printing.

Descrição:
Um token externo mapeia para UM CONJUNTO de Print Traits:

    subtype | shadowless-red-cheek  ->  SHADOWLESS
                                    ->  RED_CHEEK

Esta tabela e a autoridade semantica desse conjunto.
mapping.traits_signature e materializacao derivada dela.

SAME-GAME POR FK COMPOSTA, SEM TRIGGER:
game_id e redundante por desenho e participa das DUAS FKs. Isso torna
"mapping e trait pertencem ao mesmo Game" uma garantia ESTRUTURAL do
Postgres — a mesma escolha ja provada em
card_printing_profile_trait (Query 2167).

Regras de Negócio:
- PK (mapping_id, trait_id): um trait nunca se repete no mesmo mapping.
- Composicao imutavel apos o selamento do mapping (Query 2174).
- Todo mapping precisa de >= 1 trait no COMMIT (Query 2174).
- Nenhum trigger de same-Game: as FKs compostas bastam.
- RLS habilitado; leitura admin-only.
- NAO recebe GRANT ao service_role: o runtime da Edge Function le
  apenas traits_signature do cabecalho (Query 2182).

Pré-requisitos:
- Query 2165 - Create Card Printing Trait Table.
- Query 2172 - Create Card Printing External Mapping Table.

-------------------------------------------------------------------------------
REVISION HISTORY
-------------------------------------------------------------------------------
| 1.0 | **Criação da tabela (2026-09-12).** Executada e confirmada no banco
        físico na PHASE A da frente CARD-VARIANTS — PRINTING-ROUTING.
        Promovida de database/proposals/ para database/schema/ em 2026-09-13
        (TECHNICAL-CLOSEOUT-PROMOTION-01). O SQL executável permanece
        idêntico ao artefato executado; só o cabeçalho registra o estado
        final. A proposal original é preservada como histórico. |
===============================================================================
*/

BEGIN;

CREATE TABLE public.card_printing_external_mapping_trait (
    mapping_id UUID NOT NULL,
    trait_id UUID NOT NULL,

    -- Redundante por desenho: e o que permite a FK composta provar
    -- same-Game sem trigger nenhum.
    game_id UUID NOT NULL,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT pk_card_printing_external_mapping_trait
        PRIMARY KEY (mapping_id, trait_id),

    CONSTRAINT fk_card_printing_external_mapping_trait_mapping
        FOREIGN KEY (mapping_id, game_id)
        REFERENCES public.card_printing_external_mapping (id, game_id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    CONSTRAINT fk_card_printing_external_mapping_trait_trait
        FOREIGN KEY (trait_id, game_id)
        REFERENCES public.card_printing_trait (id, game_id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT
);

COMMENT ON TABLE public.card_printing_external_mapping_trait IS
    'FONTE DA VERDADE da composicao de um mapping de Printing. mapping.traits_signature e derivada daqui. Filtro por trait sempre passa por esta tabela — nunca por parse de token.';

COMMENT ON COLUMN public.card_printing_external_mapping_trait.game_id IS
    'Redundante por desenho. Participa das duas FKs compostas e e o que torna o same-Game entre mapping e trait uma garantia ESTRUTURAL do Postgres, sem trigger.';

-- Lookup trait -> mappings ("quais tokens externos produzem SHADOWLESS").
-- A PK ja cobre mapping -> traits.
CREATE INDEX ix_card_printing_external_mapping_trait_trait_id
    ON public.card_printing_external_mapping_trait (trait_id);

COMMENT ON INDEX public.ix_card_printing_external_mapping_trait_trait_id IS
    'Suporta a faceta inversa: dado um Print Trait, encontrar todos os tokens externos que o produzem. Util para auditoria editorial.';

ALTER TABLE public.card_printing_external_mapping_trait ENABLE ROW LEVEL SECURITY;

CREATE POLICY catalog_admin_select
    ON public.card_printing_external_mapping_trait
    FOR SELECT
    USING ((SELECT public.is_admin()));

REVOKE ALL ON public.card_printing_external_mapping_trait FROM anon, authenticated, service_role;
GRANT SELECT ON public.card_printing_external_mapping_trait TO authenticated;
-- Deliberadamente SEM grant ao service_role — ver Query 2182.

COMMIT;

-- ============================================================================
-- Resultado esperado:
--   CREATE TABLE, COMMENT x3, CREATE INDEX, ALTER TABLE, CREATE POLICY,
--   REVOKE, GRANT.
--
-- Como validar:
--   Query 2824 - Validate Card Printing Routing, Secoes S1 e S2.
-- ============================================================================
