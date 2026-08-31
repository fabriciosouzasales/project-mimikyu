/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5000 - Create Inventory Table
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-31

Descrição...:
Cria public.inventory — agregado patrimonial de ownership corrente,
1:1 por usuário (C-48/LDM-23). Identidade própria (id gerado), não
compartilha PK com auth.users — decisão revisada em
COLLECTIONS-PHYSICAL-MODELING-02 (Inventory é agregado de domínio,
não é o próprio User). 1:1 garantido por UNIQUE(owner_user_id), não
pelo PK.

Autoridade conceitual: C-47, C-48, LDM-23 (concept-decisions.md /
logical-model.md). Fundação física aprovada em
COLLECTIONS-PHYSICAL-MODELING-02 e liberada para implementação em
COLLECTIONS-PHYSICAL-PREIMPLEMENTATION-GATE-01 (READY FOR
IMPLEMENTATION, 2026-08-31) — Gate 1 confirmou ausência de qualquer
fluxo de account deletion no repositório/banco, o que viabiliza
ON DELETE RESTRICT em owner_user_id sem quebrar fluxo existente.

Regras de Negócio:
- owner_user_id é UNIQUE — garante exatamente 1 Inventory por User;
  o PK (id) é identidade própria do agregado, não emprestada de
  auth.users (contraste deliberado com o padrão de user_profile,
  justificado em COLLECTIONS-PHYSICAL-MODELING-02, item 1);
- ON DELETE RESTRICT em owner_user_id — nenhum DELETE em auth.users
  pode remover silenciosamente um Inventory com Physical Cards
  vinculados; exclusão de conta, se vier a existir, exigirá operação
  de domínio explícita antes (fora de escopo desta Query);
- RLS habilitado desde a criação; única policy é SELECT do próprio
  owner; nenhum INSERT/UPDATE/DELETE direto para authenticated —
  provisionamento é via trigger SECURITY DEFINER (Query 5002);
- GRANT mínimo (authenticated: SELECT; anon: nenhum); REVOKE de
  TRUNCATE/REFERENCES/TRIGGER/MAINTAIN mantido por consistência
  defensiva, ainda que redundante para tabelas criadas após a
  correção do default ACL (Query 2147, 2026-08-15 — ver
  COLLECTIONS-PHYSICAL-PREIMPLEMENTATION-GATE-01, Gate 4);
- nenhuma exclusão física prevista via CRUD de usuário; Inventory é
  agregado durável (C-48 — "não é histórico" não implica descartável).

CONFIRMADO EXECUTADO em 2026-08-31 (COLLECTIONS-PHYSICAL-INCREMENT-01B,
Fase 1) via apply_migration (versão de migration Supabase
20260831230314). Estrutura, RLS e grants confirmados fisicamente
contra o banco (information_schema/pg_policies/pg_class) na mesma
rodada — ver database/validations/5800_validate_collections_physical_
increment_01a.sql, itens 1-3.
================================================================
*/

CREATE TABLE public.inventory (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_user_id  UUID NOT NULL UNIQUE
                       REFERENCES auth.users(id)
                       ON UPDATE RESTRICT ON DELETE RESTRICT,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE public.inventory IS
    'Agregado patrimonial de ownership corrente, 1:1 por User (C-48/LDM-23). Não é histórico, não é Storage, não é Collection. Identidade própria (id), 1:1 garantido por UNIQUE(owner_user_id).';

ALTER TABLE public.inventory ENABLE ROW LEVEL SECURITY;

CREATE POLICY inventory_select_own
    ON public.inventory
    FOR SELECT
    USING (owner_user_id = (select auth.uid()));

GRANT SELECT ON public.inventory TO authenticated;

REVOKE TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON public.inventory FROM anon, authenticated;
