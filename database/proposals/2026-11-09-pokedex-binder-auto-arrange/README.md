# Proposta — Organização automática do fichário para Pokédex (2026-11-09)

**Status:** CONFIRMADO EXECUTADO no LIVE em 2026-11-09 (autorização do proprietário); canônica em `database/schema/5360_extend_binder_auto_arrange_to_pokedex.sql`. Pós-aplicação: assinaturas Set/Master Set idênticas; ACLs preservadas (plano sem EXECUTE para API; prévia e confirmação só `authenticated`).

## Query 1 — Pokédex na organização automática

**Objetivo:** estender a organização automática (P2: 5342/5343/5344) às coleções Pokédex
(`REFERENCE_POSITION`). O bolso de cada espécie (referências 5257–5260) que esteja vazio e livre
recebe a **representante** da espécie (mesma regra da grade 5204: representante escolhida, senão o
vínculo mais antigo), entre os exemplares da coleção guardados no local do fichário e ainda sem
bolso. As demais cópias ficam em "Cartas disponíveis" (decisão do proprietário, 2026-11-09).

**Script SQL:** `01_pokedex_binder_auto_arrange.sql` (uma transação: `CREATE OR REPLACE` das três
funções; ACLs preservadas).

Mudanças:

- 5342 `binder_auto_arrange_plan`: CTEs `kind_`, `dex_slots`, `all_slots`, `dex_rep`; `cands` ganha
  a espécie vinculada (`dpos`); `pairs` ganha o ramo Pokédex; novo motivo de exclusão
  `NOT_REPRESENTATIVE`. Bolsos de espécie sem carta não geram `UNFILLED_SLOT`. Fórmula do token
  inalterada (`aa1.2`).
- 5343/5344: os três gates aceitam também `REFERENCE_POSITION`.

**Resultado esperado:** Set/Master Set com plano e token idênticos aos de hoje; Pokédex passa de
`EMPTY` (hoje rejeitada) para `READY` com as representantes do fichário.

**Dry-run (2026-11-09, rollback):** as 7 coleções Set/Master Set com fichário tiveram a mesma
assinatura (md5 de todas as linhas do plano, inclusive token) antes e depois; a Pokédex com
fichário passou a 23 inserções, 0 exclusões. Funções LIVE conferidas inalteradas após o rollback.

**Como validar (após executar):**

```sql
select p.proname, md5(p.prosrc)
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('binder_auto_arrange_plan','preview_my_binder_auto_arrange','apply_my_binder_auto_arrange');
-- e: a prévia na tela do fichário da Pokédex mostra "N cartas prontas para o seu lugar".
```

Depois de confirmado: promover para `database/schema/` (nova numeração), atualizar o contrato
`binder-auto-arrange-contract.md` (v1.6) e o log.
