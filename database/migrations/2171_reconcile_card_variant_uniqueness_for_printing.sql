/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 2171 - Reconcile Card Variant Uniqueness for Printing
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO / LIVE
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-12
Mandato.....: CARD-VARIANTS — PRINTING-MODEL-STAGING-01 — GATE-A-01 (§14)

-------------------------------------------------------------------------------
EXECUÇÃO CONFIRMADA — 2026-09-12
-------------------------------------------------------------------------------
Executado via apply_migration no projeto Supabase qjfutqujxrbzgrtkpgkg.
Ordem de aplicacao: 2165 -> 2166 -> 2167 -> 2168 -> 2169 -> 2170 -> 2171.
Todas as sete aplicadas sem erro. Pos-execucao confirmado no LIVE:
    uq_card_variant_card_type REMOVIDA;
    uq_card_variant_card_type_no_printing e uq_card_variant_card_type_printing
    criadas com os predicados corretos;
    uq_card_variant_card_order, uq_card_variant_id_card,
    uq_card_variant_one_default_per_card, ck_card_variant_order_positive e as
    FKs preservadas; 7002 linhas, 927 defaults, zero duplicidade.
Estado final validado integralmente pela Query 2823 v1.2:
    12 PASS / 0 FAIL / 0 NOT PROVEN, zero residuo.
O SQL executavel permanece INTOCADO desde a execucao.
-------------------------------------------------------------------------------

Descrição resumida:
Troca a unicidade de card_variant para suportar o eixo de impressão, sem
UUID sentinela e sem reescrever nenhuma linha.

-------------------------------------------------------------------------------
OBJETO REAL AUDITADO NO LIVE (2026-09-12) — NAO ASSUMIDO
-------------------------------------------------------------------------------
    SELECT conname, contype, pg_get_constraintdef(oid)
      FROM pg_constraint WHERE conrelid = 'public.card_variant'::regclass;

    uq_card_variant_card_type   contype = 'u'   UNIQUE (card_id, variant_type_id)

E uma UNIQUE CONSTRAINT, NAO um indice solto. Portanto a remocao correta e
ALTER TABLE ... DROP CONSTRAINT — um DROP INDEX falharia.

Demais objetos da tabela, todos PRESERVADOS por esta Query:
    card_variant_pkey                      PRIMARY KEY (id)
    uq_card_variant_card_order             UNIQUE (card_id, variant_order)
    uq_card_variant_id_card                UNIQUE (id, card_id)   <- alvo de FK composta
    uq_card_variant_one_default_per_card   UNIQUE (card_id) WHERE is_default
    ck_card_variant_order_positive         CHECK (variant_order > 0)
    fk_card_variant_card, fk_card_variant_variant_type
    ix_card_variant_card_id, ix_card_variant_variant_type_id

-------------------------------------------------------------------------------
NOVO CONTRATO
-------------------------------------------------------------------------------
A. printing_profile_id IS NULL      -> UNIQUE (card_id, variant_type_id)
B. printing_profile_id IS NOT NULL  -> UNIQUE (card_id, variant_type_id,
                                               printing_profile_id)

Dois indices unicos PARCIAIS, preferencia aprovada no mandato. Sem UUID
sentinela: NULL nao precisa de valor magico porque o predicado do indice
ja separa os dois universos, e eles nao se sobrepoem — a uniao cobre a
tabela inteira e a intersecao e vazia.

POR QUE OS 7.002 CONTINUAM VALIDOS:
todos tem printing_profile_id NULL (a coluna nasceu NULL na Query 2170 e
nenhum UPDATE foi feito). Logo todos caem no indice A, que e literalmente
a mesma regra que ja respeitavam. Nenhuma violacao e possivel.

CONSEQUENCIA SEMANTICA:
a mesma Card com o mesmo acabamento passa a poder existir mais de uma vez,
desde que com Perfis de Impressao DIFERENTES. E exatamente o que BASE1
exige: STANDARD+Shadowless e STANDARD+Unlimited sao duas variantes reais
da mesma Card.

JANELA: o DROP e os dois CREATE estao na mesma transacao. Nao existe
instante commitado sem unicidade.

Regras de Negócio:
- Nenhuma linha e lida, escrita ou movida.
- Nenhum id, variant_order ou is_default e alterado.
- Todas as demais constraints e indices permanecem.

Pré-requisitos:
- Query 2170 - Add printing_profile_id to Card Variant (a coluna precisa
  existir antes dos indices parciais).
===============================================================================
*/

BEGIN;

ALTER TABLE public.card_variant
    DROP CONSTRAINT uq_card_variant_card_type;

CREATE UNIQUE INDEX uq_card_variant_card_type_no_printing
    ON public.card_variant (card_id, variant_type_id)
    WHERE printing_profile_id IS NULL;

COMMENT ON INDEX public.uq_card_variant_card_type_no_printing IS
    'Sucede a UNIQUE CONSTRAINT uq_card_variant_card_type. Preserva literalmente a regra antiga para o universo sem perfil de impressão declarado — onde estão as 7.002 variantes legadas.';

CREATE UNIQUE INDEX uq_card_variant_card_type_printing
    ON public.card_variant (card_id, variant_type_id, printing_profile_id)
    WHERE printing_profile_id IS NOT NULL;

COMMENT ON INDEX public.uq_card_variant_card_type_printing IS
    'Mesma Card, mesmo acabamento e mesmo Perfil de Impressão não podem se repetir. Perfis diferentes são variantes distintas — é o que BASE1 exige.';

COMMIT;

-- ============================================================================
-- Resultado esperado:
--   ALTER TABLE (DROP CONSTRAINT), CREATE INDEX x2, COMMENT x2.
--   card_variant = 7.002 linhas, inalteradas.
--
-- Rollback conceitual:
--   DROP INDEX dos dois parciais + ALTER TABLE ADD CONSTRAINT
--   uq_card_variant_card_type UNIQUE (card_id, variant_type_id).
--   Só é possível enquanto nenhuma linha tiver printing_profile_id NOT NULL.
--
-- Como validar:
--   Query 2823 - Validate Card Printing Model, Secoes 1, 3 e 4.
-- ============================================================================
