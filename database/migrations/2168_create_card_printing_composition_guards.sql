/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 2168 - Create Card Printing Composition Guards
Versão......: 1.1
Status......: CONFIRMADO EXECUTADO / LIVE
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-12
Mandato.....: CARD-VARIANTS — PRINTING-MODEL-STAGING-01 — GATE-A-01 (§10, §11)
               + GATE-A-CORRECTION-01 (v1.1)

-------------------------------------------------------------------------------
EXECUÇÃO CONFIRMADA — 2026-09-12
-------------------------------------------------------------------------------
Executado via apply_migration no projeto Supabase qjfutqujxrbzgrtkpgkg.
Ordem de aplicacao: 2165 -> 2166 -> 2167 -> 2168 -> 2169 -> 2170 -> 2171.
Todas as sete aplicadas sem erro.
Estado final validado integralmente pela Query 2823 v1.2:
    12 PASS / 0 FAIL / 0 NOT PROVEN, zero residuo.
O SQL executavel permanece INTOCADO desde a execucao.
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
v1.1 — O QUE MUDOU E POR QUE
-------------------------------------------------------------------------------
1. FIM DO MD5. A unicidade de composicao deixa de depender de
   md5(string_agg(...)) e passa a usar traits_signature UUID[] — o
   conjunto materializado, comparado elemento a elemento. Igualdade
   EXATA, nao probabilistica.

2. FIM DO created_at COMO AUTORIDADE. A imutabilidade deixa de inferir
   "mesma transacao" comparando created_at com transaction_timestamp() e
   passa a ler ESTADO SEMANTICO explicito:
       traits_signature IS NULL      -> em montagem, mutavel
       traits_signature IS NOT NULL  -> SELADO, imutavel
   Metadado temporal nao e autorizacao.

3. PROFILE VAZIO VIROU FAIL-CLOSED. Na v1.0, um Profile sem nenhum
   vinculo simplesmente nao disparava trigger nenhum (nao havia linha na
   N:N para disparar) — a limitacao ficou documentada como S5b e NAO foi
   aprovada. Agora o trigger deferido esta sobre card_printing_profile
   INSERT, nao sobre a N:N. Ele dispara UMA VEZ POR PROFILE, sempre,
   inclusive quando nenhum vinculo existe.

4. SIMPLIFICACAO REAL. O trigger deferido por vinculo desapareceu. Um
   unico trigger deferido por Profile faz as duas coisas — valida
   nao-vazio e sela — porque no COMMIT ele ja enxerga a composicao final.

-------------------------------------------------------------------------------
TRES GUARDS
-------------------------------------------------------------------------------
A) internal.seal_printing_profile_composition()
   CONSTRAINT TRIGGER AFTER INSERT ON card_printing_profile,
   DEFERRABLE INITIALLY DEFERRED. Dispara 1x por Profile, no COMMIT:
     - se o Profile ja nao existir (criado e removido na mesma transacao):
       retorna sem erro — sem falso positivo;
     - conta os vinculos; se 0 -> EXCEPTION (§3 do mandato);
     - monta traits_signature = ARRAY(SELECT trait_id ORDER BY trait_id);
     - grava. O INDICE UNICO uq_card_printing_profile_game_signature e
       avaliado NESTE UPDATE e e a AUTORIDADE FINAL da invariante de
       composicao unica, inclusive sob concorrencia.

B) internal.enforce_printing_profile_composition_immutable()
   BEFORE INSERT OR UPDATE OR DELETE ON card_printing_profile_trait.
   Le o estado de selamento do Profile:
     - UPDATE de vinculo: SEMPRE proibido;
     - Profile SELADO (signature NOT NULL): INSERT/DELETE proibidos;
     - Profile EM MONTAGEM (signature NULL): permitido;
     - reinsercao IDENTICA em Profile selado: permitida (no-op semantico),
       para que a seed com ON CONFLICT DO NOTHING continue idempotente.

