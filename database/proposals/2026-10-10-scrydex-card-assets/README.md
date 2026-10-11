# CATALOG-ASSETS-SCRYDEX-01 — imagens das cartas que a TCGdex não publica

| Campo | Valor |
|---|---|
| **Status** | **EXECUTADA / CLOSED** (2026-10-10, LIVE `qjfutqujxrbzgrtkpgkg`) |
| **Mandato** | Fabrício, 2026-10-10: "trazer para nossa base as 905 imagens de cartas que não conseguimos importar direto da API". Fonte escolhida por ele: **Scrydex**. Pares a/b de Aquapolis e My First Battle: **ficam pendentes**. |
| **Mecanismo** | Edge Function pontual `supabase/functions/import-scrydex-assets` (v2) + portão `oneshot_operation_gate` código `SCRYDEX_ASSETS_2026_10_10`. Mesmo desenho de `import-classic-collection-assets` (ME5.5CC/CEL25CC), adaptado para lotes. |
| **Exceção registrada** | O ROADMAP (bloco `ASSETS-FINAL-CLOSEOUT`, 2026-09-11) proibia nova busca de fonte de Assets sem mandato explícito. Este é o mandato. |

## 1. Diagnóstico (LIVE, antes)

905 cartas ativas sem `CARD_FRONT` ativo em nenhum idioma, em 44 Card Sets.

| Grupo | Cartas | Por que não tinham imagem |
|---|---|---|
| Trainer Kits (TK-EX/DP/HS/BW/XY/SM, 22 Sets) | 445 | Sem `card_external_reference`; nenhuma execução de asset |
| McDonald's 2011–2023 (11 Sets) | 151 | Idem |
| SM7.5 Dragões Soberanos | 78 | Importado em pt; sem execução de asset |
| EX5.5 (Poké Card Creator Pack) / XY10 | 5 / 4 | Idem |
| SMP, ECARD2, ECARD3, MFB, HGSSP, BWP, XYP, POP6, PL2, XY8 | 192 | Execução TCGdex `COMPLETED_WITH_ERRORS` (404 da TCGdex) |

**Evidência de que a TCGdex não publica:** no JSON da TCGdex guardado em `catalog_import_row.raw_data`,
903 das 905 cartas vêm **sem** o campo `image` (as 2 restantes, de XY10, apontam para `pt`); as
execuções de asset que existiam falharam exatamente nessas cartas. Ressalva: para os Sets importados
em pt (SM7.5, SMP, XY10, XY8), a ausência em inglês na TCGdex é provável, não provada.

## 2. Fonte e correspondência

- **Scrydex** (`images.scrydex.com/pokemon/<id>/large`), o mesmo servidor de imagens já usado na ME5.5CC.
- A tabela fixa `supabase/functions/import-scrydex-assets/plan.ts` (43 Sets, **863 cartas**) foi montada
  a partir das páginas públicas de expansão `scrydex.com/pokemon/expansions/<slug>/<id>` (lidas por
  `web_fetch`), cruzadas com as cartas pendentes do LIVE **por Set + número**, com **conferência de
  nome em 863/863** (nomes pt de SM7.5/SMP/XY10/XY8 traduzidos e conferidos contra o inglês da Scrydex;
  zero divergência, zero correspondência por aproximação).
- De/para dos Trainer Kits (conferido pelos nomes): TK-EX-LATIA `tk1a`, TK-EX-LATIO `tk1b`, TK-EX-P `tk2a`,
  TK-EX-M `tk2b`, TK-DP-M `tk3a`, TK-DP-L `tk3b`, TK-HS-R `tk4a`, TK-HS-G `tk4b`, TK-BW-Z `tk5a`,
  TK-BW-E `tk5b`, TK-XY-SY `tk6a`, TK-XY-N `tk6b`, TK-XY-W `tk7a`, TK-XY-B `tk7b`, TK-XY-LATIO `tk8a`,
  TK-XY-LATIA `tk8b`, TK-XY-SU `tk9a`, TK-XY-P `tk9b`, TK-SM-L `tk10a`, TK-SM-R `tk10b`.
  McDonald's `20xx` → `mcdYY`; EX5.5 → `wb1`; HGSSP → `hsp`.

