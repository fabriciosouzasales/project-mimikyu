/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5227 - Fichário Digital (P2-A1): fechar o caminho direto de
              criação de layout (create_collection_layout, 5123) para o
              papel authenticated — D1 passa a valer em TODO caminho de
              criação
Versão......: 1.1 (2026-10-23, P2-A1-PROPOSAL-FINAL-CONSOLIDATION-01:
              Decisão A de Fabrício — alternativa A aprovada COMO PROPOSTA;
              matriz efetiva de EXECUTE reafirmada e conferida por
              pós-checagem com has_function_privilege — cobre PUBLIC,
              herança por pertença a papéis e grants explícitos)
Status......: PROPOSTA — NÃO EXECUTADA. A aprovação NÃO autoriza aplicar
              em banco algum. Não aplicar no LIVE.
Autor.......: Fabrício Sales / Claude
Ordem do pacote: 5225 → 5223 → 5224 → 5226 → 5227 → 5228 (a 5227 só faz sentido
              depois que create_my_collection_binder, 5224, existe).

──────────────────────────────────────────────────────────────────────
PROBLEMA (bloqueador da auditoria)
  create_collection_layout(uuid, int, int) (5123, LIVE) tem EXECUTE para
  authenticated e cria um layout vazio, com qualquer grade 1..10 × 1..10,
  checando só dono e ACTIVE. Não lê o local padrão. Um usuário (ou cliente
  que chame a RPC direto, sem a interface) cria um fichário sem local do
  tipo BINDER e depois o povoa com add_layout_page (5125),
  assign_card_to_slot (5131) etc. — D1 contornada. Efeito colateral: a
  create_my_collection_binder (5224) devolveria ALREADY_EXISTS para esse
  layout vazio, e a montagem automática (D3) nunca aconteceria.

LEVANTAMENTO (estático, repositório inteiro)
  - Chamadores: nenhum em web/, supabase/functions/ ou em outra função SQL
    (grep de "create_collection_layout"): só a própria 5123, o harness
    histórico 5818 e o README da rodada Binder Foundation.
  - Contratos que pressupõem criação direta: apenas o 5818 (harness já
    EXECUTADO e encerrado; continua sendo evidência histórica — não é
    reexecutado; se um dia for, precisa rodar como dono ou ser adaptado).
  - Layouts já existentes no LIVE: NÃO verificável nesta rodada (acesso ao
    LIVE proibido). Nenhuma tela jamais chamou a 5123 e os harnesses
    deixaram resíduo zero, então o esperado é zero; o precheck abaixo só
    INFORMA a contagem (NOTICE), não bloqueia. Layouts antigos continuam
    legíveis (5223), editáveis (5122–5137) e desmontáveis (5226); a revogação
    não toca dados.
  - Relação com a 5224: create_my_collection_binder insere em
    collection_layout diretamente (SECURITY DEFINER), não chama a 5123 —
    revogar a 5123 não afeta a montagem automática.

ALTERNATIVAS AVALIADAS
  A. (RECOMENDADA, menor) Revogar EXECUTE da 5123 apenas de authenticated.
     A função permanece (dono/admin e harnesses), contrato e corpo
     inalterados; a única porta de criação para usuários passa a ser a
     5224, que valida D1, D2 e monta (D3). Reversível com um GRANT.
  B. Acrescentar à 5123 a checagem do local BINDER e dos 7 modelos. Mantém
     um segundo caminho que cria fichário VAZIO, sem montagem automática
     (contra D3) e duplica regra de elegibilidade em dois lugares.
  C. Reescrever a 5123 para delegar à 5224. Muda o contrato de uma função
     LIVE (assinatura de retorno, semântica) sem chamador que precise.
  Não se revoga nada além desta função (sem revogação indiscriminada).

