// Project Mimikyu — Edge Function: import-card-assets
// TCGdex Service — CONFIRMADO DEPLOYADO pela primeira vez no Sprint B3.3, junto
// com index.ts v1.3.0 e services/database.ts (ver docs/06-pipeline-importacao.md,
// "Sprint B3.3"). Único ponto do projeto que faz `fetch()` contra a API da
// TCGdex — nenhuma outra camada deve chamar a TCGdex diretamente (ver
// `adr/ADR-017-two-function-import-pipeline.md`).
//
// Substitui as versões anteriores baseadas em uma função solta
// (`findTcgDexSet`, depois `getSet` — nenhuma delas chegou a ser deployada).
// Revisado tecnicamente no Sprint B3.1: URL base extraída para uma constante
// (`BASE_URL`) e retornos tipados como `Promise<Record<string, unknown>>` em
// vez de `Promise<unknown>`.
//
// v2.5.0 (2026-07-24, retomada da implementação): bug real encontrado por
// `deno check` (primeira vez que essa validação da Convenção #7 realmente
// rodou contra este arquivo) — `getSet()` retornava `Promise<Record<string,
// unknown>>`, tipo genérico demais: toda propriedade lida desse objeto
// (`set.cards`, e cada `tcgCard` dentro do lote em index.ts) virava `unknown`
// para o TypeScript, mesmo funcionando normalmente em runtime. Corrigido
// introduzindo `TcgdexCardSummary`/`TcgdexSetDetail`, com os campos já usados
// por `index.ts` (`id`, `localId`, `name`, `image`) e `cardCount.total`
// (usado durante a pesquisa manual de MEE/MEP, ver docs/05-modelo-de-dados.md,
// seção Set/Card Set). Nenhuma mudança de lógica ou de chamada HTTP —
// apenas tipagem. `getCardsBySet`/`getCard` permanecem com o retorno genérico
// anterior, por não serem usados hoje por nenhuma Edge Function (fora de
// escopo desta correção).
//
// Pendência conhecida, ainda não resolvida: o endpoint usado por
// `getCardsBySet` (`/sets/{id}/cards`) foi assumido a partir da documentação
// da TCGdex, mas nunca foi confirmado por uma chamada real — diferente de
// `getSet`, cuja chamada real já está confirmada desde o Sprint B3.3.
//
// ---------------------------------------------------------------------------
// v2.10.0 (2026-09-11, TCGDEX-SET-FETCH-RESILIENCE-01) — RESILIÊNCIA NO GET
// DE METADATA. Blocker real, medido em produção durante o mass APPLY de XY:
//
//   RUN-20260911-00003948 (XY7/en) -> FAILED, error_summary "tls handshake eof"
//   RUN-20260911-00004081 (XY7/en) -> FAILED, "Connection reset by peer
//                                      (os error 104)"
//
// Nos dois casos `requested_count` ficou em 0: a run morreu ANTES de calcular
// o lote, porque `tcgdex.getSet()` é a primeira chamada de rede do fluxo. O
// mesmo endpoint respondia HTTP 200 quando consultado da máquina local no
// mesmo intervalo — ou seja, falha transitória de rede/TLS entre a plataforma
// Edge e a TCGdex, não indisponibilidade da API.
//
// Assimetria que causou o blocker: `services/storage.ts` já tinha timeout
// explícito (`IMAGE_DOWNLOAD_TIMEOUT_MS`) e o chamador em `index.ts` já tinha
// retry classificado por tipo de erro (NETWORK/TIMEOUT/429/5xx) para o
// DOWNLOAD DE IMAGEM — mas o GET de metadata, que roda antes e é
// pré-requisito de tudo, era um `fetch()` cru: sem timeout, sem retry. Uma
// única falha transitória de 1 segundo derrubava a run inteira de um Card Set.
//
// Corrigido aqui, com paridade deliberada ao contrato que já existe para
// imagem:
//   - até 3 tentativas por requisição;
//   - retry SOMENTE para erro de rede, timeout, HTTP 429 e HTTP 5xx;
//   - 404 e demais 4xx são permanentes — falham na primeira, sem retry;
//   - backoff curto entre tentativas, honrando `Retry-After` quando presente;
//   - timeout explícito por tentativa (`AbortController`).
//
// Contrato externo INALTERADO: `TcgdexClient`, `getSet`, `getCardsBySet` e
// `getCard` mantêm assinatura e tipos de retorno. Nenhuma mudança em Storage,
// banco, schema ou autenticação.
//
// Orçamento de tempo: 3 tentativas × 15s + ~2s de backoff = ~47s no pior caso
// absoluto (todas as tentativas pendurando até o timeout). Deliberadamente
// abaixo do teto de execução da plataforma (~150s), para que uma falha de
// metadata ainda deixe orçamento para o laço de imagens quando a última
// tentativa tem sucesso.
// ---------------------------------------------------------------------------

