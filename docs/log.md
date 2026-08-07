# Log

| Campo | Valor |
|--------|-------|
| **Documento** | Log Cronológico |
| **Arquivo** | `docs/log.md` |
| **Versão** | 1.0 |
| **Status** | Aprovado |
| **Objetivo** | Registro cronológico enxuto, uma linha por evento, de tudo que acontece no projeto — implementações, correções, mudanças de documentação e auditorias. Formato pensado para ser `grep`-ável (`grep "^## \[" docs/log.md | tail -10`), não para conter o detalhe completo. |
| **Escopo** | Todo o projeto. O detalhe de cada entrada mora no documento normativo correspondente (Revision History do documento afetado, ADR, handoff) — este arquivo só aponta para lá. |

---

## Nota de criação (2026-08-06)

Este arquivo nasce como parte da adequação do projeto ao padrão LLM Wiki (Andrej Karpathy) — ver `CLAUDE.md`. **Não é um backfill retroativo**: o histórico anterior a 2026-08-06 já está integralmente preservado nas tabelas de Revision History de cada documento (`docs/05-modelo-de-dados.md` sozinho tem 52 entradas) e não foi reescrito linha a linha aqui, para evitar perda de contexto num processo de resumo mecânico. A partir desta data, toda entrada nova de Revision History em qualquer documento também gera uma linha aqui.

Formato: `## [AAAA-MM-DD] tipo | Resumo curto`. Tipos: `ingest` (fonte/decisão nova incorporada), `fix` (correção real), `feature` (implementação nova), `docs` (mudança só de documentação), `lint` (auditoria de consistência).

---

## [2026-08-02] feature | Favicon do app com o mascote (Mimikyu)

Ícone da aba do navegador usando a marca oficial (`web/public/brand/icon-mark-*.png`), com variante clara/escura via `prefers-color-scheme`. Ver `web/app/layout.tsx`.

## [2026-08-02] docs | Auditoria de reconciliação documental completa

Reconciliação de `README.md`, `docs/**/*.md` e `database/README.md` contra o estado real do repositório — corrigidas contagens desatualizadas, pendência de rarity resolvida sinalizada, novo handoff vigente criado. Ver `docs/05-modelo-de-dados.md` revisão `1.51` e `docs/development/HANDOFF-2026-08-02.md`.

## [2026-08-02] docs | Remoção de artefatos de sessão do rastreamento Git

`.agents/` e `.codex/` (cache local de ferramentas de IA, criados sem intenção) removidos do Git via `git rm -r --cached` e adicionados ao `.gitignore` — nunca deveriam ter sido versionados.

## [2026-08-06] fix | Query 830 v1.6 — nova raridade Rara Preto e Branco

Gap real na importação (Victini 171/86, Zekrom ex 172/86): raridade `BLACK_WHITE_RARE` cadastrada, símbolo `BLACK_WHITE_STAR` novo (primeiro símbolo do catálogo com preenchimento não uniforme — 1 estrela cheia + 1 vazia), `RaritySymbol` generalizado com `emptyCount`. Ver `docs/05-modelo-de-dados.md` revisão `1.52`.

## [2026-08-06] docs | Adequação ao padrão LLM Wiki

A pedido de Fabrício, avaliação da documentação do projeto contra o padrão LLM Wiki (gist de Andrej Karpathy) e execução dos 4 itens de adequação aprovados: `CLAUDE.md` (schema versionado), `docs/log.md` (este arquivo), `docs/INDEX.md` (catálogo único) e divisão de `docs/05-modelo-de-dados.md` em páginas menores por área.

## [2026-08-06] docs | Fallback de idioma pt→en documentado (import-catalog-cards)

Modificação manual de Fabrício em `index.ts`/`normalize.ts` (commit "Implementação de FALLBACK_LANGUAGE", 2026-08-05), sem documentação até agora: coleções nunca publicadas em português na TCGdex agora caem automaticamente para inglês na busca de cartas. Ver `adr/ADR-024-catalog-card-ingestion-strategy.md` revisão `1.1`, emenda 2026-08-05.

## [2026-08-06] feature | Encadeamento PT-BR → EN na importação automática de imagens

