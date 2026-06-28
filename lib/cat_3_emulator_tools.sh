#!/bin/bash
# =============================================================================
# Emulator Manager - cat_3_emulator_tools.sh
# Módulo 3: Backup Inteligente
#
# Opções implementadas (todas offline):
#   1. Backup configuração emulador individual
#   2. Backup configuração todos os emuladores
#   3. Importar configuração personalizada  (mostra tamanho de cada backup)
#   4. Apagar backup selecionado
#   5. Exportar backup para pendrive
#   6. Restaurar configurações padrão geral
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/init.sh"
source "${SCRIPT_DIR}/core.sh"

# =============================================================================
# MAPA DE EMULADORES E SEUS DIRETÓRIOS DE CONFIGURAÇÃO
# Múltiplas pastas separadas por : para emuladores com config em mais de um lugar.
# =============================================================================
declare -A EMULATOR_DIRS
EMULATOR_DIRS["RetroArch"]="/home/ark/.config/retroarch"
EMULATOR_DIRS["RetroArch32"]="/home/ark/.config/retroarch32"
EMULATOR_DIRS["PPSSPP"]="/opt/ppsspp"
EMULATOR_DIRS["Mupen64Plus"]="/home/ark/.config/mupen64plus:/opt/mupen64plus"
EMULATOR_DIRS["DuckStation"]="/home/ark/.config/duckstation"
EMULATOR_DIRS["Flycast"]="/home/ark/.config/flycast"
EMULATOR_DIRS["ScummVM"]="/home/ark/.config/scummvm"
EMULATOR_DIRS["GZDoom"]="/home/ark/.config/gzdoom"
EMULATOR_DIRS["ECWolf"]="/home/ark/.config/ecwolf"

EMULATOR_ORDER=(
    "RetroArch" "RetroArch32" "PPSSPP" "Mupen64Plus"
    "DuckStation" "Flycast" "ScummVM" "GZDoom" "ECWolf"
)

EM_BACKUP_DIR="${EM_DATA_DIR}/backups"

# =============================================================================
# HELPERS INTERNOS
# =============================================================================

em3_init_backup_dir() {
    mkdir -p "$EM_BACKUP_DIR"
    chown ark:ark "$EM_BACKUP_DIR" 2>/dev/null || true
    chmod 755 "$EM_BACKUP_DIR" 2>/dev/null || true
}

# Retorna os diretórios de configuração de um emulador que realmente existem
em3_get_existing_dirs() {
    local emu="$1"
    local dirs="${EMULATOR_DIRS[$emu]}"
    [ -z "$dirs" ] && return
    local IFS=':'
    local d
    for d in $dirs; do
        [ -d "$d" ] && echo "$d"
    done
}

# Lista emuladores que têm ao menos uma pasta de config existente
em3_list_available_emulators() {
    local emu
    for emu in "${EMULATOR_ORDER[@]}"; do
        local existing
        existing=$(em3_get_existing_dirs "$emu")
        [ -n "$existing" ] && echo "$emu"
    done
}

# Tamanho legível das pastas de config de um emulador
em3_config_size() {
    local emu="$1"
    local total=0
    local d
    while IFS= read -r d; do
        local s
        s=$(du -sb "$d" 2>/dev/null | cut -f1)
        total=$(( total + ${s:-0} ))
    done < <(em3_get_existing_dirs "$emu")
    em_human_size "$total"
}

# Faz backup de um emulador para um arquivo .tar.gz
em3_backup_emulator() {
    local emu="$1"
    local dest="$2"
    local dirs
    mapfile -t dirs < <(em3_get_existing_dirs "$emu")
    [ "${#dirs[@]}" -eq 0 ] && return 1
    tar -czf "$dest" --ignore-failed-read "${dirs[@]}" 2>/dev/null
}

# Detecta pendrives/dispositivos montados em /media ou /mnt
# Retorna lista de pontos de montagem com espaço disponível
em3_find_usb_mounts() {
    local mount_point
    # Verifica /media (automount) e /mnt (manual)
    for base in /media /media/ark /mnt; do
        [ -d "$base" ] || continue
        while IFS= read -r -d '' mount_point; do
            # Ignora a pasta base em si e pontos sem espaço gravável
            [ "$mount_point" = "$base" ] && continue
            [ -w "$mount_point" ] && echo "$mount_point"
        done < <(find "$base" -maxdepth 1 -mindepth 1 -type d -print0 2>/dev/null)
    done
    # Também verifica montagens ativas via /proc/mounts para dispositivos sd*/usb*
    while IFS=' ' read -r dev mount rest; do
        echo "$dev" | grep -qE '^/dev/sd[b-z]|^/dev/usb' || continue
        [ -w "$mount" ] && echo "$mount"
    done < /proc/mounts 2>/dev/null
}

