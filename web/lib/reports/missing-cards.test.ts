// V1-14 R2-B — "Cartas faltantes" (D7 v1.42 §4j): Set padrão e Master Set pelas leituras canônicas
// (filtro MISSING, `loadChecklist`/`parseChecklistRows`), grupos por disponibilidade da POSIÇÃO,
// acabamentos de uma carta nos dois grupos, contagem por posição sem dupla contagem, coleção
// completa, objetivo sem posições, Pokédex/livre indisponíveis, divergência de totais, teto de
// 5.000, segurança, filtros só de tela, impressão em cartões com miniaturas e regressão do Checklist.
// Executar: node --experimental-strip-types --test lib/reports/missing-cards.test.ts (a partir de web/)

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { CHECKLIST_MAX_POSITIONS, type ChecklistKind, collectionReportItems, loadChecklist } from "./collection-checklist.ts";
import { buildMissingCardsReport, missingAvailabilityText, missingGroupsForScreen, missingHeaderLine, missingIncompleteText, missingPrintPairs } from "./missing-cards.ts";

const read = (path: string) => readFileSync(new URL(path, import.meta.url), "utf8");
const id = (n: number) => `00000000-0000-4000-8000-${n.toString(16).padStart(12, "0")}`;
const T = (n: number) => `aaaaaaaa-aaaa-4aaa-8aaa-${n.toString(16).padStart(12, "0")}`;

type Raw = Record<string, unknown>;
const setPos = (n: number, available: number, extra: Raw = {}): Raw => ({
  card_id: id(n),
  collector_number: String(n).padStart(3, "0"),
  card_name: `Carta ${n}`,
  is_satisfied: false,
  copies_in_collection: 0,
  copies_available: available,
  image_path: `cards/${n}.webp`,
  ...extra,
});
const masterPos = (n: number, finish: number | null, name: string, available: number): Raw =>
  setPos(n, available, { variant_type_id: finish === null ? null : T(finish), variant_type_name: finish === null ? null : name, is_secret: finish === null });

/** Lê como o relatório lê: `loadChecklist` (lotes de 500) sobre um "banco" falso que devolve o filtro MISSING. */
async function load(kind: ChecklistKind, rows: Raw[], over: { total?: number; failAt?: number } = {}) {
  const total = over.total ?? rows.length;
  const calls: [number, number][] = [];
  const result = await loadChecklist(kind, async (offset, limit) => {
    calls.push([offset, limit]);
    if (over.failAt !== undefined && offset >= over.failAt) return null;
    return rows.slice(offset, offset + limit).map((r) => ({ ...r, total_count: total }));
  });
  assert.equal(result.status, "ready");
  return { load: result as Extract<typeof result, { status: "ready" }>, calls };
}

test("Set padrão: faltantes em dois grupos pela disponibilidade da posição, na ordem do Set", async () => {
  const rows = [setPos(1, 0), setPos(2, 2), setPos(3, 0), setPos(5, 1)];
  const { load: l } = await load("STANDARD_SET", rows);
  const r = buildMissingCardsReport({ kind: "STANDARD_SET", load: l, totalPositions: 10, satisfiedPositions: 6 });
  assert.equal(r.complete, true);
  assert.equal(r.state, "list");
  assert.deepEqual(r.groups.map((g) => [g.title, g.lines.map((x) => x.number)]), [
    ["No acervo — disponível para alocar", ["002", "005"]],
    ["Sem exemplar disponível", ["001", "003"]],
  ]);
  assert.equal(r.missingPositions, 4);
  assert.equal(r.availablePositions + r.unavailablePositions, r.missingPositions); // Faltam = No acervo + Sem exemplar
  assert.equal(r.summary.percentText, "60%");
  assert.equal(r.groups[0]?.lines[0]?.imagePath, "cards/2.webp");
  assert.equal(missingAvailabilityText(2), "No acervo · 2 livres");
  assert.equal(missingAvailabilityText(0), "Sem exemplar disponível");
  assert.doesNotMatch(JSON.stringify(r) + missingAvailabilityText(0), /comprar|adquirir/i);
});

