#!/bin/bash
# =============================================================================
# Emulator Manager - cat_4_collection_manager.sh
# Módulo 4: Gestão da Coleção
#
# Opções implementadas (todas offline):
#   1. Backup de Saves
#   2. Restaurar Saves
#   3. Backup de BIOS
#   4. Restaurar BIOS
#   5. Exportar Coleção para Pendrive
#   6. Sincronizar com Pendrive
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/init.sh"
source "${SCRIPT_DIR}/core.sh"

# =============================================================================
# CONSTANTES DO MÓDULO 4
# =============================================================================

# Extensões de save reconhecidas
SAVE_EXTENSIONS=("sav" "srm" "state" "state1" "state2" "state3" "state4"
                 "state5" "state6" "state7" "state8" "state9" "mcr" "mc"
                 "eep" "fla" "mpk" "mpk1" "mpk2" "mpk3" "mpk4" "rtc")

# Pastas de saves fora de /roms (configs de emuladores)
SAVE_CONFIG_DIRS=(
    "/home/ark/.config/retroarch/saves"
    "/home/ark/.config/retroarch/states"
    "/home/ark/.config/retroarch32/saves"
    "/home/ark/.config/retroarch32/states"
    "/home/ark/.config/duckstation/savestates"
    "/home/ark/.config/duckstation/memcards"
    "/home/ark/.config/flycast/data"
    "/home/ark/.config/mupen64plus"
    "/home/ark/.config/ppsspp/PSP/SAVEDATA"
    "/home/ark/.config/ppsspp/PSP/PPSSPP_STATE"
)

# Pasta de BIOS
BIOS_DIR="${ROMS_BASE_DIR}/bios"

# Diretório de backups (mesmo do módulo 3)
EM4_BACKUP_DIR="${EM_DATA_DIR}/backups"

# =============================================================================
# HELPERS INTERNOS DO MÓDULO 4
# =============================================================================

em4_init_dirs() {
    mkdir -p "$EM4_BACKUP_DIR" "$EM_TMP_DIR"
    chown ark:ark "$EM4_BACKUP_DIR" 2>/dev/null || true
}

# Verifica se uma extensão é de save
em4_is_save_extension() {
    local ext="${1,,}"
    local s
    for s in "${SAVE_EXTENSIONS[@]}"; do
        [ "$ext" = "$s" ] && return 0
    done
    return 1
}

# Detecta pendrives montados (mesmo helper do módulo 3)
em4_find_usb_mounts() {
    for base in /media /media/ark /mnt; do
        [ -d "$base" ] || continue
        while IFS= read -r -d '' mp; do
            [ "$mp" = "$base" ] && continue
            [ -w "$mp" ] && echo "$mp"
        done < <(find "$base" -maxdepth 1 -mindepth 1 -type d -print0 2>/dev/null)
    done
    while IFS=' ' read -r dev mount rest; do
        echo "$dev" | grep -qE '^/dev/sd[b-z]|^/dev/usb' || continue
        [ -w "$mount" ] && echo "$mount"
    done < /proc/mounts 2>/dev/null
}

# Conta saves em /roms recursivamente
em4_count_saves_in_roms() {
    local count=0
    local sys
    for sys in "${KNOWN_SYSTEMS[@]}"; do
        local sysdir="${ROMS_BASE_DIR}/${sys}"
        [ -d "$sysdir" ] || continue
        local f
        while IFS= read -r -d '' f; do
            local ext="${f##*.}"
            em4_is_save_extension "$ext" && ((count++))
        done < <(find "$sysdir" -type f -print0 2>/dev/null)
    done
    echo "$count"
}

# Tamanho legível de um diretório
em4_dir_size() {
    local dir="$1"
    [ -d "$dir" ] || { echo "0 B"; return; }
    local bytes
    bytes=$(du -sb "$dir" 2>/dev/null | cut -f1)
    em_human_size "${bytes:-0}"
}

# =============================================================================
# 1. BACKUP DE SAVES
# Varre /roms/<sistema>/ e pastas de config dos emuladores buscando saves.
# Compacta em data/backups/saves_TIMESTAMP.tar.gz
# Se pendrive conectado, oferece salvar lá também.
# =============================================================================
em4_backup_saves() {
    em4_init_dirs

    # Coleta todos os saves de /roms
    local saves_list="${EM_TMP_DIR}/saves_list.txt"
    > "$saves_list"

    local total=0
    local sys
    for sys in "${KNOWN_SYSTEMS[@]}"; do
        local sysdir="${ROMS_BASE_DIR}/${sys}"
        [ -d "$sysdir" ] || continue
        local f
        while IFS= read -r -d '' f; do
            local ext="${f##*.}"
            em4_is_save_extension "$ext" || continue
            echo "$f" >> "$saves_list"
            ((total++))
        done < <(find "$sysdir" -type f -print0 2>/dev/null)
    done

    # Coleta saves das pastas de config dos emuladores
    local d
    for d in "${SAVE_CONFIG_DIRS[@]}"; do
        [ -d "$d" ] || continue
        local f
        while IFS= read -r -d '' f; do
            echo "$f" >> "$saves_list"
            ((total++))
        done < <(find "$d" -type f -print0 2>/dev/null)
    done

    if [ "$total" -eq 0 ]; then
        DIALOG_MSG "Backup de Saves" "Nenhum arquivo de save encontrado."
        rm -f "$saves_list"
        return
    fi

    # Prévia
    local preview=""
    local shown=0
    while IFS= read -r f; do
        preview+="$(basename "$f")\n"
        ((shown++))
        [ "$shown" -ge 12 ] && break
    done < "$saves_list"
    [ "$total" -gt 12 ] && preview+="... e mais $(( total - 12 )) arquivo(s).\n"

    local confirm
    confirm=$(DIALOG_YESNO "Backup de Saves" \
        "Saves encontrados: ${total}\n\n${preview}\nSerao compactados em:\n  ${EM4_BACKUP_DIR}/\n\nDeseja continuar?")
    [ "$confirm" -ne 0 ] && { rm -f "$saves_list"; return; }

    local timestamp
    timestamp=$(date '+%Y%m%d_%H%M%S')
    local dest="${EM4_BACKUP_DIR}/saves_${timestamp}.tar.gz"

    # Backup com gauge animado
    (
    tar -czf "$dest" --ignore-failed-read \
        --files-from="$saves_list" 2>/dev/null
    echo $? > "${EM_TMP_DIR}/saves_backup_ret"
    ) &
    local tar_pid=$!
    local i=0
    while kill -0 "$tar_pid" 2>/dev/null; do
        i=$(( (i + 2) % 101 ))
        echo "$i"
        sleep 0.3
    done | dialog --backtitle "$DIALOG_BACKTITLE" \
        --title "Backup de Saves" \
        --gauge "Compactando ${total} saves...\nAguarde." 8 60 0 \
        > "$CURR_TTY" 2> "$CURR_TTY"

    wait "$tar_pid" 2>/dev/null
    local ret
    ret=$(cat "${EM_TMP_DIR}/saves_backup_ret" 2>/dev/null || echo 1)
    rm -f "$saves_list" "${EM_TMP_DIR}/saves_backup_ret"

    if [ "$ret" -ne 0 ]; then
        rm -f "$dest"
        DIALOG_MSG "Erro" "Nao foi possivel criar o backup de saves."
        return
    fi

    chown ark:ark "$dest" 2>/dev/null || true
    local size
    size=$(em_human_size "$(stat -c%s "$dest" 2>/dev/null || echo 0)")

    # Oferece exportar para pendrive se disponível
    local mounts=()
    mapfile -t mounts < <(em4_find_usb_mounts | sort -u)

    local result_msg="Backup concluido.\n\nSaves salvos: ${total}\nArquivo: ${dest}\nTamanho: ${size}"

    if [ "${#mounts[@]}" -gt 0 ]; then
        local usb_confirm
        usb_confirm=$(DIALOG_YESNO "Exportar para Pendrive?" \
            "${result_msg}\n\nPendrive detectado em:\n  ${mounts[0]}\n\nDeseja copiar o backup para o pendrive tambem?")
        if [ "$usb_confirm" -eq 0 ]; then
            if cp "$dest" "${mounts[0]}/$(basename "$dest")" 2>/dev/null; then
                sync 2>/dev/null
                DIALOG_MSG "Backup de Saves" \
                    "${result_msg}\n\nCopiado para pendrive:\n  ${mounts[0]}/"
                return
            else
                DIALOG_MSG "Aviso" "${result_msg}\n\nNao foi possivel copiar para o pendrive."
                return
            fi
        fi
    fi

    DIALOG_MSG "Backup de Saves" "$result_msg"
}

