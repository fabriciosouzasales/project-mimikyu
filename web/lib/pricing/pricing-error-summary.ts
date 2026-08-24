/**
 * Tradução amigável de `pricing_sync_run.error_summary` (Saúde das Fontes,
 * feedback de Fabrício 2026-08-23 sobre o Hero v1: "`BUDGET_STOPPED(set=ME4)`
 * está técnico demais para a superfície principal"). O código bruto nunca é
 * descartado — quem chama continua colocando o valor original em `title`
 * (tooltip), só o texto visível troca.
 *
 * Formato bruto real, dos dois caminhos que escrevem essa coluna hoje:
 * - `_shared/pricing-justtcg-refresh/core.ts` (onda, mais antigo): códigos
 *   parametrizados, `CODIGO(chave=valor, ...)`, às vezes com `: mensagem`
 *   solta no final, múltiplos eventos concatenados com `" | "`.
 * - `_shared/pricing-justtcg-refresh/set-refresh-core.ts` (dispatcher por
 *   Set, caminho vigente): códigos simples sem parênteses (ex.:
 *   `JUSTTCG_AUTH_FAILURE`).
 *
 * Cobre os códigos conhecidos nos dois caminhos; qualquer código novo/não
 * mapeado cai no fallback (SNAKE_CASE → frase minúscula), nunca quebra nem
 * esconde o evento — só fica menos bonito até alguém adicionar o código
 * aqui.
 */

type ErrorTemplate = (params: Record<string, string>) => string;

const KNOWN_ERROR_TEMPLATES: Record<string, ErrorTemplate> = {
  AUTH_FAILURE: () => "Falha de autenticação com a fonte de preços",
  JUSTTCG_AUTH_FAILURE: () => "Falha de autenticação com a fonte de preços",
  BUDGET_STOPPED: () => "Sincronização pausada ao atingir o limite de requisições da rodada (retomada automaticamente na próxima execução)",
  DEADLINE_STOPPED: () => "Sincronização interrompida por tempo máximo de execução (retomada automaticamente)",
  WAVE_INTERNAL_DEADLINE_EXCEEDED: () => "Tempo máximo interno da rodada excedido",
  TECHNICAL_FAILURE: (p) => `Falha técnica pontual ao buscar dados${p.set ? ` do Set ${p.set}` : ""}`,
  JUSTTCG_SET_NOT_FOUND_404: () => "Set não encontrado na fonte de preços",
  JUSTTCG_PAGE_FETCH_TECHNICAL_FAILURE: () => "Falha técnica ao buscar uma página de dados",
  PRODUCT_RESOLUTION_FAILED: () => "Falha ao resolver produtos de preço",
  OBSERVATION_INSERT_FAILED: () => "Falha ao registrar observações de preço",
  PRICING_SYNC_RUN_CALL_INSERT_FAILED: () => "Falha ao registrar telemetria da execução",
  LOCAL_IDENTITY_OR_CONDITION_READ_FAILED: () => "Falha ao ler dados locais de identidade/condição",
  IDENTITY_MISMATCH_ON_REUSE: () => "Divergência de identidade ao reaproveitar um produto",
  PRINTING_LABEL_MISMATCH_ON_REUSE: () => "Divergência de variante ao reaproveitar um produto",
  PRODUCT_UNRESOLVED_SKIP_OBSERVATIONS: () => "Observações de preço ignoradas por produto não resolvido",
  OBSERVATION_DIVERGENTE_PRESERVADA: () => "Preço divergente preservado (mesmo instante de observação)",
};

/** `CODIGO(chave=valor, chave2=valor2): mensagem livre` — todas as partes opcionais exceto o código. */
const SEGMENT_PATTERN = /^([A-Z0-9_]+)(?:\(([^)]*)\))?(?::\s*(.*))?$/;

function humanizeSegment(segment: string): string {
  const match = SEGMENT_PATTERN.exec(segment.trim());
  if (!match) return segment.trim();

  const code = match[1] ?? "";
  const paramsRaw = match[2];
  const params: Record<string, string> = {};
  if (paramsRaw) {
    for (const pair of paramsRaw.split(",")) {
      const [key, value] = pair.split("=").map((part) => part.trim());
      if (key && value) params[key] = value;
    }
  }

  const template = KNOWN_ERROR_TEMPLATES[code];
  if (template) return template(params);

  // Fallback: SNAKE_CASE -> "código não mapeado" em minúsculas, com o Set se houver.
  const legivel = code.toLowerCase().replace(/_/g, " ");
  return `Evento técnico: ${legivel}${params.set ? ` (Set ${params.set})` : ""}`;
}

/**
 * Humaniza `error_summary` completo — pode conter múltiplos eventos
 * concatenados com `" | "` (ver `sanitize()` em `core.ts`); mostra só o
 * primeiro, mais recente na ordem de escrita, com indicação de quantos mais
 * existem (o valor bruto completo continua disponível via tooltip no
 * chamador).
 */
export function humanizePricingErrorSummary(raw: string | null): string | null {
  if (!raw) return null;
  const segments = raw.split(" | ").filter(Boolean);
  const [firstSegment] = segments;
  if (!firstSegment) return null;

  const primeiro = humanizeSegment(firstSegment);
  if (segments.length === 1) return primeiro;
  return `${primeiro} (+${segments.length - 1} ${segments.length - 1 === 1 ? "evento" : "eventos"})`;
}
