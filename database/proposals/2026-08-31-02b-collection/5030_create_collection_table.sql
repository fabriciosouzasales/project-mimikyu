/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5030 - Create Collection Table (PROPOSTA)
Versão......: 1.0
Status......: PROPOSTA — NÃO EXECUTADA
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-31 (COLLECTIONS-PHYSICAL-INCREMENT-02B-MODELING-01
               → -REVISION-01 → -FINAL-01)

Descrição...:
Cria public.collection — identidade própria (id gerado), ownership
direto por owner_user_id (NÃO mediado por Inventory — decisão distinta
da usada em Storage Container, já fixada em LDM-02/C-141 e não
reaberta nesta rodada). Skeleton físico do núcleo de LDM-12,
restringindo deliberadamente o escopo desta primeira materialização.

Autoridade conceitual: C-01 a C-37 (núcleo Collection), C-141 (Owner
estrutural), LDM-01 a LDM-27 (checkpoint lógico), LDM-12 (skeleton).
Precedida por Inventory + Physical Card (COLLECTIONS-PHYSICAL-
INCREMENT-01B, CONFIRMADO EXECUTADO 2026-08-31) e por Storage
Foundation (COLLECTIONS-PHYSICAL-INCREMENT-02A-IMPLEMENTATION-01,
CONFIRMADO EXECUTADO 2026-09-01) — este incremento (2B) depende de
storage_container já existir fisicamente, porque
default_storage_container_id é NOT NULL desde a criação (C-36).

Campos preservados exatamente conforme LDM-12, com exclusões
explícitas: id (identidade própria), owner_user_id NOT NULL, game_id
NOT NULL, default_storage_container_id NOT NULL, name, description,
mode, lifecycle_status, visibility, reference_locked_at, archived_at,
created_at, updated_at. SEM started_at (C-30/LDM-11 — primeira
alocação não existe ainda), SEM created_by_user_id/updated_by_user_id,
SEM completion_policy (LDM-08 — semanticamente vazio sem Collection
Reference; deferido para quando essa entidade existir), SEM Collection
Reference, Allocation, Membership, Layout — nenhuma tabela/coluna
criada para eles nesta rodada.

Regras de Negócio (constraints):
- chk_collection_mode: fisicamente só 'OPEN_CURATION' nesta etapa
  (decisão já fixada em COLLECTIONS-PHYSICAL-MODELING-03-REVISION-02,
  não reaberta) — CHECK de valor único, alargável por
  DROP+ADD CONSTRAINT quando Collection Reference existir e
  REFERENCE_BASED puder ser liberado;
- chk_collection_lifecycle_status: 'ACTIVE'/'ARCHIVED' (C-30/LDM-09);
- chk_collection_visibility: fisicamente só 'PRIVATE' nesta etapa
  (COLLECTIONS-PHYSICAL-INCREMENT-02B-MODELING-REVISION-01, item 1) —
  Public Access (C-15) não tem projeção/read model seguro implementado
  ainda; nenhuma Collection pode declarar um estado PUBLIC sem efeito
  real. Constraint alargada para 'PRIVATE'/'PUBLIC' só quando essa
  projeção existir, e só então set_collection_visibility() será
  criada — nenhuma das duas nesta rodada;
- chk_collection_name_not_blank: nome obrigatório e não-vazio após
  btrim(), mesmo padrão de create_storage_container();
- chk_collection_archived_at_consistency: archived_at
  IS NULL quando ACTIVE, IS NOT NULL quando ARCHIVED — defesa em
  profundidade, não confia apenas nas RPCs de archive/reactivate para
  manter os dois campos em sincronia;
- chk_collection_reference_locked_at_null: reference_locked_at
  IS NULL — hardening temporário
  (COLLECTIONS-PHYSICAL-INCREMENT-02B-MODELING-FINAL-01, item 1). A
  coluna existe fisicamente (evita ALTER TABLE futuro quando 2C
  chegar), mas Collection Allocation ainda não existe e nenhum estado
  legítimo deste incremento pode preenchê-la — nenhum caminho
  privilegiado futuro pode criar uma Collection com Reference Lock sem
  a operação de domínio correspondente (LDM-07: consolidação ocorre na
  primeira alocação efetiva). Esta CHECK será conscientemente removida
  ou revisada no Incremento 2C, quando a primeira Collection Allocation
  passar a controlar reference_locked_at — não antes, e não
  silenciosamente.

