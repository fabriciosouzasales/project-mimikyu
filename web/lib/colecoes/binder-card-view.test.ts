// V1-08 — "Ver carta" (lupa no fichário). IMPLEMENTATION-01; D2 revisada em CATALOG CARD PREVIEW VISUAL ALIGNMENT CORRECTION-01
// (ampliação visual pura, a mesma da página Cartas do Catálogo — sem painel nem texto).
// Executar: node --experimental-strip-types --test lib/colecoes/binder-card-view.test.ts (a partir de web/)
// Regras puras + verificações ESTRUTURAIS do código (a interação renderizada fica para a homologação visual).
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import type { BinderSlot } from "./binder.ts";
import { canViewCard, cardViewAlt, cardViewFor, cardViewTransitionName } from "./binder-card-view.ts";

const read = (path: string) => readFileSync(new URL(`../../${path}`, import.meta.url), "utf8");
const code = (src: string) => src.replace(/\/\*[\s\S]*?\*\/|\/\/.*$/gm, "");

const OWNER = "00000000-0000-4000-8000-0000000000a1";
const GUEST = "00000000-0000-4000-8000-0000000000b2";
const CARD = "00000000-0000-4000-8000-0000000000c3";
const OTHER = "00000000-0000-4000-8000-0000000000c4";

const face = (name: string, over: Partial<BinderSlot["expected"] & object> = {}) => ({
  cardName: name,
  collectorNumber: "25",
  collectorTotal: 165,
  setCode: "mew",
  imagePath: `cards/mew/${name}.webp`,
  finishCode: null,
  finishName: null,
  ...over,
});
function slot(over: Partial<BinderSlot> = {}): BinderSlot {
  return {
    slotId: "s1",
    row: 1,
    column: 1,
    locked: false,
    state: "EMPTY",
    expected: null,
    present: null,
    assignmentId: null,
    allocationId: null,
    expectedCardId: null,
    presentCardId: null,
    presentVariantTypeId: null,
    presentCollectionId: null,
    expectedCollectionId: null,
    image: null,
    regionId: null,
    ...over,
  } as BinderSlot;
}
const present = (over: Partial<BinderSlot> = {}) =>
  slot({
    state: "OCCUPIED_UNPLANNED",
    presentCardId: CARD,
    presentCollectionId: OWNER,
    present: { ...face("Pikachu"), languageCode: "pt-BR", variantLabel: "Holográfica", cardVariantId: "V-1" },
    ...over,
  });

test("quando há lupa: carta presente ou reservada; nunca vazio, imagem personalizada ou mesclagem", () => {
  assert.equal(canViewCard(present()), true);
  assert.equal(canViewCard(slot({ state: "RESERVED_EMPTY", expectedCardId: CARD, expected: face("Pikachu") })), true);
  assert.equal(canViewCard(slot()), false, "vazio sem reserva");
  assert.equal(canViewCard(slot({ image: { path: "x" } as unknown as BinderSlot["image"] })), false, "imagem personalizada");
  assert.equal(canViewCard(present({ regionId: "r1" })), false, "mesclagem");
  assert.equal(canViewCard(slot({ state: "RESERVED_EMPTY", expectedCardId: CARD, expected: null })), false, "sem face legível, nada inventado");
});

test("imagem certa: presente → exemplar; reservado vazio → carta esperada; presente prevalece sobre a reserva", () => {
  const v = cardViewFor(present())!;
  assert.deepEqual([v.kind, v.name, v.imagePath], ["present", "Pikachu", "cards/mew/Pikachu.webp"]);
  const reserved = cardViewFor(slot({ state: "RESERVED_EMPTY", expectedCardId: CARD, expectedCollectionId: GUEST, expected: face("Raichu") }))!;
  assert.deepEqual([reserved.kind, reserved.imagePath], ["reserved", "cards/mew/Raichu.webp"]);
  const both = cardViewFor(present({ state: "OCCUPIED_MISMATCH", expectedCardId: OTHER, expected: face("Raichu") }))!;
  assert.deepEqual([both.kind, both.imagePath], ["present", "cards/mew/Pikachu.webp"], "a reserva não substitui a carta presente");
  // Nome só semântico (título do diálogo / alt).
  assert.equal(cardViewAlt(v), "Pikachu, 025/165, MEW");
  assert.match(cardViewAlt(reserved), /reservada, ainda falta/);
  assert.equal(cardViewTransitionName("ab.c d"), "binder-card-view-ab-c-d", "custom-ident válido");
});

test("trava não impede ver", () => {
  assert.equal(canViewCard(present({ locked: true })), true);
  assert.equal(canViewCard(slot({ locked: true, state: "RESERVED_EMPTY", expectedCardId: CARD, expected: face("Pikachu") })), true);
});

