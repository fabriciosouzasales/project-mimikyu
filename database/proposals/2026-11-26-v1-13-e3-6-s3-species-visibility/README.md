# V1-13 · E3-6 / S3 — Visibilidade das referências de espécie no fichário compartilhado (5393)

| Campo | Valor |
|---|---|
| **Rodada** | `E3-6 / S3 — SHARED BINDER SPECIES VISIBILITY \| CONTRACT SPECIFICATION-01` (2026-11-26) |
| **Status** | **5393 EXECUTADA NO LIVE / CANÔNICA (2026-11-27), BARREIRA CLOSED** — PRE 15/15, transação confirmada, POST 11/11, md5 `34c87736…` (`S3_DEPLOY_EVIDENCE_2026-11-27.md`). Harness 5897 **não executado** (prova funcional no gate de abertura). |
| **Decisão** | **D-E3-9** — EDITOR e VIEWER podem visualizar as referências de espécie no fichário compartilhado, respeitando a apresentação mascarada e sem inferência patrimonial. |
| **Origem** | Adendo F2 (seção 11) de `../2026-11-25-v1-13-e3-6-contract-evolution/README.md`, alternativa A′ aprovada. |
| **Independência** | Separado de **S1/5390** (permissões da imagem da capa, D-E3-6) e de **S2/5391–5392** (edição de posição e representante da Pokédex, P0-A/P0-B/D-E3-8). Pode ser implantado antes, depois ou na mesma janela. |
| **Não muda** | 5315, 5316, 5318 (vitrine pública), 5257–5260, 5383, nenhuma tabela, nenhuma política. |

---

## 1. Base conferida (tipos reais, versões canônicas/implantadas)

| Objeto | Assinatura / colunas conferidas | Fonte |
|---|---|---|
| `collection_binder_masked_pages(p_collection_id uuid, p_first_page integer, p_page_count integer)` — interna, STABLE, SECURITY DEFINER, `search_path = ''` | retorna `page_number integer, row_index integer, column_index integer, pocket_state text ('CARD'\|'RESERVED'\|'EMPTY'), card_name text, collector_number text, collector_total integer, card_set_code text, variant_label text, language_code text, image_path text`; janela 1–4 páginas, página ≤ 100000; resolve o fichário próprio ou convidado; EMPTY = vazio, carta de outra coleção ou sem coleção, reserva alheia, mesclagem, imagem personalizada | `database/schema/5315_…` v2.0 |
| `get_shared_collection_binder_pages(uuid, integer, integer)` — porta do participante | mesmas 11 colunas; `collection_share_role ∈ {OWNER, VIEWER}` senão `COLLECTION_NOT_FOUND` (P0002); só `authenticated` | `database/schema/5316_…` v1.0 |
| `collection_share_role(uuid)` — interna | `'OWNER' \| 'VIEWER' \| 'PUBLIC' \| NULL`; ACTIVE de qualquer papel → `VIEWER`; PENDING/DECLINED → nunca | `5302` |
| `collection_layout_slot_species_reference` | `slot_id uuid PK → collection_layout_slot`, `layout_id uuid`, `collection_id uuid`, `pokedex_position_id uuid`, `source text`, `created_at`; `UNIQUE (layout_id, pokedex_position_id)` | `5257` |
| `collection_layout_species_reference_setting` | `layout_id uuid PK`, `references_visible boolean not null default true` (sem linha = visível, 5259) | `5257` |
| Regra do titular (5259) | só valem referências cuja `collection_id` é a **proprietária atual** do fichário; arte = `pokemon_species_artwork` IMPORTED com `display_storage_path` (no máximo uma por espécie); número = `pokedex_position.position_number`; nome = `pokemon_species.canonical_name` | `5259` |
| Unicidade da posição | `collection_layout_page UNIQUE (layout_id, page_number)` (DEFERRABLE; leitores só veem estados confirmados); `collection_layout_slot` `uq_collection_layout_slot_position` (página, linha, coluna) | `5108`, `5110` |
| Barreira | `v1_13_capability_open()` / `v1_13_assert_capability()` (42501 `CAPABILITY_NOT_ENABLED`) | `5389` |