export type TcgdexCardSummary = {
  id: string;
  localId: string;
  name: string;
  image?: string;
};

export type TcgdexSetDetail = {
  id: string;
  name: string;
  cardCount?: {
    total: number;
    official?: number;
  };
  cards: TcgdexCardSummary[];
};

/** Mesma taxonomia de `ImageDownloadErrorCode` (services/storage.ts). */
export type TcgdexRequestErrorCode =
  | "TIMEOUT"
  | "NETWORK"
  | "HTTP_429"
  | "HTTP_5XX"
  | "HTTP_404"
  | "HTTP_OTHER"
  | "INVALID_JSON";

export class TcgdexRequestError extends Error {
  constructor(
    public readonly code: TcgdexRequestErrorCode,
    message: string,
    public readonly url: string,
    public readonly status: number | null,
    public readonly retriable: boolean,
    public readonly attempts: number,
  ) {
    super(message);
    this.name = "TcgdexRequestError";
  }
}

/** Teto de tentativas por requisição de metadata. */
export const TCGDEX_MAX_ATTEMPTS = 3;
/** Timeout por tentativa. Metadata é leve; 15s já é folgado. */
export const TCGDEX_REQUEST_TIMEOUT_MS = 15_000;
/** Backoff entre tentativas, em ms. Índice = tentativa que acabou de falhar. */
export const TCGDEX_BACKOFF_MS = [500, 1_500];
/** Teto do `Retry-After` honrado — curto de propósito, o orçamento é finito. */
export const TCGDEX_MAX_RETRY_AFTER_MS = 5_000;

/**
 * Espera derivada do cabeçalho `Retry-After` (segundos ou data HTTP), com
 * fallback no backoff fixo da tentativa. Sempre limitada por
 * `TCGDEX_MAX_RETRY_AFTER_MS`.
 */
export function calcularEsperaTcgdex(
  retryAfterHeader: string | null,
  padraoMs: number,
): number {
  if (!retryAfterHeader) return padraoMs;

  const segundos = Number(String(retryAfterHeader).trim());
  if (Number.isFinite(segundos) && segundos >= 0) {
    return Math.min(segundos * 1_000, TCGDEX_MAX_RETRY_AFTER_MS);
  }

  const data = Date.parse(String(retryAfterHeader));
  if (Number.isFinite(data)) {
    return Math.min(Math.max(data - Date.now(), 0), TCGDEX_MAX_RETRY_AFTER_MS);
  }

  return padraoMs;
}

/**
 * Classifica um status HTTP. Só 429 e 5xx são transitórios: 404 significa que
 * o Set/Card não existe naquele idioma, e repetir nunca muda a resposta.
 */
export function classificarStatusTcgdex(
  status: number,
): { code: TcgdexRequestErrorCode; retriable: boolean } {
  if (status === 429) return { code: "HTTP_429", retriable: true };
  if (status >= 500) return { code: "HTTP_5XX", retriable: true };
  if (status === 404) return { code: "HTTP_404", retriable: false };
  return { code: "HTTP_OTHER", retriable: false };
}

