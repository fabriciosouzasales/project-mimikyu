# V1-14 R1-H — catálogo de raridades para o colecionador

Origem: `R1-H — FUNCTIONAL CONTRACT APPROVAL & QUERY 5355 PROPOSAL-01` (2026-11-07), decisão D2 do contrato da R1-H (D7 §4h). **Query 5355 CONFIRMADA EXECUTADA no LIVE em 2026-11-07 01:15 UTC** (ver "Aplicação no LIVE" no fim). O harness 5883 só rodou em transação com ROLLBACK. O cabeçalho do arquivo `.sql` ainda diz "PROPOSTO — NÃO EXECUTADO" porque o conteúdo aplicado tinha de ser byte a byte o aprovado (rastreabilidade do SQL original); a promoção para `database/` fica para o ciclo do commit.

| Arquivo | Natureza |
|---|---|
| `5355_create_get_rarity_catalog_PROPOSAL.sql` | RPC somente leitura `get_rarity_catalog()` → `code`, `name`, `symbol_code`, `display_order` das raridades do Game POKEMON, na ordem do catálogo |
| `5883_validate_get_rarity_catalog_HARNESS.sql` | Harness em transação com ROLLBACK: esquema (E1), RLS e policies intactas (E2), propriedades e permissões (S1/S2), anon e sem sessão (S2/S3), colecionador não administrador (S4), integridade (I1/I2), ordem (I3), compatibilidade com a 5159 (I4), desempenho (P1) |

## Por que existe

A 5159 devolve `rarity_code` (rarity.code da carta). O nome oficial e a ordem do catálogo ficam em `public.rarity`, legível só por administrador (`catalog_admin_select`, migrations 274/2134). Um mapa fixo no front ficaria desatualizado: a seed 830 tem 15 raridades, mas migrations posteriores criaram outras (ex.: `PIKACHU_RARE`, `FUTURISTIC_RARE` na 2252). A 5355 lê a tabela vigente — raridades futuras aparecem sem mudança no front — e não altera a RLS.

## Esquema validado (repositório; reconfirmado no LIVE pelo E1 do harness)

`rarity`: `code varchar(50)`, `name varchar(150)`, `symbol_code varchar(50)`, `display_order integer` (todos NOT NULL; `display_order > 0`), `game_id uuid NOT NULL`; `UNIQUE (game_id, code)`; `display_order` **não** é único → desempate por `code`. `game.code varchar(50) UNIQUE`; catálogo Pokémon = `'POKEMON'`. A 5159 (5261) devolve `r.code::text` por `card.rarity_id` (LEFT JOIN; carta sem raridade → `null`).

## Segurança (resumo; detalhe no cabeçalho da 5355)

SECURITY DEFINER, `search_path ''`, objetos qualificados, STABLE, sem parâmetros, colunas fixas, filtro fixo no Game POKEMON, sessão obrigatória (`auth.uid()`; sem sessão → 28000), EXECUTE só para `authenticated` (revogado de PUBLIC e anon), dono `postgres`. Alternativas descartadas: policy nova em `rarity` (proibida e mais ampla), view definer (sem verificação de sessão e mais fácil de ampliar por engano), INVOKER (não passa na policy).

## Condições para autorizar a simulação (harness 5883)

1. Projeto LIVE `qjfutqujxrbzgrtkpgkg` e hashes destes arquivos conferidos antes da execução.
2. Existir ao menos um titular de inventário **não administrador** (S4 aborta com `Q5883_PRE_NO_NON_ADMIN_USER` se não houver; o 2º titular usado nos harnesses 5881/5882 é candidato).
3. Execução em transação única terminada em ROLLBACK, corpo da 5355 colado no lugar do `\ir` sem nenhuma alteração.
4. Nenhuma migration concorrente; 0 transações ociosas e bloqueios antes e depois.
5. Efeito externo esperado: só o `NOTIFY pgrst` do `pgrst_ddl_watch`, transacional (descartado no ROLLBACK).

| Hash | Valor |
|---|---|
| 5355 md5 | `ff3a4e1f84757dd7ec01aade89343855` |
| 5355 sha256 | `1f40f6f85fb10b648474c6fb09f6f3b15311e0b5fde61ac86d1b066691879880` |
| 5883 md5 | `f70fc1cd65f20dd71c9c08bd978ab114` |

