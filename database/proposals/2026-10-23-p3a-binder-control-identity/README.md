# P3-A — Centro de Controle e Identidade do Fichário

| Campo | Valor |
|---|---|
| Versão | 1.2 (2026-10-24, `P3A-BINDER-CONTROL-FINAL-CLOSEOUT-01`) · 1.1 (2026-10-23, `P3A-BINDER-CONTROL-IDENTITY-IMPLEMENTATION-01`) · 1.0 (`P3-A-BINDER-CONTROL-IDENTITY-SPEC-01`) |
| Status | **ENCERRADA (2026-10-24, §11.9).** 5244–5246 executadas no LIVE (2026-10-24 UTC, §11.8), promovidas para `database/schema/` com equivalência proposta × canônica × LIVE comprovada; frontend homologado pela interface; lint e build PASS (Fabrício). Contracapa aprovada e congelada. Commit pendente (Fabrício). |
| Origem | Definição estratégica de Fabrício feita fora do repositório, formalizada aqui (decisões de 2026-10-23). |
| Depende de | Fichário Digital canônico: `5104`–`5141` (Binder/Layout), `5223`–`5230` (leitura, montagem, compartilhamento), `5231`–`5243` (imagens do bolso, mesclagem, "Abrir espaço"). |

## 1. Objetivo

Dar ao fichário uma **identidade própria** (nome e contracapa com a marca MMKYU) e um **Centro de Controle**: um painel lateral direito que reúne identidade, aparência, acesso à organização e informações, sem competir com o fichário e sem duplicar o menu esquerdo.

## 2. Decisões já tomadas (Fabrício, 2026-10-23)

| # | Decisão |
|---|---|
| D1 | O Centro de Controle é um **painel lateral direito, recolhível**, premium, que nunca cobre nem reduz o fichário além do necessário. O fichário continua protagonista. |
| D2 | O fichário passa a ter um **nome personalizado e editável**, **independente das coleções vinculadas**. |
| D3 | O nome aparece na **contracapa** e nos **demais pontos de identificação** do fichário (§6.4). |
| D4 | Contracapa, de cima para baixo: **logomarca MMKYU monocromática (só o rosto do Mimikyu)** → **nome do fichário** → assinatura **"MMKYU COLLECTOR"**. **Sem código de coleção** (o atual "MMKYU · SV1" sai). |
| D5 | A logomarca é discreta, centralizada, **sem fundo próprio**, **sem texto embutido**, sem competir com o nome. |
| D6 | Controle para **exibir/ocultar a logomarca** na contracapa. |
| D7 | **Sem upload de logomarca** nesta versão: só o asset interno da marca MMKYU. |
| D8 | O painel tem quatro seções: **Identidade do Fichário**, **Aparência**, **Organização**, **Informações**. |
| D9 | Reaproveitar o que existe; não duplicar ferramentas do menu esquerdo. |
| D10 | Distinguir **preferências individuais** de **alterações compartilhadas** (fichário compartilhado). |
| D11 | Fora desta fase: histórico, ordenação automática, informações financeiras. |

## 3. Estado atual (verificado no repositório)

- **Não existe nome de fichário.** `collection_layout` (`5105`) tem só `collection_id`, `grid_rows`, `grid_columns` e datas; a interface usa o nome da coleção (`collectionName`).
- **Contracapa atual** (`InsideCoverFace`, `web/components/colecoes/fichario/binder-chrome.tsx`): wordmark "MMKYU" + "Collector" no centro; nome da coleção e subtítulo `MMKYU · <código do Set>` embaixo.
- **Asset da marca:** `web/public/brand/icon-mark-light.png` / `icon-mark-dark.png` (547×308, RGBA, fundo transparente) = rosto do Mimikyu, **com bochechas laranja**, ou seja, não é monocromático.
- **Menu esquerdo** (`binder-tool-rail.tsx`):
  - Visão geral das páginas, Adicionar páginas, Bandeja, Cartas disponíveis, Só desta coleção, Tela cheia.
  - Ações em lote: Bandeja, fixar/soltar, reservar/liberar, tirar do fichário, limpar seleção.
