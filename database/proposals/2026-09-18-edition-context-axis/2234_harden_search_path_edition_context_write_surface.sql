/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2234 - Harden search_path das 4 funções-raiz da superfície de escrita do Batch 12
Versão......: 1.1
Status......: PROPOSTA — NÃO EXECUTADA. Exige autorização específica de Fabrício (DDL).
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-27

Descrição...:
O E00 (P7, regra search_path_unsafe) classifica como inseguras, no LIVE,
exatamente 4 funções (registros LIVE-L2/L3/L4, campo d_p7_functions):
  1. public.set_updated_at()                          proconfig {search_path=public, pg_temp} (2132)
  2. public.validate_card_variant_game_consistency()  proconfig NULL (excluída da 2132)
  3. public.normalize_catalog_variant_import_job()    proconfig NULL (2137, posterior à 2132)
  4. public.normalize_catalog_variant_import_row()    proconfig NULL (2139, posterior à 2132)
As 4 são raízes de trigger das tabelas escritas pelos lotes L5, L6, L7, L11
e L12 (game, card_variant, catalog_variant_import_job/row). A regra do E00
exige proconfig com search_path="" — a mesma das funções internal.* (2207,
2210, 2214, 2224). Esta Query iguala as 4 a esse padrão; nenhuma mitigação
de precheck substitui esta correção (o P7X dos prechecks de lote passa a
exigir search_path="" nas 8 raízes e falha enquanto a 2234 não rodar).

A proposta anterior (citada na auditoria B12, sem arquivo) tinha só 3
ALTERs e deixava set_updated_at no padrão da 2132 — o que manteria o E00
reprovando a função. Corrigido: 4 ALTERs.

Compatibilidade (corpos lidos no repositório; pinos md5 LF = LIVE):
- set_updated_at (98a97559…): `NEW.updated_at = CURRENT_TIMESTAMP`. Nenhuma
  referência a objeto. No repositório, 48 tabelas (DDL histórico e
  corrente, inclui user_profile/reserved_username) recebem trigger dela,
  todas com updated_at TIMESTAMPTZ; o alcance LIVE é provado na pré-condição.
  Efeito da troca: nenhum.
- validate_card_variant_game_consistency (c1fe1758…): lê public.card,
  public.card_set, public.expansion, public.card_variant_type — TODAS
  qualificadas; RAISE. Efeito: nenhum.
- normalize_catalog_variant_import_job/row (c01adb02… / 7ae9bd52…): UPPER,
  BTRIM, NULLIF — builtins de pg_catalog, resolvidos com search_path vazio
  (pg_catalog é sempre pesquisado implicitamente). Efeito: nenhum.
- Com search_path = '' e sem pg_temp explícito, pg_temp seria pesquisado
  primeiro para RELAÇÕES não qualificadas; nenhuma das 4 tem relação não
  qualificada. Funções nunca são resolvidas em pg_temp implicitamente.
- ALTER FUNCTION ... SET grava só proconfig: prosrc, assinatura, OID,
  owner, ACL e triggers dependentes não mudam (pg_depend intacto).
- Custo: as 3 funções hoje sem proconfig passam a salvar/restaurar o GUC
  por chamada (mesmo custo que set_updated_at e as internal.* já pagam).

Fora de escopo (registrado, não corrigido aqui): as outras 12 funções da
2132 continuam com 'public, pg_temp'; não participam da superfície de
escrita dos lotes L5–L13 e o E00 não as inclui no gate_scope.

Efeito sobre os pinos do harness: md5 dos corpos inalterado; proconfig
esperado passa a {search_path=""} nas 4 (tools/b12gen/pre.py, P7X, já
atualizado para exigir exatamente isso).

Auditoria de resolução sob search_path vazio (v1.1, corpos pinados):
- set_updated_at: `NEW.updated_at = CURRENT_TIMESTAMP` — CURRENT_TIMESTAMP é
  construção SQL (sem busca por nome). Nenhum cast: toda tabela com trigger
  para set_updated_at no repositório declara updated_at TIMESTAMPTZ; a
  pré-condição PROVA isso no LIVE para TODOS os triggers ligados à função
  (alcance real, não a contagem do repositório).
- validate_card_variant_game_consistency: relações public.card,
  public.card_set, public.expansion, public.card_variant_type (qualificadas;
  existência exigida na pré-condição); tipo UUID e operadores =/<> sobre uuid
  (pg_catalog); RAISE com formatação por OID de tipo.
