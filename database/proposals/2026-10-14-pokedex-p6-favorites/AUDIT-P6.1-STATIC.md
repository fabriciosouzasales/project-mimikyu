# Auditoria estática independente — Pokédex P6.1 (6136 / 6137 / 6849)

| Campo | Valor |
|---|---|
| Data | 2026-10-14 |
| Escopo | Leitura crítica dos três artefatos; nenhuma execução SQL (LIVE ou local), nenhuma DDL/DML, nenhum frontend |
| Artefatos (sha256) | `6136_create_pokedex_species_favorite_table.sql` `0d351bc1…a64fbdd` · `6137_create_pokedex_species_favorite_functions.sql` `9c5173b2…b2c4e` · `6849_validate_pokedex_species_favorite.sql` `e4c3fadb…bc51` |
| Precedentes comparados | `inventory` (5000), `create_collection` (5034), leituras da Pokédex (6131/6135), harness 5818 (protocolo de duas chamadas, `_as_user`/`_as_admin`, NOT PROVEN), 6830 (simulação de sessão) |
| **Parecer** | Auditoria inicial: **NOT READY** (2 BLOCKERs na 6849 v1.0). Após Correction-01 (6849 v2.0): **READY condicionado** para a primeira validação controlada — ver §7. |

## 1. Verificação sintática

- **Sintaxe ainda não validada por parser PostgreSQL.**
- Tentativas de obter um parser local sem conexão ao banco, ambas sem sucesso:
  - `libpg-query`, `pgsql-parser`, `@pgsql/parser` via npm: HTTP 403 da política do registro;
  - `pglast` via pip: pacote indisponível.
- O sandbox não tem binários do PostgreSQL. O harness `C:\b12-pg17` contém só scripts e evidências, sem binários executáveis no sandbox.
- **Inspeção visual (não é prova):** todas as construções usadas existem no PostgreSQL ≥ 15 e já aparecem em artefatos executados do projeto:
  - `returns table`, `on conflict on constraint`, `aclexplode`;
  - `to_regprocedure`, `unnest … with ordinality`, `jsonb_build_object` com `null`;
  - `set_config('role', …, true)` e `execute 'reset role'`, ambos usados no 5818.
- **Validação efetiva:** a primeira execução transacional autorizada.

## 2. Integridade

| # | Requisito | Implementação (arquivo:linha) | Prova (6849) | Resultado |
|---|---|---|---|---|
| I1 | Referências corretas a espécie e usuário | 6136:64-69 (`auth.users(id)`, `public.pokemon_species(id)`; ambos `uuid`, confirmado no diagnóstico P6) | 1.5 (só tabela referenciada e ação de exclusão) | **PASS** — prova parcial: GAP-6 |
| I2 | Tipos, chaves, constraints | 6136:58-70 (NOT NULL, PK nomeada, 2 FKs nomeadas, `ON UPDATE RESTRICT`) | 1.5, 1.6 | **PASS** |
| I3 | Unicidade usuário × espécie | 6136:62-63 (PK composta); 6137:121-123 (`ON CONFLICT ON CONSTRAINT`) | 1.6, 6.2, 6.5 | **PASS** |
| I4 | Exclusão em cascata compatível | 6136:64-66 (`ON DELETE CASCADE`). Sem conflito: hoje a exclusão de usuário já é barrada pelo `RESTRICT` de `inventory` (5000), então o CASCADE só atua quando existir fluxo de exclusão de conta | 1.5 (estrutural) | **GAP** — sem prova comportamental (L3 do README); aceitável, documentado |
| I5 | Idempotência | 6137:120-130 (define estado; INSERT ignora conflito; DELETE restrito ao dono) | 6.1–6.4 | **PASS** — 6.1/6.3 fracos: GAP-3 |
| I6 | Entradas inválidas | 6137:103-118 (estado nulo e número nulo/fora de 1..9999 → 22023; inexistente, ou inativa ao favoritar → P0002) | 7.1–7.6, 7.8 | **PASS**. 7.7 (inativa) e "desfavoritar inativa" não provados: GAP-7 |
| I7 | Padrões canônicos | Dono via `auth.uid()`, RLS de SELECT, `authenticated` só SELECT, escrita por RPC definer (= 5000/5034); funções = 6131/6135; `BEGIN/COMMIT` explícito = precedente 6000–6051 | — | **PASS** |
| I8 | Sem interferência em Favorite de Card, Inventory, Collection | 6136/6137 não referenciam essas tabelas; Favorite de Card não tem estrutura física | 9.1, 9.2 | **PASS** — 9.1 pode dar falso FAIL (nunca falso PASS) com atividade concorrente no LIVE |

