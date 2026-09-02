/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5057 - Create Collection Reference Consistency Trigger (PROPOSTA)
Versão......: 1.0
Status......: PROPOSTA — NÃO EXECUTADA
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-02 (COLLECTIONS-PHYSICAL-INCREMENT-02D-
               MODELING-01/-REVISION-01/-FINAL-01)

Descrição...:
Núcleo do enforcement transacional pedido em COLLECTIONS-PHYSICAL-
INCREMENT-02D-MODELING-REVISION-01 (item 2) — garante, no COMMIT da
transação (não em cada statement isolado), duas invariantes que
nenhuma FK/CHECK isolada consegue expressar, porque cruzam tabelas:

1. mode <-> presença de Collection Reference (LDM-04):
   REFERENCE_BASED <-> exatamente 1 collection_reference;
   OPEN_CURATION    <-> exatamente 0 collection_reference.

2. supertipo <-> subtipo (COLLECTIONS-PHYSICAL-INCREMENT-02D-MODELING-
   FINAL-01, item 1): reference_kind = 'CARD_SET' <-> exatamente 1
   collection_card_set_reference.

CONSTRAINT TRIGGER DEFERRABLE INITIALLY DEFERRED: dispara AFTER
INSERT/UPDATE/DELETE em collection_reference, mas só EXECUTA no
COMMIT da transação (ou em um SET CONSTRAINTS ... IMMEDIATE explícito,
que nenhuma RPC desta rodada precisa invocar). Isso é o que permite a
criação atômica da Query 5065 (Collection -> Collection Reference ->
Card Set Reference, três INSERTs em sequência, na mesma transação):
se a checagem rodasse imediatamente após o primeiro INSERT em
collection_reference, ela veria um estado momentaneamente incompleto
(Card Set Reference ainda não inserida) e falharia sempre — deferida,
ela só olha para o estado final, quando as três linhas já existem.

FOR EACH ROW é a única opção sintática do Postgres para CONSTRAINT
TRIGGER — REFERENCING ... TABLE (transition tables, usado em 5042/
5045) exige FOR EACH STATEMENT, que o Postgres não permite combinar
com CONSTRAINT TRIGGER. Isso é aceitável aqui porque a criação de
Collection/Reference é sempre 1 linha por operação (nunca bulk, ao
contrário de collection_allocation).

Uso do padrão "a linha pai ainda existe?" (IF FOUND) para nunca
disparar exceção quando o evento é consequência de um DELETE CASCADE
da própria Collection (delete_collection(), Query 5039) — nesse caso,
no momento em que esta trigger roda, a Collection já foi removida
dentro da mesma transação, e SELECT ... FROM collection WHERE id = ...
já não encontra nada.

BLOCKER FECHADO NESTA RODADA (COLLECTIONS-PHYSICAL-INCREMENT-02D-
MODELING-FINAL-01, item 1): esta trigger sozinha, disparando só sobre
eventos de collection_reference, NÃO detecta um DELETE ou UPDATE
direto em collection_card_set_reference que quebre a cardinalidade
subtipo (ex.: apagar o subtipo sem tocar o supertipo). Por isso a
checagem de subtipo foi extraída para uma função auxiliar comum,
check_collection_reference_subtype_consistency(), chamada também pelo
trigger da Query 5058 (que reage aos eventos do lado
collection_card_set_reference) — os dois lados agora reagem, cobrindo
os cinco casos exigidos: (A) parent+subtype na mesma transação -> PASS;
(B) parent sem subtype -> FAIL; (C) subtype apagado isoladamente ->
FAIL (via 5058); (D) subtype apontando para kind incompatível futuro
-> FAIL (via 5058); (E) DELETE da Collection inteira via CASCADE ->
PASS.

A garantia inversa — "REFERENCE_BASED criada sem nunca tocar
collection_reference na mesma transação" — não pode ser detectada por
nenhum trigger nesta tabela (ela nunca recebe evento nesse cenário);
é coberta pela Query 5059, do lado de collection.

EXECUTE revogado de PUBLIC/anon/authenticated.

STATUS DESTA QUERY: PROPOSTA — NÃO EXECUTADA.
================================================================
*/

-- Função auxiliar compartilhada entre 5057 e 5058 — único lugar que
-- sabe "o que significa" um Collection Reference estar consistente
-- com seu subtipo. Quando collection_pokedex_reference existir, um
-- novo ramo ELSIF é adicionado aqui (CREATE OR REPLACE), sem alterar
-- os dois triggers que a chamam.
CREATE FUNCTION public.check_collection_reference_subtype_consistency(p_collection_reference_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_kind           TEXT;
    v_subtype_count  INT;
BEGIN
    SELECT cr.reference_kind INTO v_kind
    FROM public.collection_reference cr
    WHERE cr.id = p_collection_reference_id;

    IF NOT FOUND THEN
        -- O próprio Collection Reference já não existe (DELETE CASCADE
        -- da Collection, ou removido nesta mesma transação) — nada a
        -- checar.
        RETURN;
    END IF;

    IF v_kind = 'CARD_SET' THEN
        SELECT count(*) INTO v_subtype_count
        FROM public.collection_card_set_reference ccsr
        WHERE ccsr.collection_reference_id = p_collection_reference_id;

        IF v_subtype_count <> 1 THEN
            RAISE EXCEPTION 'Collection Reference of kind CARD_SET must have exactly one Collection Card Set Reference (found %)', v_subtype_count;
        END IF;
    END IF;
    -- ELSIF v_kind = 'POKEDEX' THEN ... (futuro, quando o subtipo existir)
END;
$$;

REVOKE EXECUTE ON FUNCTION public.check_collection_reference_subtype_consistency(uuid) FROM PUBLIC, anon, authenticated;

CREATE FUNCTION public.validate_collection_reference_consistency()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_collection_id  UUID := COALESCE(NEW.collection_id, OLD.collection_id);
    v_reference_id   UUID := COALESCE(NEW.id, OLD.id);
    v_mode           TEXT;
    v_ref_exists     BOOLEAN;
BEGIN
    SELECT col.mode INTO v_mode
    FROM public.collection col
    WHERE col.id = v_collection_id;

    IF FOUND THEN
        SELECT EXISTS(
            SELECT 1 FROM public.collection_reference cr WHERE cr.collection_id = v_collection_id
        ) INTO v_ref_exists;

        IF v_mode = 'REFERENCE_BASED' AND NOT v_ref_exists THEN
            RAISE EXCEPTION 'REFERENCE_BASED collection must have exactly one Collection Reference';
        END IF;

        IF v_mode = 'OPEN_CURATION' AND v_ref_exists THEN
            RAISE EXCEPTION 'OPEN_CURATION collection cannot have a Collection Reference';
        END IF;
    END IF;

    PERFORM public.check_collection_reference_subtype_consistency(v_reference_id);

    RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER trg_collection_reference_consistency
    AFTER INSERT OR UPDATE OR DELETE ON public.collection_reference
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW
    EXECUTE FUNCTION public.validate_collection_reference_consistency();

REVOKE EXECUTE ON FUNCTION public.validate_collection_reference_consistency() FROM PUBLIC, anon, authenticated;
