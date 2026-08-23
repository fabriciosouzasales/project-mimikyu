"use client";

import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { Select } from "@/components/ui/select";
import { cn } from "@/lib/utils";
import type { CardCondition, PricingReportCurrency } from "@/lib/pricing/queries";

const DAY_PRESETS = [30, 90, 180, 365] as const;

/**
 * Controles de Preço por Carta (Bloco 5, migration 3943) — condição, moeda
 * e presets de histórico, todos URL-driven (mesmo padrão de
 * `PendenciasFiltros`: cada troca escreve na querystring e o Server
 * Component da página refaz a leitura). Sem debounce — são só selects/pills,
 * nunca texto livre.
 */
export function PrecoPorCartaFiltros({
  conditions,
  conditionId,
  currency,
  historyDays,
}: {
  conditions: CardCondition[];
  conditionId: string;
  currency: PricingReportCurrency;
  historyDays: number;
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
        <label className="text-xs text-muted-foreground" htmlFor="preco-carta-condicao">
          Condição
        </label>
        <Select
          id="preco-carta-condicao"
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
        <label className="text-xs text-muted-foreground" htmlFor="preco-carta-moeda">
          Moeda
        </label>
        <Select
          id="preco-carta-moeda"
          value={currency}
          onChange={(event) => pushParam("currency", event.target.value)}
          className="h-9 w-32 text-xs"
        >
          <option value="BRL">BRL — Real</option>
          <option value="USD">USD — Dólar</option>
        </Select>
      </div>

      <div className="flex items-center gap-1 rounded-lg border border-border bg-surface-muted p-0.5">
        {DAY_PRESETS.map((preset) => (
          <button
            key={preset}
            type="button"
            onClick={() => pushParam("days", String(preset))}
            className={cn(
              "rounded-md px-2.5 py-1 text-xs font-medium transition-colors",
              historyDays === preset ? "bg-surface text-foreground shadow-subtle" : "text-muted-foreground hover:text-foreground",
            )}
          >
            {preset}d
          </button>
        ))}
      </div>
    </div>
  );
}
