"use client";

import { createContext, useCallback, useContext, useEffect, useRef, useState, type ReactNode } from "react";
import { fetchAllPricingReportSetCards } from "@/lib/pricing/valor-por-set-print-client";
import type { PricingReportCurrency, PricingReportSetCardItem } from "@/lib/pricing/queries";

type PrintStatus = "idle" | "loading" | "ready" | "error";

type ValorPorSetPrintContextValue = {
  status: PrintStatus;
  allItems: PricingReportSetCardItem[] | null;
  triggerPrint: () => void;
};

const ValorPorSetPrintContext = createContext<ValorPorSetPrintContextValue | null>(null);

/**
 * Desacopla o botão "Imprimir" (no `PageHeader`, topo da tela) da folha
 * impressa (`ValorPorSetPrintFolha`, renderizada mais abaixo na árvore) sem
 * precisar movê-los fisicamente para o mesmo componente — ambos consomem
 * este Context via `useValorPorSetPrint()`.
 *
 * Requisito de performance (rodada de impressão, 2026-08-23): a tela normal
 * continua paginada em 20 cartas (fetch server-side em `page.tsx`, inalte-
 * rado). O conjunto COMPLETO do Set só é buscado quando o usuário clica em
 * "Imprimir" — nunca na carga normal da página — via
 * `fetchAllPricingReportSetCards` (client-side, mesma RPC
 * `admin_get_pricing_report_set_cards`, em lotes de 100 respeitando o cap
 * já existente no banco). `window.print()` só é chamado depois que os dados
 * chegam (`useEffect` reagindo a `status === "ready"`, guardado por `ref`
 * para nunca imprimir duas vezes pelo mesmo carregamento).
 *
 * Limitação conhecida e aceita: imprimir via atalho nativo do navegador
 * (Ctrl+P) sem antes clicar em "Imprimir" mostra só o que já estiver
 * carregado (nada, no primeiro acesso) — mesmo trade-off already implícito
 * em qualquer relatório que dependesse de um fetch sob demanda. O botão
 * "Imprimir" é o fluxo suportado; states de loading/erro no próprio botão
 * deixam isso explícito para o usuário.
 */
export function ValorPorSetPrintProvider({
  cardSetId,
  conditionId,
  currency,
  children,
}: {
  cardSetId: string | null;
  conditionId: string | null;
  currency: PricingReportCurrency | null;
  children: ReactNode;
}) {
  const [status, setStatus] = useState<PrintStatus>("idle");
  const [allItems, setAllItems] = useState<PricingReportSetCardItem[] | null>(null);
  const printedForRef = useRef<PricingReportSetCardItem[] | null>(null);

  const triggerPrint = useCallback(() => {
    if (!cardSetId || !conditionId || !currency || status === "loading") return;

    setStatus("loading");
    fetchAllPricingReportSetCards({ cardSetId, conditionId, currency })
      .then((result) => {
        if (!result) {
          setStatus("error");
          return;
        }
        setAllItems(result.items);
        setStatus("ready");
      })
      .catch(() => setStatus("error"));
  }, [cardSetId, conditionId, currency, status]);

  useEffect(() => {
    if (status === "ready" && allItems && printedForRef.current !== allItems) {
      printedForRef.current = allItems;
      window.print();
    }
  }, [status, allItems]);

  return (
    <ValorPorSetPrintContext.Provider value={{ status, allItems, triggerPrint }}>
      {children}
    </ValorPorSetPrintContext.Provider>
  );
}

export function useValorPorSetPrint(): ValorPorSetPrintContextValue {
  const ctx = useContext(ValorPorSetPrintContext);
  if (!ctx) {
    throw new Error("useValorPorSetPrint precisa estar dentro de ValorPorSetPrintProvider");
  }
  return ctx;
}
