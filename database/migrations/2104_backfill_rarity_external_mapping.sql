/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2104 - Backfill rarity_external_mapping
Versão......: 1.0
Status......: MIGRATION — CONFIRMADO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-07

Descrição...:
Popula public.rarity_external_mapping (Query 2096) com os 25 pares
valor-externo→Raridade que antes viviam hardcoded em
RARITY_NAME_ALIASES (import-catalog-cards/services/normalize.ts) —
migração de código para dado, sem qualquer mudança de
comportamento observável na importação TCGdex (mesmo conjunto de
aliases PT/EN já em uso). Fonte = TCGDEX, Game = POKEMON,
timestamp único de lote (2026-08-07 02:25:14.981183+00).

Regras de Negócio:
- Todos os external_value abaixo já em produção como aliases
  reconhecidos — este backfill não introduz nenhum mapeamento
  novo, apenas move o já existente para
  rarity_external_mapping.
- Preserva as duas variantes de escrita já aceitas para alguns
  valores (ex. "Shiny Rara"/"Shiny Rare", "Shiny Ultra
  Rara"/"Shiny Ultra Rare", "Mega Hiper Raro"/"Mega Rara Hiper",
  "ACE SPEC Rara"/"ACE SPEC Rare"/"ACE SPEC Raro") — cada uma é
  uma linha própria, já que normalized_external_value as distingue
  (a normalização remove acento/caixa/espaço, não sinônimos).
- Assume que 'POKEMON'/'TCGDEX' já existem em game/asset_source
  (dependência real, não validada por este script — falha com
  erro de FK se não existirem).

Pré-requisitos:
- Query 2096 - Create rarity_external_mapping Table.
- Rarities já cadastradas: COMMON, UNCOMMON, RARE, PROMO,
  ULTRA_RARE, DOUBLE_RARE, ILLUSTRATION_RARE,
  SPECIAL_ILLUSTRATION_RARE, ACE_SPEC_RARE, SHINY_RARE,
  SHINY_ULTRA_RARE, HYPER_RARE, MEGA_HYPER_RARE,
  MEGA_ATTACK_RARE, BLACK_WHITE_RARE.
================================================================
*/

INSERT INTO public.rarity_external_mapping (game_id, asset_source_id, external_value, normalized_external_value, rarity_id, created_at, updated_at)
SELECT g.id, asrc.id, v.external_value, public.normalize_external_catalog_value(v.external_value), r.id,
       '2026-08-07 02:25:14.981183+00'::timestamptz, '2026-08-07 02:25:14.981183+00'::timestamptz
FROM (VALUES
    ('ACE SPEC Rara', 'ACE_SPEC_RARE'),
    ('ACE SPEC Rare', 'ACE_SPEC_RARE'),
    ('ACE SPEC Raro', 'ACE_SPEC_RARE'),
    ('Brilhante Ultra Rara', 'SHINY_ULTRA_RARE'),
    ('Common', 'COMMON'),
    ('Comum', 'COMMON'),
    ('Hiper Rara', 'HYPER_RARE'),
    ('Ilustração Rara', 'ILLUSTRATION_RARE'),
    ('Ilustração Rara Especial', 'SPECIAL_ILLUSTRATION_RARE'),
    ('Incomum', 'UNCOMMON'),
    ('Mega Hiper Raro', 'MEGA_HYPER_RARE'),
    ('Mega Rara Hiper', 'MEGA_HYPER_RARE'),
    ('Promo', 'PROMO'),
    ('Rara', 'RARE'),
    ('Rara Dupla', 'DOUBLE_RARE'),
    ('Rara Mega Ataque', 'MEGA_ATTACK_RARE'),
    ('Rara Preto e Branco', 'BLACK_WHITE_RARE'),
    ('Rara Ultra', 'ULTRA_RARE'),
    ('Rare', 'RARE'),
    ('Shiny Rara', 'SHINY_RARE'),
    ('Shiny Rare', 'SHINY_RARE'),
    ('Shiny Ultra Rara', 'SHINY_ULTRA_RARE'),
    ('Shiny Ultra Rare', 'SHINY_ULTRA_RARE'),
    ('Ultra Rara', 'ULTRA_RARE'),
    ('Uncommon', 'UNCOMMON')
) AS v(external_value, rarity_code)
JOIN public.game g ON g.code = 'POKEMON'
JOIN public.asset_source asrc ON asrc.code = 'TCGDEX'
JOIN public.rarity r ON r.code = v.rarity_code AND r.game_id = g.id;

-- ================================================================
-- Confirmado executado (2026-08-07): 25 linhas inseridas, todas
-- com created_at/updated_at = 2026-08-07 02:25:14.981183+00
-- (lote único), conferido via SELECT direto em produção. Nenhuma
-- regressão observada em importações TCGdex subsequentes.
-- ================================================================
