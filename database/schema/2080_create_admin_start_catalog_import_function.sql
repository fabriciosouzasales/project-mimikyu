/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2080 - Create admin_start_catalog_import() Function
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-01

Descrição...:
Cria admin_start_catalog_import(), função pública SECURITY DEFINER —
abre um novo catalog_import_job (Query 2060) para um Card Set. Não
sabe nada sobre PDF nem TCGdex especificamente: só cria o registro
de staging com o identificador de fingerprint do canal informado. A
extração/normalização em si (que popula catalog_import_row) é feita
por processadores específicos de cada canal (Edge Function, fora do
escopo desta Query) — esta função só abre o job em status RECEIVED.

Regras de Negócio:
- Só um administrador pode chamar esta função (is_admin()).
- p_card_set_id deve existir. Este flow pressupõe um Card Set ainda
  sem Cards (o dropdown do frontend já lista só esses) — esta função
  não repete essa validação: um Card Set com Cards não é um erro
  estrutural para admin_start_catalog_import() em si (por exemplo,
  um reprocessamento após falha parcial ainda deve poder abrir um
  novo job), a garantia de "só sets vazios aparecem para o
  administrador" é responsabilidade da consulta que popula o
  dropdown, não desta função.
- p_source restrito a PDF ou TCGDEX. Exatamente um entre
  p_file_checksum (PDF) e p_external_set_id (TCGDEX) deve ser
  informado, de acordo com p_source — mesma regra da constraint
  ck_catalog_import_job_source_identifier (Query 2060); esta função
  antecipa o erro bruto de constraint com uma mensagem administrativa
  clara.
- Se já existir um job ativo (status em RECEIVED/PROCESSING/STAGED/
  CONFIRMING) com o mesmo fingerprint, a constraint
  uq_catalog_import_job_fingerprint_active (Query 2060) rejeita a
  inserção — esta função antecipa esse erro também.
- Toda abertura bem-sucedida grava uma linha em
  catalog_admin_action_log (CATALOG_IMPORT_JOB), com card_set_id e
  source em metadata.

Pré-requisitos:
- Query 2060 - Create Catalog Import Job Table.
- Query 2054 - Widen Catalog Admin Action Log for Catalog Import.
- Query 1060 - Create is_admin() Function.
================================================================
*/

CREATE OR REPLACE FUNCTION public.admin_start_catalog_import(
    p_card_set_id UUID,
    p_source TEXT,
    p_file_checksum TEXT DEFAULT NULL,
    p_external_set_id TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_job_id UUID;
    v_source TEXT;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'ADMIN_START_CATALOG_IMPORT_FORBIDDEN: apenas administradores podem iniciar uma importação de Cards.';
    END IF;

    IF p_card_set_id IS NULL THEN
        RAISE EXCEPTION 'ADMIN_START_CATALOG_IMPORT_MISSING_CARD_SET: p_card_set_id é obrigatório.';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.card_set WHERE id = p_card_set_id) THEN
        RAISE EXCEPTION 'ADMIN_START_CATALOG_IMPORT_CARD_SET_NOT_FOUND: nenhum Card Set encontrado para o id informado (%).', p_card_set_id;
    END IF;

    v_source := UPPER(BTRIM(p_source));

    IF v_source NOT IN ('PDF', 'TCGDEX') THEN
        RAISE EXCEPTION 'ADMIN_START_CATALOG_IMPORT_INVALID_SOURCE: source deve ser PDF ou TCGDEX (recebido: %).', p_source;
    END IF;

    IF v_source = 'PDF' AND (p_file_checksum IS NULL OR p_external_set_id IS NOT NULL) THEN
        RAISE EXCEPTION 'ADMIN_START_CATALOG_IMPORT_INVALID_IDENTIFIER: source PDF exige file_checksum e não aceita external_set_id.';
    END IF;

    IF v_source = 'TCGDEX' AND (p_external_set_id IS NULL OR p_file_checksum IS NOT NULL) THEN
        RAISE EXCEPTION 'ADMIN_START_CATALOG_IMPORT_INVALID_IDENTIFIER: source TCGDEX exige external_set_id e não aceita file_checksum.';
    END IF;

    BEGIN
        INSERT INTO public.catalog_import_job (
            card_set_id, source, file_checksum, external_set_id, status, initiated_by
        ) VALUES (
            p_card_set_id, v_source, p_file_checksum, p_external_set_id, 'RECEIVED', auth.uid()
        )
        RETURNING id INTO v_job_id;
    EXCEPTION WHEN unique_violation THEN
        RAISE EXCEPTION 'ADMIN_START_CATALOG_IMPORT_ALREADY_ACTIVE: já existe uma importação em andamento para este Card Set e esta origem.';
    END;

    INSERT INTO public.catalog_admin_action_log (actor_id, action, entity_type, entity_id, metadata)
        VALUES (auth.uid(), 'CATALOG_IMPORT_JOB', 'CATALOG_IMPORT_JOB', v_job_id,
                jsonb_build_object('card_set_id', p_card_set_id, 'source', v_source));

    RETURN v_job_id;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_start_catalog_import(UUID, TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_start_catalog_import(UUID, TEXT, TEXT, TEXT) TO authenticated;
