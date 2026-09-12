# Primary Species — Sourcing dos Card Sets ME*

| Campo | Valor |
|---|---|
| **Mandato** | `PRIMARY-SPECIES-ME-SOURCING-01 — BACKFILL-GATE-A-REVISION-01` |
| **Data** | 2026-09-12 |
| **Status** | **CONFIRMADO EXECUTADO / VALIDADO / CLOSED** (2026-09-12) |
| **Diagnóstico** | `PRIMARY-SPECIES-ME-SOURCING-01 — AUDIT-01` |
| **Depende de** | `6112`/`6113`, `6114`, `6115` v1.2 (LIVE); baseline `card_primary_species` = 16.657 |
| **Escopo** | 752 Cards POKEMON dos Card Sets `ME1`, `ME2`, `ME2.5`, `ME3`, `ME4`, `MEP` |
| **Resultado** | 752/752 = **100 %** · 751 `AUTOMATIC_DEXID` + 1 `EDITORIAL_RECONCILIATION` · global 16.657 → **17.409** (99,28 %) · residual **879 → 127** |

---

## Sequência completa da rodada — `CLOSED`

```
AUDIT-01                 read-only. Baseline 752, identidade externa, caminho TCGdex,
                         classificacao A-F, compatibilidade com 6115.  GO.
   ↓
BACKFILL Gate A          6129/6130/6842 escritos sem executar SQL.
  (+ REVISION-01           zero TEMP TABLE · evidencia = 752 (nao 781) ·
     CORRECAO me01-086     me01-086 = SOURCE_DATA_ERROR, nao ambiguidade ·
     FINAL-CHECK-01)       contrato transacional confirmado.
   ↓
6129                     EXECUTADA como `postgres`. Falha de parse no literal JSONB
  (SYNTAX-CORRECTION-01    (10 linhas de comentario dentro de $json$) -> corrigida ->
   + BACKFILL-01-RETRY)    parse-test 752 -> reexecucao. 751 resolvidas.
                         card_primary_species 16.657 -> 17.408.  PASS.
   ↓
6842 §1 §2 — Gate A      read-only. Manifesto pos-6129 e Gate A.
  (+ MANIFEST-FANOUT-      Defeito de manifesto (810 linhas p/ 751 Cards, fan-out de
     CORRECTION-01)        idioma nas MEP) -> dedup pelo par (card_id, external_card_id).
                         751/751/751, 0 duplicadas.  PASS.
   ↓
6130                     Preflight read-only -> identidade admin confirmada ->
  (PREFLIGHT-01 +          3 hardenings (P3b, A1b, A9/A10) -> EXECUTADA pelo Caminho B.
   ADMIN-IDENTITY-         me01-086 -> Absol / 359, EDITORIAL_RECONCILIATION.
   BINDING-01 +            card_primary_species 17.408 -> 17.409.  PASS.
   FINAL-HARDENING-01 +
   EDITORIAL-RESOLUTION-01)
   ↓
6842 §3 §4 §5            read-only. Manifesto final 752/752/752, distribuicao por Set,
  — Gates B e C            zero fan-out, zero duplicata.
                         B1-B10 = 10/10 PASS · C1-C7 = 7/7 PASS.
   ↓
DOCUMENTATION-           6129/6130 promovidas para database/migrations/;
CLOSEOUT-01              6842 permanece so em proposals/; docs canonicos reconciliados.
   ↓
CLOSED
```

**Residual de 127 — decisão de produto (2026-09-12):** `KNOWN / INTENTIONAL UNRESOLVED`, `DEFERRED TO FUTURE EDITORIAL UI`, `NON-BLOCKING FOR CARD VARIANTS`. Composição: 8 SVP sem evidência durável suficiente + 119 ambiguidades históricas reais. Preservados **de propósito** como massa real de teste da futura funcionalidade editorial do frontend. Não abrir campanha de resolução residual, backfill adicional nem resolução manual desses 127.

---

## Incidente

Os seis Card Sets ME* têm **0 % de cobertura** de `card_primary_species` — não parcial. Causa provada em `AUDIT-01`, read-only, no LIVE:

```
catalog_import_row para as 752 Cards ........................ 0 linhas
card_external_reference.metadata contendo 'dexId' ........... 0 refs
```

