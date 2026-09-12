/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 2169 - Seed Card Printing Traits and Profiles (POKEMON)
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO / LIVE
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-12
Mandato.....: CARD-VARIANTS — PRINTING-MODEL-STAGING-01 — GATE-A-01 (§1, §2, §16)

-------------------------------------------------------------------------------
EXECUÇÃO CONFIRMADA — 2026-09-12
-------------------------------------------------------------------------------
Executado via apply_migration no projeto Supabase qjfutqujxrbzgrtkpgkg.
Ordem de aplicacao: 2165 -> 2166 -> 2167 -> 2168 -> 2169 -> 2170 -> 2171.
Todas as sete aplicadas sem erro. Resultado: 5 traits / 6 profiles / 10 links.
Estado final validado integralmente pela Query 2823 v1.2:
    12 PASS / 0 FAIL / 0 NOT PROVEN, zero residuo.
O SQL executavel permanece INTOCADO desde a execucao. A unica alteracao
posterior a este arquivo foi de COMENTARIO (duas linhas que ainda diziam
"fingerprint", corrigidas em GATE-A-CORRECTION-01); nenhuma instrucao
executavel foi tocada, por isso a versao permanece 1.0.
-------------------------------------------------------------------------------

Descrição resumida:
Semeia o vocabulario RATIFICADO: 5 Print Traits, 6 Print Profiles e os 10
vinculos de composicao. Total 21 linhas. Nada alem disso.

Descrição:
Os 5 traits e os 6 profiles foram ratificados no mandato GATE-A-01. Esta
Query NAO cria routing, NAO cria mapping externo e NAO cria qualquer
conhecimento adicional. A decomposicao `shadowless-red-cheek` ->
SHADOWLESS + RED_CHEEK esta representada AQUI, e apenas aqui, pela
composicao dos Profiles P5 e P6. O routing (raw token -> trait) vem em
rodada propria.

IMPORTANTE — a ratificacao NAO autoriza parsing generico de tokens
compostos. Nenhuma regra desta Query divide strings por hifen. A
decomposicao e conhecimento declarativo explicito, escrito a mao, uma vez.

IDEMPOTENCIA: toda a seed usa ON CONFLICT DO NOTHING sobre as chaves
naturais (game_id, code) e sobre a PK da N:N. Reexecutar nao duplica e nao
levanta excecao — o guard de imutabilidade da Query 2168 deixa passar
reinsercoes identicas justamente por isso.

DETERMINISMO: nenhum id e literal. Tudo resolve por (game.code, code).

ORDEM DE DISPLAY:
Traits 1..5 seguem a ordem narrativa da tiragem (o que veio primeiro, e
depois as caracteristicas). Profiles 1..6 seguem a mesma logica.

Regras de Negócio:
- Somente Game POKEMON.
- 5 traits, 6 profiles, 10 vinculos — exatos.
- O trigger deferido da Query 2168 SELA os 6 Profiles no COMMIT, gravando
  traits_signature (UUID[] ordenado). Nenhum hash e calculado.
- Nenhum Profile fica sem trait.

Pré-requisitos:
- Query 2165, 2166, 2167, 2168 aplicadas.
- Game POKEMON existente.
===============================================================================
*/

BEGIN;

-- ---------------------------------------------------------------------------
-- 5 PRINT TRAITS
-- ---------------------------------------------------------------------------
INSERT INTO public.card_printing_trait
    (game_id, code, name, description, display_order)
SELECT g.id, v.code, v.name, v.description, v.display_order
FROM public.game g
CROSS JOIN (VALUES
    ('FIRST_EDITION', '1ª Edição', 1,
     'Tiragem inicial, identificada pelo selo "Edition 1" impresso na carta. Observada na fonte como stamp 1st-edition.'),
    ('SHADOWLESS',    'Sem Sombra', 2,
     'Impressão sem a sombra à direita da moldura da arte. Característica da segunda tiragem do Base Set, entre a 1ª Edição e a Ilimitada.'),
    ('UNLIMITED',     'Tiragem Ilimitada', 3,
     'Tiragem aberta, com sombra na moldura e sem selo de 1ª Edição. Declarada explicitamente pela fonte — nunca inferida pela ausência de outras características.'),
    ('COPYRIGHT_1999_2000', 'Copyright 1999–2000', 4,
     'Impressão tardia da tiragem Ilimitada, identificada pela linha de copyright com os dois anos.'),
    ('RED_CHEEK',     'Bochecha Vermelha', 5,
     'Característica de arte impressa: bochechas em vermelho em vez de amarelo. Observada em uma única Card do catálogo (BASE1 058 Pikachu), sempre em conjunto com Sem Sombra.')
) AS v(code, name, display_order, description)
WHERE g.code = 'POKEMON'
ON CONFLICT (game_id, code) DO NOTHING;

