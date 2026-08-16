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
 *
 * `variant` (2026-08-16, prova visual isolada da Visão Geral do Catálogo
 * Editorial, ver `docs/log.md`) — `"auto"` (default) é o comportamento de
 * sempre, direto do tema real do site. `"dark"` fixa sempre a arte clara
 * (pensada pra fundo escuro), independente de `resolvedTheme` — usada
 * quando o fundo local é deliberadamente escuro nos dois temas do site
 * (Rodada 3 da prova: a navegação voltou a ser uma âncora fixa, escura nos
 * dois temas — a Rodada 2 tinha um `"inverted"` para quando a navegação
 * ainda invertia por tema; reprovado, removido). Mesmo problema já
 * resolvido em `AuthHeroShell`/`BrandLogo` (a variante do ícone precisa
 * seguir o FUNDO local, não o tema do site). Continua dependendo de
 * `resolvedTheme` só no modo `"auto"`, mas mantém o guard de hidratação de
 * sempre em ambos os modos. Nenhum outro uso de `BrandMark` muda de
 * comportamento.
 */
export function BrandMark({
  className,
  variant = "auto",
}: {
  className?: string;
  variant?: "auto" | "dark";
}) {
  const { resolvedTheme } = useTheme();
  const [mounted, setMounted] = useState(false);
  useEffect(() => setMounted(true), []);

  if (!mounted) {
    return <div className={cn("aspect-[546/309] shrink-0", className)} aria-hidden="true" />;
  }

  const isDarkSite = resolvedTheme === "dark";
  const useDarkAsset = variant === "dark" ? true : isDarkSite;
  const src = useDarkAsset ? "/brand/icon-mark-dark.png" : "/brand/icon-mark-light.png";

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
