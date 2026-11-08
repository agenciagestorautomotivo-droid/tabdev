# OpenEXE (marco 3) — pacote de código-fonte

O sistema se chama **OpenEXE**. **NotIA** é o cérebro e a memória de longo prazo (Vault em Markdown + SQLite). O id do pacote continua `com.notia.os.notia`, por causa do login Google.

Launcher Flutter para tablet em paisagem, com 4 quadrantes editáveis.
Este pacote NÃO foi compilado (o ambiente onde foi escrito não alcança o Flutter SDK).
Espere ajustes pequenos na primeira compilação.

## Layout OpenEXE (marco 3)

Tela única para o VAIO TL10 (paisagem). De cima para baixo:

1. **Linha de status**: OpenEXE, Wi-Fi/ONLINE, bateria, Bluetooth (ícone azul só quando ligado), alarme, próxima agenda ("em 3 h"), Drive, agente (OCIOSO/TRABALHANDO), voz, hora e data.
2. **Barra de comandos**: Buscar (Ctrl K), Nota rápida, Escanear, Notificações (com contador), Agente de apps, Rotinas (contador), Modo foco, Lugar.
3. **Corpo, 5 módulos**: esquerda = Q1 Console e Q3 NotIA (cérebro e memória); direita = Q2 Hub de IAs (com aba REPOSITÓRIOS), Q5 Apps instalados e Q4 Dock (só 5 pastas). EDITAR LAYOUT troca de lugar e redimensiona.
4. **Painel de produtividade**: tablet (RAM, memória, CPU, temperatura), tarefas de hoje, próximo compromisso, última notificação, área de transferência.
5. **Rodapé**: Relógio, Calculadora, Calendário, Câmera, Gravador, Ajustes (abrem os apps do sistema), Editar layout, Sincronizar agenda e o botão de teclado.

Detalhes que merecem atenção:

- **Teclado**: com o teclado magnético do TL10 conectado, o botão mostra TECLADO FÍSICO e o campo do console não abre o teclado da tela. Tocar no botão força o virtual; ao conectar ou desconectar o teclado, volta ao automático.
- **Atalhos**: Ctrl K buscar, Ctrl N nota rápida, Ctrl L foco no console, Ctrl M microfone, Esc limpar, F1 ajuda.
- **Área de transferência**: popup com 25 textos (esquerda) e 25 imagens (direita). Fixados nunca saem sozinhos; ao passar do limite sai o mais antigo não fixado; textos que parecem senha não são guardados. O Android só entrega a área de transferência com o app aberto, então o OpenEXE confere quando volta ao primeiro plano e ao abrir o popup.
- **Monitor do tablet** (honesto sobre o Android 13): RAM e memória são reais. O Android bloqueia a leitura do uso total da CPU e do sensor térmico do processador para apps comuns; o OpenEXE estima a CPU pela frequência atual/máxima e mostra a temperatura da bateria. Tocar no cartão mostra de onde veio cada número.
- **Dock com 5 pastas** (Mídia, Google, Social, Trabalho, Utilitários). Na primeira abertura ele migra o dock antigo: pastas conhecidas são mantidas e apps soltos vão para Utilitários. App novo da Play Store aparece em Q5 com ponto amarelo (sem pasta) até você movê-lo.
- **Q5 Apps instalados**: busca, filtros TODOS / SEM PASTA / RECENTES, EDITAR para marcar vários e MOVER PARA PASTA; toque longo abre abrir, mover, info e desinstalar (o próprio Android pede a confirmação). O Android não informa quantas atualizações a Play Store tem, então ATUALIZAÇÕES e ATUALIZAR TUDO abrem a Play Store.
- **Aba REPOSITÓRIOS**: adicione por dono/repo, por URL ou buscando na sua conta (usa o token do CONFIG). A estrela define o repositório padrão do console (`gh:`). ENVIAR NOTA e WORKFLOW rodam os comandos `gh: commit` e `gh: dispatch`, que sempre pedem confirmação.
- **Tarefas**: caixas de seleção em `Notas/tarefas.md` do Vault (Markdown puro, editável no Obsidian).
- **Modo foco**: silencia a leitura em voz alta e as mensagens de notificação no console.

