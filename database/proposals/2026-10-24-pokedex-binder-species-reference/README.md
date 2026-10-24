# POKEDEX-BINDER-SPECIES-REFERENCE — referência da espécie nos bolsos do fichário da Pokédex

| | |
|---|---|
| Rodadas | POKEDEX-BINDER-SPECIES-REFERENCE-PROPOSAL-01 (proposta) · POKEDEX-BINDER-SPECIES-REFERENCE-IMPLEMENTATION-01 (implementação local) |
| Data | 2026-10-24 |
| Status | **IMPLEMENTAÇÃO LOCAL (2026-10-24, `POKEDEX-BINDER-SPECIES-REFERENCE-IMPLEMENTATION-01`)** — migrations 5257–5260 e harness 5857 escritos, **NÃO EXECUTADOS**; frontend local, homologação visual pendente. Nenhuma escrita no LIVE. Ver §9. **Precheck LIVE (somente leitura) PASS / GO** — `LIVE-PRECHECK-2026-10-24.md`. **5257–5260 CONFIRMADAS EXECUTADAS no LIVE (2026-10-24, ledger 20261024163436/163618/163711/163750; postcheck PASS)** — `LIVE-EXECUTION-2026-10-24.md`. Referências ainda não criadas; frontend não publicado; promoção canônica pendente. |
| Projeto | Supabase `mimikyu-core` (`qjfutqujxrbzgrtkpgkg`) — investigação somente leitura (`begin transaction read only; statement_timeout 30s`) |
| Escopo aprovado | F002 "Minha Pokédex": 1.025 espécies da Pokédex Nacional nos primeiros 1.025 bolsos (#0001–#1025, ordem real página → linha → coluna); 31 bolsos finais sem referência |
| Fora de escopo | contracapa, Centro de Controle, correção cromática aprovada, personalização (só preservada como possibilidade), demais modalidades de fichário |

## 1. Investigação (LIVE, somente leitura)

| Item | Resultado |
|---|---|
| Fichário | layout `bd2c0834-1310-4239-9aed-012df74ae97b`, grade 4×4, local F002 |
| Proprietária | "Minha Pokédex" `01352192-af60-4f97-9394-4dc5b5418bcc`, REFERENCE_BASED / REFERENCE_POSITION / ACTIVE |
| Páginas / bolsos | 66 páginas contíguas (1–66), 16 bolsos cada = **1.056 bolsos** |
| Conteúdo atual | 0 posições · 0 reservas · 0 imagens de bolso · 0 regiões · 0 travados · 0 convidadas · 0 alocações |
| Escopo da coleção | Pokédex NATIONAL `cd40e277-07de-4aa9-a74d-ac0332541e12`, `GENERATION_FILTERED` com todas as gerações selecionadas |
| Posições | 1.025 (`position_number` 1–1025, contíguas, todas no escopo), 1.025 espécies distintas |
| Arte | 1.025/1.025 com `pokemon_species_artwork` `IMPORTED` e `display_storage_path` (a mesma fonte de `species_artwork_path` em 5204/5211) |
| Correspondência | bolso ordinal *n* (ordem página → linha → coluna) ↔ `position_number` *n*, n = 1..1025; bolsos 1.026–1.056 (página 65 a partir do bolso 2, e página 66 inteira) sem referência |

Conclusão: o mapeamento é **determinístico e completo**, sem inventar nada — usa só a ordem nacional já cadastrada e a ordem física já gravada.

### Por que não dá para fazer só no frontend, nem reutilizar o que existe

- **Calcular na tela pela ordem dos bolsos:** a referência pularia de bolso a cada página adicionada, removida ou reordenada. Também não haveria onde gravar uma personalização futura (regra 8).
- **`collection_layout_slot_expected_content` (reserva):** exige `card_id NOT NULL`, conta como reserva no LIVRE da 5243, na montagem e nas leituras. Usá-la contradiz a regra 7.
- **Montagem/plano do fichário:** compacta as posições e opera sobre exemplares, não sobre espécies.

É preciso **uma camada própria, gravada por bolso**, que não seja carta, nem reserva, nem progresso.

## 2. Proposta funcional

1. **A referência pertence ao bolso.** É um rótulo impresso no plástico, não um conteúdo: não é carta, reserva, exemplar nem progresso.
2. **Aplicação única com prévia e confirmação.** No Centro de Controle já existe a área Organização, mas a regra é não alterá-lo nesta fase. Por isso o ponto de entrada proposto é uma ação no próprio fichário da Pokédex: *"Mostrar os Pokémon nos bolsos vazios"*.
   - A prévia mostra: "1.025 Pokémon serão posicionados do bolso 1 (pág. 1) ao bolso 1.025 (pág. 65). 31 bolsos ficarão livres. Nenhuma carta, imagem ou página será alterada."
   - O botão de confirmação aplica tudo de uma vez.
3. **Exibição só quando o bolso está visualmente vazio:** sem posição, sem imagem de bolso e fora de região mesclada. Com reserva, prevalece a reserva (que já tem visual próprio).
   - Visual: arte oficial atenuada (opacidade baixa, dessaturada, sem moldura de carta), número nacional discreto e nome no `title`/`aria-label`.
   - Não é uma carta: não é clicável como carta e não entra em contagens.
4. **Ao posicionar uma carta,** a referência some (fica sob a carta). Ao retirar, ela volta. Nada é gravado nesses momentos.
5. **Remoção:** ação *"Ocultar os Pokémon dos bolsos"*, também com confirmação. Apaga só a camada de referências.
6. **Personalização futura:** a coluna `source` (`NATIONAL_ORDER` hoje) e a chave por bolso permitem, depois, mover ou trocar referências manualmente sem mudar o modelo. Nada disso é implementado agora.

## 3. Contratos mínimos propostos (esboço — NÃO EXECUTAR)

Numeração reservada: `5257` (tabela + RLS), `5258` (escritas), `5259` (leitura). Harness: `5857`.

### 3.1 Tabela `collection_layout_slot_species_reference` (5257)

```sql
create table public.collection_layout_slot_species_reference (
  slot_id              uuid primary key
                       references public.collection_layout_slot(id) on delete cascade,
  layout_id            uuid not null
                       references public.collection_layout(id) on delete cascade,
  collection_id        uuid not null
                       references public.collection(id) on delete cascade,  -- proprietária no momento da aplicação
  pokedex_position_id  uuid not null
                       references public.pokedex_position(id) on delete restrict,
  source               text not null default 'NATIONAL_ORDER'
                       check (source in ('NATIONAL_ORDER')),               -- ampliável (ex.: 'MANUAL') em fase futura
  created_at           timestamptz not null default now(),
  constraint cl_ssr_layout_position_uk unique (layout_id, pokedex_position_id)
);
create index cl_ssr_layout_idx on public.collection_layout_slot_species_reference (layout_id);
alter table public.collection_layout_slot_species_reference enable row level security;
revoke all on public.collection_layout_slot_species_reference from public, anon, authenticated;
-- sem policies: acesso só pelas RPCs SECURITY DEFINER abaixo (deny by default)
```

**Gatilho de integridade (BEFORE INSERT/UPDATE, SECURITY DEFINER, `search_path = ''`)** — garante:

- o `layout_id` é o layout da página do bolso;
- a `collection_id` é a proprietária do layout e uma coleção REFERENCE_BASED de Pokédex;
- a posição pertence à Pokédex da coleção e está no escopo dela.

**Por que `on delete cascade` no bolso** (os conteúdos atuais usam RESTRICT): referência não é conteúdo (regra 7). Com CASCADE, remover página (5126/5235) e desmontar (5242) continuam funcionando **sem alteração** — eles apagam os filhos explícitos e depois as páginas/bolsos. Com RESTRICT, as duas funções passariam a falhar em fichários com referências e precisariam ser reescritas.

### 3.2 Escritas (5258) — todas SECURITY DEFINER, `search_path = ''`, `revoke` de PUBLIC/anon, `grant execute` só para `authenticated`, dono verificado por `auth.uid()` dentro da função

**`preview_my_binder_species_references(p_collection_id uuid) returns jsonb`**

Recusa (erro com mensagem humana) quando:

- a coleção não é do usuário, não é REFERENCE_BASED de Pokédex ou não é ACTIVE;
- a coleção não é proprietária de um fichário;
- o fichário já tem referências.

Calcula, sem gravar:

- `positions_in_scope` — posições da Pokédex no escopo da coleção, por `position_number`;
- `slots_total` — bolsos em ordem página → linha → coluna;
- `pairs = min(positions_in_scope, slots_total)` (F002: 1.025);
- `slots_left_free` (31) e `positions_unplaced` (0; > 0 se o fichário for menor que o escopo);
- primeiro e último bolso (página/linha/coluna);
- `slots_with_visible_content` — quantos dos bolsos-alvo já têm carta, imagem ou estão em região; informativo, porque a referência fica oculta neles;
- `plan_token` = md5 de (layout, lista ordenada `slot_id:pokedex_position_id` dos pares).

**`apply_my_binder_species_references(p_collection_id uuid, p_plan_token text) returns jsonb`**

- Mesmo controle de dono/modalidade.
- Trava o layout (`select … for update` em `collection_layout`) e fixa `lock_timeout 5s`.
- Recalcula o plano e compara com `p_plan_token`. Se divergir, recusa com "O fichário mudou desde a prévia; revise e confirme de novo."
- **Idempotente:** se as referências já existirem com exatamente o mesmo plano, retorna `already_applied = true` sem gravar. Se existirem com outro plano, recusa.
- Grava os pares com **um único `insert … select`** (1.025 linhas, sem laço) e devolve as contagens.
- Não toca páginas, bolsos, posições, reservas, imagens, regiões, alocações, exemplares, `updated_at` do layout nem progresso.

**`clear_my_binder_species_references(p_collection_id uuid, p_expected_count int) returns jsonb`**

- Apaga só a camada do layout da coleção do usuário.
- `p_expected_count` (vindo da tela) protege contra exclusão às cegas.
- Se não houver nada, sai sem erro (repetível).

### 3.3 Leitura (5259)

**`get_my_binder_species_references(p_collection_id uuid, p_first_page int, p_page_count int)`**

- Retorna `table(slot_id uuid, page_number int, national_number int, species_name text, species_artwork_path text)`.
- SECURITY DEFINER; o leitor precisa ser dono da coleção (mesmo critério das leituras do fichário 5252). `p_page_count` limitado a 4 (spread atual de 2 páginas + vizinhas para pré-carga).
- Só devolve referências cuja `collection_id` seja **a proprietária atual** do layout. Se o fichário for transferido (5254), as referências antigas ficam ocultas, sem apagar nada.
- `species_artwork_path`: mesma subconsulta lateral de 5204/5211 (`IMPORTED`, `display_storage_path not null`, `order by created_at, id limit 1`). O frontend usa o `speciesArtworkUrl` existente (`web/lib/pokedex/artwork.ts`).
- Payload por spread: ≤ 32 linhas (4×4 × 2 páginas), ou ≤ 64 com pré-carga.

### 3.4 Frontend (incremento posterior, separado)

- `BinderWorkspace` busca as referências do spread **só quando a proprietária é uma coleção de Pokédex**. Os demais fichários não chamam nada (regra 9).
- O bolso vazio renderiza a arte com `loading="lazy"`, `decoding="async"`, tamanho do bolso (sem resolução maior que a necessária) e proporção reservada (sem CLS). Respeita `prefers-reduced-motion`; nenhuma animação nova.
- Ações de aplicar/ocultar com prévia, confirmação, loading, sucesso, erro e retry, nos primitives do Design System. A contracapa e o Centro de Controle não são tocados.

## 4. Impacto nas operações existentes

Com a referência chaveada no `slot_id`, nenhuma função existente precisa mudar.

| Operação | Comportamento com referências | Mudança em contrato existente |
|---|---|---|
| Posicionar / retirar carta (5250, 5133) | referência oculta sob a carta; volta ao retirar | nenhuma |
| Mover / trocar carta (5132) | a carta muda de bolso; cada referência fica no seu bolso | nenhuma |
| Reservas (expected_content) | a reserva prevalece visualmente; a referência não é reserva | nenhuma |
| Imagens de bolso (5233/5234) | a imagem cobre a referência; ao limpar, ela volta | nenhuma |
| Mesclar região / imagem de região (5134, 5238–5241) | bolsos mesclados escondem as referências, que reaparecem ao desfazer a mescla | nenhuma |
| Travar bolso | sem efeito sobre a referência | nenhuma |
| Inserir / fechar vão (5243) | move apenas carta, reserva e imagem; **a referência fica no bolso** (ordem nacional preservada). O LIVRE da 5243 não olha referências, logo bolso só com referência continua LIVRE | nenhuma |
| Adicionar página (5125) | bolsos novos sem referência | nenhuma |
| Reordenar páginas (5127) | referências acompanham suas páginas; a ordem nacional fica na ordem escolhida pelo usuário | nenhuma |
| Remover página (5126/5235) | referências da página somem (CASCADE); as demais ficam onde estão | nenhuma (ver risco R3) |
| Desmontar fichário (5242) | tudo some com páginas/layout (CASCADE) | nenhuma |
| Transferir propriedade (5254) | referências ficam gravadas, mas a leitura as oculta se a nova proprietária não for a coleção que as criou | nenhuma |
| Excluir coleção | CASCADE via `collection_id`/layout | nenhuma |
| Montagem do fichário (5251) / progresso / contagens da Pokédex | não leem a tabela nova | nenhuma |
| Token de desmontagem (5226) | não serializa referências; a desmontagem continua removendo tudo | nenhuma |

**Decisão para o proprietário (D1, vão):** a proposta mantém a referência fixa no bolso durante inserir/fechar vão. A alternativa é a referência "andar" com o conteúdo, o que exigiria alterar `binder_gap_move_pocket` e a definição de LIVRE da 5243 — e romperia a ordem nacional.

## 5. Segurança, integridade e performance

- **Isolamento:** tabela sem grants e sem policies; todo acesso passa por RPC que verifica `auth.uid()`. A homologação prova que o usuário B não lê, aplica nem apaga as referências do usuário A, e que `anon` é negado.
- **Privilégio mínimo:** `search_path = ''`, objetos qualificados, `revoke` de PUBLIC/anon, `grant` só a `authenticated`. Não reutiliza RPC administrativa.
- **Atomicidade:** aplicar e ocultar rodam em transação única; falha = nada gravado.
- **Idempotência / concorrência:** PK por bolso, `unique (layout_id, pokedex_position_id)`, trava do layout, `plan_token` e retorno `already_applied`. Clique duplo, retry e timeout não duplicam nem misturam.
- **Dado externo:** nenhum; usa apenas `pokedex_position` e `pokemon_species_artwork`, já canônicos. Espécie sem arte importada: a linha existe, o frontend mostra só o número (sem placeholder inventado).
- **Volume:** 1.025 linhas por fichário de Pokédex Nacional (um `insert … select`); leitura indexada por `layout_id`, ≤ 64 linhas por spread, sem N+1. Milhares de usuários × ~1k linhas = milhões de linhas pequenas, todas acessadas por índice.

## 6. Riscos

| # | Risco | Mitigação | Classe |
|---|---|---|---|
| R1 | Usuário espera que a referência "ande" ao inserir vão | D1 explícita; a ordem nacional fica fixa por padrão | decisão |
| R2 | Reordenar páginas embaralha a ordem nacional visível | comportamento coerente com "rótulo do bolso"; ocultar e reaplicar restaura a ordem (somente se não houver outras referências) | baixo |
| R3 | Remover página apaga referências sem aviso (5235 não conta referências) | aceito nesta fase; a prévia de remoção pode passar a mencionar referências em incremento futuro; ocultar e reaplicar recompõe a ordem | baixo, registrado |
| R4 | Transferência para coleção não-Pokédex deixa linhas órfãs ocultas | a leitura filtra pela proprietária atual; ocultar limpa | baixo |
| R5 | Novas espécies (> 1.025) no futuro | o plano só usa as posições existentes; reaplicar é decisão futura (personalização) | baixo |
| R6 | Visual da referência confundido com carta possuída | opacidade baixa, sem moldura de carta, `aria-label` "Bolso vazio — reservado visualmente para #0001 Bulbasaur"; validação visual obrigatória | médio, homologação |
| R7 | Migrations nunca rodadas em PostgreSQL real antes do LIVE (mesma política do projeto) | transação por migration, harness 5857 quando autorizado, prechecks/postchecks só leitura | aceito pelo proprietário em rodadas anteriores |

## 7. Plano de homologação (cada passo exige autorização própria)

1. **Implementação local:** migrations 5257–5259 + harness `5857` + leituras de precheck/postcheck. Frontend atrás da condição "proprietária é Pokédex". Typecheck/testes; lint/build na máquina de Fabrício.
2. **Harness 5857** (onde for autorizado). Deve cobrir:
   - dono A aplica; B não lê, não aplica, não apaga; anon negado;
   - aplicação com plano divergente recusa; duplicada retorna `already_applied`; com referências de outro plano recusa;
   - coleção livre e coleção não-Pokédex recusadas;
   - 1.025 pares na ordem certa e 31 livres no F002 sintético;
   - inserir/fechar vão, mover, imagem e região não alteram a tabela;
   - remover página e desmontar apagam por CASCADE sem erro;
   - transferência oculta;
   - nenhuma alteração em posições, reservas, imagens, alocações, exemplares, `updated_at` do layout ou progresso (fingerprints antes/depois).
3. **Precheck LIVE (somente leitura):**
   - F002 = 66 páginas / 1.056 bolsos;
   - 1.025 posições no escopo com arte;
   - fingerprints `assignments_md5`, `layout_md5`, `allocations_md5`, `physical_storage_md5`;
   - 5257–5259 ausentes.
4. **Aplicar 5257 → 5258 → 5259** (uma por vez, `apply_migration`, md5 do ledger = corpo).
5. **Postcheck:**
   - ACL (sem grants na tabela; RPCs só para `authenticated`);
   - tabela vazia;
   - fingerprints idênticos.
6. **Deploy do frontend** (pelo fluxo do proprietário).
7. **Uso real pela interface:** prévia mostra 1.025 / 31 → confirmar. Postcheck:
   - 1.025 linhas, bolso ordinal *n* ↔ #n, bolsos 1.026–1.056 sem linha;
   - fingerprints de posições, layout, alocações e exemplares **inalterados**.
8. **Validação visual:** Light/Dark, desktop/tablet/mobile, teclado e foco, leitor de tela, bolso com carta e com imagem escondendo a referência, F001 sem nenhuma mudança, contracapa e Centro de Controle intactos.
9. **Promoção canônica** (`database/schema/`), `05d` (nova camada de referência por bolso), `concept-decisions` (nova decisão), `INDEX`, `log`, handoff.

## 8. Decisões pedidas ao proprietário antes da implementação

- **D1** — Referência fixa no bolso durante inserir/fechar vão (recomendado) ou acompanhando o conteúdo.
- **D2** — Ponto de entrada da ação aplicar/ocultar: no próprio fichário (recomendado, não toca o Centro de Controle) ou, mais tarde, em Organização no Centro de Controle.
- **D3** — Com reserva no bolso: a reserva prevalece (recomendado) ou mostrar a referência por baixo.

## 9. Implementação local (POKEDEX-BINDER-SPECIES-REFERENCE-IMPLEMENTATION-01)

### 9.1 Decisões aprovadas

- **D1** — Inserir e fechar vão: as referências ficam no bolso físico. As cartas se deslocam de forma independente.
- **D2** — As ações ficam no próprio Fichário Digital, num botão novo "Pokémon nos bolsos" no menu lateral. O Centro de Controle não muda.
- **D3** — A reserva tem prioridade. Carta, imagem e mesclagem também ocultam a referência enquanto ocupam o bolso.
- **Ajuste A** — Mostrar e ocultar são uma preferência persistida, separada das referências. Ocultar nunca apaga os vínculos. A remoção é uma ação separada e explícita.
- **Ajuste B** — Excluir uma página com referências exige confirmação explícita da perda.

### 9.2 Contratos preparados (NÃO EXECUTADOS)

Em relação à proposta (§3), mudou o seguinte:

- entrou a tabela de preferência (ajuste A);
- entraram a RPC de exibição e a leitura de estado;
- a leitura por páginas segue o mesmo lote de até 4 páginas das leituras 5252/5234/5241;
- entrou a **5260**, que altera `remove_layout_page` por causa do ajuste B.

| Arquivo | Conteúdo |
|---|---|
| `5257_create_binder_species_reference_tables.sql` | `collection_layout_slot_species_reference`: PK = bolso; CASCADE com bolso, layout e coleção; RESTRICT com posição; UNIQUE (layout, posição); `source` = `NATIONAL_ORDER`. `collection_layout_species_reference_setting`: preferência por fichário; sem linha = visível. RLS ligada, 0 policies, sem grants. Gatilho de integridade (bolso ↔ layout, proprietária, coleção Pokédex, posição da Pokédex da coleção). |
| `5258_create_binder_species_reference_writes.sql` | Helpers internos `binder_species_reference_target` e `binder_species_reference_plan` (fonte única do plano; sem grant). RPCs: `preview_my_binder_species_references(uuid)` (não grava); `apply_my_binder_species_references(uuid, text)` (token SHA-256 conferido sob a trava 5122; idempotente com `ALREADY_APPLIED`; um único `insert … select`); `set_my_binder_species_reference_visibility(uuid, boolean)` (preferência apenas, aceita proprietária ou convidada); `clear_my_binder_species_references(uuid, int)` (contagem exata). |
| `5259_create_binder_species_reference_reads.sql` | `get_my_binder_species_reference_state(uuid)`: leitura leve. `get_my_collection_binder_species_references(uuid, int, int)`: até 4 páginas; devolve bolso, número nacional, nome e `display_storage_path` (mesma fonte de `species_artwork_path`). Só mostra referências da proprietária atual. |
| `5260_update_remove_layout_page_species_references.sql` | Nova `remove_layout_page(uuid, integer)` com o corpo da 5235 preservado em ordem (prova S6) e o passo 5b. Com referências na página, recusa sem a contagem exata (`HINT SPECIES_REFERENCES_ON_PAGE:N`); com a contagem, apaga as referências e a página. A assinatura de 1 argumento passa a delegar com confirmação 0: página sem referências segue igual; página com referências passa a recusar. |
| `5857_validate_binder_species_reference.sql` | Harness com 35 checagens (estrutura/ACL, isolamento A×B/anon, prévia e ordem nacional, idempotência, preservação de páginas/cartas/reservas/imagens/alocações/exemplares, exibição sem apagar, páginas e ajuste B, remoção, gatilho, arquivada), com resíduo zero pela sentinela. **NÃO EXECUTADO.** |
| `static_check_species_reference.py` | Regras S1–S7 (transação, definer/search_path, grants, nenhuma migration existente cita as tabelas novas, única função existente alterada = `remove_layout_page`, corpo da 5235 preservado, total do harness). |

Impacto nas operações existentes: o mesmo da §4, com uma exceção. **Remover página** deixou de apagar referências por CASCADE e passou a exigir confirmação (5260). A desmontagem (5242) continua apagando tudo junto com o fichário, por ser a consequência explícita da própria ação.

### 9.3 Frontend local

- **`web/lib/colecoes/binder-species.ts`** — regras puras: quando ler, quando exibir (D3 + preferência), parsers, número `#0001`, falhas e mensagens. Inclui o reconhecimento da recusa da 5260 e o texto do aviso de exclusão de página.
- **Testes** — `binder-species.test.ts` com 9 testes.
- **`binder.ts`** — `BinderSlot.speciesRef` (opcional).
- **`binder-queries.ts`** — a leitura das referências entra no mesmo lote de páginas, em paralelo, **só quando o fichário é de Pokédex ou convidada**. A falha nunca bloqueia o lote: o bolso fica vazio como antes. Também traz o estado leve.
- **`fichario/page.tsx` e `binder-view.tsx`** — estado lido no servidor junto com o primeiro lote.
- **`binder-overlay.tsx`** — no fichário aberto sobre a coleção, o estado é lido pelo cliente uma única vez.
- **`fichario/actions.ts`** — `readBinderPages` aceita `speciesReferences`. Ações novas: `readSpeciesReferenceState`, `previewSpeciesReferences`, `applySpeciesReferences`, `setSpeciesReferenceVisibility`, `clearSpeciesReferences`. Todas usam a sessão do usuário, sem `service_role`.
- **`binder-slot.tsx`** — `SpeciesReferenceVisibleContext` e `SpeciesReferenceArt`:
  - arte oficial em WebP de 320 px, `loading="lazy"`, opacidade 0,26, levemente dessaturada, sem moldura de carta;
  - número nacional discreto na base;
  - rótulo acessível "bolso reservado visualmente para #0001 Bulbasaur";
  - sem arte ou com falha, mostra só o número.
- **`binder-tool-rail.tsx`** — botão "Pokémon nos bolsos" (`PawPrint`), presente só em fichário de Pokédex, ativo quando as referências estão exibidas.
- **`binder-species-dialog.tsx`** — diálogo no mesmo padrão de "Adicionar páginas":
  - prévia com Pokémon, intervalo, bolsos sem referência e avisos;
  - confirmação;
  - interruptor do Design System para exibir/ocultar, com resposta imediata e reversão se o banco recusar;
  - remoção com confirmação.
- **`binder-workspace.tsx`** — estado, provedor do contexto, botão e diálogo. Depois de aplicar ou remover, relê no lugar os lotes já carregados, sem esvaziar a tela.

Fichários que não são de Pokédex não fazem nenhuma chamada nova e não ganham botão; o bolso vazio continua idêntico. A contracapa, o Centro de Controle e a correção cromática (`binder-chrome.tsx` e `binder-finish.ts`, incluindo o Marinho da Minha Pokédex) **não foram tocados nesta rodada**.

**Exclusão de página no frontend:** hoje a interface **não oferece** remover página (nenhum chamador de `remove_layout_page` em `web/`). A proteção do ajuste B vale no contrato (5260) para qualquer chamada. Quando houver uma tela de remover página, ela deve chamar a RPC, reconhecer a recusa com `speciesReferencesOnPage`, mostrar `pageRemovalWarning(N)` e repetir com N. Isso está preparado e testado na lib.

### 9.4 Verificações desta rodada

| Verificação | Resultado |
|---|---|
| `npm run typecheck` (`tsc --noEmit`) | PASS |
| Testes unitários `lib/colecoes/*.test.ts` + `lib/pokedex/*.test.ts` | 400/400 PASS (inclui os 9 novos) |
| ESLint nos 12 arquivos modificados ou criados | PASS (0 avisos) |
| `static_check_species_reference.py` | PASS (S1–S7) |
| `git diff --check` | ver relatório da rodada |
| Migrations e harness em PostgreSQL | **NÃO EXECUTADOS** (proibido nesta rodada; sem ambiente isolado) — a sintaxe SQL não foi provada por um parser |
| `next build` / `next lint` completos | não executados (limitação do sandbox) |
| Homologação visual (Light/Dark, desktop/tablet/mobile, teclado, F001 sem mudança) | **PENDENTE** com Fabrício |

### 9.5 Riscos remanescentes

- SQL nunca executado em PostgreSQL real: erros de sintaxe ou execução só aparecem na aplicação. Mitigações: transação por migration e harness 5857 quando autorizado.
- A 5260 altera `remove_layout_page` (as duas assinaturas). Sem chamador no frontend; o risco é comportamental apenas para chamadas diretas.
- O peso visual da arte (opacidade 0,26) depende da homologação: pode competir com cartas vizinhas ou ser confundida com carta possuída.
- No overlay, o estado é lido depois de abrir: o botão aparece com pequeno atraso. Não afeta a leitura das referências, que vêm no lote.

### 9.6 Próximo gate de implantação (cada passo com autorização própria)

1. Fabrício: `next lint` e `next build` locais, mais homologação visual sobre dados simulados ou após o passo 3.
2. Precheck LIVE somente leitura:
   - F002 com 66 páginas e 1.056 bolsos;
   - 1.025 posições no escopo com arte;
   - fingerprints `assignments_md5`, `layout_md5`, `allocations_md5`, `physical_storage_md5`;
   - 5257–5260 ausentes.
3. Aplicar 5257 → 5258 → 5259 → 5260, uma por vez (md5 do ledger = corpo), com postcheck de ACL e fingerprints idênticos.
4. Deploy do frontend; uso real: prévia 1.025 / 31 → confirmar.
5. Postcheck:
   - 1.025 linhas, bolso *n* ↔ #n, bolsos 1.026–1.056 sem linha;
   - fingerprints inalterados.
6. Homologação final e promoção canônica (`database/schema/`, `05d`, `INDEX`, `log`, handoff).
