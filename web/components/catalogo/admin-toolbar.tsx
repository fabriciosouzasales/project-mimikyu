"use client";

import { Plus } from "lucide-react";
import { Button } from "@/components/ui/button";

/**
 * Título da página + botão de criação, fora do card da tabela (pedido de
 * Fabrício no ciclo de Game, 2026-07-26). Extraído para reuso direto pelos
 * ciclos de Expansion/Card Set.
 */
export function AdminToolbar({
  title,
  createLabel,
  onCreateClick,
}: {
  title: string;
  createLabel: string;
  onCreateClick: () => void;
}) {
  return (
    <div className="flex items-center justify-between">
      <h1 className="font-heading text-xl font-medium text-foreground">{title}</h1>
      <Button type="button" variant="outline-primary" size="sm" onClick={onCreateClick}>
        <Plus className="h-3.5 w-3.5" />
        {createLabel}
      </Button>
    </div>
  );
}
