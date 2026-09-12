# Card Variants — Modelo de Impressão (PRINTING) — Gate A

| Campo | Valor |
|---|---|
| **Mandato** | `PRINTING-MODEL-STAGING-01 — GATE-A-01` + `GATE-A-CORRECTION-01` + `GATE-A-EXECUTION-01` + `HARNESS-CORRECTION-01` + **`PROMOTION-CLOSEOUT-PREP-01`** |
| **Decisão** | `HYBRID-PRINTING-MODEL — MODELING-GATE-A-01` — **Modelo C2 ratificado** |
| **Data** | 2026-09-12 |
| **Status** | **EXECUTED / VALIDATED — READY FOR PROMOTION** |
| **Escopo** | Só a fundação: vocabulário, coluna, unicidade, guards. |
| **Fora de escopo** | routing semântico · printing external mapping · `import-card-variants` · RPCs · as 505 rows · BASE1 · defaults · UI |

---

## Estado

**`2165`–`2171` executadas no LIVE** (projeto `qjfutqujxrbzgrtkpgkg`), via `apply_migration`, na ordem `2165 → 2171`, todas sem erro. **`2823` v1.2: 12 PASS / 0 FAIL / 0 NOT PROVEN, zero resíduo.**

| | |
|---|---|
| **Modelo** | **C2 — Print Profile + Print Traits** |
| **Seed** | **5 traits · 6 profiles · 10 links** |
| **Legado** | **7002** `card_variant` intactos · `printing_profile_id` preenchido = **0** · 927 defaults |
| **Staging** | **505** `NEEDS_REVIEW` intactas · **4** jobs `STAGED` · 79 Variant Types · 69 mappings |

**`PROMOTED` ainda NÃO.** Os arquivos não existem em `database/migrations/`.

**Próxima ação física:** byte-copy de `2165`–`2171` para `database/migrations/` + prova SHA-256 **7/7 identical**. O ambiente de shell desta sessão não alcança o sistema de arquivos (regressão de plataforma, Windows update de 8 de setembro), então nem `cp` nem `sha256sum` estão disponíveis — a cópia precisa ser feita com identidade de bytes preservada e os hashes conferidos antes de qualquer marcação de `PROMOTED`.

## O problema que este Gate resolve

`card_variant` tem **um único eixo** (`variant_type_id`). BASE1 exige dois:

| Eixo | Valores em BASE1 | Onde vive hoje |
|---|---|---|
| **Acabamento** | `normal`, `holo` | `card_variant_type` ✅ |
| **Impressão** | `shadowless`, `unlimited`, `1999-2000-copyright`, `1st-edition`, `red-cheek` | **nenhum lugar** ❌ |

Sem o segundo eixo, as 10 assinaturas de BASE1 viram **10 Card Variant Types compostos** — e o mesmo se repete em cada Set da era WOTC (~968 Cards pendentes). Com o eixo, viram **0 tipos novos**.

Evidência do vácuo: nos **69 mappings externos existentes, `external_subtype` é `NULL` em 100 %**. A taxonomia nunca mapeou uma assinatura com `subtype`.

## Vocabulário ratificado

| Conceito | EN | pt-BR |
|---|---|---|
| Domínio | **Printing** | Impressão |
| Átomo | **Print Trait** | Característica de Impressão |
| Agregado | **Print Profile** | Perfil de Impressão |

`EDITION` foi rejeitado: só seria correto para `1st-edition` e `unlimited`. `1999-2000-copyright` é linha de copyright; `red-cheek` é característica de arte impressa.

## Arquivos

| Arquivo | O quê | Versão | Estado |
|---|---|---|---|
| `2165_create_card_printing_trait_table.sql` | Átomo. 5 registros virão da seed. | v1.0 | **CONFIRMADO EXECUTADO / LIVE** |
| `2166_create_card_printing_profile_table.sql` | Agregado + **`traits_signature UUID[]`** + índice único de composição. | **v1.1** | **CONFIRMADO EXECUTADO / LIVE** |
| `2167_create_card_printing_profile_trait_table.sql` | N:N — **fonte da verdade**. Same-Game por FK composta. | v1.0 | **CONFIRMADO EXECUTADO / LIVE** |
| `2168_create_card_printing_composition_guards.sql` | Não-vazio + selamento (deferido) · imutabilidade · guard de escrita do selo. | **v1.1** | **CONFIRMADO EXECUTADO / LIVE** |
| `2169_seed_card_printing_traits_and_profiles.sql` | **5 / 6 / 10 = 21 linhas**, idempotente. | v1.0 · *comentário* | **CONFIRMADO EXECUTADO / LIVE** |
| `2170_add_printing_profile_id_to_card_variant.sql` | Coluna NULLABLE + FK RESTRICT + índice parcial + guard same-Game. | v1.0 | **CONFIRMADO EXECUTADO / LIVE** |
| `2171_reconcile_card_variant_uniqueness_for_printing.sql` | Troca da unicidade por **dois índices parciais**. | v1.0 | **CONFIRMADO EXECUTADO / LIVE** |
| `2823_validate_card_printing_model.sql` | Harness, **12 blocos, todos fail-closed**. Permanece **só aqui** — nunca vai para `database/migrations/`. | **v1.2** | **VALIDATED / PASS** |

