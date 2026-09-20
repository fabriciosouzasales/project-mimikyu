> ## ⛔ SUPERADO — `EDITORIAL-VOCABULARY-02` (2026-09-19)

> ### ⚠️ DOCUMENTO HISTÓRICO (MAPPING-LIFECYCLE-CORRECTION-01)
> Registro do gate editorial E1/E2/E3, hoje **FECHADO**. As **173
> composições** citadas são a medição da união A ∪ B antes da curadoria;
> o corpus canônico é **144**. Ver **CURRENT STATE** em `PACKAGE-STATUS.md`.
>
> **E1 · E2 · E3 estão CLOSED.** Este documento é o registro histórico do STOP
> que os bloqueava, preservado porque o diagnóstico continua correto: o corpus
> nunca estava no repositório, e a `2841` era mesmo o caminho crítico.
>
> O que mudou: a `2841` foi executada (read-only), o corpus foi extraído das
> **1.085 rows EDITION_CONTEXT** da partição canônica, e os três seeds foram
> preenchidos. Números finais em `SEED-COVERAGE.md` v2.0 — **115 traits ·
> 156 profiles · 122 mappings · 38 `DECK_PLAYER_*` sem colisão**.
>
> A tabela de "Classificação por item do mandato" no fim deste arquivo é a que
> está desatualizada; o resto (regra de slug, regra de nomenclatura de profile,
> famílias) foi confirmado e permanece válido — a regra de nomenclatura foi
> **estendida para aridade 3**, que era a única lacuna.

# E1 / E2 / E3 — por que não fecham nesta rodada, e o que fecha

**`EDITION-CONTEXT-AXIS-EDITORIAL-VOCABULARY-01`.** Este documento é a
resposta ao mandato. O veredito vem primeiro.

---

## STOP — o corpus não está no repositório

O mandato manda derivar o vocabulário "dos `raw_data`/lineage já auditados" e
proíbe executar SQL. Os dois não podem valer ao mesmo tempo: **os `raw_data`
estão no LIVE, não em `database/`**.

As rodadas anteriores registraram as **contagens**, nunca o **corpus**. Busca
exaustiva feita nesta rodada:

| O que o mandato pede | Existe no repo? | Onde procurei |
|---|---|---|
| 115 tokens de origem | **NÃO** — só 21, e são de B | `SEED-COVERAGE.md` |
| 38 `source_value` de DECK_PLAYER | **NÃO — zero** | busca global por `deck-player`, `DECK_PLAYER_[A-Z]`, nomes próprios |
| composição dos 173 profiles | **NÃO** | `2231`, `SEED-COVERAGE.md`, `MIGRATION-MAP-365.md` |
| `qtd A` / `qtd B` por trait | **NÃO** — só agregados de B | `MIGRATION-MAP-365.md` |
| Sets observados por token | **NÃO** | — |
| GLOBAL × SOURCE_SET_SCOPED por token | **NÃO** — só `set-logo` | guard H2 do `2232` |

`TOP-SIXTEEN` e `DECK_PLAYER_JASON_KLACZYNSKI`, que poderiam parecer corpus,
aparecem **como exemplos de formato** em comentários de `2203`/`2230` — o
próprio `2230` os rotula *"NÃO são dados; remover ao preencher"*.

### O que aconteceria se eu preenchesse assim mesmo

Eu inventaria ~150 decisões editoriais: 83 `code` de traits, 38 nomes
próprios de jogadores, 173 composições. Todas passariam nos gates — os gates
provam *estrutura*, não *verdade* — e o catálogo nasceria com uma taxonomia
fabricada, indistinguível da correta até alguém conferir carta a carta.

É exatamente o modo de falha que `E1` existe para impedir, e que `2203` grava
no schema:

> *"Nenhum `code` é derivado automaticamente de token TCGdex. Tradução
> editorial obrigatória, uma a uma."*

E é a mesma classe do defeito `VALID → JSON null` que a
`BACKFILL-SEMANTICS-CORRECTION-01` eliminou: plausível, aprovado por todos os
testes, e falso.

