// V1-10 (extensão) — Favoritos no Fichário Digital. BINDER FAVORITES INTEGRATION IMPLEMENTATION-01.
// Executar: node --experimental-strip-types --test lib/colecoes/binder-favorites.test.ts (a partir de web/)
// Regras puras + verificações ESTRUTURAIS (a interação renderizada fica para a homologação visual). Ids sintéticos.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import type { BinderSlot } from "./binder.ts";
import { BINDER_MODELS, computeBinderFit } from "./binder.ts";
import { FAVORITE_READ_MAX, binderFavoriteCardId, binderFavoriteCornerSize, binderFavoriteReadIds, binderMarkerLayout, markerRowFits } from "./binder-favorites.ts";

const read = (path: string) => readFileSync(new URL(`../../${path}`, import.meta.url), "utf8");
const code = (src: string) => src.replace(/\/\*[\s\S]*?\*\/|\/\/.*$/gm, "");

const CARD = "00000000-0000-4000-8000-0000000000C3";
const OTHER = "00000000-0000-4000-8000-0000000000c4";
const slot = (over: Partial<BinderSlot> = {}) =>
  ({ state: "EMPTY", presentCardId: null, expectedCardId: null, image: null, regionId: null, ...over }) as BinderSlot;

test("carta favoritável: presente (prevalece sobre reserva divergente) ou reservada; id da CARTA em minúsculas", () => {
  assert.equal(binderFavoriteCardId(slot({ state: "OCCUPIED_UNPLANNED", presentCardId: CARD })), CARD.toLowerCase());
  assert.equal(binderFavoriteCardId(slot({ state: "OCCUPIED_MISMATCH", presentCardId: CARD, expectedCardId: OTHER })), CARD.toLowerCase(), "a presente, não a reservada");
  assert.equal(binderFavoriteCardId(slot({ state: "OCCUPIED_MATCH", presentCardId: CARD, expectedCardId: CARD })), CARD.toLowerCase());
  assert.equal(binderFavoriteCardId(slot({ state: "RESERVED_EMPTY", expectedCardId: OTHER })), OTHER, "faltante: sem posse (C-84)");
  assert.equal(binderFavoriteCardId(slot({ state: "RESERVED_EMPTY", expectedCardId: OTHER, locked: true })), OTHER, "travado também");
});

test("sem coração: vazio, só espécie, imagem personalizada, mesclagem, id ilegível", () => {
  assert.equal(binderFavoriteCardId(slot()), null);
  assert.equal(binderFavoriteCardId(slot({ speciesRef: { nationalNumber: 25 } as unknown as BinderSlot["speciesRef"] })), null, "espécie não é carta");
  assert.equal(binderFavoriteCardId(slot({ image: { path: "x" } as unknown as BinderSlot["image"] })), null);
  assert.equal(binderFavoriteCardId(slot({ state: "OCCUPIED_UNPLANNED", presentCardId: CARD, regionId: "r" })), null);
  assert.equal(binderFavoriteCardId(slot({ state: "OCCUPIED_UNPLANNED", presentCardId: "x" })), null);
});

test("leitura em lote: deduplicada (mesma carta em vários bolsos/acabamentos = 1 id), só o ainda não pedido; sem N+1", () => {
  const slots = [
    slot({ state: "OCCUPIED_UNPLANNED", presentCardId: CARD }),
    slot({ state: "RESERVED_EMPTY", expectedCardId: CARD }),
    slot({ state: "OCCUPIED_MATCH", presentCardId: CARD.toLowerCase(), expectedCardId: CARD }),
    slot({ state: "RESERVED_EMPTY", expectedCardId: OTHER }),
    slot(),
  ];
  assert.deepEqual(binderFavoriteReadIds(slots, new Set()), [CARD.toLowerCase(), OTHER]);
  assert.deepEqual(binderFavoriteReadIds(slots, new Set([CARD.toLowerCase()])), [OTHER]);
  assert.equal(FAVORITE_READ_MAX, 2000);
  const layer = code(read("components/colecoes/fichario/binder-favorites.tsx"));
  assert.ok(layer.includes("readCardFavoriteIds(ids)") && layer.includes(".slice(0, FAVORITE_READ_MAX)"), "uma chamada em lote por conjunto novo");
  assert.ok(!/\.map\([^)]*readCardFavoriteIds|setCardFavorite/.test(layer), "nunca por bolso; a gravação é do controlador da V1-10");
});

