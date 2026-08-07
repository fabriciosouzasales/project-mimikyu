/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2115 - Create admin_create_card() Function
Versão......: 1.0
Status......: CANÔNICA — CONFIRMADO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-07

Descrição...:
Cria admin_create_card(), cadastro administrativo de Card via UI
(/catalogo/cartas, botão "Nova Carta") — parte do subciclo Card do
ADR-023 (criação/desativação/reativação; edição já implementada,
Query 2114). Chama internal.write_card() (Query 2030) em modo
CREATE — primeira função pública a fazê-lo fora do fluxo de
importação em lote (admin_confirm_catalog_import(), ADR-024).

Regras de Negócio:
- Auditoria única por operação: internal.write_card() NUNCA grava
  em catalog_admin_action_log (responsabilidade da função pública
  chamadora, ADR-023) — esta função grava CARD_CREATED exatamente
  uma vez, só depois de internal.write_card() retornar com sucesso.
  Ação já prevista no CHECK original da Query 2010, nenhuma
  migration de constraint necessária.
- Consistência de Game validada explicitamente, antes da chamada a
  internal.write_card(): rarity_id e category_id devem pertencer ao
  mesmo Game do card_set informado (derivado via card_set →
  expansion → game_id). trg_card_validate_game_consistency (Query
  141) já bloqueia um INSERT inconsistente na própria tabela, mas
  com um erro genérico de trigger — esta checagem antecipa o mesmo
  problema com uma mensagem administrativa clara, mesmo padrão já
  usado em admin_update_card() (Query 2114).
- collector_number: obrigatório, normalizado por trim (case
  preservado — ao contrário de code de outras entidades, é a
  identificação impressa da carta, não um código interno). Duplicidade
  verificada explicitamente contra Cards ativas E inativas do mesmo
  card_set_id (uq_card_card_set_collector_number vale para as duas —
  ADR-023, "Card: is_active como soft delete real") — nunca confiar
  que um número livre entre as ativas está de fato livre.
- collector_order: obrigatório, positivo, duplicidade verificada
  explicitamente contra Cards ativas E inativas do mesmo card_set_id
  (mesmo raciocínio acima, uq_card_card_set_collector_order).
- rarity_id/category_id: devem existir E pertencer ao Game do
  card_set (ver acima).
- name: obrigatório, não-vazio após trim.
- collector_total: opcional, positivo quando informado (mesma regra
  de admin_update_card()).

Descoberta real durante a execução (mesmo dia): `GRANT EXECUTE ...
TO authenticated` sozinho NÃO revoga o EXECUTE que o PostgreSQL
concede a PUBLIC automaticamente na criação de toda função — `anon`
herda esse grant via PUBLIC. Validação estrutural inicial confirmou
`anon_pode = true` (deveria ser `false`). Corrigido com `REVOKE ALL
... FROM PUBLIC` e `REVOKE ALL ... FROM anon` explícitos, mesmo
padrão já usado em `internal.write_card()` — reexecutada a
validação, `anon_pode = false` confirmado. Gap provavelmente
presente nas demais funções `admin_*` do módulo (nenhuma delas tinha
esse REVOKE explícito até aqui) — sinalizado como pendência de
auditoria retroativa, fora do escopo desta Query.

Pré-requisitos:
- Query 2030 - Create internal.write_card() Function.
- Query 141 - Card Triggers (trg_card_validate_game_consistency).
================================================================
*/