MATRIZ DE EXECUTE PRETENDIDA (create_collection_layout)
  PUBLIC         não  (já revogado pela 5123; reafirmado aqui)
  anon           não  (já revogado pela 5123; reafirmado aqui)
  authenticated  não  (revogado aqui; inclui herança — conferido por
                       has_function_privilege, que considera PUBLIC e
                       pertença a papéis)
  service_role   inalterado (privilégio padrão do schema; o app não usa
                       service_role — regra permanente do projeto)
  dono (postgres) inalterado (dono sempre executa; harnesses e admin)
  A pós-checagem falha alto e desfaz a transação se authenticated ou anon
  ainda executarem por QUALQUER via (grant explícito, PUBLIC ou papel
  herdado). A simples presença textual do REVOKE não é tomada como prova.

D2 NA ALTERAÇÃO DE GRADE
  Tratado pela 5228 (Decisão B): set_collection_layout_grid passa a aceitar
  só os sete modelos, preservando a função e suas regras.
================================================================
*/

begin;

do $pre$
declare
  v_layouts bigint;
  v_callers text;
begin
  if to_regprocedure('public.create_collection_layout(uuid, integer, integer)') is null then
    raise exception 'PRECHECK 5227: create_collection_layout(uuid, integer, integer) ausente';
  end if;
  if to_regprocedure('public.create_my_collection_binder(uuid, integer, integer, text, text)') is null then
    raise exception 'PRECHECK 5227: aplique a 5224 antes (create_my_collection_binder ausente)';
  end if;
  -- Nenhuma outra função do banco pode chamar a 5123 (corpo plpgsql não
  -- gera pg_depend; a busca é textual em prosrc).
  select string_agg(p.oid::regprocedure::text, ', ') into v_callers
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname not in ('pg_catalog', 'information_schema')
    and p.proname <> 'create_collection_layout'
    and p.prosrc ilike '%create_collection_layout(%';
  if v_callers is not null then
    raise exception 'PRECHECK 5227: funções chamam create_collection_layout: %', v_callers;
  end if;
  select count(*) into v_layouts from public.collection_layout;
  raise notice '5227: % layout(s) existente(s) — permanecem intactos', v_layouts;
end;
$pre$;

revoke execute on function public.create_collection_layout(uuid, integer, integer) from public;
revoke execute on function public.create_collection_layout(uuid, integer, integer) from anon;
revoke execute on function public.create_collection_layout(uuid, integer, integer) from authenticated;

comment on function public.create_collection_layout(uuid, integer, integer) is
  'Binder Foundation (5123). A partir da 5227 (P2-A1) NÃO é executável por authenticated: usuários criam o Fichário Digital só por create_my_collection_binder (5224), que valida D1 (local padrão BINDER), D2 (sete modelos) e monta automaticamente (D3). Corpo e assinatura inalterados.';

-- Pós-checagem da matriz EFETIVA (falha alto e desfaz tudo se divergir).
do $post$
declare
  v_oid oid := to_regprocedure('public.create_collection_layout(uuid, integer, integer)');
begin
  if has_function_privilege('authenticated', v_oid, 'EXECUTE')
     or has_function_privilege('anon', v_oid, 'EXECUTE')
     or exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid = v_oid and a.grantee = 0) then
    raise exception 'POSTCHECK 5227: authenticated/anon/PUBLIC ainda executam create_collection_layout';
  end if;
  if not has_function_privilege('authenticated',
       to_regprocedure('public.create_my_collection_binder(uuid, integer, integer, text, text)'), 'EXECUTE') then
    raise exception 'POSTCHECK 5227: create_my_collection_binder (5224) sem EXECUTE para authenticated';
  end if;
  if (select pg_get_function_result(v_oid)) <> 'TABLE(id uuid, collection_id uuid, grid_rows integer, grid_columns integer)' then
    raise exception 'POSTCHECK 5227: assinatura/retorno da 5123 alterados';
  end if;
end;
$post$;

notify pgrst, 'reload schema';

commit;

/*
Reversão:
  begin;
  grant execute on function public.create_collection_layout(uuid, integer, integer) to authenticated;
  commit;

Como validar:
  select has_function_privilege('authenticated',
           'public.create_collection_layout(uuid, integer, integer)', 'EXECUTE') as auth_exec,
         has_function_privilege('anon',
           'public.create_collection_layout(uuid, integer, integer)', 'EXECUTE') as anon_exec;
  Esperado: false / false. Prova comportamental: harness 5850, 0.8 e 1.7.
*/
