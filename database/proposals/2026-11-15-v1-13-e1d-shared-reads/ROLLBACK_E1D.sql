/*
================================================================
Projeto.....: Project Mimikyu
Query.......: ROLLBACK_E1D — reversão de 5323, 5324 e 5388 (V1-13 · E1-D)
Versão......: 1.0
Status......: PROPOSTA — NÃO EXECUTADA. Uso exclusivo de recuperação, pelo
              proprietário, com autorização expressa. Ordem: R5388 → R5324 →
              R5323 (inversa da aplicação), cada bloco uma transação própria
              (psql). Vem ANTES de ROLLBACK_E1C2 (a E1-D é a última etapa
              aplicada da cadeia E1).
Autor.......: Fabrício Sales / Claude
Data........: 2026-11-15
Efeito......: retira só as leituras de participante. Não apaga nem altera
              dado algum: histórico, alocações, atribuições Pokédex, fichário
              e participações permanecem. As leituras do titular (5198, 5204,
              5269) e as leituras compartilhadas da V1-12 (5310–5321, 5325–5328)
              não são tocadas. Depois da reversão, o frontend que chamar estas
              funções recebe "função inexistente" — só reverter com a E2
              desligada.
================================================================
*/

-- R5388 -------------------------------------------------------------------------------------
begin;
set local lock_timeout = '5s';
drop function if exists public.get_shared_binder_activity_status(uuid);
drop function if exists public.get_shared_binder_activity(uuid, text[], timestamptz, bigint, integer);
commit;

-- R5324 -------------------------------------------------------------------------------------
begin;
set local lock_timeout = '5s';
drop function if exists public.get_shared_pokedex_positions(uuid, text, text, integer, integer);
commit;

-- R5323 -------------------------------------------------------------------------------------
begin;
set local lock_timeout = '5s';
drop function if exists public.get_shared_master_set_positions(uuid, text, integer, integer);
commit;