### Revisão `GATE-A-CORRECTION-01` — três pontos fechados

| # | Ponto | v1.0 (rejeitada) | v1.1 |
|---|---|---|---|
| 1 | **Autoridade da imutabilidade** | `created_at = transaction_timestamp()` — metadado temporal usado como autorização | **estado semântico**: `traits_signature IS NULL` = em montagem · `NOT NULL` = selado |
| 2 | **Unicidade de composição** | `md5(string_agg(...))` — igualdade **probabilística** | **`UUID[]` ordenado** — igualdade **exata**, sem hash |
| 3 | **Profile vazio** | `S5b` documentava a lacuna (o trigger vivia na N:N e não disparava sem vínculo) | **fail-closed**: trigger deferido migrou para `card_printing_profile` e dispara **1× por Profile**, sempre |

**Simplificação real que veio junto:** o trigger deferido por *vínculo* desapareceu. Um único trigger deferido por *Profile* faz as duas coisas — valida não-vazio e sela — porque no COMMIT ele já enxerga a composição final.

`2169` recebeu **apenas correção de comentário** (duas linhas que ainda diziam "fingerprint"). O SQL executável é byte-idêntico ao da v1.0 — por isso não sobe de versão.

### Revisão `HARNESS-CORRECTION-01` — `2823` v1.1 → v1.2

`S2.05` da v1.1 era **dependente de collation** e deu **falso FAIL** contra um banco correto. Comparava uma única string montada com `string_agg(... ORDER BY x)`; em `datcollate = en_US.UTF-8` a pontuação é desprezada na primeira passada, então `SHADOWLESS_FIRST_EDITION=…` ordena **antes** de `SHADOWLESS=…` — o inverso de `COLLATE "C"`, que foi o que a string literal assumia.

Prova da causa, read-only:

```
ORDER BY c             → 'SHADOWLESS_FIRST_EDITION=X' | 'SHADOWLESS=X'
ORDER BY c COLLATE "C" → 'SHADOWLESS=X' | 'SHADOWLESS_FIRST_EDITION=X'
```

**Não foi corrigido com `COLLATE "C"`** — isso só trocaria uma dependência de locale por outra. A composição é um **conjunto relacional**, então a prova passou a ser **set-based**: `expected EXCEPT actual` = 0 · `actual EXCEPT expected` = 0 · pares = 10 · profiles distintos = 6. Independente de collation, de ordem, de `display_order` e da ordem física de `INSERT`.

**Separação de responsabilidades preservada:** `S2.05` prova a **composição semântica** (quais traits cada profile tem). `traits_signature` continua provado à parte — `S2.06/07/08/09` (selamento, igualdade com recálculo, ordenação canônica, unicidade) e `S1.14/S1.16` (tipo e forma). As duas não voltam a se misturar.

Nenhuma lógica de modelo mudou. `2165`–`2171` permanecem intocadas e aplicadas.

Numeração livre confirmada por varredura: migrations `2161`/`2163`/`2164` ocupadas (`2162` só em proposals) → **2165–2171 livres**; validations até `2822` → **2823 livre**.

## Modelo

```
card_printing_trait          5 linhas   SHADOWLESS · FIRST_EDITION · UNLIMITED
                                        COPYRIGHT_1999_2000 · RED_CHEEK
card_printing_profile        6 linhas   P1..P6 (+ traits_signature UUID[], derivada)
card_printing_profile_trait 10 linhas   ← FONTE DA VERDADE da composição
card_variant.printing_profile_id        NULLABLE, FK RESTRICT
```

**Nem `code` nem `name` são autoridade.** A composição é a N:N. Filtro por característica é sempre `JOIN`, nunca `LIKE` no code.

### Os 6 Perfis e seus 10 vínculos

