# V1-12 — Roteiro de homologação visual (titular · VIEWER · vitrine)

| Campo | Valor |
|---|---|
| Status | **APROVADO VISUALMENTE por Fabrício (2026-10-30):** A–D, H.1–H.6 e I (biblioteca unificada em Cards, Lista e Carrossel). Quality Gate (2026-10-30): typecheck PASS; testes `lib/colecoes` 36 arquivos 432/432 PASS; ESLint (config `next/core-web-vitals`, CLI direta) 0 erros, 6 avisos preexistentes em arquivos fora do V1-12; `next lint`/`next build` não executáveis no sandbox do agente (binário SWC ausente) — pendentes na máquina de Fabrício. **V1-12 não publicado.** |
| Data | 2026-10-30 |
| Banco | 5300–5331 no LIVE e canônicas; 5861 51/51, 5862 33/33, 5863 37/37 e 5864 7/7 PASS (evidência de contrato) |
| Frontend | local, não publicado (sem deploy). Rodar `npm run dev` em `web/` |

## Preparação (uma vez)

1. Duas contas reais: **T** (titular) e **V** (participante). Uma janela anônima para o **visitante**.
2. Em T, escolher uma coleção de **Set** com fichário digital próprio (nome próprio gravado, logomarca desligada se possível) e algumas cartas faltando.
3. Opcional, mas recomendado: uma coleção **convidada** do mesmo fichário (Ajustes → Fichário compartilhado) com ao menos uma carta posicionada.
4. T convida V (Compartilhar → username); V aceita pela caixa de convites do cabeçalho.
5. Para a vitrine: T torna a coleção pública (painel "Fichário público").

Registrar em cada item: **PASS / FAIL / N.A.**, tema, viewport e captura quando FAIL.

## A. Fichário — titular × VIEWER × vitrine

| # | Verificar | Titular (`/colecoes/colecoes/[id]` → Fichário) | VIEWER (`/colecoes/compartilhada/[id]` → Abrir o fichário) | Visitante (`/fichario/[id]`) |
|---|---|---|---|---|
| A1 | Capa: couro, acabamento, cor, zíper, logo do Set | referência | igual | igual |
| A2 | Contracapa: nome próprio do fichário e logomarca conforme a preferência | referência | igual na coleção **dona** | igual na coleção dona |
| A3 | Coleção **convidada**: nome = nome da coleção; logomarca **visível** (padrão), mesmo com a do fichário dono desligada | — | sim | sim |
| A4 | Spread, lombada, bolsos 8:11, grade e número de páginas | referência | iguais | iguais |
| A5 | Cartas de **outras** coleções do mesmo fichário | visíveis | bolso vazio (nunca carta nem reserva alheia) | bolso vazio |
| A6 | Reservas desta coleção | marca-d'água | marca-d'água | marca-d'água |
| A7 | Imagens personalizadas de bolso e capa enviada | visíveis | ausentes até 5325–5329 (ver H) | ausentes até 5325–5329 (ver H) |
| A8 | Navegação « ‹ n / N › », setas, ← → Home End, Esc fecha | referência | igual, sem ferramentas de organização | igual, sem ferramentas |
| A9 | Nenhum controle de escrita (DnD, Bandeja, seleção, Centro de Controle, cadastrar) | presentes | **ausentes** | **ausentes** |

## B. Galeria compartilhada (VIEWER) — filtros

| # | Verificar |
|---|---|
| B1 | Abas **Todas · Tenho · Faltam** com contadores iguais aos do titular |
| B2 | Ordem pelo número da carta no Set, igual à do titular em cada aba |
| B3 | Carta satisfeita por variante não padrão aparece em **Tenho** |
| B4 | Carta que o titular tem só no acervo (fora da coleção) aparece em **Faltam**; nenhuma tag "No seu acervo" |
| B5 | URL `?ver=tenho` / `?ver=faltam` reabre a aba; voltar do navegador funciona; sem salto de rolagem |
| B6 | Aba vazia mostra a mensagem certa (ex.: "Nenhuma carta faltando…") |
| B7 | Zoom da carta abre e fecha por teclado |
| B8 | Menu do selo: "Sair desta coleção" abre **por cima** das imagens do cabeçalho |
| B9 | Coleção livre/Master Set/Pokédex compartilhada: galeria das cartas alocadas (sem abas de Set) — sem erro |

