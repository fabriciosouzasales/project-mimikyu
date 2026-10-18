# Capa enviada da Coleção livre (`5176`–`5178` + `5833`)

| Campo | Valor |
|---|---|
| Rodada | `FREE-COLLECTION-COVER-LOGO-01` (2026-10-17) |
| Status | **CONFIRMADO EXECUTADO no LIVE e PROMOVIDA (2026-10-18).** 5176 → 5177 → 5178 aplicadas uma a uma; `5833` v1.2 **25/25 PASS + GATE PASS**; canônicas em `database/schema/5176`–`5178`. Esta pasta fica como registro histórico da rodada. |
| Decisão de origem | Fabrício, 2026-10-17: na Coleção livre, o colecionador escolhe a imagem da placa da capa — **imagem enviada pelo usuário**. |
| Frontend | `FREE_COVER_UPLOAD_ENABLED = true` só no working tree local, para homologação no navegador. Publicar (commit/deploy) depende dessa homologação funcional e visual. |

## Arquivos

| Query | Arquivo | O que faz |
|---|---|---|
| `5176` | `5176_create_collection_cover_bucket_and_policies.sql` | Bucket **privado** `collection-cover` (1 MB, PNG/JPEG/WEBP) + 4 políticas em `storage.objects`: só o dono lê, envia, troca e apaga, na pasta `<auth.uid()>/…` |
| `5177` | `5177_add_collection_cover_logo_path.sql` | `collection.cover_logo_path` (nulo) + CHECK de formato `<dono>/<coleção>/<uuid>.(png\|jpg\|webp)` |
| `5178` | `5178_create_set_my_collection_cover_logo_function.sql` | `set_my_collection_cover_logo(p_collection_id, p_path)`: define/remove a capa; confere dono, pasta, existência do arquivo (owner_id ou owner = auth.uid()) e "só Coleção livre"; devolve o caminho anterior |
| `5833` | `5833_validate_free_collection_cover_logo.sql` | Harness v1.2: 25 checagens + GATE, usuários efêmeros, resíduo zero |

## Desenho

- **Menor superfície possível:** uma coluna, um bucket, uma função. R1 (`5168`/`5173`) não muda; a capa é lida pela política existente `collection_select_own` (5030).
- **Privacidade:** bucket privado; a interface usa URL assinada (1 h). Nenhum `anon`, nenhuma leitura cruzada (5833 §4).
- **Integridade da troca (ordem do avatar do perfil):** envia o arquivo novo → grava o ponteiro (5178) → só então apaga o anterior. Se a gravação falhar, o cliente apaga o arquivo recém-enviado e a capa atual continua. Falha ao apagar o anterior deixa só um arquivo órfão do próprio dono, nunca uma capa quebrada.
- **Idempotência:** repetir o mesmo caminho devolve o mesmo resultado, sem nada a apagar (5833 3.2).
- **Coleção de Set:** recusada (`NOT_FREE_COLLECTION`) — continua com a identidade do Set.
- Não toca cartas, alocações, locais, referência nem progresso.

## Pré-check antes de aplicar (quando autorizado)

1. ~~Confirmar como o Storage registra o dono~~ — resolvido em READINESS-01 (abaixo); 5178 v1.1 confere `owner_id` com `owner` como reserva.
2. Linha de base de `storage.buckets`, políticas de `storage.objects`, contagens de `collection` e Security Advisor.

## Execução proposta

1. Aplicar `5176` → `5177` → `5178`, uma por vez.
2. Executar `5833` v1.1 — esperado **25/25 PASS + GATE PASS**.
3. Security Advisor antes × depois: esperado só `0029` +1 (a função nova, SECURITY DEFINER por desenho).
4. Promover para `database/schema/`, documentar e só então ligar `FREE_COVER_UPLOAD_ENABLED` (feito em 2026-10-18; flag ligada só localmente até a homologação no navegador).

