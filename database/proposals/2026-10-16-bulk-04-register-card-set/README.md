# BULK-04 — `REGISTER_CARD_SET` (B2): proposta física

| Campo | Valor |
|---|---|
| **Rodada** | `BULK04-B2-IMPLEMENTATION-PROPOSAL-01` (2026-10-16) |
| **Status** | **EXECUTED / VALIDATED / PROMOTED (LIVE, 2026-10-16).** `5153`–`5158` aplicadas no LIVE (`mimikyu-core`) por autorização expressa de Fabrício e promovidas para `database/schema/`. Validação offline e LIVE com os mesmos gates: `5826` 56/56/0/0, `5823` v2.3 60/60/0/0, `5822` 64/64/0/0, `5824` v1.1 30/29/0/1. Detalhe em §7. |
| **Contrato** | `BULK04-B2-MODELING-01`; decisões Q1–Q9 (registradas em `docs/05d-colecoes-e-usuarios.md` 1.29) e I1. |
| **Pré-requisito** | `5152` aplicada no LIVE (pacote em `../2026-10-16-bulk-active-variant-hardening/README.md` §7). Todos os corpos aqui partem da versão de `5152`. |
| **Harness 5824** | Adaptação do `E02` autorizada (`BULK04-B2-HARNESS-ADAPTATION-01`): `5824` v1.1 nesta pasta (§6). |

## 1. Arquivos

| Ordem | Arquivo | O que faz |
|---|---|---|
| 1 | `5153_create_bulk_register_physical_card_items_function.sql` | Helper interno: validação de domínio + escrita. Corpo = passos 6 e 7 de `5150`/`5152`, **literal**, só com variáveis trocadas por parâmetros. |
| 2 | `5154_create_bulk_expand_card_set_function.sql` | Expansão do Card Set: um item por Card ativo na variante padrão (quantity 1), e a lista dos Cards ativos sem padrão. |
| 3 | `5155_refactor_register_physical_cards_bulk_use_shared_helper.sql` | B1: passos 6 e 7 viram uma chamada a `5153`. Nada mais muda. |
| 4 | `5156_create_preview_fingerprint_register_card_set_function.sql` | Fingerprint de B2: hash de {Set, existência, idioma, Cards sem padrão, fingerprint de `5149` sobre a expansão}, rótulo próprio. |
| 5 | `5157_create_register_card_set_bulk_function.sql` | RPC `register_card_set_bulk(p_request jsonb) → jsonb`. |
| 6 | `5158_update_preview_bulk_operation_register_card_set.sql` | `preview_bulk_operation` com o braço B2; caminho do B1 intocado. |
| H | `5826_validate_register_card_set_bulk.sql` | Harness novo do B2 — gate **56/56/0/0**. |
| H | `5823_validate_preview_bulk_operation.sql` (v2.3) | Cópia da v2.2 com **só o `V02`** alterado. A v2.2 executada continua em `../2026-09-09-bulk-03-preview/`. |
| H | `5824_validate_bulk_b1_inactive_card_variant.sql` (v1.1) | Cópia da v1.0 com **só o `E02`** alterado (alvo: `5153`). A v1.0 continua em `../2026-10-16-bulk-active-variant-hardening/`. |

Cada arquivo de migration tem `BEGIN;`/`COMMIT;` próprios e é aplicado uma vez, na ordem acima.

## 2. Reuso (Q9 / I1)

- **Uma implementação** de validação de domínio e escrita (`5153`), usada por B1 e B2. B2 não tem `INSERT` próprio.
- **Uma expansão** (`5154`), usada pelo fingerprint, pela confirmação e pelo Preview.
- **Fingerprint de B2** compõe o de `5149`, sem reler Inventory, Collection, Storage ou catálogo.
- **Preview de B2** chama o próprio Preview do B1 sobre os itens expandidos: as issues de Inventory, Collection, Storage, variante, idioma, Game e Reference existem uma vez só. B2 acrescenta apenas `CARD_SET_NOT_FOUND`, `CARD_SET_EMPTY` e `CARD_DEFAULT_VARIANT_MISSING`.
- Hash (`5147`), locks (`5148`, I9), claim/complete (`5144`/`5145`) e replay (D9): os da família, sem cópia.

## 3. Segurança e contratos preservados

| Objeto | Segurança | EXECUTE |
|---|---|---|
| `register_card_set_bulk` | `SECURITY DEFINER`, owner postgres, `search_path` vazio | só `authenticated` (igual a `5150`) |
| `preview_bulk_operation` | inalterada (`DEFINER`, `VOLATILE`) | inalterado |
| `register_physical_cards_bulk` | inalterada | inalterado |
| `bulk_register_physical_card_items`, `bulk_expand_card_set`, `preview_fingerprint_register_card_set` | `SECURITY INVOKER`, `VOLATILE`, `search_path` vazio | revogado de PUBLIC, anon, authenticated e service_role |

- **Atomicidade:** uma operação = uma transação; qualquer exceção desfaz tudo, claim incluído; guards `55000` de `5153` mantidos.
- **Idempotência:** chave por `(owner, 'REGISTER_CARD_SET', key)`; `request_hash` cobre a intenção (Set, idioma, destino), não a expansão; REPLAY independente do mundo.
- **Preview:** sem escrita, lock ou claim; fingerprint só no caminho limpo; teto de 1000 como exceção com a mesma mensagem da confirmação.
- **Sem lock novo.** O trigger de `2268` continua sendo a última barreira contra variante desativada em concorrência.
- **B1:** contrato público, mensagens, SQLSTATE e ordem idênticos; o corpo de `5153` é o texto de `5152` (verificado por diff na preparação).

