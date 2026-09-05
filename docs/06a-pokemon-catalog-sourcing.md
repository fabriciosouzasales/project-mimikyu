# Pokémon Catalog Sourcing

| Campo | Valor |
|--------|-------|
| **Documento** | Pokémon Catalog Sourcing |
| **Arquivo** | `docs/06a-pokemon-catalog-sourcing.md` |
| **Versão** | 1.3 |
| **Status** | **`POKEMON CATALOG SOURCING INITIAL LOAD — IMPLEMENTED / LIVE / SECURED / IDEMPOTENT / CLOSED`.** Sourcing real via PokéAPI executado no banco de produção (`qjfutqujxrbzgrtkpgkg`): primeiro DRY_RUN (`RUN-20260905-00000101`, `COMPLETED`, `snapshot_hash = a816dc9e83d733f02ae5aa8b01fa67ca68e4a9f48df96829a8d3e6068e0cba72`) e primeiro APPLY (`RUN-20260905-00000121`, `COMPLETED`, `2071` linhas inseridas: `Regions=11`/`Generations=9`/`Species=1025`/`National Pokédex=1`/`Positions=1025`, mais os 4 xrefs correspondentes) — ambos reais, ambos `COMPLETED`. Hardening de segurança residual (`6111`, REVOKE de `TRUNCATE`/`REFERENCES`/`TRIGGER`/`MAINTAIN` de `service_role` nas 9 tabelas canônicas) **CONFIRMADO EXECUTADO**, validado PASS A-E pela Query `6821` v1.1. Idempotência confirmada por um segundo ciclo real: segundo DRY_RUN (`RUN-20260905-00000141`, mesmo `snapshot_hash`, 100% `UNCHANGED`) e segundo APPLY (`RUN-20260905-00000161`, `0 INSERT` / `0 UPDATE` / `2071 UNCHANGED`). Zero órfãos, zero mismatch, zero duplicidade, `0` active runs. Catálogo sem dependência de PokéAPI em runtime — ver Seção 15.1. Sourcing foundation física (`6090`-`6110`, 13 objetos) permanece `CONFIRMADO EXECUTADO E PROMOVIDO` para `database/schema/`; `6111` também promovido. Próxima frente do projeto: **Collections**, não mais este contrato — ver `docs/ROADMAP.md`/handoff vigente. |
| **Objetivo** | Descrever a estratégia de aquisição, normalização, reconciliação e carga (Initial Load) do Pokémon Catalog a partir da PokéAPI — Regions, Generations, Species e National Pokédex/Positions — e o contrato definitivo do pipeline de sourcing (run lifecycle, PLAN/APPLY, snapshot, hash, segurança, idempotência). |
| **Escopo** | Initial Load do Pokémon Catalog (módulo físico `6000`-`6999`, `ADR-011`). Não cobre o pipeline de importação de cartas/imagens (`06-pipeline-importacao.md`, Edge Function `import-card-assets`, Catálogo Editorial) — domínios, fontes e arquitetura distintas. |
| **Dependências** | `02-architecture-principles.md`, `04-domain-model.md`, `docs/domain-modeling/collections/logical-model.md` (LDM-175–190), `adr/ADR-011-pokemon-tcg-domain-scope.md` (v1.3), `standards/STD-001-database-standards.md` (Seção 10). |
| **Documentos Relacionados** | `docs/05d-colecoes-e-usuarios.md` (seção Pokédex/Pokémon Region), `docs/06-pipeline-importacao.md` (pipeline irmão, domínio Card), `docs/development/HANDOFF-2026-09-04.md`. |

---

# Purpose

Este documento é a fonte canônica do contrato de sourcing do Pokémon Catalog — Regions, Generations, Species e National Pokédex/Positions — a partir da PokéAPI. O contrato foi modelado e fechado em rodadas de chat anteriores (`POKEMON-CATALOG-SOURCING-INITIAL-LOAD-MODELING-AUDIT-01`), mas nunca havia sido persistido como artefato do repositório. Este documento fecha essa lacuna: reconstrói (`POKEMON-CATALOG-SOURCING-CONTRACT-RECONSTRUCTION-01`), audita contra o HEAD físico real (zero contradição encontrada) e canonicaliza (`POKEMON-CATALOG-SOURCING-CONTRACT-CANONICALIZATION-01`) o contrato completo, incorporando a Pokémon Region Foundation (já `CLOSED / COMMITTED / PUSHED`).

Este documento registra apenas o contrato fechado — não é um changelog de tentativas/hipóteses descartadas.

---

# 1. Escopo do Initial Load

Ordem canônica de carga:

```text
Regions
  → Generations + Main Region
    → Species
      → National Pokédex
        → National Pokédex Positions
```

Fora deste Initial Load: Forms/Varieties, Locations, Areas, Version Groups, Pokédex regionais (não-nacional). `Pokémon Catalog Sourcing` cobre exclusivamente as cinco famílias acima.

---

# 2. PokéAPI Acquisition Source / MMKYU Runtime Authority

A PokéAPI é fonte de **aquisição** — nunca autoridade em tempo de execução. Depois do Initial Load, o Project Mimikyu (MMKYU) é a autoridade canônica; nenhuma rota/RPC de runtime depende de chamada à PokéAPI. O mesmo princípio já aplicado ao pipeline de cartas (`06-pipeline-importacao.md`, "Padrão Geral") — nenhuma fonte externa é proprietária lógica do catálogo.

