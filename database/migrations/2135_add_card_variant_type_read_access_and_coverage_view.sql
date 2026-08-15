/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2135 - Add Card Variant Type Read Access and Coverage View
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO (via MCP do Supabase, projeto qjfutqujxrbzgrtkpgkg)
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-14

Descrição...:
Primeiro incremento técnico do bloco Card Variant (ver ADR-028, ROADMAP.md),
depois do checkpoint que auditou o estado real de card_variant/card_variant_type
(docs/log.md, mesma data). Duas mudanças aditivas, nenhuma altera estrutura ou
dado existente de card_variant:

1. Leitura administrativa de card_variant_type — mesmo padrão ADR-022/Query 274
   (tabela a tabela, só porque uma tela real vai consultar agora), com uma
   diferença deliberada: usa (select is_admin()) desde a criação, não a chamada
   nua is_admin() que a Query 274 usava em 2026-07-26 — is_admin() já é STABLE
   desde a Query 2134 (2026-08-14, mesma data), então esta policy nasce com o
   InitPlan/One-Time Filter correto, sem precisar do hardening retroativo que
   as outras 24 policies do catálogo precisaram. card_variant_type tinha RLS
   habilitado desde a Query 150 (2026-07-18) mas nenhuma policy e nenhum GRANT
   — ninguém, nem admin, conseguia ler; achado confirmado no checkpoint.

2. View catalog_card_set_variant_coverage — mesmo padrão de
   catalog_card_set_metrics/catalog_card_set_image_coverage (ADR-027, Query
   2123): security_invoker = true, GRANT SELECT só para authenticated. Grão =
   1 linha por Card Set (43 linhas hoje, sempre um total pequeno e fixo,
   independente do volume de Cards — compatível com escala de 20.000+ Cards
   por construção, já que a agregação roda inteira no Postgres e nada é
   trazido linha a linha). Reaproveita catalog_card_set_metrics via JOIN para
   card_set_id/code/name/cards_cadastradas, em vez de recalcular — não
   duplica a definição de "Cards cadastradas" pela segunda vez. cards_com_
   variante conta Cards com pelo menos uma linha em card_variant, via
   Index Only Scan sobre ix_card_variant_card_id (já existente, Query 160) —
   nenhum índice novo necessário.

Regras de Negócio:
- Nenhuma escrita, nenhuma alteração de card_variant/card_variant_type nesta
  Query — só leitura administrativa nova e uma view derivada.
- GRANT SELECT restrito a authenticated nas duas mudanças — nunca anon, nunca
  PUBLIC.
- Nenhuma inferência de variante: a view só reporta o que já está cadastrado
  em card_variant, não estima nem sugere variantes ausentes.

Validação de segurança (2026-08-14, mesma sessão):
- pg_policies: catalog_admin_select em card_variant_type, USING
  ((select is_admin())).
- information_schema.role_table_grants: SELECT concedido a authenticated em
  card_variant_type e catalog_card_set_variant_coverage; nenhum grant para
  anon em nenhuma das duas.
- pg_class.reloptions: security_invoker=true confirmado na view nova.
- authenticated não-admin (SET LOCAL ROLE, dentro de BEGIN...ROLLBACK): 0
  linhas em card_variant_type e em catalog_card_set_variant_coverage — RLS
  efetiva mesmo atravessando a view aninhada (catalog_card_set_metrics já é
  security_invoker também).
- anon (SET LOCAL ROLE, dentro de BEGIN...ROLLBACK): permission denied em
  card_variant_type — sem GRANT, RLS nunca chega a ser avaliada.

Validação de performance (2026-08-14, mesma sessão, EXPLAIN ANALYZE BUFFERS):
- catalog_card_set_variant_coverage: 43 linhas, Execution Time 9,093 ms,
  Index Only Scan em ix_card_variant_card_id e no índice de card, sem
  Seq Scan custoso, sem N+1 — uma única leitura server-side, independente de
  quantas Cards existirem no catálogo.

Pré-requisitos:
- Query 150 - Create Card Variant Type Table.
- Query 160 - Create Card Variant Table (ix_card_variant_card_id).
- Query 274 - Add Admin-Only SELECT Policies to Catalog Tables (padrão de
  referência).
- Query 2123/2124 - Catalog Card Set Metrics Views (catalog_card_set_metrics,
  reaproveitada por JOIN).
- Query 2134 - Harden is_admin() RLS Performance (is_admin() já STABLE).
================================================================
*/

begin;

create policy catalog_admin_select on public.card_variant_type
    for select using ((select is_admin()));

grant select on public.card_variant_type to authenticated;

create or replace view public.catalog_card_set_variant_coverage
with (security_invoker = true) as
select
    m.card_set_id,
    m.card_set_code,
    m.card_set_name,
    m.cards_cadastradas,
    coalesce(variant_counts.cards_com_variante, 0) as cards_com_variante,
    m.cards_cadastradas - coalesce(variant_counts.cards_com_variante, 0) as cards_sem_variante
from public.catalog_card_set_metrics m
left join (
    select
        crd.card_set_id,
        count(distinct crd.id) as cards_com_variante
    from public.card crd
    join public.card_variant cv
        on cv.card_id = crd.id
    group by crd.card_set_id
) as variant_counts
    on variant_counts.card_set_id = m.card_set_id;

comment on view public.catalog_card_set_variant_coverage is
    'Cobertura de Card Variant por Card Set, grão = 1 linha por Card Set (43 linhas, independente do volume de Cards). security_invoker = true, mesma justificativa de catalog_card_set_metrics. cards_cadastradas reaproveitado de catalog_card_set_metrics (não recalculado).';

comment on column public.catalog_card_set_variant_coverage.cards_com_variante is
    'COUNT(DISTINCT card.id) do Card Set com pelo menos uma linha em card_variant.';

comment on column public.catalog_card_set_variant_coverage.cards_sem_variante is
    'cards_cadastradas - cards_com_variante. Cards do Card Set ainda sem nenhuma Card Variant cadastrada.';

grant select on public.catalog_card_set_variant_coverage to authenticated;

commit;

-- ================================================================
-- Confirmado executado (2026-08-14, via execute_sql/MCP do Supabase) e
-- validado: policy/grant de card_variant_type e da view nova conferidos
-- contra pg_policies/information_schema/pg_class; RLS efetiva testada com
-- SET LOCAL ROLE authenticated (0 linhas) e anon (permission denied), dentro
-- de BEGIN...ROLLBACK, nenhuma identidade real usada. EXPLAIN ANALYZE
-- BUFFERS confirmou 9,093 ms para as 43 linhas da view, usando os índices já
-- existentes. Ver docs/log.md para o relatório completo.
-- ================================================================

-- ================================================================
-- ROLLBACK (não executado, documentado para reversão futura se necessário):
--
-- begin;
-- drop view if exists public.catalog_card_set_variant_coverage;
-- revoke select on public.card_variant_type from authenticated;
-- drop policy if exists catalog_admin_select on public.card_variant_type;
-- commit;
-- ================================================================