// ---------------------------------------------------------------------------
// v2.11.0 (2026-09-11, BOOTSTRAP-METADATA-PASSTHROUGH-01) — validação do
// `set_snapshot` opcional.
//
// Motivo real: `api.tcgdex.net` está inalcançável a partir da plataforma Edge
// (TLS EOF, connection reset, e por fim v2.10 esgotando as 3 tentativas em
// ~47s), enquanto o MESMO endpoint responde 200 da máquina local e
// `assets.tcgdex.net` — host distinto, usado pelo download de imagem —
// continua alcançável (96 imagens de XY7/en baixadas com sucesso no mesmo
// dia). O script de bootstrap já obtém esse metadata no preflight; o snapshot
// evita o segundo GET redundante.
//
// FAIL CLOSED por princípio: este payload vem do cliente. Ele nunca cria
// Card, nunca traz identificador interno, e a única parte com efeito externo
// (`image`, que determina de onde um binário é baixado para o Storage do
// projeto) é restringida por origem exata.
// ---------------------------------------------------------------------------

/** Origem única autorizada para `image`. Comparação por `URL`, nunca por string. */
export const TCGDEX_ASSET_ORIGIN = "https://assets.tcgdex.net";
/** Teto de cardinalidade do snapshot. */
export const SET_SNAPSHOT_MAX_CARDS = 500;

const SNAPSHOT_TOP_KEYS = ["id", "cards"] as const;
const SNAPSHOT_CARD_KEYS = ["id", "localId", "name", "image"] as const;

/**
 * Tetos de tamanho (CORRECTION-01). Folgados o bastante para qualquer valor
 * real da TCGdex — o maior `localId` observado no corpus tem 9 caracteres
 * (`SWSH12.5GG`-style), nomes de carta raramente passam de 60 — e apertados
 * o bastante para que um payload hostil não consuma memória da Edge.
 */
export const SNAPSHOT_MAX_LEN = {
  setId: 64,
  cardId: 128,
  localId: 32,
  name: 256,
  image: 512,
} as const;

function ehObjetoSimples(v: unknown): v is Record<string, unknown> {
  return typeof v === "object" && v !== null && !Array.isArray(v);
}

function exigirStringNaoVazia(v: unknown, campo: string, maxLen: number): string {
  if (typeof v !== "string" || v.trim() === "") {
    throw new Error(`SET_SNAPSHOT_INVALID: ${campo} deve ser string não vazia.`);
  }
  if (v.length > maxLen) {
    throw new Error(
      `SET_SNAPSHOT_INVALID: ${campo} excede o teto de ${maxLen} caracteres (recebido ${v.length}).`,
    );
  }
  return v;
}

/**
 * SSRF hardening: `startsWith` é insuficiente — "https://assets.tcgdex.net.evil.com/x"
 * passaria. Só o parser de URL separa host de prefixo textual.
 */
function exigirImagemDeOrigemAutorizada(valor: string, localId: string): string {
  let parsed: URL;
  try {
    parsed = new URL(valor);
  } catch {
    throw new Error(`SET_SNAPSHOT_INVALID: image de "${localId}" não é uma URL válida.`);
  }
  // Credenciais embutidas ("https://user:pass@assets.tcgdex.net/...") preservam
  // origin e hostname, mas alteram o request enviado. Exigidas vazias.
  if (parsed.username !== "" || parsed.password !== "") {
    throw new Error(
      `SET_SNAPSHOT_INVALID: image de "${localId}" não pode conter credenciais embutidas na URL.`,
    );
  }
  if (
    parsed.protocol !== "https:" ||
    parsed.hostname !== "assets.tcgdex.net" ||
    parsed.origin !== TCGDEX_ASSET_ORIGIN
  ) {
    throw new Error(
      `SET_SNAPSHOT_INVALID: image de "${localId}" tem origem não autorizada (${parsed.origin}). ` +
      `Única origem aceita: ${TCGDEX_ASSET_ORIGIN}.`,
    );
  }
  return valor;
}

/**
 * Valida e converte o `set_snapshot` recebido no corpo da requisição.
 *
 * `chaveFn` é injetada (em produção, `chaveColecionador` de services/
 * database.ts) para que a detecção de duplicidade use exatamente a mesma
 * normalização do matching real — sem reimplementar a regra aqui.
 */
