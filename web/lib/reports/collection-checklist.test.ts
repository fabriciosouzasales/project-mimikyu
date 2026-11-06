/**
 * V1-14 R1-A — Checklist de completude: regras puras + verificações estáticas do fluxo.
 */
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { CHECKLIST_LINHAS_POR_FOLHA_A4, checklistColunasA4, checklistPaginasA4 } from "../catalogo/relatorio-checklist.ts";
import {
  CHECKLIST_FINISH_CODES,
  checklistFinishCode,
  checklistFinishLegend,
  checklistFilterShortLabel,
  checklistSummaryLine,
  CHECKLIST_BATCH,
  checklistFilterLabel,
  checklistHref,
  checklistKindOf,
  checklistSummary,
  collectionReportItems,
  loadChecklist,
  parseChecklistFilter,
  parseChecklistRows,
} from "./collection-checklist.ts";

const id = (n: number) => `00000000-0000-4000-8000-${n.toString(16).padStart(12, "0")}`;
const T1 = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const T2 = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";

function setRow(n: number, total: number, owned = false, extra: Record<string, unknown> = {}) {
  return {
    card_id: id(n),
    collector_number: String(n).padStart(3, "0"),
    card_name: `Carta ${n}`,
    is_satisfied: owned,
    copies_in_collection: owned ? 1 : 0,
    copies_available: 0,
    total_count: total,
    ...extra,
  };
}

test("objetivo → tipo de checklist (Pokédex e livre ficam fora na R1-A)", () => {
  assert.equal(checklistKindOf("STANDARD_SET"), "STANDARD_SET");
  assert.equal(checklistKindOf("MASTER_SET"), "MASTER_SET");
  assert.equal(checklistKindOf("POKEDEX"), null);
  assert.equal(checklistKindOf("NONE"), null);
  assert.equal(checklistKindOf(undefined), null);
});

test("Set padrão: uma linha por carta; posse vem do banco (is_satisfied)", () => {
  const parsed = parseChecklistRows("STANDARD_SET", [
    setRow(1, 3, true, { copies_in_collection: 2 }),
    setRow(2, 3, false, { copies_available: 1 }),
    setRow(3, 3, false),
    { card_id: "não-é-uuid", total_count: 3 },
  ]);
  assert.ok(parsed);
  assert.equal(parsed.total, 3);
  assert.equal(parsed.rows.length, 3);
  assert.deepEqual(
    parsed.rows.map((row) => [row.owned, row.copies, row.inAcervo, row.finish]),
    [
      [true, 2, false, null],
      [false, 0, true, null],
      [false, 0, false, null],
    ],
  );
  assert.equal(parsed.rows[0]?.key, id(1));
});

test("Master Set: carta + acabamento; secreta = qualquer acabamento; chaves distintas por acabamento", () => {
  const parsed = parseChecklistRows("MASTER_SET", [
    setRow(1, 3, true, { variant_type_id: T1, variant_type_name: "Normal" }),
    setRow(1, 3, false, { variant_type_id: T2, variant_type_name: "Holográfica Reversa" }),
    setRow(99, 3, false, { variant_type_id: null, is_secret: true }),
  ]);
  assert.ok(parsed);
  assert.deepEqual(
    parsed.rows.map((row) => row.finish),
    ["Normal", "Holográfica Reversa", "Qualquer acabamento"],
  );
  assert.equal(new Set(parsed.rows.map((row) => row.key)).size, 3);
  assert.equal(parsed.rows[0]?.owned, true);
  assert.equal(parsed.rows[1]?.owned, false);
});

test("resposta fora do contrato → null (vira erro, nunca lista vazia)", () => {
  assert.equal(parseChecklistRows("STANDARD_SET", null), null);
  assert.equal(parseChecklistRows("STANDARD_SET", { rows: [] }), null);
});

