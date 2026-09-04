/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 6800 - Validate Pokedex Foundation
Versão......: 1.1 (revisão: has_table_privilege, isolamento de
               2.3.4/2.3.6, conrelid em 1.5/1.6)
Status......: CONFIRMADO EXECUTADO — resultado PASS. Mantida em
               database/proposals/ como evidência histórica de
               validação (NÃO promovida para database/schema/,
               conforme COLLECTIONS-POKEDEX-POSITION-PHYSICAL-
               CANONICAL-PROMOTION-01 — este script valida a Fatia A
               no momento da implementação, não é estrutura
               persistente do módulo).
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-04 (staging em COLLECTIONS-POKEDEX-POSITION-
               PHYSICAL-STAGING-01/-REVISION-01; executada em
               2026-09-04 via COLLECTIONS-POKEDEX-POSITION-PHYSICAL-
               IMPLEMENTATION-01, contra o projeto Supabase
               qjfutqujxrbzgrtkpgkg)

Descrição...:
Script de validação da Fatia A ("Canonical Pokédex Foundation":
pokedex, pokedex_position, pokedex_external_reference — Queries
6030/6031/6040/6041/6050/6051). Executado integralmente em 2026-09-04,
após as seis Queries de estrutura acima terem sido de fato aplicadas
ao banco real — todas as asserções (Seção 1 estrutural, Seção 2
comportamental, Seção 3 privilégios de função) resultaram PASS, sem
nenhum FAIL. Zero resíduo confirmado após o ROLLBACK da Seção 2 e por
contagem direta pós-execução (as 3 tabelas e toda a fixture sintética
voltaram a zero linhas). Ver Entrega de
COLLECTIONS-POKEDEX-POSITION-PHYSICAL-IMPLEMENTATION-01 na conversa
para o relatório completo de execução. A lógica de validação abaixo
(estrutura das asserções, casos de teste, fixtures) permanece
inalterada em relação à v1.1 auditada — esta atualização de cabeçalho
registra apenas o resultado da execução real, sem reabrir a
modelagem.

Cobre, nesta ordem:
1. Validação estrutural (tabelas, colunas-chave, PK, FKs com
   ON DELETE correto, UNIQUE, CHECK, índices, triggers ativos, RLS
   habilitado, zero policy, zero grant direto a anon/authenticated).
2. Validação comportamental, transacional (BEGIN...ROLLBACK — dados de
   fixture sintéticos, nenhum resíduo real após a execução): normalização,
   unicidade, CHECK, imutabilidade, correção editorial, comportamento
   de ON DELETE CASCADE/RESTRICT.
3. Privilégios de função (EXECUTE das 8 trigger functions novas,
   esperado FALSE para anon/authenticated).
4. Performance (proporcional ao volume/risco real desta Fatia — ver
   nota na própria Seção 4, sem benchmark de carga sintética).

Segue o mesmo padrão de "número de diário" já usado nos módulos
Collections/Pricing/Pesquisa de Cartas (STD-001, Seção 10) — os testes
que verificam rejeição usam bloco BEGIN...EXCEPTION do próprio
PL/pgSQL (subtransação implícita), nunca abortando a transação externa,
que é sempre revertida ao final (ROLLBACK), garantindo zero resíduo
mesmo em execução real.

Pré-requisitos:
- Queries 6030, 6031, 6040, 6041, 6050, 6051 (todas CONFIRMADO
  EXECUTADO no banco real).
- Query 6700 (linha POKEAPI em asset_source, já CONFIRMADO EXECUTADO).

