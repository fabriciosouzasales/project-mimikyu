-- ============================================================================
-- ARQUIVO RECONSTRUIDO RETROATIVAMENTE A PARTIR DO HISTORICO OFICIAL
-- (supabase_migrations.schema_migrations) -- nunca reexecutado; o SQL abaixo e
-- o statement armazenado, sem qualquer alteracao.
-- version: 20260816232331
-- Recuperado em: 2026-08-17
-- ============================================================================

/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 3010 - Create Card Condition Table
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Claude (agente responsável pela documentação e schema)
Data........: 2026-08-16

Descrição...:
Cria a tabela public.card_condition — catálogo canônico de condições
físicas de conservação (Near Mint, Lightly Played, ...). card_condition
é uma referência conceitualmente compartilhada e neutra — não pertence
ao domínio Pricing nem ao Catálogo Editorial (ver ADR-029 e
docs/05f-pricing.md, correção de precisão versão 1.1). Sua numeração
dentro de 3000-3999 (milhar de Pricing) registra apenas o ciclo que
realizou sua primeira implementação física — não transfere a entidade
para o domínio Pricing, nem cria dependência conceitual de Ownership
(futuro collection_item) em Pricing. Decisão explícita de Fabrício
(2026-08-16): o intervalo 4000-4999 permanece livre e não deve ser
reservado; um módulo próprio de "Referências Compartilhadas" só será
criado quando existir um conjunto real de entidades/responsabilidades
que o justifique. Futuras entidades compartilhadas não devem ser
automaticamente colocadas em 3000-3999 só por precedente desta Query.

Regras de Negócio:
- code único, imutável após criação, maiúsculo;
- condition_order único e positivo;
- nenhuma exclusão física prevista — catálogo estável, gerido por seed/
  migration, não por CRUD administrativo em tempo de execução (nenhum
  CRUD administrativo é criado nesta Query — fora de escopo deste
  incremento);
- RLS habilitado desde a criação; única policy é leitura administrativa
  (card_condition_admin_select) — nome deliberadamente sem prefixo
  "pricing_", por ser referência compartilhada, não exclusiva de
  Pricing; nenhuma policy de leitura para usuário final é criada nesta
  Query (fora de escopo deste incremento);
- GRANT mínimo (authenticated: SELECT; anon: nenhum) e REVOKE de
  TRUNCATE/REFERENCES/TRIGGER/MAINTAIN de anon/authenticated, aplicados
  desde o nascimento da tabela (STD-001, revisão 1.19).
================================================================
*/

CREATE TABLE public.card_condition (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code             TEXT NOT NULL,
    name             TEXT NOT NULL,
    condition_order  INTEGER NOT NULL,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_card_condition_code UNIQUE (code),
    CONSTRAINT uq_card_condition_order UNIQUE (condition_order),
    CONSTRAINT ck_card_condition_code_format
        CHECK (code = UPPER(code) AND code ~ '^[A-Z][A-Z0-9_]*$'),
    CONSTRAINT ck_card_condition_name_not_blank CHECK (BTRIM(name) <> ''),
    CONSTRAINT ck_card_condition_order_positive CHECK (condition_order > 0)
);

COMMENT ON TABLE public.card_condition IS
    'Referência compartilhada e neutra (não exclusiva de Pricing) — catálogo canônico de condições físicas de conservação. Numerada em 3000-3999 apenas por registrar o ciclo de implementação (Incremento P1 de Pricing); não indica pertencimento de domínio. Consumida por pricing_condition_mapping/pricing_observation hoje; por collection_item no futuro. Ver ADR-029 e docs/05f-pricing.md.';

ALTER TABLE public.card_condition ENABLE ROW LEVEL SECURITY;

CREATE POLICY card_condition_admin_select
    ON public.card_condition
    FOR SELECT
    USING ((select is_admin()));

GRANT SELECT ON public.card_condition TO authenticated;

REVOKE TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON public.card_condition FROM anon, authenticated;