- normalize_*: UPPER(text), BTRIM(text) (pg_catalog), NULLIF (construção SQL).
- Tipos, casts e operadores são resolvidos por OID ou em pg_catalog, que é
  sempre pesquisado implicitamente. Nenhuma chamada a função de usuário.

Preservação (v1.1): a pré-condição grava, em GUC LOCAL da transação
(set_config(..., true) — desfeito no fim da transação, nada persiste), duas
impressões digitais: (a) metadados das 4 funções exceto proconfig (corpo LF,
owner, ACL, secdef, volatilidade, strict, leakproof, retorno, linguagem,
nargs); (b) TODOS os triggers ligados às 4 (tgrelid oid, tgname, tgtype,
tgenabled, tgfoid) + contagem de pg_depend. A pós-condição recalcula e exige
igualdade — a única diferença admitida é proconfig.

Execução: Fabrício, via apply_migration, UMA transação (BEGIN/COMMIT, mesmo
padrão das 2203–2233 executadas). Qualquer falha de pré/pós-condição aborta
tudo; nada é aplicado parcialmente. Rollback: seção ROLLBACK ao fim (texto
comentado; executar só com autorização, também em uma transação).
================================================================
*/

BEGIN;

SET LOCAL lock_timeout = '5s';

-- PRÉ-CONDIÇÃO: identidade exata (corpo + proconfig atual), relações
-- qualificadas existentes, alcance do set_updated_at e impressões digitais
DO $pre$
DECLARE
    r record;
    v_n bigint;
BEGIN
    IF current_setting('lock_timeout') <> '5s' THEN
        RAISE EXCEPTION '2234_PRECONDITION: lock_timeout=% (esperado 5s)', current_setting('lock_timeout');
    END IF;
    FOR r IN
        SELECT e.sig, e.pin, e.cfg_now,
               p.oid IS NOT NULL AS found,
               md5(replace(p.prosrc, chr(13) || chr(10), chr(10))) AS body_md5,
               p.proconfig::text[] AS cfg, p.prosecdef AS secdef
          FROM (VALUES ('public.set_updated_at()',                         '98a97559965c2e0ff884d95155ab5d3a', ARRAY['search_path=public, pg_temp']),
                       ('public.validate_card_variant_game_consistency()', 'c1fe17587dfb3b0f6d7d5d690ca13636', NULL::text[]),
                       ('public.normalize_catalog_variant_import_job()',   'c01adb02245bd5a305e8f8987a30f1c1', NULL::text[]),
                       ('public.normalize_catalog_variant_import_row()',   '7ae9bd52e030b13c3a241debda491a99', NULL::text[])) AS e(sig, pin, cfg_now)
          LEFT JOIN pg_proc p ON p.oid = to_regprocedure(e.sig)
    LOOP
        IF NOT r.found OR r.body_md5 IS DISTINCT FROM r.pin OR r.cfg IS DISTINCT FROM r.cfg_now OR r.secdef THEN
            RAISE EXCEPTION '2234_PRECONDITION: % found=% md5=% proconfig=% secdef=% (esperado md5=% proconfig=% invoker)',
                r.sig, r.found, r.body_md5, r.cfg, r.secdef, r.pin, r.cfg_now;
        END IF;
    END LOOP;
    IF to_regclass('public.card') IS NULL OR to_regclass('public.card_set') IS NULL
       OR to_regclass('public.expansion') IS NULL OR to_regclass('public.card_variant_type') IS NULL THEN
        RAISE EXCEPTION '2234_PRECONDITION: relação qualificada de validate_card_variant_game_consistency ausente';
    END IF;
    -- alcance real de set_updated_at: todo trigger ligado a ela escreve em
    -- updated_at TIMESTAMPTZ (sem cast => nenhuma resolução por nome)
    SELECT count(*) INTO v_n
      FROM pg_trigger t
      LEFT JOIN pg_attribute a ON a.attrelid = t.tgrelid AND a.attname = 'updated_at' AND NOT a.attisdropped
     WHERE NOT t.tgisinternal
       AND t.tgfoid = to_regprocedure('public.set_updated_at()')
       AND (a.atttypid IS DISTINCT FROM 'pg_catalog.timestamptz'::pg_catalog.regtype);
    IF v_n <> 0 THEN
        RAISE EXCEPTION '2234_PRECONDITION: % trigger(s) de set_updated_at em tabela sem updated_at TIMESTAMPTZ', v_n;
    END IF;
    SELECT count(*) INTO v_n FROM pg_trigger t
     WHERE NOT t.tgisinternal AND t.tgfoid = to_regprocedure('public.set_updated_at()');
    IF v_n = 0 THEN
        RAISE EXCEPTION '2234_PRECONDITION: nenhum trigger ligado a set_updated_at (inventário divergente)';
    END IF;
    RAISE NOTICE '2234: set_updated_at alcança % trigger(s), todos com updated_at TIMESTAMPTZ', v_n;
    -- impressões digitais (GUC local da transação; nada persiste)
    PERFORM set_config('mmkyu.p2234_fn', (
        SELECT string_agg(concat_ws('|', p.oid, md5(replace(p.prosrc, chr(13) || chr(10), chr(10))), p.proowner, p.proacl::text,
                                    p.prosecdef, p.provolatile, p.proisstrict, p.proleakproof, p.prorettype, p.prolang, p.pronargs),
                          ';' ORDER BY p.oid)
          FROM pg_proc p
         WHERE p.oid IN (to_regprocedure('public.set_updated_at()'),
                         to_regprocedure('public.validate_card_variant_game_consistency()'),
                         to_regprocedure('public.normalize_catalog_variant_import_job()'),
                         to_regprocedure('public.normalize_catalog_variant_import_row()'))), true);
    PERFORM set_config('mmkyu.p2234_dep', (
        SELECT concat_ws('#',
                 (SELECT string_agg(concat_ws('|', t.tgrelid::oid, t.tgname, t.tgtype, t.tgenabled, t.tgfoid::oid), ';'
                                    ORDER BY t.tgrelid::oid, t.tgname)
                    FROM pg_trigger t
                   WHERE NOT t.tgisinternal
                     AND t.tgfoid IN (to_regprocedure('public.set_updated_at()'),
                                      to_regprocedure('public.validate_card_variant_game_consistency()'),
                                      to_regprocedure('public.normalize_catalog_variant_import_job()'),
                                      to_regprocedure('public.normalize_catalog_variant_import_row()'))),
                 (SELECT count(*) FROM pg_depend d
                   WHERE d.refclassid = 'pg_catalog.pg_proc'::pg_catalog.regclass
                     AND d.refobjid IN (to_regprocedure('public.set_updated_at()'),
                                        to_regprocedure('public.validate_card_variant_game_consistency()'),
                                        to_regprocedure('public.normalize_catalog_variant_import_job()'),
                                        to_regprocedure('public.normalize_catalog_variant_import_row()'))))), true);
    IF current_setting('mmkyu.p2234_fn', true) IS NULL OR current_setting('mmkyu.p2234_dep', true) IS NULL THEN
        RAISE EXCEPTION '2234_PRECONDITION: impressão digital não capturada';
    END IF;
