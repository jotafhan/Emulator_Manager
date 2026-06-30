#!/bin/bash
# =============================================================================
# Emulator Manager - cat_5_update_manager.sh
# Módulo: Atualizar Emulator Manager (via GitHub)
#
# Repositório: https://github.com/jotafhan/Emulator_Manager
# Branch: main
#
# Opções implementadas:
#   1. Verificar atualizacoes disponiveis
#   2. Atualizar agora (com backup automatico antes)
#   3. Ver cabecalho do ultimo arquivo baixado / changelog simples
#   4. Configurar URL do repositorio (avancado)
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/init.sh"
source "${SCRIPT_DIR}/core.sh"

# =============================================================================
# CONFIGURAÇÃO DO REPOSITÓRIO
# =============================================================================
EM5_GH_USER="jotafhan"
EM5_GH_REPO="Emulator_Manager"
EM5_GH_BRANCH="main"
EM5_RAW_BASE="https://raw.githubusercontent.com/${EM5_GH_USER}/${EM5_GH_REPO}/${EM5_GH_BRANCH}"

# Lista de arquivos gerenciados pelo update (caminho relativo ao projeto)
EM5_MANAGED_FILES=(
    "Emulator_Manager.sh"
    "lib/init.sh"
    "lib/core.sh"
    "lib/cat_1_rom_management.sh"
    "lib/cat_2_advanced_organization.sh"
    "lib/cat_3_emulator_tools.sh"
    "lib/cat_4_collection_manager.sh"
)

EM5_UPDATE_BACKUP_DIR="${EM_DATA_DIR}/backups/pre_update"
EM5_TMP_UPDATE_DIR="${EM_TMP_DIR}/update_staging"

# =============================================================================
# HELPERS INTERNOS
# =============================================================================

em5_init_dirs() {
    mkdir -p "$EM5_UPDATE_BACKUP_DIR" "$EM5_TMP_UPDATE_DIR"
    chown ark:ark "$EM5_UPDATE_BACKUP_DIR" 2>/dev/null || true
}

# Testa conectividade com o GitHub (raw.githubusercontent.com)
em5_check_connectivity() {
    if ! em_has_tool curl && ! em_has_tool wget; then
        return 2  # nenhuma ferramenta disponível
    fi
    if em_has_tool curl; then
        curl -sf --max-time 8 -o /dev/null "${EM5_RAW_BASE}/Emulator_Manager.sh" && return 0
        return 1
    else
        wget -q --timeout=8 -O /dev/null "${EM5_RAW_BASE}/Emulator_Manager.sh" && return 0
        return 1
    fi
}

# Baixa um arquivo para um destino temporário
# Uso: em5_download "lib/core.sh" "/tmp/destino.sh"
em5_download() {
    local rel_path="$1"
    local dest="$2"
    local url="${EM5_RAW_BASE}/${rel_path}"

    if em_has_tool curl; then
        curl -sf --max-time 20 -o "$dest" "$url" 2>/dev/null
    elif em_has_tool wget; then
        wget -q --timeout=20 -O "$dest" "$url" 2>/dev/null
    else
        return 1
    fi
}

# Caminho local absoluto correspondente a um caminho relativo do repo
em5_local_path() {
    local rel_path="$1"
    echo "${EM_BASE_DIR}/${rel_path}"
}