| Perfil | Traits | pt-BR |
|---|---|---|
| `UNLIMITED` | UNLIMITED | Tiragem Ilimitada |
| `SHADOWLESS` | SHADOWLESS | Sem Sombra |
| `SHADOWLESS_FIRST_EDITION` | SHADOWLESS + FIRST_EDITION | Sem Sombra · 1ª Edição |
| `COPYRIGHT_1999_2000` | COPYRIGHT_1999_2000 | Copyright 1999–2000 |
| `SHADOWLESS_RED_CHEEK` | SHADOWLESS + RED_CHEEK | Sem Sombra · Bochecha Vermelha |
| `SHADOWLESS_RED_CHEEK_FIRST_EDITION` | SHADOWLESS + RED_CHEEK + FIRST_EDITION | Sem Sombra · Bochecha Vermelha · 1ª Edição |

`shadowless-red-cheek` = **SHADOWLESS + RED_CHEEK**, decomposição **ratificada** e representada apenas pela composição de P5/P6. Isso **não autoriza** parsing genérico de tokens hifenizados — cada decomposição 1:N precisa existir como conhecimento declarativo explícito.

## `traits_signature` — igualdade exata, sem hash

**Tipo: `UUID[]`, sempre ordenado ascendente.** É o **conjunto materializado**, não uma renderização dele. Escolha deliberada sobre a alternativa `TEXT`: um array de UUID é o próprio dado, comparado **elemento a elemento** pelo Postgres.

| Requisito | Como é atendido |
|---|---|
| **Sem hash** | não há `md5`, `sha`, `digest` em lugar nenhum — o harness verifica isso no `prosrc` dos guards (`S1.15`) |
| **Igualdade exata** | igualdade de array no Postgres é elemento a elemento: mesmo tamanho e mesmos elementos nas mesmas posições. **Colisão é impossível**, não improvável |
| **Independente da ordem** | o array é sempre montado com `ORDER BY trait_id` — `{A,B}` e `{B,A}` produzem literalmente o mesmo array |
| **Independente do code** | o code não participa do cálculo |
| **UNIQUE real** | btree indexa `anyarray` (`array_ops`) → `UNIQUE (game_id, traits_signature) WHERE NOT NULL` é restrição do banco |
| **Conjunto diferente → signature diferente** | por construção: dois conjuntos distintos de UUIDs ordenados não podem gerar o mesmo array |

A N:N continua sendo a **fonte da verdade**. `traits_signature` é materialização técnica derivada, para integridade e unicidade.

## Não-vazio + selamento — um trigger só

```
CONSTRAINT TRIGGER trg_card_printing_profile_seal
AFTER INSERT ON card_printing_profile
DEFERRABLE INITIALLY DEFERRED
```

Dispara **uma vez por Profile**, no COMMIT:

1. se o Profile já não existir (criado e removido na mesma transação) → retorna, **sem falso positivo**;
2. monta `ARRAY(SELECT trait_id ... ORDER BY trait_id)`;
3. se vazio → **`EXCEPTION`** — Profile sem trait nunca chega ao COMMIT;
4. grava. **É neste `UPDATE` que o índice único avalia a composição** — e é ele, não a função, a autoridade da invariante.

Por estar sobre o *Profile* e não sobre a N:N, ele dispara **inclusive quando nenhum vínculo existe** — que era exatamente a lacuna da v1.0.

## Selamento como estado semântico

```
traits_signature IS NULL      →  EM MONTAGEM   (transação de criação)
traits_signature IS NOT NULL  →  SELADO        (composição imutável)
```

`created_at` **não** é mais usado como autoridade — metadado temporal não é autorização. O selamento passa a ser propriedade derivada da própria composição.

Em transações futuras, todo Profile existente já está selado (nenhum sobrevive a um COMMIT sem selo), então:

| Operação na N:N | Profile em montagem | Profile selado |
|---|---|---|
| `INSERT` de vínculo novo | permitido | **rejeitado** (`COMPOSITION_SEALED`) |
| `DELETE` de vínculo | permitido | **rejeitado** (`COMPOSITION_SEALED`) |
| `UPDATE` de vínculo | **rejeitado sempre** (`UPDATE_FORBIDDEN`) | **rejeitado sempre** |
| `INSERT` **idêntico** (no-op) | permitido | **permitido** — é o que mantém a seed idempotente |

**Não há como destravar.** Um terceiro guard, `BEFORE UPDATE OF traits_signature ON card_printing_profile`, rejeita qualquer tentativa de mudar o selo depois de posto — inclusive voltar a `NULL` — e, ao selar, exige que o valor **corresponda exatamente** à composição real. Nem o owner consegue gravar um selo falso.

