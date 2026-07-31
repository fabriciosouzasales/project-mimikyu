"use client";

import { Search } from "lucide-react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { useEffect, useRef, useState, useTransition } from "react";
import { Input } from "@/components/ui/input";

/**
 * Busca única da tela Catálogo (Card Set ou Carta, mesmo campo) — spec
 * aprovada 2026-07-31. Atualiza o parâmetro `q` da própria URL (debounce de
 * 300ms) preservando `game`/`expansion`, para que cabeçalho/busca/filtros
 * nunca saiam do lugar — só o conteúdo abaixo muda (decisão explícita:
 * "a busca não deve trocar a estrutura da página").
 */
export function CatalogoSearchBar({
  initialQuery,
  placeholder = "Buscar por Card Set ou por Carta (nome ou número)…",
}: {
  initialQuery: string;
  placeholder?: string;
}) {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const [value, setValue] = useState(initialQuery);
  const [, startTransition] = useTransition();
  const debounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    return () => {
      if (debounceRef.current) clearTimeout(debounceRef.current);
    };
  }, []);

  function handleChange(next: string) {
    setValue(next);
    if (debounceRef.current) clearTimeout(debounceRef.current);
    debounceRef.current = setTimeout(() => {
      const params = new URLSearchParams(searchParams.toString());
      if (next.trim()) {
        params.set("q", next.trim());
      } else {
        params.delete("q");
      }
      startTransition(() => {
        router.replace(`${pathname}?${params.toString()}`);
      });
    }, 300);
  }

  return (
    <div className="relative">
      <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
      <Input
        value={value}
        onChange={(event) => handleChange(event.target.value)}
        placeholder={placeholder}
        className="h-10 pl-9 text-sm"
        aria-label="Buscar no catálogo"
      />
    </div>
  );
}