## 3. Segurança

| # | Requisito | Implementação | Prova | Resultado |
|---|---|---|---|---|
| S1 | RLS e policy | 6136:78 (`enable row level security`); 6136:80-84 (SELECT, `to authenticated`, `user_id = (select auth.uid())`) | 1.1, 1.2 (estrutural); 4.3, 4.5 (comportamental, com linha do outro usuário presente) | **PASS** |
| S2 | Privilégios da tabela | 6136:86-89 (`revoke all` de PUBLIC/anon/authenticated + `grant select`). Cobre também os default privileges do Supabase e `MAINTAIN` do PG17 | 1.3 | **PASS** na implementação; prova incompleta: **GAP-4** (não checa REFERENCES/TRIGGER/MAINTAIN, nem TRUNCATE para `anon`) |
| S3 | Privilégios das funções | 6137:137-143 (`revoke all` de PUBLIC e anon; `grant execute` a authenticated) | 1.4 (inclui ausência de PUBLIC via `aclexplode`), 2.2, 2.3 | **PASS** |
| S4 | `SECURITY DEFINER` | 6137:59, 90 | 1.4 (`prosecdef`) | **PASS** — o dono das funções não é verificado; ele precisa ser o dono da tabela para o bypass de RLS ser o esperado: GAP-8 |
| S5 | `search_path` e resolução | 6137:61, 92 (`set search_path = ''`); todos os objetos qualificados (`public.*`, `auth.uid()`) | 1.4 (`proconfig @> {search_path=""}`) | **PASS** — comparação literal frágil (o 5818 normaliza aspas): GAP-5 |
| S6 | Identidade vinda da sessão | 6137:64, 95 (`auth.uid()`); nenhum parâmetro de usuário; DELETE restrito a `user_id = v_user` (6137:125-127) | 4.1–4.5, 5.2 | **PASS** |
| S7 | Acesso anônimo | Nenhum grant a anon (tabela e funções) | 2.1–2.3 (`42501`) | **PASS** |
| S8 | Leitura/escrita cruzadas | RLS + dono derivado da sessão | 4.3 (B não lê A), 4.4 (ação de B não remove o 25 de A), 4.5, 5.2 (INSERT em nome de outro → 42501) | **PASS** |
| S9 | Exposição por grants herdados | `revoke all` explícito; o teste `has_*_privilege('anon', …)` inclui PUBLIC | 1.3, 1.4 | **PASS**, com ressalva: `service_role` mantém os privilégios padrão e ignora RLS (chave de servidor; L7) |
| S10 | Admin × authenticated | Casos comportamentais rodam como `authenticated`/`anon` (`SET LOCAL ROLE` + claims); leituras de estado (4.4, 6.2, 6.4, 7.8, 8.3, 9.1) e a duplicidade 6.5 rodam como administrador | — | **GAP** inerente (L1): prova a autorização do **banco**, não a validação do JWT pelo PostgREST/Auth. As leituras administrativas são legítimas por serem verificação de estado, e nenhuma delas é usada como prova de permissão do usuário |

## 4. Validador 6849

