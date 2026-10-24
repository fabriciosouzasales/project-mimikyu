# POKEDEX-BINDER-SPECIES-REFERENCE — evidência da aplicação no LIVE (LIVE-EXECUTION-01)

| | |
|---|---|
| Data | 2026-10-24, 16:34–16:39 UTC |
| Projeto | `mimikyu-core` (`qjfutqujxrbzgrtkpgkg`), PG 17.6, ACTIVE_HEALTHY |
| Autorização | Fabrício, expressa: 5257–5260. Baseline aprovado: 183 posições e 212 alocações. Movimentações do F001 às 16:14–16:21 UTC confirmadas como intencionais, com `assignments_md5` `b2e7c925…` aceito |
| Resultado | **5257, 5258, 5259 e 5260 CONFIRMADAS EXECUTADAS; postcheck PASS** |
| Não executado | harness 5857, criação das 1.025 referências, deploy, git, scripts de recuperação, outras migrations |

## 1. Gate de entrada (READ ONLY, 30 s)

- Ledger 524, ponta `5256`; 5257–5260 ausentes.
- 0 sessões concorrentes.
- Arquivos: static check PASS.
- Contagens = baseline aprovado: 183 posições · 212 alocações · 158 reservas · 1.353 exemplares · 106 páginas · 1.416 bolsos · 0 imagens · 1 região · 0 travados.
- F002: 66 páginas, 4×4, 1.056 bolsos vazios.

## 2. Migrations (uma por vez, `apply_migration`, cada uma atômica)

O texto enviado é o corpo estritamente entre `begin;`/`commit;` de cada arquivo. O md5 do texto gravado no ledger (`btrim`) é igual ao md5 do corpo do arquivo nas 4 migrations.

| Migration | Ledger | md5 (ledger = arquivo) | Verificação pós-aplicação |
|---|---|---|---|
| 5257 | `20261024163436` | `b1da4fbd683b53fa26417bf4e2a068af` | 2 tabelas com RLS, 0 policies, sem grants; FKs bolso/layout/coleção = CASCADE e posição = RESTRICT; gatilho presente; função do gatilho sem EXECUTE para o cliente |
| 5258 | `20261024163618` | `3ae8c0058d7330393a174c880a6539f5` | 6 funções SECURITY DEFINER com `search_path` vazio; escritas com `lock_timeout 5s`; helpers sem EXECUTE; RPCs apenas para `authenticated` |
| 5259 | `20261024163711` | `ffdb616cfc0163766e2278c0b374fe08` | 2 leituras presentes |
| 5260 | `20261024163750` | `218262ea7e44745ba8fb44694faebabe` | `remove_layout_page(uuid)` e `(uuid, integer)` presentes, ambas definer com `search_path` vazio, EXECUTE apenas para `authenticated` |

Nenhum erro, nenhum precheck interno abortado, nenhuma repetição.

## 3. Postcheck (READ ONLY, 30 s)

| Verificação | Resultado |
|---|---|
| Ledger | 528 linhas; as 4 migrations novas registradas e equivalentes |
| Permissões | 11 funções verificadas: todas SECURITY DEFINER com `search_path` vazio; sem EXECUTE para PUBLIC e anon; helpers e gatilho sem EXECUTE para `authenticated`. Tabelas novas sem SELECT/INSERT para `authenticated`/`anon` |
| Referências criadas | **0**; preferências 0 |
| F001 | 40 páginas, **183** posições |
| F002 | **66** páginas, **1.056** bolsos |
| Alocações / reservas / exemplares | **212** / 158 / 1.353 |
| Imagens / regiões / travados | 0 / 1 / 0 |
| Progresso | alocações e vínculos de Pokédex inalterados (`collection_pokedex_position_assignment` vazio antes e depois); nenhuma leitura de progresso referencia as tabelas novas (static check S4) |
| Última escrita em posições | 16:21:30 UTC (anterior às migrations); `collection_layout.updated_at` inalterado |

### Fingerprints antes × depois

| Fingerprint | Gate (antes) | Postcheck (depois) |
|---|---|---|
| `assignments_md5` | `b2e7c9255a1ed86a9c949e5b4fdc006e` | = |
| `layout_md5` | `b0906e79695b8a049b9120d99d4f7079` | = |
| `allocations_md5` | `85388eaf94d436bd5e3977f037f9e67e` | = |
| `physical_storage_md5` | `c01951e657d29949f87da46dfa4b0e18` | = |
| `pages_md5` | `6ab7dc636d36efe68810ea1ab015b7d4` | = |
| `slots_md5` | `c449aceb97ba62460d023cbe50fb42cc` | = |
| `reservations_md5` | `3d13a7f2dcbd99ef0a842602543368ef` | = |
| `regions_md5` | `6bb7a8d89af10191668fe1e648c44e44` | = |

### Security Advisor (leitura do resultado filtrada pelos objetos novos)

- "RLS habilitada sem policies" nas 2 tabelas novas: **intencional** (deny by default; acesso só pelas RPCs).
- "Função SECURITY DEFINER executável por `authenticated`" para as 7 RPCs novas e as 2 assinaturas de `remove_layout_page`: **intencional** e no mesmo padrão de todas as RPCs do Fichário.
- Nenhum achado para `anon`.
- O relatório completo do advisor não foi lido integralmente; a leitura foi filtrada pelos nomes dos objetos desta rodada.

## 4. Riscos residuais

- Comportamento das RPCs ainda **sem prova funcional no LIVE**: harness 5857 não executado e nenhuma chamada real feita. A primeira prova será a prévia pela interface após o deploy, que deve devolver 1.025 / 31 e o token `28649da3…` (§3 do precheck) se as páginas do F002 não mudarem.
- `remove_layout_page` agora recusa remover páginas com referências sem a contagem exata. Hoje não há referências nem chamador no frontend.
- Recuperação, se necessária: só por migration nova, para frente. Rollback não autorizado nesta rodada.

## 5. Parecer

**GO** para uma futura autorização de deploy do frontend local, que lê e grava com estes contratos. Pendências:

- homologação visual;
- `next lint` e `next build` na máquina de Fabrício;
- criação das referências apenas pela interface, com prévia e confirmação, sob autorização separada.

A promoção para `database/schema/` também fica para uma etapa separada.
