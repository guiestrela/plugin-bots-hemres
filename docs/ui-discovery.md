# PBH-003 — Descoberta da barra e proposta de UX

Inspeção: 2026-09-21, 15:37–15:39 -03. Responsável: frontend. Entrega para revisão do CTO, não implementação/ativação.

Projeto: `/home/guiestrela/Work/Plugin Bots Hemres`.
Plano e status oficiais: `/home/guiestrela/OneDrive/Obsidian Vault/Projetos/Plugin Bots Hemres/{Plano.md,Tarefas.md}`. Origem: `plano.md.md` na mesma pasta. Diário: `Registros/Frontend.md`.

## 1. Resultado e limites

A barra real é **Glass Bar 1.3.1**, plugin `io.github.guiestrela.glassbar`, hospedado no **Omarchy 4.0.4-1 / Quickshell 0.3.1-1**. Não é Waybar. O runtime respondeu `ok` ao ping; o catálogo ao vivo confirmou Glass Bar habilitada e `omarchy.bar` desabilitada. Configuração seleciona posição superior e transparência.

O projeto ainda contém documentação, sem package.json, lockfile, código de aplicação ou repositório Git identificado. Não introduzir React, Tailwind ou styled-components: o contrato nativo existente é QML/QtQuick com módulos `qs.Ui` e `qs.Commons`. Esta recomendação é proposta técnica a aprovar em PBH-004.

Já existe **Hermes Deck 0.2.0**, `io.github.mbot11.hermes-deck`, instalado e habilitado, com kinds `service` e `bar-widget`. Sua presença NÃO prova suporte ao fluxo de delegação pedido. Não foi executado nenhum comando de integração desse plugin, nem seus scripts/testes; não copiamos sua implementação. O CTO deve decidir coexistência ou reaproveitamento autorizado, evitando substituir silenciosamente um plugin existente.

Não foram lidos perfis Hermes, credenciais ou bancos de conversas. Não houve instalação, mudança de tema, escrita em configurações ativas, rescan, restart, abertura de painel ou envio real de tarefa. Nenhuma avaliação visual em execução ou teste de usabilidade ocorreu. A viabilidade abaixo é fundamentada no código instalado, não demonstração do produto.

## 2. Evidências reproduzíveis

| Comando executado | Resultado observado |
|---|---|
| `date -Iseconds` | Início `2026-09-21T15:37:49-03:00`; fechamento da inspeção `2026-09-21T15:39:32-03:00` |
| `command -v omarchy quickshell qs waybar qmllint qmlformat hyprctl` | omarchy em `/usr/share/omarchy/bin/omarchy`; quickshell, qs, qmllint, qmlformat, hyprctl em `/usr/bin`; nenhum caminho para waybar |
| `pacman -Q omarchy quickshell waybar` | `omarchy 4.0.4-1`, `quickshell 0.3.1-1`; pacote waybar não encontrado |
| `pgrep -a -x 'quickshell|qs|waybar'` | `543921 quickshell -n -p /usr/share/omarchy/shell` |
| `omarchy version`; `quickshell --version` | `4.0.4-1`; `Quickshell 0.3.1` |
| `omarchy plugin --help`; `omarchy bar --help` | CLI documenta validate/list/add/enable/disable/clone; bar use/put/move/set/position |
| `omarchy theme current`; `omarchy font current` | `Catppuccin`; `JetBrainsMono Nerd Font` |
| `hyprctl configerrors` | Saída vazia; não foi feito reload |
| `omarchy-shell shell ping` | `ok` |
| `omarchy plugin list --json` filtrado por jq aos IDs da barra e Hermes Deck | `omarchy.bar enabled=false`; Glass Bar e Hermes Deck `enabled=true`. Catálogo não expôs versão; versões acima vêm dos respectivos manifestos |
| `omarchy plugin validate '/home/guiestrela/.config/omarchy/plugins/io.github.guiestrela.glassbar'` | exit 0, sem saída |
| `omarchy plugin validate '/home/guiestrela/.config/omarchy/plugins/io.github.mbot11.hermes-deck'` | exit 0, sem saída |
| `git -C '/home/guiestrela/Work/Plugin Bots Hemres' status --short` | `fatal: not a git repository`; sem diff/commit disponível |
| `command -v node npm python3 shellcheck` | node/npm como shims mise; python3 e shellcheck encontrados. Presença não comprova runtime Node configurado |

