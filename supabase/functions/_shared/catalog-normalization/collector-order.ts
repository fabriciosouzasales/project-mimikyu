// Project Mimikyu — Núcleo compartilhado de normalização de catálogo.
// Derivação de `card.collector_order` — regra SET-LEVEL congelada em
// 2026-09-10 (CATALOG-HISTORICAL-BOOTSTRAP-03-CARDS-RECOVERY-G0-FREEZE).
//
// SUBSTITUI deriveCollectorOrder(localId, indexInSet) (resolve-row.ts,
// 2026-08-06 → 2026-09-10), que decidia POR LINHA entre "número da carta"
// (`Number(localId)`) e "posição na resposta HTTP" (`indexInSet + 1`).
// Os dois ramos escreviam no MESMO espaço de valores `1..N`, então qualquer
// identificador alfanumérico podia aterrissar exatamente sobre um numérico
// do mesmo Set. Consequências medidas no catálogo real (G0, 2026-09-10):
//
//   - 15 linhas falharam com `duplicate key ... uq_card_card_set_collector_order`
//     em 8 Coleções XY — e em XY2/XY6/XY9/XY10 quem perdeu a colisão foi a
//     carta NUMÉRICA (`088`, `077`, `098`, `043`), não a alfanumérica;
//   - 305 posições em 5 Coleções ficaram com ordem editorial errada SEM
//     colisão nenhuma: `BWP`/`XYP` foram gravadas na ordem lexicográfica em
//     que a TCGdex devolve (`BW10, BW100, BW101, BW11`), porque a posição do
//     array virava a ordem;
//   - mais 176 posições e 9 colisões estavam latentes em jobs ainda STAGED.
//
// O modelo híbrido POR LINHA fica proibido por construção: aqui a decisão é
// do CONJUNTO, tomada uma única vez por Card Set, antes de qualquer atribuição.
//
// A ordem devolvida pela TCGdex NÃO é usada como sinal editorial. Ela é
// internamente inconsistente — verificado por GET read-only em 2026-09-10:
// para `bwp`/`xyp` ela ordena lexicograficamente (onde `"88a" > "88"`), mas
// para `xy8`/`xy9`/`xy2`/`ecard2` ela devolve o sufixo ANTES da base
// (`145, 146a, 146, 147`) e chega a devolver `98b` antes de `98a`. As duas
// regras não podem valer ao mesmo tempo. A autoridade editorial é do MMKYU.

// `padCollectorNumber` é a ÚNICA forma canônica de collector_number no
// projeto. O guard de cobertura (assertPersistedCardsCovered) tem de comparar
// exatamente o que `resolveCatalogImportRow` vai gravar — comparar `localId`
// cru faria `"1"` e `"001"` parecerem Cards diferentes. Sem ciclo de import:
// resolve-row.ts recebe `collectorOrder` como parâmetro e nunca importa este
// módulo.
import { padCollectorNumber } from "./resolve-row.ts";

/** Modo de derivação, decidido por Card Set — nunca por linha. */
export type CollectorOrderMode = "NUMERIC_PRESERVED" | "ORDINAL_DERIVED";

/** Exceção editorial nomeada aplicada ao Set (null quando nenhuma). */
export type CollectorOrderException = "HGSS_ALPH_LITHOGRAPH" | "EXU_UNOWN" | null;

export type SetCollectorOrderPlan = {
  mode: CollectorOrderMode;
  exception: CollectorOrderException;
  /** Chaveado pelo identificador exatamente como recebido. */
  orderByToken: Map<string, number>;
  /**
   * Preenchido só quando o Set depende de uma exceção que ainda não pode ser
   * persistida (hoje: EXU). Caller DEVE recusar o Set quando não for null —
   * o plano existe para registrar a decisão editorial congelada, não para
   * liberar a escrita.
   */
  blockedReason: string | null;
};

/**
 * Fail closed. Nenhum formato desconhecido recebe ordem por heurística —
 * o Set inteiro para, com o token exato no erro.
 */
