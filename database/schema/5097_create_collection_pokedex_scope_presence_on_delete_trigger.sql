/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5097 - Create Collection Pokedex Scope Presence Trigger, lado Generation/On Delete
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-05 (staging em COLLECTIONS-POKEDEX-FATIA-B-PHYSICAL-
               MODELING-AUDIT-01, renumerada em REVISION-01; aplicado em
               2026-09-05 via COLLECTIONS-POKEDEX-FATIA-B-IMPLEMENTATION-01)

Descrição...:
Espelha o papel da Query 5077 (Master Set Scope Presence Trigger On
Delete) — CONSTRAINT TRIGGER DEFERRABLE INITIALLY DEFERRED, AFTER
DELETE ON collection_pokedex_scope_generation, chamando o mesmo helper
da Query 5094. Só precisa reagir a DELETE (nunca INSERT) pela mesma
razão de 5077: a Query 5095 (eligibility, imediata) já impede que uma
linha seja inserida enquanto scope_kind não é GENERATION_FILTERED —
logo a única forma de a invariante quebrar a partir desta tabela é
remover a ÚLTIMA linha restante enquanto scope_kind ainda é
GENERATION_FILTERED, sem trocar scope_kind de volta para
FULL_REFERENCE na mesma transação.

`DELETE` cascateado por exclusão da própria Collection (ou de sua
Reference) sempre passa — no momento em que esta trigger dispara
(diferida, no COMMIT), a collection_pokedex_reference já não existe
mais, e o helper (5094) retorna sem checar nada (mesmo padrão "a linha
pai ainda existe?" de 5057/5075/5077).

Aplicação real (COLLECTIONS-POKEDEX-FATIA-B-IMPLEMENTATION-01): aplicada
via apply_migration/MCP do Supabase (projeto qjfutqujxrbzgrtkpgkg), uma
Query por vez, na ordem exata 5085→5099, sem alteração de SQL. Postcheck
físico independente (COLLECTIONS-POKEDEX-FATIA-B-CANONICAL-PROMOTION-01)
confirmou a CONSTRAINT TRIGGER DEFERRABLE INITIALLY DEFERRED e a função
presentes, EXECUTE revogado de PUBLIC/anon/authenticated. Validado
funcionalmente pela troca de scope FULL_REFERENCE→GENERATION_FILTERED→
FULL_REFERENCE (DELETE total das Generations acompanhado do retorno a
FULL_REFERENCE na mesma transação, via 5099), em BEGIN/ROLLBACK. Zero
resíduo.

STATUS DESTA QUERY: CONFIRMADO EXECUTADO.
================================================================
*/

BEGIN;

CREATE FUNCTION public.enforce_collection_pokedex_scope_presence_on_delete()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    PERFORM public.check_collection_pokedex_scope_presence(OLD.collection_reference_id);

    RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER trg_collection_pokedex_scope_presence_on_delete
    AFTER DELETE ON public.collection_pokedex_scope_generation
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW
    EXECUTE FUNCTION public.enforce_collection_pokedex_scope_presence_on_delete();

REVOKE EXECUTE ON FUNCTION public.enforce_collection_pokedex_scope_presence_on_delete()
    FROM PUBLIC, anon, authenticated;

COMMIT;
