/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 6830 - Validate Fatia D Position Assignment
Versão......: 1.8 (EVIDÊNCIA DE VALIDAÇÃO — CLOSED. 6117-6126 CONFIRMADO
               EXECUTADO e PROMOVIDO para database/schema/ em
               COLLECTIONS-POKEDEX-FATIA-D-PROMOTION-CLOSEOUT-01. Este
               arquivo permanece em database/proposals/ como evidência
               histórica de validação — NÃO promovido para
               database/schema/, por não ser DDL/DML de schema. v1.2
               atualizada em PAUSE-SQL-DIRECT-AUDIT-01: Caso 7 e Caso 8
               reescritos, novo Caso 2b (p_confirm_override=NULL), novo
               Caso 20b (concorrência lifecycle), reforço de captura da
               RETURNING real das 4 RPCs; v1.3 renumerou referências de
               6123/6124/6125 em RENUMBER-FIX-STAGING-01, sem mudança de
               conteúdo funcional; v1.4 corrigiu o roteiro em
               6830-DIRECT-REVIEW-FIX-01: estado físico real
               (6117-6122 já aplicadas, 6123-6125 não), separação de
               contexto/role para testes que fazem DML direto vs. via
               RPC, Caso 10 dividido em duas provas, Caso 20b reforçado
               contra falso-positivo estático, e Seção 1.7 (EXECUTE)
               reescrita com prova semântica via aclexplode; v1.5
               corrigiu 2 problemas residuais encontrados em
               6830-DIRECT-REVIEW-FIX-02: a query de 1.7 referenciava
               uma coluna inexistente (acl.grantee_role) e a expectativa
               não contemplava o EXECUTE implícito do owner da função;
               e a sugestão de "service_role com BYPASSRLS" para DML
               direto estrutural foi removida (BYPASSRLS não concede
               INSERT/UPDATE/DELETE; o modelo mantém service_role sem
               DML direto nessas tabelas por decisão deliberada); v1.6
               registrou o INCIDENTE encontrado na execução real da
               Seção 3 (Caso 14, SQLSTATE 42702, ver nota logo antes do
               Caso 14 abaixo) e a migration incremental de correção
               6126, então PROPOSTA e NÃO EXECUTADA; v1.7 ajustou
               SOMENTE texto/roteiro em resposta a
               COLLECTIONS-POKEDEX-FATIA-D-6126-IMPLEMENT-RESUME-01, ver
               nota "Correção v1.7" abaixo; v1.8 — esta versão — fecha a
               bateria: Caso 16 executado explicitamente e registrado
               PASS (não reaproveitando o resultado do Caso 21), matriz
               final Casos 1-24 consolidada com zero FAIL residual,
               cleanup de fixtures/tabelas de rastreio executado e
               zero-resíduo confirmado por identidade, postcheck
               estrutural/segurança confirmou 6117-6126 intactos — ver
               "Correção v1.8" abaixo)
Status......: CONFIRMADO EXECUTADO — TECHNICAL CLOSEOUT PASS. 6117-6126
               CONFIRMADO EXECUTADO e PROMOVIDO. Seção 3 concluída
               (Casos 1-24): FAILs históricos (Caso 12-preservação, 14,
               19, 20) SUPERSEDED por PASS posterior pós-6126/fixture
               corrigido; Caso 16 PASS explícito (COLLECTIONS-POKEDEX-
               FATIA-D-FINAL-VALIDATION-CLEANUP-01); único item não
               provado permanece Caso 20b, registrado literalmente como
               "NOT EXECUTED / UNPROVEN" (ambiente sem duas sessões
               persistentes simultâneas, regra já aprovada — não conta
               como PASS). Fixtures e tabelas de rastreio
               (_fatia_d_run/_fatia_d_results) foram removidas no
               cleanup final; zero-resíduo confirmado por identidade
               (IDs capturados de _fatia_d_run antes do DROP). Dados
               reais/preexistentes (Inventory, Expansion, Game, Rarity,
               Card Category, Card Variant Type, Language, Pokémon
               Species, Pokémon Generation, usuário real de teste)
               confirmados intactos.
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-05 (staging em COLLECTIONS-POKEDEX-FATIA-D-STAGING-01;
               revisado em ...-STAGING-AUDIT-01, PAUSE-SQL-DIRECT-AUDIT-01,
               RENUMBER-FIX-STAGING-01, 6830-DIRECT-REVIEW-FIX-01,
               6830-DIRECT-REVIEW-FIX-02,
               COLLECTIONS-POKEDEX-FATIA-D-6126-STAGING-01 e
               COLLECTIONS-POKEDEX-FATIA-D-6126-IMPLEMENT-RESUME-01;
               executada integralmente — incluindo Caso 16 e cleanup —
               em 2026-09-06, COLLECTIONS-POKEDEX-FATIA-D-FINAL-
               VALIDATION-CLEANUP-01; fechada e reconciliada para
               database/schema/ em COLLECTIONS-POKEDEX-FATIA-D-
               PROMOTION-CLOSEOUT-01)

Correção v1.8 (COLLECTIONS-POKEDEX-FATIA-D-FINAL-VALIDATION-CLEANUP-01 +
COLLECTIONS-POKEDEX-FATIA-D-PROMOTION-CLOSEOUT-01) — fechamento da
bateria, sem qualquer mudança de contrato SQL (este arquivo é evidência
de validação, não schema):
(a) Caso 16 (clear_pokedex_position_primary_representative, caminho
    "sem Primary preexistente" nunca exercitado explicitamente até
    então) executado com Primary Representative preparado especificamente
    para o caso — RETURNING exato, 0 linhas remanescentes, Assignment/
    Allocation sobreviventes, snapshot completo da tabela de Assignment
    idêntico antes/depois — registrado PASS em _fatia_d_results antes de
    seu DROP, sem reutilizar o resultado do Caso 21;
(b) matriz final Casos 1-24 consolidada: zero FAIL residual — todo FAIL
    histórico (Caso 12-preservação, 14, 19, 20) foi SUPERSEDED por um
    PASS posterior na mesma rodada (pós-6126 ou fixture corrigido); Caso
    20b permanece o único item NOT EXECUTED / UNPROVEN, nunca convertido
    em PASS;
(c) cleanup final removeu exclusivamente fixtures desta bateria — 7
    Collection Allocation (incluindo 2 não rastreadas em _fatia_d_run:
    a Allocation do Caso 3b e a Allocation do Caso 1b na Collection
    "Fatia D Test OC Divergent", achadas por auditoria de identidade/
    timestamp, não por nome/prefixo), 8 Physical Card, 8 Card Variant,
    8 Card (cascata: 5 Card Primary Species), 1 Card Set, 2 Collection
    (cascata: Collection Reference/Pokedex Reference/Scope Generation),
    2 Pokedex (cascata: 3 Pokedex Position), 1 Storage Container, e as
    2 tabelas de rastreio (_fatia_d_run/_fatia_d_results, via DROP
    TABLE) — nesta ordem de dependência FK;
(d) zero-resíduo provado por identidade (13 categorias de ID, todas
    zeradas) usando os IDs capturados de _fatia_d_run ANTES do DROP,
    não por nome/prefixo; dados reais/preexistentes (Inventory,
    Expansion "Legendary Collection", Game, Rarity "Rara Holo", Card
    Category Pokémon/Treinador, Card Variant Type "Holográfica Staff",
    Language "en", Pokémon Species Bulbasaur/Ivysaur/Venusaur, Pokémon
    Generation, usuário real de teste) confirmados intactos por
    identidade, não afetados pelo cleanup;
(e) postcheck estrutural/segurança pós-cleanup confirmou:
    collection_pokedex_position_assignment e
    collection_pokedex_position_primary_representative existem e vazias
    (0 linhas, esperado — só continham fixtures desta bateria); RLS
    habilitado em ambas; as 3 RPCs (set_pokedex_position_assignment,
    remove_pokedex_position_assignment, set_pokedex_position_primary_
    representative, clear_pokedex_position_primary_representative)
    permanecem SECURITY DEFINER; 6126 (ON CONFLICT ON CONSTRAINT)
    permanece live;
(f) 6117-6126 promovidas para database/schema/ (corpo SQL byte-idêntico
    ao executado, apenas cabeçalho Status/Versão/Data atualizado por
    arquivo); este 6830 permanece em database/proposals/ como evidência
    de validação, não promovido.

Correção v1.7 (COLLECTIONS-POKEDEX-FATIA-D-6126-IMPLEMENT-RESUME-01) —
ajuste SOMENTE de texto/roteiro, sem qualquer mudança de contrato, após
auditoria direta de Fabrício confirmar 6126 (PASS) e autorizar sua
aplicação real. 6126 foi aplicada ao banco e o postcheck via
pg_get_functiondef confirmou a cláusula
`ON CONFLICT ON CONSTRAINT pk_collection_pokedex_position_primary_representative`
ao vivo, com assinatura/RETURNS TABLE/SECURITY DEFINER/search_path/
ownership/ACL/lock order/RETURNING inalterados. Quatro correções de
redação nesta versão, todas textuais:
(a) esta nota, e a nota "INCIDENTE" antes do Caso 14, não afirmam mais que
    o Caso 14 precisava de uma linha pré-existente para "colidir no
    UPSERT" — a ambiguidade do alvo do ON CONFLICT ocorre em tempo de
    RESOLUÇÃO DA INSTRUÇÃO (contra os OUT-parameters do RETURNS TABLE),
    independentemente de existir ou não um conflito real na chamada;