# =============================================================================
# 1. VERIFICAR ATUALIZAÇÕES DISPONÍVEIS
# Baixa cada arquivo remoto para staging e compara com o local via diff.
# Não substitui nada — apenas informa o que está diferente.
# =============================================================================
em5_check_updates() {
    em5_init_dirs

    if ! em_has_tool curl && ! em_has_tool wget; then
        DIALOG_MSG "Verificar Atualizacoes" \
            "Nenhuma ferramenta de download encontrada (curl ou wget).\n\nInstale com: apt install curl"
        return
    fi

    DIALOG_MSG "Verificar Atualizacoes" "Testando conexao com o GitHub...\n\nIsso pode levar alguns segundos."

    em5_check_connectivity
    local conn_ret=$?
    if [ "$conn_ret" -ne 0 ]; then
        DIALOG_MSG "Sem Conexao" \
            "Nao foi possivel conectar ao GitHub.\n\nVerifique sua conexao com a internet e tente novamente.\n\nRepositorio:\n${EM5_RAW_BASE}"
        return
    fi

    rm -rf "$EM5_TMP_UPDATE_DIR"
    mkdir -p "$EM5_TMP_UPDATE_DIR/lib"

    local total="${#EM5_MANAGED_FILES[@]}"
    local changed_file="${EM_TMP_DIR}/update_changed"
    local missing_file="${EM_TMP_DIR}/update_missing"
    > "$changed_file"
    > "$missing_file"
    em_drain_tty_buffer

    (
    local processed=0
    local rel
    for rel in "${EM5_MANAGED_FILES[@]}"; do
        ((processed++))
        echo $(( processed * 100 / total ))
        local staging_dest="${EM5_TMP_UPDATE_DIR}/${rel}"
        mkdir -p "$(dirname "$staging_dest")" 2>/dev/null

        if em5_download "$rel" "$staging_dest"; then
            local local_file
            local_file=$(em5_local_path "$rel")
            if [ ! -f "$local_file" ]; then
                echo "$rel" >> "$missing_file"
            elif ! diff -q "$local_file" "$staging_dest" >/dev/null 2>&1; then
                echo "$rel" >> "$changed_file"
            fi
        fi
    done
    ) | dialog --backtitle "$DIALOG_BACKTITLE" \
        --title "Verificar Atualizacoes" \
        --gauge "Comparando arquivos com o repositorio..." 8 60 0 \
        > "$CURR_TTY" 2> "$CURR_TTY"

    local changed_count missing_count
    changed_count=$(grep -c . "$changed_file" 2>/dev/null || echo 0)
    missing_count=$(grep -c . "$missing_file" 2>/dev/null || echo 0)

    if [ "$changed_count" -eq 0 ] && [ "$missing_count" -eq 0 ]; then
        DIALOG_MSG "Verificar Atualizacoes" \
            "Voce ja esta com a versao mais recente.\n\nNenhum arquivo precisa ser atualizado."
        rm -rf "$EM5_TMP_UPDATE_DIR"
        rm -f "$changed_file" "$missing_file"
        return
    fi

    local preview=""
    [ "$changed_count" -gt 0 ] && preview+="Arquivos modificados:\n$(cat "$changed_file")\n\n"
    [ "$missing_count" -gt 0 ] && preview+="Arquivos novos (nao existem localmente):\n$(cat "$missing_file")\n\n"

    rm -f "$changed_file" "$missing_file"

    DIALOG_MSG "Atualizacao Disponivel" \
        "Encontradas atualizacoes!\n\n${preview}Use a opcao 'Atualizar agora' no menu para aplicar.\n\n(Um backup automatico sera feito antes de qualquer alteracao)"
}

