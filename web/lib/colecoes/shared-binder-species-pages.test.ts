// V1-13 · E3-6 / F2 — páginas do participante com referências de espécie (5393). Respostas simuladas: não prova a 5393 nem sessões reais.
// Executar: node --experimental-strip-types --test lib/colecoes/shared-binder-species-pages.test.ts (a partir de web/)
import assert from "node:assert/strict";
import { test } from "node:test";
import { parseSharedBinderPagesWithSpecies, speciesPagesFallback, speciesReferencesShown, speciesSourceTransition, speciesVisibilityKnown } from "./shared-binder-species-pages.ts";
import { parseSharedBinderPages, sharedPageToBinderPage } from "./sharing.ts";

const base = (r: number, c: number, over: Record<string, unknown> = {}) => ({
  page_number: 1, row_index: r, column_index: c, pocket_state: "EMPTY", card_name: null, collector_number: null, collector_total: null,
  card_set_code: null, variant_label: null, language_code: null, image_path: null, ...over,
});
const sp = (n: number | null, name: string | null, art: string | null, vis: boolean | null) => ({ species_national_number: n, species_name: name, species_artwork_path: art, references_visible: vis });
const card = { pocket_state: "CARD", card_name: "Pikachu", collector_number: "58", collector_total: 102, card_set_code: "base1", variant_label: "Normal", language_code: "pt-BR", image_path: "p.png" };
const res = { pocket_state: "RESERVED", card_name: "Raichu", collector_number: "14", card_set_code: "base1" };

test("11 colunas idênticas ao parser da 5316; espécie só no bolso vazio mascarado", () => {
  const rows = [
    { ...base(1, 1), ...sp(25, "Pikachu", "art/25.webp", true) },
    { ...base(1, 2, card), ...sp(null, null, null, true) },
    { ...base(2, 1, res), ...sp(null, null, null, true) },
    { ...base(2, 2), ...sp(null, null, null, true) },
  ];
  const r = parseSharedBinderPagesWithSpecies(rows, 2, 2);
  assert.ok(r);
  assert.equal(r.visible, true);
  const plain = parseSharedBinderPages(rows.map((x) => { const { species_national_number, species_name, species_artwork_path, references_visible, ...rest } = x as Record<string, unknown>; void species_national_number; void species_name; void species_artwork_path; void references_visible; return rest; }), 2, 2)!;
  const strip = (p: typeof r.pages) => p.map((pg) => ({ ...pg, pockets: pg.pockets.map(({ species, ...k }) => { void species; return k; }) }));
  assert.deepEqual(strip(r.pages), plain, "as 11 colunas viram exatamente as mesmas páginas da 5316");
  const pockets = r.pages[0]!.pockets;
  assert.deepEqual(pockets[0]!.species, { nationalNumber: 25, speciesName: "Pikachu", artworkPath: "art/25.webp" });
  assert.equal(pockets[1]!.species, undefined);
  assert.equal(pockets[2]!.species, undefined);
  const slots = sharedPageToBinderPage(r.pages[0]!).slots;
  assert.equal(slots[0]!.speciesRef?.nationalNumber, 25);
  assert.ok(slots.slice(1).every((s) => s.speciesRef === undefined), "carta, reserva e bolso sem referência: nenhum rótulo");
  assert.ok(!JSON.stringify(r).match(/slot_id|layout|physical|allocation|collection_id/), "nenhum id interno");
});

test("resposta inválida rejeita o lote inteiro (C2)", () => {
  const ok = { ...base(1, 1), ...sp(1, "Bulbasaur", null, true) };
  assert.ok(parseSharedBinderPagesWithSpecies([ok], 1, 1));
  assert.equal(parseSharedBinderPagesWithSpecies([{ ...base(1, 1, card), ...sp(25, "Pikachu", null, true) }], 1, 1), null, "espécie em bolso com carta");
  assert.equal(parseSharedBinderPagesWithSpecies([{ ...base(1, 1), ...sp(25, "Pikachu", null, false) }], 1, 1), null, "espécie com exibição desligada");
  assert.equal(parseSharedBinderPagesWithSpecies([{ ...base(1, 1), ...sp(25, null, null, true) }], 1, 1), null, "número sem nome");
  assert.equal(parseSharedBinderPagesWithSpecies([{ ...base(1, 1), ...sp(null, "X", null, true) }], 1, 1), null, "nome sem número");
  assert.equal(parseSharedBinderPagesWithSpecies([{ ...base(1, 1), ...sp(null, null, "a.webp", true) }], 1, 1), null, "arte sem espécie");
  assert.equal(parseSharedBinderPagesWithSpecies([{ ...base(1, 1), ...sp(0, "X", null, true) }], 1, 1), null);
  assert.equal(parseSharedBinderPagesWithSpecies([{ ...base(1, 1), ...sp(null, null, null, true) }, { ...base(1, 2), ...sp(null, null, null, false) }], 2, 1), null, "exibição divergente entre linhas");
  assert.equal(parseSharedBinderPagesWithSpecies([{ ...base(1, 1), references_visible: "sim" }], 1, 1), null);
  assert.equal(parseSharedBinderPagesWithSpecies({}, 1, 1), null);
  assert.equal(parseSharedBinderPagesWithSpecies([{ ...base(1, 1, { pocket_state: "X" }) }], 1, 1), null, "parser da 5316 também rejeita");
});

