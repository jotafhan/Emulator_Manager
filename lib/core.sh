#!/bin/bash
# =============================================================================
# Emulator Manager - core.sh
# Funções compartilhadas: navegação dialog, normalização de retorno (B = ESC),
# helpers de log, verificação de ferramentas, formatação de tamanho.
# =============================================================================

# --- Detecta o device automaticamente ---
# R36S / dArkOSRE  → botão B envia ESC (código 255)
# RG351MP / ArkOS  → botão B envia backspace (código 1 = Cancel no dialog)
# A detecção é feita pelo hostname. Ambos os casos são tratados pelo NORM_RET.
_EM_HOSTNAME=$(hostname 2>/dev/null | tr '[:upper:]' '[:lower:]')
if echo "$_EM_HOSTNAME" | grep -qE 'rg351|rg353|rg552|rg35xx|arkos'; then
    _EM_DEVICE="rg351"
elif echo "$_EM_HOSTNAME" | grep -qE 'darkosre|r36'; then
    _EM_DEVICE="r36s"
elif [ -f /etc/device_info ]; then
    _dev_info=$(cat /etc/device_info 2>/dev/null | tr '[:upper:]' '[:lower:]')
    echo "$_dev_info" | grep -qE 'rg351|rg353' && _EM_DEVICE="rg351" || _EM_DEVICE="r36s"
else
    _EM_DEVICE="r36s"
fi

# --- Elimina o delay de ~1 segundo ao apertar ESC (botao B) ---
# O dialog usa ncurses internamente, que por padrao espera ESCDELAY
# milissegundos (1000ms de fabrica) antes de decidir que um ESC sozinho e
# de fato "ESC" e nao o inicio de uma sequencia de escape maior (como as
# teclas de seta, que comecam com ESC). Isso faz o botao B/VOLTAR parecer
# "lento" de forma consistente (sempre ~1s) em qualquer dialog --menu ou
# --msgbox. Reduzir para 25ms torna a resposta praticamente instantanea
# sem qualquer efeito colateral perceptivel na navegacao.
export ESCDELAY=25

# --- Normaliza códigos de retorno do dialog ---
# R36S (dArkOSRE): botão B → ESC → código 255
# RG351MP (ArkOS): botão B → backspace → código 1 (Cancel)
# Em ambos os casos tratamos como VOLTAR.
# OK (0) / VOLTAR (1 ou 255) / SAIR
NORM_RET() {
    local ret=$1
    if [ "$ret" -eq 255 ] || [ "$ret" -eq 1 ]; then
        echo "VOLTAR"
    elif [ "$ret" -eq 0 ]; then
        echo "OK"
    else
        echo "DESCONHECIDO"
    fi
}

# --- Wrapper padrão para dialog --menu ---
# Uso: DIALOG_MENU "Titulo" "Texto" tag1 item1 tag2 item2 ...
# Forca a TELA do dialog em $CURR_TTY (mesmo padrao do Alter_MThemes): quando
# o script e lancado pelo Tools do ES, o stdin/stdout herdados nem sempre
# apontam para o console fisico visivel, e o dialog desenha "no vazio"
# mesmo rodando normalmente (tela preta na pratica).
# Logica dos redirecionamentos (ordem importa, processados da esquerda
# para a direita):
#   3>&1            guarda o stdout ORIGINAL (o pipe do "choice=$(...)")
#   1>"$CURR_TTY"   redireciona a TELA do dialog (fd1) para o tty visivel
#   2>&3            redireciona a ESCOLHA do dialog (fd2) para o stdout
#                   original guardado no fd3, que e o que "choice=$(...)"
#                   realmente captura
#   <"$CURR_TTY"    le os botoes/inputs do tty visivel
DIALOG_MENU() {
    local title="$1"
    local text="$2"
    shift 2
    dialog --backtitle "$DIALOG_BACKTITLE" \
        --title "$title" \
        --ok-label "OK" --cancel-label "VOLTAR" \
        --menu "$text" 0 0 0 "$@" \
        3>&1 1>"$CURR_TTY" 2>&3 <"$CURR_TTY"
}