export function validarSetSnapshot(
  raw: unknown,
  externalSetIdEsperado: string,
  chaveFn: (v: string) => string,
): TcgdexSetDetail {
  if (!ehObjetoSimples(raw)) {
    throw new Error("SET_SNAPSHOT_INVALID: payload deve ser um objeto.");
  }

  const chavesTopo = Object.keys(raw);
  const extrasTopo = chavesTopo.filter((k) => !SNAPSHOT_TOP_KEYS.includes(k as never));
  if (extrasTopo.length > 0) {
    throw new Error(`SET_SNAPSHOT_INVALID: chave(s) não autorizada(s) no topo: ${extrasTopo.join(", ")}.`);
  }

  const id = exigirStringNaoVazia(raw.id, "id", SNAPSHOT_MAX_LEN.setId);
  if (id !== externalSetIdEsperado) {
    throw new Error(
      `SET_SNAPSHOT_INVALID: id "${id}" diverge do external_set_id da run ("${externalSetIdEsperado}").`,
    );
  }

  if (!Array.isArray(raw.cards)) {
    throw new Error("SET_SNAPSHOT_INVALID: cards deve ser um array.");
  }
  if (raw.cards.length < 1 || raw.cards.length > SET_SNAPSHOT_MAX_CARDS) {
    throw new Error(
      `SET_SNAPSHOT_INVALID: cards deve ter entre 1 e ${SET_SNAPSHOT_MAX_CARDS} itens (recebido ${raw.cards.length}).`,
    );
  }

  const vistos = new Map<string, string>();
  const cards: TcgdexCardSummary[] = [];

  for (const item of raw.cards) {
    if (!ehObjetoSimples(item)) {
      throw new Error("SET_SNAPSHOT_INVALID: cada card deve ser um objeto.");
    }

    const extras = Object.keys(item).filter((k) => !SNAPSHOT_CARD_KEYS.includes(k as never));
    if (extras.length > 0) {
      throw new Error(`SET_SNAPSHOT_INVALID: chave(s) não autorizada(s) em card: ${extras.join(", ")}.`);
    }

    const cardId = exigirStringNaoVazia(item.id, "card.id", SNAPSHOT_MAX_LEN.cardId);
    const localId = exigirStringNaoVazia(item.localId, "card.localId", SNAPSHOT_MAX_LEN.localId);
    const name = exigirStringNaoVazia(item.name, "card.name", SNAPSHOT_MAX_LEN.name);

    let image: string | undefined;
    if (item.image !== undefined) {
      image = exigirImagemDeOrigemAutorizada(
        exigirStringNaoVazia(item.image, "card.image", SNAPSHOT_MAX_LEN.image),
        localId,
      );
    }

    // Duplicidade pela MESMA chave do matching real: dois localId que
    // normalizam igual tornariam a resolução ambígua.
    const chave = chaveFn(localId);
    if (vistos.has(chave)) {
      throw new Error(
        `SET_SNAPSHOT_INVALID: localId "${vistos.get(chave)}" e "${localId}" normalizam para "${chave}".`,
      );
    }
    vistos.set(chave, localId);

    cards.push({ id: cardId, localId, name, ...(image !== undefined ? { image } : {}) });
  }

  return { id, name: id, cards };
}

