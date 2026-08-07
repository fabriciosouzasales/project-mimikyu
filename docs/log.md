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
