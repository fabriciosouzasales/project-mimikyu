# V1-10 — Favoritos de cartas

| Campo | Valor |
|---|---|
| Frente | V1-10 FOUNDATION & IMPLEMENTATION-02 |
| Status | **5335/5336 CONFIRMADO EXECUTADO no LIVE — EXECUTION-04 (2026-10-31): LIVE VALIDATED — READY FOR LOCAL HOMOLOGATION.** Ledger `20261031213144` (5335) e `20261031213231` (5336); md5(prosrc) das 4 funções = arquivo; harness 5868 v1.1 GATE 15/15 PASS, sem X.1, resíduo zero; `NOTIFY pgrst, 'reload schema'` enviado. P6, 5332–5334 e `remove_my_physical_card` inalterados (md5 = baseline). Preflight: a base vigente de `remove_my_physical_card` é a 5289 (P3B-S5, corpo = LIVE), não a 5165 citada no harness — só referência documental, contrato idêntico. READINESS-05: REST confirmado pelo navegador (4 funções no cache do PostgREST; anônimo 42501 nas 4 e na tabela; função inexistente PGRST202); `5335`/`5336` promovidas a `database/schema` (cópia idêntica). Pendentes: homologação do proprietário (incl. "×N" no canto inferior direito do Acervo; chamada autenticada no navegador local), commit/push/deploy. Frontend local, sem commit. |
| Data | 2026-10-31 |
| Autoridade | C-82–C-90 / LDM-70–LDM-78 (inalteradas). Precedente físico: Espécie favorita da Pokédex P6 (6136/6137). |
| Arquivos | `5335_create_card_favorite_table.sql`, `5336_create_card_favorite_functions.sql`, `5868_validate_card_favorites.sql` v1.1 (harness, GATE 15) |
| Numeração | 5335, 5336 e 5868 conferidas livres em `database/` e `docs/` |

## Modelo

`card_favorite (user_id, card_id, created_at)` — PK (user_id, card_id); FK usuário ON DELETE CASCADE; FK carta ON DELETE RESTRICT (C-90: o favorito não some em silêncio); índices (user_id, created_at desc, card_id) para a página e (card_id) para a FK. RLS com uma policy SELECT só das próprias linhas; `authenticated` só SELECT; nenhuma escrita direta pela API.

## Funções (todas `SECURITY DEFINER`, `search_path ''`, identidade só de `auth.uid()`, EXECUTE só `authenticated`)

| Função | Uso | Limites / erros |
|---|---|---|
| `set_card_favorite(uuid, boolean) → boolean` | Definir (não alternar), idempotente; única escrita | 22023 estado/carta nulos; P0002 carta inexistente (ou inativa ao favoritar) |
| `get_my_card_favorite_ids(uuid[]) → (card_id)` | Marcar grade da Pesquisa | 1..500 ids; 22023 |
| `get_my_card_favorites_by_variant(uuid[]) → (card_variant_id, card_id, is_favorite)` | Marcar grade do Acervo (a leitura 5220 só traz a variante e `card_variant` não é legível pelo usuário) | 1..500 ids; 22023 |
| `get_my_favorite_cards(int, int) → página` | Cartas favoritas, mais recentes primeiro, só cartas ativas, imagens como a `search_cards` | limite 1..100, offset 0..100000; 22023 |

A quarta função (por variante) não estava na lista inicial: é necessária porque o tile do Acervo não conhece o `card_id`. Não lê o acervo — só catálogo (identidade pública já exposta pela `search_cards`) e os favoritos do próprio usuário.

## Frontend (local)

- `web/lib/favorites/` — regras puras (máquina de intenção da P6 reaproveitada por import, sem alterar a P6; 6 testes) e leituras em lote.
- `web/app/colecoes/favoritos/` — página `/colecoes/favoritos` e server actions (`setCardFavorite`, `readCardFavoriteIds`).
- `web/components/favorites/` — botão-coração (o `FavoriteHeartIcon` da P6), controlador por delegação, hook da Pesquisa, grade da página.
- Pesquisa: coração no canto superior direito de cada carta; uma leitura em lote por leva de resultados.
- Acervo: coração no canto superior direito; o "×N" desceu para o canto inferior direito (preço continua no inferior esquerdo); coração oculto no modo seleção.
- Menu Coleções → "Cartas favoritas".

## Publicação (ordem)

