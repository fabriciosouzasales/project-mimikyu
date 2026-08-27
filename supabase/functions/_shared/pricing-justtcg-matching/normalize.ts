// Project Mimikyu — supabase/functions/_shared/pricing-justtcg-matching/normalize.ts
// Normalização — portado de scripts/sync-justtcg-pricing.ts (Incrementos P14.2/P14.2.1/
// P14.4.4) para o Incremento P16.2 (Núcleo Compartilhado de Matching, 2026-08-25).
// Nenhuma mudança de comportamento nesta extração — mesma lógica, byte a byte.

import type { JustTcgSet } from "../pricing-justtcg/mod.ts";
import type { ParsedCollectorNumber } from "./types.ts";

export function normalizeName(text: string): string {
  if (!text) return "";
  const semAcento = text.normalize("NFD").replace(/[̀-ͯ]/g, "");
  return semAcento.toLowerCase().replace(/\s+/g, " ").trim();
}

// Só deve ser chamada com um número já confirmado utilizável — ver isUsableExternalNumber().
// Não tenta adivinhar formato: assume dígitos/letras de coleção reais (ex. "058", "TG01").
export function normalizeNumber(numero: string): string {
  if (!numero) return "";
  const numerador = numero.split("/")[0];
  const limpo = numerador.replace(/[^0-9A-Za-z]/g, "");
  const semZeros = limpo.replace(/^0+/, "");
  return (semZeros || "0").toLowerCase();
}

// A JustTCG documenta `number: "N/A"` como valor real para cartas sem numeração própria
// (ex. Energias promocionais — ver https://justtcg.com/docs/schema/card, exemplo). Sem
// esta checagem, normalizeNumber("N/A") interpretaria "/" como separador de denominador
// (["N","A"]) e devolveria "n" — uma chave normalizada plausível, porém falsa, que
// poderia colidir por acidente com uma carta real de número "N". Qualquer número externo
// ausente/vazio/"N/A" (case-insensitive) fica de fora do índice por número — a carta
// correspondente só poderia ser encontrada por nome, e nome é deliberadamente secundário
// nesta rodada (nunca a única evidência) — logo, permanece ABSENT do lado da JustTCG.
export function isUsableExternalNumber(raw: string | null | undefined): raw is string {
  if (!raw) return false;
  const trimmed = raw.trim();
  if (!trimmed) return false;
  if (trimmed.toUpperCase() === "N/A") return false;
  return true;
}

// P14.4.4 fix (filtro por denominador) — decomposição puramente sintática do número de
// coleção externo em (1) numerador normalizado (MESMA normalização de normalizeNumber():
// zeros à esquerda removidos, minúsculo — reaproveitada aqui, nunca duplicada), (2)
// denominador opcional (a parte estrutural após a barra, quando existir e for numérica) e
// (3) o valor bruto preservado sem nenhuma transformação, só para evidência/auditoria.
// Nunca interpreta nome, idioma ou raridade — só a forma "N" ou "N/D" do número. Denominador
// ausente ou não-numérico -> null (nunca lançado como erro: número sem denominador é um
// formato legítimo, ex. promos "022"). Espaços em torno da barra são tolerados (o lado do
// numerador via normalizeNumber() já remove qualquer caractere não alfanumérico; o lado do
// denominador é aparado explicitamente aqui antes de extrair os dígitos).
export function parseCollectorNumberParts(raw: string | null | undefined): ParsedCollectorNumber {
  const rawValue = raw ?? "";
  if (!isUsableExternalNumber(rawValue)) {
    return { numerator: "", denominator: null, raw: rawValue };
  }
  const numerator = normalizeNumber(rawValue);
  const barraIndex = rawValue.indexOf("/");
  if (barraIndex === -1) {
    return { numerator, denominator: null, raw: rawValue };
  }
  const denominadorBruto = rawValue.slice(barraIndex + 1).trim();
  const somenteDigitos = denominadorBruto.replace(/[^0-9]/g, "");
  const denominator = somenteDigitos.length > 0 ? Number.parseInt(somenteDigitos, 10) : null;
  return { numerator, denominator: denominator !== null && Number.isFinite(denominator) ? denominator : null, raw: rawValue };
}

// P14.4.4 fix (filtro por denominador) — "válido" para fins do desempate estrutural: um
// número inteiro positivo. Qualquer outra coisa (ausente, zero, negativo, não-inteiro,
// NaN) é tratada como "ausente" pela regra 6 do pedido — nunca aplica o desempate, cai
// sempre no comportamento AMBIGUOUS conservador já existente, sem nenhum campo novo na
// evidência (garante zero regressão para todo Set sem este dado ou com dado corrompido).
export function isValidCollectorTotal(value: number | null | undefined): value is number {
  return typeof value === "number" && Number.isFinite(value) && Number.isInteger(value) && value > 0;
}

// Fix P14.2.1 (2026-08-19, mesmo dia, correção pós-piloto real de Fabrício): a JustTCG pode
// retornar `release_date` tanto como data pura (`"2000-02-24"`, formato usado nos testes
// offline originais) quanto como datetime ISO completo (`"2000-02-24T00:00:00.000Z"`, formato
// real observado no piloto de BASE4 — causa raiz confirmada do `SET_NOT_FOUND(BASE4)`, já que
// `resolveSetMatchV2` comparava a string inteira contra `card_set.release_date` local, que o
// Postgres sempre serializa como `YYYY-MM-DD`). Normaliza para `YYYY-MM-DD` extraindo o
// prefixo por regex — nunca via `new Date()`/`toISOString()`, que dependeriam do fuso horário
// do processo e poderiam deslocar o dia civil. Retorna null se o valor estiver ausente ou não
// seguir o formato esperado; um Set sem `release_date` normalizável nunca entra em `allSets`
// com um valor comparável, então nunca é confirmado automaticamente (mesma disciplina de
// "nunca confirmar" já aplicada a números de coleção ausentes/inválidos em
// isUsableExternalNumber()).
export function normalizeExternalSetReleaseDate(raw: string | null | undefined): string | null {
  if (typeof raw !== "string") return null;
  const match = raw.match(/^(\d{4}-\d{2}-\d{2})/);
  return match ? match[1] : null;
}

// Fronteira de entrada da JustTCG (fix P14.2.1): ponto único de normalização — todo Set vindo
// da API passa por aqui antes de qualquer resolução de correspondência. resolveSetMatchV2()/
// classifySetForExpansionPlan() e os testes de fixture nunca lidam com o formato bruto da
// API; o valor bruto é preservado em `release_date_raw` para ficar disponível na evidência de
// matching.
export function normalizeJustTcgSets(rawSets: JustTcgSet[]): JustTcgSet[] {
  return rawSets.map((s) => ({
    ...s,
    release_date_raw: s.release_date,
    release_date: normalizeExternalSetReleaseDate(s.release_date) ?? undefined,
  }));
}
