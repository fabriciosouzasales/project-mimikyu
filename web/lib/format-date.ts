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

/** Mesmo formato de formatarData(), acrescido do horário (ex.: "26 jul 2026, 14:32"). */
export function formatarDataHora(value: string): string {
  const date = new Date(value);

  if (Number.isNaN(date.getTime())) {
    return "—";
  }

  const hora = date.toLocaleTimeString("pt-BR", { hour: "2-digit", minute: "2-digit" });

  return `${formatarData(value)}, ${hora}`;
}
