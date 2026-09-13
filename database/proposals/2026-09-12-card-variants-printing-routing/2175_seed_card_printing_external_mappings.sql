/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 2175 - Seed Card Printing External Mappings (POKEMON / TCGDEX)
Versão......: 1.0
Status......: PROPOSTA — NÃO EXECUTADA
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-12
Mandato.....: CARD-VARIANTS — PRINTING-ROUTING — STAGING-GATE-A-01 (§9)

Descrição resumida:
Semeia os 5 mappings ACTIVE ratificados e seus 6 vinculos.

Descrição:
    subtype | shadowless            -> SHADOWLESS
    subtype | unlimited             -> UNLIMITED
    subtype | 1999-2000-copyright   -> COPYRIGHT_1999_2000
    subtype | shadowless-red-cheek  -> SHADOWLESS + RED_CHEEK   (1 cabecalho, 2 vinculos)
    stamp   | 1st-edition           -> FIRST_EDITION

                                    5 cabecalhos / 6 vinculos

IGUALDADE EXATA, SEM EXCECAO:
sem prefix, sem substring, sem LIKE, sem fuzzy, sem split de hifen.

    stamp | 1st-edition-error   NAO casa com   stamp | 1st-edition

Sao tokens DIFERENTES. A unica linha de BASEP com `1st-edition-error`
permanece na assinatura residual e NAO vira FIRST_EDITION.

Token sem mapping explicito nao e Printing automaticamente.

DETERMINISMO: nenhum id e literal. Tudo resolve por (game.code,
asset_source.code, trait.code).

IDEMPOTENCIA: os dois INSERTs usam ON CONFLICT DO NOTHING. A reexecucao
nao cria duplicata e nao altera assinatura — o guard de imutabilidade da
Query 2174 deixa passar reinsercao identica exatamente para isso.

ATENCAO — os cabecalhos nascem SEM traits_signature. O selo e gravado
pelo trigger deferido da Query 2174 no COMMIT desta transacao, depois
que os vinculos ja existem. Nenhum mapping parcial fica visivel.

Regras de Negócio:
- Somente Game POKEMON, somente Fonte TCGDEX.
- 5 mappings ACTIVE, 6 vinculos — exatos.
- Nenhum mapping nasce inativo.
- Nenhum supersedes_mapping_id na seed (nao ha predecessores).

Pré-requisitos:
- Query 2172, 2173, 2174 aplicadas.
- Query 2169 - Seed Card Printing Traits and Profiles (os 5 traits).
- Game POKEMON e asset_source TCGDEX existentes.
===============================================================================
*/

BEGIN;

-- ---------------------------------------------------------------------------
-- 5 CABECALHOS ACTIVE
-- ---------------------------------------------------------------------------
INSERT INTO public.card_printing_external_mapping
    (game_id, asset_source_id, raw_field, normalized_token, external_token)
SELECT g.id, s.id, v.raw_field, v.normalized_token, v.external_token
FROM public.game g
CROSS JOIN public.asset_source s
CROSS JOIN (VALUES
    ('subtype', 'SHADOWLESS',           'shadowless'),
    ('subtype', 'UNLIMITED',            'unlimited'),
    ('subtype', '1999-2000-COPYRIGHT',  '1999-2000-copyright'),
    ('subtype', 'SHADOWLESS-RED-CHEEK', 'shadowless-red-cheek'),
    ('stamp',   '1ST-EDITION',          '1st-edition')
) AS v(raw_field, normalized_token, external_token)
WHERE g.code = 'POKEMON'
  AND s.code = 'TCGDEX'
ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------------------
-- 6 VINCULOS DE COMPOSICAO
--
-- M1 shadowless            -> SHADOWLESS                      (1)
-- M2 unlimited             -> UNLIMITED                       (1)
-- M3 1999-2000-copyright   -> COPYRIGHT_1999_2000             (1)
-- M4 shadowless-red-cheek  -> SHADOWLESS, RED_CHEEK           (2)
-- M5 1st-edition           -> FIRST_EDITION                   (1)
--                                                     TOTAL = 6
-- ---------------------------------------------------------------------------
INSERT INTO public.card_printing_external_mapping_trait (mapping_id, trait_id, game_id)
SELECT m.id, t.id, g.id
FROM public.game g
JOIN public.asset_source s          ON s.code = 'TCGDEX'
JOIN public.card_printing_external_mapping m
     ON m.game_id = g.id AND m.asset_source_id = s.id AND m.is_active
JOIN public.card_printing_trait t   ON t.game_id = g.id
CROSS JOIN LATERAL (VALUES
    ('subtype', 'SHADOWLESS',           'SHADOWLESS'),
    ('subtype', 'UNLIMITED',            'UNLIMITED'),
    ('subtype', '1999-2000-COPYRIGHT',  'COPYRIGHT_1999_2000'),
    ('subtype', 'SHADOWLESS-RED-CHEEK', 'SHADOWLESS'),
    ('subtype', 'SHADOWLESS-RED-CHEEK', 'RED_CHEEK'),
    ('stamp',   '1ST-EDITION',          'FIRST_EDITION')
) AS v(raw_field, normalized_token, trait_code)
WHERE g.code = 'POKEMON'
  AND m.raw_field = v.raw_field
  AND m.normalized_token = v.normalized_token
  AND t.code = v.trait_code
ON CONFLICT (mapping_id, trait_id) DO NOTHING;

COMMIT;

-- ============================================================================
-- Resultado esperado (Game POKEMON, Fonte TCGDEX):
--   card_printing_external_mapping        =  5   (todos is_active = TRUE)
--   card_printing_external_mapping_trait  =  6
--   traits_signature NOT NULL             =  5   (selado no COMMIT)
--   shadowless-red-cheek                  =  1 cabecalho, assinatura com
--                                              SHADOWLESS + RED_CHEEK
--
-- Como validar:
--   Query 2824 - Validate Card Printing Routing, Secao S2 (SEED).
-- ============================================================================