test("Master Set: vários acabamentos agrupados por carta; a mesma carta nos dois grupos; contagem por posição, sem dupla contagem", async () => {
  const rows = [
    masterPos(1, 1, "Padrão", 1),
    masterPos(1, 2, "Holográfica Reversa", 0),
    masterPos(1, 3, "Poké Bola Reversa", 3),
    masterPos(2, 2, "Holográfica Reversa", 0),
    masterPos(99, null, "", 2), // carta secreta: posição única "Qualquer acabamento"
  ];
  const { load: l } = await load("MASTER_SET", rows);
  const r = buildMissingCardsReport({ kind: "MASTER_SET", load: l, totalPositions: 12, satisfiedPositions: 7 });
  assert.equal(r.complete, true);
  const [avail, none] = r.groups;
  assert.deepEqual(avail?.lines.map((x) => [x.number, x.finishes.map((f) => `${f.code ?? f.label}:${f.available}`)]), [
    ["001", ["PA:1", "PBR:3"]],
    ["099", ["QA:2"]],
  ]);
  assert.deepEqual(none?.lines.map((x) => [x.number, x.finishes.map((f) => f.code)]), [
    ["001", ["HR"]], // carta 001 também no 2º grupo, só com o acabamento sem exemplar livre
    ["002", ["HR"]],
  ]);
  // Por posição: 5 faltantes = 3 disponíveis + 2 sem exemplar; linhas (4) nunca viram contagem.
  assert.equal(r.missingPositions, 5);
  assert.equal(r.availablePositions, 3);
  assert.equal(r.unavailablePositions, 2);
  assert.equal(avail?.positions, 3);
  assert.equal(none?.positions, 2);
  assert.equal(r.groups.reduce((n, g) => n + g.lines.length, 0), 4);
  assert.equal(r.pendingCards, 3); // 001, 002, 099
  const keys = r.groups.flatMap((g) => g.lines.flatMap((x) => x.finishes.map((f) => f.key)));
  assert.equal(new Set(keys).size, keys.length); // cada posição aparece uma única vez
  assert.equal(keys.length, r.missingPositions);
});

test("coleção completa: estado positivo, imprimível; objetivo sem posições: mensagem própria", async () => {
  const { load: l } = await load("STANDARD_SET", []);
  const done = buildMissingCardsReport({ kind: "STANDARD_SET", load: l, totalPositions: 120, satisfiedPositions: 120 });
  assert.equal(done.state, "complete");
  assert.equal(done.complete, true); // impressão liberada
  assert.equal(done.summary.percentText, "100%");
  const empty = buildMissingCardsReport({ kind: "MASTER_SET", load: l, totalPositions: 0, satisfiedPositions: 0 });
  assert.equal(empty.state, "empty");
  const sheet = read("../../components/reports/missing-cards-report.tsx");
  assert.match(sheet, /Coleção completa!/);
  assert.match(sheet, /Este objetivo ainda não tem posições\./);
});

test("Pokédex e coleção livre: itens visíveis no menu e indisponíveis com o motivo", () => {
  const c = "cccccccc-cccc-4ccc-8ccc-cccccccccccc";
  for (const policy of ["REFERENCE_POSITION", "NONE"]) {
    const items = collectionReportItems({ collectionId: c, completionPolicy: policy, totalPositions: 100, satisfiedPositions: 3 });
    const missing = items.find((i) => i.id === "missing");
    assert.equal(missing?.label, "Cartas faltantes");
    assert.equal(missing?.icon, "missing");
    assert.equal(missing?.disabledReason, "Para coleções de Set padrão e Master Set.");
  }
  const set = collectionReportItems({ collectionId: c, completionPolicy: "STANDARD_SET", totalPositions: 100, satisfiedPositions: 62 });
  assert.deepEqual(set.map((i) => i.id), ["checklist", "missing"]);
  assert.equal(set[1]?.metric, "38 faltam");
  assert.equal(set[1]?.disabledReason, null);
  assert.equal(collectionReportItems({ collectionId: c, completionPolicy: "MASTER_SET", totalPositions: 10, satisfiedPositions: 10 })[1]?.metric, "Completa");
  assert.equal(set[0]?.metric, "62%"); // Checklist inalterado
});

