import assert from "node:assert/strict";
import { test } from "node:test";
import {
  POKEDEX_COLLECTION_ENABLED,
  POKEDEX_COLLECTION_RELEASED,
  appendPositions,
  classifyPokedexFailure,
  currentSelection,
  defaultSelection,
  formatDex,
  generationLine,
  generationRange,
  generationTitle,
  isPokedexCollection,
  nextOffset,
  normalizeSelection,
  parseGenerationFilter,
  parseGenerationOptions,
  parsePokedexPositions,
  planGenerationChange,
  pokedexFailureMessage,
  pokedexHref,
  parseJumpNumber,
  planPokedexJump,
  pokedexPageSize,
  POKEDEX_GENERATION_PAGE_SIZE,
  POKEDEX_PAGE_SIZE,
  sameSelection,
  selectionLabel,
  speciesInSelection,
  stateDescription,
  stateTag,
  toPokedexRpcFilter,
  toggleGeneration,
} from "./pokedex.ts";

const ROWS = [
  { generation_code: "GENERATION_II", generation_ordinal: 2, generation_name: "Generation II", region_name: "Johto", species_count: "100", first_number: 152, last_number: 251, is_selected: false, satisfied_count: "0" },
  { generation_code: "GENERATION_I", generation_ordinal: 1, generation_name: "Generation I", region_name: "Kanto", species_count: 151, first_number: 1, last_number: 151, is_selected: true, satisfied_count: 12 },
  { generation_code: "GENERATION_III", generation_ordinal: 3, generation_name: "Generation III", region_name: null, species_count: 135, first_number: 252, last_number: 386, is_selected: true, satisfied_count: 3 },
  { generation_code: "", generation_ordinal: 9 },
];

test("Pokédex publicada: a flag fica ligada em qualquer ambiente (autorização de 2026-10-19)", () => {
  assert.equal(POKEDEX_COLLECTION_RELEASED, true);
  assert.equal(POKEDEX_COLLECTION_ENABLED, true);
});

test("identifica a coleção Pokédex só pela política física", () => {
  assert.equal(isPokedexCollection({ completionPolicy: "REFERENCE_POSITION" }), true);
  assert.equal(isPokedexCollection({ completionPolicy: "STANDARD_SET" }), false);
  assert.equal(isPokedexCollection({ completionPolicy: null }), false);
});

test("5201: ordena por geração, converte números e descarta linha sem código", () => {
  const options = parseGenerationOptions(ROWS);
  assert.deepEqual(options.map((o) => o.code), ["GENERATION_I", "GENERATION_II", "GENERATION_III"]);
  assert.equal(options[1]?.speciesCount, 100);
  assert.equal(options[1]?.satisfied, 0);
  assert.equal(options[2]?.region, null);
  assert.equal(parseGenerationOptions(null).length, 0);
  const noCollection = parseGenerationOptions([{ generation_code: "GENERATION_I", generation_ordinal: 1, species_count: 151, is_selected: null, satisfied_count: null }]);
  assert.equal(noCollection[0]?.selected, null);
  assert.equal(noCollection[0]?.satisfied, null);
});

test("seleção: todas por padrão, atual, alternar mantendo ordem, espécies contempladas", () => {
  const options = parseGenerationOptions(ROWS);
  assert.deepEqual(defaultSelection(options), ["GENERATION_I", "GENERATION_II", "GENERATION_III"]);
  assert.deepEqual(currentSelection(options), ["GENERATION_I", "GENERATION_III"]);
  assert.deepEqual(toggleGeneration(["GENERATION_III"], "GENERATION_I", options), ["GENERATION_I", "GENERATION_III"]);
  assert.deepEqual(toggleGeneration(["GENERATION_I", "GENERATION_III"], "GENERATION_I", options), ["GENERATION_III"]);
  assert.equal(speciesInSelection(["GENERATION_I", "GENERATION_II"], options), 251);
  assert.equal(speciesInSelection([], options), 0);
});

test("normalização: só códigos conhecidos, sem repetição; vazia → null", () => {
  const options = parseGenerationOptions(ROWS);
  assert.deepEqual(normalizeSelection(["GENERATION_III", "X", "GENERATION_I", "GENERATION_I"], options), ["GENERATION_I", "GENERATION_III"]);
  assert.equal(normalizeSelection([], options), null);
  assert.equal(normalizeSelection(["X"], options), null);
  assert.equal(sameSelection(["A", "B"], ["B", "A"]), true);
  assert.equal(sameSelection(["A"], ["A", "B"]), false);
});

