# DESENHO DE CONCORRÊNCIA — identidade de 4 componentes

**BLOCKER 8.** Nenhum caminho pode depender de erro cru `23505` e nenhum erro
cru pode chegar à UI. Medido em rodada anterior: **nenhuma** das funções que
tocam `card_variant` trata `unique_violation` hoje — todas dependem de guard
prévio. (O rótulo "12 funções" da v1.0 vinha do inventário achatado que a
`CORRECTION-01` substituiu por 5 categorias; ver `IMPACTED-CONTRACTS.md`.)

## Onde cada coisa acontece

| Etapa | Onde | Mecanismo |
|---|---|---|
| **Matching** | `public.admin_confirm_catalog_variant_import` (Query **2218**) | `SELECT` pela identidade de 4 componentes, com `IS NOT DISTINCT FROM` nos dois eixos nuláveis |
| **Lock** | idem (**2218**) | `SELECT … FROM public.card WHERE id = p_card_id FOR UPDATE` — lock na **Card**, não na Variant, porque `variant_order` também é alocado por Card |
| **Ordem de aquisição** | idem | **um único** objeto de lock por transação de escrita de Variant, sempre `public.card`. Lote de várias Cards ⇒ `ORDER BY id` no `FOR UPDATE`, para que duas transações concorrentes adquiram na mesma ordem. Sem isso, um lote A→B e outro B→A fecham deadlock |
| **Alocação de `variant_order`** | idem (**2218**), sob o mesmo lock | `MAX(variant_order)+1` |
| **Escrita** | `internal.write_card_variant` (Query **2217**) | `INSERT` puro, 7 argumentos |

> **Correção da `GATE-A-FINAL-CORRECTION-01`.** A versão anterior colocava
> matching e lock em `write_card_variant`. **Não é onde eles estão.** A
> leitura da canônica `2143` v2.0 mostra um `INSERT` puro: sem `SELECT` de
> matching, sem lock, sem alocação de ordem — o próprio cabeçalho diz que
> `p_variant_order` *"é sempre calculado pelo chamador (Query 2145)"*.
> Logo tudo o que é concorrência pertence ao **confirm** (`2218`), e o
> writer (`2217`) permanece deliberadamente burro. Desenhar o lock no lugar
> errado teria produzido uma implementação que não protege nada.

O lock na Card serializa as duas operações que competem — matching de
identidade e alocação de ordem — com **um** único objeto de lock, evitando
deadlock por ordem de aquisição.

## Corrida entre duas transações com a mesma identidade

```
T1: lock card → match: nada → INSERT → COMMIT
T2:            ..bloqueada..  → lock card → match: ENCONTRA → UNCHANGED/MATCHED
```

O lock elimina a corrida na prática. `unique_violation` passa a ser
**rede de segurança**, não caminho esperado:

```sql
EXCEPTION
  WHEN unique_violation THEN
    -- Reentrada: relê pela identidade de 4 componentes.
    SELECT id INTO v_existing FROM public.card_variant
     WHERE card_id = p_card_id
       AND variant_type_id = p_variant_type_id
       AND printing_profile_id        IS NOT DISTINCT FROM p_printing_profile_id
       AND edition_context_profile_id IS NOT DISTINCT FROM p_edition_context_profile_id;

    IF v_existing IS NOT NULL THEN
        RETURN (v_existing, 'UNCHANGED');          -- corrida benigna
    END IF;

    -- Não achou pela identidade: a violação veio de OUTRA constraint
    -- (uq_card_variant_card_order ou one_default_per_card) => erro sistêmico.
    RAISE EXCEPTION 'CARD_VARIANT_IDENTITY_CONFLICT_UNRESOLVED: violacao de unicidade em % nao explicada pela identidade de 4 componentes.', p_card_id;
```

## Classificação determinística

| Situação | Resultado | Chega à UI como |
|---|---|---|
| Identidade já existe no matching | `UNCHANGED` / `match_status = MATCHED` | "já existente" |
| Corrida perdida, identidade reencontrada | `UNCHANGED` | idem — indistinguível |
| `23505` de `uq_card_variant_card_order` | **erro sistêmico** | `CARD_VARIANT_IDENTITY_CONFLICT_UNRESOLVED` |
| `23505` de `one_default_per_card` | **erro sistêmico** | idem |
| `23505` do staging (`uq_cvir_row_identity`) | erro de negócio | `CVIR_DUPLICATE_ROW_IN_JOB` |

## Regra terminal

`admin_confirm_catalog_variant_import` já captura `EXCEPTION WHEN OTHERS` por
row e grava `persistence_status='FAILED'` + `error_detail`. **Nenhum SQLSTATE
cru sobe para a UI**: o pior caso vira uma linha `FAILED` com mensagem de
negócio, e o job continua. Este contrato é preservado.