- **Grade é imutável** depois da montagem (gatilho `5107`). Desmontar fica em Ajustes da coleção (`5226`/`5236`/`5242`).
- **Fichário compartilhado** (`5229`/`5230`): o cabeçalho traz `role` (OWNER/GUEST), coleção proprietária e `participantCount`. **Não há contrato que liste as coleções convidadas para a proprietária** (registrado em `binder-share.ts`).
- **Não existem preferências visuais** específicas do fichário; o tema claro/escuro é global.

## 4. Proposta funcional

### 4.1 Painel (Centro de Controle)

- **Abertura:** botão "Centro de Controle" no cabeçalho do fichário, ao lado de Fechar. Atalho de teclado a definir (não conflitar com ←/→/Home/End/Esc).
- **Desktop (≥ 1200 px):** painel de ~320 px que **empurra** o palco. O encaixe (`computeBinderFit`) recalcula, e o fichário encolhe proporcionalmente, sem sobreposição.
- **Tablet e celular:** folha sobreposta (lado direito no tablet; de baixo para cima no celular), com véu, foco preso e Esc fecha.
- **Estrutura:** quatro seções recolhíveis, na ordem Identidade, Aparência, Organização, Informações. Identidade abre aberta.
- **Estado aberto/fechado e seções recolhidas:** preferência **individual** do navegador (§5.3).
- **Leitura:** coleção arquivada ou usuário sem permissão de edição veem o painel em modo leitura, com o motivo exibido.

### 4.2 Seção Identidade do Fichário

- **Nome do fichário:** campo de texto (primitive `Input` + `Label` do Design System, padrão do Login), contador discreto, Salvar/Desfazer edição. Feedback: salvando → salvo (anunciado) ou erro com o motivo.
- **Prévia da contracapa:** a própria `InsideCoverFace` em escala reduzida, atualizada **ao digitar** (prévia local) e confirmada só depois da gravação.
- **Exibir logomarca MMKYU:** interruptor (switch acessível, `role="switch"`), com efeito imediato na prévia.
- **Fichário compartilhado:** para a convidada, campos em leitura, com a frase "O nome e a contracapa são definidos pela coleção dona do fichário".

### 4.3 Seção Aparência

Centraliza as preferências visuais **do fichário**. Na v1, o conteúdo real é pequeno (ver lacuna L3):
- Exibir logomarca na contracapa: fica em **Identidade**, porque faz parte da identidade compartilhada; aqui aparece só um atalho, se houver.
- **Candidatas** (exigem decisão):
  - destacar bolsos fixados e reservados (individual);
  - densidade dos controles do bolso (individual);
  - movimento reduzido do fichário além do sistema (individual).

### 4.4 Seção Organização

Acesso às ferramentas existentes **sem duplicar o menu esquerdo**:
- **Modelo da grade** (ex.: 3×3) com a frase "A grade é definida na montagem e não muda". Só leitura.
- **Páginas:** total e um único link "Abrir visão geral das páginas", que aciona a mesma ação do menu esquerdo. Não cria um segundo botão de adicionar páginas.
- **Desmontar o fichário:** link para Ajustes da coleção, onde a ação já existe com prévia e token.
- **Fichário compartilhado:** link "Gerenciar compartilhamento" para Ajustes da coleção (associar/desassociar já existe).

### 4.5 Seção Informações

- **Capacidade:** páginas × bolsos por página = total de bolsos.
- **Ocupação:** bolsos com carta, reservados vazios, com imagem, mesclados e livres, com barra de ocupação. Sem valores financeiros.
- **Coleções vinculadas:** proprietária + convidadas, com nome e link. Exige contrato novo de leitura (lacuna L2).

## 5. Regras de negócio

### 5.1 Nome do fichário

- **R1:** O nome pertence ao **fichário** (`collection_layout`), não à coleção. Renomear uma coleção não altera o fichário, e vice-versa.
- **R2:** O nome é opcional no banco. Enquanto não for definido, exibe-se o nome da **coleção proprietária** (fallback de leitura, nunca gravado automaticamente).
- **R3:** Validação no servidor:
  - `btrim`, de 1 a 60 caracteres;
  - sem caracteres de controle nem quebras de linha;
  - espaços internos múltiplos colapsados;
  - vazio volta ao fallback (R2);
  - não precisa ser único.