## 2. Interface proposta

```
get_shared_collection_binder_pages_with_species(
  p_collection_id uuid,
  p_first_page    integer,
  p_page_count    integer
) returns table (
  page_number             integer,   -- \
  row_index               integer,   --  |
  column_index            integer,   --  |
  pocket_state            text,      --  | idênticas à 5316 (mesma ordem, mesmos valores)
  card_name               text,      --  |
  collector_number        text,      --  |
  collector_total         integer,   --  |
  card_set_code           text,      --  |
  variant_label           text,      --  |
  language_code           text,      --  |
  image_path              text,      -- /
  species_national_number integer,   -- novas: só com a regra da seção 3
  species_name            text,
  species_artwork_path    text,
  references_visible      boolean    -- estado da camada (seção 3); igual em todas as linhas
)
language plpgsql  stable  security definer  set search_path = ''
```

- Mesmas validações de argumento e mesma janela (1–4 páginas) — delegadas ao núcleo 5315 (`INVALID_ARGUMENT` 22023 para nulos/fora da janela).
- Ordem: a do núcleo 5315 (página, linha, coluna), sem reordenação.
- `revoke all … from public, anon; grant execute … to authenticated`. Nenhuma outra função nova (sem ajudante exposto).

## 3. Regras (autorização, mascaramento, exibição)

Em ordem, dentro de UMA chamada:

1. **Barreira:** `perform public.v1_13_assert_capability()` → fechada: `CAPABILITY_NOT_ENABLED` (42501). *Desvio deliberado do padrão de leitura G1 (zero linhas):* uma porta de páginas com zero linhas seria indistinguível de "janela além do fim" e faria a tela mostrar um fichário vazio; com a recusa explícita a interface volta à 5316.
2. **Acesso:** `collection_share_role(p_collection_id) ∈ {'OWNER','VIEWER'}`, senão `COLLECTION_NOT_FOUND` (P0002) — o mesmo da 5316, antes de qualquer tabela do fichário.
3. **Páginas:** as linhas são exatamente as do núcleo `collection_binder_masked_pages(p_collection_id, p_first_page, p_page_count)` — nenhuma linha a mais, nenhuma a menos.
4. **Camada autorizada** (`species_eligible`, constante para a chamada) é verdadeira só se **todas**:
   - o fichário resolvido pertence a X como **proprietária** (`collection_layout.collection_id = X`; X convidada → falso: a camada seria de outra coleção);
   - X é Pokédex (`REFERENCE_BASED`, `REFERENCE_POSITION`, referência `POKEDEX`).
5. **`references_visible`:** se `species_eligible`, `coalesce(setting.references_visible, true)`; senão `NULL`.
6. **Espécie por linha:** `species_national_number`, `species_name`, `species_artwork_path` preenchidas **somente se** `species_eligible` **e** `references_visible = true` **e** `pocket_state = 'EMPTY'` **e** o bolso dessa posição tem referência com `collection_id = X`. Caso contrário, as três são `NULL`.
   - A decisão usa **apenas o estado mascarado**. Não consulta carta, imagem, região, reserva alheia nem ocupação real — essas tabelas não entram na parte nova da consulta.
   - CARD/RESERVED de X → `NULL`: o participante já vê esse conteúdo; nada novo.
   - Referências de outra coleção (proprietária anterior após transferência 5254) nunca aparecem.
   - Exibição desligada → espécie `NULL` em todas as linhas (respeita a escolha do titular; o estado vem em `references_visible`). Ao ligar de novo, a tela relê a janela.
7. **Junção** do resultado mascarado ao bolso: por `(layout resolvido, page_number, row_index, column_index)` → `collection_layout_page`/`collection_layout_slot` (ambos únicos) → `collection_layout_slot_species_reference` (PK `slot_id`) → `pokedex_position` → `pokemon_species` → `pokemon_species_artwork`. Nenhuma coluna de id sai.

