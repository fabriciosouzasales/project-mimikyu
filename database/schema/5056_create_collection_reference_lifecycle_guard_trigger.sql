/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5056 - Create Collection Reference Lifecycle Guard Trigger
Versão......: 1.1 (endurecida em COLLECTIONS-PHYSICAL-INCREMENT-02D-
               STAGING-REVISION-01, item 1, antes da aplicação real —
               arquivo nunca foi CANÔNICO nessa versão anterior, então
               esta é a primeira aplicação, já na forma endurecida)
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-02 (aplicado em 2026-09-02,
               COLLECTIONS-PHYSICAL-INCREMENT-02D-IMPLEMENTATION-01)

Descrição...:
Impede criar ou remover um Collection Reference enquanto a Collection
não está ACTIVE (C-37, decisão fechada em COLLECTIONS-PHYSICAL-
INCREMENT-02D-MODELING-FINAL-01, item 9: "ARCHIVED bloqueia
configuração standalone").

BLOCKER FECHADO EM -STAGING-REVISION-01 (item 1): o desenho original
(v1.0) só verificava lifecycle_status, permitindo o seguinte cenário
inválido dentro de uma única transação privilegiada: INSERT Collection
REFERENCE_BASED sem Reference -> primeira Allocation materializa
reference_locked_at (Query 5062) -> só então INSERT de Collection
Reference -> COMMIT. Os triggers diferidos de 5057/5058/5059 veem o
estado FINAL consistente (Reference existe) e deixam passar — mas a
regra temporal violada ("REFERENCE_BASED deve possuir sua Reference
ANTES da primeira Allocation", C-18/LDM-07) não é sobre o estado final,
é sobre a ORDEM dos eventos, algo que nenhum trigger diferido consegue
enxergar sozinho (ele só vê o snapshot no COMMIT). A correção não pode
morar nos triggers diferidos — precisa estar numa checagem IMEDIATA no
momento do INSERT do Collection Reference, olhando o valor atual (já
materializado ou não) de reference_locked_at. Adicionado abaixo: no
INSERT, se reference_locked_at já está definido, FAIL. Defesa em
profundidade espelhada no lado do subtipo (Query 5055, mesma rodada).
Validado em execução real (COLLECTIONS-PHYSICAL-INCREMENT-02D-
IMPLEMENTATION-01, Caso Z de 5808).

Sob fluxo normal do V1, criar Reference só acontece dentro de
create_reference_based_card_set_collection() (Query 5065), que sempre
insere uma Collection nova — nasce ACTIVE por definição (C-30) — então
este guard nunca deveria disparar em produção pelo caminho de INSERT.
Mesmo assim, ele existe: nenhuma superfície de aplicação expõe DELETE
de Reference isoladamente, mas "mesmo que a aplicação não exponha,
enforcement estrutural deve permanecer coerente" (instrução explícita
da rodada) — cobre bypass direto/futuro.

DELETE standalone (Collection continua existindo, ARCHIVED) é
bloqueado. DELETE em CASCATA (a Collection inteira está sendo
excluída via delete_collection(), inclusive uma Collection ARCHIVED —
delete_collection() nunca exigiu ACTIVE) precisa continuar
funcionando. A distinção usa a mesma técnica de "a linha pai ainda
existe?": quando o DELETE desta linha é consequência do ON DELETE
CASCADE de collection_reference.collection_id -> collection(id), a
linha de collection já foi removida (dentro da mesma transação, antes
da ação de CASCADE dos filhos disparar) — SELECT ... FROM collection
WHERE id = OLD.collection_id não encontra nada, e o guard deixa
passar. Validado em execução real (5808, Casos T/U/V).

STATUS DESTA QUERY: CONFIRMADO EXECUTADO.
================================================================
*/

CREATE FUNCTION public.validate_collection_reference_lifecycle_guard()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_collection_id       UUID := COALESCE(NEW.collection_id, OLD.collection_id);
    v_lifecycle_status    TEXT;
    v_reference_locked_at TIMESTAMPTZ;
BEGIN
    SELECT col.lifecycle_status, col.reference_locked_at
    INTO v_lifecycle_status, v_reference_locked_at
    FROM public.collection col
    WHERE col.id = v_collection_id;

    IF NOT FOUND THEN
        -- A Collection já não existe nesta transação (DELETE CASCADE
        -- da própria Collection) — nada a bloquear.
        RETURN COALESCE(NEW, OLD);
    END IF;

    IF v_lifecycle_status <> 'ACTIVE' THEN
        IF TG_OP = 'INSERT' THEN
            RAISE EXCEPTION 'collection is archived — reactivate before creating a Collection Reference';
        ELSE
            RAISE EXCEPTION 'collection is archived — reactivate before removing a Collection Reference';
        END IF;
    END IF;

    -- BLOCKER (-STAGING-REVISION-01, item 1): uma Collection Reference
    -- nunca pode nascer depois que reference_locked_at já foi
    -- materializado por uma Allocation anterior — a Reference precisa
    -- preceder a primeira Allocation, não apenas coexistir com ela no
    -- estado final. Checagem imediata (não diferida): olha o valor
    -- atual de reference_locked_at no momento exato deste INSERT.
    IF TG_OP = 'INSERT' AND v_reference_locked_at IS NOT NULL THEN
        RAISE EXCEPTION 'reference_locked_at already set — a Collection Reference must be created before the first Allocation, not after';
    END IF;

    RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE TRIGGER trg_collection_reference_lifecycle_guard
    BEFORE INSERT OR DELETE ON public.collection_reference
    FOR EACH ROW
    EXECUTE FUNCTION public.validate_collection_reference_lifecycle_guard();

REVOKE EXECUTE ON FUNCTION public.validate_collection_reference_lifecycle_guard() FROM PUBLIC, anon, authenticated;
