// V1-14 R2-F (B2) — "Evolução da completude": leitura (5358) validada, indicadores, trechos e lacunas,
// mudanças e causas comprovadas, estados (zero/um fechamento, sem mudanças), textos, modelo do gráfico
// e guardas de código da folha, da sobreposição, do menu e da ação. Sem DOM: a renderização visual fica
// para a homologação do proprietário.
// Executar: node --experimental-strip-types --test lib/reports/completion-history.test.ts (a partir de web/)

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { collectionReportItems } from "./collection-checklist.ts";
import {
  type CompletionNow,
  buildCompletionReport,
  changeFacts,
  changeWhenText,
  closingText,
  completionEntries,
  expectedLastClosingDay,
  gapNoticeText,
  gapText,
  parseCompletionHistory,
  readAtText,
  recordedCauses,
  signedPp,
  sinceLastClosingText,
} from "./completion-history.ts";
import { axisLabel, completionChartAria, completionChartModel, completionChartOption, dayX, yScale } from "./completion-history-chart.ts";

const web = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const read = (path: string) => readFileSync(resolve(web, path), "utf8");
const code = (source: string) => source.replace(/\/\*[\s\S]*?\*\//g, "").replace(/^\s*\/\/.*$/gm, "").replace(/\{\/\*[\s\S]*?\*\/\}/g, "");

const SET = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const SET2 = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
const F1 = "11111111-1111-4111-8111-111111111111";
const F2 = "22222222-2222-4222-8222-222222222222";

type RawSnap = Partial<{
  day: string;
  captured_at: string;
  completion_policy: string;
  card_set_id: string | null;
  finish_type_ids: string[];
  lifecycle_status: string;
  total: number;
  satisfied: number;
  progress: number;
  opens_coverage: boolean;
}>;

function snap(day: string, satisfied: number, total: number, extra: RawSnap = {}) {
  const next = new Date(`${day}T12:00:00Z`);
  next.setUTCDate(next.getUTCDate() + 1);
  return {
    day,
    captured_at: `${next.toISOString().slice(0, 10)}T03:05:12Z`,
    completion_policy: "STANDARD_SET",
    card_set_id: SET,
    finish_type_ids: [],
    lifecycle_status: "ACTIVE",
    total,
    satisfied,
    progress: Math.round((satisfied / total) * 10000) / 100,
    opens_coverage: false,
    ...extra,
  };
}

function raw(coverage: Array<[string, string]>, snapshots: ReturnType<typeof snap>[]) {
  return {
    tracking_since: coverage[0]?.[0] ?? null,
    last_covered_day: coverage[coverage.length - 1]?.[1] ?? null,
    coverage: coverage.map(([from, to]) => ({ from, to })),
    snapshots,
  };
}

const NOW: CompletionNow = { satisfied: 125, total: 298, policy: "STANDARD_SET", lifecycle: "ACTIVE", cardSetId: SET };
/** 12/11/2026 09h00 de Brasília: o fechamento esperado mais recente é o de 11/11. */
const AT = new Date("2026-11-12T12:00:00Z");

function build(history: unknown, now: CompletionNow = NOW, at: Date = AT) {
  const parsed = parseCompletionHistory(history);
  assert.ok(parsed, "leitura válida");
  return buildCompletionReport({ history: parsed, now, at });
}

test("leitura: forma válida da 5358 é aceita; vazio é acompanhamento ainda não iniciado", () => {
  const empty = parseCompletionHistory({ tracking_since: null, last_covered_day: null, coverage: [], snapshots: [] });
  assert.deepEqual(empty, { trackingSince: null, lastCoveredDay: null, coverage: [], snapshots: [] });
  const one = parseCompletionHistory(raw([["2026-11-08", "2026-11-08"]], [snap("2026-11-08", 120, 295, { opens_coverage: true })]));
  assert.equal(one?.snapshots.length, 1);
  assert.equal(one?.trackingSince, "2026-11-08");
});

test("leitura: forma ou coerência inválida vira erro, nunca série inventada", () => {
  const base = () => raw([["2026-11-08", "2026-11-09"]], [snap("2026-11-08", 120, 295, { opens_coverage: true })]);
  const cases: Array<[string, unknown]> = [
    ["nulo", null],
    ["lista", []],
    ["sem cobertura", { snapshots: [] }],
    ["satisfeitas > total", raw([["2026-11-08", "2026-11-08"]], [snap("2026-11-08", 300, 295)])],
    ["negativo", raw([["2026-11-08", "2026-11-08"]], [snap("2026-11-08", -1, 295)])],
    ["dia inválido", raw([["2026-11-08", "2026-11-08"]], [snap("2026-02-30", 1, 2)])],
    ["fotografia fora da cobertura", raw([["2026-11-08", "2026-11-08"]], [snap("2026-11-08", 1, 2), snap("2026-11-10", 2, 2)])],
    ["intervalo sem fotografia de abertura", raw([["2026-11-08", "2026-11-08"], ["2026-11-10", "2026-11-11"]], [snap("2026-11-08", 1, 2)])],
    ["intervalos contíguos", raw([["2026-11-08", "2026-11-08"], ["2026-11-09", "2026-11-09"]], [snap("2026-11-08", 1, 2), snap("2026-11-09", 1, 2)])],
    ["fotografias fora de ordem", raw([["2026-11-08", "2026-11-10"]], [snap("2026-11-09", 1, 2), snap("2026-11-08", 1, 2)])],
    ["cobertura sem fotografias", raw([["2026-11-08", "2026-11-08"]], [])],
    ["início divergente", { ...base(), tracking_since: "2026-11-01" }],
    ["instante inválido", raw([["2026-11-08", "2026-11-08"]], [snap("2026-11-08", 1, 2, { captured_at: "ontem" })])],
  ];
  for (const [name, value] of cases) assert.equal(parseCompletionHistory(value), null, name);
});

test("sem nenhum fechamento: começa no fechamento desta noite; indicadores só com a completude atual", () => {
  const r = build({ tracking_since: null, last_covered_day: null, coverage: [], snapshots: [] });
  assert.equal(r.state, "no_history");
  assert.equal(r.delta, null);
  assert.equal(r.sinceLastClosing, null);
  assert.deepEqual(r.segments, []);
  assert.deepEqual(r.changes, []);
  assert.deepEqual(r.gaps, [], "sem acompanhamento não há lacuna");
  assert.equal(r.now.satisfied, 125);
  assert.equal(completionChartAria(r), "Gráfico da evolução da completude: ainda sem fechamentos.");
});

test("um único fechamento: variação contra o valor atual; a série parte do valor real (nunca de zero)", () => {
  const r = build(raw([["2026-11-11", "2026-11-11"]], [snap("2026-11-11", 120, 295, { opens_coverage: true })]));
  assert.equal(r.state, "single");
  assert.deepEqual(r.delta, { satisfied: 5, total: 3, pp: 1.3 });
  assert.equal(r.trackingSince, "2026-11-11");
  assert.equal(r.gapDays, 0);
  assert.equal(r.changes.length, 1);
  assert.equal(r.changes[0]?.kind, "start");
  assert.match(sinceLastClosingText(r) ?? "", /^Agora: \+5 posições satisfeitas · total esperado \+3 desde o fechamento de 11\/11\/2026 — entra no próximo fechamento\.$/);
  const model = completionChartModel(r, AT.getTime());
  assert.deepEqual(model.satisfied[0], [dayX("2026-11-11"), 120], "primeiro ponto = valor real do primeiro fechamento");
});

test("comprovado sem mudança: dias cobertos valem a última fotografia; 'Sem mudanças desde'", () => {
  const r = build(raw([["2026-11-08", "2026-11-11"]], [snap("2026-11-08", 120, 295, { opens_coverage: true })]), { ...NOW, satisfied: 120, total: 295 });
  assert.equal(r.state, "tracked");
  assert.equal(r.hasChanges, false);
  assert.deepEqual(r.segments, [{ from: "2026-11-08", to: "2026-11-11", points: [{ day: "2026-11-08", satisfied: 120, total: 295 }, { day: "2026-11-11", satisfied: 120, total: 295 }] }]);
  assert.deepEqual(r.delta, { satisfied: 0, total: 0, pp: 0 });
  assert.equal(signedPp(r.delta!.pp), "0,0 p.p.");
  assert.equal(sinceLastClosingText(r), "Sem diferença desde o fechamento de 08/11/2026.");
});

test("mudanças observadas: números objetivos; causa só quando gravada (D7)", () => {
  const r = build(
    raw(
      [["2026-11-05", "2026-11-11"]],
      [
        snap("2026-11-05", 120, 295, { opens_coverage: true }),
        snap("2026-11-07", 123, 295),
        snap("2026-11-09", 123, 298),
        snap("2026-11-10", 123, 298, { lifecycle_status: "ARCHIVED" }),
        snap("2026-11-11", 125, 298, { lifecycle_status: "ACTIVE" }),
      ],
    ),
  );
  assert.equal(r.hasChanges, true);
  const [reactivated, archived, totalChange, satisfiedChange, start] = r.changes; // decrescente
  assert.equal(start?.kind, "start");
  assert.equal(satisfiedChange?.kind, "change");
  assert.deepEqual(changeFacts(satisfiedChange!), ["Posições satisfeitas: 120 → 123"]);
  assert.deepEqual(satisfiedChange?.kind === "change" ? satisfiedChange.causes : null, [], "diferença de números não tem causa atribuída");
  assert.deepEqual(changeFacts(totalChange!), ["Total esperado: 295 → 298"]);
  assert.deepEqual(archived?.kind === "change" ? archived.causes.map((c) => c.text) : null, ["Coleção arquivada"]);
  assert.deepEqual(reactivated?.kind === "change" ? reactivated.causes.map((c) => c.text) : null, ["Coleção reativada"]);
  assert.equal(changeWhenText(reactivated!), "Fechamento de 11/11/2026");
  assert.deepEqual(changeFacts(reactivated!), ["Posições satisfeitas: 123 → 125"]);
  // Trecho arquivado no gráfico: do fechamento em que foi observado até o seguinte.
  const model = completionChartModel(r, AT.getTime());
  assert.deepEqual(model.archived, [[dayX("2026-11-10"), dayX("2026-11-11")]]);
});

test("causas comprovadas: modalidade, Card Set, acabamentos do Master Set e situação", () => {
  const a = parseCompletionHistory(raw([["2026-11-08", "2026-11-08"]], [snap("2026-11-08", 1, 2, { opens_coverage: true })]))!.snapshots[0]!;
  assert.deepEqual(recordedCauses(a, { ...a, policy: "MASTER_SET" }).map((c) => c.text), ["Modalidade: Set padrão → Master Set"]);
  assert.deepEqual(recordedCauses(a, { ...a, cardSetId: SET2 }).map((c) => c.kind), ["card-set"]);
  const m = { ...a, policy: "MASTER_SET", finishIds: [F1] };
  assert.deepEqual(recordedCauses(m, { ...m, finishIds: [F1, F2] }).map((c) => c.text), ["Acabamentos adotados alterados (1 → 2)"]);
  assert.deepEqual(recordedCauses(a, { ...a, satisfied: 2, total: 3 }), [], "números diferentes sem causa gravada");
  // Ordem dos acabamentos não é mudança (lista normalizada na leitura).
  const parsed = parseCompletionHistory(
    raw(
      [["2026-11-08", "2026-11-09"]],
      [
        snap("2026-11-08", 1, 2, { completion_policy: "MASTER_SET", finish_type_ids: [F2, F1], opens_coverage: true }),
        snap("2026-11-09", 2, 2, { completion_policy: "MASTER_SET", finish_type_ids: [F1, F2] }),
      ],
    ),
  )!;
  assert.deepEqual(recordedCauses(parsed.snapshots[0]!, parsed.snapshots[1]!), []);
});

test("lacunas: trechos nunca ligados; diferença através da lacuna é período, não data exata (D6)", () => {
  const r = build(
    raw(
      [
        ["2026-11-01", "2026-11-03"],
        ["2026-11-07", "2026-11-11"],
      ],
      [snap("2026-11-01", 100, 295, { opens_coverage: true }), snap("2026-11-02", 104, 295), snap("2026-11-07", 110, 295, { opens_coverage: true })],
    ),
  );
  assert.equal(r.segments.length, 2);
  assert.deepEqual(r.gaps, [{ from: "2026-11-04", to: "2026-11-06", days: 3, open: false }]);
  assert.equal(r.gapDays, 3);
  const resume = r.changes[0]!;
  assert.equal(resume.kind, "resume");
  assert.equal(changeWhenText(resume), "Entre 03/11/2026 e 07/11/2026 (período sem registro)");
  assert.deepEqual(changeFacts(resume), ["Posições satisfeitas: 104 → 110"]);
  assert.equal(gapText(r.gaps[0]!), "Entre 04/11/2026 e 06/11/2026 · sem registro (3 dias)");
  assert.match(gapNoticeText(r) ?? "", /^3 dias sem registro no período acompanhado\./);

  // Gráfico: um valor vazio separa os trechos; nenhum par de pontos consecutivos atravessa a lacuna.
  const model = completionChartModel(r, AT.getTime());
  for (const series of [model.satisfied, model.total]) {
    const breakIndex = series.findIndex(([, v]) => v === null);
    assert.ok(breakIndex > 0, "há interrupção");
    const before = series[breakIndex - 1]!;
    const after = series[breakIndex + 1]!;
    assert.equal(before[0], dayX("2026-11-03"));
    assert.equal(after[0], dayX("2026-11-07"));
    for (let i = 1; i < series.length; i += 1) {
      const [x0, v0] = series[i - 1]!;
      const [x1, v1] = series[i]!;
      if (v0 !== null && v1 !== null) assert.ok(!(x0 < dayX("2026-11-04") && x1 > dayX("2026-11-06")), "nenhum segmento liga os trechos");
    }
  }
  const option = completionChartOption(r, { nowMs: AT.getTime(), print: false, animate: false }) as { series: Array<{ type: string; connectNulls?: boolean; step?: string }> };
  for (const s of option.series.filter((s) => s.type === "line")) {
    assert.equal(s.connectNulls, false);
    assert.equal(s.step, "end");
  }
  // Ordem da lista: retomada, lacuna que ela encerra, depois o que veio antes.
  assert.deepEqual(
    completionEntries(r).map((e) => (e.change ? `${e.change.kind}.${e.change.day}` : `gap.${e.gap!.from}`)),
    ["resume.2026-11-07", "gap.2026-11-04", "change.2026-11-02", "start.2026-11-01"],
  );
});

test("retomada sem diferença continua sendo uma observação nova (nada se presume sobre a lacuna)", () => {
  const r = build(
    raw(
      [
        ["2026-11-01", "2026-11-01"],
        ["2026-11-05", "2026-11-11"],
      ],
      [snap("2026-11-01", 100, 295, { opens_coverage: true }), snap("2026-11-05", 100, 295, { opens_coverage: true })],
    ),
  );
  assert.equal(r.changes[0]?.kind, "resume");
  assert.equal(r.hasChanges, false);
  assert.deepEqual(changeFacts(r.changes[0]!), ["100 de 295 posições satisfeitas · sem diferença nos números"]);
});

test("lacuna aberta: fechamento esperado já passou e não há registro (03h00 de Brasília)", () => {
  assert.equal(expectedLastClosingDay(new Date("2026-11-12T12:00:00Z")), "2026-11-11"); // 09h00 BRT
  assert.equal(expectedLastClosingDay(new Date("2026-11-12T05:59:00Z")), "2026-11-10"); // 02h59 BRT: janela de 11/11 aberta
  assert.equal(expectedLastClosingDay(new Date("2026-11-12T06:00:00Z")), "2026-11-11"); // 03h00 BRT
  assert.equal(expectedLastClosingDay(new Date("2026-11-12T01:00:00Z")), "2026-11-10"); // 22h00 de 11/11 BRT
  const r = build(raw([["2026-11-05", "2026-11-08"]], [snap("2026-11-05", 120, 295, { opens_coverage: true })]));
  assert.deepEqual(r.gaps, [{ from: "2026-11-09", to: "2026-11-11", days: 3, open: true }]);
  assert.equal(gapText(r.gaps[0]!), "Desde 09/11/2026 · sem registro (3 dias)");
  const fresh = build(raw([["2026-11-05", "2026-11-11"]], [snap("2026-11-05", 120, 295, { opens_coverage: true })]));
  assert.deepEqual(fresh.gaps, [], "cobertura em dia");
});

test("textos de tempo: 'fechamento de dd/mm' + instante efetivo em Brasília; nunca 23h59", () => {
  assert.equal(closingText("2026-11-08"), "Fechamento de 08/11/2026");
  assert.equal(readAtText("2026-11-09T03:05:12Z"), "lido em 09/11 às 00:05");
  assert.equal(readAtText("2026-11-09T02:30:00Z"), "lido em 08/11 às 23:30");
  for (const file of ["lib/reports/completion-history.ts", "lib/reports/completion-history-chart.ts", "components/reports/completion-history-report.tsx"]) {
    assert.ok(!/23h59|23:59/.test(code(read(file))), `${file} não rotula fechamento como 23h59`);
  }
});

test("indicadores: numerador e denominador separados; p.p. pelos valores exatos", () => {
  const r = build(raw([["2026-11-08", "2026-11-11"]], [snap("2026-11-08", 1, 3, { opens_coverage: true })]), { ...NOW, satisfied: 2, total: 3 });
  assert.deepEqual(r.delta, { satisfied: 1, total: 0, pp: 33.3 });
  assert.equal(signedPp(-2.25), "−2,3 p.p.");
  const sheet = code(read("components/reports/completion-history-report.tsx"));
  for (const label of ['label="Completude atual"', 'label="Variação desde o início"', 'label="Total esperado"']) assert.ok(sheet.includes(label), label);
  assert.ok(sheet.includes("progressPercentText(now.satisfied, now.total)"), "percentual atual com a mesma regra do produto");
});

test("gráfico: eixo adaptado ao período; 'agora' separado; teto acima do total; impressão estática", () => {
  assert.equal(axisLabel(dayX("2026-11-08"), 30), "08/11");
  assert.equal(axisLabel(dayX("2026-11-08"), 200), "nov/26");
  const r = build(raw([["2026-11-05", "2026-11-11"]], [snap("2026-11-05", 120, 295, { opens_coverage: true }), snap("2026-11-09", 123, 298)]));
  const model = completionChartModel(r, AT.getTime());
  assert.deepEqual(model.now.value, [AT.getTime(), 125]);
  assert.ok(!model.satisfied.some(([x]) => x === AT.getTime()), "'agora' não entra na linha dos fechamentos");
  assert.ok(model.yMax >= 298);
  assert.deepEqual(yScale(298), { max: 400, interval: 100 });
  assert.deepEqual(yScale(203), { max: 250, interval: 50 });
  assert.deepEqual(yScale(1), { max: 4, interval: 1 });
  for (const total of [1, 7, 38, 158, 203, 298, 1025, 5000]) {
    const { max, interval } = yScale(total);
    assert.ok(max >= total && Number.isInteger(max / interval) && max / interval <= 5, `escala de ${total}`);
  }
  const option = completionChartOption(r, { nowMs: AT.getTime(), print: true, animate: true }) as { animation: boolean; tooltip: { show?: boolean }; series: Array<{ name: string }> };
  assert.equal(option.animation, false);
  assert.equal(option.tooltip.show, false);
  assert.deepEqual(option.series.map((s) => s.name), ["Total esperado", "Posições satisfeitas", "Fechamentos com mudança", "Mudança de objetivo ou situação", "Agora"]);
});

test("menu: 'Evolução da completude' é o 6º item; Set padrão e Master Set; indisponível com motivo nos demais", () => {
  for (const policy of ["STANDARD_SET", "MASTER_SET"]) {
    const items = collectionReportItems({ collectionId: "c", completionPolicy: policy, totalPositions: 100, satisfiedPositions: 62 });
    assert.deepEqual(items.map((i) => i.id), ["checklist", "missing", "set-wishlist", "set-favorites", "collection-value", "completion-history"]);
    assert.equal(items[5]?.label, "Evolução da completude");
    assert.equal(items[5]?.icon, "evolution");
    assert.equal(items[5]?.disabledReason, null);
  }
  for (const policy of ["REFERENCE_POSITION", "NONE", "POKEDEX"]) {
    const items = collectionReportItems({ collectionId: "c", completionPolicy: policy, totalPositions: 10, satisfiedPositions: 1 });
    assert.equal(items[5]?.disabledReason, "Para coleções de Set padrão e Master Set.");
  }
  assert.ok(read("components/reports/report-menu.tsx").includes("evolution: TrendingUp"));
});

test("abertura e autorização: ação valida o id e a sessão; coleção autorizada (5332) antes do histórico (5358)", () => {
  const action = code(read("components/reports/collection-reports-action.tsx"));
  assert.ok(action.includes('{report === "completion-history" ? <CompletionHistoryOverlay collectionId={collectionId} onClose={() => setReport(null)} /> : null}'));
  for (const id of ["checklist", "missing", "set-wishlist", "set-favorites", "collection-value"]) assert.ok(action.includes(`report === "${id}"`), `${id} preservado`);
  const actions = read("app/colecoes/colecoes/[id]/relatorios/actions.ts");
  const fn = actions.slice(actions.indexOf("export async function readCompletionHistoryReport"));
  assert.ok(fn.includes('if (!isCollectionId(input?.collectionId)) return { ok: false, reason: "not_found" };'));
  assert.ok(fn.includes('if (!user) return { ok: false, reason: "not_found" };'));
  assert.ok(fn.includes("prepareCompletionHistoryReport(supabase, input.collectionId.toLowerCase())"));
  const queries = code(read("lib/reports/completion-history-queries.ts"));
  const authorize = queries.indexOf("await getMyCollection(supabase, collectionId)");
  const history = queries.indexOf("rpc(RPC_5358_HISTORY, { p_collection_id: authorizedId })");
  assert.ok(authorize > 0 && history > authorize, "5332 antes da 5358, com o id da coleção autorizada");
  assert.ok(queries.indexOf('if (kind === null) return { status: "unavailable"') < history, "Pokédex/livre não leem histórico");
  assert.ok(queries.includes('if (res.error.code === "P0002") return { status: "not_found" };'), "alheia/compartilhada/inexistente → neutro");
  assert.ok(!/\.from\(\s*["']collection_completion/.test(queries), "nenhuma leitura direta das tabelas");
});

test("folha: impressão com indicadores e gráfico na 1ª página, lista nas seguintes; estados de zero e um fechamento", () => {
  const sheet = code(read("components/reports/completion-history-report.tsx"));
  assert.ok(sheet.includes("print:[break-before:page]"), "mudanças começam na 2ª folha");
  assert.ok(sheet.includes('<CompletionHistoryChart report={report} nowMs={readAtMs} height={CHART_HEIGHT.print} print />'), "instância estática de impressão");
  assert.ok(sheet.includes("O acompanhamento começa no fechamento desta noite."));
  assert.ok(sheet.includes("A evolução aparece a partir do próximo fechamento."));
  assert.ok(sheet.includes("Sem mudanças desde {since}."));
  assert.ok(sheet.includes("Acompanhando desde"));
  assert.ok(sheet.includes("Último fechamento"));
  const overlay = code(read("components/reports/completion-history-overlay.tsx"));
  assert.ok(overlay.includes("readCompletionHistoryReport({ collectionId })"));
  assert.ok(overlay.includes("shareInFlight("), "uma leitura por vez, sem cache depois");
});