---

# 3. Discovery

- **Region**: `/region/` — importar TODAS as Regions descobertas, nunca assumir cardinalidade fixa (nunca hardcodar "11 Regions" como regra de negócio).
- **Generation**: descoberta pela coleção/list URLs da própria API — nunca construir range `1..count`.
- **Species**: `/pokemon-species/` paginado é discovery autoritativo; usar as URLs/IDs retornados; buscar o detail de TODAS as Species descobertas. Nunca hardcodar "1025 Species".
- **National Pokédex**: `/pokedex/national` é autoridade para positions; `pokemon_entries[].entry_number` define `position_number`.

---

# 4. Normalização

## 4.0 `canonical_name` — regra comum a Region/Generation/Species/National Pokédex

Para as quatro famílias abaixo, `canonical_name` vem **exclusivamente** de `names[]` onde `language.name = 'en'` (ex.: `names[].find(n => n.language.name === 'en').name`). Valor vazio ou ausente → **VALIDATION FAILURE**, impede DRY_RUN `COMPLETED`. Nunca fallback silencioso para o `name`/slug estruturado do recurso (esse serve apenas para derivar `code`, nunca `canonical_name`).

## 4.1 Region

- `external_region_id` = ID numérico da PokéAPI, serializado TEXT (nunca o slug/name).
- `code` = structured slug normalizado (`kanto` → `KANTO`).
- `canonical_name` = `names[]` onde `language.name = 'en'` — ver 4.0.
- External reference própria (`pokemon_region_external_reference`, já física — Query `6070`).
- `main_generation` **não é persistido** em `pokemon_region`.

## 4.2 Generation

- `external_generation_id` separado da identidade interna MMKYU (UUID) — identidade própria da PokéAPI, persistida em `pokemon_generation_external_reference` (Seção 15).
- `code` de structured slug: `generation-i` → `GENERATION_I`.
- `ordinal_number` derivado estritamente do numeral romano do slug — nunca do id da PokéAPI.
- `canonical_name` = `names[]` onde `language.name = 'en'` (ex.: `Generation I`) — ver 4.0. Nunca o nome da Region (ex.: nunca `Kanto`).
- `main_region_id` resolvido exclusivamente pela identidade externa da Region — via `pokemon_region_external_reference` (já existente, Query `6070`), usando `main_region_external_id` do snapshot — nunca por `canonical_name`. **Não depende de `pokemon_generation_external_reference`** (ver Seção 15, correção de escopo).
- Slug inválido ou Region não resolvida → FAIL/DIVERGENT, nunca inferência silenciosa.

## 4.3 Species

Autoridade de identidade e numeração (fechada, não reabrir):

- `external_species_id` = `pokemon-species.id` da PokéAPI. Uso **exclusivo**: identidade externa da Species (`pokemon_species_external_reference`). Nunca usado como número, cross-check ou qualquer outra função relacionada a `national_dex_number`.
- `national_dex_number` — autoridade é `/pokedex/national.pokemon_entries[].entry_number`, **nunca** derivado do `external_species_id`. **Nunca** exigir/comparar `external_species_id = national_dex_number` — são identidades independentes, sem relação numérica esperada.
- **Cross-check nacional — OBRIGATÓRIO (não opcional).** Para **cada** Species descoberta em `/pokemon-species/`, `PokemonSpecies.pokedex_numbers[]` deve conter **exatamente uma** entrada onde `pokedex.name = 'national'`. O `entry_number` dessa entrada deve ser **idêntico** ao `entry_number` correspondente em `/pokedex/national.pokemon_entries[]` (autoridade), para **100% das Species**. Qualquer um dos casos abaixo é **VALIDATION FAILURE**, sem PLAN/APPLY:
  - entrada `national` ausente em `pokedex_numbers[]` para alguma Species;
  - entrada `national` duplicada (mais de uma) para a mesma Species;
  - `entry_number` divergente entre `pokedex_numbers[national]` e a autoridade (`/pokedex/national.pokemon_entries[].entry_number`);
  - Species presente em apenas um dos dois conjuntos (`/pokemon-species/` e `/pokedex/national`) — não pertence a ambos.
- `canonical_name` = `names[]` onde `language.name = 'en'` — ver 4.0.
- `generation_id` resolvido pela identidade externa da Generation (`generation_external_id`, via `pokemon_generation_external_reference` — Seção 15).
- Igualdade exata entre a lista descoberta (S) e o conjunto efetivamente normalizado (P): **S = P** — os `external_species_id` descobertos em `/pokemon-species/` devem coincidir exatamente com os descobertos em `/pokedex/national` (nenhum a mais, nenhum a menos). Ausência, duplicidade ou Species não resolvida impede APPLY.

## 4.4 National Pokédex

- `external_pokedex_id` = `"1"` (nunca o slug `national`).
- Structured source name esperado: `national`.
- MMKYU `code` = `NATIONAL`.
- `canonical_name` = `names[]` onde `language.name = 'en'` — ver 4.0.
- Entries: `external_species_id` + `position_number`. `position_number` usa a **mesma** autoridade de 4.3 — `pokemon_entries[].entry_number` — e é o valor que também define `national_dex_number` da Species correspondente (uma única autoridade, duas colunas de destino: `pokemon_species.national_dex_number` e `pokedex_position.position_number`).

