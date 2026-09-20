-- ============================================================================
-- Query 2206 — Guards de composição de Edition Context
-- Status: PROPOSTA — NÃO EXECUTADA · Versão 1.0
--
-- TRÊS GARANTIAS
--   G1  traits_signature é SELADA a partir da N:N (nunca escrita à mão).
--   G2  COMPOSIÇÃO IMUTÁVEL após o commit — mesma disciplina de Printing.
--       Corrigir uma composição = criar profile novo, nunca mutar o existente,
--       porque card_variant já materializado aponta para ele.
--   G3  Trait INATIVO não pode entrar em composição NOVA.
-- ============================================================================

-- Fronteira transacional EXPLÍCITA (TRANSACTION-BOUNDARY-CORRECTION-01).
-- Paridade com a Query 2168. As três funções e os dois triggers formam um
-- conjunto indivisível: um guard instalado sem o outro deixaria a composição
-- parcialmente desprotegida. Ver nota completa na Query 2203.
BEGIN;

CREATE OR REPLACE FUNCTION internal.seal_edition_context_signature()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_profile UUID := COALESCE(NEW.profile_id, OLD.profile_id);
    v_sig     UUID[];
BEGIN
    SELECT ARRAY(SELECT DISTINCT pt.trait_id
                   FROM public.card_edition_context_profile_trait pt
                  WHERE pt.profile_id = v_profile
                  ORDER BY pt.trait_id)
      INTO v_sig;

    IF v_sig IS NULL OR cardinality(v_sig) = 0 THEN
        RAISE EXCEPTION 'EDITION_CONTEXT_EMPTY_COMPOSITION: profile % ficaria sem traits.', v_profile;
    END IF;

    UPDATE public.card_edition_context_profile p
       SET traits_signature = v_sig, updated_at = now()
     WHERE p.id = v_profile;

    RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER trg_cecpt_seal_signature
    AFTER INSERT OR UPDATE OR DELETE ON public.card_edition_context_profile_trait
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION internal.seal_edition_context_signature();

-- ----------------------------------------------------------------------------
-- G2 — imutabilidade pós-commit
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION internal.guard_edition_context_composition_immutable()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_sealed UUID[];
BEGIN
    SELECT p.traits_signature INTO v_sealed
      FROM public.card_edition_context_profile p
     WHERE p.id = COALESCE(NEW.profile_id, OLD.profile_id);

    -- Assinatura já selada em transação anterior => composição fechada.
    IF v_sealed IS NOT NULL AND cardinality(v_sealed) > 0 THEN
        RAISE EXCEPTION
          'EDITION_CONTEXT_COMPOSITION_IMMUTABLE: profile % ja esta selado. Crie um profile novo — card_variant materializado aponta para este.',
          COALESCE(NEW.profile_id, OLD.profile_id);
    END IF;

    RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE TRIGGER trg_cecpt_immutable
    BEFORE INSERT OR UPDATE OR DELETE ON public.card_edition_context_profile_trait
    FOR EACH ROW EXECUTE FUNCTION internal.guard_edition_context_composition_immutable();

-- ----------------------------------------------------------------------------
-- G3 — trait inativo fora de composição nova
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

CREATE TRIGGER trg_cecpt_trait_active
    BEFORE INSERT ON public.card_edition_context_profile_trait
    FOR EACH ROW EXECUTE FUNCTION internal.guard_edition_context_trait_active();

-- ----------------------------------------------------------------------------
-- ACL das trigger functions — MAIS ESTRITA que o baseline de Printing
-- ----------------------------------------------------------------------------
-- A Query 2168 revoga apenas de PUBLIC. Aqui revoga-se tambem de anon,
-- authenticated e service_role. As tres sao funcoes de TRIGGER: quem as
-- executa e o proprio trigger, no contexto do dono da funcao (SECURITY
-- DEFINER), nunca um cliente. Nenhum papel precisa de EXECUTE direto, entao
-- retirar de todos e gratuito e fecha a superficie por completo.
--
-- SECURITY DEFINER + SET search_path = '' preservados nas tres (linhas 16-17,
-- 52-53, 83-84). SECURITY-SEED-HARDENING-01 nao alterou nenhum corpo.
REVOKE ALL ON FUNCTION internal.seal_edition_context_signature() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION internal.guard_edition_context_composition_immutable() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION internal.guard_edition_context_trait_active() FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
