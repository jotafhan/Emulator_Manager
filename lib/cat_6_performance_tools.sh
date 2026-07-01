#!/bin/bash
# =============================================================================
# Emulator Manager - cat_6_performance_tools.sh
# Módulo 5 (menu): Ferramentas de Performance
#
# Opções implementadas:
#   1. Nucleo por Sistema          (lista nucleos instalados com nota de compatibilidade)
#   2. Ajustar Configuracoes       (aplica configs testadas por emulador/sistema)
#   3. Perfil de Energia           (Economia / Balanceado / Maximo desempenho)
#   4. Cache de Shaders            (configura cache para sistemas pesados)
#   5. Restaurar Configuracoes Originais
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/init.sh"
source "${SCRIPT_DIR}/core.sh"

# =============================================================================
# CONSTANTES DO MÓDULO
# =============================================================================

# Arquivos de configuração por emulador
EM6_RA_CFG="/home/ark/.config/retroarch/retroarch.cfg"
EM6_RA32_CFG="/home/ark/.config/retroarch32/retroarch.cfg"
EM6_PPSSPP_CFG="/opt/ppsspp/PSP/SYSTEM/ppsspp.ini"
EM6_MUPEN_CFG="/home/ark/.config/mupen64plus/mupen64plus.cfg"

# Diretório de backups de performance
EM6_BACKUP_DIR="${EM_DATA_DIR}/backups/performance"

# =============================================================================
# MAPA DE NÚCLEOS RECOMENDADOS POR SISTEMA
# Baseado em compatibilidade/performance conhecida para R36S (aarch64)
# =============================================================================
declare -A EM6_CORE_NOTES
EM6_CORE_NOTES["gba"]="mgba (mais preciso) | gpsp (mais rapido, pode ter bugs)"
EM6_CORE_NOTES["gb"]="gambatte (recomendado) | sameboy (mais preciso, mais pesado)"
EM6_CORE_NOTES["gbc"]="gambatte (recomendado) | sameboy (mais preciso, mais pesado)"
EM6_CORE_NOTES["nes"]="fceumm (recomendado) | nestopia (mais preciso, mais pesado)"
EM6_CORE_NOTES["snes"]="snes9x (recomendado) | bsnes (muito pesado para R36S)"
EM6_CORE_NOTES["n64"]="mupen64plus_next (recomendado) | parallel_n64 (mais pesado)"
EM6_CORE_NOTES["psx"]="pcsx_rearmed (recomendado) | duckstation (mais pesado)"
EM6_CORE_NOTES["megadrive"]="genesis_plus_gx (recomendado) | picodrive (alternativa rapida)"
EM6_CORE_NOTES["mastersystem"]="genesis_plus_gx (recomendado)"
EM6_CORE_NOTES["gamegear"]="genesis_plus_gx (recomendado)"
EM6_CORE_NOTES["sega32x"]="picodrive (unico suportado)"
EM6_CORE_NOTES["segacd"]="genesis_plus_gx (recomendado) | picodrive (alternativa)"
EM6_CORE_NOTES["nds"]="desmume (compativel) | melonds (mais pesado)"
EM6_CORE_NOTES["psp"]="ppsspp standalone (recomendado)"
EM6_CORE_NOTES["neogeo"]="fbalpha2012 (leve) | fbneo (mais completo, mais pesado)"
EM6_CORE_NOTES["arcade"]="mame2003_plus (recomendado) | fbneo (alternativa)"
EM6_CORE_NOTES["dreamcast"]="flycast standalone (recomendado)"
EM6_CORE_NOTES["saturn"]="beetle_saturn (pesado) | yabause (mais leve)"
EM6_CORE_NOTES["atari2600"]="stella2014 (recomendado)"
EM6_CORE_NOTES["atarilynx"]="handy (recomendado)"

# =============================================================================
# PERFIS DE CONFIGURAÇÃO RETROARCH
# Cada perfil define pares chave=valor para o retroarch.cfg
# =============================================================================

