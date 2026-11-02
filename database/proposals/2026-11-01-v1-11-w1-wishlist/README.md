# V1-11 W1 — Lista de desejos (Wishlist): fundação física e operações essenciais

| Campo | Valor |
|---|---|
| **Status** | **5345, 5346 e 5347 CONFIRMADO EXECUTADO no LIVE** (LIVE SQL EXECUTION & VALIDATION-03; ledger `20261102005834` / `20261102005920` / `20261102005936`; corpos das 6 funções com md5(prosrc) idêntico aos arquivos). Harness `5873` v1.0 executado: **17/17 checagens PASS**, sem X.1, resíduo zero; GATE impresso FAIL apenas por constante errada (16) — corrigida na v1.1, **não reexecutada**. **Promovidas byte-idênticas para `database/schema/` (2026-11-02, `FINAL CLOSEOUT & CONTROLLED COMMIT-06`)**; harness `5873` permanece aqui. W1 encerrada; publicação pendente. |
| **Autoridade** | `docs/domain-modeling/collections/wishlist-product-contract.md` v1.1 (W0 aprovado, commit `559a4f3`); C-91–C-102, C-210–C-219; LDM-79–LDM-90, LDM-204–LDM-208. Nenhuma decisão reaberta. |
| **Execução** | Por Fabrício, uma Query por vez, na ordem abaixo, só com autorização explícita. |

## Arquivos e ordem

| Ordem | Query | Objeto | Natureza |
|---|---|---|---|
| 1 | `5345` | `card_wishlist_entry` (tabela, RLS, grants) | DDL |
| 2 | `5346` | `add_my_wishlist_entry`, `remove_my_wishlist_entries`, `get_my_wishlist_state_by_variant`, `get_my_wishlist_state_by_card`, `get_my_wishlist` | funções |
| 3 | `5347` | `get_my_wishlist_summary` | função |
| 4 | `5873` | harness (pg_temp, sentinela TR000, resíduo zero) — GATE 17/17 (v1.1) | validação |

Dependências: `card_variant`, `card`, `card_set`, `language`, `inventory`, `physical_card`, `card_asset*`, `card_variant_type`, `card_printing_profile`, `card_edition_context_profile` e `get_card_variants_pricing_summary` (3983) — todos já no LIVE.

## Decisões de implementação (dentro do contrato)

- **Identidade** `id uuid` estável; **unicidade** `(user_id, card_variant_id, language_id) NULLS NOT DISTINCT` — "qualquer idioma" (`NULL`) é valor próprio (C-99); repetir a inclusão devolve a mesma entrada (`created = false`).
- **Variante inativa** (C-214): inclusão recusada (`P0002 CARD_VARIANT_UNAVAILABLE`); entrada existente permanece, sinalizada (`variant_available = false`) e removível. FK `RESTRICT` impede sumiço silencioso.
- **Privacidade** (C-217): RLS só do dono; escrita só pelas funções `SECURITY DEFINER`; o cliente nunca envia `user_id`; nenhuma leitura pública/compartilhada expõe a lista.
- **Sem vínculo estrutural** (C-211): nenhuma coluna de coleção/fichário/bolso/posição; nenhuma função lê Collection/Binder.
- **Posse** (C-213): quatro níveis derivados na leitura, nunca gravados.
- **Preço** (C-216): por desejo, a interface usa o endpoint V1-09 existente (`/api/colecoes/precos`, 3983); o agregado soma **uma** referência por variante distinta, com cobertura sobre variantes distintas e `NULL` sem cobertura. Pricing inalterado.
- **Leituras para integrações futuras**: estado em lote por variante (Acervo, Fichário, Master Set) e por carta (Pesquisa, Set, Pokédex). A seleção explícita de variante usa a `5163` existente.

## Validação já feita (sem escrita no LIVE)

- A lógica de leitura de `get_my_wishlist` (junções de catálogo, rótulo de variante, imagem e os quatro níveis de posse) foi conferida no LIVE por uma consulta somente leitura com linhas simuladas em CTE — sem criar objetos nem gravar dados.
- A sintaxe completa das funções **não** foi executada (não há PostgreSQL no sandbox e a execução no LIVE não foi autorizada). Gate real = `5873` após a aplicação.

