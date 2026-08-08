/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2120 - Create admin_persist_manual_card_asset Function
Versão......: 1.0
Status......: MIGRATION — CONFIRMADO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-07

Descrição...:
Function SECURITY DEFINER que persiste em public.card_asset o
resultado de um upload MANUAL já concluído direto do navegador para
o bucket card-front (Query 2119) — parte do canal formalizado em
ADR-026, emenda "Segundo ponto de entrada via UI". A função NUNCA
recebe bytes de arquivo: o upload já aconteceu antes de ela ser
chamada; ela só valida os metadados e grava o ponteiro.

Constraint real de card_asset confirmada em produção antes desta
Query (2026-08-07, pg_get_constraintdef):
  uq_card_asset_card_type_language_order =
      UNIQUE (card_id, asset_type_id, language_id, asset_order)
É esta a chave natural usada como alvo do upsert — asset_order
sempre 1 (mesma convenção de scripts/import-manual-assets.ts:
is_primary = true, asset_order = 1, um único Card Front "vigente"
por Card + idioma).

Regras de Negócio:
- is_admin() checado explicitamente no corpo (mesmo padrão de todas
  as admin_* functions do módulo — RLS de card_asset não depende
  desta função para outras operações, mas INSERT/UPDATE aqui só
  acontece através dela).
- asset_type_id e storage_bucket_id NUNCA são parâmetros — resolvidos
  internamente para 'CARD_FRONT' (escopado ao Game do Card, mesmo
  padrão de uq_card_asset_type_game_code) e para o bucket 'card-front'
  fixo. Fecha a possibilidade de o canal Manual gravar em outro tipo
  de ativo ou bucket por engano ou por payload malicioso.
- p_card_set_id é validado contra o card_set_id real do Card
  (derivado de card → card_set; Game vem de card_set → expansion,
  não existe game_id direto em card_set — confirmado em
  141_create_card_triggers.sql) — defesa contra um Card resolvido
  incorretamente do lado do chamador (ex.: por collector_number
  ambíguo entre Coleções).
- p_language_code resolvido contra public.language; RAISE EXCEPTION
  se não existir.
- Extensão/MIME validados contra a mesma whitelist de
  scripts/import-manual-assets.ts (png/jpg/jpeg/webp) — defesa em
  profundidade, mesmo já validado no núcleo compartilhado
  (web/lib/catalogo/manual-asset-import/core.ts) antes da chamada.
- file_size_bytes e checksum_sha256 não são revalidados aqui além do
  que as CHECKs da própria tabela já garantem
  (ck_card_asset_file_size_nonnegative,
  ck_card_asset_checksum_sha256_format) — duplicar essas duas não
  agrega nada, o INSERT/UPDATE já falha com a mensagem da CHECK se
  vierem fora do formato.
- source_code sempre 'MANUAL', is_active sempre TRUE, is_primary
  sempre TRUE, asset_order sempre 1 — sem parâmetro para nenhum
  dos quatro, mesma decisão de fechar superfície de uso indevido.
- Devolve (action, previous_storage_path): 'INSERTED' com
  previous_storage_path NULL, ou 'UPDATED' com o storage_path que
  a linha tinha ANTES desta chamada — usado pelo chamador (Server
  Action) para instruir o navegador a remover o arquivo antigo do
  Storage só depois de confirmada a troca do ponteiro (nunca antes).

Pré-requisitos:
- Query 180 - Create Card Asset Table (v1.1) / 193 / 194 / 197 -
  estrutura final de card_asset.
- Query 1060 - Create is_admin() Function.
- Query 2119 - Create Card Front Storage Admin Policies.
================================================================
*/

