"use client";

import { useRouter } from "next/navigation";
import { type ReactNode, useEffect, useId, useMemo, useState } from "react";
import { GalleryHorizontal, LayoutGrid, List } from "lucide-react";
import {
  LIBRARY_MODE_COOKIE,
  type LibraryMode,
  librarySearchWithMode,
  resolveLibraryMode,
} from "@/lib/colecoes/colecoes";
import { moveCollectionInLibrary } from "@/app/colecoes/colecoes/actions";
import { collectionFailureMessage } from "@/lib/colecoes/colecoes";
import type { CollectionSummary } from "@/lib/colecoes/colecoes-queries";
import { LIBRARY_REORDER_ENABLED, moveAnchor, sameOrder } from "@/lib/colecoes/library-order";
import libraryStyles from "./colecoes.module.css";
import { LibraryCarousel } from "./library-carousel";
import { LibraryList, LibraryRow } from "./library-list";
import { LibrarySortable } from "./library-sortable";
import styles from "./library-modes.module.css";

const MODES: { id: LibraryMode; label: string; icon: typeof LayoutGrid }[] = [
  { id: "cards", label: "Cards", icon: LayoutGrid },
  { id: "lista", label: "Lista", icon: List },
  { id: "carrossel", label: "Carrossel", icon: GalleryHorizontal },
];

/** Um ano; só a preferência de visualização desta tela, no próprio navegador. */
const COOKIE_MAX_AGE = 60 * 60 * 24 * 365;

/**
 * Seção "Minha biblioteca" + seletor de modos (NS-17): Cards | Lista | Carrossel.
 *
 * A seção é a mesma moldura nos três modos (COLLECTION LIBRARY VISUAL
 * HIERARCHY-01): fio de borda a borda com marca dourada, superfície levemente
 * mais clara que se dissolve no workspace, título e seletor na mesma linha.
 * Só o conteúdo do painel muda de modo para modo.
 *
 * Os três modos recebem exatamente os mesmos itens da página já carregada no
 * servidor — trocar de modo não faz nenhuma consulta nem navegação. O modo Cards
 * continua sendo o Server Component aprovado (`cards`, renderizado pela página);
 * Lista e Carrossel são montados aqui a partir dos mesmos dados.
 *
 * Preferência: a URL (`?modo=`, atualizada com `history.replaceState`, sem
 * recarregar) e um cookie do próprio navegador, que o servidor lê na próxima
 * visita/página para já renderizar o modo certo (sem piscar). Nada vai para o
 * banco nem para a conta.
 *
 * Ordem (LIBRARY-ORDER-01, atrás de `LIBRARY_REORDER_ENABLED`): em Cards e
 * Lista o colecionador arrasta e solta para reordenar. A ordem vive aqui —
 * os três modos (inclusive o Carrossel) mostram a mesma sequência. Cada
 * gesto grava UM movimento (`move_my_collection`, 5183) de forma otimista e
 * volta ao que era se a gravação falhar.
 */
