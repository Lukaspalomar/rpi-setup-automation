#!/bin/bash

# Variables

TERRAFORM_VERSION="1.4.5"
TERRAFORM_URL="https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_arm64.zip"
INSTALL_DIR="/usr/local/bin"
TERRAFORM_BIN="${INSTALL_DIR}/terraform"
SSH_PRIVATE_KEY_PATH="${HOME}/.ssh/id_rsa"
SSH_PUBLIC_KEY_PATH="${HOME}/.ssh/id_rsa.pub"
TF_DIR="${HOME}/terraform_ansible"

# Ensure the install directory exists

sudo mkdir -p ${INSTALL_DIR}

# Download and install Terraform

if [ ! -f ${TERRAFORM_BIN} ]; then
  echo "Downloading Terraform..."
  wget -q ${TERRAFORM_URL} -O /tmp/terraform.zip
  echo "Installing Terraform..."
  sudo unzip -o /tmp/terraform.zip -d ${INSTALL_DIR}
  sudo chmod +x ${TERRAFORM_BIN}
  rm /tmp/terraform.zip
fi

# Ensure Terraform is in the PATH

export PATH=$PATH:${INSTALL_DIR}

# Verify Terraform installation

terraform --version

# Create the Terraform configuration directory if it doesn't exist

mkdir -p ${TF_DIR}

# Create setup_rpi.yml
cat > "${TF_DIR}/setup_rpi.yml" <<EOF
---
- name: Setup Raspberry Pi
  hosts: all
  become: yes
  tasks:
    - name: Add InfluxData repository key
      ansible.builtin.command:
        cmd: wget -q0- https://repos.influxdata.com/influxdb.key | sudo tee /etc/apt/trusted.gpg.d/influxdb.asc >/dev/null
      register: result

    - name: Add InfluxData repository
      ansible.builtin.command:
        cmd: echo 'deb https://repos.influxdata.com/debian stable main' | sudo tee /etc/apt/sources.list.d/influxdata.list
      when: result is succeeded

    - name: Remove old InfluxDB key
      ansible.builin.command:
        cmd: sudo rm -f /etc/apt/trusted.gpg.d/influxdb.gpg

    - name: Update apt package index
      ansible.builtin.apt:
        update_cache: yes
        cache_valid_time: 3600

    - name: Install required packages
      ansible.builtin.apt:
        name:
          - vim
          - tcpdump
          - telnet
          - vlan
          - rsync
          - picocom
          - telegraf
          - tshark
          - python3-pip
          - autossh
        state: present
        update_cache: yes

    - name: Print InfluxData repository key fingerprint
      ansible.builtin.command:
        cmd: gpg --with-fingerprint --show-keys /etc/apt/trusted.gpg.d/influxdb.asc
EOF

# Create hosts.ini
cat > "${TF_DIR}/hosts.ini" <<EOF
[all]
cureit ansible_host=10.195.132.70 ansible_user=cureit ansible_ssh_private_key_file=${SSH_PRIVATE_KEY_PATH}
EOF

# Create main.tf

cat > ${TF_DIR}/main.tf <<EOF
provider "local" {

  # This provider is used for local file operations
}

provider "null" {
  # Null provider to run external scripts
}

resource "null_resource" "ansible_playbook" {
  provisioner "local-exec" {
    command = "ansible-playbook -i \${self.triggers.inventory_file} \${self.triggers.playbook}"
    environment = {
      ANSIBLE_HOST_KEY_CHECKING = "false"
    }
  }
  triggers = {
    inventory_file = "\${path.module}/hosts.ini"
    playbook       = "\${path.module}/setup_rpi.yml"
  }
}

EOF

# Create variables.tf
cat > ${TF_DIR}/variables.tf <<EOF
variable "ssh_private_key_path" {
  description = "Path to the SSH private key"
  type        = string
}

variable "ssh_public_key_path" {
  description = "Path to the SSH public key"
  type        = string
}

EOF

# Ensure the playbook and inventory files exist

if [ ! -f ${TF_DIR}/setup_rpi.yml ] || [ ! -f ${TF_DIR}/hosts.ini ]; then
  echo "Please ensure setup_rpi.yml and hosts.ini are present in ${TF_DIR}."
  exit 1
fi

# Initialize and apply Terraform

cd ${TF_DIR}
terraform init -input=false
terraform apply -auto-approve -var "ssh_private_key_path=${SSH_PRIVATE_KEY_PATH}" -var "ssh_public_key_path=${SSH_PUBLIC_KEY_PATH}"

echo "Terraform apply complete."
