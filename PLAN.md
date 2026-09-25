# KOReader ↔ Readwise Reader — Plano canônico da V1

> **Status:** planejamento aprovado para implementação  
> **Última revisão:** 2026-09-22  
> **Repositório:** `olalaurao/reader`  
> **Fonte de verdade do escopo/V1:** este arquivo.  
> **Spec canônica de implementação:** `IMPLEMENTATION_SPEC.md`.  
> **Estado/handoff entre sessões:** `STATUS.md`.  
> Mudanças de produto atualizam `PLAN.md`; mudanças técnicas atualizam a spec; toda sessão de implementação atualiza `STATUS.md`.

## 1. Objetivo

Criar um plugin para **KOReader** que transforme o Kindle em um dispositivo de leitura para a biblioteca do **Readwise Reader**.

Fluxo principal:

```text
Salvar/organizar conteúdo no Readwise Reader
        ↓
Sincronizar no Kindle
        ↓
Baixar conteúdo e ler offline no KOReader
        ↓
Criar highlights e notas no Kindle
        ↓
Sincronizar highlights/notas para o documento original no Reader
        ↓
Exportar pelo Readwise para Obsidian
        ↓
Preservar Markdown e wikilinks como [[Foucault]]
```

A prioridade é **Reader → Kindle para leitura** e **Kindle → Reader para anotações**.  
Importar highlights já existentes do Reader para posições exatas no KOReader **não é requisito da V1**.

---

## 2. Hardware e ambiente-alvo inicial

Desenvolver e validar primeiro para o aparelho real:

- Kindle Paperwhite 3 / Paperwhite 7ª geração (PW3)
- prefixo do serial: `G090KB`
- firmware Kindle: `5.16.2.1.1 (4097470002)`
- jailbreak funcional
- KUAL funcional
- KOReader histórico dos Gates 0–4: `2025.04`
- KOReader baseline física canônica da V1 após Gate 4A-1: oficial `2026.07.1`, pacote `kindlepw2`
- Bookshelf coexistência validada no Gate 4A-2: `v5.1.4`

### Regra de compatibilidade

A V1 continua presa ao mesmo PW3 real. Até o Gate 4, `2025.04` é a baseline conhecida. **Depois que o Gate 4 passar**, faremos uma migração controlada para `2026.07.1` antes de implementar imagens, formatos raw e sidecars/anotações.

Gate 4A-1 e Gate 4A-2 passaram: KOReader `2026.07.1` é o alvo físico canônico e Bookshelf `v5.1.4` é uma coexistência validada para a V1. Phase G pode avançar sobre essa baseline. Gate 5 também passou fisicamente; Phase G está concluída e formatos raw de Phase H podem avançar. Gate 6 também passou fisicamente; Phase H está concluída e o adapter de sidecars/anotações da Phase I pode avançar. Gate 7 também passou fisicamente; Phase I está concluída e o spike de interoperabilidade de annotations da Phase J pode avançar.

Com firmware 5.16.2.1.1, o target planejado é `kindlepw2`; `kindlehf` exige firmware >= 5.16.3. Não atualizar firmware/jailbreak para esta migração.

Runbook: `docs/KOREADER_UPGRADE.md`.

### Wi‑Fi

O plugin **não deve controlar o Wi‑Fi do Kindle** na V1.

Ele pode:
- detectar conectividade;
- avisar quando não houver internet;
- executar normalmente offline para leitura/anotações locais.

Quem liga/desliga o Wi‑Fi é o usuário pelo sistema do Kindle.

---

## 3. Princípios de projeto

1. **Offline-first.** Tudo já baixado deve continuar legível e anotável sem internet.
2. **Sem perda de dados.** Nunca apagar conteúdo ou highlights remotamente por padrão.
3. **Idempotência.** Rodar Sync duas vezes não pode criar duplicatas.
4. **IDs remotos são a identidade.** Nome/título do arquivo nunca será a identidade primária.
5. **Incremental.** Depois do primeiro sync, processar somente alterações.
6. **Falhas parciais são recuperáveis.** Um documento com erro não deve quebrar o sync inteiro.
7. **Escritas atômicas.** Nunca substituir arquivo/estado válido até o novo conteúdo estar completo.
8. **Compatibilidade conservadora.** Não exigir versão mais nova do KOReader sem necessidade comprovada.
9. **Markdown literal.** Notas devem preservar texto, acentos, emojis, tags e `[[wikilinks]]`.
10. **API documentada primeiro.** Toda dependência de comportamento não garantido pela API vira um gate experimental antes de entrar na arquitetura definitiva.