CREATE OR REPLACE FUNCTION public.admin_create_card(
    p_card_set_id UUID,
    p_collector_number TEXT,
    p_collector_total INTEGER,
    p_collector_order INTEGER,
    p_rarity_id UUID,
    p_category_id UUID,
    p_name TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_game_id UUID;
    v_collector_number TEXT;
    v_name TEXT;
    v_card_id UUID;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'ADMIN_CREATE_CARD_FORBIDDEN: apenas administradores podem cadastrar uma Card.';
    END IF;

    IF p_card_set_id IS NULL THEN
        RAISE EXCEPTION 'ADMIN_CREATE_CARD_MISSING_CARD_SET: p_card_set_id é obrigatório.';
    END IF;

    SELECT e.game_id INTO v_game_id
        FROM public.card_set cs
        JOIN public.expansion e ON e.id = cs.expansion_id
        WHERE cs.id = p_card_set_id;

    IF v_game_id IS NULL THEN
        RAISE EXCEPTION 'ADMIN_CREATE_CARD_CARD_SET_NOT_FOUND: nenhuma Coleção encontrada para o id informado (%).', p_card_set_id;
    END IF;

    v_collector_number := btrim(coalesce(p_collector_number, ''));
    IF v_collector_number = '' THEN
        RAISE EXCEPTION 'ADMIN_CREATE_CARD_INVALID_COLLECTOR_NUMBER: o número não pode ser vazio.';
    END IF;

    v_name := btrim(coalesce(p_name, ''));
    IF v_name = '' THEN
        RAISE EXCEPTION 'ADMIN_CREATE_CARD_INVALID_NAME: o nome não pode ser vazio.';
    END IF;

    IF p_collector_total IS NOT NULL AND p_collector_total <= 0 THEN
        RAISE EXCEPTION 'ADMIN_CREATE_CARD_INVALID_COLLECTOR_TOTAL: o total, quando informado, deve ser positivo.';
    END IF;

    IF p_collector_order IS NULL OR p_collector_order <= 0 THEN
        RAISE EXCEPTION 'ADMIN_CREATE_CARD_INVALID_COLLECTOR_ORDER: a ordem editorial deve ser um número positivo.';
    END IF;

    IF p_rarity_id IS NULL OR NOT EXISTS (
        SELECT 1 FROM public.rarity WHERE id = p_rarity_id AND game_id = v_game_id
    ) THEN
        RAISE EXCEPTION 'ADMIN_CREATE_CARD_RARITY_MISMATCH: a Raridade informada não existe ou não pertence ao mesmo Game da Coleção.';
    END IF;

    IF p_category_id IS NULL OR NOT EXISTS (
        SELECT 1 FROM public.card_category WHERE id = p_category_id AND game_id = v_game_id
    ) THEN
        RAISE EXCEPTION 'ADMIN_CREATE_CARD_CATEGORY_MISMATCH: a Categoria informada não existe ou não pertence ao mesmo Game da Coleção.';
    END IF;

    IF EXISTS (
        SELECT 1 FROM public.card
        WHERE card_set_id = p_card_set_id AND collector_number = v_collector_number
    ) THEN
        RAISE EXCEPTION 'ADMIN_CREATE_CARD_DUPLICATE_COLLECTOR_NUMBER: já existe uma Card com o número % nesta Coleção (ativa ou inativa).', v_collector_number;
    END IF;

    IF EXISTS (
        SELECT 1 FROM public.card
        WHERE card_set_id = p_card_set_id AND collector_order = p_collector_order
    ) THEN
        RAISE EXCEPTION 'ADMIN_CREATE_CARD_DUPLICATE_COLLECTOR_ORDER: já existe outra Card com a ordem editorial % nesta Coleção (ativa ou inativa).', p_collector_order;
    END IF;

    -- internal.write_card() NUNCA grava auditoria — responsabilidade
    -- exclusiva desta função, uma única vez, logo abaixo.
    v_card_id := internal.write_card(
        'CREATE', NULL, p_card_set_id, p_rarity_id, p_category_id,
        v_collector_number, p_collector_total, p_collector_order, v_name
    );

    INSERT INTO public.catalog_admin_action_log (actor_id, action, entity_type, entity_id, metadata)
        VALUES (
            auth.uid(), 'CARD_CREATED', 'CARD', v_card_id,
            jsonb_build_object(
                'card_set_id', p_card_set_id, 'collector_number', v_collector_number,
                'collector_total', p_collector_total, 'collector_order', p_collector_order,
                'rarity_id', p_rarity_id, 'category_id', p_category_id, 'name', v_name
            )
        );

    RETURN v_card_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_create_card(UUID, TEXT, INTEGER, INTEGER, UUID, UUID, TEXT) TO authenticated;

REVOKE ALL ON FUNCTION public.admin_create_card(UUID, TEXT, INTEGER, INTEGER, UUID, UUID, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_create_card(UUID, TEXT, INTEGER, INTEGER, UUID, UUID, TEXT) FROM anon;

-- ================================================================
-- Confirmado executado (2026-08-07): definição criada em produção;
-- has_function_privilege() confirmado authenticated=true, anon=false
-- (após correção do REVOKE explícito, ver "Descoberta real" acima).
-- Validação funcional completa (cenários) fica para a Query 2817,
-- ao final do subciclo.
-- ================================================================
