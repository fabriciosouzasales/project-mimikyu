/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 1002 - Create User Profile invariants trigger
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-07-25

Descrição...:
Cria a function e o trigger que aplicam dois invariantes de
user_profile em toda gravação (INSERT ou UPDATE):
1. display_name é normalizado (trim) antes de ser gravado.
2. username não pode ser alterado depois de criado (imutável,
   sem exceção nesta fase — ver ADR-020).

Regras de Negócio:
- O trim aqui torna redundante (mas ainda útil como reforço) o
  trim() já presente no CHECK de display_name (Query 1000).
- A imutabilidade é total: nenhuma sessão ou papel tem via de
  exceção. Uma correção futura de username, quando existir
  modelo de papéis/permissões aprovado, será tratada em Query
  própria — não antecipada aqui.
================================================================
*/

CREATE OR REPLACE FUNCTION public.enforce_user_profile_invariants()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.display_name := trim(NEW.display_name);

    IF TG_OP = 'UPDATE' AND NEW.username IS DISTINCT FROM OLD.username THEN
        RAISE EXCEPTION 'username é imutável e não pode ser alterado.';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER user_profile_enforce_invariants
    BEFORE INSERT OR UPDATE ON public.user_profile
    FOR EACH ROW
    EXECUTE FUNCTION public.enforce_user_profile_invariants();
