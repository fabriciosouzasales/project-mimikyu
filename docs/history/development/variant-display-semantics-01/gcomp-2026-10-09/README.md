# Evidência G-COMP — `VARIANT-DISPLAY-SEMANTICS-01` (2026-10-09)

**Pergunta do gate:** o `rawCount` que a aplicação recebe por carta é a contagem real de `card_variant` no banco? Precisa ser, para poder ser exibido como "variantes cadastradas" (F2.2/F2.3).

**Veredito: PASS** — G-COMP-1, G-COMP-2 e G-COMP-3 iguais nos dois lados.

| Set | Banco: cartas / variantes (`G-COMP-DB-01`) | Aplicação: cartas / Σ `rawCount` | Resultado |
|---|---|---|---|
| ME2.5 | 295 / 630 | 295 / 630 | igual |
| BASE5 | 83 / 167 | 83 / 167 | igual |
| SVE | 24 / 112 | 24 / 112 | igual |

**G-COMP-3 (casos F0), esperado 2/6/6/6:**

| Carta | Banco | Aplicação |
|---|---|---|
| Dark Alakazam BASE5 #01 | 2 | 2 |
| Dark Alakazam BASE5 #18 | 2 | 2 |
| Energia de Grama SVE 001 | 6 | 6 |
| Energia de Escuridão SVE 015 | 6 | 6 |
| Energia de Metal SVE 016 | 6 | 6 |

Dark Alakazam aparece duas vezes no BASE5; as duas cartas têm 2 variantes.

**Verificações adicionais**

- Em todas as cartas dos 3 Sets, `rawCount` é igual à contagem legada.
- `variantView`: 0 `ERROR` e 0 `NONE`.
- Nenhuma carta inativa nesses Sets.

**Risco de truncamento (R7)**

- O maior Set do catálogo é SWSHP, com 300 cartas. Nenhum Set passa de 1.000, o `max-rows` padrão do PostgREST, e o máximo é 9 variantes por carta.
- O `authenticator` não sobrescreve `max-rows` em `rolconfig`.
- `getCartasCompletas` faz uma única consulta por Set, sem paginação. Com isso, a consulta não trunca no volume atual.

**Dívida preservada.** Se algum Set passar de ~1.000 cartas, a consulta precisa de paginação ou `range()`. Esse é o gatilho para revisar.

**Execução**

- **Banco:** `G-COMP-DB-01.sql` (SHA-256 `ff685520…`), um único `SELECT`, executado uma vez pelo Claude via MCP do Supabase com autorização de Fabrício. Resultado em `G-COMP-DB-01.result.json`.
- **Aplicação:** `app-side.json`. HTML da galeria servido por `next dev` em `127.0.0.1:3000` (HEAD `cdb2e5d`), lido no navegador embutido autenticado por Fabrício, sem leitura de cookie.
- **Artefatos do modo dev:** o payload traz uma linha vazia e um segundo elemento `CartasGallery` sem props. A análise usa o único elemento com `cartas`.
- **Cruzamento com o P9:** em ME2.5, o hash de IDs (`726585ce…`) coincide com o medido no P9, em build de produção.
