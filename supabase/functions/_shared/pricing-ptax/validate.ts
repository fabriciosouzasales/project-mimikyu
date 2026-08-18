// Project Mimikyu — supabase/functions/_shared/pricing-ptax/validate.ts
// Validação e normalização defensiva da resposta do BCB — Incremento P13.2.
//
// Mesma disciplina do script original (P9): nunca presumir a forma da resposta
// silenciosamente. Uma resposta que não bate exatamente com o formato documentado
// (`{"value": [{"cotacaoCompra", "cotacaoVenda", "dataHoraCotacao"}, ...]}`) é tratada
// como FALHA FUNCIONAL, nunca como um erro técnico de rede nem como um parsing
// best-effort.

import type { PtaxRawItem } from "./types.ts";

export type ShapeValidationResult = { status: "OK"; items: PtaxRawItem[] } | {
  status: "INVALID";
  reason: string;
};

export function validatePtaxResponseShape(
  json: unknown,
): ShapeValidationResult {
  if (!json || typeof json !== "object" || !("value" in json)) {
    return {
      status: "INVALID",
      reason: "BCB_RESPONSE_SHAPE_INVALID: campo 'value' ausente na resposta.",
    };
  }
  const value = (json as { value: unknown }).value;
  if (!Array.isArray(value)) {
    return {
      status: "INVALID",
      reason: "BCB_RESPONSE_SHAPE_INVALID: 'value' não é um array.",
    };
  }
  const items: PtaxRawItem[] = [];
  for (let index = 0; index < value.length; index++) {
    const item = value[index];
    if (!item || typeof item !== "object") {
      return {
        status: "INVALID",
        reason: `BCB_RESPONSE_SHAPE_INVALID: item [${index}] não é um objeto.`,
      };
    }
    const obj = item as Record<string, unknown>;
    if (typeof obj.cotacaoCompra !== "number") {
      return {
        status: "INVALID",
        reason:
          `BCB_RESPONSE_SHAPE_INVALID: item [${index}].cotacaoCompra não é number.`,
      };
    }
    if (typeof obj.cotacaoVenda !== "number") {
      return {
        status: "INVALID",
        reason:
          `BCB_RESPONSE_SHAPE_INVALID: item [${index}].cotacaoVenda não é number.`,
      };
    }
    if (typeof obj.dataHoraCotacao !== "string" || !obj.dataHoraCotacao) {
      return {
        status: "INVALID",
        reason:
          `BCB_RESPONSE_SHAPE_INVALID: item [${index}].dataHoraCotacao ausente/inválido.`,
      };
    }
    items.push({
      cotacaoCompra: obj.cotacaoCompra,
      cotacaoVenda: obj.cotacaoVenda,
      dataHoraCotacao: obj.dataHoraCotacao,
    });
  }
  return { status: "OK", items };
}

export type RateDateExtraction = { status: "OK"; rateDate: string } | {
  status: "INVALID";
  reason: string;
};

// Extrai a data efetiva (YYYY-MM-DD) de dataHoraCotacao (formato observado:
// "YYYY-MM-DD HH:MM:SS.mmm", possivelmente com "T" no lugar do espaço) — nunca usa a
// data em que o script/função rodou. Decisão registrada em 05f-pricing.md, Incremento P9.
export function extractRateDate(dataHoraCotacao: string): RateDateExtraction {
  const dataParte = dataHoraCotacao.split(/[T ]/)[0];
  if (!/^\d{4}-\d{2}-\d{2}$/.test(dataParte)) {
    return {
      status: "INVALID",
      reason:
        `BCB_RESPONSE_SHAPE_INVALID: dataHoraCotacao '${dataHoraCotacao}' não contém uma data YYYY-MM-DD reconhecível.`,
    };
  }
  return { status: "OK", rateDate: dataParte };
}