## Harness 5883 — execução controlada (2026-11-07 01:08–01:10 UTC, `QUERY 5355 HARNESS 5883 EXECUTION-01`)

LIVE `qjfutqujxrbzgrtkpgkg` (mimikyu-core, PG 17.6). Duas execuções, cada uma numa transação única: (1) harness íntegro, terminado em `ROLLBACK`; (2) o mesmo harness + bloco final de evidência somente leitura, que aborta a transação com `RAISE` antes do `ROLLBACK` (devolve os valores medidos; nada persiste). Corpo da 5355 inserido no lugar do `\ir` sem nenhuma alteração (md5 `ff3a4e1f…`); só o comentário de cabeçalho do harness foi abreviado no envio. **5355 NÃO aplicada.**

**Precheck (tudo conforme, antes de qualquer escrita):** projeto confirmado; md5 5355 `ff3a4e1f84757dd7ec01aade89343855` e 5883 `f70fc1cd65f20dd71c9c08bd978ab114`; Game POKEMON presente; 2 titulares de inventário não administradores (de 3); `rarity` com RLS ativa, única policy `catalog_admin_select` (SELECT, `( SELECT is_admin())`, impressão digital `2cb6b1f5…`), ACL `{postgres=arwdDxtm,authenticated=r,service_role=rDxtm}`; função inexistente; 488 funções `public` (impressão digital de permissões `7d424648…`); 31 raridades (impressão digital dos dados `c69b1d06…`); 0 DDL em andamento, 0 transações ociosas, 0 bloqueios em espera; última migration = 5354. Efeito externo possível: só o `NOTIFY` do `pgrst_ddl_watch` (transacional); os demais event triggers só disparam em `CREATE EXTENSION`.

| Teste | Resultado |
|---|---|
| E1 esquema e Game | **PASS** — 7 colunas com nome, tipo e NOT NULL esperados; Game POKEMON presente |
| E2 RLS e policies | **PASS** — RLS ativa; impressão digital das policies igual antes e depois |
| S1 propriedades | **PASS** — SECURITY DEFINER, `search_path=""`, STABLE, retorno `TABLE(code text, name text, symbol_code text, display_order integer)` |
| S2 permissões | **PASS** — anon e PUBLIC sem EXECUTE, authenticated com EXECUTE; chamada real como anon → 42501 |
| S3 sem sessão | **PASS** — 28000 |
| S4 colecionador não admin | **PASS** — `is_admin() = false`; a função devolveu 31 raridades; SELECT direto em `rarity` = **0 linhas** |
| I1 igualdade | **PASS** — 0 diferenças nos dois sentidos (code, name, symbol_code, display_order) |
| I2 duplicação e nulos | **PASS** — 31 codes distintos, nenhum nulo ou em branco |
| I3 ordem | **PASS** — saída = ordem `display_order, code` (1:COMMON … 31:FUTURISTIC_RARE) |
| I4 compatibilidade com a 5159 | **PASS** — as 13 raridades presentes nos exemplares físicos estão todas na saída (inclui `CLASSIC_COLLECTION`, `PIKACHU_RARE`, `FUTURISTIC_RARE`, ausentes da seed 830); 0 exemplares de carta sem raridade |
| P1 desempenho | **PASS** — EXPLAIN ANALYZE como colecionador: 0,124 / 0,117 / 0,081 ms de execução (limite 50 ms), planejamento ~0,01 ms; `Function Scan on get_rarity_catalog`, 31 linhas, `shared hit=3` |

**Pós-ROLLBACK (01:10 UTC):** função inexistente; 488 funções `public` e impressão digital de permissões `7d424648…` iguais; RLS de `rarity` ativa, policies `2cb6b1f5…` e ACL iguais; 31 raridades com impressão digital `c69b1d06…` igual (catálogo intacto); 0 tabelas temporárias `_q5883*`, 0 transações ociosas, 0 bloqueios em espera; nenhuma migration nova no ledger; hashes dos arquivos iguais.