Nota de revisão (2026-09-04, achado de auditoria externa,
COLLECTIONS-POKEDEX-POSITION-PHYSICAL-STAGING-REVISION-01): versão
1.0 corrigida em 4 pontos antes de qualquer execução real — (a) 1.10
passa a provar privilégio EFETIVO via has_table_privilege() (SELECT/
INSERT/UPDATE/DELETE/TRUNCATE/REFERENCES/TRIGGER/MAINTAIN), não só
GRANT catalogado; (b) 2.3.4 isolado para violar exclusivamente o CHECK
de metadata, sem colidir com nenhuma UNIQUE; (c) 2.3.6 isolado com
fonte externa sintética dedicada + GET STACKED DIAGNOSTICS, provando
especificamente a FK nova de pokedex_external_reference, nunca
aceitando qualquer FK de asset_source como PASS; (d) 1.5/1.6 escopadas
por conrelid, não só conname. Nenhuma mudança de modelagem — apenas
precisão de prova.
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
    IF to_regclass('public.pokedex') IS NULL THEN
        RAISE EXCEPTION 'FAIL 1.1.1: public.pokedex não existe';
    END IF;
    IF to_regclass('public.pokedex_position') IS NULL THEN
        RAISE EXCEPTION 'FAIL 1.1.2: public.pokedex_position não existe';
    END IF;
    IF to_regclass('public.pokedex_external_reference') IS NULL THEN
        RAISE EXCEPTION 'FAIL 1.1.3: public.pokedex_external_reference não existe';
    END IF;
    RAISE NOTICE 'PASS 1.1: as 3 tabelas existem';

    -- 1.2 Colunas-chave e NOT NULL (spot check)
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'pokedex'
          AND column_name = 'code' AND is_nullable = 'NO'
    ) THEN
        RAISE EXCEPTION 'FAIL 1.2.1: pokedex.code ausente ou nullable';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'pokedex_position'
          AND column_name = 'position_number' AND is_nullable = 'NO'
          AND data_type = 'integer'
    ) THEN
        RAISE EXCEPTION 'FAIL 1.2.2: pokedex_position.position_number ausente/nullable/tipo errado';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'pokedex_external_reference'
          AND column_name = 'metadata' AND data_type = 'jsonb'
    ) THEN
        RAISE EXCEPTION 'FAIL 1.2.3: pokedex_external_reference.metadata ausente/tipo errado';
    END IF;
    RAISE NOTICE 'PASS 1.2: colunas-chave conferidas';

    -- 1.3 Primary Keys
    IF (SELECT COUNT(*) FROM pg_constraint WHERE conrelid = 'public.pokedex'::regclass AND contype = 'p') <> 1 THEN
        RAISE EXCEPTION 'FAIL 1.3.1: PK de pokedex ausente';
    END IF;
    IF (SELECT COUNT(*) FROM pg_constraint WHERE conrelid = 'public.pokedex_position'::regclass AND contype = 'p') <> 1 THEN
        RAISE EXCEPTION 'FAIL 1.3.2: PK de pokedex_position ausente';
    END IF;
    IF (SELECT COUNT(*) FROM pg_constraint WHERE conrelid = 'public.pokedex_external_reference'::regclass AND contype = 'p') <> 1 THEN
        RAISE EXCEPTION 'FAIL 1.3.3: PK de pokedex_external_reference ausente';
    END IF;
    RAISE NOTICE 'PASS 1.3: as 3 PKs existem';

    -- 1.4 Foreign Keys com ON DELETE correto (confdeltype: c=cascade, r=restrict)
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'public.pokedex_position'::regclass
          AND contype = 'f' AND confrelid = 'public.pokedex'::regclass
          AND confdeltype = 'c'
    ) THEN
        RAISE EXCEPTION 'FAIL 1.4.1: FK pokedex_position.pokedex_id ausente ou sem ON DELETE CASCADE';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'public.pokedex_position'::regclass
          AND contype = 'f' AND confrelid = 'public.pokemon_species'::regclass
          AND confdeltype = 'r'
    ) THEN
        RAISE EXCEPTION 'FAIL 1.4.2: FK pokedex_position.species_id ausente ou sem ON DELETE RESTRICT';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'public.pokedex_external_reference'::regclass
          AND contype = 'f' AND confrelid = 'public.pokedex'::regclass
          AND confdeltype = 'c'
    ) THEN
        RAISE EXCEPTION 'FAIL 1.4.3: FK pokedex_external_reference.pokedex_id ausente ou sem ON DELETE CASCADE';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'public.pokedex_external_reference'::regclass
          AND contype = 'f' AND confrelid = 'public.asset_source'::regclass
          AND confdeltype = 'r'
    ) THEN
        RAISE EXCEPTION 'FAIL 1.4.4: FK pokedex_external_reference.asset_source_id ausente ou sem ON DELETE RESTRICT';
    END IF;
    RAISE NOTICE 'PASS 1.4: as 4 FKs existem com ON DELETE correto';

    -- 1.5 UNIQUE constraints (escopadas por conrelid — nunca só por
    -- conname — para não aceitar falso positivo de constraint
    -- homônima pertencente a outra tabela; achado de auditoria
    -- externa, correção desta revisão)
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'uq_pokedex_code' AND conrelid = 'public.pokedex'::regclass
    ) THEN
        RAISE EXCEPTION 'FAIL 1.5.1: uq_pokedex_code ausente em public.pokedex';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'uq_pokedex_position_pokedex_species' AND conrelid = 'public.pokedex_position'::regclass
    ) THEN
        RAISE EXCEPTION 'FAIL 1.5.2: uq_pokedex_position_pokedex_species ausente em public.pokedex_position';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'uq_pokedex_position_pokedex_number' AND conrelid = 'public.pokedex_position'::regclass
    ) THEN
        RAISE EXCEPTION 'FAIL 1.5.3: uq_pokedex_position_pokedex_number ausente em public.pokedex_position';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'uq_pokedex_external_reference_pokedex_source' AND conrelid = 'public.pokedex_external_reference'::regclass
    ) THEN
        RAISE EXCEPTION 'FAIL 1.5.4: uq_pokedex_external_reference_pokedex_source ausente em public.pokedex_external_reference';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'uq_pokedex_external_reference_source_external' AND conrelid = 'public.pokedex_external_reference'::regclass
    ) THEN
        RAISE EXCEPTION 'FAIL 1.5.5: uq_pokedex_external_reference_source_external ausente em public.pokedex_external_reference';
    END IF;
    RAISE NOTICE 'PASS 1.5: as 5 UNIQUE constraints existem, cada uma na tabela correta';

    -- 1.6 CHECK constraints (escopadas por conrelid, mesma correção)
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'ck_pokedex_code_format' AND conrelid = 'public.pokedex'::regclass
    ) THEN
        RAISE EXCEPTION 'FAIL 1.6.1: ck_pokedex_code_format ausente em public.pokedex';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'ck_pokedex_position_number_positive' AND conrelid = 'public.pokedex_position'::regclass
    ) THEN
        RAISE EXCEPTION 'FAIL 1.6.2: ck_pokedex_position_number_positive ausente em public.pokedex_position';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'ck_pokedex_external_reference_metadata' AND conrelid = 'public.pokedex_external_reference'::regclass
    ) THEN
        RAISE EXCEPTION 'FAIL 1.6.3: ck_pokedex_external_reference_metadata ausente em public.pokedex_external_reference';
    END IF;
    RAISE NOTICE 'PASS 1.6: CHECK constraints conferidas (amostra), cada uma na tabela correta';

    -- 1.7 Índices — nenhum além de PK/UNIQUE (decisão explícita de não antecipar índice especulativo)
    SELECT COUNT(*) INTO v_count
    FROM pg_indexes
    WHERE schemaname = 'public'
      AND tablename IN ('pokedex', 'pokedex_position', 'pokedex_external_reference');
    -- Esperado: 1 (PK) + 1 (UNIQUE code) = 2 para pokedex;
    --           1 (PK) + 2 (UNIQUE) = 3 para pokedex_position;
    --           1 (PK) + 2 (UNIQUE) = 3 para pokedex_external_reference; total = 8
    IF v_count <> 8 THEN
        RAISE EXCEPTION 'FAIL 1.7: número de índices inesperado (esperado 8, obtido %) — investigar índice especulativo não previsto', v_count;
    END IF;
    RAISE NOTICE 'PASS 1.7: exatamente 8 índices (somente PK/UNIQUE), nenhum especulativo';

    -- 1.8 Triggers ativos (tgenabled = 'O')
    IF (SELECT COUNT(*) FROM pg_trigger WHERE tgrelid = 'public.pokedex'::regclass AND tgenabled = 'O' AND NOT tgisinternal) <> 3 THEN
        RAISE EXCEPTION 'FAIL 1.8.1: pokedex deveria ter 3 triggers ativos';
    END IF;
    IF (SELECT COUNT(*) FROM pg_trigger WHERE tgrelid = 'public.pokedex_position'::regclass AND tgenabled = 'O' AND NOT tgisinternal) <> 2 THEN
        RAISE EXCEPTION 'FAIL 1.8.2: pokedex_position deveria ter 2 triggers ativos (sem normalize, decisão explícita 6041)';
    END IF;
    IF (SELECT COUNT(*) FROM pg_trigger WHERE tgrelid = 'public.pokedex_external_reference'::regclass AND tgenabled = 'O' AND NOT tgisinternal) <> 3 THEN
        RAISE EXCEPTION 'FAIL 1.8.3: pokedex_external_reference deveria ter 3 triggers ativos';
    END IF;
    RAISE NOTICE 'PASS 1.8: triggers ativos conferidos (3/2/3)';

    -- 1.9 RLS habilitado, zero policy
    IF NOT EXISTS (SELECT 1 FROM pg_class WHERE oid = 'public.pokedex'::regclass AND relrowsecurity) THEN
        RAISE EXCEPTION 'FAIL 1.9.1: RLS não habilitado em pokedex';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_class WHERE oid = 'public.pokedex_position'::regclass AND relrowsecurity) THEN
        RAISE EXCEPTION 'FAIL 1.9.2: RLS não habilitado em pokedex_position';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_class WHERE oid = 'public.pokedex_external_reference'::regclass AND relrowsecurity) THEN
        RAISE EXCEPTION 'FAIL 1.9.3: RLS não habilitado em pokedex_external_reference';
    END IF;
    IF EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename IN ('pokedex', 'pokedex_position', 'pokedex_external_reference')
    ) THEN
        RAISE EXCEPTION 'FAIL 1.9.4: existe policy nas 3 tabelas — deveria ser zero nesta rodada';
    END IF;
    RAISE NOTICE 'PASS 1.9: RLS habilitado, zero policy nas 3 tabelas';

    -- 1.10 Zero GRANT catalogado em information_schema.role_table_grants
    -- (checagem preliminar — a prova definitiva de privilégio EFETIVO
    -- é o loop com has_table_privilege() logo abaixo, correção desta
    -- revisão: information_schema sozinho não é suficiente, pois não
    -- reflete de forma confiável privilégios herdados de default ACL
    -- nem cobre TRUNCATE/REFERENCES/TRIGGER/MAINTAIN de forma
    -- homogênea entre versões).
    IF EXISTS (
        SELECT 1 FROM information_schema.role_table_grants
        WHERE table_schema = 'public'
          AND table_name IN ('pokedex', 'pokedex_position', 'pokedex_external_reference')
          AND grantee IN ('anon', 'authenticated')
    ) THEN
        RAISE EXCEPTION 'FAIL 1.10.0: existe GRANT catalogado em role_table_grants para anon/authenticated nas 3 tabelas';
    END IF;
    RAISE NOTICE 'PASS 1.10.0: nenhum GRANT catalogado em role_table_grants (checagem preliminar)';
