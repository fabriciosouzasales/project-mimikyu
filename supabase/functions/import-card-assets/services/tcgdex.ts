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
