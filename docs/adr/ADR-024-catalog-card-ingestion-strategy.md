# ADR-024 — Catalog Card Ingestion Strategy

| Campo | Valor |
|--------|-------|
| **ADR** | ADR-024 |
| **Título** | Catalog Card Ingestion Strategy |
| **Status** | Aprovado |
| **Data** | 2026-07-26 |
| **Decisores** | Fabrício Sales |
| **Decisão** | O banco de dados do Project Mimikyu é a única autoridade sobre os dados editoriais do catálogo — nenhuma fonte externa (PDF oficial, TCGdex, ou qualquer integração futura) tem autoridade sobre o conteúdo; cada uma fornece apenas uma proposta sujeita a validação administrativa (Princípio da Fonte Canônica, ver seção própria). Os três canais de entrada de Cards (cadastro individual, checklist oficial em PDF, importação da TCGdex) convergem para a mesma camada interna definida em `ADR-023` e nunca gravam diretamente nas tabelas canônicas. Um contrato de processamento (`fonte → processador → linhas de staging`) formaliza a interface entre a origem do dado e `catalog_import_row`, sem fixar tecnologia para nenhum dos dois canais: qual runtime concreto implementa o processador (Edge Function, backend Next.js, serviço externo, entrada semiautomática, conversão intermediária estruturada) é uma escolha inicial de implementação, revisável sem reabrir este ADR, desde que o contrato seja respeitado — a TCGdex tem hoje uma escolha inicial de implementação (Edge Function, no mesmo perímetro de confiança do pipeline de imagens); o processador do PDF fica deliberadamente indefinido até uma prova técnica avaliar as alternativas. Staging usa `catalog_import_job`/`catalog_import_row`, com quatro estados independentes por linha (`validation_status`, `match_status`, `decision_status`, `persistence_status`) e oito estados de job (`RECEIVED`/`PROCESSING`/`STAGED`/`CONFIRMING`/`COMPLETED`/`COMPLETED_WITH_ERRORS`/`FAILED`/`CANCELLED`), recalculados deterministicamente a partir da contagem real das linhas a cada chamada — nunca incrementados manualmente, nunca um "confirmado parcial" ambíguo. Idempotência de processo usa um fingerprint parcial (fonte, Card Set, idioma, checksum do arquivo ou `external_set_id` da TCGdex), válido só enquanto o job está em estado não-terminal; após a busca da TCGdex, campos de rastreabilidade adicionais (`source_fetched_at`, checksum do payload normalizado, quantidade recebida, versão/etag da fonte) registram o conteúdo obtido, fora da chave de bloqueio. `admin_confirm_catalog_import(job_id, row_ids opcional)` isola erro de dados por linha dentro de uma única transação Postgres — sem durabilidade independente por linha; falha sistêmica desfaz a chamada inteira, inclusive a transição para `CONFIRMING`; concorrência é serializada por lock na linha do job. |
| **Documentos Relacionados** | `ADR-018-single-function-import-pipeline.md`, `ADR-022-catalog-editorial-admin-only-access.md`, `ADR-023-catalog-editorial-write-authorization.md`, `../05-modelo-de-dados.md`, `../standards/STD-001-database-standards.md` |

---

# Context

`ADR-023` resolve **como** qualquer escrita administrativa do Catálogo Editorial acontece. Este ADR resolve um problema mais específico: hoje não existe nenhuma via controlada para alimentar `card` em volume — as 927 Cards atuais entraram por SQL direta, e o pipeline de importação de imagens (`import-card-assets`, `ADR-018`) deliberadamente nunca insere `card`/`card_variant`, apenas consulta.

Fabrício definiu que o cadastro de Cards precisa suportar três formas de entrada desde o início — individual, checklist oficial em PDF, e importação estruturada da TCGdex — e que essas três formas não podem criar três mecanismos de persistência independentes: precisam convergir para o mesmo modelo canônico de validação e gravação. O checklist oficial da coleção `ME05` ("Megaevolução — Escuridão Absoluta"), anexado durante a análise que originou este ADR, foi usado como caso real para validar as decisões sobre extração de PDF — não é uma coleção cadastrada no catálogo atual, serviu só como referência concreta de formato.

---

# Decision

## Princípio da Fonte Canônica: o banco é a autoridade, fontes externas propõem