---

# 5. Snapshot

Determinístico — mesmo estado externo produz sempre o mesmo `snapshot_hash`. Ordenação exata, aplicada antes do cálculo do hash:

- `regions`: `numeric(external_region_id) ASC`.
- `generations`: `numeric(external_generation_id) ASC`.
- `species`: `numeric(external_species_id) ASC`.
- `national_pokedex_entries`: `position_number ASC`, com `numeric(external_species_id) ASC` como tie-breaker.

`metadata` (em qualquer família) deve ser sanitizado (sem campos voláteis/não determinísticos da resposta da PokéAPI, ex.: nunca incluir timestamps de request) e deterministicamente serializável — mesmas chaves, mesma ordem de chaves, mesmos valores para o mesmo estado externo.

```json
{
  "regions": [
    {
      "external_region_id": "1",
      "code": "KANTO",
      "canonical_name": "Kanto",
      "source_url": "https://pokeapi.co/api/v2/region/1/",
      "metadata": {}
    }
  ],
  "generations": [
    {
      "external_generation_id": "1",
      "code": "GENERATION_I",
      "canonical_name": "Generation I",
      "ordinal_number": 1,
      "main_region_external_id": "1",
      "source_url": "https://pokeapi.co/api/v2/generation/1/",
      "metadata": {}
    }
  ],
  "species": [
    {
      "external_species_id": "1",
      "national_dex_number": 1,
      "canonical_name": "Bulbasaur",
      "generation_external_id": "1",
      "source_url": "https://pokeapi.co/api/v2/pokemon-species/1/",
      "metadata": {}
    }
  ],
  "national_pokedex": {
    "external_pokedex_id": "1",
    "code": "NATIONAL",
    "canonical_name": "National",
    "source_url": "https://pokeapi.co/api/v2/pokedex/1/",
    "metadata": {}
  },
  "national_pokedex_entries": [
    {
      "external_species_id": "1",
      "position_number": 1
    }
  ]
}
```

## 5.1 Payload guard

Proteção técnica, **não** cardinalidade de negócio:

```text
regions.length
  + generations.length
  + species.length
  + national_pokedex_entries.length
  + 1                          -- representa national_pokedex
  <= 25000
```

---

# 6. Hash

Um único helper no banco é autoridade para o hash — `TEXT`, lowercase, exatamente 64 caracteres hex:

```sql
encode(
  pg_catalog.sha256(
    pg_catalog.convert_to(p_snapshot::text, 'UTF8')
  ),
  'hex'
)
```

- CHECK, quando `snapshot_hash` não NULL: `^[0-9a-f]{64}$`.
- Preflight `COMPLETED` com hash NULL é inválido.
- Comparações de hash que precisam detectar NULL usam `IS DISTINCT FROM`, nunca apenas `<>`.

---

# 7. Run Lifecycle

`pokemon_catalog_sourcing_run` — contrato mínimo fechado:

- `id UUID PK`
- `run_code TEXT NOT NULL UNIQUE` — **decisão fechada** (não deixada para GATE 3): mesmo precedente físico já usado por `asset_import_run` (Query `220`, `CONFIRMADO EXECUTADO`) — sequência dedicada + `DEFAULT` server-side, formato `RUN-YYYYMMDD-NNNNNNNN`, `CHECK (run_code ~ '^RUN-[0-9]{8}-[0-9]{8,}$')`. O caller nunca constrói `run_code` — o valor vem exclusivamente do `DEFAULT`.
- `asset_source_id FK` → `asset_source` (linha `POKEAPI`, já física via Query `6700`, `is_active = TRUE`).
- `run_type` — `DRY_RUN` | `APPLY`.
- `preflight_run_id` — self-FK. `NULL` para `DRY_RUN`; `NOT NULL` para `APPLY`.
- `status` — `PENDING`, `ACQUIRING`, `PLANNING`, `APPLYING`, `COMPLETED`, `COMPLETED_WITH_DIVERGENCES`, `FAILED`, `CANCELLED`.
- `snapshot_hash`, `plan_summary JSONB`, `apply_summary JSONB`, `error_summary`, `heartbeat_at`, `started_at`, `finished_at`, `created_at`/`updated_at`. Quando `plan_summary`/`apply_summary` não são NULL, `jsonb_typeof(plan_summary) = 'object'` e `jsonb_typeof(apply_summary) = 'object'` — mesmo padrão já usado em `parameters`/`metadata` no restante do repositório.
- Unique partial: no máximo um run ativo por `asset_source_id`.

## 7.1 Status sets e fluxos fechados

**ACTIVE** — conjunto exato usado pela UNIQUE parcial de run ativo:

```text
PENDING, ACQUIRING, PLANNING, APPLYING
```

**TERMINAL** — exige `finished_at NOT NULL`:

```text
COMPLETED, COMPLETED_WITH_DIVERGENCES, FAILED, CANCELLED
```

Fluxo `DRY_RUN`:

```text
PENDING → ACQUIRING → PLANNING → COMPLETED | COMPLETED_WITH_DIVERGENCES
```

Fluxo `APPLY`:

```text
PENDING → APPLYING → COMPLETED
```

