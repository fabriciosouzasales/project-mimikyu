# Minhas coleções — fundação (MY-COLLECTIONS-FOUNDATION-01)

| Campo | Valor |
|---|---|
| Data | 2026-10-17 |
| Status | **INVESTIGAÇÃO E PREPARAÇÃO. Nenhum SQL escrito ou executado; nenhum contrato alterado.** STOP antes de CT-01 (contrato novo de escrita) e das decisões D-A/D-B/D-C. |
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

## 3. Decisões necessárias antes do staging

| ID | Decisão | Recomendação |
|---|---|---|
| D-A (R4) | Local padrão quando o usuário já tem locais | Criar "Local padrão" só se o usuário não tiver nenhum local; se tiver, reaproveitar o mais antigo. Nunca destino automático de cartas (NS-13). |
| D-B | Onde guardar a chave de idempotência do CT-01 | Tabela própria e mínima (`collection_creation_request`: dono + chave única → coleção e local). Alternativa: estender `bulk_operation` (exige mudar `chk_bulk_operation_type` e não se encaixa em fingerprint de Revisão). |
| D-C | "Vincular cartas que já tenho" | Padrão **1 de cada** (146 cartas; as 273 repetidas ficam no acervo); opção "todas" disponível. |

## 4. Experiência proposta (resumo)

- Rota `/colecoes/colecoes` "Minhas coleções", ao lado de Meu acervo em Coleções → Gerenciar.
- Biblioteca: baseline aprovado (Cards padrão, Lista, Carrossel; capa Binder MMKYU) promovido de `web/components/experimental/collection-*` para componentes de produto, alimentado por R1. Primeira entrega: Cards e Lista; Carrossel depois (implementação atual em iframe não é base).
- Estado vazio com uma ação: "Criar minha primeira coleção". Quando há cartas no acervo sem coleção, o vazio sugere os Sets do acervo ("Você tem 146 cartas de Celebração de 30 Anos").
- Criação: tipo ("Completar um Set") → Set (Seus Sets primeiro, com logo) → nome sugerido → "Criar coleção" (CT-01). Sucesso leva à coleção com o convite "Vincular as 146 cartas que você já tem".
- Coleção: cabeçalho com progresso protagonista ("146 de 158", 92%), grade de cartas em 8:11 reutilizando a arte de Meu acervo/Pokédex, alternância Tenho/Faltam (hipótese a homologar), repetidas como contagem, faltantes atenuadas com texto.
- Vincular: folha de Revisão ("146 cartas vão para esta coleção; 273 repetidas continuam no acervo") → confirmar → contagem animada do progresso.

## 5. Sequência mínima

1. Decisões D-A, D-B, D-C (Fabrício).
2. Staging em `database/proposals/` (este diretório): CT-01, R1, R2, R3 + harnesses (isolamento A×B, anon, idempotência, falha induzida, duplo envio, resíduo zero).
3. Aplicação no LIVE com autorização; validação; promoção para `database/schema/`.
4. Frontend: rota, Biblioteca (Cards/Lista), criação, coleção (grade + progresso), vincular. Typecheck local; lint/build na máquina do Fabrício.
5. Homologação com o acervo real: criar "Celebração de 30 Anos" e "Coleção Clássica", vincular 1 de cada, conferir 146/158 e 7/30, tirar e devolver uma carta, conferir que o acervo continua com 426 exemplares.
6. Documentação (05d, HANDOFF, log) no mesmo ciclo.
