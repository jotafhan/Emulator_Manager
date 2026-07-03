# Emulator Manager

Ferramenta modular de gerenciamento de emuladores e ROMs para handhelds retro, com interface TUI via `dialog`. Desenvolvida para o **R36S (dArkOSRE)** com compatibilidade para **RG351MP (ArkOS)**.

---

## Versão atual: 6.0.1

### Regras de versionamento
| Tipo de alteração | Incremento |
|---|---|
| Alteração em opção existente | `+0.0.1` |
| Nova opção dentro de um módulo | `+0.1.0` |
| Novo módulo | versão = número de módulos (ex: 7 módulos → `7.0.0`) |

---

## Compatibilidade

| Device | Sistema | Status |
|---|---|---|
| R36S | dArkOSRE (Debian trixie, aarch64) | ✅ Principal |
| RG351MP | ArkOS 2.0 | ✅ Compatível |

---

## Estrutura

```
Emulator_Manager.sh                    ← entry point
lib/
  init.sh                               ← paths, versão, constantes
  core.sh                               ← funções compartilhadas (dialog, NORM_RET)
  cat_1_rom_management.sh               ← Módulo 1: Gerenciamento de ROMs
  cat_2_advanced_organization.sh        ← Módulo 2: Organização Avançada
  cat_3_emulator_tools.sh               ← Módulo 3: Backup Inteligente
  cat_4_collection_manager.sh           ← Módulo 4: Gestão da Coleção
  cat_5_update_manager.sh               ← Módulo 6 (menu): Atualizar
  cat_6_performance_tools.sh            ← Módulo 5 (menu): Performance
  keys_emulator_manager.gptk            ← Mapeamento de botões (B = ESC)
data/
  dats/                                 ← Arquivos .dat No-Intro para renomeação
  backups/                              ← Backups gerados pelo script
  last_change.txt                       ← Registro da última modificação
```

---

## Instalação

```bash
# Copiar para o device via SCP
scp -r Emulator_Manager ark@<ip-do-device>:/opt/system/Tools/

# Dar permissão de execução
chmod +x /opt/system/Tools/Emulator_Manager/Emulator_Manager.sh
chmod +x /opt/system/Tools/Emulator_Manager/lib/*.sh
```

Após instalar, o script aparece automaticamente no menu **Tools** do EmulationStation.

---

## Módulos

### Módulo 1 — Gerenciamento de ROMs

| Opção | Descrição |
|---|---|
| 1. Scanner de Novas ROMs | Compara estado atual com índice salvo e lista ROMs novas |
| 2. Verificar ROMs Corrompidas | Testa integridade de ZIP/7Z e arquivos soltos |
| 3. Renomear via Banco de Dados | Renomeia ROMs pelo nome canônico No-Intro usando CRC32 e arquivo `.dat` local |
| 4. Compactar ROMs | Compacta arquivos soltos em `.zip` (pula sistemas que exigem arquivo descomprimido) |
| 5. Descompactar ROMs | Extrai arquivos `.zip` e `.7z` |
| 6. Detectar Duplicadas | Detecta duplicatas por hash MD5, exibe prévia e move para `duplicatas/` |
| 7. Tamanho Total por Sistema | Exibe espaço ocupado por cada sistema |
| 8. Estatísticas da Coleção | Total de ROMs, espaço, sistema com mais jogos, tamanho médio |

> **Opção 3 — Renomear via .dat:** coloque o arquivo `.dat` No-Intro em `data/dats/`. Consulte `dat_reference.md` para o nome correto de cada sistema. O índice CRC32 é gerado na primeira execução e reutilizado automaticamente.

---

### Módulo 2 — Organização Avançada

| Opção | Descrição |
|---|---|
| 1. Organizar por Região | Move ROMs para subpastas `USA/` `Japan/` `Europe/` `World/` `Outros/` |
| 2. Separar BIOS | Move arquivos `[BIOS]` para `bios/` |
| 3. Remover Beta/Proto/Demo | Move releases não licenciadas para `nao_licenciados/` |
| 4. Filtro 1G1R | Mantém melhor versão por título (USA→World→Europe→Japan), move resto para `descartados/` |
| 5. Remover Hacks e Traduções | Detecta tags `[h]` `[T+...]` e move para `hacks/` |
| 6. Limpar Tags do Nome | Remove tags de região/revisão do nome do arquivo (renomeia no lugar) |
| 7. Padronizar Maiúsculas | Aplica Title Case nos nomes (compatível com FAT32/exFAT) |
| 8. Exportar Lista de ROMs | Gera `.txt` ou `.csv` com toda a coleção |
| 9. Comparar com Lista Externa | Mostra ROMs faltando na coleção em relação a uma lista de referência |
| 10. Manutenção da Coleção | Extensão desconhecida / tamanho suspeito / ROM na pasta errada (com opção de mover) |

---

### Módulo 3 — Backup Inteligente

| Opção | Descrição |
|---|---|
| 1. Backup config emulador individual | Compacta configurações de um emulador específico |
| 2. Backup config todos os emuladores | Compacta configurações de todos os emuladores em um único arquivo |
| 3. Importar configuração | Restaura backup com exibição de tamanho e data |
| 4. Apagar backup | Remove backup individual ou todos |
| 5. Exportar para pendrive | Copia backup para pasta `Backup Configurações/` no pendrive |
| 6. Restaurar configurações padrão | Apaga configurações (com dupla confirmação e backup automático antes) |

**Emuladores reconhecidos:** RetroArch, RetroArch32, PPSSPP, Mupen64Plus, DuckStation, Flycast, ScummVM, GZDoom, ECWolf

---