---

## 4. Escopo da V1

### Deve funcionar

- autenticação com token Readwise;
- testar conexão;
- listar biblioteca do Reader;
- paginação completa;
- sync incremental;
- baixar artigos;
- baixar emails/newsletters;
- baixar RSS;
- baixar PDFs originais quando disponíveis;
- baixar EPUBs originais quando disponíveis;
- fallback para conteúdo processado quando o original não estiver disponível;
- abrir arquivos normalmente no KOReader;
- leitura offline;
- preservar progresso e sidecars do KOReader;
- organizar itens de forma navegável;
- criar highlight no KOReader;
- criar nota no highlight;
- sincronizar highlight/nota para Readwise/Reader;
- preservar `[[wikilinks]]`;
- impedir duplicatas;
- fila de uploads pendentes;
- retry após falha;
- editar nota local e sincronizar alteração quando suportado/validado;
- marcar documento como concluído e arquivar no Reader;
- logs úteis;
- resumo do resultado do sync;
- migração segura do estado local entre versões do plugin.

### Fora da V1

- importar todos os highlights já existentes do Reader para posições exatas no KOReader;
- sincronizar posição de leitura Reader ↔ KOReader;
- reproduzir a UI do Reader no Kindle;
- descoberta de conteúdo/feed pelo Kindle;
- edição avançada de toda a taxonomia do Reader;
- background sync automático;
- sincronização perfeita de conflitos simultâneos em ambas as pontas;
- suporte garantido a todo Kindle/KOReader antes de validar o PW3;
- dependência de heurísticas destrutivas.

---

## 5. Base existente e estratégia

Não reescrever tudo do zero.

Usar o plugin comunitário existente do KOReader/Readwise Reader como:
- referência de integração com KOReader;
- referência de menus;
- referência de Collections;
- referência de geração de HTML;
- referência de archive/finished;
- referência de leitura dos highlights locais.

Mas a nova implementação deve modernizar:
- separação em módulos;
- API client;
- persistência de estado;
- deduplicação;
- download de formatos originais;
- fila offline;
- vínculo entre documento local e Reader ID;
- vínculo entre anotação local e ID remoto;
- testes;
- logs;
- segurança do token.

### Antes de copiar código

Registrar licença e origem do código reaproveitado no repositório.

Não copiar trechos sem preservar os avisos/licença exigidos pelo projeto de origem.

---

## 6. Estrutura prevista

```text
readwisereader.koplugin/
│
├── _meta.lua
├── main.lua
│
├── api/
│   ├── client.lua
│   ├── reader.lua
│   └── readwise.lua
│
├── sync/
│   ├── coordinator.lua
│   ├── documents.lua
│   ├── annotations.lua
│   ├── archive.lua
│   └── queue.lua
│
├── content/
│   ├── html.lua
│   ├── raw_source.lua
│   ├── text_match.lua
│   └── filenames.lua
│
├── storage/
│   ├── state.lua
│   ├── migrations.lua
│   └── schema.lua
│
├── ui/
│   ├── menu.lua
│   ├── settings.lua
│   └── status.lua
│
└── tests/
    └── ...
```

A estrutura pode mudar se APIs internas do KOReader tornarem outra divisão mais idiomática.

---

## 7. Segurança e privacidade

### Token

O token Readwise:
- nunca vai para Git;
- nunca aparece em logs;
- nunca aparece em crash reports de propósito;
- deve ser mascarado na UI;
- deve ficar somente no armazenamento/configuração local do KOReader;
- deve poder ser removido pelo usuário.

Adicionar ao `.gitignore` qualquer fixture/configuração local que possa conter credenciais.

### Logs

Redigir:
- `Authorization`;
- tokens;
- URLs temporárias assinadas quando contiverem credenciais;
- conteúdo privado desnecessário.

Para debugging de text matching, registrar hash/ID e motivo da falha em vez de despejar documentos inteiros no log por padrão.

---

## 8. Modelo de dados local

Usar uma versão explícita de schema:

```text
schema_version
last_successful_document_sync
last_successful_annotation_sync
```

### Documento

Guardar pelo menos:

```text
reader_document_id
local_path
content_type
download_strategy
source_updated_at
local_content_hash
location
category
title
author
raw_source_available
last_synced_at
sync_status
```

### Anotação

Guardar pelo menos:

```text
local_annotation_id
reader_document_id
readwise_highlight_id / remote_annotation_id
text_hash
note_hash
last_synced_text
last_synced_note
last_synced_at
sync_status
created_by_plugin
```

### Invariantes

