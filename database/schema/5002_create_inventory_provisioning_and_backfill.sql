/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5002 - Create Inventory Provisioning and Backfill
Versão......: 1.1
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-31 (revisado em COLLECTIONS-PHYSICAL-INCREMENT-01A-REVISION-01)

Descrição...:
Consolida em UMA ÚNICA migration/transação: handle_new_user_inventory(),
o trigger independente on_auth_user_created_inventory em auth.users, e
o backfill idempotente dos Users já existentes. Anteriormente
distribuído em duas Queries separadas (5002/5003) — consolidado nesta
revisão para eliminar a janela de execução em que o trigger poderia
estar ativo sem que os Users pré-existentes tivessem recebido seu
Inventory (achado da rodada
COLLECTIONS-PHYSICAL-INCREMENT-01A-REVISION-01, item 1).

BEGIN/COMMIT explícitos abaixo garantem atomicidade real quando esta
Query for de fato aplicada: função, trigger e backfill entram juntos
ou nenhum entra — não existe estado intermediário possível no banco
físico.

Transaction boundary confirmado em
COLLECTIONS-PHYSICAL-INCREMENT-01A-FINAL-CHECK (Check 1): BEGIN/COMMIT
explícito é padrão comprovado e extenso deste projeto — confirmado em
72 arquivos de database/ (schema/, seeds/, validations/, migrations/),
incluindo a própria Query 2147 (status CONFIRMADO EXECUTADO, aplicada
via o mesmo mecanismo apply_migration/execute_sql que aplicará esta
Query) e Queries de backfill/seed puramente DML como 900 e 840.

Função e trigger permanecem deliberadamente independentes de
handle_new_user()/on_auth_user_created (Query 1020) — não altera a
função existente, evita risco em um mecanismo já em produção
(decisão confirmada em COLLECTIONS-PHYSICAL-MODELING-02, item 5).

Regras de Negócio:
- SECURITY DEFINER, SET search_path = '', referências totalmente
  qualificadas (public.inventory) — mesmo padrão de
  handle_new_user()/admin_revoke_admin();
- ON CONFLICT (owner_user_id) DO NOTHING — idempotente, tanto para o
  trigger quanto para o backfill; reexecução acidental (do trigger ou
  deste arquivo inteiro) não gera erro nem linha duplicada;
- falha da função reverte a transação inteira de criação do usuário
  em auth.users — mesmo comportamento de risco já aceito para
  handle_new_user()/user_profile, não é um risco novo introduzido
  aqui (COLLECTIONS-PHYSICAL-MODELING-02, item 4);
- EXECUTE revogado de PUBLIC/anon/authenticated na função de
  provisionamento — só o próprio evento de trigger a invoca;
- backfill cobre todo auth.users existente no momento da aplicação —
  2 usuários pré-existentes nesta data (2026-08-31), ambos
  backfillados com sucesso.

Garantia de "exatamente 1 Inventory por User": o UNIQUE(owner_user_id)
em public.inventory (Query 5000) é a garantia estrutural real; trigger
+ backfill consolidados nesta Query são o mecanismo de provisionamento
completo (novos Users e Users pré-existentes), aplicados atomicamente.

CONFIRMADO EXECUTADO em 2026-08-31 (COLLECTIONS-PHYSICAL-INCREMENT-01B,
Fase 1) via apply_migration (versão de migration Supabase
20260831230358). Validado ao vivo em três frentes: (1) backfill dos 2
Users pré-existentes confirmado por SELECT count(*); (2) reexecução
idempotente do backfill confirmada sem duplicar linhas
(ON CONFLICT DO NOTHING); (3) provisionamento automático de novo User
validado através do fluxo real de signup da aplicação (não INSERT
direto em auth.users, bloqueado pelo classificador de segurança do
Auto Mode) — usuária de teste yasmimlinssales@gmail.com, id
71d0ac05-1533-480d-91c4-303acf957676, gerou exatamente 1 Inventory
(babe3e5e-25f7-4075-8f51-59d1315eb70b), owner_user_id correto,
confirmado por SQL após o cadastro real — ver
database/validations/5800_validate_collections_physical_increment_01a.sql,
itens 16-17.
================================================================
*/

BEGIN;

CREATE FUNCTION public.handle_new_user_inventory()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    INSERT INTO public.inventory (owner_user_id)
    VALUES (NEW.id)
    ON CONFLICT (owner_user_id) DO NOTHING;
    RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.handle_new_user_inventory() FROM PUBLIC, anon, authenticated;

CREATE TRIGGER on_auth_user_created_inventory
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user_inventory();

-- Backfill: cobre todo auth.users já existente no momento da aplicação,
-- na MESMA transação da criação do trigger — nenhuma janela em que o
-- trigger exista sem que os Users pré-existentes tenham Inventory.
INSERT INTO public.inventory (owner_user_id)
SELECT id FROM auth.users
ON CONFLICT (owner_user_id) DO NOTHING;

COMMIT;
