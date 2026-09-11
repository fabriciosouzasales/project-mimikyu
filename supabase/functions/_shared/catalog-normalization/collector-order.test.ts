// Project Mimikyu — supabase/functions/_shared/catalog-normalization/collector-order.test.ts
// Bateria da regra SET-LEVEL de collector_order (G0-FREEZE, 2026-09-10).
//
// 100% offline: nenhuma chamada de rede, nenhum acesso ao Supabase.
//
// Execução canônica:
//   deno test supabase/functions/_shared/catalog-normalization/collector-order.test.ts
//
// O arquivo registra UM `Deno.test` real que executa toda a suíte e falha de
// verdade (throw) se qualquer assertion falhar — `deno test` nunca termina com
// "0 tests" nem com sucesso vazio. `runCollectorOrderTests()` continua
// exportada para reaproveitamento por um runner externo, mas não é mais o
// único ponto de entrada.
//
// PROCEDÊNCIA DAS FIXTURES. Os identificadores vêm do corpus real, levantado
// em 2026-09-10:
//   - `catalog_import_row.raw_data->>'localId'` de jobs `source = 'TCGDEX'`;
//   - confirmados por GET read-only em `api.tcgdex.net` nos Sets
//     `bwp, xyp, swsh9tg, tk-sm-l, xy8, xy9, ecard2`.
//   - Para Sets grandes (BWP 101, XYP 216), a fixture reproduz a FAIXA CRÍTICA
//     real (a virada de dezena/centena) — exatamente onde o defeito aparecia.
// A ordem dos tokens nas fixtures é DELIBERADAMENTE a ordem em que a TCGdex
// devolve, para provar que o resultado não depende dela.

import {
  AmbiguousCollectorKeyError,
  assertPersistedCardsCovered,
  buildSetCollectorOrderPlan,
  collectorOrderFor,
  EXU_EDITORIAL_ORDER,
  IncompleteCollectorOrderSetError,
  InvalidNumericSetError,
  UnsupportedCollectorNumberError,
} from "./collector-order.ts";

export type Resultado = { caso: string; ok: boolean; detalhe: string };

function assert(resultados: Resultado[], caso: string, ok: boolean, detalhe = "") {
  resultados.push({ caso, ok, detalhe });
}

function ordens(tokens: string[], setCode?: string): Record<string, number> {
  const plan = buildSetCollectorOrderPlan({ tokens, setCode });
  const out: Record<string, number> = {};
  for (const t of tokens) out[t] = collectorOrderFor(plan, t);
  return out;
}

