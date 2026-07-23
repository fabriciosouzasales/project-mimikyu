/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 970 - Validate Card Asset Type
Versão......: 1.2
Status......: CANÔNICA
Autor.......: Fabrício Sales / ChatGPT
Data........: 2026-07-23

Descrição resumida:
Valida a estrutura, integridade, RLS, trigger e carga canônica da entidade
public.card_asset_type.

Descrição:
Esta Query verifica: existência da tabela; colunas obrigatórias; chave
primária; chave estrangeira para Game; constraints únicas e de verificação;
índices; trigger de updated_at e sua função; RLS habilitado; duplicidade de
code/name/asset_order por Game; valores de negócio inválidos; referências
órfãs para Game; integridade de timestamps; presença e exatidão dos três
tipos canônicos do Game POKEMON.

Histórico de correção (Princípio da Fonte Canônica, STD-001 Seção 10):
- v1.0/v1.1: repetiam a mesma premissa incorreta de código de Game
  ('POKEMON_TCG') usada no Seed 870 nas versões correspondentes.
- v1.2 (esta versão): corrigida para usar o código real 'POKEMON', com
  mensagens de erro em português. Executada com sucesso.

Regras de Validação:
- Consultas de inconsistência devem retornar zero registros/exceções.
- O Game POKEMON deve possuir exatamente três tipos canônicos.
- Os três códigos esperados (CARD_FRONT, ARTWORK, CARD_BACK) devem estar
  presentes e aderentes aos valores canônicos.
- O trigger de updated_at deve existir.
- O Row Level Security deve estar habilitado.

Pré-requisitos:
- Query 170 - Create Card Asset Type Table.
- Query 171 - Create Card Asset Type Triggers.
- Query 870 - Seed Card Asset Type, versão 1.2.

===============================================================================

NOTA DE DOCUMENTAÇÃO: cabeçalho reformatado para o padrão STD-001. Lógica SQL
idêntica à versão 1.2 efetivamente executada — confirmada por Fabrício via o
próprio marcador de sucesso desta Query: "Query 970 concluída com sucesso:
card_asset_type está estruturalmente válida e com a carga canônica correta."
===============================================================================
*/

-- 01. Existência da tabela
DO $$
BEGIN
    IF to_regclass('public.card_asset_type') IS NULL THEN
        RAISE EXCEPTION
            'Falha na validação: a tabela public.card_asset_type não existe.';
    END IF;
END;
$$;

-- 02. Colunas obrigatórias
DO $$
DECLARE
    v_missing TEXT;
BEGIN
    SELECT string_agg(required.column_name, ', ' ORDER BY required.column_name)
      INTO v_missing
      FROM (
            VALUES
                ('id'), ('game_id'), ('code'), ('name'), ('description'),
                ('asset_order'), ('is_active'), ('created_at'), ('updated_at')
      ) AS required(column_name)
     WHERE NOT EXISTS (
            SELECT 1
              FROM information_schema.columns c
             WHERE c.table_schema = 'public'
               AND c.table_name = 'card_asset_type'
               AND c.column_name = required.column_name
     );

    IF v_missing IS NOT NULL THEN
        RAISE EXCEPTION
            'Falha na validação: colunas ausentes em card_asset_type: %', v_missing;
    END IF;
END;
$$;

-- 03. Chave primária
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
         WHERE conrelid = 'public.card_asset_type'::regclass
           AND contype = 'p'
    ) THEN
        RAISE EXCEPTION
            'Falha na validação: card_asset_type não possui chave primária.';
    END IF;
END;
$$;

-- 04. Chave estrangeira para Game
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
         WHERE conrelid = 'public.card_asset_type'::regclass
           AND conname = 'fk_card_asset_type_game'
           AND contype = 'f'
    ) THEN
        RAISE EXCEPTION
            'Falha na validação: a constraint fk_card_asset_type_game não existe.';
    END IF;
END;
$$;

-- 05. Constraints únicas obrigatórias
DO $$
DECLARE
    v_missing TEXT;
BEGIN
    SELECT string_agg(required.constraint_name, ', ' ORDER BY required.constraint_name)
      INTO v_missing
      FROM (
            VALUES
                ('uq_card_asset_type_game_code'),
                ('uq_card_asset_type_game_name'),
                ('uq_card_asset_type_game_order')
      ) AS required(constraint_name)
     WHERE NOT EXISTS (
            SELECT 1 FROM pg_constraint c
             WHERE c.conrelid = 'public.card_asset_type'::regclass
               AND c.conname = required.constraint_name
               AND c.contype = 'u'
     );

    IF v_missing IS NOT NULL THEN
        RAISE EXCEPTION
            'Falha na validação: constraints únicas ausentes: %', v_missing;
    END IF;