`APPLY` nunca entra em `ACQUIRING`, `PLANNING` ou `COMPLETED_WITH_DIVERGENCES` — não há aquisição/PLAN dentro de um run `APPLY` (o snapshot já vem aprovado do preflight). `FAILED`/`CANCELLED` são saídas terminais de falha/cancelamento, alcançáveis a partir de qualquer estado ACTIVE de ambos os fluxos.

Preflight aceitável para `APPLY`: **somente** `DRY_RUN` em `COMPLETED`. `COMPLETED_WITH_DIVERGENCES` **não** é preflight válido — um `DRY_RUN` com divergências precisa de novo ciclo (correção/reconciliação administrativa) antes de qualquer `APPLY`. Todo `DRY_RUN` terminado em `COMPLETED` **ou** `COMPLETED_WITH_DIVERGENCES` deve possuir `snapshot_hash NOT NULL` (o hash é calculado antes do PLAN, independente do resultado da reconciliação — ver Seção 8).

## 7.2 Open Run

`open_pokemon_catalog_sourcing_run(...)` — antes do `INSERT`: valida `asset_source` `POKEAPI` ativa, valida `run_type`, para `APPLY` valida preflight obrigatório e compatível.

- Stale recovery: threshold fixo server-side de **30 minutos**. Run ativo órfão/stale deve ser reconciliado antes do novo claim.
- Hard guard: unique partial. Corrida de absent-row: capturar `unique_violation` e retornar `SOURCE_BUSY` — nunca improvisar lock alternativo.

---

# 8. DRY_RUN / Preflight / APPLY

```text
DRY_RUN:
  Discovery → Acquire → Normalize → Validate
    → ordenar snapshot → hash → PLAN
    → salvar snapshot local sanitizado

APPLY:
  exige preflight (DRY_RUN COMPLETED)
    → reutiliza EXATAMENTE o snapshot aprovado
    → ZERO novos GETs à PokéAPI
    → não redescobre dados, não gera novo snapshot
```

---

# 9. PLAN / Reconciliation

## 9.1 PLAN

`SECURITY DEFINER`, `SET search_path = ''`, `SERVICE_ROLE ONLY` (ver Seção 13). Lê o catálogo fechado internamente. **Zero escrita canônica.** A `asset_source` é obtida pelo run, nunca confiada ao payload. Retorna summary por família: `new` / `update_name` / `unchanged` / `divergent`. `DRY_RUN` com divergências pode terminar `COMPLETED_WITH_DIVERGENCES`.

## 9.2 Regra geral de identidade

`NEW` somente quando a identidade externa não existe **e** nenhuma natural key canônica conflitante já está ocupada. Se a external reference estiver ausente mas a natural key já pertencer a uma entidade local → `DIVERGENT`. Nunca auto-bind.

## 9.3 Reconciliation matrix

Natural key por família — a coluna (ou conjunto de colunas) canônica usada para detectar ocupação prévia quando a identidade externa está ausente:

- `regions`: natural key = `code`.
- `generations`: natural key = `code` **e** `ordinal_number` (ambos, não intercambiáveis — ver Seção 4.2).
- `species`: natural key = `national_dex_number`.
- `pokedex` (National): natural key = `code` (valor fixo `NATIONAL`, Seção 4.4).

Regra fechada, sem exceção por família: identidade externa ausente **e** a natural key correspondente já ocupada por uma entidade local incompatível ⇒ `DIVERGENT`. Nunca auto-bind — nenhuma família resolve esse caso automaticamente vinculando a external reference à entidade existente.

| Família | NEW | UNCHANGED | UPDATE_NAME | DIVERGENT |
|---|---|---|---|---|
| `regions` | external id ausente **e** `code` livre (natural key não ocupada) | tudo igual | só `canonical_name` muda | `code` (natural key) ocupado por region local sem external reference compatível |
| `generations` | external id ausente **e** `code`+`ordinal_number` (natural key) livres | tudo igual | só `canonical_name` muda | `code`/`ordinal_number` (natural key) ocupados por generation local incompatível; ou `main_region_id` já setado mudaria (nunca auto-bind); slug romano inválido |
| `species` | external id ausente **e** `national_dex_number` (natural key) livre | tudo igual | correção de nome que não mexe em identidade/national dex/generation | `national_dex_number` (natural key) ocupado por species local incompatível; ou mudança estrutural (national dex/generation) — nunca overwrite automático |
| `pokedex` (National) | external id ausente **e** `code = 'NATIONAL'` (natural key) livre | tudo igual | `canonical_name` | `code` (natural key) ocupado por pokedex local incompatível; ou qualquer inconsistência estrutural |
| `positions` | ver 9.4 | ver 9.4 | sempre 0 | ver 9.4 |

## 9.4 Positions — reconciliation fechada

O schema físico (`pokedex_position`, Query `6040`) possui `UNIQUE(pokedex_id, species_id)` e `UNIQUE(pokedex_id, position_number)`. Para cada entry do snapshot:

- **NEW**: não existe row para a Species naquele Pokédex **e** o `position_number` também está livre.
- **UNCHANGED**: a mesma row corresponde simultaneamente à Species e ao `position_number`.
- **DIVERGENT**: a Species já existe no Pokédex com outro `position_number`, **ou** o `position_number` já pertence a outra Species, **ou** qualquer estado inconsistente entre os dois eixos.
- **UPDATE_NAME**: sempre 0 para Positions — não há campo de nome em `pokedex_position`.

