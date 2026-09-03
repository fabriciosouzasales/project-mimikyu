/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5073 - Create Collection Master Set Scope Eligibility Trigger
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-02 (aplicado em 2026-09-02,
               COLLECTIONS-PHYSICAL-INCREMENT-02F-IMPLEMENTATION-01)

Descrição...:
Enforcement IMEDIATO (não diferido), independente de qualquer
comportamento de RPC — mesma disciplina de
`validate_collection_card_set_reference_game_and_lock()` (5055, 02D).
`BEFORE INSERT` em `collection_master_set_scope`, uma única função
combinando as duas condições que MODELING-FINAL-FIX-01/02 tratam como
um único gate de "IMMEDIATE ELIGIBILITY":

A. A Collection referenciada deve ser `mode = 'REFERENCE_BASED'` e a
   Collection Reference correspondente deve ser `reference_kind =
   'CARD_SET'` — Master Set é especificamente a variante CARD_SET de
   REFERENCE_BASED (LDM-08: "Card Set -> STANDARD_SET ou MASTER_SET";
   Pokédex -> REFERENCE_POSITION, nunca MASTER_SET). Não basta checar
   `mode`, porque um futuro segundo subtipo de Reference (POKEDEX)
   também seria `REFERENCE_BASED` sem nunca dever aceitar Master Set
   Scope.
B. A `card_variant_id` inserida deve pertencer, via `card_variant ->
   card -> card.card_set_id`, ao mesmo Card Set referenciado pela
   Collection (`collection_card_set_reference.card_set_id`) — mesmo
   padrão de "Elegibilidade de Reference" já usado para
   `collection_allocation` (5063/5042 v1.2, 02D).

Fail-closed: qualquer uma das duas condições falhando aborta o
`INSERT` inteiro (`RAISE EXCEPTION`) — nunca insere parcialmente.

Como `mode` é estruturalmente imutável (5032) e `collection_reference`
nunca reparent (5051), a condição A, na prática, nunca falha depois do
primeiro `INSERT` bem-sucedido de Scope numa Collection — mas
permanece como camada estrutural independente de RPC, mesma
disciplina do domínio inteiro (nunca confiar só na RPC se comportar
bem).

SECURITY DEFINER porque a checagem precisa enxergar
`collection_reference`/`collection_card_set_reference`/`card_variant`/
`card` de forma consistente independentemente de qual role dispara o
`INSERT` (sempre uma das RPCs `SECURITY DEFINER` desta pasta, nunca
`authenticated` diretamente — não existe policy de INSERT para
`authenticated` em `collection_master_set_scope`). `EXECUTE` revogado
de `PUBLIC`/`anon`/`authenticated` — função de trigger, não uma RPC.

Aplicação real (COLLECTIONS-PHYSICAL-INCREMENT-02F-IMPLEMENTATION-01):
aplicada via apply_migration; postcheck físico confirmou trigger e
GRANTs idênticos a esta definição. Validado funcionalmente em 5812
(114/114 PASS, zero resíduo).

STATUS DESTA QUERY: CONFIRMADO EXECUTADO.
================================================================
*/

CREATE OR REPLACE FUNCTION public.validate_master_set_scope_eligibility()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_reference_kind TEXT;
    v_card_set_id    UUID;
    v_variant_set_id UUID;
BEGIN
    -- Condição A: mode = REFERENCE_BASED + reference_kind = CARD_SET.
    SELECT cr.reference_kind, ccsr.card_set_id
      INTO v_reference_kind, v_card_set_id
    FROM public.collection c
    JOIN public.collection_reference cr
        ON cr.collection_id = c.id
    LEFT JOIN public.collection_card_set_reference ccsr
        ON ccsr.collection_reference_id = cr.id
    WHERE c.id = NEW.collection_id
      AND c.mode = 'REFERENCE_BASED';

    IF v_reference_kind IS DISTINCT FROM 'CARD_SET' OR v_card_set_id IS NULL THEN
        RAISE EXCEPTION 'master set scope requires a REFERENCE_BASED/CARD_SET collection (collection_id=%)', NEW.collection_id
            USING ERRCODE = 'check_violation';
    END IF;

    -- Condição B: card_variant pertence ao mesmo Card Set referenciado.
    SELECT card.card_set_id
      INTO v_variant_set_id
    FROM public.card_variant cv
    JOIN public.card card ON card.id = cv.card_id
    WHERE cv.id = NEW.card_variant_id;

    IF v_variant_set_id IS DISTINCT FROM v_card_set_id THEN
        RAISE EXCEPTION 'card_variant % does not belong to the card set referenced by collection %', NEW.card_variant_id, NEW.collection_id
            USING ERRCODE = 'check_violation';
    END IF;

    RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.validate_master_set_scope_eligibility() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.validate_master_set_scope_eligibility() FROM anon;
REVOKE ALL ON FUNCTION public.validate_master_set_scope_eligibility() FROM authenticated;

CREATE TRIGGER trg_collection_master_set_scope_eligibility
    BEFORE INSERT ON public.collection_master_set_scope
    FOR EACH ROW
    EXECUTE FUNCTION public.validate_master_set_scope_eligibility();
