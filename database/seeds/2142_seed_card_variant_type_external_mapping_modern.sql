/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2142 - Seed card_variant_type_external_mapping (moderno)
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-15

Descrição...:
Semeia os 5 mapeamentos modernos já confirmados por teste real contra
o dataset-fonte da TCGdex nesta mesma frente (base1-4, me02.5-002,
swsh3-136, sv01-194/172/198): normal→STANDARD, reverse simples→
REVERSE_HOLO, holo→HOLO, reverse+foil:pokeball→POKE_BALL_REVERSE,
reverse+foil:energy→ENERGY_REVERSE.

Regras de Negócio:
- Só os 5 confirmados por evidência real entram aqui. card_variant_type
  já tem outros códigos de reverse por padrão de bola
  (MASTER_BALL_REVERSE/QUICK_BALL_REVERSE/LOVE_BALL_REVERSE/
  FRIEND_BALL_REVERSE/DUSK_BALL_REVERSE/ROCKET_REVERSE) e outros dois
  tipos (COSMOS_HOLO/PROMO_STAMPED) — plausivelmente mapeáveis por
  analogia de nome, mas NENHUM foi observado de fato num Card real da
  TCGdex nesta sessão. Ficam deliberadamente sem mapeamento agora —
  combinações da fonte que caírem neles nascerão NEEDS_REVIEW no
  Incremento 2, não um mapeamento adivinhado.
- Vintage (unlimited/shadowless/1st-edition/1999-2000-copyright) fica
  de fora, por decisão explícita — nenhuma linha aqui usa
  external_subtype/external_stamp.
- game_id/asset_source_id/variant_type_id resolvidos por subquery
  (código/nome), não por UUID fixo — script portável entre ambientes.

Pré-requisitos:
- Query 2140 - Create card_variant_type_external_mapping Table.
================================================================
*/

BEGIN;

INSERT INTO public.card_variant_type_external_mapping (
    game_id, asset_source_id,
    external_type, external_foil, external_subtype, external_stamp,
    normalized_type, normalized_foil, normalized_subtype, normalized_stamp,
    variant_type_id
)
SELECT
    g.id, a.id,
    v.external_type, v.external_foil, NULL, NULL,
    public.normalize_external_catalog_value(v.external_type),
    CASE WHEN v.external_foil IS NULL THEN NULL ELSE public.normalize_external_catalog_value(v.external_foil) END,
    NULL, NULL,
    vt.id
FROM (VALUES
    ('normal', NULL::TEXT, 'STANDARD'),
    ('reverse', NULL::TEXT, 'REVERSE_HOLO'),
    ('holo', NULL::TEXT, 'HOLO'),
    ('reverse', 'pokeball', 'POKE_BALL_REVERSE'),
    ('reverse', 'energy', 'ENERGY_REVERSE')
) AS v(external_type, external_foil, variant_type_code)
JOIN public.game g ON g.code = 'POKEMON'
JOIN public.asset_source a ON a.code = 'TCGDEX'
JOIN public.card_variant_type vt ON vt.code = v.variant_type_code;

COMMIT;

-- ================================================================
-- Confirmado executado (2026-08-15, via execute_sql/MCP do Supabase,
-- projeto qjfutqujxrbzgrtkpgkg): 5 linhas gravadas, conferidas por
-- SELECT (external_type/external_foil/variant_type_code) — exatamente
-- as 5 combinações acima, nenhuma linha extra.
-- ================================================================

-- ================================================================
-- Como validar:
-- SELECT external_type, external_foil, vt.code
-- FROM public.card_variant_type_external_mapping m
-- JOIN public.card_variant_type vt ON vt.id = m.variant_type_id
-- ORDER BY external_type, external_foil;
-- Esperado: exatamente 5 linhas, as combinações acima.
-- ================================================================