O banco de dados do Project Mimikyu é a única autoridade sobre os dados editoriais do catálogo. Nenhuma fonte externa — o checklist oficial em PDF, a API da TCGdex, ou qualquer integração futura — tem autoridade sobre o conteúdo do catálogo; cada uma fornece apenas uma **proposta** de dados, sujeita a validação administrativa antes de qualquer gravação. Consequência direta, que vale nomear explicitamente ainda que já esteja implícita em outras decisões deste ADR: PDF e TCGdex nunca gravam em tabela canônica sob nenhuma circunstância, mesmo quando o dado proposto é idêntico ao que já existe — uma linha `match_status = MATCHED` ainda passa por staging e por uma decisão (`decision_status`, ainda que resolvida automaticamente para `SKIPPED`), nunca por um atalho de gravação direta. A validação administrativa não é uma formalidade sobre dados já confiáveis; é o único mecanismo pelo qual uma proposta externa se torna fato no catálogo. Fontes futuras (qualquer integração além da TCGdex) herdam esta mesma regra automaticamente, sem exigir uma decisão nova — basta implementar o contrato de processamento definido a seguir.

Nota de nomenclatura: este princípio reutiliza deliberadamente o nome já registrado em `STD-001` (Seção 10) para outro conceito — ali, "Princípio da Fonte Canônica" significa que a Query de criação de uma entidade é a fonte de verdade sobre a forma correta de criar aquela estrutura, e migrations históricas lhe são subordinadas. A ideia comum aos dois usos é a mesma (existe sempre uma única fonte com autoridade final; tudo o que vem de fora dela é, na melhor das hipóteses, um candidato a ser incorporado, nunca um fato consumado), mas os objetos regidos são diferentes — lá, scripts SQL; aqui, dados editoriais. Fica sinalizado para uma eventual reconciliação de nomenclatura entre este ADR e `STD-001`, não resolvida unilateralmente neste documento.

## Contrato de processamento de fonte: `fonte → processador → linhas de staging`

Qualquer canal de entrada em lote é modelado como uma interface de três partes, independente de tecnologia: uma **fonte** (TCGdex API, arquivo PDF enviado), um **processador** (o componente que sabe interpretar aquela fonte específica) e uma saída obrigatória — linhas de `catalog_import_row`, já no formato que o restante do sistema entende (`raw_data`, `normalized_data`, `detected_variant_hint`, `validation_status` inicial). O processador nunca escreve em tabela canônica, nunca decide `match_status` (é recalculado contra o catálogo real, ver seção própria), e nunca decide `decision_status` (é sempre humano).

Para os dois canais, a tecnologia concreta do processador é uma escolha inicial de implementação — não uma decisão arquitetural deste ADR. Pode ser substituída por outra tecnologia equivalente, a qualquer momento, sem necessidade de um novo ADR, desde que o contrato acima seja respeitado (produzir `catalog_import_row` corretamente formada e nunca gravar em tabela canônica). O que este ADR fixa é o contrato; a tecnologia concreta de cada processador fica registrada como nota de implementação em `05-modelo-de-dados.md`, não neste documento.

**TCGdex** — fonte estruturada, sem o risco de extração do PDF. A escolha inicial de implementação é uma Edge Function, reaproveitando a integração já existente com a TCGdex no pipeline de imagens, escrevendo em tabelas de staging sob uma identidade de serviço (nunca a sessão do administrador) — mesmo perímetro de confiança já usado por aquele pipeline para escrever em tabelas não-canônicas. Essa escolha pode mudar sem impacto arquitetural, desde que o contrato seja preservado.

**PDF** — o contrato está decidido; a tecnologia do processador **não está**. O checklist oficial depende de símbolos gráficos de raridade, cor das caixas de seleção, posição visual e layout em múltiplas colunas — muito além de extração de texto simples, e com risco técnico real de precisão que uma fonte estruturada como a TCGdex não tem. Este ADR não escolhe entre Edge Function, backend Next.js, serviço externo, entrada semiautomática (administrador transcreve, sistema só grava como `catalog_import_row`) ou conversão intermediária para formato estruturado — essa escolha fica para uma prova técnica dedicada, avaliada por precisão de extração, custo por execução e limites de execução da plataforma candidata, **antes** do incremento que implementa o canal PDF. Entrada semiautomática é uma implementação legítima e já aderente ao contrato — não é um workaround temporário, e pode ser o processador real do primeiro incremento do canal PDF se a prova técnica apontar isso como a opção de menor risco.

## Staging: `catalog_import_job` e `catalog_import_row`

`catalog_import_job` — fonte, Card Set de destino, idioma, status, contagens (lidas/válidas/rejeitadas/inseridas/atualizadas/ignoradas/falhas), identificador e versão do processador que a executou, `initiated_by`, campos de idempotência e rastreabilidade (ver seções próprias), timestamps.