export class UnsupportedCollectorNumberError extends Error {
  readonly token: string;
  constructor(token: string) {
    super(`COLLECTOR_ORDER_FORMATO_NAO_SUPORTADO: ${JSON.stringify(token)}`);
    this.name = "UnsupportedCollectorNumberError";
    this.token = token;
  }
}

/** Violação das pré-condições do Modo A (número duplicado ou <= 0). */
export class InvalidNumericSetError extends Error {
  constructor(message: string) {
    super(`COLLECTOR_ORDER_SET_NUMERICO_INVALIDO: ${message}`);
    this.name = "InvalidNumericSetError";
  }
}

/**
 * HARDENING 2 (2026-09-10). Dois identificadores DIFERENTES como texto podem
 * produzir a MESMA chave natural — `"1"`/`"01"`, `"BW1"`/`"BW01"`,
 * `"88a"`/`"088a"`, `"88a"`/`"88A"`. Antes deste guard o desempate final por
 * `raw` transformava silenciosamente duas chaves semanticamente equivalentes
 * em duas posições válidas e distintas, que é exatamente a classe de erro que
 * este módulo existe para impedir. Agora o Set inteiro para.
 */
export class AmbiguousCollectorKeyError extends Error {
  readonly tokens: string[];
  constructor(chave: string, tokens: string[]) {
    super(
      `COLLECTOR_ORDER_CHAVE_AMBIGUA: a chave natural ${JSON.stringify(chave)} ` +
        `e produzida por mais de um identificador no mesmo Set: ${tokens.map((t) => JSON.stringify(t)).join(", ")}`,
    );
    this.name = "AmbiguousCollectorKeyError";
    this.tokens = tokens;
  }
}

/**
 * BLOCKER L1 (2026-09-10). G0 congelou a pré-condição do plano:
 *
 *   conjunto completo = Cards persistidas + linhas do job, inclusive FAILED.
 *
 * Sem essa garantia o Modo B atribui ordinais densos sobre um SUBCONJUNTO —
 * e qualquer Card persistida que tenha ficado de fora passa a colidir ou a
 * ocupar a posição errada. É exatamente a classe de erro que a regra
 * SET-LEVEL existe para impedir, só que um nível acima.
 *
 * `faltantes` é DELIBERADAMENTE truncado: identifica o problema sem despejar
 * o Card Set inteiro em log.
 */
export class IncompleteCollectorOrderSetError extends Error {
  readonly faltantes: string[];
  readonly totalFaltantes: number;
  constructor(motivo: string, faltantes: string[], totalFaltantes = faltantes.length) {
    const amostra = faltantes.slice(0, MAX_FALTANTES_NO_ERRO);
    super(
      `COLLECTOR_ORDER_CONJUNTO_INCOMPLETO: ${motivo}` +
        (totalFaltantes > 0
          ? ` — ${totalFaltantes} ausente(s), amostra: ${amostra.map((t) => JSON.stringify(t)).join(", ")}` +
            (totalFaltantes > amostra.length ? ` (+${totalFaltantes - amostra.length})` : "")
          : ""),
    );
    this.name = "IncompleteCollectorOrderSetError";
    this.faltantes = amostra;
    this.totalFaltantes = totalFaltantes;
  }
}

/** Teto da amostra no erro — diagnóstico sem despejar o Set inteiro. */
const MAX_FALTANTES_NO_ERRO = 10;

// ---------------------------------------------------------------------------
// Exceções editoriais nomeadas (decisão de Fabrício, 2026-09-10)
// ---------------------------------------------------------------------------

