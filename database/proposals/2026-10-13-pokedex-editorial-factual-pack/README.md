# Pokédex — Pacote factual para produção editorial pt-BR (965 espécies)

| Campo | Valor |
|---|---|
| Data | 2026-10-13 |
| Status | **ENCERRADO (2026-10-13)** — 965 espécies extraídas em 10 arquivos JSON, fidelidade ao LIVE verificada, pacote entregue à operação editorial paralela (Frente B, `ADR-011` v1.5). Nenhuma alteração no banco. |
| Origem | LIVE (`qjfutqujxrbzgrtkpgkg`), consultas exclusivamente de leitura |
| Escopo | Espécies sem conteúdo `MMKYU_EDITORIAL` pt-BR publicado (1.025 − 60 = 965) |

## O que foi extraído

Somente o que existe armazenado, sem enriquecimento:

| Campo no pacote | Origem no banco |
|---|---|
| `national_dex_number` | `pokemon_species.national_dex_number` |
| `canonical_name` | `pokemon_species.canonical_name` |
| `genus.content` | `pokemon_species_text` (`text_kind = GENUS`, `origin = SOURCE`) |
| `flavor.content` | `pokemon_species_text` (`text_kind = FLAVOR`, `origin = SOURCE`) |
| `*.language_code` | `pokemon_species_text.language_code` (sempre `en`) |
| `*.source_version` | `pokemon_species_text.source_version` |
| `*.content_md5` | `md5(content)`, idêntico ao `md5()` do Postgres — só para conferência de fidelidade |

Textos copiados exatamente como armazenados: sem tradução, correção, normalização tipográfica ou reformulação.

## Arquivos

| Arquivo | Nº nacional | Espécies |
|---|---|---|
| `pokedex-source-texts-en-01-0002-0109.json` | 2–109 | 100 |
| `pokedex-source-texts-en-02-0110-0218.json` | 110–218 | 100 |
| `pokedex-source-texts-en-03-0219-0322.json` | 219–322 | 100 |
| `pokedex-source-texts-en-04-0323-0428.json` | 323–428 | 100 |
| `pokedex-source-texts-en-05-0429-0536.json` | 429–536 | 100 |
| `pokedex-source-texts-en-06-0537-0637.json` | 537–637 | 100 |
| `pokedex-source-texts-en-07-0638-0747.json` | 638–747 | 100 |
| `pokedex-source-texts-en-08-0748-0850.json` | 748–850 | 100 |
| `pokedex-source-texts-en-09-0851-0956.json` | 851–956 | 100 |
| `pokedex-source-texts-en-10-0957-1024.json` | 957–1024 | 65 |
| **Total** | | **965** |

`index.json` traz a relação dos arquivos, contagens, sha256 de cada arquivo, fingerprints do LIVE, as 60 espécies excluídas e as ausências/observações abaixo. Pacote total ≈ 640 KB.

## Verificações

| Verificação | Resultado | Como |
|---|---|---|
| Total extraído | 965 (= 1.025 − 60) | automático |
| Duplicidade de espécie | 0 | automático |
| Ordenação por número nacional | OK | automático |
| Espécies publicadas presentes | 0 de 60 (as 60 + as 965 cobrem 1–1025 sem lacuna) | automático |
| Fidelidade ao LIVE | fingerprint de cada um dos 10 arquivos e o global (`f5669eba65c187755d96cea226bb1517`) iguais aos calculados no LIVE | automático, recalculado a partir dos arquivos finais |
| `content_md5` × conteúdo | 1.930/1.930 conferem | automático |
| Unicode NFC | 100% NFC | automático |
| LIVE inalterado | `pokemon_species_text` = 2.170 linhas (2.050 SOURCE + 120 editoriais) | leitura |

Fórmula do fingerprint (executada igual no LIVE e localmente): `md5(string_agg(n||'|'||canonical_name||'|'||md5(genus)||'|'||md5(flavor)||'|'||flavor.source_version, E'\n' order by n))`.

## Ausências e inconsistências

- **`genus.source_version` ausente (NULL) nas 965 classificações.** Mantido `null`; não foi inferido.
- **Não há texto de origem em pt-BR**: somente `en`.
- Nenhum `genus` ou `flavor` vazio; todas as 965 espécies têm exatamente 1 GENUS e 1 FLAVOR de origem.
- **Mesmo `flavor` em três espécies**: #795 Pheromosa, #797 Celesteela, #798 Kartana (texto genérico de Ultra Beast).
- **Tipografia do original preservada como está**:
  - espaço após travessão/hífen em #26, #92, #183, #457, #526, #588 (ex.: "water- repellent");
  - citação aberta com aspa de fechamento `”` em #198, #390, #456, #501, #904.
- Distribuição de `flavor.source_version`: shield 437 · legends-arceus 220 · violet 114 · alpha-sapphire 104 · ultra-moon 63 · lets-go-eevee 27.

## Como compartilhar com o ChatGPT

1. Envie **um arquivo de parte por conversa/rodada** (≈ 64 KB cada), mais `index.json` se quiser que ele confira a contagem.
2. Junto, envie as regras editoriais vigentes **sem reescrevê-las**: guia v0.2, glossário e `editorial_rules` de `../2026-10-12-pokedex-p3e-editorial-lote-01/lote-01-pt-BR.json`.
3. Instrua o ChatGPT a:
   - usar `genus.content` e `flavor.content` apenas como base factual, nunca traduzir literalmente nem acrescentar fatos externos;
   - devolver cada entrada no formato de entrada do `lote-01-pt-BR.json`, com `source_basis.flavor_version` = `flavor.source_version`, `source_basis.flavor_md5` = `flavor.content_md5` e `source_basis.genus_md5` = `genus.content_md5` copiados deste pacote.
4. O retorno passa pelo validador `scripts/editorial/validate-editorial-lot.ts` antes de qualquer aprovação; o `md5` de origem acusa deriva caso o LIVE mude.

## Encerramento da extração (2026-10-13)

| Item | Registro |
|---|---|
| Espécies extraídas | 965 (1.025 − 60 publicadas), sem duplicidade |
| Arquivos | 10 JSON (`pokedex-source-texts-en-01…10`) + `index.json` |
| Fidelidade ao LIVE | verificada por fingerprint de cada arquivo e global, recalculados a partir dos arquivos finais |
| Fingerprint consolidado | `f5669eba65c187755d96cea226bb1517` |
| Destino | entregue à operação editorial pt-BR paralela (Frente B), conforme `docs/adr/ADR-011-pokemon-tcg-domain-scope.md` v1.5 |
| Banco | nenhuma escrita; LIVE com 2.170 linhas em `pokemon_species_text` (2.050 SOURCE + 120 editoriais) |

Os arquivos de dados são imutáveis a partir deste encerramento: correções ou reextrações geram um pacote novo, nunca a edição destes. Lotes editoriais produzidos a partir deste pacote vivem em pastas próprias e conferem o `md5` de origem contra o LIVE no momento da validação.

## Limites respeitados

Nenhum SQL de escrita, migration, função, tabela, alteração de frontend, texto editorial novo ou Query de publicação. Os 60 editoriais publicados não foram tocados. Sem `git add`/commit/push.
