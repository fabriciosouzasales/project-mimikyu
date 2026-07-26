"use client";

import { useEffect, useState } from "react";
import Image from "next/image";
import { useTheme } from "next-themes";
import { cn } from "@/lib/utils";

/**
 * Ícone da marca (Mimikyu, sem o texto "MMKYU") — usado em espaços pequenos
 * onde só o símbolo cabe (cabeçalho da trilha da sidebar). Troca de arte por
 * tema (tinta escura no claro, tinta clara no escuro), com o mesmo guard de
 * hidratação do `ThemeToggle` (evita mismatch client/server no primeiro
 * render, já que o tema real só é conhecido depois de montar no cliente).
 *
 * Aspecto real do ícone é ~1.77:1 (mais largo que alto) — a className
 * definida por quem usa deve fixar largura OU altura, nunca as duas, pra
 * não esticar a arte.
 */
export function BrandMark({ className }: { className?: string }) {
  const { resolvedTheme } = useTheme();
  const [mounted, setMounted] = useState(false);
  useEffect(() => setMounted(true), []);

  if (!mounted) {
    return <div className={cn("shrink-0", className)} aria-hidden="true" />;
  }

  const src = resolvedTheme === "dark" ? "/brand/icon-mark-dark.png" : "/brand/icon-mark-light.png";

  return (
    <Image
      src={src}
      alt="Mimikyu"
      width={546}
      height={309}
      className={cn("shrink-0 object-contain", className)}
      priority
    />
  );
}
