/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2114 - Create admin_update_card() Function
Versão......: 1.1
Status......: CANÔNICA — CONFIRMADO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-07

Descrição...:
Cria admin_update_card(), habilitando a edição administrativa de
Card via UI (/catalogo/cartas, botão de ação rápida no canto
inferior direito de cada carta) — pedido de Fabrício: "Encontrei
duas cartas cadastradas com a raridade errada... possibilitando
editar todas as informações possíveis... incluindo a sua
raridade". Primeira função pública a chamar internal.write_card()
(Query 2030) em modo UPDATE — admin_confirm_catalog_import()
(ADR-024) já a chamava, sempre em modo CREATE. Ver ADR-023, emenda
2026-08-07 ("Card: atualização real via UI").

Regras de Negócio:
- card_set_id e collector_number NUNCA entram na assinatura —
  estruturalmente protegidos (ADR-023, "Campos estruturalmente
  protegidos nunca são alteráveis por atualização"). Sempre
  passados como NULL para internal.write_card(), que levantaria
  INTERNAL_WRITE_CARD_PROTECTED_FIELD se recebesse qualquer um
  dos dois.
- name/collector_total/collector_order/rarity_id/category_id são
  os únicos campos editáveis. collector_total aceita NULL (nem
  toda Card tem denominador); collector_order deve ser positivo e
  único dentro do mesmo Card Set (checagem explícita antes do
  UPDATE, antecipando uq_card_card_set_collector_order com uma
  mensagem administrativa clara).
- rarity_id/category_id validados contra rarity/card_category
  antes do UPDATE — internal.write_card() não faz essa checagem
  (confia no trigger trg_card_validate_game_consistency, que só
  dispara depois do UPDATE já ter sido tentado).
- Grava catalog_admin_action_log (CARD_UPDATED) — ação já prevista
  no CHECK desde a Query 2098 (rodada de Raridade/Mapeamento, mesmo
  dia mais cedo), nenhuma migration de constraint necessária.

Pré-requisitos:
- Query 140/141 - Create Card Table / Triggers.
- Query 2030 - Create internal.write_card() Function.
- Query 2098 - Add Rarity Actions to Catalog Admin Action Log
  (CARD_UPDATED já fazia parte do CHECK original da Query 2010;
  2098 não afeta esta ação, listada aqui por ser o estado mais
  recente confirmado da tabela antes desta Query).

Validação funcional confirmada por Fabrício (2026-08-07): edição
de Card testada via UI (/catalogo/cartas → botão editar → salvar),
sem erros.
================================================================
*/

CREATE OR REPLACE FUNCTION public.admin_update_card(
    p_id UUID,
    p_name TEXT,
    p_collector_total INTEGER,
    p_collector_order INTEGER,
    p_rarity_id UUID,
    p_category_id UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_card_set_id UUID;
    v_name TEXT;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'ADMIN_UPDATE_CARD_FORBIDDEN: apenas administradores podem atualizar uma Card.';
    END IF;

    SELECT card_set_id INTO v_card_set_id FROM public.card WHERE id = p_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'ADMIN_UPDATE_CARD_NOT_FOUND: nenhuma Card encontrada para o id informado (%).', p_id;
    END IF;

    v_name := btrim(coalesce(p_name, ''));
    IF v_name = '' THEN
        RAISE EXCEPTION 'ADMIN_UPDATE_CARD_INVALID_NAME: o nome não pode ser vazio.';
    END IF;

    IF p_collector_total IS NOT NULL AND p_collector_total <= 0 THEN
        RAISE EXCEPTION 'ADMIN_UPDATE_CARD_INVALID_COLLECTOR_TOTAL: o total, quando informado, deve ser positivo.';
    END IF;

    IF p_collector_order IS NULL OR p_collector_order <= 0 THEN
        RAISE EXCEPTION 'ADMIN_UPDATE_CARD_INVALID_COLLECTOR_ORDER: a ordem editorial deve ser um número positivo.';
    END IF;

    IF p_rarity_id IS NULL OR NOT EXISTS (SELECT 1 FROM public.rarity WHERE id = p_rarity_id) THEN
        RAISE EXCEPTION 'ADMIN_UPDATE_CARD_RARITY_NOT_FOUND: selecione uma Raridade válida.';
    END IF;

    IF p_category_id IS NULL OR NOT EXISTS (SELECT 1 FROM public.card_category WHERE id = p_category_id) THEN
        RAISE EXCEPTION 'ADMIN_UPDATE_CARD_CATEGORY_NOT_FOUND: selecione uma Categoria válida.';
    END IF;

    IF EXISTS (
        SELECT 1 FROM public.card
        WHERE card_set_id = v_card_set_id AND collector_order = p_collector_order AND id <> p_id
    ) THEN
        RAISE EXCEPTION 'ADMIN_UPDATE_CARD_DUPLICATE_COLLECTOR_ORDER: já existe outra Card com a ordem editorial % neste Card Set.', p_collector_order;
    END IF;

    -- p_card_set_id/p_collector_number sempre NULL — nunca editáveis por
    -- esta função (ADR-023).
    PERFORM internal.write_card(
        'UPDATE', p_id, NULL, p_rarity_id, p_category_id,
        NULL, p_collector_total, p_collector_order, v_name
    );

    INSERT INTO public.catalog_admin_action_log (actor_id, action, entity_type, entity_id, metadata)
        VALUES (
            auth.uid(), 'CARD_UPDATED', 'CARD', p_id,
            jsonb_build_object(
                'name', v_name, 'collector_total', p_collector_total,
                'collector_order', p_collector_order,
                'rarity_id', p_rarity_id, 'category_id', p_category_id
            )
        );

    RETURN p_id;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_update_card(UUID, TEXT, INTEGER, INTEGER, UUID, UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_update_card(UUID, TEXT, INTEGER, INTEGER, UUID, UUID) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_update_card(UUID, TEXT, INTEGER, INTEGER, UUID, UUID) TO authenticated;

-- ================================================================
-- Confirmado executado e validado funcionalmente (2026-08-07):
-- definição em produção lida via pg_get_functiondef() e conferida
-- idêntica a este arquivo; edição de Card testada via UI sem erros
-- (confirmação verbal de Fabrício).
--
-- v1.1 (2026-08-14, Finding 2 da auditoria de segurança do Catálogo
-- Editorial, Query 2131, CONFIRMADO EXECUTADO): REVOKE ALL FROM
-- PUBLIC/anon adicionados — a função só tinha GRANT EXECUTE TO
-- authenticated, sem nenhum REVOKE explícito; como Postgres concede
-- EXECUTE a PUBLIC por padrão na criação, o grant implícito a anon
-- nunca havia sido removido (Advisor de segurança do Supabase:
-- anon_security_definer_function_executable). Mesma classe de bug já
-- corrigida em admin_create_card (Query 2115) e prevenida desde o
-- início em admin_update_card_set (2048)/admin_confirm_catalog_import
-- (2082). Só GRANT/REVOKE — corpo/assinatura da função inalterados
-- (confirmado via pg_get_functiondef() idêntico a este arquivo antes e
-- depois). has_function_privilege() confirmou anon=false/
-- authenticated=true após a Query; reexecução do Advisor confirmou o
-- finding removido da lista.
-- ================================================================