Quem executa é Fabrício, uma Query por vez, confirmando antes de avançar (STD-001 §10).

## Revisão de readiness (`FREE-COLLECTION-COVER-READINESS-01`, 2026-10-17)

Leituras exclusivamente de consulta no LIVE (nenhuma escrita):

| Ponto | Evidência | Parecer |
|---|---|---|
| Dono dos arquivos no Storage | `storage.objects` tem `owner` (uuid, legada) e `owner_id` (texto). Em 100% dos arquivos enviados por usuários (avatars 2/2, card-set-logo 203/203, expansion-logo 21/21, artwork 2050/2050, card-front 268/268) as duas estão preenchidas e iguais | 5178 → v1.1: `owner_id = auth.uid()::text OR owner = auth.uid()` |
| Isolamento (5176) | RLS ligada em `storage.objects`; políticas são permissivas por bucket e nenhuma existente cobre `collection-cover`; `anon`/`authenticated` têm GRANT de tabela, então a RLS é a fronteira. As 4 políticas novas exigem `bucket_id = 'collection-cover'` e 1ª pasta = `auth.uid()` em USING e WITH CHECK (não dá para ler, gravar, renomear para pasta alheia nem apagar arquivo de terceiro). Exclusão direta por SQL ainda é barrada pelo gatilho do Storage `protect_objects_delete` (BEFORE DELETE, por statement) | OK |
| Aplicabilidade | `storage.objects` pertence a `supabase_storage_admin`; precedente LIVE: bucket + `create policy` da artwork (migration `20261012212558`) aplicados pelo mesmo caminho. `postgres` tem BYPASSRLS e SELECT/INSERT em `storage.objects` (5178, dona `postgres`, lê o arquivo; o harness insere linhas de teste) | OK |
| Exibição sem tornar público | Bucket privado; a página e os 3 modos da Biblioteca recebem URL assinada de 1 h criada com a sessão do dono (`collection_cover_select_own`); a placa usa `<img object-fit: contain>` já usada para logos; sem URL (falha/arquivo removido) cai na placa tipográfica | OK — ressalva: link assinado é portador durante 1 h; nova assinatura a cada carregamento (mesmo padrão de `card-set-logo`) |
| 5178 | Dono da coleção por `auth.uid()` + `FOR UPDATE`; mesma resposta para coleção alheia/inexistente; prefixo `<dono>/<coleção>/` (74 caracteres) + regex; arquivo precisa existir no bucket e ser do chamador; só Coleção livre; não apaga arquivos | OK |
| Falhas | Envio falha → nada muda. Gravação falha → cliente apaga o recém-enviado (se essa remoção falhar: órfão). Troca → apaga o anterior só depois de gravar (falha: órfão). Remoção → limpa o ponteiro e depois apaga o arquivo. Aba fechada no meio → órfão. Arquivo apagado por fora → URL não assina, placa tipográfica. Excluir a coleção (5039) deixa o arquivo | Órfãos ficam só na pasta privada do próprio dono, nunca quebram capa. Sem rotina de limpeza nesta rodada (dívida registrada, não bloqueante) |
| Limite e formatos | Bucket 1 048 576 bytes × frontend `1024*1024`; MIME `png/jpeg/webp` idênticos no bucket, `accept`, validação e mapa de extensão; CHECK `png\|jpg\|webp` = extensões geradas | Coerente |
| Harness 5833 | v1.1 cobre estrutura, ACL, anon/sem identidade, define/idempotente/troca/remove, arquivo inexistente, pasta de outra pessoa, pasta de outra coleção do mesmo dono, coleção alheia/inexistente, coleção de Set, CHECK, nenhuma alocação, RLS de leitura/inserção/alteração cruzadas e anon; tudo revertido (LI000) e resíduo zero inclusive em `storage.objects` | OK |

**Parecer: pronta para autorização específica. Nenhum bloqueio concreto.** Ressalvas não bloqueantes: arquivos órfãos sem limpeza automática; URL assinada válida por 1 h.

