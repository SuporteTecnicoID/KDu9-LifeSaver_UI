#!/usr/bin/env bash
# ==============================================================================
# Projeto          : Projeto Linux KDu (Index Data)
# Aplicação        : KDu9-LifeSaver_UI
# Versão           : v2.2 (ESTÁVEL: Sincronia Sob Demanda do Usuário para o View)
# ==============================================================================

if ! command -v yad &> /dev/null; then
    echo "YAD não encontrado. Por favor, instale usando: sudo apt install yad"
    exit 1
fi

# Permite que o ambiente gráfico root abra janelas na sessão do usuário atual
if [ -n "$DISPLAY" ]; then
    xhost +local:root &> /dev/null
fi

export SUDO_ASKPASS="/usr/bin/ssh-askpass"

# Identifica a pasta HOME real do usuário comum (mesmo se rodando sob pkexec/root)
if [ -n "$PKEXEC_UID" ]; then
    REAL_USER=$(id -nu "$PKEXEC_UID")
    REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
else
    REAL_HOME="$HOME"
fi

# Garante um fallback seguro caso a busca falhe
[ -z "$REAL_HOME" ] && REAL_HOME="/home/$USER"

# Função para exibir a janela de dicas técnicas explicativas
exibir_ajuda() {
    yad --title="KDu9-LifeSaver_UI v2.2 - Guia Técnico" \
        --window-icon="/usr/share/pixmaps/kdu9-lifesaver.png" \
        --width=520 --button="Entendi, obrigado!:0" \
        --text="<b>💡 Comportamento do Resgate Extremo (ddrescue):</b>\n\n\
• <b>O arquivo .img cresce, mas o .map travou em 451 Bytes?</b>\n\
  Não se preocupe! O arquivo de mapa possui uma estrutura de texto extremamente compacta. \
Enquanto o <i>ddrescue</i> estiver a ler setores saudáveis contínuos, ele precisa de apenas \
uma linha para registar o progresso. O tamanho do ficheiro só se expandirá fisicamente \
se o utilitário encontrar blocos danificados (bad sectors) e necessitar de fragmentar o mapa.\n\n\
• <b>Atraso na atualização visual (Cache do Linux):</b>\n\
  O Linux otimiza as escritas armazenando as atualizações do mapa temporariamente em cache (RAM). \
O conteúdo real em texto muda em segundo plano antes de o tamanho do ficheiro ser atualizado pelo gestor de ficheiros.\n\n\
• <b>Como validar em tempo real?</b>\n\
  Pode abrir um terminal e rodar: <span foreground='blue'><b>cat $REAL_HOME/kdu9_resgate.map</b></span> \
para ver os ponteiros hexadecimais a avançar dinamicamente."
}

export -f exibir_ajuda
export REAL_HOME

# Loop para gerir a interface principal e o botão de ajuda
while true; do
    DATA=$(yad --title="KDu9-LifeSaver_UI v2.2" \
        --window-icon="/usr/share/pixmaps/kdu9-lifesaver.png" \
        --text="<b>KDu9-LifeSaver_UI: Interface Livre para Recuperação Extrema (ddrescue)</b>\n\
<span size='small' foreground='#666'>Nota: O arquivo de mapa (.map) inicia com 451 Bytes e só expande se houver setores danificados.</span>" \
        --form --width=590 --separator="|" \
        --field="Origem (Infile / Disco Danificado):" "/dev/sda" \
        --field="Destino (Outfile / Imagem ou Disco Novo):" "$REAL_HOME/disco_recuperado.img" \
        --field="Arquivo de Mapa (Logfile / Progresso):" "$REAL_HOME/kdu9_resgate.map" \
        --field="Número de Retentativas (-r):NUM" "3!0!100!1!0" \
        --field="Tamanho do Setor (-b):CB" "512!2048!4096" \
        --field="Acesso Directo ao Disco (-d):CHK" TRUE \
        --field="Pular Fase de Raspagem (-n):CHK" FALSE \
        --field="Leitura Reversa (-R):CHK" FALSE \
        --field="Forçar Gravação (-f):CHK" TRUE \
        --field="Modo Verboso (-v):CHK" TRUE \
        --button="yad-help:2" --button="yad-cancel:1" --button="Iniciar Resgate!system-run:0")

    XCODE=$?

    if [ $XCODE -eq 2 ]; then
        exibir_ajuda
        continue
    fi

    if [ $XCODE -ne 0 ] || [ -z "$DATA" ]; then exit 0; fi
    break
