# Pipeline de Importação

| Campo | Valor |
|--------|-------|
| **Documento** | Pipeline de Importação |
| **Arquivo** | `docs/06-pipeline-importacao.md` |
| **Versão** | 0.7 |
| **Status** | Em elaboração |
| **Objetivo** | Definir a estratégia de importação e sincronização de dados de fontes externas para o Catálogo Editorial do Project Mimikyu. |
| **Escopo** | Estratégia de importação e sincronização, incluindo — desde a revisão `0.6` — a arquitetura de execução da Edge Function `import-card-assets` (Bloco B do roteiro de `05-modelo-de-dados.md`) e o roteiro de implementação incremental por sprints. Não é um manual operacional de deploy nem substitui o Supabase Dashboard/CLI reais. |
| **Dependências** | `02-architecture-principles.md`, `04-domain-model.md` |
| **Documentos Relacionados** | `adr/ADR-006-separation-of-catalog-ownership-and-analytics.md`, `adr/ADR-008-external-catalog-data-sources.md` |

---

# Purpose

Este documento descreve a estratégia geral de importação e sincronização de dados de fontes externas para o Catálogo Editorial do Project Mimikyu.

A decisão arquitetural que fundamenta este documento está registrada em `adr/ADR-008-external-catalog-data-sources.md`.

Este documento está em elaboração: o padrão estratégico já está definido, mas os mecanismos concretos de importação (frequência, formato intermediário, tratamento de falhas, etc.) ainda serão detalhados em ciclos futuros de documentação.

---

# Padrão Geral

Nenhuma fonte de dados externa é a proprietária lógica do catálogo. Toda fonte externa passa por uma camada de importação/sincronização antes de alimentar o catálogo interno:

```text
External Data Source
        ↓
Import / Synchronization
        ↓
Project Mimikyu Catalog
```

O catálogo interno do Project Mimikyu mantém registros próprios e independentes de:

- Game;
- Expansion;
- Set;
- Card;
- Card Translation;
- Card Variant.

---

# Por que o catálogo não depende de uma API externa em tempo real

Não foi identificada uma API oficial documentada mantida pela The Pokémon Company para integração de sistemas externos. Ferramentas amplamente utilizadas por desenvolvedores — como a Pokémon TCG API (atualmente integrada à plataforma Scrydex) e a TCGdex — são projetos independentes, não oficiais, cada um com sua própria base de dados.

Diante disso, o Project Mimikyu não deve assumir uma única fonte externa como definitiva, nem depender de qualquer uma delas como dependência estrutural em tempo real. A camada de Import/Synchronization existe justamente para isolar o catálogo dessas variações.

---

# Importação de Ativos Visuais (Imagens e Logos)

Além de dados editoriais estruturados, o mesmo padrão Import/Synchronization se aplica a ativos visuais (imagens de Card; logotipo completo e símbolo do Set — ver `04-domain-model.md`, seção Set — "Identidade Visual"): a fonte externa nunca é referenciada diretamente pela aplicação — o arquivo é importado via API e armazenado no Supabase (Storage), e o catálogo interno referencia o ativo já armazenado.

```text
External Data Source (imagem)
        ↓
Import / Synchronization
        ↓
Supabase Storage
        ↓
Project Mimikyu Catalog (referência ao ativo armazenado)
```

O banco físico já possui infraestrutura pré-existente para esse padrão (anterior a esta fase de consolidação documental, ver "Status Atual do Projeto" em `README.md`): `card_asset`, `card_asset_type`, `asset_source`, `asset_import_run`, `asset_import_failure`, `storage_bucket`. Essas tabelas ainda não foram documentadas em nível conceitual — previsto para um ciclo futuro.

**Correção (2026-07-22):** uma versão anterior deste documento atribuía `logo_url` à Expansion. Corrigido: a identidade visual pertence ao **Set** (`logo_url` e `symbol_url`, ver `04-domain-model.md` e `05-modelo-de-dados.md`, seção Set), não à Expansion. O princípio permanece o mesmo — importação automática via API, sem preenchimento manual — apenas a entidade destinatária foi corrigida.

---

# Benefícios do Modelo de Importação

- permite corrigir dados inconsistentes vindos de fontes externas;
- permite complementar informações ausentes;
- preserva os registros do catálogo caso uma fonte externa seja descontinuada;
- permite integrar mais de uma fonte de dados simultaneamente;
- mantém controle sobre os códigos internos do catálogo;
- permite registrar a procedência (fonte) de cada informação importada.

