/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5144 - claim_bulk_operation(): claim atômico de idempotência
Versão......: 1.1
Status......: CONFIRMADO EXECUTADO (2026-09-07)
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-07 (criado em
               COLLECTIONS-BULK-01-PHYSICAL-PROPOSAL-01;
               v1.1 em -REVISION-01)

v1.1 — duas correções, incorporadas ANTES da aplicação (a v1.0 nunca
chegou ao banco):
  (a) removida a premissa "0 linhas do INSERT => linha COMMITTADA".
      Ela é FALSA: 0 linhas significa apenas "existe linha VISÍVEL
      para esta transação com esta chave", e essa linha pode ser a da
      PRÓPRIA transação, ainda com `result_summary` NULL. O desfecho
      passa a ser decidido pelo ESTADO LIDO, não pela contagem;
  (b) `p_preview_fingerprint` deixa de ter DEFAULT NULL — a coluna é
      NOT NULL desde `5142` v1.1.

Descrição...:
Helper INTERNO. Resolve, sem corrida, os desfechos de uma chave de
idempotência:

    CLAIMED   -> a chave é nossa, prossiga
    REPLAY    -> operação CONCLUÍDA com a MESMA requisição; devolve o
                 result_summary original, zero escrita
    CONFLICT  -> mesma chave, requisição DIFERENTE. O chamador
                 (BULK-02/BULK-04) traduz este outcome no erro de
                 contrato `BULK_IDEMPOTENCY_CONFLICT`

Chamado como PASSO 3 de B1/B2 (BULK-02/BULK-04), depois dos guards de
payload e ANTES de qualquer lock ou escrita de patrimônio.

POR QUE `INSERT ... ON CONFLICT DO NOTHING` E NÃO `SELECT` ANTES
---------------------------------------------------------------
`SELECT` antes de `INSERT` é corrida: entre a leitura e a escrita,
outra sessão insere a mesma chave. Não existe consulta que feche essa
janela sem lock explícito.

`INSERT ... ON CONFLICT DO NOTHING` fecha porque o PRÓPRIO ÍNDICE
ÚNICO é o mecanismo de serialização:

  - conflito com linha JÁ VISÍVEL     -> 0 linhas inseridas,
                                         imediatamente;
  - conflito com linha AINDA EM VOO
    de OUTRA sessão                   -> a instrução BLOQUEIA até a
                                         outra transação resolver;
                                         quando ela resolve:
        outra COMMITOU   -> 0 linhas -> decidimos pelo estado lido
        outra ABORTOU    -> a linha some -> NOSSO insert sucede
                                         -> CLAIMED

Ou seja: as três provas exigidas saem do índice, não de código de
aplicação.

  (1) commit do primeiro  -> segundo vira REPLAY ou CONFLICT
  (2) rollback do primeiro-> segundo consegue o claim
  (3) o UNIQUE e' o serializador

O QUE "0 LINHAS" SIGNIFICA — E O QUE NÃO SIGNIFICA
--------------------------------------------------
Significa APENAS: existe, VISÍVEL para esta transação, uma linha com
esta chave. NÃO significa "existe linha committada". Dois casos reais
produzem 0 linhas com linha NÃO committada:

  - a linha é da PRÓPRIA transação (claim duplicado no mesmo fluxo);
  - uma sessão concorrente committou uma linha que, por defeito ainda
    não conhecido, ficou com `result_summary` NULL.

Tratar qualquer um dos dois como REPLAY devolveria `result_summary`
NULL ao chamador como se fosse resultado legítimo de uma operação
concluída — patrimônio nunca criado apresentado como criado. Por isso
o desfecho é decidido pelo ESTADO LIDO:

    linha ausente                        -> invariante interno (55000)
    request_hash diferente               -> CONFLICT
    mesmo hash + result_summary NULL     -> invariante interno (55000)
                                            NUNCA REPLAY
    mesmo hash + result_summary NOT NULL -> REPLAY

