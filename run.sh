#!/bin/bash

# Kiểm tra quyền root
if [ "$EUID" -ne 0 ]; then
    echo "Vui lòng chạy script với quyền root."
    exit
fi

# Cài đặt các gói cần thiết
echo "Cài đặt các gói cần thiết..."
apt update && apt install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils wget cloud-image-utils

# Kiểm tra KVM đã được kích hoạt chưa
if ! lsmod | grep -i kvm > /dev/null; then
    echo "KVM không được kích hoạt. Hãy kiểm tra BIOS và bật ảo hóa (VT-x/AMD-V)."
    exit
fi

# Tải Ubuntu Server Cloud Image (Minimal ISO)
IMAGE_URL="https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
IMAGE_PATH="/var/lib/libvirt/images/ubuntu-22.04-cloud.img"
if [ ! -f "$IMAGE_PATH" ]; then
    echo "Tải Ubuntu Cloud Image..."
    wget -O "$IMAGE_PATH" "$IMAGE_URL"
fi

# Tạo ổ đĩa cho máy ảo
VM_DISK="/var/lib/libvirt/images/ubuntu-22.04.qcow2"
if [ ! -f "$VM_DISK" ]; then
    echo "Tạo ổ đĩa máy ảo..."
    qemu-img create -f qcow2 -b "$IMAGE_PATH" "$VM_DISK" 20G
fi

# Tạo file dữ liệu cloud-init (để cài đặt SSH và tài khoản)
echo "Tạo dữ liệu cloud-init..."
META_DATA="meta-data"
USER_DATA="user-data"
CIDATA_ISO="/var/lib/libvirt/images/seed.iso"

cat > $META_DATA <<EOF
instance-id: ubuntu-2204
local-hostname: ubuntu-vm
EOF

cat > $USER_DATA <<EOF
#cloud-config
users:
  - name: ubuntu
    ssh_authorized_keys:
      - $(cat ~/.ssh/id_rsa.pub)  # Dùng khóa SSH hiện tại của bạn
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    groups: sudo
    shell: /bin/bash
runcmd:
  - apt-get update
  - apt-get install -y openssh-server
  - systemctl enable ssh
  - systemctl start ssh
  - apt-get install -y docker.io
  - systemctl enable docker
  - systemctl start docker
EOF

# Tạo file ISO chứa cloud-init
echo "Tạo file ISO chứa cloud-init..."
genisoimage -output "$CIDATA_ISO" -volid cidata -joliet -rock $USER_DATA $META_DATA

# Tạo máy ảo với bridge mạng vật lý
VM_NAME="Ubuntu22.04-VPS"
BRIDGE="br0" # Bridge mạng gắn IP Public hoặc IP nội bộ của máy chủ
echo "Tạo máy ảo $VM_NAME với SSH và Docker..."
virt-install \
    --name "$VM_NAME" \
    --ram 2048 \
    --vcpus 2 \
    --disk path="$VM_DISK",format=qcow2 \
    --disk path="$CIDATA_ISO",device=cdrom \
    --os-type linux \
    --os-variant ubuntu22.04 \
    --network bridge=$BRIDGE,model=virtio \
    --noautoconsole \
    --import

# Thông báo hoàn thành
echo "Máy ảo $VM_NAME đã được tạo thành công!"
echo "Đăng nhập vào máy ảo qua SSH với user 'ubuntu'."
