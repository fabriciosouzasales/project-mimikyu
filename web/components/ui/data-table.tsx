import { forwardRef } from "react";
import type { HTMLAttributes, TdHTMLAttributes, ThHTMLAttributes } from "react";
import { cn } from "@/lib/utils";

/**
 * Primitives de tabela — Fundação visual, Ciclo B (2026-07-30, ver
 * STD-004). Deliberadamente pequenas (só a mecânica repetida em
 * `JogosTable`/`ExpansoesTable`/`UsersTable`: `<table>` base, linha de
 * cabeçalho, célula de cabeçalho, linha de dado com destaque temporário,
 * célula de dado) — nenhuma DataTable universal com ordenação/seleção
 * genéricas embutidas. Ação de linha continua sendo o `Button`
 * `variant="outline" size="icon-sm"` que já existe, sem um componente novo
 * só para isso. Paginação fica fora desta rodada: nenhuma tela do piloto
 * precisa dela — `UsersTable` já tem sua própria versão inline, a
 * formalizar quando essa tela for migrada (Ciclo E).
 */
export const DataTable = forwardRef<HTMLTableElement, HTMLAttributes<HTMLTableElement>>(
  ({ className, ...props }, ref) => <table ref={ref} className={cn("w-full text-sm", className)} {...props} />,
);
DataTable.displayName = "DataTable";

export function DataTableHead({ className, ...props }: HTMLAttributes<HTMLTableSectionElement>) {
  return <thead className={className} {...props} />;
}

/** Linha de cabeçalho — envolve as `DataTableHeadCell`. */
export function DataTableHeadRow({ className, ...props }: HTMLAttributes<HTMLTableRowElement>) {
  return (
    <tr
      className={cn(
        "border-b border-border text-left text-[11px] font-normal uppercase tracking-wide text-muted-foreground",
        className,
      )}
      {...props}
    />
  );
}

export function DataTableHeadCell({
  className,
  align = "left",
  ...props
}: ThHTMLAttributes<HTMLTableCellElement> & { align?: "left" | "center" | "right" }) {
  return (
    <th
      className={cn(
        "py-1.5 pr-3 font-normal last:pr-0",
        align === "center" && "text-center",
        align === "right" && "text-right",
        className,
      )}
      {...props}
    />
  );
}

export function DataTableRow({
  className,
  highlighted,
  ...props
}: HTMLAttributes<HTMLTableRowElement> & { highlighted?: boolean }) {
  return (
    <tr
      className={cn(
        "border-b border-border/60 transition-colors duration-700 last:border-b-0",
        highlighted && "bg-primary/5",
        className,
      )}
      {...props}
    />
  );
}

export function DataTableCell({
  className,
  align = "left",
  ...props
}: TdHTMLAttributes<HTMLTableCellElement> & { align?: "left" | "center" | "right" }) {
  return (
    <td
      className={cn(
        "py-2 pr-3 text-muted-foreground last:pr-0",
        align === "center" && "text-center",
        align === "right" && "text-right",
        className,
      )}
      {...props}
    />
  );
}
