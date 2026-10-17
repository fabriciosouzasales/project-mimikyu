/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5154 - Expansão do Card Set em itens de B2 (fonte única)
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO / LIVE / PROMOVIDO (2026-10-16,
              ledger 20261016235536). Aplicado via apply_migration do
              Supabase, que envolve a migration em transacao propria
              (BEGIN/COMMIT deste arquivo omitidos no envio); corpo
              conferido byte a byte com o LIVE (md5 de prosrc).
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-16 (BULK04-B2-IMPLEMENTATION-PROPOSAL-01)
Pré-req.....: 160 (índice único parcial uq_card_variant_one_default_per_card),
              2268 (ck_card_variant_default_active).
Decisões....: Q3 (uma Physical Card por Card ativo, na variante padrão),
              Q4 (Set inteiro, sem descontar o que o usuário já possui),
              Q5 (um único language_id), Q9 (fonte única).

O que faz
  Para um Card Set e um idioma, devolve:
    o_items                  — array JSON de itens no formato de B1
                               {card_variant_id, language_id, quantity: 1},
                               um por Card ATIVO que tenha variante
                               padrão, ordenado por card_id;
    o_cards_without_default  — card_id (texto, ordenado) dos Cards ATIVOS
                               do Set sem nenhuma variante padrão.
  Cards inativos não entram em nenhuma das duas listas.

  Usada pelos três consumidores de B2: o fingerprint (5156), a
  confirmação (5157) e o Preview (5158). Assim a expansão existe uma
  única vez.

Garantias de domínio aproveitadas
  - No máximo uma variante padrão por Card (índice único parcial de
    160): o JOIN nunca duplica Card.
  - Variante padrão é sempre ativa (CHECK de 2268). Mesmo assim a
    confirmação revalida is_active pelo helper 5153 (passo 6.2b).

Não valida existência do Card Set nem do idioma: isso é decisão dos
chamadores (issues no Preview, exceção na confirmação).

Segurança
  SECURITY INVOKER, VOLATILE (lê o estado AGORA, depois dos locks da
  confirmação), search_path vazio, owner postgres. EXECUTE revogado de
  PUBLIC, anon, authenticated e service_role.
================================================================
*/

BEGIN;

CREATE FUNCTION public.bulk_expand_card_set(
    p_card_set_id               UUID,
    p_language_id               UUID,
    OUT o_items                 JSONB,
    OUT o_cards_without_default TEXT[]
)
LANGUAGE plpgsql
SECURITY INVOKER
VOLATILE
SET search_path = ''
AS $$
BEGIN
    SELECT COALESCE(jsonb_agg(
               jsonb_build_object(
                   'card_variant_id', cv.id::text,
                   'language_id',     p_language_id::text,
                   'quantity',        1
               )
               ORDER BY ca.id
           ), '[]'::jsonb)
      INTO o_items
      FROM public.card ca
      JOIN public.card_variant cv
        ON cv.card_id = ca.id
       AND cv.is_default
     WHERE ca.card_set_id = p_card_set_id
       AND ca.is_active;

    SELECT array_agg(ca.id::text ORDER BY ca.id::text)
      INTO o_cards_without_default
      FROM public.card ca
     WHERE ca.card_set_id = p_card_set_id
       AND ca.is_active
       AND NOT EXISTS (
           SELECT 1
             FROM public.card_variant cv
            WHERE cv.card_id = ca.id
              AND cv.is_default
       );
END;
$$;

COMMENT ON FUNCTION public.bulk_expand_card_set(UUID, UUID) IS
    'FONTE UNICA da expansao de B2 (REGISTER_CARD_SET): um item {card_variant_id da variante padrao, language_id, quantity 1} por Card ATIVO do Card Set, ordenado por card_id, e a lista dos Cards ativos sem variante padrao. Set inteiro, sem descontar o que o usuario ja possui (Q4). Nao valida existencia de Card Set nem de idioma. VOLATILE, SECURITY INVOKER, somente leitura. Helper INTERNO: EXECUTE revogado de PUBLIC/anon/authenticated/service_role.';

REVOKE EXECUTE ON FUNCTION public.bulk_expand_card_set(UUID, UUID)
    FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