/**
 * HGSS1–HGSS4: cada Coleção traz a sequência numérica normal mais UMA Alph
 * Lithograph identificada por extenso. Decisão editorial: numérica primeiro,
 * litógrafo por último.
 *
 * HARDENING 1 (2026-09-10), versão final. A exceção NÃO é "Set na lista × token
 * na lista" — é uma associação NOMINAL EXATA, um token por Card Set:
 *
 *   HGSS1 → ONE    HGSS2 → TWO    HGSS3 → THREE    HGSS4 → FOUR
 *
 * Consequências, todas fail closed:
 *   - `TWO` em HGSS1 não é o token esperado daquele Set ⇒ cai no caminho
 *     genérico ⇒ UnsupportedCollectorNumberError;
 *   - `ONE` em qualquer Set fora dos quatro ⇒ idem;
 *   - o token esperado aparecendo duas vezes no mesmo Set ⇒
 *     AmbiguousCollectorKeyError (duas cartas disputando a mesma posição);
 *   - qualquer OUTRO token alfabético num Set HGSS ⇒ caminho genérico ⇒ erro.
 *
 * Nenhuma heurística global baseada só no texto do identificador.
 */
const ALPH_LITHOGRAPH_BY_SET = new Map<string, string>([
  ["HGSS1", "ONE"],
  ["HGSS2", "TWO"],
  ["HGSS3", "THREE"],
  ["HGSS4", "FOUR"],
]);

/**
 * EXU (Unown collection): ordem editorial congelada `A..Z → 1..26`,
 * `! → 27`, `? → 28`.
 *
 * CONGELADA MAS NÃO LIGADA. A TCGdex devolve `%3F` (o `?` percent-encoded) e
 * `!`, e os dois violam `ck_card_collector_number_format`
 * (`^[A-Za-z0-9][A-Za-z0-9._-]*$`, database/schema/140). Converter para
 * `EXCLAMATION`/`QUESTION` descaracterizaria o identificador oficial — foi
 * explicitamente recusado. Enquanto G6 não propuser a menor correção
 * estrutural segura, buildSetCollectorOrderPlan() devolve o plano com
 * `blockedReason` preenchido e nenhum caller pode persistir o Set.
 */
const EXU_FROZEN_ORDER: readonly string[] = [
  "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M",
  "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z",
  "!", "?",
];

const EXU_BLOCKED_REASON =
  "EXU_COLLECTOR_NUMBER_CONSTRAINT: os identificadores oficiais '!' e '?' violam " +
  "ck_card_collector_number_format; ordem editorial congelada (A..Z, !, ?), " +
  "persistência pendente de G6.";

/** `%3F` é como a TCGdex expõe o `?` do EXU. Decodificado só aqui. */
function decodeExuToken(raw: string): string {
  return raw === "%3F" ? "?" : raw;
}

// ---------------------------------------------------------------------------
// Chave natural
// ---------------------------------------------------------------------------

type NaturalKey = {
  raw: string;
  /** 0 = começa com dígito (corrida principal); 1 = começa com letra (subset/promo). */
  grp: 0 | 1;
  pref: string;
  num: number;
  suf: string;
};

const RE_NUM = /^([0-9]+)$/;
const RE_NUM_SUF = /^([0-9]+)([A-Za-z]+)$/;
const RE_PREF_NUM = /^([A-Za-z]+)([0-9]+)$/;
const RE_PREF_NUM_SUF = /^([A-Za-z]+)([0-9]+)([A-Za-z]+)$/;

/**
 * Padding é irrelevante para a chave: `"088"` e `"88"` produzem `num = 88`.
 * Por isso o plano pode ser construído tanto a partir de `localId` (fluxo de
 * importação) quanto de `collector_number` já preenchido com zeros (fluxo de
 * reconciliação) — mesmo resultado.
 */
function parseNaturalKey(raw: string): NaturalKey {
  let m = RE_NUM.exec(raw);
  if (m) return { raw, grp: 0, pref: "", num: Number(m[1]), suf: "" };

  m = RE_NUM_SUF.exec(raw);
  if (m) return { raw, grp: 0, pref: "", num: Number(m[1]), suf: m[2] };

  m = RE_PREF_NUM.exec(raw);
  if (m) return { raw, grp: 1, pref: m[1], num: Number(m[2]), suf: "" };

  m = RE_PREF_NUM_SUF.exec(raw);
  if (m) return { raw, grp: 1, pref: m[1], num: Number(m[2]), suf: m[3] };

  throw new UnsupportedCollectorNumberError(raw);
}

