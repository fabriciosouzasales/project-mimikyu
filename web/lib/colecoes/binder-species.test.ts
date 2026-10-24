import { test } from "node:test";
import assert from "node:assert/strict";
import type { BinderPage, BinderSlot } from "./binder.ts";
import {
  attachSpeciesReferences,
  classifySpeciesFailure,
  formatNationalNumber,
  isSpeciesPlanToken,
  mayHaveSpeciesReferences,
  pageRemovalWarning,
  parseSpeciesPreview,
  parseSpeciesReferenceState,
  parseSpeciesReferences,
  shouldShowSpeciesReference,
  speciesReferencesOnPage,
} from "./binder-species.ts";

const S1 = "00000000-0000-4000-8000-000000000001";
const S2 = "00000000-0000-4000-8000-000000000002";
const TOKEN = "a".repeat(64);

function slot(over: Partial<BinderSlot> = {}): BinderSlot {
  return {
    slotId: S1,
    row: 0,
    column: 0,
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
    ...over,
  };
}

const ref = { nationalNumber: 1, speciesName: "Bulbasaur", artworkPath: "official-artwork/0001/w320-a28778bac7baa424.webp" };

test("só fichários de Pokédex ou convidadas leem referências", () => {
  assert.equal(mayHaveSpeciesReferences({ hasBinder: true, kind: "POKEDEX", role: "OWNER" }), true);
  assert.equal(mayHaveSpeciesReferences({ hasBinder: true, kind: "FREE", role: "GUEST" }), true);
  assert.equal(mayHaveSpeciesReferences({ hasBinder: true, kind: "SET", role: "OWNER" }), false);
  assert.equal(mayHaveSpeciesReferences({ hasBinder: true, kind: "FREE", role: "OWNER" }), false);
  assert.equal(mayHaveSpeciesReferences({ hasBinder: false, kind: "POKEDEX", role: null }), false);
});

test("referência aparece só no bolso visualmente vazio e com exibição ligada (D3, ajuste A)", () => {
  assert.equal(shouldShowSpeciesReference(slot({ speciesRef: ref }), true), true);
  assert.equal(shouldShowSpeciesReference(slot({ speciesRef: ref }), false), false, "oculta: vínculo continua, nada é mostrado");
  assert.equal(shouldShowSpeciesReference(slot({ speciesRef: ref, state: "RESERVED_EMPTY" }), true), false, "reserva tem prioridade");
  assert.equal(shouldShowSpeciesReference(slot({ speciesRef: ref, state: "OCCUPIED_UNPLANNED" }), true), false, "carta cobre");
  assert.equal(shouldShowSpeciesReference(slot({ speciesRef: ref, image: { path: "x", focalY: 50, updatedAt: null, url: null } }), true), false, "imagem cobre");
  assert.equal(shouldShowSpeciesReference(slot({ speciesRef: ref, regionId: S2 }), true), false, "mesclagem cobre");
  assert.equal(shouldShowSpeciesReference(slot(), true), false, "bolso sem referência");
});

test("número nacional discreto com quatro dígitos", () => {
  assert.equal(formatNationalNumber(1), "#0001");
  assert.equal(formatNationalNumber(25), "#0025");
  assert.equal(formatNationalNumber(1025), "#1025");
});

test("estado: formato da 5259; malformado → null", () => {
  assert.deepEqual(
    parseSpeciesReferenceState([{ layout_id: S1, has_binder: true, is_pokedex_owner: true, can_manage: true, reference_count: 1025, references_visible: false }]),
    { hasBinder: true, isPokedexOwner: true, canManage: true, referenceCount: 1025, visible: false },
  );
  assert.equal(parseSpeciesReferenceState([]), null);
  assert.equal(parseSpeciesReferenceState([{ has_binder: true, is_pokedex_owner: true, can_manage: true, reference_count: -1, references_visible: true }]), null);
  assert.equal(parseSpeciesReferenceState([{ has_binder: "sim" }]), null);
});

