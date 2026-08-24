"use client";

import { Loader2, Printer } from "lucide-react";
import { Button } from "@/components/ui/button";
import { useValorPorSetPrint } from "@/components/pricing/valor-por-set-print-context";

/**
 * Substitui `RelatorioPrintButton` genérico só em "Valor por Set" — aqui o
 * clique precisa disparar o carregamento do Set completo (ver
 * `ValorPorSetPrintProvider`) antes de chamar `window.print()`, não um
 * `window.print()` direto. Mesmo posicionamento/visual do botão genérico
 * (`print:hidden`, `variant="outline"`, `size="sm"`).
 */
export function ValorPorSetPrintButton() {
  const { status, triggerPrint } = useValorPorSetPrint();
  const loading = status === "loading";

  return (
    <div className="flex flex-col items-end gap-1 print:hidden">
      <Button type="button" variant="outline" size="sm" disabled={loading} onClick={triggerPrint}>
        {loading ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Printer className="h-3.5 w-3.5" />}
        {loading ? "Preparando impressão…" : "Imprimir"}
      </Button>
      {status === "error" && (
        <p className="text-xs text-destructive">Não foi possível carregar o Set completo. Tente novamente.</p>
      )}
    </div>
  );
}
