"use client";

import { useEffect, useState } from "react";
import { Moon, Sun } from "lucide-react";
import { useTheme } from "next-themes";
import { Button } from "@/components/ui/button";
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip";

/**
 * Alternância explícita entre modo claro e escuro, visível no cabeçalho.
 *
 * Ciclo D.3 (2026-07-30, correção pós-auditoria): tooltip adicionada — o
 * botão é só um ícone (lua/sol) sem rótulo visível, então em uso real fica
 * fácil de não notar que é um controle de tema. `TooltipProvider` já
 * envolve o app inteiro (`app/layout.tsx`); nenhuma dependência nova.
 */
export function ThemeToggle() {
  const { resolvedTheme, setTheme } = useTheme();
  // Evita mismatch de hidratação: só renderiza o ícone real após montar no cliente.
  const [mounted, setMounted] = useState(false);
  useEffect(() => setMounted(true), []);

  const isDark = mounted && resolvedTheme === "dark";

  return (
    <Tooltip>
      <TooltipTrigger asChild>
        <Button
          variant="ghost"
          size="icon"
          aria-label={isDark ? "Mudar para tema claro" : "Mudar para tema escuro"}
          onClick={() => setTheme(isDark ? "light" : "dark")}
        >
          {mounted ? (
            isDark ? <Sun className="h-4 w-4" /> : <Moon className="h-4 w-4" />
          ) : (
            <span className="h-4 w-4" />
          )}
        </Button>
      </TooltipTrigger>
      <TooltipContent>{isDark ? "Ativar tema claro" : "Ativar tema escuro"}</TooltipContent>
    </Tooltip>
  );
}