## 4. Harnesses e critérios de aprovação

| Harness | Gate | Papel |
|---|---|---|
| `5826` v1.0 (novo) | **56/56/0/0** + resíduo zero nas 12 tabelas (CALL 3) | B2 completo: estrutura, ACL, guards, Preview, caminho feliz, idempotência, PREVIEW_STALE, validações, atomicidade |
| `5823` v2.3 | **60/60/0/0** + resíduo zero | regressão do Preview do B1; só `V02` muda |
| `5822` v2.1 (sem alteração) | **64/64/0/0** + resíduo zero | regressão do B1 após a refatoração |
| `5824` v1.1 | **30/29/0/1** (K01 aceito) | regressão do hardening, com `E02` apontado para `5153` (§6) |

Ordem: aplicar `5153`→`5158`; executar `5826`, `5823` v2.3, `5822`, `5824` v1.1; CALL 3 de cada um.

## 5. Reversão

Na mesma ordem inversa: reaplicar o corpo de `5151` e de `5150` da versão `5152` (`CREATE OR REPLACE`), e `DROP FUNCTION` de `register_card_set_bulk`, `preview_fingerprint_register_card_set`, `bulk_expand_card_set` e `bulk_register_physical_card_items`. Nenhum dado é alterado pelas migrations. Rollback só com autorização específica.

## 6. `5824` v1.1 — adaptação do `E02` (autorizada)

O `E02` da v1.0 inspecionava o **código-fonte** de `register_physical_cards_bulk` e exigia `CARD_VARIANT_INACTIVE` antes de `INSERT INTO public.physical_card`. Com I1 as duas coisas moram em `5153`. A v1.1 (`BULK04-B2-HARNESS-ADAPTATION-01`) prova a mesma garantia no lugar certo:

- `5150` contém a chamada `bulk_register_physical_card_items`;
- em `5153`, `CARD_VARIANT_INACTIVE` aparece e vem antes de `INSERT INTO public.physical_card`.

Nenhum outro caso muda; total e gate continuam `30/29/0/1`. Se `5153` não existir, `v53` fica NULL e o `E02` falha (fail-closed).

## 7. Execução (2026-10-16)

### 7.1 Offline

PostgreSQL 17 isolado (`mmkyu-bulk-offline-pg17`, sem rede), sobre o ambiente que já validara `5152`, via `mmkyu-bulk04-offline-test.ps1` (fora do repositório): migrations `5153..5158` aplicadas; `5826` PASS, `5823` v2.3 PASS, `5822` PASS, `5824` v1.1 PASS; resíduo ZERO. Executado por Fabrício.

### 7.2 LIVE

| Migration | Ledger | Corpo LIVE = arquivo (md5 de `prosrc`) |
|---|---|---|
| `5153` | `20261016235518` | sim |
| `5154` | `20261016235536` | sim |
| `5155` | `20261016235631` | sim |
| `5156` | `20261016235645` | sim |
| `5157` | `20261016235726` | sim |
| `5158` | `20261016235910` | sim |

- **Antes:** hashes iguais aos validados offline; `5152` aplicada (ledger `20261016234129`) e corpos de `5149`/`5150`/`5151` no estado de `5152`; os quatro objetos novos ausentes.
- **Aplicação:** ordem `5153`→`5158`, uma vez cada, sem erro, via `apply_migration` do Supabase (transação da própria ferramenta; `BEGIN`/`COMMIT` dos arquivos omitidos no envio). Cópias canônicas idênticas em `database/schema/`; só o cabeçalho `Status` mudou após a aplicação.
- **Harnesses (todos com ROLLBACK):** `5826` **56/56/0/0**, `5823` v2.3 **60/60/0/0** (Preview com 1000 variantes reais: 982 ms, observacional), `5822` **64/64/0/0**, `5824` v1.1 **30/29/0/1 GATE OK**.
- **Resíduo:** zero em 13 tabelas; nenhum Game/Expansion/Card Set sintético remanescente; variantes inativas 0.
- **Permissões:** objetos existentes inalterados; `register_card_set_bulk` com `EXECUTE` só para `authenticated`; `bulk_register_physical_card_items`, `bulk_expand_card_set` e `preview_fingerprint_register_card_set` só `postgres` (S06: `authenticated` recebe `42501`).
- **Security Advisor:** listas completas comparadas antes × depois. Único alerta novo: `authenticated_security_definer_function_executable` para `public.register_card_set_bulk(p_request jsonb)` — **aceito por Fabrício como risco conhecido, exclusivamente para esta função** (decisão de 2026-10-16). Mesma classe já existente para `register_physical_cards_bulk` e `preview_bulk_operation`; a função é a RPC pública do B2, deriva o dono de `auth.uid()` e só atua no Inventory/Collection/Storage do chamador; `anon` sem `EXECUTE`.
- **`K01`:** NOT PROVEN / ACCEPTED RISK (mesma decisão de `5152`).