Essas Cards nunca passaram pelo pipeline de importação. Vieram de `database/seeds/840_seed_card.sql` (seed manual, checklist oficial PT-BR, 2026-07-18/21); o `card_external_reference` foi criado depois pela Edge Function `import-card-assets`, que grava `metadata: tcgCard` a partir da **listagem do Set** (`index.ts:973`, tipo `TcgdexCardSummary` em `services/tcgdex.ts:73-78`) — payload que por construção não traz `dexId`.

A `6116` nunca teve o que ler. **Não é regressão da `6116`/`6128`** — é ausência de evidência persistida na origem.

---

## Identidade externa — íntegra

| Medida | Resultado |
|---|---|
| Cards com `card_external_reference` TCGDEX ativa | **752 / 752 (100 %)** |
| `external_card_id` distintos | 752 |
| Colisões / Cards com >1 `external_card_id` | **0** |
| Refs inativas, órfãs ou fora de padrão | **0** |
| Refs totais | 811 (as 59 de MEP têm segunda linha `pt-BR` com o **mesmo** `external_card_id`) |

---

## Classificação — 752 Cards

| Set | Pendentes | AUTO_APPROVED | SOURCE_DATA_ERROR | Ambiguous | No dexId | Not found | No ref | Species missing |
|---|---|---|---|---|---|---|---|---|
| ME1 | 152 | **151** | **1** | 0 | 0 | 0 | 0 | 0 |
| ME2 | 110 | **110** | 0 | 0 | 0 | 0 | 0 | 0 |
| ME2.5 | 243 | **243** | 0 | 0 | 0 | 0 | 0 | 0 |
| ME3 | 91 | **91** | 0 | 0 | 0 | 0 | 0 | 0 |
| ME4 | 97 | **97** | 0 | 0 | 0 | 0 | 0 | 0 |
| MEP | 59 | **59** | 0 | 0 | 0 | 0 | 0 | 0 |
| **TOTAL** | **752** | **751** | **1** | **0** | **0** | **0** | **0** | **0** |

Zero Cards com mais de um `dexId` distinto em todo o universo. 444 Species distintas.

---

## `me01-086` — defeito de dado na fonte, não ambiguidade

A TCGdex publica `name = "Mega Absol ex"` com `dexId = [351]` (Castform). Confirmado pelas **duas vias, que concordam entre si**, em 2026-09-12:

| Via | `name` | `dexId` |
|---|---|---|
| GraphQL `/v2/graphql` `cards(filters:{id:"me01-08"})` | Mega Absol ex | **351** |
| **Detalhe `/v2/en/cards/me01-086`** (endpoint já usado pelo projeto) | Mega Absol ex | **351** |

Detalhe: `category Pokemon`, `localId 086`, `rarity "Double rare"`, `suffix "ex"`, `types ["Darkness"]`, `stage Basic`, `hp 280`, `illustrator "aky CG Works"`. (`/v2/pt-br/…` → HTTP 404.)

**Não há divergência entre caminhos a arbitrar — há um defeito da fonte.**

O fato de domínio está determinado: **Card = Mega Absol ex · Species = Absol · National Dex = 359**. Corroboração, toda da própria fonte e do próprio catálogo:

1. o nome publicado pela TCGdex é "Mega Absol ex";
2. o nome no Mimikyu (seed 840, checklist oficial PT-BR) é "Mega Absol ex" — duas origens independentes concordam;
3. o perfil na fonte (`Darkness`, `hp 280`, `suffix ex`, `Basic`) é **idêntico** ao de `me01-161`, também "Mega Absol ex", cujo `dexId` a própria TCGdex publica como **359**;
4. Castform (351) é tipo Normal, não tem forma Mega e não tem carta ex neste Set.

### Por que não entra na `6129`

A `6115` grava `AUTOMATIC_DEXID`, e o CHECK `chk_card_primary_species_automatic_evidence_shape` (`6112` v1.1) obriga `source_evidence` a conter `"source": "TCGDEX"`, `tcgdex_dex_ids` e `resolved_dex_id`. Injetar 359 produziria uma linha afirmando que **a TCGdex observou 359** — falso, e apagaria o registro do erro.

**Regra aplicada: não falsificar o payload da `6115`.** Na evidência congelada, `me01-086` permanece com `d: 351`, **como observado** — e o guard **G3b** aborta a execução se alguém trocar esse valor.

