/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 980 - Validate Card Asset Structure
Versão......: 1.1
Status......: CANÔNICA
Autor.......: Fabrício Sales / ChatGPT
Data........: 2026-07-18

Descrição resumida:
Valida a estrutura técnica e as regras de integridade da tabela card_asset.

Descrição:
Esta versão valida somente a estrutura da entidade antes da construção e da
execução do Seed 880.

Após o Seed 880, esta Query poderá ser evoluída para validar:
- cobertura de CARD_FRONT por Card;
- existência do ativo principal esperado;
- quantidade de ativos por Card Set;
- aderência das fontes e localizações cadastradas.

Regras de leitura:
- Consultas de inconsistência devem retornar zero registros.
- Consultas de objetos esperados devem retornar os objetos indicados.
- Antes do Seed 880, a tabela pode estar vazia.

Pré-requisitos:
- Query 180 - Create Card Asset Table, versão 1.1.
- Query 181 - Create Card Asset Triggers, versão 1.1.
- Query 170 - Create Card Asset Type Table.
- Query 870 - Seed Card Asset Type.

===============================================================================

NOTA DE DOCUMENTAÇÃO: diferente de 970 (Validate Card Asset Type), esta Query
não usa blocos DO com RAISE EXCEPTION — é inteiramente composta por SELECTs
informativos, com o resultado esperado documentado em comentário acima de
cada bloco. Isso significa que a execução sem erro (relatada por Fabrício
como "Executadas com sucesso") não garante, por si só, que os resultados
retornados batem com os valores esperados nos comentários — a comparação
é manual. Em particular, o bloco 2 espera 19 colunas e o bloco 3 espera
1 PK + 2 FK + 1 UNIQUE + 13 CHECK; como a Query 180 usa CREATE TABLE
IF NOT EXISTS contra uma tabela que já existia fisicamente (ver nota em
180_create_card_asset_table.sql), esses números podem não corresponder à
estrutura real hoje (confirmada anteriormente com 20 colunas, incluindo
storage_bucket_id e language_id, sem storage_provider). Sinalizado para
Fabrício confirmar o resultado real desses blocos, não presumido.
===============================================================================
*/

-- ============================================================================
-- 1. Confirmar existência da tabela
-- Resultado esperado: 1 registro
-- ============================================================================

SELECT
    table_schema,
    table_name
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name = 'card_asset';


-- ============================================================================
-- 2. Confirmar estrutura das colunas
-- Resultado esperado: 19 registros
-- ============================================================================

SELECT
    ordinal_position,
    column_name,
    data_type,
    is_nullable,
    column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'card_asset'
ORDER BY ordinal_position;


-- ============================================================================
-- 3. Confirmar constraints da tabela
-- Resultado esperado:
-- - 1 PRIMARY KEY
-- - 2 FOREIGN KEY
-- - 1 UNIQUE
-- - 13 CHECK
-- ============================================================================

SELECT
    tc.constraint_name,
    tc.constraint_type
FROM information_schema.table_constraints AS tc
WHERE tc.table_schema = 'public'
  AND tc.table_name = 'card_asset'
ORDER BY
    tc.constraint_type,
    tc.constraint_name;


-- ============================================================================
-- 4. Confirmar índices
-- Resultado esperado:
-- - PK
-- - unique da constraint Card + Asset Type + Order
-- - 3 índices únicos parciais
-- - 4 índices auxiliares
-- ============================================================================

SELECT
    schemaname,
    tablename,
    indexname,
    indexdef
FROM pg_catalog.pg_indexes
WHERE schemaname = 'public'
  AND tablename = 'card_asset'
ORDER BY indexname;


-- ============================================================================
-- 5. Confirmar índice único parcial do ativo principal
-- Resultado esperado: 1 registro
-- ============================================================================

SELECT
    schemaname,
    tablename,
    indexname,
    indexdef
FROM pg_catalog.pg_indexes
WHERE schemaname = 'public'
  AND tablename = 'card_asset'
  AND indexname = 'uq_card_asset_one_primary_per_card_type'
  AND indexdef ILIKE '%WHERE (is_primary = true)%';


