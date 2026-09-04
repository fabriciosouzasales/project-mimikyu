/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 6810 - Validate Pokemon Region Foundation
Versão......: 1.1 (revisão GATE 4: prova simultânea de ON UPDATE +
               ON DELETE RESTRICT na FK de main_region_id; prova
               definitiva de zero DML para service_role; todos os
               CHECKs validados, não apenas amostra; prova
               comportamental de N:1; source_order de fixture
               calculado deterministicamente)
Status......: CONFIRMADO EXECUTADO — resultado PASS
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-04 (staging em POKEMON-REGION-FOUNDATION-
               PHYSICAL-STAGING-01; revisado em 2026-09-04 via
               POKEMON-REGION-FOUNDATION-PHYSICAL-STAGING-REVISION-01;
               executado em 2026-09-04 via POKEMON-REGION-FOUNDATION-
               PHYSICAL-IMPLEMENTATION-01)

Descrição...:
Script de validação da Region Foundation: pokemon_region,
pokemon_region_external_reference, e o incremento main_region_id em
pokemon_generation (Queries 6060/6061/6070/6071/6080). Mesmo padrão
estrutural já usado em 6800 (Validate Pokedex Foundation, CONFIRMADO
EXECUTADO, PASS): Seção 1 estrutural, Seção 2 comportamental
(BEGIN...ROLLBACK, fixtures sintéticas, zero resíduo), Seção 3
privilégios de função, Seção 4 nota de performance.

Cobre, nesta ordem:
1. Validação estrutural (tabelas, colunas-chave, PK, FKs — incluindo
   prova simultânea de confupdtype='r' E confdeltype='r' para
   main_region_id —, TODAS as 5 UNIQUE/CHECK relevantes (não amostra),
   ausência de UNIQUE/índice em main_region_id, índices, triggers
   ativos, RLS habilitado, zero policy, zero privilégio efetivo para
   anon/authenticated via has_table_privilege(), e prova definitiva de
   zero DML (SELECT/INSERT/UPDATE/DELETE) para service_role em
   pokemon_region/pokemon_region_external_reference/pokemon_generation).
2. Validação comportamental, transacional (BEGIN...ROLLBACK — dados de
   fixture sintéticos, nenhum resíduo real, source_order de fixture
   calculado deterministicamente): normalização, unicidade, CHECK,
   imutabilidade, correção editorial, CASCADE/RESTRICT, comportamento
   de pokemon_generation.main_region_id (NOT NULL, N:1 comportamental —
   duas Generations distintas com o mesmo main_region_id —, RESTRICT ao
   excluir Region referenciada, correção administrativa permitida —
   decisão congelada de NÃO tornar imutável a nível de trigger).
3. Privilégios de função (EXECUTE das 6 trigger functions novas,
   esperado FALSE para anon/authenticated).
4. Performance (proporcional ao volume/risco real desta rodada — nota
   textual, sem benchmark de carga sintética).

Segue o mesmo padrão de "número de diário" já usado em 6800 — os
testes que verificam rejeição usam bloco BEGIN...EXCEPTION do próprio
PL/pgSQL (subtransação implícita), nunca abortando a transação externa,
que é sempre revertida ao final (ROLLBACK), garantindo zero resíduo
mesmo em execução real.

Pré-requisitos:
- Queries 6060, 6061, 6070, 6071, 6080 (todas PROPOSTAS nesta mesma
  pasta de staging — devem estar CONFIRMADO EXECUTADO antes deste
  script ser rodado).
- Query 6700 (linha POKEAPI em asset_source, já CONFIRMADO EXECUTADO).

IMPORTANTE — status desta versão: este arquivo é staging puro. Não foi
executado contra nenhum banco. Nenhuma alegação de PASS/FAIL real é
feita aqui — apenas a lógica de validação, pronta para execução futura
mediante autorização explícita.
===============================================================================
*/

-- ===================================================================
-- SEÇÃO 1 — VALIDAÇÃO ESTRUTURAL
-- ===================================================================
DO $$
DECLARE
    v_count INTEGER;
