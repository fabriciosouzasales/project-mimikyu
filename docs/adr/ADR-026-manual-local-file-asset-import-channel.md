# ADR-026 — Manual Local-File Asset Import Channel

| Campo | Valor |
|--------|-------|
| **ADR** | ADR-026 |
| **Título** | Manual Local-File Asset Import Channel |
| **Status** | Aprovado — formaliza um mecanismo já implementado e em uso em produção desde 2026-07-24 (`MEE`/`en`, 8/8 Cards, 0 falhas), nunca antes registrado como decisão arquitetural. |
| **Data** | 2026-08-07 (formalização retroativa; mecanismo real desde 2026-07-24) |
| **Decisores** | Project Mimikyu (Fabrício Sales / Claude) |
| **Decisão** | Quando a fonte externa (TCGdex) genuinamente não publica o asset de uma Card — Card Set inteiro ausente da fonte, não um gap pontual recuperável por retry — a aquisição da imagem passa por um canal alternativo dedicado: script administrativo standalone (`scripts/import-manual-assets.ts`), executado localmente sob demanda com a Service Role Key, lendo uma convenção fixa de pastas locais e gravando em `card_asset` com `source_code = 'MANUAL'` (fonte já modelada em `public.asset_source`, Query `200`) — nunca via Edge Function, nunca sem rastreabilidade de origem. |
| **Documentos Relacionados** | `../06-pipeline-importacao.md`, `../operations/import-card-assets.md`, `../05c-assets-e-importacao.md`, `ADR-018-single-function-import-pipeline.md`, `ADR-008-external-catalog-data-sources.md`, `../ROADMAP.md` (Trilha 1) |

---

# Context

`ADR-018` formaliza `import-card-assets` (Edge Function única) como o caminho automatizado de aquisição de referências externas e imagens, consultando a TCGdex. Esse caminho pressupõe que a fonte externa efetivamente publica o dado — uma premissa que se mostrou falsa para dois Card Sets reais da Expansion `ME`: `MEE` (Energia Básica) e `MEP` (Promocional).

Confirmado por consulta direta ao CDN da TCGdex em 2026-07-24 (HTTP 404 direto no endereço da imagem, não apenas campo `image` vazio na resposta da API): a TCGdex genuinamente não possui os assets visuais desses dois Sets. `card_external_reference` das duas coleções já estava 100% importada via `import-card-assets` (a TCGdex conhece a existência das cartas, só não publica a imagem) — o gap é estritamente de asset visual, isolado à camada `card_asset` (que não depende de `card_external_reference`, ver `05c-assets-e-importacao.md`).

Sem um mecanismo alternativo, essas duas Coleções ficariam permanentemente sem imagem — bloqueando indefinidamente um compromisso já registrado pelo próprio projeto: *"Não teremos encerrado toda a fundação do catálogo editorial do Project Mimikyu. Só concluímos após importação de todas as imagens para nossa base"* (`05-modelo-de-dados.md`, revisão `0.63`, decisão de Fabrício). Esperar a TCGdex publicar os assets não tem prazo nem garantia.

Fabrício optou, em 2026-07-24, por criar `scripts/import-manual-assets.ts`: um script administrativo que lê arquivos de imagem de uma pasta local do operador e os importa para `card_asset` com rastreabilidade explícita (`source_code = 'MANUAL'`). O mecanismo foi implementado, testado (dry-run) e executado com sucesso para `MEE`/`en` no mesmo dia — mas nunca recebeu um ADR próprio. Ficou documentado apenas no nível operacional (`operations/import-card-assets.md`, "Quando usar cada caminho") e físico (`05c-assets-e-importacao.md`, coluna `source_code`), sem nenhum registro do porquê ele existe, qual é sua fronteira de escopo, e por que não foi resolvido de outra forma — exatamente o tipo de decisão que corre risco de cair no esquecimento institucional em uma próxima sessão sem memória deste racional (ver `CLAUDE.md`, motivação para a existência de artefatos versionados).

