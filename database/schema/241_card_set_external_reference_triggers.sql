-- Project Mimikyu
-- Query 241 - Card Set External Reference Triggers
-- Status: CONFIRMADA EXECUTADA ("Success. No rows returned")
-- Ver docs/05-modelo-de-dados.md, seção "Card Set External Reference",
-- "Query 241", para o contexto completo.
--
-- Mesmo padrão já estabelecido para as demais camadas de referência externa
-- (200/201 Asset Source, 210/211 Card External Reference): normalização,
-- atualização automática de updated_at, e proteção de identidade via
-- RAISE EXCEPTION. A proteção de identidade aqui cobre também external_set_id
-- e created_at como imutáveis, além de id/card_set_id/asset_source_id.

begin;

create or replace function public.normalize_card_set_external_reference()
returns trigger
language plpgsql
set search_path = public
as $$
begin
    new.external_set_id := btrim(new.external_set_id);
    if new.source_url is not null then
        new.source_url := nullif(btrim(new.source_url), '');
    end if;
    new.metadata := coalesce(new.metadata, '{}'::jsonb);
    return new;
end;
$$;

create or replace function public.govern_card_set_external_reference()
returns trigger
language plpgsql
set search_path = public
as $$
begin
    if new.id is distinct from old.id then
        raise exception 'CARD_SET_EXTERNAL_REFERENCE_ID_IMMUTABLE';
    end if;
    if new.card_set_id is distinct from old.card_set_id then
        raise exception 'CARD_SET_EXTERNAL_REFERENCE_CARD_SET_IMMUTABLE';
    end if;
    if new.asset_source_id is distinct from old.asset_source_id then
        raise exception 'CARD_SET_EXTERNAL_REFERENCE_ASSET_SOURCE_IMMUTABLE';
    end if;
    if new.external_set_id is distinct from old.external_set_id then
        raise exception 'CARD_SET_EXTERNAL_REFERENCE_EXTERNAL_SET_ID_IMMUTABLE';
    end if;
    if new.created_at is distinct from old.created_at then
        raise exception 'CARD_SET_EXTERNAL_REFERENCE_CREATED_AT_IMMUTABLE';
    end if;
    return new;
end;
$$;

create or replace function public.touch_card_set_external_reference_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
    new.updated_at := now();
    return new;
end;
$$;

create trigger trg_010_normalize_card_set_external_reference
before insert or update
on public.card_set_external_reference
for each row
execute function public.normalize_card_set_external_reference();

create trigger trg_020_govern_card_set_external_reference
before update
on public.card_set_external_reference
for each row
execute function public.govern_card_set_external_reference();

create trigger trg_030_touch_card_set_external_reference_updated_at
before update
on public.card_set_external_reference
for each row
execute function public.touch_card_set_external_reference_updated_at();

commit;
