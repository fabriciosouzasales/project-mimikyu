/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5156 - preview_fingerprint de B2 (REGISTER_CARD_SET)
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO / LIVE / PROMOVIDO (2026-10-16,
              ledger 20261016235645). Aplicado via apply_migration do
              Supabase, que envolve a migration em transacao propria
              (BEGIN/COMMIT deste arquivo omitidos no envio); corpo
              conferido byte a byte com o LIVE (md5 de prosrc).
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-16 (BULK04-B2-IMPLEMENTATION-PROPOSAL-01)
Pré-req.....: 5147 (bulk_request_hash), 5149 na versão de 5152, 5154.
Decisão.....: Q8 — função de fingerprint própria; reaproveita 5149 por
              inteiro.

Estado hasheado
  {
    operation:              'REGISTER_CARD_SET',
    card_set_id,
    card_set_exists,        -- o Card Set existe AGORA
    language_id,
    cards_without_default,  -- Cards ativos sem variante padrão (5154)
    b1: preview_fingerprint_register_physical_cards(
          itens expandidos (5154), collection_id, storage_container_id)
  }
  fingerprint = bulk_request_hash('PREVIEW:REGISTER_CARD_SET', estado)

  O componente b1 é o fingerprint de 5149 sobre a expansão: Inventory,
  Collection (updated_at, lifecycle, mode, Game, Reference), Storage
  (updated_at) e o catálogo resolvido com is_active. Nada disso é lido
  uma segunda vez aqui.

  Qualquer mudança entre Preview e confirmação muda o fingerprint e a
  confirmação cai em PREVIEW_STALE: Card ativado/desativado, Card novo,
  troca de variante padrão, Card que perde a padrão, Card Set apagado,
  idioma ou destino diferente.

  O rótulo 'PREVIEW:REGISTER_CARD_SET' é distinto do de B1
  ('PREVIEW:REGISTER_PHYSICAL_CARDS'): um token de B1 nunca é aceito em
  B2, e vice-versa.

Exceções herdadas de 5149 (authentication required / inventory,
collection e storage not found or not owned) não acontecem no caminho
limpo do Preview, e na confirmação o 5148 já as levantou antes.

Segurança
  SECURITY INVOKER, VOLATILE, search_path vazio, owner postgres.
  EXECUTE revogado de PUBLIC, anon, authenticated e service_role —
  mesma matriz de 5149.
================================================================
*/

BEGIN;

CREATE FUNCTION public.preview_fingerprint_register_card_set(
    p_card_set_id          UUID,
    p_language_id          UUID,
    p_collection_id        UUID DEFAULT NULL,
    p_storage_container_id UUID DEFAULT NULL
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY INVOKER
VOLATILE
SET search_path = ''
AS $$
DECLARE
    v_exp   RECORD;
    v_state JSONB;
BEGIN
    SELECT e.o_items, e.o_cards_without_default
      INTO v_exp
      FROM public.bulk_expand_card_set(p_card_set_id, p_language_id) AS e;

    v_state := jsonb_build_object(
        'operation',             'REGISTER_CARD_SET',
        'card_set_id',           p_card_set_id::text,
        'card_set_exists',       EXISTS (SELECT 1 FROM public.card_set cs
                                          WHERE cs.id = p_card_set_id),
        'language_id',           p_language_id::text,
        'cards_without_default', COALESCE(to_jsonb(v_exp.o_cards_without_default),
                                          '[]'::jsonb),
        'b1',                    public.preview_fingerprint_register_physical_cards(
                                     v_exp.o_items,
                                     p_collection_id,
                                     p_storage_container_id
                                 )
    );

    RETURN public.bulk_request_hash('PREVIEW:REGISTER_CARD_SET', v_state);
END;
$$;

COMMENT ON FUNCTION public.preview_fingerprint_register_card_set(UUID, UUID, UUID, UUID) IS
    'FONTE UNICA do preview_fingerprint de B2 (REGISTER_CARD_SET). Hash de {card_set_id, card_set_exists, language_id, cards_without_default, b1 = fingerprint de 5149 sobre a expansao de 5154} com rotulo PREVIEW:REGISTER_CARD_SET, distinto do de B1. VOLATILE, SECURITY INVOKER, somente leitura. Helper INTERNO: EXECUTE revogado de PUBLIC/anon/authenticated/service_role.';

REVOKE EXECUTE ON FUNCTION public.preview_fingerprint_register_card_set(UUID, UUID, UUID, UUID)
    FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