// Retângulos (px) como o CSS do bolso os posiciona — reproduz as fórmulas de binder-slot.tsx
// (top/left/right em %, área de toque `size + 8` com margem −4; Favorito em coluna só ±4 nos lados;
// selos 14 px no celular a 6%; cápsula de ações a 6% de 30% da altura, botões `control` + py 2 px).
type Rect = { x0: number; y0: number; x1: number; y1: number };
const overlap = (a: Rect, b: Rect) => Math.min(a.x1, b.x1) - Math.max(a.x0, b.x0) > 0.01 && Math.min(a.y1, b.y1) - Math.max(a.y0, b.y0) > 0.01;
function cornerRects(p: number, wish: boolean, fav: boolean, locked: boolean, mismatch: boolean) {
  const h = (p * 11) / 8;
  const control = Math.round(Math.min(26, Math.max(18, p * 0.2)));
  const m = binderMarkerLayout({ control, pocket: p, wish, favorite: fav });
  const s = m.size;
  const select: Rect = { x0: 0.04 * p - 4, y0: 0.04 * h - 4, x1: 0.04 * p + control + 4, y1: 0.04 * h + control + 4 };
  const wishR: Rect = { x0: p - 0.04 * p - s - 4, y0: 0.04 * h - 4, x1: p - 0.04 * p + 4, y1: 0.04 * h + s + 4 };
  const right = wish && !m.stacked ? s + m.gap : 0;
  const favR: Rect = m.stacked
    ? { x0: p - 0.04 * p - s - 4, y0: 0.04 * h + s + 4, x1: p - 0.04 * p + 4, y1: 0.04 * h + 2 * s + 4 }
    : { x0: p - 0.04 * p - right - s - 4, y0: 0.04 * h - 4, x1: p - 0.04 * p - right + 4, y1: 0.04 * h + s + 4 };
  const badge = (offset: number): Rect => {
    const x0 = m.badgeSide === "left" ? 0.06 * p : p - 0.06 * p - 14;
    const y0 = 0.06 * h + offset * 20 + m.shift;
    return { x0, y0, x1: x0 + 14, y1: y0 + 14 };
  };
  const toolbarTop = h - 0.3 * h * 0.06 - control - 4;
  const toolbar: Rect = { x0: 0, y0: toolbarTop, x1: p, y1: h };
  const controls: [string, Rect][] = [["Selecionar", select]];
  if (wish) controls.push(["Desejos", wishR]);
  if (fav) controls.push(["Favorito", favR]);
  const badges: [string, Rect][] = [];
  if (locked) badges.push(["Trava", badge(0)]);
  if (mismatch) badges.push(["Divergência", badge(locked ? 1 : 0)]);
  return { m, controls, badges, toolbar, control };
}

test("canto superior direito: marcadores nunca encolhem; linha quando cabe, coluna em bolso estreito (selos à esquerda)", () => {
  assert.deepEqual(binderMarkerLayout({ control: 20, pocket: 100, wish: false, favorite: false }), { size: 20, gap: 8, shift: 0, stacked: false, badgeSide: "right" });
  assert.deepEqual(binderMarkerLayout({ control: 20, pocket: 100, wish: true, favorite: false }), { size: 20, gap: 8, shift: 24, stacked: false, badgeSide: "right" }, "só Desejos: igual a antes");
  assert.equal(binderMarkerLayout({ control: 18, pocket: 100, wish: true, favorite: true }).stacked, false);
  assert.deepEqual(binderMarkerLayout({ control: 18, pocket: 50, wish: true, favorite: true }), { size: 18, gap: 8, shift: 22, stacked: true, badgeSide: "left" });
  assert.equal(binderMarkerLayout({ control: 18, pocket: 50, wish: false, favorite: true }).stacked, false, "um marcador sozinho fica no canto");
  assert.equal(markerRowFits(18, 77), true);
  assert.equal(markerRowFits(18, 76), false);
});

