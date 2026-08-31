/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5010 - Create Physical Card Table
Versão......: 1.1
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-31 (revisado em COLLECTIONS-PHYSICAL-INCREMENT-01A-REVISION-01)

Descrição...:
Cria public.physical_card — exemplar físico individual (C-47/LDM-23),
cada cópia possuída é sua própria linha (sem coluna quantity).
inventory_id nulável — Physical Card pode existir sem Inventory
corrente (saída de custódia futura, fora de escopo desta fundação),
mas nunca perde a referência por um DELETE em cascata: FK em
ON DELETE RESTRICT, nunca SET NULL — mudança de custódia é sempre
uma operação de domínio explícita futura, nunca efeito colateral.

Índices revisados nesta rodada (COLLECTIONS-PHYSICAL-INCREMENT-01A-
REVISION-01, item 3): ix_physical_card_inventory_language substitui a
proposta original de índice isolado em language_id — todos os padrões
reais de acesso (inclusive a própria RLS) são sempre escopados por
Inventory primeiro; um índice isolado em language_id nunca seria
consultado sozinho nesse contexto, então seria overhead sem
consumidor real.

Regras de Negócio:
- card_variant_id/language_id NOT NULL, ON UPDATE/DELETE RESTRICT —
  nenhuma alteração/exclusão de catálogo pode invalidar silenciosamente
  um Physical Card existente;
- inventory_id NULL, ON UPDATE/DELETE RESTRICT — nulável por desenho
  (custódia pode não existir), mas nunca setado a NULL por um DELETE
  em cascata de Inventory;
- sem UNIQUE em (card_variant_id, language_id) — duplicatas são o
  comportamento esperado (múltiplas cópias físicas da mesma Card
  Variant/idioma);
- dois índices compostos, ambos liderados por inventory_id (padrão de
  acesso real, inclusive RLS): (inventory_id, card_variant_id) e
  (inventory_id, language_id); nenhum índice isolado em
  card_variant_id/language_id;
- RLS habilitado desde a criação; única policy é SELECT via subquery
  escalar contra inventory.owner_user_id — forma especificada
  explicitamente por Fabrício em
  COLLECTIONS-PHYSICAL-PREIMPLEMENTATION-GATE-01;
- nenhuma policy de INSERT/UPDATE/DELETE para authenticated — única
  via de escrita é a RPC add_physical_cards() (Query 5012).

CONFIRMADO EXECUTADO em 2026-08-31 (COLLECTIONS-PHYSICAL-INCREMENT-01B,
Fase 2) via apply_migration (versão de migration Supabase
20260831232056). Estrutura, índices, RLS e grants confirmados
fisicamente contra o banco. Performance dos dois índices compostos
confirmada por EXPLAIN (ANALYZE, BUFFERS) sobre volume sintético de
20.000 linhas em contexto reversível (Fase 4) — ver
database/validations/5801_performance_checks_collections_physical_
increment_01a.sql.
================================================================
*/

CREATE TABLE public.physical_card (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    card_variant_id UUID NOT NULL REFERENCES public.card_variant(id)
                        ON UPDATE RESTRICT ON DELETE RESTRICT,
    language_id     UUID NOT NULL REFERENCES public.language(id)
                        ON UPDATE RESTRICT ON DELETE RESTRICT,
    inventory_id    UUID NULL REFERENCES public.inventory(id)
                        ON UPDATE RESTRICT ON DELETE RESTRICT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE public.physical_card IS
    'Exemplar físico individual (C-47/LDM-23). Cada cópia possuída é sua própria linha — sem coluna quantity. inventory_id nulável por desenho (custódia pode não existir), mas nunca alterado por DELETE em cascata (ON DELETE RESTRICT).';

CREATE INDEX ix_physical_card_inventory_variant ON public.physical_card (inventory_id, card_variant_id);
CREATE INDEX ix_physical_card_inventory_language ON public.physical_card (inventory_id, language_id);

ALTER TABLE public.physical_card ENABLE ROW LEVEL SECURITY;

CREATE POLICY physical_card_select_own
    ON public.physical_card
    FOR SELECT
    USING (inventory_id = (SELECT i.id FROM public.inventory i WHERE i.owner_user_id = (select auth.uid())));

GRANT SELECT ON public.physical_card TO authenticated;

REVOKE TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON public.physical_card FROM anon, authenticated;
