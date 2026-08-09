/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2128 - Create admin_get_catalog_action_log_weekly_summary() Function
Versão......: 1.0
Status......: CANÔNICA — CONFIRMADO EXECUTADO E VALIDADO FUNCIONALMENTE
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-09

Descrição...:
Function pública SECURITY DEFINER que agrega public.catalog_admin_
action_log por semana ISO (segunda a domingo, via date_trunc('week',
...)) e categoria de negócio (internal.catalog_admin_action_category(),
Query 2126), restrita às últimas 12 semanas — alimenta os 3 gráficos
do topo de /catalogo/log-atualizacoes (Cadastro/Alteração/Exclusão).
Server-side por decisão explícita: agregar client-side sobre uma
única página da listagem (Query 2127) sub-contaria qualquer semana
com mais eventos que o tamanho de página.

Regras de Negócio:
- Janela fixa de 12 semanas (decisão de Fabrício, 2026-08-09) —
  date_trunc('week', now()) - INTERVAL '11 weeks' cobre a semana
  atual mais as 11 anteriores, sempre as mesmas 12, nunca "todo o
  histórico". Semanas sem nenhum evento numa categoria simplesmente
  não aparecem no resultado — o frontend (LogAtualizacoesResumo)
  completa com zero as combinações semana×categoria ausentes.
- category = 'OUTRAS' é explicitamente excluída do resultado (WHERE
  ... IN ('CADASTRO', 'ALTERACAO', 'EXCLUSAO')) — só as 3 categorias
  com gráfico próprio importam aqui; a listagem completa (incluindo
  Outras) continua na tabela da Query 2127.

Pré-requisitos:
- Query 2010 - Create Catalog Admin Action Log Table.
- Query 2126 - Create internal.catalog_admin_action_category() Function.
- Query 1060 - Create is_admin() Function.
================================================================
*/

CREATE OR REPLACE FUNCTION public.admin_get_catalog_action_log_weekly_summary()
RETURNS TABLE (
    week_start DATE,
    category TEXT,
    total_count BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'ADMIN_GET_CATALOG_ACTION_LOG_WEEKLY_SUMMARY_FORBIDDEN: acesso restrito a administradores.';
    END IF;

    RETURN QUERY
    SELECT
        date_trunc('week', l.created_at)::date AS week_start,
        internal.catalog_admin_action_category(l.action) AS category,
        count(*) AS total_count
    FROM public.catalog_admin_action_log l
    WHERE l.created_at >= date_trunc('week', now()) - INTERVAL '11 weeks'
      AND internal.catalog_admin_action_category(l.action) IN ('CADASTRO', 'ALTERACAO', 'EXCLUSAO')
    GROUP BY 1, 2
    ORDER BY 1;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_get_catalog_action_log_weekly_summary() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_get_catalog_action_log_weekly_summary() TO authenticated;

-- ================================================================
-- Resultado esperado: "Success. No rows returned".
--
-- Como validar (impersonação + ROLLBACK, mesma técnica da Query 2127):
-- BEGIN;
-- SELECT set_config(
--     'request.jwt.claims',
--     json_build_object('sub', (SELECT id::text FROM public.admin_user LIMIT 1))::text,
--     true
-- );
-- SELECT * FROM public.admin_get_catalog_action_log_weekly_summary();
-- ROLLBACK;
-- ================================================================
--
-- CONFIRMADO EXECUTADO E VALIDADO FUNCIONALMENTE (2026-08-09): a
-- validação acima devolveu 7 linhas reais (3 semanas com dado:
-- 20/07, 27/07, 03/08, cada uma com 1-3 categorias presentes),
-- nenhuma linha com category fora de CADASTRO/ALTERACAO/EXCLUSAO.
-- ================================================================
