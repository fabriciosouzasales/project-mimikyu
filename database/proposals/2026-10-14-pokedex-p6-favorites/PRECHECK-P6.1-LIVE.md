# Precheck de readiness no LIVE — Pokédex P6.1

| Campo | Valor |
|---|---|
| Data | 2026-10-14 |
| Projeto | `qjfutqujxrbzgrtkpgkg` |
| Escopo | Somente `SELECT` de leitura (6 consultas). Nenhuma DDL/DML; 6136, 6137 e 6849 **não executadas**; nenhum usuário criado |
| Artefatos de referência | 6136 `0d351bc1…a64fbdd` · 6137 `9c5173b2…b2c4e` · 6849 v2.0 `368bcc8d…2c9f` |
| **Parecer** | **READY para uma futura autorização de execução controlada**, com duas decisões pendentes (§5) |

## 1. Resultados objetivos

| # | Condição | Evidência LIVE | Resultado |
|---|---|---|---|
| 1 | Versão e MAINTAIN | `server_version_num = 170006` (PostgreSQL 17.6); `has_table_privilege('authenticated','public.inventory','MAINTAIN')` executou sem erro (`false`) | **OK** — PG17; MAINTAIN reconhecido |
| 2 | Objetos ausentes | `to_regclass` da tabela e do índice = NULL; `to_regprocedure` das duas funções = NULL; 0 sobrecargas com os mesmos nomes; 0 constraints com os nomes de 6136; 0 policy com o nome de 6136; nenhum objeto `%favor%` em schemas de usuário | **OK** |
| 3 | Tabelas referenciadas | `auth.users.id` uuid com PK; `pokemon_species`: `id uuid NOT NULL` (PK `pokemon_species_pkey`), `national_dex_number integer NOT NULL` (UNIQUE `uq_pokemon_species_national_dex_number`), `is_active boolean NOT NULL`; 1.025 ativas / 0 inativas; nº 6 e 25 existem e estão ativos; 9999 não existe; `collection`, `collection_allocation`, `physical_card`, `inventory` existem | **OK** |
| 4 | Papéis e privilégios | Executor do canal = `postgres` (não superuser, `BYPASSRLS = true`); membro de `anon` e `authenticated` (pode `SET ROLE`); `TEMP` no banco = sim; `check_function_bodies = on`; `anon`/`authenticated` sem login e sem BYPASSRLS; `service_role` com BYPASSRLS | **OK** (ver nota N1) |
| 5 | Proprietários e padrões canônicos | `pokemon_species`, `inventory` e funções canônicas (`get_pokedex_national_species`, `get_pokedex_species_type_index`, `create_collection`) pertencem a `postgres`; funções canônicas: `SECURITY DEFINER`, `search_path=""`, EXECUTE só `authenticated`. Default ACL de `postgres` em `public`: tabelas `postgres=arwdDxtm`, `service_role=Dxtm`; funções `postgres=X`. ACL efetiva de `inventory`: `{postgres=arwdDxtm, service_role=Dxtm, authenticated=r}`. Policies de `inventory`/`collection`: `(owner_user_id = ( SELECT auth.uid() AS uid))` — formato que a regex da 1.2 reconhece | **OK** — 6136/6137 reproduzem exatamente esse padrão |
| 6 | Usuários de teste | 3 usuários; 3 elegíveis (não excluídos, não anônimos, não banidos, e-mail confirmado); 1 administrador, **2 não administradores**; todos com Inventory; nenhum com Collection; nenhum Physical Card no banco. UUIDs não expostos | **OK na quantidade** — adequação depende de decisão (§5, D-A) |
| 7 | Favorite de carta, Inventory, Collection | Favorite de carta sem estrutura física (nenhum objeto `%favor%`); FKs para `auth.users` já usam CASCADE em precedentes (`user_profile`, `admin_user`) e RESTRICT em patrimônio (`inventory`, `collection`); o 6849 só lê essas tabelas | **OK** — sem incompatibilidade |

### Notas

- **N1 — `postgres` tem BYPASSRLS.**
  - Leituras administrativas do 6849 (linha de base, 4.4, 6.x, 7.8, 8.3, 9.1, 10.1) veem todas as linhas, como pretendido.
  - Ao fazer `SET LOCAL ROLE authenticated`, o papel corrente perde o BYPASSRLS. As provas de RLS (4.x, 5.x, 8.1) continuam válidas.
  - As funções `SECURITY DEFINER` (dono `postgres`) contornam RLS por desenho, igual às canônicas.
