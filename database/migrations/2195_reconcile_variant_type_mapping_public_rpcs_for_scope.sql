/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2195 - Reconcile Variant Type Mapping PUBLIC RPCs
              for Source-Set Scope
Versão......: 1.0
Status......: MIGRATION / CONFIRMADO EXECUTADO / LIVE
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-14
Executado...: 2026-09-14, via apply_migration (MCP Supabase), projeto
              qjfutqujxrbzgrtkpgkg. Ledger: 20260914025027 /
              2195_reconcile_variant_type_mapping_public_rpcs_for_scope
Reclassif..: 2026-09-18, BULK-STP-01-CANONICAL-RECONCILIATION-IMPLEMENTATION-01
Canônica....: dobrada em database/schema/2150_create_admin_resolve_catalog_
              variant_import_mapping_function.sql v2.0 (GLOBAL + SOURCE_SET)
Mandato.....: CARD-VARIANTS — EDITORIAL-CONVERGENCE-16 /
              SOURCE-SET-SCOPED-FOUNDATION / GATE-A-STAGING-01
              (§5 — BLOCKER DE STAGING: estratégia de assinatura)

Descrição...:
Fecha a estratégia de assinatura pública. Duas funções, nomes
distintos, aridades distintas, ZERO overload.

--------------------------------------------------------------
ASSINATURA ATUAL, CATALOGADA ANTES DE QUALQUER DECISÃO
--------------------------------------------------------------
Medido em pg_proc/pg_get_function_identity_arguments em 2026-09-14:

  public.admin_resolve_catalog_variant_import_mapping(
      p_row_id uuid, p_variant_type_id uuid)
  RETURNS TABLE(mapping_id uuid, rows_updated integer, jobs_affected integer)
  SECURITY DEFINER · search_path="" · ACL: authenticated, postgres
  · PUBLIC sem EXECUTE

--------------------------------------------------------------
ESTRATÉGIA ESCOLHIDA — A + B + C do §5
--------------------------------------------------------------
A. `admin_resolve_catalog_variant_import_mapping` PERMANECE com a
   assinatura EXATA e o retorno EXATO. É `CREATE OR REPLACE`, não
   `DROP`/`CREATE` — o OID e as ACLs são preservados. O corpo passa
   a delegar ao worker com escopo GLOBAL.

B. `admin_resolve_catalog_variant_import_mapping_for_set` é NOVA e
   explícita. SOURCE_SET exige chamar OUTRA função — opt-in
   impossível de acontecer por acidente.

C. As duas delegam ao MESMO worker interno (Query 2193), que por
   sua vez usa o MESMO contrato de decisão (Query 2192) que o
   preview (Query 2194).

O que isso prova, ponto a ponto contra o §5:

  - zero função antiga órfã .... a antiga não é dropada; é
                                 reescrita no lugar.
  - zero overload ambíguo ...... nomes diferentes. Nenhuma
                                 sobrecarga por aridade ou por
                                 parâmetro com DEFAULT.
  - ACL correta em todas ....... REVOKE PUBLIC/anon + GRANT
                                 authenticated nas três (execute
                                 global, execute scoped, preview).
  - clientes atuais funcionam .. assinatura, retorno, códigos de
                                 erro e mensagens preservados
                                 literalmente. Os 4 arquivos do
                                 frontend que chamam esta RPC não
                                 precisam mudar para continuar
                                 funcionando.
  - scoped exige opt-in ........ função separada, nome explícito.

--------------------------------------------------------------
ATOR
--------------------------------------------------------------
`public.is_admin()` é, literalmente,
`EXISTS (SELECT 1 FROM public.admin_user WHERE id = auth.uid())`
— confirmado no catálogo em 2026-09-14.

Logo `is_admin()` TRUE implica `auth.uid()` ∈ admin_user, e passar
`auth.uid()` como `p_actor_id` para o worker (que exige ator
administrador cadastrado) NÃO pode introduzir uma recusa nova em
caminho que hoje funciona. Verificado de propósito: era o único
ponto onde a delegação poderia quebrar compatibilidade.

Pré-requisitos:
- Query 2192 - contrato de decisão.
- Query 2193 - worker.
================================================================
*/

BEGIN;

-- =============================================================
-- A. CAMINHO GLOBAL — ASSINATURA E RETORNO INTACTOS
--
-- CREATE OR REPLACE preserva OID e ACL. Nenhum DROP.
-- =============================================================

