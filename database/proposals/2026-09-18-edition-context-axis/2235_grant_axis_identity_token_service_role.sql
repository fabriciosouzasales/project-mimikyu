/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2235 - GRANT EXECUTE de internal.axis_identity_token ao writer real do staging (service_role)
Versão......: 1.0
Status......: PROPOSTA — NÃO EXECUTADA. Exige autorização específica de Fabrício (DCL no LIVE).
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-04
Mandato.....: BATCH12-POST-UNFREEZE-CANARY-ACL-CORRECTION-01

Descrição...:
Corrige o blocker revelado pelo primeiro canary real pós-UNFREEZE (SVE,
job 3ec9c551-b91f-43df-b360-60d796e47623, FAILED):

    VARIANT_IMPORT_ROWS_INSERT_FAILED:
    permission denied for function axis_identity_token

Cadeia causal (confirmada no repositório e no LIVE, só leitura):
- A 2210 (LIVE 20260920171100) criou internal.axis_identity_token(jsonb,text)
  e o índice de expressão public.uq_cvir_row_identity, que chama a função nos
  dois eixos (printing_profile_id, edition_context_profile_id).
- A ACL gravada pela 2210 é {postgres=X, authenticated=X}: REVOKE de PUBLIC e
  anon, GRANT só a authenticated.
- O writer real de catalog_variant_import_row é a Edge import-card-variants,
  que usa o client service_role (INSERT direto, services/database.ts
  insertVariantImportRows). service_role tem INSERT na tabela, mas NÃO tem
  EXECUTE na função. O Postgres exige EXECUTE do papel efetivo para avaliar
  a expressão do índice no INSERT; sem ele, o INSERT falha.
- authenticated não tem INSERT/UPDATE na tabela: o GRANT da 2210 foi para o
  papel errado do ponto de vista do writer direto. As cinco RPCs que fazem
  UPDATE nas rows (apply_variant_type_mapping, create_card_printing_profile_
  with_backfill, admin_confirm/decide/resolve_*) são SECURITY DEFINER com
  owner postgres — não são afetadas e não mudam aqui.
- O trigger trg_cvir_normalized_shape (função internal.guard_cvir_normalized_
  shape, sem EXECUTE para service_role) NÃO é afetado: o Postgres só verifica
  EXECUTE da função de trigger no CREATE TRIGGER, não no disparo. Evidência:
  o canary falhou na avaliação do índice, depois do BEFORE trigger.
- service_role não tem USAGE no schema internal. Isso NÃO é necessário: a
  expressão do índice já está resolvida por OID e a execução verifica só
  EXECUTE na função (o erro observado é "for function", não "for schema").
  Nenhum USAGE é concedido aqui.

Correção: exatamente um GRANT EXECUTE ao service_role, em uma transação com
pré e pós-condição fail-loud. NÃO altera corpo, volatilidade, owner,
SECURITY, search_path da função; NÃO toca no índice (sem REINDEX: a função é
IMMUTABLE e seu comportamento não muda); NÃO toca em guards, RLS,
privilégios de tabela, Edge ou frontend. A 2210 é histórica e não é editada.

Matriz de EXECUTE em internal.axis_identity_token(jsonb,text):
    papel          antes   depois
    postgres       true    true    (owner)
    authenticated  true    true    (preservado; revogar exige decisão própria)
    service_role   false   TRUE    (único delta)
    anon           false   false
    PUBLIC         —       —       (sem entrada na ACL)

Execução: Fabrício, via apply_migration, UMA transação. Qualquer falha de pré
ou pós-condição aborta tudo; nada é aplicado parcialmente.
Validação depois do COMMIT: 2835_validate_staging_writer_acl.sql (read-only).
Retry do canary SVE: só depois de 2235 aplicada, 2835 gate_pass = true e
mandato próprio.
================================================================
*/

BEGIN;

SET LOCAL lock_timeout = '5s';

-- PRÉ-CONDIÇÃO: identidade exata da função e do índice; anon sem EXECUTE.
DO $pre$
DECLARE
    v_fn  oid := to_regprocedure('internal.axis_identity_token(jsonb,text)');
    v_idx oid := to_regclass('public.uq_cvir_row_identity');
    v_n   bigint;
    r     record;
