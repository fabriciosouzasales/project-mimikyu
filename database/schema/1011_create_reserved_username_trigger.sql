/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 1011 - Create Reserved Username trigger
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-07-25

Descrição...:
Cria o trigger que mantém reserved_username.updated_at atualizado
automaticamente, reaproveitando public.set_updated_at() (Query 001).

Regras de Negócio:
- Mesmo padrão já aplicado a toda tabela do projeto.
================================================================
*/

CREATE TRIGGER reserved_username_set_updated_at
    BEFORE UPDATE ON public.reserved_username
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();
