#!/bin/bash
# =============================================================================
# Emulator Manager - cat_5_update_manager.sh
# Módulo 6 (menu): Atualizar Emulator Manager
#
# Baseado na arquitetura do cat_7_atualizador.sh (Alter_MThemes)
# Repositório: https://github.com/jotafhan/Emulator_Manager
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/init.sh"
source "${SCRIPT_DIR}/core.sh"

# =============================================================================
# CONFIGURAÇÃO
# =============================================================================
EM5_UPDATE_URL="https://raw.githubusercontent.com/jotafhan/Emulator_Manager/main"
EM5_VERSION_FILE="${EM_BASE_DIR}/lib/version.txt"
EM5_VERSION_LOCAL="$EM_VERSION"
[ -f "$EM5_VERSION_FILE" ] && EM5_VERSION_LOCAL=$(cat "$EM5_VERSION_FILE" 2>/dev/null | tr -d '[:space:]')

# Lista de arquivos gerenciados — formato: "local|remoto"
EM5_MANAGED_FILES=(
    "Emulator_Manager.sh|Emulator_Manager.sh"
    "lib/init.sh|lib/init.sh"
    "lib/core.sh|lib/core.sh"
    "lib/cat_1_rom_management.sh|lib/cat_1_rom_management.sh"
    "lib/cat_2_advanced_organization.sh|lib/cat_2_advanced_organization.sh"
    "lib/cat_3_emulator_tools.sh|lib/cat_3_emulator_tools.sh"
    "lib/cat_4_collection_manager.sh|lib/cat_4_collection_manager.sh"
    "lib/cat_5_update_manager.sh|lib/cat_5_update_manager.sh"
    "lib/cat_6_performance_tools.sh|lib/cat_6_performance_tools.sh"
    "lib/keys_emulator_manager.gptk|lib/keys_emulator_manager.gptk"
)

# Arrays compartilhados entre funções (preenchidos em _em5_verificar)
EM5_ARQUIVOS_PARA_ATUALIZAR=()
EM5_TMPS_PARA_ATUALIZAR=()
EM5_VERSION_REMOTA=""

# =============================================================================
# HELPERS
# =============================================================================

# Testa conectividade
_em5_tem_internet() {
    ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1
}

# Sincroniza relógio (evita falha de certificado TLS)
_em5_sincronizar_relogio() {
    sudo timedatectl set-ntp 1 2>/dev/null || true
}

# Baixa URL para arquivo temporário
# Retorna caminho do tmp em sucesso, vazio em falha
_em5_baixar_tmp() {
    local url="$1"
    local tmp
    tmp=$(mktemp /tmp/em_upd.XXXXXX)
    wget -q --timeout=15 --tries=2 --no-check-certificate \
        --header="Cache-Control: no-cache" \
        --header="Pragma: no-cache" \
        --user-agent="Mozilla/5.0 (Linux; Android)" \
        -O "$tmp" "$url" 2>>"/tmp/em_upd_wget.log"
    if [ $? -eq 0 ] && [ -s "$tmp" ]; then
        echo "$tmp"
    else
        rm -f "$tmp"
        echo ""
    fi
}

# Compara MD5 de arquivo local com temporário remoto
# Retorna 0 se diferentes (precisa atualizar), 1 se iguais
_em5_diferente() {
    local local_f="$1"
    local remote_f="$2"
    [ ! -f "$local_f" ] && return 0
    local md5_local md5_remote
    md5_local=$(md5sum "$local_f" 2>/dev/null | cut -d' ' -f1)
    md5_remote=$(md5sum "$remote_f" 2>/dev/null | cut -d' ' -f1)
    [ "$md5_local" != "$md5_remote" ] && return 0
    return 1
}

