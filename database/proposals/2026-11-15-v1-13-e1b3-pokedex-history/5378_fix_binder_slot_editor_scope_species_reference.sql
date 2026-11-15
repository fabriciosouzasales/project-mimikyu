/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5378 - Classificação do bolso: referência de espécie de X conta como
              bolso de X (V1-13 · E1-B3) — CREATE OR REPLACE de
              binder_slot_editor_scope (5371)
Versão......: 1.0
Status......: PROPOSTA — NÃO EXECUTADA. Preparada em
              `V1-13 / E1-B3 | POKÉDEX AND ACTIVITY HISTORY FOUNDATION-01`
              (2026-11-15). Execução só com prova dinâmica sob protocolo
              controlado (C-244) e autorização expressa e específica.
Autor.......: Fabrício Sales / Claude
Data........: 2026-11-15
Contrato....: C-237 ("num fichário cuja coleção proprietária é a Pokédex X,
              também conta o bolso com referência de espécie" como bolso de X;
              bolso livre é "sem referência de espécie"), C-242.
Depende de..: E1-B1 (5371).

Defeito corrigido (concreto, por inspeção): o cabeçalho da 5371 declara
"OWN — ... referência de espécie de X", mas o corpo só recusava a referência de
OUTRA coleção e deixava a de X como FREE. Efeito prático: o EDITOR da Pokédex
proprietária não conseguia fixar nem soltar um bolso que só tem a referência de
espécie de X (fixar/soltar exigem OWN na 5375), o que a C-237 permite.
Colocar, mover para, reservar e liberar não mudam (aceitam OWN e FREE).

Mudança mínima: uma linha (`v_own := true` depois da referência de X). Nada
mais muda: assinatura, ACL (sem EXECUTE para a API), STABLE, SECURITY DEFINER.
A referência de espécie de OUTRA coleção continua FOREIGN (o EDITOR de uma
convidada nunca mexe em bolso rotulado pela Pokédex proprietária).
Canal.......: psql. Precheck: md5 do corpo vigente = 5371
              (3086014a164704f309c7051419df3f23, derivado do arquivo).
Idempotência: corpo já igual ao desta proposta (21f1b51a3a0f6c80337c2c593cc6054f) → 'JÁ APLICADA'.
Reversão....: R5378 em ROLLBACK_E1B3.sql (reaplica o corpo da 5371).
Como validar: harness 5891, seção 2.
================================================================
*/

begin;

set local lock_timeout = '5s';

do $pre$
declare
  v_m text := (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
               where p.oid = to_regprocedure('public.binder_slot_editor_scope(uuid, uuid, uuid, uuid)'));
begin
  if v_m = '21f1b51a3a0f6c80337c2c593cc6054f' then
    raise exception 'PRECHECK 5378: JÁ APLICADA — não reaplicar';
  end if;
  if v_m is distinct from '3086014a164704f309c7051419df3f23' then
    raise exception 'PRECHECK 5378: ESTADO DIVERGENTE — corpo vigente difere da 5371 (%)', v_m;
  end if;
end;
$pre$;

create or replace function public.binder_slot_editor_scope(
  p_layout_id            uuid,
  p_anchor_collection_id uuid,
  p_collection_id        uuid,
  p_slot_id              uuid
)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_page    uuid;
  v_row     integer;
  v_col     integer;
  v_locked  boolean;
  v_card    uuid;
  v_card_cl uuid;
  v_res_cl  uuid;
  v_res     boolean;
  v_spc_cl  uuid;
  v_own     boolean := false;
begin
  select s.page_id, s.row_index, s.column_index, s.locked
    into v_page, v_row, v_col, v_locked
  from public.collection_layout_slot s
  join public.collection_layout_page p on p.id = s.page_id
  where s.id = p_slot_id and p.layout_id = p_layout_id;
  if v_page is null then
    return 'FOREIGN';
  end if;

  -- Carta: só é de X se o exemplar estiver alocado a X.
  select a.physical_card_id, ca.collection_id into v_card, v_card_cl
  from public.collection_layout_slot_assignment a
  left join public.collection_allocation ca on ca.physical_card_id = a.physical_card_id
  where a.slot_id = p_slot_id;
  if v_card is not null then
    if v_card_cl is distinct from p_collection_id then
      return 'FOREIGN';
    end if;
    v_own := true;
  end if;

  -- Reserva: sem coleção registrada = da proprietária (C-196).
  select true, coalesce(e.collection_id, p_anchor_collection_id) into v_res, v_res_cl
  from public.collection_layout_slot_expected_content e
  where e.slot_id = p_slot_id;
  if v_res then
    if v_res_cl is distinct from p_collection_id then
      return 'FOREIGN';
    end if;
    v_own := true;
  end if;

  -- Imagem personalizada e região mesclada: sempre do titular / fora da E1-B1.
  if exists (select 1 from public.collection_layout_slot_image i where i.slot_id = p_slot_id) then
    return 'FOREIGN';
  end if;
  if exists (select 1 from public.collection_layout_region r
             where r.page_id = v_page
               and v_row between r.top_row and r.top_row + r.height - 1
               and v_col between r.left_column and r.left_column + r.width - 1) then
    return 'FOREIGN';
  end if;

  -- Referência de espécie: só é de X se registrada para X.
  select sr.collection_id into v_spc_cl
  from public.collection_layout_slot_species_reference sr
  where sr.slot_id = p_slot_id;
  if found then
    if v_spc_cl is distinct from p_collection_id then
      return 'FOREIGN';
    end if;
    v_own := true;   -- E1-B3 (5378): referência de espécie de X = bolso de X (C-237)
  end if;

  -- Trava: sem carta nem reserva de X, o bolso fixado é do titular.
  if v_locked and not v_own then
    return 'FOREIGN';
  end if;

  return case when v_own then 'OWN' else 'FREE' end;
end;
$fn$;

do $post$
declare
  f oid := to_regprocedure('public.binder_slot_editor_scope(uuid, uuid, uuid, uuid)');
begin
  if (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = f) is distinct from '21f1b51a3a0f6c80337c2c593cc6054f'
     or (select p.prosecdef from pg_catalog.pg_proc p where p.oid = f) is not true
     or (select p.provolatile from pg_catalog.pg_proc p where p.oid = f) <> 's'
     or (select p.proconfig from pg_catalog.pg_proc p where p.oid = f) is distinct from array['search_path=""']
     or pg_catalog.has_function_privilege('authenticated', f, 'EXECUTE') is not false
     or pg_catalog.has_function_privilege('anon', f, 'EXECUTE') is not false
     or pg_catalog.has_function_privilege('service_role', f, 'EXECUTE') is not false then
    raise exception 'POSTCHECK 5378: binder_slot_editor_scope fora do estado esperado';
  end if;
end;
$post$;

commit;
