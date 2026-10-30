"use client";

import Link from "next/link";
import { useCallback, useEffect, useRef, useState } from "react";
import { BookOpen } from "lucide-react";
import { BinderCover } from "@/components/colecoes/colecoes/binder-cover";
import { Button } from "@/components/ui/button";
import { formatCount } from "@/lib/colecoes/acervo";
import { modelLabel } from "@/lib/colecoes/binder";
import type { BinderFinish } from "@/lib/colecoes/binder-finish";
import type { PublicBinder, SharedBinderPage } from "@/lib/colecoes/sharing";
import { SharedBinderWorkspace } from "./shared-binder-workspace";
import styles from "./public-binder.module.css";

/**
 * Vitrine pública do Fichário Digital (V1-12 PUBLIC BINDER EXPERIENCE) —
 * `/fichario/[id]`, sem login, por link.
 *
 * Duas cenas, nada além do fichário:
 *  1. Capa — o objeto fechado no acabamento da coleção, nome próprio do
 *     fichário, quem montou, tamanho (páginas e grade) e um único CTA.
 *  2. Fichário aberto — a MESMA camada visual do fichário do titular e do
 *     participante (`SharedBinderWorkspace`, fonte "public": moldura, couro,
 *     contracapa com nome próprio e logomarca, bolsos), com o mascaramento
 *     do banco (5318 → 5315). O modelo de acesso continua o da vitrine.
 *
 * Sem galeria, progresso, acervo, contagens de cartas ou qualquer controle
 * de edição. Sem fichário montado: estado vazio honesto, sem substituir pela
 * galeria. `?pagina=N` abre direto na página (link compartilhável).
 */
export function PublicBinderShowcase({
  binder,
  finish,
  logoUrl,
  coverCode = null,
  initialPage,
  initialPages,
}: {
  binder: PublicBinder;
  finish: BinderFinish;
  logoUrl: string | null;
  /** Código da capa da própria coleção (5328). */
  coverCode?: string | null;
  /** 0 = abrir pela capa. */
  initialPage: number;
  initialPages: SharedBinderPage[] | null;
}) {
  const grid = binder.binder;
  const canOpen = grid !== null && grid.pageCount > 0;
  const [open, setOpen] = useState(canOpen && initialPage > 0);
  const openButton = useRef<HTMLButtonElement>(null);
  const title = binder.binderName ?? binder.name;

  const close = useCallback(() => setOpen(false), []);

  // Ao voltar para a capa, o foco retorna ao CTA (teclado e leitor de tela).
  const wasOpen = useRef(open);
  useEffect(() => {
    if (wasOpen.current && !open) openButton.current?.focus();
    wasOpen.current = open;
  }, [open]);

  if (open && grid) {
    return (
      <div className={styles.openStage}>
        <SharedBinderWorkspace
          source="public"
          variant="overlay"
          titleId="fichario-publico-titulo"
          collectionId={binder.collectionId}
          collectionName={binder.name}
          ownerDisplayName={binder.ownerDisplayName}
          finish={finish}
          identity={{ name: binder.binderName, showBrandMark: binder.showBrandMark }}
          columns={grid.columns}
          rows={grid.rows}
          pageCount={grid.pageCount}
          ownFilled={null}
          initialAnchor={Math.max(1, initialPage)}
          initialPages={initialPages}
          onClose={close}
        />
      </div>
    );
  }

  return (
    <div className={styles.coverStage}>
      <div className={styles.glow} aria-hidden="true" />
      <div className={styles.coverObject}>
        <BinderCover
          finish={finish}
          setName={binder.cardSetName}
          setCode={coverCode ?? binder.cardSetCode}
          logoUrl={logoUrl}
          fallbackTitle={title}
          complete={false}
          priority
          emblem={binder.completionPolicy === "REFERENCE_POSITION" ? "pokedex" : null}
        />
      </div>

      <div className={styles.coverText}>
        <p className={styles.eyebrow}>Fichário publicado</p>
        <h1 className={styles.title}>{title}</h1>
        <p className={styles.owner}>
          por <strong>{binder.ownerDisplayName}</strong>
        </p>

        {canOpen && grid ? (
          <>
            <p className={styles.facts}>
              {formatCount(grid.pageCount)} {grid.pageCount === 1 ? "página" : "páginas"} · {modelLabel(grid.columns, grid.rows)}
            </p>
            <Button ref={openButton} size="lg" className={styles.cta} onClick={() => setOpen(true)}>
              <BookOpen className="mr-2 h-4 w-4" aria-hidden="true" />
              Abrir o fichário
            </Button>
            <p className={styles.hint}>Folheie com as setas ou com ← →. Nada aqui pode ser alterado.</p>
          </>
        ) : (
          <div className={styles.empty} role="status">
            <p className={styles.emptyTitle}>Este fichário ainda está sendo montado.</p>
            <p className={styles.emptyText}>O colecionador publicou a coleção, mas as páginas ainda não estão prontas para visita. Volte em breve.</p>
          </div>
        )}

        <p className={styles.cta2}>
          Monte e publique o seu na <Link href="/">MMKYU Collector</Link>.
        </p>
      </div>
    </div>
  );
}
