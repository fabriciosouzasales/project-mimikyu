# Staging — PRIMARY-SPECIES-INCREMENTAL-HOOK-FIX-01

| Campo | Valor |
|---|---|
| **Mandato** | `PRIMARY-SPECIES-INCREMENTAL-HOOK-FIX-01 — GATE A` |
| **Data** | 2026-09-12 |
| **Status** | **CONFIRMADO EXECUTADO / VALIDADO / PROMOVIDO** |
| **Depende de** | Query `6116` v1.2 (CONFIRMADO EXECUTADO / LIVE) |
| **Diagnóstico** | `PRIMARY-SPECIES-INCREMENTAL-HOOK-AUDIT-01` |

---

## Incidente

Três jobs TCGDEX chegaram a `COMPLETED` com Primary Species = 0:

| Set | job_id | Recuperado por |
|---|---|---|
| SMP | `3904745c-480b-4884-ba1a-c04ac0c1e8fc` | `BACKFILL-01` (220 Cards) |
| SM10 | `1150a2eb-2e46-43e5-8e13-e592105778bc` | `BACKFILL-02` (173 Cards) |
| BW10 | `fb3b25e3-14be-4260-9d89-020412234c2a` | `BACKFILL-03` (85 Cards) |

O estado já foi reconciliado. Esta proposta trata **a recorrência**, não o dado.

## Causa — provada, não inferida

O próprio caller (`web/scripts/bootstrap-cards/run-bootstrap-cards.mjs`) registrou
a causa no CSV da rodada, campo `motivo`:

```
IMPORTED,primary_species falhou (nao bloqueante):
         canceling statement due to statement timeout
```

`out/cards-apply-2026-09-11T00-18-39-713Z.csv` (SM10 linha 130, BW10 linha 83) e
`out/cards-apply-2026-09-11T18-50-15-317Z.csv` (SMP linha 2). Varredura de toda a
série: **exatamente 3 ocorrências**, exatamente esses três Sets — nenhum caso
oculto. Jobs contemporâneos da mesma sessão (SM1, SM4, SM9, SM11, BW9) saíram com
`job COMPLETED` e resolveram normalmente.

**O caller funcionou conforme o desenho** — RPC separada pós-COMMIT, `{ data, error }`
checado, falha registrada, importação não bloqueada. O defeito é da função.

### Mecanismo

`authenticated` tem `statement_timeout = 8s`; 6116 executa como `authenticated`.
A CTE `evidence` filtra `r.resulting_card_id IN (job_rows)` **sem repetir
`r.job_id = p_job_id`**, e `catalog_import_row` não tem índice em
`resulting_card_id`. O planner varre a tabela inteira a cada chamada,
independentemente do tamanho do job.

`EXPLAIN ANALYZE` da query interna real de 6116, job do SM10, 2026-09-12, cache
quente, base ociosa, como `postgres`:

```
Seq Scan on catalog_import_row (rows=20053) .............. 6571 ms
Nested Loop Semi Join → Rows Removed by Join Filter: 3.891.225
Execution Time ........................................... 7663 ms   (96% de 8s)
```

Hoje está a ~340 ms da borda. Não é evento raro — é falha prestes a reincidir.

## Correção

Uma cláusula, na CTE `evidence`:

```diff
       WHERE r.raw_data ? 'dexId'
+        AND r.job_id = p_job_id
         AND r.resulting_card_id IN (SELECT card_id FROM job_rows)
```

| Arquivo | O quê | Estado |
|---|---|---|
| `6128_fix_resolve_card_primary_species_for_catalog_import_job_evidence_scope.sql` | `CREATE OR REPLACE` da 6116 com **apenas** a cláusula | **CONFIRMADO EXECUTADO / VALIDADO / PROMOVIDO** — este arquivo é **evidência histórica**; a fonte canônica é a cópia em `database/schema/` |

### Invariante de identidade: corpo executável, não arquivo inteiro

| Artefato | Papel |
|---|---|
| `database/proposals/2026-09-12-.../6128_…sql` | **Evidência histórica** da rodada de staging |
| `database/schema/6128_…sql` | **Fonte canônica** promovida |
| Objeto no LIVE | `public.resolve_card_primary_species_for_catalog_import_job(uuid)` |

O que precisa ser **byte-idêntico** entre os três é o **corpo SQL executável** — o texto
entre `AS $$` e `$$`, que o Postgres armazena em `pg_proc.prosrc`:
**`md5 7f2e7de82acf9a50df23a5861475b601` / 4539 bytes**, verificado no LIVE pelo `6841 §1.3`.

Os **cabeçalhos divergem de propósito**: cada cópia declara o próprio papel
(`CONFIRMADO EXECUTADO / VALIDADO / PROMOVIDO` na proposta,
`CANÔNICA — CONFIRMADO EXECUTADO / LIVE / PROMOVIDO` no schema). Exigir
byte-identidade do **arquivo inteiro** seria forçar a proposta a se declarar canônica,
o que ela não é. O cabeçalho fica fora do corpo da função e não afeta `prosrc`.
| `6841_validate_primary_species_6116_evidence_scope.sql` | 7 checagens estruturais + 10 casos funcionais + zero resíduo | **EXECUTADO / 17 PASS · 0 FAIL · 0 NOT PROVEN** — permanece AQUI como prova, **não** é promovido |

