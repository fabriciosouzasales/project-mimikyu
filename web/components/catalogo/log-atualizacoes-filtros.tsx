"use client";

import { ChevronDown, Search } from "lucide-react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { useEffect, useRef, useState, useTransition } from "react";
import type { ReactNode } from "react";
import { Input } from "@/components/ui/input";
import { ACTION_OPTIONS, ENTITY_TYPE_OPTIONS } from "@/lib/catalogo/log-atualizacoes-labels";
import type { AdminUserOption } from "@/lib/catalogo/queries";

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
      <select
        value={value}
        onChange={(event) => onChange(event.target.value)}
        aria-label={ariaLabel}
        className="h-9 min-w-[10rem] appearance-none rounded-md border border-input bg-surface-muted py-1 pl-3 pr-8 text-xs shadow-subtle transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background"
      >
        {children}
      </select>
      <ChevronDown
        className="pointer-events-none absolute right-2.5 top-1/2 h-3.5 w-3.5 -translate-y-1/2 text-muted-foreground"
        aria-hidden="true"
      />
    </div>
  );
}

/**
 * Filtros server-side de /catalogo/log-atualizacoes (busca + Entidade + Ação
 * + Usuário) — primeira tela do Catálogo Editorial cujos filtros viram
 * parâmetro de URL consumido por uma RPC paginada
 * (admin_list_catalog_action_log), não fetch-tudo-e-filtra-em-memória
 * (padrão de Importações/Atividade Recente/Cartas). Mesmo mecanismo de
 * debounce de busca de CatalogoSearchBar (300ms, router.replace, preserva
 * os demais parâmetros da URL); toda troca de filtro remove `page` da URL
 * (mesmo raciocínio de "volta pra página 0" de AtividadeRecente/JogosTable).
 */
export function LogAtualizacoesFiltros({
  initialSearch,
  entityType,
  action,
  actorId,
  usuarios,
}: {
  initialSearch: string;
  entityType: string;
  action: string;
  actorId: string;
  usuarios: AdminUserOption[];
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
          placeholder="Buscar por registro, usuário ou ação…"
          className="h-9 bg-surface-muted pl-9 text-xs"
          aria-label="Buscar no log de atualizações"
        />
      </div>

      <FilterSelect
        value={entityType}
        onChange={(value) => pushParams({ entidade: value || undefined })}
        ariaLabel="Filtrar por Entidade"
      >
        <option value="">Todas as Entidades</option>
        {ENTITY_TYPE_OPTIONS.map((option) => (
          <option key={option.value} value={option.value}>
            {option.label}
          </option>
        ))}
      </FilterSelect>

      <FilterSelect
        value={action}
        onChange={(value) => pushParams({ acao: value || undefined })}
        ariaLabel="Filtrar por Ação"
      >
        <option value="">Todas as Ações</option>
        {ACTION_OPTIONS.map((option) => (
          <option key={option.value} value={option.value}>
            {option.label}
          </option>
        ))}
      </FilterSelect>

      <FilterSelect
        value={actorId}
        onChange={(value) => pushParams({ usuario: value || undefined })}
        ariaLabel="Filtrar por Usuário"
      >
        <option value="">Todos os Usuários</option>
        {usuarios.map((usuario) => (
          <option key={usuario.id} value={usuario.id}>
            {usuario.label}
          </option>
        ))}
      </FilterSelect>
    </div>
  );
}
