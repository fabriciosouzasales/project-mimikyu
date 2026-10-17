# MEP — imagens em inglês pela Scrydex (2026-10-17, `CATALOG-MEP-REFRESH-01` Etapa 3)

| Campo | Valor |
|---|---|
| **Status** | **EXECUTADA / CLOSED (2026-10-17).** Deploy por Fabrício via CLI; probe 51/51 `DISPONIVEL`; importação 51 `IMPORTADA`, 0 falha; portão fechado sozinho. |
| **Mandato** | Fabrício, 2026-10-17: "Siga" (Etapa 3: imagens EN da Scrydex para as cartas novas do MEP; não há fonte pt). |
| **Mecanismo** | Edge Function pontual `supabase/functions/import-scrydex-assets-3` + portão `oneshot_operation_gate` código `SCRYDEX_ASSETS_2026_10_17_MEP`. Cópia de `import-scrydex-assets-2` (CATALOG-ASSETS-SCRYDEX-02); só mudam o portão e a tabela. |

## Escopo (51 cartas)

Cartas ativas do MEP sem `CARD_FRONT` em inglês no LIVE (conferido em 2026-10-17): 046–063, 072–073 e
081–088 (Etapa 1, TCGdex sem imagem) e 089–110 e 120 (Etapa 2, migration 2275). As 60 cartas com imagem
manual (pt-BR e en) ficam de fora e não são tocadas.

Tabela fixa em `plan.ts`, montada da página pública da expansão na Scrydex, com conferência de nome. Casos
especiais: 092 → `mep-92wcs` e 093 → `mep-93ws` (imagens com selo, iguais às variantes padrão do catálogo);
nomes pt ≠ en: Exeggutor de Alola, Resort Paraíso, Fanfarra de Celebração.

## Execução

1. Deploy (Fabrício): `supabase functions deploy import-scrydex-assets-3 --project-ref qjfutqujxrbzgrtkpgkg`
2. Portão (agente): `INSERT INTO public.oneshot_operation_gate (code, enabled, enabled_at) VALUES ('SCRYDEX_ASSETS_2026_10_17_MEP', true, now());`
3. Probe `{"mode":"probe"}`: esperado 51 `DISPONIVEL`, 0 nome divergente.
4. Importação `{}`: um lote (51 ≤ 120); o portão fecha sozinho.

Resultado esperado:

```sql
select count(*) from public.card c
 where c.card_set_id = '5c106d7c-c001-4f09-85c6-087c6ed0a925' and c.is_active and not exists (
   select 1 from public.card_asset a join public.card_asset_type t on t.id = a.asset_type_id
     join public.language l on l.id = a.language_id
    where a.card_id = c.id and t.code = 'CARD_FRONT' and a.is_active and l.code = 'en');
-- antes: 51 · esperado depois: 0
```

pt-BR: sem fonte para estas 51 cartas (TCGdex pt não tem imagem); seguem pelo canal manual.

## Execução (CONFIRMADO EXECUTADO, 2026-10-17)

1. Deploy: Fabrício, `supabase functions deploy import-scrydex-assets-3` (3 arquivos).
2. Portão `SCRYDEX_ASSETS_2026_10_17_MEP` criado; chamadas via `pg_net` com a chave anon legada (o portão é a
   autorização), como nas rodadas anteriores.
3. Probe: **51/51 `DISPONIVEL`**, 0 nome divergente, 0 carta ausente.
4. Importação (1 lote): **51 `IMPORTADA`**, 0 falha; `remaining = 0`; portão `enabled = false`.

## Postcheck (LIVE)

| Verificação | Resultado |
|---|---|
| Cartas do MEP sem `CARD_FRONT` en | 51 → **0** |
| Primário duplicado por carta/tipo/idioma no MEP | **0** |
| Imagens manuais do MEP (pt-BR + en) | **115**, intactas |
| Página do Set no Catálogo | Inglês 111/111; Português 55/111 |

Pendente fora desta etapa: imagens pt-BR das 56 cartas sem fonte (canal manual).
