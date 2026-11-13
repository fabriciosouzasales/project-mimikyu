# V1-16 — Validação offline em PostgreSQL (roteiro para o proprietário)

> **SUBSTITUÍDO em 2026-11-13** (`V1-16 | CONTROLLED EXECUTION READINESS-01`) por [`CONTROLLED-EXECUTION-PROTOCOL.md`](CONTROLLED-EXECUTION-PROTOCOL.md). O proprietário determinou que não serão usados ambientes isolados, containers, réplicas ou bancos de teste. A execução ocorre só no ambiente autorizado por ele, uma etapa por vez. **Não executar este roteiro.** O texto abaixo é preservado sem alteração como registro histórico da rodada `OFFLINE POSTGRES VALIDATION-01`.

| Campo | Valor |
|---|---|
| **Origem** | `V1-16 \| OFFLINE POSTGRES VALIDATION-01` (2026-11-13) — **BLOCKED para o agente**: o sandbox do agente não tem PostgreSQL nem acesso de rede para instalá-lo, e não controla o Docker da máquina do proprietário. Nada foi executado. |
| **Executor** | Fabrício, na própria máquina, **num container NOVO e descartável**. |
| **LIVE** | **Não recebe nenhum SQL deste roteiro.** O único contato com o LIVE é o passo R1 (leitura somente, pelo proprietário, se ele decidir), para obter a estrutura atual. |
| **Não usar** | O container `b12-pg17` / volume `b12-pg17-data` (FREEZE do Batch 12/E15) **não é tocado**. A réplica dele (`C:\b12-pg17\dump`, 2026-09-28) é **anterior** a 5153–5158 (16/10) e à 5262 (24/10) e não tem `register_card_set_bulk` — os prechecks de 5362/5363 parariam (por desenho). |

## R0 — Ambiente

```powershell
$ErrorActionPreference = 'Stop'
$Repo = 'C:\Users\Administrador\Documents\Coleção Pokémon\00. Desenvolvimento do Sistema Mimikyu\02 - Repositório de Dados\project-mimikyu'
$P    = Join-Path $Repo 'database\proposals\2026-11-13-v1-16-card-condition'
$W    = 'C:\v116-pg17'                     # pasta NOVA, fora do repositório
$C    = 'v116-pg17'                        # container NOVO
New-Item -ItemType Directory -Force -Path $W, "$W\out" | Out-Null
$pw = [Guid]::NewGuid().ToString('N')      # senha local descartável (não é credencial do LIVE)
docker run -d --name $C -p 127.0.0.1:55433:5432 -e POSTGRES_PASSWORD=$pw `
  -v "${W}:/work" supabase/postgres:17.6.1.147
```

Gate R0: `docker ps` mostra `v116-pg17` em `127.0.0.1:55433`; nenhuma variável de ambiente, arquivo ou `.pgpass` desta sessão contém host/usuário/senha do LIVE.

## R1 — Estrutura atual (o proprietário decide como obter)

Precisa refletir o LIVE **de hoje** (5361 nunca aplicada): esquema `public` completo (tabelas, funções, gatilhos, RLS, grants) e os **dados de referência do catálogo** usados pelos harnesses (`game`, `rarity`, `card_category`, `card_variant_type`, `language`, `card_condition`, `expansion`, `card_set`, `card`, `card_variant` e suas dependências). **Sem dados de usuários** (`physical_card`, `inventory`, `collection*`, `bulk_operation`, `storage_container`, layout, desejos, favoritos ficam vazios).

Opção recomendada: `pg_dump --schema-only --schema=public` + `pg_dump --data-only` só das tabelas de referência acima, numa sessão **somente leitura** (mesma disciplina de `C:\b12-pg17\sql\extract_live_ro.sh`: `BEGIN TRANSACTION READ ONLY`, papel sem BYPASSRLS quando possível). Salvar em `$W\schema.sql` e `$W\ref_data.sql`.

Restaurar e criar dois usuários sintéticos (os harnesses usam os dois primeiros de `auth.users`):

```powershell
function Psql([string]$f) { docker exec -e PGPASSWORD=$pw $C psql -X -h 127.0.0.1 -U postgres -d postgres -v ON_ERROR_STOP=1 -f $f }
Psql /work/schema.sql
Psql /work/ref_data.sql
docker exec -e PGPASSWORD=$pw $C psql -X -h 127.0.0.1 -U postgres -d postgres -v ON_ERROR_STOP=1 -c "
  insert into auth.users (id, created_at) values
    ('00000000-0000-4000-8000-00000000a001', now() - interval '2 days'),
    ('00000000-0000-4000-8000-00000000a002', now() - interval '1 day');"
```

## S0 — baseline e dependências (só leitura, no LOCAL)

Executar as quatro consultas da seção **S0** do `README.md` contra o local. **GO** só se:

- escala `M:1,NM:2,LP:3,MP:4,HP:5,DMG:6`;
- md5 = `a5fd5107…` (5153), `0b7221b6…` (5155), `1526fd4d…` (5157), `8dcf2656…` (5158), `d8cce43b…` (5262), uma linha cada;
- retorno de `get_my_inventory_item_copies` = 18 colunas da 5162 + `, variant_type_code text, rarity_code text)`;
- contagens anotadas.

Divergência ⇒ **STOP** (a réplica não reflete o LIVE atual, ou o LIVE diverge dos canônicos — reportar com a saída).

## S1–S4 — uma etapa por vez

Cada SQL de etapa roda **inteiro** (`begin;` … `commit;`). Para o harness, copiar `5887` para `$W\5887_sX.sql` e comentar os blocos `DO` dos grupos ainda não aplicáveis, ajustando a constante do gate (`count(*) = 66`). Rodar o harness com `ON_ERROR_STOP=1` (CALL 1 + ROLLBACK) e depois a CALL 3 (comentário no fim do arquivo).

| Etapa | Executar | Gate |
|---|---|---|
| S1 | `5361` → harness com X01, F01, F02, A01–A06 (X02 comentado; gate **9**) | sem exceção; **9/9/0**; CALL 3 = baseline; `count(*) filter (where condition_code <> 'NM')` = 0 |
| S2 | `5362` → harness X, F, A, B (gate **34**) → **5822, 5823 (versão 2026-10-16), 5824, 5826** com os gates originais (5822 64/64; 5823 60/60; 5824 30/29/0/1 — 1 NOT PROVEN por desenho; 5826 56/56; ver cabeçalho de cada um) | **34/34/0**; os quatro legados PASS; resíduo zero |
| S3 | `5363` → harness X, F, A, B, C (gate **41**) | **41/41/0** |
| S4 | `5364` → harness completo (gate **66**) → `CONCURRENCY-5364-TWO-SESSIONS.sql` (dois terminais) | **66/66/0**; cenários 1–3 com os resultados esperados; passo 9 de limpeza |

Em qualquer FAIL, exceção de compilação ou divergência: **STOP**, guardar `$W\out\*` (saída completa do psql com `-v VERBOSITY=verbose`) e reportar — **não editar os scripts** durante a execução.

Registrar, por etapa: comando, rc do psql, saída do relatório final do harness (`total/pass/fail/gate_ok/failing_cases`) e a CALL 3.

## Encerramento

```powershell
docker rm -f $C      # descarta o container; a pasta $W pode ser mantida como evidência (fora do repositório)
```

O resultado (OFFLINE PASS ou falhas com evidência) volta para a rodada seguinte; só depois disso se discute execução no LIVE.
