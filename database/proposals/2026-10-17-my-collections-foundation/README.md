# Minhas coleções — fundação (MY-COLLECTIONS-FOUNDATION-01)

| Campo | Valor |
|---|---|
| Data | 2026-10-17 |
| Status | **`5166`–`5170` CONFIRMADO EXECUTADO no LIVE (2026-10-17, autorização condicionada de Fabrício).** Ledger `20261017152343`, `…152413`, `…152431`, `…152451`, `…152501`; `prosrc` dos 4 corpos = arquivo (md5). `5830` v1.1: **GATE PASS 35/35**, resíduo zero. Security Advisor: `0029` 153 → 157 (as 4 funções, por desenho) e `0008` 29 → 30 (`collection_creation_request`, RLS sem policies por desenho — só a 5167 acessa). Nenhuma outra categoria mudou. Promovidas para `database/schema/` em 2026-10-17 (MY-COLLECTIONS-FRONTEND-01, corpo idêntico ao LIVE). |
| Autoridade | `docs/domain-modeling/collections/north-star-2026-10-16.md` v1.4 (NS-01–NS-14, Fluxos 1, 2, 3 e 5, §2.6/CT-01, B1–B8); C-*/LDM-* prevalecem em domínio. |
| Skills | `impeccable` (shape) e `mmkyu-frontend-experience` (Core Experience Set #1 — Biblioteca em 3 modos, baseline aprovado). |

## 1. Situação real (LIVE, 2026-10-17, leitura)

| | ME5.5 — Celebração de 30 Anos | ME5.5CC — Celebração de 30 Anos Coleção Clássica |
|---|---|---|
| Card Set | `3aa3fcf6-…485a`, `SPECIAL`, base 128 / total 158 | `21add268-…99f0`, `SPECIAL`, base 30 / total 30 |
| Expansion | ME | ME (mesma) |
| Referência externa | `30th` | `30th-c` |
| Cartas / variantes | 158 / 158, todas com variante padrão | 30 / 30, todas com variante padrão |
| Logo | sim | sim |
| Acervo do Fabrício | 419 exemplares, 146 cartas distintas, pt-BR, só variante padrão | 7 exemplares, 7 cartas, pt-BR |
| Repetidas | 273 | 0 |
| Em coleção / com local | 0 / 0 | 0 / 0 |
| Progresso esperado ao vincular 1 de cada | 146 de 158 (92,4%) | 7 de 30 (23,3%) |

- São **referências independentes**: Card Sets distintos, IDs externos distintos. Uma coleção tem 0..1 referência (LDM-06/07), então "ME5.5 + Coleção Clássica" = **duas coleções de Set** (ou uma Coleção livre, sem progresso — C-20).
- LIVE hoje: 0 coleções, 0 alocações, 0 locais físicos.
- Alocação é exclusiva: `UNIQUE(physical_card_id)` em `collection_allocation` — vincular **move a carta para a coleção, nunca a duplica**; a carta continua uma só no acervo.

## 2. Contratos LIVE e lacunas

### Existentes (reutilizados sem alteração)

| Necessidade | Contrato | Observação |
|---|---|---|
| Criar coleção de Set | `create_reference_based_card_set_collection` (5065/5069) | **Exige `p_default_storage_container_id` do próprio Inventory** (C-36; `collection.default_storage_container_id NOT NULL`). Ver CT-01. |
| Criar local | `create_storage_container` (5022) | Não idempotente; não pode ser orquestrado no cliente (NS-06/D1). |
| Vincular cartas | `allocate_physical_cards_to_collection` (5046) | ≤ 500 por chamada, atômica, valida dono, Game, Set referenciado e "já alocada". 146 cartas = 1 chamada. |
| Desvincular | `deallocate_physical_cards_from_collection` (5047) | "Tirar da coleção" (N14). |
| Progresso | `collection_completion_summary` (5070/5083/5100), `collection_completion_positions` (5071) | STANDARD_SET: denominador = cartas do Set; numerador = carta satisfeita por qualquer variante alocada. Sem imagem. |
| Renomear / arquivar | `update_collection_metadata`, `archive_collection`, `reactivate_collection` | Profundidade sob demanda. |
| Sets do acervo | `get_my_inventory_filter_options` (5161) | Sets presentes no acervo, com contagem — base do seletor "Seus Sets". |
| Leitura de coleção direta | RLS `collection_select_own` etc. | Insuficiente: catálogo (`card_set`, `card`) é admin-only (ADR-022). |

### Lacunas indispensáveis

| # | Lacuna | Por que é indispensável | Forma proposta |
|---|---|---|---|
| **CT-01** | Criar coleção + "Local padrão" numa transação idempotente | NS-06/D1: sem ele não existe caminho conforme para a primeira coleção (o usuário tem 0 locais) | `create_my_collection(...)` aditiva; não altera 5022/5034/5065. **Contrato novo de escrita → STOP.** |
| **R1** | Leitura da Biblioteca | "Minhas coleções" precisa de nome, Set (código, nome, logo), progresso, nº de cartas e capa numa chamada (sem N+1) | `get_my_collections(p_include_archived, p_limit, p_offset)` |
| **R2** | Conteúdo da coleção com imagem | Fluxo 3: grade "Tenho / Faltam" com arte real em 8:11; 5071 não traz imagem | `get_my_collection_positions(p_collection_id, p_filter, p_limit, p_offset)` — posição, número, nome, imagem, satisfeita, nº de exemplares na coleção, nº de exemplares disponíveis no acervo (sugestão, nunca alocação automática — C-19) |
| **R3** | Candidatas a vincular | "Vincular cartas que já tenho" sem 146 chamadas a 5162 | `get_my_collection_link_candidates(p_collection_id, p_mode)` — `ONE_PER_CARD` (padrão) ou `ALL`; só exemplares próprios, sem coleção, do Set referenciado; escolha determinística (exemplar mais antigo). A escrita continua sendo a 5046. |

Todas as leituras: `SECURITY DEFINER`, `STABLE`, `search_path = ''`, dono por `auth.uid()`, `EXECUTE` só `authenticated`, não enumeração, paginação. Numeração livre: funções `5166`+, harnesses `5830`+.

Não indispensável nesta rodada: seletor de Sets com logo e busca do catálogo inteiro (usar "Seus Sets" de 5161 + `search_cards` já usado em Meu acervo); Master Set; Coleção livre; fichário; Onde guardo.

## 3. Decisões de Fabrício (2026-10-17)

| ID | Decisão |
|---|---|
| D-A (R4, revisada) | Usuário **sem** locais → CT-01 cria automaticamente o "Local padrão". Usuário com **um ou mais** locais → o local é **escolha explícita** na criação da coleção (sem seleção automática, nem do mais antigo, nem quando só existe um). Nenhuma carta é atribuída a local algum. C-26, C-36, C-55, C-59 e NS-13 preservadas. |
| D-B | Idempotência em tabela própria e mínima (`collection_creation_request`). |
| D-C | "Vincular as cartas que já tenho": **1 de cada**. Condição da autorização de implantação: a primeira experiência **não** oferece vincular todas as repetidas — a `5170` v1.1 só tem esse modo. |

## 3a. Staging (proposto, não executado)

| Query | Objeto | Tipo | Papel |
|---|---|---|---|
| `5166` | `collection_creation_request` | tabela | Idempotência do CT-01 (D-B). RLS sem policies; sem privilégios de cliente; FKs `ON DELETE CASCADE` para não bloquear `delete_collection` |
| `5167` | `create_my_card_set_collection(key, card_set, name, storage?)` | escrita (CT-01) | Uma transação: local (D-A) + coleção via `5065` + registro. Serializa por usuário (advisory lock); replay pela chave; `55000 STORAGE_CONTAINER_REQUIRED` quando já há local e nenhum foi escolhido |
| `5168` | `get_my_collections(archived?, limit, offset)` | leitura (R1) | Biblioteca: Set (código, nome, logo), progresso canônico via `5070`, nº de cartas, capa |
| `5169` | `get_my_collection_positions(collection, filter, limit, offset)` | leitura (R2) | Grade Tenho/Faltam com arte, exemplares na coleção e disponíveis no acervo |
| `5170` | `get_my_collection_link_candidates(collection, limit)` | leitura (R3) | Exemplares livres do Set, **1 por carta ainda faltante** (sem modo "todas"), ≤ 500 por chamada (teto da `5046`) |
| `5830` | harness | validação | 35 verificações + GATE: estrutura/ACL, anon, sem identidade, falha induzida sem resíduo, D-A (cria / exige escolha / recusa local alheio), replay e chave reutilizada, entradas inválidas, nenhuma carta com local, R1/R2/R3 com isolamento A×B, vincular via `5046` sem duplicar cartas, coerência com `5070`, resíduo zero |

Ordem de aplicação: `5166` → `5167` → `5168` → `5169` → `5170` → `SELECT * FROM pg_temp.rc_5830_validate('<A>', '<B>')` (A e B sem locais nem coleções) → Security Advisor (esperado: +4 em `0029`, por desenho) → promoção para `database/schema/`.

Contratos reutilizados sem alteração: `5022`, `5065`/`5069`, `5046`, `5070`/`5083`/`5100`.

Validação estática apenas: não há Postgres no ambiente do agente e nada foi executado no LIVE; o `5830` é a prova executável. **Não provado pelo harness:** duplo envio *concorrente* (duas sessões simultâneas). O desenho cobre por `pg_advisory_xact_lock` por usuário + `UNIQUE(owner_user_id, idempotency_key)`; o `5830` prova a repetição sequencial. Prova concorrente exige duas conexões (manual, como o K01 do BULK).

## 4. Experiência proposta (resumo)

- Rota `/colecoes/colecoes` "Minhas coleções", ao lado de Meu acervo em Coleções → Gerenciar.
- Biblioteca: baseline aprovado (Cards padrão, Lista, Carrossel; capa Binder MMKYU) promovido de `web/components/experimental/collection-*` para componentes de produto, alimentado por R1. Primeira entrega: Cards e Lista; Carrossel depois (implementação atual em iframe não é base).
- Estado vazio com uma ação: "Criar minha primeira coleção". Quando há cartas no acervo sem coleção, o vazio sugere os Sets do acervo ("Você tem 146 cartas de Celebração de 30 Anos").
- Criação: tipo ("Completar um Set") → Set (Seus Sets primeiro, com logo) → nome sugerido → (se já houver locais) "Onde guardo" com escolha obrigatória, sem item pré-selecionado → "Criar coleção" (CT-01). Sucesso leva à coleção com o convite "Vincular as 146 cartas que você já tem".
- Coleção: cabeçalho com progresso protagonista ("146 de 158", 92%), grade de cartas em 8:11 reutilizando a arte de Meu acervo/Pokédex, alternância Tenho/Faltam (hipótese a homologar), repetidas como contagem, faltantes atenuadas com texto.
- Vincular: folha de Revisão ("146 cartas vão para esta coleção; 273 repetidas continuam no acervo") → confirmar → contagem animada do progresso.

## 5. Sequência mínima

1. ~~Decisões D-A, D-B, D-C~~ — tomadas em 2026-10-17.
2. ~~Staging~~ — escrito (§3a); em `database/proposals/` (este diretório): CT-01, R1, R2, R3 + harnesses (isolamento A×B, anon, idempotência, falha induzida, duplo envio, resíduo zero).
3. Aplicação no LIVE com autorização; validação; promoção para `database/schema/`.
4. Frontend: rota, Biblioteca (Cards/Lista), criação, coleção (grade + progresso), vincular. Typecheck local; lint/build na máquina do Fabrício.
5. Homologação com o acervo real: criar "Celebração de 30 Anos" e "Coleção Clássica", vincular 1 de cada, conferir 146/158 e 7/30, tirar e devolver uma carta, conferir que o acervo continua com 426 exemplares.
6. Documentação (05d, HANDOFF, log) no mesmo ciclo.

## 6. Execução no LIVE (2026-10-17)

Condições da autorização, confirmadas antes da execução:
1. **Identidades de teste:** o `5830` v1.1 não usa nenhum usuário real. Cria dois usuários efêmeros em `auth.users` dentro do bloco revertido (perfil e Inventory pelos gatilhos existentes); tudo é desfeito pela sentinela. Pós-check independente: 3 usuários, 3 perfis, 3 Inventories, 426 exemplares, 0 coleções, 0 locais, 0 alocações, 0 registros, 0 usuários `rc5830-*`, gatilho de teste ausente — idêntico à linha de base.
2. **D-C:** `5170` v1.1 só oferece "1 de cada" (modo `ALL` removido antes da aplicação); `5830` 6.2 prova que não existe outra assinatura.

Aplicação: `5166` → `5167` → `5168` → `5169` → `5170` (uma migration por arquivo, corpo idêntico). ACL das 4 funções: `postgres` + `authenticated` (sem PUBLIC, anon ou service_role).

Ressalvas: duplo envio concorrente do CT-01 não provado (só sequencial); medição B4 com volume pendente (ambiente isolado, R3); promoção para `database/schema/` e documentação canônica (05d, HANDOFF) pendentes para o fechamento do ciclo.
