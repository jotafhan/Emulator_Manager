#!/bin/bash
# =============================================================================
# Emulator Manager - cat_1_rom_management.sh
# Módulo 1: Gerenciamento de ROMs
#
# v1 (offline-first) implementa:
#   1. Scanner manual de novas ROMs (compara com índice salvo)
#   2. Verificação de integridade básica (teste de abertura ZIP/7Z + MD5)
#   3. Renomear via banco de dados No-Intro (.dat XML, offline, CRC32)
#   4. Compactar ROMs (zip/7z)
#   5. Descompactar ROMs (zip/7z)
#   6. Detectar duplicadas por hash MD5 (conteúdo, não nome)
#   7. Tamanho total ocupado por sistema
#   8. Estatísticas gerais da coleção
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/init.sh"
source "${SCRIPT_DIR}/core.sh"

# -----------------------------------------------------------------------------
# Helper interno: calcula MD5 de um arquivo, lidando com ZIP (hash do conteúdo
# interno, não do .zip em si) para que duplicatas comprimidas vs soltas batam.
# Para .7z não extraímos em memória nesta v1 (custo de CPU no R36S é alto);
# nesse caso o hash é do arquivo .7z como está, com aviso nas estatísticas.
# -----------------------------------------------------------------------------
em_calc_rom_hash() {
    local filepath="$1"
    local ext="${filepath##*.}"
    ext="${ext,,}"

    if [ "$ext" == "zip" ]; then
        # Hash do(s) arquivo(s) internos concatenados, ignorando metadados do zip
        # Isso faz com que "Jogo.zip" e "Jogo.gba" com mesmo conteúdo deem o mesmo hash.
        unzip -p "$filepath" 2>/dev/null | md5sum | awk '{print $1}'
    else
        md5sum "$filepath" 2>/dev/null | awk '{print $1}'
    fi
}