Arquivos novos: `lib/clipboard_popup.dart`, `lib/global_search.dart`, `lib/panels/apps_panel.dart`, `lib/services/{dock_model,system_monitor_service,keyboard_mode,tasks_service,repo_store}.dart`, `SystemKit.kt`, `res/xml/clip_paths.xml`.

## Como montar

Requisitos: Flutter 3.22 ou mais novo, Android SDK, JDK 17.

    bash setup.sh
    cd ../notia
    flutter run                      # tablet conectado por USB
    flutter build apk --release      # APK em build/app/outputs/flutter-apk/

Depois de instalar: Configurações do Android > Apps > App padrão de início > Notia.
No Android 13, o app tem de ser aberto uma vez para pedir o microfone.

## O que já funciona neste marco

IA universal e economia de tokens
- Qualquer IA compatível com a API OpenAI entra em CONFIG (URL, modelo, chave): Groq, Gemini,
  OpenRouter, DeepSeek, Mistral, Together, Ollama local. `@nome pergunta` escolhe a IA na hora.
- Cadeia com circuit breaker: se uma IA demora ou falha, a próxima responde. Simples vai para o
  Groq; complexo vai para o especialista (Gemini ou OpenRouter).
- Economia: comandos, contas e pedidos de mídia são resolvidos por regras locais (0 tokens), cache
  de respostas, memória injetada só quando o assunto pede, respostas limitadas a 500 tokens.
- Criar mídia ("crie uma música de ...", "gere uma imagem de ..."): imagem pelo Pollinations (sem
  chave), música pelo MusicGen no Hugging Face (token grátis; demora 20 a 60 s na primeira vez).
  O arquivo é salvo em Vault/Midia/, toca ou aparece no console e entra no backup do Drive.
  Vídeo não tem API gratuita estável: o Notia copia o pedido e abre as ferramentas de vídeo no Hub.

Quadrantes
- Q1 console: IA, calculadora (`= 2+2`, `set x = 5`, `juros`, `price`, `markup`, `margem`),
  `gh:`, `sb:`, `drive:`, voz (MIC), sugestão ao copiar link.
- Q2 Hub de IAs: atalhos para ChatGPT, Gemini, Claude, Grok, DeepSeek, Copilot, Perplexity, NotebookLM,
  Ideogram, Leonardo, Suno, Udio, Kling, Runway e outros, por categoria (texto, pesquisa, imagem, música,
  vídeo). Abre o app instalado; se não houver, abre o site dentro do quadrante. Em EDITAR você toca num
  atalho para alterar (nome, site, pacote, categoria), remove com o x ou inclui com + nova IA.
- Q3 Vault e cérebro: Vault estilo Obsidian em /sdcard/Documents/NotiaVault/ (Notas, Memoria, Diario,
  Inbox, Midia, CLAUDE.md) como fonte da verdade, índice SQLite. Sem API: o Claude Code ou o app do
  Claude no computador abre essa pasta e trabalha nos mesmos arquivos.
- Q4 dock e navegador: dock com pastas editáveis. Na primeira abertura cria "Mídia" (galeria, vídeos,
  músicas, arquivos, mais "Criações IA") e "Google". Arraste um app sobre uma pasta para guardá-lo.
- Apps da Play Store: botão PLAY STORE na dock, e pedidos como "abrir Spotify" ou "instalar Canva".
  A dock se atualiza sozinha: app instalado entra no fim da dock, app removido some (também das pastas).
  Os apps abrem em tela cheia por cima do launcher; o botão Home volta para o Notia.
- EDITAR LAYOUT muda tamanhos e a posição de cada módulo.