---

# Em Aberto

Os seguintes pontos ainda não foram definidos e serão tratados em ciclos futuros de documentação:

- quais fontes externas específicas serão efetivamente integradas — **parcialmente respondido para Card Variant** (ver abaixo); **respondido para imagens de Card** (TCGdex como fonte principal, Pokémon TCG API como alternativa — ver seção "Arquitetura de Execução", abaixo); segue em aberto para as demais entidades do catálogo;
- formato e frequência de importação/sincronização — **parcialmente respondido**: execução em lotes pequenos (recomendação inicial de 20 cartas por chamada), sob demanda via Edge Function; agendamento automático (`execution_context = SCHEDULED`) já previsto no modelo de dados (`220`/`221`), mas ainda não implementado;
- estratégia de tratamento de falhas e reprocessamento — **respondido a nível de arquitetura** (`failure_stage`/`error_code`, `RETRY_FAILURES` — ver seção "Arquitetura de Execução", abaixo); implementação real ainda pendente;
- estratégia de resolução de conflitos entre múltiplas fontes;
- documentação conceitual formal do padrão de ativos visuais (`card_asset`, `card_asset_type`, `asset_source`, `asset_import_run`, `asset_import_failure`, `storage_bucket`) e se essa infraestrutura, hoje nomeada em torno de Card, se generaliza para Set (que precisará de `logo_url` e `symbol_url` — ver `04-domain-model.md`) ou se recebe uma estrutura própria;
- convenção de pasta para versionar código de Edge Function no repositório (análoga a `database/` para SQL), ainda não formalizada — ver nota da seção "Sprint B2.0", abaixo, incluindo a divergência entre a estrutura proposta pela sessão pareada e a estrutura real já em uso em `database/`;
- se a pasta local `C:\Users\Administrador\Project-Mimikyu` (criada no Sprint B2.0 para desenvolvimento das Edge Functions) corresponde a um clone do repositório GitHub oficial `fabriciosouzasales/project-mimikyu` ou é um ambiente de trabalho local separado — ver "Sprint B2.0", abaixo;
- verificação de direitos/termos de uso das imagens antes de importação em massa (ver `05-modelo-de-dados.md`, seção "Arquitetura de Importação de Ativos" — ressalva registrada, não resolvida).

---

# Primeira Aplicação Concreta — Seed de Card Variant (`860`)

Escopo restrito: apenas para popular a tabela `card_variant` (ver `04-domain-model.md`, seção Card Variant Type/Card Variant, e `05-modelo-de-dados.md`, seção Card Variant). Não é ainda uma definição geral de pipeline para as demais entidades do catálogo.

Fontes identificadas e seus papéis:

- **Checklist oficial da Pokémon** (já usado como fonte primária para `840`): confirma quais Cards existem, numeração, raridade e a impressão principal — mas nem sempre lista individualmente variantes paralelas (`REVERSE_HOLO`, `POKE_BALL_REVERSE`, `MASTER_BALL_REVERSE`).
- **TCGdex**: expõe por Card um campo `variants` (`normal`/`reverse`/`holo`/`firstEdition`) que descreve explicitamente quais impressões são conhecidas — fonte estruturada principal proposta para `860`.
- **Pokémon TCG API**: não tem campo tão direto, mas seu objeto de preços (`normal`/`holofoil`/`reverseHolofoil`) serve como evidência complementar — não deve ser usada isoladamente, já que ausência de preço não comprova ausência da variante.

Pipeline proposto (ainda não implementado, apenas decidido): `Checklist oficial + TCGdex variants + Pokémon TCG API (evidência complementar) + validação manual de exceções (POKE_BALL_REVERSE, MASTER_BALL_REVERSE, PROMO_STAMPED — exigem tratamento individual por Card Set) → dataset intermediário rastreável (fonte + status de validação por linha) → Query 860`. Dado o volume estimado, o Seed será dividido e validado por Card Set (`860A`–`860E`), consolidado depois na Query canônica `860`.

---

# Arquitetura de Execução — Edge Function `import-card-assets` (Bloco B1)