`catalog_import_row` — `raw_data` (jsonb, dado bruto da fonte), `normalized_data` (jsonb, melhor tentativa de campos resolvidos), `detected_variant_hint` (coluna própria, não apenas dentro de `raw_data`/`normalized_data` — ver seção própria), os quatro estados independentes abaixo, `matched_card_id`/`resulting_card_id` (nullable).

Nomes definitivos das colunas e tipos exatos ficam para `05-modelo-de-dados.md` na implementação.

## Quatro estados independentes por linha

`validation_status` (`PENDING`|`VALID`|`NEEDS_REVIEW`|`INVALID`) — escrito só pelo processador, na extração/normalização; nunca por decisão humana.

`match_status` (`NEW`|`MATCHED`|`CONFLICT`) — escrito pela comparação contra o `card` real (ativas **e** inativas, por `ADR-023`), recalculado no momento da confirmação, não confiado do valor gravado no staging — protege contra corrida entre dois jobs concorrentes sobre o mesmo Card Set.

`decision_status` (`PENDING`|`APPROVED`|`REJECTED`|`SKIPPED`) — só o administrador altera. Linhas `MATCHED` com dados idênticos nascem com `SKIPPED` automático (evita exigir clique em centenas de linhas sem nada para decidir); o administrador pode sobrescrever. Linhas `CONFLICT` nascem `PENDING` e ficam bloqueadas até decisão explícita.

`persistence_status` (`PENDING`|`INSERTED`|`UPDATED`|`UNCHANGED`|`FAILED`) — só a função de confirmação altera; é o resultado real da tentativa de gravação, nunca uma inferência.

Essas quatro dimensões nunca são combinadas num único campo — misturar validação, correspondência, decisão e persistência foi a falha identificada numa versão anterior desta proposta.

## Oito estados de job, sem "confirmado parcial"

`RECEIVED` (recebimento) → `PROCESSING` (processamento) → `STAGED` (revisão — linhas geradas, aguardando decisão humana) → `CONFIRMING` (confirmação em execução) → `COMPLETED` ou `COMPLETED_WITH_ERRORS` (conclusão) → `FAILED` (falha técnica — a extração/busca em si não produziu linhas utilizáveis) → `CANCELLED` (cancelamento, só por ação administrativa explícita antes da conclusão).

Não existe um estado "confirmado parcialmente" — um job com algumas linhas decididas e outras não permanece em `STAGED`/`CONFIRMING`, nunca num estado ambíguo.

## Estado do job recalculado deterministicamente, nunca incrementado

Como `admin_confirm_catalog_import()` aceita `row_ids` e pode ser chamada em sublotes, uma chamada bem-sucedida não significa que o job terminou. Ao final de cada chamada, o status do job é recalculado do zero, por agregação real sobre `catalog_import_row`, nunca por incremento de uma variável de controle:

- Se ainda existir alguma linha com `decision_status = PENDING` ou `persistence_status = PENDING`, o job permanece (ou retorna a) `STAGED`.
- `COMPLETED` só quando **todas** as linhas estiverem em estado terminal de decisão e persistência **e nenhuma** tiver `persistence_status = FAILED`.
- `COMPLETED_WITH_ERRORS` só quando todas estiverem em estado terminal **e ao menos uma** tiver `FAILED`.
- Uma falha sistêmica não capturada desfaz a chamada inteira, inclusive a transição para `CONFIRMING` feita no início da mesma chamada — ver semântica transacional, abaixo.
- `CANCELLED` só por ação administrativa explícita, e só antes de o job alcançar um estado de conclusão.

## Idempotência de processo: fingerprint parcial

A `UNIQUE(card_set_id, collector_number)` já existente em `card` protege contra Card duplicada, não contra **processo** duplicado (job duplicado, mesmo PDF processado duas vezes, mesma busca da TCGdex repetida, confirmação repetida de um job já concluído). A proteção de processo é um fingerprint — `(source, card_set_id, language_id, file_checksum | external_set_id)` — com `UNIQUE` **parcial**, válida apenas enquanto o job correspondente está em estado não-terminal (`RECEIVED`/`PROCESSING`/`STAGED`/`CONFIRMING`). Isso bloqueia um segundo upload do mesmo arquivo ou uma segunda busca do mesmo set **enquanto o primeiro job ainda está aberto**, e libera a chave assim que o job atinge um estado terminal — reimportar de propósito (PDF corrigido, ou buscar a TCGdex de novo para pegar Cards novas) é um caso legítimo, não um erro.

`processor_code`/`processor_version` ficam fora do fingerprint — servem só para rastreabilidade (qual implementação concreta gerou aquela linha), não para bloqueio; um job reprocessado com um processador corrigido não é impedido pela versão anterior.