test("estrutura: a lupa é a ampliação do Catálogo — CardPreviewOverlay + CardImagePreview, sem painel nem texto", () => {
  const view = code(read("components/colecoes/fichario/binder-card-view.tsx"));
  assert.ok(view.includes('import { CardImagePreview } from "@/components/card/card-image-preview"'));
  assert.ok(view.includes('import { CardPreviewOverlay } from "@/components/card/card-preview-overlay"'));
  assert.ok(view.includes("container={container}"), "montada na raiz do fichário (tela cheia/overlay)");
  for (const banned of ["<dl", "<ul", "<p", "DialogTitle", "DialogDescription", "Preço", "Coleção", "Reservado", "fixado", "Lista de desejos", "bg-surface", "overflow-y-auto"]) {
    assert.ok(!view.includes(banned), `sem ${banned} na lupa`);
  }
  assert.ok(!/\bfrom "@\/app\/|reserveSlot|clearReservations|moveSlot|removeSlots|setSlotsLock/.test(view), "nenhuma ação que grava");
  // Catálogo: a página Cartas usa a mesma dupla, sem container (body), intocada.
  const catalog = code(read("components/catalogo/cartas-gallery.tsx"));
  assert.ok(catalog.includes("<CardPreviewOverlay") && !/<CardPreviewOverlay[^>]*container=/.test(catalog));
  const overlay = code(read("components/card/card-preview-overlay.tsx"));
  assert.ok(overlay.includes('className={cn("w-full max-w-[380px] border-none bg-transparent p-0 shadow-none sm:max-w-[460px]", container && "z-[96]")}'), "mesmo tamanho do Catálogo; camada só com container");
  assert.ok(overlay.includes('data-focus-trap={container ? "self" : undefined}') && overlay.includes("hideClose"), "sem container, exatamente o de antes");
  assert.ok(!read("components/card/card-image-preview.tsx").includes("binder"), "imagem ampliada intocada");
});

test("estrutura: morph do Catálogo (alvo antes do snapshot; nome solto com a lupa aberta); tela cheia e movimento reduzido = zoom+fade", () => {
  for (const file of ["components/colecoes/fichario/binder-workspace.tsx", "components/colecoes/sharing/shared-binder-workspace.tsx"]) {
    const src = code(read(file));
    assert.ok(src.includes("const morph = canUseViewTransitions() && !document.fullscreenElement;"), file);
    assert.ok(src.includes("flushSync(() => setCardViewTarget(slotId));") && src.includes("runWithViewTransition(() => setCardViewSlotId(slotId));"), file);
    assert.ok(src.includes("<CardViewTransitionContext.Provider value={cardViewSlotId ? null : cardViewTarget}>"), `${file}: sem nome duplicado`);
    assert.ok(src.includes("useViewTransition={cardViewMorph}"), file);
  }
  const slotSrc = code(read("components/colecoes/fichario/binder-slot.tsx"));
  assert.ok(slotSrc.includes("useContext(CardViewTransitionContext) === slot.slotId"));
});

test("estrutura: gatilhos — 'Ver carta' na cápsula (editável); toque na carta só em somente leitura; teclado do fichário pausado", () => {
  const slotSrc = code(read("components/colecoes/fichario/binder-slot.tsx"));
  assert.ok(slotSrc.includes('handlers.onViewCard && canViewCard(slot) ? <QuickButton icon={ZoomIn} label="Ver carta"'));
  assert.ok(slotSrc.includes("onViewCard?: (slot: BinderSlot) => void;"), "opcional");
  const ws = code(read("components/colecoes/fichario/binder-workspace.tsx"));
  const activate = ws.slice(ws.indexOf("onActivate: (slot, additive) => {"), ws.indexOf("onToggleSelect: toggleSelect"));
  assert.ok(activate.indexOf("if (armedCard)") < activate.indexOf("if (!editable && canViewCard(slot))"), "carta da mão vem antes");
  assert.ok(activate.indexOf("if (selectionActive || additive)") < activate.indexOf("if (!editable && canViewCard(slot))"), "seleção vem antes");
  assert.ok(ws.includes("if (overviewOpen || registerFor || cardViewSlotId) return;"), "Esc fecha só a lupa; setas não viram a página");
  assert.ok(ws.includes("<BinderCardView slot={cardViewSlot} container={rootRef.current}"));
  assert.ok(/onViewCard: \(slot\) => \{\s*if \(justDragged\.current/.test(ws), "arrasto não abre a lupa");
  const shared = code(read("components/colecoes/sharing/shared-binder-workspace.tsx"));
  assert.ok(shared.includes("onActivate: (slot) => (canViewCard(slot) ? openCardView(slot.slotId) : undefined)"), "compartilhado/vitrine: toque na carta");
  assert.ok(shared.includes("if (cardViewSlotId) return;"), "teclado pausado");
  assert.ok(!/reserveForMode|onReserveFor/.test(shared), "V1-07 intocado no compartilhado");
});
