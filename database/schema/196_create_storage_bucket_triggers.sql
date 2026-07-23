/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 196 - Create Storage Bucket Triggers
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / ChatGPT
Data........: 2026-07-18

Descrição:
Cria o trigger responsável pela atualização automática da coluna updated_at
na tabela public.storage_bucket.

Pré-requisitos:
- Query 195 - Create Storage Bucket.
- Função public.set_updated_at() disponível.
===============================================================================
*/

BEGIN;

/*
-------------------------------------------------------------------------------
1. Validação dos pré-requisitos
-------------------------------------------------------------------------------
*/
DO $$
BEGIN
    IF to_regclass('public.storage_bucket') IS NULL THEN
        RAISE EXCEPTION
            'Não foi possível executar a Query 196: a tabela public.storage_bucket não existe.';
    END IF;

    IF to_regprocedure('public.set_updated_at()') IS NULL THEN
        RAISE EXCEPTION
            'Não foi possível executar a Query 196: a função public.set_updated_at() não existe.';
    END IF;
END;
$$;

/*
-------------------------------------------------------------------------------
2. Trigger de updated_at
-------------------------------------------------------------------------------
*/
DROP TRIGGER IF EXISTS trg_storage_bucket_set_updated_at
ON public.storage_bucket;

CREATE TRIGGER trg_storage_bucket_set_updated_at
BEFORE UPDATE ON public.storage_bucket
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

/*
-------------------------------------------------------------------------------
3. Comentário
-------------------------------------------------------------------------------
*/
COMMENT ON TRIGGER trg_storage_bucket_set_updated_at
ON public.storage_bucket IS
'Atualiza automaticamente a coluna updated_at antes de alterações em storage_bucket.';

COMMIT;
