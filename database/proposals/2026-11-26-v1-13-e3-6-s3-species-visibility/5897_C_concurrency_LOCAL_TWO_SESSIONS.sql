/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5897_C - Concorrência da 5393 em DUAS sessões (C1): mesmo
              instantâneo dentro da chamada, controle negativo VOLATILE,
              atomicidade observada, autorização no mesmo instantâneo
Versão......: 1.0 (2026-11-26)
Status......: PROPOSTA — NÃO EXECUTADA. SOMENTE PostgreSQL LOCAL DESCARTÁVEL
              (o fixture é CONFIRMADO para a outra sessão enxergá-lo; apagar o
              banco no fim). Nunca no LIVE.
Autor.......: Fabrício Sales / Claude
Data........: 2026-11-26

Roteiro (dois terminais psql no mesmo banco local; a ordem importa):
  PARTE 0  (sessão B)  fixture confirmado → tabela de apoio wh5897c_ids
  PARTE A1 (sessão A)  ajudantes do ENSAIO em pg_temp (STABLE e VOLATILE)
  PARTE A2 (sessão A)  select * from pg_temp.wh5897c_stable();   -- dorme 8 s
  PARTE B1 (sessão B)  em até 8 s: três transações confirmadas (remover a
                       camada; reordenar páginas 1↔2; ocultar)
  → resultado A2: h1 = h2 = h_antes                         (critério C1-a)
  PARTE 0b (sessão B)  restaurar (reaplicar camada, reordenar de volta, mostrar)
  PARTE A3 (sessão A)  select * from pg_temp.wh5897c_volatile(); -- dorme 8 s
  PARTE B1 de novo
  → resultado A3: h2 ≠ h1                                   (critério C1-b: o mecanismo é a volatilidade)
  PARTE 0b de novo
  PARTE A4 / B2        atomicidade: B abre transação, remove a camada, NÃO
                       confirma; A lê (camada inteira presente); B confirma;
                       A lê (camada inteira ausente)      (critério C1-c)
  PARTE 0b de novo
  PARTE A5 / B3        autorização: A chama wh5897c_stable como VIEWER; B
                       remove a participação durante o sono e confirma
  → h2 = h1 (mesma chamada); chamada seguinte de A: P0002  (critério C1-d)
  PARTE Z              teardown: dropar o banco local.

Nada aqui é declarado PASS antes de executado e registrado.
================================================================
*/

-- PARTE 0 (sessão B) — fixture confirmado ---------------------------------------------------------
-- Pré-requisito: banco local com a cadeia E1 + 5393 aplicadas e a barreira OPEN
--   update public.v1_13_barrier_state set mode = 'OPEN', change_note = '5897_C local' where id = 1;
-- Montagem: a mesma da seção F do harness 5897 (titular U, X Pokédex proprietária do fichário 3 × 3
-- com 2 páginas e camada aplicada, VIEWER V aceito), executada FORA de transação revertida, e
-- os ids gravados em:
create table if not exists public.wh5897c_ids (k text primary key, v uuid not null);
-- insert into public.wh5897c_ids values ('U', …), ('V', …), ('X', …), ('L', …), ('M_V', …);

-- PARTE A1 (sessão A) — ajudantes do ensaio (só nesta sessão) ---------------------------------------
create or replace function pg_temp.wh5897c_as(p_user uuid)
returns void language plpgsql volatile as $as$
begin
  execute 'reset role';
  perform set_config('request.jwt.claim.sub', p_user::text, false);
  perform set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, false);
  execute 'set role authenticated';
end;
$as$;

create or replace function pg_temp.wh5897c_h(p_coll uuid)
returns text language sql stable as $h$
  select md5(coalesce(jsonb_agg(to_jsonb(x) order by x.page_number, x.row_index, x.column_index), '[]'::jsonb)::text)
  from public.get_shared_collection_binder_pages_with_species(p_coll, 1, 2) x;
$h$;

-- STABLE: as duas leituras usam o instantâneo da consulta que chamou (a mesma semântica da 5393).
create or replace function pg_temp.wh5897c_stable(out h1 text, out h2 text)
language plpgsql stable as $s$
declare x uuid := (select v from public.wh5897c_ids where k = 'X');
begin
  h1 := pg_temp.wh5897c_h(x);
  perform pg_sleep(8);
  h2 := pg_temp.wh5897c_h(x);
end;
$s$;

-- VOLATILE (controle negativo): cada leitura tira um instantâneo novo.
create or replace function pg_temp.wh5897c_volatile(out h1 text, out h2 text)
language plpgsql volatile as $v$
declare x uuid := (select v from public.wh5897c_ids where k = 'X');
begin
  h1 := pg_temp.wh5897c_h(x);
  perform pg_sleep(8);
  h2 := pg_temp.wh5897c_h(x);
end;
$v$;

-- Ler como VIEWER (sessão A), antes de cada parte:
--   select pg_temp.wh5897c_as((select v from public.wh5897c_ids where k = 'V'));
--   select pg_temp.wh5897c_h((select v from public.wh5897c_ids where k = 'X')) as h_antes;

-- PARTE A2 (sessão A) ------------------------------------------------------------------------------
--   select * from pg_temp.wh5897c_stable();

-- PARTE B1 (sessão B, durante o sono de A; cada bloco confirma sozinho, como titular U) ------------
--   select pg_temp.wh5897c_as_b(U);  -- ou set_config/set role equivalente na sessão B
--   select * from public.clear_my_binder_species_references(X, (select reference_count from public.get_my_binder_species_reference_state(X)));
--   select * from public.reorder_layout_pages(L, …);  -- reordenar 1 ↔ 2 pela função do titular (5126; conferir nome/assinatura no banco local)
--   select * from public.set_my_binder_species_reference_visibility(X, false);

-- PARTE 0b (sessão B) — restaurar ---------------------------------------------------------------------
--   select * from public.set_my_binder_species_reference_visibility(X, true);
--   reordenar de volta; preview_my_binder_species_references(X) + apply_my_binder_species_references(X, token)

-- PARTE A3 (sessão A) ------------------------------------------------------------------------------
--   select * from pg_temp.wh5897c_volatile();

-- PARTE A4 / B2 — atomicidade ------------------------------------------------------------------------
--   B: begin; select * from public.clear_my_binder_species_references(X, N);   -- sem commit
--   A: select count(*) filter (where species_national_number is not null) from public.get_shared_collection_binder_pages_with_species(X, 1, 2);  -- = N_janela
--   B: commit;
--   A: (mesma consulta)  -- = 0; nunca valor intermediário

-- PARTE A5 / B3 — autorização no mesmo instantâneo ---------------------------------------------------
--   A: select * from pg_temp.wh5897c_stable();
--   B (durante o sono): select public.remove_collection_member(X, M_V);  -- como U, confirmado
--   A: h2 = h1; depois: select * from public.get_shared_collection_binder_pages_with_species(X, 1, 2);  -- P0002 COLLECTION_NOT_FOUND

-- PARTE Z — teardown ------------------------------------------------------------------------------
--   dropar o banco local descartável (não há limpeza parcial confiável depois de confirmar o fixture).