Pedido de Fabrício: a continuação automática cartas→imagens (`useAnalyzeJob`) agora tenta `en` automaticamente depois de `pt-BR`, cobrindo coleções sem cobertura em português na TCGdex sem exigir retomada manual em `/catalogo/importar-imagens?idioma=en`. `ImportProgress` passou a mostrar um resultado por idioma tentado. Ver `adr/ADR-024-catalog-card-ingestion-strategy.md` revisão `1.1`, emenda 2026-08-06.

## [2026-08-07] feature | Revalidação self-service de linhas de staging (Ciclo Raridade)

Edge Function `revalidate-catalog-import-rows` (JWT verificado na própria função, `svc_apply_catalog_import_revalidation` Query 2106 v1.2) recalcula `catalog_import_row` já staged depois de um mapeamento de raridade ser cadastrado/corrigido, sem reimportar do zero — escopo ampliado no mesmo dia para cobrir jobs `COMPLETED_WITH_ERRORS` (não só `STAGED`), caminho real observado em produção (GYM1/SWSH1 com linhas `FAILED` por raridade não mapeada). Validado ponta a ponta contra o job GYM1: 34 linhas destravadas e persistidas como Card, `decision_status` preservado em todas as 132 linhas, `actor_id` real (não NULL) gravado em `catalog_admin_action_log`. Documentação normativa (ADR/modelo de dados) ainda pendente — task #337. Descoberta em aberto durante a validação: 19 jobs em `COMPLETED_WITH_ERRORS` no total (não só GYM1/SWSH1), vários duplicados por Coleção — não tratado nesta rodada.

## [2026-08-07] fix | GRANTs faltantes em rarity_external_mapping e catalog_import_row

Duas lacunas reais de `GRANT SELECT`, cada uma travando um fluxo diferente: `rarity_external_mapping` sem SELECT para `service_role`/`authenticated` (Query 2096 nunca concedeu — bloqueava reimportação de GYM1/SWSH1) e `catalog_import_row` sem SELECT para `service_role` (nunca precisou até a revalidação existir). Corrigidas via GRANT direto, sem mudança de schema.

## [2026-08-07] fix | Raridade RARE_HOLO cadastrada

Primeiro cadastro real via `admin_create_rarity_with_external_mapping()` (Query 2103) — `RARE_HOLO`/"Rara Holo", símbolo `BLACK_STAR`, mapeamento TCGdex "Rare Holo". Usado para validar a revalidação self-service com dado real, não sintético.

## [2026-08-07] fix | Limpeza de jobs COMPLETED_WITH_ERRORS duplicados (Query 2111)

16 jobs de importação em `COMPLETED_WITH_ERRORS` cobrindo 8 Coleções (BASE1, BASEP, GYM1, GYM2, SV1, SV4.5, SV5, SWSH1) — cada duplicata era uma nova tentativa de "Analisar" na mesma Coleção depois que a anterior terminou em erro (`admin_start_catalog_import()` só bloqueia fingerprint duplicado enquanto o job anterior está ativo, não depois de terminal). Mantido só o job mais recente por Coleção (8 apagados via `ON DELETE CASCADE` em `catalog_import_row`; nenhuma Card afetada, auditoria preservada). Decisão de Fabrício, antes da task #336 (frontend de Raridade) nascer com um botão único "revalidar tudo" em vez de job por job.

## [2026-08-07] feature | Tela /catalogo/raridades (task #336)

Cadastro/edição de raridades canônicas, mapeamento de valores externos (vincular a raridade existente ou cadastro atômico de raridade nova) e botão único "Revalidar tudo" (chama `revalidate-catalog-import-rows` sem `job_ids` — todos os jobs elegíveis de uma vez, decisão de Fabrício). Substitui o antigo fluxo de editar `RARITY_NAME_ALIASES` no código-fonte. Dois bugs reais corrigidos no mesmo ciclo: (1) `asset_source` tinha RLS ativado sem nenhuma política (`GRANT` sozinho não bastava — Query 2113, emenda à Query 274, que já sinalizava essa lacuna deliberadamente em 2026-07-26); (2) o modo do Dialog "Resolver raridade" ("Nova raridade" vs "Raridade existente") não resetava entre aberturas, ficando preso na última escolha. Novo símbolo `WHITE_STAR` (estrela vazada, sem preenchimento) em `RaritySymbol`, para a raridade `RARE_HOLO_V`/"Holo Rara V" (pedido de Fabrício). Terceiro bug real corrigido no mesmo dia: o botão "Revalidar tudo" nunca chamava `router.refresh()` após concluir — a Server Action resolvia tudo certinho no banco, mas a lista de pendências na tela ficava presa no estado anterior, levando Fabrício a tentar "Resolver" de novo um valor que já tinha mapeamento (erro de duplicata, não um bug de dado). Documentação normativa (ADR/modelo de dados) ainda pendente — task #337.

