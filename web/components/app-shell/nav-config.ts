import {
  BookOpen,
  Boxes,
  Copy,
  CreditCard,
  FileText,
  FileUp,
  Gamepad2,
  History,
  ImagePlus,
  Layers,
  LayoutDashboard,
  ScrollText,
  Sparkles,
  Tag,
  Users,
  type LucideIcon,
} from "lucide-react";

/**
 * `section` agrupa itens do submenu sob um título maiúsculo, com divisória
 * antes do primeiro item de cada novo grupo — modelo do sidebar de Database
 * do Supabase (referência de Fabrício, 2026-07-26). Campo opcional: itens
 * sem `section` (ex.: "Usuários", que tem um único filho) renderizam
 * exatamente como antes, sem título nem divisória — nenhum módulo fora do
 * Catálogo muda visualmente.
 *
 * `icon` (2026-07-31, pedido de Fabrício: "em todos os itens do bloco
 * Operações deve ter um ícone antes do título"; no mesmo dia, "ficou tão
 * bom que quero replicar para os blocos Cadastro e Gerencial" — hoje todo
 * item do submenu do Catálogo tem ícone. Continua opcional no tipo porque
 * "Lista de usuários" (único filho de Usuários) não usa.
 */
export type NavChild = { href: string; label: string; section?: string; icon?: LucideIcon };

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
    // Reestruturado em 2026-07-31 (pedido de Fabrício) — três grupos
    // (Gerencial/Cadastro/Operações) no lugar de Catálogo/Operação. Rótulos
    // e agrupamento são só de interface: não renomeiam nada no modelo de
    // dados (Game continua Game, Expansion continua Expansion etc.) — ver
    // comentário de `NavChild` acima. "Importação Manual"/"Via PDF"/"Via
    // API" são rotas novas, sem tela própria ainda (`ComingSoonPage`, ver
    // `web/app/catalogo/importacao-*/page.tsx`) — item de menu não pode
    // levar a 404 (bug já reportado por Fabrício, 2026-07-25).
    //
    // Cadastro no plural (ajuste do mesmo dia, pedido de Fabrício) — os
    // títulos das próprias páginas acompanham (ver `expansoes/page.tsx` e
    // `card-sets/page.tsx`), mesmo raciocínio da primeira rodada: menu e
    // título da página sempre dizem a mesma coisa.
    //
    // Reorganização de 2026-08-01 (retomada do dia, pedido de Fabrício —
    // início do subciclo Card criação/edição/variações/imagens):
    // 1. Bloco "Operações" trocou a categorização por MÉTODO de importação
    //    ("Importação Manual"/"Via PDF"/"Via API" — Query nunca implementada,
    //    só stubs) por categorização pelo QUE é importado: "Importar Cartas"
    //    (`/catalogo/importar-cartas`) e "Importar Imagens"
    //    (`/catalogo/importar-imagens`) — as duas frentes reais do trabalho
    //    de hoje. Rotas antigas (`importacao-manual`/`-pdf`/`-api`) não têm
    //    mais item de menu, mas os arquivos de página seguem no repositório
    //    (não podem ser removidos sem autorização explícita — sinalizar a
    //    Fabrício se a limpeza for desejada).
    // 2. Bloco "Gerencial" ganhou "Log de Atualizações"
    //    (`/catalogo/log-atualizacoes`) — trilha de auditoria de escrita
    //    administrativa (`catalog_admin_action_log`, ADR-023), distinta do
    //    "Histórico de Importações" (execuções do pipeline de imagens,
    //    `asset_import_run`) já existente no mesmo bloco.
    children: [
      { href: "/catalogo", label: "Visão Geral", section: "Gerencial", icon: LayoutDashboard },
      { href: "/catalogo/log-atualizacoes", label: "Log de Atualizações", section: "Gerencial", icon: ScrollText },
      { href: "/catalogo/importacoes", label: "Histórico de Importações", section: "Gerencial", icon: History },
      // Central de Relatórios (2026-08-09) — 4ª e última frente da Trilha 4
      // (Módulo Gerencial): 6 relatórios imprimíveis (@media print), hub em
      // /catalogo/relatorios.
      { href: "/catalogo/relatorios", label: "Central de Relatórios", section: "Gerencial", icon: FileText },
      // Ordem ajustada em 2026-08-07 (pedido de Fabrício): "Raridades" sobe
      // para o topo do bloco Cadastro, acima de "Jogos" — sem mudança de
      // significado, só de sequência visual.
      { href: "/catalogo/raridades", label: "Raridades", section: "Cadastro", icon: Tag },
      // Tipos de Variação (Incremento 2, ADR-028, 2026-08-15) — governança
      // administrativa da taxonomia canônica de card_variant_type, mesmo
      // grupo/posição lógica de Raridades (ambas taxonomias consumidas pela
      // Revisão de Variantes/Importar Cartas).
      { href: "/catalogo/tipos-variacao", label: "Tipos de Variação", section: "Cadastro", icon: Sparkles },
      { href: "/catalogo/jogos", label: "Jogos", section: "Cadastro", icon: Gamepad2 },
      { href: "/catalogo/expansoes", label: "Expansões", section: "Cadastro", icon: Layers },
      { href: "/catalogo/card-sets", label: "Coleções", section: "Cadastro", icon: Boxes },
      { href: "/catalogo/cartas", label: "Cartas", section: "Cadastro", icon: CreditCard },
      { href: "/catalogo/importar-cartas", label: "Importar Cartas", section: "Operações", icon: FileUp },
      { href: "/catalogo/importar-imagens", label: "Importar Imagens", section: "Operações", icon: ImagePlus },
      // Importar Variantes (Incremento 4, ADR-028, 2026-08-15) — cadastro em
      // lote de Card Variant a partir do dataset-fonte da TCGdex, mesmo
      // grupo Operações das outras duas frentes de importação. Pressupõe
      // Importar Cartas já concluído para o Card Set (a própria Edge
      // Function recusa sem card_set_external_reference).
      { href: "/catalogo/importar-variantes", label: "Importar Variantes", section: "Operações", icon: Copy },
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