# =============================================================================
# 1. BACKUP CONFIGURAÇÃO — EMULADOR INDIVIDUAL
# =============================================================================
em3_backup_individual() {
    em3_init_backup_dir

    local available=()
    mapfile -t available < <(em3_list_available_emulators)

    if [ "${#available[@]}" -eq 0 ]; then
        DIALOG_MSG "Backup Individual" \
            "Nenhuma pasta de configuracao encontrada para os emuladores conhecidos."
        return
    fi

    local menu_items=()
    local emu
    for emu in "${available[@]}"; do
        local size
        size=$(em3_config_size "$emu")
        menu_items+=("$emu" "${emu} (${size})")
    done

    local choice
    choice=$(DIALOG_MENU "Backup Individual" \
        "Escolha o emulador para fazer backup:" "${menu_items[@]}")
    [ "$(NORM_RET $?)" == "VOLTAR" ] && return

    local dirs_preview=""
    local d
    while IFS= read -r d; do
        dirs_preview+="  ${d}\n"
    done < <(em3_get_existing_dirs "$choice")

    local confirm
    confirm=$(DIALOG_YESNO "Backup Individual" \
        "Emulador: ${choice}\n\nPastas incluidas:\n${dirs_preview}\nDestino:\n  ${EM_BACKUP_DIR}/\n\nDeseja continuar?")
    [ "$confirm" -ne 0 ] && return

    local timestamp
    timestamp=$(date '+%Y%m%d_%H%M%S')
    local dest="${EM_BACKUP_DIR}/${choice}_${timestamp}.tar.gz"

    if em3_backup_emulator "$choice" "$dest"; then
        chown ark:ark "$dest" 2>/dev/null || true
        local size
        size=$(em_human_size "$(stat -c%s "$dest" 2>/dev/null || echo 0)")
        DIALOG_MSG "Backup Concluido" \
            "Backup de ${choice} realizado com sucesso.\n\nArquivo:\n${dest}\n\nTamanho: ${size}"
    else
        rm -f "$dest"
        DIALOG_MSG "Erro" \
            "Nao foi possivel criar o backup de ${choice}."
    fi
}

# =============================================================================
# 2. BACKUP CONFIGURAÇÃO — TODOS OS EMULADORES
# =============================================================================
em3_backup_all() {
    em3_init_backup_dir

    local available=()
    mapfile -t available < <(em3_list_available_emulators)

    if [ "${#available[@]}" -eq 0 ]; then
        DIALOG_MSG "Backup Geral" \
            "Nenhuma pasta de configuracao encontrada para os emuladores conhecidos."
        return
    fi

    local preview=""
    local emu
    for emu in "${available[@]}"; do
        local size
        size=$(em3_config_size "$emu")
        preview+="  ${emu} (${size})\n"
    done

    local confirm
    confirm=$(DIALOG_YESNO "Backup Geral" \
        "Emuladores incluidos:\n\n${preview}\nDestino:\n  ${EM_BACKUP_DIR}/\n\nDeseja continuar?")
    [ "$confirm" -ne 0 ] && return

    local timestamp
    timestamp=$(date '+%Y%m%d_%H%M%S')
    local dest="${EM_BACKUP_DIR}/backup_geral_${timestamp}.tar.gz"

    local all_dirs=()
    for emu in "${available[@]}"; do
        local d
        while IFS= read -r d; do
            all_dirs+=("$d")
        done < <(em3_get_existing_dirs "$emu")
    done

    if tar -czf "$dest" --ignore-failed-read "${all_dirs[@]}" 2>/dev/null; then
        chown ark:ark "$dest" 2>/dev/null || true
        local size
        size=$(em_human_size "$(stat -c%s "$dest" 2>/dev/null || echo 0)")
        DIALOG_MSG "Backup Geral Concluido" \
            "Backup de todos os emuladores concluido.\n\nArquivo:\n${dest}\n\nTamanho: ${size}\nEmuladores: ${#available[@]}"
    else
        rm -f "$dest"
        DIALOG_MSG "Erro" "Nao foi possivel criar o backup geral."
    fi
}