END
$pre$;

ALTER FUNCTION public.set_updated_at() SET search_path = '';
ALTER FUNCTION public.validate_card_variant_game_consistency() SET search_path = '';
ALTER FUNCTION public.normalize_catalog_variant_import_job() SET search_path = '';
ALTER FUNCTION public.normalize_catalog_variant_import_row() SET search_path = '';

-- PÓS-CONDIÇÃO: proconfig exato; metadados, triggers e dependências idênticos
DO $post$
DECLARE
    v_n bigint;
    v_fn text;
    v_dep text;
BEGIN
    SELECT count(*) INTO v_n
      FROM pg_proc p
     WHERE p.oid IN (to_regprocedure('public.set_updated_at()'),
                     to_regprocedure('public.validate_card_variant_game_consistency()'),
                     to_regprocedure('public.normalize_catalog_variant_import_job()'),
                     to_regprocedure('public.normalize_catalog_variant_import_row()'))
       AND p.proconfig::text[] = ARRAY['search_path=""']
       AND md5(replace(p.prosrc, chr(13) || chr(10), chr(10))) IN
           ('98a97559965c2e0ff884d95155ab5d3a', 'c1fe17587dfb3b0f6d7d5d690ca13636',
            'c01adb02245bd5a305e8f8987a30f1c1', '7ae9bd52e030b13c3a241debda491a99');
    IF v_n <> 4 THEN
        RAISE EXCEPTION '2234_POSTCONDITION: % de 4 funções com search_path="" e corpo pinado', v_n;
    END IF;
    SELECT string_agg(concat_ws('|', p.oid, md5(replace(p.prosrc, chr(13) || chr(10), chr(10))), p.proowner, p.proacl::text,
                                p.prosecdef, p.provolatile, p.proisstrict, p.proleakproof, p.prorettype, p.prolang, p.pronargs),
                      ';' ORDER BY p.oid)
      INTO v_fn
      FROM pg_proc p
     WHERE p.oid IN (to_regprocedure('public.set_updated_at()'),
                     to_regprocedure('public.validate_card_variant_game_consistency()'),
                     to_regprocedure('public.normalize_catalog_variant_import_job()'),
                     to_regprocedure('public.normalize_catalog_variant_import_row()'));
    SELECT concat_ws('#',
             (SELECT string_agg(concat_ws('|', t.tgrelid::oid, t.tgname, t.tgtype, t.tgenabled, t.tgfoid::oid), ';'
                                ORDER BY t.tgrelid::oid, t.tgname)
                FROM pg_trigger t
               WHERE NOT t.tgisinternal
                 AND t.tgfoid IN (to_regprocedure('public.set_updated_at()'),
                                  to_regprocedure('public.validate_card_variant_game_consistency()'),
                                  to_regprocedure('public.normalize_catalog_variant_import_job()'),
                                  to_regprocedure('public.normalize_catalog_variant_import_row()'))),
             (SELECT count(*) FROM pg_depend d
               WHERE d.refclassid = 'pg_catalog.pg_proc'::pg_catalog.regclass
                 AND d.refobjid IN (to_regprocedure('public.set_updated_at()'),
                                    to_regprocedure('public.validate_card_variant_game_consistency()'),
                                    to_regprocedure('public.normalize_catalog_variant_import_job()'),
                                    to_regprocedure('public.normalize_catalog_variant_import_row()')))))
      INTO v_dep;
    IF v_fn IS DISTINCT FROM current_setting('mmkyu.p2234_fn', true) THEN
        RAISE EXCEPTION '2234_POSTCONDITION: metadados das funções mudaram além de proconfig';
    END IF;
    IF v_dep IS DISTINCT FROM current_setting('mmkyu.p2234_dep', true) THEN
        RAISE EXCEPTION '2234_POSTCONDITION: triggers/dependências das 4 funções mudaram';
    END IF;
    SELECT count(*) INTO v_n
      FROM pg_trigger t
     WHERE NOT t.tgisinternal
       AND t.tgfoid IN (to_regprocedure('public.validate_card_variant_game_consistency()'),
                        to_regprocedure('public.normalize_catalog_variant_import_job()'),
                        to_regprocedure('public.normalize_catalog_variant_import_row()'));
    IF v_n <> 3 THEN
        RAISE EXCEPTION '2234_POSTCONDITION: % triggers ligados às 3 funções de tabela (esperado 3)', v_n;
    END IF;
