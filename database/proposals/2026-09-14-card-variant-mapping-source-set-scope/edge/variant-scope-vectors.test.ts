/*
===============================================================================
Project Mimikyu — Teste offline de PARIDADE Edge × SQL
Vetores compartilhados de precedência do mapping de Card Variant Type

Mandato...: CARD-VARIANTS — EDITORIAL-CONVERGENCE-16 /
            SOURCE-SET-SCOPED-FOUNDATION / GATE-A-REV-03
Data......: 2026-09-14
Status....: CONFIRMADO EXECUTADO — 12 PASS / 0 FAIL em 2026-09-14
            (P1–P10 + PARIDADE_INLINE + COBERTURA), contra o código REAL da
            Edge já com o patch aplicado. `deno check index.ts` PASS.
            `import-card-variants` LIVE em v10 ACTIVE, verify_jwt=true.

Rodar:
    deno test --allow-read \
      database/proposals/2026-09-14-card-variant-mapping-source-set-scope/edge/variant-scope-vectors.test.ts

-------------------------------------------------------------------------------
POR QUE ESTE TESTE IMPORTA O CÓDIGO REAL
-------------------------------------------------------------------------------
Ele NÃO reimplementa a lógica da Edge. Importa
`listVariantTypeExternalMappings` e `buildVariantComboKey` do arquivo de
produção e injeta um stub do client Supabase. Um teste que copiasse a lógica
provaria a cópia, não a Edge — e a divergência que esta frente existe para
eliminar reapareceria exatamente aí.

A única coisa reproduzida aqui é a EXPRESSÃO de lookup de dois níveis, porque
o patch a deixou inline em index.ts. Para que a cópia não possa divergir em
silêncio, o caso `PARIDADE_INLINE` lê index.ts e confirma que a expressão real
continua sendo a mesma. Se alguém mudar o index.ts sem mudar o teste, o teste
reprova.

-------------------------------------------------------------------------------
FONTE ÚNICA DOS EXPECTED
-------------------------------------------------------------------------------
Todos os valores esperados vêm de
`../test-vectors/variant-type-mapping-scope-vectors.json`, o MESMO arquivo que
o runner SQL da Seção 4 do harness 2826 consome, com o MESMO bloco `bindings`.
Nenhum expected é declarado neste arquivo.
===============================================================================
*/

import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  buildVariantComboKey,
  listVariantTypeExternalMappings,
} from "../../../../supabase/functions/import-card-variants/services/database.ts";

// -----------------------------------------------------------------------------
// Carga do arquivo ÚNICO de vetores
// -----------------------------------------------------------------------------
const VECTORS_URL = new URL(
  "../test-vectors/variant-type-mapping-scope-vectors.json",
  import.meta.url,
);
const INDEX_URL = new URL(
  "../../../../supabase/functions/import-card-variants/index.ts",
  import.meta.url,
);

type Combo = {
  type: string;
  foil: string | null;
  subtype: string | null;
  stamp: string[] | null;
};

type VectorMapping = {
  scope: string | null;
  source?: string;
  combo: Combo;
  variant_type: string;
};

type Vector = {
  id: string;
  title: string;
  job_scope: string | string[] | null;
  job_source?: string;
  combo: Combo;
  mappings: VectorMapping[];
  expected: {
    variant_type: string | null;
    matched_scope: string | null;
    validation_status?: string;
  };
};

const doc = JSON.parse(await Deno.readTextFile(VECTORS_URL));
const vectors: Vector[] = doc.vectors;
const bindings = doc.bindings;

// -----------------------------------------------------------------------------
// BINDINGS — aplicados exatamente como o bloco `bindings` do JSON descreve.
// O runner SQL aplica as mesmas regras. Divergir aqui quebra a paridade.
// -----------------------------------------------------------------------------
const SYNTHETIC: string[] = bindings.synthetic_vectors;
const SYNTH_FOIL: string = bindings.combo.synthetic.foil;

