/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2132 - Harden search_path on Catálogo Editorial/pipeline functions
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO (via MCP do Supabase, projeto qjfutqujxrbzgrtkpgkg)
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-14

Descrição...:
Finding 3 da auditoria de segurança independente do Catálogo
Editorial (GitHub + Supabase de produção): Advisor de segurança
do Supabase (get_advisors, categoria security) apontou 15
functions com function_search_path_mutable — sem search_path
fixo, uma function SECURITY DEFINER fica sujeita ao search_path
da sessão que a chama, o que é o vetor clássico de sequestro de
schema (uma role conseguindo criar um objeto de mesmo nome em um
schema que entre antes do esperado no search_path).

Escopo desta Query — 13 das 15 functions, todas do Catálogo
Editorial/pipeline de importação: set_updated_at,
validate_card_game_consistency, validate_card_asset_game_
consistency, normalize_asset_source, protect_asset_source_
identity, normalize_card_external_reference, normalize_asset_
import_run, govern_asset_import_run, normalize_asset_import_
failure, protect_card_external_reference_identity, govern_
asset_import_failure, normalize_catalog_import_job, normalize_
catalog_import_row.

Deliberadamente EXCLUÍDAS desta rodada:
- enforce_user_profile_invariants: domínio Identidade/Acesso, fora
  do escopo desta auditoria (Catálogo Editorial).
- validate_card_variant_game_consistency: pertence à infraestrutura
  de Card Variant — por instrução explícita de Fabrício, não
  tratada agora; registrada para tratamento junto com a abertura
  formal do bloco Card Variant (ver docs/ROADMAP.md).

Pré-condições confirmadas antes de aplicar:
1. public não é gravável por roles não confiáveis — has_schema_
   privilege('public', 'CREATE') = false para PUBLIC, anon,
   authenticated E service_role (CREATE em public restrito por
   padrão nesta versão do Postgres/Supabase). SET search_path =
   public, pg_temp é seguro: nenhuma role sem privilégio de
   superusuário/dono consegue criar um objeto em public que
   sequestre uma referência não qualificada dentro dessas
   functions.
2. Corpo de todas as 13 lido via pg_get_functiondef() antes de
   aplicar: 11 são trigger functions que só manipulam campos
   NEW/OLD com funções built-in (UPPER/BTRIM/NULLIF/COALESCE/
   CLOCK_TIMESTAMP), sem nenhuma referência a tabela; as 2
   restantes (validate_card_game_consistency, validate_card_
   asset_game_consistency) referenciam tabelas, mas 100%
   schema-qualificadas (public.card, public.card_set,
   public.expansion, public.rarity, public.card_category,
   public.card_asset_type) — nenhuma delas depende de resolução
   implícita por search_path, e nenhuma referencia schema fora de
   public. Corpo/assinatura de todas as 13 permanecem idênticos
   (ALTER FUNCTION ... SET só grava proconfig — nunca toca prosrc
   nem proargtypes).
3. set_updated_at é usada por 21 tabelas, incluindo duas fora do
   Catálogo Editorial (user_profile, reserved_username — domínio
   Identidade/Acesso). Incluída mesmo assim: seu corpo (`NEW.
   updated_at = CURRENT_TIMESTAMP; RETURN NEW;`) não referencia
   nenhuma tabela/schema, então o hardening é neutro para
   qualquer módulo que a use — confirmado sem impacto indevido.

Validação (2026-08-14, confirmada nesta mesma sessão):
- Reexecução do Advisor de segurança: as 13 não aparecem mais em
  function_search_path_mutable; só enforce_user_profile_invariants
  e validate_card_variant_game_consistency permanecem (esperado,
  deliberadamente fora de escopo).
- pg_proc.proconfig confirmado ['search_path=public, pg_temp'] nas
  13; enforce_user_profile_invariants e validate_card_variant_
  game_consistency confirmadas com proconfig NULL (inalteradas).
- Nenhum DROP/CREATE executado — só ALTER FUNCTION ... SET,
  garantindo estruturalmente que corpo/assinatura não mudaram.

Pré-requisitos:
- Queries originais de criação de cada trigger/function (schemas
  do Bloco B/C do Catálogo Editorial — ver docs/05-modelo-de-
  dados.md e sucessores).
================================================================
*/

ALTER FUNCTION public.set_updated_at() SET search_path = public, pg_temp;
ALTER FUNCTION public.validate_card_game_consistency() SET search_path = public, pg_temp;
ALTER FUNCTION public.validate_card_asset_game_consistency() SET search_path = public, pg_temp;
ALTER FUNCTION public.normalize_asset_source() SET search_path = public, pg_temp;
ALTER FUNCTION public.protect_asset_source_identity() SET search_path = public, pg_temp;
ALTER FUNCTION public.normalize_card_external_reference() SET search_path = public, pg_temp;
ALTER FUNCTION public.normalize_asset_import_run() SET search_path = public, pg_temp;
ALTER FUNCTION public.govern_asset_import_run() SET search_path = public, pg_temp;
ALTER FUNCTION public.normalize_asset_import_failure() SET search_path = public, pg_temp;
ALTER FUNCTION public.protect_card_external_reference_identity() SET search_path = public, pg_temp;
ALTER FUNCTION public.govern_asset_import_failure() SET search_path = public, pg_temp;
ALTER FUNCTION public.normalize_catalog_import_job() SET search_path = public, pg_temp;
ALTER FUNCTION public.normalize_catalog_import_row() SET search_path = public, pg_temp;

-- ================================================================
-- Confirmado executado (2026-08-14, via apply_migration/MCP do
-- Supabase) e validado: proconfig = ['search_path=public, pg_temp']
-- nas 13 functions; Advisor de segurança sem mais reportar
-- function_search_path_mutable para nenhuma delas; enforce_user_
-- profile_invariants e validate_card_variant_game_consistency
-- confirmadas inalteradas (excluídas deliberadamente).
-- ================================================================
