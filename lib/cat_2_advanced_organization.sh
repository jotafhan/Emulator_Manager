#!/bin/bash
# =============================================================================
# Emulator Manager - cat_2_advanced_organization.sh
# Módulo 2: Organização Avançada
#
# Opções implementadas (todas offline):
#   1. Organizar por região      (subpastas USA / Japan / Europe / World / Outros)
#   2. Separar BIOS              (move arquivos [BIOS] para subpasta bios/)
#   3. Remover Beta/Proto/Demo   (move para subpasta nao_licenciados/)
#   4. Filtro 1G1R               (mantém melhor versão, move resto para descartados/)
#   5. Remover hacks/traduções   (detecta [h] [T+...] etc, move para hacks/)
#   6. Limpar tags do nome       (renomeia no lugar removendo tags desnecessárias)
#   7. Padronizar maiúsculas     (renomeia aplicando Title Case no nome)
#   8. Exportar lista de ROMs    (gera .txt ou .csv por sistema)
#   9. Comparar com lista ext.   (mostra o que falta na sua coleção)
#  10. Manutenção da coleção     (extensão errada / tamanho zero / pasta errada)
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/init.sh"
source "${SCRIPT_DIR}/core.sh"

# =============================================================================
# HELPERS INTERNOS DO MÓDULO 2
# =============================================================================

# -----------------------------------------------------------------------------
# Detecta a região de uma ROM pelo nome do arquivo (padrão No-Intro).
# Retorna: USA | Japan | Europe | World | Outros
# Exemplos:
#   "Sonic (USA).gba"          → USA
#   "Dragon Ball Z (Japan).gba" → Japan
#   "FIFA (Europe).gba"         → Europe
#   "Tetris (World).gba"        → World
#   "Homebrew Game.gba"         → Outros
# -----------------------------------------------------------------------------
em2_detect_region() {
    local name="$1"
    # Ordem importa: World antes de USA/Europe para evitar falso positivo
    if echo "$name" | grep -qiE '\(World\)'; then
        echo "World"
    elif echo "$name" | grep -qiE '\((USA|U)\)'; then
        echo "USA"
    elif echo "$name" | grep -qiE '\((Europe|EUR|E)\)'; then
        echo "Europe"
    elif echo "$name" | grep -qiE '\((Japan|JPN|J)\)'; then
        echo "Japan"
    elif echo "$name" | grep -qiE '\((Brazil|Brasil|BRA)\)'; then
        echo "Brazil"
    elif echo "$name" | grep -qiE '\((Korea|KOR)\)'; then
        echo "Korea"
    elif echo "$name" | grep -qiE '\((China|CHN)\)'; then
        echo "China"
    elif echo "$name" | grep -qiE '\((Australia|AUS)\)'; then
        echo "Australia"
    else
        echo "Outros"
    fi
}

# -----------------------------------------------------------------------------
# Detecta se um nome de arquivo é BIOS.
# -----------------------------------------------------------------------------
em2_is_bios() {
    echo "$1" | grep -qiE '^\[BIOS\]'
}

# -----------------------------------------------------------------------------
# Detecta se um nome tem tags de versão indesejada (Beta/Proto/Demo/Sample).
# -----------------------------------------------------------------------------
em2_is_unlicensed_release() {
    echo "$1" | grep -qiE '\((Beta|Proto|Demo|Sample|Preview|Prototype)[^)]*\)'
}

# -----------------------------------------------------------------------------
# Detecta se um nome tem tags de hack ou tradução não oficial.
# Padrões: [h], [h1], [hI], [T+Eng], [T-Por], [T+...], [a], [b], [o]
# -----------------------------------------------------------------------------
em2_is_hack_or_translation() {
    echo "$1" | grep -qiE '\[(h[0-9a-zA-Z]*|T[+-][a-zA-Z]+|a[0-9]?|b[0-9]?|o[0-9]?)\]'
}

# -----------------------------------------------------------------------------
# Remove tags de organização do nome de um arquivo, retornando o nome limpo.
# Remove: (USA) (Japan) (Europe) (World) (Rev X) (v1.0) (En,Fr,De) (Beta) etc.
# Mantém o título principal intacto.
# -----------------------------------------------------------------------------
em2_clean_name() {
    local name="$1"
    # Remove extensão para trabalhar só com o nome
    local ext="${name##*.}"
    local base="${name%.*}"

    # Remove tags entre parênteses comuns (região, revisão, idiomas, versão...)
    base=$(echo "$base" | sed -E \
        -e 's/ \((USA|Japan|Europe|World|Brazil|Korea|China|Australia)[^)]*\)//gi' \
        -e 's/ \((En|Fr|De|Es|It|Nl|Pt|Sv|No|Da|Fi|Zh|Ko|Ja|Ru|Pl)[^)]*\)//gi' \
        -e 's/ \(Rev [0-9A-Za-z.]+\)//gi' \
        -e 's/ \(v[0-9]+\.[0-9.]+\)//gi' \
        -e 's/ \(Beta[^)]*\)//gi' \
        -e 's/ \(Proto[^)]*\)//gi' \
        -e 's/ \(Demo[^)]*\)//gi' \
        -e 's/ \(Sample[^)]*\)//gi' \
        -e 's/ \(Preview[^)]*\)//gi' \
        -e 's/ \(Kiosk[^)]*\)//gi' \
        -e 's/ \(Virtual Console[^)]*\)//gi' \
        -e 's/ \(GameCube[^)]*\)//gi' \
        -e 's/ \(Classic[^)]*\)//gi' \
    )

    # Remove tags entre colchetes [h] [T+...] etc
    base=$(echo "$base" | sed -E 's/ \[[^]]*\]//g')

    # Remove espaços extras nas bordas
    base=$(echo "$base" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')

    echo "${base}.${ext}"
}

# -----------------------------------------------------------------------------
# Aplica Title Case a uma string (primeira letra de cada palavra em maiúsculo).
# Palavras de ligação (the, of, a, an, in, on, at, to, for, and, or, but, nor)
# ficam em minúsculo, exceto se forem a primeira palavra.
# -----------------------------------------------------------------------------
em2_title_case() {
    local input="$1"
    local ext="${input##*.}"
    local base="${input%.*}"

    local result
    result=$(echo "$base" | python3 -c "
import sys, re
LOWER_WORDS = {'the','of','a','an','in','on','at','to','for','and','or','but','nor','is','as'}
text = sys.stdin.read().strip()
words = text.split(' ')
out = []
for i, w in enumerate(words):
    # Preserva tokens entre parênteses e colchetes como estão
    if re.match(r'^[\(\[\{]', w):
        out.append(w)
    elif i == 0 or w.lower() not in LOWER_WORDS:
        out.append(w.capitalize())
    else:
        out.append(w.lower())
print(' '.join(out))
" 2>/dev/null)

    [ -z "$result" ] && result="$base"
    echo "${result}.${ext}"
}

# -----------------------------------------------------------------------------
# Prioridade 1G1R: retorna um número de prioridade (menor = melhor).
# Critério: USA=1, World=2, Europe=3, Japan=4, outros=5
# Dentro da mesma região, versão mais alta / sem Beta/Proto ganha.
# -----------------------------------------------------------------------------
em2_1g1r_priority() {
    local name="$1"
    local region
    region=$(em2_detect_region "$name")

    local reg_score=5
    case "$region" in
        USA)       reg_score=1 ;;
        World)     reg_score=2 ;;
        Europe)    reg_score=3 ;;
        Japan)     reg_score=4 ;;
    esac

    # Penaliza Beta/Proto/Demo
    local penalty=0
    em2_is_unlicensed_release "$name" && penalty=10

    echo $(( reg_score + penalty ))
}

