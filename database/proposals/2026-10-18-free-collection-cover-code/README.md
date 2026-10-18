# Código opcional da Coleção livre (`5179`–`5180` + `5834`)

| Campo | Valor |
|---|---|
| Rodada | `FREE-COLLECTION-COVER-CODE-01` (2026-10-18) |
| Status | **CONFIRMADO EXECUTADO no LIVE e PROMOVIDA (2026-10-18, autorização de Fabrício).** 5179 → 5180 aplicadas uma a uma; `5834` **21/21 PASS + GATE PASS**; canônicas em `database/schema/5179`–`5180`. Esta pasta fica como registro histórico. |
| Decisão de origem | Fabrício, 2026-10-18: a Coleção livre pode ter um **Código**, como o código do Set no foil da capa. **Opcional**; 2 a 6 letras ou números (maiúsculas); **não precisa ser único**; definido **na criação e editável depois**. |
| Frontend | `FREE_COVER_CODE_ENABLED = true` só no working tree local, para homologação no navegador. Publicar (commit/deploy) depende dessa homologação funcional e visual. |

## Arquivos

| Query | Arquivo | O que faz |
|---|---|---|
| `5179` | `5179_add_collection_cover_code.sql` | `collection.cover_code` (nulo, sem default) + CHECK `^[A-Z0-9]{2,6}$`; sem UNIQUE |
| `5180` | `5180_create_set_my_collection_cover_code_function.sql` | `set_my_collection_cover_code(p_collection_id, p_code)` → código gravado ou `NULL`. Normaliza (trim + maiúsculas), vazio remove, só Coleção livre, dono por `auth.uid()`, coleção alheia/inexistente = mesma resposta |
| `5834` | `5834_validate_free_collection_cover_code.sql` | Harness v1.0: 21 checagens + GATE, usuários efêmeros, sentinela LI000, resíduo zero |

## Desenho

- **Menor superfície possível:** uma coluna e uma função, no mesmo padrão de `5171`/`5172` (cor) e `5177`/`5178` (imagem). R1 (`5168`/`5173`) não muda: o código é lido pela política existente `collection_select_own` (5030), na mesma consulta que já lê `cover_logo_path`.
- **Opcional de ponta a ponta:** `NULL` é o estado normal; a capa sem código fica exatamente como hoje.
- **Criação:** `5175` (LIVE) não muda. A interface chama `5175` e, se houver código, `5180` em seguida. As duas são idempotentes: um novo envio do mesmo pedido reaproveita a coleção e regrava o mesmo código. Se só o código falhar, a coleção existe e a tela final avisa que o código pode ser definido na página da coleção — nada fica inconsistente (o código é só aparência).
- **Coleção de Set:** recusada (`NOT_FREE_COLLECTION`) — continua com o código do próprio Set.
- **Segurança:** SECURITY DEFINER, `search_path` vazio, `FOR UPDATE`, EXECUTE só `authenticated`; `authenticated` não tem UPDATE direto em `collection`.
- **Performance:** sem índice novo (não há busca por código); a leitura é por `id` (PK) junto com `cover_logo_path`.
- Não toca cartas, alocações, locais, referência nem progresso.

## Execução proposta (quando autorizada)

1. Pré-check: objetos inexistentes; linha de base (contagens + fingerprints de coleções, vínculos e exemplares; Advisor).
2. Aplicar `5179` → `5180`, uma por vez, conferindo cada uma.
3. Executar `5834` — esperado **21/21 PASS + GATE PASS**.
4. Security Advisor antes × depois: esperado só `0029` +1 (a função nova, SECURITY DEFINER por desenho).
5. Promover para `database/schema/`, documentar e preparar `FREE_COVER_CODE_ENABLED = true` para homologação no navegador.

Quem executa é Fabrício, uma Query por vez, confirmando antes de avançar (STD-001 §10), salvo autorização explícita para o agente executar.

## Execução no LIVE (`FREE-COLLECTION-COVER-CODE-LIVE`, 2026-10-18)

| Etapa | Evidência |
|---|---|
| Pré-check | Coluna, CHECK e função inexistentes. Linha de base: 3 usuários, 3 coleções, 183 vínculos, 1.324 exemplares, 1 local; fps coleções `a469d0a0…` (inclui `cover_finish` e `cover_logo_path`), vínculos `2e86413b…`, exemplares `653f4b5d…`; md5 5175 `2cd097d8…`, 5178 `8b03b99d…`; Advisor 0029 = 160. |
| 5179 | Ledger `20261018005335`. Coluna `text` nula sem default; CHECK idêntico ao arquivo; 0 linhas preenchidas; fp das coleções inalterado; `authenticated` sem UPDATE em `collection`. |
| 5180 | Ledger `20261018005411`. Corpo idêntico ao arquivo (md5 `de70b01e…`, 1.026 caracteres), SECURITY DEFINER, VOLATILE, `search_path` vazio, dona `postgres`, EXECUTE `postgres` + `authenticated`. |
| `5834` | **21/21 PASS + GATE PASS** — anon 42501; sem identidade 28000; normaliza (" mmk1 " → MMK1); idempotente; 1, 7 e símbolo recusados (código anterior mantido); coleção de Set recusada; coleção alheia/inexistente = mesma resposta (código alheio intacto); mesmo código em duas coleções aceito; NULL e vazio removem; CHECK recusa minúsculas; nenhuma alocação; B não lê coleções de A; resíduo zero. |
| Pós-check | Contagens e os três fingerprints iguais à linha de base; nenhum código gravado; 5175 e 5178 intactas. |
| Advisor | Única diferença: 0029 160 → 161 (`set_my_collection_cover_code`, esperado). |