# -----------------------------------------------------------------------------
# 1. SCANNER AUTOMÁTICO DE NOVAS ROMS
# Compara o estado atual de /roms/<sistema> com o último índice salvo.
# -----------------------------------------------------------------------------
em_scan_new_roms() {
    em_init_dirs
    local systems
    mapfile -t systems < <(em_list_existing_systems)

    if [ ${#systems[@]} -eq 0 ]; then
        DIALOG_MSG "Scanner" "Nenhum diretorio de sistema conhecido foi encontrado em ${ROMS_BASE_DIR}."
        return
    fi

    local tmp_new_index="${EM_TMP_DIR}/rom_index_new.tsv"
    > "$tmp_new_index"

    local total_files=0
    local sys
    for sys in "${systems[@]}"; do
        while IFS= read -r -d '' f; do
            local ext="${f##*.}"
            em_is_rom_extension "$ext" || continue
            local size mtime
            size=$(stat -c%s "$f" 2>/dev/null)
            mtime=$(stat -c%Y "$f" 2>/dev/null)
            printf '%s\t%s\t%s\t%s\n' "$f" "-" "$size" "$mtime" >> "$tmp_new_index"
            ((total_files++))
        done < <(find "${ROMS_BASE_DIR}/${sys}" -maxdepth 1 -type f -print0 2>/dev/null)
    done

    local new_count=0
    local new_list=""
    if [ -f "$ROM_INDEX_FILE" ]; then
        while IFS=$'\t' read -r path _ _ _; do
            if ! grep -qF "$path" "$ROM_INDEX_FILE" 2>/dev/null; then
                ((new_count++))
                new_list+="$(basename "$path")\n"
            fi
        done < "$tmp_new_index"
    else
        new_count=$total_files
        new_list="(primeiro scan, todas as ROMs sao consideradas novas)\n"
    fi

    cp "$tmp_new_index" "$ROM_INDEX_FILE"

    if [ "$new_count" -eq 0 ]; then
        DIALOG_MSG "Scanner de ROMs" "Scan concluido.\n\nTotal de ROMs encontradas: ${total_files}\nNenhuma ROM nova desde o ultimo scan."
    else
        local preview
        preview=$(echo -e "$new_list" | head -n 15)
        DIALOG_MSG "Scanner de ROMs" "Scan concluido.\n\nTotal de ROMs encontradas: ${total_files}\nNovas desde o ultimo scan: ${new_count}\n\n${preview}"
    fi
}

# -----------------------------------------------------------------------------
# 2. VERIFICAR ROMS CORROMPIDAS (integridade básica + MD5)
# Nesta v1: testa se ZIP/7Z abrem sem erro. Para arquivos soltos, apenas
# confirma que são legíveis e calcula o MD5 (sem comparar com dat files, v2).
# -----------------------------------------------------------------------------
em_check_corrupted() {
    local systems
    mapfile -t systems < <(em_list_existing_systems)

    if [ ${#systems[@]} -eq 0 ]; then
        DIALOG_MSG "Verificar ROMs" "Nenhum diretorio de sistema conhecido foi encontrado."
        return
    fi

    > "$CORRUPTED_REPORT"
    local sys

    # Conta o total de arquivos ROM ANTES de iniciar, para podermos calcular
    # uma porcentagem real (0-100) em vez de um numero bruto que passa de
    # 100% em colecoes com mais de 100 arquivos.
    local total_files=0
    for sys in "${systems[@]}"; do
        local f
        while IFS= read -r -d '' f; do
            local ext="${f##*.}"
            ext="${ext,,}"
            em_is_rom_extension "$ext" && ((total_files++))
        done < <(find "${ROMS_BASE_DIR}/${sys}" -maxdepth 1 -type f -print0 2>/dev/null)
    done

    if [ "$total_files" -eq 0 ]; then
        DIALOG_MSG "Verificar ROMs" "Nenhuma ROM encontrada para verificar."
        return
    fi

    # Contadores precisam sobreviver ao subshell criado pelo pipe para o gauge,
    # entao usamos arquivos temporarios em vez de variaveis incrementadas dentro dele.
    local checked_file="${EM_TMP_DIR}/checked_count"
    local corrupted_file="${EM_TMP_DIR}/corrupted_count"
    local cancel_file="${EM_TMP_DIR}/check_cancelled"
    echo 0 > "$checked_file"
    echo 0 > "$corrupted_file"
    rm -f "$cancel_file"
    em_drain_tty_buffer

    (
    local checked=0
    for sys in "${systems[@]}"; do
        while IFS= read -r -d '' f; do
            local ext="${f##*.}"
            ext="${ext,,}"
            em_is_rom_extension "$ext" || continue

            # Checagem de cancelamento (botao B/VOLTAR ou 'q') ANTES de
            # processar mais um arquivo. Nao-bloqueante, nao compete com o
            # dialog --gauge pela leitura do TTY.
            if em_check_cancel_key; then
                echo "1" > "$cancel_file"
                exit 0
            fi

            ((checked++))
            echo "$checked" > "$checked_file"
            # Porcentagem real: arquivos verificados / total * 100
            echo $(( checked * 100 / total_files ))

            case "$ext" in
                zip)
                    if ! unzip -tqq "$f" >/dev/null 2>&1; then
                        echo "[ZIP CORROMPIDO] $f" >> "$CORRUPTED_REPORT"
                        echo $(($(cat "$corrupted_file") + 1)) > "$corrupted_file"
                    fi
                    ;;
                7z)
                    local sevenzip
                    sevenzip=$(em_get_7z_bin)
                    if [ -n "$sevenzip" ]; then
                        if ! "$sevenzip" t "$f" >/dev/null 2>&1; then
                            echo "[7Z CORROMPIDO] $f" >> "$CORRUPTED_REPORT"
                            echo $(($(cat "$corrupted_file") + 1)) > "$corrupted_file"
                        fi
                    fi
                    ;;
                *)
                    # Arquivo solto: só confirma que é legível
                    if [ ! -r "$f" ] || [ ! -s "$f" ]; then
                        echo "[VAZIO OU ILEGIVEL] $f" >> "$CORRUPTED_REPORT"
                        echo $(($(cat "$corrupted_file") + 1)) > "$corrupted_file"
                    fi
                    ;;
            esac
        done < <(find "${ROMS_BASE_DIR}/${sys}" -maxdepth 1 -type f -print0 2>/dev/null)
    done
    ) | DIALOG_GAUGE_CANCELABLE "Verificando ROMs" "Testando integridade dos arquivos...\nIsso pode levar alguns minutos.\n\n(Aperte B/VOLTAR para cancelar)"

    local checked
    local corrupted
    checked=$(cat "$checked_file")
    corrupted=$(cat "$corrupted_file")
    rm -f "$checked_file" "$corrupted_file"

    if [ -f "$cancel_file" ]; then
        rm -f "$cancel_file"
        DIALOG_MSG "Verificacao Cancelada" "Verificacao interrompida pelo usuario.\n\nArquivos verificados antes do cancelamento: ${checked}\nProblemas encontrados: ${corrupted}\n\nRelatorio parcial salvo em:\n${CORRUPTED_REPORT}"
        return
    fi

    if [ "$corrupted" -eq 0 ]; then
        DIALOG_MSG "Verificacao Concluida" "Arquivos verificados: ${checked}\nNenhum problema encontrado."
    else
        DIALOG_MSG "Verificacao Concluida" "Arquivos verificados: ${checked}\nProblemas encontrados: ${corrupted}\n\nRelatorio salvo em:\n${CORRUPTED_REPORT}"
    fi
}

# -----------------------------------------------------------------------------
# 3. RENOMEAR VIA BANCO DE DADOS No-Intro (.dat XML, offline, CRC32)
#
# Fluxo:
#   a) Usuário escolhe o sistema e aponta o .dat correspondente
#   b) python3 parseia o .dat e gera um índice CRC32->nome canônico em TSV
#      (salvo em data/dats/<sistema>_crc_index.tsv para reuso futuro)
#   c) Para cada ROM do sistema, calcula o CRC32 e cruza com o índice
#   d) Exibe lista de "será renomeado de X para Y" + quantidade, pede confirmação
#   e) Renomeia no lugar (mesma pasta, extensão preservada)
#   f) ROMs sem match são listadas separadamente e o usuário decide: pular ou
#      manter nome atual (nunca apaga nem move automaticamente)
#   g) Relatório final salvo em data/rename_report.txt
#
# Dependência: python3 (confirmado em /usr/bin/python3 no dArkOSRE do R36S)
# CRC32 é calculado via python3 inline (sem binário externo necessário).
# Para ZIPs, o CRC32 é do conteúdo interno (primeiro arquivo dentro do zip),
# igual ao campo 'crc' do .dat No-Intro, que também referencia o conteúdo.
# -----------------------------------------------------------------------------

# Helper: gera índice CRC32->nome a partir de um .dat No-Intro XML
em_dat_build_index() {
    local dat_file="$1"
    local index_file="$2"

    python3 - "$dat_file" "$index_file" <<'PYEOF'
import sys, xml.etree.ElementTree as ET, os

dat_path  = sys.argv[1]
idx_path  = sys.argv[2]

try:
    tree = ET.parse(dat_path)
except Exception as e:
    print(f"ERRO: nao foi possivel ler o .dat: {e}", file=sys.stderr)
    sys.exit(1)

root = tree.getroot()
count = 0
with open(idx_path, "w", encoding="utf-8") as out:
    for game in root.findall("game"):
        for rom in game.findall("rom"):
            crc = rom.get("crc", "").strip().lower()
            rom_name = rom.get("name", "").strip()
            if crc and rom_name:
                canonical = os.path.splitext(rom_name)[0]
                out.write(f"{crc}\t{canonical}\n")
                count += 1

print(count)
PYEOF
}

# Helper: calcula CRC32 de um arquivo ROM
em_calc_rom_crc32() {
    local filepath="$1"
    local ext="${filepath##*.}"
    ext="${ext,,}"

    if [ "$ext" == "zip" ]; then
        python3 - "$filepath" <<'PYEOF' 2>/dev/null
import sys, zipfile
try:
    with zipfile.ZipFile(sys.argv[1]) as z:
        infos = [i for i in z.infolist() if not i.filename.endswith('/')]
        if infos:
            print(format(infos[0].CRC & 0xFFFFFFFF, '08x'))
except Exception:
    pass
PYEOF
    else
        python3 - "$filepath" <<'PYEOF' 2>/dev/null
import sys, zlib
crc = 0
try:
    with open(sys.argv[1], 'rb') as f:
        while chunk := f.read(65536):
            crc = zlib.crc32(chunk, crc)
    print(format(crc & 0xFFFFFFFF, '08x'))
except Exception:
    pass
PYEOF
    fi
}

em_rename_database() {
    if ! em_has_tool python3; then
        DIALOG_MSG "Renomear ROMs" "python3 nao encontrado.\n\nEsta funcao requer python3 para ler o arquivo .dat e calcular CRC32."
        return
    fi

    local systems
    mapfile -t systems < <(em_list_existing_systems)
    if [ ${#systems[@]} -eq 0 ]; then
        DIALOG_MSG "Renomear ROMs" "Nenhum diretorio de sistema encontrado em ${ROMS_BASE_DIR}."
        return
    fi

    local menu_items=()
    local sys
    for sys in "${systems[@]}"; do
        menu_items+=("$sys" "$sys")
    done

    local chosen_sys
    chosen_sys=$(DIALOG_MENU "Renomear ROMs" "Escolha o sistema para renomear:" "${menu_items[@]}")
    [ "$(NORM_RET $?)" == "VOLTAR" ] && return

    local dats_dir="${EM_DATA_DIR}/dats"
    mkdir -p "$dats_dir"
    chown ark:ark "$dats_dir" 2>/dev/null || true

    # Mapa de palavras-chave EXCLUSIVAS por sistema para detecção do .dat.
    # Usa termos que aparecem nos nomes reais dos arquivos No-Intro/Redump
    # e que NÃO se sobrepõem entre sistemas (ex: "game_boy_advance" é exclusivo
    # de gba e não bate em "game_boy" do gb).
    declare -A EM_DAT_KEYWORDS
    EM_DAT_KEYWORDS["gba"]="game_boy_advance|game boy advance"
    EM_DAT_KEYWORDS["gb"]="game_boy_color|game boy color|game_boy_colour|game boy colour"  # gbc first
    EM_DAT_KEYWORDS["gbc"]="game_boy_color|game boy color|game_boy_colour|game boy colour"
    EM_DAT_KEYWORDS["nes"]="nintendo_entertainment_system|nintendo entertainment system"
    EM_DAT_KEYWORDS["snes"]="super_nintendo|super nintendo"
    EM_DAT_KEYWORDS["n64"]="nintendo_64|nintendo 64"
    EM_DAT_KEYWORDS["nds"]="nintendo_ds|nintendo ds"
    EM_DAT_KEYWORDS["psx"]="playstation(?!.*2)|sony.*playstation(?!.*2)"
    EM_DAT_KEYWORDS["ps2"]="playstation_2|playstation 2"
    EM_DAT_KEYWORDS["psp"]="playstation_portable|playstation portable"
    EM_DAT_KEYWORDS["megadrive"]="mega_drive|mega drive|genesis"
    EM_DAT_KEYWORDS["mastersystem"]="master_system|master system|mark_iii|mark iii"
    EM_DAT_KEYWORDS["gamegear"]="game_gear|game gear"
    EM_DAT_KEYWORDS["sega32x"]="32x|sega_32x|sega 32x"
    EM_DAT_KEYWORDS["segacd"]="mega.cd|sega.cd|mega-cd|sega-cd"
    EM_DAT_KEYWORDS["saturn"]="saturn"
    EM_DAT_KEYWORDS["dreamcast"]="dreamcast"
    EM_DAT_KEYWORDS["neogeo"]="neo.geo|neo geo"
    EM_DAT_KEYWORDS["atari2600"]="atari.*2600|2600"
    EM_DAT_KEYWORDS["atarilynx"]="atari.*lynx|lynx"

    # Função de correspondência: usa palavras-chave do mapa acima
    em_dat_matches_system() {
        local fname_lower="$1"   # nome do arquivo em lowercase
        local sys="$2"

        # 1. Correspondência exata: arquivo se chama exatamente "<sys>.dat"
        local base="${fname_lower%.dat}"
        [ "$base" = "$sys" ] && return 0

        # 2. Casos especiais com sobreposição de nome
        case "$sys" in
            gb)
                # Deve conter "game_boy" ou "game boy" MAS não "advance", "color" ou "colour"
                echo "$fname_lower" | grep -qiE "game.boy" || return 1
                echo "$fname_lower" | grep -qiE "advance|color|colour" && return 1
                return 0
                ;;
            gbc)
                echo "$fname_lower" | grep -qiE "game.boy.col" && return 0
                return 1
                ;;
            gba)
                echo "$fname_lower" | grep -qiE "game.boy.adv" && return 0
                return 1
                ;;
            nes)
                # "nintendo entertainment system" sem "super" antes
                echo "$fname_lower" | grep -qiE "nintendo.entertainment" || return 1
                echo "$fname_lower" | grep -qiE "super" && return 1
                return 0
                ;;
            snes)
                echo "$fname_lower" | grep -qiE "super.nintendo" && return 0
                return 1
                ;;
            *)
                # Para os outros sistemas usa palavras-chave do mapa
                local keywords="${EM_DAT_KEYWORDS[$sys]:-}"
                if [ -n "$keywords" ]; then
                    echo "$fname_lower" | grep -qiE "$keywords" && return 0
                fi
                ;;
        esac

        return 1
    }

    local auto_dat=""
    while IFS= read -r -d '' candidate; do
        local fname_lower
        fname_lower="$(basename "$candidate" | tr '[:upper:]' '[:lower:]')"
        if em_dat_matches_system "$fname_lower" "$chosen_sys"; then
            auto_dat="$candidate"
            break
        fi
    done < <(find "$dats_dir" -maxdepth 1 -name "*.dat" -print0 2>/dev/null)

    local dat_file=""
    if [ -n "$auto_dat" ]; then
        # .dat encontrado — pergunta se quer usar
        local confirm
        confirm=$(DIALOG_YESNO "Arquivo .dat encontrado" \
            "Arquivo .dat encontrado:\n\n$(basename "$auto_dat")\n\nUsar este arquivo?")
        if [ "$confirm" -eq 0 ]; then
            # SIM — usa o arquivo detectado
            dat_file="$auto_dat"
        else
            # NAO — usuário recusou, cancela sem tentar de novo
            DIALOG_MSG "Renomear ROMs" "Operacao cancelada.\nNenhuma alteracao foi feita."
            return
        fi
    else
        # Nenhum .dat encontrado — informa onde colocar e encerra
        DIALOG_MSG "Arquivo .dat nao encontrado" \
            "Nenhum arquivo .dat encontrado para '${chosen_sys}'.\n\nColoque o arquivo .dat No-Intro na pasta:\n\n  ${dats_dir}/\n\nConsulte o arquivo dat_reference.md para saber o nome correto de cada sistema."
        return
    fi

    # Constrói ou reutiliza o índice CRC32->nome
    local index_file="${dats_dir}/${chosen_sys}_crc_index.tsv"
    if [ ! -f "$index_file" ] || [ "$dat_file" -nt "$index_file" ]; then
        DIALOG_MSG "Indexando .dat" "Processando o arquivo .dat...\nIsso leva alguns segundos na primeira vez."
        local entry_count
        entry_count=$(em_dat_build_index "$dat_file" "$index_file")
        if [ $? -ne 0 ] || [ ! -s "$index_file" ]; then
            DIALOG_MSG "Erro" "Nao foi possivel processar o arquivo .dat:\n${dat_file}"
            rm -f "$index_file"
            return
        fi
        chown ark:ark "$index_file" 2>/dev/null || true
    fi

    # Conta ROMs do sistema
    local rom_dir="${ROMS_BASE_DIR}/${chosen_sys}"
    local total_roms=0
    local f
    while IFS= read -r -d '' f; do
        local ext="${f##*.}"
        em_is_rom_extension "$ext" && ((total_roms++))
    done < <(find "$rom_dir" -maxdepth 1 -type f -print0 2>/dev/null)

    [ "$total_roms" -eq 0 ] && {
        DIALOG_MSG "Renomear ROMs" "Nenhuma ROM encontrada em:\n${rom_dir}"
        return
    }

    local match_file="${EM_TMP_DIR}/rename_matches.tsv"
    local nomatch_file="${EM_TMP_DIR}/rename_nomatches.txt"
    local cancel_file="${EM_TMP_DIR}/rename_cancelled"
    local processed_file="${EM_TMP_DIR}/rename_processed"
    > "$match_file"
    > "$nomatch_file"
    rm -f "$cancel_file"
    echo 0 > "$processed_file"
    em_drain_tty_buffer

    (
    local processed=0
    while IFS= read -r -d '' f; do
        local ext="${f##*.}"
        em_is_rom_extension "$ext" || continue

        if em_check_cancel_key; then
            echo "1" > "$cancel_file"
            exit 0
        fi

        ((processed++))
        echo "$processed" > "$processed_file"
        echo $(( processed * 100 / total_roms ))

        local crc
        crc=$(em_calc_rom_crc32 "$f")

        if [ -z "$crc" ]; then
            echo "$f" >> "$nomatch_file"
            continue
        fi

        local canonical
        canonical=$(grep -m1 "^${crc}"$'\t' "$index_file" 2>/dev/null | cut -f2)

        if [ -n "$canonical" ]; then
            local current_name
            current_name=$(basename "${f%.*}")
            [ "$current_name" != "$canonical" ] && printf '%s\t%s\n' "$f" "$canonical" >> "$match_file"
        else
            echo "$f" >> "$nomatch_file"
        fi
    done < <(find "$rom_dir" -maxdepth 1 -type f -print0 2>/dev/null)
    ) | DIALOG_GAUGE_CANCELABLE "Calculando CRC32" \
        "Identificando ROMs via CRC32...\nIsso pode levar alguns minutos.\n\n(Aperte B/VOLTAR para cancelar)"

    local processed
    processed=$(cat "$processed_file")
    rm -f "$processed_file"

    if [ -f "$cancel_file" ]; then
        rm -f "$cancel_file"
        DIALOG_MSG "Cancelado" "Busca cancelada.\n\nROMs verificadas: ${processed}\nNenhuma alteracao foi feita."
        return
    fi

    local match_count=0
    local nomatch_count=0
    [ -s "$match_file" ]   && match_count=$(wc -l < "$match_file")
    [ -s "$nomatch_file" ] && nomatch_count=$(wc -l < "$nomatch_file")

    if [ "$match_count" -eq 0 ]; then
        DIALOG_MSG "Renomear ROMs" "Todas as ROMs ja estao com o nome No-Intro correto.\n\nROMs sem correspondencia no .dat: ${nomatch_count}"
        rm -f "$match_file" "$nomatch_file"
        return
    fi

    # Prévia das renomeações
    local preview=""
    local shown=0
    while IFS=$'\t' read -r filepath canonical; do
        local cur_name
        cur_name=$(basename "${filepath%.*}")
        preview+="DE:   ${cur_name}\nPARA: ${canonical}\n\n"
        ((shown++))
        [ "$shown" -ge 12 ] && break
    done < "$match_file"
    local remaining=$(( match_count - shown ))
    [ "$remaining" -gt 0 ] && preview+="... e mais ${remaining} arquivo(s).\n"

    local confirm
    confirm=$(DIALOG_YESNO "Confirmar Renomeacao" \
        "ROMs que SERAO renomeadas: ${match_count}\nSem correspondencia: ${nomatch_count}\n\n${preview}\nDeseja prosseguir?")

    if [ "$confirm" -ne 0 ]; then
        DIALOG_MSG "Renomear ROMs" "Operacao cancelada.\nNenhuma alteracao foi feita."
        rm -f "$match_file" "$nomatch_file"
        return
    fi

    # Executa renomeações
    local renamed=0
    local rename_errors=0
    local rename_report="${EM_DATA_DIR}/rename_report.txt"
    {
        echo "Relatorio de Renomeacao - $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Sistema: ${chosen_sys} | DAT: $(basename "$dat_file")"
        echo "=========================================="
    } > "$rename_report"

    while IFS=$'\t' read -r filepath canonical; do
        local dir ext new_path
        dir=$(dirname "$filepath")
        ext="${filepath##*.}"
        new_path="${dir}/${canonical}.${ext}"

        if [ -e "$new_path" ] && [ "$new_path" != "$filepath" ]; then
            echo "[CONFLITO] $(basename "$filepath") -> ${canonical}.${ext}" >> "$rename_report"
            ((rename_errors++))
        elif mv -- "$filepath" "$new_path" 2>/dev/null; then
            echo "[OK] $(basename "$filepath") -> ${canonical}.${ext}" >> "$rename_report"
            ((renamed++))
        else
            echo "[ERRO] $(basename "$filepath")" >> "$rename_report"
            ((rename_errors++))
        fi
    done < "$match_file"

    # ROMs sem match
    if [ "$nomatch_count" -gt 0 ]; then
        local nomatch_preview=""
        local ns=0
        while IFS= read -r nf; do
            nomatch_preview+="$(basename "$nf")\n"
            ((ns++))
            [ "$ns" -ge 15 ] && break
        done < "$nomatch_file"
        [ "$nomatch_count" -gt 15 ] && nomatch_preview+="... e mais $(( nomatch_count - 15 )) arquivo(s).\n"

        local keep
        keep=$(DIALOG_YESNO "ROMs sem correspondencia" \
            "${nomatch_count} ROM(s) nao encontradas no .dat:\n\n${nomatch_preview}\nRegistrar no relatorio?")
        [ "$keep" -eq 0 ] && {
            echo "" >> "$rename_report"
            echo "-- ROMs sem correspondencia --" >> "$rename_report"
            cat "$nomatch_file" >> "$rename_report"
        }
    fi

    chown ark:ark "$rename_report" 2>/dev/null || true
    rm -f "$match_file" "$nomatch_file"

    DIALOG_MSG "Renomear ROMs - Concluido" \
        "Renomeadas: ${renamed}\nErros/conflitos: ${rename_errors}\nSem correspondencia: ${nomatch_count}\n\nRelatorio:\n${rename_report}"
}