**O EDITOR não recebe nada a mais que o VIEWER** (a função não lê o papel real; 5302 devolve `VIEWER` para ambos). O titular, se chamar, recebe a mesma visão mascarada (como a 5316).

## 4. Matriz de autorização

| Quem / situação | Resultado da 5393 |
|---|---|
| Titular | linhas da 5316 + espécie pela regra da seção 3 (visão mascarada, não a do titular) |
| EDITOR ativo | idêntico ao VIEWER ativo (mesmo hash de resposta) |
| VIEWER ativo | linhas + espécie pela regra |
| EDITOR rebaixado para VIEWER | idêntico ao VIEWER |
| Participante removido / saiu | `COLLECTION_NOT_FOUND` (P0002) |
| Convite pendente ou recusado | P0002 |
| Coleção arquivada | como a 5316 (leitura permitida a quem tem acesso); espécie pela regra |
| Outra coleção (sem acesso) | P0002 (inexistente e alheia indistinguíveis) |
| Outra modalidade (não Pokédex) | linhas da 5316; espécie `NULL`; `references_visible NULL` |
| X convidada no fichário de outra coleção | linhas da 5316; espécie `NULL`; `references_visible NULL` |
| Coleção sem fichário | zero linhas (como a 5316) |
| Barreira CLOSED (inclusive titular) | 42501 `CAPABILITY_NOT_ENABLED` |
| Barreira TEST, usuário fora do registro | 42501 |
| Anônimo | sem EXECUTE (permission denied) |
| Coleção pública, usuário sem participação | P0002 (a vitrine usa a 5318, que não muda) |

Nunca saem: `slot_id`, `page_id`, `layout_id`, `collection_id`, `pokedex_position_id`, `assignment`, `collection_allocation_id`, `physical_card_id`, ids de carta/variante, local, condição, caminhos de imagem personalizada do titular (Storage privado), contagens.

## 5. Prova de não inferência (obrigatória, bloqueia a implantação)

**Montagem (PostgreSQL local, harness 5897):** titular U; coleção Pokédex X (proprietária do fichário F, grade 3 × 3, 2 páginas), camada de referências aplicada pelo plano canônico (5258) com exibição ligada; coleção Y de U convidada em F; participantes EDITOR E e VIEWER V em X. O bolso-alvo é (página 1, linha 1, coluna 1), com referência de X.

| Cenário | Bolso-alvo | Estado mascarado esperado |
|---|---|---|
| A | realmente vazio | EMPTY |
| B | carta alocada a Y (convidada) | EMPTY |
| B′ | carta sem coleção | EMPTY |
| C | imagem personalizada do titular (5232) | EMPTY |
| D | parte de mesclagem/região (5119/5238) | EMPTY |
| E | reserva de Y | EMPTY |

Para cada cenário, sessão V e sessão E: `h = md5(json_agg(to_jsonb(r) order by page_number, row_index, column_index)::text)` sobre **todas** as colunas e **todas** as linhas da janela (1, 2).

**Critérios (todos):**
1. `h(A) = h(B) = h(B′) = h(C) = h(D) = h(E)`, para V e para E.
2. `h_V = h_E` em todos os cenários.
3. Número de linhas = `count(*)` da 5316 na mesma janela; mesma ordem; colunas 1–11 iguais às da 5316 linha a linha.
4. No bolso-alvo, `species_*` preenchidas e iguais nos seis cenários; `references_visible = true` em todas as linhas.
5. Controle positivo: carta de **X** no bolso-alvo → `pocket_state = 'CARD'` e `species_* NULL`; reserva de X → `RESERVED` e `NULL` (diferença esperada, conteúdo já visível).
6. Exibição desligada: `species_* NULL` em todas as linhas e `references_visible = false`, idêntico em A–E.
7. Nenhuma leitura de `collection_layout_slot_assignment`, `collection_layout_slot_image`, `collection_layout_region*` na parte nova da função (conferência estática do corpo).

