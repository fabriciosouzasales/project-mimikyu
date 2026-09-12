/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 2165 - Create Card Printing Trait Table
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO / LIVE
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-12
Mandato.....: CARD-VARIANTS — PRINTING-MODEL-STAGING-01 — GATE-A-01
Decisão.....: HYBRID-PRINTING-MODEL — MODELING-GATE-A-01 (Modelo C2 ratificado)

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
Cria public.card_printing_trait — o ATOMO do dominio PRINTING / Impressao.

Descrição:
Um Print Trait e uma caracteristica INDIVISIVEL de impressao de uma Card:
tiragem (UNLIMITED, FIRST_EDITION), caracteristica de chapa (SHADOWLESS,
COPYRIGHT_1999_2000) ou caracteristica de arte impressa (RED_CHEEK).

Print Trait NAO e acabamento. Acabamento (normal/holo/reverse, foils,
stamps de evento) continua em card_variant_type, intocado. O dominio
PRINTING existe exatamente porque edicao e acabamento sao ortogonais e o
modelo atual so tem um eixo (card_variant.variant_type_id).

Por que "PRINTING" e nao "EDITION":
- EDITION so seria correto para FIRST_EDITION e UNLIMITED;
- COPYRIGHT_1999_2000 e linha de copyright, nao edicao;
- RED_CHEEK e caracteristica de arte impressa, nao tiragem.
Forcar "edicao" sobre os cinco repetiria, um nivel abaixo, o mesmo erro
conceitual do Modelo A (tipo composto) que foi rejeitado.

Hierarquia:
Game
  └── Card Printing Trait

Regras de Negócio:
- Cada Print Trait pertence a exatamente um Game.
- code unico dentro do Game; display_order unico dentro do Game.
- code em MAIUSCULAS/numeros/underscore (mesmo padrao de card_variant_type).
- name nao pode ser vazio; description opcional mas nao vazia.
- is_active permite desativar sem apagar (mesma semantica da 2152).
- Exclusao de Game referenciado e impedida.
- RLS habilitado; leitura admin-only, coerente com o catalogo editorial.

Pré-requisitos:
- Query 000 - Infrastructure.
- Tabela public.game.
- Função public.set_updated_at().
===============================================================================
*/

BEGIN;

CREATE TABLE public.card_printing_trait (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    game_id UUID NOT NULL,

    code VARCHAR(50) NOT NULL,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    display_order INTEGER NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_card_printing_trait_game
        FOREIGN KEY (game_id)
        REFERENCES public.game (id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    CONSTRAINT uq_card_printing_trait_game_code
        UNIQUE (game_id, code),

    CONSTRAINT uq_card_printing_trait_game_display_order
        UNIQUE (game_id, display_order),

    -- Necessario para a FK composta de card_printing_profile_trait, que e
    -- o mecanismo estrutural de same-Game (ver Query 2167).
    CONSTRAINT uq_card_printing_trait_id_game
        UNIQUE (id, game_id),

    CONSTRAINT ck_card_printing_trait_code_format
        CHECK (code ~ '^[A-Z][A-Z0-9_]*$'),

    CONSTRAINT ck_card_printing_trait_name_not_blank
        CHECK (btrim(name) <> ''),

    CONSTRAINT ck_card_printing_trait_description_not_blank
        CHECK (description IS NULL OR btrim(description) <> ''),

    CONSTRAINT ck_card_printing_trait_display_order_positive
        CHECK (display_order > 0)
);

COMMENT ON TABLE public.card_printing_trait IS
    'Atomo do dominio PRINTING: caracteristica indivisivel de impressao de uma Card (tiragem, chapa ou arte impressa). Nao e acabamento — acabamento vive em card_variant_type.';

COMMENT ON COLUMN public.card_printing_trait.code IS
    'Codigo tecnico canonico em ingles, unico dentro do Game. Nunca usado como chave de composicao.';

COMMENT ON COLUMN public.card_printing_trait.name IS
    'Nome de exibicao em pt-BR. Nunca usado como chave.';

COMMENT ON COLUMN public.card_printing_trait.is_active IS
    'Permite retirar o trait da oferta sem apagar historico. Trait inativo nao impede leitura de Profiles que ja o usam.';

CREATE INDEX ix_card_printing_trait_game_id
    ON public.card_printing_trait (game_id);

ALTER TABLE public.card_printing_trait ENABLE ROW LEVEL SECURITY;

CREATE POLICY catalog_admin_select
    ON public.card_printing_trait
    FOR SELECT
    USING ((SELECT public.is_admin()));

REVOKE ALL ON public.card_printing_trait FROM anon, authenticated, service_role;
GRANT SELECT ON public.card_printing_trait TO authenticated;

DROP TRIGGER IF EXISTS trg_card_printing_trait_set_updated_at
    ON public.card_printing_trait;

CREATE TRIGGER trg_card_printing_trait_set_updated_at
BEFORE UPDATE ON public.card_printing_trait
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

COMMIT;

-- ============================================================================
-- Resultado esperado:
--   CREATE TABLE, COMMENT x4, CREATE INDEX, ALTER TABLE, CREATE POLICY,
--   REVOKE, GRANT, DROP TRIGGER, CREATE TRIGGER.
--
-- Como validar:
--   Query 2823 - Validate Card Printing Model, Secao 1 (SCHEMA).
-- ============================================================================