# -----------------------------------------------------------------------------
# 4. COMPACTAR ROMS
# Compacta arquivos soltos em .zip (padrão, mais compatível com RetroArch).
# Pula sistemas presentes em NO_COMPRESS_SYSTEMS.
# Exibe barra de progresso e nome do arquivo atual durante o processo.
# -----------------------------------------------------------------------------
em_compress_roms() {
    if ! em_has_tool zip; then
        DIALOG_MSG "Compactar ROMs" "A ferramenta 'zip' nao foi encontrada.\nInstale com: apt install zip"
        return
    fi

    local systems
    mapfile -t systems < <(em_list_existing_systems)
    local menu_items=()
    local sys
    for sys in "${systems[@]}"; do
        em_is_no_compress_system "$sys" && continue
        menu_items+=("$sys" "$sys")
    done
    menu_items+=("TODOS" "Compactar em todos os sistemas elegiveis")

    local choice
    choice=$(DIALOG_MENU "Compactar ROMs" "Escolha o sistema\n(sistemas que exigem arquivo descomprimido, ex: psx, ja foram filtrados):" "${menu_items[@]}")
    [ "$(NORM_RET $?)" == "VOLTAR" ] && return

    local targets=()
    if [ "$choice" == "TODOS" ]; then
        targets=("${systems[@]}")
    else
        targets=("$choice")
    fi

    # Conta total de arquivos elegíveis para calcular porcentagem real
    local total_files=0
    local sysname f
    for sysname in "${targets[@]}"; do
        em_is_no_compress_system "$sysname" && continue
        while IFS= read -r -d '' f; do
            local ext="${f##*.}"
            ext="${ext,,}"
            [ "$ext" == "zip" ] || [ "$ext" == "7z" ] && continue
            em_is_rom_extension "$ext" && ((total_files++))
        done < <(find "${ROMS_BASE_DIR}/${sysname}" -maxdepth 1 -type f -print0 2>/dev/null)
    done

    if [ "$total_files" -eq 0 ]; then
        DIALOG_MSG "Compactar ROMs" "Nenhum arquivo elegivel para compactar encontrado."
        return
    fi

    local compacted_file="${EM_TMP_DIR}/compress_count"
    local saved_file="${EM_TMP_DIR}/compress_saved"
    echo 0 > "$compacted_file"
    echo 0 > "$saved_file"
    em_drain_tty_buffer

    (
    local processed=0
    local compacted=0
    local saved_bytes=0
    for sysname in "${targets[@]}"; do
        em_is_no_compress_system "$sysname" && continue
        while IFS= read -r -d '' f; do
            local ext="${f##*.}"
            ext="${ext,,}"
            [ "$ext" == "zip" ] || [ "$ext" == "7z" ] && continue
            em_is_rom_extension "$ext" || continue

            ((processed++))
            local pct=$(( processed * 100 / total_files ))
            local fname
            fname=$(basename "$f")
            [ "${#fname}" -gt 40 ] && fname="${fname:0:37}..."
            echo "$pct"

            local original_size
            original_size=$(stat -c%s "$f" 2>/dev/null)
            local zipfile="${f%.*}.zip"

            if [ -f "$zipfile" ]; then
                continue
            fi

            if zip -jq "$zipfile" "$f" 2>/dev/null; then
                local new_size
                new_size=$(stat -c%s "$zipfile" 2>/dev/null)
                saved_bytes=$(( saved_bytes + original_size - new_size ))
                rm -f "$f"
                ((compacted++))
                echo "$compacted" > "$compacted_file"
                echo "$saved_bytes" > "$saved_file"
            fi
        done < <(find "${ROMS_BASE_DIR}/${sysname}" -maxdepth 1 -type f -print0 2>/dev/null)
    done
    ) | dialog --backtitle "$DIALOG_BACKTITLE" \
        --title "Compactar ROMs" \
        --gauge "Compactando arquivos..." 8 60 0 \
        > "$CURR_TTY" 2> "$CURR_TTY"

    local compacted saved_bytes
    compacted=$(cat "$compacted_file" 2>/dev/null || echo 0)
    saved_bytes=$(cat "$saved_file" 2>/dev/null || echo 0)
    rm -f "$compacted_file" "$saved_file"

    DIALOG_MSG "Compactar ROMs" "Concluido.\n\nArquivos verificados: ${total_files}\nArquivos compactados: ${compacted}\nEspaco economizado: $(em_human_size ${saved_bytes:-0})"
}

