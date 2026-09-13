/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 2174 - Create Card Printing External Mapping Guards
Versão......: 1.0
Status......: PROPOSTA — NÃO EXECUTADA
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-12
Mandato.....: CARD-VARIANTS — PRINTING-ROUTING — STAGING-GATE-A-01 (§4, §6)

Descrição resumida:
Cinco guards do mapping de Printing: normalizacao canonica, imutabilidade
de identidade, lifecycle de is_active, selamento deferido e protecao do
selo.

-------------------------------------------------------------------------------
POR QUE NAO E COPIA MECANICA DA 2168
-------------------------------------------------------------------------------
O padrao de selamento da 2168 (card_printing_profile) foi reaproveitado
CONCEITUALMENTE, mas o lifecycle aqui e diferente e exigiu dois guards a
mais:

1. Profile nao tem is_active mutavel no seu contrato de identidade;
   mapping tem — e precisamos impedir REATIVACAO SILENCIOSA.
2. Profile nao tem identidade externa normalizada; mapping tem — e ela
   precisa ser canonica na entrada e imutavel depois.

Os tres guards herdados (GUARD C/D/E abaixo) sao estruturalmente
equivalentes aos da 2168 e mantem o mesmo contrato provado.

-------------------------------------------------------------------------------
INTERACAO ENTRE is_active E O SELO — verificada, nao assumida
-------------------------------------------------------------------------------
GUARD E e BEFORE UPDATE **OF traits_signature**. Um
`UPDATE ... SET is_active = FALSE` NAO o dispara, porque a coluna do selo
nao esta na lista de colunas do evento.

E o inverso tambem vale: o UPDATE de selamento emitido por GUARD D nao
mexe em is_active nem na identidade, entao passa por GUARD B sem
reclamacao.

Ou seja: composicao continua IMUTAVEL, e ainda assim o mapping pode ser
aposentado. E exatamente isso que torna a correcao editorial possivel
sem abrir excecao no selo.

Regras de Negócio:
- normalized_token e sempre canonico (normalizado na entrada).
- Identidade (game_id, asset_source_id, raw_field, normalized_token)
  imutavel apos criacao.
- is_active: TRUE -> FALSE permitido; FALSE -> TRUE PROIBIDO.
  Correcao e mapping NOVO, nunca ressurreicao.
- Mapping vazio nunca chega ao COMMIT.
- Composicao imutavel apos selamento; reinsercao identica aceita
  (idempotencia da seed).
- Selo nao pode ser destravado nem falsificado.

Pré-requisitos:
- Query 2172 - Create Card Printing External Mapping Table.
- Query 2173 - Create Card Printing External Mapping Trait Table.
- Query 2095 - normalize_external_catalog_value().
- Schema internal (Query 2000).
===============================================================================
*/

BEGIN;

-- ---------------------------------------------------------------------------
-- GUARD A — normalizacao canonica do token na entrada
--
-- Nao pode ser CHECK: normalize_external_catalog_value() depende de
-- extensions.unaccent(), que e STABLE, e o Postgres exige IMMUTABLE em
-- CHECK. Normalizar na entrada e mais forte que validar: nao existe
-- caminho pelo qual um token nao-canonico entre.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION internal.normalize_card_printing_external_mapping()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    NEW.normalized_token := public.normalize_external_catalog_value(NEW.normalized_token);

    IF btrim(NEW.normalized_token) = '' THEN
        RAISE EXCEPTION 'CARD_PRINTING_EXTERNAL_MAPPING_EMPTY_TOKEN: o token normalizado ficou vazio — token externo inválido (%).', NEW.external_token;
    END IF;

    RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION internal.normalize_card_printing_external_mapping() FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_card_printing_external_mapping_normalize
    ON public.card_printing_external_mapping;

CREATE TRIGGER trg_card_printing_external_mapping_normalize
BEFORE INSERT ON public.card_printing_external_mapping
FOR EACH ROW
EXECUTE FUNCTION internal.normalize_card_printing_external_mapping();