-- ============================================================================
-- 6. Confirmar índices únicos parciais de localização
-- Resultado esperado: 2 registros
-- ============================================================================

SELECT
    schemaname,
    tablename,
    indexname,
    indexdef
FROM pg_catalog.pg_indexes
WHERE schemaname = 'public'
  AND tablename = 'card_asset'
  AND indexname IN (
      'uq_card_asset_card_type_storage_path',
      'uq_card_asset_card_type_external_url'
  )
ORDER BY indexname;


-- ============================================================================
-- 7. Confirmar triggers
-- Resultado esperado: 2 registros
-- ============================================================================

SELECT
    event_object_schema,
    event_object_table,
    trigger_name,
    action_timing,
    event_manipulation
FROM information_schema.triggers
WHERE event_object_schema = 'public'
  AND event_object_table = 'card_asset'
ORDER BY
    trigger_name,
    event_manipulation;


-- ============================================================================
-- 8. Confirmar funções utilizadas pelos triggers
-- Resultado esperado: 2 registros
-- ============================================================================

SELECT
    n.nspname AS function_schema,
    p.proname AS function_name
FROM pg_catalog.pg_proc AS p
INNER JOIN pg_catalog.pg_namespace AS n
    ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN (
      'set_updated_at',
      'validate_card_asset_game_consistency'
  )
ORDER BY p.proname;


-- ============================================================================
-- 9. Confirmar Row Level Security
-- Resultado esperado:
-- rowsecurity = true
-- ============================================================================

SELECT
    schemaname,
    tablename,
    rowsecurity
FROM pg_catalog.pg_tables
WHERE schemaname = 'public'
  AND tablename = 'card_asset';


-- ============================================================================
-- 10. Verificar asset_order duplicado dentro de Card + Card Asset Type
-- Resultado esperado: nenhum registro
-- ============================================================================

SELECT
    card_id,
    asset_type_id,
    asset_order,
    COUNT(*) AS duplicate_count
FROM public.card_asset
GROUP BY
    card_id,
    asset_type_id,
    asset_order
HAVING COUNT(*) > 1;


-- ============================================================================
-- 11. Verificar mais de um ativo principal por Card + Card Asset Type
-- Resultado esperado: nenhum registro
-- ============================================================================

SELECT
    card_id,
    asset_type_id,
    COUNT(*) AS primary_asset_count
FROM public.card_asset
WHERE is_primary = TRUE
GROUP BY
    card_id,
    asset_type_id
HAVING COUNT(*) > 1;


-- ============================================================================
-- 12. Verificar localização ausente
-- Resultado esperado: nenhum registro
-- ============================================================================

SELECT
    id,
    card_id,
    asset_type_id,
    storage_path,
    external_url
FROM public.card_asset
WHERE NULLIF(BTRIM(storage_path), '') IS NULL
  AND NULLIF(BTRIM(external_url), '') IS NULL;


-- ============================================================================
-- 13. Verificar campos opcionais preenchidos somente com espaços
-- Resultado esperado: nenhum registro
-- ============================================================================

SELECT
    id,
    card_id,
    asset_type_id,
    source_code,
    source_reference,
    storage_provider,
    storage_path,
    external_url,
    mime_type,
    file_extension
FROM public.card_asset
WHERE (source_code IS NOT NULL AND BTRIM(source_code) = '')
   OR (source_reference IS NOT NULL AND BTRIM(source_reference) = '')
   OR (storage_provider IS NOT NULL AND BTRIM(storage_provider) = '')
   OR (storage_path IS NOT NULL AND BTRIM(storage_path) = '')
   OR (external_url IS NOT NULL AND BTRIM(external_url) = '')
   OR (mime_type IS NOT NULL AND BTRIM(mime_type) = '')
   OR (file_extension IS NOT NULL AND BTRIM(file_extension) = '');


-- ============================================================================
-- 14. Verificar asset_order inválido
-- Resultado esperado: nenhum registro
-- ============================================================================

SELECT
    id,
    card_id,
    asset_type_id,
    asset_order