# -----------------------------------------------------------------------------
# 5. DESCOMPACTAR ZIP/7Z AUTOMATICAMENTE
# Útil para sistemas em NO_COMPRESS_SYSTEMS ou por escolha do usuário.
# Exibe barra de progresso e nome do arquivo atual durante o processo.
# -----------------------------------------------------------------------------
em_decompress_roms() {
    local systems
    mapfile -t systems < <(em_list_existing_systems)
    local menu_items=()
    local sys
    for sys in "${systems[@]}"; do
        menu_items+=("$sys" "$sys")
    done
    menu_items+=("TODOS" "Descompactar em todos os sistemas")

    local choice
    choice=$(DIALOG_MENU "Descompactar ROMs" "Escolha o sistema:" "${menu_items[@]}")
    [ "$(NORM_RET $?)" == "VOLTAR" ] && return

    local targets=()
    if [ "$choice" == "TODOS" ]; then
        targets=("${systems[@]}")
    else
        targets=("$choice")
    fi

    # Conta total de arquivos ZIP/7Z para porcentagem real
    local total_files=0
    local sysname f
    for sysname in "${targets[@]}"; do
        while IFS= read -r -d '' f; do
            local ext="${f##*.}"
            ext="${ext,,}"
            { [ "$ext" == "zip" ] || [ "$ext" == "7z" ]; } && ((total_files++))
        done < <(find "${ROMS_BASE_DIR}/${sysname}" -maxdepth 1 -type f -print0 2>/dev/null)
    done

    if [ "$total_files" -eq 0 ]; then
        DIALOG_MSG "Descompactar ROMs" "Nenhum arquivo ZIP/7Z encontrado para descompactar."
        return
    fi

    local extracted_file="${EM_TMP_DIR}/decompress_count"
    echo 0 > "$extracted_file"
    em_drain_tty_buffer

    (
    local processed=0
    local extracted=0
    for sysname in "${targets[@]}"; do
        while IFS= read -r -d '' f; do
            local ext="${f##*.}"
            ext="${ext,,}"
            { [ "$ext" == "zip" ] || [ "$ext" == "7z" ]; } || continue

            ((processed++))
            local pct=$(( processed * 100 / total_files ))
            local fname
            fname=$(basename "$f")
            [ "${#fname}" -gt 40 ] && fname="${fname:0:37}..."
            echo "$pct"

            local dir
            dir=$(dirname "$f")

            case "$ext" in
                zip)
                    if em_has_tool unzip; then
                        if unzip -oq "$f" -d "$dir" 2>/dev/null; then
                            rm -f "$f"
                            ((extracted++))
                            echo "$extracted" > "$extracted_file"
                        fi
                    fi
                    ;;
                7z)
                    local sevenzip
                    sevenzip=$(em_get_7z_bin)
                    if [ -n "$sevenzip" ]; then
                        if "$sevenzip" x -y -o"$dir" "$f" >/dev/null 2>&1; then
                            rm -f "$f"
                            ((extracted++))
                            echo "$extracted" > "$extracted_file"
                        fi
                    fi
                    ;;
            esac
        done < <(find "${ROMS_BASE_DIR}/${sysname}" -maxdepth 1 -type f -print0 2>/dev/null)
    done
    ) | dialog --backtitle "$DIALOG_BACKTITLE" \
        --title "Descompactar ROMs" \
        --gauge "Descompactando arquivos..." 8 60 0 \
        > "$CURR_TTY" 2> "$CURR_TTY"

    local extracted
    extracted=$(cat "$extracted_file" 2>/dev/null || echo 0)
    rm -f "$extracted_file"

    DIALOG_MSG "Descompactar ROMs" "Concluido.\n\nArquivos encontrados: ${total_files}\nArquivos descompactados: ${extracted}"
}

