# MY-INVENTORY-HOLOGRAPHIC-FINISH-FOUNDATION-01 — acabamento holográfico no Meu acervo

| | |
|---|---|
| Data | 2026-10-24 |
| Status | **EXECUTADA / CANÔNICA / ENCERRADA (2026-10-24, `ACERVO-HOLOGRAPHIC-FINISH-FINAL-CLOSEOUT-01`)** — 5261 (ledger `20261024185908`) e 5262 (`20261024185943`) aplicadas no LIVE e promovidas para `database/schema/` (só o bloco Status difere; ledger = arquivo desta pasta, md5). 5858: B 8/8; C original inconclusiva, revalidada estável ×2 (§7); D PASS. Homologação visual em produção por Fabrício (1×). Ver §8. |
| Projeto | Supabase `mimikyu-core` (`qjfutqujxrbzgrtkpgkg`) — investigação somente leitura (`begin transaction read only; statement_timeout 30s`) |
| Protótipo aprovado | `docs/development/prototypes/2026-10-24-holo-variants/prototype.html` (intensidade 1×) |
| Escopo | Meu acervo: galeria e detalhe ampliado. Fora: fichários, Master Set, Pokédex e demais telas. |

## 1. Auditoria da classificação (LIVE, somente leitura)

### 1.1 Cobertura dos tipos de variante

97 tipos no catálogo; **23 com variantes**, 4 com exemplares no acervo hoje (STANDARD 972, HOLO 525, REVERSE_HOLO 65, COSMOS_HOLO 2). Os 74 restantes não têm variantes (a maioria inativa: estampas, campeonatos, Staff, Worlds…).

| Família | Códigos (explícitos — sem regra por sufixo) | Efeito |
|---|---|---|
| Padrão | `STANDARD` | nenhum |
| Holográfica | `HOLO`, `COSMOS_HOLO` (textura aproximada) | janela ou carta inteira, conforme a geometria |
| Reversa | `REVERSE_HOLO`, `POKE_BALL_REVERSE`, `MASTER_BALL_REVERSE`, `ENERGY_REVERSE`, `LOVE_BALL_REVERSE`, `FRIEND_BALL_REVERSE`, `QUICK_BALL_REVERSE`, `DUSK_BALL_REVERSE`, `ROCKET_REVERSE`, `COSMOS_REVERSE`, `TINSEL_REVERSE` | corpo da carta (o padrão impresso não é reproduzido) |
| Especial | `RAINBOW_HOLO`, `GOLD_HOLO`, `CRACKED_ICE_HOLO`, `GALAXY_HOLO`, `TINSEL_HOLO`, `MASTER_BALL_HOLO`, `METAL`, `METAL_GOLD`, `LENTICULAR` | nenhum (chip apenas) |
| Desconhecido | qualquer outro código (inclusive inativos e futuros) | nenhum |

**Por que não por sufixo:** `STANDARDS_*`/`STANDARD_*` (estampas) e `*_REVERSE` de campeonatos/EB Games existem no catálogo, e `*_HOLO` inclui texturas (Rainbow, Gold, Cracked Ice, Galaxy) que um arco-íris genérico descaracterizaria. Listas explícitas fazem um código novo cair em "sem efeito", nunca em um efeito errado.

### 1.2 Geometria por raridade (a raridade não decide o brilho, só onde ele cabe)

| Classe | Raridades | Justificativa |
|---|---|---|
| Janela confiável | `COMMON`, `UNCOMMON`, `RARE`, `RARE_HOLO`, `DOUBLE_RARE`, `ACE_SPEC_RARE` | moldura tradicional com janela de ilustração. No acervo atual, todas são da era Mega Evolution (ME1–ME5.5), a proporção do protótipo. |
| **Carta secreta do Set** (número puro acima do total impresso, ex.: 133/132) | qualquer raridade | **regra de Fabrício (2026-10-24): brilho na carta toda.** Prevalece sobre a raridade. Não muda o acabamento (padrão/especial seguem sem efeito; reversa secreta não existe → sem efeito). Usa `collector_number`/`collector_total`, já presentes no contrato — sem SQL adicional. |
| Carta inteira (full art) | `RARE_SECRET`, `ILLUSTRATION_RARE`, `SPECIAL_ILLUSTRATION_RARE`, `ULTRA_RARE`, `HYPER_RARE`, `MEGA_HYPER_RARE`, `SHINY_ULTRA_RARE` | arte ocupa a carta toda nessas raridades. Reversa full art não existe → sem efeito. |
| Sem evidência → sem efeito (salvo secreta) | `PIKACHU_RARE`, `PROMO`, `MEGA_ATTACK_RARE`, `FUTURISTIC_RARE`, `CLASSIC_COLLECTION`, `SHINY_RARE`, `RARE_HOLO_V/VMAX/VSTAR/LV_X`, `RARE_PRIME`, `RARE_LEGEND`, `RADIANT_RARE`, demais, `NONE` | PROMO mistura moldura comum e full art (ex.: Mimikyu SVP 075). PIKACHU_RARE: geometria não confirmada (decisão 4). Molduras antigas/V/VMAX têm janela diferente. |

