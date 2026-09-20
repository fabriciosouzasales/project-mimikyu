# AUDITORIA DE READ MODELS — impacto do terceiro eixo

**`WRITE-PATH-STAGING-01`, item 12.** Classifica todo consumidor de leitura
em duas classes, e só duas:

- **A — OBRIGATÓRIO PARA INTEGRIDADE AGORA.** Sem a mudança, o pacote
  produz ou exibe dado errado.
- **B — NECESSÁRIO APENAS PARA UX POSTERIOR.** Sem a mudança, o dado
  continua correto; o que falta é visibilidade.

> Instrução literal do mandato: *"Não alterar Collections read models nesta
> rodada se não forem necessários para integridade."* A conclusão desta
> auditoria é que **nenhum read model de Collections precisa mudar** — e a
> prova é negativa e verificável, não uma afirmação.

---

## Método

Três buscas literais sobre o repositório, não inferência:

```
grep -rln "printing_profile_id"  database/schema/
grep -rln "printing_profile_id"  web/ --include=*.ts --include=*.tsx
grep -rn  "variant_type_id"      database/schema/5*.sql database/schema/6*.sql
grep -rn  "variant_type_id"      web/ --include=*.ts --include=*.tsx
```

O critério de classificação é **como o consumidor identifica um Card
Variant**:

| Forma de identificar | Impacto do eixo novo |
|---|---|
| por `card_variant.id` (FK) | **nenhum** — a identidade é opaca |
| reconstruindo a tupla `(card_id, variant_type_id, …)` | **direto** |
| lendo `normalized_data` do staging | **direto** |

---

## Resultado 1 — `printing_profile_id` não sai do Catálogo Editorial

Dez arquivos, **todos** em `database/schema/2*.sql`:

```
2138 2143 2145 2166 2170 2171 2176 2181 2189 2193
```

`web/` → **zero ocorrências**.

**Consequência.** O eixo de Impressão, que existe no LIVE desde 2026-09,
**nunca foi exposto a nenhum read model nem a nenhuma tela**. O eixo de
Contexto de Edição nasce na mesma posição. Um eixo que nenhuma leitura
enxerga não pode quebrar nenhuma leitura.

Esta é a prova negativa central desta auditoria: o precedente do eixo 1 já
demonstrou, em produção, que adicionar um eixo de identidade ao
`card_variant` não toca a camada de leitura.

## Resultado 2 — `variant_type_id` fora do range 2xxx

| Arquivo | Linha | Natureza | Classe |
|---|---|---|---|
| `5084_…master_set_scope_positions` | 124 | `JOIN card_variant_type cvt ON cvt.id = cv.variant_type_id` — busca o **nome** para exibição; a Variant já veio por `id` | — |
| `5104_…add_unique_id_card` | 39 | comentário de precheck histórico | — |
| `6050_…pokedex_external_reference` | 39 | comentário | — |

**Nenhuma reconstrução de identidade.** O único uso executável (5084) parte
de uma `card_variant` já resolvida por `id` e busca o rótulo do Variant
Type. Acrescentar uma quarta coluna à identidade não altera nem a linha que
ele encontra nem o rótulo que ele exibe.

## Resultado 3 — Collections read models

`5070` · `5071` · `5083` · `5084` · `5100` · `5101` · `5102` · `5103`

Todos alcançam `card_variant` por `id`, via as FKs de `physical_card`,
`collection_allocation` e `collection_master_set_scope`. Nenhum deles
monta, compara ou agrupa pela tupla de identidade.

> **Veredito: nenhum é classe A. Nenhum é alterado nesta rodada.**

---

## Resultado 4 — `web/`: os três pontos reais

| Ponto | O que faz | Classe | Ação |
|---|---|---|---|
| `web/lib/catalogo/queries.ts:3004, 3027` | lê `normalized_data.variant_type_id` das linhas de staging para exibir o nome do Variant Type na tela de revisão | **B** | nenhuma nesta rodada |
| `web/components/catalogo/revisao-importacao-variantes-table.tsx:208, 679` | rotula a linha como "resolvido" × "Sem mapeamento" conforme aquele campo | **B** | nenhuma nesta rodada |
| `web/app/catalogo/importar-variantes/actions.ts:209, 264` | passa `p_variant_type_id` para a RPC de mapeamento e lê o retorno | **B** | nenhuma nesta rodada |