## 3. Contrato da Edge Function

- Sem entrada do chamador além de `{}` ou `{"mode":"probe"}`; cartas e URLs fixas em `plan.ts`.
- Só roda com o portão habilitado. Exclusão mútua por **lease** (`consumed_at` nulo ou > 5 min) com
  atualização condicional atômica; cada chamada processa até 120 cartas (6 downloads simultâneos) e libera
  o lease; ao zerar as pendências fecha o portão (`enabled = false`).
- `probe`: só `HEAD` nas URLs pendentes, não grava nada.
- Fail closed por carta (nome divergente, carta ausente, HTTP ≠ 2xx, MIME não suportado, < 1 KB);
  idempotente (pula carta que já tem `CARD_FRONT` ativo em qualquer idioma; upload com upsert; referência
  externa com upsert por carta+fonte+idioma).
- Grava: bucket `card-front`, caminho `<set>/en/<numero>.png`, `card_asset` (`source_code = POKEMON_TCG_API`,
  `source_reference = <id Scrydex>`, idioma `en`, primário) e `card_external_reference`
  (`asset_source = POKEMON_TCG_API`, `metadata = {operation, provider: scrydex, provider_name}`) —
  mesmo precedente da ME5.5CC. A tela já usa a imagem `en` quando não há `pt-BR` (`pickCardFrontPath`).
- `verify_jwt = true`; chamadas feitas via `pg_net` com a chave anon legada (o portão é a autorização).

## 4. Execução (CONFIRMADO EXECUTADO, 2026-10-10)

1. Deploy da função. A v1 subiu com um `plan.ts` incompleto (erro de montagem do deploy); como o portão
   ainda não existia, nada rodou. A v2, com o `plan.ts` idêntico ao do repositório, foi redeployada em seguida.
2. Portão: `INSERT INTO public.oneshot_operation_gate (code, enabled, enabled_at) VALUES ('SCRYDEX_ASSETS_2026_10_10', true, now());`
3. Probe: **863/863 `DISPONIVEL`**, 0 nome divergente.
4. Importação: 8 lotes (7 × 120 + 23), **863 `IMPORTADA`, 0 falha**; portão fechado automaticamente
   (`remaining = 0`, histórico dos lotes em `result.batches`).

## 5. Postcheck (LIVE)

| Verificação | Resultado |
|---|---|
| `card_external_reference` com `metadata.operation = SCRYDEX_ASSETS_2026_10_10` | 863 |
| `card_asset` ativos/primários correspondentes | 863 (todos `image/png`, 96 KB–1,9 MB, ≈ 739 MB) |
| Cartas ativas ainda sem `CARD_FRONT` | **42** = MFB 34 + ECARD2 8 (pendências decididas) |
| Portão | `enabled = false`, `remaining = 0` |

Consulta de confirmação:

```sql
select count(*) from public.card c
 where c.is_active and not exists (
   select 1 from public.card_asset a join public.card_asset_type t on t.id = a.asset_type_id
    where a.card_id = c.id and t.code = 'CARD_FRONT' and a.is_active);
-- esperado: 42
```

## 6. Pendências (decididas, fora desta operação)

- **ECARD2 50a/50b, 74a/74b, 95a/95b, 103a/103b (8):** a Scrydex só publica uma imagem por número
  (`ecard2-50` etc.); falta decidir se a mesma imagem serve para as duas versões. Candidato ao canal manual (ADR-026).
- **MFB — My First Battle (34):** não existe na Scrydex nem com imagem na TCGdex. Candidato ao canal manual (ADR-026).

## 7. Artefatos

- `supabase/functions/import-scrydex-assets/index.ts`, `plan.ts`, `deno.json` (deploy v2).
- Nenhuma migration: o portão reutiliza a tabela da 2253; a linha do portão é dado operacional registrado acima.