- **N2 — `service_role` recebe `Dxtm`** (TRUNCATE, REFERENCES, TRIGGER, MAINTAIN) na nova tabela, pelo default ACL do projeto. É idêntico a `inventory`; não recebe SELECT/INSERT/UPDATE/DELETE. O 6849 não verifica `service_role` (L7). Mantido por coerência com o canônico.
- **N3 — event triggers do Supabase:**
  - `pgrst_ddl_watch` emite `NOTIFY pgrst` em DDL, **exceto** objetos em `pg_temp` (verificado no corpo da função). A criação da função temporária do 6849 não dispara recarga.
  - A 6136/6137 dispara uma recarga do cache do PostgREST no commit (esperado).
  - `issue_pg_*_access` só agem na criação das extensões correspondentes.
- **N4 — Realtime:** a publicação `supabase_realtime` não é `FOR ALL TABLES` e está vazia; a nova tabela não entra nela.

## 2. Validação × implantação — distinção explícita

| Etapa | O que acontece | Persistência | Como é revertido/verificado |
|---|---|---|---|
| A. Criação dos objetos (6136, 6137) | DDL: tabela, índice, RLS, policy, grants, 2 funções | **Permanente** (commit) | Não é revertido pelo 6849. Reversão só por script próprio de DROP (não existe ainda) |
| B. Escritas de teste (6849) | DELETE de limpeza, chamadas de favoritar/desfavoritar, INSERT de duplicidade, trocas de papel e claims | **Temporária** — dentro do savepoint | Revertidas pela exceção sentinela `P6R00` no mesmo statement |
| C. Rollback interno | Reversão do savepoint + 10.1 (contagens = linha de base) + 10.2 (papel e claims restaurados) | — | Se 10.1 falhar, o statement inteiro aborta |
| D. Verificação independente | POSTCHECK somente leitura em nova chamada | — | Contagens iguais à linha de base de 10.1 |

**Conclusão:** o 6849 v2.0 valida **objetos já criados**. Na forma atual, a validação depende da criação permanente (A antes de B).

## 3. Testar a criação e reverter antes da implantação definitiva

Não se propõe rollback entre chamadas (o canal não preserva a transação).

- **Opção A — dry-run em statement único (recomendada; exige artefato novo e autorização):**
  - Uma função `pg_temp` executa, dentro do mesmo savepoint do 6849, o DDL **interno** de 6136 e 6137 (sem `BEGIN/COMMIT`) e, em seguida, as 47 verificações.
  - Termina com a sentinela `P6R00`, que reverte também a DDL: o DDL do PostgreSQL é transacional.
  - O `NOTIFY` do `pgrst_ddl_watch` emitido dentro do savepoint abortado é descartado.
  - Uma prova pós-bloco confere que tabela e funções voltaram a não existir.
  - **Equivalência:** hash do trecho DDL embutido = hash do trecho entre `BEGIN;`/`COMMIT;` dos arquivos 6136/6137.
  - **Riscos:**
    - durante o statement, a criação das FKs segura locks em `auth.users` e `pokemon_species`, bloqueando escritas nelas (cadastro e atualização de login) por alguns segundos;
    - é um artefato novo, que precisa de auditoria própria;
    - **não comprovado por execução.**
- **Opção B — branch do Supabase:** isolamento total, mas com custo e sem os usuários de `auth.users` (o branch não copia Auth), o que exige criar usuários no branch.
- **Opção C — harness local PG17** (`C:\b12-pg17`), com `auth` de stub: não reproduz exatamente grants, default ACL e event triggers do Supabase.
- **Opção D — criar permanentemente e depois validar (dependência declarada):** se o GATE falhar, os objetos ficam no LIVE até um script de DROP auditado.
  - **Exposição:** usuários autenticados poderiam chamar as funções via PostgREST, afetando só os próprios dados.
  - **Impacto no usuário:** nenhum, porque não há frontend que use os objetos.
  - **Pré-requisito:** preparar e auditar o script de DROP **antes** da execução.

## 4. Auditoria final do mecanismo de rollback (inspeção do 6849 v2.0)