- **R4:** **Só a coleção proprietária** edita nome e logomarca (alteração compartilhada: todas as coleções do fichário veem). A convidada só lê. Coleção arquivada só lê.
- **R5:** Escrita idempotente: o mesmo valor devolve `UNCHANGED`, sem `updated_at` novo. Usa a trava do fichário (`assert_collection_layout_mutable`), como as demais RPCs.

### 5.2 Logomarca

- **R6:** `show_brand_mark` booleano por fichário, padrão **verdadeiro**. Alteração compartilhada (R4).
- **R7:** Só o asset interno; nenhum caminho, URL ou upload aceito do cliente. A preferência guarda apenas o booleano.
- **R8:** Monocromia feita na apresentação: o PNG transparente é usado como **máscara** (`mask-image`) pintada com o tom da contracapa. Bochechas e olhos viram a mesma cor, e nenhum asset novo é obrigatório. A versão vetorial é opcional (L4).
- **R9:** Com a logomarca oculta, a composição recentraliza nome e assinatura sem deixar espaço vazio.

### 5.3 Individual × compartilhado

| Item | Tipo | Onde vive |
|---|---|---|
| Nome do fichário, exibir logomarca | Compartilhado (fichário) | Banco, editado só pela proprietária |
| Painel aberto/fechado, seções recolhidas | Individual (pessoa + navegador) | `localStorage`, best-effort com try/catch, sem dado sensível |
| Preferências de Aparência (se aprovadas) | Individual | Navegador na v1; banco só se precisarem acompanhar o usuário entre dispositivos (decisão P4) |

### 5.4 Contracapa

- **R10:** Ordem vertical fixa: logomarca (opcional) → nome → "MMKYU COLLECTOR".
  - O nome quebra em até 2 linhas, com reticências depois disso.
  - A assinatura fica sempre presente e não é editável.
- **R11:** O código do Set/coleção **não aparece mais** na contracapa (D4). Continua disponível em Informações e na página da coleção.

## 6. UX/UI

### 6.1 Composição da contracapa

- Bloco centrado verticalmente, com a assinatura ancorada embaixo como hoje.
- **Logomarca:**
  - largura de ~28–32% da largura da contracapa, proporção preservada (547×308);
  - tom do couro (família `hsl(38 …)` já usada na `InsideCoverFace`) com opacidade baixa, efeito de gravação discreta, sem brilho;
  - sem fundo, sem moldura, sem texto.
- **Nome:**
  - título na tipografia oficial;
  - um passo acima do atual na hierarquia, porque passa a ser o elemento principal;
  - tom claro discreto, sem dourado de ação.
  - O dourado MMKYU fica reservado a foco e seleção, não à marca na capa.
- **"MMKYU COLLECTOR":** caixa alta, `tracking` amplo, menor e mais apagado que o nome, como a assinatura atual de "Collector".
- **Claro/escuro:** a contracapa é couro escuro nos dois temas, como a navegação. O tom da máscara não muda com o tema; só a prévia no painel acompanha a superfície do painel.

### 6.2 Painel

- Superfícies do Design System:
  - grafite no escuro e superfície clara no claro;
  - separação por luminosidade, sem excesso de bordas.
- Títulos de seção pequenos e consistentes, com ícone discreto.
- **Dourado só em:** botão Salvar habilitado, switch ligado e foco.
- **Movimento:**
  - abrir/fechar com `transform` e `opacity` (~200 ms);
  - o reencaixe do fichário acontece ao final, sem animar o layout quadro a quadro;
  - `prefers-reduced-motion` desliga as transições.

### 6.3 Acessibilidade

- Botão de abertura com `aria-expanded` e `aria-controls`.
- Painel `role="complementary"` no desktop e `role="dialog"` com `aria-modal` no celular.
- Cada seção recolhível como `button` + região; campo com `label` associado.
- Contador de caracteres anunciado só no limite; switch com estado falado.
- Resultado de salvar em `aria-live="polite"`; erros em `role="alert"`.
- Foco devolvido ao botão de abertura ao fechar; Esc fecha o painel.
- Contraste do nome e da assinatura na contracapa ≥ 4.5:1 para o nome. A logomarca é decorativa (`aria-hidden`), e o nome continua lido.

### 6.4 Onde o nome aparece

1. Contracapa (interna e, quando existir, a capa fechada).
2. Título do cabeçalho do fichário (hoje `collectionName`; passa a "nome do fichário", com "de <coleção>" em linha secundária quando diferir).
3. Cartão/entrada do fichário na página da coleção.
4. Visão geral das páginas (título).
5. Rótulos acessíveis, como `aria-label` do palco ("Fichário <nome> — páginas 3 e 4").