O gatilho direto para formalizar isso agora: em 2026-08-07, Fabrício confirmou que concluir esta funcionalidade (a importação manual pendente de `MEP`) é **mais prioritária** do que iniciar o Ciclo 3 de `ADR-024` (prova técnica do processador de PDF) — uma decisão de sequenciamento que também precisa ficar registrada, não só na memória da sessão.

---

# Decision

## Canal dedicado, não uma exceção ad-hoc

`MANUAL` é um valor de primeira classe em `public.asset_source.source_type` (`ck_asset_source_type`, Query `200`), ao lado de `API` (TCGdex) e `DATASET` — não um caso especial escondido em código. A constraint `ck_asset_source_manual_configuration` já impõe, no nível de schema, que uma fonte `MANUAL` nunca tenha `supports_api = TRUE` nem `supports_bulk_download = TRUE`: é estruturalmente impossível confundi-la com um canal automatizável.

## Script standalone, nunca Edge Function

`scripts/import-manual-assets.ts` roda localmente, sob demanda, com a Service Role Key — nunca é implantado no Supabase. Isso não é uma escolha de conveniência: uma Edge Function não tem acesso ao sistema de arquivos local do operador (`Deno.readDirSync`/`readFile` sobre uma pasta pessoal), então este mecanismo estrutural e deliberadamente não pode viver em `supabase/functions/import-card-assets/` (que é implantada por inteiro a cada deploy). Mesmo precedente já usado por `scripts/discover-tcgdex-sets.ts` (`06-pipeline-importacao.md`, Sprint B2.5A).

## Convenção fixa de pastas

```text
assets/manual-imports/{card_set_code_lowercase}/{language_code}/{collector_number}.{ext}
```

O nome do arquivo (sem extensão) deve ser exatamente igual a `card.collector_number` já cadastrado — nunca `collector_order` — porque Card Sets promocionais preservam lacunas reais de numeração (ver `05-modelo-de-dados.md`, seção Card Set, "Migration 265-268"). O script falha explicitamente (`CARD_NOT_FOUND`) se a Card ainda não existir — este canal nunca cria Cards, só anexa imagem a uma Card já cadastrada por outra via (`ADR-023`/`ADR-024`).

## Rastreabilidade e coexistência com o canal automatizado

Todo `card_asset` criado por este script grava `source_code = 'MANUAL'`, distinto de `'TCGDEX'`. A idempotência (`upsertCardAsset`) é resolvida pela chave natural (`card_id` + `asset_type_id` + `language_id` + `storage_bucket_id`), não por `source_code` — ou seja, se a TCGdex algum dia publicar o asset real para `MEE`/`MEP`, uma execução futura do pipeline automatizado (`import-card-assets`) pode sobrescrever a linha `MANUAL` de forma transparente, sem exigir limpeza manual prévia.

## Validação antes de gravar