A resolução entra pela Query **`6130`**, explicitamente editorial, via `admin_resolve_card_primary_species()` (`6114`), preservando **o 351 observado ao lado do 359 decidido**.

Esta Card **não** é caso para a futura UI editorial de ambiguidade — aquela fica reservada às Cards em que a Species realmente não puder ser determinada (hoje, as 119 ambiguidades históricas).

---

## Arquivos

| Arquivo | O quê | Estado |
|---|---|---|
| `6129_backfill_card_primary_species_me_sets.sql` **v2.0** | Backfill automático de **751** Cards via `6115`. Contém a **evidência congelada de 752 itens**. Zero `CREATE`. | **CONFIRMADO EXECUTADO** (2026-09-12) — **promovida** para `database/migrations/`; esta cópia é **evidência histórica de staging** |
| `6130_editorial_resolve_card_primary_species_me01_086.sql` | **Resolução** editorial de `me01-086` → Absol (359) via `6114`, preservando o dado observado da fonte. | **CONFIRMADO EXECUTADO** (2026-09-12, **Caminho B**) — **promovida** para `database/migrations/`; esta cópia é **evidência histórica de staging** |
| `6842_validate_primary_species_me_sourcing.sql` **v2.1** | Validação read-only: manifesto 751 + Gate A · manifesto 752 + Gate B · não-regressão (Gate C). | **CONFIRMADO EXECUTADO / VALIDADO** — §1–§5 executadas, **B1–B10 10/10 PASS**, **C1–C7 7/7 PASS**. **NÃO promovida** (mesmo padrão de `6841`) |

Numeração livre confirmada: maior `6xxx` em `database/schema/` = `6128`; maior `68xx` em `proposals/` = `6841`.

### Governança da promoção (decisão de 2026-09-12)

`6129` e `6130` são **transformações de DADOS executadas**, não definição canônica de schema. Por isso foram promovidas para **`database/migrations/`** e **não** para `database/schema/`. Os corpos executáveis das cópias em `migrations/` são idênticos aos destas cópias de staging — a única diferença está nos cabeçalhos documentais, que declaram o papel de cada arquivo (mesmo padrão já usado em `6128` e `2161`).

`6842` segue o precedente de `6800`/`6810`/`6820`/`6821`/`6841`: script de **validação** permanece exclusivamente em `proposals/` como prova da rodada, nunca é promovido.

**Renomeação:** o arquivo é `6130_editorial_**resolve**_…`, não `…_fix_…`. Não existe linha anterior em `card_primary_species` para esta Card: a `6114` fará **INSERT** e registrará `CARD_PRIMARY_SPECIES_RESOLVED` no action log. O que se corrige é o **dado da fonte**, não um registro do Mimikyu.

---

## A evidência

### Formato — constante JSONB, zero `CREATE`

A evidência vive **dentro da `6129`**, como constante `c_evidencia JSONB` com **752 itens** `{"e": external_card_id, "d": dexId}`, agrupados por Card Set:

```json
{"e":"me01-085","d":342},
{"e":"me01-086","d":351},
{"e":"me01-087","d":442},
```

Todos os guards leem via `jsonb_to_recordset()`. O conjunto-alvo é materializado **uma única vez** numa variável `JSONB` (`v_alvo`). **Nenhum `CREATE`**, nem temporário, em nenhum ponto da Query.

### Estrutura mínima e derivação

Cada item carrega apenas o que **vem de fora** e não pode ser re-derivado: `external_card_id` e `dex_id` observado. `card_id`, `card_set`, `pokemon_species` e `card_name` são **derivados do banco por join**, com guard de totalidade nos dois sentidos (G2b e G2c).

Motivos, registrados e não silenciosos:

1. uma lista de 752 UUIDs transcrita à mão é **inauditável por um revisor humano** e pode divergir do banco sem que nada acuse. `me01-086 → 351` é conferível contra a fonte por qualquer pessoa;
2. o Gate A proibiu executar SQL; obter os 752 `card_id` exigiria um `SELECT`.

O **manifesto por Card com as seis colunas** é emitido pela `6842` — Seção 1 (751 linhas, pós-`6129`) e Seção 3 (752 linhas, pós-`6130`). Ali `card_id` é **fato do banco**, não transcrição.