### 5.1 Não inferência entre consultas (C3)

Os seis cenários de cima provam que **estados ocultos diferentes** dão a mesma resposta. Falta provar que **mudar o conteúdo oculto entre duas consultas** também não muda a resposta. Harness 5897, seção 2b, sessão V (repetida com a sessão E):

1. `h0` = hash completo da janela (todas as linhas, na ordem, as 11 colunas da 5316, as 4 novas, nulos incluídos) com o bolso-alvo no cenário A.
2. O titular (outra sessão, cada passo confirmado) percorre A → B → B′ → C → D → E → A no bolso-alvo; a cada passo, nova chamada de V: `h1 … h6`.
3. Ainda entre consultas, o titular muda conteúdo oculto **fora** do bolso-alvo, num bolso EMPTY mascarado sem referência e num com referência (colocar e retirar carta de Y, trocar a imagem, desfazer a mesclagem): `h7 … hn`.
4. **Critério:** `h0 = h1 = … = hn`, para V e para E. Em paralelo, o hash da 5316 na mesma janela também fica constante (os dados públicos não mudaram), e o número de linhas, a ordem, os estados, os nulos, `references_visible` e a espécie de cada bolso são idênticos campo a campo (diferença registrada por coluna, não só pelo hash).

**Controles positivos (a resposta DEVE mudar, e só onde o participante já vê):**
- carta de **X** colocada no bolso-alvo → só a linha do bolso-alvo muda (`pocket_state = 'CARD'`, campos da carta preenchidos, `species_* NULL`); todas as outras linhas iguais a `h0`. Retirar a carta → volta a `h0`;
- reserva de **X** no bolso-alvo → só a linha do bolso-alvo muda (`RESERVED`, `species_* NULL`); liberar → volta a `h0`;
- ocultar a camada → muda `references_visible` (todas as linhas) e as espécies passam a `NULL`; nenhuma outra coluna muda; mostrar → volta a `h0`;
- remover a camada → espécies `NULL`, `references_visible` mantém o valor; aplicar de novo o mesmo plano → volta a `h0`.

**Equivalência × desempenho:** as seções de equivalência (2, 2b) usam um fichário pequeno e só comparam resultados; não medem tempo e não dependem da seção de desempenho. O desempenho (seção 7) é medido à parte, com outro fichário, e não serve como prova de não inferência (tempo de resposta não é critério de equivalência; se um dia for, é uma prova separada).

## 6. Consistência e concorrência (corrigido — C1)

**O que é garantido:** dentro de **uma** chamada da 5393, autorização, páginas mascaradas e referências são lidas do **mesmo instantâneo MVCC**. **O que não é garantido:** que esse instantâneo seja o estado mais recente durante toda a chamada, nem consistência entre chamadas.

**Demonstração pela semântica do PostgreSQL:**

