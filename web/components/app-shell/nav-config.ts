import {
  Activity,
  BookOpen,
  Boxes,
  CircleDollarSign,
  Copy,
  CreditCard,
  FileText,
  FileUp,
  Gamepad2,
  Globe,
  History,
  ImagePlus,
  Layers,
  LayoutDashboard,
  PencilLine,
  RefreshCw,
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
  {
    id: "pricing",
    // Rótulo "Valores de Mercado" e ícone CircleDollarSign — teste visual
    // pedido por Fabrício (2026-08-22), só label/ícone do menu PRIMÁRIO.
    // Ícone trocado de TrendingUp (1ª tentativa, aprovada mas achada
    // "mais analytics que valor de mercado") para CircleDollarSign após
    // comparação lado a lado de 6 variantes da lucide-react — traço menos
    // "gráfico", círculo fechado remete a cotação/valor monetário. `id`,
    // `href` e todo o domínio técnico "Pricing" (rotas, RPCs, tabelas,
    // docs) permanecem inalterados — ver CLAUDE.md/05f-pricing.md. Menu
    // secundário (`children`, abaixo) também não muda.
    //
    // Ajuste v3.5 (2026-08-23) — Fabrício aprovou o teste visual e pediu o
    // ajuste de concordância final: "Valores de Mercado" (plural) →
    // "Valor de Mercado" (singular), em toda a linguagem visível do módulo.
    // Este `label` alimenta tanto o menu primário quanto o título do painel
    // de navegação secundário (`activeSection.label` em
    // `secondary-panel.tsx`) — um único ponto, dois lugares corrigidos.
    label: "Valor de Mercado",
    icon: CircleDollarSign,
    href: "/pricing",
    // Bloco 1 do Pricing Admin (2026-08-22, lista final aprovada por
    // Fabrício após duas rodadas de ajuste — ver docs/development/
    // HANDOFF-2026-08-21.md): 11 rotas em três grupos, mesmo modelo
    // Gerencial/Cadastros/Operações do Catálogo Editorial. Só "Visão Geral"
    // (`/pricing`) tem tela real nesta rodada — as outras 10 são
    // `ComingSoonPage` (mesmo padrão de `importacao-api/page.tsx`), porque
    // item de menu não pode levar a 404. "Cobertura de Preços" foi
    // incorporada à Visão Geral (não é rota própria); "Sincronizações"
    // inclui a Política de Sincronização (frequência/dispatcher,
    // `pricing_refresh_policy`, migrations 3937/3938).
    children: [
      { href: "/pricing", label: "Visão Geral", section: "Gerencial", icon: LayoutDashboard },
      { href: "/pricing/saude-fontes", label: "Saúde das Fontes", section: "Gerencial", icon: Activity },
      { href: "/pricing/historico-execucoes", label: "Histórico de Execuções", section: "Gerencial", icon: History },
      { href: "/pricing/relatorios", label: "Central de Relatórios", section: "Gerencial", icon: FileText },
      { href: "/pricing/fontes", label: "Fontes de Preço", section: "Cadastros", icon: Globe },
      { href: "/pricing/mapeamentos-sets", label: "Mapeamentos de Sets", section: "Cadastros", icon: Layers },
      { href: "/pricing/mapeamentos-cartas", label: "Mapeamentos de Cartas", section: "Cadastros", icon: CreditCard },
      { href: "/pricing/condicoes", label: "Condições", section: "Cadastros", icon: Tag },
      // "Resolução de Mapeamentos" removida do menu em 2026-08-27 (pedido de
      // Fabrício): só faz sentido com um `mapping` específico selecionado
      // (`?mapping=<id>`), nunca como destino de navegação solto — é
      // alcançada apenas pela ação "Resolver" da fila em Mapeamentos de
      // Cartas. Acesso direto sem esse parâmetro agora redireciona para
      // `/pricing/mapeamentos-cartas` (ver `resolucao-mapeamentos/page.tsx`).
      { href: "/pricing/sincronizacoes", label: "Sincronizações", section: "Operações", icon: RefreshCw },
      // "Preços Manuais" (2026-08-27) — fallback manual do preço automático
      // (migrations 3967-3969): tela administrativa para definir/atualizar o
      // preço quando não existe automático utilizável na condição. Fica em
      // Operações, ao lado de "Sincronizações" — mesma natureza de ação
      // operacional sobre dado de preço, não cadastro estrutural.
      { href: "/pricing/precos-manuais", label: "Preços Manuais", section: "Operações", icon: PencilLine },
    ],
    // Todo o módulo é admin-only (mesma disciplina do Catálogo, ADR-022) —
    // pricing_refresh_policy/pricing_admin_action_log e as RPCs de leitura
    // agregada (get_pricing_admin_overview) já negam acesso a não-admin no
    // banco; esta flag só evita mostrar o item no menu a quem não veria
    // nada nele.
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
