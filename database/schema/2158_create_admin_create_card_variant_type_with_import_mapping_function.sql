/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2158 - Create admin_create_card_variant_type_with_import_mapping() Function
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-15

Descrição...:
Cria admin_create_card_variant_type_with_import_mapping(), Incremento 3
da Governança da Taxonomia de Card Variant Type (ADR-028, revisão 1.2):
"Criar novo tipo + Resolver mapping" dentro de Importar Variantes,
para quando uma linha NEEDS_REVIEW não corresponde a nenhum
card_variant_type já cadastrado. Wrapper fino sobre
admin_create_card_variant_type() (Query 2154) +
admin_resolve_catalog_variant_import_mapping() (Query 2150) — nenhuma
lógica própria de negócio, só orquestra as duas chamadas na mesma
transação (mesmo padrão de admin_create_rarity_with_external_mapping,
Query 2103).

Regras de Negócio:
- is_admin() checado aqui também, apesar de ambas as funções chamadas
  já checarem — mesmo padrão defensivo já usado na Query 2103 (falha
  cedo, sem depender de comportamento transitivo).
- game_id NUNCA é parâmetro — resolvido a partir da própria linha
  (card -> card_set -> expansion -> game), exatamente a mesma
  resolução já usada por admin_resolve_catalog_variant_import_mapping
  (Query 2150). Elimina qualquer possibilidade de o chamador criar um
  Card Variant Type num Game diferente do da linha que originou a
  ação.
- Nunca cria um Card Variant Type automaticamente a partir de dado
  externo — code/name/description/display_order continuam decisão
  explícita do administrador, exatamente os mesmos parâmetros de
  admin_create_card_variant_type(). code/game_id permanecem imutáveis
  após a criação (regra de admin_create_card_variant_type, não
  duplicada aqui).
- is_active nasce true (default da coluna, Query 2152) — o tipo recém-
  criado já é elegível para o próprio mapping resolvido nesta mesma
  chamada e para futuros cadastros/mappings.
- Atomicidade: função plpgsql única, sem BEGIN/COMMIT explícito
  (desnecessário — a função inteira roda dentro da transação da
  chamada RPC). Falha em admin_create_card_variant_type() (código
  duplicado, display_order duplicado, nome vazio) aborta antes de
  qualquer resolução de mapping. Falha em
  admin_resolve_catalog_variant_import_mapping() (combinação já
  mapeada, linha não é mais NEEDS_REVIEW) desfaz também o INSERT do
  tipo recém-criado — nada fica parcialmente persistido.
- Revalidação set-based das linhas compatíveis, mesma regra e mesmo
  escopo (cross-job/cross-Card-Set dentro do mesmo Game+Fonte) da
  Query 2150 — nenhuma lógica nova aqui, só herdada da chamada.
- Nunca reconsulta TCGdex — raw_data já staged é a única fonte lida
  (via admin_resolve_catalog_variant_import_mapping).
- Vintage/Promo/erros continuam sem inferência automática — este
  wrapper não infere nada, só formaliza a decisão explícita do
  administrador.
- Retorna variant_type_id, mapping_id, rows_updated, jobs_affected —
  a UI usa os quatro (destaque do tipo criado + alcance real da
  revalidação, mesmo padrão já usado por
  admin_resolve_catalog_variant_import_mapping sozinha).

Pré-requisitos:
- Query 2150 - Create admin_resolve_catalog_variant_import_mapping() Function.
- Query 2154 - Create admin_create_card_variant_type() Function.
- Query 1060 - Create is_admin() Function.
================================================================
*/