1. **Instantâneo usado.** O cliente (PostgREST) executa cada RPC como `select … from public.get_shared_collection_binder_pages_with_species(…)` numa transação própria, em READ COMMITTED (padrão do Supabase; a função não muda o nível). Em READ COMMITTED, cada comando de nível superior obtém um instantâneo no início. É esse o instantâneo da chamada.
2. **Volatilidade.** A documentação do PostgreSQL (*Function Volatility Categories*) define: funções `STABLE` e `IMMUTABLE` usam o instantâneo estabelecido no início da consulta que as chamou; funções `VOLATILE` obtêm um instantâneo novo no início de cada consulta que executam. Em PL/pgSQL, as consultas de uma função não volátil rodam pelo SPI em modo somente leitura, sem novo instantâneo. Portanto a 5393 **precisa** ser `STABLE` (e não `VOLATILE`) para a garantia valer; se fosse `VOLATILE`, a autorização, o núcleo e a leitura das referências poderiam ver estados diferentes.
3. **5315 e referências no mesmo estado.** A 5393 faz uma única `return query` que chama o núcleo `collection_binder_masked_pages` (STABLE, conferido: `provolatile = 's'` na 5315 canônica) e junta, na mesma consulta, página/bolso/referência/posição/espécie/arte/configuração. Uma função STABLE chamada dentro de uma consulta usa o instantâneo dessa consulta; a autorização (`collection_share_role`, também STABLE — conferido na 5302 canônica: `LANGUAGE sql STABLE` —, comando anterior da mesma função STABLE) também usa o instantâneo da chamada externa. Logo, os três passos enxergam o mesmo conjunto de transações confirmadas.
4. **Alterações concorrentes.** A 5393 não trava nada (leitura pura) e não bloqueia escritores. Uma transação que confirma **antes** do início da chamada aparece inteira; uma que confirma **durante** a chamada não aparece em nada (nem nas páginas, nem nas referências, nem na autorização); uma ainda aberta nunca aparece. Não existe resposta "metade antes, metade depois". Consequência aceita (a mesma da 5388): uma revogação de acesso confirmada durante a chamada só vale na chamada seguinte.
5. **Entre chamadas** (outra janela de páginas, ou a mesma relida depois) não há consistência: cada chamada tem seu instantâneo, como a 5316 hoje. A interface relê as janelas depois de cada escrita do EDITOR e descarta leituras com numeração antiga (E2-3A).

**Condições contratuais (verificadas no static check):** `provolatile = 's'` na 5393, na 5315 e na 5302; corpo com **uma** consulta de dados depois da autorização; nenhuma chamada a função `VOLATILE` na consulta de dados; nenhuma alteração de nível de isolamento.

**Prova no harness 5897 (seção 3, PostgreSQL local, duas sessões):**
- *Mesmo instantâneo dentro da chamada:* um ajudante **só do ensaio**, criado em `pg_temp` e declarado `STABLE`, calcula `h1 = hash(5393 janela)`, executa `pg_sleep(3)` e calcula `h2 = hash(5393 janela)` dentro da mesma chamada. Durante o sono, a sessão B confirma, nesta ordem e em transações separadas, a remoção da camada, a reordenação das páginas 1 e 2 e a troca da exibição. Critério: `h1 = h2 = h_antes`. Isso exercita exatamente a semântica de que a 5393 depende (consultas de função STABLE sem instantâneo novo).
- *Controle negativo do mecanismo:* o mesmo ajudante declarado `VOLATILE` dá `h2 ≠ h1` no mesmo roteiro (mostra que a propriedade vem da volatilidade, não do acaso).
- *Atomicidade da escrita observada:* a sessão B aplica ou remove a camada inteira numa transação e só confirma depois de V ler; V lê antes (camada inteira ausente/presente) e depois (camada inteira no outro estado) — nunca uma contagem intermediária de referências.
- *Autorização no mesmo instantâneo:* com o ajudante STABLE, a sessão B remove a participação de V durante o sono; `h2` continua igual a `h1`; a chamada seguinte recusa com P0002.
- Os ajudantes do ensaio não fazem parte da migration nem existem fora da sessão local.

## 7. Desempenho

- Pior caso da janela: 4 páginas × 10 × 10 = 400 linhas (F002: 4 × 16 = 64). Junções por chaves únicas/PK; uma leitura da configuração; uma verificação de modalidade.
- Critério: no PostgreSQL local com um fichário do tamanho do F002 (66 páginas × 16 bolsos, 1.025 referências), `EXPLAIN (ANALYZE, BUFFERS)` da 5393 sem varredura sequencial nas tabelas de referência e tempo ≤ 2 × o da 5316 na mesma janela (medido, não presumido). Medição no LIVE só com autorização específica.

## 8. Plano de validação (local)