BEGIN
    -- 1.1 Tabelas existem
    IF to_regclass('public.pokemon_region') IS NULL THEN
        RAISE EXCEPTION 'FAIL 1.1.1: public.pokemon_region não existe';
    END IF;
    IF to_regclass('public.pokemon_region_external_reference') IS NULL THEN
        RAISE EXCEPTION 'FAIL 1.1.2: public.pokemon_region_external_reference não existe';
    END IF;
    RAISE NOTICE 'PASS 1.1: as 2 tabelas novas existem';

    -- 1.2 Colunas-chave e NOT NULL (spot check)
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'pokemon_region'
          AND column_name = 'code' AND is_nullable = 'NO'
    ) THEN
        RAISE EXCEPTION 'FAIL 1.2.1: pokemon_region.code ausente ou nullable';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'pokemon_region_external_reference'
          AND column_name = 'metadata' AND data_type = 'jsonb'
    ) THEN
        RAISE EXCEPTION 'FAIL 1.2.2: pokemon_region_external_reference.metadata ausente/tipo errado';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'pokemon_generation'
          AND column_name = 'main_region_id' AND is_nullable = 'NO'
          AND data_type = 'uuid'
    ) THEN
        RAISE EXCEPTION 'FAIL 1.2.3: pokemon_generation.main_region_id ausente, nullable, ou tipo errado';
    END IF;
    RAISE NOTICE 'PASS 1.2: colunas-chave conferidas (inclui main_region_id em pokemon_generation)';

    -- 1.3 Primary Keys
    IF (SELECT COUNT(*) FROM pg_constraint WHERE conrelid = 'public.pokemon_region'::regclass AND contype = 'p') <> 1 THEN
        RAISE EXCEPTION 'FAIL 1.3.1: PK de pokemon_region ausente';
    END IF;
    IF (SELECT COUNT(*) FROM pg_constraint WHERE conrelid = 'public.pokemon_region_external_reference'::regclass AND contype = 'p') <> 1 THEN
        RAISE EXCEPTION 'FAIL 1.3.2: PK de pokemon_region_external_reference ausente';
    END IF;
    RAISE NOTICE 'PASS 1.3: as 2 PKs existem';

    -- 1.4 Foreign Keys com ON DELETE correto (confdeltype: c=cascade, r=restrict)
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'public.pokemon_region_external_reference'::regclass
          AND contype = 'f' AND confrelid = 'public.pokemon_region'::regclass
          AND confdeltype = 'c'
    ) THEN
        RAISE EXCEPTION 'FAIL 1.4.1: FK pokemon_region_external_reference.pokemon_region_id ausente ou sem ON DELETE CASCADE';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'public.pokemon_region_external_reference'::regclass
          AND contype = 'f' AND confrelid = 'public.asset_source'::regclass
          AND confdeltype = 'r'
    ) THEN
        RAISE EXCEPTION 'FAIL 1.4.2: FK pokemon_region_external_reference.asset_source_id ausente ou sem ON DELETE RESTRICT';
    END IF;
    -- Prova simultânea de ON UPDATE RESTRICT (confupdtype) e ON DELETE
    -- RESTRICT (confdeltype) na FK de main_region_id — achado de
    -- auditoria externa GATE 4: a versão anterior desta Query só
    -- provava confdeltype, deixando confupdtype não verificado.
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'public.pokemon_generation'::regclass
          AND contype = 'f' AND confrelid = 'public.pokemon_region'::regclass
          AND confupdtype = 'r'
          AND confdeltype = 'r'
    ) THEN
        RAISE EXCEPTION 'FAIL 1.4.3: FK pokemon_generation.main_region_id ausente, ou sem ON UPDATE RESTRICT + ON DELETE RESTRICT simultaneamente';
    END IF;
    RAISE NOTICE 'PASS 1.4.3: FK pokemon_generation.main_region_id confirmada com ON UPDATE RESTRICT E ON DELETE RESTRICT (confupdtype=r, confdeltype=r)';
    RAISE NOTICE 'PASS 1.4: as 3 FKs existem com ON DELETE (e, para main_region_id, também ON UPDATE) correto';

    -- 1.5 UNIQUE constraints (escopadas por conrelid, nunca só por conname)
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'uq_pokemon_region_code' AND conrelid = 'public.pokemon_region'::regclass
    ) THEN
        RAISE EXCEPTION 'FAIL 1.5.1: uq_pokemon_region_code ausente em public.pokemon_region';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'uq_pokemon_region_external_reference_region_source' AND conrelid = 'public.pokemon_region_external_reference'::regclass
    ) THEN
        RAISE EXCEPTION 'FAIL 1.5.2: uq_pokemon_region_external_reference_region_source ausente em public.pokemon_region_external_reference';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'uq_pokemon_region_external_reference_source_external' AND conrelid = 'public.pokemon_region_external_reference'::regclass
    ) THEN
        RAISE EXCEPTION 'FAIL 1.5.3: uq_pokemon_region_external_reference_source_external ausente em public.pokemon_region_external_reference';
    END IF;
    -- Negativo: NÃO deve existir nenhuma UNIQUE cobrindo main_region_id
    -- em pokemon_generation (decisão congelada — cardinalidade N:1,
    -- unicidade reversa NÃO é invariante de domínio).
    IF EXISTS (
        SELECT 1 FROM pg_constraint c
        WHERE c.conrelid = 'public.pokemon_generation'::regclass
          AND c.contype = 'u'
          AND EXISTS (
              SELECT 1 FROM unnest(c.conkey) AS colnum
              WHERE colnum = (
                  SELECT attnum FROM pg_attribute
                  WHERE attrelid = 'public.pokemon_generation'::regclass
                    AND attname = 'main_region_id'
              )
          )
    ) THEN
        RAISE EXCEPTION 'FAIL 1.5.4: existe UNIQUE envolvendo pokemon_generation.main_region_id — proibido por decisão congelada (N:1)';
    END IF;
    RAISE NOTICE 'PASS 1.5: as 3 UNIQUE esperadas existem, cada uma na tabela correta; nenhuma UNIQUE em main_region_id';

    -- 1.6 CHECK constraints — TODOS, não apenas amostra (achado de
    -- auditoria externa GATE 4: a versão anterior desta Query validava
    -- só 2 dos 5 CHECKs criados por 6060/6070). Cada um escopado por
    -- conrelid, nunca só por conname.
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'ck_pokemon_region_code_format' AND conrelid = 'public.pokemon_region'::regclass
    ) THEN
        RAISE EXCEPTION 'FAIL 1.6.1: ck_pokemon_region_code_format ausente em public.pokemon_region';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'ck_pokemon_region_canonical_name_not_blank' AND conrelid = 'public.pokemon_region'::regclass
    ) THEN
        RAISE EXCEPTION 'FAIL 1.6.2: ck_pokemon_region_canonical_name_not_blank ausente em public.pokemon_region';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'ck_pokemon_region_external_reference_external_id_not_blank' AND conrelid = 'public.pokemon_region_external_reference'::regclass
    ) THEN
        RAISE EXCEPTION 'FAIL 1.6.3: ck_pokemon_region_external_reference_external_id_not_blank ausente em public.pokemon_region_external_reference';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'ck_pokemon_region_external_reference_source_url' AND conrelid = 'public.pokemon_region_external_reference'::regclass
    ) THEN
        RAISE EXCEPTION 'FAIL 1.6.4: ck_pokemon_region_external_reference_source_url ausente em public.pokemon_region_external_reference';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'ck_pokemon_region_external_reference_metadata' AND conrelid = 'public.pokemon_region_external_reference'::regclass
    ) THEN
        RAISE EXCEPTION 'FAIL 1.6.5: ck_pokemon_region_external_reference_metadata ausente em public.pokemon_region_external_reference';
    END IF;
    RAISE NOTICE 'PASS 1.6: os 5 CHECK constraints existem (2 em pokemon_region, 3 em pokemon_region_external_reference), cada um na tabela correta — cobertura completa, não amostra';

    -- 1.7 Índices — nenhum além de PK/UNIQUE nas 2 tabelas novas; e
    -- nenhum índice cobrindo main_region_id em pokemon_generation
    -- (tabela pequena, mesmo raciocínio já aplicado a pokemon_generation/
    -- pokedex — sem índice especulativo).
    SELECT COUNT(*) INTO v_count
    FROM pg_indexes
    WHERE schemaname = 'public'
      AND tablename IN ('pokemon_region', 'pokemon_region_external_reference');
    -- Esperado: 1 (PK) + 1 (UNIQUE code) = 2 para pokemon_region;
    --           1 (PK) + 2 (UNIQUE) = 3 para pokemon_region_external_reference; total = 5
    IF v_count <> 5 THEN
        RAISE EXCEPTION 'FAIL 1.7.1: número de índices inesperado nas 2 tabelas novas (esperado 5, obtido %) — investigar índice especulativo não previsto', v_count;
    END IF;
    IF EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE schemaname = 'public' AND tablename = 'pokemon_generation'
          AND indexdef ILIKE '%main_region_id%'
    ) THEN
        RAISE EXCEPTION 'FAIL 1.7.2: existe índice cobrindo main_region_id em pokemon_generation — proibido nesta rodada (decisão explícita, volume desproporcional)';
    END IF;
    RAISE NOTICE 'PASS 1.7: exatamente 5 índices nas 2 tabelas novas (somente PK/UNIQUE); nenhum índice em main_region_id';

    -- 1.8 Triggers ativos (tgenabled = 'O')
    IF (SELECT COUNT(*) FROM pg_trigger WHERE tgrelid = 'public.pokemon_region'::regclass AND tgenabled = 'O' AND NOT tgisinternal) <> 3 THEN
        RAISE EXCEPTION 'FAIL 1.8.1: pokemon_region deveria ter 3 triggers ativos';
    END IF;
    IF (SELECT COUNT(*) FROM pg_trigger WHERE tgrelid = 'public.pokemon_region_external_reference'::regclass AND tgenabled = 'O' AND NOT tgisinternal) <> 3 THEN
        RAISE EXCEPTION 'FAIL 1.8.2: pokemon_region_external_reference deveria ter 3 triggers ativos';
    END IF;
    RAISE NOTICE 'PASS 1.8: triggers ativos conferidos (3/3)';

    -- 1.9 RLS habilitado, zero policy
    IF NOT EXISTS (SELECT 1 FROM pg_class WHERE oid = 'public.pokemon_region'::regclass AND relrowsecurity) THEN
        RAISE EXCEPTION 'FAIL 1.9.1: RLS não habilitado em pokemon_region';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_class WHERE oid = 'public.pokemon_region_external_reference'::regclass AND relrowsecurity) THEN
        RAISE EXCEPTION 'FAIL 1.9.2: RLS não habilitado em pokemon_region_external_reference';
    END IF;
    IF EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename IN ('pokemon_region', 'pokemon_region_external_reference')
    ) THEN
        RAISE EXCEPTION 'FAIL 1.9.3: existe policy nas 2 tabelas novas — deveria ser zero nesta rodada';
    END IF;
    RAISE NOTICE 'PASS 1.9: RLS habilitado, zero policy nas 2 tabelas novas';

    -- 1.10 Zero GRANT catalogado em information_schema.role_table_grants
    -- (checagem preliminar — prova definitiva via has_table_privilege()
    -- logo abaixo).
    IF EXISTS (
        SELECT 1 FROM information_schema.role_table_grants
        WHERE table_schema = 'public'
          AND table_name IN ('pokemon_region', 'pokemon_region_external_reference')
          AND grantee IN ('anon', 'authenticated')
    ) THEN
        RAISE EXCEPTION 'FAIL 1.10.0: existe GRANT catalogado em role_table_grants para anon/authenticated nas 2 tabelas novas';
    END IF;
    RAISE NOTICE 'PASS 1.10.0: nenhum GRANT catalogado em role_table_grants (checagem preliminar)';