function pager(total: number, fail: Set<number> = new Set()) {
  const calls: [number, number][] = [];
  const fetch = async (offset: number, limit: number) => {
    calls.push([offset, limit]);
    if (fail.has(offset)) return null;
    const rows = [];
    for (let i = offset; i < Math.min(total, offset + limit); i += 1) rows.push(setRow(i + 1, total, i % 2 === 0));
    return rows;
  };
  return { fetch, calls };
}

test("conjunto inteiro em lotes de 500, em ordem; completo só quando lido tudo", async () => {
  const { fetch, calls } = pager(1234);
  const load = await loadChecklist("STANDARD_SET", fetch);
  assert.equal(load.status, "ready");
  if (load.status !== "ready") return;
  assert.equal(load.rows.length, 1234);
  assert.equal(load.total, 1234);
  assert.equal(load.complete, true);
  assert.equal(load.incompleteReason, null);
  assert.deepEqual(calls, [
    [0, CHECKLIST_BATCH],
    [500, CHECKLIST_BATCH],
    [1000, CHECKLIST_BATCH],
  ]);
  assert.equal(load.rows[0]?.number, "001");
  assert.equal(load.rows[1233]?.number, "1234");
});

test("filtro vazio é completo (zero de zero)", async () => {
  const load = await loadChecklist("STANDARD_SET", async () => []);
  assert.deepEqual(load, { status: "ready", rows: [], total: 0, complete: true, incompleteReason: null });
});

test("falha no primeiro lote = erro; falha depois = parcial, nunca completo", async () => {
  const first = await loadChecklist("STANDARD_SET", pager(800, new Set([0])).fetch);
  assert.equal(first.status, "error");
  const later = await loadChecklist("STANDARD_SET", pager(800, new Set([500])).fetch);
  assert.equal(later.status, "ready");
  if (later.status !== "ready") return;
  assert.equal(later.complete, false);
  assert.equal(later.incompleteReason, "partial_failure");
  assert.equal(later.rows.length, 500);
});

test("acima do teto: não prepara e marca too_large (sem truncar em silêncio)", async () => {
  const { fetch, calls } = pager(1200);
  const load = await loadChecklist("STANDARD_SET", fetch, 1000);
  assert.equal(load.status, "ready");
  if (load.status !== "ready") return;
  assert.equal(load.complete, false);
  assert.equal(load.incompleteReason, "too_large");
  assert.equal(calls.length, 1);
});

test("total divergente ou linha repetida entre lotes → incompleto", async () => {
  // O banco anuncia 600, mas o segundo lote volta vazio (dado mudou entre as leituras).
  let call = 0;
  const shrinking = async () => (call++ === 0 ? Array.from({ length: 500 }, (_, i) => setRow(i + 1, 600)) : []);
  const a = await loadChecklist("STANDARD_SET", shrinking);
  assert.equal(a.status === "ready" && a.complete, false);
  // Mesma posição em dois lotes (deslocamento por concorrência).
  let turn = 0;
  const dup = async () => (turn++ === 0 ? Array.from({ length: 500 }, (_, i) => setRow(i + 1, 501)) : [setRow(500, 501)]);
  const b = await loadChecklist("STANDARD_SET", dup);
  assert.equal(b.status === "ready" && b.complete, false);
});

test("resumo canônico: completude ≠ valor; nunca arredonda 99,6% para 100%", () => {
  assert.deepEqual(checklistSummary(250, 249), { total: 250, owned: 249, missing: 1, percent: 99, percentText: "99%" });
  assert.equal(checklistSummary(1025, 1).percentText, "<1%");
  assert.equal(checklistSummary(10, 10).percent, 100);
  assert.equal(checklistSummary(0, 0).percent, 0);
  assert.equal(checklistSummary(5, 9).owned, 5);
});

test("padrão único do sistema: mesma regra de colunas do Catálogo (2–4, 46 por coluna)", () => {
  assert.equal(checklistColunasA4(4), 2);
  assert.equal(checklistColunasA4(92), 2);
  assert.equal(checklistColunasA4(93), 3);
  assert.equal(checklistColunasA4(158), 4); // 158 → 4 × 40: uma folha A4, como na Central
  assert.equal(checklistColunasA4(184), 4);
  assert.equal(checklistColunasA4(203), 4); // > 4 × 46: continua em mais folhas (aceito no padrão)
});