Ver `05-modelo-de-dados.md`, seção "Roteiro Consolidado — Fases e Blocos", para o posicionamento deste bloco dentro do roteiro geral (Fase 1 — Catálogo Editorial: Bloco A concluído, **Bloco B iniciado nesta revisão**, Bloco C pendente).

Antes de escrever qualquer código, a sessão pareada de Fabrício apresentou uma especificação completa das responsabilidades da Edge Function `import-card-assets`. Resumo por etapa:

**1. Validar a execução.** Ao ser chamada, a função consulta `asset_import_run` e verifica: o registro existe; o `status` é `PENDING` ou `RUNNING`; o `asset_source` referenciado está ativo; o `card_set` e o `language` (quando informados) existem; o `run_type` é suportado. A transição `PENDING → RUNNING` é feita pela própria função ao iniciar — o preenchimento de `started_at` continua a cargo do trigger de governança já existente (`221`, ver `05-modelo-de-dados.md`).

**2. Selecionar as cartas.** A seleção parte do `card_set_id` da execução e varia por `run_type`: `MISSING_ONLY` seleciona cartas sem o ativo esperado; `REFRESH_EXISTING` seleciona cartas que já possuem imagem e podem ser atualizadas; `RETRY_FAILURES` seleciona apenas cartas com falhas não resolvidas em `asset_import_failure`; `SINGLE_CARD` seleciona a carta indicada em `parameters.card_id`; `FULL_CARD_SET` seleciona todas as cartas do `card_set`.

**3. Resolver a referência externa.** Para cada carta: procurar uma referência ativa em `card_external_reference`; se existir, reutilizar `external_card_id`/`image_source_url`; se não existir, consultar a fonte externa, confirmar a correspondência (por `card_set` + número da carta + idioma + fonte — o nome da carta serve apenas como verificação auxiliar, nunca como chave principal) e criar o registro em `card_external_reference`.

**4. Fontes de dados, em ordem de prioridade.** Primeira fonte: **TCGdex** — suporte multilíngue, dados de cards/sets, imagens com escolha de extensão/qualidade, API REST relativamente simples; a disponibilidade de imagem depende de ela já ter sido contribuída e processada pela própria TCGdex, portanto a ausência de imagem para uma carta/idioma deve ser tratada como falha recuperável, não como erro estrutural do sistema. Segunda fonte, usada como alternativa quando a primeira não tiver a imagem adequada: **Pokémon TCG API**.

**5. Download e validação.** `HTTP GET` da URL externa; antes de aceitar o arquivo: resposta HTTP entre 200-299; corpo não vazio; `Content-Type` válido; tamanho máximo; assinatura básica do arquivo; formato permitido (`image/png`, `image/jpeg`, `image/webp` aceitos na origem). O arquivo é mantido em memória como `ArrayBuffer`; o armazenamento efêmero em `/tmp`, disponível em Edge Functions, só deve ser usado quando a transformação exigir arquivo intermediário.

**6. Formato canônico.** A convenção já definida é `front.png`. Decisão para a primeira versão: preservar o conteúdo original quando ele já for PNG, convertendo apenas JPEG/WebP quando necessário — evita o custo de CPU/memória de converter tudo indiscriminadamente logo na primeira prova de conceito.

**7. Caminho no Storage.** Confirma, sem alterar, a convenção já fixada em `05-modelo-de-dados.md` (seção "Query 231", nota de convenção de caminho): bucket `card-front`, caminho `pokemon/{card-set-code}/{language-code}/{card-number}/front.png` (ex.: `pokemon/me1/pt-BR/001/front.png`, `pokemon/me2.5/pt-BR/217/front.png`, `pokemon/me3/en/088/front.png`). Nesta revisão a variável foi renomeada em prosa para `card-set-code` (antes referida como `collection-code`) — mesmo ajuste terminológico já aplicado ao dado físico em `220`/`221` (`collection_id` → `card_set_id`). Antes de montar o caminho, `card-set-code` é normalizado para minúsculas, `language-code` segue o código oficial cadastrado, e `card-number` segue a numeração canônica do catálogo.

**8. Política de upload (`upsert`).** `MISSING_ONLY` e `FULL_CARD_SET`: `upsert = false` — o sistema nunca deve sobrescrever silenciosamente um arquivo já existente. `REFRESH_EXISTING`: `upsert = true` — substituição explicitamente autorizada pelo tipo da execução. `RETRY_FAILURES`: depende da etapa da falha original — `upsert = false` se a falha ocorreu antes do upload; verificação de existência do objeto se a falha ocorreu após upload parcial; caso contrário, respeita o contexto da execução original.

