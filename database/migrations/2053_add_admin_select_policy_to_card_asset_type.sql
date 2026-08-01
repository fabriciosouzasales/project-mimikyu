/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 2053 - Add Admin SELECT Policy to Card Asset Type
Versão......: 1.0
Status......: MIGRATION
Autor.......: Fabrício Sales / Claude
Data........: 2026-07-31

Descrição:
Concede leitura (SELECT) de public.card_asset_type exclusivamente a
administradores — mesmo padrão da Query 274 (ADR-022: leitura do Catálogo
Editorial é liberada tabela a tabela, apenas onde uma tela real consulta).

Causa raiz: a galeria de Cartas (`/catalogo/cartas`, subciclo Card,
2026-07-31) é a primeira tela real a consultar `card_asset_type` — ela
precisa resolver qual `card_asset` de cada Card é a imagem CARD_FRONT
principal (`getCartasCompletas()`, `web/lib/catalogo/queries.ts`, embed
`card_asset(..., card_asset_type(code), ...)`). A Query 274 (2026-07-26)
deliberadamente NÃO cobriu `card_asset_type` porque, na época, nenhuma tela
o consultava — confirmado no próprio comentário daquela migration. Sem
política de SELECT, RLS bloqueia silenciosamente o embed aninhado: a query
falha, `getCartasCompletas()` retorna lista vazia, e a tela mostra "Nenhuma
carta catalogada" mesmo em Card Sets com cartas reais — sintoma relatado por
Fabrício em 2026-07-31 ("as cartas não são listadas").

Regras de Negócio:
- Uma única política de SELECT, USING (is_admin()) — mesma função já usada
  pela Query 274 e por toda a autorização administrativa do projeto
  (ADR-021).
- GRANT SELECT concedido à role authenticated — sem o GRANT de nível de
  tabela do PostgreSQL, a política de RLS nunca chega a ser avaliada (mesmo
  gap já documentado nas Queries 250/253/254/272/274).
- Nenhuma política de INSERT/UPDATE/DELETE é criada por esta Query —
  `card_asset_type` continua sem nenhuma via de escrita administrativa
  (fora de escopo; nenhuma tela cadastra/edita tipos de ativo hoje).

Pré-requisitos:
- Query 170 - Create Card Asset Type Table.
- Query 1060 - Create is_admin() Function.
- Query 274 - Add Admin-Only SELECT Policies to Catalog Tables (mesmo
  padrão, tabelas irmãs já cobertas).
===============================================================================
*/

begin;

create policy catalog_admin_select on public.card_asset_type
    for select using (is_admin());
grant select on public.card_asset_type to authenticated;

commit;
