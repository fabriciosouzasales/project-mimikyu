// Project Mimikyu — supabase/functions/_shared/pricing-ptax/select-closing.ts
// Seleção da cotação PTAX de fechamento por data — Incremento P13.2.
//
// Decisão de design registrada nesta rodada: o endpoint CotacaoDolarPeriodo,
// confirmado por chamada real em 2026-08-17 (ver url.ts), não expõe `tipoBoletim` no
// contrato já validado — a documentação pública do BCB registra esse campo para o
// dataset "todos os boletins diários" (CotacaoMoedaDia/CotacaoMoedaPeriodo), um
// recurso DIFERENTE do usado por este módulo. Ampliar `$select` para incluir
// `tipoBoletim` no endpoint atual exigiria reconfirmar contra uma nova chamada real,
// fora de escopo aqui ("não fazer chamada real ao BCB durante a validação").
//
// Na ausência desse campo, a seleção de fechamento é feita por ordenação cronológica:
// dentre os itens que caem na mesma rate_date, o item com o `dataHoraCotacao` mais
// recente é tratado como o fechamento. Isso é correto tanto no comportamento real hoje
// confirmado (uma cotação por dia — o único item da data "é" o fechamento por
// definição) quanto num cenário defensivo futuro em que o mesmo endpoint passe a
// devolver múltiplos boletins por dia sem aviso prévio.

import type { InvalidDetail, PtaxRate, PtaxRawItem } from "./types.ts";
import { extractRateDate } from "./validate.ts";

export interface SelectClosingResult {
  rates: PtaxRate[];
  invalidDetails: InvalidDetail[];
}

export function selectClosingRatesByDate(
  items: PtaxRawItem[],
): SelectClosingResult {
  const byDate = new Map<string, { rate: number; timestamp: number }>();
  const invalidDetails: InvalidDetail[] = [];

  for (const item of items) {
    const extracted = extractRateDate(item.dataHoraCotacao);
    if (extracted.status === "INVALID") {
      invalidDetails.push({ reason: extracted.reason, raw: item });
      continue;
    }
    if (!(item.cotacaoVenda > 0)) {
      invalidDetails.push({
        reason:
          `RATE_NAO_POSITIVA: cotacaoVenda=${item.cotacaoVenda} para ${extracted.rateDate}.`,
        raw: item,
      });
      continue;
    }

    const parsedTimestamp = Date.parse(item.dataHoraCotacao.replace(" ", "T"));
    const timestamp = Number.isFinite(parsedTimestamp)
      ? parsedTimestamp
      : Number.NEGATIVE_INFINITY;
    const current = byDate.get(extracted.rateDate);

    // >= (não >) de propósito: entre dois itens com timestamp idêntico (ou ambos
    // ilegíveis), o último da lista prevalece — mesma ordem em que o BCB os devolveu,
    // nunca uma ordenação adicional silenciosa por outro critério.
    if (!current || timestamp >= current.timestamp) {
      byDate.set(extracted.rateDate, { rate: item.cotacaoVenda, timestamp });
    }
  }

  const rates: PtaxRate[] = Array.from(byDate.entries())
    .map(([rateDate, v]) => ({ rateDate, rate: v.rate }))
    .sort((
      a,
      b,
    ) => (a.rateDate < b.rateDate ? -1 : a.rateDate > b.rateDate ? 1 : 0));

  return { rates, invalidDetails };
}