# =============================================================================
# 2. RESTAURAR SAVES
# Lista backups de saves disponíveis e restaura no lugar original.
# =============================================================================
em4_restore_saves() {
    local backup_files=()
    local f
    while IFS= read -r -d '' f; do
        backup_files+=("$f")
    done < <(find "$EM4_BACKUP_DIR" -maxdepth 1 -name "saves_*.tar.gz" -print0 2>/dev/null | sort -z)

    if [ "${#backup_files[@]}" -eq 0 ]; then
        DIALOG_MSG "Restaurar Saves" \
            "Nenhum backup de saves encontrado em:\n${EM4_BACKUP_DIR}\n\nCrie um backup primeiro."
        return
    fi

    local menu_items=()
    for f in "${backup_files[@]}"; do
        local fname; fname=$(basename "$f")
        local fsize; fsize=$(em_human_size "$(stat -c%s "$f" 2>/dev/null || echo 0)")
        local fdate; fdate=$(stat -c%y "$f" 2>/dev/null | cut -d'.' -f1)
        menu_items+=("$fname" "${fname}  [${fsize}]  ${fdate}")
    done

    local choice
    choice=$(DIALOG_MENU "Restaurar Saves" \
        "Escolha o backup para restaurar:" "${menu_items[@]}")
    [ "$(NORM_RET $?)" == "VOLTAR" ] && return

    local src="${EM4_BACKUP_DIR}/${choice}"
    local fsize; fsize=$(em_human_size "$(stat -c%s "$src" 2>/dev/null || echo 0)")
    local total_files; total_files=$(tar -tzf "$src" 2>/dev/null | wc -l)
    local preview; preview=$(tar -tzf "$src" 2>/dev/null | head -10)

    local confirm
    confirm=$(DIALOG_YESNO "Restaurar Saves" \
        "Arquivo: ${choice}\nTamanho: ${fsize}\nArquivos: ${total_files}\n\nPrimeiros saves:\n${preview}\n\nATENCAO: Os saves serao restaurados sobre os atuais.\n\nDeseja continuar?")
    [ "$confirm" -ne 0 ] && return

    (
    tar -xzf "$src" -C / 2>/dev/null
    echo $? > "${EM_TMP_DIR}/saves_restore_ret"
    ) &
    local tar_pid=$!
    local i=0
    while kill -0 "$tar_pid" 2>/dev/null; do
        i=$(( (i + 2) % 101 ))
        echo "$i"
        sleep 0.3
    done | dialog --backtitle "$DIALOG_BACKTITLE" \
        --title "Restaurar Saves" \
        --gauge "Restaurando saves...\nAguarde." 8 60 0 \
        > "$CURR_TTY" 2> "$CURR_TTY"

    wait "$tar_pid" 2>/dev/null
    local ret; ret=$(cat "${EM_TMP_DIR}/saves_restore_ret" 2>/dev/null || echo 1)
    rm -f "${EM_TMP_DIR}/saves_restore_ret"

    if [ "$ret" -eq 0 ]; then
        DIALOG_MSG "Restaurar Saves" \
            "Saves restaurados com sucesso.\n\nArquivo: ${choice}\nTotal restaurado: ${total_files} arquivo(s)"
    else
        DIALOG_MSG "Erro" "Nao foi possivel restaurar os saves.\n\nVerifique se o arquivo nao esta corrompido."
    fi
}