// ---------------------------------------------------------------------------
// SWSH-SUBSET-ASSET-ALIAS-RECOVERY-01 (2026-09-11)
//
// A TCGdex publica subsets cuja IDENTIDADE DE CATALOGO nao coincide com o
// DIRETORIO FISICO dos assets. Sao duas dimensoes independentes, e aqui
// tratamos SOMENTE a segunda.
//
// Evidencia medida (nao suposta):
//   Gate 0 — metadata EN dos 6 subsets = 200. Os IDs candidatos da issue
//     publica (swsh9.5tg, swsh10.5tg, swsh11.5tg, swsh12.5tg) = 404.
//     Portanto NAO ha correcao de external_set_id a fazer: o ID esta certo.
//   Piloto CDN — EN `high.webp` = 200 nos 6, sob o diretorio do Set-PAI.
//   Piloto CDN — PT-BR 404/404 nos 6 => pt-BR fica FORA desta rodada.
//   LIVE — os 6 somam 312 Cards com 0 Assets EN.
//
// O mapa carrega APENAS o par de diretorios. Nao carrega URL, origem, serie,
// idioma nem localId: tudo isso continua vindo da propria URL da fonte, que ja
// passou por `validarSetSnapshot` (origem exata, sem credenciais, com tetos).
//
// Garantia de escopo: o alias NAO altera external_set_id, external_card_id,
// source_number/localId, card_asset.source_reference, nem a identidade logica
// do Card Set no MMKYU. Ele troca UM segmento de path.
// ---------------------------------------------------------------------------

/** external_set_id (catalogo) -> diretorio fisico de assets na CDN. */
export const ALIAS_DIRETORIO_ASSET: Readonly<Record<string, string>> = Object.freeze({
  "swsh4.5sv": "swsh4.5",
  "swsh12.5gg": "swsh12.5",
  "swsh9tg": "swsh9",
  "swsh10tg": "swsh10",
  "swsh11tg": "swsh11",
  "swsh12tg": "swsh12",
});

/**
 * Idiomas autorizados a receber alias. Deliberadamente so `en`: o piloto
 * provou 404/404 em pt para os 6, e aplicar o alias em pt trocaria um 404 por
 * outro 404 — sem ganho e com ruido no diagnostico.
 */
export const IDIOMAS_COM_ALIAS_DE_DIRETORIO: readonly string[] = Object.freeze(["en"]);

export type ResolucaoBaseImageUrl = {
  url: string;
  aliasAplicado: boolean;
  /** Preenchido so quando houve troca — para log e para o harness. */
  diretorioOriginal?: string;
  diretorioAliasado?: string;
};

/**
 * Resolve a URL-base da imagem aplicando o alias de diretorio quando devido.
 *
 * Invariantes (todas cobertas pelo harness):
 *  - origem, idioma e serie preservados — a URL e reconstruida via `URL`,
 *    nunca por concatenacao de string;
 *  - `localId` preservado LITERALMENTE (ultimo segmento, jamais tocado):
 *    SV001, GG01, TG01 seguem exatos, sem normalizacao numerica;
 *  - troca so ocorre se o segmento do Set for EXATAMENTE a chave do alias —
 *    se a fonte ja publicar o diretorio correto, e no-op (idempotente);
 *  - Set fora do mapa, idioma fora da lista, ou URL invalida => no-op
 *    byte-equivalente ao comportamento atual.
 */
export function resolverBaseImageUrlComAlias(
  baseImageUrl: string | null | undefined,
  externalSetId: string | null | undefined,
  languageCode: string | null | undefined,
): ResolucaoBaseImageUrl {
  const original = typeof baseImageUrl === "string" ? baseImageUrl : "";
  const semAlias: ResolucaoBaseImageUrl = { url: original, aliasAplicado: false };

  if (original === "") return semAlias;
  if (typeof externalSetId !== "string" || externalSetId === "") return semAlias;
  if (typeof languageCode !== "string") return semAlias;
  if (!IDIOMAS_COM_ALIAS_DE_DIRETORIO.includes(languageCode)) return semAlias;

  const chave = externalSetId.toLowerCase();
  const destino = ALIAS_DIRETORIO_ASSET[chave];
  if (!destino) return semAlias;

  let parsed: URL;
  try {
    parsed = new URL(original);
  } catch {
    return semAlias; // nao-URL nunca vira URL aqui; fail closed.
  }

  // /{lang}/{serie}/{setDir}/{localId}  =>  split gera ["", lang, serie, setDir, localId]
  const segmentos = parsed.pathname.split("/");
  const iSetDir = segmentos.length - 2; // penultimo; o ultimo e o localId
  if (iSetDir < 1) return semAlias;

  const diretorioOriginal = segmentos[iSetDir];
  if (diretorioOriginal.toLowerCase() !== chave) return semAlias;

  segmentos[iSetDir] = destino;
  parsed.pathname = segmentos.join("/");

  return {
    url: parsed.toString(),
    aliasAplicado: true,
    diretorioOriginal,
    diretorioAliasado: destino,
  };
}

