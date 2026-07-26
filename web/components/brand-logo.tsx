"use client";

import { useEffect, useState } from "react";
import Image from "next/image";
import { useTheme } from "next-themes";
import { cn } from "@/lib/utils";

/**
 * Logo completa (ícone + "MMKYU" + tagline) — usada onde há espaço
 * horizontal e a marca por extenso faz sentido (cabeçalho das telas de
 * autenticação). Mesmo padrão de troca por tema e guard de hidratação do
 * `BrandMark`.
 *
 * Aspecto real ~4.43:1 (bem mais largo que alto) — fixar altura via
 * className e deixar a largura em auto.
 */
export function BrandLogo({ className }: { className?: string }) {
  const { resolvedTheme } = useTheme();
  const [mounted, setMounted] = useState(false);
  useEffect(() => setMounted(true), []);

  if (!mounted) {
    return <div className={cn("shrink-0", className)} aria-hidden="true" />;
  }

  const src = resolvedTheme === "dark" ? "/brand/logo-full-dark.png" : "/brand/logo-full-light.png";

  return (
    <Image
      src={src}
      alt="Mimikyu — para colecionadores"
      width={1142}
      height={258}
      className={cn("shrink-0 object-contain", className)}
      priority
    />
  );
}