/** Permutação determinística (LCG) — não usa Math.random, o teste é reprodutível. */
function embaralhar(tokens: string[], seed: number): string[] {
  const a = tokens.slice();
  let s = seed >>> 0;
  for (let i = a.length - 1; i > 0; i--) {
    s = (s * 1664525 + 1013904223) >>> 0;
    const j = s % (i + 1);
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}

function densoEUnico(mapa: Record<string, number>): { denso: boolean; unico: boolean } {
  const vals = Object.values(mapa).sort((x, y) => x - y);
  const unico = new Set(vals).size === vals.length;
  const denso = vals.every((v, i) => v === i + 1);
  return { denso, unico };
}

/** Executa `fn` e devolve true se ela lançou uma instância de `Erro`. */
function lancou(fn: () => unknown, Erro: new (...args: never[]) => Error): boolean {
  try {
    fn();
    return false;
  } catch (e) {
    return e instanceof Erro;
  }
}

// ---------------------------------------------------------------------------
// Fixtures reais
// ---------------------------------------------------------------------------

// BWP — 101 cartas, `BW01`..`BW101`. A TCGdex devolve lexicograficamente
// (`BW10, BW100, BW101, BW11`), e era exatamente assim que o banco gravava.
const BWP = (() => {
  const ids: string[] = [];
  for (let i = 1; i <= 101; i++) ids.push(i < 10 ? `BW0${i}` : `BW${i}`);
  return ids.slice().sort(); // ordem lexicográfica = ordem real da fonte
})();

// XYP — faixa crítica real da virada de dezena/centena.
const XYP_FAIXA = ["XY08", "XY09", "XY10", "XY100", "XY101", "XY102", "XY11", "XY12", "XY211"];

// SWSH9TG — prefixo com zero-padding; lexicográfico já coincide com o correto.
const SWSH9TG = Array.from({ length: 30 }, (_, i) => `TG${String(i + 1).padStart(2, "0")}`);

// TK-SM-L — numérico ESPARSO: 18 cartas num Set que declara 30.
// `/v2/en/sets/tk-sm-l` devolve literalmente esta lista.
const TK_SM_L = ["1", "4", "5", "11", "12", "13", "14", "15", "16", "18", "19", "21", "22", "23", "25", "27", "29", "30"];

// XY8 — faixa real em torno da carta que falhou (`146a`), na ordem da fonte,
// que devolve o sufixo ANTES da base.
const XY8_FAIXA = ["143", "144", "145", "146a", "146", "147", "148"];

// XY9 — a fonte devolve `98b` antes de `98a` antes de `98`.
const XY9_FAIXA = ["96", "97", "98b", "98a", "98", "99", "106", "107", "107a", "108"];

// ECARD2 — pares `a`/`b` SEM carta-base (não existe "50", "74", "95", "103")
// e o bloco holo `H01..H32` depois do fim da corrida numérica.
const ECARD2_FAIXA = ["48", "49", "50b", "50a", "51", "73", "74a", "74b", "75", "149", "150", "H01", "H02", "H32"];

// HGSS1 — sequência numérica + a Alph Lithograph daquele Set (`ONE`).
const HGSS1 = [...Array.from({ length: 123 }, (_, i) => String(i + 1)), "ONE"];

// EXU — a TCGdex devolve `%3F` (o `?` percent-encoded) e `!`.
const EXU = ["!", "%3F", ...Array.from({ length: 26 }, (_, i) => String.fromCharCode(65 + i))];

const CORPORA_REAIS: Array<[string, string[]]> = [
  ["BWP", BWP], ["XYP", XYP_FAIXA], ["SWSH9TG", SWSH9TG], ["TK-SM-L", TK_SM_L],
  ["XY8", XY8_FAIXA], ["XY9", XY9_FAIXA], ["ECARD2", ECARD2_FAIXA], ["HGSS1", HGSS1],
];

// ---------------------------------------------------------------------------
// Bateria
// ---------------------------------------------------------------------------

export function runCollectorOrderTests(): Resultado[] {
  const r: Resultado[] = [];

  // --- BWP ------------------------------------------------------------------
  {
    const o = ordens(BWP, "BWP");
    const plan = buildSetCollectorOrderPlan({ tokens: BWP, setCode: "BWP" });
    assert(r, "BWP modo B", plan.mode === "ORDINAL_DERIVED", plan.mode);
    assert(r, "BWP BW10 < BW11 < BW99 < BW100 < BW101",
      o["BW10"] < o["BW11"] && o["BW11"] < o["BW99"] && o["BW99"] < o["BW100"] && o["BW100"] < o["BW101"],
      `BW10=${o["BW10"]} BW11=${o["BW11"]} BW99=${o["BW99"]} BW100=${o["BW100"]} BW101=${o["BW101"]}`);
    assert(r, "BWP BW01=1 e BW101=101", o["BW01"] === 1 && o["BW101"] === 101,
      `BW01=${o["BW01"]} BW101=${o["BW101"]}`);
    const d = densoEUnico(o);
    assert(r, "BWP denso 1..101 e unico", d.denso && d.unico, JSON.stringify(d));
  }

  // --- XYP ------------------------------------------------------------------
  {
    const o = ordens(XYP_FAIXA, "XYP");
    assert(r, "XYP XY10 < XY11 < XY12 < XY100 < XY101 < XY102 < XY211",
      o["XY10"] < o["XY11"] && o["XY11"] < o["XY12"] && o["XY12"] < o["XY100"] &&
      o["XY100"] < o["XY101"] && o["XY101"] < o["XY102"] && o["XY102"] < o["XY211"],
      JSON.stringify(o));
    assert(r, "XYP corrige a ordem lexicografica da fonte", o["XY11"] < o["XY100"],
      `XY11=${o["XY11"]} XY100=${o["XY100"]}`);
  }

  // --- SWSH9TG (prefixo zero-padded: nada muda) ------------------------------
  {
    const o = ordens(SWSH9TG, "SWSH9TG");
    assert(r, "SWSH9TG TG01..TG30 -> 1..30 (sem mudanca vs. hoje)",
      SWSH9TG.every((t, i) => o[t] === i + 1), JSON.stringify(o));
  }

  // --- TK-SM-L (modo A, gaps preservados) ------------------------------------
  {
    const plan = buildSetCollectorOrderPlan({ tokens: TK_SM_L, setCode: "TK-SM-L" });
    const o = ordens(TK_SM_L, "TK-SM-L");
    assert(r, "TK-SM-L modo A", plan.mode === "NUMERIC_PRESERVED", plan.mode);
    assert(r, "TK-SM-L preserva o numero impresso (1->1, 30->30)", o["1"] === 1 && o["30"] === 30,
      `1=${o["1"]} 30=${o["30"]}`);
    assert(r, "TK-SM-L NAO densifica (18 cartas, max 30)",
      Object.keys(o).length === 18 && Math.max(...Object.values(o)) === 30,
      `n=${Object.keys(o).length} max=${Math.max(...Object.values(o))}`);
    const d = densoEUnico(o);
    assert(r, "TK-SM-L unico (denso e falso de proposito)", d.unico && !d.denso, JSON.stringify(d));
  }

  // --- XY8 (base < sufixo — decisao MMKYU contra a ordem da fonte) -----------
  {
    const o = ordens(XY8_FAIXA, "XY8");
    assert(r, "XY8 146 < 146a < 147", o["146"] < o["146a"] && o["146a"] < o["147"],
      `146=${o["146"]} 146a=${o["146a"]} 147=${o["147"]}`);
    assert(r, "XY8 146a ocupa a posicao imediatamente seguinte a 146",
      o["146a"] === o["146"] + 1, `146=${o["146"]} 146a=${o["146a"]}`);
    assert(r, "XY8 contraria a ordem da fonte (que devolve 146a antes de 146)",
      o["146a"] > o["146"], "regra MMKYU prevalece");
  }

  // --- XY9 (98 < 98a < 98b, apesar de a fonte devolver 98b primeiro) ---------
  {
    const o = ordens(XY9_FAIXA, "XY9");
    assert(r, "XY9 98 < 98a < 98b < 99",
      o["98"] < o["98a"] && o["98a"] < o["98b"] && o["98b"] < o["99"],
      `98=${o["98"]} 98a=${o["98a"]} 98b=${o["98b"]} 99=${o["99"]}`);
    assert(r, "XY9 107 < 107a < 108", o["107"] < o["107a"] && o["107a"] < o["108"],
      `107=${o["107"]} 107a=${o["107a"]} 108=${o["108"]}`);
  }

  // --- ECARD2 (par a/b sem base + bloco H no fim) ----------------------------
  {
    const o = ordens(ECARD2_FAIXA, "ECARD2");
    assert(r, "ECARD2 49 < 50a < 50b < 51 (sem carta-base 50)",
      o["49"] < o["50a"] && o["50a"] < o["50b"] && o["50b"] < o["51"],
      `49=${o["49"]} 50a=${o["50a"]} 50b=${o["50b"]} 51=${o["51"]}`);
    assert(r, "ECARD2 73 < 74a < 74b < 75",
      o["73"] < o["74a"] && o["74a"] < o["74b"] && o["74b"] < o["75"],
      `73=${o["73"]} 74a=${o["74a"]} 74b=${o["74b"]} 75=${o["75"]}`);
    assert(r, "ECARD2 bloco H depois de toda a corrida numerica",
      o["H01"] > o["150"] && o["H01"] < o["H02"] && o["H02"] < o["H32"],
      `150=${o["150"]} H01=${o["H01"]} H32=${o["H32"]}`);
  }

  // --- HGSS1 (excecao nomeada: Alph Lithograph por ultimo) -------------------
  {
    const plan = buildSetCollectorOrderPlan({ tokens: HGSS1, setCode: "HGSS1" });
    const o = ordens(HGSS1, "HGSS1");
    assert(r, "HGSS1 excecao HGSS_ALPH_LITHOGRAPH", plan.exception === "HGSS_ALPH_LITHOGRAPH", String(plan.exception));
    assert(r, "HGSS1 modo A para a corrida numerica", plan.mode === "NUMERIC_PRESERVED", plan.mode);
    assert(r, "HGSS1 numericos preservados (1->1, 123->123)", o["1"] === 1 && o["123"] === 123,
      `1=${o["1"]} 123=${o["123"]}`);
    assert(r, "HGSS1 ONE por ultimo (124)", o["ONE"] === 124, `ONE=${o["ONE"]}`);
    assert(r, "HGSS1 sem colisao", densoEUnico(o).unico, "");
  }

  // --- HARDENING 1: mapa NOMINAL EXATO Set -> token -------------------------
  // Os 6 casos exigidos pela auditoria, verbatim.
  {
    const esperado: Array<[string, string]> = [
      ["HGSS1", "ONE"], ["HGSS2", "TWO"], ["HGSS3", "THREE"], ["HGSS4", "FOUR"],
    ];
    for (const [code, token] of esperado) {
      const plan = buildSetCollectorOrderPlan({ tokens: ["1", "2", "3", token], setCode: code });
      assert(r, `H1: ${code} + ${token} -> PASS (litografo = 4)`,
        plan.exception === "HGSS_ALPH_LITHOGRAPH" &&
        plan.mode === "NUMERIC_PRESERVED" &&
        collectorOrderFor(plan, token) === 4,
        `exception=${plan.exception} mode=${plan.mode}`);
    }

    // Token certo, Set errado.
    assert(r, "H1: HGSS1 + TWO -> FAIL (token nao e o daquele Set)",
      lancou(() => buildSetCollectorOrderPlan({ tokens: ["1", "2", "TWO"], setCode: "HGSS1" }),
        UnsupportedCollectorNumberError), "");
    assert(r, "H1: HGSS4 + ONE -> FAIL (token nao e o daquele Set)",
      lancou(() => buildSetCollectorOrderPlan({ tokens: ["1", "2", "ONE"], setCode: "HGSS4" }),
        UnsupportedCollectorNumberError), "");

    // Matriz completa das 12 combinações erradas Set×token.
    const erradas: string[] = [];
    for (const [code] of esperado) {
      for (const [, token] of esperado) {
        if (ALPH_ESPERADO(code) === token) continue;
        if (!lancou(() => buildSetCollectorOrderPlan({ tokens: ["1", "2", token], setCode: code }),
          UnsupportedCollectorNumberError)) erradas.push(`${code}+${token}`);
      }
    }
    assert(r, "H1: as 12 combinacoes Set x token erradas falham fechado", erradas.length === 0, erradas.join(","));

    // Fora dos quatro Sets, nenhum dos tokens tem tratamento especial.
    const foraDosQuatro = ["SET_FICTICIO", "XY8", "BASE1", ""];
    const naoLancou: string[] = [];
    for (const code of foraDosQuatro) {
      for (const token of ["ONE", "TWO", "THREE", "FOUR"]) {
        if (!lancou(() => buildSetCollectorOrderPlan({ tokens: ["1", "2", token], setCode: code }),
          UnsupportedCollectorNumberError)) naoLancou.push(`${code || "<vazio>"}+${token}`);
      }
    }
    assert(r, "H1: ONE/TWO/THREE/FOUR fora de HGSS1-4 -> UnsupportedCollectorNumberError",
      naoLancou.length === 0, naoLancou.join(","));

    // Token esperado duplicado no Set certo.
    assert(r, "H1: token esperado duplicado (HGSS1 + ONE + ONE) -> AmbiguousCollectorKeyError",
      lancou(() => buildSetCollectorOrderPlan({ tokens: ["1", "ONE", "ONE"], setCode: "HGSS1" }),
        AmbiguousCollectorKeyError), "");

    // Outro token alfabetico dentro de um Set HGSS.
    assert(r, "H1: token alfabetico diferente do esperado em HGSS2 -> FAIL",
      lancou(() => buildSetCollectorOrderPlan({ tokens: ["1", "2", "ALPHA"], setCode: "HGSS2" }),
        UnsupportedCollectorNumberError), "");

    // Case-insensitive no token, mas sempre ancorado no Set certo.
    let minusculoOk = false;
    try {
      const p = buildSetCollectorOrderPlan({ tokens: ["1", "one"], setCode: "HGSS1" });
      minusculoOk = collectorOrderFor(p, "one") === 2;
    } catch { minusculoOk = false; }
    assert(r, "H1: token em minuscula reconhecido dentro de HGSS1", minusculoOk, "");
  }

  // --- BLOCKER L1: guard de cobertura do conjunto completo -------------------
  {
    // 1. persistido "001" + incoming raw "1", total 185 -> cobertura PASS.
    //    O guard compara collector_number CANONICO, nao localId cru.
    let cobre = true;
    try {
      assertPersistedCardsCovered({
        incoming: [
          { localId: "1", collectorTotal: 185 },
          { localId: "2", collectorTotal: 185 },
        ],
        persistedCollectorNumbers: ["001", "002"],
        setCode: "SV1",
      });
    } catch { cobre = false; }
    assert(r, "L1-1: persistido \"001\" + incoming raw \"1\" (total 185) -> cobertura PASS", cobre, "");

    // 2. persistido "001" ausente do incoming -> FAIL.
    assert(r, "L1-2: persistido \"001\" ausente do incoming -> IncompleteCollectorOrderSetError",
      lancou(() => assertPersistedCardsCovered({
        incoming: [{ localId: "2", collectorTotal: 185 }],
        persistedCollectorNumbers: ["001", "002"],
        setCode: "SV1",
      }), IncompleteCollectorOrderSetError), "");

    // 3. alfanumerico persistido "TG01" + incoming "TG01" -> PASS.
    let alfaCobre = true;
    try {
      assertPersistedCardsCovered({
        incoming: [{ localId: "TG01", collectorTotal: 30 }, { localId: "TG02", collectorTotal: 30 }],
        persistedCollectorNumbers: ["TG01", "TG02"],
        setCode: "SWSH9TG",
      });
    } catch { alfaCobre = false; }
    assert(r, "L1-3: alfanumerico persistido \"TG01\" + incoming \"TG01\" -> PASS", alfaCobre, "");

    // 4. persisted-only alfanumerico -> FAIL.
    assert(r, "L1-4: persisted-only alfanumerico (\"TG30\" so no banco) -> FAIL",
      lancou(() => assertPersistedCardsCovered({
        incoming: [{ localId: "TG01", collectorTotal: 30 }],
        persistedCollectorNumbers: ["TG01", "TG30"],
        setCode: "SWSH9TG",
      }), IncompleteCollectorOrderSetError), "");

    // Detalhe do erro: nomeia o ausente e limita a amostra.
    let detalheOk = false;
    try {
      assertPersistedCardsCovered({
        incoming: [{ localId: "1", collectorTotal: 185 }],
        persistedCollectorNumbers: ["001", "002", "003"],
        setCode: "SV1",
      });
    } catch (e) {
      detalheOk = e instanceof IncompleteCollectorOrderSetError &&
        e.totalFaltantes === 2 && e.faltantes.includes("002") && e.faltantes.includes("003");
    }
    assert(r, "L1: erro nomeia os collector_numbers persistidos ausentes", detalheOk, "");

    let truncaOk = false;
    try {
      assertPersistedCardsCovered({
        incoming: [],
        persistedCollectorNumbers: Array.from({ length: 40 }, (_, i) => String(i + 1).padStart(3, "0")),
        setCode: "GRANDE",
      });
    } catch (e) {
      truncaOk = e instanceof IncompleteCollectorOrderSetError &&
        e.totalFaltantes === 40 && e.faltantes.length === 10;
    }
    assert(r, "L1: amostra do erro truncada em 10, total preservado", truncaOk, "");

    // Conjunto vazio dos dois lados nao e erro.
    let vazioOk = true;
    try {
      assertPersistedCardsCovered({ incoming: [], persistedCollectorNumbers: [], setCode: "NOVO" });
    } catch { vazioOk = false; }
    assert(r, "L1: Set novo (zero persistido, zero incoming) nao dispara o guard", vazioOk, "");

    // Incoming maior que o persistido e o caso normal de importacao.
    let cresceOk = true;
    try {
      assertPersistedCardsCovered({
        incoming: [{ localId: "1", collectorTotal: 3 }, { localId: "2", collectorTotal: 3 }, { localId: "3", collectorTotal: 3 }],
        persistedCollectorNumbers: ["1", "2"],
        setCode: "X",
      });
    } catch { cresceOk = false; }
    assert(r, "L1: incoming com Cards novas alem das persistidas -> PASS", cresceOk, "");
  }

  // --- BLOCKER L1: completude da excecao HGSS -------------------------------
  {
    const faltando: Array<[string, string]> = [
      ["HGSS1", "ONE"], ["HGSS2", "TWO"], ["HGSS3", "THREE"], ["HGSS4", "FOUR"],
    ];
    for (const [code, token] of faltando) {
      assert(r, `L1: ${code} sem ${token} -> IncompleteCollectorOrderSetError`,
        lancou(() => buildSetCollectorOrderPlan({ tokens: ["1", "2", "3"], setCode: code }),
          IncompleteCollectorOrderSetError), "");
    }

    // Token errado continua falhando como antes (Unsupported, nao Incomplete).
    assert(r, "L1: HGSS1 + TWO continua UnsupportedCollectorNumberError (nao Incomplete)",
      lancou(() => buildSetCollectorOrderPlan({ tokens: ["1", "2", "TWO"], setCode: "HGSS1" }),
        UnsupportedCollectorNumberError), "");
  }

  // --- HARDENING 2: chave natural canonica, ambiguidade -> fail closed -------
  {
    const ambiguos: Array<[string, string[]]> = [
      ["1 / 01", ["1", "01", "2a"]],
      ["BW1 / BW01", ["BW1", "BW01", "BW2"]],
      ["88a / 088a", ["88a", "088a", "89"]],
      ["88a / 88A (caixa)", ["88a", "88A", "89"]],
      ["TG1 / tg01", ["TG1", "tg01", "TG2"]],
    ];
    const naoLancou: string[] = [];
    for (const [nome, tokens] of ambiguos) {
      if (!lancou(() => buildSetCollectorOrderPlan({ tokens, setCode: "X" }), AmbiguousCollectorKeyError)) {
        naoLancou.push(nome);
      }
    }
    assert(r, "H2: chaves naturais equivalentes -> AmbiguousCollectorKeyError",
      naoLancou.length === 0, naoLancou.join(","));

    // O erro tem de nomear os dois identificadores envolvidos.
    let nomeia = false;
    try {
      buildSetCollectorOrderPlan({ tokens: ["1", "01", "2a"], setCode: "X" });
    } catch (e) {
      nomeia = e instanceof AmbiguousCollectorKeyError && e.tokens.includes("1") && e.tokens.includes("01");
    }
    assert(r, "H2: erro nomeia os identificadores em conflito", nomeia, "");

    // Falso positivo: zero-padding uniforme NAO e ambiguidade.
    let semFalsoPositivo = false;
    try {
      const p = buildSetCollectorOrderPlan({ tokens: ["001", "002", "003a"], setCode: "X" });
      semFalsoPositivo = collectorOrderFor(p, "001") === 1 && collectorOrderFor(p, "003a") === 3;
    } catch { semFalsoPositivo = false; }
    assert(r, "H2: zero-padding uniforme nao e ambiguidade", semFalsoPositivo, "");

    // Os corpora reais continuam passando pelo guard.
    const quebrou: string[] = [];
    for (const [code, tokens] of CORPORA_REAIS) {
      try { ordens(tokens, code); } catch { quebrou.push(code); }
    }
    assert(r, "H2: nenhum corpus real dispara falso positivo", quebrou.length === 0, quebrou.join(","));
  }

  // --- Fail closed generico --------------------------------------------------
  {
    assert(r, "string sem digito fora de qualquer excecao -> erro explicito",
      lancou(() => buildSetCollectorOrderPlan({ tokens: ["1", "2", "ALPHA"], setCode: "QUALQUER" }),
        UnsupportedCollectorNumberError), "");
    assert(r, "formato nao suportado (3!) -> erro explicito / fail closed",
      lancou(() => buildSetCollectorOrderPlan({ tokens: ["1", "2", "3!"], setCode: "QUALQUER" }),
        UnsupportedCollectorNumberError), "");
  }

  // --- EXU (congelado, mas bloqueado para escrita) ---------------------------
  {
    const plan = buildSetCollectorOrderPlan({ tokens: EXU, setCode: "EXU" });
    assert(r, "EXU excecao EXU_UNOWN", plan.exception === "EXU_UNOWN", String(plan.exception));
    assert(r, "EXU bloqueado para persistencia (constraint de collector_number)",
      typeof plan.blockedReason === "string" && plan.blockedReason.length > 0, String(plan.blockedReason));
    assert(r, "EXU A=1, Z=26, !=27, ?=28",
      collectorOrderFor(plan, "A") === 1 && collectorOrderFor(plan, "Z") === 26 &&
      collectorOrderFor(plan, "!") === 27 && collectorOrderFor(plan, "%3F") === 28,
      `A=${collectorOrderFor(plan, "A")} Z=${collectorOrderFor(plan, "Z")} !=${collectorOrderFor(plan, "!")} %3F=${collectorOrderFor(plan, "%3F")}`);
    assert(r, "EXU ordem congelada tem 28 posicoes", EXU_EDITORIAL_ORDER.length === 28, String(EXU_EDITORIAL_ORDER.length));
  }

  // --- Modo A: pre-condicoes -------------------------------------------------
  {
    assert(r, "modo A recusa numero duplicado (1 e 01)",
      lancou(() => buildSetCollectorOrderPlan({ tokens: ["1", "01", "2"], setCode: "X" }),
        InvalidNumericSetError), "");
    assert(r, "modo A recusa zero/negativo",
      lancou(() => buildSetCollectorOrderPlan({ tokens: ["0", "1"], setCode: "X" }),
        InvalidNumericSetError), "");
  }

  // --- Shuffle: independencia total da ordem de entrada ----------------------
  {
    let todosIguais = true;
    const divergentes: string[] = [];
    for (const [code, tokens] of CORPORA_REAIS) {
      const base = ordens(tokens, code);
      for (let seed = 1; seed <= 25; seed++) {
        const alt = ordens(embaralhar(tokens, seed), code);
        const igual = Object.keys(base).length === Object.keys(alt).length &&
          Object.keys(base).every((k) => base[k] === alt[k]);
        if (!igual) { todosIguais = false; divergentes.push(`${code}/seed${seed}`); }
      }
    }
    assert(r, "shuffle: 8 corpora x 25 permutacoes -> saida identica", todosIguais, divergentes.join(","));
  }

  // --- Idempotencia ----------------------------------------------------------
  {
    let ok = true;
    for (const [code, tokens] of CORPORA_REAIS) {
      const p1 = ordens(tokens, code);
      const p2 = ordens(tokens, code);
      // reaplicar sobre os tokens ja reordenados pelo proprio resultado
      const reordenado = tokens.slice().sort((a, b) => p1[a] - p1[b]);
      const p3 = ordens(reordenado, code);
      if (JSON.stringify(p1) !== JSON.stringify(p2)) ok = false;
      if (!Object.keys(p1).every((k) => p1[k] === p3[k])) ok = false;
    }
    assert(r, "idempotencia: reaplicar nao muda nada", ok, "");
  }

  // --- Zero colisao em todos os corpora --------------------------------------
  {
    const comColisao: string[] = [];
    for (const [code, tokens] of CORPORA_REAIS) {
      if (!densoEUnico(ordens(tokens, code)).unico) comColisao.push(code);
    }
    assert(r, "zero colisao em 8 corpora reais", comColisao.length === 0, comColisao.join(","));
  }

  return r;
}

/** Espelha o mapa nominal de collector-order.ts — só para montar a matriz de testes. */
function ALPH_ESPERADO(setCode: string): string | null {
  switch (setCode.toUpperCase()) {
    case "HGSS1": return "ONE";
    case "HGSS2": return "TWO";
    case "HGSS3": return "THREE";
    case "HGSS4": return "FOUR";
    default: return null;
  }
}

// ---------------------------------------------------------------------------
// Deno.test real — falha de verdade quando qualquer assertion falha.
// ---------------------------------------------------------------------------

Deno.test("collector-order — suite completa (G0-FREEZE)", () => {
  const resultados = runCollectorOrderTests();
  const falhas = resultados.filter((x) => !x.ok);

  for (const x of resultados) {
    console.log(`${x.ok ? "PASS" : "FAIL"}  ${x.caso}${x.detalhe ? `  — ${x.detalhe}` : ""}`);
  }
  console.log(`\n${resultados.length} casos · ${resultados.length - falhas.length} PASS · ${falhas.length} FAIL`);

  if (resultados.length === 0) {
    throw new Error("COLLECTOR_ORDER_TESTS_VAZIO: a suite nao produziu nenhum caso.");
  }
  if (falhas.length > 0) {
    throw new Error(
      `COLLECTOR_ORDER_TESTS_FAILED (${falhas.length}/${resultados.length}):\n` +
        falhas.map((x) => `  - ${x.caso}${x.detalhe ? ` — ${x.detalhe}` : ""}`).join("\n"),
    );
  }
});
