# PR-01 · G0 — Evidência histórica da 5361 v1.0 (`pg_stat_statements`)

| Campo | Valor |
|---|---|
| **Natureza** | Captura histórica, somente leitura. **Não é script executável** nem substitui nenhum arquivo SQL. |
| **Pendência** | PR-01 (reconciliação das migrations S1–S4 do V1-16), gate G0 (`PR-01 \| G0 HISTORICAL EVIDENCE PRESERVATION-01`). |
| **Migration** | 5361 — `physical_card.condition_code` (V1-16 · S1), versão **1.0**. |
| **Origem** | `extensions.pg_stat_statements` do LIVE `mimikyu-core` (projeto `qjfutqujxrbzgrtkpgkg`), lida por `SELECT` em 2026-11-13 (`PR-01 \| MIGRATION RECONCILIATION DIAGNOSIS-01`). Nenhuma escrita. |
| **Arquivo** | `rows.json` — 7 registros `{md5, query}`; `md5` = `md5(query)` calculado **pelo próprio banco** na leitura. |

## Contexto

A 5361 v1.0 foi submetida pelo proprietário no SQL Editor do Supabase em 2026-11-13. A execução terminou com `42P01 relation "_v116_s1_before" does not exist` no postcheck; o diagnóstico somente leitura classificou o resultado como **D2** (DDL persistida, postcheck não rodou) — ver `../../CONTROLLED-EXECUTION-PROTOCOL.md` §11. O texto exato do arquivo v1.0 não foi versionado. A v1.1 (`../../5361_add_physical_card_condition_code.sql`) foi escrita depois e **não foi executada**.

## Os sete comandos recuperados

Ordem do arquivo = ordem de leitura (alfabética pelo texto), **não** a ordem de execução. Todos com `calls = 1`.

| md5 (`md5(query)`) | Bytes | Comando |
|---|---|---|
| `0c785002f91351595df817e960c81259` | 88 | `alter table … add column condition_code text not null default 'NM'` |
| `79ee6347a4b487f823fe249380feec80` | 207 | `alter table … add constraint fk_physical_card_condition_code … not valid` |
| `d0aa5c5dec8faaee871e4471d66ddebb` | 87 | `alter table … validate constraint fk_physical_card_condition_code` |
| `dd0ccbff5c7edcec0c5106aa89c4adaf` | 383 | `comment on column public.physical_card.condition_code is '…'` |
| `22c0ddaaedc93aa579c4431280d57ea8` | 498 | `create temp table _v116_s1_before on commit drop as …` (baseline) |
| `5d12aab68dbdb8a48457f1d98a659116` | 988 | `do $post$ …` (postcheck que falhou com 42P01) |
| `acf52fdc59b01bbc0cc316fe39c7a3bd` | 2039 | `do $pre$ …` (precheck) |

Os textos estão **integrais e sem normalização** no JSON, inclusive o fim de linha original CRLF (`\r\n`, escapado em JSON). Não há arquivos `.sql` separados de propósito: `.gitattributes` converteria CRLF para LF em `*.sql` e os hashes deixariam de bater.

## Como verificar

```bash
python3 -c "import json,hashlib;r=json.load(open('rows.json',encoding='utf8'));print(len(r), all(hashlib.md5(x['query'].encode('utf8')).hexdigest()==x['md5'] for x in r))"
# esperado: 7 True
sha256sum -c SHA256SUMS
```

## Limitações

- **Parcial.** `pg_stat_statements` guarda só os comandos que concluíram. Ficam de fora os comentários de cabeçalho, `begin`/`commit`, `SET LOCAL` e qualquer texto entre comandos. Não há horário nem ordem de execução.
- **Não prova o arquivo v1.0 inteiro.** Prova o texto destes sete comandos como recebidos pelo banco.
- **Transcrição verificada.** `rows.json` foi gravado a partir da resposta da leitura e aceito só porque os sete `md5` recalculados localmente batem com os `md5` calculados pelo banco. Nada foi reconstruído da transcrição da sessão nem completado à mão.
- **Volátil na origem.** Em 2026-11-13 a view tinha 4.912 de 5.000 entradas; estas, com `calls = 1`, são as primeiras a serem descartadas. A origem pode não existir mais.

## Captura × v1.0 × v1.1

| | O que é | Executado |
|---|---|---|
| Esta captura | Sete comandos da v1.0, como o banco os recebeu | Sim (é o registro da execução) |
| Script 5361 v1.0 | Arquivo submetido no SQL Editor | Sim, com falha no postcheck (D2); **arquivo não preservado** |
| `5361_add_physical_card_condition_code.sql` v1.1 | Forma canônica proposta: um único `DO` | **Não** |

Comparação feita no diagnóstico (espaços normalizados): ADD COLUMN, ADD CONSTRAINT, VALIDATE e COMMENT aparecem iguais na v1.1; baseline, precheck e postcheck da v1.0 foram reestruturados na v1.1 (variáveis no lugar da tabela temporária). Equivalência de DDL **não** é identidade textual do script.