CREATE OR REPLACE FUNCTION public.admin_persist_manual_card_asset(
    p_card_id UUID,
    p_card_set_id UUID,
    p_language_code TEXT,
    p_storage_path TEXT,
    p_mime_type TEXT,
    p_file_extension TEXT,
    p_file_size_bytes BIGINT,
    p_checksum_sha256 TEXT
)
RETURNS TABLE (action TEXT, previous_storage_path TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_card_set_id       UUID;
    v_game_id           UUID;
    v_language_id       UUID;
    v_asset_type_id     UUID;
    v_storage_bucket_id UUID;
    v_existing_id       UUID;
    v_previous_path     TEXT;
    v_action            TEXT;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'ADMIN_PERSIST_MANUAL_CARD_ASSET_FORBIDDEN: usuário não é administrador.';
    END IF;

    IF NULLIF(BTRIM(p_storage_path), '') IS NULL THEN
        RAISE EXCEPTION 'ADMIN_PERSIST_MANUAL_CARD_ASSET_STORAGE_PATH_REQUIRED: storage_path vazio.';
    END IF;

    IF LOWER(COALESCE(p_file_extension, '')) NOT IN ('png', 'jpg', 'jpeg', 'webp') THEN
        RAISE EXCEPTION 'ADMIN_PERSIST_MANUAL_CARD_ASSET_EXTENSION_NOT_SUPPORTED: extensão % não suportada.', p_file_extension;
    END IF;

    IF COALESCE(p_mime_type, '') NOT IN ('image/png', 'image/jpeg', 'image/webp') THEN
        RAISE EXCEPTION 'ADMIN_PERSIST_MANUAL_CARD_ASSET_MIME_NOT_SUPPORTED: mime % não suportado.', p_mime_type;
    END IF;

    -- Card → Card Set → Expansion → Game (card não tem game_id direto,
    -- ver 141_create_card_triggers.sql).
    SELECT card.card_set_id, expansion.game_id
      INTO v_card_set_id, v_game_id
      FROM public.card AS card
      JOIN public.card_set AS card_set ON card_set.id = card.card_set_id
      JOIN public.expansion AS expansion ON expansion.id = card_set.expansion_id
     WHERE card.id = p_card_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'ADMIN_PERSIST_MANUAL_CARD_ASSET_CARD_NOT_FOUND: Card % não existe.', p_card_id;
    END IF;

    IF v_card_set_id <> p_card_set_id THEN
        RAISE EXCEPTION 'ADMIN_PERSIST_MANUAL_CARD_ASSET_CARD_SET_MISMATCH: Card % não pertence ao Card Set %.', p_card_id, p_card_set_id;
    END IF;

    SELECT id INTO v_language_id
      FROM public.language
     WHERE code = p_language_code;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'ADMIN_PERSIST_MANUAL_CARD_ASSET_LANGUAGE_NOT_FOUND: idioma % não existe.', p_language_code;
    END IF;

    SELECT id INTO v_asset_type_id
      FROM public.card_asset_type
     WHERE code = 'CARD_FRONT'
       AND game_id = v_game_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'ADMIN_PERSIST_MANUAL_CARD_ASSET_ASSET_TYPE_NOT_FOUND: CARD_FRONT não configurado para o Game %.', v_game_id;
    END IF;

    SELECT id INTO v_storage_bucket_id
      FROM public.storage_bucket
     WHERE code = 'card-front'
       AND is_active = TRUE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'ADMIN_PERSIST_MANUAL_CARD_ASSET_BUCKET_NOT_FOUND: bucket card-front ausente ou inativo.';
    END IF;

    -- Chave natural real (uq_card_asset_card_type_language_order),
    -- asset_order fixo em 1 — convenção já usada por
    -- scripts/import-manual-assets.ts.
    SELECT id, storage_path
      INTO v_existing_id, v_previous_path
      FROM public.card_asset
     WHERE card_id = p_card_id
       AND asset_type_id = v_asset_type_id
       AND language_id = v_language_id
       AND asset_order = 1;

    IF FOUND THEN
        UPDATE public.card_asset
           SET storage_bucket_id = v_storage_bucket_id,
               storage_path      = p_storage_path,
               external_url      = NULL,
               mime_type         = p_mime_type,
               file_extension    = p_file_extension,
               file_size_bytes   = p_file_size_bytes,
               checksum_sha256   = p_checksum_sha256,
               source_code       = 'MANUAL',
               source_reference  = NULL,
               is_primary        = TRUE,
               is_active         = TRUE,
               updated_at        = now()
         WHERE id = v_existing_id;

        v_action := 'UPDATED';
    ELSE
        INSERT INTO public.card_asset (
            card_id, asset_type_id, language_id, storage_bucket_id,
            storage_path, mime_type, file_extension, file_size_bytes,
            checksum_sha256, source_code, is_primary, asset_order, is_active
        ) VALUES (
            p_card_id, v_asset_type_id, v_language_id, v_storage_bucket_id,
            p_storage_path, p_mime_type, p_file_extension, p_file_size_bytes,
            p_checksum_sha256, 'MANUAL', TRUE, 1, TRUE
        );

        v_action := 'INSERTED';
        v_previous_path := NULL;
    END IF;

    RETURN QUERY SELECT v_action, v_previous_path;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_persist_manual_card_asset(
    UUID, UUID, TEXT, TEXT, TEXT, TEXT, BIGINT, TEXT
) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.admin_persist_manual_card_asset(
    UUID, UUID, TEXT, TEXT, TEXT, TEXT, BIGINT, TEXT
) TO authenticated;

-- ================================================================
-- Resultado esperado: "Success. No rows returned" (CREATE FUNCTION/
-- REVOKE/GRANT não devolvem linhas).
--
-- Como validar (rodar depois — smoke test com um Card real que ainda
-- não tem imagem, escolha um card_id/card_set_id existentes):
--
-- SELECT * FROM public.admin_persist_manual_card_asset(
--     p_card_id          => '<uuid de um card existente>',
--     p_card_set_id      => '<card_set_id desse card>',
--     p_language_code    => 'en',
--     p_storage_path     => 'smoke-test/manual-import-check.png',
--     p_mime_type        => 'image/png',
--     p_file_extension   => 'png',
--     p_file_size_bytes  => 1024,
--     p_checksum_sha256  => repeat('a', 64)
-- );
--
-- Esperado: 1 linha, action = 'INSERTED' (ou 'UPDATED' se o Card já
-- tinha um Card Front nesse idioma), previous_storage_path NULL (ou
-- o path anterior, se UPDATED). Depois, reverter manualmente a linha
-- de teste (ela não é uma imagem real) antes de seguir para a 2121.
-- ================================================================
--
-- CONFIRMADO EXECUTADO (2026-08-07): smoke test rodado dentro de uma
-- transação com impersonação de sessão admin (set_config de
-- request.jwt.claims) e ROLLBACK ao final — devolveu action =
-- 'INSERTED', previous_storage_path = NULL, nada persistido.
-- ================================================================
