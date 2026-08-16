import type { Config } from "tailwindcss";

// Design tokens da fundação do frontend (Etapa 0) — Project Mimikyu.
// Paleta e escalas vivem em app/globals.css como CSS variables (light/dark);
// este arquivo apenas conecta essas variables às classes utilitárias do Tailwind.
const config: Config = {
  darkMode: ["class"],
  content: ["./app/**/*.{ts,tsx}", "./components/**/*.{ts,tsx}", "./lib/**/*.{ts,tsx}"],
  theme: {
    container: {
      center: true,
      padding: "1.5rem",
      screens: { "2xl": "1400px" },
    },
    extend: {
      colors: {
        border: "hsl(var(--border) / <alpha-value>)",
        input: "hsl(var(--input) / <alpha-value>)",
        ring: "hsl(var(--ring) / <alpha-value>)",
        background: "hsl(var(--background) / <alpha-value>)",
        foreground: "hsl(var(--foreground) / <alpha-value>)",
        surface: {
          DEFAULT: "hsl(var(--surface) / <alpha-value>)",
          muted: "hsl(var(--surface-muted) / <alpha-value>)",
        },
        primary: {
          DEFAULT: "hsl(var(--primary) / <alpha-value>)",
          foreground: "hsl(var(--primary-foreground) / <alpha-value>)",
          hover: "hsl(var(--primary-hover) / <alpha-value>)",
          active: "hsl(var(--primary-active) / <alpha-value>)",
          // Tom de dourado mais escuro/legível para uso como COR DE TEXTO
          // (links, nomes em destaque) — `--primary` puro tem contraste
          // insuficiente como texto sobre o workspace claro. Ver
          // app/globals.css, 2026-08-16.
          ink: "hsl(var(--primary-ink) / <alpha-value>)",
        },
        // Navegação (rail de ícones + painel contextual do AppShell) — âncora
        // fixa da identidade MMKYU, escura nos dois temas. O grosso da
        // navegação (fundo, bordas, texto) reusa os tokens genéricos
        // (surface/border/foreground/muted-foreground) via as classes de
        // escopo `.app-nav-rail`/`.app-nav-panel` em app/globals.css — só o
        // indicador de seleção/item ativo precisa de tokens PRÓPRIOS, porque
        // não pode reaproveitar `--accent`/`--primary` (cores do workspace,
        // que mudam por tema) nem `--foreground` (também sobrescrito pelo
        // escopo). Ver app/globals.css, 2026-08-16.
        nav: {
          gold: "hsl(var(--nav-gold) / <alpha-value>)",
          "active-surface": "hsl(var(--nav-active-surface) / <alpha-value>)",
          "active-ink": "hsl(var(--nav-active-ink) / <alpha-value>)",
          "panel-active-surface": "hsl(var(--nav-panel-active-surface) / <alpha-value>)",
        },
        accent: {
          DEFAULT: "hsl(var(--accent) / <alpha-value>)",
          foreground: "hsl(var(--accent-foreground) / <alpha-value>)",
        },
        destructive: {
          DEFAULT: "hsl(var(--destructive) / <alpha-value>)",
          foreground: "hsl(var(--destructive-foreground) / <alpha-value>)",
        },
        muted: {
          DEFAULT: "hsl(var(--muted) / <alpha-value>)",
          foreground: "hsl(var(--muted-foreground) / <alpha-value>)",
        },
        success: {
          DEFAULT: "hsl(var(--success) / <alpha-value>)",
          foreground: "hsl(var(--success-foreground) / <alpha-value>)",
        },
        warning: {
          DEFAULT: "hsl(var(--warning) / <alpha-value>)",
          foreground: "hsl(var(--warning-foreground) / <alpha-value>)",
        },
      },
      borderRadius: {
        lg: "var(--radius)",
        md: "calc(var(--radius) - 2px)",
        sm: "calc(var(--radius) - 4px)",
      },
      fontFamily: {
        sans: ["var(--font-sans)"],
        mono: ["var(--font-mono)"],
        heading: ["var(--font-heading)"],
      },
      boxShadow: {
        subtle: "0 1px 2px 0 hsl(var(--foreground) / 0.04)",
        panel: "0 1px 3px 0 hsl(var(--foreground) / 0.06), 0 1px 2px -1px hsl(var(--foreground) / 0.06)",
      },
      keyframes: {
        // Radix Collapsible expõe a altura real do conteúdo como variável CSS —
        // isso resolve o problema clássico de animar "height: auto" sem JS de medição manual.
        "collapsible-down": {
          from: { height: "0", opacity: "0" },
          to: { height: "var(--radix-collapsible-content-height)", opacity: "1" },
        },
        "collapsible-up": {
          from: { height: "var(--radix-collapsible-content-height)", opacity: "1" },
          to: { height: "0", opacity: "0" },
        },
        "drawer-in": { from: { transform: "translateX(-100%)" }, to: { transform: "translateX(0)" } },
        "drawer-out": { from: { transform: "translateX(0)" }, to: { transform: "translateX(-100%)" } },
        "overlay-in": { from: { opacity: "0" }, to: { opacity: "1" } },
        "overlay-out": { from: { opacity: "1" }, to: { opacity: "0" } },
        // Modal centralizado (Dialog) — zoom+fade sutil, distinto do slide
        // lateral do Drawer mobile (drawer-in/out, acima). Fundação visual,
        // Ciclo B (2026-07-30): primeiro consumidor é components/ui/dialog.tsx.
        "dialog-in": {
          from: { opacity: "0", transform: "translate(-50%, -48%) scale(0.96)" },
          to: { opacity: "1", transform: "translate(-50%, -50%) scale(1)" },
        },
        "dialog-out": {
          from: { opacity: "1", transform: "translate(-50%, -50%) scale(1)" },
          to: { opacity: "0", transform: "translate(-50%, -48%) scale(0.96)" },
        },
      },
      animation: {
        "collapsible-down": "collapsible-down 200ms ease-out",
        "collapsible-up": "collapsible-up 200ms ease-out",
        "drawer-in": "drawer-in 200ms ease-out",
        "drawer-out": "drawer-out 150ms ease-in",
        "overlay-in": "overlay-in 150ms ease-out",
        "overlay-out": "overlay-out 150ms ease-in",
        "dialog-in": "dialog-in 150ms ease-out",
        "dialog-out": "dialog-out 100ms ease-in",
      },
    },
  },
  plugins: [],
};

export default config;