| Etapa | Conteúdo |
|---|---|
| Static check | precheck/postcheck; `search_path = ''`; objetos qualificados; EXECUTE só `authenticated`; `provolatile = 's'` na 5393, na 5315 e na 5302; uma consulta de dados depois da autorização, sem função VOLATILE nela; ausência das tabelas proibidas na parte nova; md5 de 5315/5316/5318 iguais antes e depois |
| Harness 5897 (ensaio local) | seção 1 matriz da seção 4; seção 2 não inferência entre estados (seção 5); seção 2b não inferência entre consultas e controles positivos (seção 5.1); seção 3 consistência na chamada (seção 6, ajudantes STABLE/VOLATILE só do ensaio); seção 4 desempenho (seção 7, separado da equivalência); seção 5 regressão: 5316 e 5318 com as mesmas respostas de antes |
| Rollback | `R5393`: `drop function public.get_shared_collection_binder_pages_with_species(uuid, integer, integer)`; não toca dados; nenhuma outra função depende dela |

## 9. Gate de implantação (STD-001 §10)

A migration só é escrita depois da aprovação desta especificação e segue o padrão: **Query 5393 — porta de páginas do participante com referências de espécie** → **Objetivo** → **Script** (precheck: dependências 5302/5315/5257/5389 presentes, função ausente; criação; grants; postcheck) → **Resultado esperado** → **Como validar** (harness 5897, seções 1–5). Execução no LIVE só com: static check PASS, harness local PASS (incluindo a prova de não inferência), auditoria independente e autorização expressa e específica. Barreira continua CLOSED; nada disso abre a capacidade.

## 10. Impacto na F2 (sem implementar agora) e fallback controlado (C2)

- Com a configuração ligada, a leitura das páginas do participante (`readSharedBinderPages`) passa a usar a 5393, com o fallback **só** nos casos da matriz abaixo. Configuração desligada → só a 5316, nada muda.
- O conversor das páginas compartilhadas leva `species_*` ao `speciesRef` do bolso; o fichário compartilhado fornece `SpeciesReferenceVisibleContext` com `references_visible`; o bolso já desenha a arte (`SpeciesReferenceArt`).
- Diálogo do EDITOR (F2): passa a mostrar o estado real da exibição (interruptor) a partir de `references_visible` da última leitura; depois de cada ação da 5383, a tela relê as janelas (já existente).
- VIEWER: só a arte, nenhum controle. Titular: inalterado (5259). Vitrine pública: inalterada (5318).

### 10.1 Matriz de fallback

A 5316 devolve **um subconjunto** do que a 5393 devolve (as mesmas 11 colunas, sem espécie) e confere a própria autorização no banco. Por isso o fallback nunca amplia informação nem autorização — mas também só é usado quando a 5393 **não está disponível como capacidade**, nunca para mascarar recusa ou erro.

| Situação | Como é reconhecida (só código + nome da exceção; `hint`/`details` nunca lidos) | Ação da interface | Usa a 5316? |
|---|---|---|---|
| Configuração desligada | servidor da página (`MMKYU_V113_EDITOR_CURATION`) | nem chama a 5393 | **sim** (comportamento atual) |
| Barreira CLOSED (ou TEST fora do registro) | 42501 com mensagem exatamente `CAPABILITY_NOT_ENABLED` | marca a 5393 como indisponível **nesta tela** e lê pela 5316; espécie e exibição ficam desconhecidas (sem arte, sem estado presumido) | **sim** |
| 5393 não implantada | `PGRST202` ou `42883` | igual à barreira | **sim** |
| Sessão expirada | `28000` / JWT | estado de sessão expirada (entrar de novo); nenhuma leitura alternativa | **não** |
| Acesso perdido | `P0002` `COLLECTION_NOT_FOUND` | estado de permissão perdida / recarregar (a 5316 diria o mesmo); nenhuma página vazia | **não** |
| Erro inesperado (outro código, rede, tempo esgotado, 42501 com outra mensagem) | qualquer outro | estado de falha do lote com "Tentar de novo" (tenta a 5393 de novo) | **não** |
| Resposta inválida | formato inesperado: coluna ausente/tipo errado; espécie preenchida com `pocket_state ≠ 'EMPTY'`; espécie preenchida com `references_visible ≠ true`; `references_visible` diferente entre linhas | igual a erro inesperado (lote com falha); nada é desenhado do lote | **não** |