# =============================================================================
# 3. IMPORTAR CONFIGURAÇÃO PERSONALIZADA
# Lista backups disponíveis com tamanho, permite restaurar.
# =============================================================================
em3_import_config() {
    local backup_files=()
    local f
    while IFS= read -r -d '' f; do
        backup_files+=("$f")
    done < <(find "$EM_BACKUP_DIR" -maxdepth 1 -name "*.tar.gz" -print0 2>/dev/null | sort -z)

    if [ "${#backup_files[@]}" -eq 0 ]; then
        DIALOG_MSG "Importar Config" \
            "Nenhum arquivo de backup encontrado em:\n${EM_BACKUP_DIR}\n\nCrie um backup primeiro ou copie um arquivo .tar.gz para essa pasta via SFTP/SSH."
        return
    fi

    # Monta menu com nome e tamanho de cada backup
    local menu_items=()
    for f in "${backup_files[@]}"; do
        local fname
        fname=$(basename "$f")
        local fsize
        fsize=$(em_human_size "$(stat -c%s "$f" 2>/dev/null || echo 0)")
        local fdate
        fdate=$(stat -c%y "$f" 2>/dev/null | cut -d'.' -f1)
        menu_items+=("$fname" "${fname}  [${fsize}]  ${fdate}")
    done

    local choice
    choice=$(DIALOG_MENU "Importar Config" \
        "Escolha o backup para importar:" "${menu_items[@]}")
    [ "$(NORM_RET $?)" == "VOLTAR" ] && return

    local src="${EM_BACKUP_DIR}/${choice}"
    local fsize
    fsize=$(em_human_size "$(stat -c%s "$src" 2>/dev/null || echo 0)")
    local total_files
    total_files=$(tar -tzf "$src" 2>/dev/null | wc -l)
    local contents
    contents=$(tar -tzf "$src" 2>/dev/null | head -15)

    local confirm
    confirm=$(DIALOG_YESNO "Importar Config" \
        "Arquivo: ${choice}\nTamanho: ${fsize}\nArquivos contidos: ${total_files}\n\nPrimeiros arquivos:\n${contents}\n\nATENCAO: Os arquivos serao restaurados sobre as configuracoes atuais.\n\nDeseja continuar?")
    [ "$confirm" -ne 0 ] && return

    if tar -xzf "$src" -C / 2>/dev/null; then
        DIALOG_MSG "Importar Config" \
            "Configuracao importada com sucesso.\n\nArquivo restaurado:\n${choice}\n\nReinicie os emuladores para aplicar as novas configuracoes."
    else
        DIALOG_MSG "Erro" \
            "Nao foi possivel importar a configuracao.\n\nVerifique se o arquivo nao esta corrompido."
    fi
}

# =============================================================================
# 4. APAGAR BACKUP SELECIONADO
# =============================================================================
em3_delete_backup() {
    local backup_files=()
    local f
    while IFS= read -r -d '' f; do
        backup_files+=("$f")
    done < <(find "$EM_BACKUP_DIR" -maxdepth 1 -name "*.tar.gz" -print0 2>/dev/null | sort -z)

    if [ "${#backup_files[@]}" -eq 0 ]; then
        DIALOG_MSG "Apagar Backup" \
            "Nenhum arquivo de backup encontrado em:\n${EM_BACKUP_DIR}"
        return
    fi

    # Menu com nome, tamanho e data
    local menu_items=()
    for f in "${backup_files[@]}"; do
        local fname
        fname=$(basename "$f")
        local fsize
        fsize=$(em_human_size "$(stat -c%s "$f" 2>/dev/null || echo 0)")
        local fdate
        fdate=$(stat -c%y "$f" 2>/dev/null | cut -d'.' -f1)
        menu_items+=("$fname" "${fname}  [${fsize}]  ${fdate}")
    done
    menu_items+=("TODOS" "Apagar TODOS os backups")

    local choice
    choice=$(DIALOG_MENU "Apagar Backup" \
        "Escolha o backup para apagar:" "${menu_items[@]}")
    [ "$(NORM_RET $?)" == "VOLTAR" ] && return

    # Confirmação
    local warn_text
    if [ "$choice" == "TODOS" ]; then
        warn_text="TODOS os ${#backup_files[@]} backup(s) serao apagados permanentemente."
    else
        local fsize
        fsize=$(em_human_size "$(stat -c%s "${EM_BACKUP_DIR}/${choice}" 2>/dev/null || echo 0)")
        warn_text="O arquivo abaixo sera apagado permanentemente:\n\n  ${choice}\n  Tamanho: ${fsize}"
    fi

    local confirm
    confirm=$(DIALOG_YESNO "Confirmar Exclusao" \
        "${warn_text}\n\nEsta acao NAO pode ser desfeita.\n\nDeseja continuar?")
    [ "$confirm" -ne 0 ] && return

    local deleted=0
    local errors=0

    if [ "$choice" == "TODOS" ]; then
        for f in "${backup_files[@]}"; do
            if rm -f "$f" 2>/dev/null; then
                ((deleted++))
            else
                ((errors++))
            fi
        done
    else
        if rm -f "${EM_BACKUP_DIR}/${choice}" 2>/dev/null; then
            ((deleted++))
        else
            ((errors++))
        fi
    fi

    local result="Arquivos apagados: ${deleted}"
    [ "$errors" -gt 0 ] && result+="\nErros: ${errors}"
    DIALOG_MSG "Apagar Backup" "$result"
}