## Rastreabilidade adicional após a obtenção (TCGdex)

O fingerprint inicial (`external_set_id` + Card Set + idioma) é suficiente para bloquear jobs concorrentes **antes** da busca, mas não identifica o conteúdo realmente retornado pela API — dois jobs legítimos e não concorrentes podem obter respostas diferentes da TCGdex ao longo do tempo (novas Cards publicadas, correções da própria fonte). Por isso, `catalog_import_job` registra, imediatamente após a busca:

- `source_fetched_at` — quando a resposta foi obtida.
- Checksum do payload normalizado (ou equivalente) — permite comparar duas execuções sem reprocessar tudo.
- Quantidade de registros recebidos.
- Versão ou `ETag` da fonte, quando disponível.

Esses campos são de rastreabilidade e comparação entre reimportações — não entram na chave parcial usada para bloquear jobs concorrentes, porque só existem depois que a busca já ocorreu.

## Confirmação em lote: semântica transacional real

`admin_confirm_catalog_import(job_id, row_ids opcional)` — `row_ids` omitido ou vazio processa todas as linhas elegíveis (`decision_status = APPROVED` ou default `SKIPPED` já resolvido, nunca `PENDING`). Internamente, cada linha é processada num bloco `BEGIN ... EXCEPTION WHEN OTHERS ... END` que isola **erro de dados de uma linha específica** das demais — uma linha malformada não impede as outras 299 de uma mesma chamada de serem persistidas.

Precisão obrigatória sobre o que esse isolamento **não** garante: toda a chamada pertence a uma única transação Postgres. O bloco de exceção por linha não produz commits independentes — se ocorrer um erro sistêmico não capturado pelo bloco (não um erro de dados de uma linha, mas algo que aborta a função como um todo — ex. falha de conexão, timeout, bug fora do laço), **toda a chamada desfaz**, inclusive linhas já processadas com sucesso naquela mesma chamada, e inclusive a transição de status do job para `CONFIRMING` feita no início da própria função. Nada fica "parcialmente salvo" por uma chamada que não termina de executar até o fim.

A recuperação é reexecução segura, não retomada parcial: como linhas em estado terminal (`persistence_status` diferente de `PENDING`) são ignoradas em qualquer chamada seguinte, chamar a função de novo depois de uma falha sistêmica é seguro — ela recomeça, mas linhas que já teriam sido persistidas **numa chamada anterior bem-sucedida** não são reprocessadas; linhas que faziam parte de uma chamada que falhou por completo são tentadas novamente, porque nunca chegaram a ser persistidas de fato. Recomendação operacional, não uma restrição do contrato: para lotes de centenas de Cards, o chamador (frontend) deveria dividir a confirmação em sublotes (ex. 50 linhas por chamada) para obter pontos de commit reais intermediários, em vez de arriscar uma única chamada monolítica cobrindo o job inteiro.

As contagens do job são recalculadas por agregação ao final de cada chamada bem-sucedida (ver seção de estados do job), nunca incrementadas — evita desvio sob reexecução parcial.

## Concorrência: lock na linha do job, sem estado "preso" possível

`admin_confirm_catalog_import()` abre com `SELECT ... FOR UPDATE` na linha de `catalog_import_job`, antes de qualquer outra ação. Uma segunda chamada concorrente sobre o mesmo `job_id` espera a primeira terminar (commit ou rollback) e só então lê o estado real — se a primeira já tiver concluído o trabalho, a segunda não encontra nada elegível e retorna sem efeito; se a primeira tiver falhado por completo (rollback), a segunda encontra o job intacto em `STAGED` e prossegue normalmente.

Como a transição para `CONFIRMING` e todo o processamento pertencem à mesma transação (seção anterior), uma falha sistêmica desfaz os dois juntos — um job **não pode** ficar preso em `CONFIRMING` por uma interrupção de execução; ele sempre volta a `STAGED` junto com o rollback. A única forma real de um job permanecer em `CONFIRMING` de forma duradoura seria um bug de lógica que comita sem definir o status terminal em algum caminho de saída da função — mitigado por construção, recalculando o status final sempre a partir da contagem real das linhas (seção "Estado do job recalculado deterministicamente"), nunca de uma variável de controle interna que poderia ficar desatualizada. Não há, portanto, um mecanismo de "recuperação de job travado" a construir — o cenário que o exigiria não é alcançável sob a semântica transacional padrão do Postgres, dado este desenho.

## Política de conflitos e atualização

