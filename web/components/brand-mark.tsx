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
 *
 * `aspect-[546/309]` no fallback pré-hidratação (Incremento 3 da frente de
 * performance, 2026-08-14, correção de CLS real medido em produção): antes,
 * o `<div>` vazio não tinha proporção nenhuma — com `h-auto w-8`
 * (`primary-rail.tsx`, único uso real), altura de conteúdo vazio resolve
 * para 0, e o salto para a altura real (~18px) só acontecia depois de
 * montar no cliente. `aspect-[546/309]` é a mesma proporção intrínseca já
 * usada no `<Image>` abaixo (`width={546} height={309}`) — com a largura
 * fixada pelo chamador, a altura reservada pelo fallback já nasce igual à
 * altura que a imagem real vai ocupar, sem mudar nenhuma dimensão final.
 */
export function BrandMark({ className }: { className?: string }) {
  const { resolvedTheme } = useTheme();
  const [mounted, setMounted] = useState(false);
  useEffect(() => setMounted(true), []);

  if (!mounted) {
    return <div className={cn("aspect-[546/309] shrink-0", className)} aria-hidden="true" />;
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