END;
$$;

-- ---------------------------------------------------------------------
-- 1.10 (prova definitiva) — has_table_privilege() por role/tabela/
-- privilégio, cobrindo exatamente os privilégios proibidos pelo
-- STD-001/Query 2147 (TRUNCATE/REFERENCES/TRIGGER/MAINTAIN) mais os
-- de dado (SELECT/INSERT/UPDATE/DELETE, que devem estar bloqueados
-- por RLS sem policy — aqui provamos que também não há GRANT de
-- tabela concedendo-os por fora do RLS). has_table_privilege()
-- reflete o privilégio EFETIVO do role (soma de GRANT direto +
-- membership + default ACL), diferente de information_schema, que só
-- lista GRANTs catalogados diretamente.
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_role TEXT;
    v_table TEXT;
    v_priv TEXT;
    v_roles TEXT[] := ARRAY['anon', 'authenticated'];
    v_tables TEXT[] := ARRAY['pokedex', 'pokedex_position', 'pokedex_external_reference'];
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

    RAISE NOTICE 'PASS 1.10: has_table_privilege() confirma ZERO privilégio efetivo (SELECT/INSERT/UPDATE/DELETE/TRUNCATE/REFERENCES/TRIGGER/MAINTAIN) para anon/authenticated nas 3 tabelas';
    RAISE NOTICE '=== SEÇÃO 1 (ESTRUTURAL) — TODOS OS ITENS PASS ===';
