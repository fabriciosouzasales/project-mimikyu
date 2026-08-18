// Project Mimikyu — supabase/functions/_shared/pricing-ptax/url.ts
// Construção segura da URL do BCB — Incremento P13.2.
//
// Sintaxe OData e nome exato de parâmetro (`dataFinalCotacao`, não `dataFinal`)
// preservados LITERALMENTE do script sync-ptax-fx-rate.ts (Incremento P9) — essa
// sintaxe foi confirmada por uma chamada de rede real bem-sucedida (Invoke-RestMethod,
// executado por Fabrício, 2026-08-17, 6/6 cotações retornadas). Esta rodada (P13.2)
// não faz nenhuma chamada real ao BCB — a URL não foi alterada, só extraída para este
// módulo compartilhado. Não reordenar/renomear parâmetros nem ampliar `$select` sem
// reconfirmar contra uma nova chamada real.

import type { CivilDate } from "./types.ts";

export const BCB_PTAX_API_BASE =
  "https://olinda.bcb.gov.br/olinda/servico/PTAX/versao/v1/odata";

const CIVIL_DATE_FORMAT = /^\d{4}-\d{2}-\d{2}$/;

// A API Olinda exige MM-DD-YYYY nos literais da query string — o núcleo trabalha
// internamente só com datas civis YYYY-MM-DD (CivilDate); a conversão é só na borda,
// aqui.
function toBcbRequestDate(civilDate: CivilDate): string {
  const [y, m, d] = civilDate.split("-");
  return `${m}-${d}-${y}`;
}

export function buildPtaxPeriodUrl(
  startDate: CivilDate,
  endDate: CivilDate,
): string {
  if (!CIVIL_DATE_FORMAT.test(startDate)) {
    throw new Error(
      `START_DATE_FORMATO_INVALIDO: '${startDate}' não está no formato YYYY-MM-DD.`,
    );
  }
  if (!CIVIL_DATE_FORMAT.test(endDate)) {
    throw new Error(
      `END_DATE_FORMATO_INVALIDO: '${endDate}' não está no formato YYYY-MM-DD.`,
    );
  }
  const dataInicial = toBcbRequestDate(startDate);
  const dataFinalCotacao = toBcbRequestDate(endDate);
  return (
    `${BCB_PTAX_API_BASE}/CotacaoDolarPeriodo(dataInicial=@dataInicial,dataFinalCotacao=@dataFinalCotacao)` +
    `?@dataInicial='${dataInicial}'&@dataFinalCotacao='${dataFinalCotacao}'` +
    `&$format=json&$select=cotacaoCompra,cotacaoVenda,dataHoraCotacao`
  );
}
