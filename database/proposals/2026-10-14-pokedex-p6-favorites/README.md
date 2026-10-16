# Pokédex P6 — Favoritos (conceito, persistência proposta e plano)

| Campo | Valor |
|---|---|
| Data | 2026-10-14 |
| Frente | A — Produto e funcionalidades (`docs/adr/ADR-011-pokemon-tcg-domain-scope.md`; sequência em `docs/ROADMAP.md` 2.26) |
| Status | **P6.0 concluída** (conceito registrado em ADR-011 v1.6 e `ubiquitous-language.md` 1.26). **P6.1: artefatos 6136/6137 e 6849 v2.0 (Correction-01) — PROPOSTOS, NÃO EXECUTADOS**; reauditoria estática em `AUDIT-P6.1-STATIC.md` §7. **Ensaio reversível 6850 preparado (PROPOSTO, NÃO EXECUTADO)**; auditoria em `AUDIT-P6.1-DRYRUN.md`; gate final (§10): READY; **execução controlada em 2026-10-14: GATE FAIL por falso negativo na 6849/1.7, reversão confirmada (§5.5); Correction-02 (6849 v2.1, 6850 regenerado, §5.6); reexecução: GATE 6849 e GATE-ENSAIO PASS, zero resíduo (§5.7) ; **P6.2: 6136/6137 IMPLANTADOS no LIVE e validados (6849 GATE PASS), §5.8**; **P6.3: promovidos para `database/migrations/` (2026-10-15)**; **P6.4–P6.6: frontend implementado localmente, aguardando homologação de Fabrício antes do commit (§5.9)**. |
| Base | Commit `449c079` (P5a publicada); leitura LIVE somente de metadados em 2026-10-14 |

## 1. Inventário (diagnóstico)

| Capacidade | Estado | Evidência |
|---|---|---|
| Favoritos de espécie | **Ausente** — nenhuma tabela, função ou componente | LIVE: nenhuma tabela `%favor%`; código sem ocorrência |
| `Favorite` (Card) | Conceito aprovado, **outro conceito** (C-82–C-90, LDM-70–LDM-78), sem estrutura física — **inalterado** | `concept-decisions.md`, `logical-model.md` |
| Listas/preferências reutilizáveis | Ausentes (só `user_profile` e `inventory`) | LIVE |
| Autenticação | Pokédex inteira exige sessão (`/login`); funções da Pokédex exigem `auth.uid()` e não existem para `anon` | `app/pokedex/page.tsx`, 6131–6135 |
| Dados por usuário | Dono com FK para `auth.users`; RLS `= (select auth.uid())`; `authenticated` só `SELECT`; escrita só por RPC `SECURITY DEFINER` com dono resolvido no servidor | `inventory` (5000), `create_collection` (5034) |
| Escrita no frontend | Server Actions com o cliente da sessão | `app/catalogo/**/actions.ts` |
| Feedback | Inline, sem toast (STD-004) | `components/ui/feedback.tsx` |
| Galeria/filtros/URL | Galeria server-rendered de 1.025 cards (card = um `<Link>`); pesquisa (6131), geração (régua + barra P4c), tipos (P5a); contexto único `pokedexContextSearch` | P1–P5a |
| Menu secundário | `nav-config.ts`: EXPLORAR hoje só tem **Pokédex Nacional**; regra do projeto: item entra no menu no mesmo incremento em que a página funciona | `components/app-shell/nav-config.ts` |

## 2. Conceito registrado (P6.0)

**Espécie favorita** (*Favorite Species*) — ADR-011 v1.6; `ubiquitous-language.md` 1.26:

- Preferência pessoal de um User por uma Pokémon Species. Binária, privada, no máximo uma por par User × espécie.
- Independente de posse de cartas, de Inventory, de Collection, de completion, de Pokédex Position e de Wishlist.
- Distinta do **Favorite de Card** (preferência por uma carta específica — inalterado) e da **carta possuída** (item do acervo).
- Símbolo oficial: **coração vermelho**.

## 3. Decisões aprovadas e revisadas

| # | Decisão | Estado |
|---|---|---|
| D1 | Conceito "Espécie favorita", distinto do Favorite de Card | Aprovada — registrada (P6.0) |
| D2 | Persistência própria (tabela + RPCs) | Aprovada — artefatos 6136/6137 |
| D3 | `ON DELETE CASCADE` em `auth.users` | Aprovada — ver L3 |
| D4 | Desfavoritar sem saltos de layout (card atenuado até a próxima navegação) | Aprovada — aplica-se à página Pokémons Favoritos |
| D5 | ~~`?favoritos=1` na galeria~~ | **Substituída** pela página própria `/pokedex/favoritos` (D8) |
| D6 | **Revisada: coração vermelho** (antes estrela) — contorno discreto quando não favorita; preenchido em vermelho quando favorita; no desktop, o contorno aparece em hover/foco; no mobile, sempre visível com área de toque adequada; na ficha, coração + texto da ação | Aprovada |
| D7 | Contagens totais de régua/barra/capítulo inalteradas | Aprovada |
| D8 | **Nova: página própria "Pokémons Favoritos"** em `/pokedex/favoritos`, no menu secundário, seção EXPLORAR, logo após Pokédex Nacional. A pílula "Favoritos · N" junto ao filtro Tipo deixa de existir (sem navegação redundante) | Aprovada |

## 4. Futura experiência (documentada, não implementada)

**Coração**
- **Card da galeria:** botão-coração no canto superior direito da prancha, **irmão** do link do card (botão dentro de link é HTML inválido); fica na ordem de foco logo após o link.
  - Não favorito: contorno neutro (`muted-foreground`), no desktop só em hover/foco do card; no mobile sempre visível, mais discreto.
  - Favorito: preenchido em vermelho, sempre visível.
  - Área de toque ≥ 44 × 44 px; a parte visual continua pequena e não compete com a arte.
- **Vermelho:** um token novo do Design System (ex.: `--favorite`). O vermelho semântico de erro (`--destructive`) não é reaproveitado, para não comunicar erro. Contraste ≥ 3:1 (componente gráfico, WCAG 1.4.11) contra a prancha nos temas claro e escuro, a confirmar na homologação.
- **Ficha:** botão com coração + texto ("Favoritar" / "Favorito"), junto às flags da identidade.
- **Acessibilidade:**
  - `<button aria-pressed>` com nome acessível ("Favoritar Pikachu" / "Remover Pikachu dos favoritos") e foco visível no padrão do Design System.
  - Uma região `aria-live` única anuncia o resultado ("Pikachu adicionado aos favoritos").
  - A animação do coração é só transform/opacity, desligada em `prefers-reduced-motion`.