# --- Wrapper para mensagens informativas ---
# --no-collapse preserva as quebras de linha e o espacamento exatos do
# texto (essencial para relatorios formatados com printf, como o de
# tamanho por sistema e estatisticas). Sem essa flag, o dialog faz reflow
# automatico do texto e junta tudo, bagunçando o alinhamento das colunas.
#
# IMPORTANTE: "$text" pode conter sequencias \n literais (barra+n), porque
# em todo o projeto as strings sao escritas como "...texto\ntexto..." em
# aspas duplas simples - isso NUNCA produz uma quebra de linha real em
# bash, e o dialog tambem nao interpreta \n por conta propria (ele trata o
# texto como bytes). Por isso usamos printf '%b' aqui para converter essas
# sequencias de escape em quebras de linha reais antes de exibir.
DIALOG_MSG() {
    local title="$1"
    local text="$2"
    dialog --backtitle "$DIALOG_BACKTITLE" \
        --title "$title" \
        --ok-label "OK" \
        --no-collapse \
        --msgbox "$(printf '%b' "$text")" 0 0 \
        < "$CURR_TTY" > "$CURR_TTY" 2> "$CURR_TTY"
}

# --- Wrapper para caixa de progresso (gauge) ---
# Uso: comando_que_gera_numeros | DIALOG_GAUGE "Titulo" "Texto"
# Aqui NAO redirecionamos o stdin para $CURR_TTY: o gauge le os numeros de
# progresso do pipe (stdin original), entao so forcamos a tela (stdout/
# stderr) para o TTY visivel.
DIALOG_GAUGE() {
    local title="$1"
    local text="$2"
    dialog --backtitle "$DIALOG_BACKTITLE" \
        --title "$title" \
        --gauge "$(printf '%b' "$text")" 0 0 0 \
        > "$CURR_TTY" 2> "$CURR_TTY"
}

# --- Wrapper para caixa de progresso CANCELAVEL ---
# Uso: ( trabalho_pesado_que_chama em_check_cancel_key periodicamente ) | DIALOG_GAUGE_CANCELABLE "Titulo" "Texto"
#
# dialog --gauge nao le teclado durante a barra (so numeros via pipe), e
# nao e seguro ter dois processos lendo do mesmo $CURR_TTY ao mesmo tempo
# (risco de roubar bytes um do outro no hardware real). Por isso, quem
# detecta o cancelamento e o proprio PRODUTOR do progresso (o loop que
# roda dentro do "(...)" antes do pipe), chamando em_check_cancel_key em
# cada iteracao - veja essa funcao abaixo. Esta funcao aqui e apenas o
# gauge em si (idêntica ao DIALOG_GAUGE).
DIALOG_GAUGE_CANCELABLE() {
    local title="$1"
    local text="$2"
    dialog --backtitle "$DIALOG_BACKTITLE" \
        --title "$title" \
        --gauge "$(printf '%b' "$text")" 0 0 0 \
        > "$CURR_TTY" 2> "$CURR_TTY"
}

# --- Checa, de forma NAO-BLOQUEANTE, se o usuario pediu cancelamento ---
# Uso dentro de loops de trabalho pesado (scanner, hash, verificacao):
#   if em_check_cancel_key; then echo "1" > "$cancel_flag"; break 2; fi
# Le 1 caractere do $CURR_TTY com timeout quase zero (-t 0). Como isso so
# acontece entre uma iteracao e outra do loop (nao durante o dialog estar
# aguardando algo), nao compete com o gauge pela leitura do TTY.
em_check_cancel_key() {
    local key=""
    IFS= read -rsn1 -t 0.05 key < "$CURR_TTY" 2>/dev/null
    [ "$key" = $'\e' ] || [ "$key" = "q" ] || [ "$key" = "Q" ]
}