# -----------------------------------------------------------------------------
# Move arquivo para subpasta, criando a pasta se necessário.
# Trata conflitos de nome adicionando sufixo numérico.
# Retorna 0 em sucesso, 1 em falha.
# -----------------------------------------------------------------------------
em2_move_to_subdir() {
    local src="$1"
    local subdir_name="$2"   # nome da subpasta (ex: "USA", "bios", "hacks")

    local dir
    dir=$(dirname "$src")
    local fname
    fname=$(basename "$src")
    local dst_dir="${dir}/${subdir_name}"

    mkdir -p "$dst_dir"
    chown ark:ark "$dst_dir" 2>/dev/null || true

    local dst="${dst_dir}/${fname}"
    if [ -e "$dst" ] && [ "$dst" != "$src" ]; then
        local base="${fname%.*}"
        local ext="${fname##*.}"
        local i=2
        while [ -e "${dst_dir}/${base}_${i}.${ext}" ]; do ((i++)); done
        dst="${dst_dir}/${base}_${i}.${ext}"
    fi

    mv -- "$src" "$dst" 2>/dev/null
}

# =============================================================================
# 1. ORGANIZAR POR REGIÃO
# =============================================================================
em2_organize_by_region() {
    local systems
    mapfile -t systems < <(em_list_existing_systems)
    local menu_items=()
    local sys
    for sys in "${systems[@]}"; do
        menu_items+=("$sys" "$sys")
    done
    menu_items+=("TODOS" "Todos os sistemas")

    local choice
    choice=$(DIALOG_MENU "Organizar por Regiao" "Escolha o sistema:" "${menu_items[@]}")
    [ "$(NORM_RET $?)" == "VOLTAR" ] && return

    local targets=()
    if [ "$choice" == "TODOS" ]; then
        targets=("${systems[@]}")
    else
        targets=("$choice")
    fi

    # Prévia antes de mover
    local preview=""
    local preview_count=0
    local total_to_move=0
    local sysname f
    for sysname in "${targets[@]}"; do
        while IFS= read -r -d '' f; do
            local ext="${f##*.}"
            em_is_rom_extension "$ext" || continue
            local fname
            fname=$(basename "$f")
            local region
            region=$(em2_detect_region "$fname")
            preview+="${fname}  →  ${region}/\n"
            ((total_to_move++))
            ((preview_count++))
            [ "$preview_count" -ge 15 ] && break 2
        done < <(find "${ROMS_BASE_DIR}/${sysname}" -maxdepth 1 -type f -print0 2>/dev/null)
    done

    [ "$total_to_move" -eq 0 ] && {
        DIALOG_MSG "Organizar por Regiao" "Nenhuma ROM encontrada para organizar."
        return
    }

    local overflow=""
    [ "$total_to_move" -ge 15 ] && overflow="\n... e mais arquivos."

    local confirm
    confirm=$(DIALOG_YESNO "Organizar por Regiao" \
        "As ROMs serao movidas para subpastas por regiao:\n  USA/ Japan/ Europe/ World/ Outros/\n\n${preview}${overflow}\nTotal a mover: ${total_to_move}+\n\nDeseja continuar?")
    [ "$confirm" -ne 0 ] && return

    # Conta total real para gauge
    local total_real=0
    for sysname in "${targets[@]}"; do
        while IFS= read -r -d '' f; do
            local ext="${f##*.}"
            em_is_rom_extension "$ext" && ((total_real++))
        done < <(find "${ROMS_BASE_DIR}/${sysname}" -maxdepth 1 -type f -print0 2>/dev/null)
    done

    local moved_file="${EM_TMP_DIR}/region_moved"
    local errors_file="${EM_TMP_DIR}/region_errors"
    echo 0 > "$moved_file"; echo 0 > "$errors_file"
    local report="${EM_DATA_DIR}/region_report.txt"
    echo "Organizar por Regiao - $(date '+%Y-%m-%d %H:%M:%S')" > "$report"
    em_drain_tty_buffer

    (
    local processed=0 moved=0 errors=0
    for sysname in "${targets[@]}"; do
        while IFS= read -r -d '' f; do
            local ext="${f##*.}"
            em_is_rom_extension "$ext" || continue
            ((processed++))
            local pct=$(( processed * 100 / total_real ))
            local fname; fname=$(basename "$f")
            echo "$pct"
            local region; region=$(em2_detect_region "$fname")
            if em2_move_to_subdir "$f" "$region"; then
                echo "[OK] ${fname} → ${region}/" >> "$report"
                ((moved++)); echo "$moved" > "$moved_file"
            else
                echo "[ERRO] ${fname}" >> "$report"
                ((errors++)); echo "$errors" > "$errors_file"
            fi
        done < <(find "${ROMS_BASE_DIR}/${sysname}" -maxdepth 1 -type f -print0 2>/dev/null)
    done
    ) | dialog --backtitle "$DIALOG_BACKTITLE" --title "Organizar por Regiao" \
        --gauge "Movendo ROMs para subpastas por regiao..." 8 60 0 \
        > "$CURR_TTY" 2> "$CURR_TTY"

    local moved errors
    moved=$(cat "$moved_file" 2>/dev/null || echo 0)
    errors=$(cat "$errors_file" 2>/dev/null || echo 0)
    rm -f "$moved_file" "$errors_file"
    chown ark:ark "$report" 2>/dev/null || true
    DIALOG_MSG "Organizar por Regiao" \
        "Concluido.\n\nArquivos movidos: ${moved}\nErros: ${errors}\n\nRelatorio salvo em:\n${report}"
}

# =============================================================================
# 2. SEPARAR BIOS
# =============================================================================
em2_separate_bios() {
    local systems
    mapfile -t systems < <(em_list_existing_systems)

    local menu_items=()
    local sys
    for sys in "${systems[@]}"; do
        menu_items+=("$sys" "$sys")
    done
    menu_items+=("TODOS" "Todos os sistemas")

    local choice
    choice=$(DIALOG_MENU "Separar BIOS" "Escolha o sistema:" "${menu_items[@]}")
    [ "$(NORM_RET $?)" == "VOLTAR" ] && return

    local targets=()
    [ "$choice" == "TODOS" ] && targets=("${systems[@]}") || targets=("$choice")

    local found=0
    local preview=""
    local sysname f
    for sysname in "${targets[@]}"; do
        while IFS= read -r -d '' f; do
            local fname
            fname=$(basename "$f")
            if em2_is_bios "$fname"; then
                preview+="${fname}\n"
                ((found++))
            fi
        done < <(find "${ROMS_BASE_DIR}/${sysname}" -maxdepth 1 -type f -print0 2>/dev/null)
    done

    [ "$found" -eq 0 ] && {
        DIALOG_MSG "Separar BIOS" "Nenhum arquivo de BIOS encontrado\n(arquivos com nome iniciando em [BIOS])."
        return
    }

    local confirm
    confirm=$(DIALOG_YESNO "Separar BIOS" \
        "Arquivos de BIOS encontrados: ${found}\n\n${preview}\nSerao movidos para a subpasta bios/ dentro de cada sistema.\n\nDeseja continuar?")
    [ "$confirm" -ne 0 ] && return

    local moved=0
    local errors=0
    for sysname in "${targets[@]}"; do
        while IFS= read -r -d '' f; do
            local fname
            fname=$(basename "$f")
            em2_is_bios "$fname" || continue
            if em2_move_to_subdir "$f" "bios"; then
                ((moved++))
            else
                ((errors++))
            fi
        done < <(find "${ROMS_BASE_DIR}/${sysname}" -maxdepth 1 -type f -print0 2>/dev/null)
    done

    DIALOG_MSG "Separar BIOS" \
        "Concluido.\n\nArquivos movidos para bios/: ${moved}\nErros: ${errors}"
}

