"use client";

import { useEffect } from "react";

const ANCHOR = /^#especie-(\d{4})$/;

/**
 * Marca o card da última ficha aberta (Pokédex P3c, 2026-10-12).
 *
 * O "voltar" da ficha leva a galeria para `/pokedex?…#especie-0025` (âncora já usada
 * para rolar até a espécie). Este componente lê essa âncora e põe `data-recent` no
 * link do card correspondente — o visual vem do CSS da grade. Sem âncora válida na
 * URL, nada é marcado: o destaque só existe quando esse contexto existe de fato.
 *
 * Por que não `:target` no CSS: a navegação do Next usa history.pushState, que não
 * atualiza `:target`. Componente sem saída visual e sem estado: um efeito por montagem
 * e por mudança de âncora.
 */
export function RecentSpeciesMarker() {
  useEffect(() => {
    let marked: HTMLElement | null = null;

    function apply() {
      marked?.removeAttribute("data-recent");
      marked = null;
      const match = ANCHOR.exec(window.location.hash);
      if (!match) return;
      const link = document.getElementById(`especie-${match[1]}`)?.querySelector<HTMLElement>("a[href]");
      if (!link) return;
      link.setAttribute("data-recent", "");
      marked = link;
    }

    apply();
    window.addEventListener("hashchange", apply);
    return () => {
      window.removeEventListener("hashchange", apply);
      marked?.removeAttribute("data-recent");
    };
  }, []);

  return null;
}