# =============================================================================
# 3. BACKUP DE BIOS
# Compacta /roms/bios/ em data/backups/bios_TIMESTAMP.tar.gz
# =============================================================================
em4_backup_bios() {
    em4_init_dirs

    if [ ! -d "$BIOS_DIR" ]; then
        DIALOG_MSG "Backup de BIOS" \
            "Pasta de BIOS nao encontrada:\n${BIOS_DIR}\n\nNenhuma alteracao foi feita."
        return
    fi

    local bios_count
    bios_count=$(find "$BIOS_DIR" -type f 2>/dev/null | wc -l)
    local bios_size; bios_size=$(em4_dir_size "$BIOS_DIR")

    if [ "$bios_count" -eq 0 ]; then
        DIALOG_MSG "Backup de BIOS" "Nenhum arquivo BIOS encontrado em:\n${BIOS_DIR}"
        return
    fi

    # Prévia dos arquivos
    local preview
    preview=$(find "$BIOS_DIR" -type f -printf '%f\n' 2>/dev/null | sort | head -15)
    local overflow=""
    [ "$bios_count" -gt 15 ] && overflow="\n... e mais $(( bios_count - 15 )) arquivo(s)."

    local confirm
    confirm=$(DIALOG_YESNO "Backup de BIOS" \
        "Arquivos BIOS encontrados: ${bios_count}\nTamanho total: ${bios_size}\n\n${preview}${overflow}\n\nDestino:\n  ${EM4_BACKUP_DIR}/\n\nDeseja continuar?")
    [ "$confirm" -ne 0 ] && return

    local timestamp; timestamp=$(date '+%Y%m%d_%H%M%S')
    local dest="${EM4_BACKUP_DIR}/bios_${timestamp}.tar.gz"

    (
    tar -czf "$dest" --ignore-failed-read -C "$(dirname "$BIOS_DIR")" \
        "$(basename "$BIOS_DIR")" 2>/dev/null
    echo $? > "${EM_TMP_DIR}/bios_backup_ret"
    ) &
    local tar_pid=$!
    local i=0
    while kill -0 "$tar_pid" 2>/dev/null; do
        i=$(( (i + 2) % 101 ))
        echo "$i"
        sleep 0.3
    done | dialog --backtitle "$DIALOG_BACKTITLE" \
        --title "Backup de BIOS" \
        --gauge "Compactando arquivos BIOS...\nAguarde." 8 60 0 \
        > "$CURR_TTY" 2> "$CURR_TTY"

    wait "$tar_pid" 2>/dev/null
    local ret; ret=$(cat "${EM_TMP_DIR}/bios_backup_ret" 2>/dev/null || echo 1)
    rm -f "${EM_TMP_DIR}/bios_backup_ret"

    if [ "$ret" -ne 0 ]; then
        rm -f "$dest"
        DIALOG_MSG "Erro" "Nao foi possivel criar o backup de BIOS."
        return
    fi

    chown ark:ark "$dest" 2>/dev/null || true
    local size; size=$(em_human_size "$(stat -c%s "$dest" 2>/dev/null || echo 0)")
    local result_msg="Backup de BIOS concluido.\n\nArquivos: ${bios_count}\nArquivo gerado: ${dest}\nTamanho: ${size}"

    # Oferece exportar para pendrive
    local mounts=()
    mapfile -t mounts < <(em4_find_usb_mounts | sort -u)
    if [ "${#mounts[@]}" -gt 0 ]; then
        local usb_confirm
        usb_confirm=$(DIALOG_YESNO "Exportar para Pendrive?" \
            "${result_msg}\n\nPendrive detectado.\nDeseja copiar para:\n  ${mounts[0]}/?")
        if [ "$usb_confirm" -eq 0 ]; then
            cp "$dest" "${mounts[0]}/$(basename "$dest")" 2>/dev/null && sync 2>/dev/null
            DIALOG_MSG "Backup de BIOS" "${result_msg}\n\nCopiado para: ${mounts[0]}/"
            return
        fi
    fi

    DIALOG_MSG "Backup de BIOS" "$result_msg"
}

# =============================================================================
# 4. RESTAURAR BIOS
# Lista backups de BIOS e restaura em /roms/bios/
# =============================================================================
em4_restore_bios() {
    local backup_files=()
    local f
    while IFS= read -r -d '' f; do
        backup_files+=("$f")
    done < <(find "$EM4_BACKUP_DIR" -maxdepth 1 -name "bios_*.tar.gz" -print0 2>/dev/null | sort -z)

    if [ "${#backup_files[@]}" -eq 0 ]; then
        DIALOG_MSG "Restaurar BIOS" \
            "Nenhum backup de BIOS encontrado em:\n${EM4_BACKUP_DIR}\n\nCrie um backup primeiro."
        return
    fi

    local menu_items=()
    for f in "${backup_files[@]}"; do
        local fname; fname=$(basename "$f")
        local fsize; fsize=$(em_human_size "$(stat -c%s "$f" 2>/dev/null || echo 0)")
        local fdate; fdate=$(stat -c%y "$f" 2>/dev/null | cut -d'.' -f1)
        menu_items+=("$fname" "${fname}  [${fsize}]  ${fdate}")
    done

    local choice
    choice=$(DIALOG_MENU "Restaurar BIOS" \
        "Escolha o backup para restaurar:" "${menu_items[@]}")
    [ "$(NORM_RET $?)" == "VOLTAR" ] && return

    local src="${EM4_BACKUP_DIR}/${choice}"
    local total_files; total_files=$(tar -tzf "$src" 2>/dev/null | wc -l)
    local fsize; fsize=$(em_human_size "$(stat -c%s "$src" 2>/dev/null || echo 0)")

    local confirm
    confirm=$(DIALOG_YESNO "Restaurar BIOS" \
        "Arquivo: ${choice}\nTamanho: ${fsize}\nArquivos BIOS: ${total_files}\n\nOs arquivos serao restaurados em:\n  ${BIOS_DIR}/\n\nArquivos existentes com mesmo nome serao substituidos.\n\nDeseja continuar?")
    [ "$confirm" -ne 0 ] && return

    mkdir -p "$BIOS_DIR"

    (
    tar -xzf "$src" -C "$(dirname "$BIOS_DIR")" 2>/dev/null
    echo $? > "${EM_TMP_DIR}/bios_restore_ret"
    ) &
    local tar_pid=$!
    local i=0
    while kill -0 "$tar_pid" 2>/dev/null; do
        i=$(( (i + 2) % 101 ))
        echo "$i"
        sleep 0.3
    done | dialog --backtitle "$DIALOG_BACKTITLE" \
        --title "Restaurar BIOS" \
        --gauge "Restaurando arquivos BIOS...\nAguarde." 8 60 0 \
        > "$CURR_TTY" 2> "$CURR_TTY"

    wait "$tar_pid" 2>/dev/null
    local ret; ret=$(cat "${EM_TMP_DIR}/bios_restore_ret" 2>/dev/null || echo 1)
    rm -f "${EM_TMP_DIR}/bios_restore_ret"

    if [ "$ret" -eq 0 ]; then
        DIALOG_MSG "Restaurar BIOS" \
            "BIOS restaurada com sucesso.\n\nArquivos restaurados: ${total_files}\nDestino: ${BIOS_DIR}/"
    else
        DIALOG_MSG "Erro" "Nao foi possivel restaurar a BIOS.\n\nVerifique se o arquivo nao esta corrompido."
    fi
}