- `reader_document_id` é a identidade do documento.
- Um rename do título não cria novo documento.
- Um segundo sync não cria novo highlight se a anotação já tiver vínculo remoto.
- Um arquivo local nunca é considerado remoto apenas pelo nome.
- IDs devem sobreviver a reinicializações.

---

## 9. Migrações

Toda mudança incompatível no estado deve incrementar `schema_version`.

Fluxo:

```text
carrega estado
↓
detecta versão antiga
↓
faz backup
↓
migra para próxima versão
↓
valida
↓
só então substitui estado anterior
```

Se a migração falhar:
- manter backup;
- não continuar o sync;
- informar erro recuperável.

---

## 10. Fase 0 — Backup e diagnóstico

Antes de instalar builds experimentais no aparelho:

fazer cópia de:
- `koreader/settings/`
- `koreader/plugins/`
- `koreader/crash.log` quando relevante.

Confirmar:
- plugin externo mínimo carrega;
- path real do KOReader;
- filesystem gravável;
- HTTPS;
- DNS;
- certificados;
- relógio/data razoáveis;
- espaço livre.

### Gate 0

Um plugin "hello world" aparece no menu e pode ser removido sem afetar o KOReader.

---

## 11. Fase 1 — Autenticação

Criar:

```text
Readwise Reader
└── Settings
    ├── Access token
    └── Test connection
```

Teste com endpoint oficial de autenticação.

Resultados:
- conectado;
- token inválido;
- sem internet;
- timeout;
- erro TLS;
- rate limit;
- erro inesperado.

### Gate 1

No PW3 real, `Test connection` funciona com token válido sem expor a credencial.

---

## 12. Fase 2 — Listar documentos sem baixar

Implementar client Reader v3:
- headers;
- timeout;
- paginação por cursor;
- parsing;
- rate limiting;
- `Retry-After`;
- backoff;
- cancelamento seguro.

Primeiro apenas mostrar contagens:
- total;
- por location;
- por category.

### Gate 2

Conseguir percorrer a biblioteca completa sem:
- loop de cursor;
- duplicatas;
- travamento;
- exceder rate limit.

---

## 13. Fase 3 — Primeiro artigo

Baixar um único artigo usando conteúdo processado.

Criar arquivo local válido e abrir no KOReader.

Validar:
- Unicode;
- acentos;
- aspas;
- links;
- imagens;
- fonte;
- margens;
- reflow;
- busca;
- dicionário;
- highlight;
- nota;
- fechamento/reabertura;
- sidecar/progresso.

### Gate 3

O artigo se comporta como documento local normal do KOReader.

---

## 14. Fase 4 — Downloads seguros

Downloads devem seguir:

```text
arquivo.tmp
↓
download completo
↓
validação mínima
↓
fsync/close
↓
rename atômico
↓
arquivo final
```

Em erro:
- apagar temp inválido;
- preservar versão anterior;
- manter item como pendente.

### Re-download

Só substituir conteúdo local quando:
- a fonte remota mudou;
- a nova cópia terminou corretamente.

Nunca apagar sidecar/progresso do KOReader durante atualização de conteúdo sem regra explícita.

---

## 15. Fase 5 — Formatos

Estratégia preferida:

| Reader | Local |
|---|---|
| article | HTML limpo |
| email/newsletter | HTML |
| RSS | HTML |
| tweet/post textual | HTML |
| video | conteúdo textual/transcrição quando fornecido |
| PDF | PDF original quando permitido |
| EPUB | EPUB original quando permitido |

Quando `raw_source_url` existir:
- tratá-la como URL efêmera;
- baixar imediatamente;
- nunca persistir a URL como fonte permanente;
- não registrar URL assinada no log.

Quando não existir:
- usar fallback processado, se legível e suportado.

### Gate 5

Pelo menos um exemplo real de cada tipo suportado abre no aparelho.

---

## 16. Filenames e paths

Nunca usar título bruto como path sem sanitização.

Regras:
- remover/separar caracteres inválidos;
- limitar comprimento;
- evitar nomes reservados;
- evitar colisão;
- manter extensão correta;
- incluir ID curto ou outro identificador estável no filename quando necessário;
- não permitir `../` ou path traversal.

Exemplo conceitual:

```text
Foucault - Discipline and Punish--01ABC123.html
```

Título pode mudar; vínculo continua pelo ID.

---

## 17. Espaço de armazenamento

Kindles antigos têm armazenamento limitado.

Antes de download grande:
- verificar espaço livre quando possível;
- conhecer tamanho quando servidor informar;
- manter margem de segurança;
- falhar antes de deixar filesystem cheio.