(b) a anotação do Caso 14 passa a descrevê-lo como prova do caminho de
    INSERT + RETURNING real da RPC corrigida, sem usar a expressão
    "DO NOTHING" (o INSERT puro, sem conflito, não é um DO NOTHING —
    é a ausência de conflito);
(c) a anotação do Caso 15 passa a descrevê-lo especificamente como prova
    do caminho de conflito (DO UPDATE) do ON CONFLICT corrigido em 6126;
(d) a anotação do Caso 12 não assume mais literalmente "PositionTEST_A" —
    a prova agora exige capturar a Position CORRENTE real da Assignment
    de Card_Match antes do move inválido, e confirmar depois do erro
    esperado que a mesma Assignment, a mesma pokedex_position_id e o
    mesmo Primary Representative (apontando para essa Assignment/Position)
    permanecem inalterados.

Correção v1.6 (COLLECTIONS-POKEDEX-FATIA-D-6126-STAGING-01) — incidente
real encontrado na execução funcional da Seção 3 (não uma correção do
roteiro, e sim registro de bug confirmado no objeto testado):
ao chamar set_pokedex_position_primary_representative(uuid) pela primeira
vez nesta bateria (Caso 14), a função falhou com SQLSTATE 42702 ("column
reference \"collection_id\" is ambiguous"), na própria RETURN QUERY (linha
do INSERT ... ON CONFLICT ... RETURNING). Corrigido em v1.7: a ambiguidade
do alvo do ON CONFLICT ocorre em tempo de RESOLUÇÃO DA INSTRUÇÃO, contra
os OUT-parameters de mesmo nome do RETURNS TABLE — independentemente de
existir ou não um conflito real (uma linha pré-existente) na chamada; não
é necessário haver colisão real no UPSERT para o erro se manifestar.
Causa raiz: a cláusula `ON CONFLICT (collection_id, pokedex_position_id)`
usa nomes de coluna sem qualificação — sob plpgsql.variable_conflict =
'error' (confirmado ativo no banco desta sessão), esses nomes colidem com
os OUT-parameters de mesmo nome do RETURNS TABLE da própria função. Mesma
classe de bug que 6123 já havia corrigido na cláusula RETURNING desta
família de funções (6122) — mas a lista de conflito do ON CONFLICT desta
função específica (6125) ficou fora daquela rodada e só se manifesta em
execução real (nunca em teste puramente estrutural). Correção proposta em
6126 (PROPOSTA, NÃO EXECUTADA): troca de
`ON CONFLICT (collection_id, pokedex_position_id)` por
`ON CONFLICT ON CONSTRAINT pk_collection_pokedex_position_primary_representative`
— única mudança funcional, resto da função idêntico (RETURNING já
qualificada por 6125 v1.2 permanece sem alteração). Execução real da
Seção 3 foi interrompida no Caso 14 (STOP, conforme CLAUDE.md — erro
inesperado em objeto já aplicado, correção requer autorização explícita)
e aguarda aprovação/aplicação de 6126 para retomar Caso 14 em diante.

Correção v1.5 (6830-DIRECT-REVIEW-FIX-02) — segunda rodada de auditoria
direta de Fabrício sobre 6830 v1.4 (6123/6124/6125 NÃO reabertos,
permanecem PASS), encontrando 2 problemas residuais:
1. Seção 1.7 (EXECUTE das 4 RPCs) — a query reescrita em
   6830-DIRECT-REVIEW-FIX-01 referenciava acl.grantee_role, coluna que
   NÃO existe no retorno de aclexplode() (que devolve grantee como OID,
   0 = PUBLIC, não como nome de role já resolvido). Corrigida para
   resolver o OID via LEFT JOIN pg_roles + CASE explícito para
   grantee = 0. Expectativa também corrigida: para cada RPC devem
   existir exatamente dois EXECUTE legítimos — o OWNER da função e
   authenticated — nunca "apenas uma linha authenticated" como a versão
   anterior chegou a sugerir; PUBLIC/anon/service_role/qualquer outro
   principal devem estar ausentes, e um proacl NULL que fizer PUBLIC
   aparecer via acldefault é FALHA, não um caso a ignorar.
2. Sugestão indevida de "service_role com BYPASSRLS" para exercitar DML
   direto estrutural (Caso 1b e a regra geral de contexto da Seção 3) —
   removida. BYPASSRLS desabilita a checagem de RLS, mas não concede
   privilégios de tabela (INSERT/UPDATE/DELETE); o modelo desta Fatia
   deixa service_role deliberadamente sem esses grants (mesma decisão
   de least privilege que rege authenticated). Para DML direto
   estrutural, usar somente postgres/table owner, sempre em transação
   com ROLLBACK — nunca conceder privilégio temporário a service_role
   só para viabilizar um teste.

Correção v1.4 (6830-DIRECT-REVIEW-FIX-01) — resultado de auditoria direta
dos SQLs exatos de 6123/6124/6125 (aprovados PASS, sem alteração) contra
o roteiro deste arquivo, que continha 4 problemas reais:
1. Estado físico desatualizado: o cabeçalho ainda dizia "nenhuma das
   Queries 6117-6125 foi aplicada" — falso desde a implementação real
   de 6117-6122. Corrigido na Descrição/Pré-requisitos abaixo.
2. Testes estruturais com DML direto (Casos 1b, 3b, 8, 9, 10, 17)
   descritos dentro da mesma Seção 3 cujo preâmbulo manda simular sessão
   authenticated — mas authenticated deliberadamente NÃO tem INSERT/
   UPDATE/DELETE nas duas tabelas (invariante 6, RLS/grants). Rodar esses
   Casos como authenticated produziria "permission denied for table"
   (bloqueio de GRANT/RLS) ANTES de qualquer trigger/constraint ser
   exercido — um falso-positivo se confundido com o resultado esperado.
   Anotado explicitamente em cada Caso o contexto/role exigido, dentro
   de transação com ROLLBACK, com a exceção/constraint ESPECÍFICA a
   validar (nunca "permission denied" genérico como PASS).
3. Caso 10 misturava duas provas distintas (definição da FK ON DELETE
   SET NULL vs. comportamento do trigger trg_020) como se fossem uma só,
   arriscando a leitura de que o UPDATE manual prova a ação referencial
   real. Separado em Prova A (estrutural, pg_constraint) e Prova B
   (comportamental, trigger) — sem criar/apagar usuário de teste só
   para isso.
4. Seção 1.7 dependia de "exatamente 4 linhas" em
   information_schema.role_routine_grants para provar least privilege —
   frágil se outro principal (ex. um role customizado) tiver EXECUTE por
   fora do caminho esperado, já que a view pode não expor todos os
   grantees relevantes. Reescrita com aclexplode(proacl) para enumerar
   literalmente todo o ACL de cada função.

Correção v1.2 (PAUSE-SQL-DIRECT-AUDIT-01, item 6):
- Caso 8 reescrito: a versão anterior tentava provar a PK de
  collection_pokedex_position_assignment com um INSERT direto
  assignment_basis='USER_OVERRIDE' sem assigned_by_user_id — isso é
  INTERCEPTADO por trg_005 (exige ator para USER_OVERRIDE) ANTES de
  chegar na violação de PK, então o teste como estava não provava o
  invariante anunciado. Corrigido para usar assignment_basis=
  'SPECIES_MATCH' (que trg_005 não valida), isolando a violação de PK.
- Caso 7 reescrito: a versão anterior chamava
  set_pokedex_position_assignment() para a MESMA Position que Card_Match
  já tinha desde o Caso 1 — isso é um NO-OP (retorna a linha existente),
  não prova que uma Assignment nova pode ser CRIADA/MOVIDA fora do Scope.
  Corrigido para usar uma Card/Allocation SEM Assignment ainda (ou mover
  uma existente para uma Position genuinamente diferente) enquanto o
  Scope corrente exclui aquela Species/Generation.
- Caso 2b novo: p_confirm_override = NULL explícito (distinto de omitir
  o parâmetro, que usa o DEFAULT false) deve continuar exigindo
  confirmação — prova o fix fail-closed de 6122 (via migration
  incremental 6123, renumerada de 6125 em RENUMBER-FIX-STAGING-01).
- Caso 20b novo: concorrência lifecycle — write em andamento contra
  Collection ACTIVE versus archive_collection() concorrente; resultado
  deve ser serializado pelo lock real de Collection (6122 via 6123,
  e 6124/6125 v1.1/v1.2 — remove_pokedex_position_assignment() e as RPCs
  de Primary Representative, renumeradas nesta rodada), nunca um write
  após a Collection já ARCHIVED.