---

## Encerramento (2026-09-12, `PROMOTION-CLOSEOUT-01`)

**Causa real.** `statement_timeout` de 8 s do papel `authenticated`, estourado
porque a CTE `evidence` de 6116 não repetia `r.job_id = p_job_id` e
`catalog_import_row` não tem índice em `resulting_card_id` — o planner varria a
tabela inteira a cada chamada, independentemente do tamanho do job.

**Os 3 failures comprovados** (pelo CSV do próprio caller, não por inferência):
`SMP`, `SM10`, `BW10`. Exatamente 3 ocorrências de `primary_species falhou` em
toda a série de CSVs — nenhum caso oculto. Já reconciliados por
`BACKFILL-01/02/03` (478 Cards).

**Correção.** Uma cláusula: `AND r.job_id = p_job_id`.

**Equivalência funcional pré-fix.** Sobre os **199 jobs TCGDEX** do universo
auditado: 18.234 pares `(job, card)` nas duas formas, **0 divergências**.
Complementarmente, das 1.718 Cards presentes em mais de um job, **0** têm
`dexId` divergente entre jobs.

**Validação final.** `6841` = **17 PASS / 0 FAIL / 0 NOT PROVEN**, incluindo
`md5(prosrc) = 7f2e7de82acf9a50df23a5861475b601` / 4539 B, ACL/owner/COMMENT/
assinatura preservados, `SOURCE_NOT_TCGDEX`, `NO_ELIGIBLE_CARDS`, os três
guards de erro, isolamento cross-job e zero escrita em `card_primary_species`.
Fixtures integralmente revertidas: 0 jobs PDF residuais, `catalog_import_job`
de volta a 213, `card_primary_species` em 16.657.

**Performance real (job do SM10).** `7663 ms` → **`262 ms`** (~29×).
`Seq Scan` global **eliminado**; ambos os acessos a `catalog_import_row` usam
`ix_catalog_import_row_job`; margem contra o `statement_timeout` de 8 s passou
de 96 % consumido para **3,3 %**.

**Nenhum índice novo foi criado.** **Os callers permanecem não bloqueantes** —
nenhum deles foi alterado; `run-bootstrap-cards.mjs`, `confirmarImportacao()` e
`revalidate-catalog-import-rows` seguem checando `{ data, error }`, logando e
nunca revertendo a confirmação.

### Dívida de proveniência (registrada, NÃO resolvida)

| Artefato | md5 | length |
|---|---|---:|
| `prosrc` LIVE **antes** da 6128 | `9d6cd767dfcd627e76a38c21d820dbcf` | 3005 |
| corpo do arquivo canônico `6116` | `fddacfc49d0968fd1902a7d234bb0189` | 4209 |

O corpo que estava no banco **não era byte-idêntico ao canônico**, apesar de o
cabeçalho da própria `6116` afirmar *"corpo SQL byte-idêntico ao executado"*.
O **corpo histórico exato não está mais disponível** — foi substituído pelo
`CREATE OR REPLACE` e o Postgres não guarda versão anterior. **Nenhuma
equivalência byte-level retroativa é alegada.**

Classificação: **dívida documental / de proveniência — não classificada como
defeito funcional atual.** Verificar se outras funções promovidas divergem do
canônico exige **mandato próprio**.

Numeração: `6128` livre (estruturais vão até `6127`); `6841` livre (validações em
proposals: 6800/6810/6820/6821/6830/6840).

## Provas (todas read-only, executadas no Gate A)

| # | Prova | Resultado |
|---|---|---|
| 1 | **Diff semântico byte-level.** ⚠️ **Premissa corrigida em `RECOVERY-01`** — ver seção "STOP no APPLY-01" | corpo da 6128 == `prosrc` LIVE: `7f2e7de8…` / 4539 B · 6128 − delta == canônico 6116: `fddacfc4…` / 4209 B |
| 2 | **Equivalência funcional, universo inteiro.** Forma corrigida vs. forma atual, agregação `(job, card) → dexId[]`, sobre **199 jobs TCGDEX** | 18.234 pares em ambas · **0 divergências** |
| 3 | **Isolamento cross-job.** `evidence` não incorpora linhas de outros jobs | 1.718 Cards em >1 job, **0 com `dexId` divergente** entre jobs (medido em AUDIT-01) |
| 4 | **EXPLAIN comparativo** (job do SM10, mesma sessão) | atual **7663 ms** → corrigida **313 ms** (**24×**); buffers 22.427 → 19.056 |
| 5 | **Uso do índice** | ambos os scans de `catalog_import_row` passam a usar `ix_catalog_import_row_job`; **Seq Scan eliminado** |
| 6 | **SMP/SM10/BW10 semanticamente iguais** | cobertos pela prova 2 (os três estão entre os 199 jobs) |
| 7 | **Segurança/ACL** | `CREATE OR REPLACE` com assinatura idêntica preserva ACL e COMMENT; a 6128 não emite `GRANT`/`REVOKE`/`COMMENT`. Verificado em 6841 §1.4/1.5 |
| 8 | **Jobs PDF** | guard `SOURCE_NOT_TCGDEX` inalterado e verificado em 6841 §1.7 (estático) e F05 (funcional, com fixture PDF — não existe job PDF no LIVE) |