- **Linguagem:** "favorito", nunca "tenho", "minha coleção" ou contagem de cartas.

**Página Pokémons Favoritos (`/pokedex/favoritos`)**
- **Mesma galeria e mesmos filtros**, sem componentes nem contratos duplicados: `SpeciesGrid`, régua de gerações, filtro por tipo (P5a), pesquisa.
  - O recorte é a interseção da lista de 6131 com o conjunto de `get_my_pokedex_favorites()`, aplicado no servidor na mesma passagem da P5a.
  - Os links da página preservam a rota base: régua, tipos e pesquisa ficam dentro de `/pokedex/favoritos`.
- **Cabeçalho próprio:** "Pokémons Favoritos" e a contagem de favoritos. Linguagem de preferência, sem progresso nem completude, para não sugerir posse.
- **Desfavoritar direto:** o card fica atenuado com o coração vazio até a próxima navegação (D4), e favoritar de novo desfaz.
- **Estados:**
  - **Vazio sem favoritos:** explica o gesto e oferece "Explorar a Pokédex Nacional".
  - **Vazio com filtros:** "Nenhum favorito do tipo Gelo em Geração III", com saídas para remover cada filtro.
  - **Erro de leitura:** aviso específico com "Tentar novamente", nunca uma lista vazia enganosa.
- **Ficha aberta a partir da página:**
  - o contexto ganha a origem `favoritos`;
  - o "voltar" retorna a `/pokedex/favoritos`;
  - anterior/próximo seguem a regra nacional/de geração (P4a), sem restrição a favoritos — mesma lógica da P5a.

**Comportamento comum**
- **Otimista seguro:** muda na hora; por espécie vale sempre a **última intenção**, enviada com `set(número, desejado)` (idempotente). Respostas fora de ordem não invertem o estado.
- **Falha:** estado revertido e mensagem inline (STD-004).
- **Favoritos indisponíveis:** os corações ficam desabilitados com aviso discreto e a galeria continua funcionando.
- **Sem sessão:** a Pokédex já redireciona para `/login`.

## 5. Persistência e segurança (P6.1 — artefatos para auditoria)

| Arquivo | Conteúdo |
|---|---|
| `6136_create_pokedex_species_favorite_table.sql` | Tabela `pokedex_species_favorite (user_id, pokemon_species_id, created_at)`. PK composta (unicidade User × espécie). FK `auth.users` CASCADE e FK `pokemon_species` RESTRICT. Índice da FK de espécie. RLS com uma policy de SELECT das próprias linhas. `authenticated` = SELECT; `anon`/PUBLIC = nada |
| `6137_create_pokedex_species_favorite_functions.sql` | `get_my_pokedex_favorites()`: números nacionais do usuário da sessão, ordenados. `set_pokedex_species_favorite(número, estado)`: define o estado, idempotente, devolve o estado final. Ambas `SECURITY DEFINER`, `search_path=''`, `auth.uid()` obrigatório (28000), entradas validadas (22023/P0002), EXECUTE só para `authenticated` |
| `6849_validate_pokedex_species_favorite.sql` | v2.0 (Correction-01): função `pg_temp` executada num único statement; reversão interna por savepoint + exceção sentinela; 47 verificações (PASS/FAIL/NOT_PROVEN) + GATE por lista exata de ids + POSTCHECK independente |

### 5.1 Matriz da auditoria (itens pedidos → verificações da 6849)

| # | Item | Verificações |
|---|---|---|
| 1 | Acesso anônimo bloqueado | 2.1 tabela, 2.2/2.3 funções → `42501` |
| 2 | Isolamento entre dois usuários | 4.0 (leitura vazia), 4.1, 4.2 (cada um vê só os seus) |
| 3 | Leitura e escrita cruzadas impossíveis | 4.3 (SELECT de A por B = 0), 4.4 (B "desfavorita" o 25 de A sem efeito), 4.5 |
| 4 | Escrita direta negada | 5.1 INSERT próprio, 5.2 INSERT em nome de outro, 5.3 UPDATE, 5.4 DELETE → `42501` |
| 5 | Sem duplicidade | 1.6 PK, 6.1 (1 linha persistida após repetição), 6.3 INSERT duplicado → `23505` |
| 6 | Idempotência | 6.1 (true×2: retornos + 1 linha persistida), 6.2 (false×2: retornos + 0 linhas) |
| 7 | Entradas inválidas | 7.1–7.6 (0, negativo, 10000, nulos, inexistente), 7.7 (inativa, se houver), 7.8 (nenhuma linha criada) |
| 8 | Exclusão de conta e integridade | 1.5a (FK `user_id`→`auth.users(id)` CASCADE/RESTRICT), 1.5b (FK espécie RESTRICT/RESTRICT; total 2) — ver L3 |
| 9 | 1.025 favoritos | 8.1 (linhas visíveis a A = espécies ativas), 8.2 (leitura completa na ordem, WITH ORDINALITY), 8.3 (isolamento sob volume) |
| 10 | Privilégios mínimos | 1.1 RLS; 1.2 policy única (expressão conferida); 1.3a/b/c tabela (8 privilégios × authenticated/anon + PUBLIC); 1.4a/b funções (definer, search_path normalizado, EXECUTE); 1.4c proprietário; 1.7 índice; 3.1/3.2 sem identidade → `28000` |
| 11 | Sem efeito em Favorite de Card e Collection | 9.1 (collection, collection_allocation, physical_card, inventory inalterados), 9.2 (funções não referenciam Collection/Inventory/Card/Wishlist) |
| 12 | Rollback completo | 10.1 (reversão provada no próprio statement), 10.2 (papel e claims restaurados), POSTCHECK independente em nova chamada |

### 5.2 Limitações das provas