Os validates comprovam apenas os manifestos dos plugins já instalados, não validam o futuro plugin. `qmllint`/`qmlformat` disponíveis, ainda não executados sobre código do projeto porque ele não existe nesta tarefa. Não há lint/typecheck/build/testes de aplicação aplicáveis à entrega documental.

Uma chamada agrupada que incluía `python3 -c` foi bloqueada pela camada de aprovação antes de executar. A verificação de catálogo foi refeita com `jq` e comandos de leitura permitidos; nenhuma configuração de aprovação foi alterada. Busca em `/usr/share/omarchy/docs` falhou porque esse diretório não existe; documentação efetiva localizada em `/usr/share/omarchy/shell/README.md` e `shell/plugins/README.md`.

## 3. Fontes locais e extensão suportada

- `/home/guiestrela/.config/omarchy/shell.json`: somente campos necessários foram considerados no relatório (bar.id, posição, transparência, presença de Hermes Deck). Não reproduzir configuração integral, pois contém configurações pessoais não necessárias.
- `/usr/share/omarchy/shell/README.md:46–100`: manifest schemaVersion 1, kinds e facades. Linhas 102–170: instalação, isolamento e hot reload. Linhas 172–215: IPC. Linhas 258–285: persistência.
- `/usr/share/omarchy/shell/services/PluginRegistry.qml`: validação real `validateManifest`, entry points relativos seguros, resolução dos plugins.
- `/usr/share/omarchy/bin/omarchy-plugin-validate`: valida campos, schemaVersion numérico 1, namespace não reservado, entry points existentes/relativos, kinds correspondentes e ausência de symlinks. Fonte lida antes da execução.
- `/usr/share/omarchy/shell/Ui/PluginBarApi.qml`: estado escalar da barra, tooltips, registro de alvos, coordenação de popouts e troca de painel. Não equivale a isolamento contra código malicioso.
- `/usr/share/omarchy/shell/Ui/Panel.qml`: base do widget/painel com `bar`, `moduleName`, `settings`, `ipcTarget`, `open/close/toggle`; IPC pode ser desativado (`manageIpc`).
- `/usr/share/omarchy/shell/Ui/KeyboardPanel.qml:1–100`: painel ancorado com `anchorItem`, `bar`, `owner`, `open`, `focusTarget`, dimensões, foco layer-shell e dismiss. É alternativa adequada para formulário, ao contrário de popup apenas de hover.
- `/usr/share/omarchy/shell/Ui/TextField.qml`: QtQuick.Controls com tipografia, seleção, borda e foco do Omarchy. Campo é de uma linha; composição multilinha precisará `TextArea` estilizada pelos mesmos tokens, não presumir TextArea pronta no kit.
- `/usr/share/omarchy/shell/Commons/{Color.qml,Style.qml}`: paleta e tokens reativos do sistema.
- `/usr/share/omarchy/shell/plugins/agents/{manifest.json,Agent.qml}`: exemplo nativo, não integração Hermes; seus dados são uso de provedores.
- `/home/guiestrela/.config/omarchy/plugins/io.github.guiestrela.glassbar/{manifest.json,Bar.qml,PluginServiceBridge.qml}`: barra instalada e ponte customizada.
- `/home/guiestrela/.config/omarchy/plugins/io.github.mbot11.hermes-deck/manifest.json`: identificação, versão e kinds do plugin coexistente.

### Atenção: serviço sob uma barra terceirizada

O README do host, linhas 96–98, diz que widgets hospedados em barra terceirizada recebem facade sem objetos de serviço vivos. Portanto não depender cegamente de `shell.serviceFor(...)`.