BEGIN
    IF v_fn IS NULL THEN
        RAISE EXCEPTION '2235_PRECONDITION: internal.axis_identity_token(jsonb,text) ausente.';
    END IF;

    SELECT count(*) INTO v_n
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'internal' AND p.proname = 'axis_identity_token';
    IF v_n <> 1 THEN
        RAISE EXCEPTION '2235_PRECONDITION: esperado 1 overload de internal.axis_identity_token; encontrado %.', v_n;
    END IF;

    SELECT md5(p.prosrc) AS src_md5, p.provolatile, p.prosecdef, p.proisstrict,
           p.proconfig, pg_get_userbyid(p.proowner) AS owner
      INTO r
      FROM pg_proc p WHERE p.oid = v_fn;
    IF r.src_md5 <> '18682dce935281b0a4437628a6e8309a'
       OR r.provolatile <> 'i' OR r.prosecdef OR r.proisstrict
       OR r.proconfig IS DISTINCT FROM ARRAY['search_path=""']
       OR r.owner <> 'postgres' THEN
        RAISE EXCEPTION '2235_PRECONDITION: axis_identity_token divergente do contrato da 2210 (src_md5=%, volatile=%, secdef=%, strict=%, config=%, owner=%).',
            r.src_md5, r.provolatile, r.prosecdef, r.proisstrict, r.proconfig, r.owner;
    END IF;

    IF v_idx IS NULL THEN
        RAISE EXCEPTION '2235_PRECONDITION: public.uq_cvir_row_identity ausente.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_index i
                    WHERE i.indexrelid = v_idx
                      AND i.indrelid = 'public.catalog_variant_import_row'::regclass
                      AND i.indisunique AND i.indisvalid AND i.indisready) THEN
        RAISE EXCEPTION '2235_PRECONDITION: uq_cvir_row_identity não está unique/valid/ready em catalog_variant_import_row.';
    END IF;

    SELECT count(*) INTO v_n
      FROM pg_depend d
     WHERE d.classid = 'pg_class'::regclass AND d.objid = v_idx
       AND d.refclassid = 'pg_proc'::regclass;
    IF v_n <> 1 OR NOT EXISTS (SELECT 1 FROM pg_depend d
                                WHERE d.classid = 'pg_class'::regclass AND d.objid = v_idx
                                  AND d.refclassid = 'pg_proc'::regclass AND d.refobjid = v_fn) THEN
        RAISE EXCEPTION '2235_PRECONDITION: dependências pg_proc de uq_cvir_row_identity diferentes de {internal.axis_identity_token(jsonb,text)}.';
    END IF;

    IF has_function_privilege('anon', v_fn, 'EXECUTE') THEN
        RAISE EXCEPTION '2235_PRECONDITION: anon já tem EXECUTE em axis_identity_token — ACL fora do contrato; STOP.';
    END IF;
    IF NOT has_table_privilege('service_role', 'public.catalog_variant_import_row', 'INSERT') THEN
        RAISE EXCEPTION '2235_PRECONDITION: service_role sem INSERT em catalog_variant_import_row — causa raiz diferente da auditada; STOP.';
    END IF;
END
$pre$;

-- CORREÇÃO: o único statement que altera estado.
GRANT EXECUTE ON FUNCTION internal.axis_identity_token(JSONB, TEXT) TO service_role;

-- PÓS-CONDIÇÃO: matriz exata de EXECUTE, função e índice inalterados.
DO $post$
DECLARE
    v_fn  oid := to_regprocedure('internal.axis_identity_token(jsonb,text)');
    v_idx oid := to_regclass('public.uq_cvir_row_identity');
    v_grantees text[];
BEGIN
    IF NOT has_function_privilege('service_role', v_fn, 'EXECUTE') THEN
        RAISE EXCEPTION '2235_POSTCONDITION: service_role continua sem EXECUTE.';
    END IF;
    IF has_function_privilege('anon', v_fn, 'EXECUTE') THEN
        RAISE EXCEPTION '2235_POSTCONDITION: anon ganhou EXECUTE.';
    END IF;
    IF NOT has_function_privilege('authenticated', v_fn, 'EXECUTE') THEN
        RAISE EXCEPTION '2235_POSTCONDITION: authenticated perdeu EXECUTE (não autorizado nesta correção).';
    END IF;

    -- Conjunto exato de grantees na ACL; 0 = PUBLIC.
    -- (array_agg ... ORDER BY g: em agregado, ORDER BY 1 seria constante.)
    SELECT array_agg(g ORDER BY g)
      INTO v_grantees
      FROM (SELECT CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END AS g
              FROM pg_proc p, aclexplode(p.proacl) a
             WHERE p.oid = v_fn AND a.privilege_type = 'EXECUTE') s;
    IF v_grantees IS DISTINCT FROM ARRAY['authenticated','postgres','service_role'] THEN
        RAISE EXCEPTION '2235_POSTCONDITION: grantees de EXECUTE = % (esperado {authenticated,postgres,service_role}).', v_grantees;
    END IF;

    IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = v_fn) <> '18682dce935281b0a4437628a6e8309a' THEN
        RAISE EXCEPTION '2235_POSTCONDITION: corpo de axis_identity_token mudou.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_index i
                    WHERE i.indexrelid = v_idx AND i.indisunique AND i.indisvalid AND i.indisready) THEN
        RAISE EXCEPTION '2235_POSTCONDITION: uq_cvir_row_identity deixou de estar unique/valid/ready.';
    END IF;
END
$post$;

COMMIT;

-- ----------------------------------------------------------------
-- Como validar (depois do COMMIT, read-only):
--   2835_validate_staging_writer_acl.sql — resultado esperado gate_pass = true.
--   Atalho mínimo:
--   SELECT has_function_privilege('service_role','internal.axis_identity_token(jsonb,text)','EXECUTE') AS sr,
--          has_function_privilege('anon','internal.axis_identity_token(jsonb,text)','EXECUTE')        AS anon;
--   Esperado: sr = true, anon = false.
-- ----------------------------------------------------------------
-- ROLLBACK (NÃO executar sem autorização; devolve exatamente a ACL anterior):
--   BEGIN;
--   REVOKE EXECUTE ON FUNCTION internal.axis_identity_token(JSONB, TEXT) FROM service_role;
--   COMMIT;
--   Efeito: volta o blocker — a Edge import-card-variants deixa de conseguir
--   inserir rows de staging (todo import de variantes termina FAILED).
