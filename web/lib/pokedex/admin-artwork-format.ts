/**
 * Apresentação da administração de Imagens da Pokédex (Pokédex P2 Lote E).
 * Funções puras — sem rede, sem React — para filtros da URL, pesquisa e
 * linguagem humana dos códigos gravados pelo importador (Query 6132).
 */

export type ArtworkStatus = "IMPORTED" | "PENDING" | "FAILED";

/** Valores de `?status=` na URL (pt-BR) ↔ status do banco. */
const STATUS_PARAM: Record<string, ArtworkStatus> = {
  importadas: "IMPORTED",
  pendentes: "PENDING",
  "com-falha": "FAILED",
};

export const STATUS_PARAM_BY_STATUS: Record<ArtworkStatus, string> = {
  IMPORTED: "importadas",
  PENDING: "pendentes",
  FAILED: "com-falha",
};

export const STATUS_LABEL: Record<ArtworkStatus, string> = {
  IMPORTED: "Importada",
  PENDING: "Pendente",
  FAILED: "Com falha",
};

export function parseArtworkStatusParam(value: string | string[] | undefined): ArtworkStatus | null {
  const raw = Array.isArray(value) ? value[0] : value;
  return (raw && STATUS_PARAM[raw]) || null;
}

/** `?pagina=` é 1-based na URL; devolve o índice 0-based (inválido → 0). */
export function parsePageParam(value: string | string[] | undefined): number {
  const raw = Array.isArray(value) ? value[0] : value;
  if (!raw || !/^\d{1,4}$/.test(raw)) return 0;
  const page = Number(raw);
  return page >= 1 ? page - 1 : 0;
}

function normalize(text: string): string {
  return text.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().trim();
}

/**
 * Pesquisa por número (aceita "25", "#25", "0025") ou por parte do nome,
 * sem diferenciar acentos e maiúsculas.
 */
export function matchesArtworkQuery(row: { national_dex_number: number; species_name: string }, query: string): boolean {
  const q = normalize(query).replace(/^(#|n[ºo°.]?\s*)/, "");
  if (q === "") return true;
  if (/^\d+$/.test(q)) return row.national_dex_number === Number(q);
  return normalize(row.species_name).includes(q);
}

/** Erros transitórios: vale tentar de novo sem mudar nada. */
const TRANSIENT_CODES = new Set([
  "SOURCE_UNAVAILABLE",
  "SOURCE_NETWORK",
  "DOWNLOAD_TIMEOUT",
  "STORAGE_UPLOAD",
  "RECORD_IMPORT",
  "UNEXPECTED_ERROR",
]);

const ERROR_LABEL: Record<string, string> = {
  SOURCE_NATIONAL_MISMATCH: "A PokéAPI não confirmou o número nacional desta espécie.",
  SOURCE_INVALID_PAYLOAD: "A PokéAPI respondeu em um formato inesperado.",
  SOURCE_DEFAULT_FORM_AMBIGUOUS: "A espécie não tem uma única forma padrão na PokéAPI.",
  SOURCE_SPECIES_LINK_MISMATCH: "A forma padrão da PokéAPI não aponta para esta espécie.",
  SOURCE_NO_OFFICIAL_ARTWORK: "A PokéAPI não oferece arte oficial para a forma padrão.",
  SOURCE_URL_NOT_ALLOWED: "A imagem indicada está fora da origem permitida.",
  SOURCE_NOT_FOUND: "Espécie ou imagem não encontrada na origem.",
  SOURCE_UNAVAILABLE: "A origem está indisponível no momento (limite de requisições ou erro do servidor).",
  SOURCE_NETWORK: "Falha de rede ao acessar a origem.",
  SOURCE_REQUEST: "A origem recusou a requisição.",
  DOWNLOAD_TIMEOUT: "Tempo esgotado ao baixar da origem.",
  VALIDATION_EMPTY: "A origem entregou um arquivo vazio.",
  VALIDATION_TOO_LARGE: "O arquivo da origem passa de 1 MB.",
  VALIDATION_NOT_PNG: "O arquivo da origem não é um PNG válido.",
  VALIDATION_UNREADABLE: "O PNG da origem não pôde ser lido.",
  VALIDATION_DIMENSIONS: "As dimensões da imagem estão fora do intervalo aceito.",
  TRANSFORMATION_FORMAT: "A conversão para WebP não gerou um WebP.",
  TRANSFORMATION_DIMENSIONS: "A versão WebP ficou com dimensões fora do contrato.",
  TRANSFORMATION_ASPECT: "A conversão para WebP alterou a proporção.",
  TRANSFORMATION_ALPHA_LOST: "A conversão para WebP perdeu a transparência.",
  TRANSFORMATION_TOO_LARGE: "A versão WebP passou de 1 MB.",
  STORAGE_UPLOAD: "Falha ao enviar o arquivo para o armazenamento.",
  RECORD_IMPORT: "O banco recusou o registro da importação.",
  UNEXPECTED_ERROR: "Erro inesperado durante a importação.",
};

export function artworkErrorLabel(code: string | null | undefined): string | null {
  if (!code) return null;
  return ERROR_LABEL[code] ?? "Falha não catalogada — veja a mensagem técnica.";
}

export function isTransientArtworkError(code: string | null | undefined): boolean {
  return !!code && TRANSIENT_CODES.has(code);
}

export function rightsLabel(value: string | null | undefined): string | null {
  if (!value) return null;
  if (value === "THIRD_PARTY_UNLICENSED") return "Arte de terceiros · sem licença de uso comercial";
  if (value === "LICENSED") return "Licenciada";
  return value;
}

const DATE_TIME = new Intl.DateTimeFormat("pt-BR", {
  dateStyle: "short",
  timeStyle: "short",
  timeZone: "America/Sao_Paulo",
});

/** Formatado no servidor com fuso fixo — mesmo texto no HTML e na hidratação. */
export function formatArtworkDate(value: string | null | undefined): string | null {
  if (!value) return null;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : DATE_TIME.format(date);
}

export function formatBytes(value: number | null | undefined): string | null {
  if (value == null) return null;
  if (value < 1024) return `${value} B`;
  return `${new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 1 }).format(value / 1024)} KB`;
}
