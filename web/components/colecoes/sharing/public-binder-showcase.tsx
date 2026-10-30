"use client";

import Link from "next/link";
import { useCallback, useEffect, useRef, useState } from "react";
import { ArrowRight, BookOpen } from "lucide-react";
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
 *
 * Aquisição (V1.0 PUBLIC SHOWCASE & ACQUISITION-01): abaixo do CTA do
 * fichário, um convite discreto e subordinado — "Seu fichário também pode
 * ser assim." + uma linha + "Criar minha coleção" (contorno, menor que o CTA
 * dourado). Leva ao cadastro existente (ou a Minhas coleções, com sessão).
 * Nada muda no fichário publicado nem no modelo de acesso.
 *
 * Assinatura de movimento (COMPOSITION & SIGNATURE MOTION-01): só o título
 * da coleção emerge da névoa, palavra por palavra (`RevealTitle`), uma única
 * vez por visita — voltar do fichário aberto para a capa não repete.
 */
export function PublicBinderShowcase({
  binder,
  finish,
  logoUrl,
  coverCode = null,
  initialPage,
  initialPages,
  createHref = "/cadastro",
}: {
  binder: PublicBinder;
  finish: BinderFinish;
  logoUrl: string | null;
  /** Código da capa da própria coleção (5328). */
  coverCode?: string | null;
  /** 0 = abrir pela capa. */
  initialPage: number;
  initialPages: SharedBinderPage[] | null;
  /** Destino de "Criar minha coleção": cadastro (visitante) ou Minhas coleções (com sessão). */
  createHref?: string;
}) {
  const grid = binder.binder;
  const canOpen = grid !== null && grid.pageCount > 0;
  const [open, setOpen] = useState(canOpen && initialPage > 0);
  const openButton = useRef<HTMLButtonElement>(null);
  const title = binder.binderName ?? binder.name;
  // O título se revela uma vez por visita: depois que o fichário é aberto,
  // a capa (que remonta ao voltar) mostra o título já nítido.
  const [introDone, setIntroDone] = useState(false);
  const openBinder = useCallback(() => {
    setIntroDone(true);
    setOpen(true);
  }, []);

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
        <RevealTitle text={title} animate={!introDone} />
        <p className={styles.owner}>
          por <strong>{binder.ownerDisplayName}</strong>
        </p>

        {canOpen && grid ? (
          <>
            <p className={styles.facts}>
              {formatCount(grid.pageCount)} {grid.pageCount === 1 ? "página" : "páginas"} · {modelLabel(grid.columns, grid.rows)}
            </p>
            <Button ref={openButton} size="lg" className={styles.cta} onClick={openBinder}>
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

        <ProductInvite createHref={createHref} />
      </div>
    </div>
  );
}

/**
 * Título com revelação "da névoa" (blur → nítido), palavra por palavra.
 *
 * Só CSS (`filter`, `opacity`, `transform` — sem layout): cada palavra é um
 * `inline-block` que ocupa desde o primeiro quadro exatamente o espaço final,
 * então a altura/largura do título não muda e não há layout shift. O texto
 * real fica no `h1` para leitores de tela (`sr-only`); a camada animada é
 * `aria-hidden`. Onda contínua de nitidez (SIGNATURE MOTION TIMING-02):
 * 2,4 s do início da primeira palavra à nitidez da última, qualquer que seja
 * o número de palavras — os inícios se espalham por 1 s e cada palavra leva
 * o restante (1,4 s), então as transições se sobrepõem. Uma palavra só: 2,4 s.
 * `prefers-reduced-motion`: nítido de imediato (CSS). Não bloqueia nada: o
 * CTA é clicável durante o efeito.
 */
/** Duração total da revelação (início da 1ª palavra → nitidez da última). */
const REVEAL_TOTAL_MS = 2400;
/** Janela em que os inícios das palavras se distribuem (onda). */
const REVEAL_SPREAD_MS = 1000;

function RevealTitle({ text, animate }: { text: string; animate: boolean }) {
  const words = text.split(/\s+/).filter(Boolean);
  const spread = words.length > 1 ? REVEAL_SPREAD_MS : 0;
  const duration = REVEAL_TOTAL_MS - spread;
  return (
    <h1 className={styles.title}>
      <span className="sr-only">{text}</span>
      <span aria-hidden="true" data-reveal={animate || undefined} className={styles.reveal}>
        {words.map((word, index) => (
          <span key={`${index}-${word}`}>
            <span className={styles.revealWord} style={{
                animationDelay: `${words.length > 1 ? Math.round((index * spread) / (words.length - 1)) : 0}ms`,
                animationDuration: `${duration}ms`,
              }}>
              {word}
            </span>
            {index < words.length - 1 ? " " : null}
          </span>
        ))}
      </span>
    </h1>
  );
}

/** Convite secundário — sempre abaixo do CTA do fichário, nunca competindo com ele. */
function ProductInvite({ createHref }: { createHref: string }) {
  return (
    <section className={styles.invite} aria-labelledby="convite-mmkyu">
      <h2 id="convite-mmkyu" className={styles.inviteTitle}>
        Seu fichário também pode ser assim.
      </h2>
      <p className={styles.inviteText}>
        Organize suas cartas, acompanhe seu progresso e personalize seu fichário no MMKYU Collector.
      </p>
      <Button asChild variant="outline" size="sm" className={styles.inviteCta}>
        <Link href={createHref}>
          Criar minha coleção
          <ArrowRight className="ml-1.5 h-4 w-4" aria-hidden="true" />
        </Link>
      </Button>
    </section>
  );
}
