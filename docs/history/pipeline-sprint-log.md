# Diário Histórico — Pipeline de Importação (`import-card-assets`)

| Campo | Valor |
|--------|-------|
| **Documento** | Diário Histórico — Pipeline de Importação |
| **Arquivo** | `docs/history/pipeline-sprint-log.md` |
| **Versão** | 1.1 |
| **Status** | Arquivo histórico — não é atualizado com novas decisões de arquitetura (isso vai em `../06-pipeline-importacao.md`) nem com o guia de uso (isso vai em `../operations/import-card-assets.md`). |
| **Objetivo** | Preservar, fora do caminho de leitura operacional, o histórico de como o pipeline `import-card-assets` chegou ao seu estado atual — tentativas, bugs reais, erros HTTP, propostas descartadas, episódios de perda de contexto e a evolução sprint a sprint. |
| **Escopo** | Só histórico. Para arquitetura vigente, ver `../06-pipeline-importacao.md`. Para o passo a passo de uso, ver `../operations/import-card-assets.md`. |

---

# Nota sobre a origem deste documento

Este arquivo nasce de uma separação de responsabilidades: `06-pipeline-importacao.md` continha, até sua revisão `1.1`, tanto a arquitetura vigente quanto o guia operacional quanto (antes disso, até sua revisão `1.0`) o histórico completo de aproximadamente 50 revisões incrementais (`0.1`–`0.48`) e dezenas de sprints (`B2.0`–`B3.28`). A pedido de Fabrício, esse histórico foi primeiro condensado (revisão `1.0` de `06`) e agora tem um endereço próprio, para que o documento de arquitetura permaneça enxuto sem descartar a rastreabilidade do projeto.

**Limite real de granularidade, registrado por transparência**: o conteúdo abaixo reflete o nível de detalhe já condensado na revisão `1.0` de `06-pipeline-importacao.md` (uma entrada por bloco de revisões, não mais sprint a sprint com trechos de código/erros verbatim). O texto integral de cada sprint individual (`## Sprint B2.0` até `## Sprint B3.28`, com Diários Técnicos completos, mensagens de erro literais e trechos de código) não foi preservado neste arquivo — ele existia na versão do documento anterior à condensação e não foi copiado aqui linha a linha. Quem precisar desse nível de detalhe específico deve consultar o histórico de commits do repositório (fora do escopo de Claude, que não executa comandos Git) ou pedir a Claude para recuperar o contexto de conversas anteriores.

---

# Linha do Tempo

## Fundação (revisões `0.1`–`0.5`)

Padrão geral de importação/sincronização definido, com base em `ADR-008-external-catalog-data-sources.md`. Infraestrutura física de ativos visuais referenciada (`card_asset`, `card_asset_type`, `asset_source`, `asset_import_run`, `asset_import_failure`, `storage_bucket`). Corrigido, nesta fase, que a identidade visual (`logo_url`/`symbol_url`) pertence ao Set, não à Expansion.

## Bloco B iniciado — primeira Edge Function (revisões `0.6`–`0.20`, Sprints `B2.0`–`B2.5A`)

Ambiente de desenvolvimento local configurado (Supabase CLI via `npx`, sem instalação global). Primeira Edge Function `import-card-assets` criada, publicada e testada em ciclos curtos e incrementais — cada sprint só avançava com um critério de aceite validado. Nova entidade `card_set_external_reference` criada para mapear cada `card_set` ao identificador usado pela TCGdex, resolvendo uma lacuna real descoberta no meio do processo (o pipeline precisava saber qual ID a TCGdex usa para um Set antes de poder consultá-lo). Os `external_set_id` reais das 5 coleções (`ME1`–`ME4`/`ME2.5`) foram descobertos via um script administrativo standalone (`scripts/discover-tcgdex-sets.ts`), nunca presumidos manualmente.

## Correção arquitetural real: abandono do `@supabase/server` (revisões `0.21`–`0.34`, Sprints `B3.2`–`B3.10`)

Três sprints seguidos (`B3.3`–`B3.5`) não conseguiram fazer a biblioteca `@supabase/server` (`withSupabase({ auth: ["secret"] })`) autenticar corretamente com uma Secret Key — HTTP 401 persistente, mesmo depois de múltiplas hipóteses reais testadas e descartadas (tipo de chave, header `apikey`, `verify_jwt`). A causa raiz era um mecanismo de autenticação interno da própria biblioteca, incompatível com o uso pretendido. Resolvida no Sprint B3.6 com o abandono completo de `@supabase/server`, substituída por `Deno.serve()` puro + `@supabase/supabase-js`, cliente criado manualmente via `SUPABASE_SERVICE_ROLE_KEY`.