O caso "mesmo hash + NULL" é, sob o contrato vigente, inalcançável em
produção — o constraint trigger de `5143` impede que uma linha assim
seja committada. Ele é tratado assim mesmo por ser exatamente a
situação em que a premissa antiga mentiria. Falhar alto aqui é o
comportamento correto: é bug de fluxo do chamador, não desfecho de
negócio.

REPLAY É INDEPENDENTE DO MUNDO (D9)
-----------------------------------
Esta função NÃO valida `preview_fingerprint`. Fingerprint é do caminho
NOVO (passo 5 de B1/B2). Um replay devolve o resultado original mesmo
que o catálogo, a Collection ou o Adopted Scope tenham mudado depois —
decisão explícita: repetir a mesma intenção já concluída não pode
falhar por causa do mundo ter andado.

Consequência assumida: se o usuário apagou depois as cartas criadas, o
replay ainda devolve os ids originais. É o comportamento correto de um
replay.

RESULT_SUMMARY NO CLAIM
-----------------------
O claim entra com `result_summary` NULL — por isso a Query `5143`
existe. Quem completa é `5145`, na mesma transação.

SEGURANÇA
---------
`SECURITY DEFINER`, `search_path = ''`, owner `postgres`. `EXECUTE`
REVOGADO de PUBLIC/anon/authenticated/service_role: este helper NÃO é
uma RPC pública. Só as funções `SECURITY DEFINER` de BULK-02/BULK-04,
que rodam como `postgres`, o alcançam. Mesmo padrão de `5122`
(`assert_collection_layout_mutable`), que também é helper interno sem
EXECUTE para `authenticated`.

`auth.uid()` é verificado aqui e é o ÚNICO determinante de
`owner_user_id` — o chamador nunca informa o dono.

Dependências: public.bulk_operation (5142), trigger de 5143.

STATUS DESTA QUERY: CONFIRMADO EXECUTADO (2026-09-07). Ledger e
evidencia de validacao no README.md desta pasta.
================================================================
*/

BEGIN;