/** Comparação por código de ponto, nunca localeCompare — determinismo acima de idioma. */
function cmpText(a: string, b: string): number {
  return a < b ? -1 : a > b ? 1 : 0;
}

/**
 * Forma canônica da chave — o que define "mesma posição editorial".
 * Prefixo e sufixo em caixa alta: `BW1`/`bw1` e `88a`/`88A` são o MESMO
 * identificador editorial, então coexistirem no mesmo Set é ambiguidade, não
 * duas posições. Zero-padding já é irrelevante porque `num` é inteiro.
 */
function chaveCanonica(k: NaturalKey): string {
  return `${k.grp}|${k.pref.toUpperCase()}|${k.num}|${k.suf.toUpperCase()}`;
}

/** Fail closed antes de qualquer atribuição de ordem (HARDENING 2). */
function assertChavesNaoAmbiguas(chaves: NaturalKey[]): void {
  const porCanonica = new Map<string, string[]>();
  for (const k of chaves) {
    const c = chaveCanonica(k);
    const lista = porCanonica.get(c);
    if (lista) lista.push(k.raw);
    else porCanonica.set(c, [k.raw]);
  }
  for (const [c, tokens] of porCanonica) {
    if (tokens.length > 1) throw new AmbiguousCollectorKeyError(c, tokens);
  }
}

/**
 * `suf` vazio vem antes de qualquer sufixo: `88 < 88a < 88b < 89`
 * (regra MMKYU, 2026-09-10). Sem carta-base o mesmo comparador entrega
 * `50a < 50b` — caso real de ECARD2, onde `50`, `74`, `95` e `103` não
 * existem, só os pares `a`/`b`.
 */
function compareNaturalKey(a: NaturalKey, b: NaturalKey): number {
  if (a.grp !== b.grp) return a.grp - b.grp;
  const p = cmpText(a.pref.toUpperCase(), b.pref.toUpperCase());
  if (p !== 0) return p;
  if (a.num !== b.num) return a.num - b.num;
  const s = cmpText(a.suf.toUpperCase(), b.suf.toUpperCase());
  if (s !== 0) return s;
  // Inalcançável depois de assertChavesNaoAmbiguas() — mantido apenas para
  // garantir que o sort permaneça total e determinístico em qualquer caminho.
  return cmpText(a.raw, b.raw);
}

// ---------------------------------------------------------------------------
// Plano do Set
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Guard de cobertura — pré-condição congelada em G0 (BLOCKER L1)
// ---------------------------------------------------------------------------

export type IncomingCollectorItem = {
  /** Identificador cru da fonte (`localId` da TCGdex). */
  localId: string;
  /** `collector_total` do Set no contexto daquela linha; pode ser null. */
  collectorTotal: number | null;
};

/**
 * Prova que TODA Card já persistida no Card Set está representada no conjunto
 * que o fluxo vai usar para montar o plano. Fail closed.
 *
 * Comparação SEMPRE por collector_number canônico
 * (`padCollectorNumber(localId, collectorTotal)`), nunca por `localId` cru:
 * persistido `"001"` e recebido `"1"` (total 185) são a MESMA Card, e o guard
 * tem de reconhecer isso como cobertura — não criar duas posições.
 *
 * Deliberadamente NÃO faz união de tokens. Ele só verifica cobertura; quem
 * monta o plano continua sendo o conjunto recebido pelo fluxo, com os
 * identificadores na forma em que o fluxo os conhece. Unir "persistidos + crus"
 * reintroduziria o par `"001"`/`"1"` como duas entradas distintas — exatamente
 * o erro que este guard existe para detectar.
 *
 * Usado por import-catalog-cards e revalidate-catalog-import-rows com a MESMA
 * regra, antes de qualquer chamada a buildSetCollectorOrderPlan().
 */
