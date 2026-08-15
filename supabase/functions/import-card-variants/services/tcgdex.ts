// Project Mimikyu — Edge Function: import-card-variants
// TCGdex Service — cliente mínimo e próprio desta function (Convenção #3
// do projeto: responsabilidade única por function, sem import cruzado com
// import-catalog-cards/services/tcgdex.ts). Usado exclusivamente para
// resolver o nome de Série/Set em inglês, necessário para montar o
// caminho de pasta do dataset-fonte no GitHub
// (data/{Serie}/{Set}/{localId}.ts) — NUNCA para ler variants[], que vem
// só do dataset-fonte (github.com/tcgdex/cards-database), decisão já
// tomada na frente de validação da fonte (classificação B, 2026-08-15).

export type TcgdexSetSerieName = {
  id: string;
  name: string;
  serieId: string;
  serieName: string;
};

// Hardcoded "en" — deliberado, independente de TCGDEX_PRIMARY_LANGUAGE
// ("pt") usado por import-catalog-cards para o conteúdo da Card. As
// pastas do dataset-fonte no GitHub usam sempre o nome em inglês da
// Série/Set (ex. "Mega Evolution/Ascended Heroes"), confirmado por teste
// real nesta checagem — não é o idioma de exibição da Card, é só a
// convenção de nomenclatura de pasta do repositório-fonte.
const TCGDEX_METADATA_LANGUAGE = "en";
const TCGDEX_BASE_URL = "https://api.tcgdex.net/v2";

// Timeout explícito (2026-08-15, correção do incidente SV10) — mesmo padrão
// já usado em import-card-assets/services/storage.ts (`downloadImage()`,
// IMAGE_DOWNLOAD_TIMEOUT_MS, corrigido em 2026-08-02 para o mesmo problema
// estrutural: um `fetch()` sem timeout pendurado consome sozinho todo o
// orçamento de execução da Edge Function (~150s) sem nenhum progresso, e o
// código nunca chega ao catch()/failVariantJob() — a plataforma mata a
// invocação de fora para dentro (HTTP 546 nos logs), deixando o job preso
// em PROCESSING para sempre. 15s é generoso para uma única chamada de
// metadado (payload pequeno) e folgado o bastante abaixo do teto da
// plataforma para o erro sempre cair no catch existente antes disso.
const TCGDEX_METADATA_TIMEOUT_MS = 15000;

export async function resolveSetSerieName(externalSetId: string): Promise<TcgdexSetSerieName> {
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), TCGDEX_METADATA_TIMEOUT_MS);

  let response: Response;
  try {
    response = await fetch(
      `${TCGDEX_BASE_URL}/${TCGDEX_METADATA_LANGUAGE}/sets/${externalSetId}`,
      { headers: { Accept: "application/json" }, signal: controller.signal },
    );
  } catch (error) {
    if (error instanceof DOMException && error.name === "AbortError") {
      throw new Error(`TCGDEX_SET_METADATA_TIMEOUT: sem resposta em ${TCGDEX_METADATA_TIMEOUT_MS}ms`);
    }
    throw error;
  } finally {
    clearTimeout(timeoutId);
  }

  if (!response.ok) {
    throw new Error(`TCGDEX_SET_METADATA_HTTP_${response.status}`);
  }

  const data = await response.json();
  const serieName = data?.serie?.name;
  const setName = data?.name;
  if (!serieName || !setName) {
    throw new Error("TCGDEX_SET_METADATA_INCOMPLETE");
  }

  return { id: externalSetId, name: setName, serieId: data?.serie?.id ?? "", serieName };
}
