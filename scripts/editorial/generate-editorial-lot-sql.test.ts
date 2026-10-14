// Testes offline do gerador de seed/validação editorial (P3e).
// node --experimental-strip-types --test scripts/editorial/generate-editorial-lot-sql.test.ts

import assert from "node:assert/strict";
import { test } from "node:test";
import { generate } from "./generate-editorial-lot-sql.ts";
import { type Lot, type LotEntry, md5, pgLength } from "./validate-editorial-lot.ts";

function entry(n: number, genus: string, description: string, status = "APROVADO"): LotEntry {
  return {
    national_dex_number: n,
    species_name: `Sp${n}`,
    language: "pt-BR",
    origin: "MMKYU_EDITORIAL",
    status,
    genus,
    description,
    description_length: pgLength(description),
    facts: ["[EN x] fato"],
    content_md5: { genus: md5(genus), description: md5(description) },
    source_basis: { flavor_version: "x", flavor_md5: "0".repeat(32), genus_md5: "1".repeat(32) },
  };
}

const DESC_A = "Texto editorial de teste com tamanho suficiente para ficar dentro da faixa de referência do guia editorial do lote.";
const DESC_B = "Outro texto editorial de teste, também com tamanho suficiente para ficar dentro da faixa de referência do guia.";

function lot(entries: LotEntry[]): Lot {
  return {
    batch: "teste",
    guide_version: "0.2",
    revision: 1,
    selection: entries.map((e) => e.national_dex_number),
    entries,
    publication: { baseline: { source_rows: 2050, source_md5: "ca8e9c87244160063971bd1a9f808b78" } },
  };
}

const PUBLISHED = [{
  path: "pilot.json",
  sha256: "f".repeat(64),
  data: { entries: [{ national_dex_number: 1, content_md5: { genus: "a".repeat(32), description: "b".repeat(32) } }], publication: { published: true } },
}];

const input = (l: Lot) => ({ lot: l, lotSha256: "e".repeat(64), published: PUBLISHED, seedQuery: "9001", validationQuery: "9002", tag: "p3e_teste" });

test("saída determinística e contagens derivadas do lote", () => {
  const l = lot([entry(4, "Pokémon Lagarto", DESC_A), entry(6, "Pokémon Chama", DESC_B)]);
  const a = generate(input(l));
  const b = generate(input(l));
  assert.equal(a.seed, b.seed);
  assert.equal(a.validation, b.validation);
  assert.match(a.seed, /total editorial = 6 \/ 3/);
  assert.match(a.seed, /\$t\$Pokémon Lagarto\$t\$, '[0-9a-f]{32}'/);
  assert.match(a.validation, /\(\s+1, 'FLAVOR', 'b{32}'\)/);
});

test("recusa lote com entrada não aprovada", () => {
  const l = lot([entry(4, "Pokémon Lagarto", DESC_A, "PROPOSTO")]);
  assert.throws(() => generate(input(l)), /NAO_APROVADO/);
});

test("recusa espécie já publicada no lote", () => {
  const l = lot([entry(1, "Pokémon Semente", DESC_A)]);
  assert.throws(() => generate(input(l)), /JA_PUBLICADA/);
});

test("recusa texto com o delimitador $t$", () => {
  const l = lot([entry(4, "Pokémon Lagarto", DESC_A + " $t$ fim.")]);
  assert.throws(() => generate(input(l)), /delimitador/);
});

test("recusa lote sem linha de base de SOURCE", () => {
  const l = lot([entry(4, "Pokémon Lagarto", DESC_A)]);
  delete (l as { publication?: unknown }).publication;
  assert.throws(() => generate(input(l)), /baseline/);
});