1. ~~Aplicar 5335 e 5336~~ — feito (EXECUTION-04, 2026-10-31).
2. ~~Executar 5868~~ — GATE 15/15, resíduo zero.
3. ~~`NOTIFY pgrst, 'reload schema';`~~ — enviado.
4. Homologação local (Pesquisa, Acervo, Cartas favoritas; desktop/mobile; claro/escuro; teclado).
5. ~~Promover 5335/5336 a `database/schema`~~ — feito (READINESS-05). Commit/push/deploy com autorização própria.

Frontend antes do banco: as leituras falham com `PGRST202`, são registradas em `favorites.cards.read`, as grades aparecem sem corações marcados e o clique mostra "Os favoritos estão indisponíveis no momento".

## Rollback

Reverter o commit do frontend. `DROP FUNCTION` das quatro funções e `DROP TABLE public.card_favorite;` (somente se não houver favoritos a preservar).

## CORRECTION-09 — "Coleções com favoritas" (5337 CONFIRMADO EXECUTADO no LIVE, 2026-10-31) — SUBSTITUÍDA pela CORRECTION-13

**EXECUTION-11:** 5337 aplicada (ledger `20261031224148`, md5 = arquivo, SECURITY DEFINER, `search_path` vazio, EXECUTE só `authenticated`); 5869 v1.1 GATE 9/9 PASS, resíduo zero; `NOTIFY pgrst`; REST: anônimo 42501 (função reconhecida). Preflight: `archive_collection` no LIVE difere da 5037 só por 3 linhas de comentário (código idêntico). Promoção a `database/schema` pendente de autorização.

| Arquivo | Conteúdo |
|---|---|
| `5337_create_get_my_favorite_collection_count_function.sql` | `get_my_favorite_collection_count() → integer`: coleções ativas do próprio usuário com ≥ 1 exemplar alocado de uma carta favorita (ativa). `SECURITY DEFINER`, `search_path ''`, `auth.uid()` (28000), STABLE, EXECUTE só `authenticated`. Uma consulta: coleções do dono (ix owner/lifecycle) + `EXISTS` por alocações (ix collection_id) → exemplar → variante → favorito (PK) → carta |
| `5869_validate_favorite_collection_count.sql` | Harness **v1.1** (GATE 9; AUDIT-10: cartas X/Y no Game da coleção, resíduo com locais e memberships): configuração, ACL, anon 42501, sem identidade 28000, sem favoritos = 0, duas favoritas na mesma coleção = 1 (vazia, sem favoritas, arquivada, compartilhada e exemplar sem coleção fora), mesma favorita em 3 coleções = 3, isolamento A/B, resíduo zero |

Regras propostas: arquivadas fora (estante, 5182); compartilhadas com você fora (C-157). Rollback: `DROP FUNCTION public.get_my_favorite_collection_count();`. Ordem: auditoria → aplicar 5337 → 5869 → `NOTIFY pgrst`. **AUDIT-10 (2026-10-31): READY FOR CONTROLLED LIVE EXECUTION** — 5337 sem defeito; 5869 corrigida para v1.1 (fixture). Revisão estática, sem Postgres no ambiente do agente.


## CORRECTION-13 — 4º indicador: "Card Sets — com cartas favoritas" (PROPOSTA, 2026-10-31)

Correção de requisito: o 4º indicador conta **Card Sets**, não coleções. "Coleções com favoritas" (CORRECTION-09) foi interpretação errada.

**5337:** permanece no LIVE (CONFIRMADO EXECUTADO, ledger `20261031224148`), **substituída e sem consumidor** — o frontend não a chama mais. Sem DROP e sem mudança de corpo (fora do escopo autorizado); não promovida a `database/schema` (a cópia iniciada na DECISION-12, interrompida pelo proprietário, foi removida). Não é evidência para o indicador de Card Sets. Remoção futura, se desejada: `DROP FUNCTION public.get_my_favorite_collection_count();` com autorização própria.

| Arquivo | Conteúdo |
|---|---|
| `5338_create_get_my_favorite_card_set_count_function.sql` | `get_my_favorite_card_set_count() → integer`: `count(distinct card.card_set_id)` das favoritas do usuário com carta ativa. `SECURITY DEFINER` (card é restrita por RLS), `search_path ''`, `auth.uid()` (28000), STABLE, EXECUTE só `authenticated`. Uma consulta: favoritos pelo prefixo da PK `(user_id, card_id)` → carta pela PK. Não lê acervo nem coleções |
| `5870_validate_favorite_card_set_count.sql` | Harness **v1.1** (GATE 9): configuração, ACL, anon 42501, sem identidade 28000, sem favoritas = 0, 7 favoritas do mesmo Set = 1 (sem exemplar nem coleção), outro Set = 2, carta inativa fora, isolamento A/B (incl. desfavoritar), resíduo zero |