### Módulo 4 — Gestão da Coleção

| Opção | Descrição |
|---|---|
| 1. Backup de Saves | Localiza e compacta todos os saves do device; oferece copiar para pendrive |
| 2. Restaurar Saves | Lista backups de saves e restaura no lugar original |
| 3. Backup de BIOS | Compacta `/roms/bios/`; oferece copiar para pendrive |
| 4. Restaurar BIOS | Restaura arquivos BIOS de um backup |
| 5. Exportar Coleção para Pendrive | Copia ROMs de um ou todos os sistemas para o pendrive (verifica espaço antes) |
| 6. Sincronizar com Pendrive | Sincroniza saves ou ROMs entre device e pendrive (qualquer direção), copiando só o que mudou |

---

### Módulo 5 — Ferramentas de Performance

| Opção | Descrição |
|---|---|
| 1. Núcleo por Sistema | Lista núcleos recomendados com notas de compatibilidade para cada sistema |
| 2. Ajustar Configurações por Emulador | Aplica configurações otimizadas no RetroArch, PPSSPP e Mupen64Plus |
| 3. Perfil de Energia | Aplica perfil **Economia** / **Balanceado** / **Máximo Desempenho** no RetroArch |
| 4. Cache de Shaders | Ativa, limpa ou exibe status do cache de shaders |
| 5. Restaurar Configurações Originais | Restaura backups automáticos criados por este módulo |

> Backup automático é feito antes de qualquer modificação. Os arquivos ficam em `data/backups/performance/`.

---

### Módulo 6 — Atualizar Emulator Manager

| Opção | Descrição |
|---|---|
| 1. Verificar atualizações | Compara arquivos locais com o repositório GitHub sem alterar nada |
| 2. Atualizar agora | Baixa, valida e aplica a versão mais recente (backup automático antes) |
| 3. Restaurar versão anterior | Reverte para uma versão anterior salva automaticamente |

> Repositório: [github.com/jotafhan/Emulator_Manager](https://github.com/jotafhan/Emulator_Manager)

---

## Arquivo .dat para renomeação (Módulo 1, opção 3)

Coloque os arquivos `.dat` No-Intro em `data/dats/`. A detecção é automática por nome de arquivo.

| Sistema | Nome do arquivo baixado | Renomear para |
|---|---|---|
| `gba` | `Nintendo - Game Boy Advance (...).dat` | não precisa renomear |
| `gb` | `Nintendo - Game Boy (...).dat` | `gb.dat` |
| `gbc` | `Nintendo - Game Boy Color (...).dat` | `gbc.dat` |
| `nes` | `Nintendo - Nintendo Entertainment System (...).dat` | não precisa renomear |
| `snes` | `Nintendo - Super Nintendo Entertainment System (...).dat` | não precisa renomear |
| `n64` | `Nintendo - Nintendo 64 (...).dat` | não precisa renomear |
| `nds` | `Nintendo - Nintendo DS (...).dat` | não precisa renomear |
| `megadrive` | `Sega - Mega Drive - Genesis (...).dat` | `megadrive.dat` |
| `mastersystem` | `Sega - Master System - Mark III (...).dat` | `mastersystem.dat` |
| `gamegear` | `Sega - Game Gear (...).dat` | `gamegear.dat` |
| `sega32x` | `Sega - 32X (...).dat` | `sega32x.dat` |
| `segacd` | `Sega - Mega-CD - Sega CD (...).dat` | `segacd.dat` |
| `saturn` | `Sega - Saturn (...).dat` | não precisa renomear |
| `dreamcast` | `Redump - Sega - Dreamcast (...).dat` | não precisa renomear |
| `psx` | `Redump - Sony - PlayStation (...).dat` | `psx.dat` |
| `ps2` | `Redump - Sony - PlayStation 2 (...).dat` | `ps2.dat` |
| `psp` | `Redump - Sony - PlayStation Portable (...).dat` | `psp.dat` |
| `neogeo` | `SNK - Neo Geo (...).dat` | `neogeo.dat` |
| `atari2600` | `Atari - 2600 (...).dat` | `atari2600.dat` |
| `atarilynx` | `Atari - Lynx (...).dat` | `atarilynx.dat` |

---

## Dependências

| Ferramenta | Uso | Obrigatória |
|---|---|---|
| `dialog` | Interface TUI | ✅ |
| `md5sum` | Hash de ROMs | ✅ |
| `unzip` | Verificar/extrair ZIP | ✅ |
| `zip` | Compactar ROMs | ✅ |
| `python3` | CRC32 (renomear via .dat), Title Case | ✅ |
| `curl` ou `wget` | Atualizações via GitHub | ⚠️ Módulo 6 |
| `7z` / `7za` / `7zr` | Suporte a arquivos .7z | Opcional |

---

## Botões de navegação

| Botão | Ação |
|---|---|
| D-pad | Navegar no menu |
| A | Confirmar / OK |
| B | Voltar / Cancelar |
| Start | Confirmar (alternativo) |

> O script carrega automaticamente `lib/keys_emulator_manager.gptk` que mapeia o botão B como `ESC` em qualquer device, garantindo comportamento consistente no R36S e RG351MP.

---

## Observações

- Nenhuma ROM ou save é apagado automaticamente — operações destrutivas sempre pedem confirmação
- Backup automático é feito antes de qualquer operação de restauração ou modificação de configuração
- O índice do scanner (`data/rom_index.tsv`) é sobrescrito a cada scan
- Saves são localizados automaticamente em `/roms/<sistema>/` e nas pastas de configuração dos emuladores
- A última modificação feita pelo usuário aparece no topo do menu principal