# =============================================================================
# 5. EXPORTAR BACKUP PARA PENDRIVE
# Detecta dispositivos montados em /media ou /mnt e copia o backup escolhido.
# =============================================================================
em3_export_to_usb() {
    # Verifica se há backups para exportar
    local backup_files=()
    local f
    while IFS= read -r -d '' f; do
        backup_files+=("$f")
    done < <(find "$EM_BACKUP_DIR" -maxdepth 1 -name "*.tar.gz" -print0 2>/dev/null | sort -z)

    if [ "${#backup_files[@]}" -eq 0 ]; then
        DIALOG_MSG "Exportar para Pendrive" \
            "Nenhum backup encontrado em:\n${EM_BACKUP_DIR}\n\nCrie um backup primeiro."
        return
    fi

    # Detecta pendrives/dispositivos montados
    local mounts=()
    mapfile -t mounts < <(em3_find_usb_mounts | sort -u)

    if [ "${#mounts[@]}" -eq 0 ]; then
        DIALOG_MSG "Exportar para Pendrive" \
            "Nenhum pendrive ou dispositivo externo detectado.\n\nConecte o pendrive e tente novamente.\n\nO dispositivo deve ser reconhecido automaticamente em:\n  /media/  ou  /mnt/"
        return
    fi

    # Escolhe o backup
    local backup_menu=()
    for f in "${backup_files[@]}"; do
        local fname
        fname=$(basename "$f")
        local fsize
        fsize=$(em_human_size "$(stat -c%s "$f" 2>/dev/null || echo 0)")
        backup_menu+=("$fname" "${fname}  [${fsize}]")
    done
    backup_menu+=("TODOS" "Exportar todos os backups")

    local chosen_backup
    chosen_backup=$(DIALOG_MENU "Exportar para Pendrive" \
        "Escolha o backup para exportar:" "${backup_menu[@]}")
    [ "$(NORM_RET $?)" == "VOLTAR" ] && return

    # Escolhe o destino (pendrive)
    local usb_menu=()
    local mount
    for mount in "${mounts[@]}"; do
        local free
        free=$(df -h "$mount" 2>/dev/null | tail -1 | awk '{print $4}')
        usb_menu+=("$mount" "${mount}  (livre: ${free:-?})")
    done

    local chosen_mount
    chosen_mount=$(DIALOG_MENU "Exportar para Pendrive" \
        "Escolha o destino:" "${usb_menu[@]}")
    [ "$(NORM_RET $?)" == "VOLTAR" ] && return

    # Confirmação
    local confirm
    confirm=$(DIALOG_YESNO "Exportar para Pendrive" \
        "Backup: ${chosen_backup}\nDestino: ${chosen_mount}/\n\nDeseja copiar agora?")
    [ "$confirm" -ne 0 ] && return

    # Copia para o pendrive
    local copied=0
    local errors=0

    if [ "$chosen_backup" == "TODOS" ]; then
        for f in "${backup_files[@]}"; do
            local fname
            fname=$(basename "$f")
            if cp "$f" "${chosen_mount}/${fname}" 2>/dev/null; then
                ((copied++))
            else
                ((errors++))
            fi
        done
    else
        if cp "${EM_BACKUP_DIR}/${chosen_backup}" "${chosen_mount}/${chosen_backup}" 2>/dev/null; then
            ((copied++))
        else
            ((errors++))
        fi
    fi

    # Sync para garantir que os dados foram gravados no pendrive
    sync 2>/dev/null

    local result_msg="Exportacao concluida.\n\nArquivos copiados: ${copied}"
    [ "$errors" -gt 0 ] && result_msg+="\nErros: ${errors}"
    result_msg+="\n\nDestino: ${chosen_mount}/"
    result_msg+="\n\nPode remover o pendrive com segurança."

    DIALOG_MSG "Exportar para Pendrive" "$result_msg"
}

# =============================================================================
# 6. RESTAURAR CONFIGURAÇÕES PADRÃO
# =============================================================================
em3_restore_defaults() {
    local available=()
    mapfile -t available < <(em3_list_available_emulators)

    if [ "${#available[@]}" -eq 0 ]; then
        DIALOG_MSG "Restaurar Padroes" \
            "Nenhuma pasta de configuracao encontrada."
        return
    fi

    local menu_items=()
    local emu
    for emu in "${available[@]}"; do
        local size
        size=$(em3_config_size "$emu")
        menu_items+=("$emu" "${emu} (${size})")
    done
    menu_items+=("TODOS" "Restaurar TODOS os emuladores")

    local choice
    choice=$(DIALOG_MENU "Restaurar Padroes" \
        "Escolha o emulador:" "${menu_items[@]}")
    [ "$(NORM_RET $?)" == "VOLTAR" ] && return

    local warn_text
    if [ "$choice" == "TODOS" ]; then
        warn_text="TODOS os emuladores terao suas configuracoes apagadas."
    else
        warn_text="As configuracoes de ${choice} serao apagadas."
    fi

    # Confirmação dupla — operação destrutiva
    local confirm1
    confirm1=$(DIALOG_YESNO "ATENCAO" \
        "OPERACAO IRREVERSIVEL\n\n${warn_text}\n\nUm backup automatico sera feito antes.\n\nDeseja continuar?")
    [ "$confirm1" -ne 0 ] && return

    local confirm2
    confirm2=$(DIALOG_YESNO "Confirmacao Final" \
        "Tem CERTEZA?\n\nTodas as configuracoes personalizadas de ${choice} serao perdidas.\n\nConfirmar restauracao dos padroes?")
    [ "$confirm2" -ne 0 ] && return

    # Backup automático antes de apagar
    em3_init_backup_dir
    local timestamp
    timestamp=$(date '+%Y%m%d_%H%M%S')
    local auto_backup="${EM_BACKUP_DIR}/pre_restore_${choice,,}_${timestamp}.tar.gz"

    local targets=()
    [ "$choice" == "TODOS" ] && targets=("${available[@]}") || targets=("$choice")

    local all_dirs=()
    for emu in "${targets[@]}"; do
        local d
        while IFS= read -r d; do
            all_dirs+=("$d")
        done < <(em3_get_existing_dirs "$emu")
    done
    tar -czf "$auto_backup" --ignore-failed-read "${all_dirs[@]}" 2>/dev/null
    chown ark:ark "$auto_backup" 2>/dev/null || true

    # Apaga as pastas
    local removed=0
    local errors=0
    for emu in "${targets[@]}"; do
        local d
        while IFS= read -r d; do
            if rm -rf "$d" 2>/dev/null; then
                ((removed++))
            else
                ((errors++))
            fi
        done < <(em3_get_existing_dirs "$emu")
    done

    local result_msg="Restauracao concluida.\n\n"
    result_msg+="Pastas removidas: ${removed}\n"
    [ "$errors" -gt 0 ] && result_msg+="Erros: ${errors}\n"
    result_msg+="\nBackup automatico salvo em:\n${auto_backup}\n"
    result_msg+="\nReinicie os emuladores para gerar as configuracoes padrao."

    DIALOG_MSG "Restaurar Padroes" "$result_msg"
}