# =============================================================================
# 3. REMOVER BETA / PROTO / DEMO / SAMPLE
# =============================================================================
em2_remove_unlicensed() {
    local systems
    mapfile -t systems < <(em_list_existing_systems)

    local menu_items=()
    local sys
    for sys in "${systems[@]}"; do
        menu_items+=("$sys" "$sys")
    done
    menu_items+=("TODOS" "Todos os sistemas")

    local choice
    choice=$(DIALOG_MENU "Remover Beta/Proto/Demo" "Escolha o sistema:" "${menu_items[@]}")
    [ "$(NORM_RET $?)" == "VOLTAR" ] && return

    local targets=()
    [ "$choice" == "TODOS" ] && targets=("${systems[@]}") || targets=("$choice")

    local found=0
    local preview=""
    local sysname f
    for sysname in "${targets[@]}"; do
        while IFS= read -r -d '' f; do
            local ext="${f##*.}"
            em_is_rom_extension "$ext" || continue
            local fname
            fname=$(basename "$f")
            if em2_is_unlicensed_release "$fname"; then
                [ "$found" -lt 15 ] && preview+="${fname}\n"
                ((found++))
            fi
        done < <(find "${ROMS_BASE_DIR}/${sysname}" -maxdepth 1 -type f -print0 2>/dev/null)
    done

    [ "$found" -eq 0 ] && {
        DIALOG_MSG "Remover Beta/Proto/Demo" "Nenhuma ROM com tag Beta/Proto/Demo/Sample encontrada."
        return
    }

    local overflow=""
    [ "$found" -gt 15 ] && overflow="... e mais $(( found - 15 )) arquivo(s).\n"

    local confirm
    confirm=$(DIALOG_YESNO "Remover Beta/Proto/Demo" \
        "ROMs encontradas: ${found}\n\n${preview}${overflow}\nSerao movidas para a subpasta 'nao_licenciados/' dentro de cada sistema.\nNenhum arquivo sera apagado.\n\nDeseja continuar?")
    [ "$confirm" -ne 0 ] && return

    local moved_file="${EM_TMP_DIR}/unlic_moved"
    local errors_file="${EM_TMP_DIR}/unlic_errors"
    echo 0 > "$moved_file"; echo 0 > "$errors_file"
    local report="${EM_DATA_DIR}/unlicensed_report.txt"
    echo "Remover Beta/Proto/Demo - $(date '+%Y-%m-%d %H:%M:%S')" > "$report"
    em_drain_tty_buffer

    (
    local processed=0 moved=0 errors=0
    for sysname in "${targets[@]}"; do
        while IFS= read -r -d '' f; do
            local ext="${f##*.}"
            em_is_rom_extension "$ext" || continue
            local fname; fname=$(basename "$f")
            em2_is_unlicensed_release "$fname" || continue
            ((processed++))
            local pct=$(( processed * 100 / found ))
            echo "$pct"
            if em2_move_to_subdir "$f" "nao_licenciados"; then
                echo "[OK] ${fname}" >> "$report"
                ((moved++)); echo "$moved" > "$moved_file"
            else
                echo "[ERRO] ${fname}" >> "$report"
                ((errors++)); echo "$errors" > "$errors_file"
            fi
        done < <(find "${ROMS_BASE_DIR}/${sysname}" -maxdepth 1 -type f -print0 2>/dev/null)
    done
    ) | dialog --backtitle "$DIALOG_BACKTITLE" --title "Remover Beta/Proto/Demo" \
        --gauge "Movendo ROMs para nao_licenciados/..." 8 60 0 \
        > "$CURR_TTY" 2> "$CURR_TTY"

    local moved errors
    moved=$(cat "$moved_file" 2>/dev/null || echo 0)
    errors=$(cat "$errors_file" 2>/dev/null || echo 0)
    rm -f "$moved_file" "$errors_file"
    chown ark:ark "$report" 2>/dev/null || true
    DIALOG_MSG "Remover Beta/Proto/Demo" \
        "Concluido.\n\nArquivos movidos: ${moved}\nErros: ${errors}\n\nRelatorio salvo em:\n${report}"
}

# =============================================================================
# 4. FILTRO 1G1R (1 Game 1 ROM)
# Prioridade: USA → World → Europe → Japan → outros
# Para cada título base (sem tags de região/revisão), mantém o melhor
# e move os demais para descartados/
# =============================================================================
em2_filter_1g1r() {
    local systems
    mapfile -t systems < <(em_list_existing_systems)

    local menu_items=()
    local sys
    for sys in "${systems[@]}"; do
        menu_items+=("$sys" "$sys")
    done

    local choice
    choice=$(DIALOG_MENU "Filtro 1G1R" \
        "Escolha o sistema:\n(Prioridade: USA > World > Europe > Japan > Outros)" \
        "${menu_items[@]}")
    [ "$(NORM_RET $?)" == "VOLTAR" ] && return

    local sysname="$choice"
    local rom_dir="${ROMS_BASE_DIR}/${sysname}"

    # Monta lista de ROMs com seu título base (sem região/revisão) e prioridade
    # Formato do TSV temporário: prioridade TAB titulo_base TAB caminho_completo
    local tmp_list="${EM_TMP_DIR}/1g1r_list.tsv"
    > "$tmp_list"

    local f
    while IFS= read -r -d '' f; do
        local ext="${f##*.}"
        em_is_rom_extension "$ext" || continue
        local fname
        fname=$(basename "$f")

        # Título base: remove todas as tags entre parênteses e colchetes
        local base_title
        base_title=$(echo "${fname%.*}" | sed -E \
            -e 's/ \([^)]*\)//g' \
            -e 's/ \[[^]]*\]//g' \
            -e 's/[[:space:]]+$//g')

        local priority
        priority=$(em2_1g1r_priority "$fname")
        printf '%d\t%s\t%s\n' "$priority" "$base_title" "$f" >> "$tmp_list"
    done < <(find "$rom_dir" -maxdepth 1 -type f -print0 2>/dev/null)

    if [ ! -s "$tmp_list" ]; then
        DIALOG_MSG "Filtro 1G1R" "Nenhuma ROM encontrada em ${rom_dir}."
        rm -f "$tmp_list"
        return
    fi

    # Para cada título base, elege o vencedor (menor prioridade numérica)
    # e marca os demais para mover
    local to_move_file="${EM_TMP_DIR}/1g1r_to_move.txt"
    > "$to_move_file"

    local preview=""
    local preview_count=0
    local to_move_count=0

    # Obtém títulos base únicos
    local title
    while IFS= read -r title; do
        # Todos os arquivos com este título base, ordenados por prioridade
        local candidates
        candidates=$(grep -F $'\t'"${title}"$'\t' "$tmp_list" | sort -t$'\t' -k1,1n)
        local n
        n=$(echo "$candidates" | grep -c .)
        [ "$n" -le 1 ] && continue

        # Primeiro = vencedor (menor prioridade numérica = melhor)
        local winner_path
        winner_path=$(echo "$candidates" | head -n1 | cut -f3)
        local winner_name
        winner_name=$(basename "$winner_path")

        # Demais vão para descartados/
        while IFS=$'\t' read -r prio btitle fpath; do
            [ "$fpath" = "$winner_path" ] && continue
            echo "$fpath" >> "$to_move_file"
            ((to_move_count++))
            if [ "$preview_count" -lt 12 ]; then
                local losername
                losername=$(basename "$fpath")
                preview+="MANTER: ${winner_name}\nMOVER : ${losername}\n\n"
                ((preview_count += 3))
            fi
        done <<< "$candidates"
    done < <(cut -f2 "$tmp_list" | sort -u)

    rm -f "$tmp_list"

    [ "$to_move_count" -eq 0 ] && {
        DIALOG_MSG "Filtro 1G1R" "Nenhuma duplicata de titulo encontrada.\nSua colecao ja esta no formato 1G1R."
        rm -f "$to_move_file"
        return
    }

    local overflow=""
    [ "$to_move_count" -gt 12 ] && overflow="... e mais arquivos.\n"

    local confirm
    confirm=$(DIALOG_YESNO "Filtro 1G1R" \
        "Arquivos a mover para descartados/: ${to_move_count}\n\n${preview}${overflow}\nO melhor arquivo de cada titulo sera mantido.\nOs demais serao movidos para '${sysname}/descartados/'.\n\nDeseja continuar?")
    [ "$confirm" -ne 0 ] && { rm -f "$to_move_file"; return; }

    local moved_file="${EM_TMP_DIR}/1g1r_moved"
    local errors_file="${EM_TMP_DIR}/1g1r_errors"
    echo 0 > "$moved_file"; echo 0 > "$errors_file"
    local report="${EM_DATA_DIR}/1g1r_report.txt"
    echo "Filtro 1G1R - ${sysname} - $(date '+%Y-%m-%d %H:%M:%S')" > "$report"
    em_drain_tty_buffer

    (
    local processed=0 moved=0 errors=0
    while IFS= read -r fpath; do
        ((processed++))
        local pct=$(( processed * 100 / to_move_count ))
        echo "$pct"
        local fname; fname=$(basename "$fpath")
        if em2_move_to_subdir "$fpath" "descartados"; then
            echo "[MOVIDO] ${fname}" >> "$report"
            ((moved++)); echo "$moved" > "$moved_file"
        else
            echo "[ERRO] ${fname}" >> "$report"
            ((errors++)); echo "$errors" > "$errors_file"
        fi
    done < "$to_move_file"
    ) | dialog --backtitle "$DIALOG_BACKTITLE" --title "Filtro 1G1R" \
        --gauge "Movendo ROMs para descartados/..." 8 60 0 \
        > "$CURR_TTY" 2> "$CURR_TTY"

    local moved errors
    moved=$(cat "$moved_file" 2>/dev/null || echo 0)
    errors=$(cat "$errors_file" 2>/dev/null || echo 0)
    rm -f "$to_move_file" "$moved_file" "$errors_file"
    chown ark:ark "$report" 2>/dev/null || true
    DIALOG_MSG "Filtro 1G1R" \
        "Concluido.\n\nArquivos movidos para descartados/: ${moved}\nErros: ${errors}\n\nRelatorio salvo em:\n${report}"
}

