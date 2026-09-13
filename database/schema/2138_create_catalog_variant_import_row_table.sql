/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2138 - Create Catalog Variant Import Row Table
Versão......: 2.0
Status......: CANÔNICA — CONFIRMADO EXECUTADO / LIVE
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-15 (v1.0) · 2026-09-13 (v2.0)
Reconciliada: 2026-09-13 — CANONICAL-RECONCILIATION-01

Descrição...:
Cria public.catalog_variant_import_row — cada linha é uma proposta de
Card Variant gerada por um catalog_variant_import_job (Query 2136).
Nunca grava diretamente em public.card_variant: é sempre lida,
revisada e decidida pelo administrador antes de
public.admin_confirm_catalog_variant_import() (Query 2145) persistir.

----------------------------------------------------------------
v2.0 — IDENTIDADE DE DOIS EIXOS (PRINTING ROUTING)
----------------------------------------------------------------
Esta versão é o ESTADO TERMINAL do rollout CARD-VARIANTS —
PRINTING-ROUTING: o que as Queries 2138 v1.0 + 2177 + 2184
produziram no banco físico, expresso diretamente, como deve ser
criado numa instalação limpa.

O que mudou frente à v1.0 — e por quê:

A identidade de staging deixou de ser
(job_id, card_id, variant_type_id).

Quatro linhas NORMAL da mesma Card resolvem TODAS para o mesmo
Variant Type (STANDARD) e se distinguem apenas pelo Perfil de
Impressão:

    STANDARD + (sem perfil)
    STANDARD + SHADOWLESS
    STANDARD + SHADOWLESS_FIRST_EDITION
    STANDARD + COPYRIGHT_1999_2000

Sob a identidade antiga, três delas seriam recusadas como duplicata.
A identidade passa a ser de DOIS EIXOS — acabamento
(variant_type_id) e impressão (printing_profile_id) —, espelhando
exatamente o que a Query 2171 fez em public.card_variant.

O MECANISMO TRANSITÓRIO NÃO VIVE AQUI. O índice-ponte
uq_cvir_job_card_type_bridge_legacy existiu apenas entre a aplicação
da 2177 e a da 2184, para proteger linhas gravadas pelo writer ANTIGO
durante o rollout. Numa instalação limpa não existe writer antigo, não
existe linha legada e, portanto, o bridge NÃO É CRIADO. Ele permanece
registrado em database/migrations/2177 e 2184, como histórico.

Pelo mesmo motivo, ck_catalog_variant_import_row_valid_requires_
printing_key nasce aqui VALIDADA, declarada dentro do CREATE TABLE.
O par ADD CONSTRAINT ... NOT VALID + VALIDATE CONSTRAINT da Query 2184
existiu porque havia 5.653 linhas legadas a provar; numa tabela que
acabou de nascer vazia não há nada a provar.

----------------------------------------------------------------
CONTRATO TRI-ESTADO DE normalized_data.printing_profile_id
----------------------------------------------------------------
A chave tem TRÊS estados mutuamente exclusivos, e os três são
distinguíveis SOMENTE por jsonb_typeof — `->>` colapsa os dois
primeiros em SQL NULL e não serve para indexar identidade:

    estado                       jsonb_typeof(nd -> chave)   nd ->> chave
    A. resolvido SEM perfil      'null'                      SQL NULL
    B. resolvido COM perfil      'string'                    'uuid'
    C. Impressão NÃO resolvida   SQL NULL (chave ausente)    SQL NULL

    A. {"variant_type_id":"...","printing_profile_id":null}
    B. {"variant_type_id":"...","printing_profile_id":"uuid"}
    C. {"variant_type_id":"..."}                (chave AUSENTE)

VALID exige variant_type_id resolvido E a chave printing_profile_id
PRESENTE — seja JSON null explícito, seja UUID. O estado C é
NEEDS_REVIEW por construção: "ainda não sei" é informação legítima,
e chave ausente NUNCA significa NULL.