END;
$$;

-- 06. Constraints de verificação obrigatórias
DO $$
DECLARE
    v_missing TEXT;
BEGIN
    SELECT string_agg(required.constraint_name, ', ' ORDER BY required.constraint_name)
      INTO v_missing
      FROM (
            VALUES
                ('ck_card_asset_type_code_not_blank'),
                ('ck_card_asset_type_name_not_blank'),
                ('ck_card_asset_type_code_format'),
                ('ck_card_asset_type_asset_order_positive')
      ) AS required(constraint_name)
     WHERE NOT EXISTS (
            SELECT 1 FROM pg_constraint c
             WHERE c.conrelid = 'public.card_asset_type'::regclass
               AND c.conname = required.constraint_name
               AND c.contype = 'c'
     );

    IF v_missing IS NOT NULL THEN
        RAISE EXCEPTION
            'Falha na validação: constraints de verificação ausentes: %', v_missing;
    END IF;
END;
$$;

-- 07. Índices obrigatórios
DO $$
DECLARE
    v_missing TEXT;
BEGIN
    SELECT string_agg(required.index_name, ', ' ORDER BY required.index_name)
      INTO v_missing
      FROM (
            VALUES
                ('ix_card_asset_type_game_id'),
                ('ix_card_asset_type_is_active')
      ) AS required(index_name)
     WHERE NOT EXISTS (
            SELECT 1 FROM pg_indexes i
             WHERE i.schemaname = 'public'
               AND i.tablename = 'card_asset_type'
               AND i.indexname = required.index_name
     );

    IF v_missing IS NOT NULL THEN
        RAISE EXCEPTION
            'Falha na validação: índices ausentes: %', v_missing;
    END IF;
END;
$$;

-- 08. Trigger de atualização automática
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_trigger
         WHERE tgrelid = 'public.card_asset_type'::regclass
           AND tgname = 'trg_card_asset_type_set_updated_at'
           AND NOT tgisinternal
    ) THEN
        RAISE EXCEPTION
            'Falha na validação: o trigger trg_card_asset_type_set_updated_at não existe.';
    END IF;
END;
$$;

-- 09. Função utilizada pelo trigger
DO $$
BEGIN
    IF to_regprocedure('public.set_updated_at()') IS NULL THEN
        RAISE EXCEPTION
            'Falha na validação: a função public.set_updated_at() não existe.';
    END IF;
END;
$$;

-- 10. RLS habilitado
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
          FROM pg_class c
          JOIN pg_namespace n ON n.oid = c.relnamespace
         WHERE n.nspname = 'public'
           AND c.relname = 'card_asset_type'
           AND c.relrowsecurity = TRUE
    ) THEN
        RAISE EXCEPTION
            'Falha na validação: o RLS não está habilitado em card_asset_type.';
    END IF;
END;
$$;

-- 11. Duplicidade de código por Game
DO $$
DECLARE v_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_count
      FROM (
            SELECT game_id, code
              FROM public.card_asset_type
             GROUP BY game_id, code
            HAVING COUNT(*) > 1
      ) d;

    IF v_count > 0 THEN
        RAISE EXCEPTION
            'Falha na validação: foram encontradas % duplicidades de game_id + code.', v_count;
    END IF;
END;
$$;

-- 12. Duplicidade de nome por Game
DO $$
DECLARE v_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_count
      FROM (
            SELECT game_id, name
              FROM public.card_asset_type
             GROUP BY game_id, name
            HAVING COUNT(*) > 1
      ) d;

    IF v_count > 0 THEN
        RAISE EXCEPTION
            'Falha na validação: foram encontradas % duplicidades de game_id + name.', v_count;
    END IF;
END;
$$;

-- 13. Duplicidade de ordem por Game
DO $$
DECLARE v_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_count
      FROM (
            SELECT game_id, asset_order
              FROM public.card_asset_type
             GROUP BY game_id, asset_order
            HAVING COUNT(*) > 1
      ) d;

    IF v_count > 0 THEN
        RAISE EXCEPTION
            'Falha na validação: foram encontradas % duplicidades de game_id + asset_order.', v_count;
    END IF;