# --- Esvazia teclas pendentes no buffer do TTY ---
# Chamar ANTES de iniciar um loop que usa em_check_cancel_key, para evitar
# que uma tecla residual (ex: o Enter/A que confirmou a opcao do menu
# anterior) seja erroneamente interpretada como pedido de cancelamento na
# primeira iteracao do loop.
em_drain_tty_buffer() {
    local key=""
    while IFS= read -rsn1 -t 0 key < "$CURR_TTY" 2>/dev/null; do
        :
    done
}

# --- Wrapper para confirmação sim/não ---
DIALOG_YESNO() {
    local title="$1"
    local text="$2"
    dialog --backtitle "$DIALOG_BACKTITLE" \
        --title "$title" \
        --yes-label "SIM" --no-label "NAO" \
        --yesno "$text" 0 0 \
        < "$CURR_TTY" > "$CURR_TTY" 2> "$CURR_TTY"
    echo $?
}

# --- Log simples para arquivo ---
em_log() {
    local msg="$1"
    mkdir -p "$EM_LOG_DIR"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ${msg}" >> "$SCAN_LOG_FILE"
}

# --- Verifica se uma ferramenta existe no sistema ---
em_has_tool() {
    command -v "$1" >/dev/null 2>&1
}

# --- Retorna o melhor binário 7z disponível (7z, 7za ou 7zr) ---
em_get_7z_bin() {
    for bin in 7z 7za 7zr; do
        if em_has_tool "$bin"; then
            echo "$bin"
            return 0
        fi
    done
    echo ""
    return 1
}

# --- Verifica dependências obrigatórias e avisa se faltar alguma ---
em_check_dependencies() {
    local missing=()
    for tool in "${REQUIRED_TOOLS[@]}"; do
        em_has_tool "$tool" || missing+=("$tool")
    done

    if [ ${#missing[@]} -gt 0 ]; then
        DIALOG_MSG "Dependencias Faltando" \
            "As seguintes ferramentas nao foram encontradas:\n\n$(printf ' - %s\n' "${missing[@]}")\n\nInstale via apt (ex: apt install ${missing[*]}) para usar todas as funcoes."
        return 1
    fi

    if ! em_get_7z_bin >/dev/null && ! em_has_tool 7z; then
        : # 7z é opcional, só afeta compactação .7z; aviso é dado no menu específico
    fi
    return 0
}

# --- Formata bytes para formato legível (KB/MB/GB) ---
em_human_size() {
    local bytes=$1
    if [ "$bytes" -ge 1073741824 ]; then
        awk -v b="$bytes" 'BEGIN { printf "%.2f GB", b/1073741824 }'
    elif [ "$bytes" -ge 1048576 ]; then
        awk -v b="$bytes" 'BEGIN { printf "%.2f MB", b/1048576 }'
    elif [ "$bytes" -ge 1024 ]; then
        awk -v b="$bytes" 'BEGIN { printf "%.2f KB", b/1024 }'
    else
        echo "${bytes} B"
    fi
}

# --- Verifica se uma extensão está na lista de extensões de ROM conhecidas ---
em_is_rom_extension() {
    local ext="${1,,}" # lowercase
    for known in "${ROM_EXTENSIONS[@]}"; do
        [ "$ext" == "$known" ] && return 0
    done
    return 1
}

# --- Verifica se um sistema está na lista de "não compactar" ---
em_is_no_compress_system() {
    local sys="$1"
    for s in "${NO_COMPRESS_SYSTEMS[@]}"; do
        [ "$sys" == "$s" ] && return 0
    done
    return 1
}

# --- Lista os diretórios de sistema existentes dentro de /roms ---
# Retorna apenas os que realmente existem no dispositivo (interseção entre
# KNOWN_SYSTEMS e o que está em ROMS_BASE_DIR), evitando assumir sistemas
# que o usuário não tem instalados.
em_list_existing_systems() {
    local sys
    for sys in "${KNOWN_SYSTEMS[@]}"; do
        [ -d "${ROMS_BASE_DIR}/${sys}" ] && echo "$sys"
    done
}
