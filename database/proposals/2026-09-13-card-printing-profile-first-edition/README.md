# Staging — Card Printing Profile (First Edition)

| Campo | Valor |
|---|---|
| **Ciclo** | `CARD-VARIANTS — PRINTING PROFILE / FIRST EDITION` (2026-09-13) |
| **Status** | **PROMOVIDO** — pasta mantida como evidência histórica do staging |

README criado em 2026-09-18 por `BULK-STP-01-CANONICAL-RECONCILIATION-IMPLEMENTATION-01`: este ciclo não tinha README próprio, e a reconciliação canônica precisa deixar registrado, aqui, para onde cada Query foi.

---

## Reconciliação canônica — 2026-09-18

`BULK-STP-01-CANONICAL-RECONCILIATION-IMPLEMENTATION-01` classificou cada Query
deste ciclo por **natureza**, e não em bloco. Esta pasta permanece como
**evidência histórica** do staging; a fonte executável passou a ser:

| Query | Natureza | Destino |
|---|---|---|
| `2188` | alteração incremental (3 CHECK de `catalog_admin_action_log`) | `database/migrations/2188_...` · estado terminal em `database/schema/2010_...` **v2.0** |
| `2189` | criação canônica (worker + RPC) | `database/schema/2189_...` **v3.0** (já com o fold-in de `2190` e da parte alteradora de `2196`) |
| `2190` | correção permanente de função canônica | `database/migrations/2190_...` · dobrada em `database/schema/2189_...` v3.0 |

**Correção de cabeçalho:** `2188`, `2189` e `2190` declaravam `PROPOSTA — NÃO
EXECUTADA` apesar de estarem no ledger LIVE desde 13–14/09. Os três cabeçalhos
foram corrigidos; nenhuma linha de SQL foi alterada.

Nada foi reexecutado contra o Supabase nesta rodada — promoção canônica e
fold-in são alteração de arquivo, não execução (ver `database/README.md`,
seção "Queries `CANÔNICA` vs. `MIGRATION`").
