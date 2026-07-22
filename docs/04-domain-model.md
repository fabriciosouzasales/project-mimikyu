# Domain Model

| Campo | Valor |
|--------|-------|
| **Documento** | Domain Model |
| **Versão** | 1.0 |
| **Status** | Em elaboração |
| **Objetivo** | Definir o modelo conceitual do domínio do Project Mimikyu antes da modelagem lógica e física. |

---

# Purpose

Este documento descreve os conceitos fundamentais utilizados pelo sistema.

Seu objetivo é definir o domínio do problema antes da implementação no banco de dados.

Este documento não contém SQL nem detalhes físicos de implementação.

---

# Core Concepts

Os seguintes conceitos compõem o núcleo do domínio do sistema.

- Collection
- Expansion
- Card Set
- Card
- Card Variant
- Inventory Item
- Storage Location
- Game
- User Collection

---

# Concept Definitions

## Collection

*Documentação pendente.*

---
## Game (Jogo)

### O que é?

Representa um Trading Card Game suportado pelo Project Mimikyu.

Exemplos:

- Pokémon TCG
- Magic: The Gathering
- Disney Lorcana
- One Piece Card Game

---

### O que não é?

Não representa uma coleção, expansão ou conjunto de cartas.

Também não representa um fabricante ou uma empresa.

---

### Qual problema resolve?

Define a raiz do catálogo oficial do sistema.

Todo catálogo pertence obrigatoriamente a um único Game.

---

### Conceitos relacionados

Um Game pode possuir uma ou mais Expansions.

Cada Expansion agrupa seus respectivos Sets.
__

## Expansion

*Documentação pendente.*

---

## Card Set

*Documentação pendente.*

---

## Card

*Documentação pendente.*

---

## Card Variant

*Documentação pendente.*

---

## Inventory Item

*Documentação pendente.*

---

## Storage Location

*Documentação pendente.*

---

## User Collection

*Documentação pendente.*

---

# Revision History

| Versão | Descrição |
|---------|-----------|
| 1.0 | Estrutura inicial do modelo conceitual. |