# INVENTÁRIO A / B / C — o que existe, o que falta, o que bloqueia

> ### ⚠️ DOCUMENTO HISTÓRICO (MAPPING-LIFECYCLE-CORRECTION-01)
> Os bloqueios de vocabulário listados aqui (E1/E2/E3) foram **RESOLVIDOS**:
> os seeds `2230`/`2231`/`2232` estão preenchidos com **115 traits · 144
> profiles · 196 links · 122 mappings**. As menções a **173 profiles** são a
> MEDIÇÃO da união A ∪ B, anterior à curadoria — não o corpus atual.
> Autoridade sobre o estado corrente: a tabela **CURRENT STATE** em
> `PACKAGE-STATUS.md`.

**Correção 4 da `GATE-A-FINAL-CORRECTION-01`.**

> **Este pacote NÃO é implementation-ready.** A classe B abaixo é grande e
> contém o caminho de escrita inteiro. Declarar prontidão agora seria
> exatamente o que a Correção 4 mandou não fazer.

---

## Classe A — presentes e executáveis

SQL completo, gates fail-loud, sem placeholder, sem vocabulário pendente.
Executáveis assim que as pré-condições do DAG forem satisfeitas.

| Artefato | Papel |
|---|---|
| `2203` · `2204` · `2205` · `2206` · `2207` | fundação: trait · profile · N:N · guards · mapping · RLS + `catalog_admin_select` + ACL em paridade com Printing |
| `2208` | coluna aditiva em `card_variant` |
| `2209` | `UNIQUE(4) NULLS NOT DISTINCT` (índice normal, sob FREEZE) |
| `2210` | `axis_identity_token` + `uq_cvir_row_identity` + shape **permissivo** |
| `2211` | `resolve_variant_row_axes()` — contrato terminal único |

> **`2203`–`2211`: EXPLICIT TRANSACTION BOUNDARY → atomic rollback on failure.**
> Os nove declaram `BEGIN;`/`COMMIT;` próprios. Nenhum estado parcial é
> aplicável — em particular, a `2209` não pode deixar índice órfão sem
> constraint. Ver `ROLLOUT-ORDER.md`, seção "Atomicidade por arquivo".
| **`2212`** v3.0 | **resolução OPERACIONAL** — ex-backfill global; só `job vivo + PENDING` |
| **`2214`** v3.0 | **guard de transição OPERACIONAL** — job-aware; G2 não-regressão; G3 forma |
| **`2833`** v2.0 | **matriz de state machine job-aware** — 11 gates |
| **`2215`** | **DROP das 2 identidades antigas de `card_variant`** (novo) |
| **`2216`** | **DROP das 2 identidades antigas de staging** (novo) |
| **`2217`** v2.0 | **EXPAND** — cria `write_card_variant` de 7 args, sem DEFAULT; **preserva** a de 6 (novo) · ✅ **EXECUTED / LIVE VALIDATED** 2026-09-23, exceção EOL documentada (`EXECUTION-BATCHES.md`) |
| **`2223`** | **CONTRACT** — prova database-wide + `DROP` da assinatura de 6 args (novo, `WRITER-EXPAND-CONTRACT-CORRECTION-01`) |
| **`2840`** | **probe T1** — `apply_migration` × `NULLS NOT DISTINCT` (novo) |
| `2830` v6.0 · `2831` · `2832` v3.0 | harness (114 + 4 pendentes + 3 manuais) · simulação · prova operacional (14 casos) |

**15 artefatos SQL classe A.**

> **Ressalva revista (`OPERATIONAL-BOUNDARY-CORRECTION-01`).** `2212` depende
> dos seeds (classe B por E1), mas **saiu do caminho crítico**: seu universo
> — `job vivo + PENDING` — mede **1.642 rows** na baseline atual. A fundação
> física inteira (`2203`–`2211`, `2214`–`2218`, `2223`, `2209`, `2215`, `2216`) pode
> ser executada **sem E1**. O vocabulário é pré-requisito da *resolução
> editorial das 1.642*, não da estrutura.

---

## Classe B — desenhados, não executáveis

### B.1 — Seeds (bloqueio editorial E1/E2/E3)

| Artefato | O que já tem | O que falta |
|---|---|---|
| `2230` | estrutura, 6 gates, lista congelada dos 21 tokens de B | os 115 `code`/`name` |
| `2231` | estrutura, 7 gates, selagem via 2206 | composição dos 173 |
| `2232` | estrutura, gates C1/C2/C3, guard H2 de `set-logo` | os mappings |

Os três **abortam** se o vocabulário estiver vazio. Detalhe em
`SEED-COVERAGE.md`.