# =============================================================================
# 1. VERIFICAR E INSTALAR ATUALIZAÇÕES
# =============================================================================
_em5_verificar() {
    # Limpa arrays
    EM5_ARQUIVOS_PARA_ATUALIZAR=()
    EM5_TMPS_PARA_ATUALIZAR=()

    dialog --backtitle "$DIALOG_BACKTITLE" \
        --title "Verificando..." \
        --infobox "Testando conexao com o servidor..." \
        5 50 > "$CURR_TTY" 2>&1

    if ! _em5_tem_internet; then
        DIALOG_MSG "Sem Conexao" \
            "Sem conexao com a internet.\n\nVerifique o Wi-Fi e tente novamente."
        return 1
    fi

    # Sincroniza relógio antes de baixar
    _em5_sincronizar_relogio

    # Baixa version.txt remoto
    rm -f "/tmp/em_upd_wget.log"
    dialog --backtitle "$DIALOG_BACKTITLE" \
        --title "Verificando..." \
        --infobox "Baixando informacoes de versao..." \
        5 50 > "$CURR_TTY" 2>&1

    local tmp_ver
    tmp_ver=$(_em5_baixar_tmp "${EM5_UPDATE_URL}/lib/version.txt")

    if [ -z "$tmp_ver" ]; then
        local erro_detalhe
        erro_detalhe=$(tail -3 "/tmp/em_upd_wget.log" 2>/dev/null | tr -d '\r')
        DIALOG_MSG "Erro de Conexao" \
            "Nao foi possivel acessar o servidor.\n\nURL: ${EM5_UPDATE_URL}\n\nDetalhe:\n${erro_detalhe:-desconhecido}"
        return 1
    fi

    EM5_VERSION_REMOTA=$(cat "$tmp_ver" 2>/dev/null | tr -d '[:space:]')
    rm -f "$tmp_ver"

    # Compara versões
    if [ "$EM5_VERSION_REMOTA" = "$EM5_VERSION_LOCAL" ]; then
        DIALOG_MSG "Ja Atualizado" \
            "Voce ja esta na versao mais recente!\n\nVersao local : ${EM5_VERSION_LOCAL}\nVersao remota: ${EM5_VERSION_REMOTA}"
        return 0
    fi

    # Nova versão encontrada — verifica quais arquivos mudaram
    dialog --backtitle "$DIALOG_BACKTITLE" \
        --title "Nova Versao: ${EM5_VERSION_REMOTA}" \
        --infobox "Analisando arquivos modificados...\nIsso pode levar alguns segundos." \
        6 55 > "$CURR_TTY" 2>&1

    local entry local_path remote_path full_local url_remota tmp_arq
    for entry in "${EM5_MANAGED_FILES[@]}"; do
        local_path="${entry%%|*}"
        remote_path="${entry##*|}"
        full_local="${EM_BASE_DIR}/${local_path}"
        url_remota="${EM5_UPDATE_URL}/${remote_path}"

        tmp_arq=$(_em5_baixar_tmp "$url_remota")
        if [ -n "$tmp_arq" ]; then
            if _em5_diferente "$full_local" "$tmp_arq"; then
                EM5_ARQUIVOS_PARA_ATUALIZAR+=("$local_path")
                EM5_TMPS_PARA_ATUALIZAR+=("$tmp_arq")
            else
                rm -f "$tmp_arq"
            fi
        fi
    done

    if [ "${#EM5_ARQUIVOS_PARA_ATUALIZAR[@]}" -eq 0 ]; then
        # Versão diferente mas sem arquivos modificados — atualiza version.txt
        echo "$EM5_VERSION_REMOTA" > "$EM5_VERSION_FILE"
        DIALOG_MSG "Sem Mudancas" \
            "Versao remota: ${EM5_VERSION_REMOTA}\n\nNenhum arquivo foi modificado.\nVersao local atualizada para ${EM5_VERSION_REMOTA}."
        return 0
    fi

    # Monta lista do que vai ser atualizado
    local lista_info=""
    local arq
    for arq in "${EM5_ARQUIVOS_PARA_ATUALIZAR[@]}"; do
        lista_info+="  • ${arq}\n"
    done

    local confirm
    confirm=$(DIALOG_YESNO "Atualizacao Disponivel" \
        "Nova versao: ${EM5_VERSION_REMOTA}  (atual: ${EM5_VERSION_LOCAL})\n\nArquivos que serao atualizados (${#EM5_ARQUIVOS_PARA_ATUALIZAR[@]}):\n\n${lista_info}\nUm backup dos arquivos atuais sera feito antes.\n\nDeseja atualizar agora?")

    if [ "$confirm" -ne 0 ]; then
        # Limpa temporários
        local tmp
        for tmp in "${EM5_TMPS_PARA_ATUALIZAR[@]}"; do rm -f "$tmp"; done
        EM5_ARQUIVOS_PARA_ATUALIZAR=()
        EM5_TMPS_PARA_ATUALIZAR=()
        return 0
    fi

    _em5_aplicar
}

