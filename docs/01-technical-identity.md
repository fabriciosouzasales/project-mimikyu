# Technical Identity

| Campo | Valor |
|--------|-------|
| **Documento** | Technical Identity |
| **Arquivo** | `docs/01-technical-identity.md` |
| **Versão** | 1.1 |
| **Status** | Aprovado |
| **Objetivo** | Consolidar a identidade técnica permanente do Project Mimikyu. |
| **Escopo** | Tecnologias, convenções e definições técnicas adotadas pelo projeto. |
| **Dependências** | `00-project-charter.md` |
| **Documentos Relacionados** | `docs/adr/ADR-001-environment-foundation.md`, `docs/adr/ADR-002-infrastructure-region.md`, `docs/adr/ADR-019-web-application-as-primary-interface.md` |

---

# Overview

Este documento define a identidade técnica oficial do Project Mimikyu. Seu objetivo é consolidar as principais decisões técnicas adotadas para o projeto, servindo como referência para todo o desenvolvimento.

As decisões registradas aqui representam o estado atual da plataforma. As justificativas e o processo de decisão permanecem documentados nas respectivas ADRs.

---

# Technical Identity

| Item | Valor |
|------|-------|
| **Project Codename** | Project Mimikyu |
| **Backend Platform** | Supabase |
| **Database** | PostgreSQL |
| **Primary Project** | `mimikyu-core` |
| **Infrastructure Region** | South America (São Paulo) — `sa-east-1` |
| **Time Zone** | America/Sao_Paulo |
| **Technical Language** | English |
| **Frontend Platform** | Aplicação web própria (React/Next.js) — ver `ADR-019` |
| **Authentication** | Supabase Auth, com entidade de domínio própria `user_profile` (ainda não modelada fisicamente) — ver `ADR-019` |

---

# Infrastructure Principles

- Um único projeto Supabase representa todo o backend da solução.
- Novos componentes da aplicação poderão surgir no futuro sem necessidade de novos projetos Supabase.
- O banco de dados é o núcleo da plataforma.
- A infraestrutura deve ser dimensionada para os próximos 3 a 5 anos, evitando tanto o subdimensionamento quanto o superdimensionamento.

---

# Revision History

| Versão | Descrição |
|---------|-----------|
| 1.0 | Criação inicial do documento. |
| 1.1 | Adicionadas as linhas **Frontend Platform** (aplicação web própria, React/Next.js) e **Authentication** (Supabase Auth + `user_profile`), formalizando `ADR-019-web-application-as-primary-interface.md` — primeira decisão de stack de front-end do projeto, substituindo Power Apps/SharePoint/Power BI como direção-alvo. |
