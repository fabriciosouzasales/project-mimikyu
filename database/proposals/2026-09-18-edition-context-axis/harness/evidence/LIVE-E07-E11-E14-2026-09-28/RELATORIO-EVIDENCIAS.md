# Evidência LIVE — E07, E08, E09, E10, E11 e E14 (2026-09-28)

| Campo | Valor |
|---|---|
| Objetivo | Preservar no repositório a evidência primária dos `elapsed_ms` LIVE de E07–E11 e E14 (BR-2 do P9(b)′), para que a prova não dependa do histórico local de sessão nem dos uploads. |
| Mandato | `BATCH12-PHASE6-A2-P9B-BR2-EVIDENCE-PRESERVATION-01` (readiness em `…-BR2-EVIDENCE-READINESS-01`, **PASS BY ADJUDICATION**). |
| Escopo | Só preservação: bytes originais copiados sem alteração. Nenhum SQL, nenhum acesso ao LIVE, nada reexecutado. |
| Conteúdo | `MANIFEST.md5`, `.gitattributes` (`raw/** -text`) e `raw/`: 10 registros `.jsonl` (cinco pares chamada → resultado) e 1 PNG. Total: 403.553 bytes. |
| Estado | **BR-2 = CLOSED por auditoria independente em 2026-10-03** (`BATCH12-PHASE6-A2-P9B-BR2-EVIDENCE-CLOSEOUT-01`). P9(b) v7.0 continua **NOT SATISFIED AS WRITTEN**. P9(b)′ não está fechado por este artefato. |

## 1. Mapa envelope → evidência → `elapsed_ms`

| Envelope | Classe da evidência | Arquivo(s) em `raw/` | Terminal | `elapsed_ms` |
|---|---|---|---|---|
| E07 | DIRECT PRIMARY TOOL EVIDENCE | `E07_call.jsonl` + `E07_result.jsonl` | `H283P`, `E07_GAME_SENTINELA_2_6_3_3`, `pass=2/2` | **119** |
| E08 | DIRECT PRIMARY TOOL EVIDENCE | `E08_call.jsonl` + `E08_result.jsonl` | `H283P`, `E08_SECAO4_IDENTIDADE_CARD_VARIANT`, `pass=8/8` | **146** |
| E09 | DIRECT PRIMARY TOOL EVIDENCE | `E09_call.jsonl` + `E09_result.jsonl` | `H283P`, `E09_SECAO_S_STAGING`, `pass=12/12` | **167** |
| E10 | DIRECT PRIMARY OUTPUT EVIDENCE | `E10_sql_editor.png` | `H283P`, `E10_SECAO_R_ROUTING_2211`, `pass=12/12` | **258** |
| E11 | DIRECT PRIMARY TOOL EVIDENCE | `E11_call.jsonl` + `E11_result.jsonl` | `H283P`, `E11_SECAO_K_CONFIRM_ESTATICO`, `pass=3/3` | **65** |
| E14 | DIRECT PRIMARY TOOL EVIDENCE | `E14_call.jsonl` + `E14_result.jsonl` | `H283P`, `E14_SECAO_G_GUARD_2214`, `pass=8/8` | **420** |

Em todos, `elapsed_ms` é o relógio do servidor dentro do bloco DO, emitido pelo `RAISE` terminal de sucesso. O SQLSTATE `H283P` desfaz a transação de propósito. Não foi usado tempo de cliente, tempo de parede nem `statement_timeout`.

## 2. E07, E08, E09, E11 e E14 — DIRECT PRIMARY TOOL EVIDENCE

**Fonte.** Registros brutos originais da ferramenta `execute_sql` do conector Supabase (servidor `supabase` 0.13.0), persistidos no JSONL da sessão em que o agente executou os envelopes no LIVE. Cada arquivo `.jsonl` em `raw/` é **uma linha do JSONL original, copiada byte a byte** (incluindo o LF final), sem reserializar nem formatar. A origem exata (arquivo e número da linha) está no `MANIFEST.md5`.

