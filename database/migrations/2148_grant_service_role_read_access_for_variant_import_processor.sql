/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2148 - Grant Service Role Read Access for Variant Import Processor
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-15

Descrição...:
Corrige um gap real de GRANT, descoberto no teste funcional do
Incremento 4 (UI de Importar Variantes): a Edge Function
import-card-variants autentica como service_role, mas
catalog_variant_import_job (Query 2136) e catalog_variant_import_row
(Query 2138) só concederam INSERT/UPDATE a service_role, nunca
SELECT — e card_variant (Query 160) nunca concedeu nada a
service_role além de REFERENCES/TRIGGER/TRUNCATE (herdados do
default ACL do schema, ver Query 2147). RLS bypass de service_role
não substitui o GRANT de nível de tabela — mesmo gap já corrigido
pela Query 2090 para o processador de Importar Cartas ("mesmo gap já
visto quatro vezes neste projeto"); esta é a quinta ocorrência,
desta vez no processador de Importar Variantes.

Sintoma real observado (teste funcional do Incremento 4, reportado
por Fabrício): clique em Analisar retornou
"VARIANT_JOB_CREATE_FAILED: permission denied for table
catalog_variant_import_job". Causa raiz:
createVariantJobProcessing() (services/database.ts) faz
`.insert({...}).select("id").single()` — o `.select()` encadeado
após um `.insert()` faz o PostgREST emitir `INSERT ... RETURNING
id`, e RETURNING exige SELECT na tabela, não só INSERT. Auditoria
completa de information_schema.role_table_grants confirmou um
segundo gap no mesmo caminho de execução, que só não apareceu ainda
porque o primeiro erro interrompe antes: card_variant também sem
SELECT para service_role (listExistingCardVariantsMap() faz
`.from("card_variant").select(...)`, mesmo problema, seria o próximo
erro). catalog_variant_import_row incluída preventivamente na mesma
auditoria (mesma ausência de SELECT, ainda não exercida hoje —
insertVariantImportRows() só faz `.insert(payload)` sem `.select()`
— mas exposta ao mesmo risco em qualquer mudança futura que
encadeie um `.select()` ali).

Confirmado, por comparação com o pipeline de Cartas (import-catalog-
cards): a Query 2090 nunca precisou tocar catalog_import_row porque
o job de Cartas é pré-criado via RPC (admin_start_catalog_import,
SECURITY DEFINER, privilégios do owner) — só o processador de
Variantes cria o próprio job via INSERT direto do client de
service_role (diferença deliberada documentada no cabeçalho da Edge
Function: CV-02, sem RPC/tela de pré-criação neste incremento).

Regras de Negócio:
- Nenhuma política de RLS é alterada — só GRANT de nível de tabela,
  mesma técnica da Query 2090.
- anon e authenticated não são tocados — nenhum GRANT novo, nenhuma
  mudança de comportamento para esses papéis.
- Nenhum INSERT/UPDATE/DELETE novo é concedido a service_role — só
  SELECT, nas 3 tabelas exatas do gap auditado.
- card_variant continua sem nenhum grant de escrita para
  service_role — a escrita real continua exclusiva de
  internal.write_card_variant() (Query 2143, SECURITY DEFINER),
  nunca de um INSERT/UPDATE direto do client de service_role.

Pré-requisitos:
- Query 2136 - Create Catalog Variant Import Job Table.
- Query 2138 - Create Catalog Variant Import Row Table.
- Query 160 - Create Card Variant Table.
- Query 2090 - Grant Service Role Read Access for Catalog Import
  Processor (precedente direto, mesmo padrão).
================================================================
*/

BEGIN;

GRANT SELECT ON public.catalog_variant_import_job TO service_role;
GRANT SELECT ON public.catalog_variant_import_row TO service_role;
GRANT SELECT ON public.card_variant TO service_role;

COMMIT;

-- ================================================================
-- Confirmado executado (2026-08-15, via execute_sql/MCP do Supabase,
-- projeto qjfutqujxrbzgrtkpgkg), depois de dry-run em BEGIN...ROLLBACK
-- que confirmou: SELECT adicionado às 3 tabelas para service_role,
-- INSERT/UPDATE preservados sem alteração, anon sem nenhum grant
-- (intocado), authenticated com o mesmo SELECT que já tinha antes
-- (intocado), contagem de pg_policies (schema public) inalterada em
-- 20 — nenhuma RLS/policy tocada. Execução real repetiu a mesma
-- sequência com COMMIT e foi reverificada com resultado idêntico.
-- ================================================================

-- ================================================================
-- Como validar:
-- SELECT table_name, grantee, string_agg(privilege_type, ',')
-- FROM information_schema.role_table_grants
-- WHERE table_schema = 'public' AND grantee = 'service_role'
--   AND table_name IN ('catalog_variant_import_job', 'catalog_variant_import_row', 'card_variant')
-- GROUP BY table_name, grantee;
-- Esperado: catalog_variant_import_job/row com INSERT,SELECT,UPDATE
-- (+ REFERENCES/TRIGGER/TRUNCATE herdados do default ACL); card_variant
-- com SELECT (+ REFERENCES/TRIGGER/TRUNCATE), sem INSERT/UPDATE/DELETE.
-- ================================================================
