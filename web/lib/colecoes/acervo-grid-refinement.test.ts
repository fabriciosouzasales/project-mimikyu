import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import {
  type ConditionTally,
  GRID_CONDITION_CHIPS_MAX,
  GRID_CONDITION_CHIPS_NARROW,
  gridConditionDisplay,
  pageConditionMix,
} from "./condition-distribution.ts";

const read = (path: string) => readFileSync(new URL(`../../${path}`, import.meta.url), "utf8");
const tally = (counts: Partial<ConditionTally["counts"]>, unrecognized = 0): ConditionTally => {
  const full = { M: 0, NM: 0, LP: 0, MP: 0, HP: 0, DMG: 0, ...counts };
  return { counts: full, unrecognized, total: Object.values(full).reduce((s, n) => s + n, 0) + unrecognized };
};

test("gridConditionDisplay: condição uniforme → só a sigla (sem quantidade)", () => {
  assert.deepEqual(gridConditionDisplay(tally({ NM: 5 })), { kind: "uniform", part: { code: "NM", short: "NM", name: "Near Mint", count: 5 } });
  const sp = gridConditionDisplay(tally({ LP: 2 }));
  assert.equal(sp?.kind, "uniform");
  assert.equal(sp?.kind === "uniform" ? sp.part.short : null, "SP", "LP exibido como SP");
  const dm = gridConditionDisplay(tally({ DMG: 1 }));
  assert.equal(dm?.kind === "uniform" ? dm.part.short : null, "DM", "DMG exibido como DM");
});

test("gridConditionDisplay: mistas na ordem canônica; '+n' conta CONDIÇÕES ocultas nos dois limites", () => {
  const two = gridConditionDisplay(tally({ NM: 3, HP: 1 }));
  assert.equal(two?.kind, "mixed");
  if (two?.kind !== "mixed") return;
  assert.deepEqual(two.chips.map((c) => c.short), ["NM", "HP"]);
  assert.equal(two.moreNarrow, 0);
  assert.equal(two.moreWide, 0);

  const three = gridConditionDisplay(tally({ DMG: 1, NM: 9, LP: 2 }));
  if (three?.kind !== "mixed") return assert.fail("mista");
  assert.deepEqual(three.chips.map((c) => c.short), ["NM", "SP", "DM"]);
  assert.equal(three.moreNarrow, 1, "estreito: 2 visíveis, 1 condição oculta");
  assert.equal(three.moreWide, 0, "largo: 3 visíveis, nada oculto");

  const six = gridConditionDisplay(tally({ M: 1, NM: 40, LP: 7, MP: 3, HP: 2, DMG: 1 }));
  if (six?.kind !== "mixed") return assert.fail("mista");
  assert.deepEqual(six.chips.map((c) => c.short), ["M", "NM", "SP"]);
  assert.equal(six.moreNarrow, 6 - GRID_CONDITION_CHIPS_NARROW);
  assert.equal(six.moreWide, 6 - GRID_CONDITION_CHIPS_MAX);
  assert.notEqual(six.moreNarrow, 40 + 7 + 3 + 2 + 1 - 1, "nunca exemplares");
});

test("gridConditionDisplay: sem dado, vazio ou não reconhecido → nada (nunca NM inventado)", () => {
  assert.equal(gridConditionDisplay(null), null);
  assert.equal(gridConditionDisplay(undefined), null);
  assert.equal(gridConditionDisplay(tally({})), null);
  assert.equal(gridConditionDisplay(tally({ NM: 2 }, 1)), null);
});

test("gridConditionDisplay é só apresentação: não altera o tally da leitura G1", () => {
  const V = "00000000-0000-4000-8000-0000000000a1";
  const L = "00000000-0000-4000-8000-00000000f001";
  const { mix } = pageConditionMix({
    groups: [{ cardVariantId: V, languageCode: "pt-BR", copiesOwned: 3 }],
    languages: [{ id: L, code: "pt-BR" }],
    rows: [{ card_variant_id: V, language_id: L, condition_code: "LP" }],
    count: 1,
  });
  const t = [...mix.values()][0]!;
  const before = JSON.stringify(t);
  gridConditionDisplay(t);
  assert.equal(JSON.stringify(t), before);
  const src = read("lib/colecoes/condition-distribution.ts");
  const fn = src.slice(src.indexOf("export function gridConditionDisplay"), src.indexOf("/**\n * Onde estão os exemplares"));
  assert.ok(!/pageConditionMix|supabase|counts\[[^\]]+\]\s*[+-]?=/.test(fn), "sem leitura nem recálculo");
});

