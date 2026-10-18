/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5184 - Tabela collection_master_set_finish (acabamentos
              escolhidos do Master Set) + bloqueio de UPDATE
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO no LIVE em 2026-10-18 (autorização
              de Fabrício) — ledger 20261018170113; 5836 v1.3 74/74 PASS,
              5837 v1.2 10/10 PASS; baseline 5840 inalterado
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-18 (MASTER-SET-DOCUMENTATION-AND-CONTRACT-PROPOSAL-01)

Autoridade: concept-decisions C-187–C-190; logical-model LDM-191.
Substitui, para o Master Set, collection_master_set_scope (5072), que
guardava card_variant_id. A tabela antiga só é removida em 5197, depois
que todos os leitores e escritores foram trocados.

Desenho (reaproveita o padrão de 5072/5074):
  - PK natural (collection_id, variant_type_id): um acabamento aparece
    no máximo uma vez por coleção; a PK, liderada por collection_id,
    serve de índice para "acabamentos desta coleção".
  - Insert/delete-only: mudar a seleção é remover + incluir; acabamento
    mantido preserva adopted_at/adopted_by_user_id (LDM-194).
  - ON DELETE CASCADE em collection_id; RESTRICT em variant_type_id
    (o vocabulário não some por baixo de um objetivo).
  - RLS: só SELECT do próprio dono; nenhuma escrita direta para
    authenticated (toda escrita pelas RPCs 5194/5195, via a função
    interna 5193). anon: nada.

Não toca exemplares, vínculos, locais nem outras políticas.

Resultado esperado: tabela vazia, RLS ligada, 1 policy SELECT, trigger
de bloqueio de UPDATE, EXECUTE da função de trigger revogado.
Como validar: 5836 seção 0.
================================================================
*/

begin;

create table public.collection_master_set_finish (
    collection_id      uuid not null
                          references public.collection(id)
                          on update restrict on delete cascade,
    variant_type_id    uuid not null
                          references public.card_variant_type(id)
                          on update restrict on delete restrict,
    adopted_at         timestamptz not null default now(),
    adopted_by_user_id uuid not null
                          references auth.users(id)
                          on update restrict on delete restrict,

    constraint pk_collection_master_set_finish
        primary key (collection_id, variant_type_id)
);

comment on table public.collection_master_set_finish is
    'Master Set (LDM-191/C-188): tipos de acabamento escolhidos pelo dono. As posições (carta + acabamento, + cartas secretas) são derivadas do catálogo vigente por master_set_positions() (5187), nunca persistidas. Insert/delete-only.';

-- Índice para a FK de variant_type_id (vocabulário pequeno; evita varredura
-- ao validar RESTRICT quando um acabamento for excluído do vocabulário).
create index ix_collection_master_set_finish_variant_type
    on public.collection_master_set_finish (variant_type_id);

alter table public.collection_master_set_finish enable row level security;

create policy collection_master_set_finish_select_own
    on public.collection_master_set_finish for select
    using (exists (
        select 1 from public.collection c
        where c.id = collection_master_set_finish.collection_id
          and c.owner_user_id = (select auth.uid())
    ));

revoke all on public.collection_master_set_finish from public, anon, authenticated;
grant select on public.collection_master_set_finish to authenticated;

create or replace function public.reject_collection_master_set_finish_update()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    raise exception 'collection_master_set_finish rows are immutable — remove + add instead (collection_id=%, variant_type_id=%)',
        old.collection_id, old.variant_type_id
        using errcode = 'check_violation';
end;
$$;

revoke all on function public.reject_collection_master_set_finish_update() from public, anon, authenticated;

create trigger trg_collection_master_set_finish_reject_update
    before update on public.collection_master_set_finish
    for each row
    execute function public.reject_collection_master_set_finish_update();

commit;
