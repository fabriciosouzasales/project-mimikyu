/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5185 - Elegibilidade imediata de um acabamento do Master Set
Versão......: 1.0
Status......: PROPOSTA — NÃO EXECUTADA
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-18 (MASTER-SET-DOCUMENTATION-AND-CONTRACT-PROPOSAL-01)

Autoridade: LDM-191; C-187 (regra 7 da decisão: nunca posição para
acabamento inexistente no Set). Mesma disciplina de 5073: camada
estrutural independente das RPCs, BEFORE INSERT, fail-closed.

Condições (todas obrigatórias):
  A. a coleção é REFERENCE_BASED com Collection Reference CARD_SET;
  B. o acabamento pertence ao mesmo Game da coleção;
  C. no momento da escolha existe ao menos uma Card Variant ATIVA de
     uma Card ATIVA do Card Set referenciado nesse acabamento.

C é verificada só na inclusão. Se o catálogo perder depois todas as
combinações do acabamento, a linha permanece (objetivo do usuário) e
simplesmente deixa de gerar posições (LDM-195) — nunca é apagada por
evento de catálogo.

Não exige acabamento ativo no vocabulário: a desativação de vocabulário
(2156) não desativa variantes; o que manda é existir variante ativa.

Resultado esperado: trigger BEFORE INSERT; EXECUTE revogado.
Como validar: 5836 casos 4.x.
================================================================
*/

begin;

create or replace function public.validate_master_set_finish_eligibility()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_card_set_id uuid;
    v_game_id     uuid;
begin
    select ccsr.card_set_id, c.game_id
      into v_card_set_id, v_game_id
    from public.collection c
    join public.collection_reference cr
        on cr.collection_id = c.id
       and cr.reference_kind = 'CARD_SET'
    join public.collection_card_set_reference ccsr
        on ccsr.collection_reference_id = cr.id
    where c.id = new.collection_id
      and c.mode = 'REFERENCE_BASED';

    if v_card_set_id is null then
        raise exception 'master set finish requires a REFERENCE_BASED/CARD_SET collection (collection_id=%)', new.collection_id
            using errcode = 'check_violation';
    end if;

    if not exists (
        select 1 from public.card_variant_type t
        where t.id = new.variant_type_id
          and t.game_id = v_game_id
    ) then
        raise exception 'variant type % does not belong to the game of collection %', new.variant_type_id, new.collection_id
            using errcode = 'check_violation';
    end if;

    if not exists (
        select 1
        from public.card c
        join public.card_variant cv
            on cv.card_id = c.id
           and cv.is_active
           and cv.variant_type_id = new.variant_type_id
        where c.card_set_id = v_card_set_id
          and c.is_active
    ) then
        raise exception 'variant type % has no active card in the card set of collection %', new.variant_type_id, new.collection_id
            using errcode = 'check_violation';
    end if;

    return new;
end;
$$;

revoke all on function public.validate_master_set_finish_eligibility() from public, anon, authenticated;

create trigger trg_collection_master_set_finish_eligibility
    before insert on public.collection_master_set_finish
    for each row
    execute function public.validate_master_set_finish_eligibility();

commit;