# Perfil: Economia de Bateria
declare -A EM6_PROFILE_ECONOMY
EM6_PROFILE_ECONOMY["video_vsync"]="true"
EM6_PROFILE_ECONOMY["video_max_swapchain_images"]="2"
EM6_PROFILE_ECONOMY["video_threaded"]="false"
EM6_PROFILE_ECONOMY["audio_latency"]="128"
EM6_PROFILE_ECONOMY["video_frame_delay"]="8"
EM6_PROFILE_ECONOMY["fastforward_ratio"]="2.0"
EM6_PROFILE_ECONOMY["video_hard_sync"]="true"
EM6_PROFILE_ECONOMY["video_hard_sync_frames"]="3"

# Perfil: Balanceado
declare -A EM6_PROFILE_BALANCED
EM6_PROFILE_BALANCED["video_vsync"]="true"
EM6_PROFILE_BALANCED["video_max_swapchain_images"]="3"
EM6_PROFILE_BALANCED["video_threaded"]="true"
EM6_PROFILE_BALANCED["audio_latency"]="64"
EM6_PROFILE_BALANCED["video_frame_delay"]="4"
EM6_PROFILE_BALANCED["fastforward_ratio"]="3.0"
EM6_PROFILE_BALANCED["video_hard_sync"]="false"
EM6_PROFILE_BALANCED["video_hard_sync_frames"]="0"

# Perfil: Máximo Desempenho
declare -A EM6_PROFILE_MAX
EM6_PROFILE_MAX["video_vsync"]="false"
EM6_PROFILE_MAX["video_max_swapchain_images"]="3"
EM6_PROFILE_MAX["video_threaded"]="true"
EM6_PROFILE_MAX["audio_latency"]="32"
EM6_PROFILE_MAX["video_frame_delay"]="0"
EM6_PROFILE_MAX["fastforward_ratio"]="0.0"
EM6_PROFILE_MAX["video_hard_sync"]="false"
EM6_PROFILE_MAX["video_hard_sync_frames"]="0"

# =============================================================================
# HELPERS INTERNOS
# =============================================================================

em6_init_dirs() {
    mkdir -p "$EM6_BACKUP_DIR"
    chown ark:ark "$EM6_BACKUP_DIR" 2>/dev/null || true
}

# Faz backup de um arquivo de configuração antes de modificar
# Uso: em6_backup_cfg "/caminho/arquivo.cfg" "nome_descritivo"
em6_backup_cfg() {
    local cfg_file="$1"
    local label="$2"
    [ -f "$cfg_file" ] || return 1
    local timestamp; timestamp=$(date '+%Y%m%d_%H%M%S')
    local dest="${EM6_BACKUP_DIR}/${label}_${timestamp}.bak"
    cp "$cfg_file" "$dest" 2>/dev/null && chown ark:ark "$dest" 2>/dev/null || true
    echo "$dest"
}

# Lê o valor atual de uma chave num arquivo .cfg/.ini do RetroArch
# Suporta formato: chave = "valor" ou chave = valor
em6_cfg_get() {
    local file="$1"
    local key="$2"
    [ -f "$file" ] || return
    grep -m1 "^${key} \?=" "$file" 2>/dev/null \
        | sed 's/^[^=]*= *"\?//;s/"\?\s*$//'
}

# Define ou adiciona um valor num arquivo .cfg do RetroArch
# Suporta formato: chave = "valor"
em6_cfg_set() {
    local file="$1"
    local key="$2"
    local value="$3"
    [ -f "$file" ] || return 1

    if grep -q "^${key} \?=" "$file" 2>/dev/null; then
        # Substitui valor existente (com ou sem aspas)
        sed -i "s|^${key} *=.*|${key} = \"${value}\"|" "$file" 2>/dev/null
    else
        # Adiciona no final
        echo "${key} = \"${value}\"" >> "$file"
    fi
}