Configurações futuras/da V1 se simples:
- limite máximo de download;
- incluir/excluir PDFs;
- incluir/excluir EPUBs;
- limpar arquivos locais arquivados manualmente.

Nunca excluir automaticamente por falta de espaço sem confirmação.

---

## 18. Sync incremental de documentos

Primeiro sync:
- percorrer biblioteca;
- persistir IDs;
- baixar conforme filtros.

Próximos syncs:
- usar `updatedAfter`/cursor conforme API documentada;
- comparar `updated_at` e/ou hash;
- processar somente mudanças.

O timestamp de watermark só avança depois de completar com sucesso o escopo correspondente.

Evitar bug clássico:

```text
salvar last_sync antes de terminar
→ crash
→ mudanças entre os dois momentos nunca são vistas
```

Usar janela de sobreposição pequena ou outro mecanismo robusto se necessário para timestamps limítrofes.

---

## 19. Filtros da biblioteca

UI inicial:

```text
Locations:
[x] Inbox
[x] Later
[x] Shortlist (quando aplicável)
[ ] Archive

Types:
[x] Articles
[x] EPUB
[x] PDF
[x] Email
[x] RSS
[ ] Outros
```

A configuração precisa respeitar que contas/configurações do Reader podem usar estruturas diferentes de triage/shortlist.

Não hardcodar a existência de Shortlist para todos.

Depois, se útil:
- sincronizar somente tag `koreader`;
- tamanho máximo;
- período;
- include/exclude tags.

---

## 20. Organização no KOReader

Preferir mecanismo nativo e pouco invasivo:
- pasta própria;
- Collections quando estáveis;
- metadados sem alterar arquivos desnecessariamente.

### Reader como fonte de verdade da organização remota

Para documentos gerenciados pelo plugin, a organização feita no **Readwise Reader** deve ser projetada no KOReader no próximo sync, sem trocar a identidade/local path do documento.

Mapeamento canônico de `location`:

```text
Reader new       -> KOReader Collection "Readwise: Inbox"
Reader later     -> KOReader Collection "Readwise: Later"
Reader shortlist -> KOReader Collection "Readwise: Shortlist"
Reader feed      -> KOReader Collection "Readwise: Feed"
Reader archive   -> KOReader Collection "Readwise: Archive"
```

Regras:
- ao mover um item no Reader, o próximo sync remove o arquivo apenas das outras **Collections gerenciadas pelo plugin** e o adiciona à Collection correspondente à nova location;
- Collections criadas pelo usuário e não gerenciadas pelo plugin nunca devem ser removidas;
- mover/renomear no Reader não pode criar um segundo arquivo local;
- Reader ID continua sendo a identidade, independentemente de título/location;
- título, autor, resumo/site e demais metadados Reader projetados devem atualizar os custom metadata do mesmo arquivo local.

### Tags Reader -> metadata / Bookshelf

Não criar centenas de Collections automaticamente a partir de tags.

As tags do Reader devem ser projetadas para um campo de metadata compatível com KOReader/Bookshelf, preferencialmente `keywords`, preservando os valores úteis e sem transformar cada tag em Collection.

Objetivo no Bookshelf após Gate 4A:
- location visível/filtrável através das Collections `Readwise: ...`;
- tags Reader visíveis/filtráveis através de metadata/keywords (Bookshelf pode tratá-las como genres/tags);
- título/autor/progresso continuam vindo do mesmo documento local;
- uma mudança posterior de location ou tags no Reader aparece no KOReader/Bookshelf depois do próximo sync.

Isso é uma projeção Reader -> KOReader para organização. Não implica editar tags/locations no KOReader e escrevê-las de volta no Reader na V1.

---

## 21. Fase crítica — validar modelo de highlight remoto

Antes de desenhar update/delete definitivo, executar uma prova controlada com um documento descartável.

A Reader API v3 permite criar um highlight passando:
- `parent_id`;
- `content` copiado caractere por caractere do conteúdo do documento;
- `notes`.

Precisamos validar empiricamente:

1. criar highlight via Reader v3;
2. confirmar que aparece dentro do documento original no Reader;
3. descobrir/confirmar o identificador retornado;
4. verificar como esse highlight aparece na API Readwise v2/export;
5. verificar se o mesmo highlight pode ser atualizado pela API v2;
6. verificar se pode ser deletado pela API v2;
7. verificar comportamento de tags/notas;
8. documentar o contrato observado.

### Gate de arquitetura