# =============================================================================
# 5. EXPORTAR COLEÇÃO PARA PENDRIVE
# Copia /roms/<sistema>/ completo para pendrive, verificando espaço antes.
# =============================================================================
em4_export_collection() {
    # Detecta pendrives
    local mounts=()
    mapfile -t mounts < <(em4_find_usb_mounts | sort -u)

    if [ "${#mounts[@]}" -eq 0 ]; then
        DIALOG_MSG "Exportar Colecao" \
            "Nenhum pendrive detectado.\n\nConecte o pendrive e tente novamente.\nO dispositivo deve ser reconhecido em /media/ ou /mnt/."
        return
    fi

    # Escolhe o sistema
    local systems
    mapfile -t systems < <(em_list_existing_systems)
    local menu_items=()
    local sys
    for sys in "${systems[@]}"; do
        local size; size=$(em4_dir_size "${ROMS_BASE_DIR}/${sys}")
        menu_items+=("$sys" "${sys}  (${size})")
    done
    menu_items+=("TODOS" "Exportar todos os sistemas")

    local choice
    choice=$(DIALOG_MENU "Exportar Colecao" \
        "Escolha o sistema para exportar para o pendrive:" "${menu_items[@]}")
    [ "$(NORM_RET $?)" == "VOLTAR" ] && return

    # Escolhe o destino
    local usb_menu=()
    local mount
    for mount in "${mounts[@]}"; do
        local free; free=$(df -h "$mount" 2>/dev/null | tail -1 | awk '{print $4}')
        usb_menu+=("$mount" "${mount}  (livre: ${free:-?})")
    done

    local chosen_mount
    chosen_mount=$(DIALOG_MENU "Exportar Colecao" \
        "Escolha o pendrive de destino:" "${usb_menu[@]}")
    [ "$(NORM_RET $?)" == "VOLTAR" ] && return

    # Verifica espaço disponível
    local targets=()
    [ "$choice" == "TODOS" ] && targets=("${systems[@]}") || targets=("$choice")

    local total_bytes=0
    for sys in "${targets[@]}"; do
        local b; b=$(du -sb "${ROMS_BASE_DIR}/${sys}" 2>/dev/null | cut -f1)
        total_bytes=$(( total_bytes + ${b:-0} ))
    done

    local free_bytes
    free_bytes=$(df -B1 "$chosen_mount" 2>/dev/null | tail -1 | awk '{print $4}')
    free_bytes=${free_bytes:-0}

    local total_human; total_human=$(em_human_size "$total_bytes")
    local free_human; free_human=$(em_human_size "$free_bytes")

    if [ "$total_bytes" -gt "$free_bytes" ]; then
        DIALOG_MSG "Espaco Insuficiente" \
            "Espaco necessario: ${total_human}\nEspaco livre no pendrive: ${free_human}\n\nNao ha espaco suficiente no pendrive.\nNenhum arquivo foi copiado."
        return
    fi

    local confirm
    confirm=$(DIALOG_YESNO "Exportar Colecao" \
        "Sistema(s): ${choice}\nTamanho total: ${total_human}\nEspaco livre: ${free_human}\nDestino: ${chosen_mount}/\n\nDeseja copiar agora?\n(Pode demorar varios minutos)")
    [ "$confirm" -ne 0 ] && return

    # Conta total de arquivos para gauge
    local total_files=0
    for sys in "${targets[@]}"; do
        local n; n=$(find "${ROMS_BASE_DIR}/${sys}" -type f 2>/dev/null | wc -l)
        total_files=$(( total_files + n ))
    done

    local copied_file="${EM_TMP_DIR}/export_copied"
    local errors_file="${EM_TMP_DIR}/export_errors"
    echo 0 > "$copied_file"; echo 0 > "$errors_file"
    em_drain_tty_buffer

    (
    local copied=0 errors=0 processed=0
    for sys in "${targets[@]}"; do
        local src_dir="${ROMS_BASE_DIR}/${sys}"
        local dst_dir="${chosen_mount}/roms/${sys}"
        mkdir -p "$dst_dir" 2>/dev/null

        while IFS= read -r -d '' f; do
            ((processed++))
            [ "$total_files" -gt 0 ] && echo $(( processed * 100 / total_files ))
            local rel_path="${f#${src_dir}/}"
            local dst_file="${dst_dir}/${rel_path}"
            mkdir -p "$(dirname "$dst_file")" 2>/dev/null
            if cp "$f" "$dst_file" 2>/dev/null; then
                ((copied++)); echo "$copied" > "$copied_file"
            else
                ((errors++)); echo "$errors" > "$errors_file"
            fi
        done < <(find "$src_dir" -type f -print0 2>/dev/null)
    done
    sync 2>/dev/null
    ) | dialog --backtitle "$DIALOG_BACKTITLE" \
        --title "Exportar Colecao" \
        --gauge "Copiando ROMs para o pendrive...\nIsso pode demorar varios minutos." 8 60 0 \
        > "$CURR_TTY" 2> "$CURR_TTY"

    local copied errors
    copied=$(cat "$copied_file" 2>/dev/null || echo 0)
    errors=$(cat "$errors_file" 2>/dev/null || echo 0)
    rm -f "$copied_file" "$errors_file"

    local result="Exportacao concluida.\n\nArquivos copiados: ${copied}"
    [ "$errors" -gt 0 ] && result+="\nErros: ${errors}"
    result+="\n\nDestino: ${chosen_mount}/roms/\n\nPode remover o pendrive com segurança."
    DIALOG_MSG "Exportar Colecao" "$result"
}

# =============================================================================
# 6. SINCRONIZAR COM PENDRIVE
# Compara arquivos locais vs pendrive por data/tamanho.
# Copia apenas o que mudou, sem rsync.
# Escolha: saves OU ROMs (por sistema)
# =============================================================================
em4_sync_with_usb() {
    # Detecta pendrives
    local mounts=()
    mapfile -t mounts < <(em4_find_usb_mounts | sort -u)

    if [ "${#mounts[@]}" -eq 0 ]; then
        DIALOG_MSG "Sincronizar" \
            "Nenhum pendrive detectado.\n\nConecte o pendrive e tente novamente."
        return
    fi

    # Escolhe o pendrive
    local usb_menu=()
    local mount
    for mount in "${mounts[@]}"; do
        local free; free=$(df -h "$mount" 2>/dev/null | tail -1 | awk '{print $4}')
        usb_menu+=("$mount" "${mount}  (livre: ${free:-?})")
    done

    local chosen_mount
    chosen_mount=$(DIALOG_MENU "Sincronizar" \
        "Escolha o pendrive:" "${usb_menu[@]}")
    [ "$(NORM_RET $?)" == "VOLTAR" ] && return

    # Escolhe o tipo de conteúdo
    local sync_type
    sync_type=$(DIALOG_MENU "Sincronizar" \
        "O que deseja sincronizar?" \
        "1" "Saves (device → pendrive)" \
        "2" "ROMs por sistema (device → pendrive)" \
        "3" "Saves (pendrive → device)" \
        "4" "ROMs por sistema (pendrive → device)")
    [ "$(NORM_RET $?)" == "VOLTAR" ] && return

    case "$sync_type" in
        1|3) em4_sync_saves "$chosen_mount" "$sync_type" ;;
        2|4) em4_sync_roms  "$chosen_mount" "$sync_type" ;;
    esac
}

