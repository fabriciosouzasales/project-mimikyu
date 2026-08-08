/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2122 - Create admin_log_manual_card_asset_import_batch Function
Versão......: 1.0
Status......: MIGRATION — CONFIRMADO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-07

Descrição...:
Function SECURITY DEFINER que grava UMA linha de auditoria agregada
em public.catalog_admin_action_log ao final de um lote de importação
manual de imagens via UI (ADR-026, emenda "Segundo ponto de entrada
via UI") — nunca uma linha por arquivo (mesmo princípio já registrado
na Query 2010 para CATALOG_IMPORT_CONFIRMED: o detalhe fino, quando
existir, mora em outro lugar; aqui não há uma tabela própria de
detalhe por arquivo, então o resumo agregado em metadata é o único
registro).

Chamada uma única vez pelo cliente, depois que todos os arquivos do
lote já passaram por admin_persist_manual_card_asset() (Query 2120)
— sucesso ou falha, individualmente. p_run_id identifica o lote
inteiro (gerado uma vez no navegador via crypto.randomUUID() antes do
primeiro arquivo, repassado a esta chamada final) — ajuste explícito
de Fabrício, 2026-08-07.

Regras de Negócio:
- is_admin() checado explicitamente, mesmo padrão de
  admin_persist_manual_card_asset() (2120).
- p_card_set_id validado contra public.card_set — RAISE EXCEPTION se
  não existir (entity_id de catalog_admin_action_log é NOT NULL e
  sem FK, por ser polimórfico; a validação de existência precisa
  acontecer aqui, não no banco).
- Invariante leve: p_inserted_count + p_updated_count +
  p_failed_count não pode exceder p_files_total — combinação
  impossível indicaria um bug do lado do chamador na contagem.
- metadata grava run_id, language_code, files_total,
  inserted_count, updated_count, failed_count e failures (detalhe
  por arquivo com falha, formato livre — collector_number + motivo,
  mesmo espírito de ImageImportFailureView já usado pelo pipeline
  TCGdex) — retrato completo do lote, sem depender de nenhuma tabela
  auxiliar nova.
- actor_id = auth.uid() (quem confirmou o lote), mesmo padrão de
  todas as admin_* functions do módulo.
- Devolve o id da linha de auditoria criada, para o cliente exibir
  confirmação/permitir rastreio futuro.

Pré-requisitos:
- Query 2010 - Create Catalog Admin Action Log Table.
- Query 2121 - Add Manual Card Asset Import Action to Catalog Admin
  Action Log (CHECK ampliada — sem ela, o INSERT abaixo falharia).
- Query 1060 - Create is_admin() Function.
================================================================
*/

CREATE OR REPLACE FUNCTION public.admin_log_manual_card_asset_import_batch(
    p_card_set_id UUID,
    p_language_code TEXT,
    p_run_id UUID,
    p_files_total INTEGER,
    p_inserted_count INTEGER,
    p_updated_count INTEGER,
    p_failed_count INTEGER,
    p_failures JSONB DEFAULT '[]'::jsonb
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_log_id UUID;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'ADMIN_LOG_MANUAL_CARD_ASSET_IMPORT_BATCH_FORBIDDEN: usuário não é administrador.';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.card_set WHERE id = p_card_set_id) THEN
        RAISE EXCEPTION 'ADMIN_LOG_MANUAL_CARD_ASSET_IMPORT_BATCH_CARD_SET_NOT_FOUND: Card Set % não existe.', p_card_set_id;
    END IF;

    IF p_inserted_count + p_updated_count + p_failed_count > p_files_total THEN
        RAISE EXCEPTION 'ADMIN_LOG_MANUAL_CARD_ASSET_IMPORT_BATCH_INVALID_COUNTS: inserted+updated+failed (%) excede files_total (%).',
            p_inserted_count + p_updated_count + p_failed_count, p_files_total;
    END IF;

    INSERT INTO public.catalog_admin_action_log (
        actor_id, action, entity_type, entity_id, metadata
    ) VALUES (
        auth.uid(),
        'CARD_ASSET_MANUAL_IMPORT_COMPLETED',
        'CARD_SET',
        p_card_set_id,
        jsonb_build_object(
            'run_id', p_run_id,
            'language_code', p_language_code,
            'files_total', p_files_total,
            'inserted_count', p_inserted_count,
            'updated_count', p_updated_count,
            'failed_count', p_failed_count,
            'failures', COALESCE(p_failures, '[]'::jsonb)
        )
    )
    RETURNING id INTO v_log_id;

    RETURN v_log_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_log_manual_card_asset_import_batch(
    UUID, TEXT, UUID, INTEGER, INTEGER, INTEGER, INTEGER, JSONB
) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.admin_log_manual_card_asset_import_batch(
    UUID, TEXT, UUID, INTEGER, INTEGER, INTEGER, INTEGER, JSONB
) TO authenticated;

-- ================================================================
-- Resultado esperado: "Success. No rows returned".
--
-- Como validar (mesma técnica de impersonação da 2120, dentro de uma
-- transação com ROLLBACK — nada fica persistido):
--
-- BEGIN;
-- SELECT set_config(
--     'request.jwt.claims',
--     json_build_object('sub', (SELECT id::text FROM public.admin_user LIMIT 1))::text,
--     true
-- );
--
-- SELECT public.admin_log_manual_card_asset_import_batch(
--     p_card_set_id     => (SELECT id FROM public.card_set LIMIT 1),
--     p_language_code   => 'en',
--     p_run_id          => gen_random_uuid(),
--     p_files_total     => 3,
--     p_inserted_count  => 2,
--     p_updated_count   => 1,
--     p_failed_count    => 0,
--     p_failures        => '[]'::jsonb
-- );
--
-- SELECT * FROM public.catalog_admin_action_log
-- WHERE action = 'CARD_ASSET_MANUAL_IMPORT_COMPLETED'
-- ORDER BY created_at DESC LIMIT 1;
--
-- ROLLBACK;
--
-- Esperado: a função devolve um UUID (id da linha), e o SELECT
-- seguinte (ainda dentro da mesma transação) mostra a linha com
-- metadata contendo run_id/language_code/contadores.
-- ================================================================
--
-- CONFIRMADO EXECUTADO (2026-08-07): smoke test com impersonação +
-- ROLLBACK devolveu a linha esperada em catalog_admin_action_log
-- (run_id/language_code/files_total/inserted_count/updated_count/
-- failed_count/failures todos corretos); nada persistido.
-- ================================================================
