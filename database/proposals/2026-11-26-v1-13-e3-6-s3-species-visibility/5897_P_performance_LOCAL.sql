/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5897_P - Desempenho da 5393 × 5316 (separado da equivalência, C3)
Versão......: 1.0 (2026-11-26)
Status......: PROPOSTA — NÃO EXECUTADA. SOMENTE PostgreSQL LOCAL DESCARTÁVEL,
              dentro de transação revertida. Nunca no LIVE (medição no LIVE só
              com autorização específica).
Autor.......: Fabrício Sales / Claude
Data........: 2026-11-26

Montagem: como a seção F do harness 5897, mas com X cobrindo TODAS as gerações
(Pokédex Nacional inteira) e fichário 4 × 4 com 66 páginas (perfil do F002:
1.056 bolsos, ~1.025 referências), camada aplicada e exibição ligada; VIEWER V.

Medições (como V; repetir 5 vezes cada, descartar a primeira, registrar a mediana):
  janelas: (1, 4), (33, 4), (63, 4)
  explain (analyze, buffers, timing) select * from public.get_shared_collection_binder_pages(X, p, 4);
  explain (analyze, buffers, timing) select * from public.get_shared_collection_binder_pages_with_species(X, p, 4);

Critérios (registrar o valor medido; nenhum PASS presumido):
  P1  nenhuma varredura sequencial em collection_layout_slot_species_reference,
      collection_layout_slot, collection_layout_page, pokedex_position,
      pokemon_species ou pokemon_species_artwork na parte nova (uso de
      pk_cl_slot_species_reference, uq_collection_layout_slot_position,
      uq_collection_layout_page_number e PKs);
  P2  mediana da 5393 ≤ 2 × mediana da 5316 na mesma janela;
  P3  ≤ 64 linhas por janela no perfil F002 (4 × 16).
Observação: a 5393 é plpgsql SECURITY DEFINER; para ver o plano da consulta
interna, usar auto_explain local (auto_explain.log_nested_statements = on).
================================================================
*/

-- load 'auto_explain';
-- set auto_explain.log_min_duration = 0;
-- set auto_explain.log_analyze = on;
-- set auto_explain.log_buffers = on;
-- set auto_explain.log_nested_statements = on;
-- (montagem e medições conforme o cabeçalho)