Google
- Drive: backup incremental de tudo (Vault inteiro, mídias e snapshot do SQLite) na pasta "Notia Backup".
  Automático a cada 6 horas, ou `drive: backup` / botão Sync Cloud. `drive: restore` recupera.
- Agenda: SINCRONIZAR AGENDA lê as próximas 24 h e guarda uma linha curta na memória.
- Gemini: IA de texto pela chave do AI Studio.

Outros: GitHub (`gh:`), Supabase (opcional, `sb:`), pausa dos timers dos WebViews fora de foco.

## Recursos do aparelho (marco 2)

Tudo abaixo é novo e NÃO foi testado em aparelho. Digite `ajuda` no console para ver a lista.

Primeiro uso: CONFIG > Recursos do aparelho.
1. Toque em "Liberar configurações restritas": abre as informações do app; no menu de 3 pontinhos
   escolha "Permitir configurações restritas" (o Android 13 bloqueia isso em apps instalados por APK).
2. "Ativar controle de apps": ligue o serviço "Notia (controle de apps)".
3. "Ativar notificações": ligue o Notia na lista de acesso a notificações.
4. Permita contatos, calendário e localização pelos botões da mesma seção (só os que for usar).

Agente de apps (a IA usa os apps como você)
- `no ElevenLabs, gere a voz deste texto e salve` ou `agente: abra o Spotify e toque minha playlist`.
- Funciona assim: lê a tela (acessibilidade) → manda a lista de elementos para a IA → a IA responde UMA
  ação (tocar, digitar, rolar, voltar, abrir app, fim) → o Notia executa → repete (até 14 passos).
- A faixa "Notia · passo N/14 · PARAR" fica no topo por cima do app. Também vale digitar `parar`.
- Antes de tocar em algo como pagar, comprar, enviar, apagar, assinar ou transferir, aparece SIM/NÃO por
  cima do app. Campos de senha nunca são preenchidos (o agente devolve a pergunta para você).
- Recusa operar bancos, carteiras e gerenciadores de senha (lista em `app_agent_service.dart`).
- Custo: cerca de 600 a 1000 tokens por passo. O Gemini é usado primeiro (aceita telas maiores e segue o
  formato melhor). Modelos pequenos podem errar a ação; se acontecer, use `@gemini`.
- Telas protegidas (FLAG_SECURE) e jogos aparecem vazios; o agente avisa e para.
- Ao terminar, o Notia volta para a tela inicial e fala o resumo.

Notificações: `notificações [app]`, `resumir notificações` (IA, ~600 tokens), `limpar notificações`,
`notif falar whatsapp` (lê em voz alta as desse app). Ficam só na memória (últimas 100), nada em disco.

Contatos e mensagens: `ligar para João`, `mensagem para Ana: chego em 10 min`, `whatsapp para Ana: oi`.
O Notia abre a tela já preenchida; quem toca em ligar/enviar é você.

Câmera e fotos: `escanear` (câmera → texto → nota no Vault, OCR no aparelho, 0 tokens), `fotos de hoje`,
`indexar galeria` (lê o texto das fotos recentes), `achar foto nota fiscal`. Imagens enviadas por
Compartilhar também passam por OCR.

Compartilhar para o Notia: o Notia aparece no menu Compartilhar do Android (texto, links, imagens) com
as opções salvar nota, resumir com IA ou abrir link.

Painel rápido: adicione o botão "Notia" ao painel de configurações rápidas; ele abre o Notia ouvindo.

Agenda do aparelho: `agenda do aparelho` lê o Calendário do Android (inclui o que já sincronizou com
Google ou Outlook) e guarda um resumo em `agenda_local`, que a IA usa quando você pergunta da agenda.

Histórico da área de transferência: `clip`, `clip texto`, `clip limpar`. Guarda os últimos 100 itens e
ignora textos que parecem senha. Pode ser desligado em CONFIG.

Rotinas e lugares
- `rotina: 07:00 resumir minha agenda`, `rotina: carregador => drive: backup`,
  `rotina: notif whatsapp => resumir notificações`, `rotina: bateria<20 => ...`, `rotina: local casa => ...`.