# =============================================================================
# 5. REMOVER HACKS E TRADUÇÕES
# =============================================================================
em2_remove_hacks() {
    local systems
    mapfile -t systems < <(em_list_existing_systems)

    local menu_items=()
    local sys
    for sys in "${systems[@]}"; do
        menu_items+=("$sys" "$sys")
    done
    menu_items+=("TODOS" "Todos os sistemas")

    local choice
    choice=$(DIALOG_MENU "Remover Hacks/Traducoes" "Escolha o sistema:" "${menu_items[@]}")
    [ "$(NORM_RET $?)" == "VOLTAR" ] && return

    local targets=()
    [ "$choice" == "TODOS" ] && targets=("${systems[@]}") || targets=("$choice")

    local found=0
    local preview=""
    local sysname f
    for sysname in "${targets[@]}"; do
        while IFS= read -r -d '' f; do
            local ext="${f##*.}"
            em_is_rom_extension "$ext" || continue
            local fname
            fname=$(basename "$f")
            if em2_is_hack_or_translation "$fname"; then
                [ "$found" -lt 15 ] && preview+="${fname}\n"
                ((found++))
            fi
        done < <(find "${ROMS_BASE_DIR}/${sysname}" -maxdepth 1 -type f -print0 2>/dev/null)
    done

    [ "$found" -eq 0 ] && {
        DIALOG_MSG "Remover Hacks/Traducoes" \
            "Nenhuma ROM com tag de hack ou traducao encontrada.\n\nTags detectadas: [h] [h1] [T+Eng] [T-Por] [a] [b] [o]"
        return
    }

    local overflow=""
    [ "$found" -gt 15 ] && overflow="... e mais $(( found - 15 )) arquivo(s).\n"

    local confirm
    confirm=$(DIALOG_YESNO "Remover Hacks/Traducoes" \
        "ROMs com tags de hack/traducao: ${found}\n\n${preview}${overflow}\nSerao movidas para a subpasta 'hacks/' dentro de cada sistema.\nNenhum arquivo sera apagado.\n\nDeseja continuar?")
    [ "$confirm" -ne 0 ] && return

    local moved_file="${EM_TMP_DIR}/hacks_moved"
    local errors_file="${EM_TMP_DIR}/hacks_errors"
    echo 0 > "$moved_file"; echo 0 > "$errors_file"
    em_drain_tty_buffer

    (
    local processed=0 moved=0 errors=0
    for sysname in "${targets[@]}"; do
        while IFS= read -r -d '' f; do
            local ext="${f##*.}"
            em_is_rom_extension "$ext" || continue
            local fname; fname=$(basename "$f")
            em2_is_hack_or_translation "$fname" || continue
            ((processed++))
            local pct=$(( processed * 100 / found ))
            echo "$pct"
            if em2_move_to_subdir "$f" "hacks"; then
                ((moved++)); echo "$moved" > "$moved_file"
            else
                ((errors++)); echo "$errors" > "$errors_file"
            fi
        done < <(find "${ROMS_BASE_DIR}/${sysname}" -maxdepth 1 -type f -print0 2>/dev/null)
    done
    ) | dialog --backtitle "$DIALOG_BACKTITLE" --title "Remover Hacks/Traducoes" \
        --gauge "Movendo ROMs para hacks/..." 8 60 0 \
        > "$CURR_TTY" 2> "$CURR_TTY"

    local moved errors
    moved=$(cat "$moved_file" 2>/dev/null || echo 0)
    errors=$(cat "$errors_file" 2>/dev/null || echo 0)
    rm -f "$moved_file" "$errors_file"
    DIALOG_MSG "Remover Hacks/Traducoes" \
        "Concluido.\n\nArquivos movidos para hacks/: ${moved}\nErros: ${errors}"
}

# =============================================================================
# 6. LIMPAR TAGS DO NOME (renomeia no lugar)
# =============================================================================
em2_clean_tags() {
    local systems
    mapfile -t systems < <(em_list_existing_systems)

    local menu_items=()
    local sys
    for sys in "${systems[@]}"; do
        menu_items+=("$sys" "$sys")
    done
    menu_items+=("TODOS" "Todos os sistemas")

    local choice
    choice=$(DIALOG_MENU "Limpar Tags do Nome" "Escolha o sistema:" "${menu_items[@]}")
    [ "$(NORM_RET $?)" == "VOLTAR" ] && return

    local targets=()
    [ "$choice" == "TODOS" ] && targets=("${systems[@]}") || targets=("$choice")

    # Prévia
    local preview=""
    local preview_count=0
    local total=0
    local sysname f
    for sysname in "${targets[@]}"; do
        while IFS= read -r -d '' f; do
            local ext="${f##*.}"
            em_is_rom_extension "$ext" || continue
            local fname
            fname=$(basename "$f")
            local cleaned
            cleaned=$(em2_clean_name "$fname")
            [ "$fname" = "$cleaned" ] && continue
            ((total++))
            if [ "$preview_count" -lt 10 ]; then
                preview+="DE:   ${fname}\nPARA: ${cleaned}\n\n"
                ((preview_count += 3))
            fi
        done < <(find "${ROMS_BASE_DIR}/${sysname}" -maxdepth 1 -type f -print0 2>/dev/null)
    done

    [ "$total" -eq 0 ] && {
        DIALOG_MSG "Limpar Tags" "Nenhum arquivo precisa de limpeza de tags."
        return
    }

    local overflow=""
    [ "$total" -gt 10 ] && overflow="... e mais $(( total - 10 )) arquivo(s).\n"

    local confirm
    confirm=$(DIALOG_YESNO "Limpar Tags do Nome" \
        "Arquivos que serao renomeados: ${total}\n\n${preview}${overflow}\nOs arquivos serao renomeados NO LUGAR.\n\nDeseja continuar?")
    [ "$confirm" -ne 0 ] && return

    local renamed_file="${EM_TMP_DIR}/cleantags_renamed"
    local errors_file="${EM_TMP_DIR}/cleantags_errors"
    echo 0 > "$renamed_file"; echo 0 > "$errors_file"
    local report="${EM_DATA_DIR}/cleantags_report.txt"
    echo "Limpar Tags - $(date '+%Y-%m-%d %H:%M:%S')" > "$report"
    em_drain_tty_buffer

    (
    local processed=0 renamed=0 errors=0
    for sysname in "${targets[@]}"; do
        while IFS= read -r -d '' f; do
            local ext="${f##*.}"
            em_is_rom_extension "$ext" || continue
            local fname; fname=$(basename "$f")
            local cleaned; cleaned=$(em2_clean_name "$fname")
            [ "$fname" = "$cleaned" ] && continue
            ((processed++))
            local pct=$(( processed * 100 / total ))
            echo "$pct"
            local dir; dir=$(dirname "$f")
            local dst="${dir}/${cleaned}"
            if [ -e "$dst" ] && [ "$dst" != "$f" ]; then
                if [ "${fname,,}" = "${cleaned,,}" ]; then
                    local tmp="${dir}/.tmp_rename_$$"
                    if mv -- "$f" "$tmp" 2>/dev/null && mv -- "$tmp" "$dst" 2>/dev/null; then
                        echo "[OK] ${fname} -> ${cleaned}" >> "$report"
                        ((renamed++)); echo "$renamed" > "$renamed_file"
                    else
                        mv -- "$tmp" "$f" 2>/dev/null
                        echo "[ERRO] ${fname}" >> "$report"
                        ((errors++)); echo "$errors" > "$errors_file"
                    fi
                else
                    echo "[CONFLITO] ${fname} -> ${cleaned}" >> "$report"
                    ((errors++)); echo "$errors" > "$errors_file"
                fi
                continue
            fi
            if mv -- "$f" "$dst" 2>/dev/null; then
                echo "[OK] ${fname} -> ${cleaned}" >> "$report"
                ((renamed++)); echo "$renamed" > "$renamed_file"
            else
                echo "[ERRO] ${fname}" >> "$report"
                ((errors++)); echo "$errors" > "$errors_file"
            fi
        done < <(find "${ROMS_BASE_DIR}/${sysname}" -maxdepth 1 -type f -print0 2>/dev/null)
    done
    ) | dialog --backtitle "$DIALOG_BACKTITLE" --title "Limpar Tags do Nome" \
        --gauge "Renomeando arquivos..." 8 60 0 \
        > "$CURR_TTY" 2> "$CURR_TTY"

    local renamed errors
    renamed=$(cat "$renamed_file" 2>/dev/null || echo 0)
    errors=$(cat "$errors_file" 2>/dev/null || echo 0)
    rm -f "$renamed_file" "$errors_file"
    chown ark:ark "$report" 2>/dev/null || true
    DIALOG_MSG "Limpar Tags" \
        "Concluido.\n\nArquivos renomeados: ${renamed}\nErros/conflitos: ${errors}\n\nRelatorio salvo em:\n${report}"
}

