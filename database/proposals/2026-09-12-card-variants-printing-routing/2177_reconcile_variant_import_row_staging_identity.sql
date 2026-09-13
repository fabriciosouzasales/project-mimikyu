/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 2177 - Reconcile Variant Import Row Staging Identity
Versão......: 1.0
Status......: PROPOSTA — NÃO EXECUTADA
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-12
Mandato.....: CARD-VARIANTS — PRINTING-ROUTING — STAGING-GATE-A-01 (§10, §11, §12)

Descrição resumida:
Fecha o BLOCKER B1. Troca o indice de identidade de staging por DOIS
indices parciais espelhando card_variant, e adiciona o BRIDGE
transitorio que protege o writer legado durante o rollout.

-------------------------------------------------------------------------------
O BLOCKER — medido, nao suposto
-------------------------------------------------------------------------------
Indice LIVE atual:

    uq_catalog_variant_import_row_job_card_variant_type
    UNIQUE (job_id, card_id, (normalized_data ->> 'variant_type_id'))
    WHERE  (normalized_data ->> 'variant_type_id') IS NOT NULL

As 410 rows NEEDS_REVIEW de BASE1 coexistem HOJE apenas porque
normalized_data = '{}' as mantem fora do indice parcial.

No instante em que o routing resolver o Variant Type, as QUATRO rows
NORMAL da mesma Card resolvem TODAS para STANDARD:

    STANDARD + UNLIMITED
    STANDARD + SHADOWLESS
    STANDARD + SHADOWLESS_FIRST_EDITION
    STANDARD + COPYRIGHT_1999_2000

408 das 410 rows violariam a unicidade. O indice precisa passar a
conhecer printing_profile_id ANTES de qualquer resolucao.

-------------------------------------------------------------------------------
POR QUE NAO BASTA ACRESCENTAR A COLUNA AO INDICE ATUAL
-------------------------------------------------------------------------------
Porque `->>` NAO distingue "chave ausente" de "JSON null":

    expressao                                  ausente   null      "uuid"
    normalized_data ->> 'printing_profile_id'  SQL NULL  SQL NULL  'uuid'
    jsonb_typeof(normalized_data -> '...')     SQL NULL  'null'    'string'

Num UNIQUE composto, SQL NULL nao representa a identidade "resolvido
SEM perfil" — duas rows com NULL nessa posicao nao colidiriam, e o
contrato antigo ficaria sem protecao nenhuma.

jsonb_typeof(nd -> chave) distingue os tres casos, e e IMMUTABLE, logo
indexavel. E sobre ele que os predicados abaixo sao construidos.

-------------------------------------------------------------------------------
CONTRATO DE normalized_data
-------------------------------------------------------------------------------
A. resolvido SEM profile  {"variant_type_id":"...","printing_profile_id":null}
B. resolvido COM profile  {"variant_type_id":"...","printing_profile_id":"uuid"}
C. Printing NAO resolvido {"variant_type_id":"..."}   (chave AUSENTE)

VALID exige variant_type_id resolvido E a chave printing_profile_id
PRESENTE — seja null explicito, seja UUID.

Os tres predicados sao mutuamente exclusivos, e uma row no estado C nao
cai em NENHUM dos dois indices finais.

-------------------------------------------------------------------------------
BRIDGE — por que existe e quando morre
-------------------------------------------------------------------------------
Banco e Edge Function NAO sao publicados atomicamente. Entre a aplicacao
desta Query e o deploy da Edge nova existe uma janela em que o writer
ANTIGO continua gravando rows no estado C (sem a chave). Sem o bridge,
essas rows ficariam sem NENHUMA protecao de unicidade — regressao real
frente ao contrato de hoje.

O bridge reproduz exatamente o indice legado, restrito ao estado C:

    UNIQUE (job_id, card_id, variant_type_id)
    WHERE  variant_type_id IS NOT NULL
      AND  jsonb_typeof(normalized_data -> 'printing_profile_id') IS NULL

E TRANSITORIO. A Query 2184 o remove, e so depois de:
    1. fundacao aplicada;
    2. RPCs compativeis;
    3. Edge nova em producao;
    4. legado VALID reconciliado (Query 2183);
    5. zero row VALID com a chave ausente.

Regras de Negócio:
- Nenhuma linha e lida, escrita ou movida.
- Nenhum job, decision_status ou match_status e alterado.
- Em nenhum instante commitado existe estado sem protecao de unicidade:
  o DROP legado e os tres CREATE estao na mesma transacao.

Pré-requisitos:
- Query 2138 - Create Catalog Variant Import Row Table.
===============================================================================
*/

BEGIN;