END;
$$;

-- ---------------------------------------------------------------------
-- 1.10 (prova definitiva) — has_table_privilege() por role/tabela/
-- privilégio, cobrindo exatamente os privilégios proibidos pelo
-- STD-001/Query 2147 (TRUNCATE/REFERENCES/TRIGGER/MAINTAIN) mais os de
-- dado (SELECT/INSERT/UPDATE/DELETE, bloqueados por RLS sem policy).
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_role TEXT;
    v_table TEXT;
    v_priv TEXT;
    v_roles TEXT[] := ARRAY['anon', 'authenticated'];
    v_tables TEXT[] := ARRAY['pokemon_region', 'pokemon_region_external_reference'];
    v_privs TEXT[] := ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER', 'MAINTAIN'];
BEGIN
    FOREACH v_role IN ARRAY v_roles LOOP
        FOREACH v_table IN ARRAY v_tables LOOP
            FOREACH v_priv IN ARRAY v_privs LOOP
                IF has_table_privilege(v_role, ('public.' || v_table)::regclass, v_priv) THEN
                    RAISE EXCEPTION 'FAIL 1.10: % tem privilégio EFETIVO % em public.% (has_table_privilege)', v_role, v_priv, v_table;
                END IF;
            END LOOP;
        END LOOP;
    END LOOP;

    RAISE NOTICE 'PASS 1.10: has_table_privilege() confirma ZERO privilégio efetivo para anon/authenticated nas 2 tabelas novas';
