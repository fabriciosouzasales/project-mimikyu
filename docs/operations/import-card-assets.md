# Operação — Importar uma Nova Coleção (`import-card-assets`)

| Campo | Valor |
|--------|-------|
| **Documento** | Operação — Importar uma Nova Coleção |
| **Arquivo** | `docs/operations/import-card-assets.md` |
| **Versão** | 1.4 |
| **Status** | Ativo. **Dois caminhos operacionais coexistem hoje** (2026-08-02): o caminho normal, pela interface (`/catalogo/importar-imagens`, ou a continuação automática disparada por `/catalogo/importar-cartas`); e o processo manual passo a passo abaixo, para os casos que a interface não cobre (ver nota logo abaixo). Estado por coleção da Expansion `ME` (as 7 originais) preservado em "Estado Atual"; Card Sets incorporados depois via `ADR-024`/TCGdex não têm sua contagem detalhada aqui — ver handoff vigente (`../development/`). |
| **Objetivo** | Guia operacional passo a passo para importar uma nova coleção (referências externas + imagens) usando a Edge Function `import-card-assets`, incluindo quando usar o processo manual em vez da tela. |
| **Escopo** | Apenas o "como fazer". Para arquitetura, decisões de design e racional, ver `../06-pipeline-importacao.md`. Para o histórico de como o pipeline chegou a este estado, ver `../history/pipeline-sprint-log.md`. |
| **Dependências** | `../06-pipeline-importacao.md`, `../05-modelo-de-dados.md` |

---

# Quando usar cada caminho

**Caminho normal (recomendado) — pela interface**: para qualquer Card Set que já tenha `card`/`card_variant` cadastrados (via `ADR-024`/TCGdex ou manualmente), use a tela `/catalogo/importar-imagens` — selecione a Coleção, escolha o idioma (`EN`/`PT`), clique em "Importar Imagens". A tela cuida de abrir o `asset_import_run`, invocar a Edge Function, exibir progresso ao vivo ("X de Y"), repetir automaticamente em caso de timeout de plataforma, e agrupar falhas por motivo quando houver. Se a importação de Cards tiver sido feita agora mesmo por `/catalogo/importar-cartas`, a importação de imagens em `pt-BR` já é disparada automaticamente ao confirmar — não é necessário repetir manualmente.

**Processo manual (este guia, abaixo)** — use apenas quando: a tela não está disponível ou não cobre o cenário (ex.: depuração direta, reprocessamento pontual de uma única coleção via SQL Editor/API); ou ao investigar um incidente que exige inspecionar/criar `asset_import_run` diretamente. O passo a passo abaixo reflete o que a tela faz por baixo dos panos.

---

# Guia Operacional (Processo Manual) — Como Importar uma Nova Coleção

Siga esta ordem. Cada etapa depende da anterior já estar confirmada no banco antes de prosseguir.

1. **Cadastrar a coleção em `card_set`** (código, nome, quantidade de cartas, `expansion_id`, `set_type`) — ver `../05-modelo-de-dados.md`, seção Set/Card Set.
2. **Cadastrar o mapeamento externo em `card_set_external_reference`** (`card_set_id`, `asset_source_id` = TCGdex, `external_set_id` — ex.: `me05` para uma futura `ME5`).
3. **Popular `card`** com as cartas da coleção (ver `../05-modelo-de-dados.md`, seção Card). A Edge Function só consulta esta tabela, nunca insere — precisa estar completa antes do passo 6.
4. **Popular `card_variant`** com as variantes/acabamentos de cada carta (ver `../05-modelo-de-dados.md`, seção Card Variant). Mesma exigência do passo 3.
5. **Escolher o idioma (`en` ou `pt-BR`).** Desde a Edge Function v2.9.0, o idioma é resolvido dinamicamente a partir de `asset_import_run.language_id` — não é mais uma constante fixa no código (`LANGUAGE_CODE`/`TCGDEX_LANGUAGE` foram removidas). Basta informar o idioma correto ao criar o `asset_import_run` (passo 6) — nenhuma alteração de código nem reimplantação é necessária para trocar de idioma.
6. **Criar um `asset_import_run`** para a coleção, com `run_type = 'FULL_CARD_SET'`, `status = 'PENDING'` e `language_id` resolvido a partir do código de idioma escolhido:

