// Project Mimikyu — supabase/functions/import-card-variants/services/lineage-correlation.test.ts
// Bateria do FALLBACK DE CORRELAÇÃO POR LINEAGE
// (VARIANT-CARD-CORRELATION-FALLBACK-01, 2026-09-18).
//
// 100% offline: nenhuma chamada de rede, nenhum acesso ao Supabase real.
// O cliente é um stub que reimplementa apenas a fatia do PostgREST que a
// função usa (eq/in/not/order/range), de forma que os FILTROS sejam
// exercidos de verdade — um stub que devolvesse sempre a mesma lista
// provaria nada sobre os guards de escopo (casos E, F, G, H).
//
// Execução canônica:
//   deno test --allow-read supabase/functions/import-card-variants/services/lineage-correlation.test.ts
//
// `--allow-read` é exigido apenas pelo Caso K, prova ESTRUTURAL sobre o
// texto de index.ts. Os demais casos não tocam o disco.
//
// Mesmo formato de size-scope.test.ts: um único `Deno.test` real, que
// falha de verdade (throw), e uma função exportada reaproveitável.
//
// ROTEIRO DE PROVAS (A-J), exatamente o exigido pelo mandato:
//   A  primary vence lineage
//   B  fallback funciona quando primary ausente
//   C  2 card_ids para 1 external_id  -> fail-closed
//   D  2 external_ids para 1 card_id  -> fail-closed
//   E  lineage de outro Card Set nao entra
//   F  lineage de outro external_set_id nao entra
//   G  job nao-terminal nao entra
//   H  source != TCGDEX nao entra
//   I  trim/uppercase canonicos
//   J  ausencia de lineage -> uncorrelated
//   M  job CORRETO, mas resulting_card_id de Card de OUTRO Card Set
//      -> fail-closed (G0). Distinto de E: ali o JOB e de outro Set; aqui
//         o job esta certo e quem esta errada e a LINHA.
// Extras (não pedidos, mas exigidos pelo contrato do mandato):
//   K  precedencia e telemetria realmente cabeadas em index.ts
//   L  paginacao explicita (nao depende do default do PostgREST)
//   N  custo: numero de consultas por Set e O(1), nunca por linha

import { listCardLineageCorrelationMap } from "./database.ts";

// ---------------------------------------------------------------------------
// Infra de assertions (idêntica em espírito à de size-scope.test.ts)
// ---------------------------------------------------------------------------

type Resultado = { caso: string; ok: boolean; detalhe?: string };

function assert(acc: Resultado[], caso: string, ok: boolean, detalhe?: string) {
  acc.push({ caso, ok, detalhe: ok ? undefined : detalhe ?? "assertion falhou" });
}

// ---------------------------------------------------------------------------
// Stub de cliente Supabase — reimplementa a fatia usada do PostgREST.
// Registra as chamadas para que a prova de paginação (Caso L) possa
// inspecionar os `range()` efetivamente emitidos.
// ---------------------------------------------------------------------------

type JobRow = {
  id: string;
  card_set_id: string;
  source: string;
  external_set_id: string;
  status: string;
};

type LineageRow = {
  id: string;
  job_id: string;
  raw_data: unknown;
  resulting_card_id: string | null;
};

type CardRow = { id: string; card_set_id: string };

type StubDataset = { jobs: JobRow[]; rows: LineageRow[]; cards?: CardRow[] };

