import { clsx, type ClassValue } from "clsx";
import { twMerge } from "tailwind-merge";

/** Combina classes condicionalmente e resolve conflitos de utilitários Tailwind. */
export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

/** Formata um número inteiro com "." como separador de milhar (pt-BR) — ex.: 5886 → "5.886". */
export function formatNumber(value: number): string {
  return new Intl.NumberFormat("pt-BR").format(value);
}