## [2026-08-07] feature | Tela de edição de Card (ADR-023, emenda)

Fabrício encontrou duas cartas cadastradas com a raridade errada e pediu uma tela de edição de Card, mesmo padrão de ação rápida já usado em Coleções: botão "editar" no canto inferior direito de cada carta do grid (`/catalogo/cartas`), abrindo `EditCardDialog` com Nome, Total, Ordem editorial, Raridade e Categoria. `card_set_id` e `collector_number` ficam de fora — estruturalmente protegidos desde a redação original do ADR-023 ("mudar identidade não é o mesmo que corrigir conteúdo"); o Número aparece só como texto no cabeçalho do Dialog, ao lado da Coleção. Implementa `admin_update_card()` (Query 2114, ADR-023 emenda 2026-08-07) — proposta, aguardando execução e confirmação de Fabrício; frontend já com a fiação completa.

## [2026-08-07] docs | Fechamento documental — Raridade self-service + edição de Card (task #337)

Query 2114 confirmada executada e validada funcionalmente por Fabrício via UI. Escrito o backlog de 21 arquivos canônicos (`database/schema/2094`–`2106`,`2114`; `database/migrations/2098`,`2104`,`2110`–`2113`) que haviam sido executados em produção ao longo do dia sem o arquivo correspondente — reconstruídos a partir do estado real lido em produção (`pg_get_functiondef()`/`pg_get_constraintdef()`/dados reais), nunca da memória de sessão, conforme `CLAUDE.md`. `adr/ADR-024-catalog-card-ingestion-strategy.md` revisão `1.2` (nova emenda "Raridade: mapeamento self-service e revalidação"), `05e-catalogo-editorial.md` (nova seção própria + Sequência), `docs/INDEX.md` e `docs/README.md` revisão `1.70` atualizados. Fecha a pendência de documentação normativa sinalizada nas três entradas anteriores deste log (revalidação, RARE_HOLO/limpeza de jobs, tela `/catalogo/raridades`).

## [2026-08-07] feature | Card: cadastro e desativação/reativação real via UI (ADR-023, subciclo Card fechado)

Pedido explícito de Fabrício, mesmo dia da Query 2114: "Vamos avançar com o Resto do subciclo `Card` — criação e desativação/reativação administrativa". `admin_create_card()` (Query 2115), `admin_deactivate_card()` (2116), `admin_reactivate_card()` (2117) confirmadas executadas e validadas funcionalmente (validação 2817, 15 cenários). `admin_create_card()` valida consistência de Game entre Raridade/Categoria e Card Set antes de `internal.write_card()`; duplicidade de número/ordem checada contra Cards ativas e inativas. Descoberta real durante a validação: `GRANT EXECUTE ... TO authenticated` não revoga o `EXECUTE` implícito herdado de `PUBLIC` — `anon` tinha acesso indevido à Query 2115 até o `REVOKE ALL ... FROM PUBLIC/anon` explícito ser adicionado; aplicado desde o início às duas funções seguintes. Auditoria retroativa do mesmo gap nas demais funções `admin_*` do módulo adiada por decisão de Fabrício (item futuro separado). Frontend: `getCartasCompletas()` ganhou `incluirInativas`, toggle "Mostrar inativas" na galeria (opção escolhida por Fabrício entre as apresentadas), `NewCardDialog` (botão "Nova Carta", `collector_total` pré-preenchido do Card Set, `collector_order` sugerido), `DeactivateCardDialog` (confirmação com linguagem de ação reversível, distinta de `ConfirmDeleteBar`), botões Editar+Desativar (Card ativa) / Editar+Reativar (Card inativa) no grid. Ver `adr/ADR-023-catalog-editorial-write-authorization.md` revisões `1.7`/`1.8` (a `1.7`, atualização de Card via Query 2114, registrada retroativamente na mesma auditoria — estava ausente da Revision History apesar de já implementada) e `05e-catalogo-editorial.md`. Com esta rodada, o subciclo `Card` (create+update+deactivate+reactivate) deste ADR está integralmente implementado, backend e frontend.
