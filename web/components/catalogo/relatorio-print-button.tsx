"use client";

import { Printer } from "lucide-react";
import { Button } from "@/components/ui/button";

/**
 * Botão "Imprimir" dos relatórios da Central de Relatórios — `window.print()`
 * nativo do navegador, sem motor de PDF próprio (V1 aprovada por Fabrício,
 * 2026-08-09). `print:hidden` porque não faz sentido aparecer na própria
 * folha impressa.
 */
export function RelatorioPrintButton() {
  return (
    <Button type="button" variant="outline" size="sm" className="print:hidden" onClick={() => window.print()}>
      <Printer className="h-3.5 w-3.5" />
      Imprimir
    </Button>
  );
}
