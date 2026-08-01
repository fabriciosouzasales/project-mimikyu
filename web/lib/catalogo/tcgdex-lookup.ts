// Project Mimikyu — Localização automática do Set na TCGdex (Ciclo 2,
// ADR-024). Ajuste de Fabrício (2026-08-01): o administrador nunca digita o
// external_set_id diretamente — o sistema tenta localizar o Set
// correspondente pelo nome da Coleção; só em ambiguidade ou nenhuma
// correspondência é oferecida uma busca manual (ainda por nome, nunca por
// id técnico).
//
// card_set.name está em português (ver
// database/schema/120_create_card_set_table.sql) — tenta primeiro em pt,
// cai para en se não achar nada. "pt" (não "pt-br"): a documentação oficial
// da TCGdex (tcgdex.dev/errors/language-invalid) lista pt/pt-br/pt-pt como
// três idiomas distintos, mas a cobertura real de dados por Set é o que
// importa — testado ao vivo em 2026-08-01 (remediação do ME5):
// /pt-br/sets/me05 devolveu 404 (sem tradução pt-br para esse Set),
// enquanto /pt/sets/me05 tem os dados completos. Fabrício confirmou "pt"
// como o idioma correto depois de checar as duas URLs — mesmo ajuste
// aplicado no processador (services/tcgdex.ts da Edge Function). Nenhuma
// garantia de que a tradução da TCGdex bate caractere a caractere com os
// nomes cadastrados aqui; quando não bate, cai naturalmente no caminho
// manual, por desenho — não é uma falha.
//
// Único ponto do frontend que fala diretamente com a API da TCGdex — mesmo
// princípio já usado no backend (services/tcgdex.ts da Edge Function):
// nenhuma outra camada deve chamar a TCGdex diretamente.

const TCGDEX_BASE_URL = "https://api.tcgdex.net/v2";

export type TcgdexSetCandidate = {
  id: string;
  name: string;
  logo: string | null;
  cardCountTotal: number;
};

export type TcgdexAutoMatchResult =
  | { status: "MATCHED"; set: TcgdexSetCandidate; matchedLanguage: "pt" | "en" }
  | { status: "AMBIGUOUS"; candidates: TcgdexSetCandidate[] }
  | { status: "NOT_FOUND" };

type TcgdexSetBriefResponse = {
  id: string;
  name: string;
  logo?: string;
  cardCount: { total: number; official?: number };
};

async function searchTcgdexSetsByName(nameQuery: string, language: "pt" | "en"): Promise<TcgdexSetCandidate[]> {
  const url = `${TCGDEX_BASE_URL}/${language}/sets?name=${encodeURIComponent(nameQuery)}`;

  try {
    const response = await fetch(url, { headers: { Accept: "application/json" } });
    if (!response.ok) {
      return [];
    }
    const data = (await response.json()) as TcgdexSetBriefResponse[];
    return data.map((set) => ({
      id: set.id,
      name: set.name,
      logo: set.logo ?? null,
      cardCountTotal: set.cardCount?.total ?? 0,
    }));
  } catch (error) {
    console.error("TCGDEX_SET_SEARCH_FAILED:", error);
    return [];
  }
}

/**
 * Gera os ids plausíveis de Set da TCGdex a partir do código interno da
 * Coleção (card_set.code) — descoberto ao vivo em 2026-08-01 a partir de
 * jobs reais já no banco: "SVE" -> "sve" (sem parte numérica, usado como
 * está) e "SV2" -> "sv02" / "ME5" -> "me05" (parte numérica preenchida com
 * zero à esquerda até 2 dígitos). Sem uma regra única confiável — por isso
 * as duas formas plausíveis são tentadas contra a API (fetchTcgdexSetById
 * abaixo verifica de verdade, nunca assume) antes de cair no fallback por
 * nome.
 */
function candidateTcgdexIds(cardSetCode: string): string[] {
  const lower = cardSetCode.toLowerCase();
  const match = /^([a-z]+)(\d+)$/.exec(lower);
  if (!match) return [lower];
  const [, prefix, digits] = match;
  // Sob `noUncheckedIndexedAccess`, os grupos capturados de um regex exec
  // continuam tipados como `string | undefined` mesmo garantidos pela
  // própria regex (`([a-z]+)(\d+)`) — guarda defensiva só para satisfazer o
  // compilador, nunca deveria ser `undefined` na prática aqui.
  if (!prefix || !digits) return [lower];
  const padded = `${prefix}${digits.padStart(2, "0")}`;
  return padded === lower ? [lower] : [lower, padded];
}