END;
$$;

-- 14. Valores de negócio inválidos
DO $$
DECLARE v_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_count
      FROM public.card_asset_type
     WHERE BTRIM(code) = ''
        OR BTRIM(name) = ''
        OR code !~ '^[A-Z][A-Z0-9_]*$'
        OR asset_order <= 0;

    IF v_count > 0 THEN
        RAISE EXCEPTION
            'Falha na validação: foram encontrados % registros com valores de negócio inválidos.', v_count;
    END IF;
END;
$$;

-- 15. Referências órfãs para Game
DO $$
DECLARE v_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_count
      FROM public.card_asset_type cat
      LEFT JOIN public.game g ON g.id = cat.game_id
     WHERE g.id IS NULL;

    IF v_count > 0 THEN
        RAISE EXCEPTION
            'Falha na validação: foram encontradas % referências órfãs para Game.', v_count;
    END IF;
END;
$$;

-- 16. Integridade dos timestamps
DO $$
DECLARE v_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_count
      FROM public.card_asset_type
     WHERE created_at IS NULL
        OR updated_at IS NULL
        OR updated_at < created_at;

    IF v_count > 0 THEN
        RAISE EXCEPTION
            'Falha na validação: foram encontrados % registros com timestamps inválidos.', v_count;
    END IF;
END;
$$;

-- 17. Carga canônica do Pokémon Trading Card Game
DO $$
DECLARE
    v_game_id UUID;
    v_missing TEXT;
BEGIN
    SELECT g.id
      INTO v_game_id
      FROM public.game g
     WHERE g.code = 'POKEMON';

    IF v_game_id IS NULL THEN
        RAISE EXCEPTION
            'Falha na validação: o Game com o código POKEMON não existe.';
    END IF;

    SELECT string_agg(required.code, ', ' ORDER BY required.asset_order)
      INTO v_missing
      FROM (
            VALUES
                (
                    'CARD_FRONT',
                    'Frente da Carta',
                    'Imagem completa da frente utilizada como representação visual canônica da Carta, independentemente de suas variações físicas.',
                    1,
                    TRUE
                ),
                (
                    'ARTWORK',
                    'Ilustração',
                    'Ilustração isolada ou recortada a partir da imagem da Carta, quando disponível.',
                    2,
                    TRUE
                ),
                (
                    'CARD_BACK',
                    'Verso da Carta',
                    'Imagem do verso da Carta, utilizada somente quando houver necessidade específica.',
                    3,
                    TRUE
                )
      ) AS required(code, name, description, asset_order, is_active)
     WHERE NOT EXISTS (
            SELECT 1
              FROM public.card_asset_type cat
             WHERE cat.game_id = v_game_id
               AND cat.code = required.code
               AND cat.name = required.name
               AND cat.description = required.description
               AND cat.asset_order = required.asset_order
               AND cat.is_active = required.is_active
     );

    IF v_missing IS NOT NULL THEN
        RAISE EXCEPTION
            'Falha na validação: tipos canônicos ausentes ou inconsistentes: %', v_missing;
    END IF;
END;
$$;

-- 18. Quantidade exata dos tipos canônicos
DO $$
DECLARE
    v_game_id UUID;
    v_count INTEGER;
BEGIN
    SELECT g.id
      INTO v_game_id
      FROM public.game g
     WHERE g.code = 'POKEMON';

    SELECT COUNT(*)
      INTO v_count
      FROM public.card_asset_type cat
     WHERE cat.game_id = v_game_id
       AND cat.code IN ('CARD_FRONT', 'ARTWORK', 'CARD_BACK');

    IF v_count <> 3 THEN
        RAISE EXCEPTION
            'Falha na validação: eram esperados 3 tipos canônicos, mas foram encontrados %.', v_count;
    END IF;
END;
$$;

-- 19. Listagem informativa
SELECT
    g.code AS game_code,
    cat.asset_order,
    cat.code,
    cat.name,
    cat.description,
    cat.is_active,
    cat.created_at,
    cat.updated_at
FROM public.card_asset_type cat
JOIN public.game g
  ON g.id = cat.game_id
ORDER BY
    g.code,
    cat.asset_order;

-- Marcador de conclusão
SELECT
    'Query 970 concluída com sucesso: card_asset_type está estruturalmente válida e com a carga canônica correta.'
    AS validation_result;
