import { BookOpen, LayoutDashboard, Users, type LucideIcon } from "lucide-react";

export type NavChild = { href: string; label: string };

export type NavSection = {
  id: string;
  label: string;
  icon: LucideIcon;
  href: string;
  /** Itens do submenu contextual — seções sem filhos (ex.: Visão geral) não abrem submenu. */
  children?: NavChild[];
};

/**
 * Fonte única da navegação de dois níveis (trilha de ícones + submenu).
 * Os filhos aqui refletem o que já está no roadmap de cada módulo (ver ADR-019
 * e o diagnóstico da fundação), mesmo que a página ainda não exista — o padrão
 * já estabelecido nesta fundação é ter o link e resolver o 404 quando a tela
 * for construída, não esconder a navegação futura.
 */
export const NAV_SECTIONS: NavSection[] = [
  { id: "overview", label: "Visão geral", icon: LayoutDashboard, href: "/" },
  {
    id: "usuarios",
    label: "Usuários",
    icon: Users,
    href: "/usuarios",
    children: [
      { href: "/usuarios", label: "Lista de usuários" },
      { href: "/perfil", label: "Meu perfil" },
    ],
  },
  {
    id: "catalogo",
    label: "Catálogo editorial",
    icon: BookOpen,
    href: "/catalogo",
    children: [
      { href: "/catalogo", label: "Visão geral" },
      { href: "/catalogo/jogos", label: "Jogos" },
      { href: "/catalogo/expansoes", label: "Expansões" },
      { href: "/catalogo/card-sets", label: "Card Sets" },
      { href: "/catalogo/cartas", label: "Cartas" },
      { href: "/catalogo/importacoes", label: "Histórico de importações" },
    ],
  },
];

/** Determina a seção ativa a partir do pathname (match exato ou por prefixo de subrota). */
export function findActiveSection(pathname: string): NavSection {
  const nonHome = NAV_SECTIONS.filter((section) => section.id !== "overview");
  const match = nonHome.find((section) => pathname === section.href || pathname.startsWith(`${section.href}/`));
  return match ?? (NAV_SECTIONS.find((section) => section.id === "overview") as NavSection);
}