```sql
INSERT INTO public.asset_import_run (
    run_code, run_type, asset_source_id, card_set_id, status
)
SELECT
    'RUN-<AAAAMMDD>-<sequencial>', 'FULL_CARD_SET', s.id, cs.id, 'PENDING'
FROM public.asset_source s
JOIN public.card_set cs ON cs.code = '<CÓDIGO_DA_COLEÇÃO>'
WHERE s.code = 'TCGDEX';
```

7. **Invocar a Edge Function `import-card-assets`** com o `run_code` criado:

```json
{ "run_code": "RUN-<AAAAMMDD>-<sequencial>" }
```

8. **Conferir o resultado**: `success: true`, `images.failed: 0`. Se houver falhas, `failures[]` traz o motivo por carta, agrupado por causa quando consultado pela tela — não é necessário reprocessar a coleção inteira, apenas investigar as cartas listadas. O campo `status` de `asset_import_run` reflete o resultado real (`COMPLETED`/`COMPLETED_WITH_ERRORS`/`FAILED`).

**Tentativas e retomada**: uma única invocação pode não concluir uma coleção grande (teto de execução da plataforma, ~150s) — reinvocar a Edge Function com o mesmo `run_code` continua de onde parou (a função já pula cartas com imagem já importada, não reprocessa do zero). Pela tela, isso é automático (retry até `imagesFailed` chegar a `0` ou o progresso parar de avançar, com teto de segurança de tentativas). Se `success_count` permanecer `0` por várias cartas seguidas, é sinal de falha sistemática (ex.: instabilidade da fonte externa) — a tela interrompe cedo em vez de esperar o teto inteiro; pelo processo manual, o mesmo padrão deve ser observado antes de insistir em novas tentativas.

**Quando a coleção chega a 100%**: novas invocações do mesmo `run_code` (ou de uma run nova para a mesma coleção/idioma) não reprocessam imagens já importadas — o passo de sincronização e o laço de download já pulam cartas com `card_asset` presente.

**Consulta de logs**: os logs da Edge Function (visíveis via MCP do Supabase ou pelo painel do Supabase) registram uma entrada estruturada por tentativa de download (`IMAGE DOWNLOAD SUCCESS`/`IMAGE DOWNLOAD ATTEMPT FAILED`), com `externalCardId`/`collectorNumber`/`attempt`/`código do erro` — use-os para investigar falhas persistentes antes de reexecutar às cegas.

**Limitação de Card Sets que não existem na TCGdex**: quando a fonte externa não publica um Set (ex.: `MEE`/`MEP`, sets especiais de Energia/Promocional da Expansion `ME`), nem a tela nem este processo manual resolvem — a alternativa é a importação manual de arquivo local via `scripts/import-manual-assets.ts` (`source_code = 'MANUAL'`, fora do escopo desta Edge Function), documentada em `../05-modelo-de-dados.md`, seção Card Asset.

Não existe hoje nenhuma orquestração automática das 8 etapas do processo manual — cada uma é executada manualmente, uma de cada vez. A tela (`/catalogo/importar-imagens`) automatiza esse fluxo de ponta a ponta para os casos que ela cobre.

---

# Estado Atual (Confirmado) — Expansion `ME`, as 7 coleções originais

**Nota de escopo (2026-08-02)**: a tabela abaixo cobre apenas as 7 coleções da Expansion `ME`, mesmo escopo em que este documento sempre foi mantido. Card Sets incorporados depois via `ADR-024` (ingestão TCGdex, ex.: `SV1`–`SV5`) também usam esta mesma Edge Function para imagens, mas seu estado não é replicado aqui — ver o handoff vigente (`../development/`) ou `docs/README.md` para o estado agregado atual, evitando duplicar uma contagem que fica desatualizada a cada nova coleção importada.