// ---------------------------------------------------------------------------
// CORRECTION-02 (2026-09-11) — DERIVACAO RESTRITA quando a fonte NAO publica
// `image`.
//
// Fato novo, medido:
//   GET /v2/en/sets/swsh4.5sv          -> a carta SV001 EXISTE, `image` AUSENTE
//   GET /v2/en/cards/swsh4.5sv-SV001   -> `image` AUSENTE tambem
//   CDN direto                          -> /en/swsh/swsh4.5/SV001/high.webp = 200
//
// Ou seja: o alias de diretorio (correto, v44) e NECESSARIO mas INSUFICIENTE —
// nao ha URL da fonte para aliasar. A fonte da identidade (id/localId) e nao
// da a imagem.
//
// A derivacao e uma EXCECAO estreita, nao uma regra. Ela so existe porque:
//   (a) os 6 subsets estao numa allowlist fechada e ja COMPROVADA na CDN;
//   (b) o idioma e `en` (pt-BR deu 404/404 no piloto);
//   (c) o localId casa com o formato literal daquele subset.
//
// E — a regra que evita que uma hipotese vire "verdade" no banco — uma URL
// DERIVED_ALLOWLIST NAO e persistida em `image_source_url` antes de prova
// positiva (download bem-sucedido). Ver `index.ts`: na sincronizacao inicial
// DERIVED grava `null`; a promocao so acontece DEPOIS do download.
//
// SSRF: a origem e a serie sao CONSTANTES deste modulo. Nada de host, esquema
// ou path vem do cliente. O unico dado externo que entra na URL derivada e o
// `localId`, e ele passa por regex fechada (sem `/`, `.`, `%`, `:` ou `\`),
// alem de re-verificacao pos-`new URL()`.
// ---------------------------------------------------------------------------

/** Serie fisica dos 6 subsets. CONSTANTE — nunca vem do cliente. */
export const SERIE_ASSET_SWSH = "swsh";

/** Idioma unico autorizado a derivar. Mesma restricao do alias. */
export const IDIOMA_DERIVACAO = "en";

/**
 * Formato LITERAL do localId por subset. Fechado de proposito: alem de validar
 * o dominio, elimina por construcao qualquer path traversal ou encoding.
 */
export const FORMATO_LOCAL_ID_SUBSET: Readonly<Record<string, RegExp>> = Object.freeze({
  "swsh4.5sv": /^SV\d{3}$/,
  "swsh12.5gg": /^GG\d{2}$/,
  "swsh9tg": /^TG\d{2}$/,
  "swsh10tg": /^TG\d{2}$/,
  "swsh11tg": /^TG\d{2}$/,
  "swsh12tg": /^TG\d{2}$/,
});

export const ORIGEM_RESOLUCAO = {
  /** URL veio da fonte (com ou sem alias de diretorio aplicado). */
  SOURCE: "SOURCE",
  /** URL construida a partir da allowlist — HIPOTESE, nao identidade. */
  DERIVED_ALLOWLIST: "DERIVED_ALLOWLIST",
  /** Sem URL utilizavel. */
  NONE: "NONE",
} as const;

export type OrigemResolucao = typeof ORIGEM_RESOLUCAO[keyof typeof ORIGEM_RESOLUCAO];

export type ResolucaoCarta = {
  url: string;
  origem: OrigemResolucao;
  aliasAplicado: boolean;
  diretorioAliasado?: string;
};

/** `true` somente se o localId casar EXATAMENTE com o formato do subset. */
export function localIdValidoParaSubset(
  externalSetId: string | null | undefined,
  localId: string | null | undefined,
): boolean {
  if (typeof externalSetId !== "string" || typeof localId !== "string") return false;
  const formato = FORMATO_LOCAL_ID_SUBSET[externalSetId.toLowerCase()];
  return formato ? formato.test(localId) : false;
}