/** Busca um Set da TCGdex por id exato (`GET /{lang}/sets/{id}`) — `null` em qualquer falha (404 incluído), nunca lança. */
async function fetchTcgdexSetById(id: string, language: "pt" | "en"): Promise<TcgdexSetCandidate | null> {
  const url = `${TCGDEX_BASE_URL}/${language}/sets/${encodeURIComponent(id)}`;
  try {
    const response = await fetch(url, { headers: { Accept: "application/json" } });
    if (!response.ok) return null;
    const data = (await response.json()) as TcgdexSetBriefResponse;
    if (!data?.id) return null;
    return {
      id: data.id,
      name: data.name,
      logo: data.logo ?? null,
      cardCountTotal: data.cardCount?.total ?? 0,
    };
  } catch (error) {
    console.error("TCGDEX_SET_BY_ID_FAILED:", error);
    return null;
  }
}

/**
 * Tenta localizar o Set da TCGdex correspondente a um Card Set interno —
 * primeiro pelo CÓDIGO (id exato, ver candidateTcgdexIds/fetchTcgdexSetById
 * acima), só caindo para busca fuzzy por nome se nenhum id candidato
 * responder. Trocado em 2026-08-01 (bug real reportado por Fabrício): a
 * busca por nome sozinha confundia SV1 ("Escarlate e Violeta") com SVE
 * ("Energias Escarlate e Violeta") — a segunda é um resultado válido da
 * busca por nome da primeira (substring), então SV1 aparecia como
 * "ambíguo" com os dois, enquanto SVE (cujo nome pt "Energias Escarlate e
 * Violeta" não bate literalmente com a tradução real da TCGdex) não
 * encontrava nada. Busca por id evita os dois problemas: cada Coleção tem
 * exatamente um id de Set, sem ambiguidade nem depender do nome bater.
 */
export async function autoMatchTcgdexSet(cardSet: { code: string; name: string }): Promise<TcgdexAutoMatchResult> {
  for (const language of ["pt", "en"] as const) {
    for (const id of candidateTcgdexIds(cardSet.code)) {
      const set = await fetchTcgdexSetById(id, language);
      if (set) {
        return { status: "MATCHED", set, matchedLanguage: language };
      }
    }
  }

  const ptResults = await searchTcgdexSetsByName(cardSet.name, "pt");
  if (ptResults.length === 1) {
    // Destructuring (não ptResults[0]) — sob noUncheckedIndexedAccess, o
    // acesso por índice permanece `T | undefined` mesmo depois do
    // `.length === 1` acima; a desestruturação aqui é o que de fato
    // estreita o tipo para `T`.
    const [set] = ptResults;
    if (set) {
      return { status: "MATCHED", set, matchedLanguage: "pt" };
    }
  }
  if (ptResults.length > 1) {
    return { status: "AMBIGUOUS", candidates: ptResults };
  }

  const enResults = await searchTcgdexSetsByName(cardSet.name, "en");
  if (enResults.length === 1) {
    const [set] = enResults;
    if (set) {
      return { status: "MATCHED", set, matchedLanguage: "en" };
    }
  }
  if (enResults.length > 1) {
    return { status: "AMBIGUOUS", candidates: enResults };
  }

  return { status: "NOT_FOUND" };
}

/**
 * Busca manual — usada só quando autoMatchTcgdexSet não resolve sozinho
 * (ambíguo ou sem correspondência). Busca em português e inglês, mescladas
 * e sem duplicar por id. O administrador ainda escolhe visualmente (nome +
 * quantidade de cartas), nunca digita um id técnico.
 */
export async function searchTcgdexSetsManually(query: string): Promise<TcgdexSetCandidate[]> {
  if (!query.trim()) return [];
  const [pt, en] = await Promise.all([
    searchTcgdexSetsByName(query, "pt"),
    searchTcgdexSetsByName(query, "en"),
  ]);
  const byId = new Map<string, TcgdexSetCandidate>();
  for (const set of [...pt, ...en]) {
    byId.set(set.id, set);
  }
  return Array.from(byId.values());
}