# Aplica um conjunto de chave=valor a um arquivo .cfg
# Uso: em6_apply_profile "/arquivo.cfg" "NOME_PROFILE"
em6_apply_profile() {
    local cfg_file="$1"
    local profile_name="$2"
    local key

    case "$profile_name" in
        ECONOMY)
            for key in "${!EM6_PROFILE_ECONOMY[@]}"; do
                em6_cfg_set "$cfg_file" "$key" "${EM6_PROFILE_ECONOMY[$key]}"
            done
            ;;
        BALANCED)
            for key in "${!EM6_PROFILE_BALANCED[@]}"; do
                em6_cfg_set "$cfg_file" "$key" "${EM6_PROFILE_BALANCED[$key]}"
            done
            ;;
        MAX)
            for key in "${!EM6_PROFILE_MAX[@]}"; do
                em6_cfg_set "$cfg_file" "$key" "${EM6_PROFILE_MAX[$key]}"
            done
            ;;
    esac
}

# =============================================================================
# 1. NÚCLEO POR SISTEMA
# Lista núcleos instalados com nota de compatibilidade/performance
# =============================================================================
em6_core_by_system() {
    local systems
    mapfile -t systems < <(em_list_existing_systems)

    if [ "${#systems[@]}" -eq 0 ]; then
        DIALOG_MSG "Nucleo por Sistema" "Nenhum sistema encontrado em ${ROMS_BASE_DIR}."
        return
    fi

    local menu_items=()
    local sys
    for sys in "${systems[@]}"; do
        [ -n "${EM6_CORE_NOTES[$sys]}" ] && \
            menu_items+=("$sys" "$sys")
    done
    menu_items+=("TODOS" "Ver recomendacao para todos os sistemas")

    local choice
    choice=$(DIALOG_MENU "Nucleo por Sistema" \
        "Escolha o sistema para ver o nucleo recomendado:" "${menu_items[@]}")
    [ "$(NORM_RET $?)" == "VOLTAR" ] && return

    local report=""
    if [ "$choice" == "TODOS" ]; then
        local sys
        for sys in "${systems[@]}"; do
            local note="${EM6_CORE_NOTES[$sys]:-Sem recomendacao especifica}"
            report+="${sys}:\n  ${note}\n\n"
        done
        DIALOG_MSG "Nucleos Recomendados" "$report"
    else
        local note="${EM6_CORE_NOTES[$choice]:-Sem recomendacao especifica para este sistema}"
        DIALOG_MSG "Nucleo — ${choice}" \
            "Sistema: ${choice}\n\nNucleos recomendados:\n  ${note}\n\nNota: o melhor nucleo depende do jogo especifico.\nTeste ambas as opcoes se tiver problemas de performance."
    fi
}

# =============================================================================
# 2. AJUSTAR CONFIGURAÇÕES POR EMULADOR
# Aplica configurações testadas específicas por emulador/sistema
# =============================================================================
em6_adjust_settings() {
    local menu_items=(
        "retroarch"   "RetroArch (64-bit)"
        "retroarch32" "RetroArch32 (32-bit)"
        "ppsspp"      "PPSSPP (PSP)"
        "mupen64plus" "Mupen64Plus (N64)"
    )

    local choice
    choice=$(DIALOG_MENU "Ajustar Configuracoes" \
        "Escolha o emulador para aplicar configuracoes otimizadas:" \
        "${menu_items[@]}")
    [ "$(NORM_RET $?)" == "VOLTAR" ] && return

    case "$choice" in
        retroarch|retroarch32)
            em6_adjust_retroarch "$choice"
            ;;
        ppsspp)
            em6_adjust_ppsspp
            ;;
        mupen64plus)
            em6_adjust_mupen
            ;;
    esac
}

