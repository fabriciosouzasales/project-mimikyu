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
// Pendência conhecida, ainda não resolvida: o endpoint usado por
// `getCardsBySet` (`/sets/{id}/cards`) foi assumido a partir da documentação
// da TCGdex, mas nunca foi confirmado por uma chamada real — diferente de
// `getSet`, cuja primeira chamada real ainda está em andamento (Sprint B3.3).

export class TcgdexClient {
  private static readonly BASE_URL =
    "https://api.tcgdex.net/v2";

  constructor(
    private readonly language = "en",
  ) {}

  private async get<T>(path: string): Promise<T> {
    const response = await fetch(
      `${TcgdexClient.BASE_URL}/${this.language}${path}`,
      {
        headers: {
          Accept: "application/json",
        },
      },
    );
    if (!response.ok) {
      throw new Error(`TCGDEX_HTTP_${response.status}`);
    }
    return await response.json() as T;
  }

  async getSet(externalSetId: string): Promise<Record<string, unknown>> {
    return this.get(`/sets/${externalSetId}`);
  }

  async getCardsBySet(externalSetId: string): Promise<Record<string, unknown>> {
    return this.get(`/sets/${externalSetId}/cards`);
  }

  async getCard(cardId: string): Promise<Record<string, unknown>> {
    return this.get(`/cards/${cardId}`);
  }
}