Há uma nuance local importante: Glass Bar contém ponte própria. `Bar.qml:144–238` consulta metadata, limita diretório ao plugin do usuário e cria `PluginServiceBridge`; `PluginServiceBridge.qml:25–28,83–127` usa serviço do host se existir, ou carrega o entry point `service` e instancia outro objeto local. Isso é evidência de caminho de compatibilidade no código, NÃO prova de singleton/funcionamento para o novo plugin. Pode haver instância duplicada, diferenças entre versões, polling redundante ou envio duplicado se efeitos forem ligados ao ciclo de vida.

Recomendação: um `bar-widget` sem serviço global obrigatório para a primeira implementação. Adaptador pertencente ao widget, operações de leitura sob demanda e escrita somente por ação explícita. Qualquer coordenação entre monitores/processos e deduplicação de tarefas deve ser resolvida no contrato do backend, não supondo que QML é singleton. Não criar ponte alternativa ou contornar a facade do host.

## 4. Arquitetura proposta — depende de PBH-004

Fluxo: BarWidget → painel nativo → modelo de UI/adaptador → contrato local seguro aprovado pelo backend → Hermes. Sem chamadas de shell concatenadas com tarefa/ID de bot e sem credenciais em QML. Usar argv fixos e payload estruturado por canal acordado (stdin/IPC local, a definir); não assumir endpoint HTTP, porta, comando de delegação ou transporte existente.

Estrutura proposta, ainda NÃO criada:

- `manifest.json`: schemaVersion 1; ID sugerido `io.github.guiestrela.hermes-bots` (não aprovado, confirmar ausência de colisão antes de usar); kind `bar-widget`, entry point `BarWidget.qml`, allowMultiple=false, defaultSection=right. Não alterar o nome do projeto Plugin Bots Hemres.
- `BarWidget.qml`: ícone compacto com nome acessível “Bots Hermes”, tooltip e coordenação de popout. Sem avatar de todos os bots diretamente na barra, evitando excesso de largura.
- `BotsPanel.qml`: painel ancorado via kit Omarchy, regiões de seleção/composição/resultado.
- `components/BotRow.qml`, `BotAvatar.qml`, `TaskComposer.qml`, `FeedbackBanner.qml`: componentes locais coesos.
- `HermesAdapter.qml`: lifecycle de requisições, timeout e transporte conforme contrato aprovado; não ler configurações/segredos dos perfis.
- `js/BotsState.js`: normalização dos dados, estado e validação de UI; backend repete a validação autoritativa.
- `tests/`: futuros testes de estado/contrato e harness QML isolado, somente após ampliação do escopo.
- `assets/`: somente fallback original/licenciado se necessário; preferir iniciais sem dependência de fonte de ícones.

Alternativa: abrir aplicação externa ao clique. Simplifica formulário longo e isolamento visual, mas adiciona janela/stack e perde parte da UX nativa da barra. Não recomendada antes de testar a opção QML, que já tem suporte local ao painel com foco.

### Pontos obrigatórios para o contrato backend

1. Lista explícita com identificador estável, nome, descrição curta, avatar opcional seguro e capacidades de acesso/delegação. ID não deve ser inferido a partir de nome de exibição. Sem lista inventada/hardcoded.
2. Distinguir ausência de bots, erro de descoberta e integração indisponível. Roster descoberto não significa bot online; status desconhecido deve ser mostrado como desconhecido.
3. Definir o que “Acessar” realmente abre, quais recursos estão suportados e o comportamento se indisponível.
4. Delegação precisa de resultado distinguindo aceitação, execução e conclusão; recibo/ID quando suportado. Timeout após envio pode significar resultado incerto, não falha garantida.
5. Limite de tarefa, encoding Unicode, permissões, timeout, cancelamento real ou somente parada de espera, esquema de erro seguro e deduplicação/idempotência. Não exibir botão Cancelar execução sem backend que a suporte.
6. Avatares: caminhos canônicos permitidos e limites de tamanho/formato, sem URL remota arbitrária, traversal ou symlink para arquivo sensível. Avatar inválido não bloqueia a lista.
7. Nenhum texto de tarefa em logs/CLI argv se puder ser evitado; dados exibidos como texto simples. Não renderizar HTML/Markdown remoto automaticamente. Segredos e rascunhos não vão para shell.json, vault ou console.