### 1.3 Efeito no acervo de hoje (exemplares)

| Resultado | Exemplares |
|---|---|
| HOLO na janela (RARE 86, DOUBLE_RARE 102) | 188 |
| HOLO na carta inteira (IR 96, SIR 19, UR 70, MHR 1 + secretas MEGA_ATTACK 3, FUTURISTIC 1) | 190 |
| HOLO sem efeito (PIKACHU_RARE 86, PROMO 54, CLASSIC 7) | 147 |
| COSMOS_HOLO sem efeito (PROMO) | 2 |
| Reversa no corpo (COMMON 35, UNCOMMON 22, RARE 8) | 65 |
| Padrão | 972 |

## 2. Contrato proposto

| Query | Função | Mudança |
|---|---|---|
| **5261** | `get_my_inventory_items` (galeria; evolui a 5220) | + `variant_type_code text`, `rarity_code text` ao final |
| **5262** | `get_my_inventory_item_copies` (detalhe; evolui a 5162) | + `variant_type_code text`, `rarity_code text` ao final |
| **5858** | harness | A (linha de base) · B (estrutura) · C (equivalência) · D (códigos e autorização) |

**Por que duas funções:** o detalhe ampliado (decisão 5) abre por deep link com uma única chamada à 5162; ele não lê a 5220. Sem a 5262 o detalhe não teria os códigos.

**Compatibilidade investigada:**

- `CREATE OR REPLACE` não pode mudar `RETURNS TABLE` (42P13) → `DROP` + `CREATE` na mesma transação, com `REVOKE`/`GRANT` reaplicados. Ninguém observa a função ausente.
- Assinatura de entrada idêntica (10 e 2 argumentos, mesmos defaults).
- Consumidores: nenhum no banco (`pg_depend` = 0; nenhum `prosrc` chama as funções).
  - 5220: `acervo-queries.ts`, `colecoes-queries.ts` (`getAvailableGroupCount`) e 2 chamadas em `app/colecoes/colecoes/actions.ts`.
  - 5162: `acervo-queries.ts` e 3 chamadas em `actions.ts`.
  - Todos leem por nome de coluna (JSON do PostgREST). As colunas novas ao final são ignoradas por quem não as usa.
- Pré-checagens fail-loud: corpo vigente = canônico (md5 `93786a7b…` / `0835268e…`, conferidos no LIVE e no arquivo canônico), retorno vigente exato, uma sobrecarga e nenhum dependente.
- Diferença de corpo × canônica: 5261 = 2 colunas na projeção + 1 `left join rarity`; 5262 = 2 colunas no CTE `head`, 1 `left join rarity` e 2 colunas na projeção. FASE 1 (paginação, filtros, ordenação, contagens), segurança e limites intactos.
- Desempenho: junções por PK, só nas ≤ 96 linhas da página (5261) ou na linha única do cabeçalho (5262). Nenhum índice novo.
- Ordem de publicação: segura nos dois sentidos. Banco primeiro → o frontend atual ignora as colunas. Frontend primeiro → códigos ausentes = "sem efeito", nunca erro.

## 3. Plano de aplicação (quando autorizado)

1. Rodar 5858 Seção A e guardar o resultado (ensaio de 2026-10-24 abaixo; repetir imediatamente antes de aplicar).
2. Aplicar 5261, depois 5262 (cada uma em sua transação).
3. 5858 Seções B, C (comparar com A linha a linha) e D.
4. Publicar o frontend.

**Recuperação:** `drop function` da assinatura nova + reaplicar a 5220/5162 canônicas.

### Linha de base (5858 Seção A, ensaio 2026-10-24, somente leitura)

| Caso | Linhas | Impressão |
|---|---|---|
| A1 padrão RECENT | 96 | `3266f46e03ceffb6cf82c1a5d71482a5` |
| A2 SET_NUMBER | 96 | `8678c7b338d081484526853f7aceea01` |
| A3 SET_NUMBER pág. 2 | 96 | `dc6c12465d5d3cd113f8a509cd09a420` |
| A4 busca "a" | 96 | `ed9e838ed75c57536db74ff6a6e2a1b2` |
| A5 sem coleção | 96 | `0786ba5106d6599267df8b00fdcb4188` |
| A6 sem local | 96 | `fbdc3dc962dde7b14f12cdb5b683d63f` |
| A7 idioma pt-BR | 96 | `8678c7b338d081484526853f7aceea01` (= A2: o acervo de teste é todo pt-BR) |
| A8 detalhe top-5 | 42 | `c9bd957c5038cf4dc0f26baada4116a7` |

