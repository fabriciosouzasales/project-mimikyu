# ME6 Reinado Delta — imagens em inglês pela Scrydex (2026-11-08)

| Campo | Valor |
|---|---|
| **Status** | **EXECUTADA / CLOSED (2026-11-08).** Deploy por Fabrício via CLI; portão aberto com autorização; probe 141/141 `DISPONIVEL`; importação 120 + 21 `IMPORTADA`, 0 falha; portão fechado sozinho. |
| **Mandato** | Fabrício, 2026-11-08: confirmar se a TCGdex não publicou as imagens do ME6 e, confirmado, obtê-las por outra fonte externa, como em outros Card Sets. Decisão: inglês agora pela Scrydex; português aguarda a TCGdex. |
| **Mecanismo** | Edge Function pontual `supabase/functions/import-scrydex-assets-4` + portão `oneshot_operation_gate` código `SCRYDEX_ASSETS_2026_11_08_ME6`. Cópia de `import-scrydex-assets-3` (MEP, 2026-10-17); só mudam o portão e a tabela. |

## Diagnóstico (2026-11-08, somente leitura)

- LIVE: `ME6` Reinado Delta, lançamento 2026-11-06, 141 cartas ativas (103 oficiais), **0 imagens** em pt-BR e em en.
- TCGdex (`/v2/pt/sets/me06` e `/v2/en/sets/me06`): 141 cartas, **nenhuma com `image`**, sem logo do Set; `assets.tcgdex.net/{pt,en}/me/me06/001/high.webp` não existe (o equivalente do ME5 existe).
- Scrydex (`scrydex.com/pokemon/expansions/delta-reign/me6`): 141 cartas; `images.scrydex.com/pokemon/me6-N/large` carregada para N = 1..141 (733 × 1024). Nome en de cada número **idêntico** ao da TCGdex en nas 141 linhas.
- Português: a única fonte encontrada com as 141 cartas é o site oficial (`assets.pokemon.com/.../cms2-pt-br/img/cards/web/ME06/ME06_PT-BR_N.png`), em **245 × 342 px** — menos da metade da resolução habitual (TCGdex `high`, 600 × 825). A Liga Pokémon bloqueia acesso automatizado (desafio Cloudflare; não contornado). Decisão de Fabrício: **pt aguarda a TCGdex**.

## Escopo

As 141 cartas ativas do ME6 sem `CARD_FRONT` ativo em inglês. Tabela fixa em `plan.ts` (número, nome no MMKYU, número Scrydex, nome Scrydex quando difere — 28 cartas de Treinador/Energia e Rotom Calor ex). Dois lotes (`BATCH_SIZE` 120).

## Execução

1. Deploy (Fabrício): `supabase functions deploy import-scrydex-assets-4 --project-ref qjfutqujxrbzgrtkpgkg`
2. Portão (agente, com autorização): `INSERT INTO public.oneshot_operation_gate (code, enabled, enabled_at) VALUES ('SCRYDEX_ASSETS_2026_11_08_ME6', true, now());`
3. Probe `{"mode":"probe"}`: esperado 141 `DISPONIVEL`, 0 nome divergente, 0 carta ausente.
4. Importação `{}` duas vezes (120 + 21); o portão fecha sozinho quando não sobra pendência.

Verificação:

```sql
select count(*) from public.card c join public.card_set cs on cs.id = c.card_set_id
 where cs.code = 'ME6' and c.is_active and not exists (
   select 1 from public.card_asset a join public.card_asset_type t on t.id = a.asset_type_id
     join public.language l on l.id = a.language_id
    where a.card_id = c.id and t.code = 'CARD_FRONT' and a.is_active and l.code = 'en');
-- antes: 141 · esperado depois: 0
```

Pendente fora desta etapa: imagens pt-BR (aguardam a TCGdex; reimportação pelo fluxo normal do Catálogo) e logo do Set.

## Execução (CONFIRMADO EXECUTADO, 2026-11-08)

1. Deploy: Fabrício, `supabase functions deploy import-scrydex-assets-4` (3 arquivos).
2. Portão `SCRYDEX_ASSETS_2026_11_08_ME6` criado (autorização de Fabrício); chamadas via `pg_net` com a chave anon legada (o portão é a autorização), como nas rodadas anteriores.
3. Probe: **141/141 `DISPONIVEL`**, 0 nome divergente, 0 carta ausente.
4. Importação: lote 1 **120 `IMPORTADA`**, lote 2 **21 `IMPORTADA`**, 0 falha; `remaining = 0`; portão `enabled = false`.

## Postcheck (LIVE)

| Verificação | Resultado |
|---|---|
| Cartas do ME6 sem `CARD_FRONT` en | 141 → **0** |
| Primário duplicado por carta/idioma no ME6 | **0** |
| `card_external_reference` da operação | **141** |
| Formato | PNG, média ~909 KB por carta (733 × 1024) |
| Cobertura do Set no Catálogo | Inglês 141/141; Português 0/141 |

Pendente: imagens pt-BR e logo do Set (aguardam a TCGdex; fluxo normal do Catálogo).