### Delimitação do universo

A evidência contém **somente** Cards que existem localmente e estão no escopo Primary Species ME*.

```
evidência congelada ............................. 752 itens   (G0)
  pareados 1-para-1 com Card pendente ME* ....... 752         (G2, G2b, G2c)
    AUTO_APPROVED → payload da 6115 ............. 751         (G9)
    SOURCE_DATA_ERROR → me01-086, via 6130 ...... 1           (G3)
```

**Dívida de catálogo registrada, fora deste escopo:** a TCGdex publica **88** Cards Pokémon em `mep`; o Mimikyu tem **59**. As **+29** Cards que existem apenas na TCGdex (`046`–`063`, `072`, `073`, `081`–`088`, `Museum`) **não entram nesta evidência** e **nenhuma Card é criada** por estes artefatos. A composição das 59 é determinada pelo próprio seed canônico — `840_seed_card.sql` cadastra 60 Cards MEP, das quais `028` ("Fanfarra de Celebração") é `TRAINER` → 59 POKEMON —, não por inferência.

---

## Guards da `6129` (fail-closed)

Todos são `RAISE EXCEPTION` dentro de `BEGIN/COMMIT`. Qualquer falha aborta a transação inteira; não existe escrita parcial.

| # | Guard |
|---|---|
| G0 / G0b / G0c | Evidência = **752** itens · 752 `external_card_id` distintos · nenhum item malformado |
| G1 | Baseline `card_primary_species` = **16.657** |
| G2 | Pareamento: **752** Cards no alvo |
| G2b | Nenhuma Card pendente ME* ficou fora do alvo |
| **G2c** | **Nenhum item da evidência ficou sem Card local** — prova que as 29 MEP fora de escopo foram corretamente removidas |
| G3 | `me01-086` presente e classificada `SOURCE_DATA_ERROR` |
| **G3b** | **Evidência congelada de `me01-086` continua sendo `351`** — aborta se alguém "corrigir" para 359 |
| G3c | `me01-086` ainda sem `card_primary_species` |
| G4 | Todo `dexId` resolve para `pokemon_species` ativa |
| G5 / G5b | Sem `card_id` duplicado; sem `external_card_id` → várias Cards |
| G6 | Nenhum `card_id` fora dos seis Card Sets |
| **G7** | **Corroboração por nome = 751/751** — guard antitranscrição |
| G8 | Cardinalidade por Set: 151 / 110 / 243 / 91 / 97 / 59 |
| G9 / G9b | Payload = **751** · ≤ `c_max_batch_size` (10.000) da própria `6115` |
| **G10** | **Prova de exclusão: `me01-086` ausente do payload, verificada por `card_id`** |

### G7 — guard antitranscrição

A evidência foi transcrita da leitura da API para o arquivo. Um `dexId` errado que caísse em outra Species **válida** passaria por todos os guards estruturais. G7 exige que, para as 751 AUTO_APPROVED, o `canonical_name` esteja contido no nome da Card — provado em `AUDIT-01` como **751/751**. Nome aqui é **guard**, não heurística de decisão.

### Assertivas de resultado

`A1` resolved = **751** · `A2–A6` conflict = failed = ambiguous = unresolved = unchanged = **0** · `A7` total = **17.408** · `A8` 751 linhas `AUTOMATIC_DEXID` · `A9` Species gravada == Species da evidência, Card a Card · `A10` `me01-086` **não** foi tocada.

---

## Contrato de `source_evidence` da `6130`

Campos obrigatórios, verificados por `A4`–`A7` da `6130` e por `B5`–`B7` da `6842`:

```json
{
  "reason":                "SOURCE_DATA_ERROR",
  "provider":              "TCGDEX",
  "external_card_id":      "me01-086",
  "observed_name":         "Mega Absol ex",
  "observed_dex_id":       351,
  "resolved_species":      "Absol",
  "resolved_national_dex": 359
}
```

Complementares para rastreabilidade: `observed_at`, `observed_via`, `source_error`, `corroboration`, `mandate`, `not_an_ambiguity`.

