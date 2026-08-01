/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2070 - Create Catalog Import Row Table
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-01

Descrição...:
Cria public.catalog_import_row — cada linha é uma proposta de Card
gerada por um catalog_import_job (Query 2060), a partir do PDF ou da
API TCGdex. Nunca grava diretamente em public.card: é sempre lida,
revisada e decidida pelo administrador antes de
admin_confirm_catalog_import() (Query 2082) persistir. Ver ADR-024.

Regras de Negócio:
- Quatro estados por linha, deliberadamente independentes (nunca
  combinados em um único campo, ver ADR-024):
  - validation_status: resultado da validação estrutural feita pelo
    processador (PENDING/VALID/NEEDS_REVIEW/INVALID).
  - match_status: resultado da comparação com o catálogo real no
    momento da confirmação (NEW/MATCHED/CONFLICT) — recalculado por
    admin_confirm_catalog_import(), não pelo processador, porque o
    catálogo pode mudar entre o processamento e a confirmação.
  - decision_status: decisão do administrador sobre a linha
    (PENDING/APPROVED/REJECTED/SKIPPED) — o único dos quatro campos
    que só o administrador altera (admin_decide_catalog_import_row,
    Query 2081).
  - persistence_status: resultado real da tentativa de persistência
    (PENDING/INSERTED/UPDATED/UNCHANGED/FAILED), gravado por
    admin_confirm_catalog_import().
- raw_data (JSONB): o dado bruto exatamente como veio da fonte
  (linha do checklist do PDF ou registro da API), sem nenhuma
  interpretação — preservado para auditoria e reprocessamento.
- normalized_data (JSONB): melhor tentativa de campos já resolvidos
  para os identificadores internos do catálogo — inclui, entre
  outros, name, collector_number, collector_total, collector_order,
  rarity_id (UUID já resolvido contra public.rarity), category_id
  (UUID já resolvido contra public.card_category), category (código
  proposto: POKEMON/TRAINER/ENERGY), category_source (API/
  ENERGY_PREFIX/POKEMON_MATCH/TRAINER_FALLBACK — como a categoria foi
  obtida) e category_confidence (HIGH/MEDIUM/LOW — confiança nessa
  origem). O processador é responsável por essa resolução;
  admin_confirm_catalog_import() só lê os campos já resolvidos, sem
  refazer nenhum mapeamento de vocabulário externo. Mantidos dentro
  de normalized_data — sem colunas físicas próprias — por decisão
  explícita de Fabrício (2026-08-01): o desenho de dados aprovado no
  ADR-024 não é alterado nesta etapa; category_source/
  category_confidence são metadados do mesmo processo de resolução
  que já produz os demais campos deste JSONB, não um novo eixo de
  estado da linha (os quatro estados independentes do ADR-024
  continuam sendo só validation_status/match_status/decision_status/
  persistence_status). A regra de classificação em si é única para
  os dois canais: a API TCGdex, quando fornece categoria, apenas
  aumenta a confiança do mesmo algoritmo — nunca o substitui; quando
  a API não fornece categoria, aplica-se automaticamente a mesma
  lógica usada para PDF (prefixo "Energia" -> ENERGY; senão,
  correspondência de nome de espécie Pokémon via TCGdex -> POKEMON;
  senão -> TRAINER por eliminação) — implementada inteiramente no
  processador de cada canal (Ciclos 2/3/4), fora do escopo desta
  Query.
- detected_variant_hint (JSONB, opcional): sinal de variante
  detectado na origem (ex.: cor da borda do checkbox no PDF,
  distinguindo "Cartas Padrão" de "Cartas Laminadas Padrão").
  Preservado para uso futuro — esta fase não cria card_variant a
  partir dele.
- matched_card_id: Card já existente que esta linha corresponde
  (match_status IN ('MATCHED','CONFLICT')). resulting_card_id: Card
  efetivamente resultante após a confirmação (criada ou já
  existente) — usado pela tela de Resultados.
- error_detail: mensagem de erro específica desta linha quando
  persistence_status = 'FAILED'. Um erro de linha nunca aborta as
  demais — cada linha é isolada em seu próprio bloco de exceção
  dentro de admin_confirm_catalog_import() (ADR-024).
- RLS habilitado com leitura restrita a administradores
  (catalog_admin_select), GRANT SELECT para authenticated e GRANT de
  escrita (INSERT/UPDATE) para service_role — mesmo raciocínio já
  aplicado em catalog_import_job (Query 2060).
- updated_at mantido por trigger compartilhado (public.set_updated_at).

Pré-requisitos:
- Query 2060 - Create Catalog Import Job Table.
- Query 140 - Create Card Table.
- Query 001 - Create updated_at Function.
- Query 1060 - Create is_admin() Function.
================================================================
*/