END
$post$;

COMMIT;

-- ----------------------------------------------------------------
-- Como validar (depois do COMMIT, read-only):
--   SELECT p.oid::regprocedure, p.proconfig
--     FROM pg_proc p
--    WHERE p.oid IN (to_regprocedure('public.set_updated_at()'),
--                    to_regprocedure('public.validate_card_variant_game_consistency()'),
--                    to_regprocedure('public.normalize_catalog_variant_import_job()'),
--                    to_regprocedure('public.normalize_catalog_variant_import_row()'));
--   Resultado esperado: 4 linhas, proconfig = {search_path=""}. Em seguida, o
--   E00 deve listar as 4 com search_path_unsafe = false.
-- ----------------------------------------------------------------
-- ROLLBACK (NÃO executar sem autorização; restaura proconfig exato anterior):
--   BEGIN;
--   SET LOCAL lock_timeout = '5s';
--   ALTER FUNCTION public.set_updated_at() SET search_path = public, pg_temp;
--   ALTER FUNCTION public.validate_card_variant_game_consistency() RESET search_path;
--   ALTER FUNCTION public.normalize_catalog_variant_import_job() RESET search_path;
--   ALTER FUNCTION public.normalize_catalog_variant_import_row() RESET search_path;
--   -- pós-condição: set_updated_at proconfig = {"search_path=public, pg_temp"}
--   -- e as outras 3 proconfig IS NULL (RESET remove a única entrada); corpos
--   -- nos mesmos pinos. Qualquer divergência: ROLLBACK.
--   COMMIT;
--   Efeito: devolve o estado reprovado pelo E00 (P7) e pelos prechecks P7X.
-- ----------------------------------------------------------------
