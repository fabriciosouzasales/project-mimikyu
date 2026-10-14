// Testes offline do validador editorial (P3e).
// node --experimental-strip-types --test scripts/editorial/validate-editorial-lot.test.ts
// deno test --allow-read scripts/editorial/validate-editorial-lot.test.ts

import assert from "node:assert/strict";
import { test } from "node:test";
import { type Lot, type LotEntry, type SnapshotSpecies, md5, pgLength, publishedNumbers, validateLot } from "./validate-editorial-lot.ts";

const DESC = "Charmander já nasce com fogo: uma pequena chama arde na ponta de sua cauda desde o primeiro dia. Ela acompanha a vida inteira do Pokémon e está ligada a ela de forma tão estreita que, se um dia se apagasse, Charmander não sobreviveria.";
const GENUS = "Pokémon Lagarto";
const FLAVOR_MD5 = "d5536d41fd66c97f7e45059a03eb1162";
const GENUS_MD5 = "7b94628b657ad7735a1648dc12c03a7a";

function entry(over: Partial<LotEntry> = {}): LotEntry {
  const genus = over.genus ?? GENUS;
  const description = over.description ?? DESC;
  return {
    national_dex_number: 4,
    species_name: "Charmander",
    language: "pt-BR",
    origin: "MMKYU_EDITORIAL",
    status: "PROPOSTO",
    genus,
    description,
    description_length: pgLength(description),
    facts: ["[EN shield] fato"],
    content_md5: { genus: md5(genus), description: md5(description) },
    source_basis: { flavor_version: "shield", flavor_md5: FLAVOR_MD5, genus_md5: GENUS_MD5 },
    ...over,
  };
}

function lot(entries: LotEntry[], selection = [4, 6]): Lot {
  return {
    batch: "teste",
    guide_version: "0.2",
    revision: 1,
    selection,
    glossary: [{ source: "Galarian Meowth", pt: "Meowth de Galar", avoid: ["galariano"] }],
    entries,
  };
}

const SNAP: SnapshotSpecies[] = [
  { national_dex_number: 4, species_name: "Charmander", flavor_version: "shield", flavor_md5: FLAVOR_MD5, genus_md5: GENUS_MD5, editorial_rows: 0 },
  { national_dex_number: 6, species_name: "Charizard", flavor_version: "shield", flavor_md5: "681516f671fcea2c7696bae81364982b", genus_md5: "edb19fa8c041985be901624e7aca70ee", editorial_rows: 0 },
];

const codes = (f: ReturnType<typeof validateLot>, sev = "ERRO") => f.filter((x) => x.severity === sev).map((x) => x.code);

test("md5 igual ao md5() do Postgres (texto do piloto #1 GENUS)", () => {
  assert.equal(md5("Pokémon Semente"), "d106d48db7cd05b7318ef213e29ea191");
});

test("pgLength conta pontos de código", () => {
  assert.equal(pgLength("Pokémon"), 7);
  assert.equal(pgLength("—"), 1);
});

test("entrada válida não gera erro", () => {
  assert.deepEqual(codes(validateLot(lot([entry()]), { snapshot: SNAP })), []);
});

test("md5 e tamanho declarados divergentes", () => {
  const e = entry();
  e.content_md5 = { genus: md5("x"), description: e.content_md5.description };
  e.description_length = 10;
  const c = codes(validateLot(lot([e])));
  assert.ok(c.includes("MD5_CLASSIFICACAO"));
  assert.ok(c.includes("TAMANHO_DECLARADO"));
});

test("unicidade, seleção e estado", () => {
  const c = codes(validateLot(lot([entry(), entry(), entry({ national_dex_number: 99 }), entry({ national_dex_number: 6, status: "RASCUNHO", description: DESC + " Outra." })])));
  assert.ok(c.includes("ENTRADA_DUPLICADA"));
  assert.ok(c.includes("FORA_DA_SELECAO"));
  assert.ok(c.includes("ESTADO"));
  assert.ok(c.includes("DESCRICAO_REPETIDA"));
});

test("conflito com espécie já publicada", () => {
  const published = publishedNumbers([{ entries: [{ national_dex_number: 4 }], publication: { published: true } }]);
  assert.ok(codes(validateLot(lot([entry()]), { published })).includes("JA_PUBLICADA"));
  const unpublished = publishedNumbers([{ entries: [{ national_dex_number: 4 }], publication: { published: false } }]);
  assert.equal(unpublished.size, 0);
});

test("padrões proibidos e glossário", () => {
  const bad = "Você vai gostar! Eu acho que corre a 90 mph e é o mais rápido do galariano.";
  const f = validateLot(lot([entry({ description: bad })]));
  const err = codes(f);
  for (const c of ["VOZ_SEGUNDA_PESSOA", "EXCLAMACAO", "PRIMEIRA_PESSOA", "UNIDADE_IMPERIAL", "GLOSSARIO"]) assert.ok(err.includes(c), c);
  assert.ok(codes(f, "AVISO").includes("SUPERLATIVO"));
});

test("limites de palavra Unicode (acentos no início ou no fim)", () => {
  const f = validateLot(lot([entry({ description: "Mede cerca de três pés e é a única da região." })]));
  assert.ok(codes(f).includes("UNIDADE_IMPERIAL"));
  assert.ok(codes(f, "AVISO").includes("SUPERLATIVO"));
  const clean = validateLot(lot([entry({ description: "Os pés-de-moleque e a comunicação não são termos proibidos aqui." })]));
  assert.ok(!codes(clean).includes("UNIDADE_IMPERIAL"));
  assert.ok(!codes(clean, "AVISO").includes("SUPERLATIVO"));
});

test("palavras com 'me'/'eu' internas não disparam primeira pessoa", () => {
  const ok = "Meowth mede o ambiente e mexe na moeda; o europeu do texto é só exemplo de palavra.";
  assert.ok(!codes(validateLot(lot([entry({ description: ok })]))).includes("PRIMEIRA_PESSOA"));
});

test("forma do texto: NFC, bordas e classificação", () => {
  const nfd = "Pokémon Lagarto".normalize("NFD");
  const c = codes(validateLot(lot([entry({ genus: nfd }), entry({ national_dex_number: 6, genus: "Lagarto", description: " " + DESC })])));
  assert.ok(c.includes("NAO_NFC"));
  assert.ok(c.includes("CLASSIFICACAO_FORMA"));
  assert.ok(c.includes("ESPACO_BORDA"));
});

test("fonte factual alterada e editorial já existente no LIVE", () => {
  const snap = SNAP.map((s) => (s.national_dex_number === 4 ? { ...s, flavor_md5: "0".repeat(32), editorial_rows: 2 } : s));
  const c = codes(validateLot(lot([entry()]), { snapshot: snap }));
  assert.ok(c.includes("FONTE_ALTERADA"));
  assert.ok(c.includes("EDITORIAL_EXISTENTE"));
});

test("espécie da seleção ausente do snapshot", () => {
  assert.ok(codes(validateLot(lot([entry()], [4, 6, 7]), { snapshot: SNAP })).includes("SNAPSHOT_AUSENTE"));
});

test("--require-approved bloqueia lote incompleto ou não aprovado", () => {
  const c = codes(validateLot(lot([entry()]), { requireApproved: true }));
  assert.ok(c.includes("NAO_APROVADO"));
  assert.ok(c.includes("PENDENTE"));
  const done = lot([entry({ status: "APROVADO" })], [4]);
  assert.deepEqual(codes(validateLot(done, { requireApproved: true })), []);
});