## C. Revogação e privacidade (interface)

| # | Verificar |
|---|---|
| C1 | T remove V → ao recarregar, V não abre mais coleção nem fichário (página não encontrada) |
| C2 | T despublica → visitante recarrega `/fichario/[id]` e não vê mais nada |
| C3 | Em nenhuma tela de V ou do visitante aparecem local físico, condição, valor, datas, favoritos, wishlist ou acervo do titular |

## D. Tema e viewport (aplicar a A, B e C)

| Combinação | Pontos de atenção |
|---|---|
| Claro · desktop (≥ 1280 px) | navegação escura, workspace off-white, contraste das abas e contadores |
| Escuro · desktop | workspace preto profundo, cards grafite, dourado só em ativo/foco |
| Claro · celular (≈ 390 px) | fichário cabe sem rolagem horizontal; abas não quebram; menu do selo alcançável |
| Escuro · celular | mesmo do anterior; contracapa legível |
| Teclado (desktop) | foco visível em abas, selo, setas e fechar |
| `prefers-reduced-motion` | virar página e abrir/fechar sem animação |

## H. Personalizações compartilhadas e logo do Set (backend no LIVE: 5325–5331; 5863 37/37, 5864 7/7)

Rodada final. A–D já foram aprovadas — não repetir, salvo regressão aparente. Usar a preparação acima, com: na coleção **dona** do fichário, 1 imagem de bolso e 1 imagem mesclada (2 bolsos); numa coleção **convidada** do mesmo fichário, capa enviada e código de capa; uma coleção de Set **pública** sem capa enviada (para o logo oficial). Conferir em claro e escuro, desktop e celular, apenas nesta seção.

| # | Item | Verificar | Quem |
|---|---|---|---|
| H.1 | Capa personalizada | Capa enviada e código da capa aparecem no hero da coleção compartilhada e na vitrine `/fichario/[id]`, iguais ao titular | VIEWER, visitante |
| H.2 | Imagem de bolso | Aparece no mesmo bolso e com o mesmo enquadramento do titular; nenhum bolso que deveria estar vazio mostra imagem | VIEWER, visitante |
| H.3 | Imagem mesclada | Uma peça única ocupando os 2 bolsos, mesma posição e recorte do titular | VIEWER, visitante |
| H.4 | Mascaramento entre coleções | Na coleção **convidada**: nenhuma imagem do fichário dono (só a capa dela); em qualquer coleção, cartas e reservas de outra coleção do mesmo fichário seguem como bolso vazio | VIEWER, visitante |
| H.5 | Logo oficial do Set na vitrine | Visitante **sem login** vê o logo do Set na capa da vitrine (não a capa tipográfica) | visitante (janela anônima) |
| H.6 | Revogação (sanidade) | Remover o participante / despublicar → recarregar: imagens e capa deixam de carregar (URL já emitida vale até 10 min; cache local do navegador até 1 h) | VIEWER, visitante |

## I. Minhas coleções — compartilhada como coleção normal (frontend local)

Mesma página canônica (hero, painel, "Minha biblioteca", três modos). Sem seção separada de compartilhadas; convites pendentes continuam na caixa do topo.

| # | Cenário | Verificar |
|---|---|---|
| I.1 | Só coleções próprias | Idêntico ao atual (ordem, arrastar, painel) |
| I.2 | Só 1 compartilhada | Página normal com 1 card; sem estado vazio; selo "Compartilhada" + "de Fulano"; painel conta 1 coleção, sem agregados de cartas |
| I.3 | Próprias + compartilhadas | Uma estante: as suas primeiro (arrastáveis), as compartilhadas depois, sem alça; Cards, Lista e Carrossel |
| I.4 | Nenhuma coleção | Estado vazio atual |
| I.5 | Card compartilhado | Capa (logo do Set ou capa enviada), progresso e contagem iguais aos do titular; clique abre a coleção compartilhada só leitura |

## Critério de aprovação

H.1–H.6 PASS em claro/escuro e desktop/celular. Qualquer FAIL: registrar captura, não corrigir no LIVE; abrir rodada de correção de frontend. Aprovação visual **não** encerra o V1-12: faltam commit, publicação do frontend e decisão do proprietário; wrappers 5323/5324 e EDITOR (V1-13) seguem fora do escopo.
