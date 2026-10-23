/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5225 - Fichário Digital (P2-A1): conteúdo planejado com
              ACABAMENTO esperado (M3) + evolução de
              set_slot_expected_content (5128)
Versão......: 1.1 (2026-10-23, AUDIT-CORRECTION-01: precheck textual de
              chamadores; semântica do upsert e privilégios documentados)
Status......: EXECUTADA / CANÔNICA. Aplicada no LIVE em 2026-10-23 UTC
              (P2-A1-LIVE-APPLY-01, autorização expressa de Fabrício; ledger
              20261023115904 `5225_extend_slot_expected_content_variant_type`). Do `begin;` ao `commit;`
              byte a byte idêntica ao texto aplicado e ao arquivo da pasta
              database/proposals/2026-10-22-p2-a1-digital-binder/ (só este
              bloco Status difere). Pós-checagens estruturais 10/10 PASS;
              comportamento SEM prova comportamental; tetos provisórios.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-22 (P2-A1-PROPOSAL-01)

Ordem de aplicação do pacote: 5225 → 5223 → 5224 → 5226 → 5227 → 5228 (a leitura 5223 e
a montagem 5224 dependem da coluna criada aqui). Ver README.md.

Por que existe (R3, P2-A1 CONTRACT REFINEMENT-02 §7):
A posição de completude do Master Set é "carta + acabamento" (C-187,
`card_variant_type`). O conteúdo planejado (5113, C-42) só registra
`card_id` e, opcionalmente, `card_variant_id`. Nenhuma combinação dos
dois representa "esta carta, neste acabamento, qualquer impressão":
  - `card_variant_id` NULL → qualquer variante (perde o acabamento);
  - `card_variant_id` = uma variante → exige UMA impressão específica,
    mas o mesmo acabamento pode ter várias variantes (perfil de impressão,
    contexto de edição — 2171), e a C-187 diz que impressão/contexto não
    criam posições. Usar uma variante "representante" (M2) mudaria o
    significado da coluna conforme a política da coleção (rejeitado).
A posição do bolso não serve de chave (identidade do bolso independe da
posição — C-41; o usuário move cartas). Conclusão: falta um atributo.

O que muda (mínimo):
  1. Coluna `expected_variant_type_id uuid NULL` em
     public.collection_layout_slot_expected_content.
       NULL  → a reserva continua exatamente como hoje (carta, ou carta +
               variante específica). TODAS as linhas existentes ficam NULL:
               semântica preservada, nenhum backfill.
       valor → "esta carta, neste acabamento, qualquer variante dele".
  2. FK para public.card_variant_type(id) ON UPDATE/DELETE RESTRICT
     (mesmo padrão das FKs de catálogo da 5113: nenhuma reserva some por
     efeito colateral de manutenção do catálogo).
  3. CHECK `card_variant_id IS NULL OR expected_variant_type_id IS NULL`:
     três granularidades mutuamente exclusivas — carta / carta + acabamento
     / carta + variante específica. Uma variante já carrega seu acabamento;
     guardar os dois abriria espaço para contradição. Nenhuma restrição
     existente é afrouxada (a FK composta variante→carta da 5113 continua).
  4. Trigger de consistência de Game: o acabamento esperado tem de
     pertencer ao mesmo Game da carta (card → card_set → expansion →
     game; card_variant_type.game_id). Não exige que a carta TENHA
     variante ativa daquele acabamento: a C-42 aceita reserva divergente e
     o catálogo evolui (C-190); a montagem 5224 só gera acabamentos que
     existem (master_set_positions, 5187).
  5. Índice parcial na nova FK (só linhas com valor), para a verificação
     RESTRICT de card_variant_type não varrer a tabela.
  6. set_slot_expected_content: novo parâmetro opcional
     `p_expected_variant_type_id uuid DEFAULT NULL` e nova coluna no
     retorno. Como o tipo de retorno muda, a função é DROPADA e recriada
     NA MESMA TRANSAÇÃO (CREATE OR REPLACE não altera RETURNS TABLE). Isso
     também elimina o risco de sobrecarga ambígua: uma chamada de 3
     argumentos teria dois candidatos se as duas assinaturas coexistissem.
     A chamada antiga de 2 ou 3 argumentos continua válida (default NULL).
     Semântica: o upsert grava os TRÊS campos; chamar com 2/3 argumentos
     sobre um bolso que tinha acabamento LIMPA o acabamento (substituição
     integral da reserva, como já era para card_variant_id na 5128).
     Privilégios: o DROP descarta a ACL antiga; a nova função recebe as
     default privileges do schema e, em seguida, REVOKE PUBLIC/anon +
     GRANT authenticated — mesma matriz efetiva da 5128 (service_role
     mantém o EXECUTE que já tinha por default privileges; o app não o usa).
     Corpo idêntico ao da 5128 v2.0 em autorização, trava, revalidação e
     não-enumeração; acrescenta: exclusividade variante × acabamento
     (EXPECTED_CONTENT_VARIANT_AND_TYPE_EXCLUSIVE) e grava/atualiza o
     acabamento no ON CONFLICT. Continua permitido em bolso fixado
     (5118: "definir/limpar continua permitido em Slot locked").
  clear_slot_expected_content (5129) não muda: apaga a linha inteira.

