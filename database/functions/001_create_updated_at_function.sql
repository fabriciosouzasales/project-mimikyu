/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 001 - Create updated_at function
Versão......: 1.0
Autor.......: Fabrício Sales / ChatGPT
Data........: 2026-07-17
Descrição...:
Cria a função compartilhada set_updated_at(), reaproveitada por todos os
triggers de atualização automática do campo updated_at do catálogo.
===============================================================================
*/

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$;