### 6.5 Estados

- **Carregando:** esqueleto só no painel; o fichário não pisca.
- **Erro de leitura da identidade:** fallback para o nome da coleção, com logomarca exibida, aviso no painel e "Tentar de novo".
- **Funções ainda não aplicadas no banco:** painel em leitura, com "Identidade do fichário ainda não disponível". Mesmo padrão de `PGRST202` das rodadas anteriores.

## 7. Contrato de dados proposto (para aprovação; numeração a confirmar)

| Item | Proposta |
|---|---|
| Colunas | `collection_layout.display_name text null` (CHECK de 1 a 60 após trim, sem controle) e `collection_layout.show_brand_mark boolean not null default true`. |
| Escrita | `set_my_binder_identity(p_collection_id uuid, p_display_name text, p_show_brand_mark boolean)`, SECURITY DEFINER, `search_path=''`, EXECUTE só `authenticated`. Só a proprietária, coleção ativa, trava do fichário. Devolve `display_name`, `show_brand_mark` e `operation` (UPDATED/UNCHANGED). Erros: `BINDER_OWNER_ONLY`, `COLLECTION_ARCHIVED`, `INVALID_BINDER_NAME`. |
| Leitura | **Função nova e separada** `get_my_binder_identity(p_collection_id)`, que vale para proprietária e convidada e não enumera fichário alheio, em vez de mudar o tipo de retorno de `5223`/`5230`. Assim se evita `DROP`/`CREATE` de contratos em uso. Chamada em paralelo à leitura atual. |
| Coleções vinculadas | `get_my_binder_participants(p_collection_id)`: só a proprietária vê a lista completa; a convidada vê a proprietária e a si mesma. Fecha a lacuna L2. |
| Desmontagem | Sem mudança: nome e flag somem com o layout. |
| Numeração | Próximos livres após `5243` (ex.: `5244`–`5247`) + pré/pós-checagens só leitura, como nas propostas anteriores. |

## 8. Lacunas reais e decisões pendentes

| # | Lacuna / decisão | Recomendação |
|---|---|---|
| L1 | Nome do fichário não existe no banco | Contrato do §7 (colunas + 2 RPCs) |
| L2 | Não há leitura das coleções convidadas para a proprietária | `get_my_binder_participants` (§7) |
| L3 | A seção **Aparência** não tem preferências reais hoje | P1: aprovar quais entram na v1 (candidatas do §4.3) ou lançar a seção com conteúdo mínimo e ocultá-la enquanto vazia |
| L4 | O asset é colorido e raster | Máscara CSS resolve a v1; vetorizar o rosto (SVG monocromático) é melhoria opcional para nitidez em telas grandes |
| P1 | Conteúdo de Aparência na v1 | Ver L3 |
| P2 | Quem edita a identidade em fichário compartilhado | Recomendado: só a proprietária (R4) |
| P3 | Fallback do nome: coleção proprietária (R2) **ou** gravar o nome da coleção na montagem | Recomendado: fallback de leitura, sem gravar (não cria dado duplicado) |
| P4 | Preferências individuais no navegador ou na conta | Recomendado: navegador na v1 |
| P5 | Capa fechada (`binder-cover-closed`, hoje experimental) passa a usar o mesmo nome e marca? | Recomendado: sim, quando for promovida |

## 9. Fora de escopo (v1)

Upload de logomarca; texto livre na assinatura; cor/tema da capa; histórico de alterações; ordenação automática; valor financeiro do fichário; mudança de grade; novas ferramentas de organização.

## 10. Critérios de aceite

- Contracapa na ordem do D4, sem código de coleção, logomarca monocromática ocultável, legível em claro/escuro, desktop, tablet e celular.
- Nome editável só pela proprietária; convidada e arquivada em leitura; validação no servidor; idempotente.
- Painel recolhível sem sobrepor o fichário no desktop; acessível por teclado; respeita `prefers-reduced-motion`.
- Nenhuma ferramenta duplicada do menu esquerdo.
- Contratos novos com SECURITY DEFINER, `search_path=''`, sem `anon`, e testes de autorização proprietária/convidada/outro usuário.
- Nenhuma leitura extra serial no carregamento do fichário (leituras em paralelo).