Impacto em outros contratos:
  - move_slot_assignment (5132), assign_card_to_slot (5131),
    remove_slot_assignment (5133), set_slot_lock (5130): não leem nem
    escrevem conteúdo planejado → inalterados. A reserva pertence ao BOLSO
    (C-42): mover o exemplar não move a reserva — comportamento atual.
  - remove_layout_page (5126): continua recusando página com reserva.
  - RLS: a policy select-own da 5113 cobre a linha inteira; a coluna nova
    é visível só ao dono. DML continua negado a todos os papéis de API.
  - Completude: conteúdo planejado continua FORA do cálculo (C-42).

Reversão (só se nenhuma linha usar a coluna):
  begin;
    -- exige: select count(*) = 0 ... where expected_variant_type_id is not null
    drop function public.set_slot_expected_content(uuid, uuid, uuid, uuid);
    -- recriar a 5128 v2.0 a partir de database/schema/5128_*.sql (corpo canônico)
    drop trigger trg_expected_content_variant_type_game on public.collection_layout_slot_expected_content;
    drop function public.enforce_expected_content_variant_type_game();
    alter table public.collection_layout_slot_expected_content
      drop constraint chk_expected_content_variant_xor_type,
      drop constraint fk_expected_content_variant_type,
      drop column expected_variant_type_id;
  commit;
  Com linhas preenchidas a reversão destruiria reservas do Master Set: não
  é reversível sem decisão do proprietário.

Como validar: harness 5850, 0.6 e 13.1–13.4.
================================================================
*/

begin;

-- Pré-checagem (falha alto, nada é alterado) ---------------------------------
do $pre$
begin
  if to_regclass('public.collection_layout_slot_expected_content') is null
     or to_regclass('public.card_variant_type') is null
     or to_regclass('public.expansion') is null then
    raise exception 'PRECHECK 5225: tabelas de base ausentes (5113/150/110)';
  end if;
  if exists (select 1 from information_schema.columns
             where table_schema = 'public'
               and table_name = 'collection_layout_slot_expected_content'
               and column_name = 'expected_variant_type_id') then
    raise exception 'PRECHECK 5225: coluna expected_variant_type_id já existe';
  end if;
  if to_regprocedure('public.set_slot_expected_content(uuid, uuid, uuid)') is null then
    raise exception 'PRECHECK 5225: set_slot_expected_content(uuid, uuid, uuid) (5128) ausente';
  end if;
  if to_regprocedure('public.set_slot_expected_content(uuid, uuid, uuid, uuid)') is not null then
    raise exception 'PRECHECK 5225: assinatura de 4 argumentos já existe';
  end if;
  -- Nenhum objeto do banco pode depender da assinatura antiga (seria
  -- derrubado pelo DROP). Dependências normais de catálogo são ignoradas.
  if exists (select 1 from pg_depend d
             where d.refclassid = 'pg_catalog.pg_proc'::regclass
               and d.refobjid = 'public.set_slot_expected_content(uuid, uuid, uuid)'::regprocedure
               and d.deptype = 'n') then
    raise exception 'PRECHECK 5225: há objetos dependentes de set_slot_expected_content(uuid, uuid, uuid)';
  end if;
  -- Corpos plpgsql não geram pg_depend: busca textual por chamadores.
  if exists (select 1 from pg_proc p
             join pg_namespace n on n.oid = p.pronamespace
             where n.nspname not in ('pg_catalog', 'information_schema')
               and p.proname <> 'set_slot_expected_content'
               and p.prosrc ilike '%set_slot_expected_content(%') then
    raise exception 'PRECHECK 5225: outra função chama set_slot_expected_content — revisar antes do DROP';
  end if;
