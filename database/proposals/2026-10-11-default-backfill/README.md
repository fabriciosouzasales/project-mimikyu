# CATALOG-VARIANT-DEFAULT-BACKFILL-01 — variante padrão por carta

| Campo | Valor |
|---|---|
| **Status** | **EXECUTADA / CLOSED** (2026-10-11, LIVE `qjfutqujxrbzgrtkpgkg`) |
| **Sequência** | ROADMAP, item 6: ME5.5 ✔ → BOOTSTRAP-03 closeout ✔ → **DEFAULT-BACKFILL-01** → Pricing 80 → gate final de Card Variants |
| **Decisões de Fabrício (2026-10-11)** | Cartas só com versão reverse: "Default = única versão". Empates reais: "Deixar sem default". |
| **Artefato** | `database/migrations/2258_default_backfill_card_variant.sql` (CONFIRMADO EXECUTADO) · regra em `docs/05b-cartas-e-raridade.md` revisão 1.9 |

## 1. Diagnóstico (LIVE, antes)

- 21.166 cartas ativas, todas com ao menos uma variante (BOOTSTRAP-03 closeout).
- 926 já tinham padrão (seeds `860`/`860a`/`860b`, ME1–ME4/MEE/MEP, julho de 2026). Ficaram intactas.
- **20.240 sem padrão**: 6.583 com uma variante só e 13.657 com várias.
- `variant_order = 1` **não serve** como padrão: é ordem de importação. Em 3.263 cartas com várias
  variantes a primeira é `REVERSE_HOLO`.
- Quem lê `is_default` hoje: só exibição (`admin_get_pricing_mapping_detail`, `web/lib/pricing/queries.ts`).
  O resolver de preço e as RPCs de Collections não usam o campo, então o backfill não muda nenhum
  vínculo existente. O consumidor previsto é o registro de um Set inteiro (`REGISTER_CARD_SET`, BULK-04).

## 2. Regra

Ordem lexicográfica, aplicada a cada carta sem padrão:

1. **Acabamento:** STANDARD → HOLO → outros não-reverse → família reverse (só quando é a única opção).
2. **Edition Context:** sem contexto → simples → composto (mais componentes `__`).
3. **Printing:** sem perfil ou `UNLIMITED` → qualquer outro.

Mais de uma variante empatada na primeira posição: a carta fica sem padrão.

## 3. Execução e postcheck (CONFIRMADO EXECUTADO, 2026-10-11)

1. Dry-run do bloco inteiro abortado de propósito no final: 20.240 elegíveis, 20.227 atribuíveis, 13 empates.
2. Migration `2258` (lock `SHARE ROW EXCLUSIVE` em `card_variant`; P1 contagem exata e zero carta com
   dois padrões; P2 sobram exatamente os empates). 192 linhas em `catalog_admin_action_log`
   (`CARD_SET_UPDATED`, `metadata.operation = DEFAULT-BACKFILL-2258`, contagem por acabamento).

| Verificação | Resultado |
|---|---|
| Padrões atribuídos | 20.227 (STANDARD 12.952 · HOLO 6.908 · outros acabamentos 338 · só-reverse 29) |
| `card_variant` com `is_default` | 926 → **21.153** |
| Cartas com mais de um padrão | 0 |
| Cartas ativas sem padrão | 20.240 → **13** |

```sql
select count(*) from public.card c where c.is_active and not exists
  (select 1 from public.card_variant v where v.card_id = c.id and v.is_default);  -- esperado 13
```

## 4. As 13 cartas sem padrão (decisão editorial pendente)

| Set | Nº | Carta | Candidatas empatadas |
|---|---|---|---|
| BASEP | 02 | Electabuzz | STANDARD First Movie · First Movie Inverted |
| BASEP | 03 | Mewtwo | STANDARD First Movie · First Movie Inverted |
| BASEP | 04 | Pikachu | STANDARD First Movie · First Movie Inverted · Pikachu World 2000 |
| BASEP | 05 | Dragonite | STANDARD First Movie · First Movie Inverted |
| DP3 | 131 | Gardevoir | STANDARD deck Jason Klaczynski · deck Michael Pramawat |
| EX1 | 005 | Delcatty | STANDARD deck Chris Fulop · Kevin Nguyen · Reed Weichler |
| HGSS4 | 096 | Magnezone | STANDARD deck David Cohen · Gustavo Wada |
| MFB | 33 | Potion | STANDARD decks Bulbasaur · Charmander · Pikachu · Squirtle |
| MFB | 34 | Switch | STANDARD decks Bulbasaur · Charmander · Pikachu · Squirtle |
| SV3 | 022 | Toedscruel ex | STANDARD Gym Challenge · Player Rewards |
| SVP | 101 | Pikachu | STANDARD Asia 2023/24 · Player Rewards |
| HGSSP | HGSS10 | Latias | COSMOS_HOLO · CRACKED_ICE_HOLO |
| HGSSP | HGSS11 | Latios | COSMOS_HOLO · CRACKED_ICE_HOLO |

Para fechar uma delas: escolher a variante e marcar `is_default = true` (uma linha por carta).

## 5. Pendência para o gate final

Variantes criadas depois de 2026-10-11 (novas importações) nascem com `is_default = false`. Uma carta
nova com variantes ficará sem padrão até alguém aplicar a regra. Antes de fechar Card Variants é
preciso decidir como a regra roda nas cargas futuras (por exemplo, no fechamento de cada importação).