-- ---------------------------------------------------------------------------
-- Guard de forma: se a chave existir e for string, tem que ser UUID.
-- ---------------------------------------------------------------------------
ALTER TABLE public.catalog_variant_import_row
    ADD CONSTRAINT ck_catalog_variant_import_row_printing_profile_shape
    CHECK (
        jsonb_typeof(normalized_data -> 'printing_profile_id') IS NULL
        OR jsonb_typeof(normalized_data -> 'printing_profile_id') = 'null'
        OR (
            jsonb_typeof(normalized_data -> 'printing_profile_id') = 'string'
            AND (normalized_data ->> 'printing_profile_id') ~*
                '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        )
    );

COMMENT ON CONSTRAINT ck_catalog_variant_import_row_printing_profile_shape
    ON public.catalog_variant_import_row IS
    'printing_profile_id so pode assumir tres formas: chave ausente (Printing nao resolvido), JSON null (resolvido sem perfil) ou string UUID valida. Qualquer outro tipo JSON e rejeitado.';

-- ---------------------------------------------------------------------------
-- Fora o indice legado.
-- ---------------------------------------------------------------------------
DROP INDEX IF EXISTS public.uq_catalog_variant_import_row_job_card_variant_type;

-- ---------------------------------------------------------------------------
-- A. IDENTIDADE RESOLVIDA SEM PROFILE
-- ---------------------------------------------------------------------------
CREATE UNIQUE INDEX uq_cvir_job_card_type_no_printing
    ON public.catalog_variant_import_row
       (job_id, card_id, ((normalized_data ->> 'variant_type_id')))
 WHERE (normalized_data ->> 'variant_type_id') IS NOT NULL
   AND jsonb_typeof(normalized_data -> 'printing_profile_id') = 'null';

COMMENT ON INDEX public.uq_cvir_job_card_type_no_printing IS
    'Identidade de staging para rows resolvidas SEM perfil de impressão. jsonb_typeof = ''null'' exige o null EXPLICITO — chave ausente nao entra aqui. Espelha uq_card_variant_card_type_no_printing.';

-- ---------------------------------------------------------------------------
-- B. IDENTIDADE RESOLVIDA COM PROFILE
-- ---------------------------------------------------------------------------
CREATE UNIQUE INDEX uq_cvir_job_card_type_printing
    ON public.catalog_variant_import_row
       (job_id, card_id,
        ((normalized_data ->> 'variant_type_id')),
        ((normalized_data ->> 'printing_profile_id')))
 WHERE (normalized_data ->> 'variant_type_id') IS NOT NULL
   AND jsonb_typeof(normalized_data -> 'printing_profile_id') = 'string';

COMMENT ON INDEX public.uq_cvir_job_card_type_printing IS
    'Identidade de staging para rows resolvidas COM perfil. E este indice que permite as quatro rows STANDARD da mesma Card BASE1 coexistirem, cada uma com seu Perfil de Impressão. Espelha uq_card_variant_card_type_printing.';

-- ---------------------------------------------------------------------------
-- BRIDGE — TRANSITORIO. Removido pela Query 2184.
-- ---------------------------------------------------------------------------
CREATE UNIQUE INDEX uq_cvir_job_card_type_bridge_legacy
    ON public.catalog_variant_import_row
       (job_id, card_id, ((normalized_data ->> 'variant_type_id')))
 WHERE (normalized_data ->> 'variant_type_id') IS NOT NULL
   AND jsonb_typeof(normalized_data -> 'printing_profile_id') IS NULL;

COMMENT ON INDEX public.uq_cvir_job_card_type_bridge_legacy IS
    'TRANSITORIO — nao promover como permanente. Reproduz o contrato do indice legado para rows gravadas pelo writer ANTIGO (chave printing_profile_id ausente), durante a janela entre a aplicacao desta Query e o deploy da Edge Function nova. Removido pela Query 2184 apos a reconciliacao do legado VALID (Query 2183).';

COMMIT;

-- ============================================================================
-- Resultado esperado:
--   ALTER TABLE (ADD CONSTRAINT), COMMENT, DROP INDEX,
--   CREATE UNIQUE INDEX x3, COMMENT x3.
--   catalog_variant_import_row = 6.158 linhas, inalteradas.
--
-- Rollback conceitual:
--   DROP dos tres indices novos + recriar
--   uq_catalog_variant_import_row_job_card_variant_type + DROP CONSTRAINT.
--   Possivel enquanto nenhuma row tiver a chave printing_profile_id.
--
-- Como validar:
--   Query 2824 - Validate Card Printing Routing, Secoes S9, S10 e S11.
-- ============================================================================
