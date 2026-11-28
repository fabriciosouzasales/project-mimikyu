# V1-13 · G5 — Parecer GO/NO-GO da abertura funcional (etapa 7)

| Campo | Valor |
|---|---|
| **Gate** | G5 de `../2026-11-15-v1-13-e1e-security-evidence/BARRIER-FEASIBILITY-D-E1.md` §9 |
| **Data** | 2026-11-27 |
| **Parecer técnico** | **GO condicionado** a uma decisão do proprietário sobre a cobertura de ST1–ST9 e M1–M7 (§3). Sem ela, NO-GO. |
| **Decisão do proprietário** | **GO (2026-11-27):** a matriz da E4 é aceita como evidência de G4; ST e M restantes e a correção da política de Storage viram acompanhamento depois da abertura. Papéis e convites da E4 mantidos como estão. |

## 1. Gates anteriores

| Gate | Critério | Evidência | Situação |
|---|---|---|---|
| G0 | Viabilidade estática | `BARRIER-FEASIBILITY-D-E1.md` | PASS |
| G1 | Barreira preparada e verificada | `g1/` (5389, static check) | PASS |
| G2 | Barreira e cadeia provadas em ensaio | `e1e2/` (S0, G2_A, G2_B) | PASS |
| G3 | Porta persistida CLOSED; negação com JWT real | E1 DEPLOY (2026-11-18); sonda G3 15/15 antes e depois da E4 | PASS |
| G4 | Provas integradas em TEST | E4 executada (`docs/operations/v1-13-e4-homologation.md` §Resultado) | PASS nos itens da matriz; ver §3 |

## 2. Provas da E4 (TEST, contas reais, JWT real)

- **S1–S10 (C-244):** PASS, inclusive S8 concorrente e S10 (duas janelas: troca de papel durante a organização automática; titular e EDITOR na mesma posição e no mesmo fichário).
- **PR-04B:** PASS na mesma conta; entre contas, não aplicável.
- **P4-A/P4-B:** sonda TEST com JWT real pelo PostgREST, 47/47: tokens forjados, de outra coleção, de outra participação e de época anterior recusados; 5373/5374 sem EXECUTE; VIEWER e `anon` recusados em toda escrita; sem `physical_card_id` nas respostas.
- **Capa (5390, D-E3-6):** o EDITOR é recusado na pasta do titular pela API do Storage (E4-32) e no definidor de capa (E4-33).
- **Desempenho:** K1, lista de elegíveis e colocação em 112 e 126 ms (limite de 1.500 ms).
- **Barreira ao fim:** CLOSED, 0 identidades, funções canônicas (conferido por leitura depois do encerramento).
- **Correções do reteste:** D-E4-1–8 e D-E3-2 (5398) confirmadas pelo proprietário.

## 3. Lacunas frente ao texto original de G4

O G4 original (2026-11-15) lista também **ST1–ST9** (Storage pela API) e **M1–M7** (medições de desempenho). A matriz da E4, aprovada depois, cobriu parte deles:

| Item | Coberto pela E4 | Não coberto |
|---|---|---|
| ST1–ST9 | ST1/S6: EDITOR recusado na pasta do titular (E4-32); envio, troca e remoção pelo titular pela interface (F4.9) | Formato e tamanho pelo bucket, exclusão física e envios simultâneos não têm caso próprio registrado. Achado lateral: a política `collection_cover_insert_own` valida só a primeira pasta (sem escrita entre contas). |
| M1–M7 | K1 (elegíveis e colocação); tempos das telas no uso real da E4 | Medições com `EXPLAIN (ANALYZE, BUFFERS)` em volume sintético (ex.: M1, histórico com ≥ 5.000 eventos) não foram feitas. |

**Avaliação de risco:**
- **ST:** a imagem da capa é do titular (D-E3-6), e a escrita entre contas foi recusada. O que falta é higiene da própria pasta, sem exposição a outro usuário.
- **M:** as consultas novas usam índices conferidos por `EXPLAIN` (5398 em `ix_bae_owner_layout_time`). O volume atual é pequeno. Degradação apareceria primeiro no histórico de fichários muito grandes, e cada leitura é paginada (≤ 50).

**Decisão necessária do proprietário** (uma das duas):
1. **Aceitar a matriz da E4 como evidência suficiente de G4.** ST e M remanescentes viram acompanhamento depois da abertura, junto com a correção da política de Storage. → G5 = **GO**.
2. **Exigir ST1–ST9 e M1–M7 completos antes de abrir.** → G5 = **NO-GO** até uma rodada própria em TEST.

## 4. Riscos conhecidos ao abrir

- **D-E4-4 (parcial):** a resposta da organização automática do EDITOR às vezes não volta ao app. A escrita conclui, e a tela avisa em até 15 s.
- **Dados da homologação:** papéis e convites usados na E4 continuam nas contas do conjunto e passam a valer de verdade com a barreira aberta. Exemplo: Yasmim como EDITOR da Minha Pokédex e convite pendente do Ravi. Revisar antes de abrir.
- **Reversão:** `G5_CLOSE_MANIFEST.txt` fecha a barreira sem deploy. Dados gravados enquanto aberta ficam inertes.