**Limitações identificadas:**
- **I3 com empate real não exercido:** hoje não há `display_order` repetido (0 empates); o desempate por `code` está garantido pela cláusula `ORDER BY` da função e pela asserção, mas não foi observado com dado real (simular exigiria escrever no catálogo, fora do escopo).
- **Nome repetido no catálogo:** `NONE` (display_order 21) tem o nome **"Comum"**, igual a `COMMON` (display_order 1), com o mesmo símbolo. Nenhum exemplar do acervo usa `NONE` hoje, mas, se usar, a R1-H mostraria duas faixas "Comum". A 5355 devolve o catálogo como está (não corrige dado); decisão de catálogo ou de apresentação pendente — ver parecer.
- **I4 é uma fotografia:** cobre os 13 códigos presentes hoje; a regra do contrato (§4h) — código ausente da 5355 → relatório incompleto — protege os casos futuros.

**Parecer:** **pronta para aplicação definitiva** — segurança, isolamento da RLS, integridade, ordem, compatibilidade e desempenho comprovados. Recomenda-se decidir antes da implementação da R1-H como tratar o nome repetido "Comum" (`NONE`).

## Aplicação no LIVE (2026-11-07, `QUERY 5355 LIVE APPLY-01`)

- **Quando / onde:** 2026-11-07 01:15:50 UTC (versão no ledger `20261107011550`, nome `5355_create_get_rarity_catalog`), projeto `qjfutqujxrbzgrtkpgkg` (mimikyu-core, sa-east-1, PG 17.6). Transação única do `apply_migration`; nenhuma outra migration.
- **Hash aprovado = hash aplicado:** arquivo md5 `ff3a4e1f84757dd7ec01aade89343855`, sha256 `1f40f6f85fb10b648474c6fb09f6f3b15311e0b5fde61ac86d1b066691879880` (4.179 bytes); md5 das instruções gravadas no ledger = `ff3a4e1f84757dd7ec01aade89343855`.
- **Precheck (01:15 UTC), tudo igual ao do harness:** projeto; hashes; função inexistente; Game POKEMON com 31 raridades e impressão digital dos dados `c69b1d06…`; RLS ativa, policies `2cb6b1f5…`, ACL de `rarity` inalterada; 488 funções `public` com permissões `7d424648…`; 2 titulares não administradores; ACL padrão do `postgres` em `public` = só `postgres=X`; 0 DDL, transações ociosas ou bloqueios; última migration = 5354.

**Postcheck — todos PASS:**

| Verificação | Resultado |
|---|---|
| Assinatura | `get_rarity_catalog()` → `TABLE(code text, name text, symbol_code text, display_order integer)`, dono `postgres`, comentário gravado |
| Propriedades | SECURITY DEFINER, `search_path=""`, STABLE |
| Permissões | ACL `{postgres=X/postgres,authenticated=X/postgres}`; anon sem EXECUTE (chamada real → 42501); PUBLIC e service_role sem EXECUTE |
| Sem sessão | 28000 |
| Colecionador não administrador | consulta a função (31 linhas); SELECT direto em `rarity` = 0 linhas |
| Catálogo | 31 raridades do Game POKEMON; 0 diferenças nos dois sentidos; 0 codes duplicados; ordem `display_order, code` (0 fora de ordem) |
| Acervo | 13 códigos presentes nos exemplares físicos, 0 não reconhecidos |
| Desempenho | EXPLAIN ANALYZE: 0,153 / 0,127 / 0,092 ms (limite 50 ms) |
| Nada mais mudou | 489 funções `public` (488 + 1); permissões das outras 488 = `7d424648…`; dados de `rarity` `c69b1d06…`, RLS, policies `2cb6b1f5…` e ACL iguais |
| Sessão | 0 transações ociosas, 0 bloqueios em espera |

Referência: harness 5883 (seção anterior). Pricing, 3989, 3990, 5354 e JustTCG não foram tocados; NONE e COMMON não foram alterados.

**Decisão sobre nomes duplicados (proprietário, `QUERY 5355 LIVE APPLY-01`; contrato D7 §4h):** raridades agrupadas por `code`, nomes só da 5355; códigos diferentes nunca são mesclados por terem o mesmo nome; quando códigos com nome igual estiverem na mesma distribuição, diferenciar visualmente pelo `code`; sem ambiguidade, só o nome. Ausência legítima de `rarity_code` → "Sem raridade definida"; `rarity_code` não encontrado na 5355 → inconsistência que bloqueia a impressão. Os registros NONE e COMMON do catálogo ficam como estão.
