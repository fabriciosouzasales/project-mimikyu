/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 950 - Validate Card Variant Type
Versão......: 1.3
Status......: CANÔNICA
Autor.......: Fabrício Sales / ChatGPT
Data........: 2026-07-18

Descrição resumida:
Valida a estrutura, a integridade e o seed canônico da tabela
public.card_variant_type para o Game POKEMON.

Catálogo canônico esperado:
 1. STANDARD
 2. HOLO
 3. COSMOS_HOLO
 4. REVERSE_HOLO
 5. ENERGY_REVERSE
 6. POKE_BALL_REVERSE
 7. LOVE_BALL_REVERSE
 8. FRIEND_BALL_REVERSE
 9. QUICK_BALL_REVERSE
10. DUSK_BALL_REVERSE
11. ROCKET_REVERSE
12. MASTER_BALL_REVERSE
13. PROMO_STAMPED

Alterações da versão 1.3:
- Inclusão da validação de COSMOS_HOLO.
- Atualização da quantidade canônica esperada para 13 tipos.
- Atualização da sequência de display_order para 1 a 13.
- Atualização das verificações de tipos ausentes, divergentes e adicionais.
- Reescrita como bloco executável (`DO $$`) com `RAISE EXCEPTION` e rollback
  automático em qualquer inconsistência, substituindo o padrão anterior de
  SELECTs apenas informativos.

Regras de Validação:
- O Game POKEMON deve existir.
- Devem existir exatamente 13 tipos canônicos para POKEMON.
- code, name, description e display_order devem aderir ao catálogo.
- Não devem existir tipos adicionais fora do catálogo canônico.
- display_order deve formar a sequência de 1 a 13.
- Não devem existir códigos ou display_order duplicados no mesmo Game.
- Não devem existir valores obrigatórios inválidos.
- O trigger de updated_at deve existir e estar habilitado.
- Row Level Security deve estar habilitado.
- Qualquer divergência provoca falha explícita.

Pré-requisitos:
- Query 150 - Create Card Variant Type Table.
- Query 151 - Create Card Variant Type Triggers.
- Query 850 - Seed Card Variant Type, versão 1.3.

===============================================================================

NOTA DE DOCUMENTAÇÃO (Princípio da Fonte Canônica, STD-001 Seção 10): esta
versão substitui integralmente a v1.2 (12 tipos), mantida apenas no histórico
de revisões dos documentos de domínio. Executada com sucesso logo após a
Query 850 v1.3, confirmada por Fabrício.
===============================================================================
*/

BEGIN;

DO $$
DECLARE
    v_game_id UUID;

    v_registered_total INTEGER;
    v_missing_total INTEGER;
    v_divergent_total INTEGER;
    v_additional_total INTEGER;
    v_duplicate_code_total INTEGER;
    v_duplicate_order_total INTEGER;
    v_invalid_code_total INTEGER;
    v_invalid_name_total INTEGER;
    v_invalid_description_total INTEGER;
    v_invalid_order_total INTEGER;
    v_missing_order_total INTEGER;
    v_orphan_total INTEGER;
    v_invalid_timestamp_total INTEGER;
    v_trigger_total INTEGER;
    v_rls_enabled BOOLEAN;

    v_expected JSONB := $catalog$
