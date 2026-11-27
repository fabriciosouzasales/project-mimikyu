/*
================================================================
Projeto.....: Project Mimikyu
Query.......: EMERGENCY_STOP_V1_13 — complemento E2b (S2: 5391 e 5392)
Versão......: 1.0 (2026-11-27)
Status......: PROPOSTA — NÃO EXECUTADA. Uso exclusivo do proprietário, com autorização.
              Complementa g1/EMERGENCY_STOP_V1_13.sql (gerado e protegido; não alterado):
              mesma camada 2, mesmo formato, não depende da porta 5389.
Ordem.......: E1 do script principal (modo CLOSED) → E2 do principal (revoga, entre outras,
              as 4 escritas da 5380) → este E2b. Pode rodar sozinho: não depende dos outros.
Revoga......: as 4 escritas da 5392 e a leitura do EDITOR da 5391 (expõe identificadores
              opacos), de PUBLIC/anon/authenticated (como o E2). Os ajudantes internos não
              têm EXECUTE para a API.
Não faz.....: não concede nada (as escritas da 5380 continuam revogadas); não toca 5393
              (leitura do participante com fallback C2 por CAPABILITY_NOT_ENABLED — o E1 já
              a desliga; revogar trocaria o código por 42501 e quebraria o fallback); não
              cancela chamadas em curso; não desfaz o que foi gravado.
================================================================
*/

-- E2b ------------------------------------------------------------------------------------
begin;
set local lock_timeout = '5s';
revoke execute on function public.editor_move_pokedex_copy(uuid, text, uuid, uuid, boolean) from public, anon, authenticated;
revoke execute on function public.editor_unassign_pokedex_copy(uuid, text, uuid) from public, anon, authenticated;
revoke execute on function public.editor_choose_pokedex_representative(uuid, text, uuid, text) from public, anon, authenticated;
revoke execute on function public.editor_restore_pokedex_automatic_representative(uuid, uuid, text) from public, anon, authenticated;
revoke execute on function public.get_editor_pokedex_position_copies(uuid, uuid, text, text, integer, integer) from public, anon, authenticated;
commit;
