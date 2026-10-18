/*
================================================================
Projeto.....: Project Mimikyu
Artefato....: PROVA DE CONCORRÊNCIA EXTERNA — K1 a K5 (Master Set por acabamento)
Versão......: 1.2 (AUDIT-CORRECTION-01: K5; AUDIT-CORRECTION-02: pré-condições do Set e ordem dos passos do K5)
Status......: ROTEIRO MANUAL — NÃO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-18 (MASTER-SET-DOCUMENTATION-AND-CONTRACT-PROPOSAL-01)

NÃO É MIGRATION. NÃO É NUMERADO NA FAIXA 5xxx. Não promover.
Executar só depois de 5184–5197 aplicadas e 5836 GATE PASS, com
autorização de Fabrício. Mesmo formato de CONCURRENCY-PROOF-BULK-CLAIM
(2026-09-07): duas sessões psql persistentes (Session Pooler, porta
5432) + observador one-shot (SQL Editor). O SQL Editor NÃO serve para
A/B (não mantém transação aberta).

Por que fora do 5836: concorrência real exige duas conexões; um único
statement não prova espera de trava.

O que se prova (todas as escritas de objetivo travam a linha da coleção
com SELECT … FOR UPDATE, assim como 5046/5047/5081):
  K1  edição de acabamentos × vínculo de exemplar na mesma coleção:
      a segunda espera a primeira; resultado final coerente.
  K2  voltar ao Set padrão (5081) × editar acabamentos (5195): a edição
      espera e, ao obter a trava, relê a coleção e recusa com
      MASTER_SET_NOT_ACTIVE (nunca grava num Master Set desativado).
  K3  duas edições simultâneas com conjuntos diferentes: serializadas;
      vence a última confirmada; PK impede duplicidade; nunca vazio.
  K4  reenvio simultâneo da mesma ativação: a segunda espera e vira
      no-op (0 inclusões), sem erro.
  K5  editar acabamentos (5195) × desvincular exemplar (5047) na mesma
      coleção: a segunda espera a primeira (mesma trava da linha de
      collection); o exemplar desvinculado continua no acervo; o resumo
      final reflete os dois efeitos.

----------------------------------------------------------------
SETUP (CONEXÃO ADMINISTRATIVA, uma vez, COMMIT)
----------------------------------------------------------------
-- Escolher um Set real que tenha, ativos: ≥ 2 cartas com variante padrão
-- (is_default) do acabamento Padrão, e ao menos uma variante Holo e uma
-- Reverse (K1/K5 usam Reverse; K3 usa Holo). Anotar :set_id. Conferir:
--   select t.code, count(*) from public.card c
--     join public.card_variant cv on cv.card_id = c.id and cv.is_active
--     join public.card_variant_type t on t.id = cv.variant_type_id
--   where c.card_set_id = :'set_id' and c.is_active
--     and t.code in ('STANDARD','HOLO','REVERSE_HOLO') group by t.code;   -- 3 linhas
-- Criar usuário efêmero e 2 exemplares (anotar :user, :pc1, :pc2):
begin;
insert into auth.users (id, aud, role, email, raw_user_meta_data, created_at, updated_at)
values (gen_random_uuid(), 'authenticated', 'authenticated', 'mskprobe@example.invalid',
        jsonb_build_object('username','mskprobe','display_name','MS K probe'), now(), now())
returning id;                                   -- :user
insert into public.physical_card (card_variant_id, language_id, inventory_id)
select cv.id, (select id from public.language where code = 'pt-BR'),
       (select i.id from public.inventory i where i.owner_user_id = :'user')
from public.card c join public.card_variant cv on cv.card_id = c.id and cv.is_default and cv.is_active
where c.card_set_id = :'set_id' and c.is_active
order by c.collector_order limit 2
returning id;                                   -- :pc1, :pc2
commit;
-- Ids de acabamento (anotar :std, :holo, :rev):
--   select code, id from public.card_variant_type
--   where game_id = (select id from public.game where code = 'POKEMON')
--     and code in ('STANDARD','HOLO','REVERSE_HOLO');
-- Coleção (como o usuário) — anotar :coll
begin;
select set_config('request.jwt.claims', json_build_object('sub', :'user', 'role','authenticated')::text, true);
set local role authenticated;
select collection_id from public.create_my_card_set_collection(gen_random_uuid(), :'set_id', 'MS K probe', null);
select public.set_collection_completion_policy_to_master_set(:'coll', array[:'std']::uuid[]);
commit;

----------------------------------------------------------------
Em toda transação de A ou B, primeiro:
  begin;
  select set_config('request.jwt.claims', json_build_object('sub', :'user', 'role','authenticated')::text, true);
  set local role authenticated;
----------------------------------------------------------------

K1 — edição × vínculo
  A: select * from public.replace_master_set_finishes(:'coll', array[:'std', :'rev']::uuid[]);   -- não confirma
  B: select * from public.allocate_physical_cards_to_collection(:'coll', array[:'pc1']::uuid[]); -- deve ESPERAR
  A: commit;            → B destrava e conclui
  B: commit;
  OBSERVADOR: select * from public.collection_completion_summary(:'coll');  (como o usuário)
  PASS se B esperou até o COMMIT de A e o resumo reflete os 2 acabamentos e o exemplar vinculado.

K2 — voltar ao Set padrão × editar
  A: select * from public.set_collection_completion_policy_to_standard_set(:'coll');           -- não confirma
  B: select * from public.replace_master_set_finishes(:'coll', array[:'std']::uuid[]);          -- deve ESPERAR
  A: commit;            → B recebe erro MASTER_SET_NOT_ACTIVE
  B: rollback;
  PASS se B esperou e falhou com MASTER_SET_NOT_ACTIVE; acabamentos guardados intactos
  (2 linhas em collection_master_set_finish).
  Reativar para K3 (uma transação): select public.set_collection_completion_policy_to_master_set(:'coll', null); commit;

K3 — duas edições
  A: select * from public.replace_master_set_finishes(:'coll', array[:'holo']::uuid[]);  -- não confirma
  B: select * from public.replace_master_set_finishes(:'coll', array[:'std', :'holo']::uuid[]);  -- deve ESPERAR
  A: commit;   B: commit;
  OBSERVADOR (CONEXÃO ADMINISTRATIVA):
    select variant_type_id from public.collection_master_set_finish where collection_id = :'coll' order by 1;
  PASS se o resultado é exatamente {std, holo} (o de B, confirmado por último), sem linha repetida.
  (Se o Set não tiver Holo, usar outro acabamento existente no Set.)

K4 — reenvio simultâneo da ativação
  CONEXÃO ADMINISTRATIVA: voltar ao Set padrão (como o usuário, 5081) e confirmar.
  A: select * from public.set_collection_completion_policy_to_master_set(:'coll', array[:'std']::uuid[]);  -- não confirma
  B: select * from public.set_collection_completion_policy_to_master_set(:'coll', array[:'std']::uuid[]);  -- deve ESPERAR
  A: commit;   B: commit;
  PASS se B retorna finishes_added = 0, finishes_removed = 0 e não há erro.

K5 — editar × desvincular
  Pré-condições (conferir antes): coleção em MASTER_SET {std} (estado deixado pelo K4);
  :pc1 vinculado (desde o K1); :pc2 no acervo, sem vínculo.
  Ordem 1 — edição primeiro:
  A: select * from public.replace_master_set_finishes(:'coll', array[:'std', :'rev']::uuid[]);       -- não confirma
  B: select * from public.deallocate_physical_cards_from_collection(:'coll', array[:'pc1']::uuid[]); -- deve ESPERAR
  A: commit;            → B destrava e conclui
  B: commit;
  Preparação da ordem 2 (uma transação própria, como o usuário, e commit):
     select * from public.allocate_physical_cards_to_collection(:'coll', array[:'pc2']::uuid[]);
  Ordem 2 — desvínculo primeiro:
  B: select * from public.deallocate_physical_cards_from_collection(:'coll', array[:'pc2']::uuid[]); -- não confirma
  A: select * from public.replace_master_set_finishes(:'coll', array[:'std']::uuid[]);              -- deve ESPERAR
  B: commit;            → A destrava e conclui
  A: commit;
  OBSERVADOR (CONEXÃO ADMINISTRATIVA):
    select (select count(*) from public.collection_allocation where collection_id = :'coll') as vinculos,
           (select count(*) from public.physical_card where id in (:'pc1', :'pc2')) as exemplares,
           (select array_agg(variant_type_id order by 1) from public.collection_master_set_finish
              where collection_id = :'coll') as acabamentos;
  PASS se, nas duas ordens, a segunda sessão esperou o COMMIT da primeira; vinculos = 0,
  exemplares = 2 (nada apagado) e acabamentos = {std}.
  Contratos: replace_master_set_finishes(uuid, uuid[]) (5195) e
  deallocate_physical_cards_from_collection(uuid, uuid[]) (5047) travam a mesma linha de
  collection com SELECT … FOR UPDATE (5195: cabeçalho; 5047: canônica, seção de concorrência).

----------------------------------------------------------------
CLEANUP (CONEXÃO ADMINISTRATIVA, COMMIT)
----------------------------------------------------------------
begin;
select set_config('request.jwt.claims', json_build_object('sub', :'user', 'role','authenticated')::text, true);
set local role authenticated;
select public.delete_collection(:'coll');
commit;
begin;
delete from public.physical_card where inventory_id = (select id from public.inventory where owner_user_id = :'user');
delete from auth.users where id = :'user';
commit;
-- Postcheck: zero coleções, exemplares, acabamentos e usuário do probe.
select (select count(*) from auth.users where id = :'user') as usuario,
       (select count(*) from public.collection where owner_user_id = :'user') as colecoes,
       (select count(*) from public.collection_master_set_finish f
          where f.collection_id = :'coll') as acabamentos;
================================================================
*/