C) internal.enforce_printing_profile_signature_write()
   BEFORE UPDATE ON card_printing_profile. Impede "destravar" ou
   falsificar o selo por UPDATE comum:
     - signature ja definida e tentando mudar (inclusive voltar a NULL):
       EXCEPTION;
     - signature indo de NULL para um valor: so aceita se o valor
       corresponder EXATAMENTE ao conjunto real da N:N naquele instante.
   Com isso, nem o owner consegue gravar um selo que nao corresponde a
   composicao.

-------------------------------------------------------------------------------
CONCORRENCIA
-------------------------------------------------------------------------------
T1 cria PROFILE_A com {A,B}; T2 cria PROFILE_B com {A,B}, simultaneamente.
No COMMIT, ambos os triggers A calculam o MESMO array ordenado e tentam
gravar. O indice unico parcial serializa: um comita, o outro falha com
unique_violation. A protecao NAO e um SELECT EXISTS seguido de escrita —
e o indice. Mesma licao ja aplicada na Query 2164.

-------------------------------------------------------------------------------
CORORALIO RATIFICADO
-------------------------------------------------------------------------------
Corrigir a composicao de um Profile existente NAO e um UPDATE — e criar um
Profile novo e reconciliar explicitamente as card_variant. A RPC editorial
que fara isso NAO faz parte deste Gate. Nao existe caminho de "destravar".

Pré-requisitos:
- Query 2166 v1.1 (coluna traits_signature UUID[] e indice unico parcial).
- Query 2167 - Create Card Printing Profile Trait Table.
===============================================================================
*/

BEGIN;

-- ---------------------------------------------------------------------------
-- GUARD A — nao-vazio + selamento (deferido, 1x por Profile)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION internal.seal_printing_profile_composition()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_signature UUID[];
BEGIN
    -- Profile criado e removido na mesma transacao: nada a validar nem a
    -- selar. Evita falso positivo em rollback/delete intra-transacao.
    IF NOT EXISTS (SELECT 1 FROM public.card_printing_profile p WHERE p.id = NEW.id) THEN
        RETURN NULL;
    END IF;

    -- Conjunto canonico: ordenado ascendente pelo proprio trait_id.
    -- ARRAY(SELECT ...) devolve '{}' quando nao ha linhas — nunca NULL.
    v_signature := ARRAY(
        SELECT t.trait_id
          FROM public.card_printing_profile_trait t
         WHERE t.profile_id = NEW.id
         ORDER BY t.trait_id
    );

    -- §3 — PROFILE VAZIO E SEMANTICAMENTE INVALIDO. Fail-closed no COMMIT.
    IF cardinality(v_signature) = 0 THEN
        RAISE EXCEPTION 'CARD_PRINTING_PROFILE_EMPTY_COMPOSITION: o Perfil de Impressão % chegou ao COMMIT sem nenhuma Característica de Impressão. Todo Perfil precisa de ao menos uma.', NEW.id;
    END IF;

    -- Selamento. O UPDATE abaixo e avaliado pelo indice unico
    -- uq_card_printing_profile_game_signature — e ele, nao esta funcao,
    -- que rejeita composicao duplicada. Por isso e seguro sob concorrencia.
    UPDATE public.card_printing_profile
       SET traits_signature = v_signature
     WHERE id = NEW.id;

    RETURN NULL;
END;
$$;

REVOKE ALL ON FUNCTION internal.seal_printing_profile_composition() FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_card_printing_profile_seal
    ON public.card_printing_profile;

CREATE CONSTRAINT TRIGGER trg_card_printing_profile_seal
AFTER INSERT ON public.card_printing_profile
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
EXECUTE FUNCTION internal.seal_printing_profile_composition();

-- ---------------------------------------------------------------------------
-- GUARD B — imutabilidade da composicao (estado de selamento, nao relogio)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION internal.enforce_printing_profile_composition_immutable()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_profile_id UUID;
    v_signature UUID[];
    v_exists BOOLEAN;