- **L1 — papel administrativo:** a 6849 é executada por um papel administrativo que simula sessões com `SET LOCAL ROLE` e `request.jwt.claim(s)`. Prova a autorização do **banco** (RLS, grants, funções), não a validação do JWT pelo Supabase Auth/PostgREST. Complemento sugerido na homologação do frontend: dois usuários reais pela API, com a mesma matriz.
- **L2 — concorrência:** duas conexões simultâneas não cabem numa transação única. A segurança vem da PK, do `INSERT … ON CONFLICT DO NOTHING`, do `DELETE` restrito ao dono e da semântica "definir estado". Prova com duas conexões é opcional, no harness local PG17 (`C:\b12-pg17`).
- **L3 — exclusão de conta:**
  - **Por que só estrutural:** apagar usuário real no LIVE não é feito. Hoje a exclusão de um usuário já é bloqueada pelo `RESTRICT` de `inventory.owner_user_id` (5000); o CASCADE dos favoritos só age quando o projeto tiver fluxo de exclusão de conta.
  - **Prova comportamental opcional:** harness local, com `auth.users` de stub.
- **L4 — espécie inativa:** hoje todas as 1.025 estão ativas. O caso 7.7 sai `NOT_PROVEN` (único permitido pelo GATE) e a regra fica coberta só por leitura do código da 6137.
- **L5 — fixtures:** a 6849 exige **dois usuários de teste existentes** em `auth.users`, criados pelo Supabase Auth; o projeto não insere em `auth.users` por SQL. Antes de executar, os UUIDs precisam ser preenchidos no `SELECT` da CALL 1 e no POSTCHECK.
- **L6 — sintaxe:** nenhum dos três arquivos foi executado nem analisado por um parser PostgreSQL nesta rodada (não há Postgres no sandbox do agente, e o LIVE está fora de escopo). A auditoria deve incluir leitura completa; a primeira execução valida sintaxe.
- **L7 — `service_role`:** mantém os privilégios padrão do Supabase e ignora RLS por definição. É chave exclusiva de servidor, nunca usada no cliente (regra do projeto).

### 5.3 Protocolo de execução (quando autorizado — por Fabrício)

Canal de execução (fatos medidos em 5818 §B): devolve só o resultado do último statement e não preserva sessão/transação entre chamadas. Por isso a reversão **não** depende de um `ROLLBACK` numa chamada posterior — ela ocorre dentro do mesmo statement que gera o relatório (ver cabeçalho da 6849 v2.0).

1. **Precheck** (somente leitura): tabela e as duas funções ausentes (`to_regclass`/`to_regprocedure` nulos).
2. Executar a 6136; depois a 6137. Erro em qualquer uma = parar.
3. **CALL 1** — 6849 inteira (cria `pg_temp.p6_6849_validate` e executa o `SELECT`), com os dois UUIDs preenchidos. Conferir `GATE = PASS`: 47 linhas esperadas, 0 FAIL, só 7.7 pode ser `NOT_PROVEN`, 10.1 e 10.2 = PASS.
4. **CALL 2** — POSTCHECK somente leitura em nova chamada: contagens iguais à linha de base de 10.1.
5. Rodar o Security Advisor: nenhum achado novo para a tabela e as funções.
6. Promover para `database/schema/` + documentação, em etapa própria.

### 5.4 Ensaio transacional reversível 6850 (D-B = Opção A)

Antes de qualquer aplicação permanente, a decisão D-B prevê um ensaio que executa 6136, 6137 e o validador 6849 v2.0 e **reverte tudo no mesmo statement**: um savepoint com sentinela `P6D00`, sem `COMMIT` e sem `ROLLBACK` em outra chamada. **PROPOSTO, NÃO EXECUTADO.**

- **Artefato:** `6850_dryrun_pokedex_species_favorite.sql`, gerado por `generate_6850.py` a partir de `6850.template.sql`. Não editar à mão.
- **Prova de identidade:** `verify_6850_identity.py`, offline, com resultado 28/28 PASS e 13/13 mutações detectadas. Em execução, D.0.1–D.0.3 recalculam os hashes.
- **Auditoria:** `AUDIT-P6.1-DRYRUN.md`, com os caminhos de execução, a segunda revisão crítica, a separação entre o que está provado por inspeção e o que depende da primeira execução, e a ressalva R1 (funções `pg_temp` de sessão).
- **Usuários (D-A revisada):** nenhuma conta é criada. Usam-se duas contas existentes não administrativas, escolhidas por Fabrício na execução. Os UUIDs são informados só na cópia enviada ao banco, nunca no arquivo (procedimento em `AUDIT-P6.1-DRYRUN.md` §10.5). Com os placeholders, D.0.6 reprova e nada é escrito.
- **Protocolo:** CALL 1 é o arquivo inteiro e espera GATE-ENSAIO = PASS. CALL 2 é o postcheck somente leitura comentado no fim do arquivo e espera ausência total, `funcoes_temporarias_residuais = 0` e `transacoes_pendentes = 0`.
- **Parecer (gate final, §10):** READY. R1 aceitável, contrato de falha PASS. O comentário do postcheck foi corrigido para não afirmar o que uma consulta em outra conexão não prova. A próxima operação, que depende de autorização, é a CALL 1 seguida da CALL 2.

### 5.5 Execução controlada do 6850 no LIVE (2026-10-14) — GATE FAIL, reversão confirmada

Execução autorizada só do ensaio e do postcheck. Os UUIDs das contas foram informados apenas na cópia temporária enviada ao banco; o arquivo versionado mantém os placeholders (sha256 `29abf837…0cb3`, inalterado).

- **Preflight (somente leitura):** 6136/6137/6849 com os hashes de sempre; verificador 28/28; objetos ausentes; nenhuma sessão *idle in transaction*, nenhuma outra sessão ativa e nenhum lock conflitante em `auth.users`/`pokemon_species`. As duas contas não administrativas existentes foram usadas com a confirmação de Fabrício.
- **CALL 1:** terminou sem erro inesperado.
  - D.0.1–D.0.6 PASS (hashes, ausência, `lock_timeout=5s`, `statement_timeout=2min`, 2 de 2 contas). D.1.1/D.1.2 PASS: o DDL de 6136/6137 executou sem erro.
  - 6849: 47 de 47 verificações presentes, **45 PASS, 1 FAIL (1.7), 1 NOT_PROVEN (7.7, aceito)**, GATE 6849 = FAIL. Portanto D.2.1 FAIL e **GATE-ENSAIO = FAIL**.
  - Reversão: 10.1 (A+B 0→0, total 0→0), 10.2, D.3.1 e D.3.2 PASS.