em6_adjust_retroarch() {
    local target="$1"
    local cfg_file
    [ "$target" == "retroarch" ] && cfg_file="$EM6_RA_CFG" || cfg_file="$EM6_RA32_CFG"

    if [ ! -f "$cfg_file" ]; then
        DIALOG_MSG "Ajustar RetroArch" \
            "Arquivo de configuracao nao encontrado:\n${cfg_file}"
        return
    fi

    local preview
    preview="video_vsync = true\nvideo_threaded = true\naudio_latency = 64\nvideo_frame_delay = 4\nvideo_smooth = false\nvideo_scale_integer = false\nrewind_enable = false\nvideo_shader_enable = false"

    local confirm
    confirm=$(DIALOG_YESNO "Ajustar RetroArch" \
        "Aplicar configuracoes otimizadas para ${target}:\n\n${preview}\n\nUm backup sera feito antes de qualquer alteracao.\n\nDeseja continuar?")
    [ "$confirm" -ne 0 ] && return

    em6_init_dirs
    local backup
    backup=$(em6_backup_cfg "$cfg_file" "$target")

    em6_cfg_set "$cfg_file" "video_vsync"           "true"
    em6_cfg_set "$cfg_file" "video_threaded"        "true"
    em6_cfg_set "$cfg_file" "audio_latency"         "64"
    em6_cfg_set "$cfg_file" "video_frame_delay"     "4"
    em6_cfg_set "$cfg_file" "video_smooth"          "false"
    em6_cfg_set "$cfg_file" "video_scale_integer"   "false"
    em6_cfg_set "$cfg_file" "rewind_enable"         "false"
    em6_cfg_set "$cfg_file" "video_shader_enable"   "false"
    em6_cfg_set "$cfg_file" "video_max_swapchain_images" "3"
    em6_cfg_set "$cfg_file" "audio_sync"            "true"
    em6_cfg_set "$cfg_file" "menu_throttle_framerate" "true"
    em6_cfg_set "$cfg_file" "audio_resampler"       "sinc"

    DIALOG_MSG "Ajustar RetroArch" \
        "Configuracoes aplicadas com sucesso em:\n${cfg_file}\n\nBackup salvo em:\n${backup}"
}

em6_adjust_ppsspp() {
    if [ ! -f "$EM6_PPSSPP_CFG" ]; then
        DIALOG_MSG "Ajustar PPSSPP" \
            "Arquivo de configuracao nao encontrado:\n${EM6_PPSSPP_CFG}\n\nAbra o PPSSPP ao menos uma vez para gerar o arquivo."
        return
    fi

    local preview
    preview="FrameSkip = 0\nFrameSkipType = 0\nRenderingMode = 1\nHardwareTransform = True\nSoftwareSkinning = True\nTextureScalingLevel = 1\nVSync = False\nBlockTransferGPU = True"

    local confirm
    confirm=$(DIALOG_YESNO "Ajustar PPSSPP" \
        "Aplicar configuracoes otimizadas para PPSSPP (PSP):\n\n${preview}\n\nUm backup sera feito antes.\nDeseja continuar?")
    [ "$confirm" -ne 0 ] && return

    em6_init_dirs
    local backup
    backup=$(em6_backup_cfg "$EM6_PPSSPP_CFG" "ppsspp")

    # PPSSPP usa formato .ini com sections [Graphics], [General], etc.
    # Função auxiliar para ini com seção
    local file="$EM6_PPSSPP_CFG"

    # [Graphics]
    em6_ini_set "$file" "Graphics" "FrameSkip"             "0"
    em6_ini_set "$file" "Graphics" "FrameSkipType"         "0"
    em6_ini_set "$file" "Graphics" "RenderingMode"         "1"
    em6_ini_set "$file" "Graphics" "HardwareTransform"     "True"
    em6_ini_set "$file" "Graphics" "SoftwareSkinning"      "True"
    em6_ini_set "$file" "Graphics" "TextureScalingLevel"   "1"
    em6_ini_set "$file" "Graphics" "VSync"                 "False"
    em6_ini_set "$file" "Graphics" "BlockTransferGPU"      "True"
    em6_ini_set "$file" "Graphics" "AnisotropyLevel"       "0"
    em6_ini_set "$file" "Graphics" "HighQualityDepth"      "True"

    # [Sound]
    em6_ini_set "$file" "Sound" "AudioLatency"  "1"

    # [General]
    em6_ini_set "$file" "General" "FastMemory"  "True"
    em6_ini_set "$file" "General" "CPUCore"     "1"

    DIALOG_MSG "Ajustar PPSSPP" \
        "Configuracoes aplicadas em:\n${EM6_PPSSPP_CFG}\n\nBackup salvo em:\n${backup}"
}

