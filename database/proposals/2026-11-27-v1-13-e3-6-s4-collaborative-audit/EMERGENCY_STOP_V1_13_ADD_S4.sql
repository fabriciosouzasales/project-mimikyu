/*
================================================================
Projeto.....: Project Mimikyu
Query.......: EMERGENCY_STOP_V1_13 — complemento E2c (S4-b: 5395)
Versão......: 1.0 (2026-11-27)
Status......: PROPOSTA — NÃO EXECUTADA. Uso exclusivo do proprietário, com autorização.
              Mesmo formato e camada de g1/EMERGENCY_STOP_V1_13.sql (não alterado) e do E2b
              (S2). Revoga a leitura do histórico por coleção (5395) de PUBLIC/anon/authenticated.
Não faz.....: não revoga as funções do titular (6122–6126: núcleo do produto). A instrumentação
              delas já fica inerte com o E1 (modo CLOSED): v1_13_capability_open() falso → nenhum
              evento. Não concede nada; não toca outras funcionalidades.
================================================================
*/

-- E2c ------------------------------------------------------------------------------------
begin;
set local lock_timeout = '5s';
revoke execute on function public.get_collection_activity(uuid, bigint, integer) from public, anon, authenticated;
commit;
