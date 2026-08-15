/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2138 - Create Catalog Variant Import Row Table
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-15

Descrição...:
Cria public.catalog_variant_import_row — cada linha é uma proposta de
Card Variant gerada por um catalog_variant_import_job (Query 2136).
Nunca grava diretamente em public.card_variant: é sempre lida,
revisada e decidida pelo administrador antes de uma futura função de
confirmação (Incremento 3, não criada nesta Query) persistir.

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
- normalized_data (JSONB): só variant_type_id, já resolvido contra
  public.card_variant_type via card_variant_type_external_mapping
  (Query 2140) — mesmo tratamento que rarity_id/category_id recebem
  em catalog_import_row (dentro do JSONB, não coluna física, ADR-024).
  Ausente quando a combinação bruta não tem mapeamento (NEEDS_REVIEW).
- Deliberadamente SEM is_default nem variant_order: nenhum dos dois é
  inferido ou importado da fonte — permanecem decisão editorial do
  MMKYU, fora do escopo desta tabela e de qualquer incremento futuro
  de importação automática.
- Quatro estados independentes, mesmo desenho de catalog_import_row:
  validation_status (PENDING/VALID/NEEDS_REVIEW/INVALID) — NEEDS_REVIEW
  quando a combinação bruta não bate com nenhuma linha de
  card_variant_type_external_mapping; match_status
  (NEW/MATCHED/CONFLICT) — recalculado na confirmação (função futura),
  contra card_variant real; decision_status
  (PENDING/APPROVED/REJECTED/SKIPPED) — só o administrador altera;
  persistence_status (PENDING/INSERTED/UNCHANGED/FAILED) — SEM
  UPDATED (diferença real: uma Card Variant existe ou não existe, não
  há conteúdo para divergir).
- matched_variant_id / resulting_variant_id: apontam para
  public.card_variant, mesmo papel de matched_card_id/
  resulting_card_id em catalog_import_row, mas para o domínio de
  variante.
- Índice único parcial em (job_id, card_id,
  normalized_data->>'variant_type_id') impede duas propostas
  resolvidas idênticas dentro do mesmo job — preparo de idempotência
  pedido explicitamente, sem impedir múltiplas linhas ainda não
  resolvidas (variant_type_id nulo) para a mesma Card.
- RLS habilitado, mesmo padrão de leitura admin-only da Query 2136.
- updated_at mantido por trigger compartilhado (Query 2139).

Pré-requisitos:
- Query 2136 - Create Catalog Variant Import Job Table.
- Query 140 - Create Card Table.
- Query 160 - Create Card Variant Table.
- Query 001 - Create updated_at Function.
- Query 1060 - Create is_admin() Function.
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
        CHECK (JSONB_TYPEOF(normalized_data) = 'object')
);

CREATE INDEX ix_catalog_variant_import_row_job ON public.catalog_variant_import_row (job_id);
CREATE INDEX ix_catalog_variant_import_row_job_validation ON public.catalog_variant_import_row (job_id, validation_status);
CREATE INDEX ix_catalog_variant_import_row_job_decision ON public.catalog_variant_import_row (job_id, decision_status);
CREATE INDEX ix_catalog_variant_import_row_job_persistence ON public.catalog_variant_import_row (job_id, persistence_status);
CREATE INDEX ix_catalog_variant_import_row_card ON public.catalog_variant_import_row (card_id);
CREATE INDEX ix_catalog_variant_import_row_matched_variant ON public.catalog_variant_import_row (matched_variant_id) WHERE matched_variant_id IS NOT NULL;

CREATE UNIQUE INDEX uq_catalog_variant_import_row_job_card_variant_type
    ON public.catalog_variant_import_row (job_id, card_id, (normalized_data ->> 'variant_type_id'))
    WHERE normalized_data ->> 'variant_type_id' IS NOT NULL;

COMMENT ON TABLE public.catalog_variant_import_row IS
    'Staging: uma proposta de Card Variant gerada por um catalog_variant_import_job, revisada e decidida pelo administrador. Incremento 1 do bloco Card Variant, ADR-028.';

COMMENT ON COLUMN public.catalog_variant_import_row.card_id IS
    'Card já cadastrada à qual a variante proposta pertence. NOT NULL: esta tabela nunca propõe Card nova.';

COMMENT ON COLUMN public.catalog_variant_import_row.raw_data IS
    'Dado bruto exatamente como veio da fonte (type/foil/subtype/stamp), sem interpretação.';

COMMENT ON COLUMN public.catalog_variant_import_row.normalized_data IS
    'variant_type_id já resolvido contra card_variant_type. Ausente quando a combinação bruta não tem mapeamento (NEEDS_REVIEW). Nunca inclui is_default/variant_order — decisão editorial, fora do escopo desta importação.';

COMMENT ON COLUMN public.catalog_variant_import_row.persistence_status IS
    'Resultado real da tentativa de persistência. Sem UPDATED: uma Card Variant existe ou não existe, não há conteúdo para divergir.';

ALTER TABLE public.catalog_variant_import_row ENABLE ROW LEVEL SECURITY;

CREATE POLICY catalog_admin_select ON public.catalog_variant_import_row
    FOR SELECT USING ((select public.is_admin()));

GRANT SELECT ON public.catalog_variant_import_row TO authenticated;
GRANT INSERT, UPDATE ON public.catalog_variant_import_row TO service_role;

COMMIT;

-- ================================================================
-- Confirmado executado (2026-08-15, via execute_sql/MCP do Supabase,
-- projeto qjfutqujxrbzgrtkpgkg), junto com as Queries 2136-2137/
-- 2139-2142. pg_policies/role_table_grants conferidos (ver Query
-- 2136); índice único parcial validado por desenho (não testado com
-- linha real nesta rodada — nenhum job/row real foi criado, só
-- schema, conforme aprovado).
-- ================================================================
