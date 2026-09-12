# Staging — EXTERNAL-REFERENCE-READ-RPC-05

| Campo | Valor |
|---|---|
| **Mandato** | `ASSETS-FINAL-CDN-AUDIT-01 — EXTERNAL-REFERENCE-READ-RPC-05` |
| **Data** | 2026-09-11 |
| **Status** | **CONFIRMADO EXECUTADO / VALIDADO / PROMOVIDO** |
| **Depende de** | `SOURCE-404-CDN-PROOF-04` (auditor `web/scripts/bootstrap-cards/audit-assets-cdn.mjs`) |

---

## Incidente

O smoke real de XYP abortou:

```
FALHA_LER_EXTERNAL_REFERENCE:
permission denied for table card_external_reference
```

Auditoria LIVE confirmou: `card_external_reference` tem `RLS = true`, **nenhuma policy**, `authenticated` **sem** SELECT, SELECT apenas para `postgres`/`service_role`, e nenhuma RPC existente expõe a tabela.

**Isso é uma fronteira de segurança correta.** A tabela guarda a identidade de origem de todo o catálogo (31.793 linhas). A correção **não** é conceder SELECT direto, criar policy ampla, ou usar `service_role` num script local.

## Correção proposta

Uma única RPC READ-ONLY / ADMIN-ONLY, no padrão `admin_*` já consolidado (precedente: `1061_create_admin_list_users_function.sql`).

| Arquivo | O quê | Estado |
|---|---|---|
| `6127_create_admin_list_card_external_image_sources_function.sql` | v1.1 — A RPC + `REVOKE`/`GRANT` | **CONFIRMADO EXECUTADO / LIVE** · **PROMOVIDO** para `database/schema/` |
| `6840_validate_admin_list_card_external_image_sources.sql` | v1.2 — 5 checagens estruturais + 18 casos funcionais + zero resíduo | **EXECUTADO / PASS** — permanece AQUI como validação/prova, **não** é promovido |

---

## Encerramento (2026-09-11, `ASSETS — SCHEMA PROMOTION 6127`)

**`6127` — `CONFIRMADO EXECUTADO / LIVE`.** A RPC `public.admin_list_card_external_image_sources(uuid[], text, text)` está aplicada e ativa no projeto `qjfutqujxrbzgrtkpgkg`, com `SECURITY DEFINER`, `STABLE`, `SET search_path = ''`, guard `public.is_admin()` e `EXECUTE` apenas para `authenticated`.

**`6127` — `PROMOVIDO`.** Cópia **byte-idêntica** em `database/schema/6127_create_admin_list_card_external_image_sources_function.sql`. Nenhum caractere do SQL foi alterado na promoção — inclusive o cabeçalho, que segue exatamente como auditado e aplicado.

> **Divergência de cabeçalho — RESOLVIDA em 2026-09-11 (`HEADER RECONCILIATION`).** A promoção original copiou o `.sql` byte-a-byte, preservando `Status......: PROPOSTA — NÃO EXECUTADA` também na cópia canônica. Em rodada seguinte, autorizada especificamente para isso, a linha foi trocada por `Status......: CANÔNICA — CONFIRMADO EXECUTADO` **nos dois arquivos**, mantendo-os byte-idênticos entre si. Nenhuma outra linha e nenhum SQL executável mudou.
>
> **Residual encerrado em 2026-09-11 (`6840 STATUS RECONCILIATION`):** o cabeçalho de `6840_…sql` passou de `PROPOSTA — NÃO EXECUTADA` para `EXECUTADA — PASS`. A `6840` **não** é promovida para `database/schema/` — script de validação é prova, não estrutura.

**`6840` — `EXECUTADO / PASS`.** Seção 1 (5 checagens estruturais/segurança) sem exceção; Seção 2 (18 casos funcionais, `BEGIN`/`ROLLBACK`) concluída sem exceção; Seção 3 (zero resíduo) `0 | 0 | 0`, com verificação ampliada cobrindo também `card`, `card_asset` e objetos temporários — todas zero. **Permanece em `proposals/` como evidência histórica**, seguindo a convenção já aplicada a `6800`/`6810`/`6820`/`6830`: script de validação é prova, não estrutura.

### Harnesses associados (fora de `database/`)

| Arquivo | Resultado |
|---|---|
| `supabase/functions/import-card-assets/provas-promocao-image-source-url.ts` | **12/12** |
| `supabase/functions/import-card-assets/provas-asset-path-alias.ts` | **140/140** |
| `web/scripts/bootstrap-cards/provas-audit-assets-cdn.mjs` | **146/146** |

### HARDENING-CORRECTION-01 — cap por `cardinality`, não `array_length`

`array_length(arr, 1)` devolve o tamanho da **primeira dimensão**. Num `UUID[]` multidimensional o teto era contornável: `ARRAY[a, b]` com 400 elementos cada tem `array_length(.,1) = 2` (passa nos 500) e `cardinality() = 800` (o custo real do `= ANY`). Mesma classe já endurecida antes no projeto.

Ordem canônica dos guards, **toda antes do SELECT/ANY**:

1. `NULL` ou `cardinality = 0` → `RETURN` (sem erro);
2. `array_ndims <> 1` → `RAISE` (`ARRAY_NDIMS`);
3. `v_count := cardinality(p_card_ids)`;
4. `v_count > 500` → `RAISE` (`BULK_LIMIT`).

O passo 1 precede o 2 de propósito: array vazio não tem dimensão e `array_ndims('{}')` devolve `NULL` — checar forma primeiro transformaria o caso legítimo "lote vazio" em erro.

Consumidor alterado (fora deste diretório, já editado):
`web/scripts/bootstrap-cards/audit-assets-cdn.mjs` — `lerUrlsAutoritativas()` passa a chamar a RPC.
Harness: `web/scripts/bootstrap-cards/provas-audit-assets-cdn.mjs` — Bloco 12 novo (11 asserções, total 114 → **125**).

## Superfície exposta

```
admin_list_card_external_image_sources(
    p_card_ids         UUID[],
    p_language_code    TEXT,
    p_asset_source_code TEXT DEFAULT 'TCGDEX'
) RETURNS TABLE (card_id UUID, image_source_url TEXT, external_card_id TEXT)
```

- `SECURITY DEFINER`, `STABLE`, `SET search_path = ''`.
- Guard `IF NOT public.is_admin() THEN RAISE EXCEPTION` — **exception, não lista vazia**. Lista vazia seria pior: o auditor leria "identidade insuficiente" e devolveria INCONCLUSIVO por uma causa falsa (permissão, não ausência).
- Filtra `is_active`, idioma exato, fonte exata, e omite `image_source_url IS NULL`.
- Cap de 500 ids por chamada medido por `cardinality()`, com `RAISE EXCEPTION` (o consumidor usa lotes de 200). Truncar em silêncio seria fail-closed no veredito, mas mentiria sobre a causa.
- `p_card_ids` deve ser unidimensional — `UUID[][]` é rejeitado por forma.
- Zero DML.

### `external_set_id` é deliberadamente omitido

Não é economia de bytes — é uma **garantia de desenho**. Sem esse campo, o auditor fica *fisicamente* incapaz de reconstruir o path da CDN a partir do código do Set. A evidência dos subsets SWSH (`swsh4.5sv` → pasta real `swsh4.5`) prova que essa dedução é falsa. O teste 1.4 de 6840 trava isso: falha se `external_set_id` reaparecer no `RETURNS TABLE` ou no corpo.

### `external_card_id` é incluído — justificativa

Não é usado para montar URL. É evidência de rastreabilidade: quando a auditoria encontrar um `accessible_not_imported`, é o campo que liga o achado à carta na origem, e é exatamente onde a divergência catálogo↔CDN dos subsets aparece. **Se for considerado excesso, pode ser removido sem impacto no veredito** — só perde diagnóstico.

### `p_asset_source_code` — adição além do texto do mandato

O mandato pediu "somente os card_ids necessários + language_code". Acrescentei o filtro de fonte porque `image_source_url` é específico da fonte: hoje 100% das linhas são TCGDEX, mas sem o filtro uma segunda fonte futura devolveria URL de outro CDN para o mesmo Card. É **filtro**, não ampliação de exposição, e tem default. **Sinalizado explicitamente para aprovação ou remoção.**

## Grants propostos

```sql
REVOKE ALL ON FUNCTION public.admin_list_card_external_image_sources(UUID[], TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_list_card_external_image_sources(UUID[], TEXT, TEXT) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_list_card_external_image_sources(UUID[], TEXT, TEXT) TO authenticated;
```

Nenhum `GRANT` sobre `card_external_reference`. Nenhuma policy. Nenhum `ALTER TABLE`.

## Regressões travadas por 6840

**Fronteira (1.3)** — falha se alguém "resolver" o problema pelo caminho errado:

- `relrowsecurity` deixou de ser `true` → FALHA
- surgiu qualquer policy em `card_external_reference` → FALHA
- `authenticated` ou `anon` ganhou SELECT direto → FALHA

**Desenho (1.4)** — `external_set_id` reaparecendo no `RETURNS TABLE` ou no corpo → FALHA. DML no corpo → FALHA.

**Cap (1.5)** — `array_length(p_card_ids, ...)` voltando ao corpo → FALHA. Ausência de `cardinality(p_card_ids)` ou de `array_ndims(p_card_ids)` → FALHA.

## Numeração

`6127` livre (canônicos vão até `6126`). `6840` livre (validações em proposals: 6800/6810/6820/6821/6830).

## Ordem de execução (quando autorizada)

1. Aplicar `6127`.
2. Executar `6840` Seção 1 (estrutural/segurança).
3. Executar `6840` Seção 2 (funcional, termina em `ROLLBACK`).
4. Executar `6840` Seção 3 (zero resíduo) — esperado `0 | 0 | 0`.
5. Rodar `node web/scripts/bootstrap-cards/provas-audit-assets-cdn.mjs` → `125/125 OK`.
6. Só então repetir o smoke real de XYP.

## Estado

**`6127` APLICADA E PROMOVIDA; `6840` EXECUTADA COM PASS.** Ver "Encerramento", acima. Este bloco de "Ordem de execução" fica como registro do roteiro que foi de fato seguido.