BEGIN
    IF TG_OP = 'UPDATE' THEN
        RAISE EXCEPTION 'CARD_PRINTING_PROFILE_TRAIT_UPDATE_FORBIDDEN: vínculo de composição nunca pode ser atualizado. Crie um Perfil novo e reconcilie.';
    END IF;

    v_profile_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.profile_id ELSE NEW.profile_id END;

    SELECT p.traits_signature, TRUE INTO v_signature, v_exists
      FROM public.card_printing_profile p
     WHERE p.id = v_profile_id;

    -- Profile sendo removido na mesma transacao: nada a proteger.
    IF v_exists IS NULL THEN
        RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
    END IF;

    -- EM MONTAGEM: a composicao ainda pode ser escrita livremente.
    IF v_signature IS NULL THEN
        RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
    END IF;

    -- SELADO. Reinsercao IDENTICA nao e mudanca semantica — deixa passar
    -- para que a seed (ON CONFLICT DO NOTHING) continue idempotente.
    -- ATENCAO: este e um trigger BEFORE. No Postgres, triggers BEFORE INSERT
    -- disparam ANTES da arbitragem do ON CONFLICT, ou seja, ele roda mesmo
    -- quando a linha sera descartada. Por isso a excecao explicita abaixo e
    -- obrigatoria — nao da para contar com o ON CONFLICT para suprimir o
    -- disparo. O conjunto nao muda: a linha ja existe, identica.
    IF TG_OP = 'INSERT'
       AND EXISTS (
           SELECT 1 FROM public.card_printing_profile_trait t
            WHERE t.profile_id = NEW.profile_id
              AND t.trait_id = NEW.trait_id
       ) THEN
        RETURN NEW;
    END IF;

    RAISE EXCEPTION 'CARD_PRINTING_PROFILE_COMPOSITION_SEALED: o Perfil de Impressão % já está selado e sua composição é imutável. Crie um Perfil novo e reconcilie as Card Variants.', v_profile_id;
END;
$$;

REVOKE ALL ON FUNCTION internal.enforce_printing_profile_composition_immutable() FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_card_printing_profile_trait_immutable
    ON public.card_printing_profile_trait;

CREATE TRIGGER trg_card_printing_profile_trait_immutable
BEFORE INSERT OR UPDATE OR DELETE ON public.card_printing_profile_trait
FOR EACH ROW
EXECUTE FUNCTION internal.enforce_printing_profile_composition_immutable();

-- ---------------------------------------------------------------------------
-- GUARD C — o selo nao pode ser destravado nem falsificado por UPDATE comum
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION internal.enforce_printing_profile_signature_write()
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

    -- Ja selado: nenhuma mudanca, nem mesmo voltar a NULL.
    IF OLD.traits_signature IS NOT NULL THEN
        RAISE EXCEPTION 'CARD_PRINTING_PROFILE_SIGNATURE_IMMUTABLE: a assinatura de composição do Perfil % já foi selada e não pode ser alterada nem removida.', OLD.id;
    END IF;

    -- Selando agora: o valor precisa corresponder EXATAMENTE a composicao
    -- real. Impede selo falsificado mesmo por escrita direta do owner.
    v_real := ARRAY(
        SELECT t.trait_id
          FROM public.card_printing_profile_trait t
         WHERE t.profile_id = NEW.id
         ORDER BY t.trait_id
    );

    IF NEW.traits_signature IS DISTINCT FROM v_real THEN
        RAISE EXCEPTION 'CARD_PRINTING_PROFILE_SIGNATURE_MISMATCH: a assinatura informada para o Perfil % não corresponde à composição real registrada.', NEW.id;
    END IF;

    RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION internal.enforce_printing_profile_signature_write() FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_card_printing_profile_signature_write
    ON public.card_printing_profile;

CREATE TRIGGER trg_card_printing_profile_signature_write
BEFORE UPDATE OF traits_signature ON public.card_printing_profile
FOR EACH ROW
EXECUTE FUNCTION internal.enforce_printing_profile_signature_write();

COMMIT;

-- ============================================================================
-- Resultado esperado:
--   CREATE FUNCTION x3, REVOKE x3, DROP TRIGGER x3, CREATE TRIGGER x3.
--
-- Como validar:
--   Query 2823 - Validate Card Printing Model, Secoes 5 (COMPOSICAO/VAZIO)
--   e 6 (SELAMENTO).
-- ============================================================================
