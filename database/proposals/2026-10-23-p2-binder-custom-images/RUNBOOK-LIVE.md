# RUNBOOK LIVE — Imagens personalizadas do bolso (5231 → 5236)

| Campo | Valor |
|---|---|
| Versão | 1.0 (2026-10-23, `P2-BINDER-CUSTOM-IMAGES-LIVE-READINESS-01`) |
| Status | **PREPARADO — NADA EXECUTADO** (nem SELECT no LIVE). |
| Governança | Sem ambiente isolado, staging ou banco de testes. No LIVE só o que é seguro lá. |
| Quem executa | Fabrício, ou o agente com autorização expressa **por etapa** |

## 1. Classes

| Classe | O quê | Arquivo | Autorização |
|---|---|---|---|
| **R1** | leitura de catálogo, Storage (metadados/políticas/gatilhos) e contagens, em `begin transaction read only` | `LIVE_00_precheck_readonly.sql`, `LIVE_90_postcheck_readonly.sql` | uma para o R1-pré, outra para o R1-pós |
| **W1** | DDL: `5231` → `5236` | arquivos desta pasta, conteúdo integral | **expressa e separada**; aprovar R1 não aprova W1 |
| **F** | prova funcional real F1–F7 (§7): envia, vincula, tenta apagar e remove **um** arquivo de teste do próprio Fabrício | app ou SQL com o usuário real | **expressa e separada**; cria e apaga arquivo no Storage |
| **PROIBIDO** | `5852` em qualquer modo; fixtures; carga; K1–K5 automatizados | — | — |

## 2. Pré-requisitos

1. 5229/5230 aplicadas (`P1.2`).
2. Arquivos desta pasta sem alteração depois da revisão. SHA-256 de referência (2026-10-23, `AUDIT-CORRECTION-01`):

| Arquivo | SHA-256 |
|---|---|
| 5231 | `a130905d3b3b8c2fe483392da93dfa0edee82bf1271260cf910d6d47e2f4c908` |
| 5232 | `feb26342b38d38545ba04c2ae70232f96ad64a578f89e8d7617024ca6086b278` |
| 5233 | `eb743da71c731d95dbb8a18d83201c22b2180b3a78d43c2a5e9172ac1ac68c26` |
| 5234 | `611cad5401e4d1919a42bdb52ff0f6e14c1470187b3717f1f693e88899f14976` |
| 5235 | `c73303e3f6ae52428f84e94af361193fa6c5afe0836f35f040c1de90d66ee149` |
| 5236 | `8bef7b509ed45bf829042282227e83a250a11aeea8d6e14c5c90ecfec94571f8` |

3. Janela de baixo uso: 5231/5232 fazem `CREATE POLICY` em `storage.objects` (trava exclusiva breve da tabela do Storage — capas, avatares e imagens de cartas ficam em espera durante a DDL).
4. O R1 roda com **o mesmo papel** que fará o W1 (esperado `postgres`): o `PRE-5` mede as permissões desse papel.

## 3. Ordem

| # | Etapa | Classe | Comando |
|---|---|---|---|
| 0 | `PRE-1`…`PRE-8` | R1 | `LIVE_00`, bloco a bloco |
| — | **GATE** (§4) | — | — |
| 1 | `5231` bucket + SELECT/INSERT | W1 | `apply_migration` `5231_create_binder_slot_image_bucket_and_policies` |
| 2 | `5232` tabela, gatilhos, DELETE protegido | W1 | `5232_create_collection_layout_slot_image_table` |
| 3 | `5233` escrita | W1 | `5233_create_binder_slot_image_write_functions` |
| 4 | `5234` leituras | W1 | `5234_create_binder_slot_image_read_functions` |
| 5 | `5235` remoção de página | W1 | `5235_update_remove_layout_page_for_custom_images` |
| 6 | `5236` desmontagem | W1 | `5236_update_binder_dismantle_for_custom_images` |
| 7 | `POST-1`…`POST-4` | R1 | `LIVE_90` + `get_advisors(security)` |
| 8 | Prova funcional F1–F7 | F | §7, autorização própria |
| 9 | Fechamento documental e promoção | — | `database/schema/`, 05d, HANDOFF, log |
| 10 | Frontend (aba Imagem) | — | rodada própria |

Uma migration por vez. Ler a resposta e o ledger entre elas. Cada arquivo é uma transação com precheck fail-loud: um erro desfaz só aquele arquivo.

**Estados intermediários** (se parar no meio):
- após 5231: bucket vazio, sem DELETE e sem uso — inerte;
- após 5232: tabela vazia; gatilhos ativos só recusam o que nunca existe (bolso com imagem) — inerte para o app atual;
- após 5233/5234: RPCs disponíveis, sem consumidor;
- 5235/5236: comportamento antigo preservado enquanto `images = 0`.
Nenhum estado intermediário afeta cartas, reservas, travas ou o app atual.

## 4. Gate de autorização (antes do W1)

- `P1.1`, `P1.2`, `PRE-2`, `PRE-3`, `PRE-4`, `PRE-5`, `PRE-6` conforme §5.
- `PRE-7` registrado como baseline.
- `PRE-8`: nenhuma transação aberta há mais de 1 min e nenhuma trava concedida a outra sessão nas tabelas listadas.
- Mensagem expressa de Fabrício autorizando o W1.

