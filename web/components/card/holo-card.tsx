"use client";

import { useEffect, useRef, type CSSProperties, type ReactNode } from "react";
import { cn } from "@/lib/utils";

/**
 * Efeito "holográfico" ao passar o mouse sobre uma carta — novo em
 * 2026-07-31 (subciclo Card, pedido de Fabrício: "a exibição das cartas é a
 * funcionalidade que deve impressionar qualquer usuário visualmente",
 * referência anexada com 4 capturas do mesmo card em posições diferentes do
 * mouse + a versão ampliada, e o site oficial
 * tcg.pokemon.com/pt-br/galleries/scarlet-violet/). Mesmo componente usado
 * no grid (`CartaGridCard`) e no modal ampliado (`CartaZoomDialog`) — "seja
 * no gride, seja na forma ampliada" era um requisito explícito.
 *
 * Movido de `components/catalogo/` para `components/card/` em 2026-08-17
 * (pedido de Fabrício: o preview de carta da Pesquisa deve ser
 * estruturalmente compartilhado com a página administrativa `Cartas`, não
 * apenas visualmente parecido) — este componente nunca teve acoplamento
 * real ao Catálogo Editorial (nenhuma prop de edição/ativação/importação),
 * só morava na pasta errada; a mudança de local só reflete isso, zero
 * alteração de comportamento. Consumido agora também por
 * `components/card/card-image-preview.tsx` (`CardImagePreview`), o preview
 * compartilhado entre `/catalogo/cartas` e `/pesquisa`.
 *
 * Implementação inteiramente CSS/JS nativo (sem canvas/WebGL nem
 * dependência nova — o sandbox de build não tem acesso a registry npm, ver
 * memória do projeto): `onMouseMove` calcula a posição do cursor dentro do
 * card (0–100%) e grava em custom properties (`--holo-x`/`--holo-y`), que
 * alimentam ao mesmo tempo (a) a inclinação 3D via `transform` inline e (b)
 * o brilho radial + a faixa diagonal do `::after` (`.holo-card__sheen` em
 * `globals.css`), que usa `mix-blend-mode: overlay` para reagir à imagem
 * por baixo em vez de ficar como uma camada plana por cima — o mesmo
 * princípio do "foil sweep" de cartas físicas holográficas. `mouseleave`
 * volta ao estado neutro (ou retoma `floating`, ver abaixo) com uma
 * transição suave (definida na própria classe, não inline) em vez de
 * saltar.
 *
 * `floating` (2026-07-31, mesmo dia, pedido de Fabrício com prints do
 * DevTools da referência: "gostaria que essa carta ficasse com o efeito
 * flutuando na tela... a carta fica se movendo lentamente mesmo sem que o
 * mouse passe por ela") — os dois `matrix3d(...)` capturados em momentos
 * diferentes mostram uma rotação 3D contínua e lenta, não um simples
 * balanço vertical; reproduzido aqui com um loop `requestAnimationFrame`
 * que escreve em `rotateX`/`rotateY`/`translateY` senoides independentes
 * (frequências diferentes evitam um ciclo óbvio/repetitivo), pausado
 * enquanto o mouse está sobre a carta (o gesto do usuário sempre vence o
 * automático) e desligado por completo sob `prefers-reduced-motion:
 * reduce`. Usado só no modal de ampliação (`CartaZoomDialog`) — o grid
 * continua estático em repouso, "flutuar" é um comportamento de destaque
 * de uma única carta por vez, não do grid inteiro.
 */
export function HoloCard({
  children,
  className,
  rounded = "rounded-lg",
  floating = false,
  style,
}: {
  children: ReactNode;
  className?: string;
  rounded?: string;
  floating?: boolean;
  /** Repassado ao elemento raiz — usado por `CartasGallery` (2026-07-31) para aplicar `viewTransitionName`, permitindo que o grid e o modal de ampliação compartilhem a mesma identidade visual num `document.startViewTransition`. Mesclado com o `--holo-opacity` interno, não o substitui. */
  style?: CSSProperties;
}) {
  const ref = useRef<HTMLDivElement>(null);
  const hoveringRef = useRef(false);

  function handleMouseMove(event: React.MouseEvent<HTMLDivElement>) {
    const node = ref.current;
    if (!node) return;
    const rect = node.getBoundingClientRect();
    const x = Math.min(1, Math.max(0, (event.clientX - rect.left) / rect.width));
    const y = Math.min(1, Math.max(0, (event.clientY - rect.top) / rect.height));
    const rotateY = (x - 0.5) * 16;
    const rotateX = (0.5 - y) * 16;

    node.style.setProperty("--holo-x", `${x * 100}%`);
    node.style.setProperty("--holo-y", `${y * 100}%`);
    node.style.setProperty("--holo-opacity", "1");
    node.style.setProperty(
      "--holo-transform",
      `perspective(800px) rotateX(${rotateX}deg) rotateY(${rotateY}deg) scale3d(1.045, 1.045, 1.045)`,
    );
  }

  function handleMouseEnter() {
    hoveringRef.current = true;
  }

  function handleMouseLeave() {
    hoveringRef.current = false;
    const node = ref.current;
    if (!node) return;
    if (!floating) {
      node.style.setProperty("--holo-opacity", "0");
      node.style.setProperty("--holo-transform", "perspective(800px) rotateX(0deg) rotateY(0deg) scale3d(1, 1, 1)");
    }
    // Quando `floating`, não força nada aqui — o loop de animação (efeito
    // abaixo) retoma sozinho no próximo quadro, e a `transition` do CSS
    // suaviza o salto da última posição do mouse até a curva senoidal.
  }

  useEffect(() => {
    if (!floating) return;
    if (typeof window !== "undefined" && window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;

    let frameId: number;
    const start = performance.now();

    function tick(now: number) {
      const node = ref.current;
      if (node && !hoveringRef.current) {
        const t = (now - start) / 1000;
        // Três senoides com frequências/fases distintas — evita um ciclo
        // óbvio de "vai e volta" e imita a deriva orgânica capturada nos
        // dois prints do DevTools (valores de matrix3d levemente diferentes
        // a cada instante, nunca repetindo exatamente).
        const rotateY = Math.sin(t * 0.45) * 7;
        const rotateX = Math.cos(t * 0.33 + 1) * 4.5;
        const translateY = Math.sin(t * 0.52 + 0.6) * 8;
        node.style.setProperty(
          "--holo-transform",
          `perspective(900px) translateY(${translateY}px) rotateX(${rotateX}deg) rotateY(${rotateY}deg) scale3d(1, 1, 1)`,
        );
        node.style.setProperty("--holo-x", `${50 + Math.sin(t * 0.45) * 22}%`);
        node.style.setProperty("--holo-y", `${50 + Math.cos(t * 0.33) * 22}%`);
        node.style.setProperty("--holo-opacity", "0.45");
      }
      frameId = requestAnimationFrame(tick);
    }

    frameId = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(frameId);
  }, [floating]);

  return (
    <div
      ref={ref}
      onMouseMove={handleMouseMove}
      onMouseEnter={handleMouseEnter}
      onMouseLeave={handleMouseLeave}
      style={{ "--holo-opacity": 0, ...style } as CSSProperties}
      className={cn("holo-card group/holo relative isolate", rounded, className)}
    >
      {children}
      <span className={cn("holo-card__sheen pointer-events-none absolute inset-0", rounded)} aria-hidden="true" />
    </div>
  );
}