owner_user_id e game_id NÃO têm enforcement de imutabilidade nesta
Query — a garantia estrutural correspondente é responsabilidade da
Query 5032 (trigger de Structural Identity), não de um CHECK (CHECK não
pode comparar OLD/NEW; exige trigger).

RLS habilitado desde a criação; única policy é SELECT do próprio owner
— mesmo padrão de inventory/storage_container. Nenhuma policy de
INSERT/UPDATE/DELETE para authenticated; toda escrita passa pelas RPCs
SECURITY DEFINER (Queries 5034-5039). GRANT mínimo (authenticated:
SELECT; anon: nenhum); REVOKE de TRUNCATE/REFERENCES/TRIGGER/MAINTAIN
mantido por consistência defensiva, mesmo padrão de 5000/5020.

STATUS DESTA QUERY: PROPOSTA — NÃO EXECUTADA.
================================================================
*/

CREATE TABLE public.collection (
    id                           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_user_id                UUID NOT NULL
                                     REFERENCES auth.users(id)
                                     ON UPDATE RESTRICT ON DELETE RESTRICT,
    game_id                      UUID NOT NULL
                                     REFERENCES public.game(id)
                                     ON UPDATE RESTRICT ON DELETE RESTRICT,
    default_storage_container_id UUID NOT NULL
                                     REFERENCES public.storage_container(id)
                                     ON UPDATE RESTRICT ON DELETE RESTRICT,
    name                         TEXT NOT NULL,
    description                  TEXT NULL,
    mode                         TEXT NOT NULL DEFAULT 'OPEN_CURATION',
    lifecycle_status             TEXT NOT NULL DEFAULT 'ACTIVE',
    visibility                   TEXT NOT NULL DEFAULT 'PRIVATE',
    reference_locked_at          TIMESTAMPTZ NULL,
    archived_at                  TIMESTAMPTZ NULL,
    created_at                   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at                   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE public.collection IS
    'Estrutura persistente de organização de exemplares efetivamente possuídos (C-01). Ownership direto via owner_user_id (LDM-02/C-141), NÃO mediado por Inventory. mode fisicamente restrito a OPEN_CURATION e visibility a PRIVATE nesta etapa (2B) — ver chk_collection_mode/chk_collection_visibility.';

ALTER TABLE public.collection
    ADD CONSTRAINT chk_collection_mode
    CHECK (mode IN ('OPEN_CURATION'));

ALTER TABLE public.collection
    ADD CONSTRAINT chk_collection_lifecycle_status
    CHECK (lifecycle_status IN ('ACTIVE', 'ARCHIVED'));

ALTER TABLE public.collection
    ADD CONSTRAINT chk_collection_visibility
    CHECK (visibility IN ('PRIVATE'));

ALTER TABLE public.collection
    ADD CONSTRAINT chk_collection_name_not_blank
    CHECK (btrim(name) <> '');

ALTER TABLE public.collection
    ADD CONSTRAINT chk_collection_archived_at_consistency
    CHECK (
        (lifecycle_status = 'ACTIVE'   AND archived_at IS NULL)
        OR
        (lifecycle_status = 'ARCHIVED' AND archived_at IS NOT NULL)
    );

ALTER TABLE public.collection
    ADD CONSTRAINT chk_collection_reference_locked_at_null
    CHECK (reference_locked_at IS NULL);

CREATE INDEX ix_collection_owner_lifecycle
    ON public.collection (owner_user_id, lifecycle_status);

ALTER TABLE public.collection ENABLE ROW LEVEL SECURITY;

CREATE POLICY collection_select_own
    ON public.collection FOR SELECT
    USING (owner_user_id = (select auth.uid()));

GRANT SELECT ON public.collection TO authenticated;

REVOKE TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON public.collection FROM anon, authenticated;