- **CALL 2 (outra conexão, somente leitura):** todos os objetos ausentes, `funcoes_temporarias_residuais = 0`, `transacoes_pendentes = 0`, nenhuma sessão *idle in transaction*, 2 contas intactas, 1025 espécies ativas, Collection/Inventory/Physical Card nas mesmas contagens.
- **Causa do FAIL em 1.7 (falso negativo do validador, comprovado por leitura no LIVE):** `pg_index.indkey` é um `int2vector` com limite inferior 0. `indkey::int2[]` produz `'[0:0]={n}'`, e a igualdade de arrays do PostgreSQL também compara os limites, então ela nunca é verdadeira contra `array[n]` (limite 1). Em índices existentes de `pokemon_species`, a mesma igualdade dá `false` com conteúdo idêntico. O índice criado por 6136 não foi refutado, mas também não ficou comprovado por esta execução.
- **Correção mínima proposta, ainda não aplicada (exige autorização, pois altera o 6849):** na 1.7, trocar `i.indkey::int2[] = array[...]` por `i.indnatts = 1 and i.indkey[0] = (select a.attnum …)`. Depois, regenerar o 6850, reverificar e repetir CALL 1 e CALL 2.
- **Parecer:** NOT READY para implantação definitiva. Bloqueia a falha do validador; não há defeito identificado em 6136/6137.

### 5.6 Correction-02 — 6849 v2.1 (verificação 1.7) e 6850 regenerado (2026-10-14)

Não houve execução no LIVE nesta etapa.

- **6849 v2.0 → v2.1.** Só uma condição da 1.7 mudou: `i.indkey::int2[] = array[attnum]` passou a ser `i.indnatts = 1 and i.indkey[0] = attnum`. Continuam exigidos a mesma tabela (`indrelid`), o mesmo índice nomeado (`indexrelid`) e a contagem exata `n = 1`. O cabeçalho registra a mudança.
  - A semântica de `indkey[0]` já foi comprovada por leitura no LIVE (§5.5): devolve o `attnum` da coluna única do índice.
- **Escopo da mudança.** No corpo da função, o diff tem 3 linhas, todas na 1.7. Continuam iguais as 47 ids esperadas, o GATE e a regra de `NOT_PROVEN` restrita à 7.7.
- **6850 regenerado** por `generate_6850.py` (a regeneração é reprodutível). As únicas mudanças funcionais no ensaio são a linha da 1.7 e a constante `c_hash_6849`. O resto é cabeçalho e rótulos "v2.1".
  - `lock_timeout = 5s` e `statement_timeout = 120s` continuam iguais, assim como a reversão interna e a CALL 2.
- **Verificações.**
  - `verify_6850_identity.py`: 28/28 PASS.
  - 17/17 mutações detectadas, incluindo a 1.7 revertida ao bug, a 1.7 com PASS incondicional e a 1.7 sem `indnatts`.
  - 6136 e 6137 estão byte a byte inalterados.
- **Hashes.**

  | Arquivo | Antes | Depois |
  |---|---|---|
  | 6849 | `368bcc8d…2c9f` | `ae02d68f…f8a7` |
  | prosrc | `5944311b…f027a` | `4bd0860f…12b44` |
  | 6850 | `29abf837…0cb3` | `55b6d5a6…7cba` |

- **Parecer:** READY para repetir o dry-run 6850 de forma controlada, mediante nova autorização expressa.

### 5.7 Reexecução controlada do 6850 após a Correction-02 (2026-10-14) — PASS

Foram autorizados somente o ensaio reversível e o postcheck. Os UUIDs das mesmas duas contas não administrativas foram informados apenas na cópia temporária, que depois foi descartada. Os arquivos versionados não mudaram.

- **Preflight:**
  - hashes conferidos: 6136 `0d351bc1…`, 6137 `9c5173b2…`, 6849 v2.1 `ae02d68f…`, 6850 `55b6d5a6…`;
  - verificador 28/28;
  - objetos ausentes no LIVE;
  - nenhuma sessão *idle in transaction*, nenhuma outra sessão ativa, nenhum lock conflitante;
  - as duas contas são não administrativas e existem.
- **CALL 1:** terminou sem erro inesperado.
  - D.0.1–D.0.6 PASS (`lock_timeout=5s`, `statement_timeout=2min`) e D.1.1/D.1.2 PASS.
  - 6849: 47 de 47 verificações presentes; **46 PASS, 0 FAIL, 1 NOT_PROVEN** (7.7: não há espécie inativa); **1.7 PASS**; **GATE 6849 = PASS**.
  - D.2.1, D.3.1 e D.3.2 PASS; **GATE-ENSAIO = PASS** (11/11).
  - Capacidade: 1025 favoritos gravados em 102,6 ms e lidos em 2,3 ms.
- **Reversão:**
  - 10.1 (A+B 0→0, total 0→0), 10.2 e D.3.1 confirmaram a ausência dentro do próprio comando.
  - **CALL 2** (outra conexão, somente leitura): todos os objetos ausentes, `funcoes_temporarias_residuais = 0`, `transacoes_pendentes = 0`, nenhuma sessão *idle in transaction*.
  - Contas intactas: o `updated_at` máximo não mudou.
  - Entidades sem alteração: 1025 espécies ativas, Collection 0, Allocation 0, Inventory 3, Physical Card 0.
  - Limitação já registrada: a CALL 2 não prova que a sessão da CALL 1 se encerrou.
- **Parecer:** READY para a implantação definitiva de 6136/6137, que depende de autorização separada. A 7.7 continua NOT_PROVEN por falta de espécie inativa; a regra é coberta só pela leitura do código (L4).

### 5.8 P6.2 — Implantação definitiva de 6136/6137 no LIVE (2026-10-14) — CONFIRMADO EXECUTADO

Foram autorizadas apenas a implantação de 6136/6137 e sua validação. Não houve promoção canônica, frontend, DROP nem rollback.

- **Preflight.**
  - Hashes conferidos: 6136 `0d351bc1…`, 6137 `9c5173b2…`, 6849 v2.1 `ae02d68f…` (os mesmos ensaiados pelo 6850 `55b6d5a6…`; verificador 28/28).
  - PostgreSQL 17.6.
  - Objetos ausentes antes da implantação.
  - Dependências presentes: `pokemon_species` (`id`, `national_dex_number`, `is_active`), `auth.uid()`, papéis `anon`, `authenticated` e `service_role`.
  - Nenhum lock conflitante ou em espera, nenhuma sessão *idle in transaction*, nenhuma outra sessão ativa.
  - As duas contas não administrativas existem.
  - Baseline do Security Advisor capturado.
