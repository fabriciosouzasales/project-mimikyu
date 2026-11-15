# V1-13 · E1-B2 — Curadoria do EDITOR: reservas, fixação, metadados e capa (5375–5377)

| Campo | Valor |
|---|---|
| **Estado** | **PROPOSTA LOCAL VERSIONADA — NÃO EXECUTADA, NÃO APLICADA, NÃO HOMOLOGADA.** Versionada em `V1-13 / E1-B2 \| LOCAL COMMIT AND CLOSEOUT-03` (commit `feat(v1-13): prepara curadoria complementar editor e storage`). Preparada em `V1-13 / E1-B2 \| EDITOR CURATION OPERATIONS-01` e revisada em `STORAGE HARDENING AND SCOPE REVIEW-02` (2026-11-15). Nenhum SQL executado, nenhum acesso ao LIVE, nenhum ambiente, nenhuma conta. Prova dinâmica (5890) **pendente**. |
| **Base** | HEAD `b19ee93` (E1-A `a40c707` e E1-B1 `b19ee93`, ambas sem execução). Depende da E1-A e da E1-B1 aplicadas. |
| **Contrato** | C-234, C-237 (reservas, fixação, mesclagem), C-238 (fichário do titular), C-239 (metadados e capa), C-241, C-243, C-244. |
| **Validação** | Sem ambiente isolado; só sob protocolo controlado e com autorização específica. S8 concorrente, S10 e PR-04B pendentes. |
| **Fora do escopo** | Pokédex (E1-B3), expansão do histórico (E1-B3/E1-D), operações em massa (E1-C), leituras 5323/5324 (E1-D), interface (E2/E3), homologação (E1-E). |

## Arquivos

| Arquivo | O que faz |
|---|---|
| `5375_create_editor_binder_curation_writes.sql` | `editor_set_binder_reservation`, `editor_clear_binder_reservation`, `editor_set_binder_lock`, todas por posição visível |
| `5376_create_editor_collection_metadata_writes.sql` | `assert_collection_editor` (interna), `editor_update_collection_metadata`, `editor_set_collection_cover_finish`, `editor_set_collection_cover_code`, `editor_set_collection_cover_logo` |
| `5377_create_editor_collection_cover_storage_policies.sql` (v1.1) | Ajudantes `collection_cover_editor_folder_ok` (ver/apagar) e `collection_cover_editor_can_upload` (envio, com trava) e três políticas novas de Storage para a capa |
| `5890_validate_editor_curation_HARNESS.sql` (v1.1) | Prova dinâmica: 44 verificações + F.2 (GATE 45). **Não executada** |
| `ROLLBACK_E1B2.sql` | Reversão R5377 → R5375 |
| `static_check_e1b2.py` | Verificação estática, 59 verificações |

Numeração conferida: o último número usado era `5374` (E1-B1) e o último harness, `5889`.

## Matriz de permissões (E1-B2)

| Capacidade | Titular | EDITOR de X | VIEWER / não membro / ex-membro / anon |
|---|---|---|---|
| Reservar | qualquer bolso, para qualquer participante (5276) | bolso OWN ou FREE; a reserva fica **sempre** registrada para X | ✘ |
| Liberar reserva | qualquer (5277) | só reserva de X | ✘ |
| Fixar / soltar | qualquer (5278) | só bolso OWN (com carta ou reserva de X) | ✘ |
| Mesclar / desfazer | só com imagem própria (5240) | **não se aplica** (ver abaixo) | ✘ |
| Nome e descrição | ✔ (5035) | ✔ | ✘ |
| Acabamento da capa da coleção | ✔ (5172) | ✔ | ✘ |
| Código da placa (livre/Pokédex) | ✔ (5180) | ✔ | ✘ |
| Imagem da placa (livre/Pokédex) | ✔ (5178) | ✔, com arquivo na pasta do **titular** | ✘ |
| Referência do Set, escopo do Master Set, política, modalidade, visibilidade, arquivar, excluir, membros, titularidade | ✔ | ✘ (nenhum parâmetro nem caminho) | ✘ |
| Identidade, acabamento, âncora e imagens do **fichário** | ✔ | ✘ (C-238; nada aqui as toca) | ✘ |