# =============================================================================
# MENU PRINCIPAL DO MÓDULO 3
# =============================================================================
categoria_3() {
    while true; do
        local choice
        choice=$(DIALOG_MENU "Backup Inteligente" "Selecione uma opcao:" \
            "1" "Backup config emulador individual" \
            "2" "Backup config todos os emuladores" \
            "3" "Importar configuracao" \
            "4" "Apagar backup" \
            "5" "Exportar backup para pendrive" \
            "6" "Restaurar configuracoes padrao" \
            "0" "VOLTAR")

        local ret=$?
        [ "$(NORM_RET $ret)" == "VOLTAR" ] && return

        case "$choice" in
            1) em3_backup_individual ;;
            2) em3_backup_all ;;
            3) em3_import_config ;;
            4) em3_delete_backup ;;
            5) em3_export_to_usb ;;
            6) em3_restore_defaults ;;
            0) return ;;
        esac
    done
}

# Permite executar este arquivo isoladamente para testes
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    categoria_3
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/init.sh"
source "${SCRIPT_DIR}/core.sh"

# =============================================================================
# MAPA DE EMULADORES E SEUS DIRETÓRIOS DE CONFIGURAÇÃO
# Formato: "Nome exibido|pasta1|pasta2|..."
# Múltiplas pastas separadas por | para emuladores com config em mais de um lugar.
# =============================================================================
# Declaração como array associativo: EMULATOR_DIRS[nome]=pasta1:pasta2
declare -A EMULATOR_DIRS
EMULATOR_DIRS["RetroArch"]="/home/ark/.config/retroarch"
EMULATOR_DIRS["RetroArch32"]="/home/ark/.config/retroarch32"
EMULATOR_DIRS["PPSSPP"]="/opt/ppsspp"
EMULATOR_DIRS["Mupen64Plus"]="/home/ark/.config/mupen64plus:/opt/mupen64plus"
EMULATOR_DIRS["DuckStation"]="/home/ark/.config/duckstation"
EMULATOR_DIRS["Flycast"]="/home/ark/.config/flycast"
EMULATOR_DIRS["ScummVM"]="/home/ark/.config/scummvm"
EMULATOR_DIRS["GZDoom"]="/home/ark/.config/gzdoom"
EMULATOR_DIRS["ECWolf"]="/home/ark/.config/ecwolf"

# Ordem de exibição no menu
EMULATOR_ORDER=(
    "RetroArch"
    "RetroArch32"
    "PPSSPP"
    "Mupen64Plus"
    "DuckStation"
    "Flycast"
    "ScummVM"
    "GZDoom"
    "ECWolf"
)

# Diretório base onde os backups ficam salvos
EM_BACKUP_DIR="${EM_DATA_DIR}/backups"

# =============================================================================
# HELPERS INTERNOS DO MÓDULO 3
# =============================================================================

# Garante que o diretório de backups existe
em3_init_backup_dir() {
    mkdir -p "$EM_BACKUP_DIR"
    chown ark:ark "$EM_BACKUP_DIR" 2>/dev/null || true
    chmod 755 "$EM_BACKUP_DIR" 2>/dev/null || true
}

# Retorna os diretórios de configuração de um emulador que realmente existem
# Uso: em3_get_existing_dirs "RetroArch"
em3_get_existing_dirs() {
    local emu="$1"
    local dirs="${EMULATOR_DIRS[$emu]}"
    [ -z "$dirs" ] && return

    local IFS=':'
    local d
    for d in $dirs; do
        [ -d "$d" ] && echo "$d"
    done
}

# Lista emuladores que têm ao menos uma pasta de config existente
em3_list_available_emulators() {
    local emu
    for emu in "${EMULATOR_ORDER[@]}"; do
        local existing
        existing=$(em3_get_existing_dirs "$emu")
        [ -n "$existing" ] && echo "$emu"
    done
}