Um segundo padrão de bug real, recorrente ao longo de todo o projeto, apareceu pela primeira vez aqui: **`GRANT` explícito para `service_role` é sempre necessário, mesmo com RLS habilitado** — a ausência de `GRANT` em `card_set_external_reference` causava HTTP 500 mesmo com toda a autenticação correta. Esse mesmo padrão se repetiria mais seis vezes ao longo do projeto (`card_external_reference`, `language`, `card_asset_type`, `card_asset`, `expansion`, e outras), sempre diagnosticado a partir do erro real do PostgreSQL, nunca adivinhado.

Também nesta fase: `ME0` (identificador interno usado para as cartas promocionais de Mega Evolution) foi removida do catálogo depois de uma primeira investigação concluir, incorretamente, que não tinha relação com nenhuma fonte externa homologada (o Set `mee` da TCGdex era outra coisa — Energias, não Promocionais). Essa remoção foi posteriormente refinada: o identificador oficial correto era `MEP`, não `mee` — ver `../05-modelo-de-dados.md`, seção "Migration 251", e `../adr/ADR-015-promotional-card-set-model.md`, para o desfecho real.

Primeira resposta de ponta a ponta da TCGdex confirmada ao final desta fase — marco real do Sprint B3.8.

## Incremento 1 e Incremento 2 — Catálogo completo em inglês (revisões `0.35`–`0.42`, Sprints `B3.11`–`B3.22`)

Dois incrementos sucessivos, cada um validado com uma única carta antes de escalar: Incremento 1 (sincronização de `card_external_reference` a partir da TCGdex) e Incremento 2 (download de imagens, upload ao Storage, registro em `card_asset`). Ambos concluídos primeiro para a `ME1` (188/188, 0 falhas) e depois replicados **sem nenhuma alteração de código** para as demais 4 coleções. Um bug real de regra de negócio foi encontrado e corrigido nesta fase (`external_url` sendo preenchido incorretamente para ativos já armazenados internamente — deveria ser sempre `null` nesse caso). Resultado final: catálogo editorial completo em inglês — 859 cartas, 859 referências externas, 859 imagens, 0 falhas, nas 5 coleções.

## Fase 2 — Catálogo completo nos dois idiomas (revisões `0.43`–`0.48`, Sprints `B3.23`–`B3.25`)

Repetição do processo para `pt-BR`. Um bug real, diferente do que se esperava, bloqueou a primeira tentativa: o cliente da TCGdex estava sendo criado com o código interno do Mimikyu (`pt-BR`), que a API da TCGdex não reconhece — o identificador real da TCGdex para português é `pt`. Corrigido com uma constante separada (`TCGDEX_LANGUAGE`), sem alterar o código interno do banco. Depois da correção, as 5 coleções foram importadas com sucesso em português — catálogo completo nos dois idiomas: 1.718 assets, 1.718 imagens, 0 falhas.

## Reescrita do documento de arquitetura (revisão `1.0` de `06-pipeline-importacao.md`)

A pedido explícito de Fabrício, o documento de arquitetura foi reescrito para conter apenas a solução final confirmada, sem o histórico sprint a sprint — o conteúdo detalhado de cada sprint individual foi condensado nas entradas acima, e este arquivo histórico nasceu depois, na revisão `1.1`/separação em três documentos, para dar a esse histórico um endereço permanente fora do caminho de leitura do dia a dia.

## Correção real: máquina de estados de `asset_import_run` nunca escrita (2026-07-25, v2.6.0)

Fabrício, inspecionando `asset_import_run` diretamente, encontrou 100% das runs já executadas presas em `status = PENDING`, mesmo as concluídas com sucesso — `import-card-assets` nunca escrevia nessa tabela depois do `SELECT` inicial. Corrigido em `index.ts`/`services/database.ts`; as 11 runs históricas corrigidas por backfill manual (dados reais extraídos por consulta). Teste pós-deploy expôs mais um caso do padrão recorrente de `GRANT` faltando para `service_role`, corrigido por `database/migrations/272_grant_asset_import_run_write_permissions.sql`. Detalhe completo: `05-modelo-de-dados.md`, revisão `0.69`/seção "Correção real: máquina de estados nunca escrita".

## Evolução v2.7.0–v2.9.3 do pipeline de imagens (2026-08-02, mesmo dia, várias rodadas)

Sequência de incidentes reais e correções sucessivas na Edge Function `import-card-assets`, todas no mesmo dia, motivadas por testes reais de Fabrício em produção (SV4, ME5):