# Sincroniza saves entre device e pendrive
em4_sync_saves() {
    local usb="$1"
    local direction="$2"   # 1=device→usb  3=usb→device

    local usb_save_dir="${usb}/saves"

    if [ "$direction" -eq 1 ]; then
        # device → pendrive
        mkdir -p "$usb_save_dir" 2>/dev/null

        # Coleta saves do device
        local saves_src=()
        local sys
        for sys in "${KNOWN_SYSTEMS[@]}"; do
            local sysdir="${ROMS_BASE_DIR}/${sys}"
            [ -d "$sysdir" ] || continue
            local f
            while IFS= read -r -d '' f; do
                local ext="${f##*.}"
                em4_is_save_extension "$ext" && saves_src+=("$f")
            done < <(find "$sysdir" -type f -print0 2>/dev/null)
        done
        local d
        for d in "${SAVE_CONFIG_DIRS[@]}"; do
            [ -d "$d" ] || continue
            local f
            while IFS= read -r -d '' f; do
                saves_src+=("$f")
            done < <(find "$d" -type f -print0 2>/dev/null)
        done

        local total="${#saves_src[@]}"
        [ "$total" -eq 0 ] && {
            DIALOG_MSG "Sincronizar" "Nenhum save encontrado no device."
            return
        }

        local confirm
        confirm=$(DIALOG_YESNO "Sincronizar Saves" \
            "Saves encontrados no device: ${total}\nDestino: ${usb_save_dir}/\n\nApenas saves mais recentes ou novos serao copiados.\n\nDeseja continuar?")
        [ "$confirm" -ne 0 ] && return

        local copied_file="${EM_TMP_DIR}/sync_copied"
        local skip_file="${EM_TMP_DIR}/sync_skip"
        echo 0 > "$copied_file"; echo 0 > "$skip_file"
        em_drain_tty_buffer

        (
        local processed=0 copied=0 skipped=0
        for f in "${saves_src[@]}"; do
            ((processed++))
            echo $(( processed * 100 / total ))
            local fname; fname=$(basename "$f")
            local dst="${usb_save_dir}/${fname}"

            # Copia se não existe ou se o source é mais recente
            if [ ! -e "$dst" ] || [ "$f" -nt "$dst" ]; then
                cp "$f" "$dst" 2>/dev/null && ((copied++))
                echo "$copied" > "$copied_file"
            else
                ((skipped++)); echo "$skipped" > "$skip_file"
            fi
        done
        sync 2>/dev/null
        ) | dialog --backtitle "$DIALOG_BACKTITLE" \
            --title "Sincronizar Saves" \
            --gauge "Sincronizando saves para o pendrive..." 8 60 0 \
            > "$CURR_TTY" 2> "$CURR_TTY"

        local copied skipped
        copied=$(cat "$copied_file" 2>/dev/null || echo 0)
        skipped=$(cat "$skip_file" 2>/dev/null || echo 0)
        rm -f "$copied_file" "$skip_file"
        DIALOG_MSG "Sincronizar Saves" \
            "Sincronizacao concluida.\n\nSaves copiados/atualizados: ${copied}\nJa atualizados (ignorados): ${skipped}\n\nDestino: ${usb_save_dir}/"

    else
        # pendrive → device
        if [ ! -d "$usb_save_dir" ]; then
            DIALOG_MSG "Sincronizar" \
                "Nenhuma pasta 'saves/' encontrada no pendrive:\n${usb_save_dir}\n\nFaca primeiro uma sincronizacao device → pendrive."
            return
        fi

        local total
        total=$(find "$usb_save_dir" -type f 2>/dev/null | wc -l)
        [ "$total" -eq 0 ] && {
            DIALOG_MSG "Sincronizar" "Nenhum save encontrado no pendrive em:\n${usb_save_dir}"
            return
        }

        local confirm
        confirm=$(DIALOG_YESNO "Sincronizar Saves" \
            "Saves encontrados no pendrive: ${total}\n\nApenas saves mais recentes ou novos serao copiados para o device.\n\nDeseja continuar?")
        [ "$confirm" -ne 0 ] && return

        # Monta mapa de saves locais por nome de arquivo
        local local_map="${EM_TMP_DIR}/local_saves_map.tsv"
        > "$local_map"
        local sys
        for sys in "${KNOWN_SYSTEMS[@]}"; do
            local sysdir="${ROMS_BASE_DIR}/${sys}"
            [ -d "$sysdir" ] || continue
            local f
            while IFS= read -r -d '' f; do
                local ext="${f##*.}"
                em4_is_save_extension "$ext" || continue
                printf '%s\t%s\n' "$(basename "$f")" "$f" >> "$local_map"
            done < <(find "$sysdir" -type f -print0 2>/dev/null)
        done
        local d
        for d in "${SAVE_CONFIG_DIRS[@]}"; do
            [ -d "$d" ] || continue
            local f
            while IFS= read -r -d '' f; do
                printf '%s\t%s\n' "$(basename "$f")" "$f" >> "$local_map"
            done < <(find "$d" -type f -print0 2>/dev/null)
        done

        local copied_file="${EM_TMP_DIR}/sync_copied"
        local skip_file="${EM_TMP_DIR}/sync_skip"
        local new_file="${EM_TMP_DIR}/sync_new"
        echo 0 > "$copied_file"; echo 0 > "$skip_file"; echo 0 > "$new_file"
        em_drain_tty_buffer

        (
        local processed=0 copied=0 skipped=0 new_saves=0
        while IFS= read -r -d '' usb_f; do
            ((processed++))
            echo $(( processed * 100 / total ))
            local fname; fname=$(basename "$usb_f")

            # Procura o destino local pelo nome do arquivo
            local local_path
            local_path=$(grep -m1 $'^'"${fname}"$'\t' "$local_map" | cut -f2)

            if [ -n "$local_path" ]; then
                # Arquivo existe localmente: copia só se pendrive é mais recente
                if [ "$usb_f" -nt "$local_path" ]; then
                    cp "$usb_f" "$local_path" 2>/dev/null && ((copied++))
                    echo "$copied" > "$copied_file"
                else
                    ((skipped++)); echo "$skipped" > "$skip_file"
                fi
            else
                # Save novo — não sabe onde colocar, registra
                ((new_saves++)); echo "$new_saves" > "$new_file"
            fi
        done < <(find "$usb_save_dir" -type f -print0 2>/dev/null)
        ) | dialog --backtitle "$DIALOG_BACKTITLE" \
            --title "Sincronizar Saves" \
            --gauge "Sincronizando saves do pendrive para o device..." 8 60 0 \
            > "$CURR_TTY" 2> "$CURR_TTY"

        local copied skipped new_saves
        copied=$(cat "$copied_file" 2>/dev/null || echo 0)
        skipped=$(cat "$skip_file" 2>/dev/null || echo 0)
        new_saves=$(cat "$new_file" 2>/dev/null || echo 0)
        rm -f "$copied_file" "$skip_file" "$new_file" "$local_map"

        local result="Sincronizacao concluida.\n\nSaves atualizados: ${copied}\nJa em dia (ignorados): ${skipped}"
        [ "$new_saves" -gt 0 ] && result+="\nSaves novos (sem destino local): ${new_saves}"
        DIALOG_MSG "Sincronizar Saves" "$result"
    fi
}