# Faz o backup de um emulador específico para um arquivo .tar.gz
# Uso: em3_backup_emulator "RetroArch" "/caminho/destino.tar.gz"
# Retorna 0 em sucesso, 1 em falha
em3_backup_emulator() {
    local emu="$1"
    local dest="$2"

    local dirs
    mapfile -t dirs < <(em3_get_existing_dirs "$emu")

    if [ "${#dirs[@]}" -eq 0 ]; then
        return 1
    fi

    # tar com todos os diretórios válidos, comprimido em gzip
    # --ignore-failed-read: não aborta se algum arquivo sumir durante o backup
    tar -czf "$dest" --ignore-failed-read "${dirs[@]}" 2>/dev/null
    return $?
}

# Calcula tamanho total das pastas de config de um emulador
em3_config_size() {
    local emu="$1"
    local total=0
    local d
    while IFS= read -r d; do
        local s
        s=$(du -sb "$d" 2>/dev/null | cut -f1)
        total=$(( total + ${s:-0} ))
    done < <(em3_get_existing_dirs "$emu")
    em_human_size "$total"
}

# =============================================================================
# 1. BACKUP CONFIGURAÇÃO — EMULADOR INDIVIDUAL
# =============================================================================
em3_backup_individual() {
    em3_init_backup_dir

    local available=()
    mapfile -t available < <(em3_list_available_emulators)

    if [ "${#available[@]}" -eq 0 ]; then
        DIALOG_MSG "Backup Individual" \
            "Nenhuma pasta de configuracao encontrada para os emuladores conhecidos."
        return
    fi

    # Monta menu com nome e tamanho de cada emulador
    local menu_items=()
    local emu
    for emu in "${available[@]}"; do
        local size
        size=$(em3_config_size "$emu")
        menu_items+=("$emu" "${emu} (${size})")
    done

    local choice
    choice=$(DIALOG_MENU "Backup Individual" \
        "Escolha o emulador para fazer backup:" "${menu_items[@]}")
    [ "$(NORM_RET $?)" == "VOLTAR" ] && return

    # Mostra quais pastas serão incluídas
    local dirs_preview=""
    local d
    while IFS= read -r d; do
        dirs_preview+="  ${d}\n"
    done < <(em3_get_existing_dirs "$choice")

    local confirm
    confirm=$(DIALOG_YESNO "Backup Individual" \
        "Emulador: ${choice}\n\nPastas incluidas no backup:\n${dirs_preview}\nDestino:\n  ${EM_BACKUP_DIR}/\n\nDeseja continuar?")
    [ "$confirm" -ne 0 ] && return

    local timestamp
    timestamp=$(date '+%Y%m%d_%H%M%S')
    local dest="${EM_BACKUP_DIR}/${choice}_${timestamp}.tar.gz"

    if em3_backup_emulator "$choice" "$dest"; then
        chown ark:ark "$dest" 2>/dev/null || true
        local size
        size=$(em_human_size "$(stat -c%s "$dest" 2>/dev/null || echo 0)")
        DIALOG_MSG "Backup Concluido" \
            "Backup de ${choice} realizado com sucesso.\n\nArquivo gerado:\n${dest}\n\nTamanho: ${size}"
    else
        rm -f "$dest"
        DIALOG_MSG "Erro" \
            "Nao foi possivel criar o backup de ${choice}.\n\nVerifique se as pastas de configuracao existem e tem permissao de leitura."
    fi
}

# =============================================================================
# 2. BACKUP CONFIGURAÇÃO — TODOS OS EMULADORES
# =============================================================================
em3_backup_all() {
    em3_init_backup_dir

    local available=()
    mapfile -t available < <(em3_list_available_emulators)

    if [ "${#available[@]}" -eq 0 ]; then
        DIALOG_MSG "Backup Geral" \
            "Nenhuma pasta de configuracao encontrada para os emuladores conhecidos."
        return
    fi

    # Prévia do que será incluído
    local preview=""
    local total_size=0
    local emu
    for emu in "${available[@]}"; do
        local size
        size=$(em3_config_size "$emu")
        preview+="  ${emu} (${size})\n"
    done

    local confirm
    confirm=$(DIALOG_YESNO "Backup Geral" \
        "Emuladores incluidos no backup:\n\n${preview}\nTudo sera compactado em um unico arquivo .tar.gz em:\n  ${EM_BACKUP_DIR}/\n\nDeseja continuar?")
    [ "$confirm" -ne 0 ] && return

    local timestamp
    timestamp=$(date '+%Y%m%d_%H%M%S')
    local dest="${EM_BACKUP_DIR}/backup_geral_${timestamp}.tar.gz"

    # Coleta todos os diretórios existentes de todos os emuladores
    local all_dirs=()
    for emu in "${available[@]}"; do
        local d
        while IFS= read -r d; do
            all_dirs+=("$d")
        done < <(em3_get_existing_dirs "$emu")
    done

    if tar -czf "$dest" --ignore-failed-read "${all_dirs[@]}" 2>/dev/null; then
        chown ark:ark "$dest" 2>/dev/null || true
        local size
        size=$(em_human_size "$(stat -c%s "$dest" 2>/dev/null || echo 0)")
        DIALOG_MSG "Backup Geral Concluido" \
            "Backup de todos os emuladores realizado com sucesso.\n\nArquivo gerado:\n${dest}\n\nTamanho: ${size}\nEmuladores incluidos: ${#available[@]}"
    else
        rm -f "$dest"
        DIALOG_MSG "Erro" \
            "Nao foi possivel criar o backup geral.\n\nNenhum arquivo foi gerado."
    fi
}

