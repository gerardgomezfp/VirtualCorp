ifeq ($(wildcard .env),)
$(error Missing .env; create it from .env.example with: cp .env.example .env)
endif

include .env

export PROJECT_ROOT ARTIFACTS_DIR CONFIGS_DIR SSH_PUBLIC_KEY_DIR SSH_PRIVATE_KEY_DIR
export ROUTEROS_VERSION ROUTEROS_VDI_FILENAME ROUTEROS_VDI_PATH ROUTEROS_BOX_NAME ROUTEROS_BOX_FILE
export VBOX_ROOT_GROUP VM_ROUTERS_GROUP VM_TEMPLATES_GROUP VM_EQUIPMENT_GROUP VM_EQUIPMENT_BASEFOLDER VBOXMANAGE_BIN

BASH_DIR := $(PROJECT_ROOT)/infrastructure/bash
BOOTSTRAP_DIR := $(PROJECT_ROOT)/automation/scripts/bootstrap

.PHONY: help deploy-routers delete-routers reset-routers reset_routers ssh-keys routeros-box create_templates deploy_equipment deploy_pve

help:
	@printf '%s\n' \
	  'Targets:' \
	  '  deploy-routers  Create and configure the router VMs' \
	  '  delete-routers  Delete the router VM group' \
	  '  reset-routers   Delete and redeploy the router VMs' \
	  '  ssh-keys        Generate the project SSH keys' \
	  '  routeros-box    Build the RouterOS Virtual box' \
	  '  create_templates  Create Debian Server and Desktop templates' \
	  '  deploy_equipment  Deploy all Delegation 8 equipment' \
	  '  deploy_pve  Install Proxmox VE (pve01) unattended'

deploy-routers:
	"$(BASH_DIR)/deploy_routers.sh"

delete-routers:
	"$(BASH_DIR)/del_vbox_group.sh" --routers

reset-routers:
	"$(BASH_DIR)/del_vbox_group.sh" --routers
	"$(BASH_DIR)/deploy_routers.sh"

# Keep the original target name available for existing callers.
reset_routers: reset-routers

ssh-keys:
	"$(BOOTSTRAP_DIR)/create_ssh_keys.sh"

routeros-box:
	"$(BOOTSTRAP_DIR)/create_mikrotik_box.sh"

# Assegura que les plantilles base existeixen abans de desplegar res
create_templates:
	bash "$(BASH_DIR)/vcorp_create_templates.sh"

# Desplegament unificat: Clona els 29 equips, els configura i llança pve01
deploy_equipment:
	bash "$(BASH_DIR)/deploy_equipment.sh"
	bash "$(BASH_DIR)/configure_equipment.sh" --all
	bash "$(BASH_DIR)/deploy_pve.sh"