END;
$$;

-- ===================================================================
-- SEÇÃO 2 — VALIDAÇÃO COMPORTAMENTAL (transacional, zero resíduo)
-- ===================================================================
BEGIN;

DO $$
DECLARE
    v_fixture_generation_id   UUID;
    v_fixture_species_id      UUID;
    v_fixture_species_id_2    UUID;
    v_fixture_asset_source_id UUID;
    v_asset_source_id         UUID;
    v_pokedex_id              UUID;
    v_pokedex_id_2            UUID;
    v_position_id             UUID;
    v_ext_ref_id              UUID;
    v_code                    TEXT;
    v_name                    TEXT;
    v_number                  INTEGER;
    v_external_id             TEXT;
    v_count                   INTEGER;
    v_constraint_name         TEXT;
BEGIN
    -- ------------------------------------------------------------
    -- FIXTURE — dados sintéticos, revertidos no ROLLBACK final
    -- ------------------------------------------------------------
    INSERT INTO public.pokemon_generation (code, canonical_name, ordinal_number)
    VALUES ('ZZZ_VALIDATION_FIXTURE', 'Validation Fixture Generation', 999999)
    RETURNING id INTO v_fixture_generation_id;

    INSERT INTO public.pokemon_species (generation_id, national_dex_number, canonical_name)
    VALUES (v_fixture_generation_id, 999997, 'Validation Fixture Species A')
    RETURNING id INTO v_fixture_species_id;

    INSERT INTO public.pokemon_species (generation_id, national_dex_number, canonical_name)
    VALUES (v_fixture_generation_id, 999998, 'Validation Fixture Species B')
    RETURNING id INTO v_fixture_species_id_2;

    SELECT id INTO v_asset_source_id FROM public.asset_source WHERE code = 'POKEAPI';
    IF v_asset_source_id IS NULL THEN
        RAISE EXCEPTION 'FIXTURE_FAILED: linha POKEAPI ausente em asset_source (Query 6700 não aplicada?)';
    END IF;

    -- Fonte externa sintética dedicada exclusivamente à prova isolada
    -- de RESTRICT (2.3.6, abaixo) — nunca a linha real POKEAPI, que
    -- também é referenciada por outras tabelas do módulo
    -- (pokemon_species_external_reference) e cujo foreign_key_violation
    -- não provaria isoladamente a FK NOVA desta Fatia.
    INSERT INTO public.asset_source (code, name, source_type, source_order)
    VALUES ('ZZZ_VALIDATION_SOURCE', 'Validation Fixture Source', 'MANUAL', 999999)
    RETURNING id INTO v_fixture_asset_source_id;

    RAISE NOTICE 'FIXTURE OK: generation=%, species(A/B)=%/%, asset_source(POKEAPI)=%, asset_source(fixture)=%',
        v_fixture_generation_id, v_fixture_species_id, v_fixture_species_id_2, v_asset_source_id, v_fixture_asset_source_id;

    -- ------------------------------------------------------------
    -- 2.1 — pokedex
    -- ------------------------------------------------------------
    INSERT INTO public.pokedex (code, canonical_name)
    VALUES ('  zzz_validation  ', '  Pokédex de Validação  ')
    RETURNING id, code, canonical_name INTO v_pokedex_id, v_code, v_name;

    IF v_code <> 'ZZZ_VALIDATION' THEN
        RAISE EXCEPTION 'FAIL 2.1.1: normalize_pokedex não converteu code (obtido: %)', v_code;
    END IF;
    IF v_name <> 'Pokédex de Validação' THEN
        RAISE EXCEPTION 'FAIL 2.1.2: normalize_pokedex não fez trim de canonical_name (obtido: %)', v_name;
    END IF;
    RAISE NOTICE 'PASS 2.1.1/2.1.2: normalize_pokedex (code=%, canonical_name=%)', v_code, v_name;

    BEGIN
        INSERT INTO public.pokedex (code, canonical_name) VALUES ('ZZZ_VALIDATION', 'Duplicata');
        RAISE EXCEPTION 'FAIL 2.1.3: duplicidade de pokedex.code não foi rejeitada';
    EXCEPTION
        WHEN unique_violation THEN
            RAISE NOTICE 'PASS 2.1.3: duplicidade de pokedex.code rejeitada';
    END;

    BEGIN
        UPDATE public.pokedex SET code = 'OUTRO' WHERE id = v_pokedex_id;
        RAISE EXCEPTION 'FAIL 2.1.4: UPDATE em pokedex.code não foi rejeitado';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLERRM <> 'POKEDEX_CODE_IMMUTABLE' THEN
                RAISE EXCEPTION 'FAIL 2.1.4: exceção inesperada: %', SQLERRM;
            END IF;
            RAISE NOTICE 'PASS 2.1.4: UPDATE em pokedex.code rejeitado (POKEDEX_CODE_IMMUTABLE)';
    END;

    BEGIN
        UPDATE public.pokedex SET id = gen_random_uuid() WHERE id = v_pokedex_id;
        RAISE EXCEPTION 'FAIL 2.1.5: UPDATE em pokedex.id não foi rejeitado';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLERRM <> 'POKEDEX_ID_IMMUTABLE' THEN
                RAISE EXCEPTION 'FAIL 2.1.5: exceção inesperada: %', SQLERRM;
            END IF;
            RAISE NOTICE 'PASS 2.1.5: UPDATE em pokedex.id rejeitado (POKEDEX_ID_IMMUTABLE)';
    END;

    UPDATE public.pokedex SET canonical_name = 'Pokédex de Validação (corrigido)', is_active = FALSE
    WHERE id = v_pokedex_id;
    SELECT canonical_name INTO v_name FROM public.pokedex WHERE id = v_pokedex_id;
    IF v_name <> 'Pokédex de Validação (corrigido)' THEN
        RAISE EXCEPTION 'FAIL 2.1.6: canonical_name não foi corrigível';
    END IF;
    RAISE NOTICE 'PASS 2.1.6: canonical_name/is_active corrigíveis administrativamente';

    -- ------------------------------------------------------------
    -- 2.2 — pokedex_position
    -- ------------------------------------------------------------
    INSERT INTO public.pokedex_position (pokedex_id, species_id, position_number)
    VALUES (v_pokedex_id, v_fixture_species_id, 999997)
    RETURNING id INTO v_position_id;
    RAISE NOTICE 'PASS 2.2.1: insert pokedex_position válido (id=%)', v_position_id;

    BEGIN
        INSERT INTO public.pokedex_position (pokedex_id, species_id, position_number)
        VALUES (v_pokedex_id, v_fixture_species_id, 111111);
        RAISE EXCEPTION 'FAIL 2.2.2: UNIQUE(pokedex_id, species_id) não foi rejeitada';
    EXCEPTION
        WHEN unique_violation THEN
            RAISE NOTICE 'PASS 2.2.2: UNIQUE(pokedex_id, species_id) rejeitada';
    END;

    BEGIN
        INSERT INTO public.pokedex_position (pokedex_id, species_id, position_number)
        VALUES (v_pokedex_id, v_fixture_species_id_2, 999997);
        RAISE EXCEPTION 'FAIL 2.2.3: UNIQUE(pokedex_id, position_number) não foi rejeitada';
    EXCEPTION
        WHEN unique_violation THEN
            RAISE NOTICE 'PASS 2.2.3: UNIQUE(pokedex_id, position_number) rejeitada';
    END;

    BEGIN
        INSERT INTO public.pokedex_position (pokedex_id, species_id, position_number)
        VALUES (v_pokedex_id, v_fixture_species_id_2, -1);
        RAISE EXCEPTION 'FAIL 2.2.4: CHECK position_number > 0 não foi rejeitado';
    EXCEPTION
        WHEN check_violation THEN
            RAISE NOTICE 'PASS 2.2.4: CHECK position_number > 0 rejeitado';
    END;

    BEGIN
        UPDATE public.pokedex_position SET species_id = v_fixture_species_id_2 WHERE id = v_position_id;
        RAISE EXCEPTION 'FAIL 2.2.5: UPDATE em pokedex_position.species_id não foi rejeitado';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLERRM <> 'POKEDEX_POSITION_SPECIES_IMMUTABLE' THEN
                RAISE EXCEPTION 'FAIL 2.2.5: exceção inesperada: %', SQLERRM;
            END IF;
            RAISE NOTICE 'PASS 2.2.5: UPDATE em species_id rejeitado (POKEDEX_POSITION_SPECIES_IMMUTABLE)';
    END;

    BEGIN
        UPDATE public.pokedex_position SET pokedex_id = gen_random_uuid() WHERE id = v_position_id;
        RAISE EXCEPTION 'FAIL 2.2.6: UPDATE em pokedex_position.pokedex_id não foi rejeitado';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLERRM <> 'POKEDEX_POSITION_POKEDEX_IMMUTABLE' THEN
                RAISE EXCEPTION 'FAIL 2.2.6: exceção inesperada: %', SQLERRM;
            END IF;
            RAISE NOTICE 'PASS 2.2.6: UPDATE em pokedex_id rejeitado (POKEDEX_POSITION_POKEDEX_IMMUTABLE)';
    END;

    UPDATE public.pokedex_position SET position_number = 1 WHERE id = v_position_id;
    SELECT position_number INTO v_number FROM public.pokedex_position WHERE id = v_position_id;
    IF v_number <> 1 THEN
        RAISE EXCEPTION 'FAIL 2.2.7: position_number não foi corrigível';
    END IF;
    RAISE NOTICE 'PASS 2.2.7: position_number corrigível administrativamente (dado editorial canônico)';

    -- RESTRICT: excluir species referenciada por uma Position deve ser bloqueado
    BEGIN
        DELETE FROM public.pokemon_species WHERE id = v_fixture_species_id;
        RAISE EXCEPTION 'FAIL 2.2.8: DELETE em pokemon_species referenciada por Position não foi bloqueado';
    EXCEPTION
        WHEN foreign_key_violation THEN
            RAISE NOTICE 'PASS 2.2.8: DELETE em pokemon_species referenciada bloqueado (ON DELETE RESTRICT)';
    END;

    -- ------------------------------------------------------------
    -- 2.3 — pokedex_external_reference
    -- ------------------------------------------------------------
    INSERT INTO public.pokedex_external_reference (pokedex_id, asset_source_id, external_pokedex_id, source_url, metadata)
    VALUES (v_pokedex_id, v_asset_source_id, '  1  ', 'https://pokeapi.co/api/v2/pokedex/1/', '{"name": "national"}'::jsonb)
    RETURNING id, external_pokedex_id INTO v_ext_ref_id, v_external_id;

    IF v_external_id <> '1' THEN
        RAISE EXCEPTION 'FAIL 2.3.1: normalize_pokedex_external_reference não fez trim de external_pokedex_id (obtido: %)', v_external_id;
    END IF;
    RAISE NOTICE 'PASS 2.3.1: insert + normalize pokedex_external_reference válido (id=%)', v_ext_ref_id;

    BEGIN
        INSERT INTO public.pokedex_external_reference (pokedex_id, asset_source_id, external_pokedex_id)
        VALUES (v_pokedex_id, v_asset_source_id, '2');
        RAISE EXCEPTION 'FAIL 2.3.2: UNIQUE(pokedex_id, asset_source_id) não foi rejeitada';
    EXCEPTION
        WHEN unique_violation THEN
            RAISE NOTICE 'PASS 2.3.2: UNIQUE(pokedex_id, asset_source_id) rejeitada';
    END;

    -- UNIQUE(asset_source_id, external_pokedex_id) isolado do UNIQUE
    -- anterior: usa um SEGUNDO pokedex sintético, mesmo asset_source e
    -- mesmo external_pokedex_id já usado acima.
    INSERT INTO public.pokedex (code, canonical_name)
    VALUES ('ZZZ_VALIDATION_2', 'Pokédex de Validação 2')
    RETURNING id INTO v_pokedex_id_2;

    BEGIN
        INSERT INTO public.pokedex_external_reference (pokedex_id, asset_source_id, external_pokedex_id)
        VALUES (v_pokedex_id_2, v_asset_source_id, '1');
        RAISE EXCEPTION 'FAIL 2.3.3: UNIQUE(asset_source_id, external_pokedex_id) não foi rejeitada';
    EXCEPTION
        WHEN unique_violation THEN
            RAISE NOTICE 'PASS 2.3.3: UNIQUE(asset_source_id, external_pokedex_id) rejeitada (pokedex diferente, mesmo external_id)';
    END;

    -- Isolado das duas UNIQUE: usa v_pokedex_id_2 (que ainda não tem
    -- nenhuma linha persistida — a única tentativa anterior com ele,
    -- 2.3.3, falhou e reverteu) com um external_pokedex_id inédito
    -- ('3', nunca usado nesta transação), garantindo que metadata=[]
    -- seja a ÚNICA regra violada por este INSERT (achado de auditoria
    -- externa, correção desta revisão — a versão anterior reusava
    -- (v_pokedex_id, v_asset_source_id, '1'), que já colidia com as
    -- duas UNIQUE simultaneamente).
    BEGIN
        INSERT INTO public.pokedex_external_reference (pokedex_id, asset_source_id, external_pokedex_id, metadata)
        VALUES (v_pokedex_id_2, v_asset_source_id, '3', '[]'::jsonb);
        RAISE EXCEPTION 'FAIL 2.3.4: CHECK metadata objeto não foi rejeitado';
    EXCEPTION
        WHEN check_violation THEN
            RAISE NOTICE 'PASS 2.3.4: CHECK metadata (deve ser objeto JSONB) rejeitado para array — nenhuma UNIQUE envolvida (pokedex_id/external_pokedex_id inéditos nesta combinação)';
        WHEN unique_violation THEN
            RAISE EXCEPTION 'FAIL 2.3.4: violação inesperada de UNIQUE em vez de CHECK — combinação não estava isolada como esperado';
    END;

    BEGIN
        UPDATE public.pokedex_external_reference SET external_pokedex_id = '2' WHERE id = v_ext_ref_id;
        RAISE EXCEPTION 'FAIL 2.3.5: UPDATE em external_pokedex_id não foi rejeitado';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLERRM <> 'POKEDEX_EXTERNAL_REFERENCE_EXTERNAL_ID_IMMUTABLE' THEN
                RAISE EXCEPTION 'FAIL 2.3.5: exceção inesperada: %', SQLERRM;
            END IF;
            RAISE NOTICE 'PASS 2.3.5: UPDATE em external_pokedex_id rejeitado (imutável)';
    END;

    -- RESTRICT: prova ISOLADA da FK nova (pokedex_external_reference
    -- .asset_source_id). Correção desta revisão: a versão anterior
    -- excluía a linha real POKEAPI e aceitava qualquer
    -- foreign_key_violation como PASS — mas POKEAPI também é
    -- referenciada por pokemon_species_external_reference (Query
    -- 6020), então o erro capturado podia vir de QUALQUER uma das
    -- duas FKs, não provando isoladamente a FK desta Fatia. Agora:
    -- usa a fonte sintética v_fixture_asset_source_id (referenciada
    -- exclusivamente por uma linha de pokedex_external_reference
    -- criada só para este teste) e confirma via GET STACKED
    -- DIAGNOSTICS que o nome da constraint violada é especificamente
    -- o da FK nova.
    INSERT INTO public.pokedex_external_reference (pokedex_id, asset_source_id, external_pokedex_id)
    VALUES (v_pokedex_id, v_fixture_asset_source_id, 'FIXTURE_ONLY_REF');

    BEGIN
        DELETE FROM public.asset_source WHERE id = v_fixture_asset_source_id;
        RAISE EXCEPTION 'FAIL 2.3.6: DELETE em asset_source (fixture, referenciada só por pokedex_external_reference) não foi bloqueado';
    EXCEPTION
        WHEN foreign_key_violation THEN
            GET STACKED DIAGNOSTICS v_constraint_name = CONSTRAINT_NAME;
            IF v_constraint_name <> 'pokedex_external_reference_asset_source_id_fkey' THEN
                RAISE EXCEPTION 'FAIL 2.3.6: foreign_key_violation veio de constraint inesperada (%), não da FK nova desta Fatia', v_constraint_name;
            END IF;
            RAISE NOTICE 'PASS 2.3.6: DELETE em asset_source referenciado bloqueado especificamente pela FK pokedex_external_reference_asset_source_id_fkey (ON DELETE RESTRICT), confirmado via GET STACKED DIAGNOSTICS';
    END;

    -- ------------------------------------------------------------
    -- 2.4 — CASCADE: excluir o pokedex remove Position e External Reference
    -- ------------------------------------------------------------
    DELETE FROM public.pokedex WHERE id = v_pokedex_id;

    SELECT COUNT(*) INTO v_count FROM public.pokedex_position WHERE pokedex_id = v_pokedex_id;
    IF v_count <> 0 THEN
        RAISE EXCEPTION 'FAIL 2.4.1: pokedex_position não foi removida em CASCADE (restam %)', v_count;
    END IF;
    SELECT COUNT(*) INTO v_count FROM public.pokedex_external_reference WHERE pokedex_id = v_pokedex_id;
    IF v_count <> 0 THEN
        RAISE EXCEPTION 'FAIL 2.4.2: pokedex_external_reference não foi removida em CASCADE (restam %)', v_count;
    END IF;
    RAISE NOTICE 'PASS 2.4: ON DELETE CASCADE confirmado (pokedex_position e pokedex_external_reference removidas)';

    RAISE NOTICE '=== SEÇÃO 2 (COMPORTAMENTAL) — TODOS OS ITENS PASS ===';