/**
 * Constroi a URL-base derivada. Devolve `null` em QUALQUER duvida.
 * Tudo estrutural vem de constantes; so `localId` e externo, e ja validado.
 */
export function derivarBaseImageUrlAllowlist(
  externalSetId: string | null | undefined,
  localId: string | null | undefined,
  languageCode: string | null | undefined,
): string | null {
  if (languageCode !== IDIOMA_DERIVACAO) return null;
  if (typeof externalSetId !== "string" || externalSetId === "") return null;

  const destino = ALIAS_DIRETORIO_ASSET[externalSetId.toLowerCase()];
  if (!destino) return null;
  if (!localIdValidoParaSubset(externalSetId, localId)) return null;

  const candidata =
    `${TCGDEX_ASSET_ORIGIN}/${IDIOMA_DERIVACAO}/${SERIE_ASSET_SWSH}/${destino}/${localId}`;

  // Re-verificacao pos-parse: origem exata e formato de path esperado.
  let parsed: URL;
  try {
    parsed = new URL(candidata);
  } catch {
    return null;
  }
  if (parsed.origin !== TCGDEX_ASSET_ORIGIN) return null;
  if (parsed.username !== "" || parsed.password !== "") return null;
  if (parsed.search !== "" || parsed.hash !== "") return null;

  const segmentos = parsed.pathname.split("/"); // ["", lang, serie, dir, localId]
  if (segmentos.length !== 5) return null;
  if (segmentos[1] !== IDIOMA_DERIVACAO) return null;
  if (segmentos[2] !== SERIE_ASSET_SWSH) return null;
  if (segmentos[3] !== destino) return null;
  if (segmentos[4] !== localId) return null; // localId LITERAL, sem encoding

  return parsed.toString();
}

/**
 * Resolucao COMPLETA da URL-base de uma carta. Unico ponto de decisao.
 *
 * Precedencia:
 *   1. fonte publicou `image`  -> SOURCE (com alias de diretorio se devido);
 *   2. fonte NAO publicou      -> DERIVED_ALLOWLIST, se e so se a allowlist,
 *                                 o idioma e o formato do localId permitirem;
 *   3. caso contrario          -> NONE.
 *
 * Nunca lanca.
 */
export function resolverBaseImageUrlDaCarta(
  baseImageUrlDaFonte: string | null | undefined,
  externalSetId: string | null | undefined,
  localId: string | null | undefined,
  languageCode: string | null | undefined,
): ResolucaoCarta {
  const daFonte = typeof baseImageUrlDaFonte === "string" ? baseImageUrlDaFonte : "";

  if (daFonte !== "") {
    const r = resolverBaseImageUrlComAlias(daFonte, externalSetId, languageCode);
    return {
      url: r.url,
      origem: ORIGEM_RESOLUCAO.SOURCE,
      aliasAplicado: r.aliasAplicado,
      ...(r.diretorioAliasado ? { diretorioAliasado: r.diretorioAliasado } : {}),
    };
  }

  const derivada = derivarBaseImageUrlAllowlist(externalSetId, localId, languageCode);
  if (derivada) {
    return {
      url: derivada,
      origem: ORIGEM_RESOLUCAO.DERIVED_ALLOWLIST,
      aliasAplicado: true,
      diretorioAliasado: ALIAS_DIRETORIO_ASSET[String(externalSetId).toLowerCase()],
    };
  }

  return { url: "", origem: ORIGEM_RESOLUCAO.NONE, aliasAplicado: false };
}

type FetchImpl = (input: string, init?: RequestInit) => Promise<Response>;
type SleepImpl = (ms: number) => Promise<void>;

const dormirPadrao: SleepImpl = (ms) =>
  new Promise((resolve) => setTimeout(resolve, ms));

export class TcgdexClient {
  private static readonly BASE_URL =
    "https://api.tcgdex.net/v2";