## 5. UX e design Omarchy

Evidência de necessidade: usuário pediu acesso, delegação e avatar na barra. Hipótese de uso: alternar entre especialistas sem abrir várias janelas. Não houve entrevistas, Figma fornecido ou testes com usuários.

Fluxo principal proposto:

1. Acionar “Bots Hermes”; foco vai à busca se houver lista extensa, ou à seleção.
2. Listagem com avatar, nome e função; seleção única explícita. Ação “Acessar” separada de “Delegar” e habilitada por capacidade confirmada.
3. Compositor mostra destinatário, campo “Tarefa” multilinha, orientação breve de não incluir segredos e botão “Enviar tarefa”. Enter insere linha; envio exige botão ou atalho explícito Ctrl+Enter, com validação idêntica.
4. Envio bloqueia duplicação, conserva texto e mostra “Enviando…”. Troca de destinatário fica impedida durante a submissão.
5. Após aceite comprovado, mostrar “Tarefa recebida”, destinatário e recibo (se disponível), não “Concluído”. Limpar rascunho somente com comportamento aprovado; propor manter até ação “Nova tarefa”.

Layout proposto: painel com largura alvo `Style.space(440)`, limitado à área útil do monitor; lista rolável sobre compositor, altura limitada para monitores menores e barra lateral. Dimensões são hipótese inicial, não medida observada ou validada. Seleção e resumo nunca dependem só de avatar. Nome longo quebra ou tem alternativa legível, sem desaparecer com elipse inacessível.

Tema: `Color.popups.background/text/border`, `Color.accent`, `Color.urgent`; `Style.font.family/body`, `Style.spacing`, `Style.space`, `Style.cornerRadius` e helpers de foco/seleção. A fonte atual é JetBrainsMono Nerd Font e tema atual Catppuccin, mas não fixar seus valores no plugin. `Color.qml` resolve a paleta em `~/.local/state/omarchy/current/theme` e reage às atualizações. Respeitar a transparência da Glass Bar no ícone, mas oferecer superfície de leitura legível no painel. Contraste sobre wallpaper e tokens com alpha requer medição real; herdar tema não garante AA.

Avatares: imagem real apenas quando fornecida/validada pelo adaptador. Fallback por iniciais + forma estável, com indicação “Avatar não disponível” quando relevante; não inventar fotos nem baixar de serviços externos. Acessível pelo nome do bot, imagem decorativa quando o nome adjacente já identifica o item; preservar dimensões para evitar deslocamento.

### Estados exigidos

| Estado | Conteúdo/ação |
|---|---|
| Carregando roster | “Carregando bots…”; sem seleção ou envio |
| Lista vazia confirmada | “Nenhum bot disponível”; Atualizar; não configurar perfis automaticamente |
| Busca sem resultado | “Nenhum bot corresponde à busca”; limpar busca |
| Adaptador indisponível | Mensagem clara e tentar novamente; não mascarar como lista vazia |
| Avatar ausente/quebrado | Iniciais; restante do bot utilizável |
| Nenhum destinatário | Orientação de seleção; envio desabilitado com razão visível |
| Tarefa vazia/só espaços/excessiva | Erro associado ao campo; manter texto e corrigir foco |
| Enviando | Progresso indeterminado, sem reenviar ou trocar destinatário |
| Aceita | Confirmação real com recibo se suportado; não declarar conclusão |
| Rejeitada/erro | Mensagem sanitizada, texto preservado e ação de correção |
| Timeout/resultado incerto | “Não foi possível confirmar o envio”; não tentar de novo automaticamente; consultar recibo se API permitir |
| Reabertura/hot reload | Rascunho apenas em memória; fechar não reenvia. Reload pode perder rascunho — limitação explícita até solução aprovada |

## 6. Acessibilidade

Qt Quick nativo: aplicar propriedades `Accessible` (nome, papel, descrição e estado) e foco explícito; não transplantar ARIA/HTML para QML. Testar exposição AT-SPI com ferramenta disponível quando houver UI. Compatibilidade de leitor de tela não está comprovada.

