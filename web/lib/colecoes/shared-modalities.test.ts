// V1-13 · E3-6 — Master Set (5323) e Pokédex (5324) do participante. Respostas simuladas: não prova as funções, a barreira nem sessões reais.
// Executar: node --experimental-strip-types --test lib/colecoes/shared-modalities.test.ts (a partir de web/)
import assert from "node:assert/strict";
import { test } from "node:test";
import {
  parseSharedMasterSetPositions,
  parseSharedModalityFilter,
  parseSharedPokedexPositions,
  sharedModalityHref,
  sharedModalityRead,
  sharedModalitySqlFilter,
  sharedPokedexDescription,
  validSharedOffset,
} from "./shared-modalities.ts";

const C = "11111111-1111-4111-8111-111111111111";
const V = "22222222-2222-4222-8222-222222222222";
const P = "33333333-3333-4333-8333-333333333333";

test("Master Set: campos do contrato; acervo do titular nunca aparece", () => {
  const page = parseSharedMasterSetPositions([
    { card_id: C, collector_number: "4", collector_total: 102, card_name: "Charizard", variant_type_id: V, variant_type_code: "HOLO", variant_type_name: "Holo", is_secret: false, image_path: "a.png", is_satisfied: true, copies_in_collection: 3, total_count: 9, copies_available: 7 },
    { card_id: C, collector_number: "4", card_name: "Charizard", variant_type_id: null, is_secret: true, is_satisfied: false, copies_in_collection: 0, total_count: 9 },
  ]);
  assert.ok(page);
  assert.equal(page.total, 9);
  assert.equal(page.items.length, 2);
  assert.ok(page.items.every((p) => p.copiesAvailable === 0), "copies_available ignorado mesmo que viesse");
  assert.equal(page.items[0]?.variantTypeName, "Holo");
  assert.equal(page.items[1]?.variantTypeId, null);
  assert.equal(page.items[1]?.isSecret, true);
  assert.deepEqual(parseSharedMasterSetPositions([]), { items: [], total: 0 });
  assert.equal(parseSharedMasterSetPositions({}), null);
});

test("Pokédex: estado só da coleção; representante só em conquistada; sem acervo", () => {
  const page = parseSharedPokedexPositions([
    { pokedex_position_id: P, position_number: 25, species_id: "s", species_name: "Pikachu", generation_code: "I", species_artwork_path: "art.png", is_satisfied: true, copies_in_collection: 2, representative_card_name: "Pikachu", representative_collector_number: "58", representative_set_code: "base1", representative_image_path: "p.png", total_count: 151, copies_available: 4, copies_elsewhere: 1, acervo_state: "AVAILABLE" },
    { pokedex_position_id: P.replace("3333", "4444"), position_number: 26, species_name: "Raichu", is_satisfied: false, copies_in_collection: 0, representative_card_name: "Inventada", total_count: 151 },
    { pokedex_position_id: "x", position_number: 27 },
  ]);
  assert.ok(page);
  assert.equal(page.items.length, 2, "linha sem id válido descartada");
  const [pika, rai] = page.items;
  assert.equal(pika?.state, "OWNED");
  assert.equal(pika?.copiesAvailable, 0);
  assert.equal(pika?.copiesElsewhere, 0);
  assert.equal(pika?.representative?.cardName, "Pikachu");
  assert.equal(rai?.state, "NOT_FOUND");
  assert.equal(rai?.representative, null, "representante de posição não conquistada é ignorado");
  assert.equal(sharedPokedexDescription(pika!), "capturado");
  assert.equal(sharedPokedexDescription(rai!), "falta na coleção");
  const noRep = parseSharedPokedexPositions([{ pokedex_position_id: P, position_number: 1, species_name: "Bulbasaur", is_satisfied: true, total_count: 1 }]);
  assert.equal(noRep?.items[0]?.representative, null, "representante ausente: arte da espécie, nada inventado");
  assert.equal(parseSharedPokedexPositions("x"), null);
});

test("zero linhas: vazio só com prova do progresso; senão indisponível", () => {
  const prog = { satisfied: 3, total: 10 };
  assert.equal(sharedModalityRead(5, "todas", 0, null), "ok");
  assert.equal(sharedModalityRead(0, "todas", 0, prog), "unavailable", "barreira fechada não vira vazio");
  assert.equal(sharedModalityRead(0, "tenho", 0, prog), "unavailable");
  assert.equal(sharedModalityRead(0, "faltam", 0, { satisfied: 10, total: 10 }), "ok", "completa de verdade");
  assert.equal(sharedModalityRead(0, "tenho", 0, { satisfied: 0, total: 10 }), "ok", "nenhuma conquistada de verdade");
  assert.equal(sharedModalityRead(0, "todas", 120, { satisfied: 0, total: 100 }), "ok", "página além do fim");
  assert.equal(sharedModalityRead(0, "todas", 0, null), "unavailable", "progresso desconhecido");
  assert.equal(sharedModalityRead(0, "todas", 0, { satisfied: 0, total: 0 }), "unavailable");
});

test("filtros, links e deslocamento", () => {
  assert.equal(sharedModalitySqlFilter("todas"), "ALL");
  assert.equal(sharedModalitySqlFilter("tenho"), "OWNED");
  assert.equal(sharedModalitySqlFilter("faltam"), "MISSING");
  assert.equal(parseSharedModalityFilter("faltam"), "faltam");
  assert.equal(parseSharedModalityFilter(["tenho"]), "tenho");
  assert.equal(parseSharedModalityFilter("x"), "todas");
  assert.equal(sharedModalityHref("/b", "todas"), "/b");
  assert.equal(sharedModalityHref("/b", "faltam", 3), "/b?ver=faltam&pagina=3");
  assert.equal(sharedModalityHref("/b", "todas", 2), "/b?pagina=2");
  assert.ok(validSharedOffset(0) && validSharedOffset(100_000) && !validSharedOffset(-1) && !validSharedOffset(1.5) && !validSharedOffset("1"));
});
