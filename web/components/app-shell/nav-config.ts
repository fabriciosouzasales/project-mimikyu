import { BookOpen, LayoutDashboard, Users, type LucideIcon } from "lucide-react";

export type NavChild = { href: string; label: string };

export type NavSection = {
  id: string;
  label: string;
  icon: LucideIcon;
  href: string;
  /** Itens do submenu — seções sem filhos (ex.: Visão geral) não têm submenu. */
  children?: NavChild[];
};

/**
 * Fonte única da navegação. O submenu "aberto" não é um estado guardado em
 * lugar nenhum — é sempre a seção retornada por `findActiveSection(pathname)`
 * (decisão explícita de Fabrício: reseta e é recalculado pela rota a cada
 * navegação, nunca persiste manualmente).
 */
export const NAV_SECTIONS: NavSection[] = [
  { id: "overview", label: "Visão geral", icon: LayoutDashboard, href: "/" },
  {
    id: "usuarios",
    label: "Usuários",
    icon: Users,
    href: "/usuarios",
    children: [{ href: "/usuarios", label: "Lista de usuários" }],
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

/** Determina a seção ativa (e, por consequência, o submenu aberto) a partir do pathname. */
export function findActiveSection(pathname: string): NavSection {
  const nonHome = NAV_SECTIONS.filter((section) => section.id !== "overview");
  const match = nonHome.find((section) => pathname === section.href || pathname.startsWith(`${section.href}/`));
  return match ?? (NAV_SECTIONS.find((section) => section.id === "overview") as NavSection);
}
