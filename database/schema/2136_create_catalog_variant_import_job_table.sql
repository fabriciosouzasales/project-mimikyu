/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2136 - Create Catalog Variant Import Job Table
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-15

Descrição...:
Cria public.catalog_variant_import_job — staging de uma execução do
fluxo de ingestão de Card Variant (Incremento 1 do bloco Card Variant,
ver ADR-028 e o desenho aprovado nesta mesma rodada). Mesmo contrato
de ADR-024 (fonte → processador → staging → revisão → confirmação),
nova instância dele para variantes — não uma exceção ao padrão.

Regras de Negócio:
- source tem domínio de um único valor ('TCGDEX') hoje — mesma
  disciplina de catalog_import_job (Query 2060), que já nasceu com
  domínio fechado mesmo tendo só 1-2 canais ativos por vez.
  Extensível sem redesenho se uma segunda fonte de variante surgir.
- external_set_id é o identificador do Card Set no dataset-fonte da
  TCGdex (github.com/tcgdex/cards-database) — não o endpoint da API
  pública, decisão já tomada (ver desenho aprovado): a API pública
  simplifica type/foil/subtype/stamp para 4-5 booleanos, o
  dataset-fonte preserva a granularidade que card_variant_type exige.
- status segue o mesmo domínio de 8 estados de catalog_import_job
  (ADR-024) — staging revisável, nunca "confirmado parcial".
- progress_step deliberadamente SEM domínio fechado de etapas nesta
  Query: o processador (Incremento 2) ainda não existe, travar nomes
  de etapa agora seria adivinhar antes de saber o desenho real do
  processador — só a guarda de escopo (não nulo fora de PROCESSING)
  é aplicada. Um domínio fechado pode ser adicionado via ALTER quando
  o Incremento 2 definir as etapas reais.
- Contadores SEM updated_rows (diferença real de catalog_import_job):
  o domínio de persistência de catalog_variant_import_row não tem
  UPDATED — uma Card Variant existe ou não existe, não há conteúdo
  para divergir e atualizar.
- Fingerprint de idempotência: índice único parcial em
  (card_set_id, external_set_id), válido só enquanto o job está em
  estado não-terminal — mesmo mecanismo de catalog_import_job.
- RLS habilitado com leitura restrita a administradores
  (catalog_admin_select, USING ((select is_admin())) — forma já
  otimizada desde a criação, sem precisar do hardening retroativo
  que catalog_import_job precisou, porque is_admin() já é STABLE
  desde a Query 2134, anterior a esta). GRANT SELECT explícito para
  authenticated; GRANT de escrita (INSERT/UPDATE) para service_role,
  para o futuro processador (Incremento 2) gravar progresso.
- updated_at mantido por trigger compartilhado (Query 2137).

Pré-requisitos:
- Query 120 - Create Card Set Table.
- Query 001 - Create updated_at Function.
- Query 1060 - Create is_admin() Function.
- Query 2134 - Harden is_admin() RLS Performance (is_admin() STABLE).
================================================================
*/

BEGIN;