# Sincroniza ROMs entre device e pendrive
em4_sync_roms() {
    local usb="$1"
    local direction="$2"   # 2=device→usb  4=usb→device

    local systems
    mapfile -t systems < <(em_list_existing_systems)
    local menu_items=()
    local sys
    for sys in "${systems[@]}"; do
        local size; size=$(em4_dir_size "${ROMS_BASE_DIR}/${sys}")
        menu_items+=("$sys" "${sys}  (${size})")
    done
    menu_items+=("TODOS" "Todos os sistemas")

    local dir_label
    [ "$direction" -eq 2 ] && dir_label="device → pendrive" || dir_label="pendrive → device"

    local choice
    choice=$(DIALOG_MENU "Sincronizar ROMs" \
        "Sincronizar: ${dir_label}\nEscolha o sistema:" "${menu_items[@]}")
    [ "$(NORM_RET $?)" == "VOLTAR" ] && return

    local targets=()
    [ "$choice" == "TODOS" ] && targets=("${systems[@]}") || targets=("$choice")

    if [ "$direction" -eq 2 ]; then
        # device → pendrive
        local total_files=0
        for sys in "${targets[@]}"; do
            local n; n=$(find "${ROMS_BASE_DIR}/${sys}" -maxdepth 2 -type f 2>/dev/null | wc -l)
            total_files=$(( total_files + n ))
        done

        local confirm
        confirm=$(DIALOG_YESNO "Sincronizar ROMs" \
            "Sistema(s): ${choice}\nTotal de arquivos: ${total_files}\nDestino: ${usb}/roms/\n\nApenas arquivos novos ou modificados serao copiados.\n\nDeseja continuar?")
        [ "$confirm" -ne 0 ] && return

        local copied_file="${EM_TMP_DIR}/sync_rom_copied"
        local skip_file="${EM_TMP_DIR}/sync_rom_skip"
        echo 0 > "$copied_file"; echo 0 > "$skip_file"
        em_drain_tty_buffer

        (
        local processed=0 copied=0 skipped=0
        for sys in "${targets[@]}"; do
            local src_dir="${ROMS_BASE_DIR}/${sys}"
            local dst_dir="${usb}/roms/${sys}"
            mkdir -p "$dst_dir" 2>/dev/null
            while IFS= read -r -d '' f; do
                ((processed++))
                [ "$total_files" -gt 0 ] && echo $(( processed * 100 / total_files ))
                local rel="${f#${src_dir}/}"
                local dst="${dst_dir}/${rel}"
                mkdir -p "$(dirname "$dst")" 2>/dev/null
                if [ ! -e "$dst" ] || [ "$f" -nt "$dst" ]; then
                    cp "$f" "$dst" 2>/dev/null && ((copied++))
                    echo "$copied" > "$copied_file"
                else
                    ((skipped++)); echo "$skipped" > "$skip_file"
                fi
            done < <(find "$src_dir" -maxdepth 2 -type f -print0 2>/dev/null)
        done
        sync 2>/dev/null
        ) | dialog --backtitle "$DIALOG_BACKTITLE" \
            --title "Sincronizar ROMs" \
            --gauge "Sincronizando ROMs para o pendrive..." 8 60 0 \
            > "$CURR_TTY" 2> "$CURR_TTY"

        local copied skipped
        copied=$(cat "$copied_file" 2>/dev/null || echo 0)
        skipped=$(cat "$skip_file" 2>/dev/null || echo 0)
        rm -f "$copied_file" "$skip_file"
        DIALOG_MSG "Sincronizar ROMs" \
            "Concluido.\n\nArquivos copiados/atualizados: ${copied}\nJa atualizados (ignorados): ${skipped}\n\nDestino: ${usb}/roms/"

    else
        # pendrive → device
        local usb_roms_dir="${usb}/roms"
        if [ ! -d "$usb_roms_dir" ]; then
            DIALOG_MSG "Sincronizar" \
                "Nenhuma pasta 'roms/' encontrada no pendrive:\n${usb_roms_dir}\n\nFaca primeiro uma sincronizacao device → pendrive."
            return
        fi

        local total_files
        total_files=$(find "$usb_roms_dir" -type f 2>/dev/null | wc -l)

        local confirm
        confirm=$(DIALOG_YESNO "Sincronizar ROMs" \
            "Arquivos encontrados no pendrive: ${total_files}\nDestino: ${ROMS_BASE_DIR}/\n\nApenas arquivos novos ou mais recentes serao copiados.\n\nDeseja continuar?")
        [ "$confirm" -ne 0 ] && return

        local copied_file="${EM_TMP_DIR}/sync_rom_copied"
        local skip_file="${EM_TMP_DIR}/sync_rom_skip"
        echo 0 > "$copied_file"; echo 0 > "$skip_file"
        em_drain_tty_buffer

        (
        local processed=0 copied=0 skipped=0
        while IFS= read -r -d '' f; do
            ((processed++))
            [ "$total_files" -gt 0 ] && echo $(( processed * 100 / total_files ))
            local rel="${f#${usb_roms_dir}/}"
            local dst="${ROMS_BASE_DIR}/${rel}"
            mkdir -p "$(dirname "$dst")" 2>/dev/null
            if [ ! -e "$dst" ] || [ "$f" -nt "$dst" ]; then
                cp "$f" "$dst" 2>/dev/null && ((copied++))
                echo "$copied" > "$copied_file"
            else
                ((skipped++)); echo "$skipped" > "$skip_file"
            fi
        done < <(find "$usb_roms_dir" -type f -print0 2>/dev/null)
        ) | dialog --backtitle "$DIALOG_BACKTITLE" \
            --title "Sincronizar ROMs" \
            --gauge "Sincronizando ROMs do pendrive para o device..." 8 60 0 \
            > "$CURR_TTY" 2> "$CURR_TTY"

        local copied skipped
        copied=$(cat "$copied_file" 2>/dev/null || echo 0)
        skipped=$(cat "$skip_file" 2>/dev/null || echo 0)
        rm -f "$copied_file" "$skip_file"
        DIALOG_MSG "Sincronizar ROMs" \
            "Concluido.\n\nArquivos copiados/atualizados: ${copied}\nJa atualizados (ignorados): ${skipped}\n\nDestino: ${ROMS_BASE_DIR}/"
    fi
}