- Reforço transversal: cada Caso que exercita CREATE/MOVE/SET/REPLACE
  (1, 2b, 3, 7, 11, 14, 15, 21, 21b) deve capturar e conferir a própria
  linha retornada pela RPC (a RETURNING real), não só o estado da tabela
  depois — é exatamente o caminho que teria falhado com "ambiguous
  column reference" antes da correção de qualificação de RETURNING
  (PAUSE, item 2).

Descrição...:
Bateria de validação da Fatia D (collection_pokedex_position_assignment
e collection_pokedex_position_primary_representative, Queries 6117-6125
— range expandido de 6117-6124 para 6117-6125 em
RENUMBER-FIX-STAGING-01, pela inserção da migration incremental 6123),
cobrindo os 24 itens mandatados nesta rodada.

ESTADO FÍSICO REAL (atualizado em COLLECTIONS-POKEDEX-FATIA-D-PROMOTION-
CLOSEOUT-01 — 6117-6126 aplicadas com sucesso E promovidas para
database/schema/):
- 6117, 6118, 6119, 6120, 6121, 6122, 6123, 6124, 6125, 6126: CONFIRMADO
  EXECUTADO no banco real (projeto qjfutqujxrbzgrtkpgkg) e PROMOVIDO para
  database/schema/ (corpo SQL byte-idêntico ao executado, apenas
  cabeçalho Status/Versão/Data atualizado por arquivo). Tabelas,
  triggers e as quatro RPCs (set_pokedex_position_assignment,
  remove_pokedex_position_assignment,
  set_pokedex_position_primary_representative,
  clear_pokedex_position_primary_representative) já existem e estão
  ativas; 6126 confirmada ao vivo via pg_get_functiondef (ON CONFLICT ON
  CONSTRAINT pk_collection_pokedex_position_primary_representative),
  demais invariantes (assinatura, RETURNS TABLE, SECURITY DEFINER,
  search_path, ownership, ACL, lock order, RETURNING) inalterados —
  reconfirmado em postcheck pós-cleanup (COLLECTIONS-POKEDEX-FATIA-D-
  FINAL-VALIDATION-CLEANUP-01).