END;
$$;

-- ---------------------------------------------------------------------
-- 1.11 (prova definitiva) — service_role continua SEM nenhum privilégio
-- de DML (SELECT/INSERT/UPDATE/DELETE) em pokemon_region,
-- pokemon_region_external_reference E pokemon_generation (achado de
-- auditoria externa GATE 4 — a versão anterior desta Query não provava
-- nada sobre service_role). Deliberadamente NÃO exige ausência de
-- REFERENCES/TRIGGER/TRUNCATE/MAINTAIN para service_role: esse role já
-- possui esses privilégios nas 6 tabelas Pokémon/Pokédex existentes
-- (confirmado por consulta real a role_table_grants na rodada de
-- modelagem física, POKEMON-REGION-FOUNDATION-PHYSICAL-MODELING-01) —
-- via default ACL da plataforma, nunca concedido explicitamente por
-- nenhuma Query deste módulo, e este script não altera nem depende
-- disso. O que é preservado e provado aqui é exclusivamente a ausência
-- de DML direto, que é o invariante de segurança real do módulo (todo
-- acesso a dado passa por função administrativa ou RLS, nunca por
-- privilégio de tabela direto de service_role).
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_table TEXT;
    v_priv  TEXT;
    v_tables TEXT[] := ARRAY['pokemon_region', 'pokemon_region_external_reference', 'pokemon_generation'];
    v_privs  TEXT[] := ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE'];
BEGIN
    FOREACH v_table IN ARRAY v_tables LOOP
        FOREACH v_priv IN ARRAY v_privs LOOP
            IF has_table_privilege('service_role', ('public.' || v_table)::regclass, v_priv) THEN
                RAISE EXCEPTION 'FAIL 1.11: service_role tem privilégio EFETIVO % em public.% (has_table_privilege) — divergência do padrão vigente de zero DML direto', v_priv, v_table;
            END IF;
        END LOOP;
    END LOOP;

    RAISE NOTICE 'PASS 1.11: has_table_privilege() confirma ZERO privilégio de DML (SELECT/INSERT/UPDATE/DELETE) para service_role em pokemon_region, pokemon_region_external_reference e pokemon_generation — padrão vigente preservado, nenhum GRANT novo introduzido';
    RAISE NOTICE '=== SEÇÃO 1 (ESTRUTURAL) — TODOS OS ITENS PASS ===';
END;
$$;

-- ===================================================================
-- SEÇÃO 2 — VALIDAÇÃO COMPORTAMENTAL (transacional, zero resíduo)
-- ===================================================================
BEGIN;

DO $$
DECLARE
    v_asset_source_id           UUID;
    v_fixture_asset_source_id   UUID;
    v_fixture_source_order      INTEGER;
    v_region_1                  UUID;
    v_region_2                  UUID;
    v_region_3                  UUID;
    v_region_4                  UUID;
    v_ext_ref_id                UUID;
    v_generation_id              UUID;
    v_generation_id_2             UUID;
    v_code                       TEXT;
    v_name                       TEXT;
    v_external_id                TEXT;
    v_count                      INTEGER;
    v_constraint_name            TEXT;