function makeSupabaseStub(dataset: StubDataset) {
  const ranges: Array<[string, number, number]> = [];
  const tablesRead: string[] = [];

  // Universo de Cards. Quando o caso não declara `cards`, deriva-se o
  // universo "bem-comportado": todo resulting_card_id citado pertence ao
  // Card Set alvo. Assim os casos A-L continuam medindo o que mediam, e o
  // Caso M passa a poder declarar explicitamente uma Card de OUTRO Set.
  const cards: CardRow[] = dataset.cards ?? [
    ...new Set(dataset.rows.map((r) => r.resulting_card_id).filter((x): x is string => !!x)),
  ].map((id) => ({ id, card_set_id: SET_ALVO }));

  function builder(table: "catalog_import_job" | "catalog_import_row" | "card") {
    tablesRead.push(table);
    let items: any[] = table === "catalog_import_job"
      ? [...dataset.jobs]
      : table === "card"
      ? [...cards]
      : [...dataset.rows];

    const api: any = {
      select(_cols: string) {
        return api;
      },
      eq(col: string, val: unknown) {
        items = items.filter((r) => r[col] === val);
        return api;
      },
      in(col: string, vals: unknown[]) {
        items = items.filter((r) => vals.includes(r[col]));
        return api;
      },
      not(col: string, op: string, val: unknown) {
        if (op !== "is" || val !== null) throw new Error(`STUB_NOT_NAO_SUPORTADO: ${op}`);
        items = items.filter((r) => r[col] !== null && r[col] !== undefined);
        return api;
      },
      order(col: string, _opts: unknown) {
        items = [...items].sort((a, b) => String(a[col]).localeCompare(String(b[col])));
        return api;
      },
      // `range` é terminal: devolve a Promise que a função aguarda.
      range(from: number, to: number) {
        ranges.push([table, from, to]);
        return Promise.resolve({ data: items.slice(from, to + 1), error: null });
      },
      // Sem `range`, o builder é aguardável direto (caso da query de jobs).
      then(resolve: (v: unknown) => unknown, reject?: (e: unknown) => unknown) {
        return Promise.resolve({ data: items, error: null }).then(resolve, reject);
      },
    };
    return api;
  }

  return {
    client: { from: (table: any) => builder(table) },
    ranges,
    tablesRead,
  };
}

// ---------------------------------------------------------------------------
// Fixtures canônicas
// ---------------------------------------------------------------------------

const SET_ALVO = "set-alvo-uuid";
const SET_OUTRO = "set-outro-uuid";
const EXT_ALVO = "tk-xy-n";
const EXT_OUTRO = "tk-xy-p";

const CARD_1 = "card-1-uuid";
const CARD_2 = "card-2-uuid";

function job(over: Partial<JobRow> = {}): JobRow {
  return {
    id: "job-ok",
    card_set_id: SET_ALVO,
    source: "TCGDEX",
    external_set_id: EXT_ALVO,
    status: "COMPLETED",
    ...over,
  };
}

function row(id: string, jobId: string, extId: unknown, cardId: string | null): LineageRow {
  return { id, job_id: jobId, raw_data: { id: extId }, resulting_card_id: cardId };
}

/**
 * Replica EXATAMENTE a expressão de precedência de index.ts (fase
 * CORRELATING_CARDS). Mantida aqui como função pura para que os casos A, B
 * e J provem o comportamento de merge sem subir a Edge inteira; o Caso K
 * prova, por leitura do texto, que index.ts realmente usa esta forma.
 */
function correlate(
  key: string,
  primary: Map<string, string>,
  lineage: Map<string, string>,
): { cardId: string | null; source: "REFERENCE" | "LINEAGE" | null } {
  const referenceCardId = primary.get(key) ?? null;
  const lineageCardId = referenceCardId ? null : (lineage.get(key) ?? null);
  return {
    cardId: referenceCardId ?? lineageCardId,
    source: referenceCardId ? "REFERENCE" : (lineageCardId ? "LINEAGE" : null),
  };
}

// ---------------------------------------------------------------------------
// Suíte
// ---------------------------------------------------------------------------

