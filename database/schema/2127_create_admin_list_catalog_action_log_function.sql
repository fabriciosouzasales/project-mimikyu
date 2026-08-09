/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2127 - Create admin_list_catalog_action_log() Function
Versão......: 1.0
Status......: CANÔNICA — CONFIRMADO EXECUTADO E VALIDADO FUNCIONALMENTE
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-09

Descrição...:
Function pública SECURITY DEFINER que lista public.catalog_admin_
action_log paginada e filtrada inteiramente server-side — primeira
via de leitura desta tabela (RLS habilitado, zero políticas desde a
Query 2010). Alimenta a tabela de /catalogo/log-atualizacoes (Data |
Quem | Entidade | Registro | Ação | Detalhes), mesmo padrão
estrutural de admin_list_users() (Query 1061, ADR-021): is_admin()
com RAISE EXCEPTION (não lista vazia) para não-administrador,
p_limit/p_offset com teto controlado no servidor, count(*) OVER()
para total_count na mesma query (sem round-trip extra).

Regras de Negócio:
- actor_label resolvido via LEFT JOIN a public.user_profile
  (display_name com fallback username) — NULL quando actor_id é
  nulo (ex. svc_apply_catalog_import_revalidation chamada sem
  p_actor_id).
- entity_label resolvido por CASE l.entity_type: primeiro tenta a
  chave de metadata mais específica daquele tipo (name/
  card_set_name/external_value, conforme o que cada function de
  escrita já grava), com fallback via LEFT JOIN condicional à
  tabela viva correspondente (game/expansion/card_set/card/
  catalog_import_job→card_set/rarity/rarity_external_mapping) —
  necessário sobretudo para linhas gravadas antes das correções de
  metadata das Queries 2080/2082/2106/2122 (2026-08-09) e para
  CARD_DEACTIVATED/CARD_REACTIVATED (metadata vazio por desenho,
  Query 2116/2117). Nenhuma das 7 tabelas de fallback tem cardinalidade
  alta o suficiente para o JOIN condicional pesar de forma real no
  volume atual.
- category resolvida via internal.catalog_admin_action_category()
  (Query 2126) — fonte única, nunca reclassificada aqui.
- Filtros (p_entity_type/p_action/p_actor_id) são AND entre si;
  p_search é OR contra entity_label/actor_label/action (ILIKE),
  aplicado sobre os valores já resolvidos pela CTE `resolved`, não
  contra as colunas cruas da tabela.
- v_limit sempre restrito a [1, 100], independente do valor
  recebido — mesmo padrão de admin_list_users().

Pré-requisitos:
- Query 2010 - Create Catalog Admin Action Log Table.
- Query 2126 - Create internal.catalog_admin_action_category() Function.
- Query 1060 - Create is_admin() Function.
================================================================
*/