Comparação de "dados idênticos" usa apenas `name`, `rarity_id`, `category_id`, `collector_total` — nunca `collector_number`/`collector_order`/`card_set_id`, que são identidade, não conteúdo. `match_status = NEW` + `decision_status = APPROVED` → cria via camada interna de `ADR-023` → `persistence_status = INSERTED`. `match_status = MATCHED` (todos os campos comparados idênticos) → `decision_status` padrão `SKIPPED` → `persistence_status = UNCHANGED`, sem nenhum `UPDATE` físico. `match_status = CONFLICT` nunca atualiza automaticamente — permanece `PENDING` até decisão humana explícita; `APPROVED` aceita o dado da fonte e atualiza (nunca `card_set_id`/`collector_number`, por `ADR-023`); `REJECTED`/`SKIPPED` mantém o dado existente, sem gravação.

## `detected_variant_hint` preservado, sem criar `card_variant`

`catalog_import_row` recebe uma coluna própria, estruturada (jsonb, não texto livre) — `detected_variant_hint` — capturando o que a fonte sinalizou sobre acabamento/impressão (ex. cor da caixa de seleção no PDF, indicando "carta laminada padrão"), sem criar nenhuma linha em `card_variant` agora. É preenchida na normalização, nunca lida pela função de confirmação. Existe para que um incremento futuro de `card_variant` possa reconstruir a intenção original sem reprocessar a fonte — nenhuma informação é descartada, mesmo não sendo usada ainda.

## Retenção do arquivo enviado (canal PDF)

O arquivo em si não é a fonte de verdade — as linhas de staging já extraídas são. O objeto permanece no Storage privado até o job atingir um estado terminal, mais uma janela de 30 dias (valor inicial, ajustável), depois descartável por um mecanismo de limpeza a implementar em incremento próprio. O registro de `catalog_import_job` (incluindo o checksum do arquivo) permanece indefinidamente como trilha de auditoria, mesmo depois do arquivo ser removido.

## Auditoria: uma ação agregada por confirmação

`admin_confirm_catalog_import()` grava exatamente uma linha na auditoria editorial de `ADR-023` por chamada bem-sucedida — referenciando o `job_id` e as contagens resultantes —, nunca uma linha por Card confirmada. O detalhe linha a linha (dado bruto, dado normalizado, decisão, resultado de persistência) já vive em `catalog_import_row`; duplicá-lo na auditoria seria redundante.

## Emenda (2026-08-01) — Continuação automática: cartas → imagens

Pedido explícito de Fabrício: "Após a confirmação das cartas, o fluxo de importação deve continuar automaticamente com a importação das imagens do Card Set." Resolve, para o canal TCGdex, a pendência sinalizada acima em "Restrições / Pendências" ("A interação entre `is_active` e o pipeline de imagens existente não é resolvida aqui") — apenas para o caso de continuação automática; a interação de `is_active` com o pipeline de imagens em si continua fora do escopo deste ADR.

Depois que `admin_confirm_catalog_import()` (Query 2082) persiste as Cards de um Card Set, o frontend passa a continuar automaticamente para o pipeline de imagens já existente (`import-card-assets`, `ADR-018`) — sem substituir, remover ou duplicar esse pipeline, e sem alterar seu processamento interno. A continuação é só uma nova forma de abrir uma execução (`asset_import_run`) que antes só existia via SQL manual por Coleção.

Regras:

- "Suporte à importação automática" é a existência de `card_set_external_reference` ativo para (Card Set, TCGDEX) — o mesmo dado que `import-card-assets` já exige internamente e que o próprio processador TCGdex de Cards (`import-catalog-cards`, este ADR) já grava como parte do seu processamento. Nenhuma nova regra de detecção foi criada.
- Quando ausente (Card Sets de Promo, Energia ou qualquer Set fora da cobertura da TCGdex), a ausência de suporte não é um erro — a importação das Cards é finalizada normalmente, e o usuário é informado de que as imagens desse Card Set continuam dependendo do pipeline manual existente.
- Falhas parciais na importação de imagens (algumas imagens não obtidas) não impedem a conclusão do cadastro das Cards — o resumo final distingue cartas cadastradas, imagens importadas e imagens pendentes; as pendentes continuam resolvíveis pelo pipeline manual.
- A abertura da execução (`INSERT` em `asset_import_run`) passa a ser feita por uma função administrada (`admin_start_asset_import_run()`, Query 2092) em vez de SQL avulso por Coleção — mesmo padrão de acesso do restante deste módulo (`ADR-023`): a aplicação nunca grava direto nas tabelas do pipeline de imagens.
- O pipeline de imagens em si (`import-card-assets`) não é alterado por esta emenda — inclusive sua limitação conhecida de idioma fixo (`en`), herdada sem modificação pela continuação automática.

