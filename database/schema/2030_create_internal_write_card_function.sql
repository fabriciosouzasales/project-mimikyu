/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2030 - Create internal.write_card() Function
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-07-26

Descrição...:
Cria internal.write_card(), a camada canônica única de persistência
de Card, reutilizada por admin_create_card()/admin_update_card()
(Queries 2037/2038, ainda não escritas) e, em ADR-024, por
admin_confirm_catalog_import(). Não é um contrato RPC público — ver
ADR-023, seção "Camada interna canônica, isolada de qualquer
contrato RPC público", e STD-001 v1.17 §9.

Descoberta de implementação: a consistência de Game (Card Set/
Rarity/Card Category no mesmo Game) e updated_at já são garantidos
por trigger existente (trg_card_validate_game_consistency,
trg_card_set_updated_at — Query 141), independentemente de quem
faz o INSERT/UPDATE em public.card. Esta função não duplica essa
validação — a "validação de FK" que ADR-023 atribui a esta camada
já é satisfeita por construção: se card_set_id/rarity_id/
category_id não existirem ou pertencerem a Games diferentes, o
próprio trigger BEFORE recusa a operação com uma mensagem clara,
antes de qualquer constraint de FK bruta ser avaliada.

Regras de Negócio:
- p_mode distingue CREATE de UPDATE — função única, nunca duas
  funções internas separadas (evita duplicar a proteção de campos
  sensíveis em dois lugares).
- Modo CREATE: p_card_id deve ser NULL (não se aceita um id
  sugerido); p_card_set_id e p_collector_number são obrigatórios.
- Modo UPDATE: p_card_id é obrigatório; p_card_set_id e
  p_collector_number devem ser NULL — se o chamador informar
  qualquer um dos dois, a função levanta exceção. Nunca ignora
  silenciosamente um valor divergente (ADR-023, campos
  estruturalmente protegidos nunca são alteráveis por atualização).
- Semântica de substituição integral no UPDATE: rarity_id,
  category_id, collector_total, collector_order e name são sempre
  substituídos pelo valor informado — o chamador (admin_update_card,
  e por trás dele o formulário) deve enviar o estado completo atual
  dos campos editáveis, não apenas o que mudou. Evita a ambiguidade
  de usar NULL como sentinela de "não alterar" num campo (
  collector_total) que também aceita NULL como valor real.
- is_active nunca é tocado por esta função — pertence exclusivamente
  a admin_deactivate_card()/admin_reactivate_card() (Queries
  2039/2040), que não passam por esta camada.
- GET DIAGNOSTICS ... ROW_COUNT confirma o efeito real do UPDATE —
  nunca assume sucesso apenas porque a chamada não retornou erro
  (mesmo padrão de admin_set_card_set_logo()).
- SET search_path = '' e toda referência qualificada por schema
  (public.card) — nunca um nome ambíguo.
- EXECUTE revogado de PUBLIC, anon e authenticated: só é chamável
  por outra função SECURITY DEFINER do mesmo owner (o owner tem
  EXECUTE implícito sobre seus próprios objetos — nenhum GRANT
  adicional necessário para chamadas internal-to-internal).

Pré-requisitos:
- Query 140/141 - Create Card Table / Triggers.
- Query 2020 - Add is_active to Card (não referenciada por esta
  função, mas parte da mesma fundação do módulo).
================================================================
*/

CREATE OR REPLACE FUNCTION internal.write_card(
    p_mode TEXT,
    p_card_id UUID,
    p_card_set_id UUID,
    p_rarity_id UUID,
    p_category_id UUID,
    p_collector_number TEXT,
    p_collector_total INTEGER,
    p_collector_order INTEGER,
    p_name TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_card_id UUID;
    v_rows_affected INTEGER;
BEGIN
    IF p_mode NOT IN ('CREATE', 'UPDATE') THEN
        RAISE EXCEPTION 'INTERNAL_WRITE_CARD_INVALID_MODE: p_mode deve ser CREATE ou UPDATE (recebido: %).', p_mode;
    END IF;

    IF p_mode = 'CREATE' THEN
        IF p_card_id IS NOT NULL THEN
            RAISE EXCEPTION 'INTERNAL_WRITE_CARD_UNEXPECTED_ID: p_card_id não deve ser informado em modo CREATE.';
        END IF;

        IF p_card_set_id IS NULL THEN
            RAISE EXCEPTION 'INTERNAL_WRITE_CARD_MISSING_CARD_SET: p_card_set_id é obrigatório em modo CREATE.';
        END IF;

        IF p_collector_number IS NULL THEN
            RAISE EXCEPTION 'INTERNAL_WRITE_CARD_MISSING_COLLECTOR_NUMBER: p_collector_number é obrigatório em modo CREATE.';
        END IF;

        INSERT INTO public.card (
            card_set_id, rarity_id, category_id,
            collector_number, collector_total, collector_order, name
        ) VALUES (
            p_card_set_id, p_rarity_id, p_category_id,
            p_collector_number, p_collector_total, p_collector_order, p_name
        )
        RETURNING id INTO v_card_id;

        RETURN v_card_id;
    END IF;

    -- p_mode = 'UPDATE'
    IF p_card_id IS NULL THEN
        RAISE EXCEPTION 'INTERNAL_WRITE_CARD_MISSING_ID: p_card_id é obrigatório em modo UPDATE.';
    END IF;

    IF p_card_set_id IS NOT NULL OR p_collector_number IS NOT NULL THEN
        RAISE EXCEPTION 'INTERNAL_WRITE_CARD_PROTECTED_FIELD: card_set_id e collector_number nunca são alteráveis por atualização (ADR-023).';
    END IF;

    UPDATE public.card
        SET rarity_id = p_rarity_id,
            category_id = p_category_id,
            collector_total = p_collector_total,
            collector_order = p_collector_order,
            name = p_name
        WHERE id = p_card_id;

    GET DIAGNOSTICS v_rows_affected = ROW_COUNT;

    IF v_rows_affected <> 1 THEN
        RAISE EXCEPTION 'INTERNAL_WRITE_CARD_NOT_FOUND: nenhuma Card encontrada para o id informado (%).', p_card_id;
    END IF;

    RETURN p_card_id;
END;
$$;

REVOKE ALL ON FUNCTION internal.write_card(
    TEXT, UUID, UUID, UUID, UUID, TEXT, INTEGER, INTEGER, TEXT
) FROM PUBLIC;

REVOKE ALL ON FUNCTION internal.write_card(
    TEXT, UUID, UUID, UUID, UUID, TEXT, INTEGER, INTEGER, TEXT
) FROM anon;

REVOKE ALL ON FUNCTION internal.write_card(
    TEXT, UUID, UUID, UUID, UUID, TEXT, INTEGER, INTEGER, TEXT
) FROM authenticated;