## Execução no LIVE (`FREE-COLLECTION-COVER-LIVE`, 2026-10-18)

| Etapa | Evidência |
|---|---|
| Pré-check | Objetos inexistentes (bucket, 4 políticas, coluna, CHECK, função). Baseline: 5 buckets (fp `85e03f28…`), 17 políticas em `storage.objects` (fp `5ca3c253…`), 33.803 objetos; 3 usuários, 3 coleções, 183 vínculos, 1.324 exemplares, 1 local; fps coleções `2e4e1097…`, vínculos `2e86413b…`, exemplares `653f4b5d…`; md5 5175 `2cd097d8…` e 5167 `e6bd4883…`; Advisor 0029 = 159. |
| 5176 | Ledger `20261018000947`. Bucket privado, 1 MB, png/jpeg/webp; 4 políticas `authenticated` com o predicado aprovado; as 17 políticas anteriores inalteradas (mesmo fp); 0 objetos no bucket. |
| 5177 | Ledger `20261018001008`. Coluna nula sem default, CHECK idêntico ao arquivo, 0 linhas preenchidas, fp das coleções inalterado, `authenticated` só SELECT em `collection`. |
| 5178 | Ledger `20261018001031`. Corpo idêntico ao arquivo (md5 `8b03b99d…`, 1.882 caracteres), SECURITY DEFINER, VOLATILE, `search_path` vazio, dona `postgres`, EXECUTE `postgres` + `authenticated`. |
| `5833` v1.1 | 21 checagens PASS (0.1–0.5, 1.1, 2.1, 3.1–3.9, 3.12, 4.1–4.4) e 9.1 resíduo zero PASS; **X.1 FAIL** em 4.5: `42501 permission denied for function is_admin`. 3.10 e 3.11 não chegaram a rodar. GATE FAIL (22/23). |
| Causa | Defeito do harness, não exposição: o SELECT de `anon` em `storage.objects` aciona políticas **preexistentes** de outros buckets (`card_set_logo_admin_select`, `expansion_logo_admin_select`, role `public`) que chamam `is_admin()`, sem EXECUTE para `anon` — o banco recusa a leitura inteira (fail-closed). O 4.5 esperava "0 linhas" e não tratava esse erro. |
| Pós-check | Contagens e os três fingerprints idênticos à linha de base; 0 objetos no bucket; nenhuma capa gravada. |
| Advisor | Única diferença: 0029 159 → 160 (`set_my_collection_cover_logo`, esperado). |

Correção: `5833` **v1.2** — 4.5 em subbloco, aceitando bloqueio por 42501 ou por 0 linhas.

| Retomada (autorização de Fabrício) | Evidência |
|---|---|
| `5833` v1.2 | **25/25 PASS + GATE PASS.** 4.5: `anon no bucket: 42501 (0 linha(s) lidas)`; 3.10 CHECK recusa formato inválido (23514); 3.11 nenhuma alocação criada; 9.1 resíduo zero. |
| Isolamento | Entre usuários: 3.5, 3.7, 4.1–4.4. Entre coleções do mesmo usuário: 3.6 (Set recusada) e 3.12 (pasta de outra coleção). |
| Pós-check | Igual à linha de base: 3 usuários, 3 coleções, 183 vínculos, 1.324 exemplares, 1 local, 33.803 objetos; fps coleções `2e4e1097…`, vínculos `2e86413b…`, exemplares `653f4b5d…`, demais políticas do Storage `5ca3c253…`; 0 objetos no bucket; 0 capas; última migration `20261018001031`. |
| Advisor | 0029 = 160 (só `set_my_collection_cover_logo` a mais em relação ao início). |
| Promoção | `database/schema/5176`–`5178` = arquivos executados (5178: md5 do corpo `8b03b99d…`, idêntico ao LIVE). |
