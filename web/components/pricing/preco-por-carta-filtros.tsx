"use client";

import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { Select } from "@/components/ui/select";
import { cn } from "@/lib/utils";
import type { CardCondition, PricingReportCurrency } from "@/lib/pricing/queries";

const DAY_PRESETS = [30, 90, 180, 365] as const;

/**
 * Controles de Preço por Carta (Bloco 5, migration 3943) — condição e moeda,
 * URL-driven (mesmo padrão de `PendenciasFiltros`: cada troca escreve na
 * querystring e o Server Component da página refaz a leitura). Sem
 * debounce — são só selects, nunca texto livre.
 *
 * v2 (2026-08-23, recomposição "Carta | Histórico de Preço" aprovada por
 * Fabrício) — os presets de período (30/90/180/365) saem daqui e migram para
 * `PrecoPorCartaPeriodoFiltro`, no próprio cabeçalho do gráfico
 * (`preco-por-carta-report.tsx`): "os controles de período podem migrar para
 * o cabeçalho do gráfico... evitar repetir controles em duas áreas". A barra
 * do topo fica só com busca/condição/moeda — "controles da análise", não
 * formulário administrativo.
 */
export function PrecoPorCartaFiltros({
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
    </div>
  );
}

/**
 * Presets de período (30/90/180/365 dias) — extraído de `PrecoPorCartaFiltros`
 * (v2, ver comentário acima) para viver no cabeçalho do gráfico de Histórico
 * de Preço, mais perto do que controla. Mesmo mecanismo URL-driven
 * (`?days=`), duplicado deliberadamente em vez de compartilhar hook com o
 * componente acima — ambos são poucas linhas e evoluem por pedidos visuais
 * distintos (mesma lógica já registrada em `lib/pesquisa/format.ts`).
 */
export function PrecoPorCartaPeriodoFiltro({ historyDays }: { historyDays: number }) {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();

  function pushDays(value: number) {
    const params = new URLSearchParams(searchParams.toString());
    params.set("days", String(value));
    router.push(`${pathname}?${params.toString()}`);
  }

  return (
    <div className="flex items-center gap-1 rounded-lg border border-border bg-surface-muted p-0.5">
      {DAY_PRESETS.map((preset) => (
        <button
          key={preset}
          type="button"
          onClick={() => pushDays(preset)}
          className={cn(
            "rounded-md px-2.5 py-1 text-xs font-medium transition-colors",
            historyDays === preset ? "bg-surface text-foreground shadow-subtle" : "text-muted-foreground hover:text-foreground",
          )}
        >
          {preset}d
        </button>
      ))}
    </div>
  );
}