## Reservas, fixação e mesclagem

- **Base:** usam a fundação da E1-B1, sem alterá-la:
  - autorização e travas da 5371 (proprietária → layout → convidada → participação);
  - bolso pela posição;
  - classificação OWN/FREE/FOREIGN sob a trava do bolso.
- **Recusa:** bolso de terceiros e posição inexistente recebem a mesma `SLOT_NOT_EDITABLE`. Isso vale para carta ou reserva de outra coleção, fixado sem conteúdo de X, mesclagem, imagem ou referência alheia.
- **Reservar:**
  - em bolso OWN ou FREE, inclusive com carta de X (reserva da carta presente, como no V1-07);
  - qualquer reserva existente no bolso precisa ser de X;
  - a reserva nova é sempre de X, nunca a da carta nem a da proprietária quando X é convidada;
  - variante e acabamento são exclusivos;
  - reserva idêntica → `UNCHANGED`, sem evento;
  - **não aloca nada.**
- **Liberar:** só reserva de X em bolso OWN. Sem reserva → `UNCHANGED`.
- **Fixar e soltar:** só bolso OWN.
  - fixar um bolso livre ocuparia o espaço de todas as coleções;
  - soltar um bolso fixado sem conteúdo de X mexeria na fixação do titular;
  - os dois casos são recusados.
- **Mesclagem: nenhuma operação implementada.** Desde a 5238, a mesclagem só existe como "imagem em vários bolsos" do titular (5240). As RPCs genéricas `merge/unmerge_layout_region` não estão abertas a `authenticated`, e o gatilho impede mesclar bolsos com carta, reserva ou trava. Pela C-237/C-238, mesclagem com imagem é do titular. O escopo do EDITOR fica vazio no modelo vigente. Uma mesclagem sem imagem para o EDITOR seria funcionalidade nova (decisão 1 abaixo).

## Metadados e capa

- **Nome e descrição:** espelho da 5035. Nome sem brancos nas pontas e não vazio.
- **Objetivo textual: não implementado.** `collection` não tem campo de objetivo textual. O "objetivo" existente é estrutural (Set, escopo do Master Set, política) e é do titular. Não criei campo (decisão 2 abaixo).
- **Capa:** acabamento (espelho da 5172), código e imagem da placa (espelho da 5180/5178, só coleção livre ou Pokédex). O acabamento é o **da capa da coleção**, não o do fichário (5245, intocado).
- **Ajudante:** `assert_collection_editor` (interna) trava coleção X (FOR UPDATE) → participação (FOR SHARE), a mesma ordem de 5369/5370/5371. Coleção arquivada → `COLLECTION_ARCHIVED`, só depois de autorizado.

## Segurança de Storage (C-239)

| Política nova (TO authenticated) | Permite |
|---|---|
| `collection_cover_insert_editor` | EDITOR ACTIVE grava `<titular>/<coleção>/<uuid>.(png\|jpg\|webp)`, coleção ativa livre/Pokédex, **até 3 arquivos dele ainda não usados** na pasta |
| `collection_cover_select_editor` | EDITOR vê só os arquivos **que ele enviou** naquela pasta |
| `collection_cover_delete_editor` | EDITOR apaga só arquivos **que ele enviou**, nunca a capa atual |

- **O que não muda:** as políticas do dono (5176) e a leitura compartilhada da capa atual (5329).
- **Nunca é permitido ao EDITOR:**
  - ler, trocar ou apagar arquivo do titular;
  - gravar fora da pasta da coleção autorizada;
  - atualizar objeto, porque não há política de UPDATE.