| Requisito | Verificação | Resultado |
|---|---|---|
| Escritas de teste dentro do bloco protegido | Todas as escritas (DELETE de limpeza, INSERTs, chamadas de `set_…`, DELETE pós-6.3) estão entre o `begin` interno e o `raise … P6R00`. Fora do bloco só há leituras (linha de base, 10.1, 10.2) e a saída | **OK** |
| Papel e identidade restaurados | `SET LOCAL ROLE` e `set_config(…, true)` ficam dentro do savepoint e são revertidos na exceção; há também `reset role` explícito em cada seção; 10.2 confere | **OK** |
| Exceção inesperada não gera PASS | `when others` → linha `X.1 = FAIL`. As verificações seguintes não são emitidas, então o GATE recusa (ids faltantes + FAIL) | **OK** |
| Nenhum efeito externo não transacional | Sem sequências (a tabela não tem serial), sem `dblink`, sem `NOTIFY` (`pg_temp` ignorado pelo `pgrst_ddl_watch`), sem `RAISE NOTICE`. `clock_timestamp()` é só leitura. Logs de servidor e estatísticas existem, mas não alteram dados | **OK** |
| Privilégios da função temporária | Exige `TEMP` (sim), associação a `anon`/`authenticated` (sim) e leitura de `auth.users` e catálogos (sim). A função não é `SECURITY DEFINER`, então `SET ROLE` é permitido | **OK** |
| Relatório não mascara ausências/duplicidades | O GATE compara a lista exata de 47 ids (contagem, distintos, sem extras, sem faltas), recusa FAIL e recusa NOT_PROVEN fora da 7.7 | **OK** |

**Sintaxe:** ainda não validada por parser nem por execução. Com `check_function_bodies = on` (confirmado), o `CREATE FUNCTION` do 6849 e da 6137 rejeita erro de sintaxe do corpo antes de qualquer teste. Erros semânticos (nomes, tipos) só aparecem na execução.

## 5. Protocolo seguro para a primeira execução (proposta — não executar sem autorização)

**Decisões pendentes:**
- **D-A — usuários de teste:** confirmar que os 2 usuários **não administradores** são contas de teste (ou suas próprias contas secundárias). As escritas do 6849 são todas revertidas, mas o projeto prefere contas dedicadas. Se não forem, criar duas contas de teste pelo Supabase Auth em rodada própria.
- **D-B — estratégia:** Opção A (dry-run revertido antes da implantação) **ou** Opção D (implantação seguida de validação, com script de DROP preparado antes).

**Sequência com a Opção A (recomendada):**
1. Autorizar e auditar o artefato `6849-DRY` (DDL embutido com hash igual ao de 6136/6137 + 47 verificações + prova de inexistência pós-reversão).
2. Executar o dry-run (1 chamada), depois um POSTCHECK confirmando que tabela e funções **não existem**.
3. GATE PASS → aplicar 6136 e depois 6137 (implantação definitiva).
4. Executar o 6849 v2.0 (CALL 1) e o POSTCHECK (CALL 2) contra os objetos definitivos.
5. Rodar o Security Advisor; só então promover para o schema canônico e atualizar a documentação.

**Sequência com a Opção D:**
1. Preparar e auditar o script de DROP.
2. Precheck: repetir o item 2 deste documento.
3. Aplicar 6136 e depois 6137.
4. Executar 6849 v2.0 (CALL 1) e o POSTCHECK (CALL 2).
5. Rodar o Security Advisor.
6. Se o GATE der FAIL: parar e decidir entre correção incremental ou DROP.

## 6. Riscos e incompatibilidades remanescentes

- **Sintaxe e semântica não comprovadas** até a primeira execução. Mitigação: Opção A (falha sem efeito permanente).
- **Locks de DDL** em `auth.users`/`pokemon_species` por alguns segundos durante a criação, tanto na Opção A quanto na D.
- **`service_role` com `Dxtm`** na nova tabela (N2), coerente com `inventory`.
- **Limitações de prova já registradas:** papel administrativo vs JWT real (L1), concorrência real (L2), exclusão de conta só estrutural (L3), 7.7 NOT_PROVEN (L4).
- **Nenhuma incompatibilidade encontrada** com Favorite de carta, Inventory ou Collection.

## 7. Parecer

**READY para uma futura autorização de execução controlada.** Todas as condições de entrada verificáveis por leitura estão satisfeitas.

Antes de executar, faltam duas decisões: **D-A** (adequação dos usuários de teste) e **D-B** (Opção A, dry-run revertido, ou Opção D, criação permanente seguida de validação com DROP preparado). Nada foi executado; nada foi criado.
