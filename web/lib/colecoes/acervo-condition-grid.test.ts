import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { getPageConditionMix } from "./acervo-condition-queries.ts";
import {
  type ConditionTally,
  PAGE_CONDITION_READ_MAX,
  conditionDistributionAccessible,
  conditionDistributionText,
  conditionGroupKey,
  gridConditionChips,
  pageConditionMix,
} from "./condition-distribution.ts";

const read = (path: string) => readFileSync(new URL(`../../${path}`, import.meta.url), "utf8");
const V1 = "00000000-0000-4000-8000-0000000000a1";
const V2 = "00000000-0000-4000-8000-0000000000b2";
const PT = "00000000-0000-4000-8000-00000000f001";
const EN = "00000000-0000-4000-8000-00000000f002";
const JA = "00000000-0000-4000-8000-00000000f003";
const languages = [
  { id: PT, code: "pt-BR" },
  { id: EN, code: "en" },
];
const row = (v: string, l: string, c: string) => ({ card_variant_id: v, language_id: l, condition_code: c });
const text = (t: ConditionTally | undefined) => (t ? conditionDistributionText(t) : null);
const run = (groups: { cardVariantId: string; languageCode: string; copiesOwned: number }[], rows: unknown[], count: number | null = rows.length) =>
  pageConditionMix({ groups, languages, rows, count });

test("mesma variante, idiomas diferentes: grupos separados", () => {
  const groups = [
    { cardVariantId: V1, languageCode: "pt-BR", copiesOwned: 3 },
    { cardVariantId: V1, languageCode: "en", copiesOwned: 2 },
  ];
  const { mix, issues } = run(groups, [row(V1, PT, "LP"), row(V1, EN, "HP"), row(V1, EN, "HP")]);
  assert.deepEqual(issues, []);
  assert.equal(text(mix.get(conditionGroupKey(V1, "pt-BR"))), "NM ×2 · SP ×1");
  assert.equal(text(mix.get(conditionGroupKey(V1, "en"))), "HP ×2", "nenhum NM: total = não-NM");
});

test("distribuição mista e NM por diferença; Σ = total do grupo", () => {
  const { mix } = run([{ cardVariantId: V1, languageCode: "pt-BR", copiesOwned: 10 }], [row(V1, PT, "M"), row(V1, PT, "MP"), row(V1, PT, "DMG"), row(V1, PT, "LP")]);
  const t = mix.get(conditionGroupKey(V1, "pt-BR"))!;
  assert.equal(conditionDistributionText(t), "M ×1 · NM ×6 · SP ×1 · MP ×1 · DM ×1");
  assert.equal(Object.values(t.counts).reduce((s, n) => s + n, 0), 10);
  assert.equal(t.total, 10);
  assert.equal(t.unrecognized, 0);
});

test("CORRECTION-01 (substitui a D1): grupo todo NM mostra NM ×N; sem exemplar físico, nada", () => {
  const groups = [
    { cardVariantId: V1, languageCode: "pt-BR", copiesOwned: 4 },
    { cardVariantId: V2, languageCode: "pt-BR", copiesOwned: 2 },
    { cardVariantId: V2, languageCode: "en", copiesOwned: 0 },
  ];
  const { mix, issues } = run(groups, [row(V2, PT, "HP")]);
  assert.deepEqual(issues, []);
  assert.equal(text(mix.get(conditionGroupKey(V1, "pt-BR"))), "NM ×4");
  assert.equal(text(mix.get(conditionGroupKey(V2, "pt-BR"))), "NM ×1 · HP ×1");
  assert.equal(mix.has(conditionGroupKey(V2, "en")), false, "grupo sem exemplar físico: sem chips");
  // Página toda NM: leitura completa com zero linhas.
  const allNm = run(groups.slice(0, 1), [], 0);
  assert.equal(text(allNm.mix.get(conditionGroupKey(V1, "pt-BR"))), "NM ×4");
  assert.deepEqual(gridConditionChips(allNm.mix.get(conditionGroupKey(V1, "pt-BR"))!), {
    chips: [{ code: "NM", short: "NM", name: "Near Mint", count: 4 }],
    more: 0,
  });
});