Por que função nova: `get_my_favorite_cards` (5336) só traz `card_set_code` por página — contar exigiria paginar todas as favoritas no cliente — e `card` não é legível pelo usuário. Frontend: `getMyFavoriteCardSetCount` substitui `getMyFavoriteCollectionCount`; até a 5338 existir no LIVE a leitura falha com `PGRST202` e o indicador mostra "—" ("indisponível agora").

Ordem: auditoria SQL → aplicar 5338 → 5870 → `NOTIFY pgrst, 'reload schema'` → homologação local. Rollback: `DROP FUNCTION public.get_my_favorite_card_set_count();`.

**SQL READINESS-14 (2026-10-31, revisão estática — nada executado):** 5338 sem defeito (identidade só de `auth.uid()`; `count(distinct card_set_id)` sobre o join favorito → carta ativa; 0 legítimo sem favoritas; nenhuma tabela de acervo/coleção; PK de `card_favorite` + PK de `card`; SECURITY DEFINER, `search_path ''`, EXECUTE só `authenticated`; chamada do frontend sem argumentos, retorno inteiro). 5870 corrigida para **v1.1**: a desativação transacional da carta do caso inativo passa a exigir `row_count = 1` (senão TR_FIXTURE → X.1) e o comentário passa a citar os dois triggers de `card` (141; o de consistência de Game não dispara para `is_active`). 5337 sem consumidor no frontend, sem DROP previsto. **READY FOR CONTROLLED LIVE EXECUTION.**

**CONTROLLED LIVE EXECUTION-15 (2026-10-31) — STOP.** Preflight sem divergência (5338 ausente; md5 das 4 funções da 5336 e da 5337 = baseline; `card` com os dois triggers da 141, sem regras, dono `postgres`, sem FORCE RLS; 21.246 cartas, 1 inativa — Set SVP —, usada pelo caso 3.4: nenhum UPDATE no catálogo). **5338 CONFIRMADO EXECUTADO** (ledger `20261031230439`; md5(prosrc) `9659f61d…` = arquivo; sem argumentos, integer, SECURITY DEFINER, `search_path ''`, STABLE, `auth.uid()`; ACL `postgres` + `authenticated`, anon e PUBLIC sem EXECUTE; 1 versão). **5870 v1.1:** as 10 checagens deram PASS (0.1, 0.2, 1.1 = 42501, 2.1 = 28000, 3.1 = 0, 3.2 = 1, 3.3 = 2, 3.4 = 2 com carta já inativa, 3.5 = B 1 / A 2 / A 1 / B 1, 9.1 resíduo zero), sem X.1, mas **GATE = FAIL** por defeito do harness: ele exige `n = 9` e tem 10 checagens (contagem errada desde a CORRECTION-13, não pega na READINESS-14). Pelos critérios da rodada: STOP, harness não alterado, `NOTIFY pgrst` **não enviado**, REST não verificado. Postcheck: 0 usuários sintéticos; usuários, favoritos e estado de `card` (md5 de id/is_active/updated_at) iguais ao baseline; 5335 (RLS + 1 policy), 5336 e 5337 inalteradas; sem locks residuais. A 5338 permanece no LIVE (sem rollback automático). Correção proposta para nova autorização: GATE `n = 10` (v1.2) e nova execução, ou aceitar o resultado 10/10 por decisão do proprietário.

