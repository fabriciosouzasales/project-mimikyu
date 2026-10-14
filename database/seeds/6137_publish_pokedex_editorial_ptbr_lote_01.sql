-- Query 6137 | Pokédex P3e — publicação do P3e-lote-01: editorial MMKYU pt-BR (50 espécies, 100 linhas)
--
-- Tipo: PUBLICAÇÃO DE DADOS EDITORIAIS (não é migration de esquema; sem DDL, funções ou grants).
-- Status: CANÔNICA — CONFIRMADO EXECUTADO / LIVE em 2026-10-13 (UTC 2026-10-14 01:01:53), projeto
--         qjfutqujxrbzgrtkpgkg, via execute_sql DIRETO (MCP Supabase), com o begin/commit do próprio
--         arquivo. SEM ENTRADA DE LEDGER (mesmo regime da 6136 e das seeds 2240–2256): supabase_migrations
--         permaneceu em 419.
-- Mandato: Fabrício, 2026-10-13 — "AUTORIZO EXPRESSAMENTE A EXECUÇÃO DEFINITIVA DA QUERY 6137 NO LIVE,
--         exclusivamente para publicar o Lote 01 de 50 espécies já aprovadas."
-- Proveniência: database/proposals/2026-10-12-pokedex-p3e-editorial-lote-01/ — proposta sha256
--         6032b2672d3e4f46d1df35c6a2acb7561cdc827267435106e5a286e0b3aac4b8 (gerada deterministicamente do
--         JSON revisão 11, sha256 73ab17d3…f001), executada sem alteração de lógica; este arquivo difere da
--         proposta só neste cabeçalho de status. Ensaio LIVE com rollback integral = PASS antes da execução.
-- Validação: 6848 (proposta, inalterada) = PASS sobre os dados persistidos; 120 editoriais / 60 espécies;
--         hash do conjunto do lote 4a4a08f4930965918f9b093d809ebca2; P3d preservada (conjunto
--         6c1653539c8abbb5ed06c1a4159e294b, metadados 98de7d5ff26ebbba74937f1c84e7cc9d); SOURCE 2.050 /
--         ca8e9c87244160063971bd1a9f808b78.
-- Gerado por scripts/editorial/generate-editorial-lot-sql.ts — NÃO EDITAR À MÃO; regerar a partir do JSON.
-- Lote: P3e-lote-01 · revisão 11 · guia 0.2 · sha256 do JSON 73ab17d3fbb634b504e86854450cf0f89ccfa0fe32d67c6d7913d8f49fddf001
-- Publicado preservado: database/proposals/2026-10-12-pokedex-p3d-editorial-ptbr/pilot-pt-BR.json · sha256 4d2edea2f7848abb5193f6a27e8ba205eda4921dab9362049dfcac9fa5045115
--
-- Objetivo
-- Gravar em public.pokemon_species_text a classificação (GENUS) e a descrição (FLAVOR) editoriais
-- MMKYU em pt-BR das 50 espécies do lote aprovado. Conteúdo autoral MMKYU — nunca oficial.
--
-- Garantias (falha integral: qualquer violação lança exceção e nada é gravado)
-- 1. Payload: 100 textos de 50 espécies, md5 de cada texto igual ao aprovado no JSON; nenhuma
--    espécie de lote já publicado; conteúdo entre 1 e 2000 caracteres.
-- 2. Pré-condições: 50 espécies ativas, perfil IMPORTED, com GENUS + FLAVOR SOURCE en;
--    SOURCE = 2050 linhas com o hash de linha de base; editorial fora do lote = exatamente os
--    20 registros publicados (10 espécies), com md5 iguais aos versionados.
-- 3. Escrita restrita a origin = 'MMKYU_EDITORIAL' das 50 espécies (INSERT ... ON CONFLICT na
--    chave editorial; SOURCE nunca é alvo). Idempotente: reexecução não cria linhas.
-- 4. Pós-condições na mesma transação: 100 linhas do lote com conteúdo exato; total editorial =
--    120 linhas / 60 espécies; SOURCE inalterado; editoriais publicados inalterados (id,
--    conteúdo e updated_at).

begin;

do $pub$
declare
  v_lot constant integer[] := array[4, 6, 7, 39, 52, 54, 94, 133, 143, 151, 155, 175, 197, 212, 248, 249, 257, 282, 359, 382, 384, 385, 393, 405, 445, 448, 483, 491, 494, 495, 530, 609, 643, 658, 681, 700, 701, 716, 722, 745, 778, 791, 823, 873, 887, 888, 908, 959, 998, 1000];
  v_published constant integer[] := array[1, 25, 150, 201, 493, 649, 721, 905, 906, 1025];
  v_source_baseline_count constant integer := 2050;
  v_source_baseline_md5 constant text := 'ca8e9c87244160063971bd1a9f808b78';
  v_n integer;
  v_written integer;
  v_source_md5 text;
  v_published_before text;
  v_published_after text;