Ordem de Tab/Shift+Tab previsível; setas para lista somente quando esta tiver foco; Espaço/Enter para seleção/controles; Esc fecha sem enviar e restaura foco ao acionador quando possível. Não capturar setas de edição do compositor com navegação global de painel. Testar coexistência com `KeyboardPanel` e troca de popout.

Foco visível por borda e contraste; erro/sucesso por texto + ícone, nunca cor isolada. Alvos confortáveis, texto escalável, rolagem utilizável por teclado e sem perda do botão de envio. Metas WCAG 2.2 AA aplicáveis: contraste 4,5:1 para texto normal e 3:1 para componentes/foco relevante, sem alegar certificação. Evitar animação decorativa contínua; animações reduzidas/desativáveis e sem depender delas para comunicar estado.

## 7. Testes futuros e critérios de avanço

Somente inspeções de leitura descritas na seção 2 foram executadas. Não há UI renderizada deste projeto, integração, mocks ou protótipo a demonstrar.

Após contrato e ampliação de escopo pelo CTO:

1. Validar manifesto do projeto com `omarchy plugin validate <pasta-do-plugin>` e confirmar ausência de colisão de ID. Não instalar para validar.
2. Executar `qmllint` e análise de formato nos arquivos criados, resolvendo imports Omarchy/Quickshell em harness separado. Não afirmar teste aprovado se faltarem metadados de módulos. `qmlformat` sem modo de escrita durante revisão.
3. Testes puros de estado/validação: Unicode, vazio, limite, roster malformado, ID estável, fallback, mensagens simples, timeout incerto, proteção contra duplo envio. Definir runner disponível com backend/CTO, sem instalar dependências implicitamente.
4. Harness fora de `~/.config/omarchy/plugins` e fora da barra ativa; transporte fixture claramente identificado como teste. Exercitar Qt offscreen quando suportado para construção e estados. Isso não valida layer-shell, integração Hermes nem acessibilidade real.
5. Revisão visual e teclado em sessão isolada autorizada: tema claro/escuro, texto ampliado, tamanho estreito, nomes longos, top/bottom/left/right, múltiplos monitores, popup concorrente, foco inicial/retorno e ausência de perda de texto. Não lançar segunda shell Omarchy completa, pois pode duplicar notificações/lock/serviços.
6. Contrato backend real em modo de leitura autorizado para roster/avatares, sem dados sensíveis em evidência. Qualquer envio real exige autorização específica, destinatário e tarefa de teste acordados. Fixture aprovada não equivale a delegação real.
7. Instalação/ativação somente após aprovação separada, backup e rollback definidos pelo CTO. Validar Glass Bar e barra nativa em ambiente autorizado, duplicidade de instâncias e ausência de envio automático após reload. Sem mudar barra ativa agora.

Critério para PBH-003: fontes e runtime documentados, API/tema e compatibilidade analisados, arquitetura/UX/estados/acessibilidade e plano de testes registrados. Critério para produto pronto permanece pendente: implementação, testes reais, revisão defensiva, contrato aprovado e demonstração autorizada.

## 8. Riscos e decisões pendentes

- PBH-004 bloqueia implementação de transporte e escolhas finais de arquitetura.
- Ponte de serviço da Glass Bar não é contrato universal: preferir widget sem serviço global obrigatório; não confundir código encontrado com execução verificada.
- Plugins são código não sandboxed no mesmo processo do desktop. Minimizar código/dependências e impedir dados sensíveis na árvore QML ou logs.
- Hot reload automático em diretório ativo: manter todo desenvolvimento na pasta Work; nunca usar clone/add/enable apenas para explorar.
- Hermes Deck coexistente: distinguir ícone/nome e não sobrescrever seu ID/arquivos.
- Tema/transparência, foco layer-shell, leitores de tela e multi-monitor precisam de teste real posterior.
- Sem repositório Git inicializado, não há commit/diff nesta etapa. Inicialização cabe ao CTO se autorizada.
