// Project Mimikyu — Localização automática do Set na TCGdex (Ciclo 2,
// ADR-024). Ajuste de Fabrício (2026-08-01): o administrador nunca digita o
// external_set_id diretamente — o sistema tenta localizar o Set
// correspondente pelo nome da Coleção; só em ambiguidade ou nenhuma
// correspondência é oferecida uma busca manual (ainda por nome, nunca por
// id técnico).
//
// card_set.name está em português (ver database/schema/120_create_card_set_table.sql)
// — tenta primeiro em pt, cai para en se não achar nada. Nenhuma garantia de
// que a tradução oficial da TCGdex bate caractere a caractere com os nomes
// cadastrados aqui; quando não bate, cai naturalmente no caminho manual, por
// desenho — não é uma falha.
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
 * Tenta localizar o Set da TCGdex correspondente a um Card Set interno pelo
 * nome — primeiro em português, depois em inglês. Um único resultado conta
 * como localizado; mais de um é ambíguo; nenhum nos dois idiomas cai para
 * busca manual (ver searchTcgdexSetsManually).
 */
export async function autoMatchTcgdexSet(cardSetName: string): Promise<TcgdexAutoMatchResult> {
  const ptResults = await searchTcgdexSetsByName(cardSetName, "pt");
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

  const enResults = await searchTcgdexSetsByName(cardSetName, "en");
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
