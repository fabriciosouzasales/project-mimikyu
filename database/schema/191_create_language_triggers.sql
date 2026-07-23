/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 191 - Create Language Triggers
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / ChatGPT
Data........: 2026-07-18

Descrição resumida:
Cria o trigger de manutenção automática de updated_at para a tabela language.

Descrição:
Esta Query garante que o campo updated_at seja atualizado automaticamente
antes de cada alteração em um registro da tabela language.

Pré-requisitos:
- Query 190 - Create Language Table.
- Função public.set_updated_at() criada na infraestrutura.
===============================================================================
*/

BEGIN;

DO $$
BEGIN
    IF to_regprocedure('public.set_updated_at()') IS NULL THEN
        RAISE EXCEPTION
            'Não foi possível executar a Query 191: a função public.set_updated_at() não existe.';
    END IF;
END;
$$;

DROP TRIGGER IF EXISTS trg_language_set_updated_at
ON public.language;

CREATE TRIGGER trg_language_set_updated_at
BEFORE UPDATE ON public.language
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

COMMENT ON TRIGGER trg_language_set_updated_at
ON public.language IS
'Atualiza automaticamente o campo updated_at antes de cada alteração em language.';

COMMIT;