export function assertPersistedCardsCovered(input: {
  incoming: IncomingCollectorItem[];
  /** Chaves de `existingCardsByCollectorNumber` (já são collector_number canônico). */
  persistedCollectorNumbers: Iterable<string>;
  /** Só para a mensagem de erro. */
  setCode?: string | null;
}): void {
  const recebidos = new Set<string>();
  for (const item of input.incoming ?? []) {
    recebidos.add(padCollectorNumber(String(item.localId), item.collectorTotal));
  }

  const faltantes: string[] = [];
  for (const persistido of input.persistedCollectorNumbers ?? []) {
    if (!recebidos.has(persistido)) faltantes.push(persistido);
  }

  if (faltantes.length > 0) {
    faltantes.sort();
    const alvo = input.setCode ? ` no Card Set ${input.setCode}` : "";
    throw new IncompleteCollectorOrderSetError(
      `existem Cards persistidas${alvo} que nao aparecem no conjunto recebido pelo fluxo; ` +
        "o plano SET-LEVEL exige o conjunto completo (persistidas + linhas do job, inclusive FAILED)",
      faltantes,
    );
  }
}

export type BuildSetCollectorOrderPlanInput = {
  /**
   * Conjunto COMPLETO do Card Set — todas as cartas que existirão nele ao
   * final, nunca um subconjunto. Ordem do array é irrelevante por desenho.
   */
  tokens: string[];
  /** `card_set.code`, usado só para reconhecer as exceções editoriais nomeadas. */
  setCode?: string | null;
};

/**
 * Decide o modo do Set e devolve `collector_order` para cada identificador.
 *
 * Modo A (`NUMERIC_PRESERVED`) — todo identificador casa `^[0-9]+$`:
 *   `collector_order = valor numérico`. Gaps legítimos são PRESERVADOS, nunca
 *   densificados. Caso real: `TK-SM-L` tem 18 cartas com ordens
 *   `1,4,5,11,...,30` num Set que declara 30 — densificar destruiria a
 *   correspondência com o número impresso. Confirmado contra a fonte
 *   (`/v2/en/sets/tk-sm-l` devolve exatamente `1, 4, 5, 11, ...`).
 *
 * Modo B (`ORDINAL_DERIVED`) — há pelo menos um identificador alfanumérico:
 *   ordena o conjunto completo pela chave natural e atribui `1..N` denso.
 *   Aqui o valor é POSIÇÃO, não número — que é exatamente o que
 *   `COMMENT ON COLUMN public.card.collector_order` já declara.
 *
 * Nenhum caminho depende da ordem em que `tokens` chega.
 */
