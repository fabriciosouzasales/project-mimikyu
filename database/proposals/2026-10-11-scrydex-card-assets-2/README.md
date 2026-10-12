# CATALOG-ASSETS-SCRYDEX-02 — imagens em inglês que ainda faltam (Importar Imagens)

| Campo | Valor |
|---|---|
| **Status** | **EXECUTADA / CLOSED** (2026-10-11, LIVE `qjfutqujxrbzgrtkpgkg`). Deploy pelo Fabrício via CLI (a ferramenta de deploy do agente recusou os parâmetros) |
| **Mandato** | Fabrício, 2026-10-11: 1. importar pela Scrydex — "Pode"; 2. a/b de Aquapolis com a mesma imagem — "Sim"; 3. SM2 143 — "Confirma o nome antes" |
| **Mecanismo** | Edge Function pontual `supabase/functions/import-scrydex-assets-2` + portão `oneshot_operation_gate` código `SCRYDEX_ASSETS_2026_10_11`. Mesmo desenho da `CATALOG-ASSETS-SCRYDEX-01` (`2026-10-10-scrydex-card-assets`) |

## 1. Diagnóstico (LIVE)

Importar Imagens com filtro EN mostrava **153** cartas sem imagem. A tela conta por idioma:

| Set | Cartas | Situação |
|---|---:|---|
| SM3.5 Lendas Luminescentes | 78 | têm imagem pt-BR, sem en |
| SM6 Luz Proibida | 6 (082, 090, 122, 126, 134, 140) | têm pt-BR, sem en |
| SM2 Guardiões Ascendentes | 1 (143) | tem pt-BR, sem en |
| EXU Unown Collection | 26 | sem imagem (TCGdex não publica) |
| ECARD2 a/b | 8 | sem imagem (uma imagem por número na fonte) |
| MFB My First Battle | 34 | sem fonte |

## 2. Correspondência (plan.ts, 119 cartas)

Páginas públicas de expansão da Scrydex lidas por `web_fetch`, cruzadas por Set + número com conferência de nome:
SM3.5 78/78 (nomes pt traduzidos: Luminescente = Shining, Hibi = Hau, Lílian = Lillie, Chris = Sophocles…);
SM6 6/6; EXU A–Z = `ex10-A…Z`; ECARD2 50a/50b→`ecard2-50`, 74a/b→74, 95a/b→95, 103a/b→103.

**SM2 143 (confirmação pedida):** catálogo "Pandam", Scrydex "Hala". O texto da carta na TCGdex pt (`sm2-143`):
"Embaralhe a sua mão no seu baralho. Se você usou o seu ataque GX, compre 7 cartas. Caso contrário, compre 4 cartas."
é o efeito de Hala. Os vizinhos seguem o mesmo padrão de tradução (144 Hibi = Hau, 145 Lulú = Mallow). **Confirmado: mesma carta.**

Fora: MFB (34, sem fonte), Unown "!" e "?" (aguardam decisão sobre o número; a Scrydex tem `ex10-exclamation` / `ex10-question`).

## 3. Diferença para a v1

Pendência = **sem `CARD_FRONT` ativo em inglês** (a v1 olhava qualquer idioma e pularia SM3.5/SM6/SM2). A imagem pt existente não é tocada; o primário é por idioma (`ux_card_asset_primary_per_card_type_language`).

## 4. Plano de execução

1. Deploy (Fabrício): `supabase functions deploy import-scrydex-assets-2 --project-ref qjfutqujxrbzgrtkpgkg`
2. Portão: `INSERT INTO public.oneshot_operation_gate (code, enabled, enabled_at) VALUES ('SCRYDEX_ASSETS_2026_10_11', true, now());`
3. Probe (`{"mode":"probe"}`): esperado 119 `DISPONIVEL`, 0 nome divergente.
4. Importação (`{}`): um lote (119 ≤ 120); o portão fecha sozinho.

Resultado esperado: EN sem imagem 153 → **34** (só MFB); cartas sem imagem em nenhum idioma 68 → **34**.

```sql
select count(*) from public.card c join public.card_set s on s.id = c.card_set_id
 where c.is_active and s.code in ('SM3.5','SM6','SM2','EXU','ECARD2') and not exists (
   select 1 from public.card_asset a join public.card_asset_type t on t.id = a.asset_type_id
     join public.language l on l.id = a.language_id
    where a.card_id = c.id and t.code = 'CARD_FRONT' and a.is_active and l.code = 'en');
-- esperado após a execução: 0
```

## 5. Execução (CONFIRMADO EXECUTADO, 2026-10-11)

1. Deploy: Fabrício, `supabase functions deploy import-scrydex-assets-2` (3 arquivos).
2. Portão criado; chamadas via `pg_net` com a chave anon legada (o portão é a autorização), como na v1.
3. Probe: **119/119 `DISPONIVEL`**, 0 nome divergente, 0 carta ausente.
4. Importação (1 lote): **119 imagens gravadas** (`card_asset` en, primário). 115 `IMPORTADA` + 4 marcadas `FALHOU`
   na etapa da referência externa: ECARD2 50b, 74a, 95b, 103b. A imagem dessas 4 foi gravada; a referência
   não, porque `uq_card_external_reference_source_external_language` admite uma carta por id da fonte e o par
   já a usa. É o resultado correto para a imagem compartilhada. Portão fechado à mão com nota em `result`.

## 6. Postcheck (LIVE)

| Verificação | Resultado |
|---|---|
| Cartas dos 5 Sets sem `CARD_FRONT` en | **0** |
| Cartas ativas sem `CARD_FRONT` en (catálogo todo) | 153 → **34** (só MFB) |
| Cartas ativas sem imagem em nenhum idioma | 68 → **34** (só MFB) |
| Primário duplicado por carta/tipo/idioma | 0 |
| Portão | `enabled = false` |

Pendentes: MFB (34, sem fonte, canal manual `ADR-026`); Unown "!" e "?" (decisão do número; imagem já localizada em `ex10-exclamation`/`ex10-question`).