test("siglas de acabamento: canônicas, únicas, sem invenção; legenda só do que aparece", () => {
  assert.deepEqual(checklistFinishCode("Padrão"), { code: "PA", label: "Padrão" });
  assert.equal(checklistFinishCode("Holográfica")?.code, "HO");
  assert.equal(checklistFinishCode("Holográfica Reversa")?.code, "HR");
  assert.equal(checklistFinishCode("  holografica   reversa ")?.code, "HR"); // acento/espaço/caixa
  assert.equal(checklistFinishCode("Qualquer acabamento")?.code, "QA");
  assert.equal(checklistFinishCode("Poké Bola Reversa")?.code, "PBR");
  // Sem correspondência inequívoca → nome por extenso (sem sigla inventada).
  for (const name of ["Holográfica Cracked Ice", "Poke Ball Pattern", "Master Ball Pattern", "Promocional Estampada", "Equipe Rocket Reversa", "Exclusiva Pokemon Center", "Acabamento"]) {
    assert.equal(checklistFinishCode(name), null, name);
  }
  assert.equal(checklistFinishCode(null), null);
  const codes = CHECKLIST_FINISH_CODES.map((entry) => entry.code);
  assert.equal(new Set(codes).size, codes.length);
  const labels = CHECKLIST_FINISH_CODES.map((entry) => entry.label.toLowerCase());
  assert.equal(new Set(labels).size, labels.length);
  assert.deepEqual(
    checklistFinishLegend(["Holográfica Reversa", "Padrão", "Padrão", "Holográfica Cracked Ice", null]).map((entry) => entry.code),
    ["PA", "HR"],
  );
});

test("resumo e filtro curtos da folha, com números reais", () => {
  assert.equal(checklistSummaryLine(158, 149), "94% completo · 149 de 158 posições · 9 faltantes");
  assert.equal(checklistSummaryLine(1, 0), "0% completo · 0 de 1 posição · 1 faltante");
  assert.equal(checklistSummaryLine(250, 249), "99% completo · 249 de 250 posições · 1 faltante");
  assert.equal(checklistFilterShortLabel("todas"), "Todas");
  assert.equal(checklistFilterShortLabel("tenho"), "Possuídas");
  assert.equal(checklistFilterShortLabel("faltam"), "Faltantes");
});

test("URL e filtro do relatório", () => {
  const c = "cccccccc-cccc-4ccc-8ccc-cccccccccccc";
  assert.equal(checklistHref(c), `/colecoes/colecoes/${c}/relatorios/checklist`);
  assert.equal(checklistHref(c, "faltam"), `/colecoes/colecoes/${c}/relatorios/checklist?situacao=faltam`);
  assert.equal(parseChecklistFilter("tenho"), "tenho");
  assert.equal(parseChecklistFilter(["faltam"]), "faltam");
  assert.equal(parseChecklistFilter("x"), "todas");
  assert.equal(checklistFilterLabel("faltam"), "Somente faltantes");
});

test("menu da coleção: checklist real em Set/Master; motivo explícito nos demais", () => {
  const c = "cccccccc-cccc-4ccc-8ccc-cccccccccccc";
  const [set] = collectionReportItems({ collectionId: c, completionPolicy: "MASTER_SET", totalPositions: 100, satisfiedPositions: 62 });
  assert.equal(set?.href, checklistHref(c));
  assert.equal(set?.metric, "62%");
  assert.equal(set?.disabledReason, null);
  const [pokedex] = collectionReportItems({ collectionId: c, completionPolicy: "POKEDEX", totalPositions: 1025, satisfiedPositions: 3 });
  assert.equal(pokedex?.href, null);
  assert.ok(pokedex?.disabledReason);
});