**A distinção é o ponto:** `observed_dex_id = 351` é **dado observado da fonte**; `resolved_national_dex = 359` é **decisão editorial corretiva**. A assertiva `A7` proíbe que a evidência editorial contenha `tcgdex_dex_ids` ou `resolved_dex_id` — ou seja, ela **não pode se passar por automática**.

---

## Autenticação da `6130` — restrição estrutural

A `6130` **não pode** rodar como `postgres` anônimo no SQL Editor:

- `6114` exige `public.is_admin()` = `EXISTS (… WHERE id = auth.uid())`;
- `6114` grava `resolved_by_user_id = auth.uid()`;
- `chk_card_primary_species_basis_resolver_coupling` (`6112`) **exige** `resolved_by_user_id IS NOT NULL` quando o basis é `EDITORIAL_RECONCILIATION`.

Sem sessão autenticada, `auth.uid()` é NULL: a função falha no guard e, se passasse, a CHECK rejeitaria a linha. **Uma decisão editorial precisa de responsável nomeado.**

| Caminho | Como | Ressalva |
|---|---|---|
| **A (preferido)** | `supabase.rpc('admin_resolve_card_primary_species', …)` de sessão de administrador real | `auth.uid()` vem da sessão; nada declarado manualmente |
| **B** | SQL Editor com `request.jwt.claims` declarado | `c_admin_user_id` precisa ser o id do **administrador real responsável**, obtido e confirmado no preflight |

### Preflight de identidade (`6130` Seção 2) — read-only

```sql
SELECT count(*) AS total_administradores FROM public.admin_user;

SELECT au.id AS admin_user_id,
       left(u.email,2) || '***@' || split_part(u.email,'@',2) AS email_mascarado,
       au.id = auth.uid() AS e_a_sessao_atual
FROM public.admin_user au
JOIN auth.users u ON u.id = au.id
ORDER BY email_mascarado;
```

E-mail sai **mascarado**; nenhum outro dado pessoal é lido. **A escolha nunca é automática** — mesmo que exista um único administrador, o id é confirmado explicitamente antes de preencher `c_admin_user_id`. Sem preenchimento, o bloco aborta em `P1`. Não usar `service_role`; não usar usuário temporário ou de terceiro.

---

## Ordem de execução e rollback

```
1. 6129 Seção 0   read-only   confirmar current_user = postgres
2. 6129 Seção 1   ESCRITA     BEGIN … COMMIT — 751 Cards, uma única vez
3. 6842 Seção 1   read-only   manifesto 751 — exportar como evidência
4. 6842 Seção 2   read-only   GATE A: 751 automáticas, total 17.408, residual ME* = 1
5. 6130 Seção 1   read-only   pré-check da Card
6. 6130 Seção 2   read-only   preflight de identidade do admin
7. 6130 §3 ou §4  ESCRITA     resolução editorial — Caminho A ou B
8. 6842 Seção 3   read-only   manifesto 752 — registro final
9. 6842 Seção 4   read-only   GATE B: 751 + 1, total 17.409, residual 127
10. 6842 Seção 5  read-only   não-regressão
```

**Rollback.** Não há script e não é necessário: as duas escritas são transacionais e fail-closed. Se qualquer guard ou assertiva falhar, a transação aborta inteira e o banco fica idêntico ao estado anterior. Desfazer **após** um COMMIT bem-sucedido seria um `DELETE` escopado pelos `card_id` do manifesto — deliberadamente **não** preparado aqui; exige mandato próprio.

---

## Projeção

| Momento | `card_primary_species` | Cobertura | Residual |
|---|---|---|---|
| Hoje | 16.657 | 94,99 % | 879 |
| Após `6129` | **17.408** | **99,27 %** | **128** = 1 `me01-086` + 8 SVP + 119 ambiguidades |
| Após `6130` | **17.409** | **99,28 %** | **127** = 8 SVP + 119 ambiguidades |

As duas classes residuais permanecem **separadas**: 8 SVP = sem evidência durável persistida (recuperáveis por sourcing); 119 = ambiguidades reais, que exigem decisão editorial.

---

## Fora de escopo

Não abertos nesta rodada: as 8 Cards SVP; as 119 ambiguidades históricas; a UI editorial; Card Variants; Assets; Collections; a dívida de proveniência; a dívida de observabilidade do hook. O MEP incompleto (88 na fonte × 59 aqui) fica **registrado, não corrigido**.
