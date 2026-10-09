import json
CC="private, no-cache, no-store, max-age=0, must-revalidate"
VARY="rsc, next-router-state-tree, next-router-prefetch, next-router-segment-prefetch, Accept-Encoding"
CID="726585cea36861942981ce642a4c588c89d3cb2573a5784a433972db3d028359"
LP="93268591669112c4c97d0de270405a762ab111cd202b40d71cd288812174ef86"
BID={"baseline":"JQtcMuYg6MbbYaCanNpMw","f21":"CoxlLMPXijHlnKCyBIYoL"}
DEC={("baseline","A"):710892,("baseline","B"):402779,("f21","A"):830842,("f21","B"):508439}
# (env, sc, round, compressed, decompSha, durationMs) — transcrito das saídas do navegador
T=[
("baseline","A",0,83752,"04f3866749cdd36bda6a29998bcd305bf1850f00a47dcc1ab7a71ab13ae51bc5",2366),
("baseline","B",0,57559,"1ec06dda92c51fdcbc55ebe3ce8267151377236b87f7547b28b04963b8615828",757),
("baseline","A",1,83744,"2ed5a885efff29ca778ebfdc710fce45fc03e38a2cad66591fe8ae1094968c9d",705),
("baseline","B",1,57563,"df8646b8f0446805bdc426c7128be726ecf7c133481ef2d66cf399fbfab49764",642),
("baseline","A",2,83750,"135515b128bf2f4798c5799958166c2d19b5ab58c6e5e7f2c03483e274da4947",765),
("baseline","B",2,57555,"015f8165387748585dc9076e5e1641746583e99dce76a5e46f6055ab287940a5",635),
("baseline","A",3,83735,"b5209ccc4eb9ac980cb09ce2fc1668306dc9d47808834c5482da274265412e72",818),
("baseline","B",3,57562,"ae576c39c0a9f5e5764df8930d6f4c2ef1bbb76bdc761e928a0cbdbe4501de54",686),
("baseline","A",4,83746,"5f246c6438dbdb00ab77746822f534a2e191d34ff3bf6a7d7825e5bda5afadac",743),
("baseline","B",4,57558,"aeb5cc1517bee9cdfa18d5253a1e3dfa359cf1555f8acca1e746f4c5954dc0dc",646),
("baseline","A",5,83743,"366c6a3aeccb980a2b7635309be46a19b739bd29cbd21aa865c3955abc407267",681),
("baseline","B",5,57561,"efe6d14502c1267c7f45fa0ba4e0113a9036d2020bfe44234b544d7b95900427",635),
("f21","A",0,88042,"a8b14978bc6d2ae1f51b45d92a6887842ae73fccd198bf2a24978264759cc0d7",1081),
("f21","B",0,61729,"9904da3e9110846f78e7879b09dfa53fbd9fe3d9cce35c8f558990170d306769",766),
("f21","A",1,88047,"058f39c55ec0cfccce13becdb3d4c549f805310472ea7c6f83f31cf56276277b",1513),
("f21","B",1,61731,"125ece8b0a35c2ea76a76e8e4e8a7f048b18ff690d0f546c43632df721e1d078",927),
("f21","A",2,88049,"66447c15af6e67a5ed1c511a4e5b776698e22cb6070428f5e10904fa2942b0c2",1062),
("f21","B",2,61731,"006478694fdd247d2d939480d99c497832538ea20185142904bbe3783ccac97c",781),
("f21","A",3,88053,"a3548708d5079fde741447b98cb4344a83d4d64612b35adf599aa65fbb461fa1",830),
("f21","B",3,61733,"ff973d32891f718de4e07c040cf4e49e5b5ba93ef0fa82cc751e3f2869227f30",936),
("f21","A",4,88051,"682b95bcf605c4490628c24f4b9d2b8dca6865d94559c7c491ec739ea1c82fb2",1154),
("f21","B",4,61730,"58faa26af00dd5452cdfab966c5563e4b0b0f778763ee9c9866d692328627d7f",921),
("f21","A",5,88045,"4e8351b5046d999ba6c9763d0baaed60b7b24effda93c627f49e22df95a5186b",719),
("f21","B",5,61729,"a6af7ce7a577bb79b5df388aa7bc52c6ac5409846f27a74a6c1b815e01c85dfe",671),
]
out=[]
for env,sc,r,c,sha,ms in T:
    vv={"absent":295,"ok":0,"none":0,"error":0,"invalid":0,"sumRawCount":0,"okLegacyIdMismatch":0,"noneLegacyNonEmpty":0} if env=="baseline" else {"absent":0,"ok":295,"none":0,"error":0,"invalid":0,"sumRawCount":630,"okLegacyIdMismatch":0,"noneLegacyNonEmpty":0}
    out.append({"env":env,"scenario":sc,"round":r,"measured":r>=1,"status":200,
      "contentType":"text/html" if sc=="A" else "text/x-component","contentEncoding":"gzip","cacheControl":CC,"vary":VARY,
      "setCookieNames":[],"sessionRotated":False,"rawBytes":c,"compressedBytes":c,"compressedValid":True,
      "decompressedBytes":DEC[(env,sc)],"decompressedSha256":sha,"durationMs":ms,"buildId":BID[env],
      "gallery":{"selectedCode":"ME2.5","cartas":295,"legacyVariants":630,"cardIdsSha256":CID,"legacyPairsSha256":LP,"cardsCatalogadosDoSet":295,"variantView":vv},
      "galleryElements":1,
      "tagCounts":{"model":21,"I":19,"H":3} if sc=="A" else {"model":9,"I":12},
      "transport":{"bootstrap":1,"data":17,"formState":0,"binary":0,"unknown":0} if sc=="A" else None,
      "issues":[]})
json.dump(out,open("samples.json","w"),indent=1)
meta={"method":"P9-B (navegador embutido, fetch same-origin, Resource Timing)",
 "envs":{"baseline":{"origin":"http://127.0.0.1:3101","commit":"94b64ba3796e2f6d73db20ee7d0d77d8932d8996","buildIdFlight":BID["baseline"]},
         "f21":{"origin":"http://127.0.0.1:3102","commit":"94b64ba + working tree F2.1","buildIdFlight":BID["f21"]}},
 "targetSet":"ME2.5","setSelectionMethod":"S1","expected":{"cartas":295,"variants":630},
 "order":"r0..r5; rodadas pares baseline primeiro, ímpares f21 primeiro",
 "scenarioB":{"computed":True,"crossEnvEqual":True,
   "url":"/catalogo/cartas?set=ME2.5&_rsc=NNfcYhoFWiYSdCZj",
   "headers":{"rsc":"1","next-url":None,"next-router-prefetch":None,"next-router-state-tree":"[\"\",{\"children\":[\"catalogo\",{\"children\":[\"cartas\",{\"children\":[\"__PAGE__\",{},null,\"refetch\"]},null,null]},null,null]},null,null] (URI-encoded)"},
   "browserCheck":{"validated":True,"reasons":[],"how":"headers observados no fetch do roteador ao trocar o seletor ME2→ME2.5, independentemente em cada porta; valores idênticos"}},
 "injectedCodeSha256":"7df16e9471c562bdc6bb41583fc282f443bda7234d67a1d0d853d0226975512f",
 "noCookiesRead":True}
json.dump(meta,open("capture-meta.json","w"),indent=1,ensure_ascii=False)