// >>> GATE-A-REV-03 §1 <<<
// A v2.0 tinha `symbol ?? "TCGDEX"` — um default HARDCODED. O runner SQL lia
// bindings.source.default; trocar o default no arquivo mudava um runner e não
// o outro, que é exatamente a divergência silenciosa que o bloco `bindings`
// existe para impedir.
//
// Aceita: símbolo (SRC_A/SRC_B), código concreto igual ao que o binding
// declara, ou ausência -> default do JSON. Qualquer outra coisa é erro.
function bindSource(symbol: string | undefined): string {
  const s = symbol ?? bindings.source.default;
  if (s === "SRC_A") return bindings.source.SRC_A;
  if (s === "SRC_B") return bindings.source.SRC_B;
  if (s === bindings.source.SRC_A) return bindings.source.SRC_A;
  if (s === bindings.source.SRC_B) return bindings.source.SRC_B;
  if (s === bindings.source.default) return bindings.source.default;
  throw new Error(
    `job_source/mapping.source "${s}" nao casa com SRC_A/SRC_B/default do bloco bindings.`,
  );
}

function bindFoil(vectorId: string, foil: string | null): string | null {
  return SYNTHETIC.includes(vectorId) ? SYNTH_FOIL : foil;
}

// TODOS os escopos declarados pelo vetor.
//
// >>> GATE-A-REV-02 §3 <<<
// A v1.0 devolvia só `job_scope[0]`. P9 cita sv03.5, sv05 e sv06 — um acerto
// em sv03.5 NÃO prova P9; o vetor afirma que o override de base3 não toca
// NENHUM dos três. Testar um e declarar o vetor provado é falso-verde.
function jobScopesOf(v: Vector): (string | null)[] {
  if (Array.isArray(v.job_scope)) return v.job_scope;
  return [v.job_scope ?? null];
}

// -----------------------------------------------------------------------------
// Stub do client Supabase — APLICA os .eq() de verdade
//
// >>> GATE-A-REV-03 §2 <<<
// A v2.0 tinha `eq: () => builder`: o stub IGNORAVA os filtros, e o teste
// pré-filtrava as rows por Fonte antes de chamar a função. Consequência: se
// alguém removesse `.eq("asset_source_id", ...)` do código de produção, P7
// continuaria passando — porque quem isolou a Fonte foi o TESTE, não a Edge.
// Isso transformava o vetor de isolamento entre Fontes em decoração.
//
// Agora o stub registra e APLICA cada .eq(), e devolve só as rows que passam.
// O isolamento passa a ser trabalho da função real. `calls` expõe os filtros
// para que o teste prove QUE eles foram emitidos.
// -----------------------------------------------------------------------------
type StubResult = {
  from: () => unknown;
  calls: [string, unknown][];
};

function makeSupabaseStub(rows: Record<string, unknown>[]): StubResult {
  const calls: [string, unknown][] = [];
  const builder = {
    select: () => builder,
    eq: (col: string, val: unknown) => {
      calls.push([col, val]);
      return builder;
    },
    then: (resolve: (r: unknown) => void) => {
      const filtered = rows.filter((r) =>
        calls.every(([col, val]) => r[col] === val)
      );
      return resolve({ data: filtered, error: null });
    },
  };
  return { from: () => builder, calls };
}

// Rows no formato do PostgREST, COM game_id e asset_source_id — porque agora
// é a função real que precisa filtrá-las.
function rowsFromVector(v: Vector, gameId: string): Record<string, unknown>[] {
  return v.mappings.map((m) => ({
    game_id: gameId,
    asset_source_id: bindSource(m.source),
    normalized_type: m.combo.type,
    normalized_foil: bindFoil(v.id, m.combo.foil),
    normalized_subtype: m.combo.subtype,
    normalized_stamp: m.combo.stamp,
    external_set_id: m.scope,
    variant_type_id: m.variant_type,
    // NOTA: variant_type_id carrega o CODE do vetor, não um UUID. O teste
    // compara identidade simbólica; o runner SQL resolve o mesmo símbolo para
    // o UUID real. É a mesma asserção em dois alfabetos.
  }));
}

