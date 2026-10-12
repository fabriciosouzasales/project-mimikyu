"use client";

import { useEffect, useRef, useState } from "react";
import { Pokeball } from "@/components/icons/pokeball-icon";
import { cn } from "@/lib/utils";

/**
 * Arte da espécie dentro da moldura quadrada da grade (Pokédex P2 Lote C).
 *
 * Client Component mínimo — só existe para o que o servidor não sabe: se a
 * imagem chegou (fade-in) ou falhou (volta para a Pokébola). Espécies sem
 * arte nem chegam aqui: a grade renderiza o fallback no servidor.
 *
 * - <img> nativo, não next/image: o arquivo já é um WebP 320 px otimizado na
 *   importação, servido por URL imutável; reprocessar no servidor do Next só
 *   acrescentaria custo.
 * - width/height fixos + moldura aspect-square: zero layout shift.
 * - object-contain com respiro: arte inteira, sem corte nem distorção,
 *   transparência sobre o fundo da moldura (claro e escuro).
 * - loading lazy + decoding async por padrão; só as primeiras imagens da
 *   grade recebem eager/fetchPriority alta.
 * - Fade-in curto, desligado com prefers-reduced-motion.
 */
export function SpeciesArtwork({ src, priority }: { src: string; priority: boolean }) {
  const [state, setState] = useState<"loading" | "loaded" | "failed">("loading");
  const imgRef = useRef<HTMLImageElement>(null);

  // A imagem é renderizada no servidor: se terminar (ou falhar) antes da
  // hidratação, onLoad/onError já passaram — lê o estado real do elemento.
  useEffect(() => {
    const img = imgRef.current;
    if (img?.complete) setState(img.naturalWidth > 0 ? "loaded" : "failed");
  }, []);

  if (state === "failed") {
    return <Pokeball className="h-1/3 w-1/3 text-foreground/[0.07] dark:text-foreground/[0.09]" strokeWidth={1.25} />;
  }

  return (
    // eslint-disable-next-line @next/next/no-img-element -- WebP já otimizado na importação, URL imutável
    <img
      ref={imgRef}
      src={src}
      alt=""
      width={320}
      height={320}
      loading={priority ? "eager" : "lazy"}
      decoding="async"
      fetchPriority={priority ? "high" : "low"}
      draggable={false}
      onLoad={() => setState("loaded")}
      onError={() => setState("failed")}
      className={cn(
        "h-full w-full select-none object-contain p-[9%] drop-shadow-[0_6px_10px_rgba(0,0,0,0.12)] dark:drop-shadow-[0_6px_12px_rgba(0,0,0,0.45)]",
        "transition-opacity duration-300 ease-out motion-reduce:transition-none",
        state === "loaded" ? "opacity-100" : "opacity-0",
      )}
    />
  );
}