Ver `05-modelo-de-dados.md` (Query 2092) e `database/schema/2092_create_admin_start_asset_import_run_function.sql` para a implementação.

## Emenda (2026-08-05) — Fallback de idioma na busca de cartas: pt → en

Contexto real, descoberto por Fabrício ao importar coleções mais antigas: algumas Expansions nunca tiveram cartas publicadas em português na TCGdex — o processador TCGdex de Cards (`import-catalog-cards`, este ADR) tinha o idioma da busca fixo em `"pt"` (ver `index.ts`, comentário de `TCGDEX_PRIMARY_LANGUAGE`/histórico de correção de 2026-08-01), então essas coleções sempre falhavam por completo neste canal — `TCGDEX_HTTP_404` ao buscar o Set em `pt`, ou (caso mais sutil) um Set que responde com sucesso mas devolve a lista de cartas vazia mesmo reportando uma contagem (`cardCount`) maior que zero.

Implementado diretamente por Fabrício (commit "Implementação de FALLBACK_LANGUAGE", `supabase/functions/import-catalog-cards/index.ts`/`services/normalize.ts`, 2026-08-05): `pt` (`TCGDEX_PRIMARY_LANGUAGE`) continua sendo tentado primeiro, sempre — se a busca do Set falhar com `TCGDEX_HTTP_404`, ou responder com `cards.length === 0` apesar de `cardCount` reportar cartas, o processador tenta a MESMA busca em inglês (`TCGDEX_FALLBACK_LANGUAGE = "en"`) e segue o restante do job (resolução de raridade/categoria, busca de detalhe de cada carta, `card_set_external_reference.source_url`) inteiramente naquele idioma. Efeito colateral direto: em inglês a TCGdex devolve nomes de raridade em inglês ("Common"/"Rare"/"Uncommon"), que não batiam contra o cadastro em português de `rarity.name` — `RARITY_NAME_ALIASES` (`services/normalize.ts`) ganhou três aliases defensivos (`COMMON`→`COMUM`, `RARE`→`RARA`, `UNCOMMON`→`INCOMUM`) na mesma família dos aliases de gênero/ordem de palavras já existentes (Query `830` v1.4).

Nenhuma mudança de schema — o idioma efetivamente usado não é persistido por linha; só molda o conteúdo das cartas staged naquele job. `catalog_import_row`/staging continuam agnósticos de qual idioma da fonte produziu o dado.

## Emenda (2026-08-06) — Encadeamento PT-BR → EN na continuação automática de imagens

A "Emenda (2026-08-01) — Continuação automática: cartas → imagens" (acima) registrou que o pipeline de imagens herdava, sem modificação, "sua limitação conhecida de idioma fixo (`en`)" — essa observação já estava desatualizada desde 2026-08-02 (Edge Function `import-card-assets` v2.9.0 passou a aceitar idioma por parâmetro, ver `06-pipeline-importacao.md`, revisão `1.6`; a continuação automática passou a chamá-la fixando `pt-BR`, não mais `en` — ver `05-modelo-de-dados.md`, revisão `1.40`) e fica formalmente superada por esta emenda.

Mesmo problema de origem da emenda anterior (coleções nunca publicadas em português na TCGdex): mesmo depois de `pt-BR` virar o idioma padrão da continuação automática (2026-08-02), essas coleções continuavam falhando por completo nesta etapa — nenhuma imagem em `pt-BR` existe pra importar —, e o administrador precisava perceber a falha e repetir a operação manualmente na tela dedicada `/catalogo/importar-imagens?idioma=en`. Pedido explícito de Fabrício (2026-08-06): encadear a tentativa em inglês automaticamente, sem esperar intervenção manual.

`useAnalyzeJob` (`web/components/catalogo/importar-tcgdex-view.tsx`) passou a tentar `pt-BR` (`AUTO_CONTINUATION_LANGUAGE_CODE`) e, em seguida, incondicionalmente, `en` (`AUTO_CONTINUATION_FALLBACK_LANGUAGE_CODE`) — mesmas Server Actions e mesma lógica de retry/aborto antecipado/reabertura de run já existentes por idioma (`abrirImportacaoImagens`/`executarImportacaoImagens`), agora parametrizadas e chamadas duas vezes em sequência. A tentativa em inglês só é pulada quando `pt-BR` já devolveu `supported = false` (Card Set sem `card_set_external_reference`/TCGDEX — Promo/Energia/fora de cobertura, condição independente de idioma; tentar `en` não mudaria o resultado). O resumo final da UI (`ImportProgress`) passou a mostrar um par "importadas/pendentes" por idioma tentado, nunca somado — uma carta pendente em `pt-BR` pode já ter sido importada em `en` (ou o inverso), não é o mesmo conjunto de cartas nos dois idiomas.

