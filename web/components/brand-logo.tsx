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
 *
 * `aspect-[1142/258]` no fallback pré-hidratação (Incremento 3 da frente de
 * performance, 2026-08-14, correção de CLS real medido em produção): antes,
 * o `<div>` vazio não tinha proporção nenhuma — com `h-8 w-auto` (único uso
 * real, `app/(auth)/layout.tsx`), largura de conteúdo vazio resolve para 0,
 * e o salto para a largura real (~142px) só acontecia depois de montar no
 * cliente. `aspect-[1142/258]` é a mesma proporção intrínseca já usada no
 * `<Image>` abaixo (`width={1142} height={258}`) — com a altura fixada pelo
 * chamador, a largura reservada pelo fallback já nasce igual à largura que a
 * imagem real vai ocupar, sem mudar nenhuma dimensão final.
 */
export function BrandLogo({ className }: { className?: string }) {
  const { resolvedTheme } = useTheme();
  const [mounted, setMounted] = useState(false);
  useEffect(() => setMounted(true), []);

  if (!mounted) {
    return <div className={cn("aspect-[1142/258] shrink-0", className)} aria-hidden="true" />;
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