export function LibraryModes({
  initialMode,
  items,
  logoUrls,
  cardNodes,
  children,
  meta = null,
}: {
  initialMode: LibraryMode;
  items: readonly CollectionSummary[];
  logoUrls: Readonly<Record<string, string>>;
  /** Fichário de cada coleção no modo Cards (Server Component), por id. */
  cardNodes: Readonly<Record<string, ReactNode>>;
  /** Conteúdo comum a todos os modos, abaixo do modo ativo (paginação). */
  children?: ReactNode;
  /** Linha discreta sob o título da seção (ex.: faixa exibida quando há paginação). */
  meta?: string | null;
}) {
  const router = useRouter();
  const [mode, setMode] = useState<LibraryMode>(initialMode);
  const serverOrder = useMemo(() => items.map((item) => item.id), [items]);
  const [order, setOrder] = useState<string[]>(serverOrder);
  const [saving, setSaving] = useState(false);
  const [orderStatus, setOrderStatus] = useState<{ tone: "ok" | "error"; text: string } | null>(null);

  // Dados novos do servidor (gravação concluída, outra página, outra aba) mandam.
  useEffect(() => {
    setOrder((current) => (sameOrder(current, serverOrder) ? current : serverOrder));
  }, [serverOrder]);

  useEffect(() => {
    if (orderStatus?.tone !== "ok") return;
    const timer = window.setTimeout(() => setOrderStatus(null), 3000);
    return () => window.clearTimeout(timer);
  }, [orderStatus]);

  const byId = useMemo(() => new Map(items.map((item) => [item.id, item])), [items]);
  const orderedItems = useMemo(
    () => order.map((id) => byId.get(id)).filter((item): item is CollectionSummary => item !== undefined),
    [order, byId],
  );
  const labels = useMemo(() => Object.fromEntries(items.map((item) => [item.id, item.name])), [items]);

  const commitOrder = async (next: string[], movedId: string) => {
    const anchor = moveAnchor(next, movedId);
    if (!anchor) return;
    const previous = order;
    setOrder(next);
    setSaving(true);
    setOrderStatus(null);
    const result = await moveCollectionInLibrary({ collectionId: movedId, ...anchor }).catch(() => ({
      ok: false as const,
      reason: "unavailable" as const,
    }));
    setSaving(false);
    if (!result.ok) {
      setOrder(previous);
      setOrderStatus({ tone: "error", text: `A ordem não foi salva. ${collectionFailureMessage(result.reason)}` });
      return;
    }
    setOrderStatus({ tone: "ok", text: "Ordem salva." });
    router.refresh();
  };
  const [carouselIndex, setCarouselIndex] = useState(0);
  const groupName = useId();
  const panelId = useId();
  const headingId = useId();

  // Voltar/avançar do navegador pode restaurar a página com o modo da primeira
  // renderização; a URL (e, sem ela, o cookie) é a fonte da verdade.
  useEffect(() => {
    const params = Object.fromEntries(new URLSearchParams(window.location.search));
    const cookie = document.cookie
      .split("; ")
      .find((entry) => entry.startsWith(`${LIBRARY_MODE_COOKIE}=`))
      ?.slice(LIBRARY_MODE_COOKIE.length + 1);
    const resolved = resolveLibraryMode(params, cookie);
    setMode((current) => (current === resolved ? current : resolved));
  }, []);

  const choose = (next: LibraryMode) => {
    if (next === mode) return;
    setMode(next);
    try {
      document.cookie = `${LIBRARY_MODE_COOKIE}=${next}; path=/colecoes; max-age=${COOKIE_MAX_AGE}; samesite=lax`;
    } catch {
      // Cookies bloqueados: o modo vale só nesta visita.
    }
    const search = librarySearchWithMode(window.location.search, next);
    window.history.replaceState(window.history.state, "", `${window.location.pathname}${search}${window.location.hash}`);
  };

  return (
    <section className={styles.region} aria-labelledby={headingId}>
      <div className={styles.head}>
        <div className={styles.headText}>
          <h2 id={headingId} className={styles.headTitle}>
            Minha biblioteca
          </h2>
          {meta ? <p className={styles.headMeta}>{meta}</p> : null}
        </div>
        <fieldset className={styles.switcher}>
          <legend className="sr-only">Modo de visualização</legend>
          {MODES.map(({ id, label, icon: Icon }) => (
            <label key={id} className={styles.option} data-checked={mode === id || undefined}>
              <input
                type="radio"
                name={groupName}
                value={id}
                checked={mode === id}
                onChange={() => choose(id)}
                className={styles.optionInput}
              />
              <Icon className={styles.optionIcon} aria-hidden="true" />
              <span className={styles.optionLabel}>{label}</span>
            </label>
          ))}
        </fieldset>
      </div>

      <div id={panelId} className={styles.panel} data-mode={mode}>
        {mode === "cards" ? (
          LIBRARY_REORDER_ENABLED && order.length > 1 ? (
            <LibrarySortable
              ids={order}
              labels={labels}
              layout="grid"
              className={libraryStyles.library ?? ""}
              ariaLabel="Suas coleções"
              busy={saving}
              renderItem={(id) => cardNodes[id] ?? null}
              onCommit={(next, moved) => void commitOrder(next, moved)}
            />
          ) : (
            <ul className={libraryStyles.library} aria-label="Suas coleções">
              {order.map((id) => (
                <li key={id}>{cardNodes[id]}</li>
              ))}
            </ul>
          )
        ) : null}
        {mode === "lista" ? (
          LIBRARY_REORDER_ENABLED && order.length > 1 ? (
            <LibrarySortable
              ids={order}
              labels={labels}
              layout="list"
              className={styles.list ?? ""}
              ariaLabel="Suas coleções"
              busy={saving}
              renderItem={(id) => {
                const collection = byId.get(id);
                return collection ? <LibraryRow collection={collection} logoUrls={logoUrls} /> : null;
              }}
              onCommit={(next, moved) => void commitOrder(next, moved)}
            />
          ) : (
            <LibraryList items={orderedItems} logoUrls={logoUrls} />
          )
        ) : null}
        {mode === "carrossel" ? (
          <LibraryCarousel
            items={orderedItems}
            logoUrls={logoUrls}
            initialIndex={carouselIndex}
            onActiveChange={setCarouselIndex}
          />
        ) : null}
      </div>

      {LIBRARY_REORDER_ENABLED ? (
        <p
          className={styles.orderStatus}
          data-tone={orderStatus?.tone}
          role={orderStatus?.tone === "error" ? "alert" : "status"}
          aria-live="polite"
        >
          {saving ? "Salvando a ordem…" : orderStatus?.text ?? null}
        </p>
      ) : null}

      {children}
    </section>
  );
}
