"use client";

import { forwardRef } from "react";
import type { ButtonHTMLAttributes } from "react";
import { cn } from "@/lib/utils";

export interface SwitchProps extends Omit<ButtonHTMLAttributes<HTMLButtonElement>, "onChange" | "role" | "aria-checked"> {
  checked: boolean;
  onCheckedChange: (checked: boolean) => void;
}

/**
 * Interruptor liga/desliga do Design System (P3-A, primeiro consumidor:
 * "Exibir logomarca" do Centro de Controle do Fichário).
 *
 * `<button role="switch" aria-checked>`: Espaço/Enter alternam (nativo do
 * botão), o estado é falado pelo leitor de tela e o rótulo vem de um
 * `<Label htmlFor>` ou `aria-labelledby`. Tokens de controle do Login:
 * desligado = `control-border`; ligado = `primary` (dourado MMKYU, reservado a
 * estado ativo). Foco com o mesmo halo dos inputs. Só `transform` anima, e
 * nada anima com `prefers-reduced-motion`.
 */
export const Switch = forwardRef<HTMLButtonElement, SwitchProps>(({ checked, onCheckedChange, className, disabled, ...props }, ref) => (
  <button
    ref={ref}
    type="button"
    role="switch"
    aria-checked={checked}
    disabled={disabled}
    onClick={() => onCheckedChange(!checked)}
    className={cn(
      "relative inline-flex h-5 w-9 flex-none items-center rounded-full border border-transparent transition-colors",
      checked ? "bg-primary" : "bg-control-border",
      "focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-primary/25",
      "disabled:cursor-not-allowed disabled:opacity-50",
      className,
    )}
    {...props}
  >
    <span
      aria-hidden
      className={cn(
        "pointer-events-none block h-4 w-4 rounded-full bg-white shadow-sm transition-transform duration-150 motion-reduce:transition-none",
        checked ? "translate-x-[1.0625rem]" : "translate-x-0.5",
      )}
    />
  </button>
));
Switch.displayName = "Switch";