### BLOCKER-1 — Protocolo de execução incompatível com o executor do projeto

- **Evidência:**
  - o arquivo termina com `rollback;` (6849:449) e tem **dois** `SELECT` de resultado (6849:435 e 6849:437-447);
  - o canal de execução do projeto devolve **só o resultado do último statement** e não preserva sessão entre chamadas (medido e registrado em 5818 §B / §14; mesma disciplina de 5808/5812).
- **Efeito:** executado como está, o relatório e o GATE **não aparecem**, porque o último statement é o `ROLLBACK`, que não devolve linhas. Mesmo sem o ROLLBACK, só o GATE voltaria, sem as linhas individuais.
- **Correção mínima proposta:**
  1. Juntar relatório e GATE num **único** `SELECT` final (linhas por verificação + uma linha `GATE`, via `union all` com `order by`).
  2. Dividir a execução em **CALL 1** (do `begin;` até esse `SELECT`, inclusive), **CALL 2** (`rollback;`, confirmação, no-op se a sessão já fechou) e **CALL 3** (POSTCHECK).
  3. Atualizar o cabeçalho da 6849 e o §5.3 do README com esse protocolo.

### BLOCKER-2 — PASS incondicional em 8.1

- **Evidência:** 6849:392 grava `'pass', true` sem condição nenhuma, só registra tempo.
- **Efeito:** é exatamente o "PASS vazio" que o projeto proíbe (lição E09 do 5818 §11). Infla a contagem de 38 e o GATE.
- **Correção mínima proposta:** depois do laço, ainda como A, contar as próprias linhas e exigir igualdade com o número de espécies ativas:
  - `execute 'select count(*) from public.pokedex_species_favorite' into n2;`
  - `pass := n2 = array_length(v_nums, 1)`.
  - O tempo continua no `detail`.

### GAPs (não bloqueiam a primeira execução, mas devem ser corrigidos junto)

| # | Problema | Correção mínima proposta |
|---|---|---|
| GAP-3 | 6.1/6.3 validam só o valor de retorno, que a função sempre devolve igual ao parâmetro (não discriminam). O estado é provado em 6.2/6.4 | Renomear como "retorno coerente" ou fundir a checagem de estado (6.2/6.4) na mesma linha |
| GAP-4 | 1.3 não cobre REFERENCES, TRIGGER, MAINTAIN para `authenticated`/`anon`, nem TRUNCATE para `anon` | Acrescentar esses `has_table_privilege` (mesmo padrão do 5000: `REVOKE TRUNCATE, REFERENCES, TRIGGER, MAINTAIN`) |
| GAP-5 | 1.4 compara `search_path=""` literalmente | Usar a normalização do 5818 (`btrim(…, '''" ') = ''`) |
| GAP-6 | 1.5 não amarra coluna → tabela nem checa `confupdtype` | Comparar `conkey` (`user_id` → `auth.users`, `pokemon_species_id` → `pokemon_species`) e `confupdtype = 'r'` |
| GAP-7 | Sem prova de "desfavoritar espécie inativa" e de leitura vazia (usuário sem favoritos devolve 0 linhas, sem erro) | Novo caso: `get_my_pokedex_favorites()` como A logo após a limpeza → 0 linhas. Inativa segue NOT PROVEN (L4) |
| GAP-8 | Dono das funções não verificado | Checar `proowner = relowner` da tabela |
| GAP-9 | 8.2 depende da ordem natural de saída da função (`row_number() over ()`) | Usar `from public.get_my_pokedex_favorites() with ordinality x(n, ord)` |
| GAP-10 | `ok` nulo (catálogo inesperado) aparece como NOT_APPLICABLE na linha (o GATE já reprova) | `coalesce(ok, false)` nas verificações que nunca podem ser NOT PROVEN |
| GAP-11 | Contagem fixa `count(*) = 38` no GATE | Recalcular depois das correções; manter "só 7.7 pode ser NOT PROVEN" |

