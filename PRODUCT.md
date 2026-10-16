# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users

Today the platform is operated by Fabrício (owner/admin) and a small group of testers. The admin side (`/catalogo`, `/pricing`, `/usuarios`, `/pokedex/imagens`) is used to populate and validate the Catálogo Editorial, Card Variants, Pricing and Pokédex artwork. Since October 2026 there is also a first **collector-facing surface — the Pokédex** (`/pokedex`, `/pokedex/[numero]`, `/pokedex/favoritos`), available to any authenticated user. The repository records no external (non-tester) collector users.

The committed audience is Trading Card Game collectors managing their own physical collections — starting with Pokémon TCG. The Collection module (the collector's own cards, collections and binders) is the next strategic front; its backend exists, but its collector-facing experience has not been built or decided yet.

## Product Purpose

A professional platform for managing Trading Card Game collections, starting with Pokémon TCG, built on solid software-engineering principles and prepared for continuous evolution and eventual commercialization. Success today means a consistent, documented, scalable architecture and a catalog database ready for sustained growth — not yet collector-facing feature completeness.

## Positioning

Architecture designed from the outset to support multiple Trading Card Games on the same data model and platform, not a single-game (Pokémon) tool that happens to exist. The catalog's structural entities (`game`, `expansion`, `card_set`, `card`, `card_variant`, `card_asset`, etc.) are modeled to generalize across TCGs; Pokémon TCG is the first game onboarded, not the ceiling of the design.

## Operating Context

- **Catálogo Editorial** (admin-only, formally closed on 2026-08-08; Card Variants closed on 2026-10-11): the reference catalog of games, expansions, card sets, cards, variants and card assets, sourced mainly from TCGdex (plus Pokémon TCG API snapshots and Scrydex for specific gaps), with manual fallbacks. Content is bilingual (`en` + `pt-BR`). Administrative write and ingestion flows for Game, Expansion, Card Set, Card and Card Variant are implemented.
- **Pricing / "Valor de Mercado"** (admin): functional backend with scheduled refresh, admin screens and reports.
- **Pokédex** (collector-facing, published October 2026): National Pokédex gallery of 1,025 species, individual species pages, generation exploration, type filter, and personal favorite species (red heart, `/pokedex/favoritos`). Bilingual editorial text exists for 60 species; the remaining pt-BR editorial work runs as a separate, parallel front.
- **Identity & Access**: Supabase Auth integrated with `public.user_profile` (public identity via `username`, editable profile, avatar in Supabase Storage) and a separate `admin_user` role for administrative capability. Admin actions are logged (`catalog_admin_action_log`, `admin_action_log`).
- **Collections** (backend implemented, no collector-facing UI yet): the collector's domain — physical cards owned (Physical Card, Inventory), storage, collections, allocation of cards to collections, completion progress (set, master set, Pokédex), binder layout and bulk registration. Conceptually and logically modeled and approved (`docs/domain-modeling/collections/`), and physically implemented and validated in the live database between 2026-08-31 and 2026-09-09 (`docs/05d-colecoes-e-usuarios.md`). No product screen consumes it yet; only experimental UI spikes with mock data exist (`web/app/experimental/*`). Its resumption is the next strategic front, after a documentation gate (`DOC-GATE-01`, 2026-10-15).
- Infrastructure is a single Supabase project (`mimikyu-core`), PostgreSQL, region `sa-east-1` (São Paulo), timezone `America/Sao_Paulo`.

## Capabilities and Constraints

- Stack: Next.js (App Router) + React + TypeScript + Tailwind CSS, Supabase (Auth, Storage, Edge Functions, Postgres via `@supabase/ssr`). Technical/code language is English.
- User-facing UI copy and routes are Portuguese (`/catalogo`, `/catalogo/jogos`, `/catalogo/cartas`, `/catalogo/expansoes`, `/usuarios`, `/perfil`, `/configuracoes`, `/cadastro`, `/login`) — future UI work should default to PT-BR copy unless told otherwise.
- Admin screens are gated by server-side guards. The Pokédex is the only collector-facing surface; it requires an authenticated session (no anonymous access). There is still no public (logged-out) surface.
- Catalog tables keep RLS with admin-only direct read/write (`ADR-022`); collector-facing reads go through `SECURITY DEFINER` functions that require `auth.uid()` and expose only what the screen needs.
- Open/undecided: the public product name and brand (see Brand Commitments); scope and design of the Collection experience; valuation/analytics are probable future direction but not committed.

## Brand Commitments

"Mimikyu" is an internal project codename only, not a confirmed public-facing brand or product name. "MMKYU Collector" is the working name used across documents (e.g. `ADR-033`) and the app title is currently "MMKyu TCG Collector" (`web/app/layout.tsx`), but no formal public-brand decision is recorded. Future design work must not treat these names (or Pokémon-character branding implied by them) as settled public identity.

## Evidence on Hand

- Catalog size (dated baselines, not live counts): 200 Pokémon Card Sets and 30,261 card assets (2026-09-18); 21,166 active cards and 37,851 card variants at the Card Variants closing audit (2026-10-11). See `docs/README.md` and `docs/ROADMAP.md`.
- Pokédex reference data: 1,025 species with artwork, types and profiles; 60 species with pt-BR editorial text (2026-10-13).
- Working screens: admin (`/catalogo/*`, `/pricing/*`, `/usuarios`, `/pokedex/imagens`), collector-facing Pokédex (`/pokedex`, `/pokedex/[numero]`, `/pokedex/favoritos`), account (`/perfil`, `/configuracoes`) and auth flows (`login`, `cadastro`, `recuperar-senha`, `atualizar-senha`).
- No testimonials, pricing, case studies, or external customer evidence exist — none should be fabricated in design work.

## Product Principles

- Architecture and data model before feature implementation.
- Intentional simplicity — avoid solving problems the project doesn't have yet.
- Every material decision gets documented (ADRs, standards) before or alongside implementation.
- Evolution is incremental and vertical (one entity/cycle at a time), not speculative breadth.
- Quality over speed; each decision should generate more value than effort.

## Document status

This file is product context for the `impeccable` design skill and is **not** a normative source. The current project state lives in `docs/README.md` ("Status Atual do Projeto") and `docs/ROADMAP.md`; the active handoff is `docs/development/HANDOFF-2026-10-15.md`. Last reconciled on 2026-10-15 (`DOC-GATE-01`); before that, the content dated from early August 2026 and stated that Collections had not started and that no collector-facing surface existed — both no longer true.