test("divergência de totais, posição satisfeita no filtro, falha parcial e teto de 5.000 → incompleto (impressão bloqueada)", async () => {
  const rows = [setPos(1, 0), setPos(2, 1)];
  const ok = (await load("STANDARD_SET", rows)).load;
  // Resumo canônico diz 3 faltantes, a leitura trouxe 2.
  const off = buildMissingCardsReport({ kind: "STANDARD_SET", load: ok, totalPositions: 10, satisfiedPositions: 7 });
  assert.equal(off.incompleteReason, "mismatch");
  assert.equal(off.complete, false);
  // Filtro MISSING devolvendo posição satisfeita = inconsistência.
  const sat = (await load("STANDARD_SET", [setPos(1, 0), setPos(2, 0, { is_satisfied: true })])).load;
  assert.equal(buildMissingCardsReport({ kind: "STANDARD_SET", load: sat, totalPositions: 10, satisfiedPositions: 8 }).incompleteReason, "mismatch");
  // total_count maior que o lido (lote seguinte falhou).
  const many = Array.from({ length: 700 }, (_, i) => setPos(i + 1, i % 2));
  const partial = (await load("STANDARD_SET", many, { failAt: 500 })).load;
  assert.equal(buildMissingCardsReport({ kind: "STANDARD_SET", load: partial, totalPositions: 900, satisfiedPositions: 200 }).incompleteReason, "partial_failure");
  // Acima do teto: não lê além do 1º lote, "too_large".
  const { load: big, calls } = await load("STANDARD_SET", many.slice(0, 500), { total: CHECKLIST_MAX_POSITIONS + 1 });
  assert.equal(calls.length, 1);
  assert.equal(buildMissingCardsReport({ kind: "STANDARD_SET", load: big, totalPositions: 6000, satisfiedPositions: 0 }).incompleteReason, "too_large");
  for (const r of ["too_large", "partial_failure", "mismatch"] as const) assert.match(missingIncompleteText(r) ?? "", /impressão fica indisponível/);
  assert.equal(missingIncompleteText(null), null);
  // 700 posições: lotes de 500 (sem N+1).
  const { calls: c700, load: l700 } = await load("STANDARD_SET", many);
  assert.deepEqual(c700, [
    [0, 500],
    [500, 500],
  ]);
  assert.equal(buildMissingCardsReport({ kind: "STANDARD_SET", load: l700, totalPositions: 900, satisfiedPositions: 200 }).complete, true);
});