begin
  create temporary table p3e_lote_01_text (
    national_dex_number integer not null,
    text_kind text not null,
    content text not null,
    content_md5 text not null,
    primary key (national_dex_number, text_kind)
  ) on commit drop;

  insert into p3e_lote_01_text (national_dex_number, text_kind, content, content_md5) values
    (   4, 'GENUS',  $t$Pokémon Lagarto$t$, 'b24a7e70e2d533ce4eef92e3c3dc1a31'),
    (   4, 'FLAVOR', $t$Charmander já nasce com fogo: uma pequena chama arde na ponta de sua cauda desde o primeiro dia. Ela acompanha a vida inteira do Pokémon e está ligada a ela de forma tão estreita que, se um dia se apagasse, Charmander não sobreviveria.$t$, '343335b22fdd573894634e9e19eb0557'),
    (   6, 'GENUS',  $t$Pokémon Chama$t$, '9f92472c0938112d9d44f849651ce1bd'),
    (   6, 'FLAVOR', $t$Charizard reúne voo e fogo na mesma silhueta. Suas asas o elevam a cerca de 1.400 metros de altitude, e as labaredas que lança chegam a temperaturas altíssimas.$t$, '9743cae699f8a3ae3ef23fdcf73a2442'),
    (   7, 'GENUS',  $t$Pokémon Tartaruguinha$t$, '33407a53a4904f248cc7e8b01cca01f9'),
    (   7, 'FLAVOR', $t$Squirtle tem uma defesa em dois tempos. Diante de uma ameaça, recolhe os membros para dentro do casco e, já protegido, responde com jatos de água disparados pela boca.$t$, '5b112eade7decef9ecbf35c1d8012127'),
    (  39, 'GENUS',  $t$Pokémon Balão$t$, '2e32f89c3ee9b7d452ab45405054edcf'),
    (  39, 'FLAVOR', $t$O instrumento de Jigglypuff é a própria voz, que ele modula à vontade. Dessa afinação nasce uma melodia enigmática, capaz de fazer adormecer quem a escuta.$t$, '532b3cca9c2aa60d7ea3a54e28cd5b5c'),
    (  52, 'GENUS',  $t$Pokémon Gato-Arranhador$t$, '309165673409905f16cf135cb3ade0fa'),
    (  52, 'FLAVOR', $t$Meowth lava o rosto com frequência para manter impecável a moeda que traz na testa. Com o Meowth de Galar, sua forma regional, a convivência não costuma ser boa.$t$, '64470b6b27a745546826a812de143479'),
    (  54, 'GENUS',  $t$Pokémon Pato$t$, '5e4beb323ec546b053ece35cad31fe77'),
    (  54, 'FLAVOR', $t$Psyduck convive com dores de cabeça que não dão trégua. Quando o incômodo passa do limite, um poder latente escapa à revelia dele — e foi esse sofrimento que levou um pesquisador de Hisui a buscar maneiras de aliviá-lo.$t$, '533dd3ec252fb9854aba6083835b8a14'),
    (  94, 'GENUS',  $t$Pokémon Sombra$t$, '58a039a54d455f2d5dd3e0348a40dcfc'),
    (  94, 'FLAVOR', $t$Registros de Hisui associam Gengar às sombras: segundo eles, o Pokémon se apossa da sombra de outros seres para lhes tirar a vida. Os mesmos registros orientam quem perceber a própria sombra rindo a recorrer a um amuleto de proteção.$t$, '830c01f7f5b764e8274369299b3f5c97'),
    ( 133, 'GENUS',  $t$Pokémon Evolução$t$, 'a41190d264d3703c2f84dac2868111fc'),
    ( 133, 'FLAVOR', $t$A marca de Eevee é a versatilidade: sua evolução pode seguir por caminhos diferentes e levar a formas bem variadas. Essa abertura fez dele, para um pesquisador de Hisui, uma chave para os mistérios da evolução Pokémon.$t$, '7eeeae80d9ec1e6190d0a3658ca42c97'),
    ( 143, 'GENUS',  $t$Pokémon Dorminhoco$t$, 'b44b3c01e5af5be6a5af1cc1108d0ce2'),
    ( 143, 'FLAVOR', $t$Nos vilarejos de Hisui, Snorlax aparecia sem aviso e devorava celeiros inteiros de arroz. Para comunidades que dependiam dessas reservas, sua chegada era motivo de grande preocupação.$t$, '61c6f59e35995f73487c5288b95238c1'),
    ( 151, 'GENUS',  $t$Pokémon Nova Espécie$t$, '18d8ec6a20b3a3b3288bfa72bf0ce058'),
    ( 151, 'FLAVOR', $t$Mew guarda uma surpresa para quem o observa de perto: ao microscópio, seu corpo revela pelos curtos, finos e delicados.$t$, 'c69bd73a6d87c7709bf0bbc428ddd0f6'),
    ( 155, 'GENUS',  $t$Pokémon Rato de Fogo$t$, '0245650b1405a4c97af318d9a5e88cba'),
    ( 155, 'FLAVOR', $t$Tímido por natureza, Cyndaquil costuma ficar enrolado como uma bola. A postura recolhida, porém, esconde um poder de fogo notável.$t$, 'a3f4634e0ea6313cc8174c3cb5dfaa3d'),
    ( 175, 'GENUS',  $t$Pokémon Bola de Espinhos$t$, '0f3dc2d6d7063b5060d1afa2a194a2a0'),
    ( 175, 'FLAVOR', $t$Quem cruza com Togepi em campos ou montanhas pode achar que viu um ovo andando — engano frequente, por causa de seu corpo ovalado. O sorriso ingênuo que exibe tem efeito tranquilizador.$t$, '01f3aae0593caef4476048cbfe633bd5'),
    ( 197, 'GENUS',  $t$Pokémon Luar$t$, 'a1a4bf3659f9f6585b829fba950fdd5a'),
    ( 197, 'FLAVOR', $t$Umbreon é uma criatura da madrugada: sua atividade se intensifica quando o luar se espalha pela paisagem. Os olhos grandes atravessam a escuridão e permitem enxergar presas com nitidez.$t$, 'bfcf5738cfe3c4c75b036ef907ece037'),
    ( 212, 'GENUS',  $t$Pokémon Pinça$t$, '9f4618b8cc507be88a55f517dc86843b'),
    ( 212, 'FLAVOR', $t$O corpo de Scizor é protegido por uma carapaça cuja resistência já se mostrou superior à do aço forjado.$t$, 'cf89ebf61f640f83f54f7ec24bf2ce87'),
    ( 248, 'GENUS',  $t$Pokémon Armadura$t$, '3c6dbcff474e09bed96c55ff2c4b49b7'),
    ( 248, 'FLAVOR', $t$Tyranitar é capaz de alterar a paisagem por onde passa. Seus passos provocam tremores que podem abalar até grandes montanhas e modificar o terreno ao redor.$t$, '4c8d023f2e23fd1c72c9c528996c20f6'),
    ( 249, 'GENUS',  $t$Pokémon Mergulhador$t$, '3ddcfcadb80e30bc48d5974ce5c52d48'),
    ( 249, 'FLAVOR', $t$Lugia vive longe dos olhares, nas profundezas do mar — escolha ligada à força das próprias asas. Um simples bater delas basta para pôr abaixo casas comuns.$t$, 'd48621e41565e76701d805e8560cfccc'),
    ( 257, 'GENUS',  $t$Pokémon Labareda$t$, '8b49ff1491b01304d13b468ba7fce892'),
    ( 257, 'FLAVOR', $t$A força de Blaziken está nas pernas, capazes de levá-lo por cima de um prédio de 30 andares em um só salto. Já os socos, envoltos em chamas, deixam os adversários chamuscados.$t$, 'c9cb7eb264981b9371586ecdf69ce2fd'),
    ( 282, 'GENUS',  $t$Pokémon Abraço$t$, 'ffc965bd4092d93d6db22581044f4db3'),
    ( 282, 'FLAVOR', $t$Gardevoir se dedica a proteger o Treinador a quem se afeiçoa. Uma vez estabelecido esse vínculo, coloca a defesa dele acima da própria segurança.$t$, '643000e8d65a84f099f1fc176aa8e79e'),
    ( 359, 'GENUS',  $t$Pokémon Desastre$t$, 'ac79a97a83e1abb5d28b61badc16efae'),
    ( 359, 'FLAVOR', $t$Absol pressente o perigo — e foi justamente essa sensibilidade que, no passado, levou as pessoas a confundi-lo com um mensageiro da desgraça.$t$, 'ea4f32d6d1f0a9e50d421a3b6f1ed03c'),
    ( 382, 'GENUS',  $t$Pokémon Bacia Oceânica$t$, '0c307a7fc8d7bdbcf277d78ee6d1215f'),
    ( 382, 'FLAVOR', $t$Kyogre é tido como a personificação do próprio mar. Segundo as lendas, ele e Groudon se enfrentaram repetidas vezes, cada um em busca do domínio sobre as forças da natureza.$t$, '37b0a7afa2ec85213627e485e91c23b6'),
    ( 384, 'GENUS',  $t$Pokémon Alto Céu$t$, '28610adb538038f02db36666c2e3747c'),
    ( 384, 'FLAVOR', $t$A energia de que Rayquaza precisa para a Mega Evolução vem dos meteoroides que acumula no corpo — seu alimento durante os longos voos pela camada de ozônio.$t$, '274e8bb7e47ced8f09f7b6732d585792'),
    ( 385, 'GENUS',  $t$Pokémon Desejo$t$, 'f4e99f4a3ff0911c3eff99bc3254bd51'),
    ( 385, 'FLAVOR', $t$Segundo a crença, Jirachi desperta de um sono de mil anos e, então, realiza os desejos escritos nos bilhetes presos à sua cabeça.$t$, 'fb649717e5f546a6c4ac014926aa1916'),
    ( 393, 'GENUS',  $t$Pokémon Pinguim$t$, '7ae75282e5974a837bce7d55cff14583'),
    ( 393, 'FLAVOR', $t$Piplup prefere regiões frias e costuma aparecer no litoral. Por trás da aparência adorável há um temperamento orgulhoso: ele recusa o que as pessoas lhe oferecem.$t$, 'de583feff1e0107bb257ba343f25e2e7'),
    ( 405, 'GENUS',  $t$Pokémon Olhos Brilhantes$t$, '2dd4da7ea9a3d0f54d8821bac55f56c3'),
    ( 405, 'FLAVOR', $t$Luxray vive em bandos, cada um conduzido por um macho. Sobre seus olhos, corre uma lenda: quando brilham em dourado, Luxray seria capaz de enxergar através dos objetos.$t$, '96b786fa9c3e113fb93919fe12845d80'),
    ( 445, 'GENUS',  $t$Pokémon Mach$t$, '65e96af2db4c2e828f710b9c5b5bbf68'),
    ( 445, 'FLAVOR', $t$Garchomp cruza os céus em velocidade vertiginosa. Seu temperamento é selvagem, e encontrá-lo na natureza exige muita cautela.$t$, '8e635338c33ab41d5357a510071e1a86'),
    ( 448, 'GENUS',  $t$Pokémon Aura$t$, 'ec8c96672616044281b3139e97babeb9'),
    ( 448, 'FLAVOR', $t$Lucario emite ondas de energia e as controla com precisão, usando-as para perceber outros seres mesmo a grande distância. Um pesquisador de Hisui, ao descrever esse poder, deu-lhe o nome de “aura”.$t$, 'fd55b91c878fa2650fcbb099ff809e46'),
    ( 483, 'GENUS',  $t$Pokémon Temporal$t$, '099aabfeece0a97765abeb104dec3751'),
    ( 483, 'FLAVOR', $t$As lendas de Hisui reverenciam Dialga como divindade e ligam seu nascimento à origem do tempo: teria sido ele a pôr em curso o grande rio do tempo no mundo.$t$, 'cb1196a57b390792bc37ec1dfaccad0f'),
    ( 491, 'GENUS',  $t$Pokémon Breu$t$, 'd1a4cf787e901ba0739c9f43ba20afa5'),
    ( 491, 'FLAVOR', $t$Um relato conta que, numa noite sem lua, todos os moradores de um vilarejo tiveram pesadelos. Segundo os próprios moradores, Darkrai aparecia nesses sonhos.$t$, 'bcef8b0432a7a340c46753524a7fbc28'),
    ( 494, 'GENUS',  $t$Pokémon Vitória$t$, '37b7c9340dd9190ef47e9901991b5854'),
    ( 494, 'FLAVOR', $t$Victini gera uma energia descrita como infinita. Quando ele a compartilha, o corpo de quem a recebe passa a transbordar de força.$t$, 'bb9e8bca29f51e6c7b4700c199b9afb2'),
    ( 495, 'GENUS',  $t$Pokémon Cobra-Planta$t$, '956d411657ebceb2a97e3b92508403d2'),
    ( 495, 'FLAVOR', $t$A cauda de Snivy funciona como um painel solar: exposta à luz, é por ela que a espécie faz fotossíntese. Também denuncia seu estado — quando Snivy não está bem, a cauda pende.$t$, 'bc92067e5d138bcc5f9a51f329438c4a'),
    ( 530, 'GENUS',  $t$Pokémon Subterrâneo$t$, '59fe9b288ffedf4fc2d99ec72009da00'),
    ( 530, 'FLAVOR', $t$Chamado de Rei da Broca, Excadrill atravessa o subsolo cavando túneis em velocidades acima de 140 km/h.$t$, 'a18609ef2a68a4f2a23ea56a23102a31'),
    ( 609, 'GENUS',  $t$Pokémon Chamariz$t$, 'bcee38e4d822db107c2e0ba2c8402561'),
    ( 609, 'FLAVOR', $t$Conta-se que as casas iluminadas por Chandelure, no lugar de lâmpadas comuns, conviviam com funerais frequentes.$t$, 'edd85d4421a01b1ca0e05db9584b6ae5'),
    ( 643, 'GENUS',  $t$Pokémon Branco Imenso$t$, 'a6173c2914a60e8c720c96a3446a8c90'),
    ( 643, 'FLAVOR', $t$O mito de Reshiram fala de povos que ignoram a verdade e se deixam consumir pela cobiça. A eles, segundo a narrativa, Reshiram chega para incendiar seus reinos.$t$, '55b64b01ad80d61ed845a6b73295f673'),
    ( 658, 'GENUS',  $t$Pokémon Ninja$t$, '6d149b1e0e49a30f275486f2022fe3d0'),
    ( 658, 'FLAVOR', $t$Greninja surge e desaparece com a discrição de um ninja. Em combate, desorienta os adversários com movimentos rápidos enquanto os atinge com shurikens de água afiada.$t$, '24be99151c0e78fc2aa080d385de3408'),
    ( 681, 'GENUS',  $t$Pokémon Espada Real$t$, 'e77121d067bbaade6af979456efeb39c'),
    ( 681, 'FLAVOR', $t$Os poderes espectrais de Aegislash permitem que ele manipule outros seres. Houve um tempo em que os usou para obrigar pessoas e Pokémon a erguer um reino de acordo com sua vontade.$t$, '36600ea587ef4b06c0d6093ceeccd493'),
    ( 700, 'GENUS',  $t$Pokémon Enlace$t$, 'f38e45e87bcfabc84ad4a723e702b321'),
    ( 700, 'FLAVOR', $t$Dos apêndices em forma de fita, Sylveon emana uma aura tranquilizadora. Quando há uma briga por perto, enlaça os que discutem com essas fitas, e a tensão se dissipa de imediato.$t$, 'b3647b17fb2c06d81ef7508058a024c4'),
    ( 701, 'GENUS',  $t$Pokémon Luta-Livre$t$, '2ea6571cf6de05029970c31bd1894935'),
    ( 701, 'FLAVOR', $t$Antes do golpe final, Hawlucha não abre mão de fazer pose. O hábito tem seu preço: há adversários que aproveitam esse instante para contra-atacar.$t$, 'd029740e1e4c314cd5bda92207e65b44'),
    ( 716, 'GENUS',  $t$Pokémon Vida$t$, '81899657afbb581ced2b3e2fecaa3558'),
    ( 716, 'FLAVOR', $t$Diz-se que Xerneas compartilha a vida eterna — e o sinal seria o brilho de seus chifres, que se acendem em sete cores.$t$, 'a816cfbd6d77e53e5a9ef1ce1aad68a3'),
    ( 722, 'GENUS',  $t$Pokémon Pena-Planta$t$, '6c2590752b6922ff943ac37126a95691'),
    ( 722, 'FLAVOR', $t$As asas delicadas de Rowlet cumprem dois papéis: permitem um voo silencioso e lançam, com destreza, penas afiadas como punhais.$t$, '8290c277cba180981eb618f0e256bc93'),
    ( 745, 'GENUS',  $t$Pokémon Lobo$t$, '551977e57c69e4026c76f4a153e490fc'),
    ( 745, 'FLAVOR', $t$Lycanroc caça por cerco: com movimentos rápidos, vai encurralando a presa aos poucos. Seus dentes buscam os pontos fracos do adversário.$t$, '77395ffa87477f8a48383891ce3d6a65'),
    ( 778, 'GENUS',  $t$Pokémon Disfarce$t$, '0ba5cb3bb921f34f0d0dbade25cf1cf9'),
    ( 778, 'FLAVOR', $t$Sob o trapo velho que lhe serve de disfarce, Mimikyu guarda um mistério. Um relato conta que um cientista espiou por baixo do pano em nome da pesquisa; o mesmo relato registra que ele morreu de uma doença misteriosa.$t$, '7b14a080a87104f91aed12f0cebe752c'),
    ( 791, 'GENUS',  $t$Pokémon Sol$t$, '3c0f18354040cd55a4ac1772b20aa2d4'),
    ( 791, 'FLAVOR', $t$Houve um tempo em que Solgaleo era chamado de “a Fera que Devora o Sol”. Seu corpo é uma fonte abundante de energia em forma de luz.$t$, 'fe7f34a958db027ccc1d851229e174e4'),
    ( 823, 'GENUS',  $t$Pokémon Corvo$t$, 'cd0b8fa23aa708fb8557a7620cee46e7'),
    ( 823, 'FLAVOR', $t$Na região de Galar, Corviknight atua como táxi aéreo — um serviço que a inteligência e a habilidade de voo da espécie tornam bem-sucedido.$t$, 'b2bc1c6ec0826cc13848e877f458f063'),
    ( 873, 'GENUS',  $t$Pokémon Mariposa de Gelo$t$, '7a5495843c178fdaec192de83b3d3322'),
    ( 873, 'FLAVOR', $t$Frosmoth não tolera quem desrespeita campos e montanhas. Nesses casos, voa com as asas geladas e provoca uma nevasca para afastar os responsáveis.$t$, 'b4b26eddc8eb2e25a08a00c12d0457af'),
    ( 887, 'GENUS',  $t$Pokémon Furtivo$t$, 'b756311878629947da37b18c3681a6a5'),
    ( 887, 'FLAVOR', $t$Dragapult carrega Dreepy nos chifres e os lança em velocidade supersônica. Ao que parece, os Dreepy aguardam esse momento com entusiasmo.$t$, '4ba35576531137466f3d572cb98add7f'),
    ( 888, 'GENUS',  $t$Pokémon Guerreiro$t$, '97d9b0adce09d3abc724fe0a72147a9e'),
    ( 888, 'FLAVOR', $t$Zacian passou muitos anos adormecido. Sua ligação com Zamazenta divide opiniões: há quem diga que é a irmã mais velha dele, e há quem os veja como rivais.$t$, '4b83ce45be82b18cca1cbb39bab94bf4'),
    ( 908, 'GENUS',  $t$Pokémon Ilusionista$t$, '1d6aecc4e311a4a8180f94f13d83852c'),
    ( 908, 'FLAVOR', $t$A arte de Meowscarada é a distração. Enquanto desvia a atenção dos adversários, prende neles bombas de flores carregadas de pólen e as detona antes que percebam o que está acontecendo.$t$, '430a452996d9d3040ba7abe46ae3ee46'),
    ( 959, 'GENUS',  $t$Pokémon Martelo$t$, '0565b9face192bd0f06e1f0ca4f1401f'),
    ( 959, 'FLAVOR', $t$O martelo de Tinkaton pesa cerca de 100 kg e, mesmo assim, é brandido com facilidade. É com ele que Tinkaton se apodera do que bem entende e carrega o saque para casa.$t$, 'b9c6ed4e83f07733c66ec6d17c86d883'),
    ( 998, 'GENUS',  $t$Pokémon Dragão de Gelo$t$, '0d5d2691d133d5ce1ba14eb406a0b512'),
    ( 998, 'FLAVOR', $t$Baxcalibur se lança ao combate de cabeça para baixo, expelindo ar gélido pela boca. Para encerrar a luta, recorre à lâmina dorsal.$t$, '726023d457038935fcc6a3da363a3697'),
    (1000, 'GENUS',  $t$Pokémon Ser de Moedas$t$, 'fc79b1400553132e6655197e23376a92'),
    (1000, 'FLAVOR', $t$Moedas empilhadas formam o corpo resistente de Gholdengo — e também são sua munição: em combate, ele as dispara uma após a outra, em rápida sequência, até sobrepujar os adversários.$t$, 'cda80f8290b76c9500f9437e7e1a3406');

  create temporary table p3e_lote_01_published_md5 (
    national_dex_number integer not null,
    text_kind text not null,
    content_md5 text not null,
    primary key (national_dex_number, text_kind)
  ) on commit drop;

  insert into p3e_lote_01_published_md5 (national_dex_number, text_kind, content_md5) values
    (   1, 'FLAVOR', '6fa190f58d6d7c9d181dbdf9fa8b029f'),
    (   1, 'GENUS', 'd106d48db7cd05b7318ef213e29ea191'),
    (  25, 'FLAVOR', 'ff535631f50d1f62ad41e6097fc4eb6e'),
    (  25, 'GENUS', 'aeebd93bae1f0ffe1fd5d851a5c69f7d'),
    ( 150, 'FLAVOR', '77a4292d419ffa4e7675a9f638af9c72'),
    ( 150, 'GENUS', '59c850213022ef77e8c3fee5abaab90e'),
    ( 201, 'FLAVOR', '1e5fae200a90906ea79405ad638901ab'),
    ( 201, 'GENUS', '602a3977a95fcc0d5599e3685ece02a1'),
    ( 493, 'FLAVOR', '2306a6e97fac096a4146f0eeddb03362'),
    ( 493, 'GENUS', '4b5972befe205497fcc1223c6e19c713'),
    ( 649, 'FLAVOR', '3c39ddbe6f6ca53ef61f4b384c440d81'),
    ( 649, 'GENUS', '15eb9c3d28c0ed3243f9f9d37249b334'),
    ( 721, 'FLAVOR', '3aec691ce234c1c25e55b0421cef99e3'),
    ( 721, 'GENUS', '3485c9988307a1efcba84ac1314c2a0b'),
    ( 905, 'FLAVOR', '2961132bc5248df54ff10d3235cc3cb0'),
    ( 905, 'GENUS', '903cdcab9a504b1c836323397c451f24'),
    ( 906, 'FLAVOR', 'c1bab719d860c5afb06cc003b54ba08f'),
    ( 906, 'GENUS', '3d4ed43e6b1573197d5a106253b15a3c'),
    (1025, 'FLAVOR', '4cf656088f060510dd78da734f1db26a'),
    (1025, 'GENUS', 'c790cbbfb620b3210bae0eb51ec6d1fd');

  -- 1. Payload
  if (select count(*) from p3e_lote_01_text) <> 100
     or (select count(distinct national_dex_number) from p3e_lote_01_text) <> 50
     or exists (select 1 from p3e_lote_01_text where not (national_dex_number = any (v_lot))) then
    raise exception '6137 FAIL: payload deve ter 100 textos das 50 espécies do lote';
  end if;
  if exists (select 1 from p3e_lote_01_text where national_dex_number = any (v_published)) then
    raise exception '6137 FAIL: payload contém espécie de lote já publicado';
  end if;
  select count(*) into v_n from p3e_lote_01_text where md5(content) <> content_md5;
  if v_n <> 0 then
    raise exception '6137 FAIL: % textos com md5 diferente do aprovado', v_n;
  end if;
  if exists (select 1 from p3e_lote_01_text where btrim(content) = '' or length(content) > 2000) then
    raise exception '6137 FAIL: conteúdo vazio ou acima de 2000 caracteres';
  end if;

  -- 2. Pré-condições
  select count(*) into v_n
    from (select distinct national_dex_number from p3e_lote_01_text) t
    join public.pokemon_species s on s.national_dex_number = t.national_dex_number and s.is_active
    join public.pokemon_species_profile p on p.pokemon_species_id = s.id and p.status = 'IMPORTED'
   where exists (select 1 from public.pokemon_species_text o
                  where o.pokemon_species_id = s.id and o.origin = 'SOURCE' and o.language_code = 'en' and o.text_kind = 'GENUS')
     and exists (select 1 from public.pokemon_species_text o
                  where o.pokemon_species_id = s.id and o.origin = 'SOURCE' and o.language_code = 'en' and o.text_kind = 'FLAVOR');
  if v_n <> 50 then
    raise exception '6137 FAIL: % de 50 espécies elegíveis (ativa, perfil IMPORTED, textos oficiais en)', v_n;
  end if;

  select count(*), md5(string_agg(st.pokemon_species_id::text || '|' || st.text_kind || '|' || st.language_code || '|' || coalesce(st.source_version, '') || '|' || st.content || '|' || st.rights_status || '|' || coalesce(st.asset_source_id::text, '') || '|' || coalesce((st.retrieved_at at time zone 'UTC')::text, ''), E'\n' order by st.pokemon_species_id, st.text_kind, st.language_code))
    into v_n, v_source_md5
    from public.pokemon_species_text st where st.origin = 'SOURCE';
  if v_n <> v_source_baseline_count or v_source_md5 is distinct from v_source_baseline_md5 then
    raise exception '6137 FAIL: SOURCE fora da linha de base antes da escrita (% linhas, hash %)', v_n, v_source_md5;
  end if;

  select count(*) into v_n
    from public.pokemon_species_text st
    join public.pokemon_species s on s.id = st.pokemon_species_id
   where st.origin = 'MMKYU_EDITORIAL' and not (s.national_dex_number = any (v_lot));
  if v_n <> 20 then
    raise exception '6137 FAIL: % linhas editoriais fora do lote, esperado 20 (publicados)', v_n;
  end if;

  select count(*) into v_n
    from p3e_lote_01_published_md5 e
    join public.pokemon_species s on s.national_dex_number = e.national_dex_number
    left join public.pokemon_species_text st
      on st.pokemon_species_id = s.id and st.text_kind = e.text_kind
     and st.origin = 'MMKYU_EDITORIAL' and st.language_code = 'pt-BR'
   where st.id is null or md5(st.content) <> e.content_md5;
  if v_n <> 0 then
    raise exception '6137 FAIL: % registros publicados divergentes dos md5 versionados', v_n;
  end if;

  select md5(coalesce(string_agg(st.id::text || '|' || st.content || '|' || st.updated_at::text, E'\n' order by st.id), ''))
    into v_published_before
    from public.pokemon_species_text st
    join public.pokemon_species s on s.id = st.pokemon_species_id
   where st.origin = 'MMKYU_EDITORIAL' and not (s.national_dex_number = any (v_lot));

  -- 3. Escrita
  insert into public.pokemon_species_text as st (
    pokemon_species_id, text_kind, language_code, origin,
    asset_source_id, source_version, content, rights_status, retrieved_at
  )
  select s.id, t.text_kind, 'pt-BR', 'MMKYU_EDITORIAL',
         null, null, t.content, 'MMKYU_EDITORIAL', null
    from p3e_lote_01_text t
    join public.pokemon_species s on s.national_dex_number = t.national_dex_number and s.is_active
  on conflict on constraint uq_pokemon_species_text do update
     set content = excluded.content,
         rights_status = 'MMKYU_EDITORIAL'
   where st.origin = 'MMKYU_EDITORIAL'
     and (st.content is distinct from excluded.content or st.rights_status is distinct from 'MMKYU_EDITORIAL');
  get diagnostics v_written = row_count;

  -- 4. Pós-condições
  select count(*) into v_n
    from p3e_lote_01_text t
    join public.pokemon_species s on s.national_dex_number = t.national_dex_number
    left join public.pokemon_species_text st
      on st.pokemon_species_id = s.id and st.text_kind = t.text_kind
     and st.language_code = 'pt-BR' and st.origin = 'MMKYU_EDITORIAL'
   where st.id is null
      or st.content is distinct from t.content
      or md5(st.content) <> t.content_md5
      or st.rights_status <> 'MMKYU_EDITORIAL'
      or st.asset_source_id is not null or st.source_version is not null or st.retrieved_at is not null;
  if v_n <> 0 then
    raise exception '6137 FAIL: % textos do lote divergentes após a escrita', v_n;
  end if;

  select count(*) into v_n from public.pokemon_species_text where origin = 'MMKYU_EDITORIAL';
  if v_n <> 120 then
    raise exception '6137 FAIL: % linhas editoriais no total, esperado 120', v_n;
  end if;
  select count(distinct pokemon_species_id) into v_n from public.pokemon_species_text where origin = 'MMKYU_EDITORIAL';
  if v_n <> 60 then
    raise exception '6137 FAIL: % espécies com editorial, esperado 60', v_n;
  end if;

  select count(*), md5(string_agg(st.pokemon_species_id::text || '|' || st.text_kind || '|' || st.language_code || '|' || coalesce(st.source_version, '') || '|' || st.content || '|' || st.rights_status || '|' || coalesce(st.asset_source_id::text, '') || '|' || coalesce((st.retrieved_at at time zone 'UTC')::text, ''), E'\n' order by st.pokemon_species_id, st.text_kind, st.language_code))
    into v_n, v_source_md5
    from public.pokemon_species_text st where st.origin = 'SOURCE';
  if v_n <> v_source_baseline_count or v_source_md5 is distinct from v_source_baseline_md5 then
    raise exception '6137 FAIL: textos oficiais (SOURCE) alterados';
  end if;

  select md5(coalesce(string_agg(st.id::text || '|' || st.content || '|' || st.updated_at::text, E'\n' order by st.id), ''))
    into v_published_after
    from public.pokemon_species_text st
    join public.pokemon_species s on s.id = st.pokemon_species_id
   where st.origin = 'MMKYU_EDITORIAL' and not (s.national_dex_number = any (v_lot));
  if v_published_after is distinct from v_published_before then
    raise exception '6137 FAIL: registros editoriais já publicados foram alterados';
  end if;

  raise notice '6137 OK: % linhas gravadas/atualizadas; lote = 100 linhas / 50 espécies; total editorial = 120 / 60; SOURCE preservado (2050)', v_written;
end
$pub$;

commit;

-- Resultado esperado
-- Primeira execução: "6137 OK: 100 linhas gravadas/atualizadas; ...". Reexecução: "6137 OK: 0 linhas ...".
-- Qualquer FAIL desfaz a transação inteira (nada gravado).
--
-- Como validar: executar 6848_validate_pokedex_editorial_ptbr_lote_01.sql → "6848 PASS".
--
-- Rollback (somente as 100 linhas do lote; publicados anteriores e SOURCE intocados):
--   delete from public.pokemon_species_text st
--    using public.pokemon_species s
--    where s.id = st.pokemon_species_id and st.origin = 'MMKYU_EDITORIAL'
--      and st.language_code = 'pt-BR'
--      and s.national_dex_number in (4, 6, 7, 39, 52, 54, 94, 133, 143, 151, 155, 175, 197, 212, 248, 249, 257, 282, 359, 382, 384, 385, 393, 405, 445, 448, 483, 491, 494, 495, 530, 609, 643, 658, 681, 700, 701, 716, 722, 745, 778, 791, 823, 873, 887, 888, 908, 959, 998, 1000);