`--dry-run` é obrigatório antes de qualquer execução real (Convenção #7 do projeto, já citada no cabeçalho do script) — mostra exatamente o que seria criado/atualizado, sem gravar nada.

## Fronteira de escopo: só imagem, nunca conteúdo de Card

Este canal grava exclusivamente `card_asset` (a imagem). Ele nunca cria ou corrige `card`/`card_set`/`rarity`/`card_category` — o conteúdo estrutural da Card precisa já existir via `ADR-023` (cadastro administrativo) ou `ADR-024` (ingestão por PDF/TCGdex) antes deste script poder anexar uma imagem a ela. Misturar as duas responsabilidades no mesmo mecanismo violaria a separação já estabelecida entre conteúdo editorial (`ADR-024`) e ativos visuais (`ADR-018`).

## Prioridade confirmada (2026-08-07)

Fabrício confirmou explicitamente: concluir a importação manual de `MEP` (`60` Cards, `en`+`pt-BR`) é **prioridade mais alta do que iniciar o Ciclo 3 de `ADR-024`** (prova técnica do processador de PDF). Registrado aqui e em `ROADMAP.md`, Trilha 1 — não é uma reordenação de Ciclo 3 em si (que segue não iniciado, sem cronograma), apenas a confirmação de que esta funcionalidade tem precedência quando ambas competirem por atenção.

## Emenda: segundo ponto de entrada via UI (2026-08-08)

`scripts/import-manual-assets.ts` continua existindo e funcionando exatamente como descrito acima — esta emenda não o substitui, adiciona um segundo produtor independente para o mesmo canal `MANUAL`, pedido explícito de Fabrício: evoluir `/catalogo/importar-imagens` para suportar `Fonte = API` (fluxo TCGdex existente, intocado) ou `Fonte = Manual` (upload direto do navegador, sem campo de texto para caminho local), com validação prévia (nomes, quantidade, extensões, duplicidade, Card inexistente, Card já com imagem) antes de qualquer gravação.

Decisões de arquitetura desta emenda:

- **Upload direto navegador → Storage**: bytes nunca passam pelo servidor. Duas novas políticas admin-only em `storage.objects` (`card_front_admin_insert`/`card_front_admin_delete`, Query `2119`) — menor privilégio real do fluxo: sem `SELECT`/`UPDATE` (a checagem de "já tem imagem" usa `card_asset`, não lista o Storage; nunca há sobrescrita in-place, sempre um path novo). `card-front` não tinha nenhuma política dedicada antes desta Query — confirmado por consulta a `pg_policies` antes de implementar.
- **Path sempre novo, nunca reaproveitado**: `{cardSetCode}/{languageCode}/{collectorNumber}-{uuid}.{ext}` — diferente da convenção de pasta do script (que usa `{collector_number}.{ext}` fixo). Path determinístico com sobrescrita in-place foi cogitado e descartado: se a persistência em `card_asset` falhasse depois do upload, o rollback (remover o arquivo recém-subido) apagaria uma imagem anterior boa no mesmo caminho. Com path sempre único, o rollback do navegador nunca toca em nada além do que ele mesmo acabou de subir; o arquivo antigo (se havia) só é removido depois de confirmada a troca do ponteiro — mesmo padrão de três passos já usado por `CardSetLogoUploader`/`ExpansaoLogoUploader`/`AvatarUploader`.
- **Servidor recebe só metadados**: `admin_persist_manual_card_asset()` (Query `2120`, `SECURITY DEFINER`) nunca recebe bytes — só resolve invariantes (Card pertence ao Card Set informado; idioma existe; `CARD_FRONT`/bucket `card-front` resolvidos **internamente**, nunca aceitos como parâmetro, fechando a possibilidade de o canal gravar em outro tipo de ativo ou bucket) e faz o upsert pela chave natural real de `card_asset` (`uq_card_asset_card_type_language_order`, confirmada em produção antes de escrever a função — não assumida da leitura do repositório). Devolve o `storage_path` anterior (se havia) para o cliente decidir o que remover, e só depois de confirmado o sucesso.
- **Auditoria por lote, não por arquivo**: `admin_log_manual_card_asset_import_batch()` (Query `2122`) grava uma única linha em `catalog_admin_action_log` ao final do lote inteiro (ação nova `CARD_ASSET_MANUAL_IMPORT_COMPLETED`, associada a `entity_type = 'CARD_SET'` — Query `2121` ampliou as CHECKs correspondentes), com `run_id` (gerado no navegador) e contadores no `metadata` — mesma granularidade agregada já usada por `CATALOG_IMPORT_CONFIRMED` (`ADR-024`).
- **Núcleo compartilhado, sem duplicar lógica**: a lógica de validação/persistência (resolver Card/idioma/tipo/bucket, checar extensão/MIME, montar o upsert) vive em `web/lib/catalogo/manual-asset-import/core.ts` — runtime-neutro (sem Next.js, sem Deno, sem filesystem, sem variáveis de ambiente, sem criar seu próprio client Supabase — recebe um client já pronto). `scripts/import-manual-assets.ts` passa a importar este núcleo em vez de duplicar a lógica; sua parte exclusiva (ler arquivos do disco local, `Deno.readDirSync`/`readFile`) continua existindo, só não duplica mais as regras de negócio que agora também servem à Server Action da web.
- Backend SQL (Queries `2119`–`2122`, validação consolidada `2819`) CONFIRMADO EXECUTADO E VALIDADO em 2026-08-07/08.
- **Frontend implementado (2026-08-08)**: `web/lib/catalogo/manual-asset-import/core.ts` (núcleo runtime-neutro — extensão/MIME, checksum, resolução de Card Set/Card/idioma); `scripts/import-manual-assets.ts` refatorado para importá-lo (mesmo comportamento de antes, sem duplicar a lógica); Server Actions `persistirImagemManual()`/`fecharLoteImportacaoManual()` (`web/app/catalogo/importar-imagens/manual-actions.ts`); `getCartasParaImportacaoManual()` (manifesto por Card Set + idioma, `web/lib/catalogo/queries.ts`); `ImportarImagensManualPicker` (seletor de arquivos + tabela de revisão + progresso, `web/components/catalogo/importar-imagens-manual-picker.tsx`) integrado a `ImportarImagensView` via novo `FonteToggle` (`API`/`Manual`, `?fonte=`), com o modo `API` preservado integralmente. `tsc --noEmit` limpo.
- **Validação funcional em produção real CONFIRMADA (2026-08-08)**: Fabrício testou com a Coleção `SVE` (Energias Escarlate e Violeta) — 6 arquivos de energia básica (Grama/Fogo/Água/Raios/Psíquica/Luta) selecionados pela UI, importados com sucesso e visíveis na galeria `/catalogo/cartas` com a imagem correta. `#007` (Energia de Escuridão) permaneceu "Sem imagem" deliberadamente — não fazia parte do lote testado, não é uma falha. Fluxo completo (seleção → validação prévia → upload direto ao Storage → persistência via `admin_persist_manual_card_asset()` → auditoria de lote) validado de ponta a ponta pela primeira vez em produção real.

---

# Consequences

## Benefícios

- Fecha um gap real de fonte externa (TCGdex não publica `MEE`/`MEP`) com um mecanismo auditável e de baixo risco, em vez de bloquear indefinidamente o fechamento do Catálogo Editorial esperando um terceiro.
- Rastreabilidade real (`source_code = 'MANUAL'`) distingue explicitamente do canal automatizado — permite substituição futura transparente se a TCGdex publicar o asset real, sem exigir intervenção manual de limpeza.
- Nenhuma mudança na arquitetura de ingestão de conteúdo (`ADR-024`) ou no pipeline automatizado de imagens (`ADR-018`) — o canal manual é estritamente aditivo, isolado à camada `card_asset`.
- Este ADR, por si, resolve o risco de esquecimento institucional que motivou sua criação: qualquer sessão futura (Claude ou outro agente) agora encontra o racional completo sem depender de memória de sessão.

## Restrições / Pendências

- O script depende de arquivos locais já organizados pelo operador na convenção de pastas — isso continua valendo para quem preferir esse caminho. Desde a emenda de 2026-08-08, `/catalogo/importar-imagens` também suporta um segundo ponto de entrada (`Fonte = Manual`, upload direto do navegador) para o mesmo canal — ver seção "Emenda" acima. Backend, frontend e validação funcional em produção real (teste com `SVE`, 6 arquivos) todos confirmados — emenda encerrada.
- `MEP` ainda não está completa: hoje só há `13`/`60` arquivos de `en` salvos localmente, pasta `pt-BR` ainda não iniciada — Fabrício optou por aguardar as duas pastas completas antes de rodar o script contra produção (ver `ROADMAP.md`, Trilha 1). Com a decisão de prioridade desta ADR, esta é a próxima ação concreta pendente do módulo Catálogo Editorial.
- Sem validação SQL dedicada (diferente das validações `2813`/`2814`/`2818` do Ciclo 1/2 de `ADR-024`) — o `--dry-run` do próprio script é a única rede de segurança antes de gravar. Suficiente para o volume atual (2 Card Sets, `128` Cards no total); reavaliar se o padrão se repetir para volumes maiores.
- Verificação de direitos/termos de uso das imagens antes de importação em massa continua como ressalva geral do pipeline (`06-pipeline-importacao.md`, "Em Aberto"), aplicável também a este canal.

---

# Alternatives Considered

## Esperar a TCGdex publicar os assets de `MEE`/`MEP`

Rejeitada. Sem prazo nem garantia de que a fonte algum dia publicará esses assets — bloquearia indefinidamente o fechamento do Catálogo Editorial por uma dependência fora do controle do projeto, contrariando o próprio compromisso já registrado de só declarar a fundação do catálogo concluída com todas as imagens importadas.

## Upload avulso genérico pela interface, sem `source_code` dedicado

Rejeitada. Perderia a rastreabilidade que distingue uma imagem oficial da fonte de uma imagem substituta/manual — tornaria impossível saber, mais tarde, quais Cards têm uma imagem "provisória" candidata a ser substituída se a TCGdex algum dia publicar o asset real.

## Ler as pastas locais dentro da própria Edge Function `import-card-assets`

Rejeitada por impossibilidade técnica, não só por preferência: uma Edge Function do Supabase não tem acesso ao sistema de arquivos do computador do operador. Viabilizar isso exigiria um upload prévio dos arquivos para algum lugar acessível pela função — exatamente o passo extra que o script evita para o volume atual (2 Card Sets).

---

# Related Documents

- `../06-pipeline-importacao.md`
- `../operations/import-card-assets.md`
- `../05c-assets-e-importacao.md`
- `ADR-018-single-function-import-pipeline.md`
- `ADR-008-external-catalog-data-sources.md`
- `../ROADMAP.md` (Trilha 1)

---

# Revision History

| Versão | Descrição |
|---------|-----------|
| 1.0 | Criação (2026-08-07) — formaliza um mecanismo já implementado e usado em produção desde 2026-07-24 (`scripts/import-manual-assets.ts`, `asset_source` `MANUAL`), nunca antes registrado como decisão arquitetural — risco real de esquecimento institucional, apontado por Fabrício ao perceber que nenhum ADR cobria essa funcionalidade. Motivada também pela decisão explícita de Fabrício de priorizar a conclusão desta funcionalidade (`MEP` pendente) à frente do Ciclo 3 de `ADR-024` (prova técnica do processador de PDF). Nenhuma mudança de código — documenta o estado real e a decisão de sequenciamento. |
| 1.1 | Emenda "Segundo ponto de entrada via UI" (2026-08-07/08) — `/catalogo/importar-imagens` passa a suportar `Fonte = Manual` (upload direto do navegador para `card-front`), além do canal `API` (TCGdex) já existente, intocado. Backend SQL implementado e CONFIRMADO EXECUTADO E VALIDADO: Query `2119` (2 políticas admin-only em `storage.objects`, menor privilégio — só `INSERT`/`DELETE`), Query `2120` (`admin_persist_manual_card_asset()`, resolve `CARD_FRONT`/bucket internamente, upsert pela chave natural real de `card_asset` confirmada em produção antes de escrever a função), Query `2121` (amplia `catalog_admin_action_log` para a nova ação `CARD_ASSET_MANUAL_IMPORT_COMPLETED`), Query `2122` (`admin_log_manual_card_asset_import_batch()`, uma linha de auditoria por lote, com `run_id`), Query `2819` (validação consolidada dos quatro artefatos). Frontend implementado na mesma rodada: núcleo compartilhado (`web/lib/catalogo/manual-asset-import/core.ts`), `scripts/import-manual-assets.ts` refatorado para reutilizá-lo, Server Actions (`manual-actions.ts`), manifesto (`getCartasParaImportacaoManual`) e `ImportarImagensManualPicker` integrado via `FonteToggle`. `tsc --noEmit` limpo. **Validação funcional em produção real CONFIRMADA no mesmo dia**: teste com a Coleção `SVE`, 6 arquivos de energia básica importados com sucesso pela UI, visíveis na galeria com a imagem correta — fluxo completo (seleção, validação prévia, upload direto ao Storage, persistência, auditoria de lote) funcionando de ponta a ponta. Emenda encerrada. |
