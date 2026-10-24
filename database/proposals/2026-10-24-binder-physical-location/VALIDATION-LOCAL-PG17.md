# Validação em PostgreSQL real sem novo projeto Supabase — Protocolo C (proposto)

| | |
|---|---|
| Status | **DESCARTADO** (LIVE-READINESS-01: validação isolada descartada pelo proprietário; o pacote fica NÃO EXECUTADO e não é requisito). Antes: **PACOTE PREPARADO — NÃO EXECUTADO** (PG17-POWERSHELL-PACKAGE-01). O roteiro C1 virou o pacote `pg17-validation/` (RUN, CLEANUP, manifestos, SQL); a linha de base vem das canônicas do repositório (173 arquivos, sem leitura do LIVE), não de exportação. Execução depende de autorização de Fabrício. Ver `pg17-validation/README.md`. |
| Base | precedente já executado por Fabrício: réplica PostgreSQL 17 local isolada (`C:\b12-pg17`, loopback), Protocolos A/B do Batch 12 (`RUNBOOK-PROTOCOL-A.md`, `PROTOCOL-A-CLOSEOUT.md`). O agente apenas leu esses dois relatórios; nada em `C:\b12-pg17` foi alterado. |
| Não usa | LIVE (exceto leituras de catálogo já previstas no Protocolo B), novo projeto Supabase, branch Supabase, instalação de software |

## 1. Opções avaliadas

| Opção | Banco real? | Novo ambiente/instalação? | Situação |
|---|---|---|---|
| **C1 — PG17 local já instalado (réplica isolada `b12-pg17`), banco descartável novo dentro dele** | sim (17.6) | não (instância existente; só `createdb` de um banco temporário) | **recomendada; precisa de autorização** (o diretório é intocável sem mandato) |
| C2 — Supabase CLI local (`supabase start`, Docker) | sim | sim (Docker/CLI, se não instalados) | depende de autorização de instalação |
| C3 — PGlite (Postgres em WASM, npm) | sim (16.x) | sim (dependência npm; registro bloqueado no sandbox do agente) | não recomendada |
| Supabase Branching | sim | **sim (ambiente novo)** | **excluída** pela governança |
| Transação com ROLLBACK no LIVE | sim | não | **proibida** |

## 2. Roteiro C1 (Fabrício executa; agente prepara e audita a evidência)

1. **Banco descartável:** `createdb -h 127.0.0.1 mmkyu_bpl_validate` na instância PG17 local (nunca o banco da réplica do Batch 12).
2. **Esquema base (só leitura no LIVE):** exportar DDL de `public` e `internal` com o extrator existente, ampliando o filtro de tabelas para o domínio de coleções:
   - `inventory`, `physical_card`, `storage_container`, `storage_container_kind`;
   - `collection*`;
   - `collection_layout*`;
   - catálogo mínimo: `game`, `language`, `expansion`, `card_set`, `card`, `card_variant`, `card_variant_type`, `rarity`, `card_category`, `card_asset*`, `card_printing_profile`, `card_edition_context_profile`.

   Exportar também as funções/gatilhos de `public` e o gatilho que cria `inventory` na inserção em `auth.users`.
3. **Stubs Supabase (local, sem dados):**
   - roles `anon`, `authenticated` e `service_role`;
   - esquema `auth` com `auth.users` (colunas usadas pelo harness);
   - função `auth.uid()` lendo `current_setting('request.jwt.claim.sub', true)::uuid`.

   Mesmo padrão dos stubs do Protocolo A.
4. **Referência mínima:** `game` POKEMON, `language` pt-BR, `card_variant_type` STANDARD, 1 `rarity` e 1 `card_category`, mais 1 card real (o harness cria o restante sinteticamente).
5. **Linha de base:** aplicar as canônicas até 5246 (`database/schema/`) e conferir as funções 5223/5224/5229/5230/5246 por md5 normalizado contra o LIVE (leitura).
6. **Execução, em ordem, com log por passo:**
   1. 5247 → 5255.
   2. Popular um fichário com cenário equivalente ao LIVE: 1 layout, proprietária + convidada, posições e uma carta "Mudkip" de coleção não participante.
   3. Rodar LIVE_00/LIVE_50 adaptados ao banco local.
   4. 5256.
   5. `select * from pg_temp.wh_5854_validate();` — esperado **GATE 53/53 PASS**.
7. **Recuperação (no mesmo banco local):**
   1. Rodar R0.
   2. R1 → conferir.
   3. R2A → conferir que todas as posições continuam (contagem e md5 idênticos).
   4. R2B com uma posição sem coleção presente → **deve abortar em P2 sem mudar nada**.
   5. Retirar a posição pelo fluxo normal → R2B → **deve concluir**, com as 155 posições equivalentes preservadas.
8. **Evidência:** ZIP com logs, saídas, md5 e manifesto (padrão Protocolo A). Depois, `dropdb mmkyu_bpl_validate`.

## 3. O que C1 prova e o que não prova

| Prova | Não prova |
|---|---|
| sintaxe e compilação reais de 5247–5256, R0/R1/R2A/R2B | JWT/PostgREST reais (RLS via `SET ROLE`) |
| comportamento funcional (harness 53 casos) e de recuperação | volume e planos com dados reais do LIVE (réplica parcial) |
| ausência de perda de posições nos rollbacks | concorrência entre sessões (exige duas conexões; pode ser feito à parte no mesmo banco) |