Nenhuma mudança na Edge Function `import-card-assets` nem em `admin_start_asset_import_run()` (Query 2092) — orquestração inteiramente no frontend, reaproveitando o que já existia por idioma. A tela dedicada `/catalogo/importar-imagens` (idioma único, escolhido manualmente via `LanguageToggle`) não foi alterada por esta emenda.

---

# Consequences

## Benefícios

- Os três canais de entrada convergem para o mesmo modelo de validação e gravação, sem três mecanismos de persistência paralelos — exatamente o requisito que originou este ADR.
- O contrato `fonte → processador → linhas de staging` permite validar o mecanismo inteiro (staging, revisão, idempotência, confirmação em lote, concorrência) com a TCGdex — fonte estruturada, sem risco técnico de extração — antes de comprometer qualquer tecnologia para o PDF.
- A separação em quatro estados independentes por linha elimina ambiguidade sobre o que uma linha "significa" a cada momento — validação, correspondência, decisão e persistência nunca se misturam.
- A semântica transacional documentada com precisão evita uma falsa expectativa de durabilidade parcial que não existe — a resiliência real do sistema (reexecução idempotente) é conhecida e testável, não uma suposição otimista.
- `detected_variant_hint` preserva sinal valioso do PDF sem comprometer prematuramente o modelo de `card_variant`.
- O Princípio da Fonte Canônica dá uma resposta única e não-ambígua a qualquer pergunta futura sobre "essa fonte pode gravar direto?" — não, nunca, independente de qual fonte for.
- Separar arquitetura (o contrato) de implementação (a tecnologia concreta de cada processador) permite trocar a tecnologia da TCGdex — ou adicionar uma fonte totalmente nova — sem reabrir este ADR, desde que o contrato seja respeitado.

## Restrições / Pendências

- A tecnologia do processador de PDF permanece deliberadamente indefinida — o incremento do canal PDF não pode começar antes da prova técnica mencionada neste ADR.
- A escolha inicial de implementação para o processador da TCGdex (Edge Function) não é uma decisão arquitetural travada — pode ser revisada na implementação sem necessidade de nova aprovação deste ADR, desde que o contrato de processamento seja preservado.
- Nomes definitivos de tabelas/colunas e assinaturas completas de função ficam para `05-modelo-de-dados.md`, na implementação.
- A janela de retenção de 30 dias para arquivos enviados é um valor inicial, não uma política formalmente aprovada de retenção de dados — sujeita a revisão.
- Rotas e telas do módulo (listagem de jobs, tela de revisão, filtros) permanecem conceituais — nenhum componente de frontend é criado por este ADR.
- A interação entre `is_active` (`ADR-023`) e o pipeline de imagens existente (`import-card-assets`) não é resolvida aqui — sinalizada em `ADR-023`, não neste documento.

---

# Alternatives Considered

## Decidir agora a tecnologia do processador de PDF

Considerada nas primeiras versões desta proposta, rejeitada explicitamente por Fabrício. O checklist oficial depende de símbolos gráficos, cores e layout — risco técnico real que uma fonte estruturada como a TCGdex não tem. Comprometer uma tecnologia sem prova de viabilidade, precisão e custo inverteria a ordem correta de decisão.

## Uma chamada RPC independente por linha na confirmação em lote

Rejeitada explicitamente por Fabrício — inviável para importações de centenas de Cards. `admin_confirm_catalog_import(job_id, row_ids opcional)` processa múltiplas linhas por chamada, com isolamento de erro por linha dentro da mesma transação.

## Confiar no `match_status` calculado no momento do staging

Rejeitada. Entre o staging e a confirmação, outro job pode alterar o catálogo do mesmo Card Set — confiar no valor antigo permitiria uma corrida silenciosa. `match_status` é sempre recalculado no momento da confirmação.

## Contagens do job incrementadas manualmente a cada linha processada

Rejeitada. Sob reexecução parcial (ver semântica transacional), incrementos manuais divergiriam do estado real das linhas. Contagens são sempre recalculadas por agregação.

## Um único campo de estado por linha (`validation_status` sobrecarregado)

Rejeitada explicitamente por Fabrício. Misturava validação automática, correspondência contra o catálogo, decisão humana e resultado de persistência num só valor — impossível de interpretar sem ambiguidade. Substituído pelos quatro estados independentes.

## Criar `card_variant` diretamente a partir do sinal de acabamento do PDF

Rejeitada nesta fase, por acordo explícito de Fabrício. O sinal é preservado via `detected_variant_hint` para um incremento futuro dedicado a `card_variant`, sem comprometer esse modelo agora.

