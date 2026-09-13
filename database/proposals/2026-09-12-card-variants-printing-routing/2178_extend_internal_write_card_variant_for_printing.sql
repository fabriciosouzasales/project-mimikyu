/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 2178 - Extend internal.write_card_variant() for Printing
Versão......: 1.0
Status......: PROPOSTA — NÃO EXECUTADA
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-12
Mandato.....: CARD-VARIANTS — PRINTING-ROUTING — STAGING-GATE-A-01 (§18)

Descrição resumida:
Adiciona p_printing_profile_id a internal.write_card_variant(), a unica
rotina que grava em public.card_variant.

-------------------------------------------------------------------------------
ASSINATURA NOVA — E POR QUE A ANTIGA E REMOVIDA
-------------------------------------------------------------------------------
Antes:  (p_mode, p_variant_id, p_card_id, p_variant_type_id, p_variant_order)
Depois: (p_mode, p_variant_id, p_card_id, p_variant_type_id, p_variant_order,
         p_printing_profile_id)

O parametro novo tem DEFAULT NULL, entao a chamada antiga de 5 argumentos
continua valida — mas a assinatura de 5 argumentos e explicitamente
DROPADA no fim desta Query.

Motivo: se as duas coexistissem, `internal.write_card_variant(..., NULL)`
ficaria AMBIGUO entre a versao de 5 e a de 6 argumentos, e o Postgres
resolveria por regras de coercao que ninguem quer auditar num caminho de
escrita de catalogo. Uma unica assinatura, sempre.

O unico caller e a Query 2179 (confirm), adaptada na mesma leva.

-------------------------------------------------------------------------------
NULL CONTINUA SIGNIFICANDO EXATAMENTE UMA COISA
-------------------------------------------------------------------------------
p_printing_profile_id NULL = "sem perfil de impressão declarado".
Nao e Unlimited, nao e padrao, nao e desconhecido, nao e erro.

A coluna card_variant.printing_profile_id ja e NULLABLE (Query 2170) e o
trigger de same-Game (mesma Query) retorna cedo quando ela e NULL — o
caminho sem perfil continua com custo zero.

Regras de Negócio:
- Modo UPDATE permanece DESABILITADO, como na 2143.
- Nenhuma validacao de same-Game aqui: e responsabilidade do trigger
  trg_card_variant_printing_profile_game (Query 2170). Duplicar seria
  criar duas fontes de verdade para a mesma invariante.
- Nenhuma criacao automatica de Print Profile. Jamais.
- REVOKE de PUBLIC/anon/authenticated preservado.

Pré-requisitos:
- Query 2143 - internal.write_card_variant() (versao de 5 argumentos).
- Query 2170 - printing_profile_id em card_variant + guard same-Game.
- Query 2171 - dois indices parciais de unicidade.
===============================================================================
*/

BEGIN;

CREATE OR REPLACE FUNCTION internal.write_card_variant(
    p_mode TEXT,
    p_variant_id UUID,
    p_card_id UUID,
    p_variant_type_id UUID,
    p_variant_order INTEGER,
    p_printing_profile_id UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_variant_id UUID;
BEGIN
    IF p_mode NOT IN ('CREATE', 'UPDATE') THEN
        RAISE EXCEPTION 'INTERNAL_WRITE_CARD_VARIANT_INVALID_MODE: p_mode deve ser CREATE ou UPDATE (recebido: %).', p_mode;
    END IF;

    IF p_mode = 'UPDATE' THEN
        RAISE EXCEPTION 'INTERNAL_WRITE_CARD_VARIANT_UPDATE_NOT_SUPPORTED: nenhum fluxo atual atualiza uma Card Variant existente — ela é tratada como UNCHANGED. Parâmetro reservado para uma necessidade futura ainda não desenhada.';
    END IF;

    -- p_mode = 'CREATE'
    IF p_variant_id IS NOT NULL THEN
        RAISE EXCEPTION 'INTERNAL_WRITE_CARD_VARIANT_UNEXPECTED_ID: p_variant_id não deve ser informado em modo CREATE.';
    END IF;
    IF p_card_id IS NULL THEN
        RAISE EXCEPTION 'INTERNAL_WRITE_CARD_VARIANT_MISSING_CARD: p_card_id é obrigatório em modo CREATE.';
    END IF;
    IF p_variant_type_id IS NULL THEN
        RAISE EXCEPTION 'INTERNAL_WRITE_CARD_VARIANT_MISSING_TYPE: p_variant_type_id é obrigatório em modo CREATE.';
    END IF;
    IF p_variant_order IS NULL OR p_variant_order <= 0 THEN
        RAISE EXCEPTION 'INTERNAL_WRITE_CARD_VARIANT_INVALID_ORDER: p_variant_order deve ser um inteiro positivo (recebido: %).', p_variant_order;
    END IF;

    -- Se um perfil foi informado, ele precisa existir. Same-Game NAO e
    -- checado aqui de proposito: o trigger da Query 2170 e a autoridade.
    IF p_printing_profile_id IS NOT NULL
       AND NOT EXISTS (
           SELECT 1 FROM public.card_printing_profile p WHERE p.id = p_printing_profile_id
       ) THEN
        RAISE EXCEPTION 'INTERNAL_WRITE_CARD_VARIANT_PRINTING_PROFILE_NOT_FOUND: Perfil de Impressão % não encontrado.', p_printing_profile_id;
    END IF;

    INSERT INTO public.card_variant (card_id, variant_type_id, variant_order, printing_profile_id)
    VALUES (p_card_id, p_variant_type_id, p_variant_order, p_printing_profile_id)
    RETURNING id INTO v_variant_id;

    RETURN v_variant_id;
END;
$$;

REVOKE ALL ON FUNCTION internal.write_card_variant(TEXT, UUID, UUID, UUID, INTEGER, UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION internal.write_card_variant(TEXT, UUID, UUID, UUID, INTEGER, UUID) FROM anon;
REVOKE ALL ON FUNCTION internal.write_card_variant(TEXT, UUID, UUID, UUID, INTEGER, UUID) FROM authenticated;

-- Elimina a ambiguidade de overload. A partir daqui existe UMA assinatura.
DROP FUNCTION IF EXISTS internal.write_card_variant(TEXT, UUID, UUID, UUID, INTEGER);

COMMIT;

-- ============================================================================
-- Resultado esperado:
--   CREATE FUNCTION (6 args), REVOKE x3, DROP FUNCTION (5 args).
--   Depois desta Query, pg_proc tem EXATAMENTE UMA
--   internal.write_card_variant.
--
-- Como validar:
--   Query 2824 - Validate Card Printing Routing, Secao S12.
-- ============================================================================