- **6136.** Arquivo executado integralmente via `execute_sql` (não `apply_migration`, para não registrar a migration no histórico, já que a promoção canônica não estava autorizada). Sem erro.
  - Confirmado: tabela, RLS ativa, 3 constraints (PK + 2 FKs), índice, 1 policy.
  - ACL: `authenticated=r`, `service_role=Dxtm`, `postgres` dono.
  - 0 linhas.
- **6137.** Arquivo executado integralmente. Sem erro.
  - As 2 funções têm SECURITY DEFINER, `search_path=""` e EXECUTE apenas para `authenticated` e para o dono.
  - O `prosrc` no LIVE tem o mesmo sha256 dos corpos do arquivo: `fc158789…` (get) e `2d06ab2f…` (set).
- **6849 v2.1.** Executado contra os objetos permanentes; UUIDs só na cópia temporária.
  - 47 de 47 verificações presentes: **46 PASS, 0 FAIL, 1 NOT_PROVEN (7.7)**; **GATE PASS**.
  - 10.1: A+B 0→0, total 0→0.
  - Capacidade: 1025 favoritos gravados em 111,7 ms e lidos em 2,3 ms.
- **Postcheck independente (somente leitura).**
  - Objetos permanentes presentes e conformes: RLS ativa e não forçada, policy `user_id = (select auth.uid())`.
  - `anon` sem SELECT nem EXECUTE; `authenticated` com EXECUTE nas duas funções.
  - 0 favoritos no total e 0 das contas de teste.
  - Contas de teste com `updated_at` inalterado; 3 usuários.
  - Entidades inalteradas: 1025 espécies ativas, Collection 0, Allocation 0, Inventory 3, Physical Card 0.
  - Nenhuma função temporária visível e nenhuma sessão *idle in transaction*.
- **Security Advisor.** Única novidade: as duas funções passam a constar em `authenticated_security_definer_function_executable` (WARN). Esse resultado é esperado: é o mesmo padrão das demais RPCs do produto (SECURITY DEFINER, executável por `authenticated`, `auth.uid()` obrigatório).
  - Nenhum alerta novo de RLS, `search_path` ou exposição a `anon`.
  - A tabela não aparece em `rls_enabled_no_policy`.
- **Limitações que permanecem.**
  - 7.7: não há espécie inativa no banco para testar a regra.
  - L1: o isolamento foi provado pelo banco, não pelo JWT real do PostgREST; essa prova fica para a homologação manual.
  - Promoção canônica: feita na P6.3 (§5.9).

### 5.9 P6.3–P6.6 — Promoção canônica e frontend (2026-10-15) — implementado localmente, aguardando homologação

**P6.3 — Promoção canônica.** Mesma convenção das 6131–6135: o arquivo canônico fica em `database/migrations/`, o validador 6849 e o ensaio 6850 ficam em `proposals/`. Nada foi executado nem alterado no LIVE nesta etapa.

- `database/migrations/6136_create_pokedex_species_favorite_table.sql` e `6137_create_pokedex_species_favorite_functions.sql`: cópias das propostas em que só o cabeçalho mudou (`Versão 1.0 (canônica — P6.3)` e bloco "CONFIRMADO EXECUTADO"). O bloco registra:
  - execução via `execute_sql`, sem registro de `apply_migration` / `schema_migrations`;
  - 6849 v2.1: 46 PASS, 0 FAIL, 1 NOT_PROVEN (7.7);
  - postcheck sem resíduos;
  - WARN esperado `authenticated_security_definer_function_executable`.
- **Identidade.** O texto entre a linha `begin;` e a linha `commit;` (mesma definição usada pelo 6850) é byte a byte igual entre proposta e canônico:

| Arquivo | sha256 do texto entre `begin;` e `commit;` (proposta = canônico) |
|---|---|
| 6136 | `d4d5c2d75ea24771f4d56ee5bbc160e812ddcc1b98b07f1c598eb7e014d63223` |
| 6137 | `37ea65d7893b07c8681e85e09f4ca53c1e83f50081e9e969f5520f22a195d6c7` |

- O `prosrc` LIVE das duas funções (lido na P6.2) é igual ao corpo do arquivo:
  - `get_my_pokedex_favorites`: `fc158789…a8cd95b`;
  - `set_pokedex_species_favorite`: `2d06ab2f…e557fe`.

**P6.4 — Regras e integração** (só as duas RPCs implantadas; nenhum contrato alterado):

- `web/lib/pokedex/favorites.ts` contém só regras puras:
  - recorte da galeria;
  - normalização da leitura;
  - máquina de intenção por espécie: otimista, no máximo uma gravação em andamento, a última intenção vence, falha reverte ao último estado confirmado;
  - mapeamento de erros: 28000/42501, 22023, P0002, PGRST202 e demais;
  - textos de anúncio e de erro em pt-BR, sem códigos técnicos.
- `web/lib/pokedex/queries.ts` → `getMyPokedexFavorites()`:
  - uma leitura agregada por página, paginada por `.range()` (limite de 1000 linhas do PostgREST);
  - qualquer falha devolve `null`, que a interface trata como "indisponível". Nunca há uma consulta por card.
- `web/app/pokedex/actions.ts` → Server Action `setPokedexSpeciesFavorite`:
  - identidade só pela sessão (cookie), sem `user_id` e sem `service_role`;
  - valida a entrada;
  - DEFINE o estado (idempotente);
  - registra o erro no log do servidor;
  - sem `revalidatePath`.

**P6.5 — Galeria e `/pokedex/favoritos`:**

- **Rota e galeria compartilhadas.** `web/app/pokedex/favoritos/page.tsx` e `web/app/pokedex/page.tsx` delegam a `web/components/pokedex/pokedex-gallery-page.tsx`, com guarda e redirecionamentos comuns e quatro leituras em paralelo. Existe uma única galeria (`PokedexNationalView` + `SpeciesGrid`) com `mode`.
- **Filtros.** Os favoritos são recortados sobre a lista da 6131 antes do filtro por tipo, então pesquisa, geração e tipo continuam valendo.
- **Origem.** `PokedexContext.origin = "favoritos"` faz pesquisa, filtros e links dos cards usarem `/pokedex/favoritos`.
- **Menu.** Novo item "Pokémons Favoritos" (ícone coração) logo abaixo de "Pokédex Nacional".
- **Coração.**
  - É um `<button>` irmão do link do card, nunca dentro dele.
  - Nome acessível constante ("Favoritar X"); o estado vai em `aria-pressed`.
  - Área de toque de 2.75rem.
  - Contorno quando não favorito, preenchido com o token próprio `--favorite` (claro `350 76% 48%`, escuro `350 88% 64%`), separado de `--destructive`.
  - Desktop (`hover:hover` e `pointer:fine`): o coração não marcado só aparece com hover/foco no card. Mobile: sempre visível.
  - Um único sprite SVG (`<use>`).