## 4. Frontend local (não publicado)

| Arquivo | Papel |
|---|---|
| `web/lib/colecoes/card-finish.ts` (+ `.test.ts`, 15 testes) | classificação pura e camadas por efeito |
| `web/lib/colecoes/acervo-queries.ts` | `variantTypeCode`/`rarityCode` no item (opcionais no contrato) |
| `web/components/colecoes/acervo/card-finish-layers.tsx` | camadas decorativas (servidor), reutiliza `.holo-card__sheen` |
| `web/components/colecoes/acervo/finish-pointer.tsx` | um listener delegado, rAF, só mouse, desligado com movimento reduzido |
| `web/components/colecoes/acervo/acervo-view.tsx` | tile da galeria e arte do detalhe (inclinação só no detalhe e só com acabamento) |
| `web/components/colecoes/acervo/acervo.module.css` | foil/reflexo/máscara, intensidade 1× do protótipo |

## 5. Readiness (MY-INVENTORY-HOLOGRAPHIC-FINISH-READINESS-01, 2026-10-24) — GO

- **Segurança:** 5261/5262 mantêm SECURITY DEFINER, STABLE, `search_path ''`, `auth.uid()` (28000) e filtro por `inventory_id = v_inventory` (corpo = canônico + só as colunas/junção novas). ACL no LIVE hoje `{postgres=X/postgres,authenticated=X/postgres}`; o default ACL de funções criadas por `postgres` em `public` é só `{postgres=X}` + EXECUTE implícito de PUBLIC, removido pelo `revoke … from public` → ACL final idêntica. Harness 5858 ganhou B8 (dono `postgres` + ACL exata). Aplicar pelo mesmo canal da 5220 (dono `postgres`).
- **Transação:** cada arquivo é uma transação (`begin`…`commit`, precheck que aborta). As 4 combinações (5261 sim/não × 5262 sim/não) são compatíveis: colunas só acrescentadas ao final; frontend sem códigos → sem efeito. Falha da 5262 após a 5261 = galeria com brilho, detalhe sem brilho, sem erro.
- **Performance (inspeção estática):** um único listener delegado (`pointermove` passivo no documento + `pointerleave`), sem `useState`/re-render (só custom properties no nó sob o mouse, 1 escrita por quadro); camadas são componentes de servidor (2 `span` estáticos por carta com acabamento, máx. 48 por página); nenhuma animação em repouso; movimento reduzido: listener não registrado, reflexo e inclinação ocultos via CSS.
- **Visual:** intensidade 1× (0,42/0,8 holo; 0,38/0,65 reversa); PIKACHU_RARE e geometrias não confirmadas sem efeito (salvo carta secreta); Cosmos e reversas com padrão = arco-íris genérico no lugar físico certo (aproximação registrada). `HoloCard`, Catálogo e Pesquisa não alterados.

## 6. Execução LIVE (MY-INVENTORY-HOLOGRAPHIC-FINISH-LIVE-EXECUTION-01, 2026-10-24) — STOP na Seção C

- Autorização de Fabrício: "Autorizo a aplicação da 5261 e 5262".
- **5261 aplicada** — ledger `20261024185908` (arquivo md5 `5b68560e…`, conteúdo integral, sem alteração). **5262 aplicada** — ledger `20261024185943` (md5 `2ab0eada…`).
- **5858 B: 8/8 ok** (B1–B8, incluindo dono `postgres` e ACL `{postgres=X/postgres,authenticated=X/postgres}`).
- **5858 C: inconclusiva.** A8 (detalhe) idêntica (`c9bd957c…`); A1–A7 divergem da linha de base pré-aplicação. Causa observada: o acervo de teste estava recebendo cadastros durante a janela (121 exemplares criados nos 30 min anteriores; último 1,3 s antes da consulta; total 1.665). Divergência não atribuível às migrations com a evidência atual → STOP conforme mandato.
- **5858 D: não executada** (interrompida no STOP).
- Nenhuma correção nem rollback executados.

## 7. Pós-check de recuperação (MY-INVENTORY-HOLOGRAPHIC-FINISH-LIVE-POSTCHECK-RECOVERY-01, 2026-10-24) — GO frontend

