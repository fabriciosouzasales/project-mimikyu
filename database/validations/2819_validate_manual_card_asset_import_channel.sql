/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2819 - Validate Manual Card Asset Import Channel
Versão......: 1.0
Status......: VALIDAÇÃO — CONFIRMADO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-08

Descrição...:
Validação consolidada do backend SQL do canal de importação manual de
imagens via UI (ADR-026, emenda "Segundo ponto de entrada via UI") —
mesmo espírito agregador da Query 2818 (Ciclo 2 de ADR-024): confirma
num único lugar as quatro Queries deste ciclo (2119–2122), já
validadas individualmente uma a uma durante a implementação.

Regras de Negócio:
- Somente leitura — nenhuma linha é alterada.
- Cobre: as 2 políticas de storage.objects (2119); assinatura e
  SECURITY DEFINER de admin_persist_manual_card_asset (2120) e
  admin_log_manual_card_asset_import_batch (2122); presença de
  CARD_ASSET_MANUAL_IMPORT_COMPLETED nas duas CHECK constraints de
  catalog_admin_action_log (2121).

Pré-requisitos:
- Queries 2119, 2120, 2121, 2122 (todas já CONFIRMADO EXECUTADO).
================================================================
*/

-- 1. Políticas em storage.objects (2119) — esperado 2 linhas.
SELECT '1. storage.objects policies' AS item, policyname, cmd, qual, with_check
FROM pg_policies
WHERE schemaname = 'storage'
  AND tablename = 'objects'
  AND policyname LIKE 'card_front_admin_%'
ORDER BY policyname;

-- 2. admin_persist_manual_card_asset (2120) — esperado 1 linha, SECURITY DEFINER.
SELECT '2. admin_persist_manual_card_asset' AS item,
       p.proname,
       p.prosecdef AS is_security_definer,
       pg_get_function_arguments(p.oid) AS argumentos,
       pg_get_function_result(p.oid) AS retorno
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'admin_persist_manual_card_asset';

-- 3. admin_log_manual_card_asset_import_batch (2122) — esperado 1 linha, SECURITY DEFINER.
SELECT '3. admin_log_manual_card_asset_import_batch' AS item,
       p.proname,
       p.prosecdef AS is_security_definer,
       pg_get_function_arguments(p.oid) AS argumentos,
       pg_get_function_result(p.oid) AS retorno
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'admin_log_manual_card_asset_import_batch';

-- 4. CHECK constraints de catalog_admin_action_log (2121) — esperado 2 linhas,
--    CARD_ASSET_MANUAL_IMPORT_COMPLETED presente nas duas definições.
SELECT '4. catalog_admin_action_log CHECKs' AS item, conname, pg_get_constraintdef(oid) AS definicao
FROM pg_constraint
WHERE conrelid = 'public.catalog_admin_action_log'::regclass
  AND conname IN (
      'ck_catalog_admin_action_log_action_valid',
      'ck_catalog_admin_action_log_action_entity_match'
  );

-- ================================================================
-- Resultado esperado, por item:
-- 1. Duas linhas: card_front_admin_delete/insert, ambas com
--    qual/with_check = ((bucket_id = 'card-front'::text) AND
--    is_admin()).
-- 2. Uma linha: is_security_definer = true, 8 argumentos
--    (p_card_id..p_checksum_sha256), retorno
--    "TABLE(action text, previous_storage_path text)".
-- 3. Uma linha: is_security_definer = true, 8 argumentos
--    (p_card_set_id..p_failures), retorno "uuid".
-- 4. Duas linhas: CARD_ASSET_MANUAL_IMPORT_COMPLETED presente na
--    action_valid e associada a entity_type = 'CARD_SET' na
--    action_entity_match.
-- ================================================================
--
-- CONFIRMADO EXECUTADO E VALIDADO (2026-08-08): os 4 itens conferem
-- exatamente com o esperado (rodados em execuções separadas, já que
-- o editor do Supabase só exibe/exporta o resultado da última
-- instrução quando várias rodam juntas).
-- ================================================================