Regras complementares:
- **Troca durante a sessão:** se a 5393 passar a recusar com `CAPABILITY_NOT_ENABLED` depois de já ter respondido (barreira fechada no meio do uso), a tela descarta o cache de páginas lidas pela 5393, desliga a exibição de referências e relê pela 5316 — nunca mistura lotes das duas fontes.
- **Volta à 5393** só numa nova abertura do fichário (sem sondagem periódica).
- Zero linhas da 5393 têm o mesmo significado da 5316 (janela além do fim / sem fichário), nunca "barreira".

## 11. Auditoria das referências (decidida — C4: D-E3-8 ampliada)

**Decisão do proprietário (2026-11-26):** a **D-E3-8** passa a abranger também as alterações colaborativas de referências de espécie feitas pela **5383** (EDITOR). A obrigação **não** faz parte da 5393 (leitura) e a 5383 **não** é alterada nesta rodada.

Especificação conceitual (a detalhar no pacote de auditoria):

| Operação (5383) | Evento | Quando gera | Resumo autorizado |
|---|---|---|---|
| Aplicar (`APPLIED`) | referências associadas | só `APPLIED`; `ALREADY_APPLIED` não gera | quantidade associada; intervalo de páginas (primeira–última); intervalo de números nacionais (primeiro–último) |
| Remover (`REMOVED`) | referências removidas | só com `removed_count > 0`; remoção de 0 não gera | quantidade removida |
| Mostrar (`UPDATED` para visível) | exibição ligada | só `UPDATED`; `UNCHANGED` não gera | — |
| Ocultar (`UPDATED` para oculto) | exibição desligada | só `UPDATED`; `UNCHANGED` não gera | — |

- **Um evento por operação efetiva**, gravado na mesma transação da escrita (se a escrita for desfeita, o evento também).
- **Autor:** quem executou (titular ou participante), exibido pelo nome de exibição público, como C-241; nunca e-mail, usuário ou id.
- **Nunca no resumo:** bolsos ocupados (`slots_with_content`), ids de bolso/página/fichário/posição, cartas, exemplares, local, condição, valores, outras coleções.
- **Visibilidade:** titular vê; participantes de X veem nas regras de C-241 (D12–D14).
- **Recomendação** (não decidida): registrar também as mesmas operações do titular (5258), para a trilha não ser só de um lado.

**Dependência contratual para a implementação futura:** (1) `CREATE OR REPLACE` das quatro escritas da 5383 (e, se adotada a recomendação, das da 5258) para gravar o evento; (2) tipos novos de evento no registro do histórico (restrição de tipos de `binder_activity_event` e a lista permitida ao EDITOR, 5381/5384), com categoria; (3) inclusão na lista de permissão da leitura compartilhada (5388) e na leitura do titular (5269), com o autor; (4) harness próprio. Pacote: o mesmo da auditoria de posição e representante (S2) ou um pacote de auditoria dedicado — a decidir no desenho do S2. **Enquanto não existir, a abertura funcional das operações da F2 (5383) para o EDITOR fica bloqueada pela D-E3-8**, como já está a edição da Pokédex.

---

## 12. Artefatos preparados (2026-11-26, `E3-6 / S3-5393 — SQL & HARNESS PREPARATION-01`) — NÃO EXECUTADOS