END;
$$;

-- Zero resíduo: reverte TODA a fixture (generation/species/asset_source/
-- pokedex/position/external_reference sintéticos, incluindo a fonte
-- ZZZ_VALIDATION_SOURCE criada só para a prova isolada de RESTRICT).
-- Nenhuma linha real do banco (incluindo a linha POKEAPI de
-- asset_source, nunca excluída nesta versão) é alterada de forma
-- permanente — a tentativa de DELETE em pokemon_species (2.2.8) e a
-- tentativa de DELETE na fonte sintética (2.3.6) falharam por
-- RESTRICT antes de qualquer efeito, e o restante da fixture nunca é
-- commitado.
ROLLBACK;

-- ===================================================================
-- SEÇÃO 3 — PRIVILÉGIOS DE FUNÇÃO (EXECUTE, leitura pura, sem mutação)
-- ===================================================================
DO $$
DECLARE
    v_fn TEXT;
    v_functions TEXT[] := ARRAY[
        'normalize_pokedex', 'govern_pokedex', 'touch_pokedex_updated_at',
        'govern_pokedex_position', 'touch_pokedex_position_updated_at',
        'normalize_pokedex_external_reference', 'govern_pokedex_external_reference',
        'touch_pokedex_external_reference_updated_at'
    ];