**9. Registro em `card_asset`.** Só é criado ou atualizado **depois** do upload confirmado — nunca antes, para não presumir que o upload funcionará. O registro aponta para carta, tipo de ativo, idioma, bucket, caminho interno, MIME type, tamanho, dimensões, hash e origem, além do status ativo.

**10. Hash e idempotência.** A função calcula `SHA-256` do conteúdo baixado (reaproveitando `checksum_sha256`, já existente em `card_asset` e nunca usado até agora — ver `05-modelo-de-dados.md`, seção "Arquitetura de Importação de Ativos"). Antes do upload, verifica se já existe `card_asset` para aquela combinação carta+idioma+tipo, se o caminho já existe, e se o hash é igual — se for, o resultado é `SKIPPED_ALREADY_CURRENT` e o item soma em `skipped_count`, não em `success_count`/`failed_count`. Reexecutar a mesma operação não deve gerar registros duplicados nem resultados inconsistentes.

**11. Tratamento de falhas.** Cada falha de carta é registrada em `asset_import_failure` (ver `05-modelo-de-dados.md`, "Query 230"), com exemplos de `failure_stage`/`error_code`: `REFERENCE_LOOKUP`/`EXTERNAL_CARD_NOT_FOUND`; `SOURCE_REQUEST`/`HTTP_429`; `DOWNLOAD`/`DOWNLOAD_TIMEOUT`; `VALIDATION`/`INVALID_CONTENT_TYPE`; `TRANSFORMATION`/`IMAGE_CONVERSION_FAILED`; `STORAGE_UPLOAD`/`STORAGE_UPLOAD_FAILED`; `CARD_ASSET_WRITE`/`DATABASE_WRITE_FAILED`. O pipeline segue para a próxima carta sempre que a falha for isolada a um item; apenas uma falha estrutural (fonte inexistente, credencial inválida, bucket inexistente, configuração incoerente, banco indisponível) encerra toda a execução.

**12. Contadores e status final.** Cada item processado incrementa `processed_count` e, conforme o resultado, `success_count`, `failed_count` ou `skipped_count`. Ao final: `failed_count = 0` → `COMPLETED`; `failed_count > 0` e houve sucessos → `COMPLETED_WITH_ERRORS`; nenhuma carta processada por falha estrutural → `FAILED` — a mesma máquina de estados já validada pelo trigger `govern_asset_import_run()` (`221`).

**13. Segurança.** A função usa internamente a credencial de serviço do projeto (`service_role`), mantida em secrets da Edge Function — nunca exposta ao cliente, junto com tokens das APIs externas, detalhes internos do banco e mensagens técnicas completas. Na primeira fase, a execução da função fica restrita a chamadas administrativas.

**14. Estrutura de arquivos prevista (planejamento, não implementada de uma vez):**

```text
supabase/functions/import-card-assets/
├── index.ts
├── types.ts
├── config.ts
├── services/
│   ├── database.ts
│   ├── storage.ts
│   ├── image.ts
│   └── import-run.ts
├── sources/
│   ├── source-adapter.ts
│   ├── tcgdex.ts
│   └── pokemon-tcg-api.ts
└── utils/
    ├── errors.ts
    ├── hash.ts
    └── paths.ts
```

Para a primeira prova de conceito, a implementação começa menor (um único arquivo) e só é separada em módulos quando houver comportamento real para cada um.

---

# Roteiro de Implementação Incremental — Bloco B (Sprints B2.1–B2.12)

Depois de apresentar a arquitetura completa acima, Fabrício pediu explicitamente para reduzir a verbosidade do processo de trabalho: *"Siga. Vamos ser um pouco mais objetivo nessa fase."* A sessão pareada concordou e adotou um ritmo de ciclos curtos — **Objetivo → Implementar → Validar → Evoluir** — entregando por sprint apenas objetivo, código, forma de validar e próximo passo, sem repetir a arquitetura já registrada acima.