end;
$pre$;

-- 1–3. Coluna, FK e exclusividade ----------------------------------------------
alter table public.collection_layout_slot_expected_content
  add column expected_variant_type_id uuid null;

alter table public.collection_layout_slot_expected_content
  add constraint fk_expected_content_variant_type
    foreign key (expected_variant_type_id)
    references public.card_variant_type (id)
    on update restrict on delete restrict;

alter table public.collection_layout_slot_expected_content
  add constraint chk_expected_content_variant_xor_type
    check (card_variant_id is null or expected_variant_type_id is null);

comment on column public.collection_layout_slot_expected_content.expected_variant_type_id is
  'Opcional (5225, M3). Acabamento esperado: "esta carta, neste acabamento, qualquer variante dele" — a posição do Master Set (C-187). NULL = reserva por carta ou por variante específica (semântica da 5113 preservada). Exclusivo com card_variant_id (chk_expected_content_variant_xor_type). Mesmo Game da carta (trigger 5225).';

-- 5. Índice parcial da nova FK ------------------------------------------------
create index ix_expected_content_variant_type
  on public.collection_layout_slot_expected_content (expected_variant_type_id)
  where expected_variant_type_id is not null;

-- 4. Consistência de Game -------------------------------------------------------
create function public.enforce_expected_content_variant_type_game()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_card_game uuid;
  v_type_game uuid;
begin
  if new.expected_variant_type_id is null then
    return new;
  end if;

  select e.game_id into v_card_game
  from public.card c
  join public.card_set cs on cs.id = c.card_set_id
  join public.expansion e on e.id = cs.expansion_id
  where c.id = new.card_id;

  select t.game_id into v_type_game
  from public.card_variant_type t
  where t.id = new.expected_variant_type_id;

  if v_card_game is null or v_type_game is null or v_card_game <> v_type_game then
    raise exception 'EXPECTED_VARIANT_TYPE_GAME_MISMATCH: o acabamento esperado precisa pertencer ao mesmo Game da carta'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

comment on function public.enforce_expected_content_variant_type_game() is
  '5225 (M3): o acabamento esperado de uma reserva pertence ao mesmo Game da carta. Trigger function — sem EXECUTE para papéis de API.';

revoke all on function public.enforce_expected_content_variant_type_game() from public;
revoke all on function public.enforce_expected_content_variant_type_game() from anon;
revoke all on function public.enforce_expected_content_variant_type_game() from authenticated;
revoke all on function public.enforce_expected_content_variant_type_game() from service_role;

create trigger trg_expected_content_variant_type_game
  before insert or update of card_id, expected_variant_type_id
  on public.collection_layout_slot_expected_content
  for each row
  execute function public.enforce_expected_content_variant_type_game();

-- 6. set_slot_expected_content: evolução (DROP + CREATE na mesma transação) ----
drop function public.set_slot_expected_content(uuid, uuid, uuid);

