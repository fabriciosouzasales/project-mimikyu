"use client";

import { Trash2 } from "lucide-react";
import { Button } from "@/components/ui/button";

/** Barra "N selecionados" + ações em massa. Extraída do ciclo de Game para reuso. */
export function BulkSelectionBar({
  count,
  nounSingular,
  nounPlural,
  onClear,
  onDeleteClick,
}: {
  count: number;
  nounSingular: string;
  nounPlural: string;
  onClear: () => void;
  onDeleteClick: () => void;
}) {
  return (
    <div className="flex items-center justify-between rounded-md border border-border bg-surface-muted px-3 py-2">
      <p className="text-xs text-muted-foreground">
        {count} {count === 1 ? nounSingular : nounPlural}
      </p>
      <div className="flex gap-2">
        <Button type="button" variant="outline" size="sm" onClick={onClear}>
          Limpar seleção
        </Button>
        <Button type="button" variant="destructive" size="sm" onClick={onDeleteClick}>
          <Trash2 className="h-3.5 w-3.5" />
          Excluir selecionados
        </Button>
      </div>
    </div>
  );
}
