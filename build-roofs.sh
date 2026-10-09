#!/bin/bash
set -euo pipefail

# ============================================================
# Dellkix - RootFS Builder
# ============================================================

ROOTFS="$(pwd)/rootfs"
INITRAMFS="$(pwd)/initramfs.img"

BUSYBOX="${BUSYBOX:-$(command -v busybox || true)}"

if [[ -z "$BUSYBOX" ]]; then
    echo "ERRO: BusyBox não encontrado."
    echo "Instale com: sudo pacman -S busybox"
    exit 1
fi

echo "==> Dellkix RootFS Builder"
echo

# ------------------------------------------------------------
# Verificações
# ------------------------------------------------------------

if [[ $EUID -eq 0 ]]; then
    echo "Não rode este script como root."
    echo "Ele só precisa de sudo quando necessário."
    exit 1
fi

echo "==> BusyBox: $BUSYBOX"

# ------------------------------------------------------------
# Limpeza
# ------------------------------------------------------------

echo "==> Limpando rootfs anterior..."

rm -rf "$ROOTFS"
mkdir -p "$ROOTFS"

# ------------------------------------------------------------
# Estrutura básica
# ------------------------------------------------------------

echo "==> Criando estrutura..."

mkdir -p \
    "$ROOTFS"/bin \
    "$ROOTFS"/sbin \
    "$ROOTFS"/usr/bin \
    "$ROOTFS"/usr/sbin \
    "$ROOTFS"/dev \
    "$ROOTFS"/proc \
    "$ROOTFS"/sys \
    "$ROOTFS"/run \
    "$ROOTFS"/tmp \
    "$ROOTFS"/etc \
    "$ROOTFS"/root \
    "$ROOTFS"/mnt \
    "$ROOTFS"/var \
    "$ROOTFS"/lib \
    "$ROOTFS"/lib64

chmod 1777 "$ROOTFS/tmp"

# ------------------------------------------------------------
# BusyBox
# ------------------------------------------------------------

echo "==> Instalando BusyBox e bash..."

# Copia o binário real, não um symlink amaldiçoado apontando
# para algum diretório do sistema hospedeiro.
cp -L "$BUSYBOX" "$ROOTFS/bin/busybox"

chmod +x "$ROOTFS/bin/busybox"

# ------------------------------------------------------------
# Applets
# ------------------------------------------------------------

echo "==> Instalando todos os applets disponíveis..."

BUSYBOX_BIN="$ROOTFS/bin/busybox"

if [[ ! -x "$BUSYBOX_BIN" ]]; then
    echo "ERRO: BusyBox não encontrado em $BUSYBOX_BIN"
    exit 1
fi

# Cria um link para cada applet compilado no BusyBox.
while IFS= read -r applet; do
    [[ -n "$applet" ]] || continue

    # Não substituir o próprio binário.
    [[ "$applet" == "busybox" ]] && continue

    ln -sf busybox "$ROOTFS/bin/$applet"
done < <("$BUSYBOX_BIN" --list)

# O shell é essencial para inicializar o sistema.
if ! "$BUSYBOX_BIN" --list | grep -qx 'sh'; then
    echo "ERRO: este BusyBox não possui o applet sh."
    exit 1
fi

ln -sf busybox "$ROOTFS/bin/sh"

echo "==> Applets instalados: $(find "$ROOTFS/bin" -type l | wc -l)"

# ------------------------------------------------------------
# /etc
# ------------------------------------------------------------

echo "==> Criando configuração básica..."

cat >"$ROOTFS/etc/os-release" <<'EOF'
NAME="Dellkix GNU/Linux"
VERSION="0.1 prototype"
ID=dellkix
VERSION_ID=0.1
PRETTY_NAME="Dellkix 0.1 (prototype)"
EOF

cat >"$ROOTFS/etc/hostname" <<'EOF'
something
EOF

cat >"$ROOTFS/etc/passwd" <<'EOF'
root:x:0:0:root:/root:/bin/sh
EOF

cat >"$ROOTFS/etc/group" <<'EOF'
root:x:0:
EOF

# ------------------------------------------------------------
# /init
# ------------------------------------------------------------

echo "==> Criando /init..."

cat >"$ROOTFS/init" <<'EOF'
#!/bin/sh

# ============================================================
# Dellkix - PID 1
# ============================================================

export PATH=/bin:/sbin:/usr/bin:/usr/sbin

mount -t devtmpfs devtmpfs /dev 2>/dev/null
mount -t proc proc /proc 2>/dev/null
mount -t sysfs sysfs /sys 2>/dev/null
mount -t tmpfs tmpfs /run 2>/dev/null

clear 2>/dev/null

echo
echo "======================================"
echo "            Dellkix 0.1"
echo "======================================"
echo
echo "Kernel : $(uname -r)"
echo "Machine: $(uname -m)"
echo

# ------------------------------------------------------------
# Power saving
# ------------------------------------------------------------

for cpu in /sys/devices/system/cpu/cpu[0-9]*; do
    governor="$cpu/cpufreq/scaling_governor"

    if [ -w "$governor" ]; then
        echo powersave > "$governor" 2>/dev/null || true
    fi
done

# ------------------------------------------------------------
# Shell
# ------------------------------------------------------------

echo "Type 'help' for available commands."
echo

while true; do
    /bin/sh
    echo
    echo "Shell encerrado. Voltando para o shell..."
done
EOF

chmod +x "$ROOTFS/init"

# ------------------------------------------------------------
# BusyBox shell fallback
# ------------------------------------------------------------

ln -sf busybox "$ROOTFS/bin/init"

# ------------------------------------------------------------
# Gerando initramfs
# ------------------------------------------------------------

echo "==> Gerando initramfs..."

rm -f "$INITRAMFS"

(
    cd "$ROOTFS"

    find . -print0 |
        cpio --null -ov --format=newc |
        gzip -9
) >"$INITRAMFS"

# ------------------------------------------------------------
# Informações
# ------------------------------------------------------------

SIZE="$(du -h "$INITRAMFS" | cut -f1)"

echo
echo "======================================"
echo " RootFS criado com sucesso"
echo "======================================"
echo
echo "RootFS:     $ROOTFS"
echo "Initramfs:  $INITRAMFS"
echo "Tamanho:    $SIZE"
echo
echo "Teste:"
echo
echo "qemu-system-x86_64 \\"
echo "    -kernel arch/x86/boot/bzImage \\"
echo "    -initrd $INITRAMFS \\"
echo '    -append "console=ttyS0" \\'
echo "    -nographic"
echo