CREATE OR REPLACE FUNCTION public.admin_create_card_variant_type_with_import_mapping(
    p_row_id UUID,
    p_code TEXT,
    p_name TEXT,
    p_description TEXT,
    p_display_order INTEGER
)
RETURNS TABLE (
    variant_type_id UUID,
    mapping_id UUID,
    rows_updated INTEGER,
    jobs_affected INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_row public.catalog_variant_import_row%ROWTYPE;
    v_game_id UUID;
    v_variant_type_id UUID;
    v_mapping_id UUID;
    v_rows_updated INTEGER;
    v_jobs_affected INTEGER;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'ADMIN_CREATE_CARD_VARIANT_TYPE_WITH_IMPORT_MAPPING_FORBIDDEN: apenas administradores podem criar um Card Variant Type com mapeamento.';
    END IF;

    IF p_row_id IS NULL THEN
        RAISE EXCEPTION 'ADMIN_CREATE_CARD_VARIANT_TYPE_WITH_IMPORT_MAPPING_MISSING_ROW: p_row_id é obrigatório.';
    END IF;

    SELECT r.* INTO v_row FROM public.catalog_variant_import_row r WHERE r.id = p_row_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'ADMIN_CREATE_CARD_VARIANT_TYPE_WITH_IMPORT_MAPPING_ROW_NOT_FOUND: nenhuma linha encontrada para o id informado (%).', p_row_id;
    END IF;

    -- game_id resolvido a partir da própria linha (card -> card_set ->
    -- expansion -> game) — mesma regra de
    -- admin_resolve_catalog_variant_import_mapping (Query 2150), nunca
    -- recebido como parâmetro.
    SELECT e.game_id INTO v_game_id
    FROM public.card c
    JOIN public.card_set cs ON cs.id = c.card_set_id
    JOIN public.expansion e ON e.id = cs.expansion_id
    WHERE c.id = v_row.card_id;

    IF v_game_id IS NULL THEN
        RAISE EXCEPTION 'ADMIN_CREATE_CARD_VARIANT_TYPE_WITH_IMPORT_MAPPING_GAME_NOT_FOUND: não foi possível resolver o Game desta linha.';
    END IF;

    v_variant_type_id := public.admin_create_card_variant_type(v_game_id, p_code, p_name, p_description, p_display_order);

    SELECT rm.mapping_id, rm.rows_updated, rm.jobs_affected
        INTO v_mapping_id, v_rows_updated, v_jobs_affected
        FROM public.admin_resolve_catalog_variant_import_mapping(p_row_id, v_variant_type_id) rm;

    RETURN QUERY SELECT v_variant_type_id, v_mapping_id, v_rows_updated, v_jobs_affected;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_create_card_variant_type_with_import_mapping(UUID, TEXT, TEXT, TEXT, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_create_card_variant_type_with_import_mapping(UUID, TEXT, TEXT, TEXT, INTEGER) TO authenticated;

-- ================================================================
-- Confirmado executado (2026-08-15, via execute_sql/MCP do Supabase,
-- projeto qjfutqujxrbzgrtkpgkg), depois de dry-run em BEGIN...ROLLBACK
-- contra dado real (linhas NEEDS_REVIEW de um job STAGED, Pikachu
-- normal+1st-edition-error): chamador não-admin -> FORBIDDEN; admin cria
-- tipo novo (TEST_1ST_EDITION_ERROR) + resolve o mapping da linha na
-- mesma chamada (rows_updated=1, jobs_affected=1), linha vira VALID,
-- tipo nasce is_active=true; atomicidade comprovada — uma segunda
-- tentativa com o mesmo code numa outra linha falha por inteiro
-- (ADMIN_CREATE_CARD_VARIANT_TYPE_DUPLICATE_CODE), sem deixar um
-- segundo card_variant_type de teste criado e sem tocar a segunda
-- linha (permanece NEEDS_REVIEW/PENDING); display_order duplicado
-- também corretamente rejeitado. 8/8 asserções. ROLLBACK — nenhum dado
-- de teste persistido.
-- ================================================================

-- ================================================================
-- Como validar:
-- SELECT routine_name, security_type FROM information_schema.routines
-- WHERE routine_name = 'admin_create_card_variant_type_with_import_mapping';
-- Esperado: security_type = 'DEFINER'.
-- SELECT grantee, privilege_type FROM information_schema.role_routine_grants
-- WHERE routine_name = 'admin_create_card_variant_type_with_import_mapping';
-- Esperado: só 'authenticated' com EXECUTE.
-- ================================================================