[
  {
    "code": "STANDARD",
    "name": "Padrão",
    "description": "Versão principal da Card, conforme sua impressão editorial padrão.",
    "display_order": 1
  },
  {
    "code": "HOLO",
    "name": "Holográfica",
    "description": "Versão com acabamento holográfico.",
    "display_order": 2
  },
  {
    "code": "COSMOS_HOLO",
    "name": "Holográfica Cosmos",
    "description": "Versão com acabamento holográfico no padrão Cosmos.",
    "display_order": 3
  },
  {
    "code": "REVERSE_HOLO",
    "name": "Holográfica Reversa",
    "description": "Versão com acabamento holográfico reverso genérico.",
    "display_order": 4
  },
  {
    "code": "ENERGY_REVERSE",
    "name": "Energia Reversa",
    "description": "Versão holográfica reversa com padrão de Energia.",
    "display_order": 5
  },
  {
    "code": "POKE_BALL_REVERSE",
    "name": "Poké Bola Reversa",
    "description": "Versão holográfica reversa com padrão de Poké Bola.",
    "display_order": 6
  },
  {
    "code": "LOVE_BALL_REVERSE",
    "name": "Love Ball Reversa",
    "description": "Versão holográfica reversa com padrão de Love Ball.",
    "display_order": 7
  },
  {
    "code": "FRIEND_BALL_REVERSE",
    "name": "Friend Ball Reversa",
    "description": "Versão holográfica reversa com padrão de Friend Ball.",
    "display_order": 8
  },
  {
    "code": "QUICK_BALL_REVERSE",
    "name": "Quick Ball Reversa",
    "description": "Versão holográfica reversa com padrão de Quick Ball.",
    "display_order": 9
  },
  {
    "code": "DUSK_BALL_REVERSE",
    "name": "Dusk Ball Reversa",
    "description": "Versão holográfica reversa com padrão de Dusk Ball.",
    "display_order": 10
  },
  {
    "code": "ROCKET_REVERSE",
    "name": "Equipe Rocket Reversa",
    "description": "Versão holográfica reversa com padrão ou símbolo da Equipe Rocket.",
    "display_order": 11
  },
  {
    "code": "MASTER_BALL_REVERSE",
    "name": "Master Ball Reversa",
    "description": "Versão holográfica reversa com padrão de Master Ball.",
    "display_order": 12
  },
  {
    "code": "PROMO_STAMPED",
    "name": "Promocional Estampada",
    "description": "Versão que possui uma marca ou estampa promocional oficialmente aplicada.",
    "display_order": 13
  }
]
$catalog$::JSONB;
BEGIN
    /*
    ===========================================================================
    1. Validar Game
    ===========================================================================
    */

    SELECT g.id
      INTO v_game_id
      FROM public.game AS g
     WHERE g.code = 'POKEMON';

    IF v_game_id IS NULL THEN
        RAISE EXCEPTION
            'Falha na Query 950: o Game POKEMON não está cadastrado.';
    END IF;

    /*
    ===========================================================================
    2. Validar quantidade total
    ===========================================================================
    */

    SELECT COUNT(*)
      INTO v_registered_total
      FROM public.card_variant_type AS cvt
     WHERE cvt.game_id = v_game_id;

    IF v_registered_total <> 13 THEN
        RAISE EXCEPTION
            'Falha na Query 950: esperados exatamente 13 tipos para POKEMON, encontrados %.',
            v_registered_total;
    END IF;

    /*
    ===========================================================================
    3. Validar tipos ausentes
    ===========================================================================
    */

    SELECT COUNT(*)
      INTO v_missing_total
      FROM jsonb_array_elements(v_expected) AS item
     WHERE NOT EXISTS (
        SELECT 1
          FROM public.card_variant_type AS cvt
         WHERE cvt.game_id = v_game_id
           AND cvt.code = item->>'code'
     );

    IF v_missing_total <> 0 THEN
        RAISE EXCEPTION
            'Falha na Query 950: existem % tipos canônicos ausentes.',
            v_missing_total;
    END IF;

    /*
    ===========================================================================
    4. Validar valores canônicos
    ===========================================================================
    */

    SELECT COUNT(*)
      INTO v_divergent_total
      FROM jsonb_array_elements(v_expected) AS item
      INNER JOIN public.card_variant_type AS cvt
          ON cvt.game_id = v_game_id
         AND cvt.code = item->>'code'
     WHERE cvt.name <> item->>'name'
        OR cvt.description IS DISTINCT FROM item->>'description'
        OR cvt.display_order <> (item->>'display_order')::INTEGER;

    IF v_divergent_total <> 0 THEN
        RAISE EXCEPTION
            'Falha na Query 950: existem % tipos com valores divergentes do catálogo canônico.',
            v_divergent_total;
    END IF;

    /*
    ===========================================================================
    5. Validar tipos adicionais
    ===========================================================================
    */

    SELECT COUNT(*)
      INTO v_additional_total
      FROM public.card_variant_type AS cvt
     WHERE cvt.game_id = v_game_id
       AND NOT EXISTS (
            SELECT 1
              FROM jsonb_array_elements(v_expected) AS item
             WHERE item->>'code' = cvt.code
       );

    IF v_additional_total <> 0 THEN
        RAISE EXCEPTION
            'Falha na Query 950: existem % tipos adicionais fora do catálogo canônico.',
            v_additional_total;
    END IF;

    /*
    ===========================================================================
    6. Validar duplicidades
    ===========================================================================
    */

    SELECT COUNT(*)
      INTO v_duplicate_code_total
      FROM (
            SELECT cvt.code
              FROM public.card_variant_type AS cvt
             WHERE cvt.game_id = v_game_id
             GROUP BY cvt.code
            HAVING COUNT(*) > 1
      ) AS duplicate_code;

    IF v_duplicate_code_total <> 0 THEN
        RAISE EXCEPTION
            'Falha na Query 950: existem % códigos duplicados para POKEMON.',
            v_duplicate_code_total;
    END IF;

    SELECT COUNT(*)
      INTO v_duplicate_order_total
      FROM (
            SELECT cvt.display_order
              FROM public.card_variant_type AS cvt
             WHERE cvt.game_id = v_game_id
             GROUP BY cvt.display_order
            HAVING COUNT(*) > 1
      ) AS duplicate_order;

    IF v_duplicate_order_total <> 0 THEN
        RAISE EXCEPTION
            'Falha na Query 950: existem % valores de display_order duplicados para POKEMON.',
            v_duplicate_order_total;
    END IF;

    /*
    ===========================================================================
    7. Validar campos obrigatórios
    ===========================================================================
    */

    SELECT COUNT(*)
      INTO v_invalid_code_total
      FROM public.card_variant_type AS cvt
     WHERE cvt.game_id = v_game_id
       AND (
            cvt.code IS NULL
         OR BTRIM(cvt.code) = ''
         OR cvt.code !~ '^[A-Z][A-Z0-9_]*$'
       );

    IF v_invalid_code_total <> 0 THEN
        RAISE EXCEPTION
            'Falha na Query 950: existem % códigos inválidos.',
            v_invalid_code_total;
    END IF;

    SELECT COUNT(*)
      INTO v_invalid_name_total
      FROM public.card_variant_type AS cvt
     WHERE cvt.game_id = v_game_id
       AND (
            cvt.name IS NULL
         OR BTRIM(cvt.name) = ''
       );

    IF v_invalid_name_total <> 0 THEN
        RAISE EXCEPTION
            'Falha na Query 950: existem % nomes inválidos.',
            v_invalid_name_total;
    END IF;

    SELECT COUNT(*)
      INTO v_invalid_description_total
      FROM public.card_variant_type AS cvt
     WHERE cvt.game_id = v_game_id
       AND (
            cvt.description IS NULL
         OR BTRIM(cvt.description) = ''
       );

    IF v_invalid_description_total <> 0 THEN
        RAISE EXCEPTION
            'Falha na Query 950: existem % descrições inválidas.',
            v_invalid_description_total;
    END IF;

    SELECT COUNT(*)
      INTO v_invalid_order_total
      FROM public.card_variant_type AS cvt
     WHERE cvt.game_id = v_game_id
       AND cvt.display_order <= 0;

    IF v_invalid_order_total <> 0 THEN
        RAISE EXCEPTION
            'Falha na Query 950: existem % valores de display_order inválidos.',
            v_invalid_order_total;
    END IF;

    /*
    ===========================================================================
    8. Validar sequência de display_order
    ===========================================================================
    */

    SELECT COUNT(*)
      INTO v_missing_order_total
      FROM generate_series(1, 13) AS expected_order(display_order)
     WHERE NOT EXISTS (
        SELECT 1
          FROM public.card_variant_type AS cvt
         WHERE cvt.game_id = v_game_id
           AND cvt.display_order = expected_order.display_order
     );

    IF v_missing_order_total <> 0 THEN
        RAISE EXCEPTION
            'Falha na Query 950: existem % posições ausentes na sequência de display_order de 1 a 13.',
            v_missing_order_total;
    END IF;

    /*
    ===========================================================================
    9. Validar integridade referencial e timestamps
    ===========================================================================
    */

    SELECT COUNT(*)
      INTO v_orphan_total
      FROM public.card_variant_type AS cvt
      LEFT JOIN public.game AS g
          ON g.id = cvt.game_id
     WHERE g.id IS NULL;

    IF v_orphan_total <> 0 THEN
        RAISE EXCEPTION
            'Falha na Query 950: existem % registros de card_variant_type sem Game válido.',
            v_orphan_total;
    END IF;

    SELECT COUNT(*)
      INTO v_invalid_timestamp_total
      FROM public.card_variant_type AS cvt
     WHERE cvt.game_id = v_game_id
       AND (
            cvt.created_at IS NULL
         OR cvt.updated_at IS NULL
         OR cvt.updated_at < cvt.created_at
       );

    IF v_invalid_timestamp_total <> 0 THEN
        RAISE EXCEPTION
            'Falha na Query 950: existem % registros com timestamps inválidos.',
            v_invalid_timestamp_total;
    END IF;

    /*
    ===========================================================================
    10. Validar trigger de updated_at
    ===========================================================================
    */

    SELECT COUNT(*)
      INTO v_trigger_total
      FROM pg_catalog.pg_trigger AS t
      INNER JOIN pg_catalog.pg_class AS c
          ON c.oid = t.tgrelid
      INNER JOIN pg_catalog.pg_namespace AS n
          ON n.oid = c.relnamespace
     WHERE n.nspname = 'public'
       AND c.relname = 'card_variant_type'
       AND t.tgname = 'trg_card_variant_type_set_updated_at'
       AND t.tgenabled <> 'D'
       AND NOT t.tgisinternal;

    IF v_trigger_total <> 1 THEN
        RAISE EXCEPTION
            'Falha na Query 950: o trigger trg_card_variant_type_set_updated_at não existe, está duplicado ou está desabilitado.';
    END IF;

    /*
    ===========================================================================
    11. Validar Row Level Security
    ===========================================================================
    */

    SELECT c.relrowsecurity
      INTO v_rls_enabled
      FROM pg_catalog.pg_class AS c
      INNER JOIN pg_catalog.pg_namespace AS n
          ON n.oid = c.relnamespace
     WHERE n.nspname = 'public'
       AND c.relname = 'card_variant_type'
       AND c.relkind = 'r';

    IF v_rls_enabled IS DISTINCT FROM TRUE THEN
        RAISE EXCEPTION
            'Falha na Query 950: Row Level Security não está habilitado em public.card_variant_type.';
    END IF;

    RAISE NOTICE
        'Query 950 concluída: card_variant_type validada com 13 tipos canônicos para POKEMON.';
END;
$$;

-- Resultado final para conferência no editor SQL.
SELECT
    cvt.code,
    cvt.name,
    cvt.description,
    cvt.display_order
FROM public.card_variant_type AS cvt
INNER JOIN public.game AS g
    ON g.id = cvt.game_id
WHERE g.code = 'POKEMON'
ORDER BY cvt.display_order, cvt.code;

COMMIT;