CREATE TABLE public.catalog_import_row (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    job_id UUID NOT NULL,

    raw_data JSONB NOT NULL DEFAULT '{}'::JSONB,
    normalized_data JSONB NOT NULL DEFAULT '{}'::JSONB,
    detected_variant_hint JSONB,

    validation_status TEXT NOT NULL DEFAULT 'PENDING',
    match_status TEXT NOT NULL DEFAULT 'NEW',
    decision_status TEXT NOT NULL DEFAULT 'PENDING',
    persistence_status TEXT NOT NULL DEFAULT 'PENDING',

    matched_card_id UUID,
    resulting_card_id UUID,

    error_detail TEXT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT fk_catalog_import_row_job
        FOREIGN KEY (job_id)
        REFERENCES public.catalog_import_job (id)
        ON DELETE CASCADE,

    CONSTRAINT fk_catalog_import_row_matched_card
        FOREIGN KEY (matched_card_id)
        REFERENCES public.card (id)
        ON DELETE SET NULL,

    CONSTRAINT fk_catalog_import_row_resulting_card
        FOREIGN KEY (resulting_card_id)
        REFERENCES public.card (id)
        ON DELETE SET NULL,

    CONSTRAINT ck_catalog_import_row_validation_status
        CHECK (validation_status IN ('PENDING', 'VALID', 'NEEDS_REVIEW', 'INVALID')),

    CONSTRAINT ck_catalog_import_row_match_status
        CHECK (match_status IN ('NEW', 'MATCHED', 'CONFLICT')),

    CONSTRAINT ck_catalog_import_row_decision_status
        CHECK (decision_status IN ('PENDING', 'APPROVED', 'REJECTED', 'SKIPPED')),

    CONSTRAINT ck_catalog_import_row_persistence_status
        CHECK (persistence_status IN ('PENDING', 'INSERTED', 'UPDATED', 'UNCHANGED', 'FAILED')),

    CONSTRAINT ck_catalog_import_row_raw_data_object
        CHECK (JSONB_TYPEOF(raw_data) = 'object'),

    CONSTRAINT ck_catalog_import_row_normalized_data_object
        CHECK (JSONB_TYPEOF(normalized_data) = 'object'),

    CONSTRAINT ck_catalog_import_row_variant_hint_object
        CHECK (detected_variant_hint IS NULL OR JSONB_TYPEOF(detected_variant_hint) = 'object')
);

CREATE INDEX ix_catalog_import_row_job ON public.catalog_import_row (job_id);
CREATE INDEX ix_catalog_import_row_job_validation ON public.catalog_import_row (job_id, validation_status);
CREATE INDEX ix_catalog_import_row_job_decision ON public.catalog_import_row (job_id, decision_status);
CREATE INDEX ix_catalog_import_row_job_persistence ON public.catalog_import_row (job_id, persistence_status);
CREATE INDEX ix_catalog_import_row_matched_card ON public.catalog_import_row (matched_card_id) WHERE matched_card_id IS NOT NULL;

COMMENT ON TABLE public.catalog_import_row IS
    'Staging: uma proposta de Card gerada por um catalog_import_job, revisada e decidida pelo administrador antes de persistir. ADR-024.';

COMMENT ON COLUMN public.catalog_import_row.raw_data IS
    'Dado bruto exatamente como veio da fonte (PDF ou API), sem interpretação.';

COMMENT ON COLUMN public.catalog_import_row.normalized_data IS
    'Melhor tentativa de campos já resolvidos: name, collector_number, collector_total, collector_order, rarity_id, category_id, category, category_source, category_confidence.';

COMMENT ON COLUMN public.catalog_import_row.detected_variant_hint IS
    'Sinal de variante detectado na origem (ex.: cor da borda no PDF). Preservado, não usado para criar card_variant nesta fase.';

COMMENT ON COLUMN public.catalog_import_row.validation_status IS
    'Resultado da validação estrutural feita pelo processador.';

COMMENT ON COLUMN public.catalog_import_row.match_status IS
    'Resultado da comparação com o catálogo real, recalculado na confirmação (não no processamento).';

COMMENT ON COLUMN public.catalog_import_row.decision_status IS
    'Decisão do administrador sobre esta linha. Único dos quatro estados que só o administrador altera.';

COMMENT ON COLUMN public.catalog_import_row.persistence_status IS
    'Resultado real da tentativa de persistência em public.card, gravado por admin_confirm_catalog_import().';

COMMENT ON COLUMN public.catalog_import_row.error_detail IS
    'Mensagem de erro específica desta linha quando persistence_status = FAILED. Isolada: nunca aborta as demais linhas.';

ALTER TABLE public.catalog_import_row ENABLE ROW LEVEL SECURITY;

CREATE POLICY catalog_admin_select ON public.catalog_import_row
    FOR SELECT USING (public.is_admin());

GRANT SELECT ON public.catalog_import_row TO authenticated;
GRANT INSERT, UPDATE ON public.catalog_import_row TO service_role;