Uma linha no estado C não cai em NENHUM dos dois índices de
identidade — é justamente por isso que ela pode coexistir com outras
não resolvidas para a mesma Card.

Regras de Negócio:
- card_id é NOT NULL — diferença estrutural real frente a
  catalog_import_row.matched_card_id (nullable): uma linha de
  variante só existe para uma Card já cadastrada (correlacionada via
  card_external_reference, já validado nesta frente), nunca propõe
  Card nova. Importar Variantes pressupõe Importar Cartas já
  concluído para o Card Set.
- raw_data (JSONB): preserva type/foil/subtype/stamp exatamente como
  a fonte devolveu, sem interpretação — inclusive stamp como veio
  (array na fonte, ex. ["1st-edition"]), para auditoria e
  reprocessamento futuro (vintage).
- normalized_data (JSONB): dois eixos resolvidos —
  variant_type_id (acabamento, resolvido contra
  public.card_variant_type via card_variant_type_external_mapping,
  Query 2140, a partir da assinatura RESIDUAL) e printing_profile_id
  (impressão, resolvido contra public.card_printing_profile pela
  Query 2176). Ambos dentro do JSONB, não coluna física (ADR-024).
- Deliberadamente SEM is_default nem variant_order: nenhum dos dois é
  inferido ou importado da fonte — permanecem decisão editorial do
  MMKYU, fora do escopo desta tabela e de qualquer incremento futuro
  de importação automática.
- Quatro estados independentes, mesmo desenho de catalog_import_row:
  validation_status (PENDING/VALID/NEEDS_REVIEW/INVALID) — NEEDS_REVIEW
  quando a assinatura residual não bate com nenhuma linha de
  card_variant_type_external_mapping OU quando a Impressão não foi
  resolvida; match_status (NEW/MATCHED/CONFLICT) — recalculado na
  confirmação (Query 2145), contra card_variant real; decision_status
  (PENDING/APPROVED/REJECTED/SKIPPED) — só o administrador altera;
  persistence_status (PENDING/INSERTED/UNCHANGED/FAILED) — SEM
  UPDATED (diferença real: uma Card Variant existe ou não existe, não
  há conteúdo para divergir).
- matched_variant_id / resulting_variant_id: apontam para
  public.card_variant, mesmo papel de matched_card_id/
  resulting_card_id em catalog_import_row, mas para o domínio de
  variante.
- DOIS índices únicos parciais de identidade, mutuamente exclusivos,
  espelhando uq_card_variant_card_type_no_printing e
  uq_card_variant_card_type_printing (Query 2171). Nenhum deles
  alcança linhas ainda não resolvidas.
- DUAS constraints de contrato sobre normalized_data: uma de FORMA
  (que tipos a chave pode assumir) e uma de PRESENÇA (VALID exige a
  chave). Juntas dão o contrato completo.
- RLS habilitado, mesmo padrão de leitura admin-only da Query 2136.
- updated_at mantido por trigger compartilhado (Query 2139).

Pré-requisitos:
- Query 2136 - Create Catalog Variant Import Job Table.
- Query 140 - Create Card Table.
- Query 160 - Create Card Variant Table.
- Query 001 - Create updated_at Function.
- Query 1060 - Create is_admin() Function.

----------------------------------------------------------------
REVISION HISTORY
----------------------------------------------------------------
| 1.0 | **Criação da tabela de staging de variantes (2026-08-15).**
        Identidade de um eixo: (job_id, card_id, variant_type_id). |
| 2.0 | **Identidade de dois eixos — estado terminal do Printing
        Routing (2026-09-13).** Reconciliação canônica
        (CANONICAL-RECONCILIATION-01) do estado que hoje resulta de
        2138 v1.0 + 2177 + 2184 no banco físico. O índice
        uq_catalog_variant_import_row_job_card_variant_type é
        substituído por uq_cvir_job_card_type_no_printing e
        uq_cvir_job_card_type_printing; entram as constraints
        ck_..._printing_profile_shape e
        ck_..._valid_requires_printing_key, esta última já VALIDADA
        por nascer no CREATE TABLE; o índice-ponte
        uq_cvir_job_card_type_bridge_legacy NÃO é criado, por ser
        mecanismo exclusivo de migração. Nenhuma coluna física nova.
        Esta Query NÃO foi reexecutada contra o LIVE: o banco já está
        neste estado desde a PHASE E (ver database/migrations/2177 e
        2184). |
