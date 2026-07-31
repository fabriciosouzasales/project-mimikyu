/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2045 - Add Expansion Logo Column
Versão......: 1.0
Status......: MIGRATION
Autor.......: Fabrício Sales / Claude
Data........: 2026-07-31

Descrição...:
Adiciona a coluna expansion.logo_storage_path, responsável por armazenar
o caminho relativo (nunca uma URL completa) da logo oficial da Expansão
dentro do bucket dedicado expansion-logo (ver Query 2047). Mesmo padrão
já usado por card_set.logo_storage_path (Query 273, ADR-022) — numerada
aqui, no milhar 2000-2999, e não na faixa legada 200-299 (congelada,
STD-001 v1.x §10), pedido de Fabrício ("vamos incluir uma imagem para
cada expansão").

Regras de Negócio:
- logo_storage_path é opcional (NULL = Expansão ainda sem logo cadastrada).
- logo_storage_path nunca deve conter uma URL absoluta (http:// ou https://)
  — apenas o caminho relativo dentro do bucket expansion-logo.
- A escrita deste campo não ocorre por UPDATE direto da aplicação; é
  restrita à função administrativa admin_set_expansion_logo() (Query 2046).
================================================================
*/

begin;

alter table public.expansion
    add column logo_storage_path text null;

alter table public.expansion
    add constraint ck_expansion_logo_storage_path_not_url
    check (
        logo_storage_path is null
        or logo_storage_path !~* '^[a-z][a-z0-9+.-]*://'
    );

comment on column public.expansion.logo_storage_path is
    'Caminho relativo da logo oficial da Expansão dentro do bucket privado expansion-logo (nunca uma URL completa). NULL = Expansão ainda sem logo cadastrada. Escrita restrita à função admin_set_expansion_logo().';

commit;

-- ================================================================
-- Validação: aguardando execução por Fabrício. Sugestão de roteiro:
-- - information_schema.columns: logo_storage_path / text / nullable / sem
--   default.
-- - pg_constraint: ck_expansion_logo_storage_path_not_url presente,
--   definição exata: CHECK (((logo_storage_path IS NULL) OR
--   (logo_storage_path !~* '^[a-z][a-z0-9+.-]*://'::text))).
-- ================================================================
