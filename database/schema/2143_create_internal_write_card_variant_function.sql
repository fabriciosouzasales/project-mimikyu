/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2143 - Create internal.write_card_variant() Function
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-15

Descrição...:
Cria internal.write_card_variant() — camada de escrita canônica e
isolada para public.card_variant, mesmo papel de
internal.write_card() (Query 2030) para public.card. Único caminho
pelo qual card_variant é fisicamente gravada a partir do fluxo de
importação (Incremento 3 do bloco Card Variant, ADR-028). Chamada
só por public.admin_confirm_catalog_variant_import() (Query 2145),
nunca diretamente por um cliente.

Regras de Negócio:
- Schema internal (não public) + REVOKE ALL de PUBLIC/anon/
  authenticated: só alcançável por outra função SECURITY DEFINER do
  mesmo owner, nunca um contrato RPC público — mesmo padrão de
  internal.write_card().
- p_mode = 'CREATE': único modo implementado nesta rodada. Insere
  (card_id, variant_type_id, variant_order) — is_default NUNCA é
  incluído no INSERT, nasce sempre FALSE pelo default da própria
  coluna (Query 160), inclusive para a primeira variante de uma
  Card. Tornar uma variante padrão continua sendo decisão editorial
  explícita, fora do escopo de qualquer confirmação automática.
- p_mode = 'UPDATE': deliberadamente NÃO implementado — levanta
  exceção explícita. Não existe, nesta rodada, nenhum cenário em que
  uma Card Variant já existente deva ser sobrescrita pela
  importação: uma variante existe ou não existe para um
  (card_id, variant_type_id); não há conteúdo interno para divergir
  e atualizar (diferença estrutural real frente a card, que tem
  name/rarity_id/category_id/collector_total mutáveis). O
  parâmetro p_variant_id já existe na assinatura para não exigir
  uma quebra de contrato se uma necessidade real de atualização
  surgir no futuro.
- p_variant_order é sempre calculado pelo chamador (Query 2145) como
  o próximo inteiro livre para aquele card_id — nunca lido de
  raw_data/normalized_data/TCGdex. Esta função só valida que veio
  preenchido e positivo; não recalcula.

Pré-requisitos:
- Query 160 - Create Card Variant Table.
================================================================
*/

CREATE OR REPLACE FUNCTION internal.write_card_variant(
    p_mode TEXT,
    p_variant_id UUID,
    p_card_id UUID,
    p_variant_type_id UUID,
    p_variant_order INTEGER
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

    INSERT INTO public.card_variant (card_id, variant_type_id, variant_order)
    VALUES (p_card_id, p_variant_type_id, p_variant_order)
    RETURNING id INTO v_variant_id;

    RETURN v_variant_id;
END;
$$;

REVOKE ALL ON FUNCTION internal.write_card_variant(TEXT, UUID, UUID, UUID, INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION internal.write_card_variant(TEXT, UUID, UUID, UUID, INTEGER) FROM anon;
REVOKE ALL ON FUNCTION internal.write_card_variant(TEXT, UUID, UUID, UUID, INTEGER) FROM authenticated;

-- ================================================================
-- Confirmado executado (2026-08-15, via execute_sql/MCP do Supabase,
-- projeto qjfutqujxrbzgrtkpgkg), depois de dry-run em BEGIN...ROLLBACK
-- que exercitou CREATE (variante nova, is_default FALSE, variant_order
-- correto), o bloqueio de UPDATE, e todas as validações de parâmetro
-- obrigatório. role_routine_grants confirma só 'postgres' (owner) com
-- EXECUTE — nenhum grant para anon/authenticated, conforme desenhado.
-- ================================================================

-- ================================================================
-- Como validar:
-- SELECT p.proname, p.prosecdef, p.proconfig
-- FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
-- WHERE n.nspname = 'internal' AND p.proname = 'write_card_variant';
-- Esperado: prosecdef = true, proconfig contém 'search_path='.
-- SELECT grantee, privilege_type FROM information_schema.role_routine_grants
-- WHERE routine_name = 'write_card_variant';
-- Esperado: só 'postgres' (owner) — nenhum grant para anon/authenticated.
-- ================================================================