# =============================================================================
# 7. INSTALAR BIOS DO PENDRIVE
# Detecta arquivos de BIOS no pendrive, verifica MD5, renomeia para o nome
# correto e copia para /roms/bios/
# =============================================================================

# Mapa de BIOS conhecidas: MD5 → "nome_correto|sistema|obrigatoria"
# Fontes: Libretro docs, EmulationGeneralWiki, RetroArch system/ requirements
declare -A EM4_BIOS_DB
# --- PlayStation 1 ---
EM4_BIOS_DB["8dd7d5296a650fac7319bce665a6a53c"]="scph5500.bin|PSX (BIOS Japao)|obrigatoria"
EM4_BIOS_DB["490f666e1afb15b7362b406ed1cea246"]="scph5501.bin|PSX (BIOS EUA)|obrigatoria"
EM4_BIOS_DB["32736f17079d0b2b7024407c39bd3050"]="scph5502.bin|PSX (BIOS Europa)|obrigatoria"
EM4_BIOS_DB["8dd7d5296a650fac7319bce665a6a53c"]="scph1001.bin|PSX (BIOS EUA v2)|opcional"
# --- PlayStation 2 ---
EM4_BIOS_DB["bdc585c61f4a4be14acb3ce61dbe9954"]="SCPH-70012.bin|PS2 (BIOS EUA)|obrigatoria"
# --- Game Boy Advance ---
EM4_BIOS_DB["a860e8c0b6d573d191e4ec7db1b1e4f6"]="gba_bios.bin|GBA|opcional"
# --- Nintendo DS ---
EM4_BIOS_DB["a392174eb3e572fed6447e956bde4b25"]="bios7.bin|NDS (ARM7)|obrigatoria"
EM4_BIOS_DB["1280f0d3a0e328e25f3a27e4b75d37b9"]="bios9.bin|NDS (ARM9)|obrigatoria"
EM4_BIOS_DB["145eaef5bd3037cbc247c213bb3da1b3"]="firmware.bin|NDS (Firmware)|obrigatoria"
# --- Sega CD ---
EM4_BIOS_DB["e66fa1dc5820d254611fdcdba0662372"]="bios_CD_E.bin|Sega CD (Europa)|obrigatoria"
EM4_BIOS_DB["854b9150240a198070150e4566ae1220"]="bios_CD_J.bin|Sega CD (Japao)|obrigatoria"
EM4_BIOS_DB["2efd74e3232ff260e371b99f84024f7f"]="bios_CD_U.bin|Sega CD (EUA)|obrigatoria"
# --- Sega Saturn ---
EM4_BIOS_DB["af5828fdff51384f99b3c4926be27762"]="sega_101.bin|Saturn (Japao v1.01)|obrigatoria"
EM4_BIOS_DB["3240872c70984b6cbfda1586cab68dbe"]="mpr-17933.bin|Saturn (Japao v1.00)|obrigatoria"
# --- Dreamcast ---
EM4_BIOS_DB["e10c53c2f8b90bab96ead2d368858623"]="dc_boot.bin|Dreamcast (BIOS)|obrigatoria"
EM4_BIOS_DB["0a93f7940c455905bea479ec6e3721eb"]="dc_flash.bin|Dreamcast (Flash)|obrigatoria"
# --- Atari Lynx ---
EM4_BIOS_DB["fcd403db69f54290b51035d82f835e7b"]="lynxboot.img|Atari Lynx|obrigatoria"
# --- Neo Geo ---
EM4_BIOS_DB["dff6d41d4b4f7614074c42c4e5c6c0f9"]="neogeo.zip|Neo Geo|obrigatoria"
# --- Famicom Disk System ---
EM4_BIOS_DB["ca30b50f880eb660a320674ed365ef7a"]="disksys.rom|FDS (Famicom Disk)|obrigatoria"
# --- PC Engine / TurboGrafx ---
EM4_BIOS_DB["ff1a674273fe3540ccef576376407d1d"]="syscard3.pce|PC Engine CD|obrigatoria"

