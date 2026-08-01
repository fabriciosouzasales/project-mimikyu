// Project Mimikyu — Edge Function: import-catalog-cards
// TCGdex Service — versão evoluída e independente de
// supabase/functions/import-card-assets/services/tcgdex.ts (Convenção #3:
// responsabilidade única por função, sem import cruzado entre funções).

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

export type TcgdexSetBrief = {
  id: string;
  name: string;
  logo?: string;
  symbol?: string;
  cardCount: {
    total: number;
    official?: number;
  };
};

export type TcgdexCardDetail = {
  id: string;
  localId: string;
  name: string;
  category: "Pokemon" | "Trainer" | "Energy" | string;
  rarity?: string;
  dexId?: number[];
  image?: string;
};

export class TcgdexClient {
  private static readonly BASE_URL = "https://api.tcgdex.net/v2";

  // Default defensivo — index.ts sempre passa TCGDEX_LANGUAGE ("pt")
  // explicitamente; nunca depender deste valor sozinho.
  constructor(private readonly language = "pt") {}

  private async get<T>(path: string): Promise<T> {
    const response = await fetch(
      `${TcgdexClient.BASE_URL}/${this.language}${path}`,
      { headers: { Accept: "application/json" } },
    );
    if (!response.ok) {
      throw new Error(`TCGDEX_HTTP_${response.status}`);
    }
    return await response.json() as T;
  }

  async getSet(externalSetId: string): Promise<TcgdexSetDetail> {
    return this.get(`/sets/${externalSetId}`);
  }

  async getCard(cardId: string): Promise<TcgdexCardDetail> {
    return this.get(`/cards/${cardId}`);
  }

  async searchSets(nameQuery: string): Promise<TcgdexSetBrief[]> {
    return this.get(`/sets?name=${encodeURIComponent(nameQuery)}`);
  }
}