done

ORIGEM=$(echo "$DATA" | cut -d'|' -f1)
DESTINO=$(echo "$DATA" | cut -d'|' -f2)
MAPA=$(echo "$DATA" | cut -d'|' -f3)

# Corrige o bug do YAD local convertendo "3,0" ou "0,0" estritamente para números inteiros simples
RETRIED_RAW=$(echo "$DATA" | cut -d'|' -f4)
if [[ "$RETRIED_RAW" == *","* ]]; then
    RETRIED=$(echo "$RETRIED_RAW" | cut -d',' -f1)
elif [[ "$RETRIED_RAW" == *"."* ]]; then
    RETRIED=$(echo "$RETRIED_RAW" | cut -d'.' -f1)
else
    RETRIED=$RETRIED_RAW
fi

SECTOR=$(echo "$DATA" | cut -d'|' -f5)
DIRECT=$(echo "$DATA" | cut -d'|' -f6)
NOSCRAPE=$(echo "$DATA" | cut -d'|' -f7)
REVERSE=$(echo "$DATA" | cut -d'|' -f8)
FORCE=$(echo "$DATA" | cut -d'|' -f9)
VERBOSE=$(echo "$DATA" | cut -d'|' -f10)

CMD="ddrescue"
[ "$DIRECT" == "TRUE" ] && CMD="$CMD -d"
[ "$NOSCRAPE" == "TRUE" ] && CMD="$CMD -n"
[ "$REVERSE" == "TRUE" ] && CMD="$CMD -R"
[ "$FORCE" == "TRUE" ] && CMD="$CMD -f"
[ "$VERBOSE" == "TRUE" ] && CMD="$CMD -v"
CMD="$CMD -b $SECTOR -r $RETRIED $ORIGEM $DESTINO $MAPA"

yad --title="KDu9-LifeSaver_UI v2.2 - CONFIRMAÇÃO" --image="dialog-error" \
    --text="<b>O utilitário KDu9-LifeSaver_UI vai disparar o comando nativo:</b>\n\n<span foreground='red'><b>$CMD</b></span>\n\nConfirme os alvos de escrita!" \
    --button="yad-cancel:1" --button="Confirmar e Rodar!:0"

if [ $? -ne 0 ]; then exit 0; fi

# Criação preventiva do arquivo com permissão correta ao usuário comum antes do pkexec assumir
if [ ! -f "$MAPA" ]; then
    touch "$MAPA"
    chmod 666 "$MAPA"
fi

# Definição das opções visuais para o xterm (Padrão RoyalBlue com Fonte Forte)
X_OPTS="-bg #4169E1 -fg #FFFFFF -fn 9x15bold -geometry 100x30"

# 1. Abre o xterm liberando o sub-shell para o ddrescue rodar solto no fundo
if [ "$env" == "root" ] || [ "$USER" == "root" ]; then
    xterm $X_OPTS -title "KDu9-LifeSaver_UI Monitor [ROOT]" -e "chmod 666 \"$MAPA\"; $CMD; echo ''; echo 'Cópia finalizada!'; read -n1" &
else
    xterm $X_OPTS -title "KDu9-LifeSaver_UI Monitor" -e "pkexec bash -c \"chmod 666 '$MAPA'; $CMD; echo ''; echo 'Processo encerrado!'; read -n1\"" &
fi

# 2. Em vez de abrir o view no susto com sleep fixo, o YAD entra em cena como um painel de controle interativo.
# Você digita a senha no xterm e, assim que ver os dados subindo no terminal, clica no botão abaixo.
yad --title="KDu9-LifeSaver_UI v2.2 - Painel Visual" \
    --text="<b>Terminal RoyalBlue iniciado!</b>\n\n1. Insira a sua senha de administrador no terminal.\n2. Assim que o mapa começar a se mover no xterm, clique no botão abaixo para ligar o gráfico dinâmico." \
    --image="dialog-information" \
    --button="LIGAR MAPA EM TEMPO REAL:0" --button="Fechar Painel:1"

if [ $? -eq 0 ]; then
    if command -v ddrescueview &> /dev/null; then
        # Abre o view com o arquivo já modificado e ativo pelo ddrescue, engrenando o '-r 5'
        ddrescueview -r 5 "$MAPA" &
    else
        yad --text="Erro: ddrescueview não foi encontrado no laboratório." --image="dialog-warning"
    fi
fi