Só os registros brutos de chamada (`tool_use`) e de resultado (`tool_result`) são evidência. O histórico narrativo da sessão **não** é prova e não foi preservado.

**Vínculo chamada → resultado.** Para cada par, três ligações independentes, todas verificadas:

1. `tool_result.tool_use_id` = `tool_use.id`;
2. `parentUuid` do resultado = `uuid` da chamada;
3. `sourceToolAssistantUUID` do resultado = `uuid` da chamada.

| Envelope | `tool_use.id` | Chamada (UTC) | Resultado (UTC) | Projeto | md5 do SQL submetido = md5 do canônico |
|---|---|---|---|---|---|
| E11 | `toolu_01U1kHbBoLEmwegVN4yxdvcg` | 02:52:42.694 | 02:52:46.744 | `qjfutqujxrbzgrtkpgkg` | `9ddaf49cfdec5e045737178aefe0011c` = `../../2830H_E11_section_k_confirm_static.sql` |
| E07 | `toolu_01RJr5MFewtzG2myQrpEaRUY` | 03:07:53.962 | 03:07:57.870 | `qjfutqujxrbzgrtkpgkg` | `8a31b5a6d37dd164a3df96a4a2fade7e` = `../../2830H_E07_game_sentinel_2_6_3_3.sql` |
| E08 | `toolu_01PEd7tdMc9GchDX1w6Ed327` | 03:15:04.453 | 03:15:08.973 | `qjfutqujxrbzgrtkpgkg` | `237468822d1298ea49d7e141f74500d9` = `../../2830H_E08_section4_card_variant_identity.sql` |
| E14 | `toolu_01Gg2mpS9iwuPWiuiK29yiUe` | 03:23:02.211 | 03:23:07.026 | `qjfutqujxrbzgrtkpgkg` | `28bc469d08a07004033a254f48fddd30` = `../../2830H_E14_section_g_guard_2214.sql` |
| E09 | `toolu_01NZaCDRYArydySmygqUWHsL` | 03:32:06.983 | 03:32:12.259 | `qjfutqujxrbzgrtkpgkg` | `e4266fd60f92eb5cdb5f8611adfb38e5` = `../../2830H_E09_section_s_staging.sql` |

O md5 é do campo `query` de `tool_use.input`, codificado em UTF-8. A cópia do mesmo SQL em `wireToolInputs`, no mesmo registro, é idêntica. A **identidade dos bytes do SQL executado está provada criptograficamente** contra o artefato versionado (commit `696caed`).

**Terminais literais** (campo `content` do `tool_result`, com `is_error = true`, que é o caminho esperado do `H283P`):

```
E11: ERROR:  H283P: H2830_ROLLBACK_PASS: envelope=E11_SECAO_K_CONFIRM_ESTATICO pass=3/3 casos=K3,K4,K8 marker=H2830_02B450E2A5154A41951446A135517462 elapsed_ms=65 confirm_md5=b83f7708ca2b7498b753b394d768f66e
     CONTEXT:  PL/pgSQL function inline_code_block line 260 at RAISE
E07: ERROR:  H283P: H2830_ROLLBACK_PASS: envelope=E07_GAME_SENTINELA_2_6_3_3 pass=2/2 casos=2.6,3.3 marker=H2830_B5D6D4264D444B98B3636F1C45B1D3BF elapsed_ms=119
     CONTEXT:  PL/pgSQL function inline_code_block line 234 at RAISE
E08: ERROR:  H283P: H2830_ROLLBACK_PASS: envelope=E08_SECAO4_IDENTIDADE_CARD_VARIANT pass=8/8 casos=4.1,4.2,4.3,4.4,4.5,4.6,4.7,4.8 marker=H2830_A12C1B7A5B884413ADF94BF470FACCD1 elapsed_ms=146
     CONTEXT:  PL/pgSQL function inline_code_block line 639 at RAISE
E14: ERROR:  H283P: H2830_ROLLBACK_PASS: envelope=E14_SECAO_G_GUARD_2214 pass=8/8 casos=G1,G2,G3,G4,G5,G6,G7,G8 marker=H2830_351F58E56EF34350BDA4B7F27BC8EFC0 elapsed_ms=420
     CONTEXT:  PL/pgSQL function inline_code_block line 741 at RAISE
E09: ERROR:  H283P: H2830_ROLLBACK_PASS: envelope=E09_SECAO_S_STAGING pass=12/12 casos=S1,S2,S2-BIS,S3,S4,S5,S6,S7,S8,S9,S10,S11 marker=H2830_66C992E1E8564D289216913441A802FB elapsed_ms=167
     CONTEXT:  PL/pgSQL function inline_code_block line 1148 at RAISE
```