BEGIN
    SELECT id INTO v_asset_source_id FROM public.asset_source WHERE code = 'POKEAPI';
    IF v_asset_source_id IS NULL THEN
        RAISE EXCEPTION 'FIXTURE_FAILED: linha POKEAPI ausente em asset_source (Query 6700 não aplicada?)';
    END IF;

    -- Fonte externa sintética dedicada exclusivamente à prova isolada
    -- de RESTRICT (2.2.6) — nunca a linha real POKEAPI, que também é
    -- referenciada por outras tabelas do módulo. source_order calculado
    -- deterministicamente a partir do estado corrente da própria
    -- transação (achado de auditoria externa GATE 4: a versão anterior
    -- fixava 999999, que deixaria de ser livre se algum dia existir
    -- essa quantidade real de linhas em asset_source) — nunca toca a
    -- linha real POKEAPI nem depende de nenhum valor mágico permanecer
    -- livre para sempre.
    SELECT COALESCE(MAX(source_order), 0) + 1 INTO v_fixture_source_order FROM public.asset_source;

    INSERT INTO public.asset_source (code, name, source_type, source_order)
    VALUES ('ZZZ_VALIDATION_REGION_SOURCE', 'Validation Fixture Source (Region)', 'MANUAL', v_fixture_source_order)
    RETURNING id INTO v_fixture_asset_source_id;

    -- ------------------------------------------------------------
    -- 2.1 — pokemon_region
    -- ------------------------------------------------------------
    INSERT INTO public.pokemon_region (code, canonical_name)
    VALUES ('  zzz_validation_region  ', '  Região de Validação  ')
    RETURNING id, code, canonical_name INTO v_region_1, v_code, v_name;

    IF v_code <> 'ZZZ_VALIDATION_REGION' THEN
        RAISE EXCEPTION 'FAIL 2.1.1: normalize_pokemon_region não converteu code (obtido: %)', v_code;
    END IF;
    IF v_name <> 'Região de Validação' THEN
        RAISE EXCEPTION 'FAIL 2.1.2: normalize_pokemon_region não fez trim de canonical_name (obtido: %)', v_name;
    END IF;
    RAISE NOTICE 'PASS 2.1.1/2.1.2: normalize_pokemon_region (code=%, canonical_name=%)', v_code, v_name;

    BEGIN
        INSERT INTO public.pokemon_region (code, canonical_name) VALUES ('ZZZ_VALIDATION_REGION', 'Duplicata');
        RAISE EXCEPTION 'FAIL 2.1.3: duplicidade de pokemon_region.code não foi rejeitada';
    EXCEPTION
        WHEN unique_violation THEN
            RAISE NOTICE 'PASS 2.1.3: duplicidade de pokemon_region.code rejeitada';
    END;

    BEGIN
        UPDATE public.pokemon_region SET code = 'OUTRO' WHERE id = v_region_1;
        RAISE EXCEPTION 'FAIL 2.1.4: UPDATE em pokemon_region.code não foi rejeitado';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLERRM <> 'POKEMON_REGION_CODE_IMMUTABLE' THEN
                RAISE EXCEPTION 'FAIL 2.1.4: exceção inesperada: %', SQLERRM;
            END IF;
            RAISE NOTICE 'PASS 2.1.4: UPDATE em pokemon_region.code rejeitado (POKEMON_REGION_CODE_IMMUTABLE)';
    END;

    BEGIN
        UPDATE public.pokemon_region SET id = gen_random_uuid() WHERE id = v_region_1;
        RAISE EXCEPTION 'FAIL 2.1.5: UPDATE em pokemon_region.id não foi rejeitado';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLERRM <> 'POKEMON_REGION_ID_IMMUTABLE' THEN
                RAISE EXCEPTION 'FAIL 2.1.5: exceção inesperada: %', SQLERRM;
            END IF;
            RAISE NOTICE 'PASS 2.1.5: UPDATE em pokemon_region.id rejeitado (POKEMON_REGION_ID_IMMUTABLE)';
    END;

    UPDATE public.pokemon_region SET canonical_name = 'Região de Validação (corrigido)', is_active = FALSE
    WHERE id = v_region_1;
    SELECT canonical_name INTO v_name FROM public.pokemon_region WHERE id = v_region_1;
    IF v_name <> 'Região de Validação (corrigido)' THEN
        RAISE EXCEPTION 'FAIL 2.1.6: canonical_name não foi corrigível';
    END IF;
    RAISE NOTICE 'PASS 2.1.6: canonical_name/is_active corrigíveis administrativamente';

    -- Segunda região, isolada, para os testes de UNIQUE cruzada de
    -- pokemon_region_external_reference (mesmo padrão de v_pokedex_id_2
    -- em 6800).
    INSERT INTO public.pokemon_region (code, canonical_name)
    VALUES ('ZZZ_VALIDATION_REGION_2', 'Região de Validação 2')
    RETURNING id INTO v_region_2;

    -- ------------------------------------------------------------
    -- 2.2 — pokemon_region_external_reference
    -- ------------------------------------------------------------
    INSERT INTO public.pokemon_region_external_reference (pokemon_region_id, asset_source_id, external_region_id, source_url, metadata)
    VALUES (v_region_1, v_asset_source_id, '  1  ', 'https://pokeapi.co/api/v2/region/1/', '{"name": "kanto"}'::jsonb)
    RETURNING id, external_region_id INTO v_ext_ref_id, v_external_id;

    IF v_external_id <> '1' THEN
        RAISE EXCEPTION 'FAIL 2.2.1: normalize_pokemon_region_external_reference não fez trim de external_region_id (obtido: %)', v_external_id;
    END IF;
    RAISE NOTICE 'PASS 2.2.1: insert + normalize pokemon_region_external_reference válido (id=%)', v_ext_ref_id;

    BEGIN
        INSERT INTO public.pokemon_region_external_reference (pokemon_region_id, asset_source_id, external_region_id)
        VALUES (v_region_1, v_asset_source_id, '2');
        RAISE EXCEPTION 'FAIL 2.2.2: UNIQUE(pokemon_region_id, asset_source_id) não foi rejeitada';
    EXCEPTION
        WHEN unique_violation THEN
            RAISE NOTICE 'PASS 2.2.2: UNIQUE(pokemon_region_id, asset_source_id) rejeitada';
    END;

    -- UNIQUE(asset_source_id, external_region_id) isolado do UNIQUE
    -- anterior: usa a SEGUNDA região, mesmo asset_source e mesmo
    -- external_region_id já usado acima.
    BEGIN
        INSERT INTO public.pokemon_region_external_reference (pokemon_region_id, asset_source_id, external_region_id)
        VALUES (v_region_2, v_asset_source_id, '1');
        RAISE EXCEPTION 'FAIL 2.2.3: UNIQUE(asset_source_id, external_region_id) não foi rejeitada';
    EXCEPTION
        WHEN unique_violation THEN
            RAISE NOTICE 'PASS 2.2.3: UNIQUE(asset_source_id, external_region_id) rejeitada (região diferente, mesmo external_id)';
    END;

    -- Isolado das duas UNIQUE: v_region_2 ainda não tem nenhuma linha
    -- persistida (a tentativa anterior, 2.2.3, falhou e reverteu) com
    -- um external_region_id inédito ('3'), garantindo que metadata=[]
    -- seja a ÚNICA regra violada por este INSERT.
    BEGIN
        INSERT INTO public.pokemon_region_external_reference (pokemon_region_id, asset_source_id, external_region_id, metadata)
        VALUES (v_region_2, v_asset_source_id, '3', '[]'::jsonb);
        RAISE EXCEPTION 'FAIL 2.2.4: CHECK metadata objeto não foi rejeitado';
    EXCEPTION
        WHEN check_violation THEN
            RAISE NOTICE 'PASS 2.2.4: CHECK metadata (deve ser objeto JSONB) rejeitado para array — nenhuma UNIQUE envolvida';
        WHEN unique_violation THEN
            RAISE EXCEPTION 'FAIL 2.2.4: violação inesperada de UNIQUE em vez de CHECK — combinação não estava isolada como esperado';
    END;

    BEGIN
        UPDATE public.pokemon_region_external_reference SET external_region_id = '2' WHERE id = v_ext_ref_id;
        RAISE EXCEPTION 'FAIL 2.2.5: UPDATE em external_region_id não foi rejeitado';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLERRM <> 'POKEMON_REGION_EXTERNAL_REFERENCE_EXTERNAL_ID_IMMUTABLE' THEN
                RAISE EXCEPTION 'FAIL 2.2.5: exceção inesperada: %', SQLERRM;
            END IF;
            RAISE NOTICE 'PASS 2.2.5: UPDATE em external_region_id rejeitado (imutável)';
    END;

    -- RESTRICT: prova ISOLADA da FK nova (pokemon_region_external_
    -- reference.asset_source_id) — usa a fonte sintética
    -- v_fixture_asset_source_id (referenciada exclusivamente por uma
    -- linha criada só para este teste) e confirma via GET STACKED
    -- DIAGNOSTICS que o nome da constraint violada é especificamente o
    -- da FK nova.
    INSERT INTO public.pokemon_region_external_reference (pokemon_region_id, asset_source_id, external_region_id)
    VALUES (v_region_1, v_fixture_asset_source_id, 'FIXTURE_ONLY_REF');

    BEGIN
        DELETE FROM public.asset_source WHERE id = v_fixture_asset_source_id;
        RAISE EXCEPTION 'FAIL 2.2.6: DELETE em asset_source (fixture, referenciada só por pokemon_region_external_reference) não foi bloqueado';
    EXCEPTION
        WHEN foreign_key_violation THEN
            GET STACKED DIAGNOSTICS v_constraint_name = CONSTRAINT_NAME;
            IF v_constraint_name <> 'pokemon_region_external_reference_asset_source_id_fkey' THEN
                RAISE EXCEPTION 'FAIL 2.2.6: foreign_key_violation veio de constraint inesperada (%), não da FK nova desta rodada', v_constraint_name;
            END IF;
            RAISE NOTICE 'PASS 2.2.6: DELETE em asset_source referenciado bloqueado especificamente pela FK pokemon_region_external_reference_asset_source_id_fkey (ON DELETE RESTRICT), confirmado via GET STACKED DIAGNOSTICS';
    END;

    -- ------------------------------------------------------------
    -- 2.3 — CASCADE: excluir a região remove sua External Reference
    -- ------------------------------------------------------------
    DELETE FROM public.pokemon_region WHERE id = v_region_1;

    SELECT COUNT(*) INTO v_count FROM public.pokemon_region_external_reference WHERE pokemon_region_id = v_region_1;
    IF v_count <> 0 THEN
        RAISE EXCEPTION 'FAIL 2.3.1: pokemon_region_external_reference não foi removida em CASCADE (restam %)', v_count;
    END IF;
    RAISE NOTICE 'PASS 2.3.1: ON DELETE CASCADE confirmado (pokemon_region_external_reference removida com a Região)';

    -- ------------------------------------------------------------
    -- 2.4 — pokemon_generation.main_region_id (Query 6080)
    -- ------------------------------------------------------------
    -- Duas novas regiões, isoladas das já excluídas acima, dedicadas
    -- aos testes de main_region_id (inicial e reatribuição).
    INSERT INTO public.pokemon_region (code, canonical_name)
    VALUES ('ZZZ_VALIDATION_REGION_3', 'Região de Validação 3')
    RETURNING id INTO v_region_3;

    INSERT INTO public.pokemon_region (code, canonical_name)
    VALUES ('ZZZ_VALIDATION_REGION_4', 'Região de Validação 4')
    RETURNING id INTO v_region_4;

    -- NOT NULL: inserir Generation sem main_region_id deve falhar.
    BEGIN
        INSERT INTO public.pokemon_generation (code, canonical_name, ordinal_number)
        VALUES ('ZZZ_VALIDATION_GENERATION_NO_REGION', 'Validation Fixture Generation (sem região)', 999996);
        RAISE EXCEPTION 'FAIL 2.4.1: INSERT em pokemon_generation sem main_region_id não foi rejeitado';
    EXCEPTION
        WHEN not_null_violation THEN
            RAISE NOTICE 'PASS 2.4.1: NOT NULL de main_region_id rejeitado corretamente';
    END;

    -- Insert válido com main_region_id = v_region_3.
    INSERT INTO public.pokemon_generation (code, canonical_name, ordinal_number, main_region_id)
    VALUES ('ZZZ_VALIDATION_GENERATION', 'Validation Fixture Generation', 999999, v_region_3)
    RETURNING id INTO v_generation_id;
    RAISE NOTICE 'PASS 2.4.2: insert pokemon_generation com main_region_id válido (id=%)', v_generation_id;

    -- N:1 comportamental (achado de auditoria externa GATE 4): uma
    -- SEGUNDA Generation distinta (code e ordinal_number diferentes)
    -- apontando para a MESMA Region deve inserir com sucesso — prova
    -- de que não há nenhuma UNIQUE/constraint 1:1 escondida sobre
    -- main_region_id, além da ausência estrutural já confirmada em
    -- 1.5.4.
    INSERT INTO public.pokemon_generation (code, canonical_name, ordinal_number, main_region_id)
    VALUES ('ZZZ_VALIDATION_GENERATION_2', 'Validation Fixture Generation 2', 999998, v_region_3)
    RETURNING id INTO v_generation_id_2;
    RAISE NOTICE 'PASS 2.4.3: segunda Generation distinta (code/ordinal_number diferentes) com o MESMO main_region_id inserida com sucesso (id=%) — confirma N:1, nenhuma constraint 1:1 escondida', v_generation_id_2;

    -- RESTRICT: excluir a Região referenciada como main_region_id deve
    -- ser bloqueado enquanto QUALQUER Generation ainda a referencia
    -- (agora duas: v_generation_id e v_generation_id_2).
    BEGIN
        DELETE FROM public.pokemon_region WHERE id = v_region_3;
        RAISE EXCEPTION 'FAIL 2.4.4: DELETE em pokemon_region referenciada por main_region_id não foi bloqueado';
    EXCEPTION
        WHEN foreign_key_violation THEN
            GET STACKED DIAGNOSTICS v_constraint_name = CONSTRAINT_NAME;
            IF v_constraint_name <> 'pokemon_generation_main_region_id_fkey' THEN
                RAISE EXCEPTION 'FAIL 2.4.4: foreign_key_violation veio de constraint inesperada (%), não da FK main_region_id', v_constraint_name;
            END IF;
            RAISE NOTICE 'PASS 2.4.4: DELETE em pokemon_region referenciada por main_region_id bloqueado (ON DELETE RESTRICT), confirmado via GET STACKED DIAGNOSTICS';
    END;

    -- Correção administrativa: main_region_id É corrigível a nível de
    -- banco (decisão congelada POKEMON-REGION-FOUNDATION-PHYSICAL-
    -- MODELING-01 — proteção contra divergência não intencional vive na
    -- camada de sourcing/reconciliação, não em trigger de imutabilidade
    -- de govern_pokemon_generation(), Query 6001, não reescrita).
    UPDATE public.pokemon_generation SET main_region_id = v_region_4 WHERE id = v_generation_id;
    SELECT main_region_id INTO v_region_1 FROM public.pokemon_generation WHERE id = v_generation_id; -- reuso de v_region_1 só como variável de leitura
    IF v_region_1 <> v_region_4 THEN
        RAISE EXCEPTION 'FAIL 2.4.5: main_region_id não foi corrigível administrativamente';
    END IF;
    RAISE NOTICE 'PASS 2.4.5: main_region_id corrigível administrativamente (sem trigger de imutabilidade, decisão congelada)';

    -- Reatribui também a segunda Generation, para que v_region_3 fique
    -- sem nenhuma referência antes da prova final de DELETE permitido
    -- abaixo (isolamento — não é uma nova regra testada, apenas limpeza
    -- necessária para que a próxima asserção prove exatamente "sem
    -- referência = DELETE permitido", não uma mistura de estados).
    UPDATE public.pokemon_generation SET main_region_id = v_region_4 WHERE id = v_generation_id_2;

    -- Após a reatribuição de AMBAS as Generations, v_region_3 não é
    -- mais referenciada por nenhuma — a exclusão agora deve ser
    -- permitida (prova complementar de que o bloqueio anterior era
    -- especificamente por referência ativa, não por qualquer outra
    -- razão).
    DELETE FROM public.pokemon_region WHERE id = v_region_3;
    RAISE NOTICE 'PASS 2.4.6: DELETE em pokemon_region permitido após main_region_id de todas as Generations ser reatribuído (região não mais referenciada)';

    RAISE NOTICE '=== SEÇÃO 2 (COMPORTAMENTAL) — TODOS OS ITENS PASS ===';
END;
$$;

-- Zero resíduo: reverte TODA a fixture (regiões/asset_source/external_
-- reference/generation sintéticos). Nenhuma linha real do banco
-- (incluindo a linha POKEAPI de asset_source, nunca excluída nesta
-- versão) é alterada de forma permanente.
ROLLBACK;

-- ===================================================================
-- SEÇÃO 3 — PRIVILÉGIOS DE FUNÇÃO (EXECUTE, leitura pura, sem mutação)
-- ===================================================================
DO $$
DECLARE
    v_fn TEXT;
    v_functions TEXT[] := ARRAY[
        'normalize_pokemon_region', 'govern_pokemon_region', 'touch_pokemon_region_updated_at',
        'normalize_pokemon_region_external_reference', 'govern_pokemon_region_external_reference',
        'touch_pokemon_region_external_reference_updated_at'
    ];
BEGIN
    IF array_length(v_functions, 1) <> 6 THEN
        RAISE EXCEPTION 'FAIL 3.0: lista de funções esperadas não tem 6 elementos';
    END IF;

    FOREACH v_fn IN ARRAY v_functions LOOP
        IF has_function_privilege('anon', ('public.' || v_fn || '()')::regprocedure, 'EXECUTE') THEN
            RAISE EXCEPTION 'FAIL 3.1: anon ainda tem EXECUTE em public.%()', v_fn;
        END IF;
        IF has_function_privilege('authenticated', ('public.' || v_fn || '()')::regprocedure, 'EXECUTE') THEN
            RAISE EXCEPTION 'FAIL 3.2: authenticated ainda tem EXECUTE em public.%()', v_fn;
        END IF;
    END LOOP;

    RAISE NOTICE '=== SEÇÃO 3 (PRIVILÉGIOS) — as 6 trigger functions sem EXECUTE para anon/authenticated: PASS ===';
END;
$$;

-- ===================================================================
-- SEÇÃO 4 — PERFORMANCE (proporcional ao volume/risco desta rodada)
-- ===================================================================
-- Nota: volume esperado é de 11 linhas em pokemon_region (todas as
-- Regiões da PokéAPI) e de até ~9 linhas em pokemon_generation
-- referenciando main_region_id — ambas ordens de grandeza muito abaixo
-- do que já justificou benchmark de carga em outras Fatias do projeto
-- (ex.: Master Set Scope, Query 5813, >= 20 mil linhas sintéticas).
-- pokemon_region_external_reference tem o mesmo teto superior de
-- pokemon_region (uma linha por Região por Fonte). Nenhum EXPLAIN
-- ANALYZE contra dado sintético em massa foi preparado aqui, por
-- decisão explícita de não antecipar validação desproporcional ao
-- risco real — mesmo raciocínio já aplicado em 6800, Seção 4, para a
-- Fatia A (Pokédex Foundation). Caso o volume real divirja desta
-- expectativa após o sourcing (hoje SUSPENSO), uma validação de
-- performance própria deve ser criada como Query nova.

-- ===================================================================
-- FIM — CONFIRMADO EXECUTADO (2026-09-04, via apply_migration/MCP do
-- Supabase, projeto qjfutqujxrbzgrtkpgkg, POKEMON-REGION-FOUNDATION-
-- PHYSICAL-IMPLEMENTATION-01). Resultado: PASS em todas as Seções 1-4
-- (RAISE NOTICE não é observável pelas ferramentas de execução MCP
-- usadas nesta rodada — cada assertion foi re-derivada de forma
-- independente e observável via SELECT/has_table_privilege()/
-- has_function_privilege(), e via função pg_temp para a prova
-- comportamental de N:1, "Nenhum PASS inferido: reportar somente
-- saída realmente observada"). Postcheck independente adicional em
-- GATE 8 (POKEMON-REGION-FOUNDATION-CANONICAL-PROMOTION-01) confirmou
-- zero resíduo (fixtures ZZZ_VALIDATION_%/asset_source sintético = 0,
-- pokemon_region/pokemon_region_external_reference/pokemon_generation
-- ainda com zero linhas — sourcing permanece SUSPENSO). Este arquivo
-- permanece em database/proposals/2026-09-04-pokemon-region-
-- foundation/ como evidência histórica de validação — não promovido
-- para database/schema/, mesmo padrão já adotado para 6800 (Validate
-- Pokedex Foundation), precedente COLLECTIONS-POKEDEX-POSITION-
-- PHYSICAL-CANONICAL-PROMOTION-01. Corpo da Seção 1/2/3/4 permanece
-- v1.1, não reescrito nesta promoção.
-- ===================================================================