Cadastros pausados por Fabrício. Tudo somente leitura. A Seção C original (§6) permanece **INCONCLUSIVA** — não reclassificada. Seção B não repetida (estado inalterado, ver abaixo).

**Estado conferido:** ledger `20261024185908` (5261) e `20261024185943` (5262); md5 dos corpos no LIVE = arquivos (`58f341e8…` / `d8cce43b…`); dono `postgres` e ACL `{postgres=X/postgres,authenticated=X/postgres}` inalterados; acervo de teste 1.741 exemplares, último criado/alterado 19:10:44 UTC — sem escrita durante as leituras (19:11:53 → 19:14:07).

**Estabilidade operacional (Seção C ×2, 19:12:11 e 19:12:28 UTC) — PASS, idênticas:**

| Caso | Linhas | Impressão (execuções 1 = 2) |
|---|---|---|
| A1 | 96 | `3cefd4dd308997443490beb95082dd8d` |
| A2 | 96 | `22ab2978815bc237f60e2f36eface474` |
| A3 | 96 | `7816452badfd168a0489504dbed9c08e` |
| A4 | 96 | `29773c1b3ba4a2e54239af939ba97c24` |
| A5 | 96 | `98b3d92ab1df7f2429800b654acfbe24` |
| A6 | 96 | `369c475f493b4c9fcb8db0c0a4bd1374` |
| A7 | 96 | `22ab2978815bc237f60e2f36eface474` (= A2, acervo todo pt-BR) |
| A8 | 43 | `bd399ba623315ea1b7d5f8f8fa152da3` |

**Equivalência lógica com 5220/5162 (documentada à parte, não medida em LIVE):** as funções anteriores não existem mais, então não há comparação direta antes/depois sob dados congelados. A prova é estática: diff de corpo = só 2 colunas novas na projeção final + `left join rarity` por PK (`card.rarity_id NOT NULL`, 0 cartas sem raridade → a junção não altera cardinalidade); FASE 1 (paginação/filtros/ordem/contagens) textualmente idêntica. Evidência LIVE auxiliar: A8 idêntica antes/depois da aplicação na janela original (`c9bd957c…`).

**Seção D — PASS:**

- D0: 1.148 grupos no acervo = 1.148 linhas lidas na galeria (todas as 12 páginas).
- D1/D2: `variant_type_code` e `rarity_code` = catálogo em 100 % das linhas da galeria; D3: nenhum código nulo.
- D4: detalhe (5262) em todos os 1.148 grupos → 1.741 linhas (= exemplares), códigos = catálogo; D4b: códigos constantes por grupo.
- Distribuição: STANDARD 624, HOLO 454, REVERSE_HOLO 68, COSMOS_HOLO 2 grupos.
- D5/D6: sem sessão → `28000 not_authenticated` nas duas funções.
- D7–D9: usuário B (inventário real, vazio, ≠ A) → galeria 0 linhas; detalhe nos 1.148 grupos de A → 0 linhas.
- D10–D12: sessão sintética sem inventário → galeria 0; detalhe nos grupos de A → 0.

## 8. Encerramento (ACERVO-HOLOGRAPHIC-FINISH-FINAL-CLOSEOUT-01, 2026-10-24)

- **Homologação:** Fabrício confirmou a aprovação visual em produção, intensidade 1×, na galeria e no detalhe do Meu acervo.
- **Promoção canônica:** `database/schema/5261_evolve_get_my_inventory_items_finish_codes.sql` e `database/schema/5262_evolve_get_my_inventory_item_copies_finish_codes.sql`; os arquivos desta pasta permanecem como evidência (byte a byte = texto do ledger).

| | Proposta (= ledger) | Canônica | Canônica com Status revertido | Corpo `begin;`→fim |
|---|---|---|---|---|
| 5261 | `5b68560e9060f3f96c00ba9f7d695fe5` | `4936de42e61905e41e20474e63443cb3` | `5b68560e…` (= ledger) | idêntico |
| 5262 | `2ab0eada31e6c7afaf9a778c9eed1cb6` | `e4584b4b8c2664aba899ee1afddab13a` | `2ab0eada…` (= ledger) | idêntico |

Ledger: `supabase_migrations.schema_migrations.statements` com 1 statement por versão, md5 = arquivo da proposta. Corpo das funções no LIVE (`prosrc`) = corpo dos arquivos (`58f341e8…` / `d8cce43b…`, conferido na §7). Cabeçalhos de `5220` e `5162` em `database/schema/` anotados como SUPERADAS (só documentação).

- **Não executado:** harness completo além das Seções A–D registradas; medição de desempenho.
- **Limitações registradas:** equivalência com 5220/5162 por prova estática; isolamento cruzado sem segundo acervo com cartas; desempenho não medido.