## 11. Implementação local (v1.1) e plano de implantação

### 11.1 Decisões aprovadas (Fabrício, 2026-10-23)

| # | Decisão | Como foi aplicada |
|---|---|---|
| P1 | Aparência oculta até existir preferência útil | Painel com 3 seções: Identidade, Organização, Informações. Nenhum controle sem função. |
| P2 | Só a proprietária edita nome e logomarca; convidadas veem | `set_my_binder_identity` recusa convidada (`BINDER_OWNER_ONLY`); painel da convidada em leitura com o motivo. |
| P3 | Fallback = nome da coleção proprietária, sem cópia no banco | `display_name` NULL; `effective_name = coalesce(display_name, nome da proprietária)`. |
| P4 | Preferências individuais no navegador | `localStorage` `mmkyu:binder-control:v1` (painel aberto no desktop + seções recolhidas), best-effort com try/catch. |
| P5 | Nome e logomarca em todos os pontos de identificação | Contracapa (frente e traseira), título do fichário, título da aba (rota `/fichario`), rótulo do palco, entrada na página da coleção (quando há nome próprio). A capa fechada experimental segue fora (não é produção). |

### 11.2 Ajustes de contrato em relação ao §7 (decisão de implementação)

- **Leitura dividida por custo:** em vez de uma leitura única, `get_my_binder_identity` (leve, PK/UNIQUE, lida no servidor em paralelo ao cabeçalho — contracapa e título já saem certos na primeira pintura) e `get_my_binder_occupancy` (agregado de bolsos, lida **só** quando a seção Informações abre). Nenhuma leitura serial nova na abertura do fichário.
- **Ocupação sem dupla contagem:** cada bolso físico conta uma vez, na precedência carta > imagem > mesclagem > reservado vazio > livre; o frontend recusa resposta cuja soma não feche.
- `get_my_binder_participants` inclui bolsos com carta por coleção (caminho assignment → allocation, o mesmo da 5230).

### 11.3 Arquivos desta pasta

| Arquivo | Conteúdo | Estado |
|---|---|---|
| `5244_add_collection_layout_identity.sql` | `display_name` + `show_brand_mark` + CHECK de formato | PROPOSTO |
| `5245_create_binder_identity_functions.sql` | `set_my_binder_identity`, `get_my_binder_identity`, `get_my_binder_occupancy` | PROPOSTO |
| `5246_create_get_my_binder_participants.sql` | `get_my_binder_participants` | PROPOSTO |
| `5853_validate_p3a_binder_identity.sql` | Harness 30 checagens (estrutura, outro usuário, proprietária, convidada, arquivada, integridade, resíduo zero). **Nunca no LIVE.** | PROPOSTO, não executado |

Verificação estática feita: `begin;`/`commit;` e `$$` balanceados; nenhuma execução (não há Postgres no ambiente do agente).

### 11.4 Frontend (local)

- `web/lib/colecoes/binder-identity.ts` (+ teste): normalização idêntica ao servidor (caracteres, não bytes), parsers, fallback, mensagens, preferências.
- `web/components/colecoes/fichario/binder-control.tsx` + `.module.css`: Centro de Controle (acoplado ≥ 1280 px; folha modal abaixo disso).
- `web/components/ui/switch.tsx`: primitive novo do Design System (`role="switch"`), primeiro consumidor "Exibir logomarca".
- `binder-chrome.tsx`: `BrandMark` (asset `brand/icon-mark-light.png` como máscara CSS, tom da contracapa) e `InsideCoverFace`. **Correção visual (P3A-BINDER-BACK-COVER-VISUAL-CORRECTION-01):** composição, tipografia, escala e posições da P2 restauradas; o rosto do Mimikyu entra acima da marca "MMKYU / Collector" do centro (que é a assinatura neutra), no mesmo tom e relevo; o rodapé mostra o nome do fichário no tratamento do antigo nome da coleção; sai só o código ("MMKYU · SV1"). Logo oculta = contracapa da P2, salvo essas mudanças de texto.
- `binder-workspace.tsx`, `binder-view.tsx`, `binder-overlay.tsx`, `binder-entry.tsx`, as duas páginas e `actions.ts`/`binder-queries.ts`: identidade lida em paralelo e propagada; ações `saveBinderIdentity`, `readBinderOccupancy`, `readBinderParticipants`.
- **Antes da migration:** a interface funciona igual, com o nome da coleção e a logomarca; o painel mostra "ainda não disponível" e não oferece edição (PGRST202 tratado, sem log de erro).