FROM public.card_asset
WHERE asset_order <= 0;


-- ============================================================================
-- 15. Verificar valores técnicos inválidos
-- Resultado esperado: nenhum registro
-- ============================================================================

SELECT
    id,
    file_size_bytes,
    width_pixels,
    height_pixels,
    checksum_sha256
FROM public.card_asset
WHERE (file_size_bytes IS NOT NULL AND file_size_bytes < 0)
   OR (width_pixels IS NOT NULL AND width_pixels <= 0)
   OR (height_pixels IS NOT NULL AND height_pixels <= 0)
   OR (
        checksum_sha256 IS NOT NULL
        AND checksum_sha256 !~ '^[A-Fa-f0-9]{64}$'
   );


-- ============================================================================
-- 16. Verificar referências inválidas para Card
-- Resultado esperado: nenhum registro
-- ============================================================================

SELECT
    ca.id,
    ca.card_id
FROM public.card_asset AS ca
LEFT JOIN public.card AS c
    ON c.id = ca.card_id
WHERE c.id IS NULL;


-- ============================================================================
-- 17. Verificar referências inválidas para Card Asset Type
-- Resultado esperado: nenhum registro
-- ============================================================================

SELECT
    ca.id,
    ca.asset_type_id
FROM public.card_asset AS ca
LEFT JOIN public.card_asset_type AS cat
    ON cat.id = ca.asset_type_id
WHERE cat.id IS NULL;


-- ============================================================================
-- 18. Verificar inconsistências de Game
-- Resultado esperado: nenhum registro
-- ============================================================================

SELECT
    ca.id AS card_asset_id,
    c.id AS card_id,
    cs.code AS card_set_code,
    e.game_id AS card_game_id,
    cat.code AS asset_type_code,
    cat.game_id AS asset_type_game_id
FROM public.card_asset AS ca
INNER JOIN public.card AS c
    ON c.id = ca.card_id
INNER JOIN public.card_set AS cs
    ON cs.id = c.card_set_id
INNER JOIN public.expansion AS e
    ON e.id = cs.expansion_id
INNER JOIN public.card_asset_type AS cat
    ON cat.id = ca.asset_type_id
WHERE e.game_id <> cat.game_id;


-- ============================================================================
-- 19. Verificar timestamps obrigatórios
-- Resultado esperado: nenhum registro
-- ============================================================================

SELECT
    id,
    created_at,
    updated_at
FROM public.card_asset
WHERE created_at IS NULL
   OR updated_at IS NULL;


-- ============================================================================
-- 20. Verificar updated_at anterior a created_at
-- Resultado esperado: nenhum registro
-- ============================================================================

SELECT
    id,
    created_at,
    updated_at
FROM public.card_asset
WHERE updated_at < created_at;


-- ============================================================================
-- 21. Visão estrutural dos registros existentes
-- Antes do Seed 880, o resultado pode estar vazio.
-- ============================================================================

SELECT
    g.code AS game_code,
    cs.code AS card_set_code,
    c.collector_number,
    c.name AS card_name,
    cat.code AS asset_type_code,
    ca.source_code,
    ca.source_reference,
    ca.storage_provider,
    ca.storage_path,
    ca.external_url,
    ca.mime_type,
    ca.file_extension,
    ca.file_size_bytes,
    ca.width_pixels,
    ca.height_pixels,
    ca.checksum_sha256,
    ca.is_primary,
    ca.asset_order,
    ca.is_active,
    ca.created_at,
    ca.updated_at
FROM public.card_asset AS ca
INNER JOIN public.card AS c
    ON c.id = ca.card_id
INNER JOIN public.card_set AS cs
    ON cs.id = c.card_set_id
INNER JOIN public.expansion AS e
    ON e.id = cs.expansion_id
INNER JOIN public.game AS g
    ON g.id = e.game_id
INNER JOIN public.card_asset_type AS cat
    ON cat.id = ca.asset_type_id
ORDER BY
    g.code,
    e.release_order,
    cs.release_order,
    c.collector_order,
    cat.asset_order,
    ca.asset_order;