test("rótulos de seleção e geração", () => {
  const options = parseGenerationOptions(ROWS);
  assert.equal(selectionLabel(defaultSelection(options), options), "Todas as gerações (I–III)");
  assert.equal(selectionLabel(["GENERATION_II"], options), "Geração II");
  assert.equal(selectionLabel(["GENERATION_I", "GENERATION_III"], options), "Gerações I e III");
  assert.equal(selectionLabel([], options), "Nenhuma geração");
  assert.equal(generationTitle("GENERATION_IX"), "Geração IX");
  assert.equal(generationRange({ firstNumber: 1, lastNumber: 151 }), "#0001 - #0151");
  assert.equal(formatDex(25), "0025");
  assert.equal(generationLine({ code: "GENERATION_I", region: "Kanto", speciesCount: 151 }), "Geração I - Kanto: 151 Pokémon");
  assert.equal(generationLine({ code: "GENERATION_X", region: null, speciesCount: 1 }), "Geração X: 1 Pokémon");
});

test("plano de Ajustes: nada, inválido e mudança com prévia a partir da 5201", () => {
  const options = parseGenerationOptions(ROWS);
  assert.deepEqual(planGenerationChange(options, ["GENERATION_III", "GENERATION_I"]), { kind: "none" });
  assert.deepEqual(planGenerationChange(options, []), { kind: "invalid" });
  const plan = planGenerationChange(options, ["GENERATION_I", "GENERATION_II"]);
  assert.equal(plan.kind, "change");
  if (plan.kind !== "change") return;
  assert.deepEqual(plan.codes, ["GENERATION_I", "GENERATION_II"]);
  assert.deepEqual(plan.added.map((o) => o.code), ["GENERATION_II"]);
  assert.deepEqual(plan.removed.map((o) => o.code), ["GENERATION_III"]);
  assert.deepEqual(plan.preview, { currentTotal: 286, currentSatisfied: 15, nextTotal: 251, nextSatisfied: 12 });
});

test("URL: filtro de geração validado e href estável", () => {
  assert.equal(parseGenerationFilter({ geracao: "GENERATION_IV" }), "GENERATION_IV");
  assert.equal(parseGenerationFilter({ geracao: ["GENERATION_I", "GENERATION_II"] }), "GENERATION_I");
  assert.equal(parseGenerationFilter({ geracao: "drop table" }), null);
  assert.equal(parseGenerationFilter({}), null);
  const id = "00000000-0000-0000-0000-000000000001";
  assert.equal(pokedexHref(id, "todas", null), `/colecoes/colecoes/${id}`);
  assert.equal(pokedexHref(id, "faltam", "GENERATION_I"), `/colecoes/colecoes/${id}?ver=faltam&geracao=GENERATION_I`);
  assert.equal(toPokedexRpcFilter("tenho"), "OWNED");
  assert.equal(toPokedexRpcFilter("faltam"), "MISSING");
  assert.equal(toPokedexRpcFilter("todas"), "ALL");
});

const POSITION_ROWS = [
  {
    pokedex_position_id: "p1", position_number: 1, species_id: "s1", species_name: "Bulbasaur", generation_code: "GENERATION_I",
    species_artwork_path: "official-artwork/0001/w320-0123456789abcdef.webp", is_satisfied: true, copies_in_collection: 2,
    copies_available: 0, copies_elsewhere: 0, acervo_state: "OWNED", representative_card_name: "Bulbasaur",
    representative_collector_number: "001", representative_set_code: "sv1", representative_image_path: "x.webp", total_count: "151",
  },
  {
    pokedex_position_id: "p2", position_number: 2, species_id: "s2", species_name: "Ivysaur", generation_code: "GENERATION_I",
    species_artwork_path: null, is_satisfied: false, copies_in_collection: 0, copies_available: 1, copies_elsewhere: 0,
    acervo_state: "AVAILABLE", representative_card_name: null, total_count: 151,
  },
  { pokedex_position_id: "p3", acervo_state: "INVENTED", total_count: 151 },
];

test("5204: converte, mantém total antes do limite e descarta estado desconhecido", () => {
  const page = parsePokedexPositions(POSITION_ROWS);
  assert.equal(page.total, 151);
  assert.equal(page.items.length, 2);
  assert.equal(page.items[0]?.representative?.setCode, "sv1");
  assert.equal(page.items[1]?.representative, null);
  assert.equal(page.items[1]?.artworkPath, null);
  assert.deepEqual(parsePokedexPositions(undefined), { items: [], total: 0 });
});