### 11.5 Plano mínimo de implantação e homologação

1. Fabrício revisa e faz commit do frontend (pode ir antes do banco: degrada para o fallback).
2. Com autorização: aplicar no LIVE **5244 → 5245 → 5246**, uma por vez, conferindo o ledger; pós-checagem só leitura de cada "Como validar".
3. Security Advisor (esperado: nada novo; funções com `search_path=''`).
4. Harness 5853 só em ambiente descartável (branch), se houver.
5. Homologação pela interface: H1 renomear e ver contracapa/título/entrada; H2 vazio volta ao nome da coleção; H3 nome inválido (61 caracteres) recusado com mensagem; H4 ocultar/exibir logomarca; H5 Informações com cartas, imagens, mesclagens e reservas reais (soma = bolsos); H6 convidada vê a identidade sem editar; H7 coleção arquivada em leitura; H8 teclado (Tab/Esc/foco devolvido), celular (folha), claro/escuro.
6. Promoção para `database/schema/` e docs canônicos (05d, INDEX, log, HANDOFF) só depois.

### 11.6 Riscos e pendências reais

- SQL **não executado**: sintaxe e comportamento só provados por inspeção.
- `npm run lint`/`build` e verificação visual em navegador não rodam no ambiente do agente — pendentes com Fabrício.
- A página da coleção passa a fazer uma leitura leve a mais (PK), em paralelo.
- A logomarca usa o PNG raster como máscara: nítida até ~200 px de largura; um SVG monocromático seria melhoria opcional (L4).

### 11.7 Prontidão LIVE (P3A-BINDER-CONTROL-IDENTITY-LIVE-READINESS-01, 2026-10-23)

- **Precheck só leitura executado no LIVE:** `LIVE_00_precheck_readonly.sql` → p01–p10 todos PASS (ledger termina em 5243; 5244–5246 ausentes; dependências 5122/5229/5232/5234/5238/5239 presentes; helpers internos sem EXECUTE para a API; nenhuma função/visão depende de `collection_layout.*`; sem sessão ativa no fichário). Baseline anotado no próprio arquivo.
- **Dry-read das consultas novas** (SELECT puro, sem criar nada) sobre o fichário real: ocupação 216 bolsos = 155 com carta + 0 imagem + 2 em mesclagem + 10 reservados vazios + 49 livres (soma fecha; nenhuma sobreposição carta×imagem×mesclagem); 1 mesclagem com imagem; 2 participantes, 148 + 7 cartas por coleção. Colunas e junções da 5245/5246 conferem com o LIVE.
- **Aplicação:** `apply_migration`, uma por vez, 5244 → 5245 → 5246, com o corpo de cada arquivo **sem** as linhas `begin;`/`commit;` externas (precedente 5237/P2) e com `set local lock_timeout = '5s';` antes do `alter table` da 5244. Bloco A/B/C do `LIVE_90_postcheck_readonly.sql` após cada uma; D + Security Advisor no fim.
- **Reversão:** `R0_rollback_source.sql` (ordem inversa; só objetos novos). Não executar sem autorização.
- **Fora do LIVE:** harness 5853 (cria dados).

### 11.8 Execução LIVE (P3A-BINDER-CONTROL-IDENTITY-LIVE-EXECUTION-01, autorização expressa de Fabrício)

| Migration | Ledger | Postcheck |
|---|---|---|
| 5244_add_collection_layout_identity | 20261024002319 | A1–A7 PASS (linha do fichário intacta: md5 igual, `updated_at` não mudou) |
| 5245_create_binder_identity_functions | 20261024002413 | B: 3 funções definer, `search_path=''`, EXECUTE só authenticated, sem PUBLIC/anon, `set_` com lock_timeout 5s |
| 5246_create_get_my_binder_participants | 20261024002445 | B/C: 4 funções, mesmos critérios |