- `rotinas` lista; `rotina remover N` / `rotina pausar N`. O comando de uma rotina é qualquer coisa que
  você digitaria no console.
- `lugar salvar casa` guarda onde você está (raio de 150 m); a chegada é checada a cada 10 min e ao voltar
  ao app, só com o Notia aberto (ele é o launcher, então quase sempre está).
- Horários perdidos nos últimos 90 minutos rodam quando o app volta.

Bateria e rede: o backup automático do Drive só roda no Wi-Fi e com carregador ou 30% de bateria.

Biometria: em CONFIG, "Pedir digital/PIN para abrir a CONFIG" e "Travar o Vault" (pede de novo depois
de 5 min fora do app). Se o aparelho não tem trava de tela, não há como proteger e ele não bloqueia.

Se a compilação falhar por causa do `local_auth` (tema AppCompat) ou do ML Kit, os dois são opcionais:
remova o pacote do `setup.sh`, os arquivos `lock_service.dart` / `ocr_service.dart` / `gallery_service.dart`
e as referências a eles em `device_kit.dart`, `main.dart` e `device_commands.dart`.

## Configurar o login Google (uma vez, grátis)
1. console.cloud.google.com: crie um projeto; ative as APIs "Google Drive API" e "Google Calendar API".
2. Tela de consentimento OAuth: tipo Externo, em modo de teste, adicione seu e-mail como usuário de teste.
3. Credenciais > ID do cliente OAuth > Android: pacote `com.notia.os.notia` e o SHA-1 do seu certificado
   (`cd android && ./gradlew signingReport`).
4. Abra o Notia > CONFIG > Entrar com Google. Os escopos pedidos são drive.file (só arquivos criados
   pelo Notia) e calendar.readonly.
O restore em outro tablet funciona porque o escopo drive.file enxerga os arquivos criados pelo mesmo
cliente OAuth.

## Pontos que podem quebrar a compilação (nada foi compilado ainda)

Este código foi escrito sem acesso ao Flutter SDK, então a primeira compilação pode apontar erros pequenos. Os mais prováveis, em ordem:

1. `local_auth` e ML Kit (marco 2): veja as instruções de remoção acima.
2. `installed_apps`: o filtro RECENTES lê `installedTimestamp` de forma tolerante (se a versão não tiver o campo, RECENTES fica sem ordem, mas não quebra).
3. `SystemKit.kt`: usa `androidx.core` (FileProvider). Ele chega junto com o `local_auth`; sem ele, adicione `implementation("androidx.core:core-ktx")` em `android/app/build.gradle.kts`.
4. Se algum erro disser "undefined name/method", mande a mensagem completa que eu corrijo.

## Ainda NÃO implementado (próximos marcos)
- Modelo de IA rodando no tablet (depende da memória e do chip; falta saber o modelo do aparelho).
- Voz offline forçada: o Android usa o reconhecimento offline sozinho quando o pacote de português
  está baixado (Configurações > Idioma > Voz).
- Rotinas e checagem de lugar rodam só com o Notia vivo; não há serviço em segundo plano próprio.
- O agente de apps roda no Dart. Se o Android encerrar o Notia com outro app aberto, o agente para.
- Escuta contínua por palavra de ativação com serviço em primeiro plano.
- Despertador real (agendamento, janela de 90 s, escalada com áudio).
- Confirmação por voz ("sim", "pode"): hoje a confirmação é por toque.
- Tabela credenciais_servicos (criada, vazia). Chaves e senhas ficam em SharedPreferences (pasta
  privada do app); o ideal depois é flutter_secure_storage.
- Bloqueio de imagens no navegador é por CSS/JS; o WebView do Flutter não intercepta sub-recursos.
- Música: o prompt vai como você digitou; o MusicGen entende melhor inglês.
- Pacotes Android dos atalhos de IA podem estar desatualizados; nesse caso abre o site.