test("CORRECTION-01: NM nunca presumido quando a leitura falha ou fica incompleta", () => {
  const groups = [{ cardVariantId: V1, languageCode: "pt-BR", copiesOwned: 4 }];
  assert.equal(run(groups, [], null).mix.size, 0, "sem contagem exata");
  assert.equal(run(groups, [], 3).mix.size, 0, "contagem > linhas recebidas");
  assert.equal(run(groups, [], PAGE_CONDITION_READ_MAX + 1).mix.size, 0, "acima do teto");
  assert.equal(run(groups, [{ card_variant_id: V1 }], 1).mix.size, 0, "linha malformada");
  // Variante com idioma sem código conhecido: não dá para saber de qual grupo é → sem NM inferido.
  assert.equal(run(groups, [row(V1, JA, "HP")]).mix.has(conditionGroupKey(V1, "pt-BR")), false);
  // Código inesperado no grupo → sem chips (não vira NM).
  assert.equal(run(groups, [row(V1, PT, "XX")]).mix.has(conditionGroupKey(V1, "pt-BR")), false);
});

test("D2: total = copiesOwned (todos os exemplares), nunca o recorte filtrado", () => {
  // Filtro de local mostra 1 aqui; a identidade tem 5 (copiesOwned). A leitura não-NM não tem filtro.
  const { mix } = run([{ cardVariantId: V1, languageCode: "pt-BR", copiesOwned: 5 }], [row(V1, PT, "LP")]);
  assert.equal(text(mix.get(conditionGroupKey(V1, "pt-BR"))), "NM ×4 · SP ×1");
  const view = read("components/colecoes/acervo/acervo-view.tsx");
  assert.ok(!/conditionMix[^\n]*copiesCount/.test(view));
  const queries = read("lib/colecoes/acervo-condition-queries.ts");
  assert.ok(!/storage_container_id|collection/.test(queries.slice(queries.indexOf("export async function"))), "sem filtro de local/coleção");
});

test("variante da página em outro idioma (fora da página) é ignorada sem afetar os grupos", () => {
  const { mix, issues } = run([{ cardVariantId: V1, languageCode: "pt-BR", copiesOwned: 2 }], [row(V1, EN, "HP"), row(V1, PT, "MP")]);
  assert.deepEqual(issues, []);
  assert.equal(text(mix.get(conditionGroupKey(V1, "pt-BR"))), "NM ×1 · MP ×1");
  assert.equal(mix.size, 1);
});

test("limite e retorno incompleto: nenhuma distribuição na página", () => {
  const groups = [{ cardVariantId: V1, languageCode: "pt-BR", copiesOwned: 3 }];
  const rows = [row(V1, PT, "LP")];
  assert.deepEqual(run(groups, rows, null).issues, ["count_missing"]);
  assert.equal(run(groups, rows, null).mix.size, 0);
  assert.deepEqual(run(groups, rows, 2).issues, ["count_mismatch"], "count maior que as linhas recebidas (resposta truncada)");
  assert.equal(run(groups, rows, 2).mix.size, 0);
  assert.deepEqual(run(groups, rows, PAGE_CONDITION_READ_MAX + 1).issues, ["over_limit"]);
  assert.equal(run(groups, rows, PAGE_CONDITION_READ_MAX + 1).mix.size, 0);
});

