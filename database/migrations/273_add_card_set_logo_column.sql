/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 273 - Add Card Set Logo Column
Versão......: 1.0
Status......: MIGRATION
Autor.......: Fabrício Sales / Claude
Data........: 2026-07-26

Descrição...:
Adiciona a coluna card_set.logo_storage_path, responsável por armazenar o
caminho relativo (nunca uma URL completa) da logo oficial do Card Set dentro
do bucket dedicado card-set-logo (ver Query 276). Parte da fundação de
autorização e infraestrutura do Catálogo Editorial aprovada em ADR-022.

Regras de Negócio:
- logo_storage_path é opcional (NULL = Card Set ainda sem logo cadastrada).
- logo_storage_path nunca deve conter uma URL absoluta (http:// ou https://)
  — apenas o caminho relativo dentro do bucket card-set-logo.
- A escrita deste campo não ocorre por UPDATE direto da aplicação; é
  restrita à função administrativa admin_set_card_set_logo() (Query 275).
================================================================
*/

begin;

alter table public.card_set
    add column logo_storage_path text null;

alter table public.card_set
    add constraint ck_card_set_logo_storage_path_not_url
    check (
        logo_storage_path is null
        or logo_storage_path !~* '^[a-z][a-z0-9+.-]*://'
    );

comment on column public.card_set.logo_storage_path is
    'Caminho relativo da logo oficial do Card Set dentro do bucket privado card-set-logo (nunca uma URL completa). NULL = Card Set ainda sem logo cadastrada. Escrita restrita à função admin_set_card_set_logo().';

commit;

-- ================================================================
-- Validação executada e confirmada (2026-07-26):
-- - information_schema.columns: logo_storage_path / text / nullable / sem default.
-- - pg_constraint: ck_card_set_logo_storage_path_not_url presente, definição
--   exata: CHECK (((logo_storage_path IS NULL) OR (logo_storage_path !~*
--   '^[a-z][a-z0-9+.-]*://'::text))).
-- ================================================================
