# PROVA DE TOOLING — `NULLS NOT DISTINCT`

**BLOCKER 10.** "PostgreSQL 17.6" não basta; era preciso provar o *fluxo do
projeto*.

## Fato verificado no repositório

| Verificação | Resultado |
|---|---|
| `supabase/migrations/` | **não existe** |
| `.github/workflows/` | **não existe** |
| `supabase/` | apenas `config.toml` e `functions/` |
| `web/package.json` scripts | `dev`, `build`, `start`, `lint`, `typecheck` — nenhum de banco |

`database/README.md`, texto normativo:

> "**Não é** um sistema de migration automatizado — os arquivos aqui não são
> aplicados a um banco novo executando esta pasta em sequência; cada Query é
> executada e validada individualmente, uma de cada vez. A execução pode
> ocorrer diretamente pelo ambiente de desenvolvimento autorizado (hoje, Claude
> Code integrado ao Supabase via MCP, usando `apply_migration`/`execute_sql`)
> ou, excepcionalmente, pelo SQL Editor do Supabase."

## Consequência — o risco é menor do que eu havia estimado

| Risco levantado em STAGING-01 | Status real |
|---|---|
| `pg_dump` / restore do projeto | **não se aplica** — não há dump/restore no fluxo |
| Supabase CLI `db diff` / `db push` | **não se aplica** — CLI não é usada para schema |
| Schema-diff em CI | **não se aplica** — não há CI de banco |
| `apply_migration` (MCP) aceitar `NULLS NOT DISTINCT` | ⚠️ **prova pendente T1** |
| `apply_migration` / `execute_sql` aceitarem `INDEX CONCURRENTLY` | ✅ **não se aplica mais** — `CONCURRENTLY` foi REMOVIDO da proposta (Correção 2) |

`apply_migration` envia SQL literal ao servidor 17.6; não há camada de parsing
intermediária conhecida que reescreva DDL. A expectativa é de suporte pleno —
**mas isso é expectativa, não prova.**

## Correção 2 — `CONCURRENTLY` saiu da proposta, e T2 com ele

**Decisão arquitetural de Fabrício, acatada:** índice normal sob FREEZE.
`2209` e `2210` foram reescritos; `2215` e `2216` (DROP) nascem sem
`CONCURRENTLY`. O teste T2 **deixou de existir** — não se testa o que não
se usa.

### Comparação que fundamenta a escolha

| | **A — índice normal sob FREEZE** ✅ | B — `CONCURRENTLY` |
|---|---|---|
| Lock | `ShareLock`: bloqueia escrita, **não** bloqueia leitura | `ShareUpdateExclusive`: não bloqueia escrita |
| Duração | `card_variant` 24.893 linhas / 9.064 kB · staging em escala controlada ⇒ centenas de ms | 2 varreduras + espera por transações antigas: mais lento |
| Transacional | **sim** — compatível com `apply_migration`, revertível junto | **não** — exige autocommit |
| Precedente no projeto | todos os índices existentes | **zero** (medido) |
| Falha parcial | aborta a transação, nada fica | deixa índice `INVALID` exigindo limpeza manual |

**O único benefício de B — não bloquear escrita — é irrelevante sob FREEZE.**
Sem tráfego concorrente, B só acrescenta um modo de execução inédito, um
estado de falha novo e a perda da reversibilidade transacional. A preferência
arquitetural está correta e **não há prova concreta em contrário**: nem o
volume nem a disponibilidade exigida tornam A inadequado.

### Evidência que sustentava o risco (agora resolvido)

```
grep -rl "INDEX CONCURRENTLY" database/schema database/migrations  ->  vazio
```

`2209` e `2210` usam `CREATE UNIQUE INDEX CONCURRENTLY`. Verificação feita:

```
grep -rl "INDEX CONCURRENTLY" database/schema database/migrations  ->  vazio
```

**Zero ocorrências.** O projeto nunca aplicou DDL não-transacional por este
caminho. `apply_migration` envolve o SQL em transação, e `CONCURRENTLY`
**não pode** rodar dentro de bloco transacional (`25001`). Portanto:

Zero ocorrências: o projeto nunca aplicou DDL não-transacional por este
caminho. Introduzi-lo agora seria assumir risco novo sem ganho — daí a
eliminação, não a mitigação.

## Prova exigida no Gate A — **T1, e só T1**

Script completo e executável: **Query `2840`**.

### T1 — `NULLS NOT DISTINCT`

```sql
BEGIN;
CREATE TEMP TABLE t_nnd (a INT, b INT, UNIQUE NULLS NOT DISTINCT (a, b));
INSERT INTO t_nnd VALUES (1, NULL);
INSERT INTO t_nnd VALUES (1, NULL);   -- deve falhar com 23505
ROLLBACK;
```

Executado via `apply_migration` **e** via `execute_sql`, em TEMP TABLE, dentro
de transação revertida — zero efeito no schema LIVE. Se qualquer um dos dois
não aceitar a sintaxe, a estratégia cai para quatro índices parciais e o
`2209` é reescrito **antes** de qualquer execução.

**Resultado esperado:** o segundo `INSERT` falha com `23505`. Se ele **passar**,
`NULLS NOT DISTINCT` foi silenciosamente ignorado — pior cenário possível, e o
motivo de o teste existir.

**Postcheck:** `SELECT COUNT(*) FROM t_nnd;` deve ser 1 antes do `ROLLBACK`.
**Cleanup:** o `ROLLBACK` descarta a TEMP TABLE; nada a limpar.

### T2 — `INDEX CONCURRENTLY` (achado do Gate A)

Não pode usar TEMP TABLE (índice concorrente exige tabela persistente), então
usa uma tabela descartável em `public`, criada e destruída no mesmo teste:

```sql
-- (1) preparação — transacional, via apply_migration
CREATE TABLE public._t_conc_probe (a INT);

-- (2) o teste — envio ISOLADO, autocommit, via execute_sql
CREATE INDEX CONCURRENTLY ix_t_conc_probe ON public._t_conc_probe (a);

-- (3) postcheck
SELECT indisvalid FROM pg_index
 WHERE indexrelid = 'public.ix_t_conc_probe'::regclass;   -- esperado: true

-- (4) cleanup OBRIGATORIO — roda mesmo se (2) falhar
DROP TABLE IF EXISTS public._t_conc_probe CASCADE;
```

**Resultado esperado:** (2) conclui e (3) devolve `true`.
**Falha esperada se houver transação implícita:** `25001` —
*"CREATE INDEX CONCURRENTLY cannot run inside a transaction block"*.
**Rollback/cleanup:** o passo (4) é incondicional; a tabela tem prefixo `_t_`
e zero linhas, não colide com nenhum objeto canônico.

**Não executadas nesta rodada** — o mandato veda execução de SQL.

