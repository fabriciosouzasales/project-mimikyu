/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2150 - Create admin_resolve_catalog_variant_import_mapping() Function
Versão......: 2.0
Status......: CANÔNICA — CONFIRMADO EXECUTADO / LIVE / RECONCILIADA
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-15

Descrição...:
Esta Query canoniza as DUAS RPCs públicas do mesmo contrato de
resolução de mapeamento de Card Variant Type, ambas SECURITY
DEFINER, ambas partindo de uma linha NEEDS_REVIEW de
catalog_variant_import_row (Query 2138):

  A. admin_resolve_catalog_variant_import_mapping(row, type)
     -> escopo GLOBAL (external_set_id NULL). Assinatura, retorno e
        mensagens de erro preservados literalmente desde a v1.0.

  B. admin_resolve_catalog_variant_import_mapping_for_set(row, type)
     -> escopo SOURCE_SET. É OPT-IN EXPLÍCITO: uma RPC própria, e
        não um parâmetro da RPC global. Quem quer escopo restrito
        precisa dizer isso escolhendo a função — nunca por engano,
        nunca por default.

--------------------------------------------------------------
DELEGAÇÃO — ONDE A REGRA REALMENTE VIVE
--------------------------------------------------------------
NENHUMA das duas contém a lógica de resolução. As duas resolvem a
identidade da sessão (auth.uid()) e delegam ao WORKER ÚNICO
internal.apply_variant_type_mapping() (Query 2193), passando
'GLOBAL' ou 'SOURCE_SET' como scope_kind. O worker cria o mapping
em card_variant_type_external_mapping (Query 2140 v2.0) e propaga
a revalidação na MESMA transação, reemitindo os mesmos códigos de
erro de antes (NOT_NEEDS_REVIEW, VARIANT_TYPE_MISMATCH,
PRINTING_UNRESOLVED, DUPLICATE, SCOPE_MISMATCH).

Isso é uma mudança de estado, não de contrato: até a v1.0 a
resolução era relacional inline, inteira dentro desta função. Ela
NÃO é mais — descrever assim ensinaria um contrato que não existe
mais no banco.

O external_set_id do caminho SOURCE_SET é DERIVADO do contrato
canônico — internal.resolve_variant_mapping_scope() sobre a
card_set_external_reference ativa da linha de origem —, jamais
informado livremente pelo chamador. Divergência entre o escopo
derivado e o declarado é fail-closed (SCOPE_MISMATCH).

--------------------------------------------------------------
ALCANCE DA REVALIDAÇÃO
--------------------------------------------------------------
Diferença deliberada frente à revalidação de raridade: o mapeamento
recém-criado é canônico para Game+Fonte+combinação (mais o Card Set,
no caminho SOURCE_SET) — não apenas para o job que originou a ação
(decisão explícita de Fabrício, 2026-08-15). Por isso a revalidação
é cross-job/cross-Card Set dentro do mesmo Game+Fonte, não restrita
ao job_id da linha original: resolver holo+cosmos->COSMOS_HOLO uma
única vez destrava automaticamente qualquer outro staging já
existente com a mesma combinação. Mesmo espírito de
admin_create_rarity_external_mapping() (Query 2101), mas com
revalidação embutida — lá ela é feita por uma Edge Function
separada, revalidate-catalog-import-rows, porque depende de lógica
adicional em TypeScript.

Regras de Negócio:
*(As regras abaixo descrevem o CONTRATO do conjunto — as duas RPCs
públicas mais o worker. Desde a v2.0 a IMPLEMENTAÇÃO de quase todas
elas vive em internal.apply_variant_type_mapping() e no read
contract da Query 2192 v2.0, não no corpo destas funções; o
contrato observável pelo chamador não mudou.)*
- Só um administrador pode chamar esta função (is_admin()).
- Só aceita linhas com validation_status = 'NEEDS_REVIEW' —
  resolver uma linha já VALID não faz sentido (já tem mapeamento).
- game_id é resolvido a partir da própria linha (card -> card_set ->
  expansion -> game), nunca recebido como parâmetro — elimina a
  possibilidade de o chamador informar um Game divergente do real.
  asset_source_id é resolvido a partir de catalog_variant_import_job
  .source (hoje sempre 'TCGDEX') -> asset_source.code.
- p_variant_type_id deve pertencer ao mesmo game_id resolvido acima
  (ADMIN_RESOLVE_CATALOG_VARIANT_IMPORT_MAPPING_VARIANT_TYPE_MISMATCH)
  — nunca aceita silenciosamente um cruzamento entre Games. Esta
  função NUNCA cria um card_variant_type novo — só associa a um já
  existente (fora de escopo: CRUD de card_variant_type é incremento
  futuro).
- type/foil/subtype/stamp são extraídos de raw_data (preservado
  integralmente, nunca reinterpretado) e normalizados exatamente
  pela mesma disciplina de quem grava a seed/processador (Query
  2140 v1.1): normalize_external_catalog_value() nos três campos de
  texto; stamp normalizado elemento a elemento e ORDENADO, tratando
  a combinação como conjunto, não sequência.
