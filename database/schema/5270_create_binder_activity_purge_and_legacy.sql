/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5270 - P3-B S1 · Histórico do Fichário — exclusão definitiva
              e registro legado
              purge_my_binder_activity(uuid, uuid)   — SEM permissão para clientes (O2)
              importação única do legado L01 (Chi-Yu)
Versão......: 1.0 (2026-10-25, P3-B-S1-FOUNDATION-READINESS-01)
Status......: EXECUTADA / CANÔNICA. Aplicada no LIVE mimikyu-core em 2026-10-27
              (P3-B S1, autorização expressa de Fabrício — G8; G5b/G5c dispensados
              sob H-A só para a S1; ledger 20261027024918 `5270_create_binder_activity_purge_and_legacy`). Do `begin;` ao `commit;`
              idêntica ao arquivo de database/proposals/2026-10-25-p3b-binder-
              activity-history/ (só este bloco Status difere); enviada via
              apply_migration sem as linhas `begin;`/`commit;` externas — o texto
              gravado no ledger é igual ao corpo do arquivo da proposta (md5).
              LIVE_90 12/12. Harness 5860 NÃO EXECUTADO (H-A). Ver README §28.34.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-25
Autoridade..: C-203 (exclusão definitiva como exceção controlada),
              C-209 (legado parcial); LDM-201, LDM-203; README v1.2 §6.3, §6.4.

A. Exclusão definitiva (A3) — estrutura pronta, interface pós-MVP:
  · Só o titular (auth.uid()), só os SEUS eventos de UM fichário.
  · Confirmação explícita: p_confirm deve repetir a chave do fichário.
  · Marca a transação com mmkyu.binder_activity_purge = '<titular>:<chave>'
    — a única porta que o gatilho de imutabilidade (5267) abre para DELETE
    de evento; itens saem em cascata.
  · Grava/atualiza o marco mínimo (binder_activity_coverage):
    covered_from = agora, reason = HISTORY_PURGED. Nada mais: o marco não
    guarda contagem, tipos, cartas, posições nem datas dos eventos apagados
    (nenhum conteúdo histórico recuperável).
  · Não grava evento (registrar o apagamento contradiria a exclusão).
  · Obrigação de retenção (P2): ponto de extensão documentado — nenhuma
    identificada hoje; se existir, a verificação entra aqui antes do DELETE.
  · EXECUTE revogado de authenticated nesta fatia: a liberação acontece com
    a interface, por migration própria.
  · Diferença para exclusão de conta (A5): a conta apaga eventos E marcos
    do titular pela cascata das FKs (5267), sem esta função e sem marco
    remanescente.

B. Legado L01 (D4) — importação única e idempotente:
  · Fonte: collection_layout_catalog_incorporation (linhas reais).
  · Cada linha vira um evento LEGACY_CATALOG_INCORPORATION com:
      titular = dono da coleção da linha (mesmo dono do fichário; 5229/5255),
      occurred_at = incorporated_at (data real), actor = NULL,
      source = LEGADO, collection_id da linha, collection_name = NULL,
      binder_name = NULL, summary = {"item_key": <chave>}.
    Item único CARD/INCORPORATED com a cópia do catálogo (nome, número, Set,
    acabamento quando a chave o tiver; '*' = qualquer acabamento → NULL).
    Sem posição, sem ator, sem quantidade, sem efeito no bolso: atributos
    ausentes não são inventados.
  · Idempotência: não importa se já existe evento legado com a mesma chave
    para o mesmo fichário, coleção e titular.
  · LIVE (leitura de 2026-10-25): 1 linha esperada (Chi-Yu · 059 · Holo Reversa).

Dependências: 5267; collection_layout_catalog_incorporation (5263).
================================================================
*/
begin;

do $pre$
begin
  if to_regclass('public.binder_activity_event') is null or to_regclass('public.binder_activity_coverage') is null then
    raise exception 'PRECHECK 5270: aplique a 5267 antes';
  end if;
  if to_regclass('public.collection_layout_catalog_incorporation') is null then
    raise exception 'PRECHECK 5270: 5263 ausente';
  end if;
  if to_regprocedure('public.purge_my_binder_activity(uuid, uuid)') is not null then
    raise exception 'PRECHECK 5270: função de exclusão já existe';
  end if;