CREATE FUNCTION public.claim_bulk_operation(
    p_operation_type      TEXT,
    p_idempotency_key     UUID,
    p_request_hash        TEXT,
    p_preview_fingerprint TEXT
)
RETURNS TABLE (
    outcome        TEXT,
    operation_id   UUID,
    result_summary JSONB
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_owner    UUID;
    v_new_id   UUID;
    v_existing RECORD;
BEGIN
    v_owner := (select auth.uid());

    IF v_owner IS NULL THEN
        RAISE EXCEPTION 'authentication required' USING ERRCODE = '28000';
    END IF;

    IF p_idempotency_key IS NULL THEN
        RAISE EXCEPTION 'idempotency_key e obrigatoria' USING ERRCODE = '22023';
    END IF;

    IF p_request_hash IS NULL OR btrim(p_request_hash) = '' THEN
        RAISE EXCEPTION 'request_hash e obrigatorio' USING ERRCODE = '22023';
    END IF;

    -- preview_fingerprint e NOT NULL na tabela (5142 v1.1): os dois
    -- operation_type do vocabulario atual exigem preview.
    IF p_preview_fingerprint IS NULL OR btrim(p_preview_fingerprint) = '' THEN
        RAISE EXCEPTION 'preview_fingerprint e obrigatorio' USING ERRCODE = '22023';
    END IF;

    -- ================================================================
    -- CLAIM ATOMICO. Sem SELECT-antes-de-INSERT.
    -- O indice uq_bulk_operation_owner_type_key serializa sessoes
    -- concorrentes: com linha em voo esta instrucao BLOQUEIA ate a
    -- outra transacao resolver.
    -- ================================================================
    INSERT INTO public.bulk_operation
        (owner_user_id, operation_type, idempotency_key,
         request_hash, preview_fingerprint, result_summary)
    VALUES
        (v_owner, p_operation_type, p_idempotency_key,
         p_request_hash, p_preview_fingerprint, NULL)
    ON CONFLICT ON CONSTRAINT uq_bulk_operation_owner_type_key DO NOTHING
    RETURNING public.bulk_operation.id INTO v_new_id;

    IF v_new_id IS NOT NULL THEN
        -- Caminho novo. A operacao segue para lock, fingerprint e escrita.
        RETURN QUERY SELECT 'CLAIMED'::TEXT, v_new_id, NULL::JSONB;
        RETURN;
    END IF;

    -- ================================================================
    -- 0 linhas inseridas. Isso significa SOMENTE que existe linha
    -- VISIVEL com esta chave — NAO que ela esteja committada nem
    -- concluida. O desfecho e decidido pelo ESTADO LIDO abaixo.
    -- ================================================================
    SELECT b.id, b.request_hash, b.result_summary
      INTO v_existing
      FROM public.bulk_operation b
     WHERE b.owner_user_id   = v_owner
       AND b.operation_type  = p_operation_type
       AND b.idempotency_key = p_idempotency_key;

    IF NOT FOUND THEN
        -- Estado impossivel sob o contrato vigente (nao ha DELETE
        -- concedido a ninguem). Falha ALTO em vez de seguir adiante.
        RAISE EXCEPTION
            'estado inconsistente: conflito de idempotencia sem linha correspondente'
            USING ERRCODE = '55000';
    END IF;

    IF v_existing.request_hash IS DISTINCT FROM p_request_hash THEN
        -- Mesma chave, INTENCAO diferente. O chamador traduz este
        -- outcome em BULK_IDEMPOTENCY_CONFLICT.
        RETURN QUERY SELECT 'CONFLICT'::TEXT, v_existing.id, NULL::JSONB;
        RETURN;
    END IF;

    IF v_existing.result_summary IS NULL THEN
        -- MESMA intencao, mas a operacao NAO esta concluida.
        -- NUNCA REPLAY: devolver NULL como resultado apresentaria
        -- patrimonio nunca criado como criado.
        -- Ou e claim duplicado dentro da propria transacao (bug de
        -- fluxo do chamador), ou e linha committada sem resultado
        -- (violacao do invariante de 5143). Nos dois casos, falha alto.
        RAISE EXCEPTION
            'estado inconsistente: claim % existente com result_summary NULL — operacao incompleta, replay recusado',
            v_existing.id
            USING ERRCODE = '55000';
    END IF;

    -- REPLAY. Zero escrita. Fingerprint NAO e consultado aqui (D9).
    RETURN QUERY SELECT 'REPLAY'::TEXT, v_existing.id, v_existing.result_summary;
END;
$$;

COMMENT ON FUNCTION public.claim_bulk_operation(TEXT, UUID, TEXT, TEXT) IS
    'Helper INTERNO de idempotencia Bulk. INSERT ... ON CONFLICT DO NOTHING, sem SELECT-antes-de-INSERT: o indice unico e o serializador. 0 linhas NAO significa "linha committada" — o desfecho e decidido pelo estado lido: hash diferente => CONFLICT; mesmo hash com result_summary NULL => erro de invariante interno (NUNCA REPLAY); mesmo hash com result_summary preenchido => REPLAY. Nao valida preview_fingerprint — replay e independente do estado do mundo (D9). EXECUTE revogado de todos os papeis.';

REVOKE EXECUTE ON FUNCTION public.claim_bulk_operation(TEXT, UUID, TEXT, TEXT)
    FROM PUBLIC, anon, authenticated, service_role;

COMMIT;

/*
Como validar (APÓS aplicar): harness `5821`, grupos C (sessão única) e
K (duas sessões reais — prova externa, ver runbook desta pasta).

Prova estática esperada:
- corpo contém 'ON CONFLICT ON CONSTRAINT uq_bulk_operation_owner_type_key DO NOTHING';
- corpo NÃO contém nenhum SELECT sobre bulk_operation ANTES do INSERT.
*/
