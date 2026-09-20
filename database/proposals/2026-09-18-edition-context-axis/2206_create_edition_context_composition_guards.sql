-- ============================================================================
-- Query 2206 — Guards de composição de Edition Context
-- Status: PROPOSTA — NÃO EXECUTADA · Versão 2.0
--
-- v2.0 (BATCH1-RUNTIME-CORRECTION-02) — PARIDADE REAL COM A 2168
--   A v1.0 reproduzia EXATAMENTE o defeito que a Printing já havia corrigido.
--   O header da Query 2168 v1.1 (LIVE), item 3, registra:
--
--     "PROFILE VAZIO VIROU FAIL-CLOSED. Na v1.0, um Profile sem nenhum
--      vinculo simplesmente nao disparava trigger nenhum (nao havia linha na
--      N:N para disparar) — a limitacao ficou documentada como S5b e NAO foi
--      aprovada. Agora o trigger deferido esta sobre card_printing_profile
--      INSERT, nao sobre a N:N."
--
--   A 2206 v1.0 tinha o selo `AFTER INSERT OR UPDATE OR DELETE ON
--   card_edition_context_profile_trait` — por EVENTO NA N:N. Consequência
--   determinística: Profile criado sem nenhuma linha na N:N não dispara
--   trigger algum e chega ao COMMIT com traits_signature NULL, violando
--   "todo Profile precisa de >= 1 trait no COMMIT". Era o S5b, reintroduzido.
--
--   Faltava também o equivalente de
--   `internal.enforce_printing_profile_signature_write()`. Sem ele — e agora
--   sem o CHECK inválido que a 2204 v1.0 carregava — um UPDATE direto poderia
--   gravar um UUID[] 1-D não vazio SEM CORRESPONDÊNCIA com a N:N. Os dois
--   CHECKs escalares da 2204 v1.1 provam forma, nunca conteúdo.
--
-- QUATRO GUARDS
--   A  selo + não-vazio     — CONSTRAINT TRIGGER deferido no CABEÇALHO
--   B  composição imutável  — BEFORE INSERT/UPDATE/DELETE na N:N
--   C  selo não falsificável — BEFORE UPDATE OF traits_signature no cabeçalho
--   D  trait inativo        — específico de Edition Context, preservado da v1.0
--
--   A, B e C copiam as INVARIANTES provadas da 2168, não os nomes. D não tem
--   equivalente em Printing: lá o vocabulário é praticamente fechado; aqui
--   cada temporada competitiva acrescenta átomos e `is_active` governa a
--   disponibilidade para composições NOVAS (ver 2204, nota de divergência).
--
-- LIFECYCLE ESPECÍFICO DE EDITION CONTEXT — por que o padrão se aplica
--   O seed 2231 monta cada Profile como: INSERT do cabeçalho -> INSERT das
--   linhas N:N -> COMMIT. O trigger A é DEFERRABLE INITIALLY DEFERRED, então
--   no instante do COMMIT ele já enxerga a composição final — mesmo padrão e
--   mesma ordem do seed 2169, que é LIVE e validado. Não há passo editorial
--   intermediário que precise de um Profile selado-vazio.
-- ============================================================================

-- Fronteira transacional EXPLÍCITA (TRANSACTION-BOUNDARY-CORRECTION-01).
-- Paridade com a Query 2168. As quatro funções e os quatro triggers formam um
-- conjunto indivisível: um guard instalado sem o outro deixaria a composição
-- parcialmente desprotegida. Ver nota completa na Query 2203.
BEGIN;

