/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 6100 - Create Pokemon Catalog Sourcing Run Table
Versão......: 1.1 (PROPOSTA — GATE 3 STAGING, REVISION-01)
Status......: PROPOSTO / NÃO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-04 (staging em POKEMON-CATALOG-SOURCING-INITIAL-LOAD-
               PHYSICAL-STAGING-01, materializando docs/06a-pokemon-catalog-
               sourcing.md v1.1, Seção 7; revisado em ...-STAGING-REVISION-01
               após GATE 4 apontar que nada nesta tabela impedia um run
               DRY_RUN de entrar em APPLYING — o espelho exato do que a CHECK
               ck_pokemon_catalog_sourcing_run_apply_never_dry_states já fazia
               para o outro sentido)

REVISION-01 — o que mudou: adicionada
ck_pokemon_catalog_sourcing_run_dry_run_never_applying, fechando o fluxo
fisicamente nos DOIS sentidos (DRY_RUN nunca ACQUIRING/PLANNING/APPLYING
trocado por: DRY_RUN nunca APPLYING; APPLY nunca ACQUIRING/PLANNING/CWD — já
existia). Reforço espelhado na máquina de estados (Query 6101 REVISION-01),
por exigência explícita do GATE 4 ("preferir enforcement tanto em CHECK
quanto na máquina de estados").

Descrição resumida:
Run ledger do Pokémon Catalog Sourcing — mesmo papel de asset_import_run
(Query 220), adaptado ao fluxo dual DRY_RUN/APPLY exigido pela Seção 7.1 do
contrato canônico (docs/06a-pokemon-catalog-sourcing.md).

Regras de Negócio (literais do contrato 06a, Seção 7):
- run_code gerado server-side, formato RUN-AAAAMMDD-NNNNNNNN (mesmo padrão de
  asset_import_run/Query 220), nunca informado pelo caller.
- run_type ∈ {DRY_RUN, APPLY}.
- Fluxo DRY_RUN: PENDING → ACQUIRING → PLANNING → COMPLETED |
  COMPLETED_WITH_DIVERGENCES.
- Fluxo APPLY: PENDING → APPLYING → COMPLETED (nunca entra em ACQUIRING,
  PLANNING ou COMPLETED_WITH_DIVERGENCES — CHECK
  ck_pokemon_catalog_sourcing_run_apply_never_dry_states; e DRY_RUN nunca
  entra em APPLYING — CHECK ck_pokemon_catalog_sourcing_run_dry_run_never_
  applying, adicionada na REVISION-01). Ambas as CHECKs são espelhadas na
  máquina de estados (Query 6101).
- ACTIVE = {PENDING, ACQUIRING, PLANNING, APPLYING}; TERMINAL = {COMPLETED,
  COMPLETED_WITH_DIVERGENCES, FAILED, CANCELLED} — todo TERMINAL exige
  finished_at NOT NULL.
- Um APPLY exige preflight_run_id apontando para um DRY_RUN; um DRY_RUN nunca
  tem preflight_run_id (CHECK ck_..._preflight_by_type).
- Todo DRY_RUN que termina em COMPLETED ou COMPLETED_WITH_DIVERGENCES exige
  snapshot_hash NOT NULL (CHECK ck_..._dry_run_completed_hash) — hash SHA-256
  lowercase, formato ^[0-9a-f]{64}$.
- Apenas um run ATIVO por asset_source_id — índice UNIQUE parcial
  (uq_pokemon_catalog_sourcing_run_active_source), garantindo o guard de
  concorrência SOURCE_BUSY exigido pela Seção 7.2 (violação de unicidade na
  tentativa de claim).
- plan_summary/apply_summary, quando presentes, são sempre objeto JSON (nunca
  array/escalar) — payload por família (Seção 9/10).
- error_summary nunca vazio quando presente.

Índices:
- uq_pokemon_catalog_sourcing_run_active_source: UNIQUE parcial em
  (asset_source_id) WHERE status IN ACTIVE — é o próprio mecanismo de
  concorrência exigido pelo contrato (SOURCE_BUSY via unique_violation), não
  um índice de performance especulativo. Sem este índice, dois runs
  concorrentes para a mesma Fonte poderiam coexistir.
- Nenhum outro índice — run_code já é UNIQUE (índice implícito da constraint);
  nenhum índice adicional por status/run_type/asset_source_id justificado
  nesta rodada por ausência de padrão de acesso PLAN/APPLY demonstrável que o
  exija (volume de linhas desta tabela é operacional, não de catálogo).

Grants (auditoria explícita desta rodada — Seção 13/14 do contrato):
- service_role recebe SOMENTE SELECT direto na tabela — necessário para o
  script chamador (Deno) poder consultar o estado de um run já aberto (ex.:
  polling, diagnóstico, resolução de preflight_run_id de um DRY_RUN anterior)
  sem depender de as RPCs retornarem tudo em toda chamada. NENHUM
  INSERT/UPDATE/DELETE direto é concedido a service_role: toda escrita no run
  ledger flui exclusivamente pelas RPCs SECURITY DEFINER (open_run/PLAN/APPLY,
  Query 6103/6104/6105), que executam como o owner da função (não dependem de
  GRANT de tabela). Esta é a decisão explícita exigida pela Seção 14 do 06a
  ("service_role pode possuir SOMENTE grants mínimos explicitamente definidos
  e auditados no GATE 3 STAGING — nunca acesso irrestrito").
- PUBLIC/anon/authenticated: nenhum grant. RLS habilitado sem policy fecha
  SELECT/INSERT/UPDATE/DELETE por completo para quem não faz bypass de RLS;
  REVOKE explícito de TRUNCATE/REFERENCES/TRIGGER/MAINTAIN cobre o que RLS não
  alcança (mesmo padrão de 6070/2147). service_role no Supabase possui
  BYPASSRLS — por isso o grant de SELECT a service_role é uma decisão de
  privilégio real, não cosmética, e está documentada aqui explicitamente.

Pré-requisitos:
- Query 200 - Create Asset Source Table (CONFIRMADO EXECUTADO).
- Query 220 - Create Asset Import Run (precedente físico do padrão run_code).
===============================================================================
*/

BEGIN;

CREATE SEQUENCE public.pokemon_catalog_sourcing_run_code_seq
    AS BIGINT
    START WITH 1
    INCREMENT BY 1
    MINVALUE 1
    NO MAXVALUE
    CACHE 20;

CREATE TABLE public.pokemon_catalog_sourcing_run (
    id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    run_code              TEXT NOT NULL DEFAULT (
                              'RUN-' || TO_CHAR(CLOCK_TIMESTAMP(), 'YYYYMMDD') || '-' ||
                              LPAD(NEXTVAL('public.pokemon_catalog_sourcing_run_code_seq'::REGCLASS)::TEXT, 8, '0')
                          ),

    asset_source_id       UUID NOT NULL
                              REFERENCES public.asset_source (id)
                              ON DELETE RESTRICT,

    run_type              TEXT NOT NULL,
    preflight_run_id      UUID
                              REFERENCES public.pokemon_catalog_sourcing_run (id)
                              ON DELETE RESTRICT,

    status                TEXT NOT NULL DEFAULT 'PENDING',

    snapshot_hash         TEXT,
    plan_summary          JSONB,
    apply_summary         JSONB,
    error_summary         TEXT,

    heartbeat_at          TIMESTAMPTZ,
    started_at            TIMESTAMPTZ,
    finished_at           TIMESTAMPTZ,

    created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_pokemon_catalog_sourcing_run_code
        UNIQUE (run_code),

    CONSTRAINT ck_pokemon_catalog_sourcing_run_code_format
        CHECK (run_code ~ '^RUN-[0-9]{8}-[0-9]{8,}$'),
    CONSTRAINT ck_pokemon_catalog_sourcing_run_type
        CHECK (run_type IN ('DRY_RUN', 'APPLY')),
    CONSTRAINT ck_pokemon_catalog_sourcing_run_status
        CHECK (status IN (
            'PENDING', 'ACQUIRING', 'PLANNING', 'APPLYING',
            'COMPLETED', 'COMPLETED_WITH_DIVERGENCES', 'FAILED', 'CANCELLED'
        )),
    CONSTRAINT ck_pokemon_catalog_sourcing_run_preflight_by_type
        CHECK (
            (run_type = 'DRY_RUN' AND preflight_run_id IS NULL)
            OR (run_type = 'APPLY' AND preflight_run_id IS NOT NULL)
        ),
    CONSTRAINT ck_pokemon_catalog_sourcing_run_snapshot_hash_format
        CHECK (snapshot_hash IS NULL OR snapshot_hash ~ '^[0-9a-f]{64}$'),
    CONSTRAINT ck_pokemon_catalog_sourcing_run_plan_summary_object
        CHECK (plan_summary IS NULL OR JSONB_TYPEOF(plan_summary) = 'object'),
    CONSTRAINT ck_pokemon_catalog_sourcing_run_apply_summary_object
        CHECK (apply_summary IS NULL OR JSONB_TYPEOF(apply_summary) = 'object'),
    CONSTRAINT ck_pokemon_catalog_sourcing_run_error_summary_not_blank
        CHECK (error_summary IS NULL OR BTRIM(error_summary) <> ''),
    CONSTRAINT ck_pokemon_catalog_sourcing_run_terminal_finished_at
        CHECK (
            status NOT IN ('COMPLETED', 'COMPLETED_WITH_DIVERGENCES', 'FAILED', 'CANCELLED')
            OR finished_at IS NOT NULL
        ),
    CONSTRAINT ck_pokemon_catalog_sourcing_run_dry_run_completed_hash
        CHECK (
            NOT (
                run_type = 'DRY_RUN'
                AND status IN ('COMPLETED', 'COMPLETED_WITH_DIVERGENCES')
                AND snapshot_hash IS NULL
            )
        ),
    CONSTRAINT ck_pokemon_catalog_sourcing_run_apply_never_dry_states
        CHECK (NOT (run_type = 'APPLY' AND status IN ('ACQUIRING', 'PLANNING', 'COMPLETED_WITH_DIVERGENCES'))),
    CONSTRAINT ck_pokemon_catalog_sourcing_run_dry_run_never_applying
        CHECK (NOT (run_type = 'DRY_RUN' AND status = 'APPLYING')),
    CONSTRAINT ck_pokemon_catalog_sourcing_run_period
        CHECK (finished_at IS NULL OR started_at IS NULL OR finished_at >= started_at)
);

ALTER SEQUENCE public.pokemon_catalog_sourcing_run_code_seq
    OWNED BY public.pokemon_catalog_sourcing_run.run_code;

-- Guard de concorrência exigido pela Seção 7.2 do contrato: no máximo um run
-- ATIVO por asset_source_id. A tentativa concorrente de claim colide aqui
-- (unique_violation), traduzida pela RPC open_run (Query 6103) em SOURCE_BUSY.
CREATE UNIQUE INDEX uq_pokemon_catalog_sourcing_run_active_source
    ON public.pokemon_catalog_sourcing_run (asset_source_id)
    WHERE status IN ('PENDING', 'ACQUIRING', 'PLANNING', 'APPLYING');

COMMENT ON TABLE public.pokemon_catalog_sourcing_run IS
    'Run ledger do Pokémon Catalog Sourcing (PokéAPI). Fluxo dual DRY_RUN/APPLY conforme docs/06a-pokemon-catalog-sourcing.md Seção 7. Proposta GATE 3 STAGING.';
COMMENT ON COLUMN public.pokemon_catalog_sourcing_run.run_code IS
    'Gerado server-side via sequence, formato RUN-AAAAMMDD-NNNNNNNN. Nunca informado pelo caller.';
COMMENT ON COLUMN public.pokemon_catalog_sourcing_run.snapshot_hash IS
    'SHA-256 lowercase (64 hex) do snapshot determinístico, calculado por public.compute_pokemon_catalog_sourcing_snapshot_hash (Query 6102).';

ALTER TABLE public.pokemon_catalog_sourcing_run ENABLE ROW LEVEL SECURITY;

REVOKE TRUNCATE, REFERENCES, TRIGGER, MAINTAIN
    ON public.pokemon_catalog_sourcing_run
    FROM anon, authenticated;

-- Grant mínimo explícito (ver "Grants" no cabeçalho acima): apenas leitura
-- direta para service_role. Toda escrita flui pelas RPCs SECURITY DEFINER.
GRANT SELECT ON public.pokemon_catalog_sourcing_run TO service_role;

COMMIT;