// ---- verificações estáticas ----
const read = (path: string) => readFileSync(new URL(path, import.meta.url), "utf8");

test("leitura só pelas RPCs canônicas do titular, sem escrita nem RPC administrativa", () => {
  const queries = read("./checklist-queries.ts");
  const rpcs = [...queries.matchAll(/"(get_my_[a-z_]+)"/g)].map((m) => m[1]).sort();
  assert.deepEqual(rpcs, ["get_my_collection_positions", "get_my_master_set_positions"]);
  assert.doesNotMatch(queries, /admin_|\.insert\(|\.update\(|\.delete\(|\.upsert\(/);
});

test("preparação única (sobreposição e rota): titular via get_my_collection, 404 para alheia, Pokédex fora", () => {
  const queries = read("./checklist-queries.ts");
  assert.match(queries, /getMyCollection\(supabase, collectionId\)/);
  assert.match(queries, /if \(collection === undefined\) return \{ status: "not_found" \};/);
  assert.match(queries, /checklistKindOf\(collection\.completionPolicy\)/);
  const page = read("../../app/colecoes/colecoes/[id]/relatorios/checklist/page.tsx");
  assert.match(page, /prepareChecklistReport\(supabase, collectionId, filter\)/);
  assert.match(page, /if \(result\.status === "not_found"\) notFound\(\);/);
  const action = read("../../app/colecoes/colecoes/[id]/relatorios/actions.ts");
  assert.match(action, /^"use server";/);
  assert.match(action, /if \(!user\) return \{ ok: false, reason: "not_found" \};/);
  assert.match(action, /prepareChecklistReport\(/);
  assert.doesNotMatch(action, /\.rpc\(|admin_/);
});

test("paginação explícita: folhas cheias, cada uma completa em si, sem coluna continuando na seguinte", () => {
  // Reproduz o preenchimento da tabela: folha → coluna → linha, e devolve a ordem de leitura.
  const reading = (total: number) => {
    const { colunas, paginas } = checklistPaginasA4(total);
    const out: number[] = [];
    for (const p of paginas) {
      assert.ok(p.linhas <= CHECKLIST_LINHAS_POR_FOLHA_A4);
      const seen: number[] = [];
      for (let c = 0; c < colunas; c += 1) for (let l = 0; l < p.linhas; l += 1) {
        const local = c * p.linhas + l;
        if (local < p.tamanho) seen.push(p.inicio + local);
      }
      // A folha contém exatamente o intervalo contíguo [inicio, inicio + tamanho).
      assert.deepEqual(seen, Array.from({ length: p.tamanho }, (_, i) => p.inicio + i));
      out.push(...seen);
    }
    return { colunas, paginas, out };
  };
  const set158 = reading(158);
  assert.equal(set158.paginas.length, 1); // Set padrão de 158: 4 × 40, uma folha
  assert.equal(set158.paginas[0]?.linhas, 40);
  const set194 = reading(194); // ME5 (194 posições): uma folha só, 49 linhas por coluna
  assert.equal(set194.paginas.length, 1);
  assert.equal(set194.paginas[0]?.linhas, 49);
  const master203 = reading(203);
  assert.equal(master203.colunas, 4);
  // Folha 1 cheia (4 × 50), nunca "meia folha"; só a última fica parcial.
  assert.equal(CHECKLIST_LINHAS_POR_FOLHA_A4, 50);
  assert.deepEqual(master203.paginas.map((p) => p.tamanho), [200, 3]);
  assert.deepEqual(master203.paginas.map((p) => p.linhas), [50, 1]);
  for (const total of [201, 203, 500, 1000]) {
    const { paginas, colunas } = reading(total);
    for (const p of paginas.slice(0, -1)) assert.equal(p.tamanho, colunas * CHECKLIST_LINHAS_POR_FOLHA_A4, `folha cheia ${total}`);
  }
  for (const total of [1, 4, 92, 93, 168, 169, 184, 203, 500, 1000]) {
    const { out } = reading(total);
    assert.deepEqual(out, Array.from({ length: total }, (_, i) => i), `ordem/contagem ${total}`);
  }
  assert.deepEqual(checklistPaginasA4(0).paginas, []);
});

test("folha = padrão do Catálogo: mesmos componentes, tela igual à impressão, conjunto completo ou aviso", () => {
  const view = read("../../components/reports/collection-checklist-report.tsx");
  for (const piece of ["RelatorioFolha", "RelatorioCabecalho", "RelatorioRodape", "RelatorioChecklistFolhas", "ChecklistLinhaBase"]) {
    assert.match(view, new RegExp(piece));
  }
  assert.match(view, /const ready = load\.status === "ready" && load\.complete;/);
  assert.match(view, /\{ready && load\.status === "ready" \? \(\s*<ChecklistSheet/);
  assert.match(view, /não foi impresso porque não está completo/);
  // A folha não é mais "só impressão": é a própria visualização (sem `hidden print:block`).
  assert.doesNotMatch(view, /hidden print:block|data-print-page|CHECKLIST_PRINT_MM|ScreenList/);
  assert.match(view, /state=\{row\.owned \? "owned" : row\.inAcervo \? "acervo" : "missing"\}/);
  assert.match(view, /checklistSummaryLine\(collection\.totalPositions, collection\.satisfiedPositions\)/);
  // O Catálogo usa a mesma tabela compartilhada (uma implementação só).
  const catalogo = read("../../app/catalogo/relatorios/checklist/page.tsx");
  assert.match(catalogo, /<RelatorioChecklistFolhas/);
  assert.match(catalogo, /<ChecklistLinhaBase/);
  assert.match(catalogo, /legenda=\{/);
  const tabela = read("../../components/catalogo/relatorio-checklist-tabela.tsx");
  // Uma folha A4 por página (tela e impressão), cada uma com cabeçalho, legenda e rodapé paginado.
  assert.match(tabela, /paginas\.map\(\(pagina, paginaIndex\)/);
  assert.match(tabela, /breakAfter: ultima \? "auto" : "page"/);
  assert.match(tabela, /\{cabecalho\}[\s\S]*\{legenda \?[\s\S]*Página \{paginaIndex \+ 1\} de \{paginas\.length\}/);
  assert.match(tabela, /Gerado por MMKYU Collector em \{data\}/);
  assert.doesNotMatch(tabela, /<tfoot>|<thead>|breakBefore|RelatorioRodape/); // sem rodapé fixo no paginado
  assert.match(read("../../app/globals.css"), /\.relatorio-folha\[data-checklist-folha\] \{\s*padding-bottom: 0;/);
  assert.match(tabela, /checklistPaginasA4\(itens\.length\)/);
  assert.match(view, /legenda=\{legenda\}/);
  assert.doesNotMatch(catalogo, /const MAX_COLUNAS_A4|<table\s+className/);
  const button = read("../../components/reports/report-print-button.tsx");
  assert.match(button, /if \(!ready\) return;/);
  assert.match(button, /window\.print\(\)/);
  assert.match(read("../../app/globals.css"), /\[data-report-overlay\],\s*\[data-report-overlay\] > \* \{\s*display: block !important;/);
  assert.doesNotMatch(read("../../app/globals.css"), /data-checklist-sheet/);
});

test("menu de Relatórios: acessível, compacto, sem dependência nova, movimento e transparência reduzidos", () => {
  const menu = read("../../components/reports/report-menu.tsx");
  assert.match(menu, /role="menu"/);
  assert.match(menu, /role="menuitem"/);
  assert.match(menu, /aria-disabled=\{disabled \|\| undefined\}/);
  assert.match(menu, /event\.key === "Escape"/);
  assert.doesNotMatch(menu, /next\/link|href=/); // escolhe; não navega
  const external = (source: string) =>
    [...source.matchAll(/from "([^"]+)"/g)]
      .map((m) => m[1])
      .filter((m): m is string => typeof m === "string" && !m.startsWith("@/") && !m.startsWith("./"))
      .sort();
  assert.deepEqual(external(menu), ["lucide-react", "react", "react-dom"]);
  const action = read("../../components/reports/collection-reports-action.tsx");
  assert.match(action, /aria-haspopup="menu"/);
  assert.match(action, /aria-expanded=\{menuOpen\}/);
  assert.match(action, /<CollectionReportOverlay/);
  for (const path of ["../../components/reports/report-menu.module.css", "../../components/ui/action-capsule.module.css"]) {
    const css = read(path);
    assert.match(css, /prefers-reduced-motion: reduce/);
    assert.match(css, /prefers-reduced-transparency: reduce/);
    assert.match(css, /max-width: 640px/);
  }
});

test("cápsula: uma superfície, um indicador; gatilhos de origem preservados", () => {
  const capsule = read("../../components/ui/action-capsule.tsx");
  assert.match(capsule, /role="group"/);
  assert.match(capsule, /className=\{styles\.indicator\}/);
  assert.match(capsule, /attributeFilter: \["aria-expanded"\]/);
  assert.match(capsule, /translateX\(/);
  const imports = [...capsule.matchAll(/from "([^"]+)"/g)].map((m) => m[1]);
  assert.deepEqual(imports.sort(), ["./action-capsule.module.css", "react"]);
  // Compartilhar e Ajustes só ganham apresentação; painel e permissões continuam os mesmos.
  const share = read("../../components/colecoes/sharing/share-panel.tsx");
  assert.match(share, /className=\{className \?\? manageStyles\.settingsButton\}/);
  assert.match(share, /<SharePanel collectionId=\{collectionId\}/);
  const manage = read("../../components/colecoes/colecoes/collection-manage.tsx");
  assert.match(manage, /className=\{className \?\? styles\.settingsButton\}/);
});

test("coleção: Relatórios, Compartilhar e Ajustes na mesma cápsula (Relatórios também na arquivada)", () => {
  const view = read("../../components/colecoes/colecoes/collection-view.tsx");
  assert.match(view, /<ActionCapsule label="Ações da coleção">\s*\{reportsAction\}\s*<CollectionShareButton/);
  assert.match(view, /<ActionCapsule label="Ações da coleção">\{reportsAction\}<\/ActionCapsule>\s*<ReactivateCollectionButton/);
  assert.doesNotMatch(view, /ReportLens/);
  for (const path of ["../../components/colecoes/colecoes/free-collection-view.tsx", "../../components/colecoes/colecoes/pokedex-collection-view.tsx"]) {
    assert.match(read(path), /<ActionCapsule label="Ações da coleção">\s*<CollectionShareButton/);
  }
});

test("relatório em sobreposição: casca do Fichário, sem navegar; impressão só da folha", () => {
  const overlay = read("../../components/reports/collection-report-overlay.tsx");
  assert.match(overlay, /<BinderOverlayShell labelledBy=\{titleId\} onClose=\{onClose\}>/);
  assert.match(overlay, /readChecklistReport\(\{ collectionId, filter: target \}\)/);
  assert.match(overlay, /data-report-overlay=""/);
  // Um só cabeçalho por mídia: o funcional na tela, o institucional na folha.
  assert.match(overlay, /className=\{`\$\{styles\.header\} print:hidden`\}/);
  assert.match(read("../../components/reports/report-overlay.module.css"), /@media print \{\s*\.header \{\s*display: none !important;/);
  assert.match(overlay, /event\.key !== "Escape"/);
  assert.match(overlay, /requestFullscreen/);
  assert.match(overlay, /<ReportPrintButton/);
  assert.match(overlay, /aria-label="Fechar relatório"/);
  assert.doesNotMatch(overlay, /router\.push|next\/navigation|next\/link/);
  const globals = read("../../app/globals.css");
  assert.match(globals, /body:has\(\[data-report-overlay\]\) > :not\(\[data-binder-overlay\]\)/);
});
