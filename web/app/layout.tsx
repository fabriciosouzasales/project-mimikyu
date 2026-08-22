import type { Metadata } from "next";
import { Inter, Manrope } from "next/font/google";
import { GeistMono } from "geist/font/mono";
import { SpeedInsights } from "@vercel/speed-insights/next";
import { Analytics } from "@vercel/analytics/next";
import { SessionRefresher } from "@/components/auth/session-refresher";
import { ThemeProvider } from "@/components/theme-provider";
import { TooltipProvider } from "@/components/ui/tooltip";
import "./globals.css";

// Inter substitui Geist Sans em 2026-07-26: pedido de Fabrício para igualar a
// tipografia do app à do Supabase Dashboard (confirmado via DevTools —
// font-family: inter, 13px — no submenu de referência). Geist Mono é mantida
// para o token --font-mono, que não foi objeto do pedido.
const inter = Inter({ subsets: ["latin"], variable: "--font-inter" });

// Manrope, também em 2026-07-26: Fabrício identificou via DevTools que o
// Supabase Dashboard usa uma fonte separada (Manrope) para títulos de página
// (ex.: h4 "Settings", 16px) — diferente do Inter usado na navegação. Vira o
// token --font-heading, aplicado só nos títulos de página (h1 de cada rota),
// não no --font-sans do corpo do texto.
const manrope = Manrope({ subsets: ["latin"], variable: "--font-manrope" });

export const metadata: Metadata = {
  title: "MMKyu TCG Collector",
  description: "Plataforma para gestão de coleções de Pokémon TCG.",
  // Favicon com o mascote (Mimikyu) — pedido de Fabrício em 2026-08-02, inspirado
  // em como a página oficial da Pokémon usa seu ícone na aba do navegador.
  // Duas variantes (olhos+boca claros/escuros) alternam via prefers-color-scheme
  // para permanecer legível tanto em abas de navegador claras quanto escuras.
  // Fonte: web/public/brand/icon-mark-{light,dark}.png, recortadas e
  // centralizadas em web/public/favicon/.
  icons: {
    icon: [
      { url: "/favicon/icon-light.png", media: "(prefers-color-scheme: light)" },
      { url: "/favicon/icon-dark.png", media: "(prefers-color-scheme: dark)" },
    ],
    apple: [{ url: "/favicon/apple-icon.png" }],
  },
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html
      lang="pt-BR"
      suppressHydrationWarning
      className={`${inter.variable} ${manrope.variable} ${GeistMono.variable}`}
    >
      <body>
        <ThemeProvider attribute="class" defaultTheme="system" enableSystem disableTransitionOnChange>
          {/* delayDuration=0: tooltip instantâneo, pedido explícito de Fabrício (o title nativo do navegador demorava ~1s e parecia quebrado) */}
          <TooltipProvider delayDuration={0}>{children}</TooltipProvider>
        </ThemeProvider>
        <SessionRefresher />
        <SpeedInsights />
        <Analytics />
      </body>
    </html>
  );
}