export function buildSetCollectorOrderPlan(
  input: BuildSetCollectorOrderPlanInput,
): SetCollectorOrderPlan {
  const tokens = input.tokens ?? [];
  const setCode = (input.setCode ?? "").toUpperCase();

  if (tokens.length === 0) {
    return { mode: "ORDINAL_DERIVED", exception: null, orderByToken: new Map(), blockedReason: null };
  }

  // --- Exceção nomeada: EXU (congelada, bloqueada para escrita) -------------
  if (setCode === "EXU") {
    const orderByToken = new Map<string, number>();
    for (const raw of tokens) {
      const decoded = decodeExuToken(raw);
      const idx = EXU_FROZEN_ORDER.indexOf(decoded);
      if (idx < 0) throw new UnsupportedCollectorNumberError(raw);
      orderByToken.set(raw, idx + 1);
    }
    return {
      mode: "ORDINAL_DERIVED",
      exception: "EXU_UNOWN",
      orderByToken,
      blockedReason: EXU_BLOCKED_REASON,
    };
  }

  // --- Exceção nomeada: HGSS1-4 (Alph Lithograph por último) ----------------
  // Associação nominal exata Set → token (HARDENING 1). Qualquer outro token,
  // em qualquer outro Set, segue o caminho genérico e falha fechado.
  const tokenEsperado = ALPH_LITHOGRAPH_BY_SET.get(setCode) ?? null;
  const lithographs = tokenEsperado
    ? tokens.filter((t) => t.toUpperCase() === tokenEsperado)
    : [];
  if (lithographs.length > 1) {
    throw new AmbiguousCollectorKeyError(`ALPH_LITHOGRAPH|${setCode}|${tokenEsperado}`, lithographs);
  }
  const hasLithograph = lithographs.length > 0;
  const regulares = hasLithograph
    ? tokens.filter((t) => t.toUpperCase() !== tokenEsperado)
    : tokens;

  // --- Decisão do modo, sobre o conjunto completo (sem os litógrafos) -------
  const todosNumericos = regulares.every((t) => RE_NUM.test(t));
  const mode: CollectorOrderMode = todosNumericos ? "NUMERIC_PRESERVED" : "ORDINAL_DERIVED";

  const orderByToken = new Map<string, number>();

  if (mode === "NUMERIC_PRESERVED") {
    const vistos = new Set<number>();
    for (const t of regulares) {
      const n = Number(t);
      if (!Number.isInteger(n) || n <= 0) {
        throw new InvalidNumericSetError(`identificador ${JSON.stringify(t)} nao e um inteiro positivo`);
      }
      if (vistos.has(n)) {
        throw new InvalidNumericSetError(`valor numerico ${n} aparece mais de uma vez no Set`);
      }
      vistos.add(n);
      orderByToken.set(t, n);
    }
    // Alph Lithograph por último: continua a partir do maior número em uso,
    // nunca reaproveita um valor existente.
    let proximo = regulares.length > 0 ? Math.max(...vistos) + 1 : 1;
    for (const t of lithographs.slice().sort(cmpText)) {
      orderByToken.set(t, proximo);
      proximo += 1;
    }
  } else {
    const chaves = regulares.map(parseNaturalKey);
    assertChavesNaoAmbiguas(chaves);
    chaves.sort(compareNaturalKey);
    chaves.forEach((k, i) => orderByToken.set(k.raw, i + 1));
    let proximo = chaves.length + 1;
    for (const t of lithographs.slice().sort(cmpText)) {
      orderByToken.set(t, proximo);
      proximo += 1;
    }
  }

  // Completude da exceção HGSS (BLOCKER L1). O token esperado tem de existir
  // EXATAMENTE UMA vez: duplicata já falhou acima; ausência falha aqui.
  // Deliberadamente no FIM — assim um token errado (ex.: `TWO` em HGSS1)
  // continua morrendo antes, em parseNaturalKey, como
  // UnsupportedCollectorNumberError, que é o contrato já aprovado.
  if (tokenEsperado && !hasLithograph) {
    throw new IncompleteCollectorOrderSetError(
      `o Card Set ${setCode} exige a Alph Lithograph ${JSON.stringify(tokenEsperado)}, ausente no conjunto recebido`,
      [tokenEsperado],
    );
  }

  return {
    mode,
    exception: hasLithograph ? "HGSS_ALPH_LITHOGRAPH" : null,
    orderByToken,
    blockedReason: null,
  };
}

/**
 * Leitura do plano. Erro explícito quando o identificador não estava no
 * conjunto usado para construí-lo — sinal de que o caller montou o plano a
 * partir de um subconjunto, que é justamente o erro que este módulo existe
 * para impedir.
 */
export function collectorOrderFor(plan: SetCollectorOrderPlan, token: string): number {
  const ord = plan.orderByToken.get(token);
  if (ord === undefined) {
    throw new UnsupportedCollectorNumberError(token);
  }
  return ord;
}

/** Só para inspeção/documentação — a ordem congelada do EXU. */
export const EXU_EDITORIAL_ORDER: readonly string[] = EXU_FROZEN_ORDER;