em6_adjust_mupen() {
    if [ ! -f "$EM6_MUPEN_CFG" ]; then
        DIALOG_MSG "Ajustar Mupen64Plus" \
            "Arquivo de configuracao nao encontrado:\n${EM6_MUPEN_CFG}\n\nAbra o Mupen64Plus ao menos uma vez para gerar o arquivo."
        return
    fi

    local preview
    preview="ScreenWidth = 640\nScreenHeight = 480\nEnableFullscreen = True\nEnableFog = False\nEnableEdgeAA = False\nAnisotropicFiltering = 0"

    local confirm
    confirm=$(DIALOG_YESNO "Ajustar Mupen64Plus" \
        "Aplicar configuracoes otimizadas para Mupen64Plus (N64):\n\n${preview}\n\nUm backup sera feito antes.\nDeseja continuar?")
    [ "$confirm" -ne 0 ] && return

    em6_init_dirs
    local backup
    backup=$(em6_backup_cfg "$EM6_MUPEN_CFG" "mupen64plus")

    em6_cfg_set "$EM6_MUPEN_CFG" "ScreenWidth"         "640"
    em6_cfg_set "$EM6_MUPEN_CFG" "ScreenHeight"        "480"
    em6_cfg_set "$EM6_MUPEN_CFG" "EnableFullscreen"    "True"
    em6_cfg_set "$EM6_MUPEN_CFG" "EnableFog"           "False"
    em6_cfg_set "$EM6_MUPEN_CFG" "EnableEdgeAA"        "False"
    em6_cfg_set "$EM6_MUPEN_CFG" "AnisotropicFiltering" "0"

    DIALOG_MSG "Ajustar Mupen64Plus" \
        "Configuracoes aplicadas em:\n${EM6_MUPEN_CFG}\n\nBackup salvo em:\n${backup}"
}

# Helper: define chave em arquivo .ini com seções [Section]
em6_ini_set() {
    local file="$1"
    local section="$2"
    local key="$3"
    local value="$4"

    # Verifica se a chave já existe na seção
    # Usa python3 para manipulação segura de .ini
    python3 - "$file" "$section" "$key" "$value" <<'PYEOF' 2>/dev/null
import sys
file_path, section, key, value = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]

try:
    with open(file_path, 'r', encoding='utf-8', errors='replace') as f:
        lines = f.readlines()
except Exception:
    sys.exit(1)

in_section = False
key_found = False
new_lines = []

for line in lines:
    stripped = line.strip()
    if stripped.startswith('['):
        if key_found is False and in_section and not key_found:
            pass
        in_section = stripped.lower() == f'[{section.lower()}]'
    if in_section and stripped.lower().startswith(key.lower() + ' =') or \
       (in_section and stripped.lower().startswith(key.lower() + '=')):
        line = f'{key} = {value}\n'
        key_found = True
    new_lines.append(line)

# Se a chave não foi encontrada, adiciona na seção correta
if not key_found:
    in_section = False
    final_lines = []
    for line in new_lines:
        stripped = line.strip()
        if stripped.startswith('['):
            if in_section:
                final_lines.append(f'{key} = {value}\n')
                key_found = True
            in_section = stripped.lower() == f'[{section.lower()}]'
        final_lines.append(line)
    if in_section and not key_found:
        final_lines.append(f'{key} = {value}\n')
    new_lines = final_lines

with open(file_path, 'w', encoding='utf-8') as f:
    f.writelines(new_lines)
PYEOF
}

