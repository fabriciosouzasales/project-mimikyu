/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5307 - Create set_collection_visibility()
Versão......: 1.0
Status......: PROPOSTA — NÃO EXECUTADA (V1-12) — depende de 5301
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-30

Descrição...:
Titular torna a coleção PUBLIC ou PRIVATE por escolha explícita
(C-15/C-151/C-152). Visibilidade não cria nem altera participações.

Regras de Negócio:
- Só o titular; coleção alheia/inexistente → COLLECTION_NOT_FOUND.
- Só coleção ACTIVE (configuração — C-37/C-162). Tornar PRIVATE é
  permitido também ARCHIVED (fechar acesso nunca depende de reativar).
- Idempotente: mesmo valor → UNCHANGED.
- PRIVATE revoga o acesso público na mesma transação (5302).
================================================================
*/

CREATE OR REPLACE FUNCTION public.set_collection_visibility(
    p_collection_id UUID,
    p_visibility TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_user      UUID := auth.uid();
    v_target    TEXT := upper(btrim(coalesce(p_visibility, '')));
    v_current   TEXT;
    v_lifecycle TEXT;
BEGIN
    IF v_user IS NULL THEN
        RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '28000';
    END IF;
    IF v_target NOT IN ('PRIVATE', 'PUBLIC') THEN
        RAISE EXCEPTION 'INVALID_VISIBILITY' USING ERRCODE = '22023';
    END IF;

    SELECT c.visibility, c.lifecycle_status INTO v_current, v_lifecycle
    FROM public.collection c
    WHERE c.id = p_collection_id
      AND c.owner_user_id = v_user
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'COLLECTION_NOT_FOUND' USING ERRCODE = 'P0002';
    END IF;
    IF v_current = v_target THEN
        RETURN jsonb_build_object('outcome', 'UNCHANGED', 'visibility', v_current);
    END IF;
    IF v_target = 'PUBLIC' AND v_lifecycle <> 'ACTIVE' THEN
        RAISE EXCEPTION 'COLLECTION_ARCHIVED' USING ERRCODE = '55000';
    END IF;

    UPDATE public.collection c
    SET visibility = v_target
    WHERE c.id = p_collection_id;

    RETURN jsonb_build_object('outcome', 'CHANGED', 'visibility', v_target);
END;
$$;

REVOKE ALL ON FUNCTION public.set_collection_visibility(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_collection_visibility(UUID, TEXT) TO authenticated;