export async function runLineageCorrelationTests(): Promise<Resultado[]> {
  const r: Resultado[] = [];

  // === A — primary vence lineage ==========================================
  {
    const primary = new Map([["TK-XY-N-1", CARD_1]]);
    const lineage = new Map([["TK-XY-N-1", CARD_2]]);
    const out = correlate("TK-XY-N-1", primary, lineage);

    assert(r, "A card_id vem da referencia primaria", out.cardId === CARD_1, `recebido ${out.cardId}`);
    assert(r, "A origem e REFERENCE", out.source === "REFERENCE", `recebido ${out.source}`);
    assert(r, "A lineage NUNCA sobrescreve referencia existente", out.cardId !== CARD_2);
  }

  // === B — fallback quando primary ausente ================================
  {
    const { client } = makeSupabaseStub({
      jobs: [job()],
      rows: [row("r1", "job-ok", "tk-xy-n-1", CARD_1)],
    });
    const lineage = await listCardLineageCorrelationMap(client, SET_ALVO, EXT_ALVO);
    const out = correlate("TK-XY-N-1", new Map(), lineage);

    assert(r, "B lineage resolve quando nao ha referencia", out.cardId === CARD_1, `recebido ${out.cardId}`);
    assert(r, "B origem e LINEAGE", out.source === "LINEAGE", `recebido ${out.source}`);
  }

  // === C — 2 card_ids para 1 external_id -> fail-closed ===================
  {
    const { client } = makeSupabaseStub({
      jobs: [job()],
      rows: [
        row("r1", "job-ok", "tk-xy-n-1", CARD_1),
        row("r2", "job-ok", "tk-xy-n-1", CARD_2),
      ],
    });
    const lineage = await listCardLineageCorrelationMap(client, SET_ALVO, EXT_ALVO);

    assert(r, "C identidade ambigua ext->card e excluida do mapa",
      !lineage.has("TK-XY-N-1"), `mapa devolveu ${lineage.get("TK-XY-N-1")}`);
    assert(r, "C NAO escolhe o primeiro registro",
      lineage.get("TK-XY-N-1") !== CARD_1 && lineage.get("TK-XY-N-1") !== CARD_2);
    assert(r, "C resultado e uncorrelated", correlate("TK-XY-N-1", new Map(), lineage).cardId === null);
  }

  // === D — 2 external_ids para 1 card_id -> fail-closed ===================
  {
    const { client } = makeSupabaseStub({
      jobs: [job()],
      rows: [
        row("r1", "job-ok", "tk-xy-n-1", CARD_1),
        row("r2", "job-ok", "tk-xy-n-2", CARD_1),
      ],
    });
    const lineage = await listCardLineageCorrelationMap(client, SET_ALVO, EXT_ALVO);

    assert(r, "D ambiguidade card->ext remove AS DUAS chaves", lineage.size === 0,
      `mapa ficou com ${lineage.size} entrada(s)`);
    assert(r, "D nenhuma das chaves sobrevive",
      !lineage.has("TK-XY-N-1") && !lineage.has("TK-XY-N-2"));
  }

  // === E — lineage de outro Card Set nao entra ============================
  {
    const { client } = makeSupabaseStub({
      jobs: [job({ id: "job-outro-set", card_set_id: SET_OUTRO })],
      rows: [row("r1", "job-outro-set", "tk-xy-n-1", CARD_1)],
    });
    const lineage = await listCardLineageCorrelationMap(client, SET_ALVO, EXT_ALVO);

    assert(r, "E job de outro card_set_id e ignorado", lineage.size === 0,
      `vazou ${lineage.size} entrada(s)`);
  }

  // === F — lineage de outro external_set_id nao entra =====================
  {
    // Dois bloqueios independentes provados de uma vez: o job tem
    // external_set_id divergente E a chave nao tem o prefixo esperado (G3).
    const { client } = makeSupabaseStub({
      jobs: [job({ id: "job-outro-ext", external_set_id: EXT_OUTRO })],
      rows: [row("r1", "job-outro-ext", "tk-xy-p-1", CARD_1)],
    });
    const lineage = await listCardLineageCorrelationMap(client, SET_ALVO, EXT_ALVO);

    assert(r, "F job de outro external_set_id e ignorado", lineage.size === 0,
      `vazou ${lineage.size} entrada(s)`);

    // G3 isolado: job correto, mas external id de outro Set no raw_data.
    const { client: c2 } = makeSupabaseStub({
      jobs: [job()],
      rows: [row("r1", "job-ok", "tk-xy-p-1", CARD_1)],
    });
    const l2 = await listCardLineageCorrelationMap(c2, SET_ALVO, EXT_ALVO);
    assert(r, "F G3 barra external_id fora do prefixo do Set esperado", l2.size === 0,
      `vazou ${l2.size} entrada(s)`);
  }

  // === G — job nao-terminal nao entra =====================================
  {
    for (const status of ["RECEIVED", "PROCESSING", "STAGED", "CONFIRMING", "FAILED", "CANCELLED"]) {
      const { client } = makeSupabaseStub({
        jobs: [job({ id: `job-${status}`, status })],
        rows: [row("r1", `job-${status}`, "tk-xy-n-1", CARD_1)],
      });
      const lineage = await listCardLineageCorrelationMap(client, SET_ALVO, EXT_ALVO);
      assert(r, `G job em ${status} e ignorado`, lineage.size === 0, `vazou ${lineage.size}`);
    }

    // Contraprova: COMPLETED_WITH_ERRORS É terminal e DEVE entrar.
    const { client } = makeSupabaseStub({
      jobs: [job({ id: "job-cwe", status: "COMPLETED_WITH_ERRORS" })],
      rows: [row("r1", "job-cwe", "tk-xy-n-1", CARD_1)],
    });
    const lineage = await listCardLineageCorrelationMap(client, SET_ALVO, EXT_ALVO);
    assert(r, "G COMPLETED_WITH_ERRORS e terminal e ENTRA", lineage.get("TK-XY-N-1") === CARD_1);
  }

  // === H — source != TCGDEX nao entra =====================================
  {
    const { client } = makeSupabaseStub({
      jobs: [job({ id: "job-pdf", source: "PDF" })],
      rows: [row("r1", "job-pdf", "tk-xy-n-1", CARD_1)],
    });
    const lineage = await listCardLineageCorrelationMap(client, SET_ALVO, EXT_ALVO);

    assert(r, "H job com source PDF e ignorado", lineage.size === 0, `vazou ${lineage.size}`);
  }

  // === I — trim/uppercase canonicos =======================================
  {
    const { client } = makeSupabaseStub({
      jobs: [job()],
      rows: [row("r1", "job-ok", "  TK-xY-n-1  ", CARD_1)],
    });
    const lineage = await listCardLineageCorrelationMap(client, SET_ALVO, EXT_ALVO);

    assert(r, "I chave normalizada para UPPER(TRIM(...))", lineage.has("TK-XY-N-1"),
      `chaves: ${[...lineage.keys()].join("|")}`);
    assert(r, "I chave crua nao permanece no mapa", !lineage.has("  TK-xY-n-1  "));
    assert(r, "I normalizacao e a mesma do lado primario (externalCardId.toUpperCase())",
      correlate(`${EXT_ALVO}-1`.toUpperCase(), new Map(), lineage).cardId === CARD_1);
  }

  // === J — ausencia de lineage -> uncorrelated ============================
  {
    // J.1 nenhum job
    const { client: c1 } = makeSupabaseStub({ jobs: [], rows: [] });
    const l1 = await listCardLineageCorrelationMap(c1, SET_ALVO, EXT_ALVO);
    assert(r, "J.1 sem job elegivel o mapa e vazio", l1.size === 0);
    assert(r, "J.1 resultado e uncorrelated", correlate("TK-XY-N-1", new Map(), l1).cardId === null);

    // J.2 job existe, mas a row nao tem resulting_card_id
    const { client: c2 } = makeSupabaseStub({
      jobs: [job()],
      rows: [row("r1", "job-ok", "tk-xy-n-1", null)],
    });
    const l2 = await listCardLineageCorrelationMap(c2, SET_ALVO, EXT_ALVO);
    assert(r, "J.2 row sem resulting_card_id nao entra", l2.size === 0);

    // J.3 raw_data.id vazio / ausente / nao-string
    const { client: c3 } = makeSupabaseStub({
      jobs: [job()],
      rows: [
        row("r1", "job-ok", "   ", CARD_1),
        row("r2", "job-ok", undefined, CARD_2),
        row("r3", "job-ok", 12345, "card-3-uuid"),
      ],
    });
    const l3 = await listCardLineageCorrelationMap(c3, SET_ALVO, EXT_ALVO);
    assert(r, "J.3 raw_data.id vazio/ausente/nao-string nao entra", l3.size === 0,
      `vazou ${l3.size}`);

    // J.4 argumentos ausentes
    const { client: c4 } = makeSupabaseStub({ jobs: [job()], rows: [row("r1", "job-ok", "tk-xy-n-1", CARD_1)] });
    assert(r, "J.4 cardSetId vazio devolve mapa vazio",
      (await listCardLineageCorrelationMap(c4, "", EXT_ALVO)).size === 0);
    assert(r, "J.4 externalSetId vazio devolve mapa vazio",
      (await listCardLineageCorrelationMap(c4, SET_ALVO, "")).size === 0);
  }

  // === M — G0: job correto, Card de OUTRO Card Set -> fail-closed ========
  {
    // Cenario exato do mandato: TUDO no job esta certo — source TCGDEX,
    // card_set_id = SET_ALVO, external_set_id = EXT_ALVO, status terminal —
    // e o raw_data.id ate tem o prefixo esperado (G3 passa). O unico defeito
    // esta no DESTINO da linha: a Card pertence ao SET_OUTRO. Nenhum guard
    // anterior a G0 enxerga isso, porque a FK de resulting_card_id so prova
    // que a Card existe.
    const { client } = makeSupabaseStub({
      jobs: [job()],
      rows: [row("r1", "job-ok", "tk-xy-n-1", CARD_1)],
      cards: [{ id: CARD_1, card_set_id: SET_OUTRO }],
    });
    const lineage = await listCardLineageCorrelationMap(client, SET_ALVO, EXT_ALVO);

    assert(r, "M identidade com Card de outro Card Set e descartada", lineage.size === 0,
      `mapa devolveu ${JSON.stringify([...lineage])}`);
    assert(r, "M o fallback NAO retorna essa Card", ![...lineage.values()].includes(CARD_1));
    assert(r, "M resultado operacional e uncorrelated",
      correlate("TK-XY-N-1", new Map(), lineage).cardId === null);

    // Contraprova positiva na MESMA fixture: com a Card no Set certo, a
    // mesma linha passa. Prova que M reprova por pertença, e nao por
    // qualquer outro efeito colateral da fixture.
    const { client: cOk } = makeSupabaseStub({
      jobs: [job()],
      rows: [row("r1", "job-ok", "tk-xy-n-1", CARD_1)],
      cards: [{ id: CARD_1, card_set_id: SET_ALVO }],
    });
    const lOk = await listCardLineageCorrelationMap(cOk, SET_ALVO, EXT_ALVO);
    assert(r, "M contraprova: mesma linha com Card no Set certo PASSA",
      lOk.get("TK-XY-N-1") === CARD_1);

    // Mistura: uma linha boa e uma ruim no MESMO job. So a boa sobrevive —
    // o guard e por identidade, nao derruba o Set inteiro.
    const { client: cMix } = makeSupabaseStub({
      jobs: [job()],
      rows: [
        row("r1", "job-ok", "tk-xy-n-1", CARD_1),
        row("r2", "job-ok", "tk-xy-n-2", CARD_2),
      ],
      cards: [{ id: CARD_1, card_set_id: SET_ALVO }, { id: CARD_2, card_set_id: SET_OUTRO }],
    });
    const lMix = await listCardLineageCorrelationMap(cMix, SET_ALVO, EXT_ALVO);
    assert(r, "M lote misto: a linha valida sobrevive", lMix.get("TK-XY-N-1") === CARD_1);
    assert(r, "M lote misto: a linha fora do Set e descartada", !lMix.has("TK-XY-N-2"));
    assert(r, "M lote misto: exatamente 1 identidade no mapa", lMix.size === 1);

    // Card Set sem nenhuma Card: universo de pertenca vazio -> mapa vazio.
    const { client: cEmpty } = makeSupabaseStub({
      jobs: [job()],
      rows: [row("r1", "job-ok", "tk-xy-n-1", CARD_1)],
      cards: [],
    });
    assert(r, "M Card Set sem Cards devolve mapa vazio",
      (await listCardLineageCorrelationMap(cEmpty, SET_ALVO, EXT_ALVO)).size === 0);
  }

  // === N — custo: O(1) consultas por Set, nunca por linha =================
  {
    const rows: LineageRow[] = [];
    const cards: CardRow[] = [];
    for (let i = 1; i <= 250; i += 1) {
      rows.push(row(`r${String(i).padStart(4, "0")}`, "job-ok", `tk-xy-n-${i}`, `card-${i}`));
      cards.push({ id: `card-${i}`, card_set_id: SET_ALVO });
    }
    const { client, tablesRead } = makeSupabaseStub({ jobs: [job()], rows, cards });
    const lineage = await listCardLineageCorrelationMap(client, SET_ALVO, EXT_ALVO);

    assert(r, "N 250 linhas correlacionadas", lineage.size === 250, `mapa: ${lineage.size}`);
    assert(r, "N exatamente 3 consultas (job + card + row)", tablesRead.length === 3,
      `consultas: ${tablesRead.join(", ")}`);
    assert(r, "N ordem das consultas e job -> card -> row",
      tablesRead.join(",") === "catalog_import_job,card,catalog_import_row",
      tablesRead.join(","));
    assert(r, "N nenhuma consulta por linha", tablesRead.length < 250);
  }

  // === K — precedencia e telemetria realmente cabeadas em index.ts ========
  {
    let src = "";
    try {
      src = Deno.readTextFileSync(new URL("../index.ts", import.meta.url));
    } catch { /* coberto pelas assertions abaixo */ }

    assert(r, "K index.ts foi lido", src.length > 0);
    assert(r, "K o fallback e importado", src.includes("listCardLineageCorrelationMap"));
    assert(r, "K a referencia primaria e consultada primeiro",
      /const\s+referenceCardId\s*=\s*cardExternalReferences\.get\(/.test(src));
    assert(r, "K o lineage so e consultado quando a referencia falhou",
      /const\s+lineageCardId\s*=\s*referenceCardId\s*\?\s*null\s*:/.test(src));
    assert(r, "K a precedencia final e reference ?? lineage",
      /const\s+cardId\s*=\s*referenceCardId\s*\?\?\s*lineageCardId/.test(src));
    assert(r, "K telemetria correlated_by_reference presente", src.includes("correlated_by_reference:"));
    assert(r, "K telemetria correlated_by_lineage presente", src.includes("correlated_by_lineage:"));
    assert(r, "K campos antigos preservados",
      src.includes("correlated: correlatedCardIds.length") &&
      src.includes("uncorrelated: uncorrelated.length") &&
      src.includes("fetch_failed: fetchFailed.length"));
    assert(r, "K contagem por card_id distinto nos dois lados (invariante)",
      src.includes("const cardIdsByReference = new Set(") &&
      src.includes("const cardIdsByLineage = new Set("));
  }

  // === L — paginacao explicita ============================================
  {
    // 2.500 linhas: forca 3 paginas de 1.000 e prova que a leitura nao
    // depende do teto default do PostgREST.
    const total = 2500;
    const rows: LineageRow[] = [];
    for (let i = 1; i <= total; i += 1) {
      rows.push(row(`r${String(i).padStart(5, "0")}`, "job-ok", `tk-xy-n-${i}`, `card-${i}`));
    }
    const { client, ranges } = makeSupabaseStub({ jobs: [job()], rows });
    const lineage = await listCardLineageCorrelationMap(client, SET_ALVO, EXT_ALVO);

    const rowPages = ranges.filter(([t]) => t === "catalog_import_row");
    const cardPages = ranges.filter(([t]) => t === "card");

    assert(r, "L leitura completa alem de 1000 linhas", lineage.size === total,
      `mapa tem ${lineage.size}, esperado ${total}`);
    assert(r, "L lineage emitiu 3 paginas", rowPages.length === 3,
      `paginas emitidas: ${rowPages.length} (${JSON.stringify(rowPages)})`);
    assert(r, "L primeira pagina comeca em 0", rowPages[0]?.[1] === 0);
    assert(r, "L paginas sao contiguas e sem sobreposicao",
      rowPages.every(([, from], i) => i === 0 || from === rowPages[i - 1][2] + 1));
    assert(r, "L ultima linha foi lida", lineage.get(`TK-XY-N-${total}`) === `card-${total}`);
    // G0 tambem pagina: o universo de pertenca nao pode truncar, senao
    // reprovaria Cards legitimas do proprio Set.
    assert(r, "L o universo de pertenca (G0) tambem e paginado ate exaurir",
      cardPages.length === 3, `paginas de card: ${cardPages.length}`);
    assert(r, "L paginas de card sao contiguas",
      cardPages.every(([, from], i) => i === 0 || from === cardPages[i - 1][2] + 1));

    // Prova negativa: a chamada NUNCA e feita sem range.
    let sawBareSelect = false;
    try {
      const src = Deno.readTextFileSync(new URL("./database.ts", import.meta.url));
      const fn = src.slice(src.indexOf("export async function listCardLineageCorrelationMap"));
      const body = fn.slice(0, fn.indexOf("\n}\n"));
      sawBareSelect = body.includes('.from("catalog_import_row")') && !body.includes(".range(");
    } catch { /* coberto abaixo */ }
    assert(r, "L a leitura de catalog_import_row sempre usa .range()", !sawBareSelect);
  }

  return r;
}

// ---------------------------------------------------------------------------
// Deno.test real — falha de verdade quando qualquer assertion falha.
// ---------------------------------------------------------------------------

Deno.test("lineage-correlation — fallback determinístico de correlação de Cards", async () => {
  const resultados = await runLineageCorrelationTests();
  const falhas = resultados.filter((x) => !x.ok);

  for (const x of resultados) {
    console.log(`${x.ok ? "PASS" : "FAIL"}  ${x.caso}${x.detalhe ? `  — ${x.detalhe}` : ""}`);
  }
  console.log(`\n${resultados.length} casos · ${resultados.length - falhas.length} PASS · ${falhas.length} FAIL`);

  if (resultados.length === 0) {
    throw new Error("LINEAGE_CORRELATION_TESTS_VAZIO: a suite nao produziu nenhum caso.");
  }
  if (falhas.length > 0) {
    throw new Error(
      `LINEAGE_CORRELATION_TESTS_FAILED (${falhas.length}/${resultados.length}):\n` +
        falhas.map((x) => `  - ${x.caso}${x.detalhe ? ` — ${x.detalhe}` : ""}`).join("\n"),
    );
  }
});
