// Project Mimikyu — supabase/functions/_shared/pricing-ptax/period.ts
// Cálculo e validação de período — Incremento P13.2.

import type { CivilDate, PtaxPeriod } from "./types.ts";

const CIVIL_DATE_FORMAT = /^\d{4}-\d{2}-\d{2}$/;

// Janela padrão: exatamente 10 datas corridas, inclusive (decisão registrada nesta
// rodada, P13.2) — data de referência (civil, America/Sao_Paulo, calculada pelo
// chamador) + nove dias anteriores. Não considera calendário de dias úteis: dias sem
// pregão/feriado simplesmente não aparecem na resposta do BCB, mesma regra já
// registrada em 05f-pricing.md, Incremento P9.
export const DEFAULT_WINDOW_DAYS = 10;

// Teto explícito para override manual (backfill controlado) — decisão desta rodada,
// documentada em 05f-pricing.md. Evita que um erro de digitação (ex.: ano trocado)
// dispare uma janela de milhares de dias contra a API do BCB sem nenhum limite.
export const MAX_OVERRIDE_WINDOW_DAYS = 90;

// new Date(Date.UTC(...)) normaliza datas fora do calendário (ex.: 2026-02-30 vira
// 2026-03-02) em vez de rejeitá-las — comparar os componentes de volta é o que torna
// esta validação estrita (rejeita explicitamente, nunca aceita uma data "corrigida"
// silenciosamente). Cobre também anos bissextos corretamente (Date.UTC já sabe que
// 2028-02-29 é válido e 2027-02-29 não é, sem lógica adicional aqui).
export function isValidCivilDate(value: string): boolean {
  if (!CIVIL_DATE_FORMAT.test(value)) return false;
  const [y, m, d] = value.split("-").map(Number);
  const date = new Date(Date.UTC(y, m - 1, d));
  return date.getUTCFullYear() === y && date.getUTCMonth() === m - 1 &&
    date.getUTCDate() === d;
}

// Aritmética de data sempre em UTC (nunca no fuso local do processo) — o valor de
// entrada já é uma data civil resolvida pelo chamador (America/Sao_Paulo ou uma data
// de override explícita), então tratá-la como UTC-meia-noite aqui é seguro e evita
// qualquer efeito de fuso horário/DST na soma de dias.
export function addDaysUTC(civilDate: CivilDate, days: number): CivilDate {
  const [y, m, d] = civilDate.split("-").map(Number);
  const date = new Date(Date.UTC(y, m - 1, d));
  date.setUTCDate(date.getUTCDate() + days);
  const yyyy = date.getUTCFullYear().toString().padStart(4, "0");
  const mm = (date.getUTCMonth() + 1).toString().padStart(2, "0");
  const dd = date.getUTCDate().toString().padStart(2, "0");
  return `${yyyy}-${mm}-${dd}`;
}

export function diffDaysUTC(start: CivilDate, end: CivilDate): number {
  const [ys, ms, ds] = start.split("-").map(Number);
  const [ye, me, de] = end.split("-").map(Number);
  const a = Date.UTC(ys, ms - 1, ds);
  const b = Date.UTC(ye, me - 1, de);
  return Math.round((b - a) / 86_400_000);
}

export type PeriodResolution = { status: "OK"; period: PtaxPeriod } | {
  status: "INVALID";
  reason: string;
};

export function resolveDefaultPeriod(
  referenceDate: CivilDate,
): PeriodResolution {
  if (!isValidCivilDate(referenceDate)) {
    return {
      status: "INVALID",
      reason:
        `REFERENCE_DATE_INVALIDA: '${referenceDate}' não é uma data civil YYYY-MM-DD válida.`,
    };
  }
  const startDate = addDaysUTC(referenceDate, -(DEFAULT_WINDOW_DAYS - 1));
  return { status: "OK", period: { startDate, endDate: referenceDate } };
}

// Override explícito de início/fim para backfill manual controlado — validação
// estrita de formato, ordem e tamanho máximo. Nunca abre uma janela silenciosamente
// maior que MAX_OVERRIDE_WINDOW_DAYS nem aceita start > end.
export function resolveOverridePeriod(
  startDate: string,
  endDate: string,
): PeriodResolution {
  if (!isValidCivilDate(startDate)) {
    return {
      status: "INVALID",
      reason:
        `OVERRIDE_START_INVALIDO: '${startDate}' não é uma data civil YYYY-MM-DD válida.`,
    };
  }
  if (!isValidCivilDate(endDate)) {
    return {
      status: "INVALID",
      reason:
        `OVERRIDE_END_INVALIDO: '${endDate}' não é uma data civil YYYY-MM-DD válida.`,
    };
  }
  if (diffDaysUTC(startDate, endDate) < 0) {
    return {
      status: "INVALID",
      reason:
        `OVERRIDE_ORDEM_INVALIDA: start (${startDate}) é posterior a end (${endDate}).`,
    };
  }
  const totalDays = diffDaysUTC(startDate, endDate) + 1;
  if (totalDays > MAX_OVERRIDE_WINDOW_DAYS) {
    return {
      status: "INVALID",
      reason:
        `OVERRIDE_PERIODO_MUITO_LONGO: ${totalDays} dias solicitados, máximo permitido é ${MAX_OVERRIDE_WINDOW_DAYS}.`,
    };
  }
  return { status: "OK", period: { startDate, endDate } };
}

export function enumerateCivilDates(period: PtaxPeriod): CivilDate[] {
  const total = diffDaysUTC(period.startDate, period.endDate) + 1;
  return Array.from(
    { length: total },
    (_, i) => addDaysUTC(period.startDate, i),
  );
}