**Portanto E1/E2/E3 NÃO podem ser declarados CLOSED nesta rodada.**

---

## O que esta rodada FECHA de verdade

O mandato pede para maximizar fechamento seguro. Quatro coisas fecham sem
inventar nada — todas são **algoritmo ou derivação de material já aprovado**,
não conteúdo editorial.

### 1. A extração do corpus — `2841` (novo, read-only)

Produz exatamente as listas que faltam, em 4 recortes:

| Recorte | Entrega | Destrava |
|---|---|---|
| **1.A** | tokens residuais de A por `raw_field`, com `qtd`, Sets e sinal de escopo | **E1** |
| **1.B** | assinaturas residuais completas de A — cada uma é um candidato a profile | **E3** |
| **2** | as 365 de B via lineage, com `raw_data` real | E1 · E3 |
| **3** | candidatos a DECK_PLAYER (forma de nome próprio) | **E2** |
| **4** | contagens de controle contra 1.069 / 365 | falha alto se a baseline mudou |

Sem INSERT/UPDATE/DELETE/DDL, dentro de `BEGIN`/`ROLLBACK`. **É o único item
desta rodada que precisa de execução autorizada** — e é ele que transforma
E1/E2/E3 de "impossível" em "uma sessão de trabalho".

O recorte 3 usa forma (`^[a-z]+(-[a-z]+)+$`, sem dígitos) apenas para
**encurtar a lista que um humano revisa**. A decisão "isto é um jogador"
continua editorial, e o recorte 1.A traz o universo inteiro para conferência
cruzada — nenhuma inferência por substring decide nada.

### 2. O slug determinístico — `slugify.mjs` (**16 PASS / 0 FAIL**)

Item 4 do mandato é **algoritmo**, não conteúdo. Implementado e testado:

```
jason-klaczynski  -> JASON_KLACZYNSKI     José Muñoz    -> JOSE_MUNOZ
Jason Klaczynski  -> JASON_KLACZYNSKI     Łukasz ...    -> LUKASZ_KOWALSKI
O'Brien / O’Brien -> O_BRIEN  (mesmo)     Søren Nielsen -> SOREN_NIELSEN
```

Cobre as regras uma a uma: determinístico · ASCII (NFD + lista fechada para
`Ł Ø Ð Þ ß Æ Œ`) · `UPPER_SNAKE_CASE` · remove só pontuação e diacrítico ·
**não traduz nome próprio** (não há tabela de tradução) · prefixo sempre
`DECK_PLAYER_`, sem trait genérico `PERSON`/`PLAYER`.

**Colisão é detectada, nunca resolvida sozinha.** Três grafias de `O'Brien`
colidem em `DECK_PLAYER_O_BRIEN` e o script sai com código 1 — desambiguar
homônimo é decisão de pessoa. Modo operacional:
`node slugify.mjs --from-csv edition-context-vocabulary.csv`.

### 3. A regra de nomenclatura de profile — item 6, determinística

O mandato pede regra única. Proposta, e ela é mecânica:

| Aridade | `code` | `name` |
|---|---|---|
| **1 trait** | `code` do trait, sem prefixo novo | `name` do trait |
| **2 traits** | `<A>__<B>`, A e B em ordem **alfabética do code** | `"<name A> · <name B>"` |
| **3 traits** | `<A>__<B>__<C>`, em ordem **alfabética do code** | `"<name A> · <name B> · <name C>"` |

- A ordem alfabética do `code` torna o `code` do profile **função pura da
  composição** — a mesma dupla nunca gera dois codes.
- `display_order`: passo **10**, esparso, na ordem `(família do 1º trait,
  code)`. Esparso para que inserção futura não renumere nada.
- Aridade máxima observada é **3** (`SEED-COVERAGE.md` §3, gate P4 da `2231`:
  `SEED_PROFILE_ARITY: esperada 3`), então a regra cobre **144/144** do corpus
  canônico sem caso de exceção. ⟨hist.⟩ A v1.0 deste arquivo dizia "aridade
  máxima 2 ... cobre 173/173": ambos os números eram da medição pré-curadoria.
