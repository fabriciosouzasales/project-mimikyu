import { BookOpen, LayoutDashboard, Users, type LucideIcon } from "lucide-react";

export type NavChild = { href: string; label: string };

export type NavSection = {
  id: string;
  label: string;
  icon: LucideIcon;
  href: string;
  /** Itens do submenu — seções sem filhos (ex.: Visão geral) não têm submenu. */
  children?: NavChild[];
  /** Só aparece no menu para administradores (ver ADR-021) — checagem de UX, não a autoridade de acesso: a página em si também nega acesso a não-admins. */
  adminOnly?: boolean;
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
    adminOnly: true,
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
    // Módulo restrito a administradores (ADR-022) — leitura dos dados
    // editoriais/operacionais já é bloqueada no banco via RLS (is_admin());
    // esta flag só evita mostrar o item a quem não teria acesso a nada nele.
    adminOnly: true,
  },
];

/** Seções visíveis no menu para o usuário atual — filtra `adminOnly` quando `isAdmin` é falso. */
export function getVisibleNavSections(isAdmin: boolean): NavSection[] {
  return NAV_SECTIONS.filter((section) => !section.adminOnly || isAdmin);
}

/** Determina a seção ativa (e, por consequência, o submenu aberto) a partir do pathname. */
export function findActiveSection(pathname: string): NavSection {
  const nonHome = NAV_SECTIONS.filter((section) => section.id !== "overview");
  const match = nonHome.find((section) => pathname === section.href || pathname.startsWith(`${section.href}/`));
  return match ?? (NAV_SECTIONS.find((section) => section.id === "overview") as NavSection);
}