test("fora da camada / desligada: nada aparece; estado conhecido ou não", () => {
  const off = parseSharedBinderPagesWithSpecies([{ ...base(1, 1), ...sp(null, null, null, false) }], 1, 1)!;
  assert.equal(off.visible, false);
  const none = parseSharedBinderPagesWithSpecies([{ ...base(1, 1), ...sp(null, null, null, null) }], 1, 1)!;
  assert.equal(none.visible, null);
  assert.equal(parseSharedBinderPagesWithSpecies([], 1, 1)?.visible, null);
  assert.equal(speciesReferencesShown({ source: "5393", visible: true }), true);
  assert.equal(speciesReferencesShown({ source: "5393", visible: false }), false);
  assert.equal(speciesReferencesShown({ source: "5393", visible: null }), false);
  assert.equal(speciesReferencesShown({ source: "5316" }), false);
  assert.equal(speciesReferencesShown(null), false);
  assert.equal(speciesVisibilityKnown({ source: "5393", visible: false }), false);
  assert.equal(speciesVisibilityKnown({ source: "5316" }), null);
});

test("matriz C2: fallback só para barreira e função ausente", () => {
  assert.equal(speciesPagesFallback("42501", "CAPABILITY_NOT_ENABLED"), true);
  assert.equal(speciesPagesFallback("PGRST202", "x"), true);
  assert.equal(speciesPagesFallback("42883", "function does not exist"), true);
  assert.equal(speciesPagesFallback("42501", "permission denied for function"), false, "42501 com outra mensagem = erro");
  assert.equal(speciesPagesFallback("28000", "not_authenticated"), false, "sessão expirada");
  assert.equal(speciesPagesFallback("P0002", "COLLECTION_NOT_FOUND"), false, "acesso perdido");
  assert.equal(speciesPagesFallback("XX000", "boom"), false);
  assert.equal(speciesPagesFallback(undefined, undefined), false, "rede/sem código");
});

test("não misturar fontes: troca de fonte ou de exibição descarta e relê", () => {
  assert.equal(speciesSourceTransition(null, { source: "5393", visible: true }), "adopt");
  assert.equal(speciesSourceTransition(null, { source: "5316" }), "adopt");
  assert.equal(speciesSourceTransition({ source: "5393", visible: true }, { source: "5393", visible: true }), "keep");
  assert.equal(speciesSourceTransition({ source: "5393", visible: true }, { source: "5316" }), "reload", "barreira fechou no meio do uso");
  assert.equal(speciesSourceTransition({ source: "5393", visible: true }, { source: "5393", visible: false }), "reload", "exibição mudou");
  assert.equal(speciesSourceTransition({ source: "5316" }, { source: "5316" }), "keep");
});

test("mascaramento no bolso: só dados autorizados decidem a referência (F2, conferência final)", async () => {
  const { shouldShowSpeciesReference } = await import("./binder-species.ts");
  // Conteúdo oculto (carta de outra coleção, reserva alheia, mesclagem sem imagem) já chega como EMPTY: idêntico ao bolso vazio real.
  const hidden = parseSharedBinderPagesWithSpecies([{ ...base(1, 1), ...sp(25, "Pikachu", null, true) }], 1, 1)!;
  const real = parseSharedBinderPagesWithSpecies([{ ...base(1, 1), ...sp(25, "Pikachu", null, true) }], 1, 1)!;
  const sh = sharedPageToBinderPage(hidden.pages[0]!).slots[0]!;
  assert.deepEqual(sh, sharedPageToBinderPage(real.pages[0]!).slots[0]!);
  assert.equal(shouldShowSpeciesReference(sh, true), true);
  // Imagem decorativa AUTORIZADA (5326, já visível ao participante) prevalece, como no titular (D3).
  const withImage = { ...hidden.pages[0]!, images: [{ pageNumber: 1, row: 1, column: 1, height: 1, width: 1, region: false, path: "u/c/i.webp", focalX: 50, focalY: 50, updatedAt: null, url: "https://x/i.webp" }] };
  assert.equal(shouldShowSpeciesReference(sharedPageToBinderPage(withImage).slots[0]!, true), false);
  // Imagem sem URL assinada não é mostrada → não suprime a referência (nada que o participante não veja decide).
  const unsigned = { ...withImage, images: [{ ...withImage.images[0]!, url: null }] };
  assert.equal(shouldShowSpeciesReference(sharedPageToBinderPage(unsigned).slots[0]!, true), true);
  // Carta e reserva desta coleção prevalecem (e o parser nem aceita espécie nelas).
  const cardSlot = sharedPageToBinderPage(parseSharedBinderPagesWithSpecies([{ ...base(1, 1, card), ...sp(null, null, null, true) }], 1, 1)!.pages[0]!).slots[0]!;
  assert.equal(cardSlot.speciesRef, undefined);
  assert.equal(shouldShowSpeciesReference(cardSlot, true), false);
});
