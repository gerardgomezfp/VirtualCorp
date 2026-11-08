# VirtualCorp

VirtualCorp is a virtual networking lab for designing and deploying a branch office network. It uses MikroTik RouterOS CHR virtual machines on VirtualBox and automates their setup with shell scripts and Make.

Read the [full project statement](docs/statement.html) for the scenario, requirements, and detailed assignment.

## 📚 Documentació de les Activitats

Pots consultar les memòries tècniques i el desenvolupament complet de cada fase del projecte:

* **Exercici 1:** [Configuració i Desplegament de MikroTiks](./docs/exercici1-mikrotiks.md)
* **Exercici 2:** [Memòria Tècnica de Desplegament (Delegació 8)](./docs/memoria-tecnica-desplegament-vcorp.md)

---

## Getting started

### 1. Install prerequisites

Install GNU Make, VirtualBox with `VBoxManage`, `curl`, `unzip`, and the OpenSSH client. Make sure hardware virtualization is enabled on the host.

### 2. Adapt the environment

From the project root, create the local Make configuration and edit it for your machine:

```bash
cp .env.example .env