CREATE OR REPLACE FUNCTION public.admin_resolve_catalog_variant_import_mapping(
    p_row_id          UUID,
    p_variant_type_id UUID
)
RETURNS TABLE(
    mapping_id     UUID,
    rows_updated   INTEGER,
    jobs_affected  INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $global$
DECLARE
    v RECORD;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'ADMIN_RESOLVE_CATALOG_VARIANT_IMPORT_MAPPING_FORBIDDEN: apenas administradores podem resolver um mapeamento de variante.';
    END IF;

    IF p_row_id IS NULL OR p_variant_type_id IS NULL THEN
        RAISE EXCEPTION 'ADMIN_RESOLVE_CATALOG_VARIANT_IMPORT_MAPPING_MISSING_IDS: p_row_id e p_variant_type_id sao obrigatorios.';
    END IF;

    -- Delegação. Todos os guards herdados (NOT_NEEDS_REVIEW,
    -- VARIANT_TYPE_MISMATCH, PRINTING_UNRESOLVED, DUPLICATE) são
    -- avaliados pelo contrato único e re-emitidos pelo worker com
    -- as MESMAS mensagens de erro de antes.
    SELECT * INTO v
      FROM internal.apply_variant_type_mapping(
               (select auth.uid()), p_row_id, p_variant_type_id, 'GLOBAL');

    -- Retorno idêntico ao histórico: 3 colunas, mesmos nomes.
    -- `rows_updated` continua significando "linhas revalidadas".
    RETURN QUERY SELECT v.mapping_id, v.rows_reclassified, v.jobs_affected;
END;
$global$;

COMMENT ON FUNCTION public.admin_resolve_catalog_variant_import_mapping(UUID, UUID) IS
    'Cria mapping GLOBAL de Card Variant Type a partir de uma linha de staging NEEDS_REVIEW. Assinatura, retorno e mensagens de erro PRESERVADOS da versao anterior (Query 2150). Passou a delegar ao worker unico internal.apply_variant_type_mapping(..., GLOBAL) - Query 2193. Para escopo por source-set use admin_resolve_catalog_variant_import_mapping_for_set().';

-- =============================================================
-- B. CAMINHO SOURCE_SET — NOVO, EXPLÍCITO, OPT-IN
--
-- O admin NÃO digita external_set_id. O escopo é DERIVADO do
-- Card Set do job da linha de origem, via card_set_external_reference
-- (decisão 4 + §15 do mandato).
-- =============================================================

CREATE OR REPLACE FUNCTION public.admin_resolve_catalog_variant_import_mapping_for_set(
    p_row_id          UUID,
    p_variant_type_id UUID
)
RETURNS TABLE(
    mapping_id          UUID,
    scope_kind          TEXT,
    external_set_id     TEXT,
    rows_total          INTEGER,
    rows_reclassified   INTEGER,
    rows_still_pending  INTEGER,
    jobs_affected       INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $scoped$
DECLARE
    v RECORD;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'ADMIN_RESOLVE_VARIANT_IMPORT_MAPPING_FOR_SET_FORBIDDEN: apenas administradores podem resolver um mapeamento de variante.';
    END IF;

    IF p_row_id IS NULL OR p_variant_type_id IS NULL THEN
        RAISE EXCEPTION 'ADMIN_RESOLVE_VARIANT_IMPORT_MAPPING_FOR_SET_MISSING_IDS: p_row_id e p_variant_type_id sao obrigatorios.';
    END IF;

    SELECT * INTO v
      FROM internal.apply_variant_type_mapping(
               (select auth.uid()), p_row_id, p_variant_type_id, 'SOURCE_SET');

    RETURN QUERY SELECT v.mapping_id, v.scope_kind, v.external_set_id,
                        v.rows_total, v.rows_reclassified,
                        v.rows_still_pending, v.jobs_affected;
END;
$scoped$;

COMMENT ON FUNCTION public.admin_resolve_catalog_variant_import_mapping_for_set(UUID, UUID) IS
    'Cria mapping SOURCE_SET_SCOPED de Card Variant Type. Opt-in EXPLICITO: e uma funcao separada, nunca um parametro da RPC global. O external_set_id NAO e digitado - e DERIVADO do Card Set do job da linha de origem via card_set_external_reference ATIVA. Delega ao worker unico da Query 2193. Coexiste com o mapping global; removendo a linha, o comportamento global e restaurado.';

-- =============================================================
-- C. ACL — least-privilege nas duas
-- =============================================================

REVOKE ALL ON FUNCTION public.admin_resolve_catalog_variant_import_mapping(UUID, UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_resolve_catalog_variant_import_mapping(UUID, UUID) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_resolve_catalog_variant_import_mapping(UUID, UUID) TO authenticated;

REVOKE ALL ON FUNCTION public.admin_resolve_catalog_variant_import_mapping_for_set(UUID, UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_resolve_catalog_variant_import_mapping_for_set(UUID, UUID) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_resolve_catalog_variant_import_mapping_for_set(UUID, UUID) TO authenticated;

COMMIT;

-- ================================================================
-- CONFIRMADO EXECUTADO em 2026-09-14 (GATE-B-EXECUTION-01). Cópia mantida em
-- proposals/ como evidência histórica do ciclo.
-- ================================================================
