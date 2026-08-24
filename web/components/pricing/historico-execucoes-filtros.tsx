"use client";

import { ChevronDown } from "lucide-react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { useTransition } from "react";
import type { ReactNode } from "react";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import type { PricingCardSetOption } from "@/lib/pricing/queries";

const STATUS_OPTIONS = [
  { value: "COMPLETED", label: "Concluída" },
  { value: "COMPLETED_WITH_ERRORS", label: "Concluída com erros" },
  { value: "FAILED", label: "Falhou" },
];

/**
 * Bloco rotulado — label discreto (uppercase, pequeno) acima do controle.
 * v1.1 (2026-08-23, feedback de Fabrício: "área de filtros visualmente
 * parecida com formulário cru") — sem isso, Status/Set/período ficavam sem
 * contexto visual próprio, com hierarquia igual à de qualquer form solto.
 * `gap-1` mantém a altura total da faixa praticamente igual à versão sem
 * label (label em `text-[10px]` + `leading-none`).
 */
function FilterField({ label, htmlFor, children }: { label: string; htmlFor?: string; children: ReactNode }) {
  return (
    <div className="flex shrink-0 flex-col gap-1">
      <label
        htmlFor={htmlFor}
        className="text-[10px] font-medium uppercase leading-none tracking-wide text-muted-foreground"
      >
        {label}
      </label>
      {children}
    </div>
  );
}

function FilterSelect({
  value,
  onChange,
  ariaLabel,
  id,
  children,
}: {
  value: string;
  onChange: (value: string) => void;
  ariaLabel: string;
  id?: string;
  children: ReactNode;
}) {
  return (
    <div className="relative">
      <Select
        id={id}
        value={value}
        onChange={(event) => onChange(event.target.value)}
        aria-label={ariaLabel}
        className="h-9 min-w-[10rem] appearance-none bg-surface-muted py-1 pl-3 pr-8 text-xs"
      >
        {children}
      </Select>
      <ChevronDown
        className="pointer-events-none absolute right-2.5 top-1/2 h-3.5 w-3.5 -translate-y-1/2 text-muted-foreground"
        aria-hidden="true"
      />
    </div>
  );
}

/**
 * Filtros de Histórico de Execuções — status/Set/período, mesmo padrão
 * URL-driven de `PendenciasFiltros` (troca de filtro zera `page`). Período
 * usa dois `<input type="date">` nativos em vez de um date-picker próprio —
 * suficiente para o volume/uso desta tela administrativa, sem depender de
 * mais uma dependência.
 */
export function HistoricoExecucoesFiltros({
  status,
  cardSetId,
  dateFrom,
  dateTo,
  cardSets,
}: {
  status: string;
  cardSetId: string;
  dateFrom: string;
  dateTo: string;
  cardSets: PricingCardSetOption[];
}) {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const [, startTransition] = useTransition();

  function pushParams(next: Record<string, string | undefined>) {
    const params = new URLSearchParams(searchParams.toString());
    for (const [key, value] of Object.entries(next)) {
      if (value) params.set(key, value);
      else params.delete(key);
    }
    params.delete("page");
    startTransition(() => {
      router.replace(`${pathname}?${params.toString()}`);
    });
  }

  return (
    <div className="flex flex-wrap items-end gap-3">
      <FilterField label="Status" htmlFor="historico-filtro-status">
        <FilterSelect
          id="historico-filtro-status"
          value={status}
          onChange={(value) => pushParams({ status: value || undefined })}
          ariaLabel="Filtrar por Status"
        >
          <option value="">Todos os Status</option>
          {STATUS_OPTIONS.map((option) => (
            <option key={option.value} value={option.value}>
              {option.label}
            </option>
          ))}
        </FilterSelect>
      </FilterField>

      <FilterField label="Set" htmlFor="historico-filtro-set">
        <FilterSelect
          id="historico-filtro-set"
          value={cardSetId}
          onChange={(value) => pushParams({ set: value || undefined })}
          ariaLabel="Filtrar por Set"
        >
          <option value="">Todos os Sets</option>
          {cardSets.map((cardSet) => (
            <option key={cardSet.id} value={cardSet.id}>
              {cardSet.name} ({cardSet.code})
            </option>
          ))}
        </FilterSelect>
      </FilterField>

      <div className="flex items-end gap-1.5">
        <FilterField label="Data inicial" htmlFor="historico-filtro-de">
          <Input
            id="historico-filtro-de"
            type="date"
            value={dateFrom}
            onChange={(event) => pushParams({ de: event.target.value || undefined })}
            className="h-9 w-[9.5rem] bg-surface-muted text-xs"
            aria-label="Data inicial"
          />
        </FilterField>
        <span className="pb-2 text-xs text-muted-foreground">até</span>
        <FilterField label="Data final" htmlFor="historico-filtro-ate">
          <Input
            id="historico-filtro-ate"
            type="date"
            value={dateTo}
            onChange={(event) => pushParams({ ate: event.target.value || undefined })}
            className="h-9 w-[9.5rem] bg-surface-muted text-xs"
            aria-label="Data final"
          />
        </FilterField>
      </div>
    </div>
  );
}
