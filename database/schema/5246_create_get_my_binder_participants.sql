/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5246 - Coleções vinculadas a um fichário
              get_my_binder_participants(uuid) — leitura
Versão......: 1.0 (2026-10-23, P3A-BINDER-CONTROL-IDENTITY-IMPLEMENTATION-01)
Status......: EXECUTADA / CANÔNICA. Aplicada no LIVE em 2026-10-24 UTC
              (P3A-BINDER-CONTROL-IDENTITY-LIVE-EXECUTION-01, autorização expressa de
              Fabrício; ledger 20261024002445 `5246_create_get_my_binder_participants`).
              Do `begin;` ao `commit;` idêntica ao arquivo da pasta
              database/proposals/2026-10-23-p3a-binder-control-identity/ (só este
              bloco Status difere); enviada via apply_migration sem as linhas
              `begin;`/`commit;` externas (o SQL executável é o mesmo). Conferida
              contra o LIVE em 2026-10-24 (P3A-BINDER-CONTROL-FINAL-CLOSEOUT-01, só
              leitura): corpos das funções por md5 normalizado (sem comentários e
              espaços) 4/4 iguais; colunas, CHECK, SECURITY DEFINER, search_path e
              EXECUTE (authenticated sim, anon não) conforme o arquivo. Pós-checagem
              LIVE_90 PASS; homologação pela interface PASS (Fabrício). Ver README
              da proposta §11.8–§11.9.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-23

Fecha a lacuna L2 (não havia leitura das convidadas para a proprietária).

Regras:
  - Fronteira: a coleção pedida é do usuário (owner-scoped) antes de
    qualquer outra tabela; alheia/inexistente → COLLECTION_NOT_FOUND.
  - Proprietária: vê a si mesma e TODAS as convidadas.
  - Convidada: vê só a proprietária e a si mesma (README §7, decisão de
    menor exposição — as demais convidadas não lhe dizem respeito).
  - Toda linha devolvida é coleção do próprio usuário (5229 só associa
    coleções do mesmo dono); o filtro owner_user_id é reaplicado em cada
    linha como defesa em profundidade.
  - Contagem por participante: bolsos com carta DESTA coleção
    (collection_allocation.collection_id) — o que a página "Só desta
    coleção" já distingue. Sem valores financeiros.
  - Teto de 200 linhas (guarda operacional; 5229 não limita convidadas).
  - Ordem: proprietária primeiro, depois convidadas por nome.
  - Custo: convidadas pelo índice ix_collection_layout_guest_layout (5229);
    contagem por participante pelo caminho assignment → allocation já
    usado em 5230 (own_filled_count).
Dependências: 5040 (collection_allocation), 5115, 5229, 5245.
================================================================
*/

begin;

do $pre$
begin
  if to_regclass('public.collection_layout_guest') is null then
    raise exception 'PRECHECK 5246: aplique a 5229 antes';
  end if;
  if to_regprocedure('public.get_my_binder_identity(uuid)') is null then
    raise exception 'PRECHECK 5246: aplique a 5245 antes';
  end if;
  if to_regprocedure('public.get_my_binder_participants(uuid)') is not null then
    raise exception 'PRECHECK 5246: função já existe';
  end if;
end;
$pre$;

create function public.get_my_binder_participants(p_collection_id uuid)
returns table (
  collection_id     uuid,
  collection_name   text,
  binder_role       text,
  lifecycle_status  text,
  is_current        boolean,
  card_pocket_count integer
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_uid    uuid := auth.uid();
  v_layout uuid;
  v_owner  uuid;
  v_role   text;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_collection_id is null then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;

  perform 1 from public.collection c
  where c.id = p_collection_id and c.owner_user_id = v_uid;
  if not found then
    raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';
  end if;

  select l.id, l.collection_id into v_layout, v_owner
  from public.collection_layout l where l.collection_id = p_collection_id;
  if v_layout is not null then
    v_role := 'OWNER';
  else
    select g.layout_id into v_layout from public.collection_layout_guest g where g.collection_id = p_collection_id;
    if v_layout is null then
      return;
    end if;
    select l.collection_id into v_owner from public.collection_layout l where l.id = v_layout;
    v_role := 'GUEST';
  end if;

  return query
  with members as (
    select v_owner as cid, 'OWNER'::text as role
    union all
    select g.collection_id, 'GUEST'::text
    from public.collection_layout_guest g
    where g.layout_id = v_layout
      and (v_role = 'OWNER' or g.collection_id = p_collection_id)
  )
  select c.id,
         c.name::text,
         m.role,
         c.lifecycle_status::text,
         c.id = p_collection_id,
         (select count(*)
            from public.collection_layout_page p
            join public.collection_layout_slot s            on s.page_id = p.id
            join public.collection_layout_slot_assignment a on a.slot_id = s.id
            join public.collection_allocation ca            on ca.id = a.collection_allocation_id
           where p.layout_id = v_layout
             and ca.collection_id = c.id)::integer
  from members m
  join public.collection c on c.id = m.cid and c.owner_user_id = v_uid
  order by (m.role = 'OWNER') desc, c.name, c.id
  limit 200;
end;
$$;

comment on function public.get_my_binder_participants(uuid) is
  'P3-A (5246): coleções que usam o fichário — proprietária vê todas; convidada vê a proprietária e a si mesma. Com bolsos com carta de cada coleção. Coleção alheia → COLLECTION_NOT_FOUND; sem fichário → 0 linhas. Teto 200.';

revoke all on function public.get_my_binder_participants(uuid) from public;
revoke all on function public.get_my_binder_participants(uuid) from anon;
grant execute on function public.get_my_binder_participants(uuid) to authenticated;

commit;

/*
Resultado esperado: 1 função nova, SECURITY DEFINER, search_path='',
EXECUTE só para authenticated. Nenhum dado alterado.

Como validar (só leitura):
select p.prosecdef, p.proconfig,
       has_function_privilege('anon', p.oid, 'EXECUTE')          as anon_exec,  -- false
       has_function_privilege('authenticated', p.oid, 'EXECUTE') as auth_exec   -- true
from pg_proc p
where p.oid = 'public.get_my_binder_participants(uuid)'::regprocedure;
*/