BEGIN
    IF array_length(v_functions, 1) <> 8 THEN
        RAISE EXCEPTION 'FAIL 3.0: lista de funções esperadas não tem 8 elementos';
    END IF;

    FOREACH v_fn IN ARRAY v_functions LOOP
        IF has_function_privilege('anon', ('public.' || v_fn || '()')::regprocedure, 'EXECUTE') THEN
            RAISE EXCEPTION 'FAIL 3.1: anon ainda tem EXECUTE em public.%()', v_fn;
        END IF;
        IF has_function_privilege('authenticated', ('public.' || v_fn || '()')::regprocedure, 'EXECUTE') THEN
            RAISE EXCEPTION 'FAIL 3.2: authenticated ainda tem EXECUTE em public.%()', v_fn;
        END IF;
    END LOOP;

    RAISE NOTICE '=== SEÇÃO 3 (PRIVILÉGIOS) — as 8 trigger functions sem EXECUTE para anon/authenticated: PASS ===';
END;
$$;

-- ===================================================================
-- SEÇÃO 4 — PERFORMANCE (proporcional ao volume/risco desta Fatia)
-- ===================================================================
-- Nota: a Fatia A tem volume esperado da ordem de milhares de linhas no
-- limite superior (Pokédex Nacional), hoje zero (pokemon_species ainda
-- sem seed). Os dois padrões de acesso previsíveis — buscar uma Position
-- por (pokedex_id, species_id) e por (pokedex_id, position_number) — já
-- são cobertos pelos índices gerados automaticamente pelas UNIQUE
-- compostas (confirmados na Seção 1.7), com pokedex_id como coluna
-- líder em ambos. Não há padrão de acesso real conhecido que justifique
-- um índice isolado em species_id (ex.: "todas as Positions de uma
-- Species através de múltiplos Pokédex" não é um caso de uso desta
-- Fatia, que trata de um único Pokédex Nacional).
--
-- Diferente de Master Set Scope (Query 5813, 02F), que exigiu benchmark
-- com >= 20 mil linhas sintéticas por lidar com volume real de Card
-- Variant, esta Fatia não justifica benchmark de carga: nenhum
-- EXPLAIN ANALYZE contra dado sintético em massa foi preparado aqui,
-- por decisão explícita de não antecipar validação desproporcional ao
-- risco real. Caso o volume real diverja desta expectativa após o seed
-- de pokemon_species/pokedex_position, uma validação de performance
-- própria deve ser criada como Query nova, não retroativamente aqui.

-- ===================================================================
-- FIM — CONFIRMADO EXECUTADO (2026-09-04, contra o projeto Supabase
-- qjfutqujxrbzgrtkpgkg, via COLLECTIONS-POKEDEX-POSITION-PHYSICAL-
-- IMPLEMENTATION-01), APÓS 6030/6031/6040/6041/6050/6051 terem sido
-- confirmadamente aplicadas nesta mesma rodada. Resultado: PASS em
-- todas as seções (1 estrutural, 2 comportamental, 3 privilégios de
-- função), sem nenhum FAIL. Este arquivo permanece em
-- database/proposals/2026-09-04-pokedex-foundation/ como evidência
-- histórica de validação executada — NÃO promovido para
-- database/schema/ (COLLECTIONS-POKEDEX-POSITION-PHYSICAL-CANONICAL-
-- PROMOTION-01, regra 5): é um script de validação pontual da
-- implementação, não estrutura persistente do módulo.
-- ===================================================================