-- ---------------------------------------------------------------------------
-- GUARD B — identidade imutavel + lifecycle de is_active
--
-- Um mapping NUNCA muda de token, Game, Fonte ou raw_field: isso seria
-- reescrever a historia do routing. E um mapping aposentado NUNCA
-- ressuscita: correcao e mapping novo, com supersedes_mapping_id.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION internal.enforce_card_printing_external_mapping_header()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    IF NEW.game_id           IS DISTINCT FROM OLD.game_id
    OR NEW.asset_source_id   IS DISTINCT FROM OLD.asset_source_id
    OR NEW.raw_field         IS DISTINCT FROM OLD.raw_field
    OR NEW.normalized_token  IS DISTINCT FROM OLD.normalized_token THEN
        RAISE EXCEPTION 'CARD_PRINTING_EXTERNAL_MAPPING_IDENTITY_IMMUTABLE: a identidade externa de um mapeamento de impressão não pode ser alterada. Crie um mapeamento novo e aponte supersedes_mapping_id.';
    END IF;

    IF NEW.supersedes_mapping_id IS DISTINCT FROM OLD.supersedes_mapping_id THEN
        RAISE EXCEPTION 'CARD_PRINTING_EXTERNAL_MAPPING_SUPERSEDES_IMMUTABLE: a cadeia histórica de um mapeamento não pode ser reescrita.';
    END IF;

    -- FALSE -> TRUE e o unico caminho proibido. TRUE -> FALSE e a
    -- aposentadoria legitima; TRUE -> TRUE e FALSE -> FALSE sao no-ops.
    IF OLD.is_active = FALSE AND NEW.is_active = TRUE THEN
        RAISE EXCEPTION 'CARD_PRINTING_EXTERNAL_MAPPING_REACTIVATION_FORBIDDEN: um mapeamento aposentado não pode ser reativado. A correção editorial é criar um mapeamento novo, nunca ressuscitar um antigo.';
    END IF;

    RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION internal.enforce_card_printing_external_mapping_header() FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_card_printing_external_mapping_header
    ON public.card_printing_external_mapping;

CREATE TRIGGER trg_card_printing_external_mapping_header
BEFORE UPDATE ON public.card_printing_external_mapping
FOR EACH ROW
EXECUTE FUNCTION internal.enforce_card_printing_external_mapping_header();

-- ---------------------------------------------------------------------------
-- GUARD C — nao-vazio + selamento (deferido, 1x por mapping)
--
-- Mesmo mecanismo da 2168: CONSTRAINT TRIGGER sobre o CABECALHO, nao
-- sobre a N:N. Dispara uma vez por mapping, no COMMIT — inclusive quando
-- nenhum vinculo existe, que e justamente o caso que precisa falhar.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION internal.seal_card_printing_external_mapping()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_signature UUID[];
BEGIN
    -- Criado e removido na mesma transacao: nada a validar nem a selar.
    IF NOT EXISTS (
        SELECT 1 FROM public.card_printing_external_mapping m WHERE m.id = NEW.id
    ) THEN
        RETURN NULL;
    END IF;

    -- ARRAY(SELECT ...) devolve '{}' quando nao ha linhas — nunca NULL.
    v_signature := ARRAY(
        SELECT t.trait_id
          FROM public.card_printing_external_mapping_trait t
         WHERE t.mapping_id = NEW.id
         ORDER BY t.trait_id
    );

    IF cardinality(v_signature) = 0 THEN
        RAISE EXCEPTION 'CARD_PRINTING_EXTERNAL_MAPPING_EMPTY_COMPOSITION: o mapeamento de impressão % chegou ao COMMIT sem nenhuma Característica de Impressão. Mapeamento parcial não é permitido.', NEW.id;
    END IF;

    UPDATE public.card_printing_external_mapping
       SET traits_signature = v_signature
     WHERE id = NEW.id;

    RETURN NULL;
END;
$$;

REVOKE ALL ON FUNCTION internal.seal_card_printing_external_mapping() FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_card_printing_external_mapping_seal
    ON public.card_printing_external_mapping;

CREATE CONSTRAINT TRIGGER trg_card_printing_external_mapping_seal
AFTER INSERT ON public.card_printing_external_mapping
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
EXECUTE FUNCTION internal.seal_card_printing_external_mapping();

-- ---------------------------------------------------------------------------
-- GUARD D — imutabilidade da composicao (estado de selamento)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION internal.enforce_card_printing_external_mapping_composition_immutable()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_mapping_id UUID;
    v_signature UUID[];
    v_exists BOOLEAN;