**Disciplina de execução refinada e formalizada em revisão posterior desta seção**, depois que Fabrício interrompeu diretamente para perguntar se deveria executar algum dos códigos já mostrados: *"Vamos com calma. Eu deveria executar algum desses códigos? Até agora não executei nenhum código."* A sessão pareada confirmou que **nada do Sprint B2.1 nem do B2.2 havia sido executado até aquele ponto** — apenas descrito — e adotou, para código, a mesma disciplina já usada para SQL: **um passo → Fabrício executa → validação → só então o próximo passo**, em vez de apresentar vários sprints em sequência antes de qualquer execução real. Esta seção documenta o roteiro planejado; a marcação `(CONFIRMADO)` em cada sprint abaixo indica execução real, verificada por evidência (captura de terminal ou saída explícita), no mesmo padrão já aplicado a Queries SQL.

Roteiro definido:

| Sprint | Escopo |
|--------|--------|
| B2.0 | Preparar o ambiente local de desenvolvimento (VS Code, Node.js, Supabase CLI) |
| B2.1 | Criar Edge Function básica |
| B2.2 | Testar acesso ao banco |
| B2.3 | Ler um `asset_import_run` |
| B2.4 | Consultar uma carta na TCGdex |
| B2.5 | Baixar uma imagem |
| B2.6 | Enviar uma imagem ao Storage |
| B2.7 | Criar `card_external_reference` |
| B2.8 | Criar `card_asset` |
| B2.9 | Registrar falha |
| B2.10 | Processar um pequeno lote |
| B2.11 | Executar um `card_set` completo |
| B2.12 | Realizar a carga oficial da Query `880` |

## Sprint B2.0 — Preparar o ambiente local (CONFIRMADO — ambiente pronto)

Sprint inserido nesta revisão, antes de qualquer execução real de código. Até este ponto, **100% do trabalho de banco de dados (tabelas, triggers, RLS, migrations) foi feito com sucesso apenas pelo painel web do Supabase** — suficiente para SQL, mas não para Edge Functions, que são código TypeScript real e se beneficiam de versionamento de arquivos, organização de código, testes locais e deploy controlado, hoje só bem resolvidos via **Supabase CLI**. Fabrício confirmou trabalhar até então apenas pelo painel web, sem CLI instalada.

Passos executados e confirmados, um de cada vez (disciplina descrita acima), com evidência real de terminal em cada etapa:

1. Verificação do ambiente (`code --version`, `node --version`, `supabase --version`) — **confirmado**: Visual Studio Code instalado; Node.js `23.6.0` instalado; Supabase CLI não instalada.
2. Tentativa de instalação via `winget install Supabase.CLI` — **falhou**: pacote não encontrado no repositório do `winget` daquela instalação do Windows (confirmado também por `winget search supabase`, sem resultados).
3. Verificação de `scoop --version` como alternativa — **confirmado que o Scoop também não estava instalado**.
4. **Decisão final de instalação**: em vez de instalar mais um gerenciador de pacotes, usar a CLI via `npx supabase` (sem instalação global) — evita problemas de instalação no Windows, sempre usa a versão mais recente, dispensa Scoop/Winget, e facilita compartilhar o projeto em outra máquina no futuro. Requisito mínimo do Supabase CLI (Node.js 20+) já atendido pela versão instalada.
5. Criação da pasta raiz do ambiente de desenvolvimento local, confirmada via `pwd`: `C:\Users\Administrador\Project-Mimikyu`.
6. `npx supabase --version` executado com sucesso (download automático do pacote na primeira execução) — **confirmado via captura real de terminal**: Supabase CLI `2.109.1` baixada e funcionando.

**Nota importante, não resolvida nesta revisão**: `C:\Users\Administrador\Project-Mimikyu` é uma pasta local nova, criada nesta sessão para o desenvolvimento das Edge Functions — **ainda não confirmado se ela corresponde a um clone do repositório GitHub oficial `fabriciosouzasales/project-mimikyu`** (o mesmo que esta documentação governa) ou se é um ambiente de trabalho local separado, a ser integrado ao repositório em um momento posterior. A sessão pareada também apresentou uma proposta de estrutura de pastas (`database/migrations`, `database/seeds`, `supabase/functions`, `supabase/config.toml`) que **diverge da estrutura já estabelecida e em uso no repositório real** (`database/schema`, `database/functions` — funções SQL compartilhadas —, `database/migrations`, `database/seeds`, `database/validations`, `database/reference-data`, `database/diagrams`, governadas por `database/README.md` e `STD-001`) — presumivelmente porque a sessão pareada, ao contrário desta, não tem visibilidade direta do repositório GitHub real. Antes de qualquer código de Edge Function ser de fato incorporado ao repositório, recomenda-se que Fabrício confirme: (a) se a pasta local se tornará o próprio clone do repositório oficial; (b) a estrutura de pastas final para `supabase/functions/`, para não conflitar com a estrutura de `database/` já documentada. Não resolvido unilateralmente.

