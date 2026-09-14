# Edge `import-card-variants` — staging do lookup com escopo

**Mandato:** CARD-VARIANTS — EDITORIAL-CONVERGENCE-16 / SOURCE-SET-SCOPED-FOUNDATION / GATE-A-REV-01 §9–§10
**Status:** PROPOSTA — NÃO APLICADA. `supabase/functions/import-card-variants/` **não foi tocada.**
**Versão:** 2.0 (a v1.0 era contrato conceitual; esta traz patch executável e corrige duas premissas erradas)

---

## O que mudou da v1.0 para a v2.0

A v1.0 deste arquivo **não era prova suficiente para o Gate A** — era um diff conceitual em prosa. O REV-01 §9 rejeitou isso. Agora existem artefatos executáveis:

| arquivo | o que é |
|---|---|
| `2026-09-14-variant-source-set-scope.patch` | patch unified aplicável com `git apply` |
| `variant-scope-vectors.test.ts` | runner Deno dos vetores P1–P10, importando o código **real** da Edge |

Este arquivo passa a ser só o índice e o registro das decisões.

---

## Duas premissas da v1.0 que a auditoria do código real derrubou

### 1. "A Edge usaria o `external_set_id` do job, e isso seria errado" — **FALSO**

A v1.0 afirmava que o valor à mão na Edge era o do job, e que usá-lo seria a escolha natural e errada.

Auditado no código, 2026-09-14:

- `index.ts:418` → `findCardSetExternalReference(supabase, cardSetId, assetSource.id)`
- `database.ts:67-74` → essa função filtra **`.eq("is_active", true)`**
- `index.ts:425` → `externalSetId` := referência canônica **ativa**
- `index.ts:429` → o job é **criado** com esse valor

A Edge **já** trata `card_set_external_reference` como autoridade; o `job.external_set_id` **nasce** dela. O valor à mão **é** o canônico.

**Consequência:** o guard `VARIANT_IMPORT_SCOPE_MISMATCH` previsto para a Edge seria **código morto** no caminho de criação. Ele permanece necessário só no SQL (contrato da Query 2192), que opera sobre jobs **já gravados** e pode encontrar um job adulterado por fora da Edge — é lá que o caso **N** do harness 2826 o exercita.

### 2. "`types.ts` precisa de um tipo com `external_set_id`" — **FALSO**

Auditado: não existe tipo declarado para a linha de mapping. O código usa `.map((row: any) => ...)`. Não há tipo a estender.

**Consequência:** o patch toca **dois** arquivos, não três.

---

## Decisão de escaping do PostgREST (§9)

O desenho original estreitaria a query no servidor com
`.or("external_set_id.is.null,external_set_id.eq.${scope}")`.

| opção | veredito |
|---|---|
| **A.** interpolar o valor cru | **rejeitada** — na gramática do `.or()` do PostgREST, vírgula e parênteses são **estrutura**, não literal. Um valor que os contenha muda a árvore do predicado. `external_set_id` é TEXT livre da fonte; o CHECK só proíbe string em branco. Sem prova de que todo valor é inofensivo, o mandato veda. |
| **B.** quotar com `"` e escapar `"`/`\` | **rejeitada** — funciona, mas amarra o código a um detalhe de quoting do PostgREST fora do nosso controle, e passa a exigir um teste de escaping para uma otimização de que não precisamos. |
| **C.** não filtrar escopo no servidor; particionar no cliente | **ESCOLHIDA** |

**Por que C.** A query fica idêntica à de hoje (`.eq(game_id).eq(asset_source_id)`), só com `external_set_id` a mais no SELECT. Continua **uma** query por job — zero round-trip novo. O conjunto é pequeno: **70 mappings** no LIVE em 2026-09-14. A superfície de escaping vai a **zero**: não existe valor de dado capaz de alterar a consulta.

---

## Os dois pontos do diff

1. **`listVariantTypeExternalMappings`** ganha o parâmetro `scopeExternalSetId` e devolve `{ globalMap, scopedMap }`, particionados em memória. Escopos de **outros** Sets são descartados — espelho do isolamento provado pelo vetor P3.

2. **Lookup em `index.ts`** vira dois níveis:
   `scopedMap.get(k) ?? globalMap.get(k) ?? null` — `??` e não `||`.

**`buildVariantComboKey` permanece inalterada.** O escopo separa os **mapas**, não entra na **chave** — assim a correspondência 1:1 com a expressão dos índices parciais da Query 2191 fica preservada e a única função já provada contra a UNIQUE não é reescrita.

---

## Paridade Edge × SQL (§10)

`variant-scope-vectors.test.ts` consome `../test-vectors/variant-type-mapping-scope-vectors.json` — o **mesmo** arquivo do runner SQL da Seção 4 do 2826, com o **mesmo** bloco `bindings`.

Três garantias que tornam a paridade verificável em vez de afirmada:

- o teste **importa o código real** da Edge e injeta um stub do client; não reimplementa a lógica;
- o caso `PARIDADE_INLINE` lê `index.ts` e confirma que a expressão de lookup copiada no teste **ainda é** a expressão de produção, com guard negativo contra o retorno de `||`;
- o caso `COBERTURA` reprova se o arquivo de vetores encolher ou os ids mudarem.

Os `expected` existem só no JSON. Nenhum dos dois runners declara o seu.

---

## Ordem de aplicação no GATE-B

1. aplicar as Queries 2191–2197 no banco;
2. `git apply --check` do patch → se falhar, **rebasear** (não resolver no olho);
3. `git apply`;
4. `deno test --allow-read .../edge/variant-scope-vectors.test.ts` → 12 testes (10 vetores + PARIDADE_INLINE + COBERTURA);
5. executar o harness 2826 com o payload de vetores carregado;
6. **deploy** da Edge — passo manual separado, fora do Gate B de banco.
