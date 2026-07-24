-- Project Mimikyu
-- Query 240 - Create Card Set External Reference
-- Status: CONFIRMADA EXECUTADA ("Success. No rows returned")
-- Ver docs/05-modelo-de-dados.md, seção "Card Set External Reference", para o
-- contexto completo da decisão de modelagem.
--
-- Mapeia um card_set interno para seu identificador em uma fonte externa
-- (TCGdex, Pokémon TCG API etc.), mesmo padrão já usado por
-- card_external_reference para card — mas deliberadamente mais enxuta:
-- sem external_card_id (não se aplica a Set) e sem image_source_url (o
-- Pipeline Automático de Imagens baixa imagens de cartas, não de Sets).
--
-- Esta migration cria somente a estrutura. Normalização de dados, governança
-- e atualização automática de updated_at ficam para a Query 241 (ainda não
-- executada).

begin;

create table public.card_set_external_reference (
    id uuid not null default gen_random_uuid(),
    card_set_id uuid not null,
    asset_source_id uuid not null,
    external_set_id text not null,
    source_url text null,
    metadata jsonb not null default '{}'::jsonb,
    is_active boolean not null default true,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint card_set_external_reference_pkey
        primary key (id),
    constraint fk_card_set_external_reference_card_set
        foreign key (card_set_id)
        references public.card_set (id)
        on delete cascade,
    constraint fk_card_set_external_reference_asset_source
        foreign key (asset_source_id)
        references public.asset_source (id)
        on delete restrict,
    constraint uq_card_set_external_reference_card_set_source
        unique (card_set_id, asset_source_id),
    constraint uq_card_set_external_reference_source_external
        unique (asset_source_id, external_set_id),
    constraint ck_card_set_external_reference_external_set_id
        check (btrim(external_set_id) <> ''),
    constraint ck_card_set_external_reference_source_url
        check (
            source_url is null
            or (
                btrim(source_url) <> ''
                and source_url ~ '^https://'
            )
        ),
    constraint ck_card_set_external_reference_metadata
        check (jsonb_typeof(metadata) = 'object')
);

create index ix_card_set_external_reference_card_set
    on public.card_set_external_reference (card_set_id);
create index ix_card_set_external_reference_asset_source
    on public.card_set_external_reference (asset_source_id);
create index ix_card_set_external_reference_active
    on public.card_set_external_reference (asset_source_id, is_active);

alter table public.card_set_external_reference enable row level security;

commit;