Próximo passo, ao final deste sprint: login na conta Supabase, conexão da CLI ao projeto existente (`mimikyu-core`) e criação da primeira Edge Function — ainda sem alterar nenhuma tabela do banco.

## Sprint B2.1 — Criar Edge Function (código proposto, deploy ainda não confirmado)

Objetivo: ter uma Edge Function publicada e respondendo, sem nenhuma lógica de importação ainda.

```ts
// supabase/functions/import-card-assets/index.ts
import { serve } from "https://deno.land/std/http/server.ts";

serve(async () => {
  return new Response(
    JSON.stringify({
      success: true,
      function: "import-card-assets",
      status: "ready",
    }),
    { headers: { "Content-Type": "application/json" } }
  );
});
```

Deploy proposto: `supabase functions deploy import-card-assets`. Teste proposto: `supabase functions invoke import-card-assets`, esperando `{"success": true, "function": "import-card-assets", "status": "ready"}`.

**Confirmado nesta revisão que nada disto foi executado.** Fabrício perguntou diretamente se deveria rodar algum dos códigos apresentados até então, e a resposta foi explícita: *"Nada do B2.1 nem do B2.2 foi executado."* Este código permanece como proposta, não como resultado — mesmo princípio já aplicado a SQL não confirmado (ver `database/README.md`: nada é registrado como concluído sem confirmação real). Quando o deploy for confirmado (após o Sprint B2.0 acima ser concluído — login + conexão do projeto), este código deverá ser versionado no repositório; a convenção de pasta ainda não foi formalizada (ver nota do Sprint B2.0, acima).

## Sprint B2.2 — Ler uma execução de importação (código refinado, ainda não executado)

Objetivo: a Edge Function deve receber um `run_id` via payload JSON, consultar `asset_import_run` no Supabase e retornar os dados da execução — nada de TCGdex, Storage ou download ainda.

```ts
// supabase/functions/import-card-assets/index.ts
import { serve } from "https://deno.land/std/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

serve(async (req) => {
  const { run_id } = await req.json();

  if (!run_id) {
    return Response.json(
      { success: false, error: "run_id is required" },
      { status: 400 }
    );
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
  );

  const { data, error } = await supabase
    .from("asset_import_run")
    .select("*")
    .eq("id", run_id)
    .single();

  if (error) {
    return Response.json(
      { success: false, error: error.message },
      { status: 404 }
    );
  }

  return Response.json({
    success: true,
    run: data,
  });
});
```

Estrutura de arquivos ajustada nesta revisão: `supabase/functions/import-card-assets/{index.ts, deno.json}` (`deno.json` adicionado à estrutura antes prevista). Deploy/teste propostos: `supabase functions deploy import-card-assets`, depois criar um registro de teste em `asset_import_run` e invocar com `supabase functions invoke import-card-assets --body '{"run_id":"..."}'`, esperando `{"success": true, "run": {...}}`. **Mesmo status do Sprint B2.1: código proposto, nenhuma execução confirmada.** Próximo sprint planejado após a execução real de B2.1/B2.2 (ainda sujeito ao Sprint B2.0 acima): B2.3 — primeira consulta ao catálogo (`run_id` → `asset_import_run` → `card_set` → `language` → listar cartas), ainda sem nenhuma API externa.

---

# Revision History