  // `fetchImpl`/`sleepImpl` existem exclusivamente para teste offline do
  // retry (simular 503/429/timeout sem rede e sem esperar backoff real).
  // Em produção os defaults são usados e o comportamento é idêntico ao
  // `fetch` global.
  constructor(
    private readonly language = "en",
    private readonly fetchImpl: FetchImpl = fetch,
    private readonly sleepImpl: SleepImpl = dormirPadrao,
  ) {}

  private async get<T>(path: string): Promise<T> {
    const url = `${TcgdexClient.BASE_URL}/${this.language}${path}`;
    let ultimoErro: TcgdexRequestError | null = null;

    for (let tentativa = 1; tentativa <= TCGDEX_MAX_ATTEMPTS; tentativa += 1) {
      const controller = new AbortController();
      const timeoutId = setTimeout(
        () => controller.abort(),
        TCGDEX_REQUEST_TIMEOUT_MS,
      );

      let response: Response;

      try {
        response = await this.fetchImpl(url, {
          headers: { Accept: "application/json" },
          signal: controller.signal,
        });
      } catch (error) {
        const abortado = error instanceof Error && error.name === "AbortError";
        ultimoErro = new TcgdexRequestError(
          abortado ? "TIMEOUT" : "NETWORK",
          abortado
            ? `TCGDEX_TIMEOUT: sem resposta em ${TCGDEX_REQUEST_TIMEOUT_MS}ms (tentativa ${tentativa}/${TCGDEX_MAX_ATTEMPTS}).`
            : `TCGDEX_NETWORK: ${error instanceof Error ? error.message : String(error)} (tentativa ${tentativa}/${TCGDEX_MAX_ATTEMPTS}).`,
          url,
          null,
          true,
          tentativa,
        );

        if (tentativa < TCGDEX_MAX_ATTEMPTS) {
          await this.sleepImpl(TCGDEX_BACKOFF_MS[tentativa - 1]);
          continue;
        }
        throw ultimoErro;
      } finally {
        clearTimeout(timeoutId);
      }

      if (response.ok) {
        try {
          return await response.json() as T;
        } catch (error) {
          // Corpo malformado não é falha de transporte — repetir não ajuda.
          throw new TcgdexRequestError(
            "INVALID_JSON",
            `TCGDEX_INVALID_JSON: ${error instanceof Error ? error.message : String(error)}`,
            url,
            response.status,
            false,
            tentativa,
          );
        }
      }

      const { code, retriable } = classificarStatusTcgdex(response.status);

      // Mensagem preservada no prefixo histórico `TCGDEX_HTTP_<status>` —
      // qualquer leitor a jusante que dependa desse texto continua válido.
      ultimoErro = new TcgdexRequestError(
        code,
        `TCGDEX_HTTP_${response.status} (tentativa ${tentativa}/${TCGDEX_MAX_ATTEMPTS}).`,
        url,
        response.status,
        retriable,
        tentativa,
      );

      if (!retriable) throw ultimoErro;

      if (tentativa < TCGDEX_MAX_ATTEMPTS) {
        await this.sleepImpl(
          calcularEsperaTcgdex(
            response.headers?.get?.("Retry-After") ?? null,
            TCGDEX_BACKOFF_MS[tentativa - 1],
          ),
        );
        continue;
      }
      throw ultimoErro;
    }

    // Inalcançável: o laço sempre retorna ou lança. Guarda para o compilador.
    throw ultimoErro ??
      new TcgdexRequestError(
        "NETWORK",
        "TCGDEX_EXHAUSTED: laço de tentativas terminou sem resposta utilizável.",
        url,
        null,
        true,
        TCGDEX_MAX_ATTEMPTS,
      );
  }

  async getSet(externalSetId: string): Promise<TcgdexSetDetail> {
    return this.get(`/sets/${externalSetId}`);
  }

  async getCardsBySet(externalSetId: string): Promise<Record<string, unknown>> {
    return this.get(`/sets/${externalSetId}/cards`);
  }

  async getCard(cardId: string): Promise<Record<string, unknown>> {
    return this.get(`/cards/${cardId}`);
  }
}