### B.2 — Contratos SQL existentes a redefinir (Correção 7)

> **RESOLVIDO em `WRITE-PATH-STAGING-01`.** Os cinco corpos foram escritos
> por inteiro, como `CREATE OR REPLACE` de estado final. Esta seção deixou de
> ser classe B e passou a ser **classe A** — ver `PACKAGE-STATUS.md`. A
> tabela abaixo permanece como registro do delta exigido e das âncoras
> usadas; a coluna "Linhas" foi corrigida onde estava errada.

| Nº | Alvo | Base canônica | Linhas | Delta exigido |
|---|---|---|---:|---|
| **`2218`** | `public.admin_confirm_catalog_variant_import` | `2145` v2.0 | 519 | ler `normalized_data.edition_context_profile_id` (tri-state) · **matching quádruplo com `IS NOT DISTINCT FROM`** · `FOR UPDATE` na Card com `ORDER BY id` no lote · handler de `unique_violation` · chamar o writer com **7** args |
| **`2219`** | `internal.apply_variant_type_mapping` | `2193` | 324 | trocar 2 chamadas a `compute_variant_residual_signature` por `resolve_variant_row_axes` · gravar as **duas** chaves de eixo |
| **`2220`** | `variant_type_mapping_impact` · `_decision` · `lookup_variant_type_for_row` | `2192` | 563 | residual pós-dois-eixos · impacto contado pela identidade de 4 · `EDITION_CONTEXT_UNRESOLVED` no `decision`. **NÃO faz same-Game** — ver nota abaixo |
| **`2224`** ✅ **EXECUTADA / LIVE VALIDATED / CLOSED** *(2026-09-22)* | `internal.enforce_card_variant_edition_context_profile_game` + `trg_card_variant_edition_context_profile_game` | `2170` (padrão) | — | **same-Game do 3º eixo** — guard dedicado, autoridade única. **Não é mais artefato pendente**: blob executado `5bae844b…`, publicado em `2fcd6231`, POSTCHECK **20/20 GATEs · GLOBAL PASS**, zero drift. Permanece nesta tabela como registro do **motivo de criação** (ver correção abaixo) |

> ### ⚠️ CORREÇÃO (`BATCH9-2217-READINESS-CORRECTION-01`)
> A linha da `2220` acima atribuía a ela `validate_card_variant_game_consistency`
> e o **same-Game do 3º eixo**. **Era falso**, e a auditoria
> `BATCH9-2217-READINESS-AUDIT-01` provou mecanicamente: o escopo declarado no
> cabeçalho da própria `2220` é `variant_type_mapping_impact` +
> `_decision`; o arquivo não contém `CREATE TRIGGER` nem menciona
> `validate_card_variant_game_consistency`. E aquela função (`161:60-104`)
> compara Card × **Variant Type**, nunca `edition_context_profile_id`.
>
> Até a `2224`, **nenhuma** proteção server-side recusava um
> `edition_context_profile_id` de outro Game — a FK da `2208` garante apenas
> existência. A `2224` fecha a lacuna, e é **pré-requisito da `2217`**:
> **`2224` → `2217` → `2218` → `2223`**. O número não é a ordem; o `DAG.md` é.
>
> ✅ **LACUNA FECHADA NO LIVE em 2026-09-22** (`BATCH9-2224-CLOSEOUT-01`).
> O guard está **ATIVO**: os três eixos passam a ter autoridade same-Game
> dedicada (`2170` Impressão · `161` Variant Type · `2224` Contexto de
> Edição). O **pré-requisito da `2217` está SATISFEITO**.
>
> ✅ **`2217` EXECUTED / LIVE VALIDATED em 2026-09-23**
> (`BATCH9-2217-LIVE-VALIDATION-CLOSEOUT-01`), com exceção documental de
> terminador de linha (raw DIFFERENT só por CRLF · normalizado EXACT ·
> divergência semântica NONE). ~~Próximo estágio: `2218` SWITCH — READINESS~~
> *(superado)*.
>
> ✅ **`2218` e `2223` EXECUTED / LIVE VALIDATED / CLOSED em 2026-09-25**
> (`BATCH9-EDITION-CONTEXT-WRITER-CLOSEOUT-01`) — **Batch 9 CLOSED**. Próximo
> estágio: **Batch 10 / `2209` — READINESS**, `NÃO EXECUTADA`, exigindo mandato.
| **`2221`** | `public.admin_resolve_catalog_variant_import_printing_mapping` | `2181` | 652 | revalidação via 2211 (lógica de Printing inalterada) |
| **`2222`** | `internal.create_card_printing_profile_with_backfill` | `2189` | 583 | backfill **preservar** `edition_context_profile_id` (2 call sites) |