## 3. E10 — DIRECT PRIMARY OUTPUT EVIDENCE

**Fonte.** Captura de tela do SQL Editor do Supabase feita por Fabrício, que executou o E10 uma única vez em 2026-09-28. O arquivo original do upload foi copiado byte a byte: 17.913 bytes, md5 `e43061640c0d37fa920cfd5c3bf7a523`, SHA-256 `fa1bd3a2a9e49125484ad72b7a4242c1496bc831e4daece1326b91aa61d1ca72`, mtime 2026-09-28T13:33:36Z. O PNG só tem chunks de imagem (`IHDR`, `sRGB`, `gAMA`, `pHYs`, `IDAT`, `IEND`), sem metadados de texto.

**Conteúdo visível (prova direta da saída):** `ERROR: H283P: H2830_ROLLBACK_PASS:`, `envelope=E10_SECAO_R_ROUTING_2211`, `pass=12/12`, `casos=R1,R2,R3,R4,R5,R6,R7,R8,R9,R10,R11,R12`, `marker=H2830_18D4DA2EA52E4DAF819FA467EBC4EEB8`, **`elapsed_ms=258`**, `CONTEXT: PL/pgSQL function inline_code_block line 1615 at RAISE`.

**SQL BYTE IDENTITY = INDIRECT / ACCEPTED BY ADJUDICATION.** A imagem **não contém** o md5 nem os bytes do SQL executado. A identidade com o E10 canônico versionado (`../../2830H_E10_section_r_routing_2211.sql`, md5 `c810a76e294feb2244fcae0ca63fb414`, commit `696caed` de 2026-09-27, anterior à execução) é só corroborada:

- o nome do envelope na imagem é a constante `c_env` do arquivo (linha 27);
- o bloco `DO` do arquivo começa na linha 25, então a linha 1615 do bloco é a linha 1639 do arquivo, exatamente o `RAISE EXCEPTION USING ERRCODE = 'H283P'` terminal;
- o formato da mensagem é o da linha 1640.

Isso **não** é identidade criptográfica.

## 4. Segurança

Varredura estrita nos 10 registros e no PNG antes da preservação: nenhum JWT, chave anon/service, `sb_secret_`/`sbp_`, senha, `PGPASSWORD`, cabeçalho de autorização, cookie, connection string ou chave privada.

Os únicos acertos foram falsos positivos:
- contadores de uso do modelo (`input_tokens`, `output_tokens`, `thinking_tokens`);
- identificadores do SQL dos envelopes (`normalized_token`, `axis_identity_token`).

Os registros também contêm, sem valor de segredo: caminho local de trabalho, IDs de sessão e de requisição, e o identificador do projeto Supabase.

## 5. Limites

- **Uma única amostra por envelope.** Não há 3×, nem cache frio, nem `ANALYZE` controlado.
- **Todos ≤ 60 s** (o maior é E14, com 420 ms). Isso **não** prova o pior caso contratual.
- **P9(b) v7.0 continua NOT SATISFIED AS WRITTEN.** Este artefato só satisfaz a condição de proveniência do BR-2 para o P9(b)′, se a auditoria o aprovar.
