/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2060 - Create Catalog Import Job Table
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-01

Descrição...:
Cria public.catalog_import_job — entidade de staging que representa
uma execução do fluxo de ingestão de Cards para um Card Set já
cadastrado e ainda sem Cards (ADR-024, Catalog Card Ingestion
Strategy). Infraestrutura comum ao fluxo TCGdex e ao fluxo PDF —
Ciclo 1 da ordem de execução aprovada por Fabrício em 2026-08-01.

Cada linha representa uma tentativa de importar o checklist de um
Card Set a partir de uma fonte externa (PDF ou API TCGdex). A fonte
externa nunca grava diretamente nas tabelas canônicas — grava
propostas em catalog_import_row (Query 2070), e só
admin_confirm_catalog_import() (Query 2082) persiste em public.card,
sempre por decisão explícita do administrador.

Regras de Negócio:
- card_set_id é obrigatório e não tem relação com idioma: card_set
  não possui coluna de idioma (confirmado em database/schema/120 e
  database/schema/140 — o nome da Card já nasce no idioma de
  publicação do próprio Card Set, sem dimensão adicional). Por isso
  esta tabela não guarda language_id.
- source restrito a 'PDF' ou 'TCGDEX' — os dois únicos canais
  previstos na ordem de ciclos aprovada.
- Identificador de fingerprint por canal: file_checksum (PDF, hash
  do arquivo enviado) ou external_set_id (TCGdex, id do Set na API)
  — exatamente um dos dois é obrigatório, de acordo com source.
- status segue o domínio de 8 estados do ADR-024: RECEIVED,
  PROCESSING, STAGED, CONFIRMING, COMPLETED, COMPLETED_WITH_ERRORS,
  FAILED, CANCELLED. Não existe estado "parcialmente confirmado" —
  os contadores abaixo são sempre recalculados por agregação sobre
  catalog_import_row, nunca incrementados diretamente.
- progress_step é um enum/índice estável (TEXT com CHECK fechado),
  não um texto de exibição — os textos e ícones pertencem
  inteiramente ao frontend, que mapeia cada código para um rótulo
  em português (ajuste final de Fabrício, 2026-08-01). Só tem
  sentido durante status = 'PROCESSING'; fora desse estado permanece
  NULL.
- Fingerprint de idempotência: um índice único parcial impede duas
  execuções ativas (status em RECEIVED/PROCESSING/STAGED/CONFIRMING)
  para a mesma combinação de source + card_set_id + identificador de
  origem. Deixa de valer assim que o job atinge um estado terminal
  (COMPLETED, COMPLETED_WITH_ERRORS, FAILED, CANCELLED) — reprocessar
  o mesmo Card Set depois de concluído é permitido.
- Os contadores (total_rows .. failed_rows) nunca são incrementados
  diretamente pelo processador ou pela confirmação — são sempre
  recalculados por agregação sobre catalog_import_row, exatamente
  como determina o ADR-024.
- initiated_by anulável com ON DELETE SET NULL, mesmo padrão de
  catalog_admin_action_log — a exclusão futura do usuário nunca
  apaga o histórico do job.
- Sem trigger de governança de estado (diferente do padrão já usado
  em asset_import_run/Query 221): as transições de status deste
  fluxo são inteiramente controladas pelas próprias funções
  SECURITY DEFINER (admin_start/decide/confirm_catalog_import) e por
  admin_confirm_catalog_import() rodar dentro de uma única transação
  com SELECT ... FOR UPDATE na linha do job — um estado inválido é
  estruturalmente inalcançável sem precisar de um trigger adicional.
- RLS habilitado com leitura restrita a administradores
  (catalog_admin_select, mesmo padrão de asset_import_run e das
  demais tabelas do Catálogo Editorial — Query 274), para a tela de
  Revisão poder ler o job diretamente pela sessão do administrador.
  GRANT SELECT explícito para authenticated (a política sozinha não
  basta sem o GRANT de nível de tabela — gap já visto antes neste
  projeto, ver migration 272). GRANT de escrita (INSERT/UPDATE) para
  service_role, para a Edge Function processadora poder gravar o
  progresso — mesmo gap de GRANT já visto 4 vezes neste projeto
  (Queries 250/253/254/272), corrigido aqui desde a criação da
  tabela em vez de esperar a produção revelar a falta.
- updated_at mantido por trigger compartilhado (public.set_updated_at,
  Query 001), mesmo padrão de todas as tabelas com updated_at neste
  projeto.

Pré-requisitos:
- Query 120 - Create Card Set Table.
- Query 001 - Create updated_at Function.
- Query 1060 - Create is_admin() Function.
================================================================
*/