- Verificação explícita de duplicidade antes do INSERT, com erro
  dedicado — mesmo padrão de admin_create_rarity_external_mapping
  (Query 2101). Desde a v2.0 a checagem é contra o índice único
  PARCIAL correspondente ao escopo pedido: ..._combo_global no
  caminho GLOBAL, ..._combo_scoped no caminho SOURCE_SET (Query
  2140 v2.0). O índice único da v1.0
  (uq_card_variant_type_external_mapping_combo) não existe mais.
- Revalidação set-based, um único UPDATE (sem loop, sem N+1):
  atualiza normalized_data.variant_type_id e validation_status =
  'VALID' em toda catalog_variant_import_row cuja combinação
  normalizada bate com a recém-mapeada, restrita a:
  (a) mesmo game_id (via job.card_set_id -> expansion.game_id) e
      mesmo asset_source_id (via job.source);
  (b) job.status = 'STAGED' — "job ainda revisável". Um job só
      permanece STAGED enquanto tiver alguma linha com decision_
      status = 'PENDING' (admin_confirm_catalog_variant_import,
      Query 2145, força o status para STAGED sempre que houver
      decision_pending_rows > 0) — logo esta condição já é, por
      construção, equivalente a "ainda tem linha pendente de
      decisão", mas é mantida explícita por defesa em profundidade;
  (c) row.decision_status = 'PENDING' — deliberado: uma linha
      NEEDS_REVIEW já REJECTED/SKIPPED teve uma decisão humana
      final registrada; não é silenciosamente reescrita para VALID
      só porque um mapeamento surgiu depois (o rótulo de decisão já
      resolveu o destino dela, independente da validação).
  match_status NUNCA é tocado aqui — admin_confirm_catalog_variant_
  import() (Query 2145) já recalcula match_status contra
  public.card_variant real no momento da confirmação, nunca herda
  do processamento/revalidação (mesmo raciocínio já documentado na
  Query 2145).
- Jobs futuros (ainda não criados) não precisam de nenhuma ação
  aqui: o processador (import-card-variants) já consulta
  card_variant_type_external_mapping no momento da geração — uma
  vez cadastrado o mapeamento, toda nova execução nasce VALID
  automaticamente para essa combinação.
- Nunca escreve em public.card_variant — só staging
  (catalog_variant_import_row) e o próprio mapeamento.
- Grava catalog_admin_action_log
  (CARD_VARIANT_TYPE_EXTERNAL_MAPPING_CREATED) — ação habilitada
  pela Query 2151, com rows_updated/jobs_affected no metadata para
  auditoria do alcance real da resolução.
- Retorna mapping_id, rows_updated e jobs_affected (contagem
  distinta de jobs cujas linhas foram revalidadas) — a UI usa os
  dois últimos para informar ao administrador o alcance real da
  resolução ("N linhas em M jobs foram destravadas").

Pré-requisitos:
- Query 2095 - Create normalize_external_catalog_value() Function.
- Query 2136/2138 - Create Catalog Variant Import Job/Row Tables.
- Query 2140 - Create card_variant_type_external_mapping Table.
- Query 2151 - Widen Catalog Admin Action Log for Variant Mapping.
- Query 1060 - Create is_admin() Function.
----------------------------------------------------------------
REVISION HISTORY
----------------------------------------------------------------
| 1.0 | **Criação da RPC de resolução de mapping (2026-08-15).** Resolução
        relacional inline, escopo único (canônico por Game+Fonte+combinação),
        revalidação set-based embutida. |
| 2.0 | **Duas RPCs públicas do mesmo contrato — GLOBAL + SOURCE_SET
        (2026-09-18, BULK-STP-01-CANONICAL-RECONCILIATION-IMPLEMENTATION-01).**
        Estado terminal introduzido pela migration **`2195`** (ledger
        `20260914025027`): a lógica relacional inline da v1.0 **não existe
        mais no LIVE** — as duas RPCs delegam para o worker único
        `internal.apply_variant_type_mapping()` (Query 2193), que reemite os
        mesmos códigos de erro. Esta Query canônica passa a representar as
        **duas** entradas públicas do contrato:
        · `admin_resolve_catalog_variant_import_mapping()` — escopo `GLOBAL`;
        · `admin_resolve_catalog_variant_import_mapping_for_set()` — escopo
          `SOURCE_SET`.
        Decisão explícita de Fabrício (2026-09-18): não criar Query nova para
        a segunda RPC — o repositório já admite múltiplos objetos
        semanticamente coesos numa mesma Query canônica. A migration `2195`
        permanece em `database/migrations/` como histórico. |
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
-- CONFIRMADO EXECUTADO / LIVE.
--
-- Esta Query CANÔNICA foi reconciliada em 2026-09-18
-- (BULK-STP-01-CANONICAL-RECONCILIATION-IMPLEMENTATION-01): o corpo passou a
-- representar o ESTADO TERMINAL LIVE, provado equivalente por
-- md5(prosrc) normalizado contra pg_get_functiondef do Supabase
-- (projeto qjfutqujxrbzgrtkpgkg).
--
-- NÃO foi reexecutada contra o LIVE — fold-in canônico é alteração de
-- arquivo, não execução (database/README.md, "Queries CANÔNICA vs. MIGRATION").
-- As migrations que introduziram cada camada seguem preservadas em
-- database/migrations/ como histórico.
-- ================================================================