O sourcing **não** atualiza `position_number` automaticamente. `position_number` permanece administrativamente corrigível fora do fluxo de sourcing (mesmo tratamento editorial já documentado em `pokedex_position`, Query `6040`).

---

# 10. APPLY

`apply_pokemon_catalog_sourcing_run(p_run_id UUID, p_snapshot JSONB)` — `SECURITY DEFINER`, `SET search_path = ''`.

Antes de qualquer escrita, validar no banco: run existe; `run_type = APPLY`; status compatível; `preflight_run_id` existe; preflight é `DRY_RUN`; preflight `COMPLETED`; mesma `asset_source`; `asset_source` `POKEAPI` ativa; `preflight.snapshot_hash` não NULL; hash do snapshot recebido corresponde exatamente ao hash aprovado (`IS DISTINCT FROM`); fresh reconciliation sem divergências. Divergência detectada → `RAISE EXCEPTION` antes de qualquer commit canônico.

## 10.1 Atomicidade

Escrita canônica atômica, uma única transação lógica, ordem exata:

```text
Regions
  → Region External References
    → Generations + Main Region
      → Generation External References
        → Species
          → Species External References
            → National Pokédex
              → Pokédex External Reference
                → Positions
```

Se qualquer etapa falhar: `ROLLBACK` de TODA a escrita canônica daquele APPLY. Run closeout/erro é tratado fora da transação canônica quando necessário, para que a falha permaneça observável.

Summary por família: `inserted` / `updated` / `unchanged`.

---

# 11. Idempotência

Primeiro APPLY válido: insere/atualiza conforme PLAN. Segundo `DRY_RUN`/APPLY do mesmo estado externo: zero `NEW`, zero `UPDATE_NAME`, zero `DIVERGENT`, tudo `UNCHANGED`, zero duplicação, mesmos external mappings.

---

# 12. HTTP / Fair Use

Aquisição: concorrência default `5`, configurável entre `1..10`; retries limitados; timeout limitado; retry de `429`/`5xx` respeitando `Retry-After`; cache/reuso local; redução de frequência conforme Fair Use da PokéAPI.

---

# 13. Segurança

As tabelas canônicas Pokémon/Pokédex permanecem fechadas — `service_role` **não** recebe DML direto nelas (confirmado fisicamente: zero privilégio efetivo via `has_table_privilege()` em todas as 8 tabelas do módulo). O acesso do sourcing às tabelas fechadas ocorre exclusivamente pelas RPCs `SECURITY DEFINER` explicitamente controladas.

**`SERVICE_ROLE ONLY`** — decisão fechada, sem ambiguidade de "papel administrativo apropriado": as RPCs de sourcing (`open_pokemon_catalog_sourcing_run(...)`, PLAN, APPLY, e qualquer helper operacional exposto ao caller) concedem `EXECUTE` **exclusivamente** a `service_role`. `PUBLIC`/`anon`/`authenticated` **sem `EXECUTE`** em nenhuma delas — nesta versão do contrato, nenhum `authenticated` administrativo chama sourcing diretamente; o caller é sempre o script Deno standalone (Seção 15) autenticado como `service_role`.

Funções que acessam o catálogo fechado (PLAN/APPLY e qualquer helper que leia/escreva `pokemon_*`/`pokedex_*`): `SECURITY DEFINER` + `SET search_path = ''`, mesmo padrão já usado em toda a base (`internal.write_card`, `admin_create_game`, etc.).

Helpers internos não destinados a ser chamados diretamente pelo caller (ex.: sub-rotinas de reconciliação usadas apenas dentro de PLAN/APPLY): **não** recebem `EXECUTE` de `service_role` sem necessidade — só o entrypoint real (`open_...`, PLAN, APPLY) precisa do grant.

O run ledger (`pokemon_catalog_sourcing_run`) pode possuir grants próprios mínimos, separados do catálogo canônico, mas segue o mesmo princípio `SERVICE_ROLE ONLY` — `PUBLIC`/`anon`/`authenticated` sem acesso direto à tabela.

**Internal writers** (`internal.write_pokemon_species()`, `internal.write_pokemon_generation()`): decisão fechada — não são criados especulativamente. O futuro APPLY `SECURITY DEFINER` é o canal controlado do sourcing. Só se justificam se uma implementação real demonstrar necessidade concreta de um segundo canal de escrita convergente (mesmo critério já usado em `6010`/`6020` para adiar `internal.write_pokemon_species()`) — não é um risco em aberto, é uma decisão deliberada de não antecipar.

---

# 14. Critérios PASS do Initial Load

Dinâmicos — nunca números fixos:

- 100% das Regions descobertas reconciliadas.
- 100% das Generations descobertas reconciliadas.
- 100% das Species descobertas reconciliadas; `S = P` exato.
- **Cross-check nacional 100% PASS**: para 100% das Species, `pokedex_numbers[national].entry_number` = `/pokedex/national.pokemon_entries[].entry_number` (ver 4.3) — entrada `national` presente, única e coincidente, sem exceção.
- 100% das `Generation.main_region` resolvidas.
- National Pokédex resolvida; 100% das entries resolvidas para Species; positions completas segundo o snapshot.
- Zero divergência; zero external identity duplicada.
- Segundo DRY_RUN/APPLY idempotente (100% `UNCHANGED`).
- Zero resíduo de run/fixture inválido.
- Segurança preservada (consistente com a Seção 13 — `SERVICE_ROLE ONLY`):
  - Tabelas canônicas `pokemon_*`/`pokedex_*`: `service_role` sem DML direto.
  - Toda escrita/leitura privilegiada do catálogo canônico ocorre somente pelas RPCs `SECURITY DEFINER` autorizadas (PLAN/APPLY/helpers de entrypoint).
  - `pokemon_catalog_sourcing_run`: `service_role` pode possuir **somente** grants mínimos explicitamente definidos e auditados no `GATE 3 STAGING` — nunca acesso irrestrito.
  - `PUBLIC`/`anon`/`authenticated` sem acesso direto ao run ledger (`pokemon_catalog_sourcing_run`).
  - `PUBLIC`/`anon`/`authenticated` sem `EXECUTE` nas RPCs de sourcing.

---

# 15. Objetos físicos (CONFIRMADO EXECUTADO E PROMOVIDO — 2026-09-04)

Todos os objetos abaixo foram criados, aplicados ao banco real e promovidos
para `database/schema/` (corpo SQL idêntico ao aplicado; apenas cabeçalho
Status/Data atualizado na promoção). Numeração efetivamente usada (contra
`database/schema/` real, 6000-6999):

| Query | Objeto | Status |
|---|---|---|
| `6090`/`6091` | `pokemon_generation_external_reference` (tabela/triggers) — identidade externa própria da Generation; resolve `species[].generation_external_id → pokemon_generation.id` (Seção 4.3). Não resolve `main_region_external_id` (já coberto por `6070`). | CONFIRMADO EXECUTADO |
| `6100`/`6101` | `pokemon_catalog_sourcing_run` (tabela + sequência de `run_code`) e seus triggers (máquina de estados `run_type`-aware) | CONFIRMADO EXECUTADO |
| `6102` | `compute_pokemon_catalog_sourcing_snapshot_hash()` (hash helper) | CONFIRMADO EXECUTADO |
| `6103` | `open_pokemon_catalog_sourcing_run(...)` | CONFIRMADO EXECUTADO |
| `6104` | RPC de PLAN | CONFIRMADO EXECUTADO |
| `6105` | RPC de APPLY | CONFIRMADO EXECUTADO |
| `6106` | `reconcile_pokemon_catalog_sourcing_snapshot()` (auxiliar, usado por PLAN e APPLY) | CONFIRMADO EXECUTADO |
| `6107` | `heartbeat_pokemon_catalog_sourcing_run()` (auxiliar) | CONFIRMADO EXECUTADO |
| `6108` | `close_failed_pokemon_catalog_sourcing_run()` (auxiliar) | CONFIRMADO EXECUTADO |
| `6109` | hotfix runtime: `RETURNING` ambíguo de `run_code` em `open_pokemon_catalog_sourcing_run` (erro real `42702`, migration incremental própria — não reescreve `6103`) | CONFIRMADO EXECUTADO |
| `6110` | hotfix temporal: `finished_at = NOW()` → `CLOCK_TIMESTAMP()` em `plan`/`apply`/`close_failed` (erro real `23514` em `ck_..._run_period`, migration incremental própria — não reescreve `6104`/`6105`/`6108`) | CONFIRMADO EXECUTADO |
| `6820` | script de validação (`BEGIN...ROLLBACK`, 16 Seções) — permanece em `database/proposals/`, mesmo padrão de não promoção de `6800`/`6810` | CONFIRMADO EXECUTADO — resultado PASS |
| `6111` | hardening de segurança residual: `REVOKE TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ... FROM service_role` nas 9 tabelas canônicas (achado pós-APPLY real — o default ACL de `postgres` para `public` concede esses 4 privilégios estruturais a `service_role` em toda tabela nova, independente do REVOKE explícito já aplicado a `anon`/`authenticated`) | CONFIRMADO EXECUTADO |
| `6821` | script de validação do hardening (`BEGIN...ROLLBACK`, 5 Seções A-E) — permanece em `database/proposals/2026-09-05-pokemon-catalog-sourcing-security-hardening/`, mesmo padrão de não promoção de `6800`/`6810`/`6820` | CONFIRMADO EXECUTADO — resultado PASS |

Residual conhecido, não corrigido por instrução explícita: `open_pokemon_catalog_sourcing_run`
(`6103`/`6109`) mantém `finished_at = NOW()` no passo de stale recovery.
Classificação: **KNOWN / ACCEPTED / NON-BLOCKING**.

Ferramenta administrativa: script Deno standalone (fora do banco, `scripts/run-pokemon-catalog-sourcing.ts` + `supabase/functions/_shared/pokemon-catalog-sourcing/`). `APPLY` não faz HTTP. Cache local sanitizado e determinístico. Nunca logar `service key`, headers sensíveis ou payload secreto.

---

# 15.1 Initial Load — CONFIRMADO EXECUTADO (2026-09-05)

A carga real via PokéAPI foi executada no banco de produção (`qjfutqujxrbzgrtkpgkg`), fechando o Initial Load descrito neste contrato.

**Primeiro ciclo (carga inicial):**