## 5. PASS / STOP

| Ponto | PASS | STOP |
|---|---|---|
| `P1.1` / `P1.2` | `true` | 5231–5236 já no ledger, ou 5229/5230 ausentes |
| `PRE-2` | 6/6 `ok` | qualquer objeto do pacote já existe |
| `PRE-3` | 5/5 `ok` | dependência ausente (função, coluna, unicidade do Storage) |
| `PRE-4` | `P4.1`–`P4.4` `ok`; `P4.5` duas colunas `true`; `P4.6`/`P4.7` duas colunas `true`; `P4.8` sem escritor inesperado fora da trava | corpo vivo ≠ canônico (marcador); dependente de função recriada; escritor sem trava |
| `PRE-4` md5 | igual: registrar | diferente com marcadores `ok`: registrar e comparar o texto antes do W1 (não é STOP automático) |
| `PRE-5` | `rolbypassrls` ou `rolsuper`; `obj_select`, `obj_update`, `bkt_insert`; dono de `storage.objects` alcançável **ou** `P5.2` `true` | **sem bypass de RLS → NO-GO**: o `FOR SHARE` da 5233 exigiria política UPDATE que o bucket não tem; todo vínculo falharia |
| `PRE-6` | `P6.1` RLS ligada; `P6.3` `true`; revisão manual de `P6.2` sem política permissiva de escrita que alcance o bucket novo | política permissiva de DELETE/UPDATE/INSERT/ALL sem filtro de bucket (ou com filtro por negação) → a proteção do arquivo vinculado seria anulada por OR |
| `PRE-7` | — (baseline) | — |
| `PRE-8` | sem bloqueio | transação longa ou trava: esperar |
| W1 cada | sucesso + entrada nova no ledger | qualquer erro: §6 |
| `POST-1` | 13/13 `ok` | qualquer `false` |
| `POST-2` | igual ao `PRE-7`, exceto `buckets +1`, `storage_object_policies +3`; `images = 0`; `objects_in_new_bucket = 0`; `fp_storage_policies_preexisting = fp_storage_policies` do `PRE-7` | qualquer outra diferença |
| `POST-3` | 6 linhas, 5231→5236 | ausente, duplicada, fora de ordem |
| `POST-4` | nenhum achado novo de outra classe | achado novo |
| F1–F7 | todos conforme §7 | F3 ou F4 apagam o arquivo vinculado → **incidente**: desativar a aba Imagem; corrigir antes de qualquer uso |

## 6. Conduta em erro

1. **Parar.** Não reaplicar, não editar no LIVE, não seguir para a próxima migration. Guardar SQLSTATE e texto integrais.
2. Rodar `PRE-2` e `POST-3` para fotografar o que existe (a migration que falhou não deixou nada; as anteriores ficaram).
3. Reportar. Correção só como nova proposta, com nova autorização.

**Reversão** (só com autorização, como proposta própria; segura enquanto `images = 0` e `objects_in_new_bucket = 0`), na ordem inversa:
5236 → reaplicar o bloco 7b da 5229 · 5235 → reaplicar o bloco da 5126 · 5234/5233 → `drop function` das 4+4 · 5232 → `drop policy binder_slot_image_delete_own`, gatilhos, funções, tabela · 5231 → `drop policy` das 2 e `delete from storage.buckets where id = 'binder-slot-image'` (bucket vazio).

## 7. Prova funcional autorizada (classe F)

Leitura **não** prova a proteção do arquivo: ela depende do comportamento real da API do Storage e da reavaliação da política sob concorrência. Com autorização expressa, Fabrício (usuário real, sessão do app ou SQL com o JWT dele) executa, com **um** arquivo de teste pequeno num bolso livre de um fichário dele:

| Passo | Ação | Esperado |
|---|---|---|
| F1 | enviar `teste.webp` pela API do Storage (`upsert:false`) | criado; linha em `storage.objects` com `owner_id` dele e `metadata.mimetype/size` |
| F2 | `set_my_binder_slot_image` no bolso | `ADDED`; `get_my_collection_binder_slot_images` mostra o bolso |
| F3 | **API do Storage** `remove([caminho])` | resposta sem o arquivo (ou erro); **arquivo continua** em `storage.objects` **e** no armazenamento (URL assinada abre) |
| F4 | `upload` com `upsert:true` no mesmo caminho | recusado; conteúdo inalterado |
| F5 | `clear_my_binder_slot_image` | `REMOVED` com `previous_path` |
| F6 | `remove([caminho])` | arquivo some do `storage.objects` e do armazenamento |
| F7 | (opcional, duas sessões) K5 do README: sessão 1 vincula sem confirmar; sessão 2 tenta apagar; sessão 1 confirma | arquivo continua e vinculado |

Resultado registrado no README ("Execução no LIVE"). Ao fim, o bolso volta vazio e o arquivo de teste não existe.

## 8. Evidência a registrar

Saídas integrais de `PRE-*`/`POST-*` com hora UTC; papel usado; SHA-256 e resposta de cada W1; `PRE-7` × `POST-2` campo a campo; `P6.2`/`P6.4` anexados; advisors antes × depois; F1–F7 com respostas; autorizações citadas literalmente. Destino: seção "Execução no LIVE" do `README.md`, `docs/log.md` e 05d, no mesmo ciclo.
