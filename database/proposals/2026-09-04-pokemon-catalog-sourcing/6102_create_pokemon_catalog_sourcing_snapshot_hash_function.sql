/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 6102 - Create Pokemon Catalog Sourcing Snapshot Hash Function
Versão......: 1.0 (PROPOSTA — GATE 3 STAGING)
Status......: PROPOSTO / NÃO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-04 (staging em POKEMON-CATALOG-SOURCING-INITIAL-LOAD-
               PHYSICAL-STAGING-01, materializando docs/06a-pokemon-catalog-
               sourcing.md v1.1, Seção 6)

Descrição resumida:
Único helper no banco que é autoridade para o cálculo do hash determinístico
do snapshot (Seção 6 do contrato 06a). Usado internamente por PLAN (Query
6104) e APPLY (Query 6105) para: (a) gravar snapshot_hash no DRY_RUN; (b)
validar que o snapshot recebido no APPLY corresponde byte-a-byte ao snapshot
aprovado no preflight.

Regras de Negócio (literais do contrato 06a, Seção 6):
- Fórmula exata: encode(pg_catalog.sha256(pg_catalog.convert_to(p_snapshot::
  text, 'UTF8')), 'hex') — produz hex lowercase de 64 caracteres.
- Função pura, determinística (IMMUTABLE): mesma entrada produz sempre a
  mesma saída. Não lê nem escreve nenhuma tabela.
- SET search_path = '' com todas as referências explicitamente qualificadas
  por pg_catalog — nenhuma dependência implícita de search_path.
- SECURITY INVOKER (não precisa de privilégio elevado; não toca em nenhuma
  tabela canônica).

Grants:
- Exposta como SERVICE_ROLE ONLY (mesmo padrão de todas as RPCs de sourcing,
  Seção 13) — permite que o caller (script Deno) recalcule/valide o hash de
  forma independente como diagnóstico, sem duplicar a fórmula fora do banco.
  PUBLIC/anon/authenticated sem EXECUTE.

Pré-requisitos: nenhum (função pura, sem dependência de tabela).
===============================================================================
*/

BEGIN;

CREATE OR REPLACE FUNCTION public.compute_pokemon_catalog_sourcing_snapshot_hash(
    p_snapshot JSONB
)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
    SELECT pg_catalog.encode(
        pg_catalog.sha256(
            pg_catalog.convert_to(p_snapshot::TEXT, 'UTF8')
        ),
        'hex'
    );
$$;

COMMENT ON FUNCTION public.compute_pokemon_catalog_sourcing_snapshot_hash(JSONB) IS
    'Autoridade única para o hash determinístico SHA-256 (lowercase, 64 hex) do snapshot do Pokémon Catalog Sourcing. Ver docs/06a-pokemon-catalog-sourcing.md Seção 6.';

REVOKE ALL ON FUNCTION public.compute_pokemon_catalog_sourcing_snapshot_hash(JSONB)
    FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.compute_pokemon_catalog_sourcing_snapshot_hash(JSONB)
    TO service_role;

COMMIT;
