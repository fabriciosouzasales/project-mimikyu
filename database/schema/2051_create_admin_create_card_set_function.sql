/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2051 - Create admin_create_card_set() Function
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-07-31

Descrição...:
Cria admin_create_card_set(), função pública SECURITY DEFINER —
única via de cadastro de Card Set (ADR-023, emenda 2026-07-31
"Card Set: cadastro real via UI"). Mesmo padrão de
admin_create_expansion() (Query 2033): sem camada interna
própria, o INSERT acontece diretamente aqui. Diferente de
admin_update_card_set() (Query 2048), que só aceita nome/ordem
de lançamento, esta função precisa cobrir todos os campos
estruturais obrigatórios de card_set — não há valor anterior de
onde herdar set_type/base_set_size/total_set_size.

Regras de Negócio:
- Só um administrador pode chamar esta função (is_admin()).
- expansion_id deve corresponder a uma Expansion existente —
  checado explicitamente antes do INSERT, com mensagem clara
  (antecipa o erro bruto de fk_card_set_expansion).
- code é normalizado para maiúsculas e sem espaços nas pontas
  antes de validar formato (^[A-Z0-9][A-Z0-9._-]*$ — permite
  começar com dígito, diferente de Game/Expansion, mesmo formato
  de ck_card_set_code_format) e duplicidade dentro da mesma
  Expansion (uq_card_set_expansion_code).
- release_order deve ser positivo e único dentro da mesma
  Expansion (uq_card_set_expansion_release_order).
- set_type é normalizado para maiúsculas e deve ser REGULAR,
  SPECIAL ou PROMO (ck_card_set_type).
- base_set_size deve ser positivo; total_set_size deve ser maior
  ou igual a base_set_size (ck_card_set_total_size_valid).
- Quando set_type = PROMO: base_set_size deve ser igual a
  total_set_size (ck_card_set_promo_size) e não pode já existir
  outro Card Set PROMO na mesma Expansion
  (uq_card_set_expansion_promo) — ambos antecipados com mensagem
  administrativa clara antes do erro bruto de constraint.
- release_date é opcional (NULL = data de lançamento ainda não
  confirmada, mesma regra de negócio já registrada na Query 120).
- Toda criação bem-sucedida grava uma linha em
  catalog_admin_action_log (CARD_SET_CREATED) — ação já prevista
  no CHECK da tabela desde a Query 2049 (v1.2), nenhuma alteração
  de schema necessária para esta Query.

Pré-requisitos:
- Query 120 - Create Card Set Table.
- Query 1060 - Create is_admin() Function.
- Query 2010 - Create Catalog Admin Action Log Table (v1.2, com CARD_SET_CREATED).
================================================================
*/

