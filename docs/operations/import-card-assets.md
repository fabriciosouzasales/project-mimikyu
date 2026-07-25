# Operação — Importar uma Nova Coleção (`import-card-assets`)

| Campo | Valor |
|--------|-------|
| **Documento** | Operação — Importar uma Nova Coleção |
| **Arquivo** | `docs/operations/import-card-assets.md` |
| **Versão** | 1.3 |
| **Status** | Ativo — processo confirmado por execução real (7 coleções; referências externas 100%; imagens completas para 6 — `ME1`-`ME4`/`ME2.5` via pipeline, `MEE` via importação manual —, `MEP` pendente, ver "Estado Atual"). |
| **Objetivo** | Guia operacional passo a passo para importar uma nova coleção (referências externas + imagens) usando a Edge Function `import-card-assets`. |
| **Escopo** | Apenas o "como fazer". Para arquitetura, decisões de design e racional, ver `../06-pipeline-importacao.md`. Para o histórico de como o pipeline chegou a este estado, ver `../history/pipeline-sprint-log.md`. |
| **Dependências** | `../06-pipeline-importacao.md`, `../05-modelo-de-dados.md` |

---

# Guia Operacional — Como Importar uma Nova Coleção

Siga esta ordem. Cada etapa depende da anterior já estar confirmada no banco antes de prosseguir.

1. **Cadastrar a coleção em `card_set`** (código, nome, quantidade de cartas, `expansion_id`, `set_type`) — ver `../05-modelo-de-dados.md`, seção Set/Card Set.
2. **Cadastrar o mapeamento externo em `card_set_external_reference`** (`card_set_id`, `asset_source_id` = TCGdex, `external_set_id` — ex.: `me05` para uma futura `ME5`).
3. **Popular `card`** com as cartas da coleção (ver `../05-modelo-de-dados.md`, seção Card). A Edge Function só consulta esta tabela, nunca insere — precisa estar completa antes do passo 6.
4. **Popular `card_variant`** com as variantes/acabamentos de cada carta (ver `../05-modelo-de-dados.md`, seção Card Variant). Mesma exigência do passo 3.
5. **Conferir o idioma desejado contra o estado atual do código.** `index.ts` usa `LANGUAGE_CODE`/`TCGDEX_LANGUAGE` como constantes fixas, não parâmetros — ver `../06-pipeline-importacao.md`, seção "Arquitetura Final", "⚠️ Limitação real atual", para o estado publicado e como trocar de idioma. Se for diferente do que está publicado, atualizar as constantes e reimplantar antes de prosseguir.
6. **Criar um `asset_import_run`** para a coleção, com `run_type = 'FULL_CARD_SET'` e `status = 'PENDING'`:

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

8. **Conferir o resultado**: `success: true`, `images.failed: 0`. Se houver falhas, `failures[]` traz o motivo por carta — não é necessário reprocessar a coleção inteira, apenas investigar as cartas listadas. A partir da v2.6.0, o campo `status` de `asset_import_run` também reflete o resultado real (`COMPLETED`/`COMPLETED_WITH_ERRORS`/`FAILED`) — antes desta versão, ficava sempre em `PENDING`, mesmo em execuções bem-sucedidas (bug real corrigido, ver `../05-modelo-de-dados.md`, seção "Correção real: máquina de estados nunca escrita").

Não existe hoje nenhuma orquestração automática destas 8 etapas — cada uma é executada manualmente, uma de cada vez.

---

# Estado Atual (Confirmado)

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