end;
$pre$;

-- A. Exclusão definitiva ---------------------------------------------------------------------
create function public.purge_my_binder_activity(p_layout_key uuid, p_confirm uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_uid uuid := (select auth.uid());
  v_n   integer;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_layout_key is null or p_confirm is distinct from p_layout_key then
    raise exception 'confirmation does not match the binder' using errcode = '22023', hint = 'BINDER_ACTIVITY_PURGE_CONFIRM';
  end if;
  -- P2 (retenção legal/contratual): verificação entra aqui quando existir.

  perform set_config('mmkyu.binder_activity_purge', v_uid::text || ':' || p_layout_key::text, true);
  delete from public.binder_activity_event e
  where e.owner_user_id = v_uid and e.layout_key = p_layout_key;
  get diagnostics v_n = row_count;
  perform set_config('mmkyu.binder_activity_purge', '', true);

  insert into public.binder_activity_coverage as cv (owner_user_id, layout_key, covered_from, reason, updated_at)
  values (v_uid, p_layout_key, now(), 'HISTORY_PURGED', now())
  on conflict (owner_user_id, layout_key)
  do update set covered_from = excluded.covered_from, reason = excluded.reason, updated_at = excluded.updated_at;

  return v_n;
end;
$fn$;

revoke all on function public.purge_my_binder_activity(uuid, uuid) from public, anon, authenticated, service_role;

comment on function public.purge_my_binder_activity(uuid, uuid) is
  'P3-B 5270 (C-203): exclusão definitiva do histórico de um fichário pelo titular; deixa só o marco HISTORY_PURGED (data). Sem permissão para clientes até a interface (O2).';

-- B. Legado L01 --------------------------------------------------------------------------------
do $legacy$
declare
  r record;
  v_owner uuid;
  v_card uuid;
  v_vt uuid;
  v_event bigint;
  c_name text; c_num text; c_set text; vt_code text; vt_name text;
begin
  for r in
    select ci.layout_id, ci.collection_id, ci.item_key, ci.incorporated_at
    from public.collection_layout_catalog_incorporation ci
    order by ci.incorporated_at, ci.item_key
  loop
    select c.owner_user_id into v_owner from public.collection c where c.id = r.collection_id;
    if v_owner is null then
      raise exception 'LEGACY 5270: coleção sem dono para a chave %', r.item_key;
    end if;
    if exists (select 1 from public.binder_activity_event e
               where e.source = 'LEGADO' and e.owner_user_id = v_owner and e.layout_key = r.layout_id
                 and e.collection_id = r.collection_id and e.summary ->> 'item_key' = r.item_key) then
      continue;
    end if;

    v_card := split_part(r.item_key, ':', 1)::uuid;
    v_vt   := nullif(split_part(r.item_key, ':', 2), '*')::uuid;
    select k.name, k.collector_number, cs.code into c_name, c_num, c_set
    from public.card k join public.card_set cs on cs.id = k.card_set_id where k.id = v_card;
    if c_name is null then
      raise exception 'LEGACY 5270: carta da chave % não encontrada', r.item_key;
    end if;
    vt_code := null; vt_name := null;
    if v_vt is not null then
      select t.code, t.name into vt_code, vt_name from public.card_variant_type t where t.id = v_vt;
    end if;

    insert into public.binder_activity_event
      (owner_user_id, layout_key, occurred_at, actor_user_id, event_type, source,
       collection_id, collection_name, binder_name, summary)
    values
      (v_owner, r.layout_id, r.incorporated_at, null, 'LEGACY_CATALOG_INCORPORATION', 'LEGADO',
       r.collection_id, null, null, jsonb_build_object('item_key', r.item_key))
    returning id into v_event;

    insert into public.binder_activity_item
      (event_id, ordinal, item_kind, effect, card_id, card_name, collector_number, card_set_code,
       variant_type_code, variant_type_name)
    values
      (v_event, 1, 'CARD', 'INCORPORATED', v_card, left(c_name, 200), left(c_num, 40), left(c_set, 40),
       left(vt_code, 60), left(vt_name, 120));
  end loop;
end;
$legacy$;

commit;