test("inconsistências: leitura incoerente derruba a página; dúvida no grupo derruba só o grupo", () => {
  const groups = [
    { cardVariantId: V1, languageCode: "pt-BR", copiesOwned: 2 },
    { cardVariantId: V2, languageCode: "pt-BR", copiesOwned: 3 },
  ];
  // Variante que não foi pedida → resposta incoerente → nada.
  assert.equal(run(groups, [row(V1, PT, "LP"), row("00000000-0000-4000-8000-0000000000ff", PT, "HP")]).mix.size, 0);
  // Linha malformada → nada.
  assert.equal(run(groups, [row(V1, PT, "LP"), { card_variant_id: V2 }]).mix.size, 0);
  // Não-NM acima do total (adição/remoção concorrente) → só esse grupo some.
  const over = run(groups, [row(V1, PT, "LP"), row(V1, PT, "HP"), row(V1, PT, "MP"), row(V2, PT, "HP")]);
  assert.equal(over.mix.has(conditionGroupKey(V1, "pt-BR")), false);
  assert.equal(text(over.mix.get(conditionGroupKey(V2, "pt-BR"))), "NM ×2 · HP ×1");
  assert.ok(over.issues.includes("exceeds_total"));
  // Código inesperado → grupo sem resumo (nunca "não reconhecida" estimada nem NM inventado).
  const odd = run(groups, [row(V1, PT, "XX"), row(V2, PT, "HP")]);
  assert.equal(odd.mix.has(conditionGroupKey(V1, "pt-BR")), false);
  assert.ok(odd.issues.includes("unexpected_code"));
  // NM numa leitura de não-NM → grupo sem resumo.
  assert.equal(run(groups, [row(V1, PT, "NM"), row(V1, PT, "HP")]).mix.has(conditionGroupKey(V1, "pt-BR")), false);
  // Idioma sem código conhecido → a variante inteira fica sem resumo.
  const lang = run(
    [
      { cardVariantId: V1, languageCode: "pt-BR", copiesOwned: 3 },
      { cardVariantId: V2, languageCode: "pt-BR", copiesOwned: 3 },
    ],
    [row(V1, PT, "LP"), row(V1, JA, "HP"), row(V2, PT, "HP")],
  );
  assert.equal(lang.mix.has(conditionGroupKey(V1, "pt-BR")), false);
  assert.equal(text(lang.mix.get(conditionGroupKey(V2, "pt-BR"))), "NM ×2 · HP ×1");
  assert.ok(lang.issues.includes("unmapped_language"));
});

test("chips: até três na ordem canônica + '+n'; leitura completa acessível", () => {
  const t: ConditionTally = { counts: { M: 1, NM: 2, LP: 1, MP: 1, HP: 0, DMG: 3 }, unrecognized: 0, total: 8 };
  const { chips, more } = gridConditionChips(t);
  assert.deepEqual(chips.map((c) => `${c.short}×${c.count}`), ["M×1", "NM×2", "SP×1"]);
  assert.equal(more, 2);
  assert.equal(conditionDistributionAccessible(t), "Condições declaradas: 1 Mint, 2 Near Mint, 1 Slightly Played, 1 Moderately Played, 3 Damaged");
  assert.ok(!/preço|grad/i.test(conditionDistributionAccessible(t)));
  assert.equal(gridConditionChips({ counts: { M: 0, NM: 1, LP: 0, MP: 0, HP: 1, DMG: 0 }, unrecognized: 0, total: 2 }).more, 0);
});

type Call = { table: string; select?: string; opts?: unknown; in?: [string, string[]]; neq?: [string, string]; limit?: number };
function fakeClient(result: { data: unknown; error: unknown; count: number | null } | Error, calls: Call[]) {
  return {
    from(table: string) {
      const call: Call = { table };
      calls.push(call);
      const b = {
        select(cols: string, opts: unknown) {
          call.select = cols;
          call.opts = opts;
          return b;
        },
        in(col: string, vals: string[]) {
          call.in = [col, vals];
          return b;
        },
        neq(col: string, val: string) {
          call.neq = [col, val];
          return b;
        },
        limit(n: number) {
          call.limit = n;
          if (result instanceof Error) return Promise.reject(result);
          return Promise.resolve(result);
        },
      };
      return b;
    },
  } as never;
}