- **VIEWER, estranho e anon:** não ganham nenhum acesso.
- **Ajudantes:** SECURITY DEFINER, como o precedente 5237, que evita recursão de RLS. Só respondem sobre o usuário da sessão.
  - `collection_cover_editor_folder_ok(name)` (STABLE): ver e apagar;
  - `collection_cover_editor_can_upload(name)` (VOLATILE): envio. Toma `pg_advisory_xact_lock` pela chave (EDITOR, coleção), reavalia a autorização e só então conta os arquivos dele ainda não usados.
- **Imagem da placa:** `editor_set_collection_cover_logo` aceita só arquivo na pasta do titular, enviado pelo EDITOR ou pelo titular. O arquivo anterior volta para exclusão só se o EDITOR o enviou.
- **Teto sob concorrência:**
  - sem trava, a contagem usa o snapshot do comando: N envios simultâneos do mesmo EDITOR veriam a mesma contagem e todos passariam;
  - com a trava, o segundo envio espera o fim da transação do primeiro. Em READ COMMITTED, a contagem seguinte, com snapshot novo, já inclui o arquivo confirmado. A chave inclui o usuário, então ninguém trava o envio de outro;
  - **não comprovado.** Depende de a API do Storage gravar a linha de `storage.objects` sob esta política, na mesma transação e em READ COMMITTED. Se ela testar a permissão numa transação e gravar em outra, ou usar outro isolamento, o teto volta a ser aproximado. O harness roda numa sessão só e prova a trava apenas estruturalmente (0.5). A prova real é de envios paralelos pela API, na homologação.
- **Limites:**
  - o arquivo antigo do titular substituído pelo EDITOR fica no armazenamento do titular (ver "Arquivos órfãos");
  - o comportamento real na API do Storage (upload e remove) só se prova na homologação.

## Arquivos órfãos

| Situação | Quando o arquivo deixa de ser usado | Quem pode apagar | Limpeza no fluxo atual |
|---|---|---|---|
| Titular troca ou tira a capa | quando a 5178 grava a nova capa | titular (5176) | o cliente apaga o anterior depois da troca gravada (`cover-logo-uploader.tsx`); se a troca falha, apaga o novo. Só no melhor esforço: fechar a página no meio deixa órfão |
| EDITOR troca a capa que ele mesmo enviou | quando a 5376 grava a nova capa | EDITOR (política nova) e titular (5176) | a 5376 devolve `removable_previous_path` para o cliente apagar. Interface do EDITOR ainda não existe (E2/E3) |
| EDITOR troca a capa que o titular enviou | quando a 5376 grava a nova capa | **só o titular** (5176) | nenhuma: a 5376 nunca devolve arquivo do titular. Fica órfão na pasta do titular |
| EDITOR envia e não usa | nunca chegou a ser usado | EDITOR e titular | nenhuma automática. Conta no teto de 3 até ser apagado |
| EDITOR perde o papel ou sai | arquivos dele que não são a capa ficam sem uso | **só o titular** (o ex-EDITOR perde ver e apagar na hora) | nenhuma. Não contam mais no teto de ninguém |
| Coleção arquivada ou excluída | conforme o fluxo do titular | titular | igual ao de hoje, sem mudança |

- **O titular pode limpar com segurança.** As políticas 5176 deixam o titular ver e apagar qualquer arquivo da própria pasta, inclusive os enviados pelo EDITOR. Apagar a capa atual quebra a imagem da placa até uma nova ser escolhida. Uma limpeza segura apaga só arquivos que não são a capa atual de nenhuma coleção.
- **O EDITOR nunca apaga arquivo do titular:** a política exige `owner_id` = EDITOR e nunca a capa atual. 5890 6.9 prova isso por DELETE direto.
- **Política futura:** precisa de limpeza do lado do titular (ferramenta "arquivos sem uso" ou rotina agendada). Fica registrada como limitação. Nenhuma rotina automática nesta etapa.