# =============================================================================
# Aplica os arquivos já baixados
# =============================================================================
_em5_aplicar() {
    local erros=0
    local ok=0
    local bak_dir="${EM_BASE_DIR}/lib/backups_update_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$bak_dir" 2>/dev/null

    printf '\033c' > "$CURR_TTY" 2>/dev/null || true
    printf "Aplicando atualizacao v%s...\n\n" "$EM5_VERSION_REMOTA" > "$CURR_TTY"

    local i=0
    local arq
    for arq in "${EM5_ARQUIVOS_PARA_ATUALIZAR[@]}"; do
        local full_local="${EM_BASE_DIR}/${arq}"
        local tmp="${EM5_TMPS_PARA_ATUALIZAR[$i]}"
        (( i++ ))

        printf "  Atualizando: %s\n" "$arq" > "$CURR_TTY"

        # Backup do arquivo local
        if [ -f "$full_local" ]; then
            local bak_nome
            bak_nome=$(echo "$arq" | tr '/' '_')
            cp "$full_local" "${bak_dir}/${bak_nome}.bak" 2>/dev/null
        fi

        # Garante que o diretório existe
        mkdir -p "$(dirname "$full_local")" 2>/dev/null

        # Aplica
        if cp "$tmp" "$full_local" 2>/dev/null; then
            chmod 755 "$full_local" 2>/dev/null
            chown ark:ark "$full_local" 2>/dev/null || true
            (( ok++ ))
        else
            printf "  ERRO ao atualizar: %s\n" "$arq" > "$CURR_TTY"
            (( erros++ ))
        fi
        rm -f "$tmp"
    done

    # Salva nova versão
    echo "$EM5_VERSION_REMOTA" > "$EM5_VERSION_FILE"
    chown ark:ark "$EM5_VERSION_FILE" 2>/dev/null || true
    chown -R ark:ark "$bak_dir" 2>/dev/null || true

    sleep 1

    if [ "$erros" -eq 0 ]; then
        DIALOG_MSG "Atualizacao Concluida" \
            "Atualizacao concluida com sucesso!\n\nVersao anterior : ${EM5_VERSION_LOCAL}\nVersao atual    : ${EM5_VERSION_REMOTA}\nArquivos atualizados: ${ok}\n\nBackup em:\n${bak_dir}\n\nReinicie o Emulator Manager para aplicar."
    else
        DIALOG_MSG "Atualizacao Parcial" \
            "Atualizacao concluida com erros.\n\nOK    : ${ok} arquivo(s)\nErros : ${erros} arquivo(s)\n\nBackup em:\n${bak_dir}"
    fi

    # Limpa arrays
    EM5_ARQUIVOS_PARA_ATUALIZAR=()
    EM5_TMPS_PARA_ATUALIZAR=()
}

# =============================================================================
# 2. HISTÓRICO DE BACKUPS DE ATUALIZAÇÃO
# =============================================================================
_em5_historico() {
    local baks_list=()
    local d
    while IFS= read -r -d '' d; do
        baks_list+=("$d")
    done < <(find "${EM_BASE_DIR}/lib" -maxdepth 1 -name "backups_update_*" \
        -type d -print0 2>/dev/null | sort -rz)

    if [ "${#baks_list[@]}" -eq 0 ]; then
        DIALOG_MSG "Historico" \
            "Nenhum backup de atualizacao encontrado.\n\nOs backups sao criados automaticamente ao atualizar."
        return
    fi

    local menu_items=()
    local d
    for d in "${baks_list[@]}"; do
        local dname; dname=$(basename "$d")
        local count; count=$(find "$d" -name "*.bak" 2>/dev/null | wc -l)
        menu_items+=("$dname" "${count} arquivo(s)")
    done

    local choice
    choice=$(DIALOG_MENU "Historico de Atualizacoes" \
        "Backups disponíveis (mais recente primeiro):" "${menu_items[@]}")
    [ "$(NORM_RET $?)" == "VOLTAR" ] && return

    # Lista os arquivos dentro do backup selecionado
    local bak_path="${EM_BASE_DIR}/lib/${choice}"
    local files_list
    files_list=$(find "$bak_path" -name "*.bak" -printf '%f\n' 2>/dev/null | sort)

    DIALOG_MSG "Backup: ${choice}" \
        "Arquivos contidos neste backup:\n\n${files_list}\n\nUse 'Reverter para Backup' para restaurar."
}