## Riscos registrados

- `get_my_wishlist_summary` chama a 3983 em blocos de 100: custo proporcional às variantes distintas do usuário (mesmo padrão da 5340).
- O preço por desejo vem do endpoint em lote do V1-09 (mesma regra, mesma cache); o agregado vem do banco — ambos da 3983, sem regra duplicada.
- Fora deste incremento (W2+): entradas Set, Master Set, Pokédex e Fichário; filtros/ordenações da página (Set, posse, idioma, "falta em alguma coleção"); inclusão de faltantes em lote; sugestão de remoção após registrar no acervo (C-213); lacunas L2/L3/L6.

## SQL READINESS & UX CORRECTION-02 (2026-11-01)

- **Revisão direcionada de 5345/5346/5347/5873:** autorização por `auth.uid()` em todas as funções (28000 sem sessão), RLS só do dono, nenhuma escrita direta pela API, EXECUTE só `authenticated`, `search_path` vazio e objetos qualificados; unicidade `(user, variante, idioma)` NULLS NOT DISTINCT com `ON CONFLICT … DO NOTHING` + releitura (idempotente e segura sob concorrência); remoção só de linhas do próprio usuário, idempotente; valor NM somado uma vez por variante distinta (`array_agg(distinct …)` + 3983, que também deduplica); variante inativa recusada na inclusão, mantida na leitura e removível. **Nenhum defeito comprovado — SQL inalterado.**
- **Correção de UX (frontend):** desmarcar a variante na grade (Acervo/Pesquisa) só remove quando há exatamente **um** desejo dela; com desejos em mais de um idioma nada é removido, o marcador volta a marcado e a mensagem leva à Lista de desejos. Inclusão e o clique único com um desejo continuam iguais.
- **Endurecimento menor:** a confirmação de inclusão exige `entry_id` devolvido (corrida rara com remoção simultânea passa a ser "não confirmado").

## Execução controlada no LIVE (por Fabrício, uma etapa por vez)

| Etapa | O quê | Esperado |
|---|---|---|
| 0 | Pré-checagem somente leitura (abaixo) | `true / 0 / 2 / true` |
| 1 | `5345` (arquivo inteiro; via `apply_migration` sem `begin;`/`commit;`) | sucesso; validação do rodapé `t / 1 / f / f` |
| 2 | `5346` | sucesso; 5 funções |
| 3 | `5347` | sucesso |
| 4 | `5873` (uma chamada; cria e desfaz o próprio cenário) | 17 linhas `PASS` + `GATE PASS 17/17`; nenhuma `X.1`; `9.1` resíduo zero |
| 5 | Pós-checagem somente leitura (abaixo) | `0` desejos; 6 funções `SECURITY DEFINER`; advisors sem achado novo |

Pré-checagem (etapa 0):

```sql
select to_regclass('public.card_wishlist_entry') is null as tabela_ausente_ok,
       (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.proname like '%wishlist%') as funcoes_wishlist,
       (select count(*) from public.language where is_active) as idiomas_ativos,
       to_regprocedure('public.get_card_variants_pricing_summary(uuid[])') is not null as preco_3983_ok;
-- Esperado: true | 0 | 2 | true
```

Pós-checagem (etapa 5):

```sql
select (select count(*) from public.card_wishlist_entry) as desejos,
       (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.prosecdef
           and p.proname in ('add_my_wishlist_entry','remove_my_wishlist_entries','get_my_wishlist_state_by_variant',
                             'get_my_wishlist_state_by_card','get_my_wishlist','get_my_wishlist_summary')) as funcoes_secdef,
       (select bool_and(not has_function_privilege('anon', p.oid, 'EXECUTE')) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.proname like '%wishlist%') as anon_sem_execute;
-- Esperado: 0 | 6 | true
```

Parar na primeira divergência. Qualquer falha em 1–3: não seguir; reportar a mensagem. Falha no 5873: não usar a interface; reportar as linhas FAIL.

## Como reverter

`DROP FUNCTION` das seis funções (5347, 5346) e, sem desejos a preservar, `DROP TABLE public.card_wishlist_entry` (5345).