### Por que B e não A — e o que muda de fato na tela

Com o contrato novo, uma linha cujo Contexto de Edição esteja indeterminado
**deixa de carregar `variant_type_id`** (outcome C das Queries 2221/2222,
partição A-BLOQUEADO da 2219). A tela passará a mostrar "Sem mapeamento"
para linhas que hoje mostram um Variant Type resolvido.

Isso **não é regressão** — é a correção do defeito. Hoje a tela afirma
"resolvido" para uma linha cuja identidade canônica está incompleta: o
rótulo é otimista e a linha não seria confirmável. Depois, o rótulo passa a
ser verdadeiro.

O que **falta**, e é legítimo que falte nesta rodada, é o rótulo
*específico*: o revisor verá "Sem mapeamento" sem saber que a causa é o
eixo 3, não o Variant Type. É UX, não integridade — e o dado para
diferenciar já está sendo produzido:

- `variant_type_mapping_decision` (Query 2220) devolve o `block_reason`
  `EDITION_CONTEXT_UNRESOLVED` com detalhe;
- `admin_resolve_…_printing_mapping` (2221) e o worker de backfill (2222)
  gravam `rows_blocked_edition_context` no `catalog_admin_action_log`.

Ou seja: a rodada de UX posterior consome contadores e razões que **já
existem**; não precisará de nenhuma migration nova.

---

## Classe A — a lista completa

**Vazia para read models.** Os únicos artefatos classe A desta rodada são de
CAMINHO DE ESCRITA, e todos já estão escritos:

| Artefato | Papel |
|---|---|
| `2218` | confirm — tri-state dos dois eixos, matching quádruplo, corrida benigna |
| `2219` | propagation — partição A-RESOLVIDO / A-BLOQUEADO |
| `2220` | contrato de leitura ADMINISTRATIVO (`…_impact` / `…_decision`) — é leitura, mas é leitura que **decide escrita**, por isso classe A |
| `2221` | resolução de mapeamento de Impressão + reavaliação |
| `2222` | criação de Perfil de Impressão + backfill |
| Edge patch | chave de matching 3→4 e as três chaves em `normalized_data` |

`2220` merece a nota: é o único read model classe A do pacote. Não alimenta
tela — alimenta a decisão de aplicar um mapeamento. Um `block_reason`
errado ali vira escrita errada adiante.

---

## Verificação independente do índice de identidade

Durante esta auditoria surgiu uma dúvida legítima: o precheck da Query
`5104` (linha 39, datado de 2026-09-06) lista

```
uq_card_variant_card_type  UNIQUE (card_id, variant_type_id)
```

como existente. Se esse índice de DUAS colunas tivesse sobrevivido, a
identidade de QUATRO seria letra morta — ele proibiria duas Variants que
difiram apenas em tiragem ou contexto.

**Confirmado que não sobreviveu, e que a prova é automática.** A Query
`2171` o removeu (`ALTER TABLE … DROP CONSTRAINT uq_card_variant_card_type`,
linha 92) ao introduzir os dois índices parciais de Printing. E a prova
final da `2215` (linhas 100-112) **não é uma lista de nomes**: ela conta
todos os índices únicos de `card_variant` que contenham a coluna
`variant_type_id` e exige exatamente **1**.

```sql
SELECT COUNT(*) INTO v_ident
  FROM pg_index i ...
 WHERE i.indrelid = 'public.card_variant'::REGCLASS
   AND i.indisunique
   AND EXISTS (... a.attname = 'variant_type_id');
IF v_ident <> 1 THEN RAISE EXCEPTION 'IDENTITY_NOT_UNIQUE_SOURCE' ...
```

Qualquer índice legado de identidade — inclusive um que ninguém lembrou de
listar — faz a contagem ir a 2 e aborta. O gate é exaustivo por construção,
não por memória. Nenhuma correção necessária.