# =============================================================================
# 3. REVERTER PARA BACKUP
# =============================================================================
_em5_reverter() {
    local baks_list=()
    local d
    while IFS= read -r -d '' d; do
        baks_list+=("$d")
    done < <(find "${EM_BASE_DIR}/lib" -maxdepth 1 -name "backups_update_*" \
        -type d -print0 2>/dev/null | sort -rz)

    if [ "${#baks_list[@]}" -eq 0 ]; then
        DIALOG_MSG "Reverter" \
            "Nenhum backup de atualizacao encontrado.\n\nOs backups sao criados automaticamente ao atualizar."
        return
    fi

    local menu_items=()
    for d in "${baks_list[@]}"; do
        local dname; dname=$(basename "$d")
        local count; count=$(find "$d" -name "*.bak" 2>/dev/null | wc -l)
        menu_items+=("$dname" "${count} arquivo(s)")
    done

    local choice
    choice=$(DIALOG_MENU "Reverter para Backup" \
        "Escolha o backup para restaurar:" "${menu_items[@]}")
    [ "$(NORM_RET $?)" == "VOLTAR" ] && return

    local bak_path="${EM_BASE_DIR}/lib/${choice}"

    local confirm
    confirm=$(DIALOG_YESNO "Reverter" \
        "Restaurar backup:\n${choice}\n\nOs arquivos atuais serao substituidos pelos do backup.\n\nDeseja continuar?")
    [ "$confirm" -ne 0 ] && return

    printf '\033c' > "$CURR_TTY" 2>/dev/null || true
    printf "Revertendo para %s...\n\n" "$choice" > "$CURR_TTY"

    local ok=0 erros=0
    local bak
    for bak in "${bak_path}"/*.bak; do
        [ -f "$bak" ] || continue
        # Reconstrói o caminho original: _ volta a /
        local dest_rel
        dest_rel=$(basename "$bak" .bak | tr '_' '/')
        local dest="${EM_BASE_DIR}/${dest_rel}"
        printf "  Restaurando: %s\n" "$dest_rel" > "$CURR_TTY"
        if cp "$bak" "$dest" 2>/dev/null; then
            chmod 755 "$dest" 2>/dev/null
            chown ark:ark "$dest" 2>/dev/null || true
            (( ok++ ))
        else
            printf "  ERRO: %s\n" "$dest_rel" > "$CURR_TTY"
            (( erros++ ))
        fi
    done

    sleep 1

    DIALOG_MSG "Revertido" \
        "Backup restaurado.\n\nArquivos restaurados: ${ok}\nErros: ${erros}\n\nReinicie o Emulator Manager para aplicar."
}

# =============================================================================
# MENU PRINCIPAL DO MÓDULO 6
# =============================================================================
categoria_5() {
    while true; do
        local choice
        choice=$(DIALOG_MENU "Atualizar Emulator Manager" \
            "Versao local : ${EM5_VERSION_LOCAL}\nServidor      : github.com/jotafhan/Emulator_Manager" \
            "1" "Verificar e Instalar Atualizacoes" \
            "2" "Historico de Atualizacoes" \
            "3" "Reverter para Backup Anterior" \
            "0" "VOLTAR")

        local ret=$?
        [ "$(NORM_RET $ret)" == "VOLTAR" ] && return

        case "$choice" in
            1) _em5_verificar ;;
            2) _em5_historico ;;
            3) _em5_reverter ;;
            0) return ;;
        esac
    done
}

# Permite executar este arquivo isoladamente para testes
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    categoria_5
fi
