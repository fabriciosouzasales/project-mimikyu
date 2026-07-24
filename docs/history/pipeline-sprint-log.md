# Diário Histórico — Pipeline de Importação (`import-card-assets`)

| Campo | Valor |
|--------|-------|
| **Documento** | Diário Histórico — Pipeline de Importação |
| **Arquivo** | `docs/history/pipeline-sprint-log.md` |
| **Versão** | 1.0 |
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

---

# Revision History

| Versão | Descrição |
|---------|-----------|
| 1.0 | Documento criado a partir da separação de `06-pipeline-importacao.md` em três artefatos (arquitetura/processo, guia operacional, diário histórico), a pedido explícito de Fabrício. Conteúdo reconstruído a partir da tabela de Revision History condensada que existia em `06-pipeline-importacao.md` (revisões `0.1`–`1.1`) — o nível de detalhe por sprint individual, anterior a essa condensação, não foi recuperado linha a linha (ver "Nota sobre a origem deste documento", acima). |
