#!/bin/bash
# =============================================================================
# Emulator Manager
# Entry point principal
#
# Estrutura:
#   Emulator_Manager.sh              <- este arquivo
#   lib/init.sh                       <- paths, constantes, config
#   lib/core.sh                        <- funcoes compartilhadas (dialog, NORM_RET, etc)
#   lib/cat_1_rom_management.sh        <- Modulo 1: Gerenciamento de ROMs
#   lib/cat_2_advanced_organization.sh <- Modulo 2: Organizacao Avancada
# =============================================================================

# -----------------------------------------------------------------------------
# Eleva para root, mesmo padrao do Alter_MThemes. Sem isso, o gptokeyb pode
# nao conseguir fazer o "grab" completo do /dev/uinput quando este e o
# primeiro script de Tools executado desde o boot (mesmo com chmod 666) -
# isso faz o D-pad/botoes nao responderem dentro do dialog, embora o
# gptokeyb pareca iniciar normalmente sem erro visivel. Rodar como root
# evita depender de outro script (como o Alter_MThemes) ja ter "destravado"
# o dispositivo de input antes.
# -----------------------------------------------------------------------------
if [ "$(id -u)" -ne 0 ]; then
    exec sudo -- "$0" "$@"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

source "${LIB_DIR}/init.sh"
source "${LIB_DIR}/core.sh"
source "${LIB_DIR}/cat_1_rom_management.sh"
source "${LIB_DIR}/cat_2_advanced_organization.sh"
source "${LIB_DIR}/cat_3_emulator_tools.sh"

# -----------------------------------------------------------------------------
# Limpa o TTY visivel antes de comecar. Mesmo padrao do Alter_MThemes: o
# EmulationStation pode deixar "lixo" do framebuffer anterior, e sem isso a
# primeira tela do dialog pode nao aparecer corretamente.
# -----------------------------------------------------------------------------
printf '\033c' > "$CURR_TTY" 2>/dev/null || true

# -----------------------------------------------------------------------------
# Inicializa o gptokeyb para traduzir os botoes fisicos do R36S (D-pad, A, B)
# em eventos de teclado que o dialog entende. Sem isso, quando o script e
# lancado pelo Tools do EmulationStation, nenhum input fisico chega ao dialog
# e o processo morre imediatamente (tela preta). Mesmo padrao do Alter_MThemes.
#
# IMPORTANTE: usamos pkill -9 (em vez de pkill simples) e um pequeno delay
# antes de iniciar a nova instancia. Sem isso, existe uma race condition:
# se a instancia antiga do gptokeyb ainda nao tiver liberado completamente
# o /dev/uinput no momento em que tentamos abrir uma nova instancia, o
# gptokeyb novo falha silenciosamente (sem nenhum erro visivel) e nenhum
# input fisico chega ao dialog - o menu aparece normalmente na tela, mas
# D-pad/A/B simplesmente nao fazem nada.
# -----------------------------------------------------------------------------
if [ -x /opt/inttools/gptokeyb ]; then
    [[ -e /dev/uinput ]] && chmod 666 /dev/uinput 2>/dev/null || true
    export SDL_GAMECONTROLLERCONFIG_FILE="/opt/inttools/gamecontrollerdb.txt"
    pkill -9 -f "gptokeyb -1 $SCRIPT_NAME" 2>/dev/null || true
    sleep 0.3

    # Usa arquivo de mapeamento específico do Emulator Manager se existir,
    # garantindo que o botão B sempre envie ESC (VOLTAR) em qualquer device.
    # O arquivo fica em lib/ junto com os módulos.
    _EM_GPTK="${LIB_DIR}/keys_emulator_manager.gptk"
    [ ! -f "$_EM_GPTK" ] && _EM_GPTK="/opt/inttools/keys.gptk"

    /opt/inttools/gptokeyb -1 "$SCRIPT_NAME" \
        -c "$_EM_GPTK" >/dev/null 2>&1 &
    # Pequena pausa para garantir que o gptokeyb subiu e fez o grab do
    # dispositivo de input antes do primeiro dialog ser exibido.
    sleep 0.2
fi

# -----------------------------------------------------------------------------
# Menu principal
# Modulos implementados aparecem com nome direto.
# Modulos pendentes aparecem com "(em breve)".
# -----------------------------------------------------------------------------
main_menu() {
    while true; do
        local choice
        choice=$(DIALOG_MENU "Emulator Manager v${EM_VERSION}" "Selecione um modulo:" \
            "1" "Gerenciamento de ROMs" \
            "2" "Organizacao Avancada" \
            "3" "Backup Inteligente" \
            "4" "Ferramentas de Performance (em breve)" \
            "5" "Ferramentas para Emuladores (em breve)" \
            "0" "SAIR")

        local ret=$?
        if [ "$(NORM_RET $ret)" == "VOLTAR" ]; then
            pkill -f "gptokeyb -1 $SCRIPT_NAME" 2>/dev/null || true
            printf '\033c' > "$CURR_TTY" 2>/dev/null || true
            exit 0
        fi

        case "$choice" in
            1) categoria_1 ;;
            2) categoria_2 ;;
            3) categoria_3 ;;
            4) DIALOG_MSG "Ferramentas de Performance" "Modulo ainda nao implementado." ;;
            5) DIALOG_MSG "Ferramentas para Emuladores" "Modulo ainda nao implementado." ;;
            0)
                pkill -f "gptokeyb -1 $SCRIPT_NAME" 2>/dev/null || true
                printf '\033c' > "$CURR_TTY" 2>/dev/null || true
                exit 0
                ;;
        esac
    done
}

main_menu