# =============================================================================
# 3. PERFIL DE ENERGIA
# Aplica perfil Economia / Balanceado / Máximo no RetroArch
# =============================================================================
em6_energy_profile() {
    local menu_items=(
        "1" "Economia de Bateria   (vsync, sync forte, baixa latencia audio)"
        "2" "Balanceado            (configuracao padrao recomendada)"
        "3" "Maximo Desempenho     (vsync off, threaded, latencia minima)"
    )

    local choice
    choice=$(DIALOG_MENU "Perfil de Energia" \
        "Escolha o perfil de desempenho para o RetroArch:" \
        "${menu_items[@]}")
    [ "$(NORM_RET $?)" == "VOLTAR" ] && return

    local profile_name label
    case "$choice" in
        1) profile_name="ECONOMY"; label="Economia de Bateria" ;;
        2) profile_name="BALANCED"; label="Balanceado" ;;
        3) profile_name="MAX";     label="Maximo Desempenho" ;;
        *) return ;;
    esac

    # Mostra o que será aplicado
    local preview=""
    case "$profile_name" in
        ECONOMY)
            preview="video_vsync = true\nvideo_threaded = false\naudio_latency = 128\nvideo_frame_delay = 8\nvideo_hard_sync = true"
            ;;
        BALANCED)
            preview="video_vsync = true\nvideo_threaded = true\naudio_latency = 64\nvideo_frame_delay = 4\nvideo_hard_sync = false"
            ;;
        MAX)
            preview="video_vsync = false\nvideo_threaded = true\naudio_latency = 32\nvideo_frame_delay = 0\nvideo_hard_sync = false"
            ;;
    esac

    # Escolhe qual RetroArch aplicar
    local ra_choice
    ra_choice=$(DIALOG_MENU "Perfil de Energia" \
        "Aplicar perfil '${label}' em qual RetroArch?" \
        "1" "RetroArch (64-bit)" \
        "2" "RetroArch32 (32-bit)" \
        "3" "Ambos")
    [ "$(NORM_RET $?)" == "VOLTAR" ] && return

    local confirm
    confirm=$(DIALOG_YESNO "Perfil: ${label}" \
        "Configuracoes que serao aplicadas:\n\n${preview}\n\nUm backup sera feito antes.\nDeseja continuar?")
    [ "$confirm" -ne 0 ] && return

    em6_init_dirs
    local applied=""

    if [ "$ra_choice" == "1" ] || [ "$ra_choice" == "3" ]; then
        if [ -f "$EM6_RA_CFG" ]; then
            em6_backup_cfg "$EM6_RA_CFG" "retroarch_profile" >/dev/null
            em6_apply_profile "$EM6_RA_CFG" "$profile_name"
            applied+="RetroArch (64-bit)\n"
        fi
    fi
    if [ "$ra_choice" == "2" ] || [ "$ra_choice" == "3" ]; then
        if [ -f "$EM6_RA32_CFG" ]; then
            em6_backup_cfg "$EM6_RA32_CFG" "retroarch32_profile" >/dev/null
            em6_apply_profile "$EM6_RA32_CFG" "$profile_name"
            applied+="RetroArch32 (32-bit)\n"
        fi
    fi

    DIALOG_MSG "Perfil de Energia" \
        "Perfil '${label}' aplicado com sucesso em:\n\n${applied}\nBackup salvo em:\n${EM6_BACKUP_DIR}/"
}