CREATE TABLE public.catalog_variant_import_job (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    card_set_id UUID NOT NULL,

    source TEXT NOT NULL,
    external_set_id TEXT NOT NULL,

    status TEXT NOT NULL DEFAULT 'RECEIVED',
    progress_step TEXT,

    total_rows INTEGER NOT NULL DEFAULT 0,
    valid_rows INTEGER NOT NULL DEFAULT 0,
    rejected_rows INTEGER NOT NULL DEFAULT 0,
    inserted_rows INTEGER NOT NULL DEFAULT 0,
    unchanged_rows INTEGER NOT NULL DEFAULT 0,
    skipped_rows INTEGER NOT NULL DEFAULT 0,
    failed_rows INTEGER NOT NULL DEFAULT 0,

    error_summary TEXT,

    initiated_by UUID,

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT fk_catalog_variant_import_job_card_set
        FOREIGN KEY (card_set_id)
        REFERENCES public.card_set (id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    CONSTRAINT fk_catalog_variant_import_job_initiated_by
        FOREIGN KEY (initiated_by)
        REFERENCES auth.users (id)
        ON DELETE SET NULL,

    CONSTRAINT ck_catalog_variant_import_job_source
        CHECK (source = 'TCGDEX'),

    CONSTRAINT ck_catalog_variant_import_job_status
        CHECK (
            status IN (
                'RECEIVED', 'PROCESSING', 'STAGED', 'CONFIRMING',
                'COMPLETED', 'COMPLETED_WITH_ERRORS', 'FAILED', 'CANCELLED'
            )
        ),

    CONSTRAINT ck_catalog_variant_import_job_progress_step_scope
        CHECK (progress_step IS NULL OR status = 'PROCESSING'),

    CONSTRAINT ck_catalog_variant_import_job_counts_non_negative
        CHECK (
            total_rows >= 0 AND valid_rows >= 0 AND rejected_rows >= 0
            AND inserted_rows >= 0 AND unchanged_rows >= 0
            AND skipped_rows >= 0 AND failed_rows >= 0
        )
);

CREATE UNIQUE INDEX uq_catalog_variant_import_job_fingerprint_active
    ON public.catalog_variant_import_job (card_set_id, external_set_id)
    WHERE status IN ('RECEIVED', 'PROCESSING', 'STAGED', 'CONFIRMING');

CREATE INDEX ix_catalog_variant_import_job_card_set
    ON public.catalog_variant_import_job (card_set_id, created_at DESC);

CREATE INDEX ix_catalog_variant_import_job_active
    ON public.catalog_variant_import_job (created_at DESC)
    WHERE status IN ('RECEIVED', 'PROCESSING', 'STAGED', 'CONFIRMING');

COMMENT ON TABLE public.catalog_variant_import_job IS
    'Staging: uma execução do fluxo de ingestão de Card Variant (TCGdex, dataset-fonte). Incremento 1 do bloco Card Variant, ADR-028.';

COMMENT ON COLUMN public.catalog_variant_import_job.card_set_id IS
    'Card Set alvo da importação de variantes.';

COMMENT ON COLUMN public.catalog_variant_import_job.external_set_id IS
    'Identificador do Set no dataset-fonte da TCGdex (github.com/tcgdex/cards-database), não a API pública.';

COMMENT ON COLUMN public.catalog_variant_import_job.status IS
    'Estado do job, recalculado por agregação sobre catalog_variant_import_row — nunca incrementado diretamente. Mesmo domínio de 8 estados de catalog_import_job (ADR-024).';

COMMENT ON COLUMN public.catalog_variant_import_job.progress_step IS
    'Código de fase, significativo só durante PROCESSING. Sem domínio fechado nesta Query — processador ainda não existe (Incremento 2).';

ALTER TABLE public.catalog_variant_import_job ENABLE ROW LEVEL SECURITY;

CREATE POLICY catalog_admin_select ON public.catalog_variant_import_job
    FOR SELECT USING ((select public.is_admin()));

GRANT SELECT ON public.catalog_variant_import_job TO authenticated;
GRANT INSERT, UPDATE ON public.catalog_variant_import_job TO service_role;

COMMIT;

-- ================================================================
-- Confirmado executado (2026-08-15, via execute_sql/MCP do Supabase,
-- projeto qjfutqujxrbzgrtkpgkg), depois de dry-run em BEGIN...ROLLBACK
-- junto com as Queries 2137-2142. Validado: pg_policies confirma
-- catalog_admin_select com qual = "( SELECT is_admin() AS is_admin)";
-- information_schema.role_table_grants confirma SELECT para
-- authenticated e INSERT/UPDATE para service_role, nenhum grant para
-- anon. Teste funcional (SET LOCAL ROLE authenticated não-admin,
-- dentro de BEGIN...ROLLBACK): 0 linhas visíveis, RLS efetiva.
-- ================================================================