test("AcervoTile: hierarquia compacta; variante em texto; condição uniforme na linha da variante; mistas em linha própria", () => {
  const view = read("components/colecoes/acervo/acervo-view.tsx");
  const tile = view.slice(view.indexOf("function AcervoTile"), view.indexOf("function GridConditionChips"));
  const meta = tile.slice(tile.indexOf("styles.tileMeta"));
  const iName = meta.indexOf("styles.nameRow");
  const iSub = meta.indexOf("styles.tileSub");
  const iVariant = meta.indexOf("styles.tileVariantRow");
  const iMixed = meta.indexOf('display?.kind === "mixed"');
  const iStorage = meta.indexOf("styles.storageMatch");
  assert.ok(iName > 0 && iName < iSub && iSub < iVariant && iVariant < iMixed && iMixed < iStorage, "ordem das linhas");
  assert.ok(meta.includes("{caption} · {item.languageCode}"), "Set · número · idioma em texto");
  assert.ok(!meta.includes("styles.tag"), "nenhum chip de idioma ou variante no Meu acervo");
  assert.ok(!meta.includes("styles.sub}"), "linha secundária própria (não a .sub compartilhada)");
  assert.match(meta, /<span className=\{styles\.tileVariant\} title=\{tag\}>\s*\{tag\}/, "variante em texto, com o nome completo no title");
  assert.match(meta, /display\?\.kind === "uniform" \? \(\s*<span className=\{`\$\{conditionStyles\.conditionCode\} \$\{styles\.tileCondition\}`\} title=\{display\.part\.name\}>\s*\{display\.part\.short\}/, "sigla sem quantidade");
  assert.ok(tile.includes('className={`${styles.meta} ${styles.tileMeta}`} aria-hidden="true"'), "bloco visual oculto para leitor de tela");
  assert.ok(meta.includes("{copies > 1 ? <span className={styles.qtyInline}>×{formatCount(copies)}</span> : null}"), "×N preservado");
  // Imagem, preço e acabamento intocados.
  assert.ok(tile.includes("<AcervoPriceTag price={price} now={priceNow} />"));
  assert.ok(tile.includes("<CardFinishLayers"));
  const chips = view.slice(view.indexOf("function GridConditionChips"), view.indexOf("function ActiveFilterChips"));
  assert.ok(chips.includes('data-wide-only={index >= GRID_CONDITION_CHIPS_NARROW ? "" : undefined}'));
  assert.ok(chips.includes('data-width="narrow"') && chips.includes('data-width="wide"'));
});

test("nome acessível completo preservado (Set, variante, idioma, quantidade, preço, condições)", () => {
  const view = read("components/colecoes/acervo/acervo-view.tsx");
  const tile = view.slice(view.indexOf("function AcervoTile"), view.indexOf("function GridConditionChips"));
  const name = tile.slice(tile.indexOf("const accessibleName = ["), tile.indexOf(".join(\", \")"));
  for (const part of ["item.cardName", "caption", "tag", "item.languageName", "priceAccessibleText(price, priceNow)", "conditionDistributionAccessible(conditions)"]) {
    assert.ok(name.includes(part), part);
  }
  assert.ok(tile.includes("ariaLabel={accessibleName}"), "seleção/navegação pelo mesmo shell");
  assert.ok(tile.includes("acervoHref({ ...state, detail: { cardVariantId: item.cardVariantId, languageCode: item.languageCode } })"));
});

test("CSS: classes novas só do Meu acervo; compartilhadas intocadas; troca 2/3 por container query", () => {
  const css = read("components/colecoes/acervo/acervo.module.css");
  assert.match(css, /\.tileMeta \{\s*container: acervo-tile \/ inline-size;/);
  assert.match(css, /\.tileSub \{[^}]*white-space: nowrap;[^}]*text-overflow: ellipsis;/);
  // GRID TYPOGRAPHY ADJUSTMENT-01: só a 2ª linha (Set · número · idioma) fica menor.
  assert.match(css, /\.tileSub \{\s*margin-top: 0\.1875rem;\s*overflow: hidden;\s*font-size: 0\.6875rem;\s*line-height: 1\.25;\s*font-variant-numeric: tabular-nums;\s*white-space: nowrap;\s*text-overflow: ellipsis;\s*color: hsl\(var\(--muted-foreground\)\);\s*\}/);
  assert.match(css, /\.name \{[^}]*font-size: 0\.84375rem;/, "nome inalterado");
  assert.match(css, /\.tileVariant \{[^}]*font-size: 0\.6875rem;\s*line-height: 1\.3;/, "variante inalterada");
  assert.match(css, /\.qtyInline \{[^}]*font-size: 0\.75rem;/, "quantidade inalterada");
  assert.match(css, /\.tileVariant \{[^}]*min-width: 0;[^}]*text-overflow: ellipsis;/);
  assert.match(css, /\.conditionChip\[data-wide-only\],\s*\.conditionMore\[data-width="wide"\] \{\s*display: none;/);
  assert.match(css, /@container acervo-tile \(min-width: 10\.5rem\) \{[\s\S]*?\.conditionMore\[data-width="narrow"\] \{\s*display: none;/);
  assert.match(css, /\.conditionChips \{[^}]*flex-wrap: wrap;/, "salvaguarda: quebra, nunca sobrepõe");
  // Estilos compartilhados com Collection, Pokédex, Master Set e outras grades: iguais.
  assert.match(css, /\.meta \{\s*margin-top: 0\.75rem;\s*padding: 0 0\.125rem;\s*\}/);
  assert.match(css, /\.sub \{\s*display: flex;\s*flex-wrap: wrap;\s*align-items: center;\s*gap: 0\.375rem;\s*margin-top: 0\.1875rem;/);
  assert.match(css, /\.tag \{\s*display: inline-flex;[^}]*border: 1px solid hsl\(var\(--border\)\);\s*\}/);
  assert.match(css, /\.storageMatch \{[^}]*\}\s*\.storageMatch\[data-partial\] \{/, "regras do storageMatch juntas");
  for (const shared of ["collection-view.tsx", "free-collection-view.tsx", "master-set-gallery.tsx", "pokedex-grid.tsx"]) {
    const src = read(`components/colecoes/colecoes/${shared}`);
    assert.ok(!/tileMeta|tileSub|tileVariant/.test(src), `${shared} não usa as classes novas`);
  }
});
