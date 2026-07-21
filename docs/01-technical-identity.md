# Technical Identity

| Campo | Valor |
|--------|-------|
| **Documento** | Technical Identity |
| **Arquivo** | `docs/01-technical-identity.md` |
| **Versão** | 1.0 |
| **Status** | Aprovado |
| **Objetivo** | Consolidar a identidade técnica permanente do Project Mimikyu. |
| **Escopo** | Tecnologias, convenções e definições técnicas adotadas pelo projeto. |
| **Dependências** | `00-project-charter.md` |
| **Documentos Relacionados** | `docs/adr/ADR-001-*.md`, `docs/adr/ADR-002-*.md` |

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