# =============================================================================
# 2. ATUALIZAR AGORA
# Baixa todos os arquivos, faz backup dos atuais, substitui.
# =============================================================================
em5_update_now() {
    em5_init_dirs

    if ! em_has_tool curl && ! em_has_tool wget; then
        DIALOG_MSG "Atualizar" \
            "Nenhuma ferramenta de download encontrada (curl ou wget).\n\nInstale com: apt install curl"
        return
    fi

    DIALOG_MSG "Atualizar" "Testando conexao com o GitHub..."
    em5_check_connectivity
    if [ $? -ne 0 ]; then
        DIALOG_MSG "Sem Conexao" \
            "Nao foi possivel conectar ao GitHub.\n\nVerifique sua conexao e tente novamente."
        return
    fi

    local confirm
    confirm=$(DIALOG_YESNO "Atualizar Emulator Manager" \
        "Isso ira:\n\n1. Baixar a versao mais recente do GitHub\n2. Fazer backup dos arquivos atuais\n3. Substituir pelos novos arquivos\n\nRepositorio:\n${EM5_GH_USER}/${EM5_GH_REPO}\n\nDeseja continuar?")
    [ "$confirm" -ne 0 ] && return

    rm -rf "$EM5_TMP_UPDATE_DIR"
    mkdir -p "$EM5_TMP_UPDATE_DIR/lib"

    local total="${#EM5_MANAGED_FILES[@]}"
    local downloaded_file="${EM_TMP_DIR}/update_downloaded"
    local failed_file="${EM_TMP_DIR}/update_failed"
    echo 0 > "$downloaded_file"
    > "$failed_file"
    em_drain_tty_buffer

    # --- Etapa 1: Download para staging ---
    (
    local processed=0 downloaded=0
    local rel
    for rel in "${EM5_MANAGED_FILES[@]}"; do
        ((processed++))
        echo $(( processed * 100 / total ))
        local staging_dest="${EM5_TMP_UPDATE_DIR}/${rel}"
        mkdir -p "$(dirname "$staging_dest")" 2>/dev/null

        if em5_download "$rel" "$staging_dest" && [ -s "$staging_dest" ]; then
            # Validação básica: arquivo .sh deve começar com shebang
            if head -1 "$staging_dest" 2>/dev/null | grep -q '^#!/bin/bash'; then
                ((downloaded++))
                echo "$downloaded" > "$downloaded_file"
            else
                echo "$rel" >> "$failed_file"
                rm -f "$staging_dest"
            fi
        else
            echo "$rel" >> "$failed_file"
        fi
    done
    ) | dialog --backtitle "$DIALOG_BACKTITLE" \
        --title "Atualizar" \
        --gauge "Baixando arquivos do GitHub..." 8 60 0 \
        > "$CURR_TTY" 2> "$CURR_TTY"

    local downloaded
    downloaded=$(cat "$downloaded_file" 2>/dev/null || echo 0)
    local failed_count
    failed_count=$(grep -c . "$failed_file" 2>/dev/null || echo 0)
    rm -f "$downloaded_file"

    if [ "$downloaded" -eq 0 ]; then
        DIALOG_MSG "Erro" \
            "Nenhum arquivo pode ser baixado.\n\nVerifique sua conexao e tente novamente."
        rm -rf "$EM5_TMP_UPDATE_DIR"
        rm -f "$failed_file"
        return
    fi

    if [ "$failed_count" -gt 0 ]; then
        local failed_list
        failed_list=$(cat "$failed_file")
        local proceed_anyway
        proceed_anyway=$(DIALOG_YESNO "Aviso" \
            "Alguns arquivos nao puderam ser baixados:\n\n${failed_list}\n\nDeseja continuar atualizando apenas os arquivos baixados com sucesso (${downloaded}/${total})?")
        if [ "$proceed_anyway" -ne 0 ]; then
            rm -rf "$EM5_TMP_UPDATE_DIR"
            rm -f "$failed_file"
            DIALOG_MSG "Atualizar" "Atualizacao cancelada.\nNenhum arquivo foi alterado."
            return
        fi
    fi
    rm -f "$failed_file"

    # --- Etapa 2: Backup dos arquivos atuais ---
    local timestamp
    timestamp=$(date '+%Y%m%d_%H%M%S')
    local backup_dest="${EM5_UPDATE_BACKUP_DIR}/backup_pre_update_${timestamp}.tar.gz"

    local existing_files=()
    local rel
    for rel in "${EM5_MANAGED_FILES[@]}"; do
        local local_file
        local_file=$(em5_local_path "$rel")
        [ -f "$local_file" ] && existing_files+=("$local_file")
    done

    if [ "${#existing_files[@]}" -gt 0 ]; then
        tar -czf "$backup_dest" --ignore-failed-read "${existing_files[@]}" 2>/dev/null
        chown ark:ark "$backup_dest" 2>/dev/null || true
    fi

    # --- Etapa 3: Substitui os arquivos locais pelos baixados ---
    local applied=0
    local apply_errors=0
    for rel in "${EM5_MANAGED_FILES[@]}"; do
        local staging_file="${EM5_TMP_UPDATE_DIR}/${rel}"
        [ -f "$staging_file" ] || continue
        local local_file
        local_file=$(em5_local_path "$rel")
        mkdir -p "$(dirname "$local_file")" 2>/dev/null

        if cp "$staging_file" "$local_file" 2>/dev/null; then
            chmod +x "$local_file" 2>/dev/null || true
            chown ark:ark "$local_file" 2>/dev/null || true
            ((applied++))
        else
            ((apply_errors++))
        fi
    done

    rm -rf "$EM5_TMP_UPDATE_DIR"

    local result_msg="Atualizacao concluida.\n\nArquivos atualizados: ${applied}/${total}"
    [ "$apply_errors" -gt 0 ] && result_msg+="\nErros ao aplicar: ${apply_errors}"
    [ -f "$backup_dest" ] && result_msg+="\n\nBackup da versao anterior:\n${backup_dest}"
    result_msg+="\n\nReinicie o Emulator Manager para usar a nova versao."

    DIALOG_MSG "Atualizacao Concluida" "$result_msg"
}