**GATE COUNT ACCEPTANCE & API CLOSEOUT-16 (2026-10-31).** Decisão do proprietário, registrada formalmente: **`ACCEPTED BY INDEPENDENT REVIEW — 10/10 CHECKS PASS; GATE COUNT CONFIGURATION DEFECT`**. A execução original da v1.1 (EXECUTION-15) **continua registrada como GATE FAIL**, sem reclassificação retroativa. A causa foi a expectativa `n = 9` num harness de 10 checagens. A evidência aceita são as 10 checagens individuais PASS, sem X.1, com resíduo zero. **5870 v1.2 preparada e NÃO EXECUTADA:** em relação à v1.1, só muda a expectativa do GATE (`n = 10` e "esperado 10") mais cabeçalho e histórico. Diff do corpo: 2 linhas; consultas, fixtures, checagens e exceções idênticas; 10 identificadores presentes (0.1, 0.2, 1.1, 2.1, 3.1–3.5, 9.1) mais o X.1 de erro. `NOTIFY pgrst, 'reload schema'` enviado. REST com a chave pública:
- `rpc/get_my_favorite_card_set_count` → HTTP 401, 42501 (função reconhecida, anônimo sem permissão);
- controle com nome inexistente → PGRST202, com a dica "Perhaps you meant … get_my_favorite_card_set_count".

Estado final: md5 da 5338 = aplicado (`9659f61d…`); ACL `postgres` + `authenticated`; 5336 e 5337 inalteradas; 5337 sem consumidor no frontend; 0 usuários sintéticos; favoritos e estado de `card` iguais ao baseline. **LIVE ACCEPTED BY INDEPENDENT REVIEW — READY FOR LOCAL KPI HOMOLOGATION.** Pendentes: homologação local do KPI 4; promoção da 5338 para `database/schema` (autorização própria); commit/push/deploy.

## DATA CONTRACTS-17 — KPIs "Valor de referência" e "No meu acervo" (PROPOSTA, 2026-10-31)

**5338 promovida a `database/schema`** (cópia idêntica à proposta; md5(prosrc) `9659f61d…` = LIVE, conferido na CLOSEOUT-16).

**No meu acervo (5339 `get_my_favorite_owned_count() → integer`).** Conta os `card_id` favoritos ativos com pelo menos um `physical_card` no Inventory do próprio usuário (`inventory.owner_user_id = auth.uid()`, 1:1). Cópias, variantes e idiomas contam uma vez (a unidade é a linha de `card_favorite`). Não lê Collection, Binder nem Storage; coleções compartilhadas nunca entram. Sem Inventory: 0. Custo: favoritas do usuário via prefixo da PK → `EXISTS` (`card_variant (card_id, …)` UNIQUE → `ix_physical_card_inventory_variant`). Nenhum contrato existente servia: as leituras do Acervo (5159–5162) são paginadas por variante + idioma.

**Valor de referência (5340 `get_my_favorite_reference_value() → (favorite_count, priced_count, total_brl)`).**
- **Fonte canônica:** `get_cards_pricing_summary` (3968 + 3972), a mesma da Pesquisa. Devolve uma referência por `card_id` em BRL:
  - NM, MARKET, mapeamento e identidade CONFIRMED;
  - hierarquia de impressão: Normal > Holofoil > Reverse Holofoil > Unlimited > Unlimited Holofoil > 1st Edition > 1st Edition Holofoil;
  - observação mais recente;
  - PTAX da data da observação;
  - fallback manual;
  - sem idioma.
- **Regra:** soma de uma referência por favorita ativa coberta. Nunca multiplica por exemplares (o Inventory não é lido). Cobertura X de Y; `total_brl` é NULL sem cobertura.
- **Execução:** a função canônica é chamada em blocos de 100 dentro do banco, então a regra de preço não é duplicada.
- **Limitação registrada:** a 3972 não devolve `observed_at`, então não há janela de validade. A Pesquisa também não aplica janela; os 14 dias da V1-09 valem para preço por variante (3983), não para esta referência.
- **Câmbio:** carta com observação mas sem PTAX conta como sem cotação.

**Harness 5871 (v1.0: 19 checagens; v1.1: 20 — ver READINESS-18; GATE por identificadores, sem contagem escrita à mão):**
- configuração, ACL, anon 42501 e 28000 nas duas funções;
- No meu acervo:
  - nenhuma favorita → 0;
  - 3 exemplares, 2 variantes e 2 idiomas → 1;
  - exemplar de outro usuário não conta;
  - carta inativa fora;
  - remover exemplares → 0;
  - corpo da 5339 sem collection/binder/storage;
- Valor de referência:
  - 105 favoritas em 2 blocos, iguais à função canônica chamada diretamente, com 0 < priced < 105;
  - exemplares não multiplicam;
  - carta inativa fora;
  - isolamento entre usuários;
- resíduo zero.