### Demais pontos verificados (sem achado)

- **Usuários de teste:**
  - placeholders inválidos ou iguais → linha 0.2 e GATE FAIL (fail-closed);
  - a limpeza inicial (6849:114) só atinge A e B e é desfeita pelo rollback.
- **Tabela temporária:** criada e lida só pelo papel administrativo (gravada depois do `reset role`), então não depende de GRANT para `authenticated`; a falha 42501 do 5818 §A não se aplica.
- **Simulação de sessão:** `request.jwt.claims` com `sub`, como o `_as_user` do 5818, já validado no LIVE; a 6849 define também `request.jwt.claim.sub` (inócuo).
- **Independência dos casos:** cada seção redefine papel e claims; o estado entre seções é conhecido (A: 25 → removido → 1.025; B: 6).
- **Dependências implícitas:**
  - o papel executor precisa ler `auth.users` e as tabelas de Collection/Inventory (já lidas pelos harnesses 5804/5806/5818);
  - exige duas contas de teste criadas pelo Supabase Auth.

## 5. Ordem segura para a futura execução controlada (só com autorização)

1. Aplicar as correções do BLOCKER-1 e do BLOCKER-2 (e dos GAPs) na 6849 e passar por nova auditoria estática.
2. **Precheck** (somente leitura): `select to_regclass('public.pokedex_species_favorite'), to_regprocedure('public.get_my_pokedex_favorites()'), to_regprocedure('public.set_pokedex_species_favorite(integer, boolean)');` → todos nulos.
3. Executar a 6136 e, depois, a 6137. A primeira execução é também a validação de sintaxe; erro em qualquer uma = parar, sem prosseguir.
4. Preencher os dois UUIDs de teste na 6849. Executar a CALL 1, que devolve o relatório: GATE = PASS, 0 FAIL e só 7.7 NOT PROVEN.
5. Executar a CALL 2 (`rollback;`) e depois a CALL 3 (POSTCHECK): nenhuma linha dos usuários de teste e nenhuma tabela temporária.
6. Rodar o Security Advisor: nenhum achado novo para a tabela e as duas funções.
7. Só então: promoção para `database/schema/` e documentação.

## 6. Parecer

**NOT READY para a primeira validação transacional.**

- 6136 e 6137 não têm BLOCKER e implementam todos os requisitos de integridade e segurança; a sintaxe não foi validada por parser.
- O validador 6849 tem **dois BLOCKERs**: o protocolo de execução, que perderia a evidência, e um PASS incondicional.
- Com as correções da seção 4 aplicadas e revisadas, o conjunto fica pronto para a primeira execução controlada.
- Nenhuma correção foi aplicada nesta rodada.

## 7. Correction-01 — reauditoria estática (6849 v2.0)

| Campo | Valor |
|---|---|
| Arquivos alterados | `6849_validate_pokedex_species_favorite.sql` (v1.0 → v2.0), `README.md` (§5, §5.1, §5.2, §5.3, status), este documento |
| Preservados | 6136 `0d351bc163ee17f917ef7aac5efc0bb435fef96086a8fedebeac683e9a64fbdd`, 6137 `9c5173b24a0eca8feb9f11ae8412e77cd8c8ef358e8964c59e85d7e9aafc2b4e` (iguais aos de antes da Correction-01) |
| 6849 | v1.0 `e4c3fadb830c080a947e76bac5fb908d8562be925ee9512e586b23061d88bc51` → v2.0 `368bcc8d94e7c802e5ad405bf611d4448d231be32db53d2ac42707282d002c9f` |

### 7.1 Reconciliação do protocolo (condição crítica)