-- ----------------------------------------------------------------------------
-- GUARD A — não-vazio + selamento (deferido, 1x por Profile)
--
-- CONSTRAINT TRIGGER sobre o CABEÇALHO, não sobre a N:N. Dispara uma vez por
-- Profile, no COMMIT — inclusive quando NENHUM vínculo existe, que é
-- justamente o caso que precisa falhar. É esta troca que fecha o S5b.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION internal.seal_edition_context_composition()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_signature UUID[];
BEGIN
    -- Profile criado e removido na mesma transação: nada a validar nem a
    -- selar. Evita falso positivo em rollback/delete intra-transação.
    IF NOT EXISTS (
        SELECT 1 FROM public.card_edition_context_profile p WHERE p.id = NEW.id
    ) THEN
        RETURN NULL;
    END IF;

    -- Conjunto canônico: DISTINCT por construção (pk_cecpt é
    -- (profile_id, trait_id), logo não existe par repetido) e ORDENADO
    -- ascendente pelo próprio trait_id.
    -- ARRAY(SELECT ...) devolve '{}' quando não há linhas — nunca NULL.
    v_signature := ARRAY(
        SELECT t.trait_id
          FROM public.card_edition_context_profile_trait t
         WHERE t.profile_id = NEW.id
         ORDER BY t.trait_id
    );

    IF cardinality(v_signature) = 0 THEN
        RAISE EXCEPTION 'EDITION_CONTEXT_PROFILE_EMPTY_COMPOSITION: o Perfil de Contexto de Edição % chegou ao COMMIT sem nenhum Traço. Todo Perfil precisa de ao menos um.', NEW.id;
    END IF;

    -- Selamento. O UPDATE abaixo é avaliado pelo índice único parcial
    -- uq_cecp_game_signature — e é ele, não esta função, que rejeita
    -- composição duplicada. Por isso é seguro sob concorrência: duas
    -- transações que montem o MESMO conjunto calculam o MESMO array ordenado,
    -- e o índice serializa (uma comita, a outra recebe unique_violation).
    -- A proteção NÃO é SELECT EXISTS seguido de escrita — é o índice.
    UPDATE public.card_edition_context_profile
       SET traits_signature = v_signature,
           updated_at       = now()
     WHERE id = NEW.id;

    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_cecp_seal
    ON public.card_edition_context_profile;

CREATE CONSTRAINT TRIGGER trg_cecp_seal
AFTER INSERT ON public.card_edition_context_profile
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
EXECUTE FUNCTION internal.seal_edition_context_composition();

-- ----------------------------------------------------------------------------
-- GUARD B — imutabilidade da composição (estado de selamento, não relógio)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION internal.guard_edition_context_composition_immutable()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_profile_id UUID;
    v_signature  UUID[];
    v_exists     BOOLEAN;
BEGIN
    IF TG_OP = 'UPDATE' THEN
        RAISE EXCEPTION 'EDITION_CONTEXT_PROFILE_TRAIT_UPDATE_FORBIDDEN: vínculo de composição nunca pode ser atualizado. Crie um Perfil novo e reconcilie.';
    END IF;

    v_profile_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.profile_id ELSE NEW.profile_id END;

    SELECT p.traits_signature, TRUE INTO v_signature, v_exists
      FROM public.card_edition_context_profile p
     WHERE p.id = v_profile_id;

    -- Profile sendo removido na mesma transação: nada a proteger.
    IF v_exists IS NULL THEN
        RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
    END IF;

    -- EM MONTAGEM: a composição ainda pode ser escrita livremente.
    IF v_signature IS NULL THEN
        RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
    END IF;

    -- SELADO. Reinserção IDÊNTICA não é mudança semântica — deixa passar para
    -- que o seed 2231 (ON CONFLICT DO NOTHING) continue idempotente.
    -- ATENÇÃO: este é um trigger BEFORE. No Postgres, triggers BEFORE INSERT
    -- disparam ANTES da arbitragem do ON CONFLICT, ou seja, ele roda mesmo
    -- quando a linha será descartada. Por isso o ramo explícito abaixo é
    -- obrigatório — não dá para contar com o ON CONFLICT para suprimir o
    -- disparo. O conjunto não muda: a linha já existe, idêntica.
    IF TG_OP = 'INSERT'
       AND EXISTS (
           SELECT 1 FROM public.card_edition_context_profile_trait t
            WHERE t.profile_id = NEW.profile_id
              AND t.trait_id   = NEW.trait_id
       ) THEN
        RETURN NEW;
    END IF;

    RAISE EXCEPTION 'EDITION_CONTEXT_COMPOSITION_IMMUTABLE: o Perfil de Contexto de Edição % já está selado e sua composição é imutável. Crie um Perfil novo — card_variant materializado aponta para este.', v_profile_id;
END;
$$;

DROP TRIGGER IF EXISTS trg_cecpt_immutable
    ON public.card_edition_context_profile_trait;

CREATE TRIGGER trg_cecpt_immutable
BEFORE INSERT OR UPDATE OR DELETE ON public.card_edition_context_profile_trait
FOR EACH ROW
EXECUTE FUNCTION internal.guard_edition_context_composition_immutable();