- **Ilha cliente.** `FavoritesController` é a única ilha para toda a grade. Escuta por delegação e altera só atributos (`aria-pressed`, `data-pending`, `data-fav-removed`), sem re-render da grade.
  - Anúncio em região `aria-live`.
  - Falha: estado revertido e mensagem inline com `role="alert"`.
- **Desfavoritar na página Favoritos.** O card fica atenuado no lugar até a próxima navegação, sem salto de layout.
- **Estados.**
  - Nenhum favorito: estado vazio próprio, que leva à Pokédex Nacional.
  - Filtro sem resultado: "Nenhum favorito…".
  - Leitura indisponível: alerta com "Tentar novamente" na página Favoritos; aviso discreto na Pokédex Nacional, com os corações desabilitados.

**P6.6 — Ficha da espécie:**

- `FavoriteToggle` usa a mesma máquina da galeria.
  - Texto visível constante "Favorito", com `aria-pressed`.
  - Dica no `title`.
  - Desabilitado com explicação (`aria-describedby`) quando a leitura falha.
  - Erro inline; a última intenção é enviada mesmo se o usuário sair da ficha.
  - O estado inicial vem da mesma leitura agregada da galeria.
- Com `?origem=favoritos`:
  - "voltar" e a trilha levam a Pokémons Favoritos, com âncora no card enquanto ele ainda for favorito;
  - anterior/próximo seguem a regra da P4a (sequência nacional/geração, não restrita aos favoritos) e preservam a origem.

**Validação local (2026-10-15):**

| Verificação | Resultado | Tipo |
|---|---|---|
| `npx tsc --noEmit` | PASS | automático |
| `node --experimental-strip-types --test lib/pokedex/*.test.ts` | **83/83 PASS** (64 anteriores + 19 novos) | automático |
| ESLint (`next/core-web-vitals`) nos arquivos alterados | PASS | automático |
| Concorrência / respostas fora de ordem / falha → reversão | coberto por testes da máquina de estados | automático |
| `npm run build`, `npm run lint` completos, First Load JS, tamanho do HTML | **não executado** (limitação do sandbox) | pendente — Fabrício |
| Visual (claro/escuro, desktop/mobile), teclado, leitor de tela | **não executado** | pendente — homologação |

- **Estimativa de custo (não medida).** São cerca de 230 bytes de HTML por card, ou seja, de 15 a 20 KB gzip para 1.025 cards, mais o payload RSC. O JS cliente novo se resume a uma ilha pequena e à Server Action.

**Limitações:**

- 7.7 continua NOT_PROVEN.
- L1: o isolamento pelo JWT real do PostgREST só é provado na homologação.
- Na ficha aberta a partir de Favoritos, o menu continua destacando "Pokédex Nacional" (aceito na v1, §6).
- A régua de gerações da página Favoritos mostra os totais nacionais.
- As decisões sobre os itens de menu "Por Geração" e "Pesquisa Avançada" continuam pendentes (§6).

**Checklist de homologação (Fabrício):**

1. **Build e medição.**
   - Rodar `npm run lint` e `npm run build` em `web/` e anotar o First Load JS de `/pokedex`, `/pokedex/favoritos` e `/pokedex/[numero]`.
   - Anotar o tamanho do HTML de `/pokedex` (comparar com o build anterior).
2. **Menu.** "Pokémons Favoritos" aparece logo abaixo de "Pokédex Nacional" e fica ativo em `/pokedex/favoritos`.
3. **Coração na galeria, desktop.** O coração não marcado só aparece com hover ou foco no card; o marcado fica sempre visível, preenchido em vermelho.
4. **Coração na galeria, mobile.** Fica sempre visível, com área de toque confortável e sem sobrepor o selo "recente".
5. **Temas claro e escuro.** O contraste do contorno e do preenchimento é bom e o vermelho do favorito não se confunde com o vermelho de erro.
6. **Favoritar e desfavoritar na galeria.** A mudança é imediata; recarregar a página mantém o estado.
7. **Cliques rápidos.** Dar 5 a 6 cliques seguidos no mesmo coração; depois de recarregar, o estado deve ser o da tela.
8. **Falha.** Ficar offline (DevTools) e clicar: o coração volta ao estado anterior, aparece a mensagem inline e nada muda após recarregar.
9. **`/pokedex/favoritos`.**
   - Mostra só os favoritos do usuário logado.
   - Pesquisa, geração e tipo funcionam.
   - Testar o estado vazio (conta sem favoritos) e o filtro sem resultado.
10. **Desfavoritar em Favoritos.** O card fica atenuado no lugar, sem salto de layout, e some na próxima navegação.
11. **Ficha.**
    - O botão "Favorito" mostra o mesmo estado da galeria e alterna na hora.
    - Ir para o anterior/próximo atualiza o estado do botão.
12. **Retorno.**
    - Abrir uma ficha a partir de Favoritos: "voltar" e a trilha levam a Favoritos, ancorados no card, com os filtros preservados.
    - Anterior/próximo mantêm a origem.
13. **Teclado.**
    - Tab alcança o link do card e depois o coração; Enter/Espaço alternam; o foco fica visível.
    - Leitor de tela: "Favoritar X, botão de alternância, pressionado/não pressionado" e o anúncio após a confirmação.
14. **Isolamento (L1).** Com duas contas, os favoritos de uma não aparecem na outra.
15. **`prefers-reduced-motion`.** Sem transições do coração.

### 5.10 Correção de UX-01 — galeria contínua de Favoritos (2026-10-15) — implementada localmente, aguardando homologação

Decisão aprovada na homologação: a página Pokémons Favoritos é uma galeria **contínua**; a Pokédex Nacional continua organizada por gerações. Mudança só de frontend: nenhum SQL, migration ou contrato alterado.