- **Zero colisão é consequência estrutural**, não verificação: `code` é
  função injetora da composição; `traits_signature` é selada por `2206` com
  `uq_cecp_game_signature`; `display_order` é gerado por ordenação total.
- `code` estável mesmo se o `name` for refinado depois — o `name` não
  participa do `code`.

Exemplo, com os traits que o `MIGRATION-MAP-365` já fixou:
`STANDARD_REGIONAL_CHAMPIONSHIPS_STAFF` → composição `{EVENT_REGIONALS,
ROLE_STAFF}` → `EVENT_REGIONALS__ROLE_STAFF`.

### 4. O arquivo editorial — `edition-context-vocabulary.csv`

Colunas exatas do item 2. **32 linhas já com token ou code conhecido**,
derivados de material aprovado:

- **16 `code`** vindos da tabela de destinos do `MIGRATION-MAP-365.md` —
  `PROGRAM_PLAYER_REWARDS`, `ROLE_STAFF`, `ARTWORK_SET_LOGO`,
  `PROGRAM_PROFESSOR`, `CHANNEL_POKEMON_CENTER`, `EVENT_GYM_CHALLENGE`,
  `CHANNEL_GAMESTOP`, `EVENT_REGIONALS`, `CHANNEL_EB_GAMES`,
  `CAMPAIGN_PIKACHU_WORLD_2000`, `CHANNEL_WOTC_PROMO`, `CAMPAIGN_FIRST_MOVIE`,
  `CAMPAIGN_FIRST_MOVIE_INVERTED`, `PROGRAM_LEAGUE`, `EVENT_WORLDS_2024`,
  `CAMPAIGN_HORIZONS`, com `qtd_b` conferida contra a tabela;
- **16 tokens** da lista congelada dos 21 exclusivos de B (os outros 5 já
  estão no bloco 1), com `code` em aberto.

`115 − 32 = 83` pendentes, **dos quais 38 são DECK_PLAYER**. Toda coluna não
derivável está marcada `<PENDENTE-2841>` (mecânica) ou `<PENDENTE-E1>`
(editorial) — nenhum valor plausível foi inserido.

---

## Classificação por item do mandato

| Item | Estado | Motivo |
|---|---|---|
| 1 — fonte da verdade | ⛔ | corpus não está no repo; `2841` o produz |
| 2 — 115 traits | ⛔ **BLOCKER** | 83 `code`/`name` dependem de dado ausente |
| 3 — famílias | ✅ | as 8 preservadas; nenhuma nona criada; nenhum item forçou revisão |
| 4 — 38 DECK_PLAYER | ⚠️ **parcial** | algoritmo de slug FECHADO e testado; os 38 `source_value` não existem no repo |
| 5 — 173 profiles | ⛔ | composição depende do recorte 1.B |
| 6 — nomenclatura de profile | ✅ | regra determinística fechada, zero colisão por construção |
| 7 — mappings | ⛔ | escopo GLOBAL × SCOPED exige os Sets observados por token. **`set-logo` permanece SCOPED a `dp1`/`swsh9`/`svp`**; EX7–EX10 fora; `foil` impossível por `CHECK` |
| 8 — cobertura | ⛔ | não recalculável sem o corpus. 285 × 80 preservados em `MIGRATION-MAP-365.md` |
| 9 — seeds | ⛔ | `2230`/`2231`/`2232` **intocados** — já abortam corretamente |
| 10 — ambiguidade | ✅ | 2 `HOLD_EDITORIAL` registrados (`league`, `player-reward` — blocker B3) |
| 11 — UX/labels | ✅ | coluna `name_pt_br` criada no CSV como tabela editorial, **sem tocar schema** |
| 12 — validação | ⛔ | nada a validar sem vocabulário; harness inalterado |

---

## O caminho crítico, em uma frase

**Executar a `2841` e colar os 4 recortes no CSV.** Depois disso, E1 vira
trabalho editorial de uma sessão, E2 sai do `slugify.mjs` em segundos, e E3
é derivação mecânica de E1 pela regra da seção 3.

Nenhuma outra ordem funciona: inverter significa escolher os nomes antes de
saber o que está sendo nomeado.