CREATE TABLE public.catalog_import_job (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    card_set_id UUID NOT NULL,

    source TEXT NOT NULL,
    file_checksum TEXT,
    external_set_id TEXT,

    status TEXT NOT NULL DEFAULT 'RECEIVED',
    progress_step TEXT,

    total_rows INTEGER NOT NULL DEFAULT 0,
    valid_rows INTEGER NOT NULL DEFAULT 0,
    rejected_rows INTEGER NOT NULL DEFAULT 0,
    inserted_rows INTEGER NOT NULL DEFAULT 0,
    updated_rows INTEGER NOT NULL DEFAULT 0,
    unchanged_rows INTEGER NOT NULL DEFAULT 0,
    skipped_rows INTEGER NOT NULL DEFAULT 0,
    failed_rows INTEGER NOT NULL DEFAULT 0,

    error_summary TEXT,

    initiated_by UUID,

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT fk_catalog_import_job_card_set
        FOREIGN KEY (card_set_id)
        REFERENCES public.card_set (id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,

    CONSTRAINT fk_catalog_import_job_initiated_by
        FOREIGN KEY (initiated_by)
        REFERENCES auth.users (id)
        ON DELETE SET NULL,

    CONSTRAINT ck_catalog_import_job_source
        CHECK (source IN ('PDF', 'TCGDEX')),

    CONSTRAINT ck_catalog_import_job_status
        CHECK (
            status IN (
                'RECEIVED', 'PROCESSING', 'STAGED', 'CONFIRMING',
                'COMPLETED', 'COMPLETED_WITH_ERRORS', 'FAILED', 'CANCELLED'
            )
        ),

    CONSTRAINT ck_catalog_import_job_progress_step
        CHECK (
            progress_step IS NULL
            OR progress_step IN (
                'FETCHING_SOURCE', 'EXTRACTING_CARDS', 'DETECTING_RARITY',
                'CLASSIFYING_CATEGORY', 'VALIDATING_SEQUENCE',
                'MATCHING_CATALOG', 'PREPARING_REVIEW'
            )
        ),

    CONSTRAINT ck_catalog_import_job_progress_step_scope
        CHECK (progress_step IS NULL OR status = 'PROCESSING'),

    CONSTRAINT ck_catalog_import_job_source_identifier
        CHECK (
            (source = 'PDF' AND file_checksum IS NOT NULL AND external_set_id IS NULL)
            OR (source = 'TCGDEX' AND external_set_id IS NOT NULL AND file_checksum IS NULL)
        ),

    CONSTRAINT ck_catalog_import_job_counts_non_negative
        CHECK (
            total_rows >= 0 AND valid_rows >= 0 AND rejected_rows >= 0
            AND inserted_rows >= 0 AND updated_rows >= 0 AND unchanged_rows >= 0
            AND skipped_rows >= 0 AND failed_rows >= 0
        )
);

CREATE UNIQUE INDEX uq_catalog_import_job_fingerprint_active
    ON public.catalog_import_job (source, card_set_id, COALESCE(file_checksum, ''), COALESCE(external_set_id, ''))
    WHERE status IN ('RECEIVED', 'PROCESSING', 'STAGED', 'CONFIRMING');

CREATE INDEX ix_catalog_import_job_card_set
    ON public.catalog_import_job (card_set_id, created_at DESC);

CREATE INDEX ix_catalog_import_job_active
    ON public.catalog_import_job (created_at DESC)
    WHERE status IN ('RECEIVED', 'PROCESSING', 'STAGED', 'CONFIRMING');

COMMENT ON TABLE public.catalog_import_job IS
    'Staging: uma execução do fluxo de ingestão de Cards (PDF ou TCGdex) para um Card Set ainda sem Cards. ADR-024.';

COMMENT ON COLUMN public.catalog_import_job.card_set_id IS
    'Card Set alvo da importação. Sem dimensão de idioma: card_set não possui language_id.';

COMMENT ON COLUMN public.catalog_import_job.source IS
    'Canal de origem: PDF (checklist oficial) ou TCGDEX (API pública).';

COMMENT ON COLUMN public.catalog_import_job.file_checksum IS
    'Hash do arquivo PDF enviado. Obrigatório e exclusivo quando source = PDF.';

COMMENT ON COLUMN public.catalog_import_job.external_set_id IS
    'Identificador do Set na API TCGdex. Obrigatório e exclusivo quando source = TCGDEX.';

COMMENT ON COLUMN public.catalog_import_job.status IS
    'Estado do job, sempre recalculado por agregação sobre catalog_import_row — nunca incrementado diretamente. Domínio fechado de 8 estados (ADR-024).';

COMMENT ON COLUMN public.catalog_import_job.progress_step IS
    'Código estável da fase de processamento, significativo apenas durante status = PROCESSING. Sem texto de exibição — isso é responsabilidade do frontend.';

COMMENT ON COLUMN public.catalog_import_job.total_rows IS
    'Total de linhas de staging geradas. Recalculado por agregação, nunca incrementado.';

COMMENT ON COLUMN public.catalog_import_job.error_summary IS
    'Mensagem de erro de alto nível quando status = FAILED (falha sistêmica, não erro de uma linha isolada).';

COMMENT ON COLUMN public.catalog_import_job.initiated_by IS
    'Administrador que iniciou a importação. Anulável: sobrevive à exclusão futura do usuário.';

ALTER TABLE public.catalog_import_job ENABLE ROW LEVEL SECURITY;

CREATE POLICY catalog_admin_select ON public.catalog_import_job
    FOR SELECT USING (public.is_admin());

GRANT SELECT ON public.catalog_import_job TO authenticated;
GRANT INSERT, UPDATE ON public.catalog_import_job TO service_role;