- **Grade.** `SpeciesGrid` ganhou `layout="continuous"`: os mesmos cards (coração, atenuação ao desfavoritar e âncoras de retorno incluídos) numa única `<ul>`, na ordem nacional, sem cabeçalhos, separadores ou espaçamento de capítulo. A Pokédex Nacional segue com `layout="chapters"` (padrão).
- **Filtro compacto de geração** (`favorites-generation-filter.tsx`) substitui, só em Favoritos, a régua de nove gerações e a barra compacta da P4c.
  - Botão "Geração" recolhido por padrão, que reaproveita o disclosure da P5a (`variant="generation"`; o padrão `type` não mudou). A geração ativa aparece como chip removível.
  - O painel lista "Todas as gerações" mais cada geração com a contagem de favoritos que bate com a pesquisa e os tipos atuais; geração sem favoritos fica indisponível. O painel fecha ao escolher.
  - Os links preservam pesquisa, tipos e origem (URL compartilhável) e não rolam a página.
- **Dados.**
  - Em Favoritos, a leitura de 6131 é feita sem filtro de geração (só a pesquisa), a mesma leitura da Pokédex Nacional sem filtros. A geração é aplicada em memória (`filterByGeneration`/`countByGeneration`), depois do recorte de favoritos.
  - Nenhuma leitura nova.
- **Geração no card:** não acrescentada. O número nacional já situa a espécie e o filtro cobre a navegação por geração; um rótulo a mais aumentaria a altura ou competiria com nome e tipos. Pode ser reavaliado na homologação.
- **Performance.**
  - Com geração selecionada, Favoritos passa a buscar a lista nacional completa (2 páginas) em vez de uma geração, o mesmo custo da Pokédex Nacional sem filtro.
  - A grade contínua não usa `content-visibility` por seção, que existia por capítulo. Ela renderiza no máximo o número de favoritos do usuário; com centenas, o custo é menor que o da Pokédex Nacional completa.
- **Validação local:**
  - `tsc --noEmit`: PASS.
  - `node --test`: **84/84** (+1 teste: geração como filtro e contagens).
  - ESLint nos arquivos alterados: PASS.
  - Visual, responsividade e leitor de tela: pendentes de homologação.

### 5.11 UX Correction-02 — organização visual dos Favoritos (2026-10-15) — implementada localmente, aguardando homologação

Composição entre o cabeçalho e a galeria de `/pokedex/favoritos`. Só layout: nenhuma leitura, dependência, componente cliente ou contrato novo; a Pokédex Nacional não muda (mesmo DOM e mesmas classes).

- **Cabeçalho.** O mesmo, com espaço inferior menor (`.heroFavorites`).
- **Barra de ferramentas.** Geração e Tipo ficam na mesma linha (`.favoritesToolbar`, `role="group"`), quebrando só quando falta espaço.
  - Os dois filtros mantêm componentes, comportamento, chips e remoção individual.
  - Novo modo `inline` no disclosure da P5a (só CSS: `display: contents`): botão e chips viram itens da linha, e o painel aberto ocupa a linha de baixo, na largura toda. Sem `inline`, o filtro por tipo da Pokédex Nacional fica idêntico.
- **Faixa de resultados** logo acima da grade, com separador sutil:
  - com filtros, "Exibindo X de Y favoritos" (Y = total do cabeçalho);
  - sem filtros, "Todos os seus favoritos", sem repetir a contagem;
  - à direita, "Ordem: Número nacional", só informativo.
- **Ritmo vertical.** Os blocos passam de 1,5rem para 1,25rem; a faixa fica a 1rem da grade (0,75rem no mobile). Tudo continua alinhado à mesma borda esquerda do cabeçalho e da grade; não há novos containers.
- **Limitação conhecida.** Com o painel de Geração aberto, a ordem de Tab segue o DOM: botão Geração → opções de geração (visualmente abaixo da linha) → botão Tipo. O painel fecha ao escolher e Esc devolve o foco ao botão.
- **Validação local:** `tsc --noEmit` PASS; `node --test` 84/84; ESLint PASS nos arquivos alterados. A homologação visual está pendente.

### 5.12 UX Correction-03 — coração da ficha no agrupamento superior direito (2026-10-15) — implementada localmente, aguardando homologação

- **Posição.** O `FavoriteToggle` saiu da área central (abaixo dos tipos) e foi para o agrupamento do topo da ficha, na ordem coração → indicações ←/→ → seletor "Nº 0000 de 1.025". A área central volta a ser ilustração → número/geração/região → nome → classificação → tipos → Português/English, sem espaço residual (o bloco antigo e seu `margin-top` foram removidos).
- **Visual.**
  - Botão circular de 2.5rem, com a mesma superfície e o mesmo anel do seletor de número, e área de toque de 2.75rem (`::before`).
  - Coração em contorno quando não é favorito; preenchido em `--favorite` (e anel avermelhado) quando é.
  - Visível em desktop e mobile, sem depender de hover; foco visível com anel `--primary`.
- **Acessibilidade.**
  - Botão nativo com `aria-pressed`. O nome acessível é o mesmo da galeria ("Favoritar Mimikyu"), constante; o estado vem de pressionado/não pressionado.
  - A dica visual (`title`) indica a ação do próximo clique ("Adicionar aos favoritos" / "Remover dos favoritos").
  - Indisponível: botão desabilitado, com explicação em `aria-describedby`.
  - Confirmação em `aria-live`; falha com `role="alert"`, ancorada sob o botão, sem deslocar a composição.
- **Comportamento.** Mesmo componente e mesma máquina de estados (otimista, uma gravação por vez, última intenção vence, falha reverte). Leitura, Server Action, `key` por espécie e navegação não mudaram.
- **Escopo.** Só `favorite-toggle.tsx`, `species-detail-view.tsx` e `species-detail.module.css`. Galeria, Favoritos e Pokédex Nacional ficaram intocadas.
- **Validação local.** `tsc --noEmit` PASS; `node --test` 84/84; ESLint PASS. Homologação visual pendente.

### 5.13 UX Correction-04 — controles da ficha e placeholder da pesquisa (2026-10-15) — implementada localmente, aguardando homologação