- **Contradição da proposta da §4:** ela afirmava que o canal não preserva sessão e, ao mesmo tempo, propunha `ROLLBACK` numa chamada separada. As duas coisas não se sustentam juntas: um `ROLLBACK` posterior não pode reverter uma conexão anterior. **Essa proposta foi descartada.**
- **Contrato documentado do canal** (5818 §B/§14, medido por sonda):
  - devolve só o resultado do **último** statement;
  - **não** preserva sessão nem transação entre chamadas;
  - transação aberta sem COMMIT termina em rollback implícito ao fim da chamada. A 6849 v2.0 **não depende** deste último ponto.
- **Estratégia adotada:** reversão **dentro do mesmo statement** que produz o relatório.
  1. `SELECT * FROM pg_temp.p6_6849_validate(A, B)` é um único statement e, portanto, uma única transação. Não existe commit entre as operações dele (requisito 3).
  2. Todas as escritas, trocas de papel (`SET LOCAL ROLE`) e claims ficam num bloco `BEGIN … EXCEPTION` (savepoint). O bloco termina **sempre** com a exceção sentinela `P6R00`, que reverte o savepoint (requisito 1). Os resultados ficam em variáveis PL/pgSQL, que não são transacionais e sobrevivem à reversão (requisito 2).
  3. A 10.1 prova a reversão dentro do próprio statement: contagens de A+B e total iguais à linha de base. A 10.2 prova papel e claims restaurados. Se a 10.1 falhar, a função aborta o statement inteiro (`P6_6849_ROLLBACK_NOT_CONFIRMED`): nada persiste.
  4. Erro inesperado no bloco é revertido e vira `X.1 = FAIL`. Erro fora do bloco aborta o statement (atômico). Erro de sintaxe do corpo é detectado pelo `CREATE FUNCTION` (`check_function_bodies`) antes de qualquer execução (requisito 5).
  5. A CALL 2 (POSTCHECK) roda em **nova chamada**, somente leitura, e compara com a linha de base informada na 10.1 (requisito 4, verificação independente).
  6. Único objeto fora do statement: a função `pg_temp`, local da sessão, sem dados, eliminada no fim da sessão.
- **Precedentes:** funções `pg_temp` com `SET LOCAL ROLE` + `request.jwt.claims` (5818 `_as_user`/`_as_admin`, executado no LIVE); simulação de sessão de 5802/5804/5806/6830.

### 7.2 Mapeamento BLOCKER/GAP → alteração → evidência esperada

| Achado | Alteração na v2.0 | Evidência esperada na execução |
|---|---|---|
| BLOCKER-1 | Função `pg_temp` + savepoint com sentinela `P6R00`; relatório num único `SELECT` final (último statement); POSTCHECK em nova chamada | Relatório de 48 linhas (47 + GATE) devolvido pela CALL 1; 10.1 = PASS; POSTCHECK igual à linha de base |
| BLOCKER-2 | 8.1 = PASS só se linhas visíveis a A (via RLS) = nº de espécies ativas (> 0) | `detail` com as duas contagens iguais |
| GAP-3 | 6.1/6.2 exigem retorno E linhas persistidas (1 e 0); PK dup vira 6.3 | 6.1 "1 linha", 6.2 "0 linhas" |
| GAP-4 | 1.3a (authenticated: só SELECT; 7 privilégios negados, incl. TRUNCATE/REFERENCES/TRIGGER/MAINTAIN), 1.3b (anon: os 8 negados), 1.3c (PUBLIC ausente da ACL) | Três PASS |
| GAP-5 | 1.4a/1.4b: `search_path` normalizado (remoção de aspas simples/duplas e espaços, padrão 5818) | PASS para as duas funções |
| GAP-6 | 1.5a/1.5b: `conkey`/`confkey` por nome de coluna, `confdeltype` e `confupdtype`, total de FKs = 2 | PASS |
| GAP-7 | 4.0: `get_my_pokedex_favorites()` como A sem favoritos → 0 linhas, sem erro | "0 linhas" |
| GAP-8 | 1.4c: `proowner` = `relowner` da tabela, não `anon`/`authenticated`, `relforcerowsecurity = false` | PASS + nome do proprietário no `detail` |
| GAP-9 | 4.1/4.2/8.2 usam `WITH ORDINALITY` | 8.2 com lista igual às espécies ativas |
| GAP-10 | Três estados (`PASS`/`FAIL`/`NOT_PROVEN`); nulo em verificação obrigatória → `FAIL`; só 7.7 aceita `NOT_PROVEN` | GATE recusa qualquer outro `NOT_PROVEN` |
| GAP-11 | GATE compara a **lista exata** de 47 ids (sem faltas, extras ou duplicadas) | "esperadas=47; recebidas=47" |