| Versão | Descrição |
|---------|-----------|
| 0.1 | Estrutura inicial do documento, com o padrão geral de importação/sincronização definido em ADR-008. Mecanismos concretos de pipeline ainda pendentes. |
| 0.2 | Adicionada a seção "Importação de Ativos Visuais": o mesmo padrão Import/Synchronization se aplica a imagens e logotipos, com armazenamento no Supabase Storage. Referenciada a infraestrutura física pré-existente (`card_asset`, `card_asset_type`, `asset_source`, `asset_import_run`, `asset_import_failure`, `storage_bucket`) e sinalizada como ponto em aberto se ela se generaliza além de Card. Confirmado que o logotipo da Expansion segue este mesmo padrão. |
| 0.3 | Correção: o logotipo/símbolo pertence ao Set, não à Expansion (ver `04-domain-model.md` e `05-modelo-de-dados.md`). Atualizadas as referências à infraestrutura de ativos visuais e ao ponto em aberto sobre generalização. |
| 0.4 | Adicionada a seção "Primeira Aplicação Concreta — Seed de Card Variant (`860`)": resposta parcial e com escopo restrito ao ponto em aberto "quais fontes externas específicas serão efetivamente integradas" — checklist oficial + campo `variants` da TCGdex (fonte estruturada principal) + Pokémon TCG API (evidência complementar de preço, não fonte isolada) + validação manual para variantes específicas de Card Set (`POKE_BALL_REVERSE`/`MASTER_BALL_REVERSE`) e `PROMO_STAMPED`. Pipeline decidido, ainda não implementado. Ver `04-domain-model.md` e `05-modelo-de-dados.md`, seção Card Variant, para o contexto completo. |
| 0.5 | Cross-referência à seção "Finish/Card Finish" de `04-domain-model.md` corrigida para "Card Variant Type/Card Variant", refletindo a convergência de nomenclatura de ADR-016. |
| 0.6 | **Bloco B (Pipeline de Importação) iniciado.** Adicionada a seção "Arquitetura de Execução — Edge Function `import-card-assets` (Bloco B1)": especificação completa das 14 responsabilidades da função (validação da execução, seleção de cartas por `run_type`, resolução de `card_external_reference`, fontes TCGdex/Pokémon TCG API, download/validação, formato canônico, caminho no Storage, política de `upsert`, ordem de registro em `card_asset`, hash/idempotência via `SHA-256`, tratamento de falhas por `failure_stage`/`error_code`, contadores/status final, segurança, estrutura de arquivos prevista). Adicionada a seção "Roteiro de Implementação Incremental — Bloco B (Sprints B2.1–B2.12)", registrando a mudança de método pedida por Fabrício ("Siga. Vamos ser um pouco mais objetivo nessa fase.") — ciclos curtos Objetivo/Implementar/Validar/Evoluir. Documentado o código proposto do Sprint B2.1 (Edge Function básica, apenas resposta `status: ready`) e o objetivo do Sprint B2.2 — **nenhum dos dois confirmado como executado/deployado nesta revisão**. Atualizada a seção "Em Aberto" com os pontos parcialmente respondidos por esta arquitetura. |
| 0.7 | **Confirmado explicitamente por Fabrício que nada do Sprint B2.1/B2.2 havia sido executado ("Vamos com calma. Eu deveria executar algum desses códigos? Até agora não executei nenhum código.") — disciplina de execução refinada para código: um passo por vez, com validação antes de prosseguir, mesmo padrão já usado para SQL.** Novo **Sprint B2.0 — Preparar o ambiente local**, inserido antes do B2.1: até este ponto, 100% do trabalho de banco foi feito pelo painel web do Supabase, suficiente para SQL mas não para Edge Functions; migração para desenvolvimento local **CONFIRMADA e concluída nesta revisão**, com evidência real de terminal em cada etapa — VS Code e Node.js `23.6.0` já instalados; tentativa de instalar a Supabase CLI via `winget` falhou (pacote ausente no repositório); Scoop também não instalado; decisão final de usar `npx supabase` sem instalação global; pasta raiz local `C:\Users\Administrador\Project-Mimikyu` criada; `npx supabase --version` executado com sucesso, confirmando Supabase CLI `2.109.1` funcional. **Nota não resolvida**: ainda não confirmado se essa pasta local corresponde a um clone do repositório GitHub oficial `fabriciosouzasales/project-mimikyu`, nem como a estrutura de pastas proposta pela sessão pareada (`database/migrations`, `database/seeds`, `supabase/functions`) se concilia com a estrutura já real e documentada em `database/README.md` (`schema`/`functions`/`migrations`/`seeds`/`validations`/`reference-data`/`diagrams`). Sprint B2.2 recebeu código refinado (payload `run_id`, `createClient`, consulta a `asset_import_run`, tratamento de erro) e a estrutura de arquivos ganhou `deno.json` — **status inalterado: proposto, não executado**. Atualizada a seção "Em Aberto" com os dois novos pontos (convenção de pasta de Edge Function + relação pasta local/repositório oficial). |