test("geometria: em todas as grades × 320/375/390/430 px (e desktop), nenhum controle se sobrepõe; selos não invadem controles", () => {
  const cases: [string, number][] = [];
  for (const model of BINDER_MODELS) {
    for (const vw of [320, 375, 390, 430]) cases.push([`${model.key} @${vw}`, computeBinderFit(vw - 24, 560, model.columns, model.rows, false).pocket]);
    cases.push([`${model.key} @desktop`, computeBinderFit(1100, 760, model.columns, model.rows, true).pocket]);
  }
  for (const [label, p] of cases) {
    for (const [wish, fav, locked, mismatch] of [
      [true, true, false, false],
      [false, true, true, false],
      [false, true, false, true],
      [true, true, true, false],
      [true, true, true, true],
    ] as const) {
      const { m, controls, badges, toolbar, control } = cornerRects(p, wish, fav, locked, mismatch);
      assert.equal(m.size, control, `${label}: marcador no tamanho de sempre (sem encolher)`);
      for (let i = 0; i < controls.length; i++)
        for (let j = i + 1; j < controls.length; j++)
          assert.ok(!overlap(controls[i]![1], controls[j]![1]), `${label} ${controls[i]![0]} × ${controls[j]![0]} (${JSON.stringify({ wish, fav, locked, mismatch })})`);
      // Marcadores de cima × cápsula de ações (revelada junto no hover/toque).
      for (const [name, r] of controls) assert.ok(!overlap(r, toolbar), `${label}: ${name} × cápsula`);
      // Selos (só visuais) × controles de cima.
      for (const [b, rb] of badges) for (const [c, rc] of controls) assert.ok(!overlap(rb, rc), `${label}: ${b} × ${c}`);
      for (let i = 0; i < badges.length; i++) for (let j = i + 1; j < badges.length; j++) assert.ok(!overlap(badges[i]![1], badges[j]![1]), label);
    }
  }
});

test("estrutura: o controlador da V1-10 ganhou só props opcionais; Acervo e Pesquisa iguais", () => {
  const ctrl = code(read("components/favorites/card-favorites-controller.tsx"));
  assert.ok(ctrl.includes("className?: string;") && ctrl.includes('onFeedback?: (feedback: { tone: "error"; text: string }) => void;'));
  assert.ok(ctrl.includes("if (onFeedback) onFeedback({ tone: \"error\", text: message });\n      else setError(message);"), "sem onFeedback: aviso no fluxo, como antes");
  for (const file of ["components/colecoes/acervo/acervo-view.tsx", "components/pesquisa/pesquisa-view.tsx"]) {
    assert.ok(!/<CardFavoritesController[^>]*(className|onFeedback)=/.test(code(read(file))), file);
  }
});

test("estrutura: coração no bolso — delegação por data-card-fav, inerte com seleção/carta na mão, não arrasta; só no titular", () => {
  const slotSrc = code(read("components/colecoes/fichario/binder-slot.tsx"));
  const mark = slotSrc.slice(slotSrc.indexOf("function FavoriteMark("), slotSrc.indexOf("function SelectButton("));
  for (const piece of [
    "data-card-fav={cardId}",
    "aria-pressed={favorited}",
    "aria-label={favoriteToggleLabel(name)}",
    "disabled={inert}",
    "onPointerDown={(event) => event.stopPropagation()}",
    "<FavoriteHeartIcon",
    "hsl(var(--favorite))",
    "peer/fav group/fav pointer-events-none absolute z-30 flex items-center justify-center rounded-full opacity-0",
  ]) {
    assert.ok(mark.includes(piece), piece);
  }
  assert.ok(slotSrc.includes("inert={selectionActive || placing}\n          size={marks.size}\n          beside={wishShown && !marks.stacked ? marks.size + marks.gap : 0}"), "inerte com seleção/carta na mão; ao lado do Desejos");
  assert.ok(slotSrc.includes("below={wishShown && marks.stacked ? marks.size + STACK_GAP : 0}") && slotSrc.includes("const STACK_GAP = 4;"), "em coluna: abaixo do Desejos");
  assert.ok(slotSrc.includes('width: size + 8, height: size, margin: "0 -4px"'), "em coluna: área de toque só para os lados");
  assert.ok((slotSrc.match(/<Badge side=\{marks\.badgeSide\}/g) ?? []).length === 2, "trava e divergência seguem o lado do layout");
  assert.ok(slotSrc.includes("const favShown = favCardId !== null && favCtx !== null && favCtx.known.has(favCardId);"), "sem leitura, sem coração");
  const ws = code(read("components/colecoes/fichario/binder-workspace.tsx"));
  assert.ok(ws.includes("<BinderFavoriteLayer pages={cache} onFeedback={onWishFeedback}>"), "toast do fichário; também no arquivado (não depende de editable)");
  const shared = code(read("components/colecoes/sharing/shared-binder-workspace.tsx"));
  assert.ok(!/BinderFavoriteLayer|BinderFavoriteContext/.test(shared), "compartilhado e vitrine: sem coração");
  // Lupa (V1-08) e Lista de desejos intocadas.
  assert.ok(!/favorit/i.test(code(read("components/colecoes/fichario/binder-card-view.tsx"))));
  assert.ok(!/favorit/i.test(code(read("components/colecoes/fichario/binder-wish.tsx"))));
  const layer = code(read("components/colecoes/fichario/binder-favorites.tsx"));
  assert.ok(!/reserveSlot|clearReservations|moveSlot|removeSlots|setSlotsLock|placeAvailableCard/.test(layer), "nada grava no fichário");
});