test("referências por bolso; linha malformada invalida o lote inteiro", () => {
  const map = parseSpeciesReferences([
    { page_number: 1, slot_id: S1, national_number: 1, species_name: "Bulbasaur", artwork_path: ref.artworkPath },
    { page_number: 1, slot_id: S2, national_number: 2, species_name: "Ivysaur", artwork_path: null },
  ]);
  assert.ok(map);
  assert.equal(map.size, 2);
  assert.deepEqual(map.get(S1), ref);
  assert.equal(map.get(S2)?.artworkPath, null, "sem arte → só o número");
  assert.equal(parseSpeciesReferences([{ slot_id: S1, national_number: 0, species_name: "x" }]), null);
  assert.equal(parseSpeciesReferences({}), null);
});

test("anexar referências não altera bolsos sem referência nem os outros campos", () => {
  const pages: BinderPage[] = [{ pageNumber: 1, pageId: "p1", slots: [slot(), slot({ slotId: S2, state: "OCCUPIED_MATCH" })] }];
  const out = attachSpeciesReferences(pages, new Map([[S2, { ...ref, nationalNumber: 2 }]]));
  assert.equal(out[0]?.slots[0], pages[0]?.slots[0], "bolso sem referência: mesma referência de objeto");
  assert.equal(out[0]?.slots[1]?.speciesRef?.nationalNumber, 2);
  assert.equal(out[0]?.slots[1]?.state, "OCCUPIED_MATCH", "a carta continua no bolso — a referência só fica escondida");
  assert.equal(attachSpeciesReferences(pages, new Map()), pages, "sem referências: nada é copiado");
});

test("prévia: formato da 5258 e token obrigatório", () => {
  const preview = parseSpeciesPreview([
    {
      layout_id: S1,
      positions_in_scope: 1025,
      slots_total: 1056,
      pair_count: 1025,
      slots_left_free: 31,
      positions_unplaced: 0,
      first_page: 1,
      last_page: 65,
      first_number: 1,
      last_number: 1025,
      slots_with_content: 0,
      existing_count: 0,
      already_applied: false,
      plan_token: TOKEN,
    },
  ]);
  assert.ok(preview);
  assert.equal(preview.pairCount, 1025);
  assert.equal(preview.slotsLeftFree, 31);
  assert.equal(preview.lastPage, 65);
  assert.equal(parseSpeciesPreview([{ pair_count: 1, plan_token: "x" }]), null);
  assert.equal(isSpeciesPlanToken(TOKEN), true);
  assert.equal(isSpeciesPlanToken("A".repeat(64)), false);
});

test("falhas da 5258 viram motivos estáveis", () => {
  assert.equal(classifySpeciesFailure("PGRST202", "x"), "unavailable");
  assert.equal(classifySpeciesFailure("P0001", "PLAN_CHANGED"), "plan_changed");
  assert.equal(classifySpeciesFailure("P0001", "SPECIES_REFERENCES_PRESENT"), "present");
  assert.equal(classifySpeciesFailure("P0001", "COUNT_MISMATCH"), "count_mismatch");
  assert.equal(classifySpeciesFailure("42501", "BINDER_OWNER_ONLY"), "owner_only");
  assert.equal(classifySpeciesFailure("22023", "NOT_POKEDEX_COLLECTION"), "not_pokedex");
  assert.equal(classifySpeciesFailure("55000", "COLLECTION_ARCHIVED"), "archived");
  assert.equal(classifySpeciesFailure("P0002", "COLLECTION_NOT_FOUND"), "not_found");
});

test("remoção de página (5260, ajuste B): recusa com contagem é reconhecida e gera aviso", () => {
  assert.equal(speciesReferencesOnPage("page has 16 species reference(s) — confirm their removal before deleting the page", "SPECIES_REFERENCES_ON_PAGE:16"), 16);
  assert.equal(speciesReferencesOnPage("page has 3 species reference(s) — confirm…", null), 3);
  assert.equal(speciesReferencesOnPage("page has 2 slot assignment(s) — remove them before deleting the page", null), null);
  assert.match(pageRemovalWarning(16), /16 Pokémon de referência/);
  assert.match(pageRemovalWarning(1), /1 Pokémon de referência/);
});