## Compatibilidade com o titular e com a E1-B1

- **Funções do titular:** 5276, 5277, 5278, 5035, 5172, 5178 e 5180 ficam byte a byte iguais (md5 no pre e postcheck). Os md5 de 5276–5278, 5178 e 5180 já foram registrados como iguais ao LIVE.
- **E1-B1 e E1-A:** inalteradas. A 5375 exige a 5371 e a 5372 (histórico com ator EDITOR).
- **Escrita direta:**
  - 5375: `collection_layout_slot_expected_content` e `collection_layout_slot.locked`;
  - 5376: as colunas `name`, `description`, `cover_finish`, `cover_code` e `cover_logo_path` de `collection`.
- **Escrita de auditoria:** eventos do histórico (reservar, liberar, fixar, soltar), com o EDITOR como ator e a coleção autorizada. Metadados e capa não têm evento no histórico do fichário, como no titular.
- **Escrita patrimonial:** nenhuma.
- **Dever de espelho:** mudanças futuras nas funções do titular listadas acima precisam ser repetidas aqui. A verificação estática 6.6 confere eventos e itens.

## Verificações

- **Estática** (executada, sem banco): `static_check_e1b2.py` → **59/59 PASS**.
- **Dinâmica** (pendente): `5890` → **45/45** esperado, sob protocolo controlado, depois de E1-A e E1-B1.

**Cenários cobertos pela 5890:**

- **Quem chama:** EDITOR autorizado; VIEWER; não membro; EDITOR removido; titular no caminho do EDITOR; EDITOR de outra coleção; anon.
- **Bolsos de terceiros:**
  - reserva de outra coleção;
  - bolso "vazio" que é fixado, mesclado ou com imagem;
  - fixação de terceiros;
  - mesclagem com conteúdo misto, que fica FOREIGN;
  - posição inexistente.
- **Fichário com várias coleções:** reservas e fixações em CO e CX.
- **Metadados e titular:** campos exclusivos do titular pelos caminhos dele; metadados e capa.
- **Storage:** envio dentro e fora da pasta, teto sequencial, VIEWER e anon, visão só dos próprios arquivos, troca de capa, arquivo do titular nunca devolvido, caminho na pasta do EDITOR recusado, DELETE direto (arquivo do titular e capa atual: 0 linhas; arquivo antigo do EDITOR: 1), forma da trava do teto.

| O que a 5890 prova (SQL, papel authenticated) | O que só a API real do Storage prova |
|---|---|
| políticas e ajudantes no lugar, ajudante de envio volátil com trava antes da contagem (0.4, 0.5) | teto sob envios paralelos |
| teto sequencial: o 4º envio é recusado (6.1) | que o `upload` grava sob a política de INSERT, na mesma transação e em READ COMMITTED |
| pasta errada, nome fora do formato, VIEWER, anon (6.2, 6.3) | `remove` pela API, que usa o próprio caminho de exclusão do Storage |
| ver só os próprios arquivos (6.4) | JWT real do PostgREST/Storage, em vez de `SET LOCAL ROLE` |
| troca de capa e arquivo do titular nunca oferecido (6.5–6.7) | tamanho e tipo do arquivo (limites do bucket) |
| exclusão: titular e capa atual protegidos (6.8, 6.9) | |
| capa final e arquivo do titular intactos (6.10); rebaixamento corta o envio (7.1) | |
- **Papel:** troca EDITOR → VIEWER com efeito imediato.
- **Histórico, titular e patrimônio:** eventos com o EDITOR; titular intocado; nenhum efeito patrimonial.
- **Coleção arquivada:** recusa.

| S1–S10 | Situação depois da E1-B2 |
|---|---|
| S1 (reservar, liberar, fixar, metadados, capa), S2, S3, S6, S7, S9 (Storage) | **Preparados na 5890, não executados** |
| S3: referência de espécie | Só por inspeção (fixture Pokédex = E1-B3) |
| S8 sequencial | 5890 7.1, não executado |
| S8 concorrente (inclui o teto de envio sob corrida) e S10 | **Pendentes** |