## Function interna de persistência acoplada diretamente às RPCs públicas `admin_create_card()`/`admin_update_card()`

Rejeitada explicitamente por Fabrício. A lógica de persistência vive numa camada interna própria (`ADR-023`), reutilizada pelas três vias (individual, atualização, confirmação em lote) — as RPCs públicas continuam sendo contratos distintos entre si, não a mesma função reexposta sob nomes diferentes.

## Gravação automática quando o dado da fonte é idêntico ao já existente (`match_status = MATCHED`)

Considerada como simplificação (evitar staging para o caso trivial "nada mudou"), rejeitada pelo Princípio da Fonte Canônica. Mesmo um dado idêntico é, formalmente, uma proposta — passa por staging e por uma decisão (ainda que resolvida automaticamente para `SKIPPED`), nunca por um atalho de gravação direta a partir da fonte externa.

## Fixar a tecnologia do processador da TCGdex como decisão arquitetural permanente deste ADR

Considerada na primeira versão deste documento, revisada por Fabrício. Nomear uma tecnologia concreta (Edge Function) como decisão do ADR misturaria arquitetura (o contrato `fonte → processador → linhas de staging`) com implementação (qual runtime o executa) — a mesma distinção já aplicada ao processador de PDF. A escolha de implementação para a TCGdex permanece registrada como nota inicial, revisável sem novo ADR.

---

# Related Documents

- `ADR-018-single-function-import-pipeline.md`
- `ADR-022-catalog-editorial-admin-only-access.md`
- `ADR-023-catalog-editorial-write-authorization.md`
- `../05-modelo-de-dados.md`
- `../standards/STD-001-database-standards.md`

---

# Revision History

| Versão | Descrição |
|---------|-----------|
| 1.0 | Criação — formaliza os três canais de entrada de Cards (individual, PDF, TCGdex) convergindo para a camada interna de `ADR-023`, via um contrato de processamento (`fonte → processador → linhas de staging`) que separa arquitetura (o contrato) de implementação (a tecnologia concreta de cada processador) — a TCGdex tem uma escolha inicial de implementação (Edge Function), o PDF não tem nenhuma, pendente de prova técnica; nenhuma das duas é uma decisão arquitetural travada deste ADR. Registra explicitamente o Princípio da Fonte Canônica: o banco do Project Mimikyu é a única autoridade sobre dados editoriais, e qualquer fonte externa (PDF, TCGdex, integrações futuras) fornece apenas propostas sujeitas a validação administrativa — nunca grava em tabela canônica, mesmo quando o dado é idêntico ao existente. Define staging (`catalog_import_job`/`catalog_import_row`) com quatro estados independentes por linha e oito estados de job, sem "confirmado parcial". Formaliza idempotência de processo por fingerprint parcial (não confundir com a UNIQUE de conteúdo já existente em `card`), acrescida de campos de rastreabilidade pós-busca para a TCGdex. Corrige a semântica transacional da confirmação em lote: isolamento de erro por linha não é durabilidade independente por linha; documenta o comportamento real sob falha sistêmica, a impossibilidade estrutural de um job preso em `CONFIRMING`, e o recálculo determinístico (nunca incremental) do status do job e das contagens. Preserva sinal de variante do PDF via `detected_variant_hint`, sem criar `card_variant` nesta fase. Motivado pela decisão de Fabrício de suportar três formas de cadastro de Cards desde o início do módulo, convergindo para um único modelo canônico de validação e gravação. |
| 1.1 | **Duas novas emendas (2026-08-06), documentando modificações reais já em produção.** (1) "Fallback de idioma na busca de cartas: pt → en" (2026-08-05) — coleções nunca publicadas em português na TCGdex sempre falhavam neste canal (`TCGDEX_HTTP_404` ou lista de cartas vazia); implementado diretamente por Fabrício (commit "Implementação de FALLBACK_LANGUAGE"), `import-catalog-cards` agora tenta `pt` primeiro e cai para `en` automaticamente nesses dois casos, com três aliases defensivos novos em `RARITY_NAME_ALIASES` para as raridades em inglês. (2) "Encadeamento PT-BR → EN na continuação automática de imagens" (2026-08-06, pedido de Fabrício) — a continuação automática cartas→imagens (emenda 2026-08-01) agora tenta `en` automaticamente depois de `pt-BR`, mesma causa raiz da emenda anterior; supera a observação de idioma fixo (`en`) registrada na emenda de 2026-08-01, já desatualizada desde a v2.9.0 da Edge Function (2026-08-02). Nenhuma mudança de schema em nenhuma das duas. |