| Arquivo | Conteúdo |
|---|---|
| `5393_create_get_shared_collection_binder_pages_with_species.sql` | migration (uma transação): precheck (dependências; md5 do prosrc de 5302, 5315, 5316, 5318 e 5389 ×2 derivados dos arquivos canônicos; dependências STABLE e `auth.uid()` presente; função ausente) → `create function` → comentário → `revoke … from public, anon` / `grant … to authenticated` → postcheck (definer, `search_path`, STABLE, mesmo dono do núcleo 5315, grants, retorno exato, 5315/5316/5318 intactas) |
| `ROLLBACK_S3.sql` | R5393: `drop function if exists` (assinatura exata) + postcheck |
| `5897_validate_shared_binder_species_HARNESS.sql` | harness de sessão única, transação revertida pelo operador: 24 verificações — estrutura (0.1–0.4), fixture (F.2), matriz de papéis e barreira (1.1–1.10), regressão 5316/5318 e 11 colunas (2.1), não inferência A/B/B′/C/D/E para VIEWER e EDITOR (3.1), entre consultas e controles positivos (4.1–4.6), reversão ensaiada (5.1) |
| `5897_C_concurrency_LOCAL_TWO_SESSIONS.sql` | roteiro de duas sessões em banco local descartável: ajudantes do ensaio STABLE e VOLATILE com pausa, atomicidade observada, autorização no mesmo instantâneo (C1-a a C1-d) |
| `5897_P_performance_LOCAL.sql` | medição separada (perfil F002, 5316 × 5393, `auto_explain` local), critérios P1–P3 |
| `static_check_s3.py` | verificação estática do texto (sem banco) |

**Dependências transitivas conferidas (C1, pelo texto dos arquivos canônicos):** `v1_13_assert_capability` (plpgsql STABLE) → `v1_13_capability_open` (sql STABLE) → `auth.uid()`; `collection_share_role` (5302, sql STABLE) → `auth.uid()`; `collection_binder_masked_pages` (5315, plpgsql STABLE, só tabelas, sem chamadas de função). `auth.uid()` é da plataforma (Supabase: sql STABLE) — **não está no repositório**; o precheck recusa a aplicação se ela não for STABLE/IMMUTABLE no banco de destino.

### 12.1 Gates de qualidade (STD-001 §10)

| # | Gate | Como | Estado em 2026-11-26 |
|---|---|---|---|
| G1 | Inspeção estática | `python3 -I -B …/static_check_s3.py` | **PASS 35/35** (executado; prova só o texto) |
| G2 | Compilação real | diretriz executiva (2026-11-27): sem ambiente isolado — compilação e postcheck internos na própria implantação controlada no LIVE | **PASS no LIVE** (transação confirmada; POST 11/11) |
| G3 | Testes funcionais | harness 5897 (cenários sintéticos) — inadequado ao LIVE pela diretriz; vira gate da abertura (TEST/OPEN) | **NÃO EXECUTADO** |
| G4 | Provas de concorrência | roteiro `5897_C` | **NÃO EXECUTADO** (gate de abertura) |
| G5 | Desempenho | roteiro `5897_P` (5393 não responde com a barreira CLOSED) | **NÃO EXECUTADO** (gate de abertura) |
| G6 | Auditoria independente | revisão das evidências da implantação | **ACEITA** (2026-11-27; canal do conector aceito excepcionalmente) |
| G7 | Autorização de implantação | autorização expressa (2026-11-27); PRE confirmou md5 e volatilidade no LIVE | **CONCEDIDA e executada** |

Nenhum gate além do G1 foi executado; nada aqui é PASS antes de executado e registrado.

### 12.2 Auditoria das referências — pacote futuro S4 (decisão registrada, nada implementado)

Decisão (2026-11-26): a D-E3-8 cobre as operações **efetivas** de referências de espécie **do titular (5258) e do EDITOR (5383)** — associar, remover, mostrar, ocultar; um evento por operação efetiva; nenhum para `ALREADY_APPLIED`, remoção de 0 ou `UNCHANGED`; autor pelo nome público; resumo sem dados patrimoniais. Fica no pacote independente **S4** (provisório). Nesta rodada nada foi alterado em 5258, 5383, 5269 ou 5388.