## Decisões de produto em aberto (não bloqueiam a E1-B2)

Registradas como **propostas, aguardando aprovação do proprietário.** C-237 e C-239 não foram alteradas. Nada foi implementado para elas.

| ID | Proposta | Detalhe |
|---|---|---|
| **D9** | Mesclagem não aplicável ao EDITOR no modelo atual | item 1 abaixo |
| **D10** | Objetivo narrativo representado pela descrição da coleção | item 2 abaixo |
| **D11** | Limpeza de arquivos órfãos de capa como melhoria operacional futura, sem versão comprometida | "Arquivos órfãos" acima |


1. **Mesclagem pelo EDITOR.**
   - **Interpretação confirmada:**
     - toda mesclagem vigente é a da 5240 (imagem do titular em vários bolsos);
     - as RPCs genéricas estão revogadas de `authenticated` desde a 5238;
     - o gatilho impede região sobre bolso com carta, reserva ou trava.
   - **Consequência:** o EDITOR não tem mesclagem a fazer sem tocar imagem do titular (C-238). Nenhuma mesclagem nova nesta rodada.
   - **Representação proposta** (só documental, sem mudar a norma): C-237 "mesclar" fica **"não aplicável no modelo vigente"**, não "entregue". C-238 continua valendo: imagem do fichário é do titular. A matriz da E1-B2 já mostra assim.
   - **Decisão do proprietário:** manter como não aplicável ou pedir, numa etapa futura, mesclagem sem imagem para o EDITOR (funcionalidade nova).
2. **Objetivo textual da coleção.**
   - **Confirmado:** `collection` não tem campo de objetivo textual. Nenhum campo criado.
   - **Refinamento proposto para a C-239** (texto para decisão, C-239 não alterada):
     > "O objetivo da coleção, para o EDITOR, é o texto livre da descrição. Os objetivos estruturais (Set de referência, escopo do Master Set, política de completude) são só do titular."
   - **Efeito, se aprovado:** a E1-B2 já cumpre a C-239 por `editor_update_collection_metadata`, sem mudança de modelo.
   - **Alternativa:** campo próprio de objetivo, mudança de modelo numa etapa futura.

## Riscos

1. **Storage:**
   - as políticas novas ainda não foram provadas na API real;
   - o teto sob envios paralelos depende da trava e de como a API grava. Não comprovado;
   - arquivos podem ficar órfãos (tabela acima), sem limpeza automática.
2. **Concorrência:** a ordem de travas é a mesma da E1-B1 e de 5369/5370, e não há ciclo por inspeção. **Não está aprovada sem S8/S10.**
3. **md5 não confirmados no LIVE:** os de 5035 e 5172 foram derivados dos arquivos; a S0 de qualquer execução precisa confirmá-los.
4. **Ordem de aplicação:** E1-A → E1-B1 → E1-B2.

## Critério para a E3 (interface)

- Comunicar com clareza o limite de 3 arquivos ainda não usados e quantos restam.
- Permitir que o EDITOR veja e apague os próprios envios não usados, pelas permissões da 5377: só arquivos dele, nunca a capa atual nem arquivos do titular.
- Depois da troca gravada, apagar o arquivo anterior devolvido pela 5376, como no fluxo do titular.
- Nada de frontend nesta etapa.

## Estado

| Item | Situação |
|---|---|
| E1-B2 | proposta local versionada, não executada nem homologada |
| Teto de envios simultâneos | prova pela API do Storage pendente |
| Harness 5890 | não executado |
| S1–S10 | sem comprovação dinâmica |
| S8 concorrente e S10 | pendentes |
| PR-04B | aberta |
| Publicação da V1-13 | bloqueada |
| D9–D11 | aguardando aprovação do proprietário |
