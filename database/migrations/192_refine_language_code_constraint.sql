/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 192 - Refine Language Code Constraint
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / ChatGPT
Data........: 2026-07-18

Descrição:
Simplifica a validação do código de idioma da tabela public.language.

Formatos aceitos:
- xx
- xx-YY

Exemplos válidos:
- en
- ja
- es
- fr
- de
- it
- pt-BR
- pt-PT

Pré-requisitos:
- Query 190 - Create Language Table.
- Query 191 - Create Language Triggers.
===============================================================================
*/

BEGIN;

DO $$
BEGIN
    IF to_regclass('public.language') IS NULL THEN
        RAISE EXCEPTION
            'Não foi possível executar a Query 192: a tabela public.language não existe.';
    END IF;
END;
$$;

ALTER TABLE public.language
    DROP CONSTRAINT IF EXISTS ck_language_code_format;

ALTER TABLE public.language
    ADD CONSTRAINT ck_language_code_format
    CHECK (
        code ~ '^[a-z]{2}(-[A-Z]{2})?$'
    );

COMMENT ON CONSTRAINT ck_language_code_format
ON public.language IS
'Permite códigos de idioma nos formatos xx ou xx-YY, como en, ja e pt-BR.';

COMMIT;
