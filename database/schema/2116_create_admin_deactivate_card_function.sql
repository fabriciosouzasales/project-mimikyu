/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2116 - Create admin_deactivate_card() Function
Versão......: 1.0
Status......: CANÔNICA — CONFIRMADO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-07

Descrição...:
Cria admin_deactivate_card(), desativação administrativa de Card
via UI — soft delete real e irrestrito (ADR-023, "Card: is_active
como soft delete real"), não condicionado à ausência de
dependentes. card_variant/card_asset/card_external_reference nunca
são tocados — permanecem exatamente como estavam, preservando
histórico por completo.

Regras de Negócio:
- Não usa internal.write_card() — is_active está fora do escopo
  daquela camada por decisão explícita (Query 2030: "is_active
  nunca é tocado por esta função"). UPDATE direto em public.card,
  mesmo padrão de admin_set_card_set_logo() (função pública simples,
  sem camada internal própria, quando a operação é só um campo).
- Erro claro se a Card já estiver inativa
  (ADMIN_DEACTIVATE_CARD_ALREADY_INACTIVE) — evita um UPDATE sem
  efeito e uma linha de auditoria sem sentido (a Card já estava
  desativada por outra chamada).
- GET DIAGNOSTICS ... ROW_COUNT confirma o efeito real do UPDATE —
  nunca assume sucesso apenas porque a chamada não retornou erro.
- Grava catalog_admin_action_log (CARD_DEACTIVATED) — ação já
  prevista no CHECK original da Query 2010, nenhuma migration de
  constraint necessária.
- REVOKE ALL de PUBLIC/anon explícito desde a criação (gap
  descoberto na Query 2115, corrigido aqui desde o início — validado
  correto na primeira tentativa, sem necessidade de correção
  posterior).

Pré-requisitos:
- Query 2020 - Add is_active to Card.
- Query 2010 - Create Catalog Admin Action Log Table.
================================================================
*/

CREATE OR REPLACE FUNCTION public.admin_deactivate_card(p_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_rows_affected INTEGER;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'ADMIN_DEACTIVATE_CARD_FORBIDDEN: apenas administradores podem desativar uma Card.';
    END IF;

    IF p_id IS NULL THEN
        RAISE EXCEPTION 'ADMIN_DEACTIVATE_CARD_MISSING_ID: p_id é obrigatório.';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.card WHERE id = p_id) THEN
        RAISE EXCEPTION 'ADMIN_DEACTIVATE_CARD_NOT_FOUND: nenhuma Card encontrada para o id informado (%).', p_id;
    END IF;

    IF EXISTS (SELECT 1 FROM public.card WHERE id = p_id AND is_active = false) THEN
        RAISE EXCEPTION 'ADMIN_DEACTIVATE_CARD_ALREADY_INACTIVE: esta Card já está desativada.';
    END IF;

    UPDATE public.card
        SET is_active = false
        WHERE id = p_id;

    GET DIAGNOSTICS v_rows_affected = ROW_COUNT;

    IF v_rows_affected <> 1 THEN
        RAISE EXCEPTION 'ADMIN_DEACTIVATE_CARD_NOT_FOUND: nenhuma Card encontrada para o id informado (%).', p_id;
    END IF;

    INSERT INTO public.catalog_admin_action_log (actor_id, action, entity_type, entity_id, metadata)
        VALUES (auth.uid(), 'CARD_DEACTIVATED', 'CARD', p_id, jsonb_build_object());

    RETURN p_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_deactivate_card(UUID) TO authenticated;

REVOKE ALL ON FUNCTION public.admin_deactivate_card(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_deactivate_card(UUID) FROM anon;

-- ================================================================
-- Confirmado executado (2026-08-07): has_function_privilege()
-- confirmado authenticated=true, anon=false, correto desde a
-- primeira execução. Validação funcional completa fica para a
-- Query 2817, ao final do subciclo.
-- ================================================================
