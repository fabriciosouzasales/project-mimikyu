/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5059 - Create Collection Reference Presence Trigger (PROPOSTA)
Versão......: 1.0
Status......: PROPOSTA — NÃO EXECUTADA
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-02 (COLLECTIONS-PHYSICAL-INCREMENT-02D-
               MODELING-01/-REVISION-01/-FINAL-01)

Descrição...:
Fecha a outra metade do enforcement mode <-> Reference (ver Query
5057) — o lado de collection. Sem esta trigger, o cenário "INSERT INTO
collection (mode = 'REFERENCE_BASED') e nunca inserir nenhuma linha em
collection_reference na mesma transação" nunca dispararia nenhum
evento sobre collection_reference, então nenhuma checagem rodaria
sobre uma tabela que nunca recebeu evento — o COMMIT passaria,
deixando uma Collection REFERENCE_BASED sem Reference, exatamente o
estado inválido que esta rodada existe para impedir.

AFTER INSERT apenas — não precisa cobrir UPDATE, porque mode é
imutável após a criação (Query 5061, extensão de 5032/5044): a única
janela em que mode é definido é o INSERT.

DEFERRABLE INITIALLY DEFERRED pelo mesmo motivo de 5057/5058: uma
trigger imediata dispararia logo após o INSERT em collection, antes de
a RPC (Query 5065) ter tido a chance de inserir collection_reference
e collection_card_set_reference nas duas próximas statements da mesma
transação — falharia sempre. Deferida, só avalia no COMMIT, quando as
três linhas já existem.

OPEN_CURATION não precisa de checagem nesta trigger — a direção
"OPEN_CURATION com Reference" já é coberta do lado de
collection_reference (Query 5057), que dispara sempre que uma linha é
inserida ali, seja qual for o mode da Collection.

EXECUTE revogado de PUBLIC/anon/authenticated.

STATUS DESTA QUERY: PROPOSTA — NÃO EXECUTADA.
================================================================
*/

CREATE FUNCTION public.validate_collection_reference_presence()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    IF NEW.mode = 'REFERENCE_BASED' THEN
        IF NOT EXISTS (
            SELECT 1 FROM public.collection_reference cr WHERE cr.collection_id = NEW.id
        ) THEN
            RAISE EXCEPTION 'REFERENCE_BASED collection must have exactly one Collection Reference';
        END IF;
    END IF;

    RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER trg_collection_reference_presence
    AFTER INSERT ON public.collection
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW
    EXECUTE FUNCTION public.validate_collection_reference_presence();

REVOKE EXECUTE ON FUNCTION public.validate_collection_reference_presence() FROM PUBLIC, anon, authenticated;