================================================================
*/

BEGIN;

CREATE TABLE public.catalog_variant_import_row (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    job_id UUID NOT NULL,

    card_id UUID NOT NULL,

    raw_data JSONB NOT NULL DEFAULT '{}'::JSONB,
    normalized_data JSONB NOT NULL DEFAULT '{}'::JSONB,

    validation_status TEXT NOT NULL DEFAULT 'PENDING',
    match_status TEXT NOT NULL DEFAULT 'NEW',
    decision_status TEXT NOT NULL DEFAULT 'PENDING',
    persistence_status TEXT NOT NULL DEFAULT 'PENDING',

    matched_variant_id UUID,
    resulting_variant_id UUID,

    error_detail TEXT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT fk_catalog_variant_import_row_job
        FOREIGN KEY (job_id)
        REFERENCES public.catalog_variant_import_job (id)
        ON DELETE CASCADE,

    CONSTRAINT fk_catalog_variant_import_row_card
        FOREIGN KEY (card_id)
        REFERENCES public.card (id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    CONSTRAINT fk_catalog_variant_import_row_matched_variant
        FOREIGN KEY (matched_variant_id)
        REFERENCES public.card_variant (id)
        ON DELETE SET NULL,

    CONSTRAINT fk_catalog_variant_import_row_resulting_variant
        FOREIGN KEY (resulting_variant_id)
        REFERENCES public.card_variant (id)
        ON DELETE SET NULL,

    CONSTRAINT ck_catalog_variant_import_row_validation_status
        CHECK (validation_status IN ('PENDING', 'VALID', 'NEEDS_REVIEW', 'INVALID')),

    CONSTRAINT ck_catalog_variant_import_row_match_status
        CHECK (match_status IN ('NEW', 'MATCHED', 'CONFLICT')),

    CONSTRAINT ck_catalog_variant_import_row_decision_status
        CHECK (decision_status IN ('PENDING', 'APPROVED', 'REJECTED', 'SKIPPED')),

    CONSTRAINT ck_catalog_variant_import_row_persistence_status
        CHECK (persistence_status IN ('PENDING', 'INSERTED', 'UNCHANGED', 'FAILED')),

    CONSTRAINT ck_catalog_variant_import_row_raw_data_object
        CHECK (JSONB_TYPEOF(raw_data) = 'object'),

    CONSTRAINT ck_catalog_variant_import_row_normalized_data_object
        CHECK (JSONB_TYPEOF(normalized_data) = 'object'),

    -- ------------------------------------------------------------
    -- CONTRATO DE FORMA (Printing Routing).
    -- printing_profile_id só pode assumir os três estados do contrato
    -- tri-estado. Qualquer outro tipo JSON — number, boolean, array,
    -- object — é rejeitado, e uma string precisa ser UUID válido.
    -- ------------------------------------------------------------
    CONSTRAINT ck_catalog_variant_import_row_printing_profile_shape
        CHECK (
            jsonb_typeof(normalized_data -> 'printing_profile_id') IS NULL
            OR jsonb_typeof(normalized_data -> 'printing_profile_id') = 'null'
            OR (
                jsonb_typeof(normalized_data -> 'printing_profile_id') = 'string'
                AND (normalized_data ->> 'printing_profile_id') ~*
                    '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
            )
        ),

    -- ------------------------------------------------------------
    -- CONTRATO DE PRESENÇA (Printing Routing) — invariante final.
    -- Linha VALID tem obrigatoriamente a chave printing_profile_id.
    -- NEEDS_REVIEW e os demais estados podem mantê-la ausente.
    --
    -- Nasce VALIDADA por estar no CREATE TABLE. O par
    -- ADD CONSTRAINT ... NOT VALID + VALIDATE CONSTRAINT da Query 2184
    -- foi mecanismo de MIGRAÇÃO — existia para provar 5.653 linhas
    -- legadas. Numa instalação limpa não há linha a provar.
    -- ------------------------------------------------------------
    CONSTRAINT ck_catalog_variant_import_row_valid_requires_printing_key
        CHECK (
            validation_status <> 'VALID'
            OR normalized_data ? 'printing_profile_id'
        )
);

CREATE INDEX ix_catalog_variant_import_row_job ON public.catalog_variant_import_row (job_id);
CREATE INDEX ix_catalog_variant_import_row_job_validation ON public.catalog_variant_import_row (job_id, validation_status);
CREATE INDEX ix_catalog_variant_import_row_job_decision ON public.catalog_variant_import_row (job_id, decision_status);
CREATE INDEX ix_catalog_variant_import_row_job_persistence ON public.catalog_variant_import_row (job_id, persistence_status);
CREATE INDEX ix_catalog_variant_import_row_card ON public.catalog_variant_import_row (card_id);
CREATE INDEX ix_catalog_variant_import_row_matched_variant ON public.catalog_variant_import_row (matched_variant_id) WHERE matched_variant_id IS NOT NULL;

-- ---------------------------------------------------------------------------
-- IDENTIDADE DE STAGING — DOIS EIXOS, DOIS ÍNDICES MUTUAMENTE EXCLUSIVOS.
--
-- Os predicados usam jsonb_typeof, e não `->>`, porque `->>` devolve SQL NULL
-- tanto para "chave ausente" quanto para "JSON null" — e num UNIQUE composto
-- SQL NULL não representa identidade: duas linhas com NULL nessa posição não
-- colidiriam, e o contrato ficaria sem proteção nenhuma.
--
-- jsonb_typeof é IMMUTABLE, logo indexável, e distingue os três estados.
-- ---------------------------------------------------------------------------

-- A. IDENTIDADE RESOLVIDA SEM PERFIL DE IMPRESSÃO.
CREATE UNIQUE INDEX uq_cvir_job_card_type_no_printing
    ON public.catalog_variant_import_row
       (job_id, card_id, ((normalized_data ->> 'variant_type_id')))
 WHERE (normalized_data ->> 'variant_type_id') IS NOT NULL
   AND jsonb_typeof(normalized_data -> 'printing_profile_id') = 'null';

-- B. IDENTIDADE RESOLVIDA COM PERFIL DE IMPRESSÃO.
CREATE UNIQUE INDEX uq_cvir_job_card_type_printing
    ON public.catalog_variant_import_row
       (job_id, card_id,
        ((normalized_data ->> 'variant_type_id')),
        ((normalized_data ->> 'printing_profile_id')))
 WHERE (normalized_data ->> 'variant_type_id') IS NOT NULL
   AND jsonb_typeof(normalized_data -> 'printing_profile_id') = 'string';

COMMENT ON TABLE public.catalog_variant_import_row IS
    'Staging: uma proposta de Card Variant gerada por um catalog_variant_import_job, revisada e decidida pelo administrador. Incremento 1 do bloco Card Variant, ADR-028.';

COMMENT ON COLUMN public.catalog_variant_import_row.card_id IS
    'Card já cadastrada à qual a variante proposta pertence. NOT NULL: esta tabela nunca propõe Card nova.';

COMMENT ON COLUMN public.catalog_variant_import_row.raw_data IS
    'Dado bruto exatamente como veio da fonte (type/foil/subtype/stamp), sem interpretação.';

COMMENT ON COLUMN public.catalog_variant_import_row.normalized_data IS
    'Resolução dos DOIS eixos da identidade de uma Card Variant: variant_type_id (acabamento, resolvido a partir da assinatura RESIDUAL contra card_variant_type_external_mapping) e printing_profile_id (impressão, resolvido contra card_printing_profile). printing_profile_id é TRI-ESTADO e só e distinguivel por jsonb_typeof: ''null'' = resolvido SEM perfil; ''string'' = resolvido COM perfil (UUID); chave AUSENTE = Impressao NAO resolvida (NEEDS_REVIEW). Chave ausente NUNCA significa NULL. VALID exige variant_type_id resolvido E a chave printing_profile_id presente. Nunca inclui is_default/variant_order — decisao editorial, fora do escopo desta importacao.';

COMMENT ON COLUMN public.catalog_variant_import_row.persistence_status IS
    'Resultado real da tentativa de persistência. Sem UPDATED: uma Card Variant existe ou não existe, não há conteúdo para divergir.';

COMMENT ON CONSTRAINT ck_catalog_variant_import_row_printing_profile_shape
    ON public.catalog_variant_import_row IS
    'printing_profile_id so pode assumir tres formas: chave ausente (Printing nao resolvido), JSON null (resolvido sem perfil) ou string UUID valida. Qualquer outro tipo JSON e rejeitado.';

COMMENT ON CONSTRAINT ck_catalog_variant_import_row_valid_requires_printing_key
    ON public.catalog_variant_import_row IS
    'Invariante final do roteamento de Impressão: linha VALID tem obrigatoriamente a chave printing_profile_id. O TIPO do valor é garantido por ck_catalog_variant_import_row_printing_profile_shape. NEEDS_REVIEW pode manter a chave ausente — "ainda não sei" é estado legítimo.';

COMMENT ON INDEX public.uq_cvir_job_card_type_no_printing IS
    'Identidade de staging para rows resolvidas SEM perfil de impressão. jsonb_typeof = ''null'' exige o null EXPLICITO — chave ausente nao entra aqui. Espelha uq_card_variant_card_type_no_printing.';

COMMENT ON INDEX public.uq_cvir_job_card_type_printing IS
    'Identidade de staging para rows resolvidas COM perfil. E este indice que permite as quatro rows STANDARD da mesma Card coexistirem, cada uma com seu Perfil de Impressão. Espelha uq_card_variant_card_type_printing.';

ALTER TABLE public.catalog_variant_import_row ENABLE ROW LEVEL SECURITY;

CREATE POLICY catalog_admin_select ON public.catalog_variant_import_row
    FOR SELECT USING ((select public.is_admin()));

GRANT SELECT ON public.catalog_variant_import_row TO authenticated;
GRANT INSERT, UPDATE ON public.catalog_variant_import_row TO service_role;

COMMIT;

-- ================================================================
-- Confirmado executado:
--   v1.0 em 2026-08-15 (via execute_sql/MCP do Supabase, projeto
--   qjfutqujxrbzgrtkpgkg), junto com as Queries 2136-2137/2139-2142.
--   pg_policies/role_table_grants conferidos (ver Query 2136).
--
--   v2.0 NÃO foi reexecutada. O estado terminal que ela descreve já
--   está LIVE desde a PHASE E do rollout CARD-VARIANTS —
--   PRINTING-ROUTING, produzido por:
--     database/migrations/2177_reconcile_variant_import_row_staging_identity.sql
--     database/migrations/2184_drop_staging_identity_bridge_index.sql
--   Esta é a forma que uma INSTALAÇÃO LIMPA deve usar — ver o aviso
--   do database/README.md: atualizar uma Query CANÔNICA é alteração
--   de arquivo, não executa nada contra o Supabase.
--
-- Estado LIVE verificado em 2026-09-13 (read-only):
--   ck_catalog_variant_import_row_printing_profile_shape .... convalidated = true
--   ck_catalog_variant_import_row_valid_requires_printing_key convalidated = true
--   uq_cvir_job_card_type_no_printing ....................... presente
--   uq_cvir_job_card_type_printing .......................... presente
--   uq_cvir_job_card_type_bridge_legacy ..................... AUSENTE (PHASE E)
--   uq_catalog_variant_import_row_job_card_variant_type ..... AUSENTE (2177)
-- ================================================================
