# BINDER-PHYSICAL-LOCATION — evidência da Fase B no LIVE (LIVE-PHASE-B-EXECUTION-01)

| | |
|---|---|
| Data | 2026-10-24, 13:20–13:26 UTC |
| Projeto | `mimikyu-core` (`qjfutqujxrbzgrtkpgkg`), PG 17.6, ACTIVE_HEALTHY |
| Autorização | Fabrício, expressa: 5256 + LIVE_90. Nenhuma outra escrita. |
| Resultado | **5256 CONFIRMADO EXECUTADO; LIVE_90 PASS (7/7)** |
| Não executado | outras migrations, harness 5854, R0/R1/R2A/R2B, deploy, git |

## 1. Gate de entrada (READ ONLY, 30 s)

- Fase A 9/9 no ledger; 5256 ausente; nada após 5255.
- q05: nenhuma posição fora do local físico. Duplicidades: exemplar 0, bolso 0, local de fichário 0; posições sem exemplar 0.
- Baseline homologado conferido: 2 fichários (F001 40 páginas/360 bolsos; F002 1/16; total 41/376), 182 posições, 158 reservas, 211 alocações, 0 travados; `assignments_md5` `b010d1de…`, `layout_md5` `b0906e79…`, `allocations_md5` `a180e923…` (todos =). Extra: `physical_storage_md5` (exemplar → local) `b7f9597e7b042d60fc7475ef5ffedb3b`.
- Concorrência: 0 outras sessões ativas; 0 travas em `physical_card`/posições; última posição criada 13:02 UTC.
- Limites: `lock_timeout 5s` próprio da 5256; `statement_timeout` do servidor 30 s.
- Frontend publicado (`0389498`): só chama a leitura de 5 argumentos e as sobrecargas confirmadas (`p_unplace_from_binder`) — o DROP da leitura de 3 argumentos não afeta chamador.

## 2. Migration

| | |
|---|---|
| Ledger | `20261024132349 5256_binder_physical_location_contract` (nada depois) |
| Equivalência | md5 do texto no ledger `7d32fce9f55f78727caaa3635f72858a` = md5 do corpo do arquivo entre `begin;`/`commit;` (arquivo `a613a961…`) |
| Precheck interno | passou (0 posições fora do local) |

## 3. LIVE_90 (arquivo `dfecdaa3…`, sem alteração)

**Consulta 1:** q01 ledger 10 · q02 gatilho habilitado · q03 função do gatilho privada e `search_path` vazio · q04 leitura de 3 args removida e de 5 args presente · q05 escritores legados presentes (protegidos pelo gatilho) · q06 posições dentro do local · q07 posições com exemplar → **todas true**.

**Consulta 2:** assignments 182 · reservations 158 · slot_images 0 · regions 1 · allocations 211.

**Complementar:** gatilho BEFORE UPDATE, SECURITY DEFINER, sem EXECUTE para anon/authenticated; duplicidades 0; F001 40/360, F002 1/16; travados 0; imagens de região 1.

## 4. Antes × depois

| | Gate | LIVE_90 |
|---|---|---|
| posições / reservas / alocações | 182 / 158 / 211 | 182 / 158 / 211 |
| `assignments_md5` | `b010d1de3453373f741d994e3f2f839b` | = |
| `layout_md5` | `b0906e79695b8a049b9120d99d4f7079` | = |
| `allocations_md5` | `a180e923764e3b5a9cb225ee68f873c0` | = |
| `physical_storage_md5` | `b7f9597e7b042d60fc7475ef5ffedb3b` | = |

## 5. Riscos residuais

- A proteção não foi provocada no LIVE (proibido); a prova funcional do gatilho depende do harness 5854, nunca executado (risco já aceito).
- Recuperação disponível: R1 (desfaz só a Fase B), não executado.
- Promoção para `database/schema/` e documentação canônica: etapa separada.