-- ----------------------------------------------------------------------------
-- GUARD C — o selo não pode ser destravado nem falsificado por UPDATE comum
--
-- Este guard é o que substitui, com prova de CONTEÚDO, o que a 2204 v1.0
-- tentava (e não conseguia) provar por CHECK. Os dois CHECKs escalares que
-- restaram na 2204 v1.1 provam FORMA — não vazio, unidimensional. A
-- correspondência com a N:N só pode ser verificada por trigger, porque exige
-- consultar outra tabela.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION internal.enforce_edition_context_signature_write()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_real UUID[];
BEGIN
    IF NEW.traits_signature IS NOT DISTINCT FROM OLD.traits_signature THEN
        RETURN NEW;  -- UPDATE que não toca o selo: livre.
    END IF;

    -- Já selado: nenhuma mudança, nem mesmo voltar a NULL.
    IF OLD.traits_signature IS NOT NULL THEN
        RAISE EXCEPTION 'EDITION_CONTEXT_SIGNATURE_IMMUTABLE: a assinatura de composição do Perfil % já foi selada e não pode ser alterada nem removida.', OLD.id;
    END IF;

    -- Selando agora: o valor precisa corresponder EXATAMENTE à composição
    -- real. Impede selo falsificado mesmo por escrita direta do owner.
    -- É também o que garante canonicidade: v_real é sempre DISTINCT (pela PK
    -- da N:N) e ORDENADO, então um array fora de ordem ou com duplicata é
    -- IS DISTINCT FROM v_real e cai no EXCEPTION abaixo.
    v_real := ARRAY(
        SELECT t.trait_id
          FROM public.card_edition_context_profile_trait t
         WHERE t.profile_id = NEW.id
         ORDER BY t.trait_id
    );

    IF NEW.traits_signature IS DISTINCT FROM v_real THEN
        RAISE EXCEPTION 'EDITION_CONTEXT_SIGNATURE_MISMATCH: a assinatura informada para o Perfil % não corresponde à composição real registrada.', NEW.id;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_cecp_signature_write
    ON public.card_edition_context_profile;

CREATE TRIGGER trg_cecp_signature_write
BEFORE UPDATE OF traits_signature ON public.card_edition_context_profile
FOR EACH ROW
EXECUTE FUNCTION internal.enforce_edition_context_signature_write();

-- ----------------------------------------------------------------------------
-- GUARD D — trait inativo fora de composição nova (específico de Edition Context)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION internal.guard_edition_context_trait_active()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.card_edition_context_trait t
                    WHERE t.id = NEW.trait_id AND t.is_active) THEN
        RAISE EXCEPTION 'EDITION_CONTEXT_TRAIT_INACTIVE: trait % esta inativo.', NEW.trait_id;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_cecpt_trait_active
    ON public.card_edition_context_profile_trait;

CREATE TRIGGER trg_cecpt_trait_active
BEFORE INSERT ON public.card_edition_context_profile_trait
FOR EACH ROW
EXECUTE FUNCTION internal.guard_edition_context_trait_active();

-- ----------------------------------------------------------------------------
-- ACL das trigger functions — MAIS ESTRITA que o baseline de Printing
-- ----------------------------------------------------------------------------
-- A Query 2168 revoga apenas de PUBLIC. Aqui revoga-se também de anon,
-- authenticated e service_role. As quatro são funções de TRIGGER: quem as
-- executa é o próprio trigger, no contexto do dono da função (SECURITY
-- DEFINER), nunca um cliente. Nenhum papel precisa de EXECUTE direto, então
-- retirar de todos é gratuito e fecha a superfície por completo.
REVOKE ALL ON FUNCTION internal.seal_edition_context_composition()            FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION internal.guard_edition_context_composition_immutable() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION internal.enforce_edition_context_signature_write()     FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION internal.guard_edition_context_trait_active()          FROM PUBLIC, anon, authenticated, service_role;

COMMIT;

-- ============================================================================
-- Resultado esperado:
--   CREATE FUNCTION x4 · DROP TRIGGER x4 · CREATE TRIGGER x4 · REVOKE x4.
--   Destes, 1 é CONSTRAINT TRIGGER (trg_cecp_seal).
--
-- NOTA DE SUPERSESSÃO — a v1.0 criava
--   internal.seal_edition_context_signature()   (selo por evento na N:N)
-- Essa função NÃO é criada pela v2.0 e NÃO existe no LIVE: a 2206 nunca foi
-- executada. Não há DROP a fazer — apenas o nome mudou junto com o mecanismo,
-- para que "signature" (o que era selado) desse lugar a "composition" (o que
-- é validado e selado), alinhado com a 2168.
-- ============================================================================