CREATE OR REPLACE FUNCTION public.admin_list_catalog_action_log(
    p_search TEXT DEFAULT NULL,
    p_entity_type TEXT DEFAULT NULL,
    p_action TEXT DEFAULT NULL,
    p_actor_id UUID DEFAULT NULL,
    p_limit INT DEFAULT 20,
    p_offset INT DEFAULT 0
)
RETURNS TABLE (
    id UUID,
    created_at TIMESTAMPTZ,
    actor_id UUID,
    actor_label TEXT,
    entity_type TEXT,
    entity_id UUID,
    entity_label TEXT,
    action TEXT,
    category TEXT,
    metadata JSONB,
    total_count BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_limit INT;
    v_offset INT;
    v_search TEXT;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'ADMIN_LIST_CATALOG_ACTION_LOG_FORBIDDEN: acesso restrito a administradores.';
    END IF;

    v_limit := LEAST(GREATEST(COALESCE(p_limit, 20), 1), 100);
    v_offset := GREATEST(COALESCE(p_offset, 0), 0);
    v_search := NULLIF(BTRIM(p_search), '');

    RETURN QUERY
    WITH resolved AS (
        SELECT
            l.id,
            l.created_at,
            l.actor_id,
            COALESCE(up.display_name, up.username) AS actor_label,
            l.entity_type,
            l.entity_id,
            CASE l.entity_type
                WHEN 'GAME' THEN COALESCE(l.metadata->>'name', g.name, l.entity_id::text)
                WHEN 'EXPANSION' THEN COALESCE(l.metadata->>'name', e.name, l.entity_id::text)
                WHEN 'CARD_SET' THEN COALESCE(l.metadata->>'name', l.metadata->>'card_set_name', cs.name, l.entity_id::text)
                WHEN 'CARD' THEN COALESCE(l.metadata->>'name', c.name, l.entity_id::text)
                WHEN 'CATALOG_IMPORT_JOB' THEN COALESCE(l.metadata->>'card_set_name', job_cs.name, l.entity_id::text)
                WHEN 'RARITY' THEN COALESCE(l.metadata->>'name', rar.name, l.entity_id::text)
                WHEN 'RARITY_EXTERNAL_MAPPING' THEN COALESCE(l.metadata->>'external_value', rem.external_value, l.entity_id::text)
                ELSE l.entity_id::text
            END AS entity_label,
            l.action,
            internal.catalog_admin_action_category(l.action) AS category,
            l.metadata
        FROM public.catalog_admin_action_log l
        LEFT JOIN public.user_profile up ON up.id = l.actor_id
        LEFT JOIN public.game g ON l.entity_type = 'GAME' AND g.id = l.entity_id
        LEFT JOIN public.expansion e ON l.entity_type = 'EXPANSION' AND e.id = l.entity_id
        LEFT JOIN public.card_set cs ON l.entity_type = 'CARD_SET' AND cs.id = l.entity_id
        LEFT JOIN public.card c ON l.entity_type = 'CARD' AND c.id = l.entity_id
        LEFT JOIN public.catalog_import_job job ON l.entity_type = 'CATALOG_IMPORT_JOB' AND job.id = l.entity_id
        LEFT JOIN public.card_set job_cs ON job_cs.id = job.card_set_id
        LEFT JOIN public.rarity rar ON l.entity_type = 'RARITY' AND rar.id = l.entity_id
        LEFT JOIN public.rarity_external_mapping rem ON l.entity_type = 'RARITY_EXTERNAL_MAPPING' AND rem.id = l.entity_id
    )
    SELECT
        r.id, r.created_at, r.actor_id, r.actor_label,
        r.entity_type, r.entity_id, r.entity_label, r.action, r.category, r.metadata,
        count(*) OVER() AS total_count
    FROM resolved r
    WHERE (p_entity_type IS NULL OR r.entity_type = p_entity_type)
      AND (p_action IS NULL OR r.action = p_action)
      AND (p_actor_id IS NULL OR r.actor_id = p_actor_id)
      AND (
          v_search IS NULL
          OR r.entity_label ILIKE '%' || v_search || '%'
          OR r.actor_label ILIKE '%' || v_search || '%'
          OR r.action ILIKE '%' || v_search || '%'
      )
    ORDER BY r.created_at DESC
    LIMIT v_limit
    OFFSET v_offset;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_list_catalog_action_log(TEXT, TEXT, TEXT, UUID, INT, INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_list_catalog_action_log(TEXT, TEXT, TEXT, UUID, INT, INT) TO authenticated;

-- ================================================================
-- Resultado esperado: "Success. No rows returned".
--
-- Como validar (impersonação + ROLLBACK, mesma técnica da Query 2122):
-- BEGIN;
-- SELECT set_config(
--     'request.jwt.claims',
--     json_build_object('sub', (SELECT id::text FROM public.admin_user LIMIT 1))::text,
--     true
-- );
-- SELECT * FROM public.admin_list_catalog_action_log(p_limit => 5);
-- ROLLBACK;
-- ================================================================
--
-- CONFIRMADO EXECUTADO E VALIDADO FUNCIONALMENTE (2026-08-09): a
-- validação acima devolveu as 5 linhas mais recentes, entity_label
-- resolvido corretamente até para linhas anteriores à correção de
-- metadata (via JOIN de segurança: "Forças Temporais", "Evoluções
-- em Paldea", "151", "Escuridão Incandescente"), category = OUTRAS
-- para CATALOG_IMPORT_ROWS_REVALIDATED/CATALOG_IMPORT_CONFIRMED
-- (conforme mapa aprovado), total_count consistente em todas as
-- linhas. Segunda revisão independente (persona ECC database/
-- security-reviewer) sinalizou que 4 dos 7 entity_type dependiam só
-- de metadata->>'name' sem JOIN de segurança — corrigido antes desta
-- execução, todos os 7 tipos agora têm fallback.
-- ================================================================