create function public.set_slot_expected_content(
  p_slot_id                  uuid,
  p_card_id                  uuid,
  p_card_variant_id          uuid default null,
  p_expected_variant_type_id uuid default null
)
returns table (
  slot_id                  uuid,
  card_id                  uuid,
  card_variant_id          uuid,
  expected_variant_type_id uuid
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_layout_id uuid;
begin
  if (select auth.uid()) is null then
    raise exception 'authentication required';
  end if;

  -- Resolve owner-scoped (inexistente e alheio caem no mesmo ramo).
  select p.layout_id
    into v_layout_id
    from public.collection_layout_slot s
    join public.collection_layout_page p on p.id = s.page_id
    join public.collection_layout l      on l.id = p.layout_id
    join public.collection c             on c.id = l.collection_id
   where s.id = p_slot_id
     and c.owner_user_id = (select auth.uid());

  if not found then
    raise exception 'layout slot not found or not owned by caller';
  end if;

  -- Collection → Layout (trava + ACTIVE), como na 5128.
  begin
    perform public.assert_collection_layout_mutable(v_layout_id);
  exception
    when others then
      if sqlerrm like 'collection layout not found%' then
        raise exception 'layout slot not found or not owned by caller';
      end if;
      raise;
  end;

  perform 1
     from public.collection_layout_slot s
    where s.id = p_slot_id
    for update;

  -- Revalidação pós-trava.
  perform 1
     from public.collection_layout_slot s
     join public.collection_layout_page p on p.id = s.page_id
     join public.collection_layout l      on l.id = p.layout_id
     join public.collection c             on c.id = l.collection_id
    where s.id = p_slot_id
      and p.layout_id = v_layout_id
      and c.owner_user_id = (select auth.uid());

  if not found then
    raise exception 'layout slot not found or not owned by caller';
  end if;

  if p_card_id is null then
    raise exception 'p_card_id é obrigatório';
  end if;

  if p_card_variant_id is not null and p_expected_variant_type_id is not null then
    raise exception 'EXPECTED_CONTENT_VARIANT_AND_TYPE_EXCLUSIVE: informe a variante específica OU o acabamento, não os dois'
      using errcode = '22023';
  end if;

  begin
    insert into public.collection_layout_slot_expected_content as ec
      (slot_id, card_id, card_variant_id, expected_variant_type_id)
    values
      (p_slot_id, p_card_id, p_card_variant_id, p_expected_variant_type_id)
    on conflict on constraint collection_layout_slot_expected_content_pkey
    do update set card_id                  = excluded.card_id,
                  card_variant_id          = excluded.card_variant_id,
                  expected_variant_type_id = excluded.expected_variant_type_id;
  exception
    when foreign_key_violation then
      raise exception
        'Card/Card Variant/acabamento inválido — quando informada, a Card Variant deve pertencer à Card indicada e o acabamento deve existir';
  end;

  return query
  select e.slot_id, e.card_id, e.card_variant_id, e.expected_variant_type_id
    from public.collection_layout_slot_expected_content e
   where e.slot_id = p_slot_id;
end;
$$;

comment on function public.set_slot_expected_content(uuid, uuid, uuid, uuid) is
  '5128 evoluída pela 5225 (M3): define o conteúdo planejado de um bolso do próprio Fichário Digital — carta; carta + variante específica; ou carta + acabamento (exclusivos). Exige auth.uid(); não enumera; coleção ACTIVE (5122); permitido em bolso fixado (5118).';

revoke all on function public.set_slot_expected_content(uuid, uuid, uuid, uuid) from public;
revoke all on function public.set_slot_expected_content(uuid, uuid, uuid, uuid) from anon;
grant execute on function public.set_slot_expected_content(uuid, uuid, uuid, uuid) to authenticated;

notify pgrst, 'reload schema';

commit;

/*
Como validar (estrutura, sem escrita):

select column_name, is_nullable, data_type
from information_schema.columns
where table_schema = 'public'
  and table_name = 'collection_layout_slot_expected_content'
order by ordinal_position;
-- Esperado: ... expected_variant_type_id | YES | uuid

select conname, pg_get_constraintdef(oid)
from pg_constraint
where conrelid = 'public.collection_layout_slot_expected_content'::regclass
order by conname;
-- Esperado (além das 4 FKs e da PK da 5113):
--   chk_expected_content_variant_xor_type :: CHECK ((card_variant_id IS NULL) OR (expected_variant_type_id IS NULL))
--   fk_expected_content_variant_type      :: FOREIGN KEY (expected_variant_type_id) REFERENCES card_variant_type(id) ...

select oid::regprocedure from pg_proc
where proname = 'set_slot_expected_content' and pronamespace = 'public'::regnamespace;
-- Esperado: exatamente 1 linha — set_slot_expected_content(uuid,uuid,uuid,uuid)
*/
