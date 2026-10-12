# Pokédex P2 — Lote A: fundação das imagens das espécies

| Arquivo | Papel | Status |
|---|---|---|
| `6132_create_pokemon_species_artwork_foundation.sql` | Tabela `pokemon_species_artwork`, 3 funções admin, bucket `pokemon-species-artwork` + policies, `get_pokedex_national_species` com `artwork_path` | **CONFIRMADO EXECUTADO** 2026-10-12 (v1.0) — promovida para `database/migrations/6132_create_pokemon_species_artwork_foundation.sql`; este arquivo fica como registro da proposta |
| `6842_validate_pokemon_species_artwork_foundation.sql` | Validação (BEGIN/ROLLBACK) | **v1.1 executada — `6842 PASS`** |
| `6843_postcheck_pokemon_species_artwork_full_load.sql` | Conferência pós-carga integral do Lote D (somente leitura; Bloco 2 em BEGIN/ROLLBACK) | **Executada após a carga integral (2026-10-12) — 22/22 PASS + Bloco 2 PASS** (1.025 IMPORTED, 2.050 objetos, 0 faltantes/órfãos, `artwork_path` 1.025/1.025, outros buckets e `card_asset` idênticos ao baseline) |

**6842 v1.1.** A v1.0 abortou no passo 3 com 42501: o fixture lia `pokemon_species_external_reference` já no papel `authenticated` (tabela corretamente fechada). Defeito do script, não da 6132; a transação foi desfeita por inteiro (0 linhas, 0 objetos). Na v1.1 a referência é lida como owner antes da troca de papel (`set_config('mmkyu.v6842_ref', …)`); nenhuma asserção foi alterada.

**Evidência da execução (LIVE, 2026-10-12).**
- `6842 PASS`: estrutura/RLS/privilégios/bucket/policies; usuário comum com 1.025 espécies e `artwork_path` nulo, busca e filtros intactos, sem acesso à tabela nem às funções admin; admin com 1.025 pendentes, vínculo/caminho/objeto/dimensões inválidos recusados, `RECOVERED` → `UNCHANGED` → falha com imagem preservada → `REPLACED`; colecionador recebendo só o caminho WebP; anon sem execução; CHECKs de status e completude.
- Rollback integral dos fixtures: `pokemon_species_artwork` = 0 linhas; bucket com 0 objetos; total de `storage.objects` igual ao baseline (31.702).
- Postcheck contra o baseline pré-execução: espécies (1.025, hash idêntico), gerações (9, hash idêntico), regiões, posições, referências externas, `card_primary_species`, `card_asset`; hash de ACL das tabelas existentes, hash das policies existentes e hash das funções pré-existentes — todos idênticos. Única mudança: os objetos novos da 6132 e a recriação de `get_pokedex_national_species` (+ `artwork_path`).

**Contrato para o Lote B (processo Node + Sharp, sessão de administrador):**
1. Resolver origem: `/pokemon-species/{external_species_id}` → `varieties[is_default]` → `/pokemon/{id}` → `sprites.other.official-artwork.front_default`.
2. Baixar, validar PNG e dimensões, gerar WebP 320 px (Sharp), calcular SHA-256 dos dois.
3. Enviar `official-artwork/<NNNN>/original-<sha16>.png` e `.../w320-<sha16>.webp` (sem upsert — arquivos imutáveis).
4. Registrar com `admin_record_pokemon_species_artwork_import(...)`; em qualquer falha, `admin_record_pokemon_species_artwork_failure(...)` (não derruba imagem válida).

**Rollback** (antes de haver imagens): `drop function` das 3 funções admin; recriar `get_pokedex_national_species` da 6131; `drop table public.pokemon_species_artwork`; remover as 2 policies e o bucket vazio.