BEGIN
    IF TG_OP = 'UPDATE' THEN
        RAISE EXCEPTION 'CARD_PRINTING_EXTERNAL_MAPPING_TRAIT_UPDATE_FORBIDDEN: vínculo de composição nunca pode ser atualizado. Crie um mapeamento novo e reconcilie.';
    END IF;

    v_mapping_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.mapping_id ELSE NEW.mapping_id END;

    SELECT m.traits_signature, TRUE INTO v_signature, v_exists
      FROM public.card_printing_external_mapping m
     WHERE m.id = v_mapping_id;

    -- Mapping sendo removido na mesma transacao: nada a proteger.
    IF v_exists IS NULL THEN
        RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
    END IF;

    -- EM MONTAGEM: a composicao ainda pode ser escrita livremente.
    IF v_signature IS NULL THEN
        RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
    END IF;

    -- SELADO. Reinsercao IDENTICA nao e mudanca semantica.
    -- ATENCAO: este e um trigger BEFORE. No Postgres, triggers BEFORE
    -- INSERT disparam ANTES da arbitragem do ON CONFLICT, ou seja, ele
    -- roda mesmo quando a linha sera descartada. Por isso o ramo
    -- explicito abaixo e obrigatorio — nao da para contar com o
    -- ON CONFLICT para suprimir o disparo.
    IF TG_OP = 'INSERT'
       AND EXISTS (
           SELECT 1 FROM public.card_printing_external_mapping_trait t
            WHERE t.mapping_id = NEW.mapping_id
              AND t.trait_id = NEW.trait_id
       ) THEN
        RETURN NEW;
    END IF;

    RAISE EXCEPTION 'CARD_PRINTING_EXTERNAL_MAPPING_COMPOSITION_SEALED: o mapeamento de impressão % já está selado e sua composição é imutável. Crie um mapeamento novo e aponte supersedes_mapping_id.', v_mapping_id;
END;
$$;

REVOKE ALL ON FUNCTION internal.enforce_card_printing_external_mapping_composition_immutable() FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_card_printing_external_mapping_trait_immutable
    ON public.card_printing_external_mapping_trait;

CREATE TRIGGER trg_card_printing_external_mapping_trait_immutable
BEFORE INSERT OR UPDATE OR DELETE ON public.card_printing_external_mapping_trait
FOR EACH ROW
EXECUTE FUNCTION internal.enforce_card_printing_external_mapping_composition_immutable();

-- ---------------------------------------------------------------------------
-- GUARD E — o selo nao pode ser destravado nem falsificado
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION internal.enforce_card_printing_external_mapping_signature_write()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_real UUID[];
BEGIN
    IF NEW.traits_signature IS NOT DISTINCT FROM OLD.traits_signature THEN
        RETURN NEW;  -- UPDATE que nao toca o selo: livre.
    END IF;

    IF OLD.traits_signature IS NOT NULL THEN
        RAISE EXCEPTION 'CARD_PRINTING_EXTERNAL_MAPPING_SIGNATURE_IMMUTABLE: a assinatura de composição do mapeamento % já foi selada e não pode ser alterada nem removida.', OLD.id;
    END IF;

    v_real := ARRAY(
        SELECT t.trait_id
          FROM public.card_printing_external_mapping_trait t
         WHERE t.mapping_id = NEW.id
         ORDER BY t.trait_id
    );

    IF NEW.traits_signature IS DISTINCT FROM v_real THEN
        RAISE EXCEPTION 'CARD_PRINTING_EXTERNAL_MAPPING_SIGNATURE_MISMATCH: a assinatura informada para o mapeamento % não corresponde à composição real registrada.', NEW.id;
    END IF;

    RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION internal.enforce_card_printing_external_mapping_signature_write() FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_card_printing_external_mapping_signature_write
    ON public.card_printing_external_mapping;

CREATE TRIGGER trg_card_printing_external_mapping_signature_write
BEFORE UPDATE OF traits_signature ON public.card_printing_external_mapping
FOR EACH ROW
EXECUTE FUNCTION internal.enforce_card_printing_external_mapping_signature_write();

COMMIT;

-- ============================================================================
-- Resultado esperado:
--   CREATE FUNCTION x5, REVOKE x5, DROP TRIGGER x5, CREATE TRIGGER x5
--   (um deles CONSTRAINT TRIGGER DEFERRABLE INITIALLY DEFERRED).
--
-- Como validar:
--   Query 2824 - Validate Card Printing Routing, Secoes S3 a S6.
-- ============================================================================