**Corolário:** corrigir a composição de um Profile existente **não é UPDATE** — é criar Profile novo e reconciliar explicitamente. A RPC editorial que fará isso **não** faz parte deste Gate.

## Concorrência

T1 cria `PROFILE_A` com `{A,B}`; T2 cria `PROFILE_B` com `{A,B}`, simultaneamente. No COMMIT ambos os triggers calculam o **mesmo array ordenado** e tentam gravar. O índice único parcial serializa: um comita, o outro falha com `unique_violation`.

A proteção **não é** `SELECT EXISTS(...)` seguido de escrita. É o índice. Mesma lição da `2164`.

## §13 — Same-Game, duas camadas

| Relação | Mecanismo | Trigger? |
|---|---|---|
| Profile ↔ Trait | **FK COMPOSTA** contra `UNIQUE (id, game_id)` das duas tabelas | **não** — estrutural |
| Card Variant → Profile | trigger `BEFORE INSERT OR UPDATE`, só quando `printing_profile_id IS NOT NULL` | sim |

O segundo precisa de trigger porque `card_variant` não tem `game_id` — o Game só é alcançável por `card → card_set → expansion → game`. Custo **zero** para os 7.002 legados e para todo Set moderno.

## §14 — Troca da unicidade

**Objeto real auditado no LIVE, não assumido:**

```
uq_card_variant_card_type   contype = 'u'   UNIQUE (card_id, variant_type_id)
```

É **UNIQUE CONSTRAINT**, não índice solto → remoção por `ALTER TABLE ... DROP CONSTRAINT`.

```
A. printing_profile_id IS NULL      → UNIQUE (card_id, variant_type_id)
B. printing_profile_id IS NOT NULL  → UNIQUE (card_id, variant_type_id, printing_profile_id)
```

Dois índices parciais, **sem UUID sentinela** — os predicados já separam os universos e não se sobrepõem. Os 7.002 (todos `NULL`) caem no índice A, que é literalmente a regra que já respeitavam.

**Preservados e verificados:** `card_variant_pkey` · `uq_card_variant_card_order` · `uq_card_variant_id_card` (alvo de FK composta) · `uq_card_variant_one_default_per_card` · `ck_card_variant_order_positive` · as duas FKs · os dois índices simples.

## Semântica do NULL

`printing_profile_id IS NULL` significa **exatamente** "sem perfil de impressão declarado".

**Não** significa Unlimited · **não** significa desconhecido · **não** significa padrão · **não** significa erro.

`UNLIMITED` só é atribuído quando a fonte **declara explicitamente** o token. Ausência de token de impressão **nunca** implica UNLIMITED.

## Matriz do harness (`2823`)

