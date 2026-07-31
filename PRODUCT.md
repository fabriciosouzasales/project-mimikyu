# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users

Today, the platform has two real users: Fabrício (owner/admin) and a small group of testers — both operating the admin side of the product (`/catalogo`, `/usuarios`, `/perfil`, `/configuracoes`), populating and validating the Catálogo Editorial (games, expansions, card sets, cards, variants, assets). There are no external collector users yet.

The committed future audience (Sub-Fase 2 — Coleções, not yet started) is Trading Card Game collectors managing their own physical collections — starting with Pokémon TCG. Design and product decisions made now for admin surfaces should not assume collector-facing needs; decisions for anything collector-facing are still open.

## Product Purpose

A professional platform for managing Trading Card Game collections, starting with Pokémon TCG, built on solid software-engineering principles and prepared for continuous evolution and eventual commercialization. Success today means a consistent, documented, scalable architecture and a catalog database ready for sustained growth — not yet collector-facing feature completeness.

## Positioning

Architecture designed from the outset to support multiple Trading Card Games on the same data model and platform, not a single-game (Pokémon) tool that happens to exist. The catalog's structural entities (`game`, `expansion`, `card_set`, `card`, `card_variant`, `card_asset`, etc.) are modeled to generalize across TCGs; Pokémon TCG is the first game onboarded, not the ceiling of the design.

## Operating Context

- **Catálogo Editorial** (admin-only, in active build): the reference catalog of games, expansions, card sets, cards, variants, and card assets (images), sourced primarily from TCGdex via an automated import pipeline, with a manual fallback path for assets missing at the source. Content is bilingual (`en` + `pt-BR`). Administrative writes go through vertical per-entity cycles (backend → screen → validation): `Game` and `Expansion` are complete; `Card Set` is next; `Card` create/edit and deactivate/reactivate follow.
- **Identity & Access**: Supabase Auth integrated with `public.user_profile` (public identity via `username`, editable profile, avatar in Supabase Storage) and a separate `admin_user` role for administrative capability. Admin actions are logged (`catalog_admin_action_log`, `admin_action_log`).
- **Collections** (planned, not started): the collector's domain — physical copies owned, collection goals, and the relationship between them. Conceptually modeled and approved but has no physical schema or tables yet. Starts only after the Catálogo Editorial's five fronts (data model, asset pipeline, read UI, admin write, admin ingestion) are all closed.
- Infrastructure is a single Supabase project (`mimikyu-core`), PostgreSQL, region `sa-east-1` (São Paulo), timezone `America/Sao_Paulo`.

## Capabilities and Constraints

- Stack: Next.js (App Router) + React + TypeScript + Tailwind CSS, Supabase (Auth, Storage, Edge Functions, Postgres via `@supabase/ssr`). Technical/code language is English.
- User-facing UI copy and routes are Portuguese (`/catalogo`, `/catalogo/jogos`, `/catalogo/cartas`, `/catalogo/expansoes`, `/usuarios`, `/perfil`, `/configuracoes`, `/cadastro`, `/login`) — future UI work should default to PT-BR copy unless told otherwise.
- Every screen that exists today is admin/internal tooling, gated by server-side guards; there is no public/collector-facing surface yet.
- Catalog tables currently have RLS enabled and admin-only read/write policies (`ADR-022`); nothing in the catalog is publicly readable today.
- Open/undecided: the public product name and brand (see Brand Commitments); scope and design of collector-facing surfaces (Sub-Fase 2); acquisition/movement tracking and valuation/analytics are listed as probable future direction but not committed.

## Brand Commitments

"Mimikyu" is an internal project codename only, not a confirmed public-facing brand or product name. Future design work must not treat "Mimikyu" (or Pokémon-character branding implied by the name) as settled user-facing identity — the real name is pending a future decision.

## Evidence on Hand

- 927 cards catalogued across 7 Card Sets (the `ME` expansion — Mega Evolution).
- 1,718 card assets imported (`en` + `pt-BR`) for the 5 original collections, 0 failures, via the automated `import-card-assets` pipeline (TCGdex-sourced); manual import path (`source_code = 'MANUAL'`) used for assets confirmed missing at the source.
- Working admin screens already in the repo: `/catalogo` (overview), `/catalogo/jogos`, `/catalogo/expansoes`, `/catalogo/card-sets` (+ detail), `/catalogo/cartas`, `/catalogo/importacoes`, `/usuarios`, `/perfil`, `/configuracoes`, plus auth flows (`login`, `cadastro`, `recuperar-senha`, `atualizar-senha`).
- No testimonials, pricing, case studies, or external customer evidence exist — none should be fabricated in design work.

## Product Principles

- Architecture and data model before feature implementation.
- Intentional simplicity — avoid solving problems the project doesn't have yet.
- Every material decision gets documented (ADRs, standards) before or alongside implementation.
- Evolution is incremental and vertical (one entity/cycle at a time), not speculative breadth.
- Quality over speed; each decision should generate more value than effort.