# =============================================================================
# 3. EXPORTAR CONFIGURAÇÃO PERSONALIZADA
# Permite ao usuário escolher um emulador e exportar sua config atual
# para um arquivo nomeado por ele (ex: "minha_config_retroarch.tar.gz")
# que pode ser compartilhado ou guardado como referência.
# =============================================================================
em3_export_config() {
    em3_init_backup_dir

    local available=()
    mapfile -t available < <(em3_list_available_emulators)

    if [ "${#available[@]}" -eq 0 ]; then
        DIALOG_MSG "Exportar Config" \
            "Nenhuma pasta de configuracao encontrada."
        return
    fi

    local menu_items=()
    local emu
    for emu in "${available[@]}"; do
        local size
        size=$(em3_config_size "$emu")
        menu_items+=("$emu" "${emu} (${size})")
    done
    menu_items+=("TODOS" "Exportar todos os emuladores")

    local choice
    choice=$(DIALOG_MENU "Exportar Config" \
        "Escolha o emulador para exportar:" "${menu_items[@]}")
    [ "$(NORM_RET $?)" == "VOLTAR" ] && return

    # Nome do arquivo de exportação
    local timestamp
    timestamp=$(date '+%Y%m%d_%H%M%S')
    local default_name="config_${choice,,}_${timestamp}"

    # Usa inputbox para o usuário dar um nome ao arquivo
    local custom_name
    custom_name=$(dialog --backtitle "$DIALOG_BACKTITLE" \
        --title "Exportar Config" \
        --ok-label "OK" --cancel-label "VOLTAR" \
        --inputbox "Nome do arquivo de exportacao\n(sem extensao, .tar.gz sera adicionado automaticamente):" \
        0 0 "$default_name" \
        3>&1 1>"$CURR_TTY" 2>&3 <"$CURR_TTY")
    [ "$(NORM_RET $?)" == "VOLTAR" ] && return
    [ -z "$custom_name" ] && custom_name="$default_name"

    # Remove caracteres inválidos do nome
    custom_name=$(echo "$custom_name" | tr -cd '[:alnum:]_.-')
    local dest="${EM_BACKUP_DIR}/${custom_name}.tar.gz"

    local success=0
    if [ "$choice" == "TODOS" ]; then
        local all_dirs=()
        for emu in "${available[@]}"; do
            local d
            while IFS= read -r d; do
                all_dirs+=("$d")
            done < <(em3_get_existing_dirs "$emu")
        done
        tar -czf "$dest" --ignore-failed-read "${all_dirs[@]}" 2>/dev/null && success=1
    else
        em3_backup_emulator "$choice" "$dest" && success=1
    fi

    if [ "$success" -eq 1 ]; then
        chown ark:ark "$dest" 2>/dev/null || true
        local size
        size=$(em_human_size "$(stat -c%s "$dest" 2>/dev/null || echo 0)")
        DIALOG_MSG "Exportar Config" \
            "Configuracao exportada com sucesso.\n\nArquivo:\n${dest}\n\nTamanho: ${size}\n\nVoce pode copiar este arquivo via SFTP/SSH para guardar ou compartilhar."
    else
        rm -f "$dest"
        DIALOG_MSG "Erro" "Nao foi possivel exportar a configuracao."
    fi
}

# =============================================================================
# 4. IMPORTAR CONFIGURAÇÃO PERSONALIZADA
# Lista arquivos .tar.gz em EM_BACKUP_DIR e permite restaurar um deles
# para os diretórios originais de configuração.
# =============================================================================
em3_import_config() {
    # Lista backups disponíveis em EM_BACKUP_DIR
    local backups=()
    local f
    while IFS= read -r -d '' f; do
        backups+=("$(basename "$f")" "$(basename "$f")")
    done < <(find "$EM_BACKUP_DIR" -maxdepth 1 -name "*.tar.gz" -print0 2>/dev/null | sort -z)

    if [ "${#backups[@]}" -eq 0 ]; then
        DIALOG_MSG "Importar Config" \
            "Nenhum arquivo de backup encontrado em:\n${EM_BACKUP_DIR}\n\nColoque um arquivo .tar.gz gerado por este script (Exportar Config) nessa pasta via SFTP/SSH e tente novamente."
        return
    fi

    local choice
    choice=$(DIALOG_MENU "Importar Config" \
        "Escolha o arquivo para importar:" "${backups[@]}")
    [ "$(NORM_RET $?)" == "VOLTAR" ] && return

    local src="${EM_BACKUP_DIR}/${choice}"

    # Mostra o conteúdo do arquivo antes de restaurar
    local contents
    contents=$(tar -tzf "$src" 2>/dev/null | head -20)
    local total_files
    total_files=$(tar -tzf "$src" 2>/dev/null | wc -l)

    local confirm
    confirm=$(DIALOG_YESNO "Importar Config" \
        "Arquivo: ${choice}\nTotal de arquivos: ${total_files}\n\nPrimeiros arquivos contidos:\n${contents}\n\nATENCAO: Os arquivos serao restaurados sobre as configuracoes atuais.\nFaca um backup antes se necessario.\n\nDeseja continuar com a importacao?")
    [ "$confirm" -ne 0 ] && return

    # Restaura extraindo para / (os caminhos absolutos dentro do tar
    # garantem que cada arquivo vai para o lugar certo)
    if tar -xzf "$src" -C / 2>/dev/null; then
        DIALOG_MSG "Importar Config" \
            "Configuracao importada com sucesso.\n\nArquivo restaurado:\n${choice}\n\nReinicie os emuladores para que as novas configuracoes tenham efeito."
    else
        DIALOG_MSG "Erro" \
            "Nao foi possivel importar a configuracao.\n\nVerifique se o arquivo nao esta corrompido e se ha espaco suficiente."
    fi
}

