"use client";

import { type ReactNode, useEffect, useId, useState } from "react";
import { GalleryHorizontal, LayoutGrid, List } from "lucide-react";
import {
  LIBRARY_MODE_COOKIE,
  type LibraryMode,
  librarySearchWithMode,
  resolveLibraryMode,
} from "@/lib/colecoes/colecoes";
import type { CollectionSummary } from "@/lib/colecoes/colecoes-queries";
import { LibraryCarousel } from "./library-carousel";
import { LibraryList } from "./library-list";
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
 */
export function LibraryModes({
  initialMode,
  items,
  logoUrls,
  cards,
  children,
  meta = null,
}: {
  initialMode: LibraryMode;
  items: readonly CollectionSummary[];
  logoUrls: Readonly<Record<string, string>>;
  /** Grade do modo Cards (Server Component existente). */
  cards: ReactNode;
  /** Conteúdo comum a todos os modos, abaixo do modo ativo (paginação). */
  children?: ReactNode;
  /** Linha discreta sob o título da seção (ex.: faixa exibida quando há paginação). */
  meta?: string | null;
}) {
  const [mode, setMode] = useState<LibraryMode>(initialMode);
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
        {mode === "cards" ? cards : null}
        {mode === "lista" ? <LibraryList items={items} logoUrls={logoUrls} /> : null}
        {mode === "carrossel" ? (
          <LibraryCarousel
            items={items}
            logoUrls={logoUrls}
            initialIndex={carouselIndex}
            onActiveChange={setCarouselIndex}
          />
        ) : null}
      </div>

      {children}
    </section>
  );
}