test("leitura G1: uma consulta, só variantes da página, só não-NM, count exato, teto; falha → null sem lançar", async () => {
  const quiet = console.error;
  console.error = () => {};
  try {
    const groups = [
      { cardVariantId: V1.toUpperCase(), languageCode: "pt-BR", copiesOwned: 2 },
      { cardVariantId: V1, languageCode: "en", copiesOwned: 1 },
    ];
    const calls: Call[] = [];
    const mix = await getPageConditionMix(fakeClient({ data: [row(V1, PT, "LP")], error: null, count: 1 }, calls), groups, languages);
    assert.equal(calls.length, 1);
    assert.equal(calls[0]!.table, "physical_card");
    assert.equal(calls[0]!.select, "card_variant_id, language_id, condition_code", "sem id de exemplar");
    assert.deepEqual(calls[0]!.opts, { count: "exact" });
    assert.deepEqual(calls[0]!.in, ["card_variant_id", [V1]], "variantes deduplicadas");
    assert.deepEqual(calls[0]!.neq, ["condition_code", "NM"]);
    assert.equal(calls[0]!.limit, PAGE_CONDITION_READ_MAX);
    assert.equal(text(mix?.get(conditionGroupKey(V1, "pt-BR"))), "NM ×1 · SP ×1");

    const allNm = await getPageConditionMix(fakeClient({ data: [], error: null, count: 0 }, []), groups, languages);
    assert.equal(text(allNm?.get(conditionGroupKey(V1, "pt-BR"))), "NM ×2", "leitura completa sem não-NM → todo NM");
    assert.equal(text(allNm?.get(conditionGroupKey(V1, "en"))), "NM ×1");
    const none: Call[] = [];
    assert.equal((await getPageConditionMix(fakeClient({ data: [], error: null, count: 0 }, none), [], languages))?.size, 0);
    assert.equal(none.length, 0, "página vazia: nenhuma leitura");
    assert.equal(await getPageConditionMix(fakeClient({ data: [], error: null, count: 0 }, []), groups, []), null, "sem idiomas: sem resumo");
    assert.equal(await getPageConditionMix(fakeClient({ data: null, error: { code: "42501" }, count: null }, []), groups, languages), null);
    assert.equal(await getPageConditionMix(fakeClient(new Error("network"), []), groups, languages), null, "exceção não derruba a página");
    const partial = await getPageConditionMix(fakeClient({ data: [row(V1, PT, "LP")], error: null, count: 5 }, []), groups, languages);
    assert.equal(partial?.size, 0, "truncada: nenhuma distribuição (nem NM presumido)");
  } finally {
    console.error = quiet;
  }
});

test("página: leitura na 2ª rodada paralela, sem mudar a 5159; grade mostra chips e nome acessível", () => {
  const page = read("app/colecoes/acervo/page.tsx");
  assert.ok(page.includes("getPageConditionMix(supabase, page?.items ?? [], addLanguages)"));
  assert.ok(page.includes("conditionMix={conditionMix}"));
  assert.ok(page.includes("const ACERVO_RENDER_READS_BASE = 12;"));
  const items = read("lib/colecoes/acervo-queries.ts");
  assert.ok(!/condition/i.test(items.slice(items.indexOf("export async function getAcervoItems"), items.indexOf("type OptionRow"))), "get_my_inventory_items intocada");
  const view = read("components/colecoes/acervo/acervo-view.tsx");
  assert.ok(view.includes("conditionMix?.get(conditionGroupKey(item.cardVariantId, item.languageCode))"), "identidade exata variante + idioma");
  assert.ok(view.includes("conditions ? conditionDistributionAccessible(conditions) : null"), "descrição completa no nome acessível");
  assert.ok(view.includes("const display = gridConditionDisplay(conditions);"), "sem dado → sem condição");
  const chips = view.slice(view.indexOf("function GridConditionChips"), view.indexOf("function ActiveFilterChips"));
  assert.ok(chips.includes("conditionStyles.conditionCode"), "mesmo selo de Seus exemplares");
  assert.ok(chips.includes("+{formatCount(display.moreNarrow)}") && chips.includes("+{formatCount(display.moreWide)}"));
  const css = read("components/colecoes/acervo/acervo.module.css");
  assert.match(css, /\.conditionChips \{[^}]*flex-wrap: wrap;/);
});

test("edição de condição revalida o Meu acervo → resumo relido na próxima renderização", () => {
  const actions = read("app/colecoes/acervo/actions.ts");
  const fn = actions.slice(actions.indexOf("export async function setMyCopiesCondition"));
  assert.ok(/revalidatePath\(ACERVO_PATH\)/.test(fn.slice(0, 2000)));
});