- DRY_RUN `RUN-20260905-00000101` — `COMPLETED`, `snapshot_hash = a816dc9e83d733f02ae5aa8b01fa67ca68e4a9f48df96829a8d3e6068e0cba72`.
- APPLY `RUN-20260905-00000121` — `COMPLETED`, `apply_summary`: `regions.inserted=11`, `generations.inserted=9`, `species.inserted=1025`, `pokedex.inserted=1`, `positions.inserted=1025` (`updated=0`/`unchanged=0` em todas as famílias) — `2071` linhas no total, mais os 4 xrefs correspondentes (`pokemon_region_external_reference=11`, `pokemon_generation_external_reference=9`, `pokemon_species_external_reference=1025`, `pokedex_external_reference=1`).

**Hardening de segurança residual (mesmo dia):** achado pós-APPLY — `service_role` sem SELECT/INSERT/UPDATE/DELETE nas 9 tabelas canônicas (correto), mas ainda com `TRUNCATE`/`REFERENCES`/`TRIGGER`/`MAINTAIN` (herança do default ACL de `postgres` para `public`, não coberta pelo padrão histórico de REVOKE que visava apenas `anon`/`authenticated`). Corrigido pela Query `6111` (REVOKE atômico, escopo restrito às 9 tabelas, sem alterar o default ACL global nem qualquer outro domínio) e validado PASS pela Query `6821` v1.1 (Seções A-E: zero privilégio estrutural remanescente de `service_role`; as 5 RPCs mantêm `service_role EXECUTE=true`/`PUBLIC`+`anon`+`authenticated EXECUTE=false`, PUBLIC provado via `aclexplode`/`grantee=0`; contagens preservadas; os dois runs `COMPLETED`, `0` active runs; RLS/policies/triggers habilitados/`search_path` das RPCs inalterados).

**Segundo ciclo (prova de idempotência, mesmo estado externo):**

- DRY_RUN `RUN-20260905-00000141` — `COMPLETED`, mesmo `snapshot_hash` do primeiro DRY_RUN (`a816dc9e83d733f02ae5aa8b01fa67ca68e4a9f48df96829a8d3e6068e0cba72`) — 100% `UNCHANGED`, confirmando que o estado externo da PokéAPI não mudou entre os dois ciclos.
- APPLY `RUN-20260905-00000161` — `COMPLETED`, `apply_summary`: `0 inserted` / `0 updated` / `2071 unchanged` em todas as famílias (`regions=11`, `generations=9`, `species=1025`, `pokedex=1`, `positions=1025`) — critério de idempotência da Seção 11 confirmado por execução real, não apenas pelo contrato.

**Integridade pós-carga (verificação read-only):** zero duplicidade (`national_dex_number` único por Species; `(pokedex_id, position_number)` e `(pokedex_id, species_id)` únicos em `pokedex_position`), zero órfão (toda Species referencia uma Generation existente; toda Position referencia uma Species e um Pokédex existentes; todo xref referencia sua entidade-mãe existente), `0` active runs (`4` runs no total, todos `COMPLETED`).

Catálogo sem dependência de PokéAPI em runtime (Seção 2) — as leituras do MMKYU após o Initial Load nunca chamam a PokéAPI; ela permanece exclusivamente fonte de aquisição do sourcing.

Próxima frente do projeto **não é mais** este contrato — ver `docs/ROADMAP.md`/handoff vigente para a retomada de Collections (Pokédex Position Assignment/Primary Representative e Fatias B/C/D/E permanecem `PHYSICALLY NOT STARTED`, fora do escopo deste Initial Load).

---

# 16. Fora de escopo (decisão explícita)

- Forms/Varieties.
- Locations, Areas, Version Groups, grafo de navegação entre Regiões.
- Pokédex regionais (não-nacional).
- Pokédex Position Assignment, Primary Representative, Card → Primary Species (Fatias B/C/D/E do Pokédex — `LDM-175`–`185`).
- Qualquer dependência runtime da PokéAPI.
- `internal.write_pokemon_species()`/`internal.write_pokemon_generation()` especulativos (ver Seção 13).
- Decomposição fina exata das RPCs de PLAN/APPLY (quantas funções, nomes definitivos) — trabalho de GATE 3 STAGING, não deste contrato.

---

# Revision History