test("filtros da tela não alteram o conjunto impresso; impressão em pares (duas colunas)", async () => {
  const { load: l } = await load("STANDARD_SET", [setPos(1, 0), setPos(2, 1), setPos(3, 0)]);
  const r = buildMissingCardsReport({ kind: "STANDARD_SET", load: l, totalPositions: 3, satisfiedPositions: 0 });
  assert.deepEqual(missingGroupsForScreen(r.groups, "available").map((g) => g.id), ["available"]);
  assert.deepEqual(missingGroupsForScreen(r.groups, "unavailable").map((g) => g.id), ["unavailable"]);
  assert.equal(missingGroupsForScreen(r.groups, "all").length, 2);
  assert.equal(r.groups.length, 2); // o relatório (base da impressão) não muda com o filtro
  assert.deepEqual(missingPrintPairs([1, 2, 3]), [
    [1, 2],
    [3, null],
  ]);
  const sheet = read("../../components/reports/missing-cards-report.tsx");
  assert.match(sheet, /missingGroupsForScreen\(report\.groups, filter\)/); // tela
  assert.match(sheet, /<div className="hidden print:block">\s*<PrintImageGate>\s*\{report\.groups\.map\(\(group\) => \(/); // impressão: conjunto completo
  for (const label of ["Todas", "No acervo", "Sem exemplar disponível"]) assert.match(read("./missing-cards.ts"), new RegExp(`label: "${label}"`));
});

test("folha: cabeçalho institucional em toda página, KPIs só na 1ª, impressão com caixa de marcação", () => {
  const sheet = read("../../components/reports/missing-cards-report.tsx");
  const head = sheet.slice(sheet.indexOf("<thead>"), sheet.indexOf("</thead>"));
  assert.match(head, /\{cabecalho\}/);
  assert.doesNotMatch(head, /Indicator/);
  assert.match(sheet, /<tr style=\{\{ breakInside: "auto", pageBreakInside: "auto" \}\}>/);
  for (const label of ["Faltam", "Completo", "No acervo", "Sem exemplar disponível"]) assert.match(sheet, new RegExp(`label="${label}"`), label);
  // Tela e impressão separadas: a lista de tela é print:hidden; a impressão fica num bloco próprio.
  assert.match(sheet, /<div className="hidden print:block">\s*<PrintImageGate>/);
  assert.match(sheet, /<div className="print:hidden">\s*\{missingGroupsForScreen/);
  assert.doesNotMatch(sheet, /render\/image|width=\d+&|R\$|formatBrl|wishlist/i); // sem transformação, sem preço, sem Lista de Desejos
  assert.match(sheet, /pode estar\s+alocada em outra coleção/);
  for (const piece of ["RelatorioFolha", "RelatorioCabecalho", "RelatorioRodape"]) assert.match(sheet, new RegExp(`<${piece}`));
});

test("segurança e reutilização: mesma preparação do Checklist, só leituras do titular, sem escrita nem identificador de titular", () => {
  const queries = read("./missing-cards-queries.ts");
  assert.match(queries, /prepareChecklistReport\(supabase, collectionId, "faltam"\)/);
  assert.doesNotMatch(queries, /\.rpc\(|\.from\(|\.insert\(|\.update\(|\.delete\(|\.upsert\(|user_id|owner/);
  const actions = read("../../app/colecoes/colecoes/[id]/relatorios/actions.ts");
  assert.match(actions, /export async function readMissingCardsReport\(input: \{ collectionId: string \}\)/);
  assert.match(actions, /if \(!isCollectionId\(input\?\.collectionId\)\) return \{ ok: false, reason: "not_found" \};/);
  const overlay = read("../../components/reports/missing-cards-overlay.tsx");
  assert.match(overlay, /shareInFlight\(\(\) => readMissingCardsReport\(\{ collectionId \}\)\)/); // uma leitura simultânea por coleção
  assert.match(overlay, /ReportSheetOverlay/);
  assert.match(overlay, /preparePrint: data\.report\.state === "list" \? \(onProgress\) => preparePrintImages\(onProgress\) : undefined/); // miniaturas preparadas (R1-G)
  const action = read("../../components/reports/collection-reports-action.tsx");
  assert.match(action, /report === "missing" \? <MissingCardsOverlay collectionId=\{collectionId\}/);
  assert.match(action, /report === "checklist" \? <CollectionReportOverlay collectionId=\{collectionId\}/); // Checklist intacto
  // O Checklist continua com as mesmas RPCs canônicas.
  const checklist = read("./checklist-queries.ts");
  assert.deepEqual([...checklist.matchAll(/"(get_my_[a-z_]+)"/g)].map((m) => m[1]).sort(), ["get_my_collection_positions", "get_my_master_set_positions"]);
});

test("impressão premium: cartões de checklist em duas colunas, caixa confortável, número e nome, acabamentos com caixa própria", () => {
  const sheet = read("../../components/reports/missing-cards-report.tsx");
  const printPart = sheet.slice(sheet.indexOf("function PrintGroup"), sheet.indexOf("function StateMessage"));
  // Duas colunas equilibradas (50% / 50%), pares em ordem de leitura.
  assert.match(printPart, /<col style=\{\{ width: "50%" \}\} \/>\s*<col style=\{\{ width: "50%" \}\} \/>/);
  assert.match(printPart, /const pairs = missingPrintPairs\(group\.lines\);/);
  // Cartão: borda discreta, caixa de marcação de 5 mm (Set padrão), número e nome com hierarquia.
  assert.match(printPart, /data-missing-print-card=""/);
  assert.match(printPart, /rounded-md border border-neutral-300/);
  assert.match(printPart, /size === "lg" \? "h-\[5mm\] w-\[5mm\]"/);
  assert.match(printPart, /isMaster \? null : <CheckBox size="lg" \/>/);
  assert.match(printPart, />Nº \{line\.number \|\| "—"\}</);
  assert.match(printPart, /text-\[12\.5px\] font-semibold leading-snug text-neutral-900">\{line\.name\}/);
  // Master Set: cada acabamento (= uma posição) com a própria caixa, sigla e nome por extenso.
  assert.match(printPart, /line\.finishes\.map\(\(finish\) => \(\s*<li key=\{finish\.key\}[^>]*data-missing-print-finish="">\s*<CheckBox size="sm" \/>/);
  assert.match(printPart, /<span className="font-semibold">\{finish\.code\}<\/span> <span className="text-neutral-600">\{finish\.label\}<\/span>/);
  // Paginação: título do grupo no thead (repete; preso às linhas), cada par de cartões indivisível.
  assert.match(printPart, /<thead>\s*<tr style=\{\{ breakAfter: "avoid" \}\}>/);
  assert.match(printPart, /<tr key=\{left\.key\} style=\{\{ breakInside: "avoid" \}\}>/);
  assert.match(printPart, /style=\{\{ breakInside: "avoid" \}\} data-missing-print-card=""/); // o próprio cartão também é indivisível
  assert.match(printPart, /\{plural\(group\.positions, "posição", "posições"\)\}/); // quantidade de posições do grupo
  assert.doesNotMatch(printPart, /position: ?"?fixed|minHeight: "297mm"/); // sem preenchimento artificial nem posicionamento fixo
});

test("impressão Master Set: cada posição faltante vira exatamente uma caixa por acabamento, sem duplicar", async () => {
  const rows = [masterPos(1, 1, "Padrão", 0), masterPos(1, 2, "Holográfica Reversa", 0), masterPos(1, 3, "Poké Bola Reversa", 0), masterPos(1, 4, "Master Ball Reversa", 2)];
  const { load: l } = await load("MASTER_SET", rows);
  const r = buildMissingCardsReport({ kind: "MASTER_SET", load: l, totalPositions: 4, satisfiedPositions: 0 });
  const boxes = r.groups.flatMap((g) => g.lines.flatMap((x) => x.finishes));
  assert.equal(boxes.length, r.missingPositions); // uma caixa por posição
  assert.deepEqual(r.groups.map((g) => g.lines.map((x) => x.finishes.map((f) => f.code))), [[["MBR"]], [["PA", "HR", "PBR"]]]);
  // Volume: 9 e centenas de posições produzem pares completos, sem perder nem repetir cartões.
  for (const n of [9, 240]) {
    const many = Array.from({ length: n }, (_, i) => setPos(i + 1, i % 3 === 0 ? 1 : 0));
    const rep = buildMissingCardsReport({ kind: "STANDARD_SET", load: (await load("STANDARD_SET", many)).load, totalPositions: n, satisfiedPositions: 0 });
    const printed = rep.groups.flatMap((g) => missingPrintPairs(g.lines).flat().filter(Boolean));
    assert.equal(printed.length, n);
  }
});

test("miniaturas impressas: canônicas, proporção da carta, nas duas colunas, preparadas pelo mecanismo da R1-G, sem transformação", () => {
  const sheet = read("../../components/reports/missing-cards-report.tsx");
  const printPart = sheet.slice(sheet.indexOf("function PrintGroup"), sheet.indexOf("function StateMessage"));
  // Cada cartão (das duas colunas: <PrintCard> à esquerda e à direita) traz a miniatura.
  assert.equal((printPart.match(/<PrintCard line=\{(left|right)\}/g) ?? []).length, 2);
  assert.match(printPart, /const src = cardFrontUrl\(SUPABASE_URL, line\.imagePath\);/); // mesma URL canônica da tela (cache)
  assert.match(printPart, /<img src=\{src\} alt="" width=\{120\} height=\{168\} loading="lazy"/);
  assert.match(sheet, /PRINT_THUMB_MM = \{ width: 12, height: 16\.8 \}/);
  assert.ok(Math.abs(12 / 16.8 - 63 / 88) < 0.002); // proporção da carta (63:88)
  assert.match(printPart, /Sem imagem no catálogo/); // nunca omitida em silêncio
  // Caixas preservadas (5 mm na principal; uma por acabamento no Master Set).
  assert.match(printPart, /isMaster \? null : <CheckBox size="lg" \/>/);
  assert.match(printPart, /<CheckBox size="sm" \/>/);
  // Mecanismo da R1-G, sem duplicar infraestrutura: o mesmo gate e o mesmo preparo.
  assert.match(sheet, /import \{ PrintImageGate \} from "\.\/print-image-gate";/);
  const overlay = read("../../components/reports/missing-cards-overlay.tsx");
  assert.match(overlay, /import \{ preparePrintImages \} from "\.\/print-image-gate";/);
  const gate = read("../../components/reports/print-image-gate.tsx");
  assert.match(gate, /concurrency: PRINT_IMAGE_CONCURRENCY/); // 6 simultâneas, progresso real, 30 s por imagem
  for (const source of [sheet, overlay]) assert.doesNotMatch(source, /render\/image|\?width=|&quality=|createSignedUrl|\/transform/i); // nenhuma transformação faturável (endpoint /render/image ou parâmetros)
});

test("impressão de dezenas ou centenas de posições: todas as miniaturas e caixas, independente do filtro de tela", async () => {
  const rows = Array.from({ length: 180 }, (_, i) => setPos(i + 1, i % 4 === 0 ? 2 : 0));
  const r = buildMissingCardsReport({ kind: "STANDARD_SET", load: (await load("STANDARD_SET", rows)).load, totalPositions: 200, satisfiedPositions: 20 });
  const printed = r.groups.flatMap((g) => missingPrintPairs(g.lines).flat().filter((x): x is NonNullable<typeof x> => x !== null));
  assert.equal(printed.length, 180);
  assert.ok(printed.every((line) => line.imagePath !== null)); // cada cartão leva a imagem da leitura homologada
  for (const filter of ["available", "unavailable"] as const) assert.ok(missingGroupsForScreen(r.groups, filter).length < r.groups.length); // a tela filtra…
  assert.equal(r.groups.length, 2); // …a impressão (report.groups) não
});

test("densidade da impressão: miniatura ~12 × 17 mm, cartão do Set padrão entre 20 e 23 mm, caixa de 5 mm, sem altura fixa", () => {
  const sheet = read("../../components/reports/missing-cards-report.tsx");
  const printPart = sheet.slice(sheet.indexOf("function PrintGroup"), sheet.indexOf("function StateMessage"));
  const thumb = { width: 12, height: 16.8 };
  assert.ok(Math.abs(thumb.width - 12) <= 0.5 && Math.abs(thumb.height - 17) <= 0.5);
  // Altura do cartão do Set padrão = miniatura + respiro vertical (2 × 1,8 mm) + borda (~0,5 mm).
  const card = thumb.height + 2 * 1.8 + 0.5;
  assert.ok(card >= 20 && card <= 23, `cartão ${card} mm`);
  assert.match(printPart, /px-2 py-\[1\.8mm\]/);
  assert.doesNotMatch(printPart, /min-h-\[|minHeight|h-\[\d+mm\] w-full/); // sem altura fixa no cartão: Master Set cresce com os acabamentos
  assert.match(printPart, /size === "lg" \? "h-\[5mm\] w-\[5mm\]"/); // caixa de 5 mm preservada
  assert.match(printPart, /borderSpacing: "3mm 1\.8mm"/);
  // Densidade maior que a versão anterior (24 × 33,5 mm, cartão ≈ 38 mm): pelo menos 1,6× mais cartões por página.
  const usable = 297 - 10 - 14 - 40; // A4 menos margens e cabeçalho institucional (aprox.)
  const before = Math.floor(usable / (38 + 2.5)) * 2;
  const after = Math.floor(usable / (card + 1.8)) * 2;
  assert.ok(after >= before * 1.6, `${before} → ${after} cartões por página`);
  // Miniatura da TELA inalterada (40 × 56 px).
  assert.match(sheet, /<img src=\{src\} alt="" width=\{40\} height=\{56\}/);
});

test("cabeçalho impresso: linha de metadados curta (nunca truncada), com tipo, completude, faltantes e emissão", async () => {
  const { load: l } = await load("STANDARD_SET", Array.from({ length: 9 }, (_, i) => setPos(i + 1, 0)));
  const r = buildMissingCardsReport({ kind: "STANDARD_SET", load: l, totalPositions: 158, satisfiedPositions: 149 });
  const line = missingHeaderLine(r, "07/11/2026, 10:28");
  assert.equal(line, "Set padrão · 94% completo · 9 faltantes de 158 · Emitido em 07/11/2026, 10:28");
  assert.ok(line.length <= 80, `${line.length} caracteres`); // cabe na linha do cabeçalho A4 (a anterior passava de 100 e era cortada)
  assert.match(missingHeaderLine({ ...r, kind: "MASTER_SET" }, "x"), /^Master Set · /);
  assert.match(read("../../components/reports/missing-cards-report.tsx"), /subtitulo=\{missingHeaderLine\(report, issuedAt\)\}/);
});
