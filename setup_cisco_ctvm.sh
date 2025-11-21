#!/bin/bash

# =============== КОНФИГУРАЦИЯ ===============
VMID=104
VM_NAME="cisco-ctvm"
ISO_PATH="/mnt/data/template/iso/AS_CTVM_LARGE_8_10_196_0.iso"
STORAGE="local-lvm"           # или "local", если используете каталог
BRIDGE_PHYSICAL="vmbr0"       # мост, к которому подключён физический интерфейс
OVS_BRIDGE="ovsbr"            # имя OVS-моста (должно совпадать с ожидаемым в Cisco)
MAC1="00:50:56:01:00:01"
MAC2="00:50:56:01:00:02"
# ==========================================

set -e  # Остановить при любой ошибке

echo "🔧 Установка Open vSwitch..."
apt-get update
apt-get install -y openvswitch-switch bridge-utils

echo "🔧 Создание OVS-моста $OVS_BRIDGE..."
ovs-vsctl add-br "$OVS_BRIDGE" 2>/dev/null || true

echo "🔧 Создание внутреннего порта для связи с $BRIDGE_PHYSICAL..."
ovs-vsctl add-port "$OVS_BRIDGE" ovsbr-uplink -- set interface ovsbr-uplink type=internal 2>/dev/null || true

echo "🔧 Подключение ovsbr-uplink к $BRIDGE_PHYSICAL..."
ip link set ovsbr-uplink up
brctl addif "$BRIDGE_PHYSICAL" ovsbr-uplink 2>/dev/null || true

echo "🔧 Делаем настройку постоянной..."
cat > /etc/network/interfaces.d/ovsbr <<EOF
auto ovsbr-uplink
iface ovsbr-uplink inet manual
    pre-up ovs-vsctl add-br $OVS_BRIDGE 2>/dev/null || true
    pre-up ovs-vsctl add-port $OVS_BRIDGE ovsbr-uplink -- set interface ovsbr-uplink type=internal 2>/dev/null || true
    up ip link set ovsbr-uplink up
    up brctl addif $BRIDGE_PHYSICAL ovsbr-uplink 2>/dev/null || true
EOF

echo "✅ OVS настроен. Создаём ВМ $VMID..."

# Удаляем старую ВМ, если существует
qm destroy "$VMID" --destroy-unreferenced-disks --purge 2>/dev/null || true

# Создаём ВМ
qm create "$VMID" \
  --name "$VM_NAME" \
  --memory 8192 \
  --cores 2 \
  --cpu kvm64 \
  --bios seabios \
  --vga vmware \
  --scsihw virtio-scsi-pci \
  --scsi0 "$STORAGE":8,format=raw \
  --net0 e1000,bridge="$OVS_BRIDGE",macaddr="$MAC1" \
  --net1 e1000,bridge="$OVS_BRIDGE",macaddr="$MAC2"

# Подключаем ISO
qm set "$VMID" --ide2 "$ISO_PATH",media=cdrom

echo "✅ ВМ создана!"
echo ""
echo "➡️  Запустите установку:"
echo "   qm start $VMID"
echo ""
echo "ℹ️ После завершения установки и перезагрузки отключите ISO:"
echo "   qm set $VMID --ide2 none,media=cdrom"