- **v2.7.0**: retry de staleness em `admin_start_asset_import_run()` (Query `2092` v1.2) — runs presas em `PENDING`/`RUNNING` por mais de 15 minutos passam a ser fechadas como `FAILED` antes de abrir uma nova, destravando o bloqueio permanente relatado em SV4.
- **Bug real**: contador ao vivo "X de Y" nunca aparecia na tela — causa raiz isolada na leitura via Server Action (`getProgressoImportacaoImagens`), não na gravação; corrigido trocando a leitura para consulta direta client-side (`fetchProgressoImportacaoImagens`).
- **v2.8.0/retry automático (revisão `1.38` de `05-modelo-de-dados.md`)**: cliente passou a repetir automaticamente a chamada à Edge Function com o mesmo `run_code` até concluir ou detectar falha persistente, compensando o teto de execução da plataforma (~150s). Reordenação da sincronização de referências para só cobrir cartas pendentes (evita retrabalho redundante a cada tentativa).
- **Bugs reais pós-retry**: tela resetava ao concluir (Card Set concluído saía da lista filtrada, forçando remount que apagava o resultado) — corrigido com `getCardSetImagensById()` como fallback.
- **v2.9.0**: suporte real e simultâneo a `en`+`pt-BR` — `language_id` passou a fazer parte da identidade de `card_external_reference` (antes, uma segunda importação em outro idioma sobrescrevia a mesma linha); idioma deixou de ser constante fixa no código, passando a vir de `asset_import_run.language_id`.
- **Incidente ME5 (v2.9.1/v2.9.2/v2.9.3)**: download sem timeout causava travamento (corrigido com `AbortController`, 20s); retry automático reabrindo uma run já `FAILED` sobrescrevia o erro real com uma mensagem genérica de transição de estado (corrigido com checagem `IMPORT_RUN_ALREADY_TERMINAL`); causa de fundo era instabilidade transiente da própria TCGdex (`TCGDEX_HTTP_502`), resolvida sozinha. `v2.9.3` adicionou retry por download individual (até 3 tentativas por carta, com classificação de erro `retriable`/não), editado diretamente por Fabrício nos arquivos da função.
- **Aborto antecipado**: quando um número relevante de cartas processadas mostra `0` sucesso, a tentativa é interrompida cedo em vez de esperar o teto inteiro de execução — implementado como monitoramento server-side dentro da própria Server Action (o `fetch` para a Edge Function não pode ser abortado do lado do navegador, por rodar no servidor Next.js).

Detalhe completo, revisão a revisão: `05-modelo-de-dados.md`, revisões `1.30`–`1.44`.

## Correções de mapeamento de raridade — saga TCGdex (2026-08-02, mesmo dia)

Ao processar Card Sets adicionais via `ADR-024`/TCGdex (`SV4.5`, `SV5`), surgiram raridades e variações de nome ainda sem alias/cadastro, cada uma bloqueando confirmação de linhas no staging (`RARIDADE_NAO_MAPEADA`):

- Query `830` v1.4: três raridades novas cadastradas (`ACE_SPEC_RARE`/`SHINY_RARE`/`SHINY_ULTRA_RARE`), com símbolos oficiais confirmados por referência visual de Fabrício (estrela rosa/magenta; sparkle dourado simples/duplo, depois ajustado para estrela com borda dourada e centro cinza).
- Gaps de alias descobertos via consulta direta ao banco (MCP do Supabase), não por suposição: `"Brilhante Ultra Rara"` (não coberto pela suposição inicial de texto em inglês) e `"ACE SPEC Raro"` (variação de gênero) — ambos corrigidos em `RARITY_NAME_ALIASES` (`normalize.ts`).
- Query `830` v1.5: símbolo de `HYPER_RARE` corrigido de uma estrela dourada (`GOLD_STAR`, colidindo com `ILLUSTRATION_RARE` desde a criação) para três (`GOLD_TRIPLE_STAR`, código dedicado) — reportado por Fabrício com referência visual oficial, CONFIRMADO EXECUTADO.

Detalhe completo: `05-modelo-de-dados.md`, revisões `1.45`–`1.50`.

---

# Revision History

| Versão | Descrição |
|---------|-----------|
| 1.0 | Documento criado a partir da separação de `06-pipeline-importacao.md` em três artefatos (arquitetura/processo, guia operacional, diário histórico), a pedido explícito de Fabrício. Conteúdo reconstruído a partir da tabela de Revision History condensada que existia em `06-pipeline-importacao.md` (revisões `0.1`–`1.1`) — o nível de detalhe por sprint individual, anterior a essa condensação, não foi recuperado linha a linha (ver "Nota sobre a origem deste documento", acima). |
| 1.1 | **Auditoria de reconciliação documental (2026-08-02), a pedido de Fabrício.** Três seções novas registram histórico operacional que não deve permanecer como estado vigente em `06`/`05`: correção da máquina de estados de `asset_import_run` (v2.6.0, 2026-07-25); evolução v2.7.0–v2.9.3 do pipeline de imagens (retry automático, suporte EN+PT-BR, incidente ME5, aborto antecipado); saga de correções de mapeamento de raridade motivada pela ingestão TCGdex (`ADR-024`). Cronologia e rastreabilidade preservadas, com referência cruzada para o detalhe revisão-a-revisão em `05-modelo-de-dados.md`. Este arquivo não passa a ser fonte de estado atual — para isso, ver `docs/README.md`/handoff vigente. |