Reforço extra, sem enfraquecer nada: a 1.2 agora confere também a expressão da policy (`user_id = (select auth.uid())`), além de permissiva e sem `WITH CHECK`; a 1.7 confere a coluna do índice; a 3.x foi separada em 3.1 (leitura) e 3.2 (escrita).

### 7.3 Contagem

- **47 verificações** + 1 linha GATE: 0.x (2), 1.x (12), 2.x (3), 3.x (2), 4.x (6), 5.x (4), 6.x (3), 7.x (8), 8.x (3), 9.x (2), 10.x (2).
- `X.1` só aparece se houver erro inesperado; nesse caso o GATE é FAIL.

### 7.4 Inspeções estáticas executadas (sem banco)

- Ids emitidos × lista esperada: 47/47, nenhum faltante. Extras só `X.1` (intencional). Os "duplicados" 7.7 e 10.1 estão em ramos mutuamente exclusivos.
- Delimitadores `$fn$` pareados (2).
- Parênteses balanceados fora de comentários e literais (268/268).
- Blocos `BEGIN/END`, `IF/END IF`, `LOOP/END LOOP` e `CASE … END` consistentes: 76 `END` = 20 blocos + 7 IF + 1 LOOP + 48 CASE.
- `#variable_conflict use_column` declarado. As colunas de saída (`seq`, `check_id`, `item`, `status`, `detail`) não colidem com as colunas dos catálogos usados. As referências ambíguas (`x.n`) estão qualificadas.
- 6136/6137: hashes inalterados.
- **Sintaxe PostgreSQL ainda não validada por parser.** Os parsers locais seguem indisponíveis (npm 403; pip sem pacote) e o sandbox não tem PostgreSQL.

### 7.5 Limitações ainda não comprovadas

- **Sintaxe:** não validada por parser. Na primeira execução, o `CREATE FUNCTION` valida o corpo antes de rodar qualquer teste.
- **Comportamento do canal:** a captura do último statement e a ausência de sessão vêm dos registros de 5818. A v2.0 depende só da captura do último statement, que é o mesmo fato em que o 5818 se apoiou.
- **L1:** papel administrativo com `SET LOCAL ROLE` prova o banco, não o JWT do PostgREST.
- **L2:** sem concorrência real entre conexões.
- **L3:** exclusão de conta só estrutural.
- **L4:** 7.7 NOT_PROVEN enquanto não houver espécie inativa.
- **L5:** exige dois usuários de teste do Supabase Auth.
- **MAINTAIN:** exige PostgreSQL 17, mesmo requisito da 5000 já executada. Em versão anterior, a 1.3a/1.3b viraria FAIL (erro de privilégio desconhecido), nunca falso PASS.
- **Ruído no LIVE (9.1):** atividade concorrente pode causar falso FAIL, nunca falso PASS.

### 7.6 Parecer

**READY (condicionado) para uma futura validação controlada**, nos termos de §5.3 do README: precheck → 6136 → 6137 → CALL 1 → CALL 2 → Advisor.

- Condição: a primeira execução é também a primeira validação de sintaxe. Qualquer erro de compilação ou FAIL no GATE significa parar, sem promoção.
- Nenhum SQL foi executado; nada foi promovido.