| Versão | Descrição |
|---------|-----------|
| 1.0 | **Criação deste documento (2026-09-04), `POKEMON-CATALOG-SOURCING-CONTRACT-CANONICALIZATION-01`.** Persiste como fonte canônica o contrato de Pokémon Catalog Sourcing fechado em rodadas de chat anteriores (`POKEMON-CATALOG-SOURCING-INITIAL-LOAD-MODELING-AUDIT-01`, nunca antes persistido), reconstruído e auditado contra o HEAD físico real sem nenhuma contradição encontrada (`POKEMON-CATALOG-SOURCING-CONTRACT-RECONSTRUCTION-01`), incorporando a Pokémon Region Foundation já `CLOSED / COMMITTED / PUSHED`. Decisões fechadas nesta canonicalização: formato de `run_code` (`RUN-YYYYMMDD-NNNNNNNN`, precedente `asset_import_run`); reconciliation matrix completa de Positions; fórmula exata do payload guard; `internal.write_pokemon_species()`/`internal.write_pokemon_generation()` confirmados como não-risco (não antecipados). Mantida como versão única durante três rodadas de auditoria/revisão do contrato (`REVISION-01`/`02`/`03`, mesmo dia) por instrução explícita — arquivo ainda não commitado. Nenhum objeto físico criado — `AWAITING COMMIT`, `GATE 3 STAGING` é o próximo gate autorizável. |
| 1.1 | **Reconciliação pós-commit (2026-09-04), `POKEMON-CATALOG-SOURCING-CONTRACT-POST-COMMIT-CLOSEOUT-01`.** Commit/push documental confirmado no remote (`0e032cbcc2b903a4859838acc98e069f9543588d`, `docs(collections): canonicalize pokemon catalog sourcing contract`) — inclui o conteúdo v1.0 já corrigido pelas três rodadas de revisão (`REVISION-01`/`02`/`03`). Apenas status atualizado: `CANONICALIZED / AUDITED / COMMITTED / PUSHED`; próximo gate `GATE 3 — POKEMON CATALOG SOURCING STAGING`. Nenhuma alteração ao contrato técnico. |
| 1.2 | **Reconciliação pós-implementação (2026-09-04), `POKEMON-CATALOG-SOURCING-GATE-9-PROMOTION-RECONCILIATION-01`.** Sourcing foundation física implementada: `6090`-`6110` (13 objetos) CONFIRMADO EXECUTADO no banco real e promovidos para `database/schema/` (`GATE-5-IMPLEMENTATION-01`, `GATE-5-HOTFIX-6109-IMPLEMENTATION-01`, `GATE-5-HOTFIX-6110-IMPLEMENTATION-01`, `GATE-9-PROMOTION-RECONCILIATION-01`). `6109` = hotfix runtime do `RETURNING` ambíguo de `run_code` em `open_pokemon_catalog_sourcing_run` (erro real `42702`). `6110` = hotfix temporal `NOW()`→`CLOCK_TIMESTAMP()` em `plan`/`apply`/`close_failed` (erro real `23514`, `ck_..._run_period`). Script de validação `6820` v2.3 executado integralmente com **PASS** (16 Seções, zero resíduo) — permanece em `database/proposals/` como evidência histórica, não promovido. Zero resíduo confirmado pós-validação; advisors de segurança/performance sem novo bloqueador atribuível a `6090`-`6110`. Residual conhecido, não corrigido: `open_pokemon_catalog_sourcing_run` mantém `NOW()` no stale recovery — `KNOWN / ACCEPTED / NON-BLOCKING`. **Sourcing real via PokéAPI ainda NÃO executado.** Seção 15 reescrita para refletir objetos físicos existentes (era "futuros/GATE 3 STAGING"). Ver `docs/log.md` e `database/proposals/2026-09-04-pokemon-catalog-sourcing/README.md`. |
| 1.3 | **`POKEMON CATALOG SOURCING INITIAL LOAD — IMPLEMENTED / LIVE / SECURED / IDEMPOTENT / CLOSED` (2026-09-05), `POKEMON-CATALOG-SOURCING-INITIAL-LOAD-FINAL-REPOSITORY-RECONCILIATION-01`.** Sourcing real via PokéAPI executado no banco de produção: primeiro DRY_RUN (`RUN-20260905-00000101`) e primeiro APPLY (`RUN-20260905-00000121`), ambos `COMPLETED` (`2071` linhas: `Regions=11`/`Generations=9`/`Species=1025`/`Pokédex=1`/`Positions=1025`, mais os 4 xrefs). Achado de segurança residual pós-APPLY (`service_role` com `TRUNCATE`/`REFERENCES`/`TRIGGER`/`MAINTAIN` remanescentes por herança do default ACL de `postgres`) corrigido pela Query `6111` (REVOKE atômico, escopo restrito às 9 tabelas) — **CONFIRMADO EXECUTADO**, validado PASS A-E pela Query `6821` v1.1 (corrigida antes da execução: PUBLIC provado via `aclexplode`/`grantee=0` em vez de `has_function_privilege('public', ...)`, assinaturas exatas via `regprocedure`, active-run set canônico `PENDING`/`ACQUIRING`/`PLANNING`/`APPLYING`, `search_path` exato `search_path=""`, `tgenabled<>'D'`). Idempotência confirmada por segundo ciclo real: DRY_RUN `RUN-20260905-00000141` (mesmo `snapshot_hash`, 100% `UNCHANGED`) e APPLY `RUN-20260905-00000161` (`0 INSERT`/`0 UPDATE`/`2071 UNCHANGED`). Nova Seção 15.1 com a evidência completa; `6111`/`6821` adicionados à tabela da Seção 15 (`6111` promovido para `database/schema/`; `6821` permanece em `database/proposals/`, mesmo padrão de `6800`/`6810`/`6820`). `.pokemon-catalog-sourcing-snapshots/` adicionado ao `.gitignore` (artefato operacional local). Executor Deno (`scripts/run-pokemon-catalog-sourcing.ts`, `supabase/functions/_shared/pokemon-catalog-sourcing/`) incorporado ao repositório sem alteração funcional. **Próxima frente do projeto: Collections, não mais este contrato.** Nenhum commit/push realizado nesta reconciliação. Ver `docs/README.md`, `docs/ROADMAP.md`, `docs/INDEX.md`, handoff vigente e `docs/log.md`. |