CREATE OR REPLACE FUNCTION public.admin_create_card_set(
    p_expansion_id UUID,
    p_code TEXT,
    p_name TEXT,
    p_set_type TEXT,
    p_release_order INTEGER,
    p_base_set_size INTEGER,
    p_total_set_size INTEGER,
    p_release_date DATE DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_code TEXT;
    v_name TEXT;
    v_set_type TEXT;
    v_id UUID;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'ADMIN_CREATE_CARD_SET_FORBIDDEN: apenas administradores podem cadastrar um Card Set.';
    END IF;

    IF p_expansion_id IS NULL THEN
        RAISE EXCEPTION 'ADMIN_CREATE_CARD_SET_MISSING_EXPANSION: p_expansion_id é obrigatório.';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.expansion WHERE id = p_expansion_id) THEN
        RAISE EXCEPTION 'ADMIN_CREATE_CARD_SET_EXPANSION_NOT_FOUND: nenhuma Expansão encontrada para o id informado (%).', p_expansion_id;
    END IF;

    v_code := upper(btrim(coalesce(p_code, '')));
    v_name := btrim(coalesce(p_name, ''));
    v_set_type := upper(btrim(coalesce(p_set_type, '')));

    IF v_code = '' THEN
        RAISE EXCEPTION 'ADMIN_CREATE_CARD_SET_INVALID_CODE: o código não pode ser vazio.';
    END IF;

    IF v_code !~ '^[A-Z0-9][A-Z0-9._-]*$' THEN
        RAISE EXCEPTION 'ADMIN_CREATE_CARD_SET_INVALID_CODE: o código deve começar com letra ou número e conter apenas letras maiúsculas, números, ponto, hífen e sublinhado.';
    END IF;

    IF v_name = '' THEN
        RAISE EXCEPTION 'ADMIN_CREATE_CARD_SET_INVALID_NAME: o nome não pode ser vazio.';
    END IF;

    IF v_set_type NOT IN ('REGULAR', 'SPECIAL', 'PROMO') THEN
        RAISE EXCEPTION 'ADMIN_CREATE_CARD_SET_INVALID_SET_TYPE: o tipo deve ser REGULAR, SPECIAL ou PROMO.';
    END IF;

    IF p_release_order IS NULL OR p_release_order <= 0 THEN
        RAISE EXCEPTION 'ADMIN_CREATE_CARD_SET_INVALID_RELEASE_ORDER: a ordem de lançamento deve ser um número positivo.';
    END IF;

    IF p_base_set_size IS NULL OR p_base_set_size <= 0 THEN
        RAISE EXCEPTION 'ADMIN_CREATE_CARD_SET_INVALID_BASE_SIZE: a quantidade base deve ser um número positivo.';
    END IF;

    IF p_total_set_size IS NULL OR p_total_set_size < p_base_set_size THEN
        RAISE EXCEPTION 'ADMIN_CREATE_CARD_SET_INVALID_TOTAL_SIZE: a quantidade total deve ser maior ou igual à quantidade base.';
    END IF;

    IF v_set_type = 'PROMO' AND p_base_set_size <> p_total_set_size THEN
        RAISE EXCEPTION 'ADMIN_CREATE_CARD_SET_PROMO_SIZE_MISMATCH: um Card Set do tipo PROMO deve ter quantidade base igual à quantidade total.';
    END IF;

    IF v_set_type = 'PROMO' AND EXISTS (
        SELECT 1 FROM public.card_set WHERE expansion_id = p_expansion_id AND set_type = 'PROMO'
    ) THEN
        RAISE EXCEPTION 'ADMIN_CREATE_CARD_SET_DUPLICATE_PROMO: esta Expansão já possui um Card Set do tipo PROMO.';
    END IF;

    IF EXISTS (SELECT 1 FROM public.card_set WHERE expansion_id = p_expansion_id AND code = v_code) THEN
        RAISE EXCEPTION 'ADMIN_CREATE_CARD_SET_DUPLICATE_CODE: já existe um Card Set com o código % para esta Expansão.', v_code;
    END IF;

    IF EXISTS (SELECT 1 FROM public.card_set WHERE expansion_id = p_expansion_id AND release_order = p_release_order) THEN
        RAISE EXCEPTION 'ADMIN_CREATE_CARD_SET_DUPLICATE_RELEASE_ORDER: já existe um Card Set com a ordem de lançamento % para esta Expansão.', p_release_order;
    END IF;

    INSERT INTO public.card_set (expansion_id, code, name, set_type, release_order, release_date, base_set_size, total_set_size)
        VALUES (p_expansion_id, v_code, v_name, v_set_type, p_release_order, p_release_date, p_base_set_size, p_total_set_size)
        RETURNING id INTO v_id;

    INSERT INTO public.catalog_admin_action_log (actor_id, action, entity_type, entity_id, metadata)
        VALUES (
            auth.uid(), 'CARD_SET_CREATED', 'CARD_SET', v_id,
            jsonb_build_object(
                'expansion_id', p_expansion_id, 'code', v_code, 'name', v_name,
                'set_type', v_set_type, 'release_order', p_release_order,
                'base_set_size', p_base_set_size, 'total_set_size', p_total_set_size,
                'release_date', p_release_date
            )
        );

    RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_create_card_set(UUID, TEXT, TEXT, TEXT, INTEGER, INTEGER, INTEGER, DATE) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_create_card_set(UUID, TEXT, TEXT, TEXT, INTEGER, INTEGER, INTEGER, DATE) TO authenticated;
