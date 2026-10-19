"use client";

import { useLinkStatus } from "next/link";
import { ChevronDown, Layers, Loader2, SlidersHorizontal } from "lucide-react";
import { type KeyboardEvent, type MouseEvent, type ReactNode, useId, useRef, useState } from "react";
import styles from "./type-filter.module.css";

/**
 * Ilha cliente do filtro por tipo (Pokédex P5a, 2026-10-14): só o abrir/fechar do
 * seletor. As opções, os chips ativos e o "Limpar" são links renderizados no servidor
 * (chegam como `children`/`chips`) — a filtragem acontece no servidor, pela URL.
 *
 * - Recolhido por padrão; o painel abre no fluxo da página, logo abaixo da linha do
 *   botão (nunca sobre as cartas) e continua aberto enquanto o usuário escolhe o
 *   segundo tipo — o componente não remonta na navegação suave.
 * - Esc dentro do painel fecha e devolve o foco ao botão.
 *
 * Pokédex P6, Correção de UX-01 (2026-10-15): o mesmo disclosure serve ao filtro
 * compacto de geração da página Pokémon Favoritos (`variant="generation"`): rótulo
 * "Geração", ícone próprio e — escolha única — o painel fecha ao escolher. O padrão
 * (`variant="type"`) mantém o comportamento aprovado da P5a sem nenhuma mudança.
 *
 * UX-02 (2026-10-15): `inline` (só na página Favoritos) deixa o botão e os chips
 * participarem de uma barra de ferramentas em linha (Geração e Tipo lado a lado) e o
 * painel abrir abaixo dela, na largura toda. Só layout (CSS); sem `inline`, nada muda.
 */
const VARIANTS = {
  type: { name: "Tipo", noun: "tipo", Icon: SlidersHorizontal, closeOnSelect: false },
  generation: { name: "Geração", noun: "geração", Icon: Layers, closeOnSelect: true },
} as const;

export function TypeFilterDisclosure({
  activeLabel,
  activeCount,
  chips,
  children,
  variant = "type",
  inline = false,
}: {
  /** "Fogo e Voador" quando há filtro (rótulo acessível do botão). */
  activeLabel: string | null;
  activeCount: number;
  chips: ReactNode;
  children: ReactNode;
  variant?: keyof typeof VARIANTS;
  inline?: boolean;
}) {
  const { name, noun, Icon, closeOnSelect } = VARIANTS[variant];
  const [open, setOpen] = useState(false);
  const panelId = useId();
  const buttonRef = useRef<HTMLButtonElement>(null);

  function onPanelKeyDown(event: KeyboardEvent<HTMLDivElement>) {
    if (event.key !== "Escape") return;
    event.preventDefault();
    setOpen(false);
    buttonRef.current?.focus();
  }

  function onPanelClick(event: MouseEvent<HTMLDivElement>) {
    if (!closeOnSelect || !(event.target as HTMLElement).closest("a[href]")) return;
    setOpen(false);
  }

  return (
    <div className={styles.root} data-inline={inline ? "" : undefined}>
      <div className={styles.bar}>
        <button
          ref={buttonRef}
          type="button"
          className={styles.trigger}
          data-active={activeCount > 0 ? "" : undefined}
          aria-expanded={open}
          aria-controls={panelId}
          aria-label={activeLabel ? `${name}: ${activeLabel}. Alterar filtro por ${noun}` : `${name}: filtrar por ${noun}`}
          onClick={() => setOpen((value) => !value)}
        >
          <Icon className={styles.triggerIcon} aria-hidden="true" />
          {name}
          {activeCount > 0 ? (
            <span className={styles.triggerCount} aria-hidden="true">
              {activeCount}
            </span>
          ) : null}
          <ChevronDown className={styles.chevron} aria-hidden="true" />
        </button>
        {chips}
      </div>
      <div id={panelId} className={styles.panel} hidden={!open} onKeyDown={onPanelKeyDown} onClick={onPanelClick}>
        {children}
      </div>
    </div>
  );
}

/**
 * Indicador de carregamento do link clicado (opção ou chip) enquanto a galeria
 * filtrada chega do servidor — resposta imediata ao toque, sem tempo artificial.
 * Precisa estar dentro do `<Link>`.
 */
export function TypeLinkPending() {
  const { pending } = useLinkStatus();
  return pending ? <Loader2 className={styles.pending} aria-hidden="true" /> : null;
}
