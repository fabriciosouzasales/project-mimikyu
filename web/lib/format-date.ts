/**
 * Formata uma data para exibição em telas administrativas — deliberadamente
 * NÃO no formato numérico "DD/MM/AAAA" (pedido explícito de Fabrício,
 * 2026-07-26), para não ficar ambíguo/confundível com outros formatos
 * numéricos de data já usados em inputs. Ex.: "26 jul 2026".
 */
export function formatarData(value: string): string {
  const date = new Date(value);

  if (Number.isNaN(date.getTime())) {
    return "—";
  }

  const dia = date.toLocaleDateString("pt-BR", { day: "2-digit" });
  const mes = date.toLocaleDateString("pt-BR", { month: "short" }).replace(".", "");
  const ano = date.toLocaleDateString("pt-BR", { year: "numeric" });

  return `${dia} ${mes} ${ano}`;
}

/**
 * Formata uma data civil pura (coluna `DATE` do Postgres, ex.: `pricing_fx_rate.rate_date`,
 * formato `"AAAA-MM-DD"`, sem hora/fuso) — nunca via `new Date(value)` puro,
 * que interpreta a string como meia-noite UTC e pode exibir o dia anterior em
 * fusos negativos como o do Brasil (UTC-3). Corrige um risco identificado e
 * deliberadamente aceito na primeira versão do painel de preços (P12,
 * 2026-08-17) — nunca chegou a se manifestar visivelmente porque o dado só
 * era exibido em relatórios internos até então, mas o redesenho do painel
 * (2026-08-18) tornou isso público o bastante para valer a correção.
 */
export function formatarDataCivil(value: string): string {
  const match = /^(\d{4})-(\d{2})-(\d{2})/.exec(value);
  if (!match) return "—";

  const [, anoStr, mesStr, diaStr] = match;
  const date = new Date(Number(anoStr), Number(mesStr) - 1, Number(diaStr));

  if (Number.isNaN(date.getTime())) {
    return "—";
  }

  const dia = date.toLocaleDateString("pt-BR", { day: "2-digit" });
  const mes = date.toLocaleDateString("pt-BR", { month: "short" }).replace(".", "");
  const ano = date.toLocaleDateString("pt-BR", { year: "numeric" });

  return `${dia} ${mes} ${ano}`;
}

/** Mesmo formato de formatarData(), acrescido do horário (ex.: "26 jul 2026, 14:32"). */
export function formatarDataHora(value: string): string {
  const date = new Date(value);

  if (Number.isNaN(date.getTime())) {
    return "—";
  }

  const hora = date.toLocaleTimeString("pt-BR", { hour: "2-digit", minute: "2-digit" });

  return `${formatarData(value)}, ${hora}`;
}