# =============================================================================
# 7. PADRONIZAR MAIÚSCULAS (Title Case)
# =============================================================================
em2_title_case_roms() {
    if ! em_has_tool python3; then
        DIALOG_MSG "Padronizar Maiusculas" "python3 nao encontrado. Esta funcao requer python3."
        return
    fi

    local systems
    mapfile -t systems < <(em_list_existing_systems)

    local menu_items=()
    local sys
    for sys in "${systems[@]}"; do
        menu_items+=("$sys" "$sys")
    done
    menu_items+=("TODOS" "Todos os sistemas")

    local choice
    choice=$(DIALOG_MENU "Padronizar Maiusculas" "Escolha o sistema:" "${menu_items[@]}")
    [ "$(NORM_RET $?)" == "VOLTAR" ] && return

    local targets=()
    [ "$choice" == "TODOS" ] && targets=("${systems[@]}") || targets=("$choice")

    local preview=""
    local preview_count=0
    local total=0
    local sysname f
    for sysname in "${targets[@]}"; do
        while IFS= read -r -d '' f; do
            local ext="${f##*.}"
            em_is_rom_extension "$ext" || continue
            local fname
            fname=$(basename "$f")
            local titled
            titled=$(em2_title_case "$fname")
            [ "$fname" = "$titled" ] && continue
            ((total++))
            if [ "$preview_count" -lt 10 ]; then
                preview+="DE:   ${fname}\nPARA: ${titled}\n\n"
                ((preview_count += 3))
            fi
        done < <(find "${ROMS_BASE_DIR}/${sysname}" -maxdepth 1 -type f -print0 2>/dev/null)
    done

    [ "$total" -eq 0 ] && {
        DIALOG_MSG "Padronizar Maiusculas" "Nenhum arquivo precisa de ajuste de maiusculas."
        return
    }

    local overflow=""
    [ "$total" -gt 10 ] && overflow="... e mais $(( total - 10 )) arquivo(s).\n"

    local confirm
    confirm=$(DIALOG_YESNO "Padronizar Maiusculas" \
        "Arquivos que serao renomeados: ${total}\n\n${preview}${overflow}\nOs arquivos serao renomeados NO LUGAR.\n\nDeseja continuar?")
    [ "$confirm" -ne 0 ] && return

    local renamed_file="${EM_TMP_DIR}/titlecase_renamed"
    local errors_file="${EM_TMP_DIR}/titlecase_errors"
    echo 0 > "$renamed_file"; echo 0 > "$errors_file"
    em_drain_tty_buffer

    (
    local processed=0 renamed=0 errors=0
    for sysname in "${targets[@]}"; do
        while IFS= read -r -d '' f; do
            local ext="${f##*.}"
            em_is_rom_extension "$ext" || continue
            local fname; fname=$(basename "$f")
            local titled; titled=$(em2_title_case "$fname")
            [ "$fname" = "$titled" ] && continue
            ((processed++))
            local pct=$(( processed * 100 / total ))
            echo "$pct"
            local dir; dir=$(dirname "$f")
            local dst="${dir}/${titled}"
            if [ "${fname,,}" = "${titled,,}" ]; then
                local tmp="${dir}/.tmp_rename_$$"
                if mv -- "$f" "$tmp" 2>/dev/null && mv -- "$tmp" "$dst" 2>/dev/null; then
                    ((renamed++)); echo "$renamed" > "$renamed_file"
                else
                    mv -- "$tmp" "$f" 2>/dev/null
                    ((errors++)); echo "$errors" > "$errors_file"
                fi
            else
                if [ -e "$dst" ]; then
                    ((errors++)); echo "$errors" > "$errors_file"
                    continue
                fi
                if mv -- "$f" "$dst" 2>/dev/null; then
                    ((renamed++)); echo "$renamed" > "$renamed_file"
                else
                    ((errors++)); echo "$errors" > "$errors_file"
                fi
            fi
        done < <(find "${ROMS_BASE_DIR}/${sysname}" -maxdepth 1 -type f -print0 2>/dev/null)
    done
    ) | dialog --backtitle "$DIALOG_BACKTITLE" --title "Padronizar Maiusculas" \
        --gauge "Aplicando Title Case nos nomes..." 8 60 0 \
        > "$CURR_TTY" 2> "$CURR_TTY"

    local renamed errors
    renamed=$(cat "$renamed_file" 2>/dev/null || echo 0)
    errors=$(cat "$errors_file" 2>/dev/null || echo 0)
    rm -f "$renamed_file" "$errors_file"
    DIALOG_MSG "Padronizar Maiusculas" \
        "Concluido.\n\nArquivos renomeados: ${renamed}\nErros/conflitos: ${errors}"
}