test("estados em linguagem de colecionador", () => {
  assert.equal(stateTag("OWNED"), "Conquistado");
  assert.equal(stateTag("AVAILABLE"), "No seu acervo");
  assert.equal(stateTag("ELSEWHERE"), "Em outra coleção");
  assert.equal(stateTag("NOT_FOUND"), "Falta");
  assert.match(stateDescription({ state: "AVAILABLE", copiesAvailable: 2, copiesElsewhere: 0, copiesInCollection: 0 }), /2 cartas deste Pokémon livres/);
  assert.match(stateDescription({ state: "ELSEWHERE", copiesAvailable: 0, copiesElsewhere: 1, copiesInCollection: 0 }), /outra coleção/);
  assert.match(stateDescription({ state: "OWNED", copiesAvailable: 0, copiesElsewhere: 0, copiesInCollection: 3 }), /3 cartas/);
});

test("carregamento incremental: próximo deslocamento e junção sem repetir", () => {
  assert.equal(nextOffset(120, 151), 120);
  assert.equal(nextOffset(151, 151), null);
  const page = parsePokedexPositions(POSITION_ROWS).items;
  const merged = appendPositions(page.slice(0, 1), page);
  assert.deepEqual(merged.map((item) => item.positionId), ["p1", "p2"]);
});

test("erros: mensagens estáveis dos contratos viram motivo, texto cru nunca vaza", () => {
  assert.equal(classifyPokedexFailure("22023", "GENERATION_NOT_AVAILABLE"), "generation_unavailable");
  assert.equal(classifyPokedexFailure("55000", "POKEDEX_NOT_AVAILABLE"), "pokedex_unavailable");
  assert.equal(classifyPokedexFailure("55000", "STORAGE_CONTAINER_REQUIRED"), "storage_required");
  assert.equal(classifyPokedexFailure("55000", "COLLECTION_ARCHIVED"), "archived");
  assert.equal(classifyPokedexFailure("P0002", "COLLECTION_NOT_FOUND"), "not_found");
  assert.equal(classifyPokedexFailure("22023", "IDEMPOTENCY_KEY_REUSED"), "conflict");
  assert.equal(classifyPokedexFailure("28000", "not_authenticated"), "not_authenticated");
  assert.equal(classifyPokedexFailure("22023", "INVALID_REQUEST"), "invalid");
  assert.equal(classifyPokedexFailure("XX000", "boom"), "unavailable");
  for (const reason of ["generation_unavailable", "archived", "unavailable"] as const) {
    assert.doesNotMatch(pokedexFailureMessage(reason), /GENERATION_|COLLECTION_|SQL/);
  }
});

test("busca/salto (UX-04): número → geração escolhida, URL e página da geração inteira", () => {
  const id = "11111111-1111-4111-8111-111111111111";
  const options = [
    { code: "GENERATION_I", firstNumber: 1, lastNumber: 151, selected: true },
    { code: "GENERATION_II", firstNumber: 152, lastNumber: 251, selected: false },
    { code: "GENERATION_V", firstNumber: 494, lastNumber: 649, selected: true },
  ];
  assert.deepEqual(planPokedexJump(options, 25), { kind: "go", generation: "GENERATION_I" });
  assert.deepEqual(planPokedexJump(options, 649), { kind: "go", generation: "GENERATION_V" });
  assert.deepEqual(planPokedexJump(options, 200), { kind: "outside" });
  assert.deepEqual(planPokedexJump(options, 1100), { kind: "outside" });

  assert.equal(pokedexHref(id, "todas", "GENERATION_I", 25), `/colecoes/colecoes/${id}?geracao=GENERATION_I&n=25`);
  assert.equal(pokedexHref(id, "todas", null, 0), `/colecoes/colecoes/${id}`);

  assert.equal(parseJumpNumber({ n: "25" }), 25);
  assert.equal(parseJumpNumber({ n: ["7", "8"] }), 7);
  assert.equal(parseJumpNumber({ n: "0" }), null);
  assert.equal(parseJumpNumber({ n: "25a" }), null);
  assert.equal(parseJumpNumber({ n: "12345" }), null);
  assert.equal(parseJumpNumber({}), null);

  // Maior geração (156) cabe numa página quando há geração escolhida.
  assert.ok(POKEDEX_GENERATION_PAGE_SIZE >= 156 && POKEDEX_GENERATION_PAGE_SIZE <= 500);
  assert.equal(pokedexPageSize("GENERATION_V"), POKEDEX_GENERATION_PAGE_SIZE);
  assert.equal(pokedexPageSize(null), POKEDEX_PAGE_SIZE);
});