- **Ficha.** Saíram as indicações visuais ←/→ (`<span class="kbd">`, `aria-hidden`, só desktop), que não eram clicáveis. O agrupamento do topo ficou: coração → seletor "Nº 0000 de 1.025".
  - Os atalhos de teclado continuam em `SpeciesKeyboardNav` (← / →), e os controles laterais grandes de anterior/próximo não mudaram.
  - Removidos os estilos sem uso: `.kbd` e as propriedades tipográficas de `.position`, que só serviam às setas.
- **Pesquisa.** O placeholder do componente compartilhado `PokedexSearch` (usado por `/pokedex` e `/pokedex/favoritos`) passou de "Nome ou número — ex.: Pikachu, 25" para "Nome ou número". O rótulo acessível ("Pesquisar Pokémon por nome ou número"), a lógica, os parâmetros de URL e a submissão não mudaram.
- **Fora do escopo, intocados:** o placeholder do seletor de número da ficha (`species-quick-search.tsx`), a pesquisa administrativa de artes (`artwork-admin-search.tsx`) e a pesquisa global de cartas.
- **Validação local:** `tsc --noEmit` PASS; `node --test` 84/84; ESLint PASS; `git diff --check` OK.

## 6. Página própria × navegação existente (compatibilidade)

- **Rota:** `/pokedex/favoritos` é compatível. O App Router resolve segmentos estáticos antes do dinâmico `[numero]` (precedente: `/pokedex/imagens` já convive com `/pokedex/[numero]`). Além disso, `parseNationalNumberParam("favoritos")` já devolve `null`.
- **Menu:**
  - Entra um item `{ href: "/pokedex/favoritos", label: "Pokémons Favoritos", section: "Explorar" }` logo após "Pokédex Nacional".
  - O `activePattern` atual de "Pokédex Nacional" (`/^\/pokedex\/\d+$/`) não captura `/pokedex/favoritos`.
  - Os demais grupos não mudam.
- **Divergência:** "Por Geração" e "Pesquisa Avançada" **não existem como itens de menu** — são capacidades da própria Pokédex Nacional (P4/P5a). Pela regra do projeto, só entram quando houver página própria.
  - Hoje a seção fica: 1. Pokédex Nacional · 2. Pokémons Favoritos.
  - A ordem aprovada (Nacional → Favoritos → Por Geração → Pesquisa Avançada) fica reservada no comentário do menu para quando existirem.
  - **Decisão pendente:** criar ou não esses dois itens (e para onde apontariam).
- **Destaque ativo da ficha:** o menu decide o item ativo pelo pathname. Uma ficha aberta a partir de Favoritos (`/pokedex/25?…`) continuará destacando "Pokédex Nacional". Mostrar "Pokémons Favoritos" exigiria ler o contexto na lógica do menu. **Decisão pendente** (recomendação: aceitar na primeira versão).
- **Contexto:** o `PokedexContext` ganha a origem (`nacional` | `favoritos`). O "voltar" e os links internos usam a rota base correspondente, e a P4a/P5a continuam como estão.

## 7. Plano de implementação (atualizado)

| Etapa | Entrega | Estado |
|---|---|---|
| P6.0 | Conceito canônico (ADR-011 v1.6, ubiquitous-language 1.26) | **Concluída** |
| P6.1 | Artefatos 6136/6137/6849 + protocolo + ensaio 6850 | **Concluída** (§5.4–§5.7) |
| P6.2 | Implantação de 6136/6137 no LIVE + 6849 + postcheck + Advisor | **Concluída** (§5.8) |
| P6.3 | Promoção para `database/migrations/` + log/ROADMAP | **Concluída** (§5.9) |
| P6.4 | `lib/pokedex/favorites.ts` (leitor, recorte, intenção/concorrência) + contexto com origem + testes | **Implementada localmente** (§5.9) |
| P6.5 | Coração na galeria + página `/pokedex/favoritos` + item de menu + token `--favorite` | **Implementada localmente** (§5.9) |
| P6.6 | Coração na ficha + "voltar" para a origem | **Implementada localmente** (§5.9) |
| P6.7 | (fundida em P6.5/P6.6 na rodada de 2026-10-15) | — |
| P6.8 | Medição (HTML, First Load JS), homologação, commit | **Pendente — Fabrício** |

## 8. Matriz de testes (completa)

| Área | Casos | Como |
|---|---|---|
| Segurança/RLS/privilégios | Itens 1–4 e 10 (seção 5.1) | 6849 |
| Integridade | Itens 5–8 | 6849 |
| Volume | Item 9 (tempos registrados) | 6849 |
| Isolamento de domínio | Item 11 | 6849 |
| Resíduo | Item 12 | POSTCHECK |
| Lógica pura | Recorte favoritos × pesquisa × geração × tipos; contexto com origem; "voltar" para a origem; reducer de última intenção; respostas fora de ordem; rollback em falha | `node --test` |
| Visual | Coração nos estados (vazio/preenchido/hover/foco/pendente/erro), claro/escuro, mobile estreito, página Favoritos (cheia, vazia, filtrada vazia, erro) | Homologação |
| Acessibilidade | `aria-pressed`, nomes, ordem de foco, `aria-live`, contraste ≥ 3:1, área de toque ≥ 44 px, reduced-motion | Homologação + inspeção |
| Regressão | P4a, P4b, P4c (âncoras, barra), P5a (tipos, URL canônica), busca rápida da ficha, menu | 64 testes + cenários |
| Performance | HTML da galeria com corações (estimativa +10–15 KB comprimidos), First Load JS `/pokedex` e `/pokedex/favoritos`, uma leitura extra em paralelo, nenhuma por card | `npm run build` + medição |

## 9. Riscos

- **HTML maior na galeria:** mitigação com markup mínimo + sprite único, medido no build.
- **Confusão favorito × posse:** mitigação com coração, linguagem de preferência e nenhuma contagem de cartas.
- **Vermelho confundido com erro:** mitigação com token próprio, nunca o `--destructive`, sempre com forma de coração.
- **Item ativo do menu numa ficha aberta a partir de Favoritos:** ver seção 6 (decisão pendente).
- **Itens "Por Geração" e "Pesquisa Avançada" sem página própria:** ver seção 6 (decisão pendente).
- **Multiaba:** não há sincronização em tempo real; o estado se reconcilia na navegação. Aceito.
- **Provas com privilégio administrativo e sintaxe não validada:** L1/L6, a cobrir na auditoria e na primeira execução.

**Fora de escopo:** Favorite de Card, Wishlist, Collection, P7/P8/P9, compartilhamento de favoritos e P5b.