EXECUÇÃO REAL DA SEÇÃO 3 (testes funcionais) — CONCLUÍDA. Casos 1 a 13
(incluindo 1b adaptado, 2b, 3b, 10 Prova A/B) executados com PASS contra
o banco real; Caso 14 encontrou o bug SQLSTATE 42702 descrito na
Correção v1.6, execução interrompida ali (STOP conforme CLAUDE.md),
corrigido via 6126 e retomada em COLLECTIONS-POKEDEX-FATIA-D-6126-
IMPLEMENT-RESUME-01 (Caso 14, Caso 12 preservação completa e Casos 15 a
24 reexecutados/executados com PASS). Lacuna de rastreabilidade do
Caso 16 (clear_pokedex_position_primary_representative, caminho "sem
Primary preexistente") fechada explicitamente em COLLECTIONS-POKEDEX-
FATIA-D-FINAL-VALIDATION-CLEANUP-01, sem reaproveitar o resultado do
Caso 21. Matriz final: zero FAIL residual nos 24 casos — todo FAIL
histórico foi SUPERSEDED por PASS posterior na própria rodada; Caso 20b
permanece o único item NOT EXECUTED / UNPROVEN (ambiente sem duas
sessões persistentes simultâneas), nunca convertido em PASS. Fixtures e
tabelas de rastreio (_fatia_d_run/_fatia_d_results) foram removidas no
cleanup final, com zero-resíduo confirmado por identidade — ver
Correção v1.8. Os blocos [SQL ESTÁTICO] desta Seção 1 continuam válidos
e já executados (6117-6126 todas já vivas e promovidas).

Mesma convenção de 5804/5806 (2B/2C): blocos [SQL ESTÁTICO] são queries
diretas sobre catálogo (information_schema/pg_constraint/pg_policies/
pg_trigger), executáveis hoje mesmo sem nenhuma Query aplicada (retornam
0 linhas até lá, o que já é parte do teste). Blocos [TESTE FUNCIONAL]
exigem sessões autenticadas distintas e são descritos como roteiro —
mesma razão de 5804/5806: collection.owner_user_id e
inventory.owner_user_id têm FK real para auth.users (confirmado nesta
auditoria); esta tabela é gerenciada pelo serviço de Auth do Supabase,
nunca por INSERT direto via SQL neste projeto (nenhum precedente em
database/ faz isso). Quando executado de fato, usar um usuário de teste
já existente (criado via Supabase Auth Admin API) e simular a sessão
com set_config('role','authenticated', true) + set_config
('request.jwt.claim.sub', '<uuid_do_owner>', true) — técnica já
validada em 5802/5804/5806. Blocos [ESTRUTURAL] validam trigger/
constraint diretamente contra fixtures sintéticas de catálogo (Game,
Pokédex, Position, Species — nenhuma delas depende de auth.users) onde
isso for suficiente para provar o invariante sem precisar de uma
Collection real.

Pré-requisitos:
- Queries 6117, 6118, 6119, 6120, 6121, 6122, 6123, 6124, 6125, 6126 —
  CONFIRMADO EXECUTADO no banco real (ver ESTADO FÍSICO REAL acima).
================================================================
*/

-- ================================================================
-- SEÇÃO 1 — VALIDAÇÃO ESTRUTURAL (executável hoje, sem fixtures)
-- ================================================================

-- 1.1 [SQL ESTÁTICO] Tabelas existem com as colunas esperadas
SELECT table_name, column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name IN (
      'collection_pokedex_position_assignment',
      'collection_pokedex_position_primary_representative'
  )
ORDER BY table_name, ordinal_position;
-- Esperado (assignment): collection_allocation_id (uuid, NO), pokedex_
-- position_id (uuid, NO), assignment_basis (text, NO), assigned_at
-- (timestamptz, NO), assigned_by_user_id (uuid, YES).
-- Esperado (primary_representative): collection_id (uuid, NO),
-- pokedex_position_id (uuid, NO), collection_allocation_id (uuid, NO),
-- created_at (timestamptz, NO), updated_at (timestamptz, NO).

-- 1.2 [SQL ESTÁTICO] PK/UNIQUE/FK de collection_pokedex_position_assignment
SELECT conname, contype, pg_get_constraintdef(oid) AS definicao
FROM pg_constraint
WHERE conrelid = 'public.collection_pokedex_position_assignment'::regclass
ORDER BY contype, conname;
-- Esperado: PK em (collection_allocation_id); FK collection_allocation_id
-- -> collection_allocation(id) ON DELETE CASCADE; FK pokedex_position_id
-- -> pokedex_position(id) ON DELETE RESTRICT; FK assigned_by_user_id ->
-- auth.users(id) ON DELETE SET NULL; CHECK assignment_basis IN
-- ('SPECIES_MATCH','USER_OVERRIDE'). (item 8, 9, 10, 13, 19 — base
-- estrutural)

-- 1.3 [SQL ESTÁTICO] PK/UNIQUE/FK de collection_pokedex_position_primary_representative
SELECT conname, contype, pg_get_constraintdef(oid) AS definicao
FROM pg_constraint
WHERE conrelid = 'public.collection_pokedex_position_primary_representative'::regclass
ORDER BY contype, conname;
-- Esperado: PK (collection_id, pokedex_position_id); UNIQUE
-- (collection_allocation_id); FK collection_id -> collection(id)
-- RESTRICT; FK pokedex_position_id -> pokedex_position(id) RESTRICT;
-- FK collection_allocation_id -> collection_pokedex_position_assignment
-- (collection_allocation_id) ON DELETE CASCADE. (item 14-19 — base
-- estrutural)

-- 1.4 [SQL ESTÁTICO] Triggers ativos
SELECT tgrelid::regclass::text AS tabela, tgname, pg_get_triggerdef(oid) AS definicao
FROM pg_trigger
WHERE tgrelid IN (
      'public.collection_pokedex_position_assignment'::regclass,
      'public.collection_pokedex_position_primary_representative'::regclass,
      'public.collection_allocation'::regclass
  )
  AND NOT tgisinternal
ORDER BY tabela, tgname;
-- Esperado (assignment): trg_005_enforce_..._user_override_actor (BEFORE
-- INSERT — correção STAGING-AUDIT-01 item 1), trg_010_enforce_..._
-- pokedex_match (BEFORE INSERT), trg_020_govern_... (BEFORE UPDATE).
-- Esperado (primary_representative): trg_010_validate_..._integrity
-- (BEFORE INSERT OR UPDATE), trg_020_touch_..._updated_at (BEFORE
-- UPDATE).
-- Esperado (collection_allocation): as 4 já existentes (2C) MAIS
-- trg_collection_allocation_auto_assign_species_match (AFTER INSERT,
-- REFERENCING NEW TABLE, FOR EACH STATEMENT) — item 1.

-- 1.5 [SQL ESTÁTICO] RLS habilitado, zero policy de escrita
SELECT c.relname, c.relrowsecurity
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relname IN (
      'collection_pokedex_position_assignment',
      'collection_pokedex_position_primary_representative'
  );
-- Esperado: relrowsecurity = true para as duas.

SELECT tablename, policyname, cmd
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN (
      'collection_pokedex_position_assignment',
      'collection_pokedex_position_primary_representative'
  )
ORDER BY tablename, policyname;
-- Esperado: exatamente 1 policy por tabela, cmd = 'SELECT'. Zero
-- policy de INSERT/UPDATE/DELETE (item 22).

-- 1.6 [SQL ESTÁTICO] Grants — least privilege (item 22)
SELECT table_name, grantee, privilege_type
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
  AND table_name IN (
      'collection_pokedex_position_assignment',
      'collection_pokedex_position_primary_representative'
  )
  AND grantee IN ('anon', 'authenticated', 'service_role');
-- Esperado: única linha por tabela é (authenticated, SELECT). ZERO
-- linhas para anon. ZERO linhas de INSERT/UPDATE/DELETE/TRUNCATE/
-- REFERENCES/TRIGGER/MAINTAIN para qualquer papel, inclusive
-- service_role (lição de least privilege, Query 6111/6112).

-- 1.7 [SQL ESTÁTICO] EXECUTE das 4 RPCs restrito a authenticated (item 22)
-- Corrigido em 6830-DIRECT-REVIEW-FIX-01, item 5: a versão anterior
-- consultava information_schema.role_routine_grants e assumia "exatamente
-- 4 linhas" como prova de least privilege — frágil, porque essa view não
-- garante expor TODO principal com EXECUTE (ex.: um role customizado ou
-- um grant direto ao dono da função por fora do caminho esperado).
-- Reescrita com aclexplode(proacl) para enumerar literalmente todo o ACL
-- de cada função, sem depender da view intermediária.
-- Corrigida novamente em 6830-DIRECT-REVIEW-FIX-02, item 1: a versão
-- anterior (v1.4) referenciava acl.grantee_role, que NÃO existe no
-- retorno de aclexplode() — aclexplode retorna grantee como OID (0 =
-- PUBLIC), não como um nome de role já resolvido. Corrigida para
-- resolver o OID via JOIN com pg_roles, com CASE explícito para o caso
-- grantee = 0 (PUBLIC não tem linha em pg_roles).
SELECT
    p.proname,
    CASE
        WHEN acl.grantee = 0 THEN 'PUBLIC'
        ELSE r.rolname
    END AS grantee,
    acl.privilege_type,
    (acl.grantee = p.proowner) AS is_owner
FROM pg_proc p
CROSS JOIN LATERAL
    aclexplode(
        COALESCE(p.proacl, acldefault('f', p.proowner))
    ) AS acl(grantor, grantee, privilege_type, is_grantable)
LEFT JOIN pg_roles r
    ON r.oid = acl.grantee
WHERE p.pronamespace = 'public'::regnamespace
  AND p.proname IN (
      'set_pokedex_position_assignment',
      'remove_pokedex_position_assignment',
      'set_pokedex_position_primary_representative',
      'clear_pokedex_position_primary_representative'
  )
  AND acl.privilege_type = 'EXECUTE'
ORDER BY p.proname, grantee;
-- Esperado (corrigido em 6830-DIRECT-REVIEW-FIX-02, item 1 — não afirmar
-- mais "única linha authenticated"): para cada uma das 4 funções, as
-- ÚNICAS linhas com privilege_type = 'EXECUTE' devem ser exatamente
-- duas: (a) o OWNER da função (is_owner = true; hoje postgres — todo
-- owner de função tem EXECUTE implícito, materializado no ACL por
-- acldefault quando proacl é NULL, ou explicitamente se proacl já foi
-- customizado) e (b) authenticated (is_owner = false). DEVEM ESTAR
-- AUSENTES, para as 4 funções: PUBLIC, anon, service_role, e qualquer
-- outro role/principal não previsto. Se p.proacl for NULL e isso fizer
-- PUBLIC aparecer via acldefault('f', p.proowner) — comportamento
-- padrão do Postgres, que concede EXECUTE a PUBLIC em funções novas
-- quando o ACL nunca foi customizado — isso é uma FALHA a sinalizar
-- (proacl deveria estar explicitamente REVOKE'd de PUBLIC e GRANT'd só
-- a authenticated, além do owner implícito), não um caso a ignorar ou
-- relativizar. Qualquer linha além dessas duas por função é uma
-- violação de least privilege a investigar antes do GO.

-- 1.8 [SQL ESTÁTICO] SECURITY DEFINER + search_path='' nas 4 RPCs
SELECT p.proname, p.prosecdef, p.proconfig
FROM pg_proc p
WHERE p.pronamespace = 'public'::regnamespace
  AND p.proname IN (
      'set_pokedex_position_assignment',
      'remove_pokedex_position_assignment',
      'set_pokedex_position_primary_representative',
      'clear_pokedex_position_primary_representative',
      'auto_assign_pokedex_position_species_match'
  );
-- Esperado: prosecdef = true e proconfig contendo 'search_path=' para
-- as 4 RPCs de escrita. auto_assign_... é trigger function (SET
-- search_path = public, sem SECURITY DEFINER — roda com o privilégio
-- de quem já disparou o INSERT em collection_allocation via RPC
-- SECURITY DEFINER, mesmo padrão de validate_collection_allocation_
-- integrity, 2C).

-- ================================================================
-- SEÇÃO 2 — VALIDAÇÃO COMPORTAMENTAL [ESTRUTURAL], fixtures de
-- catálogo puro (sem Collection/auth.users) — provam os triggers das
-- Queries 6118/6121 isoladamente.
-- ================================================================

BEGIN;

DO $$
DECLARE
    v_pokedex_a       UUID;
    v_pokedex_b       UUID;
    v_generation      UUID;
    v_region          UUID;
    v_species_1       UUID;
    v_species_2       UUID;
    v_position_a1     UUID; -- Pokédex A, Species 1
    v_position_b1     UUID; -- Pokédex B, mesma Species 1 (Pokédex errado para A)
    v_fake_allocation UUID := gen_random_uuid();
BEGIN
    -- Fixtures de catálogo puro (não dependem de auth.users).
    INSERT INTO public.pokemon_region (code, canonical_name)
        VALUES ('TEST_REGION_6830', 'Test Region 6830') RETURNING id INTO v_region;
    INSERT INTO public.pokemon_generation (code, canonical_name, ordinal_number, main_region_id)
        VALUES ('TEST_GEN_6830', 'Test Generation 6830', 999, v_region) RETURNING id INTO v_generation;
    INSERT INTO public.pokemon_species (generation_id, national_dex_number, canonical_name)
        VALUES (v_generation, 99901, 'Test Species 1 6830') RETURNING id INTO v_species_1;
    INSERT INTO public.pokemon_species (generation_id, national_dex_number, canonical_name)
        VALUES (v_generation, 99902, 'Test Species 2 6830') RETURNING id INTO v_species_2;
    INSERT INTO public.pokedex (code, canonical_name)
        VALUES ('TEST_POKEDEX_A_6830', 'Test Pokedex A 6830') RETURNING id INTO v_pokedex_a;
    INSERT INTO public.pokedex (code, canonical_name)
        VALUES ('TEST_POKEDEX_B_6830', 'Test Pokedex B 6830') RETURNING id INTO v_pokedex_b;
    INSERT INTO public.pokedex_position (pokedex_id, species_id, position_number)
        VALUES (v_pokedex_a, v_species_1, 1) RETURNING id INTO v_position_a1;
    INSERT INTO public.pokedex_position (pokedex_id, species_id, position_number)
        VALUES (v_pokedex_b, v_species_1, 1) RETURNING id INTO v_position_b1;

    -- Caso ESTRUTURAL 1 (item 6): INSERT direto em
    -- collection_pokedex_position_assignment apontando para uma
    -- Position cujo Pokédex não é o da Collection referenciada pela
    -- Allocation deveria disparar trg_010 (enforce_pokedex_position_
    -- assignment_pokedex_match). Como v_fake_allocation não existe em
    -- collection_allocation, a FK de collection_allocation_id falha
    -- ANTES do trigger BEFORE INSERT ser útil para provar o guard de
    -- Pokédex isoladamente — este caso específico (mismatch de
    -- Pokédex) só é provável de ponta a ponta com uma Allocation real
    -- (ver roteiro da Seção 3, Caso 6). Mantido aqui como
    -- documentação do motivo, não como asserção executável.
    RAISE NOTICE 'NOTA: item 6 (Position de outro Pokédex) requer Allocation real — ver Seção 3, Caso 6.';

    RAISE NOTICE 'Fixtures de catálogo puro OK: pokedex_a=%, pokedex_b=%, position_a1=%, position_b1=%',
        v_pokedex_a, v_pokedex_b, v_position_a1, v_position_b1;
END;
$$;

ROLLBACK;

-- ================================================================
-- SEÇÃO 3 — VALIDAÇÃO COMPORTAMENTAL [TESTE FUNCIONAL], roteiro
-- (mesma convenção de 5804/5806) — exige um usuário de teste real
-- (criado via Supabase Auth Admin API, NUNCA por INSERT direto em
-- auth.users) cujo id substitui <owner_uuid> abaixo, e fixtures reais
-- de Game/Card Set/Card/Card Variant/Physical Card/Inventory/
-- Collection construídas com esse owner. Cada Caso assume que os
-- Casos anteriores da mesma "trilha" já foram executados na mesma
-- sessão (mesmo padrão de dependência sequencial de 5806).
--
-- Simulação de sessão: set_config('role', 'authenticated', true);
-- set_config('request.jwt.claim.sub', '<owner_uuid>', true);
--
-- REGRA GERAL DE CONTEXTO (6830-DIRECT-REVIEW-FIX-01, item 2): todo
-- Caso desta Seção que chama uma das 4 RPCs ou a trigger automática
-- roda normalmente como authenticated (é exatamente o caminho de
-- produção). Mas os Casos que fazem DML DIRETO nas tabelas
-- collection_pokedex_position_assignment/collection_pokedex_position_
-- primary_representative para testar trigger/constraint isoladamente
-- (1b, 3b, 8, 9, 10-Prova B, 17) NÃO podem rodar como authenticated —
-- essa role deliberadamente não tem INSERT/UPDATE/DELETE nessas tabelas
-- (Seção 1.5/1.6, least privilege). Cada um desses Casos está anotado
-- individualmente com o contexto/role privilegiado exigido: postgres/
-- table owner. NUNCA service_role (corrigido em
-- 6830-DIRECT-REVIEW-FIX-02, item 2 — BYPASSRLS não concede INSERT/
-- UPDATE/DELETE; o modelo desta Fatia deixa service_role deliberadamente
-- sem DML direto nessas tabelas, e conceder privilégio temporário a
-- service_role só para viabilizar um teste violaria essa decisão).
-- authenticated permanece exclusivo para os caminhos reais via RPC.
-- Sempre dentro de uma transação com ROLLBACK ao final para não deixar
-- resíduo, e sempre validando a exceção/constraint ESPECÍFICA esperada
-- — um "permission
-- denied for table" genérico nunca deve ser aceito como PASS destes
-- Casos, pois indicaria que o teste nem chegou a exercitar o
-- trigger/constraint sob prova. Ao final de cada bloco privilegiado,
-- restaurar explicitamente set_config('role','authenticated', true) +
-- set_config('request.jwt.claim.sub', '<owner_uuid>', true) antes de
-- prosseguir para o próximo Caso da trilha que dependa do contexto do
-- owner de teste.
-- ================================================================

-- Fixture-base do roteiro (uma vez, fora de qualquer Caso):
--   1. Game/Expansion/CardSet/Rarity/CardVariantType (catálogo, como
--      superuser).
--   2. Pokédex + Position TEST_A (Species TEST_1) e Position TEST_B
--      (mesmo Pokédex, Species TEST_2, para o Caso 11/12) e Position
--      TEST_C (Pokédex DIFERENTE, mesma Species TEST_1, para o Caso 6).
--   3. Duas Cards POKEMON: Card_Match (card_primary_species aponta
--      para Species TEST_1 via AUTOMATIC_DEXID ou EDITORIAL_
--      RECONCILIATION, Query 6114/6115) e Card_Mismatch (sem linha em
--      card_primary_species, ou apontando para uma Species diferente
--      de qualquer Position do Pokédex TEST). Uma Card TRAINER
--      (Card_Trainer, category_id de card_category.code='TRAINER').
--   4. Um Physical Card por Card acima (mesmo inventory_id do owner
--      de teste).
--   5. Uma Collection REFERENCE_BASED/POKEDEX referenciando o Pokédex
--      TEST via create_reference_based_pokedex_collection() (função
--      já existente, Fatia B).

-- Caso 1 — SPECIES_MATCH automático após Allocation.
--   allocate_physical_cards_to_collection(collection_id, ARRAY[Card_Match.physical_card_id]);
--   SELECT * FROM collection_pokedex_position_assignment
--     WHERE collection_allocation_id = <allocation de Card_Match>;
--   Esperado: 1 linha, pokedex_position_id = Position TEST_A,
--   assignment_basis = 'SPECIES_MATCH', assigned_by_user_id IS NULL.

-- Caso 1b — auto-match não dispara fora de REFERENCE_BASED
-- (STAGING-AUDIT-01, item 2, defesa em profundidade).
--   Cenário hipotético (não deveria ocorrer em uso normal, mas não é
--   impedido por constraint que o mode↔reference_kind seja violado):
--   uma Collection cujo mode NÃO é 'REFERENCE_BASED' mas que ainda
--   possui uma linha remanescente em collection_reference/collection_
--   pokedex_reference (reference_kind='POKEDEX'). Alocar uma Card com
--   Species correspondente a essa Collection.
--   Esperado: trigger 6119 NÃO cria nenhuma Assignment (o JOIN exige
--   explicitamente col.mode = 'REFERENCE_BASED' agora) — 0 linhas em
--   collection_pokedex_position_assignment para aquela Allocation.
--   CONTEXTO/ROLE (corrigido em 6830-DIRECT-REVIEW-FIX-01, item 2):
--   forçar o estado remanescente em collection_reference/collection_
--   pokedex_reference exige UPDATE/INSERT direto nessas tabelas de
--   catálogo, bypassando os caminhos normais de criação/lifecycle de
--   Collection Pokédex — authenticated não tem esse GRANT (RLS/escrita
--   só via RPC), então esta parte do setup deve rodar como
--   table owner/role privilegiado (ex.: postgres). NUNCA service_role
--   (corrigido em 6830-DIRECT-REVIEW-FIX-02, item 2 — BYPASSRLS não
--   concede INSERT/UPDATE/DELETE, e o modelo desta Fatia deixa
--   service_role deliberadamente sem DML direto nessas tabelas; não
--   conceder privilégio temporário a service_role só para viabilizar
--   este teste), dentro de uma transação com ROLLBACK ao final. A
--   ALOCAÇÃO em si (allocate_physical_cards_to_collection) já pode ser
--   feita como authenticated normalmente, pois é uma RPC. Após o setup
--   privilegiado e a alocação, restaurar explicitamente o contexto
--   authenticated + request.jwt.claim.sub do owner de teste antes de
--   prosseguir para o próximo Caso da trilha. A asserção específica é
--   "0 linhas em collection_pokedex_position_assignment para aquela
--   Allocation" — não aceitar "nenhum erro" como prova, o trigger deve
--   ter rodado e decidido não inserir.

-- Caso 2 — mismatch sem confirmação → bloqueado.
--   allocate_physical_cards_to_collection(collection_id, ARRAY[Card_Mismatch.physical_card_id]);
--   -- trigger 6119 não cria Assignment (nenhum match) — confirmar 0 linhas.
--   set_pokedex_position_assignment(Card_Mismatch.physical_card_id, PositionTEST_A, false);
--   Esperado: RAISE EXCEPTION SET_POKEDEX_POSITION_ASSIGNMENT_CONFIRMATION_REQUIRED.

-- Caso 2b — p_confirm_override = NULL explícito → continua bloqueado,
-- fail-closed (PAUSE-SQL-DIRECT-AUDIT-01, item 1 — bug corrigido em
-- 6122 (via migration incremental 6123, renumerada de 6125): "IF NOT
-- p_confirm_override" tratava NULL como falso-negativo, permitindo
-- bypass silencioso da confirmação).
--   set_pokedex_position_assignment(Card_Mismatch.physical_card_id, PositionTEST_A, NULL);
--   Esperado (v1.1/6123, corrigido): RAISE EXCEPTION
--   SET_POKEDEX_POSITION_ASSIGNMENT_CONFIRMATION_REQUIRED — idêntico ao
--   comportamento de p_confirm_override = false. Antes da correção
--   (bug confirmado por leitura direta do corpo aplicado), esta chamada
--   teria criado um USER_OVERRIDE silenciosamente, sem nenhuma
--   confirmação real do chamador.

-- Caso 3 — mismatch com confirmação → USER_OVERRIDE.
--   set_pokedex_position_assignment(Card_Mismatch.physical_card_id, PositionTEST_A, true);
--   Esperado: 1 linha RETORNADA PELA PRÓPRIA RPC (capturar a RETURNING
--   real, não só reconsultar a tabela depois — exercita a correção de
--   qualificação de RETURNING, PAUSE item 2), assignment_basis =
--   'USER_OVERRIDE', assigned_by_user_id = <owner_uuid> (nunca NULL — a
--   própria RPC sempre grava auth.uid() quando v_basis = 'USER_OVERRIDE',
--   e o trg_005 (6118, STAGING-AUDIT-01 item 1) reforça isso
--   estruturalmente contra qualquer INSERT direto que bypassasse a RPC).

-- Caso 3b — USER_OVERRIDE sem ator, via INSERT direto → bloqueado
-- estruturalmente (STAGING-AUDIT-01, item 1, defesa em profundidade).
--   CONTEXTO/ROLE (corrigido em 6830-DIRECT-REVIEW-FIX-01, item 2):
--   este INSERT é direto na tabela, bypassando a RPC — authenticated
--   NÃO tem GRANT de INSERT nela (só SELECT, ver Seção 1.6/1.5), então
--   rodar como authenticated produziria "permission denied for table
--   collection_pokedex_position_assignment" (bloqueio de GRANT/RLS)
--   ANTES do trigger trg_005 ser sequer avaliado — um falso-positivo se
--   confundido com o resultado esperado abaixo. Rodar como table
--   owner/role privilegiado (ex.: postgres), dentro de uma transação
--   com ROLLBACK ao final, e restaurar authenticated +
--   request.jwt.claim.sub do owner de teste logo em seguida.
--   INSERT INTO collection_pokedex_position_assignment
--     (collection_allocation_id, pokedex_position_id, assignment_basis, assigned_at, assigned_by_user_id)
--     VALUES (<allocation livre, sem Assignment ainda>, PositionTEST_A, 'USER_OVERRIDE', NOW(), NULL);
--   Esperado (asserção específica, não "permission denied" genérico):
--   RAISE EXCEPTION COLLECTION_POKEDEX_POSITION_ASSIGNMENT_
--   USER_OVERRIDE_REQUIRES_ACTOR (trg_005, Query 6118) — a RPC nunca
--   produziria este estado (ela mesma grava auth.uid()), mas o trigger
--   garante que nenhum caminho de escrita, presente ou futuro, consiga
--   criar uma linha USER_OVERRIDE sem um ator identificável.
--   Repetir o mesmo INSERT (ainda como role privilegiado, mesma
--   transação) com assignment_basis = 'SPECIES_MATCH' e
--   assigned_by_user_id = NULL -> Esperado: SUCESSO (trg_005 não valida
--   nada para SPECIES_MATCH, só para USER_OVERRIDE). ROLLBACK ao final
--   para não deixar resíduo desta linha sintética.

-- Caso 4 — Species ausente → mesma regra do Caso 2/3.
--   Repetir Casos 2/3 com uma Card POKEMON sem nenhuma linha em
--   card_primary_species (resolução ainda pendente, não mismatch).
--   Esperado: mesmo comportamento — bloqueado sem confirmação, USER_
--   OVERRIDE com confirmação.

-- Caso 5 — TRAINER/ENERGY → mesma regra.
--   allocate_physical_cards_to_collection(collection_id, ARRAY[Card_Trainer.physical_card_id]);
--   set_pokedex_position_assignment(Card_Trainer.physical_card_id, PositionTEST_A, false);
--   Esperado: bloqueado (category_code <> 'POKEMON').
--   set_pokedex_position_assignment(Card_Trainer.physical_card_id, PositionTEST_A, true);
--   Esperado: USER_OVERRIDE.

-- Caso 6 — Position de outro Pokédex → bloqueada.
--   set_pokedex_position_assignment(Card_Match.physical_card_id, PositionTEST_C, true);
--   -- PositionTEST_C pertence a um Pokédex diferente do referenciado
--   -- pela Collection.
--   Esperado: RAISE EXCEPTION SET_POKEDEX_POSITION_ASSIGNMENT_WRONG_POKEDEX
--   (mesmo guard do trigger 6118/trg_010, exercitado aqui via RPC).

-- Caso 7 — Position fora do Scope → permitida (REESCRITO,
-- PAUSE-SQL-DIRECT-AUDIT-01 item 6: a versão anterior chamava a RPC para
-- a MESMA Position que Card_Match já tinha desde o Caso 1 — isso é um
-- NO-OP, não prova CREATE/MOVE fora do Scope). Requer uma Card/Allocation
-- adicional (Card_Match_Scope) com SPECIES_MATCH ainda não atribuída, OU
-- mover Card_Match para uma Position genuinamente diferente (mesmo
-- Pokédex) enquanto o Scope corrente exclui a Generation/Species dela.
--   -- Preparação: alocar uma Card nova (Card_Match_Scope, Species
--   -- TEST_1, mesma Species de PositionTEST_A) SEM que o trigger 6119
--   -- ainda tenha criado Assignment para ela (ex.: card_primary_species
--   -- resolvida só DEPOIS da Allocation, para forçar o caminho manual
--   -- via RPC em vez do trigger automático).
--   set_collection_pokedex_scope(collection_id, 'GENERATION_FILTERED', ARRAY[<generation diferente da de TEST_1>]);
--   set_pokedex_position_assignment(Card_Match_Scope.physical_card_id, PositionTEST_A_ou_outra_livre, false);
--   Esperado: SUCESSO — capturar a RETURNING real da chamada (1 linha
--   NOVA, assignment_basis conforme o match), confirmando que uma
--   Assignment é de fato CRIADA (não um no-op) mesmo com a Position/
--   Species correspondente fora do Scope corrente — nenhuma checagem de
--   Scope em nenhum trigger/RPC desta Fatia (LDM-177).

-- Caso 8 — 1 Allocation → no máximo 1 Assignment (REESCRITO,
-- PAUSE-SQL-DIRECT-AUDIT-01 item 6: a versão anterior usava
-- assignment_basis='USER_OVERRIDE' sem assigned_by_user_id, o que é
-- INTERCEPTADO por trg_005 — "USER_OVERRIDE exige ator" — antes de
-- chegar na violação de PK, não provando o invariante anunciado).
-- Confirmar PK física de collection_pokedex_position_assignment já
-- garante isto por construção — tentar, com assignment_basis =
-- 'SPECIES_MATCH' (trg_005 não valida nada para SPECIES_MATCH) e
-- assigned_by_user_id NULL, para isolar exclusivamente a violação de PK:
--   CONTEXTO/ROLE (corrigido em 6830-DIRECT-REVIEW-FIX-01, item 2): este
--   INSERT bypassa a RPC; authenticated não tem GRANT de INSERT nesta
--   tabela. Rodar como table owner/role privilegiado, dentro de
--   transação com ROLLBACK, para que o erro observado seja a violação
--   de PK do Postgres e não "permission denied for table" do GRANT.
--   Restaurar authenticated + request.jwt.claim.sub logo após.
--   INSERT INTO collection_pokedex_position_assignment
--     (collection_allocation_id, pokedex_position_id, assignment_basis, assigned_at, assigned_by_user_id)
--     VALUES (<allocation de Card_Match>, PositionTEST_B, 'SPECIES_MATCH', NOW(), NULL);
--   diretamente (bypassando a RPC) quando já existe uma linha para a
--   mesma Allocation.
--   Esperado (asserção específica): ERROR de violação de PK
--   (SQLSTATE 23505, duplicate key value viola unique constraint
--   "pk_collection_pokedex_position_assignment" ou nome equivalente) —
--   confirmando que a PK, e não trg_005, é quem bloqueia aqui. Não
--   aceitar qualquer ERROR genérico como PASS.

-- Caso 9 — Assignment UPDATE normal → bloqueado.
--   CONTEXTO/ROLE (corrigido em 6830-DIRECT-REVIEW-FIX-01, item 2): este
--   UPDATE é direto na tabela; authenticated não tem GRANT de UPDATE
--   nela (só SELECT). Rodar como table owner/role privilegiado, dentro
--   de transação com ROLLBACK, para que a exceção observada venha do
--   trigger trg_020 (imutabilidade), não de "permission denied for
--   table" do GRANT. Restaurar authenticated + request.jwt.claim.sub
--   logo após.
--   UPDATE collection_pokedex_position_assignment
--     SET pokedex_position_id = PositionTEST_B
--     WHERE collection_allocation_id = <allocation de Card_Match>;
--   Esperado (asserção específica): RAISE EXCEPTION
--   COLLECTION_POKEDEX_POSITION_ASSIGNMENT_IMMUTABLE
--   (trg_020_govern_collection_pokedex_position_assignment, Query 6118)
--   — não aceitar "permission denied" genérico como prova desta
--   exceção.

-- Caso 10 — limpeza técnica assigned_by_user_id → NULL → permitida.
-- DIVIDIDO EM DUAS PROVAS DISTINTAS (corrigido em
-- 6830-DIRECT-REVIEW-FIX-01, item 3 — a versão anterior misturava as
-- duas como se fossem uma só prova, arriscando a leitura de que o
-- UPDATE manual abaixo prova que uma exclusão real de auth.users
-- ocorreu; ele prova apenas que o trigger aceita a transição técnica).
-- Sem criar/apagar usuário de teste real só para isto.
--
-- PROVA A [SQL ESTÁTICO, estrutural] — a FK está definida como
-- ON DELETE SET NULL contra auth.users(id):
--   SELECT conname, confrelid::regclass::text AS referenced_table,
--          confdeltype -- 'n' = SET NULL
--     FROM pg_constraint
--    WHERE conrelid = 'public.collection_pokedex_position_assignment'::regclass
--      AND conname = 'fk_collection_pokedex_position_assignment_assigned_by_user_id';
--   Esperado: confrelid = 'auth.users', confdeltype = 'n' (SET NULL).
--   Isto é a única prova de que uma exclusão REAL em auth.users
--   dispararia a ação referencial — não depende de UPDATE manual.
--
-- PROVA B [comportamental, trigger] — trg_020 aceita especificamente
-- esta transição técnica (assigned_by_user_id NOT NULL -> NULL, mais
-- nenhum outro campo alterado), sem afirmar que isto reproduz uma
-- exclusão real de auth.users:
--   CONTEXTO/ROLE: UPDATE direto na tabela, authenticated não tem GRANT
--   de UPDATE. Rodar como table owner/role privilegiado, dentro de
--   transação com ROLLBACK, restaurando authenticated +
--   request.jwt.claim.sub logo após.
--   UPDATE collection_pokedex_position_assignment
--     SET assigned_by_user_id = NULL
--     WHERE collection_allocation_id = <allocation de Card_Mismatch (USER_OVERRIDE, Caso 3)>;
--   Esperado: SUCESSO — único UPDATE que trg_020 permite (a MESMA
--   transição técnica que ON DELETE SET NULL produziria — a prova NÃO
--   afirma que a origem foi uma exclusão genuína de auth.users, apenas
--   que o trigger tecnicamente aceita essa forma específica de UPDATE).
--   Repetir a mesma UPDATE (mesma transação, mesmo contexto
--   privilegiado) mudando também outro campo junto (ex.:
--   assignment_basis) na mesma chamada -> Esperado (asserção
--   específica): RAISE EXCEPTION
--   COLLECTION_POKEDEX_POSITION_ASSIGNMENT_IMMUTABLE (a exceção exige
--   TODOS os demais campos IS NOT DISTINCT FROM OLD) — não "permission
--   denied" genérico.

-- Caso 11 — move Assignment → DELETE+INSERT atômico.
--   set_pokedex_position_assignment(Card_Match.physical_card_id, PositionTEST_B_mesmo_pokedex, false);
--   -- Card_Match já tinha Assignment em PositionTEST_A (Caso 1).
--   -- PositionTEST_B_mesmo_pokedex tem Species TEST_2 (mismatch) ->
--   -- precisa p_confirm_override = true.
--   set_pokedex_position_assignment(Card_Match.physical_card_id, PositionTEST_B_mesmo_pokedex, true);
--   Esperado: SUCESSO — 1 linha só para aquela Allocation, agora
--   apontando para PositionTEST_B_mesmo_pokedex, assignment_basis =
--   'USER_OVERRIDE', assigned_at atualizado (linha NOVA, não a
--   antiga). Confirmar exatamente 1 linha total para a Allocation
--   (não 2).

-- Caso 12 — move inválido → Assignment/Position/Primary preservados por
--   rollback (corrigido em COLLECTIONS-POKEDEX-FATIA-D-6126-IMPLEMENT-
--   RESUME-01, item D: a versão anterior assumia literalmente
--   "PositionTEST_A", mas a Position real de Card_Match neste ponto da
--   trilha depende do estado acumulado dos Casos anteriores — capturar
--   sempre o valor CORRENTE, nunca um literal fixo).
--   Antes de mover, definir Primary Representative de Card_Match (ver
--   Caso 14) e CAPTURAR o estado corrente (não assumir qual Position é):
--   SELECT a.pokedex_position_id INTO <v_pos_antes>
--     FROM collection_pokedex_position_assignment a
--    WHERE a.collection_allocation_id = <allocation de Card_Match>;
--   SELECT pr.collection_allocation_id INTO <v_primary_alloc_antes>
--     FROM collection_pokedex_position_primary_representative pr
--    WHERE pr.pokedex_position_id = <v_pos_antes>;
--   -- (v_primary_alloc_antes deve ser <allocation de Card_Match>, pelo
--   -- Caso 14 imediatamente anterior)
--   Tentar mover Card_Match para uma Position inexistente:
--   set_pokedex_position_assignment(Card_Match.physical_card_id, gen_random_uuid(), false);
--   Esperado: RAISE EXCEPTION SET_POKEDEX_POSITION_ASSIGNMENT_POSITION_NOT_FOUND
--   -- toda a chamada é uma única transação de RPC: confirmar, DEPOIS do
--   -- erro, que TODOS os três permanecem exatamente como capturados
--   -- ANTES da tentativa (nada foi desfeito indevidamente, e nada do
--   -- DELETE parcial vazou):
--   -- 1. mesma Assignment (mesma linha, mesmo collection_allocation_id);
--   -- 2. mesma pokedex_position_id = <v_pos_antes> (não gen_random_uuid());
--   -- 3. mesmo Primary Representative, ainda apontando para
--   --    <allocation de Card_Match> na mesma <v_pos_antes>.

-- Caso 13 — deallocate → Assignment removida por CASCADE.
--   deallocate_physical_cards_from_collection(collection_id, ARRAY[Card_Trainer.physical_card_id]);
--   SELECT count(*) FROM collection_pokedex_position_assignment
--     WHERE collection_allocation_id = <allocation de Card_Trainer>;
--   Esperado: 0 linhas (CASCADE via collection_allocation_id, Query 6117).

-- INCIDENTE (COLLECTIONS-POKEDEX-FATIA-D-6126-STAGING-01, Correção v1.6
-- do header acima; texto ajustado em v1.7, item A): a execução real
-- deste Caso 14, na primeira chamada de
-- set_pokedex_position_primary_representative(uuid) desta bateria,
-- falhou com SQLSTATE 42702 ("column reference \"collection_id\" is
-- ambiguous"), na própria RETURN QUERY (INSERT ... ON CONFLICT
-- (collection_id, pokedex_position_id) ... RETURNING). A ambiguidade do
-- alvo do ON CONFLICT ocorre em tempo de RESOLUÇÃO DA INSTRUÇÃO, contra
-- os OUT-parameters de mesmo nome do RETURNS TABLE, sob
-- plpgsql.variable_conflict = 'error' — independentemente de existir ou
-- não um conflito real (uma linha pré-existente) na chamada; não é
-- necessário haver colisão real no UPSERT para o erro se manifestar.
-- Esta foi a CAUSA DO STOP que interrompeu a execução real da Seção 3
-- nesta rodada. Correção: 6126 (CONFIRMADO EXECUTADO em
-- COLLECTIONS-POKEDEX-FATIA-D-6126-IMPLEMENT-RESUME-01, postcheck via
-- pg_get_functiondef sem divergências): troca do conflict target por
-- `ON CONFLICT ON CONSTRAINT
-- pk_collection_pokedex_position_primary_representative`. Este Caso 14
-- está sendo reexecutado nesta rodada contra a função corrigida.

-- Caso 14 — Primary set (v1.7, item B: prova do caminho de INSERT +
-- RETURNING real da RPC corrigida — não um "DO NOTHING", apenas ausência
-- de conflito, já que não existe Primary Representative prévio para
-- esta Position).
--   set_pokedex_position_primary_representative(<allocation de Card_Match>);
--   Esperado: 1 linha em collection_pokedex_position_primary_
--   representative, (collection_id, Position corrente de Card_Match
--   conforme estado real herdado do Caso 11, <allocation de Card_Match>)
--   — deve consumir a RETURNING real da RPC (não só o SELECT posterior
--   da tabela), exatamente a via que expôs o bug 42702 acima; só
--   considerar PASS após reexecução bem-sucedida contra 6126 já aplicada.

-- Caso 15 — Primary replace (v1.7, item C: prova específica do caminho
-- de CONFLITO — DO UPDATE — do ON CONFLICT corrigido em 6126; o Caso 14
-- prova apenas o caminho de INSERT sem conflito, este Caso é quem
-- exercita de fato a colisão real na PK e o UPDATE resultante).
--   -- Alocar uma segunda Card (Card_Match_2) com SPECIES_MATCH para a
--   -- mesma Position do Primary corrente, depois:
--   set_pokedex_position_primary_representative(<allocation de Card_Match_2>);
--   Esperado: a mesma PK (collection_id, Position) agora aponta para
--   Card_Match_2 — exatamente 1 linha total para aquela Position
--   (UPDATE via ON CONFLICT, não um segundo INSERT).

-- Caso 16 — Primary clear.
--   clear_pokedex_position_primary_representative(collection_id, <Position do Caso 15>);
--   Esperado: 0 linhas para aquela Position. Chamar de novo (idempotência
--   negativa, ver Caso 21) -> RAISE EXCEPTION ..._NOT_FOUND.

-- Caso 17 — Primary de Position errada → bloqueado.
--   CONTEXTO/ROLE (corrigido em 6830-DIRECT-REVIEW-FIX-01, item 2): este
--   INSERT é direto na tabela collection_pokedex_position_primary_
--   representative, bypassando a RPC — authenticated não tem GRANT de
--   INSERT nela (só SELECT). Rodar como table owner/role privilegiado,
--   dentro de transação com ROLLBACK, para que a exceção observada
--   venha do trigger trg_010, não de "permission denied for table" do
--   GRANT. Restaurar authenticated + request.jwt.claim.sub logo após.
--   -- Tentar (via INSERT direto, bypassando a RPC) um Primary cujo
--   -- collection_allocation_id pertence a uma Assignment de Position
--   -- diferente da declarada na própria linha:
--   INSERT INTO collection_pokedex_position_primary_representative
--     (collection_id, pokedex_position_id, collection_allocation_id)
--     VALUES (<collection_id>, PositionTEST_A, <allocation cuja Assignment é de PositionTEST_B>);
--   Esperado (asserção específica): RAISE EXCEPTION
--   PRIMARY_REPRESENTATIVE_ASSIGNMENT_MISMATCH
--   (trg_010_validate_primary_representative_integrity, Query 6121) —
--   não "permission denied" genérico.

-- Caso 18 — remover Assignment → Primary removido.
--   set_pokedex_position_primary_representative(<allocation X>);
--   remove_pokedex_position_assignment(<physical_card de X>);
--   SELECT count(*) FROM collection_pokedex_position_primary_representative
--     WHERE collection_allocation_id = <allocation X>;
--   Esperado: 0 linhas (CASCADE via Query 6120).

-- Caso 19 — mover Assignment → Primary antigo removido.
--   set_pokedex_position_primary_representative(<allocation Y>);
--   set_pokedex_position_assignment(<physical_card de Y>, <Position diferente>, true);
--   SELECT count(*) FROM collection_pokedex_position_primary_representative
--     WHERE collection_allocation_id = <allocation Y>;
--   Esperado: 0 linhas — o DELETE interno do move já disparou o
--   CASCADE (Revision-01, item 1); a nova Assignment (mesma Allocation,
--   Position nova) NÃO herda o Primary automaticamente.

-- Caso 20 — Collection ARCHIVED → writes bloqueadas.
--   archive_collection(collection_id);
--   set_pokedex_position_assignment(<qualquer physical_card>, <qualquer position>, true);
--   Esperado: RAISE EXCEPTION ..._COLLECTION_ARCHIVED. Repetir para
--   remove_pokedex_position_assignment, set_pokedex_position_primary_
--   representative e clear_pokedex_position_primary_representative —
--   as 4 RPCs devem bloquear igualmente.
--   reactivate_collection(collection_id); -- restaura para os próximos casos, se houver.

-- Caso 20b — concorrência lifecycle: write em andamento versus archive
-- concorrente (NOVO, PAUSE-SQL-DIRECT-AUDIT-01 item 3 — prova o lock
-- Collection-first de 6122 (via 6123) e 6124/6125 v1.1/v1.2). Requer duas sessões
-- simuladas na mesma transação de teste via savepoints/dblink, OU duas
-- conexões reais (mais fiel):
--   Sessão A: BEGIN; SELECT set_pokedex_position_assignment(<physical_card>, <position>, true)
--     -- interrompida ANTES do commit, com o lock de Collection (FOR
--     -- UPDATE) já adquirido dentro da própria função.
--   Sessão B (concorrente): archive_collection(collection_id);
--     -- deve BLOQUEAR (esperar o lock), não prosseguir imediatamente.
--   Sessão A: COMMIT.
--   Sessão B: agora libera e completa (ou falha, se a regra de negócio de
--     archive exigir 0 Assignments pendentes — verificar contrato de
--     archive_collection() existente).
--   Esperado: serialização real — nunca um estado em que a Assignment de
--   A tenha sido escrita DEPOIS que a Collection já está ARCHIVED sem
--   que B tenha esperado o lock de A. Se a ordem inverter (B primeiro),
--   A deve então falhar com COLLECTION_ARCHIVED ao tentar seu próprio
--   lock de Collection — nunca as duas escritas coexistindo de forma
--   não serializada.
--   REFORÇADO (6830-DIRECT-REVIEW-FIX-01, item 4): este caso exige
--   execução com duas conexões/sessões REAIS — é estruturalmente
--   impossível provar concorrência dentro de uma única transação
--   BEGIN/ROLLBACK, e uma leitura estática do código (confirmar que a
--   cláusula FOR UPDATE existe) NÃO é, por si só, prova funcional de
--   que a serialização realmente ocorre em runtime.
--   - SE o ambiente de execução sustentar duas conexões persistentes
--     simultâneas (ex.: dois clientes psql, ou duas sessões via MCP/
--     ferramenta que mantenha conexões abertas): executar o roteiro
--     acima com as sessões reais e registrar no relatório de
--     implementação, de forma explícita e verificável: (a) a ordem
--     temporal observada das duas chamadas; (b) se a Sessão B de fato
--     bloqueou aguardando o lock (evidenciável via pg_locks/pg_stat_
--     activity durante o teste, não só inferido); (c) o estado final
--     das linhas (Assignment e status da Collection) após ambas as
--     sessões concluírem, confirmando que corresponde exatamente ao
--     "Esperado" acima.
--   - SE o ambiente NÃO sustentar duas conexões persistentes reais
--     (ex.: ferramenta de execução que só permite uma call SQL síncrona
--     por vez, sem sessões long-lived): marcar este caso explicitamente
--     como "Caso 20b: NOT EXECUTED / UNPROVEN — ambiente sem suporte a
--     duas sessões persistentes simultâneas" no relatório de
--     implementação. NUNCA converter uma leitura estática do FOR UPDATE
--     em uma alegação de que a concorrência foi comprovada — a
--     existência do lock no código é necessária, mas não suficiente,
--     para provar o comportamento em runtime sob concorrência real.

-- Caso 21 — idempotência das RPCs aplicáveis.
--   set_pokedex_position_assignment(<physical_card>, <mesma Position já atribuída>, false);
--   Esperado: SUCESSO, no-op (mesma linha, mesmo assigned_at — nenhuma
--   escrita nova, ver Query 6122, "no-op idempotente").
--   set_pokedex_position_primary_representative(<mesma allocation já Primary>);
--   Esperado: SUCESSO, UPSERT idempotente (mesmo valor).
--   remove_pokedex_position_assignment/clear_..._primary_representative
--   NÃO são idempotentes por design (RAISE EXCEPTION ..._NOT_FOUND na
--   segunda chamada) — comportamento intencional, documentado aqui
--   como o contrato correto, não uma falha de idempotência.

-- Caso 21b — no-op real mesmo com evidência de Species drifted
-- (STAGING-AUDIT-01, item 3 — bug corrigido em 6122 v1.1).
--   Com Card_Match já Assignment em PositionTEST_A via SPECIES_MATCH
--   (Caso 1), forçar uma mudança na evidência de Species dessa Card
--   DEPOIS da Assignment já existir (ex.: um admin corrige card_
--   primary_species de Card_Match para apontar para uma Species que
--   NÃO é a de PositionTEST_A, via admin_resolve_card_primary_species,
--   Query 6114) — sem mover a Assignment.
--   set_pokedex_position_assignment(Card_Match.physical_card_id, PositionTEST_A, false);
--   -- MESMA Position já atribuída, mas agora a Species evidenciada
--   -- pela Card não corresponde mais a PositionTEST_A.
--   Esperado (v1.1, corrigido): SUCESSO, no-op — retorna a linha
--   existente sem exigir p_confirm_override. Antes da correção (v1.0),
--   esta chamada teria levantado erroneamente SET_POKEDEX_POSITION_
--   ASSIGNMENT_CONFIRMATION_REQUIRED, violando "mesma Position -> no-op
--   real". Restaurar a evidência original de Species ao final do caso,
--   se outros casos da trilha dependerem dela.

-- Caso 22 — grants/RLS/EXECUTE least privilege.
--   Já coberto integralmente pela Seção 1 (itens 1.6/1.7/1.8), SQL
--   ESTÁTICO, sem fixtures.

-- Caso 23 — nenhuma dependência de Scope na criação da Assignment.
--   Já coberto pelo Caso 7 (Scope GENERATION_FILTERED não impede a
--   criação) — reforço adicional: grep manual desta rodada (Query
--   6117/6118/6119/6122) confirma zero referência a scope_kind/
--   collection_pokedex_scope_generation em qualquer um dos 8 arquivos
--   desta Fatia D.

-- Caso 24 — zero impacto em completion nesta Fatia.
--   Nenhuma Query desta Fatia cria, altera ou lê nenhuma função de
--   completion existente (collection_completion_summary e
--   equivalentes de MASTER_SET, Queries 5070/5083) — confirmável por
--   grep estático: nenhum arquivo 6117-6125 referencia essas funções.
--   completion de REFERENCE_POSITION (LDM-181) permanece inteiramente
--   NOT STARTED, responsabilidade da futura Fatia E.

-- ================================================================
-- SEÇÃO 4 — PERFORMANCE
-- ================================================================
-- Proporcional ao volume/risco real desta Fatia (mesma nota de 6800):
-- nenhuma linha existe hoje em nenhuma das duas tabelas (RLS fechado,
-- nenhum sourcing/uso real ainda); a trigger de auto-assign (Query
-- 6119) processa no máximo 500 linhas por chamada (mesmo guard de
-- allocate_physical_cards_to_collection, 2C) com JOINs sobre colunas
-- já indexadas (PK/UNIQUE de card_primary_species, pokedex_position
-- UNIQUE (pokedex_id, species_id)) — sem necessidade de benchmark de
-- carga sintética nesta rodada.