# =============================================================================
# 3. RESTAURAR VERSÃO ANTERIOR (a partir do backup automático)
# =============================================================================
em5_restore_previous() {
    local backup_files=()
    local f
    while IFS= read -r -d '' f; do
        backup_files+=("$f")
    done < <(find "$EM5_UPDATE_BACKUP_DIR" -maxdepth 1 -name "backup_pre_update_*.tar.gz" -print0 2>/dev/null | sort -rz)

    if [ "${#backup_files[@]}" -eq 0 ]; then
        DIALOG_MSG "Restaurar Versao Anterior" \
            "Nenhum backup de atualizacao encontrado.\n\nBackups sao criados automaticamente sempre que voce usa 'Atualizar agora'."
        return
    fi

    local menu_items=()
    for f in "${backup_files[@]}"; do
        local fname; fname=$(basename "$f")
        local fdate; fdate=$(stat -c%y "$f" 2>/dev/null | cut -d'.' -f1)
        menu_items+=("$fname" "$fdate")
    done

    local choice
    choice=$(DIALOG_MENU "Restaurar Versao Anterior" \
        "Escolha o backup para restaurar:" "${menu_items[@]}")
    [ "$(NORM_RET $?)" == "VOLTAR" ] && return

    local src="${EM5_UPDATE_BACKUP_DIR}/${choice}"
    local confirm
    confirm=$(DIALOG_YESNO "Restaurar Versao Anterior" \
        "Isso ira reverter o Emulator Manager para a versao salva em:\n${choice}\n\nDeseja continuar?")
    [ "$confirm" -ne 0 ] && return

    if tar -xzf "$src" -C / 2>/dev/null; then
        DIALOG_MSG "Restaurar Versao Anterior" \
            "Versao anterior restaurada com sucesso.\n\nReinicie o Emulator Manager para aplicar."
    else
        DIALOG_MSG "Erro" "Nao foi possivel restaurar o backup.\n\nO arquivo pode estar corrompido."
    fi
}

# =============================================================================
# MENU PRINCIPAL DO MÓDULO 5
# =============================================================================
categoria_5() {
    while true; do
        local choice
        choice=$(DIALOG_MENU "Atualizar Emulator Manager" "Selecione uma opcao:" \
            "1" "Verificar atualizacoes disponiveis" \
            "2" "Atualizar agora" \
            "3" "Restaurar versao anterior" \
            "0" "VOLTAR")

        local ret=$?
        [ "$(NORM_RET $ret)" == "VOLTAR" ] && return

        case "$choice" in
            1) em5_check_updates ;;
            2) em5_update_now ;;
            3) em5_restore_previous ;;
            0) return ;;
        esac
    done
}

# Permite executar este arquivo isoladamente para testes
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    categoria_5
fi