**Invariantes obrigatórios nos cinco** — nenhum pode regredir:
`SECURITY DEFINER`/`INVOKER` vigente · `search_path = ''` · grants atuais
(sem `anon`/`authenticated` onde hoje não há) · bounds de payload
(`c_max_variant_ids = 10000`) · códigos de erro preservados literalmente,
novos apenas aditivos · **nenhuma função pode calcular residual de Finish
antes de Edition Context**.

> **Como foram escritos.** Cada corpo canônico foi lido por inteiro antes de
> ser reemitido — guards, mensagens de erro e gates de reconciliação que não
> pertencem ao delta foram preservados byte a byte. Os cinco carregam
> pré-condições que abortam se a base divergir (inclusive verificação de
> assinatura, contra sobrecarga silenciosa) e postchecks que provam **no
> banco** que o contrato de dois eixos não é mais chamado.
>
> **Escala, conferida com `wc -l`.** Os cinco arquivos canônicos de base somam
> **2.641** linhas (519 + 324 + 563 + 652 + 583) — a contagem da tabela acima
> está correta. Os cinco artefatos produzidos somam **2.738** linhas
> (502 + 406 + 479 + 595 + 756). A diferença é cabeçalho de proposta,
> pré-condições e postchecks, que a base canônica não tem.

### B.3 — Edge

| Artefato | Estado |
|---|---|
| `edge/import-card-variants.patch` rev 2.0 | **escrito** — 5 diffs com âncoras conferidas no arquivo real; **D3 fechado** |
| `edge/edition-context.test.ts` rev 2.0 | **escrito** — **8** testes; T3, T7 e T8 falham contra o código atual, por desenho |

Classe B porque `supabase/functions/` **não foi tocado** e o deploy depende
de `2203`-`2211` e dos seeds `2230`-`2232`.

> **Correção de premissa (rev 2.0).** A rev 1.0 afirmava que a Edge seria
> *consumidora* do contrato do servidor para o eixo 3. É falso para esta
> função: o cabeçalho da PHASE C (`index.ts:128-134`) declara que o eixo de
> Impressão já é um **espelho em memória**, por decisão arquitetural. O eixo
> 3 nasce simétrico — é a decisão D3, agora fechada.
>
> **Defeito corrigido.** A rev 1.0 gravava a chave do eixo 3 sempre que a
> Impressão resolvia, o que afirma "resolvido sem contexto" sobre linha de
> contexto indeterminado. O gate passou a ser sobre os DOIS eixos.

---

## Classe C — blockers editoriais e operacionais

| # | Blocker | Escala | Dono | Bloqueia |
|---|---|---:|---|---|
| **E1** | tradução editorial dos 115 `code` | 115 | Fabrício | resolução das **1.642** · `2831`/`2213` (285). **NÃO bloqueia a fundação física** |
| **E2** | os 38 `DECK_PLAYER_*` (grafia, homônimos) | 38 | Fabrício | ⊂ E1 |
| **E3** | composição dos 173 profiles | 173 | derivado de E1 | `2231` |
| **E4** | `foil`-programa indeterminado (B3) | 57 rows | Fabrício | nada — segue em HOLD |
| **O1** | **T1 não executado** — `NULLS NOT DISTINCT` pelo caminho real | — | execução | `2209` e o grafo inteiro |
| **O2** | Pricing: 80 READY condicionados | 80 | mandato próprio | `2213` |
| ~~**D3**~~ | ~~preload de mappings na Edge × chamada única a 2211~~ | — | — | **FECHADO** em `WRITE-PATH-STAGING-01`: espelho em memória (opção A), simétrico à PHASE C. Justificativa e alternativas recusadas no cabeçalho do patch. |

---

## Veredito

| Pergunta | Resposta |
|---|---|
| A fundação física está completa? | **Sim** — classe A, 14 artefatos |
| A fundação depende de E1? | **NÃO** — mudou nesta correção |
| O backfill global existe ainda? | **Não** — eliminado; sobrou resolução operacional |
| Quantas rows o `2212` toca hoje? | **1.642** — `NEEDS_REVIEW` em jobs vivos |
| O histórico é reescrito? | **Não** — ~23.957 terminais + 415 `CANCELLED` intocados |
| A identidade nova entra em vigor? | **Sim, agora** — `2215`/`2216` existem e são executáveis |
| O caminho de escrita está pronto? | **Não** — `2218`–`2222` são classe B |
| O vocabulário existe? | **Não** — E1/E2/E3 |
| O pacote é implementation-ready? | **NÃO** |
| O pacote é Gate-A-complete? | **Sim, quanto às 10 correções** — com os blockers acima declarados, não disfarçados |