-- ---------------------------------------------------------------------------
-- 6 PRINT PROFILES
-- ---------------------------------------------------------------------------
INSERT INTO public.card_printing_profile
    (game_id, code, name, description, display_order)
SELECT g.id, v.code, v.name, v.description, v.display_order
FROM public.game g
CROSS JOIN (VALUES
    ('UNLIMITED', 'Tiragem Ilimitada', 1,
     'Perfil de impressão da tiragem aberta.'),
    ('SHADOWLESS', 'Sem Sombra', 2,
     'Perfil de impressão sem sombra na moldura, sem selo de 1ª Edição.'),
    ('SHADOWLESS_FIRST_EDITION', 'Sem Sombra · 1ª Edição', 3,
     'Perfil de impressão sem sombra na moldura e com selo de 1ª Edição.'),
    ('COPYRIGHT_1999_2000', 'Copyright 1999–2000', 4,
     'Perfil de impressão tardia da tiragem Ilimitada, com linha de copyright de dois anos.'),
    ('SHADOWLESS_RED_CHEEK', 'Sem Sombra · Bochecha Vermelha', 5,
     'Perfil de impressão sem sombra na moldura, com bochechas em vermelho.'),
    ('SHADOWLESS_RED_CHEEK_FIRST_EDITION', 'Sem Sombra · Bochecha Vermelha · 1ª Edição', 6,
     'Perfil de impressão sem sombra na moldura, com bochechas em vermelho e selo de 1ª Edição.')
) AS v(code, name, display_order, description)
WHERE g.code = 'POKEMON'
ON CONFLICT (game_id, code) DO NOTHING;

-- ---------------------------------------------------------------------------
-- 10 VINCULOS DE COMPOSICAO
--
-- P1 UNLIMITED                            -> UNLIMITED                     (1)
-- P2 SHADOWLESS                           -> SHADOWLESS                    (1)
-- P3 SHADOWLESS_FIRST_EDITION             -> SHADOWLESS, FIRST_EDITION     (2)
-- P4 COPYRIGHT_1999_2000                  -> COPYRIGHT_1999_2000           (1)
-- P5 SHADOWLESS_RED_CHEEK                 -> SHADOWLESS, RED_CHEEK         (2)
-- P6 SHADOWLESS_RED_CHEEK_FIRST_EDITION   -> SHADOWLESS, RED_CHEEK,
--                                            FIRST_EDITION                 (3)
--                                                                  TOTAL = 10
-- ---------------------------------------------------------------------------
INSERT INTO public.card_printing_profile_trait (profile_id, trait_id, game_id)
SELECT p.id, t.id, g.id
FROM public.game g
JOIN public.card_printing_profile p ON p.game_id = g.id
JOIN public.card_printing_trait   t ON t.game_id = g.id
CROSS JOIN LATERAL (VALUES
    ('UNLIMITED',                          'UNLIMITED'),
    ('SHADOWLESS',                         'SHADOWLESS'),
    ('SHADOWLESS_FIRST_EDITION',           'SHADOWLESS'),
    ('SHADOWLESS_FIRST_EDITION',           'FIRST_EDITION'),
    ('COPYRIGHT_1999_2000',                'COPYRIGHT_1999_2000'),
    ('SHADOWLESS_RED_CHEEK',               'SHADOWLESS'),
    ('SHADOWLESS_RED_CHEEK',               'RED_CHEEK'),
    ('SHADOWLESS_RED_CHEEK_FIRST_EDITION', 'SHADOWLESS'),
    ('SHADOWLESS_RED_CHEEK_FIRST_EDITION', 'RED_CHEEK'),
    ('SHADOWLESS_RED_CHEEK_FIRST_EDITION', 'FIRST_EDITION')
) AS v(profile_code, trait_code)
WHERE g.code = 'POKEMON'
  AND p.code = v.profile_code
  AND t.code = v.trait_code
ON CONFLICT (profile_id, trait_id) DO NOTHING;

COMMIT;

-- ============================================================================
-- Resultado esperado (Game POKEMON):
--   card_printing_trait          =  5
--   card_printing_profile        =  6
--   card_printing_profile_trait  = 10
--   traits_signature   NOT NULL  =  6   (selado pelo trigger no COMMIT)
--
-- Como validar:
--   Query 2823 - Validate Card Printing Model, Secao 2 (SEED).
-- ============================================================================
