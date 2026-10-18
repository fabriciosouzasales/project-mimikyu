/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5186 - "Master Set nunca vazio" passa a olhar os
              acabamentos (reaproveita 5075/5076; novo gatilho de DELETE)
Versão......: 1.0
Status......: PROPOSTA — NÃO EXECUTADA
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-18 (MASTER-SET-DOCUMENTATION-AND-CONTRACT-PROPOSAL-01)

Reaproveitamento:
  - check_master_set_scope_presence(uuid) (5075): mesma assinatura,
    mesmo contrato de "estado corrente" (coleção inexistente → PASS;
    policy ≠ MASTER_SET → PASS; MASTER_SET exige ≥ 1 linha). Só a
    tabela consultada muda: collection_master_set_finish.
  - trg_collection_master_set_scope_presence (5076, lado collection):
    INALTERADO — continua chamando o helper.
  - Novo lado "acabamentos": AFTER DELETE deferido em
    collection_master_set_finish, espelho de 5077.

Pré-condição de aplicação (verificada no pré-check do README): nenhuma
coleção MASTER_SET no LIVE e collection_master_set_scope vazia. Assim,
trocar o corpo do helper não muda o resultado de nenhuma coleção
existente. O gatilho antigo de DELETE em collection_master_set_scope
continua existindo até 5197 e chama o mesmo helper (inofensivo: a
tabela antiga está vazia e deixa de ser escrita).

Resultado esperado: helper com novo corpo; trigger deferido novo.
Como validar: 5836 casos 5.x (último acabamento removido sem reposição
→ falha no COMMIT; trocar todos numa transação → passa).
================================================================
*/

begin;

create or replace function public.check_master_set_scope_presence(
    p_collection_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_completion_policy text;
begin
    select c.completion_policy
      into v_completion_policy
    from public.collection c
    where c.id = p_collection_id;

    if not found then
        return; -- coleção não existe mais (DELETE CASCADE): PASS.
    end if;

    if v_completion_policy is distinct from 'MASTER_SET' then
        return; -- policy corrente ≠ MASTER_SET: PASS.
    end if;

    if exists (
        select 1
        from public.collection_master_set_finish f
        where f.collection_id = p_collection_id
    ) then
        return; -- MASTER_SET com ≥ 1 acabamento: PASS.
    end if;

    raise exception 'master set collection % would have no finish at commit', p_collection_id
        using errcode = 'check_violation';
end;
$$;

revoke all on function public.check_master_set_scope_presence(uuid) from public, anon, authenticated;

create or replace function public.enforce_master_set_finish_presence_on_delete()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    perform public.check_master_set_scope_presence(old.collection_id);
    return null;
end;
$$;

revoke all on function public.enforce_master_set_finish_presence_on_delete() from public, anon, authenticated;

create constraint trigger trg_collection_master_set_finish_presence_on_delete
    after delete on public.collection_master_set_finish
    deferrable initially deferred
    for each row
    execute function public.enforce_master_set_finish_presence_on_delete();

commit;
