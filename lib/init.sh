#!/bin/bash
# =============================================================================
# Emulator Manager - init.sh
# Configurações globais, paths e constantes do projeto
# =============================================================================

# --- Paths principais (ArkOS) ---
ROMS_BASE_DIR="/roms"
EM_BASE_DIR="/opt/system/Tools/Emulator_Manager"
EM_DATA_DIR="${EM_BASE_DIR}/data"
EM_LOG_DIR="${EM_BASE_DIR}/logs"
EM_TMP_DIR="/tmp/emulator_manager"

# --- Arquivos de índice / dados ---
ROM_INDEX_FILE="${EM_DATA_DIR}/rom_index.tsv"      # path \t md5 \t size \t mtime
SCAN_LOG_FILE="${EM_LOG_DIR}/scan_$(date +%Y%m%d_%H%M%S).log"
DUPLICATES_REPORT="${EM_DATA_DIR}/duplicates_report.txt"
CORRUPTED_REPORT="${EM_DATA_DIR}/corrupted_report.txt"
RENAME_REPORT="${EM_DATA_DIR}/rename_report.txt"

# --- Diretório para arquivos .dat No-Intro (opção 3 - Renomear) ---
# Coloque os .dat aqui via SFTP/SSH antes de usar a opção 3.
# O nome do arquivo deve conter o nome do sistema (ex: "gba") para
# detecção automática. Ex: Nintendo_-_Game_Boy_Advance.dat
EM_DATS_DIR="${EM_DATA_DIR}/dats"

# --- Versão ---
# Regra de versionamento:
#   Alteracao em opcao existente  → +0.0.1
#   Nova opcao dentro de modulo   → +0.1.0
#   Novo modulo                   → versao = numero de modulos (ex: 7 modulos = 7.0.0)
EM_VERSION="6.0.0"

# --- Arquivo de registro de última modificação ---
# Formato: DATA HORA|MODULO|DESCRICAO
EM_LAST_CHANGE_FILE="${EM_DATA_DIR}/last_change.txt"

# --- Sistemas conhecidos (pastas dentro de /roms) ---
# Lista usada para varrer e gerar estatísticas. Pode ser expandida.
KNOWN_SYSTEMS=(
    "gba" "gb" "gbc" "nes" "snes" "n64" "psx" "ps2"
    "megadrive" "mastersystem" "gamegear" "sega32x" "segacd"
    "saturn" "neogeo" "arcade" "fba" "mame" "pico8"
    "psp" "nds" "dreamcast" "atari2600" "atarilynx"
)

# --- Sistemas onde NÃO se deve compactar (cores exigem arquivo descomprimido) ---
NO_COMPRESS_SYSTEMS=(
    "psx" "ps2" "saturn" "dreamcast" "psp"
)

# --- Extensões de ROM reconhecidas (para scanner) ---
ROM_EXTENSIONS=(
    "zip" "7z" "gba" "gb" "gbc" "nes" "sfc" "smc" "n64" "z64"
    "bin" "cue" "iso" "chd" "pbp" "nds" "md" "gen" "32x" "sms" "gg"
)

# --- Ferramentas externas necessárias (verificadas em runtime) ---
REQUIRED_TOOLS=("md5sum" "unzip" "zip")
OPTIONAL_TOOLS=("7z" "7za" "7zr")

# --- Cores/diálogo (mesmo padrão visual do Alter_MThemes) ---
DIALOG_BACKTITLE="Emulator Manager v${EM_VERSION}"

# --- TTY visivel usado pelo EmulationStation neste sistema ---
# Mesmo padrao do Alter_MThemes: quando o script e lancado pelo Tools do ES,
# o stdin/stdout/stderr herdados nem sempre apontam para o console fisico
# visivel na tela. Sem forcar explicitamente o dialog a desenhar em
# /dev/tty1, a tela fica preta mesmo com o dialog rodando normalmente.
CURR_TTY="/dev/tty1"

# --- Garantir diretórios essenciais ---
# Como o script agora roda como root (necessario para o gptokeyb fazer o
# grab do /dev/uinput de forma confiavel), garantimos aqui que os
# diretorios e arquivos de dados continuem acessiveis ao usuario normal
# (ark) - sem isso, tudo que o script cria ficaria de propriedade do root,
# dificultando o acesso via SFTP/SSH como usuario comum.
em_init_dirs() {
    mkdir -p "$EM_DATA_DIR" "$EM_LOG_DIR" "$EM_TMP_DIR" "$EM_DATS_DIR"
    chown -R ark:ark "$EM_DATA_DIR" "$EM_LOG_DIR" "$EM_TMP_DIR" "$EM_DATS_DIR" 2>/dev/null || true
    chmod -R 755 "$EM_DATA_DIR" "$EM_LOG_DIR" "$EM_TMP_DIR" "$EM_DATS_DIR" 2>/dev/null || true
}

# --- Registra a última modificação feita pelo usuário ---
# Uso: em_register_change "Modulo 3 - Backup Inteligente" "Exportar para pendrive"
em_register_change() {
    local modulo="$1"
    local descricao="$2"
    local timestamp
    timestamp=$(date '+%d/%m/%Y %H:%M')
    echo "${timestamp}|${modulo}|${descricao}" > "$EM_LAST_CHANGE_FILE"
    chown ark:ark "$EM_LAST_CHANGE_FILE" 2>/dev/null || true
}

# --- Lê a última modificação registrada ---
# Retorna string formatada ou vazio se não houver registro
em_read_last_change() {
    [ -f "$EM_LAST_CHANGE_FILE" ] || return
    local line
    line=$(cat "$EM_LAST_CHANGE_FILE" 2>/dev/null)
    [ -z "$line" ] && return
    local ts modulo descricao
    IFS='|' read -r ts modulo descricao <<< "$line"
    echo "${ts} — ${modulo}"
}

em_init_dirs
