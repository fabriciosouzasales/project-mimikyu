/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 1830 - Validate username_available
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-07-25

Descrição...:
Validação de username_available(): SECURITY DEFINER ativo,
EXECUTE liberado para anon/authenticated, e três casos reais de
uso (reservado, formato inválido, disponível).
================================================================
*/

SELECT proname, prosecdef FROM pg_proc
WHERE pronamespace = 'public'::regnamespace AND proname = 'username_available';

-- Esperado: true / true.
SELECT
    has_function_privilege('anon', 'public.username_available(text)', 'EXECUTE') AS anon,
    has_function_privilege('authenticated', 'public.username_available(text)', 'EXECUTE') AS authenticated;

-- Esperado: false (termo reservado, ver Query 1710).
SELECT public.username_available('admin') AS deve_ser_false_reservado;

-- Esperado: false (menos de 3 caracteres, fora do formato).
SELECT public.username_available('ab') AS deve_ser_false_formato_invalido;

-- Esperado: true (username válido, dentro do limite de 20 caracteres, não usado).
SELECT public.username_available('fabricio_teste') AS deve_ser_true_disponivel;