- Precheck LIVE_00 repetido imediatamente antes: p01–p10 PASS; baseline idêntico ao da prontidão. Arquivos aplicados = md5 da prontidão (5244 `229a043e…`, 5245 `84526206…`, 5246 `24ed4ebd…`), sem `begin;`/`commit;` externos; 5244 com `set local lock_timeout = '5s'`.
- Bloco D: layouts 1, convidadas 1, páginas 24, bolsos 216, posições 155, reservas 158, imagens 0, mesclagens 1 (1 imagem), travas 0, alocações 211 — iguais ao antes. Nenhum nome/logomarca gravado.
- Prova só leitura (transação `read only`, sem escrita): outro usuário → `COLLECTION_NOT_FOUND`; `anon` → 42501; proprietária lê identidade (OWNER, pode editar), convidada lê a mesma identidade (GUEST, sem edição); ocupação 155+0+2+10+49 = 216; participantes 148/7 (proprietária vê 2; convidada vê a proprietária e a si).
- Security Advisor: +4 avisos `authenticated_security_definer_function_executable` (as 4 RPCs, padrão aceito); nenhum aviso de `anon` ou `search_path` novo; categorias iguais às do baseline.
- Não executado: harness 5853 (proibido no LIVE), escrita de identidade (homologação pela interface), promoção para `database/schema/`.

### 11.9 Encerramento (P3A-BINDER-CONTROL-FINAL-CLOSEOUT-01, 2026-10-24)

**Promoção canônica.** `database/schema/5244_add_collection_layout_identity.sql`, `5245_create_binder_identity_functions.sql` e `5246_create_get_my_binder_participants.sql` criadas a partir desta pasta; só o bloco `Status` do cabeçalho difere (conferido: texto antes e depois do bloco idêntico byte a byte). Os arquivos desta pasta seguem intactos (md5 5244 `229a043e…`, 5245 `84526206…`, 5246 `24ed4ebd…` = os aplicados). Ledger: 5244 `20261024002319`, 5245 `20261024002413`, 5246 `20261024002445`.

**Equivalência com o LIVE (só leitura, 2026-10-24).** Corpos de `set_my_binder_identity`, `get_my_binder_identity`, `get_my_binder_occupancy` e `get_my_binder_participants` por md5 normalizado (sem comentários `--` e sem espaços) iguais ao arquivo: 4/4. Todas SECURITY DEFINER, `search_path=""` (`set_` também com `lock_timeout=5s`), EXECUTE para `authenticated` e não para `anon`. Colunas `display_name text null` e `show_brand_mark boolean not null default true`; CHECK `chk_collection_layout_display_name_format` com a mesma regra do arquivo. Nenhuma migration reexecutada.

**Decisões funcionais finais (após a execução LIVE, só frontend, sem contrato novo):**
- "Coleções neste fichário" é só informativa — sem link nem navegação (`P3A-CONTROL-PARTICIPANTS-UX-CORRECTION-01`); sair do fichário continua sendo "Voltar à coleção".
- Informações ganhou "Progresso das coleções": proprietária primeiro e em destaque, convidadas compactas por nome (pt-BR) e id; números do resumo oficial de cada coleção (R1 `get_my_collections` → completion summary), nunca somados nem tirados dos bolsos; participantes via 5246, resumos numa varredura (`P3A-BINDER-CONTROL-OWNER-PROGRESS-01` → `MULTI-COLLECTION-PROGRESS-01`).
- Contracapa: composição da P2 + rosto monocromático do Mimikyu + nome do fichário, baixo relevo — **aprovada e congelada definitivamente**.

**Homologação pela interface (Fabrício):** renomear o fichário com persistência após F5 — PASS; ocultar, salvar, recarregar e restaurar a logomarca — PASS; participantes só informativos — PASS; progresso das coleções vinculadas e indicadores de capacidade/ocupação — aprovados visualmente. `npm run lint` e `npm run build` PASS (máquina de Fabrício); typecheck e testes `lib/colecoes` PASS (289/289 na última execução).

**Não executado / não comprovado:** harness `5853` (não roda no LIVE; também não rodou em banco descartável); concorrência real de gravação de identidade entre abas (só a trava `lock_timeout` de 5 s, não exercitada); recusa de edição por coleção arquivada não exercitada; visão da convidada comprovada só pela prova de leitura no LIVE (§11.8), não pela interface; desempenho de `get_my_collections` com milhares de coleções (varredura de 100 em 100, ressalva já registrada).

