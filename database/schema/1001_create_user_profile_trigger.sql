/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 1001 - Create User Profile trigger
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-07-25

Descrição...:
Cria o trigger que mantém user_profile.updated_at atualizado
automaticamente a cada UPDATE, reaproveitando a function
compartilhada public.set_updated_at() (Query 001).

Regras de Negócio:
- Mesmo padrão já aplicado a toda tabela do projeto (Game,
  Expansion, Card Set, etc.) — nenhuma lógica nova aqui.
================================================================
*/

CREATE TRIGGER user_profile_set_updated_at
    BEFORE UPDATE ON public.user_profile
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();