# =============================================================================
# 4. CACHE DE SHADERS
# Configura cache de shaders e disco para sistemas pesados no RetroArch
# =============================================================================
em6_shader_cache() {
    local menu_items=(
        "1" "Ativar cache de shaders    (recomendado para N64, PSX, PSP)"
        "2" "Limpar cache de shaders    (resolver glitches visuais)"
        "3" "Ver status do cache"
    )

    local choice
    choice=$(DIALOG_MENU "Cache de Shaders" \
        "Gerenciar cache de shaders do RetroArch:" \
        "${menu_items[@]}")
    [ "$(NORM_RET $?)" == "VOLTAR" ] && return

    local shader_cache_dir="/home/ark/.config/retroarch/shaders/presets/cache"
    local shader_cache_dir32="/home/ark/.config/retroarch32/shaders/presets/cache"
    local disk_cache_dir="/home/ark/.config/retroarch/cache"

    case "$choice" in
        1)
            # Ativa cache de shaders e configura diretório
            if [ ! -f "$EM6_RA_CFG" ] && [ ! -f "$EM6_RA32_CFG" ]; then
                DIALOG_MSG "Cache de Shaders" \
                    "Nenhum arquivo de configuracao do RetroArch encontrado."
                return
            fi

            local confirm
            confirm=$(DIALOG_YESNO "Ativar Cache de Shaders" \
                "Isso ira ativar:\n\n- video_shader_cache_type = 1 (GPU cache)\n- cache_directory configurado\n- video_shader_enable = false (ate shaders serem escolhidos)\n\nRecomendado para N64, PSX, PSP, Dreamcast.\nUm backup sera feito antes.\n\nDeseja continuar?")
            [ "$confirm" -ne 0 ] && return

            em6_init_dirs
            mkdir -p "$shader_cache_dir" "$shader_cache_dir32" "$disk_cache_dir" 2>/dev/null
            chown -R ark:ark "$shader_cache_dir" "$shader_cache_dir32" "$disk_cache_dir" 2>/dev/null || true

            if [ -f "$EM6_RA_CFG" ]; then
                em6_backup_cfg "$EM6_RA_CFG" "retroarch_cache" >/dev/null
                em6_cfg_set "$EM6_RA_CFG" "video_shader_cache_type"   "1"
                em6_cfg_set "$EM6_RA_CFG" "cache_directory"           "$disk_cache_dir"
                em6_cfg_set "$EM6_RA_CFG" "video_shader_dir"          "/home/ark/.config/retroarch/shaders"
            fi
            if [ -f "$EM6_RA32_CFG" ]; then
                em6_backup_cfg "$EM6_RA32_CFG" "retroarch32_cache" >/dev/null
                em6_cfg_set "$EM6_RA32_CFG" "video_shader_cache_type"  "1"
                em6_cfg_set "$EM6_RA32_CFG" "cache_directory"          "$disk_cache_dir"
                em6_cfg_set "$EM6_RA32_CFG" "video_shader_dir"         "/home/ark/.config/retroarch32/shaders"
            fi

            DIALOG_MSG "Cache de Shaders" \
                "Cache de shaders ativado com sucesso.\n\nDiretorio de cache:\n${disk_cache_dir}\n\nOs shaders sao compilados na primeira execucao de cada jogo e reutilizados automaticamente depois."
            ;;

        2)
            # Limpa o cache
            local cache_size=""
            [ -d "$shader_cache_dir" ]   && cache_size+="$(du -sh "$shader_cache_dir" 2>/dev/null | cut -f1) (RA64)\n"
            [ -d "$shader_cache_dir32" ] && cache_size+="$(du -sh "$shader_cache_dir32" 2>/dev/null | cut -f1) (RA32)\n"
            [ -d "$disk_cache_dir" ]     && cache_size+="$(du -sh "$disk_cache_dir" 2>/dev/null | cut -f1) (disco)\n"
            [ -z "$cache_size" ] && cache_size="Nenhum cache encontrado."

            local confirm
            confirm=$(DIALOG_YESNO "Limpar Cache de Shaders" \
                "Tamanho atual do cache:\n${cache_size}\nIsso apagara o cache compilado. Os shaders serao recompilados na proxima execucao de cada jogo.\n\nDeseja continuar?")
            [ "$confirm" -ne 0 ] && return

            rm -rf "${shader_cache_dir:?}"/* "${shader_cache_dir32:?}"/* "${disk_cache_dir:?}"/* 2>/dev/null
            DIALOG_MSG "Cache de Shaders" "Cache limpo com sucesso.\n\nOs shaders serao recompilados na proxima execucao de cada jogo."
            ;;

        3)
            # Status do cache
            local status=""
            if [ -d "$shader_cache_dir" ]; then
                local count; count=$(find "$shader_cache_dir" -type f 2>/dev/null | wc -l)
                local size; size=$(du -sh "$shader_cache_dir" 2>/dev/null | cut -f1)
                status+="RetroArch (64-bit):\n  ${count} arquivo(s) — ${size}\n\n"
            else
                status+="RetroArch (64-bit): sem cache\n\n"
            fi
            if [ -d "$shader_cache_dir32" ]; then
                local count; count=$(find "$shader_cache_dir32" -type f 2>/dev/null | wc -l)
                local size; size=$(du -sh "$shader_cache_dir32" 2>/dev/null | cut -f1)
                status+="RetroArch32 (32-bit):\n  ${count} arquivo(s) — ${size}\n\n"
            else
                status+="RetroArch32 (32-bit): sem cache\n\n"
            fi
            if [ -d "$disk_cache_dir" ]; then
                local size; size=$(du -sh "$disk_cache_dir" 2>/dev/null | cut -f1)
                status+="Cache de disco: ${size}"
            fi
            DIALOG_MSG "Status do Cache" "$status"
            ;;
    esac
}

# =============================================================================
# 5. RESTAURAR CONFIGURAÇÕES ORIGINAIS
# Lista backups feitos por este módulo e restaura
# =============================================================================
em6_restore_original() {
    em6_init_dirs

    local backup_files=()
    local f
    while IFS= read -r -d '' f; do
        backup_files+=("$f")
    done < <(find "$EM6_BACKUP_DIR" -maxdepth 1 -name "*.bak" -print0 2>/dev/null | sort -rz)

    if [ "${#backup_files[@]}" -eq 0 ]; then
        DIALOG_MSG "Restaurar Configuracoes" \
            "Nenhum backup de configuracao encontrado em:\n${EM6_BACKUP_DIR}\n\nOs backups sao criados automaticamente quando voce aplica qualquer configuracao neste modulo."
        return
    fi

    local menu_items=()
    for f in "${backup_files[@]}"; do
        local fname; fname=$(basename "$f")
        local fdate; fdate=$(stat -c%y "$f" 2>/dev/null | cut -d'.' -f1)
        menu_items+=("$fname" "${fdate}")
    done

    local choice
    choice=$(DIALOG_MENU "Restaurar Configuracoes" \
        "Escolha o backup para restaurar:" "${menu_items[@]}")
    [ "$(NORM_RET $?)" == "VOLTAR" ] && return

    local src="${EM6_BACKUP_DIR}/${choice}"

    # Determina o destino pelo nome do backup
    local dest=""
    case "$choice" in
        retroarch_*)    dest="$EM6_RA_CFG" ;;
        retroarch32_*)  dest="$EM6_RA32_CFG" ;;
        ppsspp_*)       dest="$EM6_PPSSPP_CFG" ;;
        mupen64plus_*)  dest="$EM6_MUPEN_CFG" ;;
        *)
            DIALOG_MSG "Restaurar" \
                "Nao foi possivel determinar o destino para:\n${choice}\n\nNome de backup nao reconhecido."
            return
            ;;
    esac

    local confirm
    confirm=$(DIALOG_YESNO "Restaurar Configuracoes" \
        "Backup: ${choice}\nDestino: ${dest}\n\nO arquivo atual sera substituido pelo backup.\n\nDeseja continuar?")
    [ "$confirm" -ne 0 ] && return

    if cp "$src" "$dest" 2>/dev/null; then
        chown ark:ark "$dest" 2>/dev/null || true
        DIALOG_MSG "Restaurar Configuracoes" \
            "Configuracao restaurada com sucesso.\n\nArquivo restaurado:\n${dest}\n\nReinicie o emulador para aplicar as mudancas."
    else
        DIALOG_MSG "Erro" \
            "Nao foi possivel restaurar o backup.\n\nVerifique as permissoes do arquivo de destino."
    fi
}

# =============================================================================
# MENU PRINCIPAL DO MÓDULO 5 (menu item 5)
# =============================================================================
categoria_6() {
    while true; do
        local choice
        choice=$(DIALOG_MENU "Ferramentas de Performance" "Selecione uma opcao:" \
            "1" "Nucleo por Sistema" \
            "2" "Ajustar Configuracoes por Emulador" \
            "3" "Perfil de Energia" \
            "4" "Cache de Shaders" \
            "5" "Restaurar Configuracoes Originais" \
            "0" "VOLTAR")

        local ret=$?
        [ "$(NORM_RET $ret)" == "VOLTAR" ] && return

        case "$choice" in
            1) em6_core_by_system ;;
            2) em6_adjust_settings ;;
            3) em6_energy_profile ;;
            4) em6_shader_cache ;;
            5) em6_restore_original ;;
            0) return ;;
        esac
    done
}

# Permite executar este arquivo isoladamente para testes
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    categoria_6
fi