| Bloco | Transação | Prova |
|---|---|---|
| **S1 — SCHEMA** (16 grupos) | read-only | 3 tabelas · coluna NULLABLE sem default · FK RESTRICT · 2 FKs compostas · PK composta · RLS ×3 · grants não ampliados · 3 índices · **constraint antiga removida** · 2 parciais novos com predicado · 6 constraints preexistentes + o parcial de default sobrevivem · **4** triggers, com o de selamento sendo `CONSTRAINT TRIGGER DEFERRABLE INITIALLY DEFERRED` **sobre `card_printing_profile`** · **4** funções `SECURITY DEFINER` com `search_path=""` · `traits_signature` é `udt_name='_uuid'` · **`traits_fingerprint` não existe mais** · **nenhum guard contém `md5`/`sha256`/`digest`** · os 2 CHECKs de forma |
| **S2 — SEED** (12) | read-only | 5 / 6 / 10 exatos · os 5 codes exatos · **composição set-based** (`EXCEPT` nos dois sentidos, 10 pares, 6 profiles) · **6 selados** · assinatura bate com **recálculo independente** (igualdade de array) · assinatura **ordenada ascendente** · nenhuma assinatura duplicada · same-Game em 100 % · nenhum profile vazio · nada fora de POKEMON |
| **S3 — LEGADO** (10) | read-only | `card_variant` = 7002 · **0 com perfil** · zero duplicidade lógica · `variant_order` válido · 927 defaults · 79 Variant Types · 69 mappings · **0 com `external_subtype`** · 505 NEEDS_REVIEW · 4 jobs STAGED · 0 VALID/PENDING |
| **S4 — UNICIDADE** | `BEGIN…ROLLBACK` | sem perfil aceita 1ª · duplicata sem perfil **rejeitada** · perfis **diferentes** permitidos · **mesmo** perfil rejeitado · nenhuma nasce default |
| **S5A — PROFILE VAZIO** | `BEGIN…ROLLBACK` | Profile criado **sem nenhum vínculo** → `EMPTY_COMPOSITION` no COMMIT lógico (`SET CONSTRAINTS ALL IMMEDIATE`). **Fecha a lacuna 5b da v1.0.** |
| **S5A.2 — CRIAR+REMOVER** | `BEGIN…ROLLBACK` | criar e apagar o Profile na mesma transação **não** gera falso positivo |
| **S5B — CONJUNTO DUPLICADO** | `BEGIN…ROLLBACK` | conjunto já existente inserido **em ordem inversa** e com **code diferente** → rejeitado. Prova independência de ordem **e** de code de uma vez |
| **S5C — CONJUNTOS DIFERENTES** | `BEGIN…ROLLBACK` | `{A,B}` e `{A,C}` **ambos aceitos** · assinaturas **distintas** · ambos selados |
| **S6 — SELAMENTO** (7) | `BEGIN…ROLLBACK` | pré-condição: P2 selado · ADD em selado **rejeitado** · DELETE **rejeitado** · `UPDATE` de vínculo **sempre** rejeitado · **destravar** o selo (`= NULL`) rejeitado · **falsificar** o selo rejeitado · reinserção idêntica **aceita** · Profile em montagem **aceita** composição |
| **S6B — IDEMPOTÊNCIA REAL** | `BEGIN…ROLLBACK` | os **três `INSERT` da `2169` reaplicados na íntegra** · sem exceção · 5/6/10 estável · **nenhuma assinatura alterada** |
| **S7 — SAME-GAME** | `BEGIN…ROLLBACK` | vínculo cross-game rejeitado pela FK composta · `card_variant` com perfil de outro Game rejeitado pelo trigger · caminho feliz aceito |
| **S8 — ZERO RESÍDUO** | read-only | nenhum `HARNESS%` · vocabulário de volta a 5/6/10 · `card_variant` 7002 e 0 com perfil |

**Todos os 12 blocos são fail-closed.** O MCP não propaga `RAISE NOTICE`: o sinal de PASS é a **ausência de exceção**.

Os blocos que precisam observar o efeito de um trigger **deferido** usam `SET CONSTRAINTS ALL IMMEDIATE` dentro de um sub-bloco com `EXCEPTION` — forçam a avaliação do COMMIT lógico sem precisar commitar de verdade.

**Fixtures** usam Card POKEMON ativa **real sem nenhuma variante** (para não colidir com `uq_card_variant_card_order`) — mesma disciplina da `2822` v1.1: reutilizar dado real, nunca exigir massa impossível.

## Ordem de execução (quando autorizado)

```
1. 2165  trait
2. 2166  profile
3. 2167  profile_trait          (depende de 2165 e 2166 — FKs compostas)
4. 2168  guards                 (depende de 2166 e 2167)
5. 2169  seed 5/6/10            (depende de 2168 — o selamento acontece aqui)
6. 2170  coluna + same-Game
7. 2171  troca de unicidade     (depende de 2170 — a coluna precisa existir)
8. 2823  harness, 12 blocos
```

## Rollback conceitual

Enquanto **nenhum** `card_variant` tiver `printing_profile_id` preenchido:

```
DROP INDEX uq_card_variant_card_type_no_printing, uq_card_variant_card_type_printing;
ALTER TABLE card_variant ADD CONSTRAINT uq_card_variant_card_type UNIQUE (card_id, variant_type_id);
ALTER TABLE card_variant DROP COLUMN printing_profile_id;   -- leva a FK, o índice e o trigger
DROP TABLE card_printing_profile_trait, card_printing_profile, card_printing_trait;
```

Os 7.002 nunca souberam que essas tabelas existiram. **Ponto de não-retorno real:** o primeiro Physical Card apontando para uma variante com perfil — e hoje `physical_card` tem **0 linhas**.

## Fora de escopo deste Gate

- `card_printing_external_mapping` e o **routing semântico** (`raw_field` × `raw_token` → trait) — rodada própria.
- `import-card-variants` (assinatura residual) — rodada própria.
- `normalized_data.printing_profile_id`, RPCs, BASE1, as 505 rows, defaults, UI.
- **D1** (`STANDARDS_WORLDS_2026_TOP_8`, ano errado no code) — forense fechada, **não corrigido**, isolado.
- **D2** (`SET_LOGO_REVERSE`, 87 variants) — `REVIEW_NEEDED`, exige conferência física, isolado.

Nenhum dos dois contamina o modelo de impressão.
