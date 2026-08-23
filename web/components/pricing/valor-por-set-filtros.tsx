"use client";

import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { Select } from "@/components/ui/select";
import type { CardCondition, PricingReportCurrency } from "@/lib/pricing/queries";

/** Condição/moeda de "Valor por Set" — mesmo padrão de `PrecoPorCartaFiltros`, sem os presets de dias (este relatório não tem série temporal). */
export function ValorPorSetFiltros({
  conditions,
  conditionId,
  currency,
}: {
  conditions: CardCondition[];
  conditionId: string;
  currency: PricingReportCurrency;
}) {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();

  function pushParam(key: string, value: string) {
    const params = new URLSearchParams(searchParams.toString());
    params.set(key, value);
    router.push(`${pathname}?${params.toString()}`);
  }

  return (
    <div className="flex flex-wrap items-center gap-3">
      <div className="flex items-center gap-1.5">
        <label className="text-xs text-muted-foreground" htmlFor="valor-set-condicao">
          Condição
        </label>
        <Select
          id="valor-set-condicao"
          value={conditionId}
          onChange={(event) => pushParam("condition", event.target.value)}
          className="h-9 w-40 text-xs"
        >
          {conditions.map((condition) => (
            <option key={condition.id} value={condition.id}>
              {condition.name}
            </option>
          ))}
        </Select>
      </div>

      <div className="flex items-center gap-1.5">
        <label className="text-xs text-muted-foreground" htmlFor="valor-set-moeda">
          Moeda
        </label>
        <Select
          id="valor-set-moeda"
          value={currency}
          onChange={(event) => pushParam("currency", event.target.value)}
          className="h-9 w-32 text-xs"
        >
          <option value="BRL">BRL — Real</option>
          <option value="USD">USD — Dólar</option>
        </Select>
      </div>
    </div>
  );
}
