"use client";

import { ChevronDown, Search } from "lucide-react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { useEffect, useRef, useState, useTransition } from "react";
import type { ReactNode } from "react";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import type { PricingRefreshPolicyItem } from "@/lib/pricing/queries";

// P16.4.1 (revisão final, migration 3952) — 2 opções novas (ONBOARDING_PENDING/PROCESSING)
// somadas às 3 já existentes, mesmo domínio de refresh_bucket usado nas demais telas de
// Pricing (Visão Geral, Saúde das Fontes, Mapeamentos de Sets).
const STATUS_OPTIONS = [
  { value: "ONBOARDING_PENDING", label: "Aguardando primeira sincronização" },
  { value: "PROCESSING", label: "Sincronizando" },
  { value: "HEALTHY", label: "Saudável" },
  { value: "PROBLEM", label: "Com problema" },
  { value: "PAUSED", label: "Pausado" },
];

function FilterSelect({
  value,
  onChange,
  ariaLabel,
  children,
}: {
  value: string;
  onChange: (value: string) => void;
  ariaLabel: string;
  children: ReactNode;
}) {
  return (
    <div className="relative shrink-0">
      <Select
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
 * Filtros da seção "Estado dos Sets" — mesmo padrão de debounce/URL-driven
 * de `PendenciasFiltros`. Vocabulário de status é o `refresh_bucket` derivado
 * em SQL por `admin_list_pricing_set_refresh_states` via `pricing_derive_refresh_bucket()`
 * (ONBOARDING_PENDING/PROCESSING/HEALTHY/PROBLEM/PAUSED, migration 3952,
 * P16.4.1 revisão final), não o status bruto de `pricing_sync_run`.
 */
export function EstadoSetsFiltros({
  initialSearch,
  status,
  pricingSourceId,
  sources,
}: {
  initialSearch: string;
  status: string;
  pricingSourceId: string;
  sources: PricingRefreshPolicyItem[];
}) {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const [search, setSearch] = useState(initialSearch);
  const [, startTransition] = useTransition();
  const debounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    return () => {
      if (debounceRef.current) clearTimeout(debounceRef.current);
    };
  }, []);

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

  function handleSearchChange(value: string) {
    setSearch(value);
    if (debounceRef.current) clearTimeout(debounceRef.current);
    debounceRef.current = setTimeout(() => {
      pushParams({ q: value.trim() || undefined });
    }, 300);
  }

  return (
    <div className="flex flex-wrap items-center gap-2">
      <div className="relative min-w-[14rem] flex-1">
        <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
        <Input
          value={search}
          onChange={(event) => handleSearchChange(event.target.value)}
          placeholder="Buscar por Set…"
          className="h-9 bg-surface-muted pl-9 text-xs"
          aria-label="Buscar Set"
        />
      </div>

      <FilterSelect value={status} onChange={(value) => pushParams({ status: value || undefined })} ariaLabel="Filtrar por Status">
        <option value="">Todos os Status</option>
        {STATUS_OPTIONS.map((option) => (
          <option key={option.value} value={option.value}>
            {option.label}
          </option>
        ))}
      </FilterSelect>

      {sources.length > 1 && (
        <FilterSelect
          value={pricingSourceId}
          onChange={(value) => pushParams({ source: value || undefined })}
          ariaLabel="Filtrar por Fonte"
        >
          <option value="">Todas as Fontes</option>
          {sources.map((source) => (
            <option key={source.pricingSourceId} value={source.pricingSourceId}>
              {source.pricingSourceName} ({source.pricingSourceCode})
            </option>
          ))}
        </FilterSelect>
      )}
    </div>
  );
}