# =============================================================================
# 5. RESTAURAR CONFIGURAÇÕES PADRÃO
# Apaga as configurações atuais de um ou todos os emuladores,
# forçando-os a recriar os padrões na próxima inicialização.
# ATENÇÃO: operação destrutiva — pede confirmação dupla.
# =============================================================================
em3_restore_defaults() {
    local available=()
    mapfile -t available < <(em3_list_available_emulators)

    if [ "${#available[@]}" -eq 0 ]; then
        DIALOG_MSG "Restaurar Padroes" \
            "Nenhuma pasta de configuracao encontrada."
        return
    fi

    local menu_items=()
    local emu
    for emu in "${available[@]}"; do
        menu_items+=("$emu" "$emu")
    done
    menu_items+=("TODOS" "Restaurar TODOS os emuladores")

    local choice
    choice=$(DIALOG_MENU "Restaurar Padroes" \
        "Escolha o emulador:" "${menu_items[@]}")
    [ "$(NORM_RET $?)" == "VOLTAR" ] && return

    # Confirmação 1
    local warn_text=""
    if [ "$choice" == "TODOS" ]; then
        warn_text="TODOS os emuladores terao suas configuracoes apagadas."
    else
        warn_text="As configuracoes de ${choice} serao apagadas."
    fi

    local confirm1
    confirm1=$(DIALOG_YESNO "ATENCAO" \
        "OPERACAO IRREVERSIVEL\n\n${warn_text}\n\nAs configuracoes serao apagadas e os emuladores voltarao ao estado padrao na proxima inicializacao.\n\nRecomendamos fazer um backup antes.\n\nDeseja continuar?")
    [ "$confirm1" -ne 0 ] && return

    # Confirmação 2 — segurança extra para operação destrutiva
    local confirm2
    confirm2=$(DIALOG_YESNO "Confirmacao Final" \
        "Tem CERTEZA?\n\nEsta acao NAO pode ser desfeita.\n\nTodas as configuracoes personalizadas de ${choice} serao perdidas.\n\nConfirmar restauracao dos padroes?")
    [ "$confirm2" -ne 0 ] && return

    # Faz backup automático antes de apagar (segurança)
    em3_init_backup_dir
    local timestamp
    timestamp=$(date '+%Y%m%d_%H%M%S')
    local auto_backup="${EM_BACKUP_DIR}/pre_restore_${choice,,}_${timestamp}.tar.gz"

    local targets=()
    if [ "$choice" == "TODOS" ]; then
        targets=("${available[@]}")
    else
        targets=("$choice")
    fi

    # Backup automático antes de apagar
    local all_dirs=()
    for emu in "${targets[@]}"; do
        local d
        while IFS= read -r d; do
            all_dirs+=("$d")
        done < <(em3_get_existing_dirs "$emu")
    done
    tar -czf "$auto_backup" --ignore-failed-read "${all_dirs[@]}" 2>/dev/null
    chown ark:ark "$auto_backup" 2>/dev/null || true

    # Apaga as pastas de configuração
    local removed=0
    local errors=0
    for emu in "${targets[@]}"; do
        local d
        while IFS= read -r d; do
            if rm -rf "$d" 2>/dev/null; then
                ((removed++))
            else
                ((errors++))
            fi
        done < <(em3_get_existing_dirs "$emu")
    done

    local result_msg="Restauracao concluida.\n\n"
    result_msg+="Pastas de configuracao removidas: ${removed}\n"
    [ "$errors" -gt 0 ] && result_msg+="Erros: ${errors}\n"
    result_msg+="\nBackup automatico salvo em:\n${auto_backup}\n"
    result_msg+="\nReinicie os emuladores para que gerem as configuracoes padrao."

    DIALOG_MSG "Restaurar Padroes" "$result_msg"
}

# =============================================================================
# MENU PRINCIPAL DO MÓDULO 3
# =============================================================================