test("indicador na moldura: triângulo passivo só quando favorita; some com as ações reveladas, exceto com a ação indisponível", () => {
  const slotSrc = code(read("components/colecoes/fichario/binder-slot.tsx"));
  const mark = slotSrc.slice(slotSrc.indexOf("function FavoriteMark("), slotSrc.indexOf("function SelectButton("));
  assert.ok(!mark.includes("aria-pressed:opacity-100"), "o coração interativo não fica mais sempre visível em repouso");
  assert.ok(mark.includes('"group-hover/slot:pointer-events-auto group-hover/slot:opacity-100 group-focus-within/slot:pointer-events-auto group-focus-within/slot:opacity-100 focus-visible:opacity-100"'), "coração só com ações reveladas — e só então clicável (sem desfavoritar às cegas no toque)");
  assert.ok(mark.includes('"pointer-events-none absolute right-0 top-0 z-[25] hidden peer-aria-pressed/fav:block"'), "segue o aria-pressed (inclusive otimista); sem área de toque");
  assert.ok(mark.includes('!inert && "group-hover/slot:!hidden group-focus-within/slot:!hidden"'), "some no hover/foco/toque; fica com seleção/carta na mão");
  assert.ok(mark.includes('background: "hsl(var(--favorite))", clipPath: "polygon(0 0, 100% 0, 100% 100%)"') && mark.includes("stroke-white"), "--favorite + coração vazado");
  assert.equal((slotSrc.match(/data-card-fav=/g) ?? []).length, 1, "uma só ação de favoritar");
  // Tamanho: ~7% do bolso, 8–14 px.
  assert.deepEqual([50, 80, 120, 200, 280].map(binderFavoriteCornerSize), [8, 8, 8, 14, 14]);
});

test("geometria do triângulo: no vértice, sem tocar Desejos, Favorito em coluna, Selecionar nem selos (todas as grades, 320–430 px e desktop)", () => {
  for (const model of BINDER_MODELS) {
    const pockets = [320, 375, 390, 430].map((vw) => computeBinderFit(vw - 24, 560, model.columns, model.rows, false).pocket);
    pockets.push(computeBinderFit(1100, 760, model.columns, model.rows, true).pocket);
    for (const p of pockets) {
      const t = binderFavoriteCornerSize(p);
      const tri: Rect = { x0: p - t, y0: 0, x1: p, y1: t };
      const { controls, badges } = cornerRects(p, true, true, true, true);
      // Controles visíveis em repouso: Desejos marcado (sempre visível) — o triângulo não o encobre.
      // Teste conservador pelo retângulo do triângulo contra o CÍRCULO visual do Desejos e os selos.
      const h = (p * 11) / 8;
      const control = Math.round(Math.min(26, Math.max(18, p * 0.2)));
      // Círculo visual do Desejos (sempre visível quando marcado): menor (dx + dy) do círculo, medido do vértice,
      // tem de ficar além do cateto do triângulo (o triângulo é a região dx + dy < t).
      const r = control / 2;
      const nearest = 0.04 * p + r + (0.04 * h + r) - r * Math.SQRT2;
      assert.ok(nearest > t, `${model.key} p=${p}: triângulo sobre o Desejos (${nearest.toFixed(1)} ≤ ${t})`);
      for (const [name, r] of badges) assert.ok(!overlap(tri, r), `${model.key} p=${p}: triângulo × ${name}`);
      assert.ok(!overlap(tri, controls[0]![1]), `${model.key} p=${p}: triângulo × Selecionar`);
      assert.ok(t <= 14 && t / p <= 0.16, `${model.key} p=${p}: discreto`);
    }
  }
});