Frontend local: KPIs 2 e 3 ligados às duas leituras; leitura indisponível → "—"; sem cotação → "—" com "0 de Y com cotação", nunca "R$ 0". Ordem: auditoria SQL → aplicar 5339 e 5340 → 5871 → `NOTIFY pgrst` → homologação. Rollback: `DROP FUNCTION` de cada uma. **Nada executado.**

**SQL READINESS-18 (2026-10-31, revisão estática — nada executado).**
- **5339:** sem defeito.
  - Identidade só de `auth.uid()`; Inventory resolvido pelo UNIQUE `owner_user_id`.
  - Encadeamento `card_favorite` → `card` ativa → `EXISTS` (`card_variant.card_id` → `physical_card` do Inventory do usuário); cópias, variantes e idiomas não duplicam.
  - Não lê Collection, Binder nem Storage. Retorna 0 legítimo.
  - Índices: PK de `card_favorite`, UNIQUE `(card_id, variant_type_id)` de `card_variant`, `ix_physical_card_inventory_variant`.
- **5340 → v1.1:** referência **≤ 0** não conta como cotação, porque `pricing_observation` e `pricing_manual_price` aceitam `price = 0` (`CHECK >= 0`). É regra só deste KPI; a 3972 não muda.
- **Performance da 5340 (estimativa, não medida):**
  - custo linear de ⌈Y/100⌉ chamadas da função canônica, o mesmo custo por bloco que a Pesquisa já paga a cada 100 cartas;
  - o termo dominante é `candidate_by_printing`, que percorre o histórico NM/MARKET dos produtos das cartas do bloco (`ix_pricing_observation_latest_lookup`), mais dois LATERAL por carta (PTAX e preço manual);
  - sem gargalo estrutural novo e sem cache; risco registrado para coleções com milhares de favoritas; medir a duração no postcheck da execução controlada.
- **5871 → v1.1 (20 checagens, GATE por identificadores):**
  - fixture de 105 cartas reescrita: na v1.0 as candidatas com preço podiam ser cortadas pelo `ORDER BY id LIMIT 105`;
  - agora são 20 mapeadas fixas mais as não mapeadas;
  - filtro `> 0` alinhado à 5340;
  - nova checagem 4.5 (favoritas sem nenhuma cotação → `(1, 0, NULL)`), lacuna material do estado "sem cotação".

**CONTROLLED LIVE EXECUTION-19 (2026-10-31) — STOP NO PREFLIGHT, nenhuma escrita no LIVE.**

Preflight conforme:
- 5339 e 5340 ausentes;
- md5 de `get_cards_pricing_summary` (`7bc92ffa…`) = corpo da 3972 no repositório, uma versão;
- md5 das funções 5336/5337/5338 = baseline;
- arquivos 5339 / 5340 v1.1 / 5871 v1.1 = revisados (md5 `158ce28f…` / `e04b319c…` / `c9911c95…`);
- harness com os 20 identificadores esperados, sem duplicidade; TR000 e X.1 presentes;
- baselines: 3 usuários, 8 favoritos, 2.712 exemplares, 3 Inventories, 21.245 cartas ativas / 1 inativa, md5 do estado de `card` `d7dedf24…`.

**Divergência bloqueante (fixture da 5871 v1.1):** o cenário 4.1 monta 105 favoritas como 20 cartas com mapeamento CONFIRMED + 85 cartas ativas **sem mapeamento algum**. O LIVE tem só **82** cartas ativas sem mapeamento, então `cardinality(v_ids)` = 102 → `TR_FIXTURE` → X.1 → GATE FAIL garantido. A fixture foi dimensionada sem conferir esse volume no LIVE.

**Achado complementar (não bloqueante neste catálogo):** `physical_card` tem o trigger `trg_guard_card_variant_active` (`internal.guard_card_variant_reference_active`, recusa exemplar de `card_variant` inativa — MV001), que não entrou na revisão estática. O LIVE tem 12 variantes inativas; as variantes que a fixture escolheria (X, Y, a carta desativada na transação e as 20 mapeadas) estão todas ativas, e nenhuma carta inativa tem variante (o caso 3.4 usaria o caminho de desativação transacional).

**Correção mínima proposta (v1.2, não aplicada):**
- completar as 105 com as cartas ativas sem mapeamento e, se faltar, com outras cartas ativas não escolhidas;
- as sem mapeamento ainda garantem `priced < 105`;
- filtrar `cv.is_active` na escolha das variantes da fixture.

Nenhuma outra checagem, regra ou função muda.