em4_install_bios_from_usb() {
    # Detecta pendrives
    local mounts=()
    mapfile -t mounts < <(em4_find_usb_mounts | sort -u)

    if [ "${#mounts[@]}" -eq 0 ]; then
        DIALOG_MSG "Instalar BIOS" \
            "Nenhum pendrive detectado.\n\nConecte o pendrive com os arquivos de BIOS e tente novamente.\n\nOrganize os arquivos de BIOS em qualquer pasta do pendrive — o script vai varrer tudo automaticamente."
        return
    fi

    # Escolhe o pendrive
    local usb_menu=()
    local mount
    for mount in "${mounts[@]}"; do
        local free; free=$(df -h "$mount" 2>/dev/null | tail -1 | awk '{print $4}')
        usb_menu+=("$mount" "${mount}  (livre: ${free:-?})")
    done

    local chosen_mount
    chosen_mount=$(DIALOG_MENU "Instalar BIOS" \
        "Escolha o pendrive que contem os arquivos de BIOS:" "${usb_menu[@]}")
    [ "$(NORM_RET $?)" == "VOLTAR" ] && return

    DIALOG_MSG "Instalar BIOS" "Varrendo o pendrive em busca de arquivos de BIOS...\n\nIsso pode levar alguns segundos."

    # Varre todo o pendrive buscando arquivos que possam ser BIOS
    local candidate_files=()
    local f
    while IFS= read -r -d '' f; do
        candidate_files+=("$f")
    done < <(find "$chosen_mount" -type f -print0 2>/dev/null)

    local total="${#candidate_files[@]}"
    if [ "$total" -eq 0 ]; then
        DIALOG_MSG "Instalar BIOS" "Nenhum arquivo encontrado no pendrive."
        return
    fi

    # Calcula MD5 de cada arquivo e cruza com o banco de dados
    local found_file="${EM_TMP_DIR}/bios_found.tsv"   # md5 TAB caminho_origem TAB nome_destino TAB sistema TAB tipo
    > "$found_file"
    local checked_file="${EM_TMP_DIR}/bios_checked"
    echo 0 > "$checked_file"
    em_drain_tty_buffer

    (
    local processed=0
    for f in "${candidate_files[@]}"; do
        ((processed++))
        echo $(( processed * 100 / total ))
        echo "$processed" > "$checked_file"
        local md5
        md5=$(md5sum "$f" 2>/dev/null | cut -d' ' -f1)
        [ -z "$md5" ] && continue
        local entry="${EM4_BIOS_DB[$md5]:-}"
        [ -z "$entry" ] && continue
        local dest_name sistema tipo
        IFS='|' read -r dest_name sistema tipo <<< "$entry"
        printf '%s\t%s\t%s\t%s\t%s\n' "$md5" "$f" "$dest_name" "$sistema" "$tipo" >> "$found_file"
    done
    ) | dialog --backtitle "$DIALOG_BACKTITLE" \
        --title "Instalar BIOS" \
        --gauge "Verificando arquivos no pendrive via MD5..." 8 60 0 \
        > "$CURR_TTY" 2> "$CURR_TTY"

    local checked
    checked=$(cat "$checked_file" 2>/dev/null || echo 0)
    rm -f "$checked_file"

    local found_count=0
    [ -s "$found_file" ] && found_count=$(wc -l < "$found_file")

    if [ "$found_count" -eq 0 ]; then
        DIALOG_MSG "Instalar BIOS" \
            "Nenhuma BIOS reconhecida encontrada no pendrive.\n\nArquivos verificados: ${checked}\n\nVerifique se os arquivos de BIOS sao os corretos.\nO script verifica pelo MD5 (hash), nao pelo nome do arquivo."
        rm -f "$found_file"
        return
    fi

    # Monta prévia do que será instalado
    local preview=""
    local already=0
    local new_count=0
    while IFS=$'\t' read -r md5 src dest_name sistema tipo; do
        local dest_path="${BIOS_DIR}/${dest_name}"
        if [ -f "$dest_path" ]; then
            preview+="[JA EXISTE] ${dest_name} (${sistema})\n"
            ((already++))
        else
            preview+="[NOVO] ${dest_name} (${sistema}) — ${tipo}\n"
            ((new_count++))
        fi
    done < "$found_file"

    local confirm
    confirm=$(DIALOG_YESNO "Instalar BIOS" \
        "BIOS reconhecidas no pendrive: ${found_count}\n\nNovas: ${new_count}\nJa instaladas: ${already}\n\n${preview}\nOs arquivos serao copiados para:\n  ${BIOS_DIR}/\n\nDeseja instalar?")
    if [ "$confirm" -ne 0 ]; then
        DIALOG_MSG "Instalar BIOS" "Operacao cancelada.\nNenhum arquivo foi copiado."
        rm -f "$found_file"
        return
    fi

    # Copia e renomeia para o nome correto
    mkdir -p "$BIOS_DIR"
    chown ark:ark "$BIOS_DIR" 2>/dev/null || true

    local installed=0
    local skipped=0
    local errors=0
    local total_to_install
    total_to_install=$(wc -l < "$found_file")
    local processed=0
    em_drain_tty_buffer

    (
    local processed=0
    while IFS=$'\t' read -r md5 src dest_name sistema tipo; do
        ((processed++))
        echo $(( processed * 100 / total_to_install ))
        local dest_path="${BIOS_DIR}/${dest_name}"
        if [ -f "$dest_path" ]; then
            # Verifica se a existente é idêntica
            local existing_md5
            existing_md5=$(md5sum "$dest_path" 2>/dev/null | cut -d' ' -f1)
            if [ "$existing_md5" = "$md5" ]; then
                echo "skip" >> "${EM_TMP_DIR}/bios_skip"
            else
                # Substitui se for diferente (versão errada)
                if cp "$src" "$dest_path" 2>/dev/null; then
                    chown ark:ark "$dest_path" 2>/dev/null || true
                    echo "ok" >> "${EM_TMP_DIR}/bios_ok"
                else
                    echo "err" >> "${EM_TMP_DIR}/bios_err"
                fi
            fi
        else
            if cp "$src" "$dest_path" 2>/dev/null; then
                chown ark:ark "$dest_path" 2>/dev/null || true
                echo "ok" >> "${EM_TMP_DIR}/bios_ok"
            else
                echo "err" >> "${EM_TMP_DIR}/bios_err"
            fi
        fi
    done < "$found_file"
    ) | dialog --backtitle "$DIALOG_BACKTITLE" \
        --title "Instalar BIOS" \
        --gauge "Instalando arquivos de BIOS..." 8 60 0 \
        > "$CURR_TTY" 2> "$CURR_TTY"

    installed=$(grep -c "ok"   "${EM_TMP_DIR}/bios_ok"   2>/dev/null || echo 0)
    skipped=$(grep -c  "skip"  "${EM_TMP_DIR}/bios_skip" 2>/dev/null || echo 0)
    errors=$(grep -c   "err"   "${EM_TMP_DIR}/bios_err"  2>/dev/null || echo 0)
    rm -f "$found_file" "${EM_TMP_DIR}/bios_ok" "${EM_TMP_DIR}/bios_skip" "${EM_TMP_DIR}/bios_err"

    local result="Instalacao concluida.\n\n"
    result+="BIOS instaladas/atualizadas: ${installed}\n"
    result+="Ja estavam corretas (ignoradas): ${skipped}\n"
    [ "$errors" -gt 0 ] && result+="Erros: ${errors}\n"
    result+="\nDestino: ${BIOS_DIR}/"

    DIALOG_MSG "Instalar BIOS" "$result"
}

# =============================================================================
# MENU PRINCIPAL DO MÓDULO 4 (atualizado)
# =============================================================================
categoria_4() {
    while true; do
        local choice
        choice=$(DIALOG_MENU "Gestao da Colecao" "Selecione uma opcao:" \
            "1" "Backup de Saves" \
            "2" "Restaurar Saves" \
            "3" "Backup de BIOS" \
            "4" "Restaurar BIOS" \
            "5" "Exportar Colecao para Pendrive" \
            "6" "Sincronizar com Pendrive" \
            "7" "Instalar BIOS do Pendrive" \
            "0" "VOLTAR")

        local ret=$?
        [ "$(NORM_RET $ret)" == "VOLTAR" ] && return

        case "$choice" in
            1) em4_backup_saves ;;
            2) em4_restore_saves ;;
            3) em4_backup_bios ;;
            4) em4_restore_bios ;;
            5) em4_export_collection ;;
            6) em4_sync_with_usb ;;
            7) em4_install_bios_from_usb ;;
            0) return ;;
        esac
    done
}

# Permite executar este arquivo isoladamente para testes
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    categoria_4
fi
