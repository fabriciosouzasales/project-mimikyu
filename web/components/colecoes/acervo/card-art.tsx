"use client";

import { useEffect, useRef, useState } from "react";
import styles from "./acervo.module.css";

/**
 * Frente da carta dentro da moldura 8:11 (Meu acervo).
 *
 * Mesmo padrão de `SpeciesArtwork` (Pokédex P2): Client Component mínimo, só
 * para o que o servidor não sabe — se a imagem chegou (fade-in curto) ou
 * falhou (moldura com nome e número, sem quebrar a grade).
 *
 * - Elemento img nativo: o arquivo vem do bucket público `card-front`, URL imutável;
 *   reprocessar no servidor do Next só acrescentaria custo.
 * - width/height + moldura com aspect-ratio fixo: zero layout shift.
 * - lazy + decoding async por padrão; só o topo da grade tem prioridade.
 * - Fade desligado com prefers-reduced-motion (CSS).
 */
export function CardArt({
  src,
  alt,
  name,
  caption,
  priority = false,
  sizes,
}: {
  src: string | null;
  alt: string;
  /** Texto da moldura quando não há imagem. */
  name: string;
  caption: string;
  priority?: boolean;
  sizes?: string;
}) {
  const [state, setState] = useState<"loading" | "loaded" | "failed">(src ? "loading" : "failed");
  const imgRef = useRef<HTMLImageElement>(null);

  // Imagem já resolvida antes da hidratação (cache): onLoad/onError já passaram.
  useEffect(() => {
    const img = imgRef.current;
    if (img?.complete) setState(img.naturalWidth > 0 ? "loaded" : "failed");
  }, []);

  if (!src || state === "failed") {
    return (
      <div className={styles.artFallback} role="img" aria-label={`${alt} (imagem indisponível)`}>
        <span>{name}</span>
        <span className={styles.artFallbackWindow} aria-hidden="true" />
        <small>{caption}</small>
      </div>
    );
  }

  return (
    // eslint-disable-next-line @next/next/no-img-element -- asset já otimizado no pipeline, URL pública imutável
    <img
      ref={imgRef}
      src={src}
      alt={alt}
      width={367}
      height={512}
      sizes={sizes}
      loading={priority ? "eager" : "lazy"}
      decoding="async"
      fetchPriority={priority ? "high" : "low"}
      draggable={false}
      data-state={state}
      className={styles.artImage}
      onLoad={() => setState("loaded")}
      onError={() => setState("failed")}
    />
  );
}