**CONTROLLED EXECUTION-20 (2026-10-31) — LIVE VALIDATED.**

Causa do STOP anterior (EXECUTION-19): a fixture 4.1 exigia 85 cartas sem mapeamento de preço, e o LIVE tem 82.

**5871 v1.2 (só fixture e metadados):**
- as 105 cartas são escolhidas em três camadas com `<> all`: 20 mapeadas CONFIRMED + as sem mapeamento disponíveis (82) + outras ativas (3), ordenadas e distintas;
- todos os exemplares usam só variantes ativas (o trigger `trg_guard_card_variant_active`, MV001, recusa variante inativa);
- checagens, critérios, lotes, comparação canônica, TR000, X.1 e resíduo não mudaram.

**Preflight:**
- 5339 e 5340 ausentes;
- `get_cards_pricing_summary` (`7bc92ffa…`, uma versão) e 5336–5338 iguais à base;
- 105 cartas distintas elegíveis e 37.999 variantes ativas;
- 20 candidatas para 4.5 sem mapeamento e sem preço manual;
- baselines: 3 usuários, 8 favoritos, 2.712 exemplares, 3 Inventories, 21.245 cartas ativas, md5 de `card` `d7dedf24…`.

**Aplicação:**
- **5339:** ledger `20261031233429`, md5(prosrc) `3bade316…` = arquivo.
- **5340 v1.1:** ledger `20261031233455`, md5(prosrc) `fab45a74…` = arquivo.
- Configuração das duas: SECURITY DEFINER, `search_path ''`, STABLE, `auth.uid()`; ACL `postgres` + `authenticated`; anon e PUBLIC sem EXECUTE; a 5340 chama a função canônica, que continua inalterada.

**5871 v1.2: GATE 20/20 PASS**, ids conferidos, sem X.1, resíduo zero:
- O1.1/V1.1: anon 42501; O2.1/V2.1: sem identidade 28000;
- 3.1: (0; 0, 0, NULL);
- 3.2: 3 exemplares, 2 variantes, 2 idiomas → 1;
- 3.3: exemplar de outro usuário não conta → 1 / 0;
- 3.4: carta inativa (desativada na transação) não conta;
- 3.5: remover exemplares → 0;
- 3.6: corpo da 5339 sem collection/binder/storage;
- 4.1: C `(105, 23, 2215.69)` = canônica em dois blocos `(105, 23, 2215.69)`;
- 4.2: 3 exemplares não alteram o valor;
- 4.3: favorita inativa fora;
- 4.4: isolamento (A 3 favoritas);
- 4.5: sem cotação `(1, 0, NULL)`;
- 9.1: resíduo zero.

**Tempos (leitura direcionada, favoritas reais do proprietário — 8 cartas):**
- 5339: 28,8 ms;
- 5340: 253,1 ms na primeira chamada e 8,9 ms na segunda, com retorno `(8, 8, 3206.75)`;
- não comprova desempenho para milhares de favoritas.

**Postcheck:**
- 0 usuários sintéticos; favoritos 8; Inventories 3; estado de `card` = baseline; 3972 e 5335–5338 inalteradas; sem locks residuais;
- exemplares 2.712 → 2.724: atividade real e concorrente do proprietário — um único Inventory real, inserções contínuas desde 23:07 UTC, antes da execução; não é resíduo.

**API:** `NOTIFY pgrst` enviado; REST anônimo nas duas funções → 42501, e o controle com nome inexistente devolve PGRST202, o que confirma que o cache foi recarregado.

Pendentes: homologação local dos KPIs 2 e 3; promover 5339/5340 a `database/schema`; commit/push/deploy.

**FINAL RELEASE READINESS-22 (2026-10-31).**
- 5339 e 5340 v1.1 promovidas a `database/schema` (cópia idêntica à proposta; md5(prosrc) `3bade316…` / `fab45a74…` = LIVE da EXECUTION-20).
- `database/schema` contém 5335, 5336, 5338, 5339 e 5340, todas com corpos = LIVE.
- A 5337 fica só aqui: CONFIRMADO EXECUTADO, substituída, sem consumidor, sem DROP.
- Homologação visual desktop aprovada pelo proprietário (quatro indicadores); mobile só após o deploy.
- Gates: typecheck OK; 652/652 testes; `git diff --check` OK; lint/build com o proprietário.
- Commit/push/deploy aguardam autorização.