Só depois dessa prova decidir o caminho definitivo para:
- update;
- delete;
- reconciliação;
- remote ID persistido.

Se v2/v3 não interoperarem como esperamos, adaptar o desenho sem sacrificar criação e notas da V1.

---

## 22. Text matching

A API Reader exige que o texto enviado como highlight corresponda ao conteúdo do documento.

Pipeline:

1. exact match;
2. normalização de whitespace;
3. normalização Unicode;
4. equivalência conservadora de aspas/hífens;
5. localizar candidato único no conteúdo remoto;
6. recuperar o **substring original exato**;
7. enviar esse substring.

### Não fazer

- fuzzy match agressivo;
- escolher silenciosamente entre múltiplos candidatos;
- enviar texto modificado inventando posição.

Se houver ambiguidade:
- marcar como `unmatched`;
- manter highlight local;
- não perder nota;
- oferecer fallback/diagnóstico.

---

## 23. Highlights KOReader → Reader

Fluxo esperado:

```text
highlight local novo
↓
document ID conhecido?
├── não → não sincronizar; informar
└── sim
     ↓
text match seguro
     ↓
POST remoto
     ↓
resposta válida
     ↓
persistir remote ID
```

A persistência do remote ID ocorre **somente depois de confirmação remota**.

Se a resposta remota for ambígua, não assumir sucesso.

---

## 24. Notas e Obsidian

Nota local:

```text
Relacionar com [[Foucault]] e [[Biopolítica]].
#pesquisar
```

Deve chegar ao Readwise sem modificar o texto.

Não:
- escapar `[[ ]]`;
- converter Markdown;
- trocar hashtags;
- remover quebras de linha;
- normalizar conteúdo da nota além do necessário para transporte.

### Teste end-to-end obrigatório

```text
KOReader
→ Reader/Readwise
→ plugin/export oficial do Readwise
→ Obsidian
```

Critério:
- `[[Foucault]]` vira wikilink normal no Obsidian.

Também testar update posterior de nota, porque o comportamento do export do Obsidian evoluiu ao longo do tempo.

---

## 25. Deduplicação

Cada anotação sincronizada deve ter vínculo persistente.

Além do remote ID, guardar hashes para detectar alteração.

Nunca deduplicar somente por texto, porque duas ocorrências idênticas podem existir no mesmo documento.

Antes de retry após timeout de POST:
- tentar confirmar se a criação remota aconteceu;
- evitar "timeout depois do servidor criar" virar duplicata.

A estratégia concreta depende do comportamento observado da API e deve ser testada.

---

## 26. Edição de notas

Estado local:

```text
last_synced_note
note_hash
remote_id
```

Se nota local mudou desde o último sync:
- atualizar remoto quando endpoint validado;
- confirmar sucesso;
- atualizar hash somente após sucesso.

Na V1, o fluxo principal é local → remoto.

Conflitos simultâneos são tratados de forma conservadora.

---

## 27. Política de conflitos

A V1 deve evitar "last writer wins" silencioso em dados que podem ser perdidos.

### Documentos

Reader é a fonte de verdade do conteúdo da biblioteca.

### Highlight criado no Kindle

KOReader é a fonte inicial daquele highlight.

### Nota editada apenas no Kindle

Upload normal.

### Nota mudou local e remotamente desde o último sync

Não sobrescrever automaticamente.

Marcar:

```text
conflict
```

e manter ambas as versões nos logs/estado necessário para resolução futura, sem expor conteúdo sensível além do necessário.

Uma UI de resolução sofisticada pode ficar pós-V1; a V1 pode simplesmente não sobrescrever e avisar.

---

## 28. Exclusão

Exclusão remota é operação destrutiva.

Default:

```text
Propagate highlight deletions: OFF
```

Se um highlight local desapareceu:
- não apagar remoto automaticamente;
- registrar possível deleção.

Somente quando opção explícita estiver habilitada e o vínculo remoto for inequívoco:
- executar delete;
- confirmar resposta;
- marcar estado.

Nunca inferir que arquivo/sidecar ausente significa intenção de apagar conteúdo remoto.

---

## 29. Finished → Archive

Quando documento for marcado como finished no KOReader, opção:

```text
When finished:
(*) Archive in Reader
( ) Do nothing
```

Na V1:
- arquivar remotamente;
- **manter arquivo local**.

Remoção local automática é recurso posterior ou explicitamente configurável.

---

## 30. Offline queue

A fila deve suportar:

- create highlight;
- update note;
- delete quando habilitado;
- archive document.

Cada item:

```text
operation_id
operation_type
local_id
remote_document_id
remote_annotation_id
payload_hash
attempt_count
last_attempt_at
last_error_class
status
```

Estados:

```text
pending
in_flight
succeeded
retryable_error
blocked
conflict
```

Após reiniciar o KOReader, a fila deve continuar consistente.

No PW3 alvo, flags locais de Wi-Fi/online não são autoridade suficiente para liberar escrita remota: o Gate 13 demonstrou estado local falso-positivo em Airplane Mode. O Sync deve primeiro descobrir/registrar novos highlights em todos os documentos Reader gerenciados que estejam realmente presentes localmente, persistir a fila, e só então exigir um probe remoto **somente leitura** bem-sucedido antes de processá-la. Falha do probe mantém a fila local e não executa escrita remota. Updates de nota e deletes permanecem limitados ao documento atual nesta fase para não ampliar silenciosamente o escopo destrutivo.

---

## 31. Retry e rate limit

Implementar:
- timeout;
- backoff exponencial limitado;
- `Retry-After` para 429;
- distinção 4xx não-retryable vs 5xx/rede retryable;
- limite de tentativas por ciclo;
- retomada no próximo sync.

Não bloquear UI por tempo indefinido.

---

## 32. UX do Sync

Menu inicial:

```text
Readwise Reader
│
├── Sync now
├── Open Readwise folder
├── Sync status
└── Settings
    ├── Account
    │   ├── Access token
    │   └── Test connection
    ├── Documents
    │   ├── Locations
    │   ├── Types
    │   └── Download images
    ├── Highlights
    │   ├── Upload highlights
    │   ├── Upload notes
    │   └── Propagate deletions
    └── Finished documents
        └── Archive in Reader
```

Resumo:

```text
Readwise sync complete

3 new documents
1 updated
4 highlights uploaded
2 notes updated
1 item pending
0 fatal errors
```

Evitar mensagens técnicas para usuário normal; detalhes ficam no log.

---

## 33. Cancelamento e responsividade

PW3 tem hardware limitado.

Operações longas devem:
- permitir cancelamento quando APIs do KOReader possibilitarem;
- atualizar progresso em lotes;
- evitar ler toda biblioteca enorme em memória;
- fazer streaming/download por chunks quando apropriado;
- limitar concorrência.

Na V1, preferir processamento sequencial/baixa concorrência à velocidade agressiva.

---

## 34. Imagens e HTML

Para artigos:
- usar HTML processado do Reader;
- reescrever URLs/imagens apenas quando necessário;
- escolher cache de imagens conservador;
- tolerar imagem que falha sem invalidar documento;
- evitar data URIs enormes se prejudicarem o PW3.

HTML deve manter:
- headings;
- parágrafos;
- listas;
- links;
- blockquotes;
- imagens úteis.

Não priorizar fidelidade visual sobre legibilidade/performance.

---

## 35. Estado do progresso e sidecars

Objetivo fundamental: atualizações remotas não devem apagar:
- posição de leitura;
- highlights;
- notas;
- configurações por documento.

Testar atualização de um artigo já parcialmente lido.

Se substituir conteúdo tornar posições inválidas:
- detectar;
- preservar backup;
- documentar limitação;
- evitar substituir automaticamente quando houver alto risco até termos política segura.

---

## 36. Observabilidade

Log técnico:

```text
[AUTH] success
[DOC] downloaded id=...
[DOC] unchanged id=...
[PDF] raw source unavailable; fallback
[HL] created local=... remote=...
[HL] unmatched local=...
[QUEUE] retry op=...
[API] 429 retry_after=...
```

Nunca logar token.

Adicionar versão do plugin e schema ao início do log/sessão para facilitar debugging.

---

## 37. Testes automatizados

Mesmo sem Kindle em CI, testar módulos puros em Lua quando possível.

Cobrir:
- paginação;
- cursor repetido;
- deduplicação;
- hashes;
- filename sanitization;
- text matching;
- Unicode;
- migrations;
- queue state machine;
- retry classification;
- conflitos;
- parsing de respostas;
- downloads interrompidos simulados.

Fixtures não devem conter conteúdo privado do usuário.

---

## 38. Testes no aparelho

Criar uma biblioteca de casos controlados:

1. artigo curto;
2. artigo longo;
3. artigo com imagens;
4. Unicode/acentos;
5. frase repetida duas vezes;
6. PDF textual;
7. PDF problemático;
8. EPUB;
9. newsletter;
10. RSS;
11. documento atualizado depois de baixado;
12. highlight sem nota;
13. highlight com `[[wikilink]]`;
14. nota multilinha;
15. internet cai durante download;
16. internet cai depois de POST;
17. 429;
18. pouco espaço;
19. reboot no meio da fila;
20. sync duas vezes sem mudanças.