# =============================================================================
# 8. EXPORTAR LISTA DE ROMS
# =============================================================================
em2_export_list() {
    local systems
    mapfile -t systems < <(em_list_existing_systems)

    local menu_items=()
    local sys
    for sys in "${systems[@]}"; do
        menu_items+=("$sys" "$sys")
    done
    menu_items+=("TODOS" "Todos os sistemas")

    local choice
    choice=$(DIALOG_MENU "Exportar Lista de ROMs" "Escolha o sistema:" "${menu_items[@]}")
    [ "$(NORM_RET $?)" == "VOLTAR" ] && return

    local targets=()
    [ "$choice" == "TODOS" ] && targets=("${systems[@]}") || targets=("$choice")

    local fmt
    fmt=$(DIALOG_MENU "Formato" "Escolha o formato de exportacao:" \
        "1" "TXT - uma ROM por linha" \
        "2" "CSV - sistema,nome,tamanho,regiao")
    [ "$(NORM_RET $?)" == "VOLTAR" ] && return

    local timestamp
    timestamp=$(date '+%Y%m%d_%H%M%S')
    local outfile

    # Conta total para gauge
    local total_roms=0
    local sysname f
    for sysname in "${targets[@]}"; do
        while IFS= read -r -d '' f; do
            local ext="${f##*.}"
            em_is_rom_extension "$ext" && ((total_roms++))
        done < <(find "${ROMS_BASE_DIR}/${sysname}" -maxdepth 1 -type f -print0 2>/dev/null)
    done

    local count_file="${EM_TMP_DIR}/export_count"
    echo 0 > "$count_file"
    em_drain_tty_buffer

    if [ "$fmt" == "1" ]; then
        outfile="${EM_DATA_DIR}/rom_list_${timestamp}.txt"
        > "$outfile"
        (
        local processed=0
        for sysname in "${targets[@]}"; do
            echo "=== ${sysname} ===" >> "$outfile"
            while IFS= read -r -d '' f; do
                local ext="${f##*.}"
                em_is_rom_extension "$ext" || continue
                basename "$f" >> "$outfile"
                ((processed++))
                [ "$total_roms" -gt 0 ] && echo $(( processed * 100 / total_roms ))
                echo "$processed" > "$count_file"
            done < <(find "${ROMS_BASE_DIR}/${sysname}" -maxdepth 1 -type f -print0 2>/dev/null | sort -z)
            echo "" >> "$outfile"
        done
        ) | dialog --backtitle "$DIALOG_BACKTITLE" --title "Exportar Lista" \
            --gauge "Gerando lista TXT..." 8 60 0 \
            > "$CURR_TTY" 2> "$CURR_TTY"
    else
        outfile="${EM_DATA_DIR}/rom_list_${timestamp}.csv"
        echo "sistema,nome,tamanho_bytes,regiao" > "$outfile"
        (
        local processed=0
        for sysname in "${targets[@]}"; do
            while IFS= read -r -d '' f; do
                local ext="${f##*.}"
                em_is_rom_extension "$ext" || continue
                local fname size region
                fname=$(basename "$f")
                size=$(stat -c%s "$f" 2>/dev/null || echo 0)
                region=$(em2_detect_region "$fname")
                printf '%s,%s,%s,%s\n' "$sysname" "$fname" "$size" "$region" >> "$outfile"
                ((processed++))
                [ "$total_roms" -gt 0 ] && echo $(( processed * 100 / total_roms ))
                echo "$processed" > "$count_file"
            done < <(find "${ROMS_BASE_DIR}/${sysname}" -maxdepth 1 -type f -print0 2>/dev/null | sort -z)
        done
        ) | dialog --backtitle "$DIALOG_BACKTITLE" --title "Exportar Lista" \
            --gauge "Gerando lista CSV..." 8 60 0 \
            > "$CURR_TTY" 2> "$CURR_TTY"
    fi

    local total
    total=$(cat "$count_file" 2>/dev/null || echo "?")
    rm -f "$count_file"
    chown ark:ark "$outfile" 2>/dev/null || true
    DIALOG_MSG "Exportar Lista" \
        "Lista exportada com sucesso.\n\nArquivo gerado:\n${outfile}\n\nROMs exportadas: ${total}"
}

# =============================================================================
# 9. COMPARAR COM LISTA EXTERNA
# Lê um arquivo de texto com um nome de ROM por linha e mostra quais
# estão faltando na coleção local.
# O arquivo de lista deve ser colocado em data/ antes de usar esta opção.
# =============================================================================
em2_compare_with_list() {
    # Procura arquivos .txt em EM_DATA_DIR que possam ser listas externas
    local list_files=()
    local f
    while IFS= read -r -d '' f; do
        # Exclui relatórios gerados pelo próprio script
        local fname
        fname=$(basename "$f")
        echo "$fname" | grep -qE '^(rom_list_|region_|unlicensed_|1g1r_|cleantags_|duplicates_|corrupted_|rename_)' && continue
        list_files+=("$f")
    done < <(find "$EM_DATA_DIR" -maxdepth 1 -name "*.txt" -print0 2>/dev/null)

    if [ "${#list_files[@]}" -eq 0 ]; then
        DIALOG_MSG "Comparar com Lista" \
            "Nenhuma lista externa encontrada em:\n${EM_DATA_DIR}\n\nColoque um arquivo .txt com um nome de ROM por linha nessa pasta via SFTP/SSH e tente novamente."
        return
    fi

    local menu_items=()
    for f in "${list_files[@]}"; do
        local fname
        fname=$(basename "$f")
        menu_items+=("$fname" "$fname")
    done

    local chosen_list
    chosen_list=$(DIALOG_MENU "Comparar com Lista" \
        "Escolha o arquivo de lista externa:" "${menu_items[@]}")
    [ "$(NORM_RET $?)" == "VOLTAR" ] && return

    local list_path="${EM_DATA_DIR}/${chosen_list}"

    # Escolhe o sistema para comparar
    local systems
    mapfile -t systems < <(em_list_existing_systems)
    local menu_items2=()
    local sys
    for sys in "${systems[@]}"; do
        menu_items2+=("$sys" "$sys")
    done
    menu_items2+=("TODOS" "Todos os sistemas")

    local choice
    choice=$(DIALOG_MENU "Comparar com Lista" "Sistema a comparar:" "${menu_items2[@]}")
    [ "$(NORM_RET $?)" == "VOLTAR" ] && return

    local targets=()
    [ "$choice" == "TODOS" ] && targets=("${systems[@]}") || targets=("$choice")

    # Conta linhas da lista para gauge
    local total_list
    total_list=$(grep -c . "$list_path" 2>/dev/null || echo 1)

    # Monta índice local
    local tmp_local="${EM_TMP_DIR}/compare_local.txt"
    > "$tmp_local"
    local sysname
    for sysname in "${targets[@]}"; do
        while IFS= read -r -d '' f; do
            local ext="${f##*.}"
            em_is_rom_extension "$ext" || continue
            local fname; fname=$(basename "${f%.*}")
            echo "${fname,,}" >> "$tmp_local"
        done < <(find "${ROMS_BASE_DIR}/${sysname}" -maxdepth 1 -type f -print0 2>/dev/null)
    done

    local report="${EM_DATA_DIR}/compare_report.txt"
    {
        echo "Comparacao com lista: ${chosen_list}"
        echo "Sistema(s): ${choice}"
        echo "Data: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "=========================================="
        echo ""
        echo "--- ROMs FALTANDO na sua colecao ---"
    } > "$report"

    local missing_file="${EM_TMP_DIR}/compare_missing"
    local found_file="${EM_TMP_DIR}/compare_found"
    echo 0 > "$missing_file"; echo 0 > "$found_file"
    em_drain_tty_buffer

    (
    local processed=0 missing=0 found_count=0
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        ((processed++))
        [ "$total_list" -gt 0 ] && echo $(( processed * 100 / total_list ))
        local line_base="${line%.*}"
        local line_lower="${line_base,,}"
        if grep -qxF "$line_lower" "$tmp_local" 2>/dev/null; then
            ((found_count++)); echo "$found_count" > "$found_file"
        else
            echo "$line" >> "$report"
            ((missing++)); echo "$missing" > "$missing_file"
        fi
    done < "$list_path"
    ) | dialog --backtitle "$DIALOG_BACKTITLE" --title "Comparar com Lista" \
        --gauge "Comparando com a colecao local..." 8 60 0 \
        > "$CURR_TTY" 2> "$CURR_TTY"

    local missing found_count
    missing=$(cat "$missing_file" 2>/dev/null || echo 0)
    found_count=$(cat "$found_file" 2>/dev/null || echo 0)
    rm -f "$tmp_local" "$missing_file" "$found_file"
    chown ark:ark "$report" 2>/dev/null || true

    local total_list_real=$(( missing + found_count ))
    DIALOG_MSG "Comparar com Lista" \
        "Comparacao concluida.\n\nROMs na lista externa: ${total_list_real}\nEncontradas na colecao: ${found_count}\nFaltando: ${missing}\n\nRelatorio salvo em:\n${report}"
}

# =============================================================================
# 10. MANUTENÇÃO DA COLEÇÃO
# Sub-menu com 3 verificações
# =============================================================================