**Sobre a prova 4:** a AUDIT-01 havia medido 87× num recorte mais simples da query.
Na forma real da função o ganho é **24×**. O número que importa não é o múltiplo:
é que o termo de custo que crescia com a tabela inteira (Seq Scan) desaparece —
o custo passa a ser proporcional ao job.

## STOP no APPLY-01 e recuperação (2026-09-12)

### a) Causa do STOP

A 6128 foi aplicada com sucesso, mas a asserção de md5 pós-apply falhou:
esperado `449d88bc…` / 3335 B, obtido `7f2e7de8…` / **4539 B**.

O erro foi de premissa, na montagem do Gate A: o md5 esperado foi calculado
por `replace()` sobre o **`prosrc` LIVE**, enquanto a 6128 foi escrita a partir
do **arquivo canônico** `database/schema/6116_…sql`. Assumi que os dois eram o
mesmo corpo. Não eram.

### b) Divergência histórica canônico ↔ PRE-6128 LIVE

| Artefato | md5 | length |
|---|---|---:|
| `prosrc` LIVE **antes** da 6128 | `9d6cd767dfcd627e76a38c21d820dbcf` | 3005 |
| corpo do arquivo canônico `6116` | `fddacfc49d0968fd1902a7d234bb0189` | 4209 |

Diferença de ~1200 bytes, essencialmente **linhas de comentário internas**
ausentes no corpo que estava no banco. A divergência **é anterior a esta
rodada** e contradiz o cabeçalho da própria `6116`, que afirma *"corpo SQL
byte-idêntico ao executado"*.

**Classificação: dívida de proveniência/documentação — não classificada como
defeito funcional.** O corpo histórico não existe mais em lugar algum
alcançável, e **nenhuma equivalência byte-level retroativa é alegada** entre
ele e o canônico. Verificar se outras funções promovidas divergem é escopo de
mandato próprio.

### c) Prova 6128 ↔ LIVE atual (`RECOVERY-01`, read-only)

```
corpo(6128 em disco)                 md5 7f2e7de82acf9a50df23a5861475b601 / 4539 B
prosrc LIVE atual                    md5 7f2e7de82acf9a50df23a5861475b601 / 4539 B
igualdade byte-a-byte (operador =)   TRUE

corpo(6128) − DELTA_APROVADO         md5 fddacfc49d0968fd1902a7d234bb0189 / 4209 B
corpo(canônico 6116)                 md5 fddacfc49d0968fd1902a7d234bb0189 / 4209 B

=> 6128 = CANÔNICO_6116 + DELTA_APROVADO
```

`DELTA_APROVADO` = 4 linhas de comentário + `AND r.job_id = p_job_id`
(330 B, ocorrência única). **Único delta executável: a cláusula.**
Ambos os arquivos em disco são LF-only — não há delta de CRLF nem de whitespace.

### d) O que não é alegado

Não se alega que o corpo agora no LIVE seja funcionalmente equivalente ao
corpo pré-6128 por comparação byte-level: essa comparação é impossível, o
objeto foi substituído. O que está provado é que o LIVE é exatamente o
**arquivo canônico do repositório mais a cláusula autorizada** — ou seja, o
LIVE passou a coincidir com a fonte de verdade documental, que antes não
coincidia.

## Fora de escopo (deliberado)

- **Índice em `resulting_card_id`** — desnecessário após a correção; seria DDL sem
  necessidade comprovada.
- **`run-bootstrap-cards.mjs`** — funcionou conforme o desenho. Fica registrado
  como observação o `else` da linha 842 (job já terminal na entrada do laço retorna
  sem chamar 6116): lacuna real, **não foi o que ocorreu aqui**, sem evidência de
  que já tenha disparado.
- **Observabilidade** — a informação já é gravada no CSV; falta destaque no sumário
  de fim de rodada. Ergonomia, não defeito. Rodada própria.
- **As 760 pendências sem evidência durável** e **Card Variants** — frentes distintas.

## Ordem de execução (quando autorizada)

1. Aplicar `6128`.
2. Executar `6841` Seção 1 (estrutural/segurança/diff) — aborta na 1ª divergência.
3. Executar `6841` Seção 2 (funcional, termina em `ROLLBACK`).
4. Executar `6841` Seção 3 (zero resíduo) — esperado `0 | 0 | 0`.

`6841` é prova, não estrutura: **não** é promovida para `database/schema/`.