---

## 39. CI e qualidade

Quando houver código:

- lint/checagem Lua compatível;
- testes unitários;
- validação de estrutura do plugin;
- geração de ZIP instalável como artifact/release;
- nenhuma credencial em fixtures;
- checagem básica de arquivos inesperadamente grandes.

Não adicionar dependências pesadas sem necessidade.

---

## 40. Releases

Estratégia:

```text
v0.0.x — bootstrap/API experiments
v0.1.x — documentos básicos
v0.2.x — formatos/downloads
v0.3.x — highlights
v0.4.x — queue/offline/conflicts
v0.9.x — hardening no PW3
v1.0.0 — fluxo completo validado
```

Cada release de teste deve informar:
- compatibilidade;
- mudanças;
- migrations;
- riscos conhecidos;
- como instalar;
- como reverter.

---

## 41. Instalação de teste

Distribuição pretendida:

```text
readwisereader.koplugin/
→ koreader/plugins/
→ reiniciar KOReader
```

Nunca exigir alteração do firmware para uma atualização comum do plugin.

Manter instruções de rollback:
- fechar KOReader;
- remover/desativar pasta do plugin;
- restaurar backup se necessário.

---

## 42. Ordem exata de implementação / gates

### Bootstrap
1. Registrar licença/origem do plugin antigo.
2. Criar estrutura mínima do repo.
3. Plugin mínimo carrega no KOReader 2025.04.
4. Backup/rollback documentado.

### Conectividade
5. Armazenamento seguro do token.
6. Test connection.
7. Classificação de erros de rede.

### Biblioteca
8. Listar documentos.
9. Paginação completa.
10. Primeiro artigo.
11. Sync incremental.
12. Persistência/versionamento do estado.
13. Filenames seguros.
14. Downloads atômicos.
15. espaço livre/limites.

### Migração controlada do KOReader — depois do Gate 4 e antes das fases seguintes
15A. Congelar/registrar a build que passou Gate 4 em KOReader 2025.04.
15B. Fazer backup de KOReader/settings/plugins/DB e dos documentos/sidecars Readwise.
15C. Atualizar **somente KOReader** para o release oficial v2026.07.1 usando o pacote `kindlepw2`; não atualizar firmware/jailbreak.
15D. Repetir smoke/regressão do Readwise Reader sem Bookshelf; corrigir qualquer incompatibilidade.
15E. Quando Gate 4A-1 passar, adotar v2026.07.1 como baseline das fases seguintes.
15F. Instalar Bookshelf v5.1.4 com Cover browser habilitado e testar coexistência.
15G. Só depois habilitar opcionalmente `Start with -> Bookshelf`.
15H. Não começar imagens/formatos/sidecars antes de Gate 4A-1 e Gate 4A-2 passarem.

### Formatos
16. Artigos.
17. Emails/newsletters.
18. RSS.
19. PDF raw source + fallback.
20. EPUB raw source + fallback.
21. Outros tipos textuais quando fizer sentido.

### Organização
22. Collections/pasta.
23. Locations/filtros.
24. Metadados.

### API de highlights
25. Prova v3 create com `parent_id`.
26. Confirmar representação na v2/export.
27. Confirmar update.
28. Confirmar delete.
29. Registrar contrato real observado.

### Sync de anotações
30. Ler highlights/notas do KOReader.
31. Text matching.
32. Criar highlight remoto.
33. Persistir remote ID.
34. Deduplicação.
35. Nota com Markdown/`[[wikilink]]`.
36. Update de nota.
37. Conflitos.
38. Delete opcional e seguro.

### Offline e conclusão
39. Queue persistente.
40. Retry/backoff.
41. Finished → Archive.
42. Reboot/crash recovery.

### Hardening
43. Bibliotecas grandes.
44. documentos grandes;
45. pouco armazenamento;
46. Unicode;
47. performance no PW3;
48. regressão sidecars/progresso;
49. logs/redaction;
50. instalação/rollback.

### Integração final
51. Reader → Kindle.
52. leitura offline.
53. Kindle → Reader.
54. Reader/Readwise → Obsidian.
55. `[[wikilinks]]` funcionando.
56. segundo sync sem duplicatas.
57. release candidate.
58. v1.0.0.

---

## 43. Critérios de aceite da V1

A V1 só está pronta quando, no **Kindle PW3 real**, conseguirmos repetir:

1. salvar um artigo no Reader;
2. executar Sync no KOReader;
3. artigo aparecer localmente;
4. abrir normalmente;
5. desligar Wi‑Fi;
6. continuar lendo;
7. criar highlight;
8. adicionar nota `ver [[Foucault]]`;
9. ligar Wi‑Fi;
10. executar Sync;
11. highlight aparecer ligado ao documento correto no Reader;
12. nota aparecer intacta;
13. exportar/sincronizar para Obsidian;
14. `[[Foucault]]` funcionar como wikilink;
15. executar Sync novamente;
16. nenhuma duplicata ser criada;
17. mover esse documento no Reader (Inbox/Later/Archive etc.) e sincronizar;
18. a mesma cópia local mudar para a Collection `Readwise: ...` correspondente, sem perder Collections não gerenciadas pelo plugin;
19. alterar uma tag no Reader e sincronizar;
20. a tag atualizada aparecer nos metadados do mesmo documento e, com Bookshelf habilitado, ficar disponível como tag/genre/keyword sem criar uma Collection por tag;
21. editar uma nota e sincronizar;
22. simular falha de rede e recuperar;
23. reiniciar o KOReader com fila pendente e recuperar;
24. marcar documento finished;
25. sincronizar;
26. documento ir para Archive no Reader;
27. arquivo local e sidecar continuarem íntegros.

Além disso:
- token não aparece em Git/log;
- não há perda silenciosa de highlight/nota;
- falha de um item não invalida todo o sync;
- rollback do plugin é simples.

---

## 44. Decisões que não devem ser tomadas por suposição

Antes de implementar definitivamente, medir/testar:

- interoperabilidade de IDs Reader v3 ↔ Readwise v2;
- update/delete de highlight criado via v3;
- comportamento de highlights em PDF/EPUB;
- formato e estabilidade dos sidecars no KOReader pós-migração (esperado v2026.07.1);
- eventos/hooks apropriados para detectar criação/edição/remoção de annotations;
- efeito de atualizar conteúdo local em posições e highlights existentes;
- disponibilidade real de `raw_source_url` por tipo;
- comportamento do Obsidian export para updates de notas em documentos novos/antigos;
- APIs internas do KOReader revalidadas especificamente na baseline pós-migração antes das fases que dependem delas.

Esses pontos viram testes, não pressupostos.

---

## 45. Não objetivos / regras de segurança operacional

Não:
- atualizar Kindle firmware/jailbreak para facilitar desenvolvimento;
- atualizar KOReader fora da migração planejada Gate 4 -> Gate 4A ou sem backup/rollback;
- mexer no jailbreak;
- armazenar token no repo;
- apagar biblioteca remota automaticamente;
- apagar arquivos locais automaticamente na V1;
- fazer fuzzy matching destrutivo;
- avançar watermark antes de sucesso;
- depender do filename como ID;
- tratar timeout de POST como "definitivamente falhou";
- substituir sidecar sem backup;
- fazer sync em background antes de o fluxo manual estar sólido.

---

## 46. Próximo passo

A candidata **0.1.47** já passou fisicamente no PW3:
- startup/settings/token;
- preservação do artigo gerenciado;
- primeiro Sync Wi-Fi-on;
- segundo Sync inalterado/no-op;
- highlight/nota local em offline controlado -> fila durável, sem remote write;
- restart completo ainda offline -> highlight/nota local + fila SQLite persistiram, diagnóstico read-only sem remote write;
- reconnect + um único Sync -> fixture entregue exatamente uma vez, fila zerada e nenhuma duplicata.

Também ficou coberto off-device que um create já marcado `succeeded` continua sucedido/não-runnable após fechar e reabrir o SQLite em um novo processo.

Último checkpoint físico do Gate 16:
1. não editar/recriar/deletar o fixture nem rodar novo Sync antes;
2. reiniciar completamente o KOReader;
3. reabrir o mesmo artigo e confirmar progresso/posição/highlights/notas, incluindo o fixture Gate 16;
4. confirmar Readwise Reader + Bookshelf carregando normalmente;
5. confirmar no Reader remoto que o fixture continua existindo uma única vez;
6. revisar localmente `koreader/crash.log` e exigir ausência de token/Authorization, URL assinada, HTML/conteúdo privado e payload privado de nota/highlight;
7. se qualquer segredo aparecer, não compartilhar o log bruto e falhar Gate 16;
8. se tudo passar, fechar Gate 16, mergear PR #19 e iniciar Phase S / aceite final V1.

Gate 16 continua aberto; Phase S continua bloqueada até esse último PASS.