# --- 10a. Extensão não reconhecida ---
em2_check_unknown_ext() {
    local systems
    mapfile -t systems < <(em_list_existing_systems)

    local menu_items=()
    local sys
    for sys in "${systems[@]}"; do
        menu_items+=("$sys" "$sys")
    done
    menu_items+=("TODOS" "Todos os sistemas")

    local choice
    choice=$(DIALOG_MENU "Extensao Desconhecida" "Escolha o sistema:" "${menu_items[@]}")
    [ "$(NORM_RET $?)" == "VOLTAR" ] && return

    local targets=()
    [ "$choice" == "TODOS" ] && targets=("${systems[@]}") || targets=("$choice")

    local report="${EM_DATA_DIR}/unknown_ext_report.txt"
    echo "Extensoes desconhecidas - $(date '+%Y-%m-%d %H:%M:%S')" > "$report"

    # Conta total para gauge
    local total_files=0
    local sysname f
    for sysname in "${targets[@]}"; do
        while IFS= read -r -d '' f; do
            ((total_files++))
        done < <(find "${ROMS_BASE_DIR}/${sysname}" -maxdepth 1 -type f -print0 2>/dev/null)
    done

    local found_file="${EM_TMP_DIR}/unknownext_found"
    echo 0 > "$found_file"
    em_drain_tty_buffer

    (
    local processed=0 found=0
    for sysname in "${targets[@]}"; do
        while IFS= read -r -d '' f; do
            ((processed++))
            [ "$total_files" -gt 0 ] && echo $(( processed * 100 / total_files ))
            local ext="${f##*.}"
            ext="${ext,,}"
            em_is_rom_extension "$ext" && continue
            [ -z "$ext" ] && continue
            echo "${sysname}: $(basename "$f")" >> "$report"
            ((found++)); echo "$found" > "$found_file"
        done < <(find "${ROMS_BASE_DIR}/${sysname}" -maxdepth 1 -type f -print0 2>/dev/null)
    done
    ) | dialog --backtitle "$DIALOG_BACKTITLE" --title "Extensao Desconhecida" \
        --gauge "Verificando extensoes..." 8 60 0 \
        > "$CURR_TTY" 2> "$CURR_TTY"

    local found
    found=$(cat "$found_file" 2>/dev/null || echo 0)
    rm -f "$found_file"
    chown ark:ark "$report" 2>/dev/null || true

    if [ "$found" -eq 0 ]; then
        DIALOG_MSG "Extensao Desconhecida" "Nenhum arquivo com extensao desconhecida encontrado."
    else
        DIALOG_MSG "Extensao Desconhecida" \
            "Arquivos com extensao nao reconhecida: ${found}\n\nRelatorio salvo em:\n${report}\n\n(Nenhum arquivo foi movido ou apagado)"
    fi
}

# --- 10b. Tamanho zero ou suspeito ---
em2_check_zero_size() {
    local systems
    mapfile -t systems < <(em_list_existing_systems)

    local menu_items=()
    local sys
    for sys in "${systems[@]}"; do
        menu_items+=("$sys" "$sys")
    done
    menu_items+=("TODOS" "Todos os sistemas")

    local choice
    choice=$(DIALOG_MENU "Tamanho Suspeito" "Escolha o sistema:" "${menu_items[@]}")
    [ "$(NORM_RET $?)" == "VOLTAR" ] && return

    local targets=()
    [ "$choice" == "TODOS" ] && targets=("${systems[@]}") || targets=("$choice")

    local min_bytes=512
    local report="${EM_DATA_DIR}/zero_size_report.txt"
    echo "Arquivos suspeitos (< ${min_bytes} bytes) - $(date '+%Y-%m-%d %H:%M:%S')" > "$report"

    # Conta total para gauge
    local total_files=0
    local sysname f
    for sysname in "${targets[@]}"; do
        while IFS= read -r -d '' f; do
            local ext="${f##*.}"
            em_is_rom_extension "$ext" && ((total_files++))
        done < <(find "${ROMS_BASE_DIR}/${sysname}" -maxdepth 1 -type f -print0 2>/dev/null)
    done

    local found_file="${EM_TMP_DIR}/zerosize_found"
    echo 0 > "$found_file"
    em_drain_tty_buffer

    (
    local processed=0 found=0
    for sysname in "${targets[@]}"; do
        while IFS= read -r -d '' f; do
            local ext="${f##*.}"
            em_is_rom_extension "$ext" || continue
            ((processed++))
            [ "$total_files" -gt 0 ] && echo $(( processed * 100 / total_files ))
            local size; size=$(stat -c%s "$f" 2>/dev/null || echo 0)
            if [ "$size" -lt "$min_bytes" ]; then
                printf '%s: %s (%d bytes)\n' "$sysname" "$(basename "$f")" "$size" >> "$report"
                ((found++)); echo "$found" > "$found_file"
            fi
        done < <(find "${ROMS_BASE_DIR}/${sysname}" -maxdepth 1 -type f -print0 2>/dev/null)
    done
    ) | dialog --backtitle "$DIALOG_BACKTITLE" --title "Tamanho Suspeito" \
        --gauge "Verificando tamanhos dos arquivos..." 8 60 0 \
        > "$CURR_TTY" 2> "$CURR_TTY"

    local found
    found=$(cat "$found_file" 2>/dev/null || echo 0)
    rm -f "$found_file"
    chown ark:ark "$report" 2>/dev/null || true

    if [ "$found" -eq 0 ]; then
        DIALOG_MSG "Tamanho Suspeito" "Nenhum arquivo com tamanho suspeito encontrado."
    else
        DIALOG_MSG "Tamanho Suspeito" \
            "Arquivos suspeitos (< ${min_bytes} bytes): ${found}\n\nRelatorio salvo em:\n${report}\n\n(Nenhum arquivo foi apagado)"
    fi
}

