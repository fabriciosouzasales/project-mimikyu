import assert from "node:assert/strict";
import { test } from "node:test";
import {
  POKEDEX_BULK_MAX,
  bulkLeftover,
  cardIdentityLine,
  classifyLinkFailure,
  copyAttributesLine,
  exceptionNote,
  exceptionWarning,
  linkFailureMessage,
  normalizeBulkIds,
  parseBulkPreview,
  parsePokedexLinkCandidates,
  parsePokedexPositionCopies,
  speciesLabel,
} from "./pokedex-link.ts";

const A = "11111111-1111-4111-8111-111111111111";
const B = "22222222-2222-4222-8222-222222222222";
const C = "33333333-3333-4333-8333-333333333333";

test("5208: candidatos válidos, total e malformados descartados", () => {
  const parsed = parsePokedexLinkCandidates([
    {
      physical_card_id: A,
      card_name: "Pikachu",
      collector_number: "025",
      card_set_code: "svi",
      card_set_name: "Escarlate e Violeta",
      variant_label: "Holo",
      is_default_variant: false,
      language_code: "pt-BR",
      language_name: "Português",
      storage_name: "Caixa azul",
      image_path: "a.webp",
      added_at: "2026-10-01T00:00:00Z",
      in_this_collection: true,
      card_species_name: "Pikachu",
      card_species_number: 25,
      species_match: false,
      total_count: "7",
    },
    { physical_card_id: "x", card_name: "inválido" },
    null,
  ]);
  assert.equal(parsed.items.length, 1);
  assert.equal(parsed.total, 7);
  const item = parsed.items[0]!;
  assert.equal(item.inThisCollection, true);
  assert.equal(item.speciesMatch, false);
  assert.equal(item.cardSpeciesNumber, 25);
  assert.equal(copyAttributesLine(item), "Português · Holo · Caixa azul");
  assert.equal(cardIdentityLine(item), "SVI · 025");
  assert.deepEqual(parsePokedexLinkCandidates("nada"), { items: [], total: 0 });
});

test("5209: base do vínculo obrigatória; representante e espécie da carta", () => {
  const parsed = parsePokedexPositionCopies([
    {
      collection_allocation_id: B,
      physical_card_id: A,
      card_name: "Pikachu",
      assignment_basis: "USER_OVERRIDE",
      is_representative: true,
      card_species_name: "Pikachu",
      card_species_number: 25,
      language_code: "en",
      language_name: "Inglês",
      is_default_variant: true,
      total_count: 2,
    },
    { collection_allocation_id: C, physical_card_id: A, card_name: "X", assignment_basis: "OUTRA" },
  ]);
  assert.equal(parsed.items.length, 1);
  assert.equal(parsed.items[0]!.basis, "USER_OVERRIDE");
  assert.equal(parsed.items[0]!.isRepresentative, true);
  assert.equal(copyAttributesLine(parsed.items[0]!), "Inglês");
  assert.equal(exceptionNote(parsed.items[0]!), "Exceção · carta de Pikachu (#0025)");
  assert.equal(exceptionNote({ cardSpeciesName: null, cardSpeciesNumber: null }), "Exceção · carta sem Pokémon catalogado");
});

test("5211: prévia sem exemplar repetido; faltantes nunca menor que a lista", () => {
  const row = (pos: string, copy: string, n: number) => ({
    pokedex_position_id: pos,
    position_number: n,
    species_name: "Bulbasaur",
    eligible_count: 2,
    physical_card_id: copy,
    card_name: "Bulbasaur",
    missing_total: 1,
    total_count: 2,
  });
  const parsed = parseBulkPreview([row(A, B, 1), row(C, B, 4)]);
  assert.equal(parsed.items.length, 1);
  assert.equal(parsed.missingTotal, 1);
  assert.equal(parsed.items[0]!.eligibleCount, 2);
});

test("aviso de exceção: explica a divergência e preserva o catálogo", () => {
  const warning = exceptionWarning({
    cardName: "Pikachu V",
    cardSpeciesName: "Pikachu",
    cardSpeciesNumber: 25,
    positionSpeciesName: "Raichu",
    positionNumber: 26,
  });
  assert.equal(warning.title, "Esta carta é de Pikachu (#0025)");
  assert.match(warning.body, /posição de Raichu \(#0026\) só nesta coleção/);
  assert.match(warning.body, /continua sendo de Pikachu/);
  const trainer = exceptionWarning({
    cardName: "Professor",
    cardSpeciesName: null,
    cardSpeciesNumber: null,
    positionSpeciesName: "Mew",
    positionNumber: 151,
  });
  assert.equal(trainer.title, "Esta carta não tem um Pokémon catalogado");
  assert.equal(speciesLabel("Mew", 151), "Mew (#0151)");
  assert.equal(speciesLabel(null, 151), null);
});

test("erros: contratos novos e reutilizados viram motivos estáveis", () => {
  assert.equal(classifyLinkFailure("55000", "EXCEPTION_CONFIRMATION_REQUIRED"), "confirmation_required");
  assert.equal(classifyLinkFailure("55000", "COPY_IN_OTHER_COLLECTION"), "copy_elsewhere");
  assert.equal(classifyLinkFailure("55000", "COPY_ALREADY_LINKED"), "copy_already_linked");
  assert.equal(classifyLinkFailure("P0002", "COPY_NOT_FOUND"), "copy_not_found");
  assert.equal(classifyLinkFailure("22023", "POSITION_NOT_IN_SCOPE"), "position_out_of_scope");
  assert.equal(classifyLinkFailure("P0001", "uma ou mais physical_card_ids já estão alocadas a uma Collection"), "already_linked");
  assert.equal(classifyLinkFailure("23505", "duplicate key"), "already_linked");
  assert.equal(classifyLinkFailure("P0001", "REMOVE_POKEDEX_POSITION_ASSIGNMENT_NOT_FOUND: x"), "not_found");
  assert.equal(classifyLinkFailure("55000", "COLLECTION_ARCHIVED"), "archived");
  assert.equal(classifyLinkFailure("P0001", "SET_POKEDEX_POSITION_PRIMARY_REPRESENTATIVE_COLLECTION_ARCHIVED: x"), "archived");
  assert.equal(classifyLinkFailure("28000", "not_authenticated"), "not_authenticated");
  assert.equal(classifyLinkFailure("XX000", "boom"), "unavailable");
  assert.equal(classifyLinkFailure("PGRST202", "Could not find the function"), "not_deployed");
  assert.equal(classifyLinkFailure("42883", "function does not exist"), "not_deployed");
  for (const reason of ["confirmation_required", "copy_elsewhere", "already_linked", "unavailable"] as const) {
    assert.ok(linkFailureMessage(reason).length > 10);
  }
});

test("lote: ids únicos, válidos e no teto da 5046; sobra explicada", () => {
  assert.deepEqual(normalizeBulkIds([A, A, B]), [A, B]);
  assert.equal(normalizeBulkIds([]), null);
  assert.equal(normalizeBulkIds(["x"]), null);
  assert.equal(normalizeBulkIds(Array.from({ length: POKEDEX_BULK_MAX + 1 }, (_, i) => `${String(i).padStart(8, "0")}-1111-4111-8111-111111111111`)), null);
  assert.equal(bulkLeftover({ missingTotal: 10, offered: 4, linked: 4 }), "6 Pokémon ainda não têm carta livre da mesma espécie no seu acervo.");
  assert.equal(bulkLeftover({ missingTotal: 4, offered: 4, linked: 3 }), "1 ficou desmarcado.");
  assert.equal(bulkLeftover({ missingTotal: 4, offered: 4, linked: 4 }), null);
});
