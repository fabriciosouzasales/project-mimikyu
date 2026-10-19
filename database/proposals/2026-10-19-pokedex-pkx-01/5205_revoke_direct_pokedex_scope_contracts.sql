/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5205 - Fecha o acesso direto às RPCs de escopo antigo
              (5098 create_reference_based_pokedex_collection e 5099
              set_collection_pokedex_scope)
Versão......: 1.0
Status......: PROPOSTA — não executada no LIVE.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-19 (POKEDEX-PKX-01-IMPLEMENTATION-01)

Por quê:
  5098 e 5099 aceitam scope_kind = 'FULL_REFERENCE', cujo total é
  calculado ao vivo — uma geração catalogada no futuro entraria sozinha
  na coleção, o que contraria C-02 e a decisão do proprietário
  (2026-10-19: coleções existentes não incorporam gerações novas).
  Com EXECUTE para authenticated, uma chamada direta à API criaria esse
  escopo sem passar pelas novas portas (5202/5203).

O que faz:
  REVOKE EXECUTE de authenticated (e reafirma PUBLIC/anon) nas duas
  funções. Nada mais: corpo, assinatura e dono inalterados.

Consumidores verificados (2026-10-19, leitura do repositório e do LIVE):
  - web/ e supabase/functions/: nenhuma chamada.
  - SQL no LIVE: nenhuma função além das próprias referencia 5098/5099;
    a partir desta proposta, só 5202/5203 (SECURITY DEFINER, dono
    postgres) — o dono mantém EXECUTE implícito, então as novas portas
    continuam funcionando.
  - Harnesses históricos 5814/5815/5816/6830 chamavam 5098 como
    authenticated; já executados e encerrados. Se algum precisar ser
    reexecutado, a chamada passa a ser feita como dono (ver README).
  - Tabelas do escopo (collection_reference, collection_pokedex_reference,
    collection_pokedex_scope_generation, collection): authenticated só
    tem SELECT — não existe caminho alternativo de escrita.
  - LIVE: 0 coleções Pokédex.

Como validar: 5844 v1.0 (0.2, 0.3 e testes negativos 1.2).
Recuperação:
  grant execute on function public.create_reference_based_pokedex_collection(uuid, text, text, uuid, uuid, text, uuid[]) to authenticated;
  grant execute on function public.set_collection_pokedex_scope(uuid, text, uuid[]) to authenticated;
================================================================
*/

begin;

revoke execute on function public.create_reference_based_pokedex_collection(uuid, text, text, uuid, uuid, text, uuid[])
  from public, anon, authenticated;

revoke execute on function public.set_collection_pokedex_scope(uuid, text, uuid[])
  from public, anon, authenticated;

comment on function public.create_reference_based_pokedex_collection(uuid, text, text, uuid, uuid, text, uuid[]) is
  'Fatia B (Query 5098). Desde a 5205: sem EXECUTE para clientes; uso interno via create_my_pokedex_collection (5202), sempre com escopo explícito.';

comment on function public.set_collection_pokedex_scope(uuid, text, uuid[]) is
  'Fatia B (Query 5099). Desde a 5205: sem EXECUTE para clientes; uso interno via set_my_pokedex_generations (5203), sempre com escopo explícito.';

commit;