# -----------------------------------------------------------------------------
# 6. DETECTAR ROMS REPETIDAS POR HASH
# Usa MD5 do conteúdo (não do nome do arquivo). Para ZIP, hash do conteúdo
# interno (ver em_calc_rom_hash), permitindo achar duplicatas entre formatos.
#
# Após a busca:
#   - Exibe na tela quais arquivos são duplicatas e qual será mantido
#   - Pede confirmação antes de mover qualquer arquivo
#   - Move as duplicatas para <pasta_do_sistema>/duplicatas/
#   - O arquivo mantido é o de nome mais curto; em empate, o primeiro
#     alfabeticamente
#   - Relatório completo salvo em data/duplicates_report.txt
# -----------------------------------------------------------------------------
em_find_duplicates() {
    local systems
    mapfile -t systems < <(em_list_existing_systems)

    if [ ${#systems[@]} -eq 0 ]; then
        DIALOG_MSG "Duplicadas" "Nenhum diretorio de sistema conhecido foi encontrado."
        return
    fi

    local tmp_hashes="${EM_TMP_DIR}/hashes.tsv"
    > "$tmp_hashes"

    # Conta o total de arquivos ROM ANTES de iniciar, para calcular uma
    # porcentagem real (0-100) em vez de um numero bruto que passa de 100%
    # em colecoes com mais de 100 arquivos (ex: "133%").
    local total_files=0
    local sys
    for sys in "${systems[@]}"; do
        local f
        while IFS= read -r -d '' f; do
            local ext="${f##*.}"
            em_is_rom_extension "$ext" && ((total_files++))
        done < <(find "${ROMS_BASE_DIR}/${sys}" -maxdepth 1 -type f -print0 2>/dev/null)
    done

    if [ "$total_files" -eq 0 ]; then
        DIALOG_MSG "Duplicadas" "Nenhuma ROM encontrada para verificar."
        return
    fi

    local cancel_file="${EM_TMP_DIR}/dup_cancelled"
    rm -f "$cancel_file"
    em_drain_tty_buffer

    local count=0
    (
    local sys
    for sys in "${systems[@]}"; do
        local f
        while IFS= read -r -d '' f; do
            local ext="${f##*.}"
            em_is_rom_extension "$ext" || continue

            # Checagem de cancelamento (botao B/VOLTAR ou 'q') ANTES de
            # processar mais um arquivo.
            if em_check_cancel_key; then
                echo "1" > "$cancel_file"
                exit 0
            fi

            local h
            h=$(em_calc_rom_hash "$f")
            [ -n "$h" ] && printf '%s\t%s\n' "$h" "$f" >> "$tmp_hashes"
            ((count++))
            # Porcentagem real: arquivos processados / total * 100
            echo $(( count * 100 / total_files ))
        done < <(find "${ROMS_BASE_DIR}/${sys}" -maxdepth 1 -type f -print0 2>/dev/null)
    done
    ) | DIALOG_GAUGE_CANCELABLE "Procurando Duplicadas" "Calculando hashes das ROMs...\nIsso pode levar varios minutos dependendo da colecao.\n\n(Aperte B/VOLTAR para cancelar)"

    if [ -f "$cancel_file" ]; then
        rm -f "$cancel_file"
        DIALOG_MSG "Duplicadas" "Busca cancelada pelo usuario.\n\nNenhum relatorio foi gerado, pois a busca nao foi concluida."
        return
    fi

    # -------------------------------------------------------------------------
    # Processar grupos de duplicatas:
    # Para cada hash com N > 1 arquivos, eleger o "vencedor" (nome mais curto,
    # desempate alfabético) e marcar os demais para mover.
    # -------------------------------------------------------------------------
    > "$DUPLICATES_REPORT"
    local dup_groups=0
    local dup_files=0

    # Arquivo temporário: uma linha por arquivo a mover → "caminho_origem TAB pasta_destino"
    local to_move_file="${EM_TMP_DIR}/dup_to_move.tsv"
    > "$to_move_file"

    # Texto de prévia para exibir no dialog de confirmação (limitado a N linhas)
    local preview=""
    local preview_lines=0
    local preview_max=20   # máximo de linhas na prévia (tela pequena do R36S)

    local hash
    for hash in $(cut -f1 "$tmp_hashes" | sort -u); do
        # Todos os arquivos com este hash, um por linha
        local matches
        matches=$(grep -P "^${hash}\t" "$tmp_hashes" | cut -f2)
        local n
        n=$(echo "$matches" | grep -c .)
        [ "$n" -le 1 ] && continue

        ((dup_groups++))
        dup_files=$((dup_files + n))

        # -----------------------------------------------------------------
        # Eleger o arquivo a manter: menor comprimento de basename;
        # empate → primeiro em ordem alfabética (sort já garante isso).
        # Construímos pares "comprimento TAB caminho" para ordenar.
        # -----------------------------------------------------------------
        local winner=""
        local shortest_len=99999
        local tmp_sorted
        tmp_sorted=$(echo "$matches" | while IFS= read -r fpath; do
            local bname
            bname=$(basename "$fpath")
            printf '%d\t%s\n' "${#bname}" "$fpath"
        done | sort -t$'\t' -k1,1n -k2,2)

        winner=$(echo "$tmp_sorted" | head -n1 | cut -f2)
        local winner_name
        winner_name=$(basename "$winner")
        local winner_dir
        winner_dir=$(dirname "$winner")

        # Pasta de destino das duplicatas deste sistema
        local dup_dir="${winner_dir}/duplicatas"

        # Registrar no relatório
        {
            echo "--- Hash: ${hash} (${n} copias) ---"
            echo "  MANTER : ${winner_name}"
        } >> "$DUPLICATES_REPORT"

        # Marcar os demais para mover e acumular prévia
        while IFS= read -r fpath; do
            [ "$fpath" = "$winner" ] && continue
            local fname
            fname=$(basename "$fpath")
            printf '%s\t%s\n' "$fpath" "$dup_dir" >> "$to_move_file"
            echo "  MOVER  : ${fname}  →  $(basename "$dup_dir")/" >> "$DUPLICATES_REPORT"

            if [ "$preview_lines" -lt "$preview_max" ]; then
                preview+="MANTER: ${winner_name}\n"
                preview+="MOVER : ${fname}\n\n"
                ((preview_lines += 3))
            fi
        done <<< "$matches"

        echo "" >> "$DUPLICATES_REPORT"
    done

    # -------------------------------------------------------------------------
    # Nenhuma duplicata encontrada
    # -------------------------------------------------------------------------
    if [ "$dup_groups" -eq 0 ]; then
        DIALOG_MSG "Duplicadas" "Nenhuma ROM duplicada encontrada."
        return
    fi

    # -------------------------------------------------------------------------
    # Exibir prévia e pedir confirmação antes de mover qualquer coisa
    # -------------------------------------------------------------------------
    local to_move_count
    to_move_count=$(wc -l < "$to_move_file")

    local overflow=""
    local hidden=$(( dup_groups - preview_lines / 3 ))
    [ "$hidden" -gt 0 ] && overflow="... e mais grupos nao exibidos.\n\n"

    local confirm
    confirm=$(DIALOG_YESNO "Duplicatas Encontradas" \
        "Grupos de duplicatas: ${dup_groups}\nArquivos a mover: ${to_move_count}\n\n${preview}${overflow}Os arquivos serao movidos para a pasta 'duplicatas/' dentro de cada sistema.\nO arquivo de nome mais curto sera mantido no lugar.\n\nDeseja mover as duplicatas agora?")

    if [ "$confirm" -ne 0 ]; then
        DIALOG_MSG "Duplicadas" "Operacao cancelada.\nNenhum arquivo foi movido.\n\nRelatorio salvo em:\n${DUPLICATES_REPORT}"
        rm -f "$to_move_file"
        return
    fi

    # -------------------------------------------------------------------------
    # Mover os arquivos marcados
    # -------------------------------------------------------------------------
    local moved=0
    local move_errors=0

    while IFS=$'\t' read -r src dst_dir; do
        mkdir -p "$dst_dir"
        chown ark:ark "$dst_dir" 2>/dev/null || true

        local fname
        fname=$(basename "$src")
        local dst="${dst_dir}/${fname}"

        # Se já existe um arquivo com o mesmo nome na pasta duplicatas
        # (raro, mas possível se houver hashes diferentes com mesmo nome),
        # adiciona sufixo numérico para não sobrescrever.
        if [ -e "$dst" ]; then
            local base="${fname%.*}"
            local ext="${fname##*.}"
            local i=2
            while [ -e "${dst_dir}/${base}_${i}.${ext}" ]; do
                ((i++))
            done
            dst="${dst_dir}/${base}_${i}.${ext}"
        fi

        if mv -- "$src" "$dst" 2>/dev/null; then
            ((moved++))
        else
            ((move_errors++))
            echo "  ERRO AO MOVER: $(basename "$src")" >> "$DUPLICATES_REPORT"
        fi
    done < "$to_move_file"

    chown ark:ark "$DUPLICATES_REPORT" 2>/dev/null || true
    rm -f "$to_move_file"

    # -------------------------------------------------------------------------
    # Resultado final
    # -------------------------------------------------------------------------
    local result_msg="Grupos de duplicatas: ${dup_groups}\n"
    result_msg+="Arquivos movidos: ${moved}\n"
    [ "$move_errors" -gt 0 ] && result_msg+="Erros ao mover: ${move_errors}\n"
    result_msg+="\nOs arquivos movidos estao em:\n"
    result_msg+="  <sistema>/duplicatas/\n"
    result_msg+="\nRelatorio completo salvo em:\n${DUPLICATES_REPORT}"

    DIALOG_MSG "Duplicadas - Concluido" "$result_msg"
}

# -----------------------------------------------------------------------------
# 7. TAMANHO TOTAL OCUPADO POR SISTEMA
# -----------------------------------------------------------------------------
em_show_size_per_system() {
    local systems
    mapfile -t systems < <(em_list_existing_systems)

    if [ ${#systems[@]} -eq 0 ]; then
        DIALOG_MSG "Tamanho por Sistema" "Nenhum diretorio de sistema conhecido foi encontrado."
        return
    fi

    local report=""
    local total_bytes=0
    local sys
    for sys in "${systems[@]}"; do
        local bytes
        bytes=$(du -sb "${ROMS_BASE_DIR}/${sys}" 2>/dev/null | cut -f1)
        bytes=${bytes:-0}
        total_bytes=$((total_bytes + bytes))
        # IMPORTANTE: $(...) remove a quebra de linha final do printf, por
        # isso adicionamos $'\n' explicitamente depois - sem isso, cada
        # linha do relatorio fica colada na proxima (ex: "gba ... GBgb ...").
        report+="$(printf '%-15s %s' "$sys" "$(em_human_size "$bytes")")"$'\n'
    done

    report+=$'\n----------------------------\n'
    report+="$(printf '%-15s %s' "TOTAL" "$(em_human_size "$total_bytes")")"$'\n'

    DIALOG_MSG "Tamanho por Sistema" "$report"
}

# -----------------------------------------------------------------------------
# 8. ESTATISTICAS DA COLECAO
# -----------------------------------------------------------------------------
em_show_collection_stats() {
    local systems
    mapfile -t systems < <(em_list_existing_systems)

    if [ ${#systems[@]} -eq 0 ]; then
        DIALOG_MSG "Estatisticas" "Nenhum diretorio de sistema conhecido foi encontrado."
        return
    fi

    local total_roms=0
    local total_bytes=0
    local systems_with_roms=0
    local biggest_system=""
    local biggest_count=0
    local report=""

    local sys
    for sys in "${systems[@]}"; do
        local count bytes
        count=$(find "${ROMS_BASE_DIR}/${sys}" -maxdepth 1 -type f 2>/dev/null | wc -l)
        bytes=$(du -sb "${ROMS_BASE_DIR}/${sys}" 2>/dev/null | cut -f1)
        bytes=${bytes:-0}

        if [ "$count" -gt 0 ]; then
            ((systems_with_roms++))
            total_roms=$((total_roms + count))
            total_bytes=$((total_bytes + bytes))
            if [ "$count" -gt "$biggest_count" ]; then
                biggest_count=$count
                biggest_system=$sys
            fi
        fi
    done

    local avg_size=0
    [ "$total_roms" -gt 0 ] && avg_size=$((total_bytes / total_roms))

    # Usamos $'\n' (quebra de linha real) em vez de "\n" (que e apenas o
    # texto literal barra+n dentro de aspas duplas simples) para garantir
    # que o dialog --no-collapse exiba cada estatistica em sua propria linha.
    report="Sistemas com ROMs: ${systems_with_roms}"$'\n'
    report+="Total de ROMs: ${total_roms}"$'\n'
    report+="Espaco total ocupado: $(em_human_size ${total_bytes})"$'\n'
    report+="Tamanho medio por ROM: $(em_human_size ${avg_size})"$'\n'
    report+="Sistema com mais ROMs: ${biggest_system:-N/A} (${biggest_count})"$'\n'

    DIALOG_MSG "Estatisticas da Colecao" "$report"
}

# -----------------------------------------------------------------------------
# MENU PRINCIPAL DO MODULO
# -----------------------------------------------------------------------------
categoria_1() {
    em_check_dependencies

    while true; do
        local choice
        choice=$(DIALOG_MENU "Gerenciamento de ROMs" "Selecione uma opcao:" \
            "1" "Scanner de Novas ROMs" \
            "2" "Verificar ROMs Corrompidas" \
            "3" "Renomear via Banco de Dados (.dat)" \
            "4" "Compactar ROMs" \
            "5" "Descompactar ROMs" \
            "6" "Detectar Duplicadas (Hash)" \
            "7" "Tamanho Total por Sistema" \
            "8" "Estatisticas da Colecao" \
            "0" "VOLTAR")

        local ret=$?
        if [ "$(NORM_RET $ret)" == "VOLTAR" ]; then
            return
        fi

        case "$choice" in
            1) em_scan_new_roms ;;
            2) em_check_corrupted ;;
            3) em_rename_database ;;
            4) em_compress_roms ;;
            5) em_decompress_roms ;;
            6) em_find_duplicates ;;
            7) em_show_size_per_system ;;
            8) em_show_collection_stats ;;
            0) return ;;
        esac
    done
}

# Permite executar este arquivo isoladamente para testes
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    categoria_1
fi