# --- 10c. ROM na pasta de sistema errado ---
# Cruza a extensão do arquivo com as extensões esperadas para cada sistema.
# Após listar, oferece opção de mover para a pasta correta.
em2_check_wrong_system() {
    # Mapa: extensão → sistema esperado
    declare -A EXT_TO_SYS=(
        [gba]="gba"   [gb]="gb"     [gbc]="gbc"
        [nes]="nes"   [sfc]="snes"  [smc]="snes"
        [n64]="n64"   [z64]="n64"
        [md]="megadrive" [gen]="megadrive"
        [sms]="mastersystem" [gg]="gamegear"
        [32x]="sega32x"
        [nds]="nds"   [pbp]="psp"
    )

    # Pastas dentro de /roms/ que devem ser ignoradas na verificação
    local SKIP_FOLDERS=("bios" "ports" "themes" "tools" "backup" "duplicatas" "descartados" "hacks" "nao_licenciados")

    # Conta total de arquivos em /roms/ para gauge (excluindo pastas ignoradas)
    local total_files=0
    local f
    while IFS= read -r -d '' f; do
        # Verifica se o arquivo está dentro de uma pasta ignorada
        local rel="${f#${ROMS_BASE_DIR}/}"
        local top_folder; top_folder=$(echo "$rel" | cut -d'/' -f1)
        local skip=0
        for skip_dir in "${SKIP_FOLDERS[@]}"; do
            [ "$top_folder" = "$skip_dir" ] && skip=1 && break
        done
        [ "$skip" -eq 0 ] && ((total_files++))
    done < <(find "${ROMS_BASE_DIR}" -type f -print0 2>/dev/null)

    if [ "$total_files" -eq 0 ]; then
        DIALOG_MSG "Sistema Errado" "Nenhum arquivo encontrado em ${ROMS_BASE_DIR}."
        return
    fi

    local wrong_file="${EM_TMP_DIR}/wrong_system.tsv"
    local report="${EM_DATA_DIR}/wrong_system_report.txt"
    > "$wrong_file"
    echo "ROMs em sistema errado - $(date '+%Y-%m-%d %H:%M:%S')" > "$report"
    echo "Varredura em: ${ROMS_BASE_DIR} (recursiva)" >> "$report"
    echo "" >> "$report"

    local found_file="${EM_TMP_DIR}/wrong_found"
    echo 0 > "$found_file"
    em_drain_tty_buffer

    (
    local processed=0
    while IFS= read -r -d '' f; do
        # Verifica se está numa pasta ignorada
        local rel="${f#${ROMS_BASE_DIR}/}"
        local top_folder; top_folder=$(echo "$rel" | cut -d'/' -f1)
        local skip=0
        for skip_dir in "${SKIP_FOLDERS[@]}"; do
            [ "$top_folder" = "$skip_dir" ] && skip=1 && break
        done
        [ "$skip" -eq 1 ] && continue

        ((processed++))
        [ "$total_files" -gt 0 ] && echo $(( processed * 100 / total_files ))

        local ext="${f##*.}"
        ext="${ext,,}"
        local expected="${EXT_TO_SYS[$ext]:-}"
        # Extensão ambígua (bin, iso, zip...) ou não mapeada — pula
        [ -z "$expected" ] && continue

        # Determina a pasta atual do arquivo em relação a /roms/
        local rel_path="${f#${ROMS_BASE_DIR}/}"
        local current_folder
        current_folder=$(echo "$rel_path" | cut -d'/' -f1)

        # Está na pasta correta — pula
        [ "$current_folder" = "$expected" ] && continue

        # Pasta de destino deve existir no device
        [ ! -d "${ROMS_BASE_DIR}/${expected}" ] && continue

        # Registra para mover
        printf '%s\t%s\n' "$f" "$expected" >> "$wrong_file"
        printf 'ATUAL: %s  ESPERADO: %s/  ARQUIVO: %s\n' \
            "$current_folder" "$expected" "$(basename "$f")" >> "$report"

        local n; n=$(cat "$found_file")
        echo $(( n + 1 )) > "$found_file"
    done < <(find "${ROMS_BASE_DIR}" -type f -print0 2>/dev/null)
    ) | dialog --backtitle "$DIALOG_BACKTITLE" \
        --title "Verificar Sistema Errado" \
        --gauge "Varrendo ${ROMS_BASE_DIR} recursivamente...\n(Ignorando: bios/ ports/ themes/ tools/)" 9 60 0 \
        > "$CURR_TTY" 2> "$CURR_TTY"

    local found
    found=$(cat "$found_file" 2>/dev/null || echo 0)
    rm -f "$found_file"
    chown ark:ark "$report" 2>/dev/null || true

    if [ "$found" -eq 0 ]; then
        DIALOG_MSG "Sistema Errado" \
            "Nenhuma ROM encontrada fora da pasta correta.\n\nArquivos verificados: ${total_files}"
        rm -f "$wrong_file"
        return
    fi

    # Monta prévia das primeiras 12 entradas
    local preview=""
    local shown=0
    while IFS=$'\t' read -r fpath expected; do
        local rel="${fpath#${ROMS_BASE_DIR}/}"
        local current_folder; current_folder=$(echo "$rel" | cut -d'/' -f1)
        local fname; fname=$(basename "$fpath")
        preview+="${fname}\n  ${current_folder}/ → ${expected}/\n\n"
        ((shown++))
        [ "$shown" -ge 12 ] && break
    done < "$wrong_file"
    local overflow=""
    [ "$found" -gt 12 ] && overflow="... e mais $(( found - 12 )) arquivo(s).\n\n"

    # Pergunta se quer mover
    local confirm
    confirm=$(DIALOG_YESNO "ROMs em pasta errada" \
        "ROMs encontradas fora da pasta correta: ${found}\n\n${preview}${overflow}Deseja mover as ROMs para as pastas corretas agora?")

    if [ "$confirm" -ne 0 ]; then
        DIALOG_MSG "Sistema Errado" \
            "Nenhum arquivo foi movido.\n\nRelatorio salvo em:\n${report}"
        rm -f "$wrong_file"
        return
    fi

    # Move com gauge de progresso
    local total_to_move
    total_to_move=$(wc -l < "$wrong_file")
    local moved_file="${EM_TMP_DIR}/wrong_moved"
    local errors_file="${EM_TMP_DIR}/wrong_errors"
    echo 0 > "$moved_file"; echo 0 > "$errors_file"
    em_drain_tty_buffer

    (
    local processed=0 moved=0 errors=0
    while IFS=$'\t' read -r fpath expected; do
        ((processed++))
        [ "$total_to_move" -gt 0 ] && echo $(( processed * 100 / total_to_move ))
        local dest_dir="${ROMS_BASE_DIR}/${expected}"
        local fname; fname=$(basename "$fpath")
        local dest="${dest_dir}/${fname}"

        if [ -e "$dest" ]; then
            local base="${fname%.*}"
            local ext="${fname##*.}"
            local i=2
            while [ -e "${dest_dir}/${base}_${i}.${ext}" ]; do ((i++)); done
            dest="${dest_dir}/${base}_${i}.${ext}"
        fi

        if mv -- "$fpath" "$dest" 2>/dev/null; then
            echo "[MOVIDO] $(basename "$fpath") → ${expected}/" >> "$report"
            ((moved++)); echo "$moved" > "$moved_file"
        else
            echo "[ERRO] $(basename "$fpath")" >> "$report"
            ((errors++)); echo "$errors" > "$errors_file"
        fi
    done < "$wrong_file"
    ) | dialog --backtitle "$DIALOG_BACKTITLE" \
        --title "Sistema Errado" \
        --gauge "Movendo ROMs para as pastas corretas..." 8 60 0 \
        > "$CURR_TTY" 2> "$CURR_TTY"

    local moved errors
    moved=$(cat "$moved_file" 2>/dev/null || echo 0)
    errors=$(cat "$errors_file" 2>/dev/null || echo 0)
    rm -f "$wrong_file" "$moved_file" "$errors_file"
    chown ark:ark "$report" 2>/dev/null || true

    local result="ROMs movidas para pasta correta: ${moved}"
    [ "$errors" -gt 0 ] && result+="\nErros: ${errors}"
    result+="\n\nRelatorio salvo em:\n${report}"
    DIALOG_MSG "Sistema Errado - Concluido" "$result"
}

# Sub-menu de manutenção
em2_maintenance() {
    while true; do
        local choice
        choice=$(DIALOG_MENU "Manutencao da Colecao" "Selecione uma verificacao:" \
            "1" "Extensao nao reconhecida" \
            "2" "Arquivos com tamanho zero/suspeito" \
            "3" "ROM na pasta de sistema errado" \
            "0" "VOLTAR")
        [ "$(NORM_RET $?)" == "VOLTAR" ] && return

        case "$choice" in
            1) em2_check_unknown_ext ;;
            2) em2_check_zero_size ;;
            3) em2_check_wrong_system ;;
            0) return ;;
        esac
    done
}

# =============================================================================
# MENU PRINCIPAL DO MÓDULO 2
# =============================================================================
categoria_2() {
    while true; do
        local choice
        choice=$(DIALOG_MENU "Organizacao Avancada" "Selecione uma opcao:" \
            "1"  "Organizar por Regiao" \
            "2"  "Separar BIOS" \
            "3"  "Remover Beta/Proto/Demo/Sample" \
            "4"  "Filtro 1G1R (melhor versao por titulo)" \
            "5"  "Remover Hacks e Traducoes" \
            "6"  "Limpar Tags do Nome" \
            "7"  "Padronizar Maiusculas (Title Case)" \
            "8"  "Exportar Lista de ROMs" \
            "9"  "Comparar com Lista Externa" \
            "10" "Manutencao da Colecao" \
            "0"  "VOLTAR")

        local ret=$?
        [ "$(NORM_RET $ret)" == "VOLTAR" ] && return

        case "$choice" in
            1)  em2_organize_by_region ;;
            2)  em2_separate_bios ;;
            3)  em2_remove_unlicensed ;;
            4)  em2_filter_1g1r ;;
            5)  em2_remove_hacks ;;
            6)  em2_clean_tags ;;
            7)  em2_title_case_roms ;;
            8)  em2_export_list ;;
            9)  em2_compare_with_list ;;
            10) em2_maintenance ;;
            0)  return ;;
        esac
    done
}

# Permite executar este arquivo isoladamente para testes
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    categoria_2
fi