| Item | Total | Situação |
|------|-------|----------|
| Coleções | 5 (`ME1`/`ME2`/`ME2.5`/`ME3`/`ME4`) | ✅ |
| Cartas editoriais | 859 | ✅ |
| Referências externas (`card_external_reference`) | 859 | ✅ (idioma-agnóstico — ver `../06-pipeline-importacao.md`) |
| Assets (`card_asset`) | 1.718 (859 `en` + 859 `pt-BR`) | ✅ |
| Imagens no Storage | 1.718 | ✅ |
| Falhas de importação | 0 | ✅ |
| `MEE` — referências externas (`en`) | 8/8 | ✅ (`RUN-20260724-00000041`) |
| `MEE` — imagens (`en`+`pt-BR`) | 16/16 | ✅ Importadas manualmente via `scripts/import-manual-assets.ts` (`source_code = 'MANUAL'`) — TCGdex não publica `image` para este Set (confirmado direto no CDN), gap de dados na fonte, não falha do pipeline. |
| `MEP` — referências externas (`en`) | 60/60 | ✅ (`RUN-20260724-00000061`) |
| `MEP` — imagens (`en`+`pt-BR`) | 0/120 | ⚠️ Mesmo gap de dados na TCGdex — resolução pela mesma via manual, ainda NÃO executada (hoje só há `13`/`60` de `en` salvas localmente; aguardando as duas pastas completas antes de rodar o script). |

---

# Revision History

| Versão | Descrição |
|---------|-----------|
| 1.0 | Documento criado a partir da separação de `06-pipeline-importacao.md` em três artefatos (arquitetura/processo, guia operacional, diário histórico), a pedido explícito de Fabrício, para reduzir o tamanho e melhorar a navegabilidade da documentação do pipeline. Conteúdo idêntico ao "Guia Operacional" e "Estado Atual" antes publicados em `06-pipeline-importacao.md`, versão `1.1`. |
| 1.1 | **Primeira execução real do pipeline além das 5 coleções originais: `MEE`, `en` (`RUN-20260724-00000041`).** Dois bugs de tipagem corrigidos em `import-card-assets` antes do deploy (v2.5.0) — `TcgdexClient.getSet()` retornava tipo genérico demais; `image_source_url` estava tipado como `string` obrigatório, divergindo da coluna real (nula, com `CHECK`). Resultado real: `card_external_reference` 8/8 importadas; imagens 0/8, bloqueadas porque a TCGdex ainda não publica o campo `image` para este Set (confirmado no endpoint de Set e de carta individual) — gap de dados na fonte, não falha do pipeline. "Estado Atual" atualizado com as linhas de `MEE`/`MEP`. |
| 1.2 | **`MEP` executada no mesmo dia (`RUN-20260724-00000061`, `en`), sem nenhuma mudança de código: 60/60 referências externas importadas, mesmas 0/60 imagens bloqueadas pelo mesmo gap real de dados na TCGdex.** Com isso, as sete Card Sets da Expansion `ME` têm referências externas 100% importadas; não há mais nenhuma coleção com execução pendente — falta apenas a TCGdex publicar os assets de `MEE`/`MEP`. "Estado Atual" atualizado com o resultado real de `MEP`. |
| 1.3 | **`MEE` imagens (`en`+`pt-BR`, 16/16) resolvidas por importação manual (`scripts/import-manual-assets.ts`) — confirmado que o asset genuinamente não existe no CDN da TCGdex, não é só ausência no campo `image` da API.** `MEP` segue com o mesmo gap, resolução pela mesma via ainda não executada. Passo 8 atualizado: a partir da v2.6.0 de `import-card-assets`, `asset_import_run.status` reflete o resultado real da execução — bug real corrigido (a coluna ficava presa em `PENDING` até esta versão, mesmo em execuções bem-sucedidas). Header **Status** atualizado para refletir o estado real por coleção. |
| 1.4 | **Auditoria de reconciliação documental (2026-08-02), a pedido de Fabrício.** Nova seção "Quando usar cada caminho": reconhece que a tela `/catalogo/importar-imagens` (e a continuação automática de `/catalogo/importar-cartas`) é hoje o caminho normal de importação de imagens — este guia manual passa a ser o caminho alternativo/de depuração, não o único processo existente (estava desatualizado desde a criação da tela). Passo 5 corrigido: idioma não depende mais de editar constantes no código (`LANGUAGE_CODE`/`TCGDEX_LANGUAGE` foram removidas na v2.9.0) — é só um parâmetro do `asset_import_run`. Passo 8 ampliado com tentativas/retomada, comportamento a 100%, consulta de logs, e limitação de Sets ausentes na TCGdex (referenciando a via manual de arquivo local). "Estado Atual" recebeu nota de escopo: cobre só a Expansion `ME`; Card Sets incorporados via `ADR-024`/TCGdex não são replicados aqui, para não duplicar uma contagem que fica desatualizada a cada nova coleção. |