// -----------------------------------------------------------------------------
// Vetores P1..P10
// -----------------------------------------------------------------------------
for (const v of vectors) {
  Deno.test(`${v.id} — ${v.title}`, async () => {
    const GAME = "GAME-UNDER-TEST";
    const sourceId = bindSource(v.job_source);
    const scopes = jobScopesOf(v);

    // NADA de pré-filtro por Fonte aqui. As rows entram TODAS, inclusive as
    // de outra Fonte (P7), e quem tem de isolá-las é a query real da Edge.
    const rows = rowsFromVector(v, GAME);

    const comboKey = buildVariantComboKey(
      v.combo.type,
      bindFoil(v.id, v.combo.foil),
      v.combo.subtype,
      v.combo.stamp,
    );

    // CADA escopo declarado precisa conferir. Ver jobScopesOf().
    for (const scope of scopes) {
      const stub = makeSupabaseStub(rows);
      const { globalMap, scopedMap } = await listVariantTypeExternalMappings(
        stub,
        GAME,
        sourceId,
        scope,
      );

      // A função REAL tem de ter emitido os dois filtros. Sem isto, o
      // isolamento entre Fontes (P7) passaria por acidente.
      const emitted = stub.calls.map(([c, v2]) => `${c}=${v2}`);
      assert(
        emitted.includes(`game_id=${GAME}`),
        `${v.id}: listVariantTypeExternalMappings nao chamou .eq("game_id", ...). Filtros emitidos: ${emitted.join(", ") || "<nenhum>"}`,
      );
      assert(
        emitted.includes(`asset_source_id=${sourceId}`),
        `${v.id}: listVariantTypeExternalMappings nao chamou .eq("asset_source_id", ...). Sem esse filtro, mappings de OUTRA Fonte entram nos mapas e o vetor de isolamento vira decoracao. Filtros emitidos: ${emitted.join(", ") || "<nenhum>"}`,
      );

      // Expressão de lookup — espelho literal do index.ts (ver PARIDADE_INLINE).
      const got = scopedMap.get(comboKey) ?? globalMap.get(comboKey) ?? null;

      assertEquals(
        got,
        v.expected.variant_type,
        `${v.id} [escopo ${scope ?? "<sem escopo>"}]: variant_type esperado=${v.expected.variant_type ?? "<nenhum>"} obtido=${got ?? "<nenhum>"} (fonte=${sourceId}, combo=${comboKey})`,
      );

      // O vetor também declara QUAL escopo deveria ter casado. Conferir só o
      // variant_type deixaria passar um acerto pelo motivo errado.
      const matched = scopedMap.has(comboKey)
        ? "SOURCE_SET"
        : (globalMap.has(comboKey) ? "GLOBAL" : null);
      assertEquals(
        matched,
        v.expected.matched_scope,
        `${v.id} [escopo ${scope ?? "<sem escopo>"}]: casou por ${matched ?? "<nenhum>"}, esperado ${v.expected.matched_scope ?? "<nenhum>"}`,
      );

      // validation_status só é comparado quando o vetor o declara — mesma
      // regra do runner SQL.
      if (v.expected.validation_status !== undefined) {
        const vs = got === null ? "NEEDS_REVIEW" : "VALID";
        assertEquals(
          vs,
          v.expected.validation_status,
          `${v.id} [escopo ${scope ?? "<sem escopo>"}]: validation_status esperado=${v.expected.validation_status} obtido=${vs}`,
        );
      }
    }
  });
}

// -----------------------------------------------------------------------------
// PARIDADE_INLINE — a expressão copiada acima ainda é a do index.ts?
// -----------------------------------------------------------------------------
Deno.test("PARIDADE_INLINE — lookup de dois níveis do index.ts inalterado", async () => {
  const src = await Deno.readTextFile(INDEX_URL);
  const normalized = src.replace(/\s+/g, " ");

  assert(
    normalized.includes(
      "const variantTypeId = variantTypeMaps.scopedMap.get(residualComboKey) ?? variantTypeMaps.globalMap.get(residualComboKey) ?? null;",
    ),
    "A expressão de lookup do index.ts mudou. Este teste reproduz essa expressão; " +
      "se ela mudar sem o teste mudar junto, os vetores passam a provar uma lógica " +
      "que a Edge não usa mais. Rebasear os dois juntos.",
  );

  // Guard negativo: o fallback NUNCA pode voltar a ser `||`, que descartaria
  // string vazia — e um variant_type_id vazio é dado corrompido, não ausência.
  assert(
    !normalized.includes("variantTypeMaps.scopedMap.get(residualComboKey) ||"),
    "index.ts usa `||` no fallback de escopo. Precisa ser `??`.",
  );
});

// -----------------------------------------------------------------------------
// COBERTURA — o arquivo de vetores não pode encolher em silêncio
// -----------------------------------------------------------------------------
Deno.test("COBERTURA — 10 vetores e bloco bindings presentes", () => {
  assertEquals(vectors.length, 10, "esperados 10 vetores (P1..P10)");
  assert(bindings, "arquivo de vetores sem bloco `bindings` — paridade não verificável");
  assertEquals(
    vectors.map((v) => v.id).join(","),
    "P1,P2,P3,P4,P5,P6,P7,P8,P9,P10",
    "ids dos vetores divergem do roster esperado",
  );
});
