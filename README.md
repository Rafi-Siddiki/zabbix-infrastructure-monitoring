# Zabbix Infrastructure Monitoring

![Screenshot](images/image5.png)

A production-oriented collection of **Zabbix 7.4 hardware monitoring templates** for mixed infrastructure environments.

This repository documents and packages a monitoring setup built around this workflow:

> **Read vendor MIBs → identify useful OIDs → build Zabbix templates → normalize statuses into a shared numeric model → display them consistently in dashboards and honeycomb tiles.**

It combines:

- **SNMP-based vendor templates** for Dell, HPE, IBM, Lenovo, and Synology
- **Agent-based Proxmox RAID SMART monitoring** for MegaRAID-backed disks using `smartctl`
- **Normalized value mapping** so dashboard tiles can use consistent color logic
- **Discovery-heavy monitoring** for disks, RAID, power, fans, memory, CPU, and other hardware components

---

## What is a monitoring tool?

A monitoring tool is a platform that continuously checks the health, status, and behavior of infrastructure components such as:

- servers
- disks and RAID controllers
- fans, PSUs, and temperature sensors
- memory and CPU
- network interfaces
- storage appliances and NAS devices

Instead of engineers manually logging into each device and checking hardware one by one, a monitoring tool collects the data centrally, evaluates it, and highlights what is healthy, degraded, or failed.

In this repository, **Zabbix** is the monitoring platform used to collect hardware data through **SNMP** and **Zabbix Agent 2**.

---

## Why monitoring is needed

In our current environment, hardware checks often have to be done **manually** across multiple devices and vendors.

That creates several operational problems:

- it is **time-consuming**
- it is **error-prone**
- it depends too much on **manual effort**
- it is difficult to maintain a **consistent checking process**
- hardware issues can be **missed or noticed late**

When the process is manual, teams usually need to open each server interface, review health states, compare disk or RAID conditions, and repeat the same work again and again. As the environment grows, this becomes harder to sustain.

---

## Existing problem statement

The main reason for building this setup was simple: **the company should not need to manually check every single hardware component every time it wants to confirm system health.**

Before this monitoring approach:

- hardware status checks were not centralized
- checks were repetitive and manual
- different vendors exposed information differently
- there was no single automated view for quick health validation

This repository solves that by creating a structured monitoring approach where Zabbix can:

- automatically collect hardware data
- discover components dynamically
- normalize vendor-specific states
- show clear dashboard colors and tiles
- reduce manual checking effort

So the value of this repository is not only in the templates themselves — it is in turning a **manual hardware validation process** into a more **automated, repeatable, and operationally useful monitoring system**.

---

## Project start and deployment approach

When this project started, the first design decision was to run **Zabbix inside a container on a virtual machine**.

That decision was made to make the setup:

- easier to **replicate**
- easier to **rebuild**
- easier to **move between environments**
- easier to **document in a clean and repeatable way**

Using a containerized Zabbix deployment on a VM gave a practical balance between:

- VM-level isolation and infrastructure control
- container-level portability
- simpler documentation and repeatability for future deployments

This repository should therefore be understood not only as a template collection, but also as the documented result of building a **replicable monitoring environment**.

---

## Why this repository exists

Zabbix hardware monitoring often becomes messy in real environments because each vendor exposes:

- different MIB trees
- different status texts and numeric values
- different discovery patterns
- different dashboard behavior
- different levels of built-in Zabbix template support

The goal of this repo is to make those templates **portable, understandable, and reusable**.

This repo is especially useful if you want:

- a **single place** to keep your Zabbix hardware templates
- a **repeatable process** for importing and maintaining templates
- **dashboard-friendly state normalization** across different vendors
- a clean GitHub repository you can extend over time

---

## Template development journey

One of the main practical challenges during this project was hardware template availability.

In our data center, one of the most common server models is the **Lenovo SR650**. Zabbix did not provide a built-in template that matched our needs for this hardware, so the initial plan of simply importing an official template was not possible.

### What happened first

The first step was to search online for an existing Lenovo community template. Only **one community template** could be found that was somewhat relevant.

### Why that was not enough

Although that template was helpful as a starting point, it was **not suitable enough for our environment and monitoring requirements**. In practice, that meant:

- the available items were incomplete for our needs
- the structure was not aligned with the dashboard style we wanted
- the extracted values were not consistent enough for unified visual monitoring
- it did not fully solve the problem of cross-vendor status consistency

### What had to be done instead

Because of that, the template work had to move from simple reuse to actual template engineering.

The workflow became:

1. inspect the vendor **MIB tree**
2. browse the MIB structure using the **Observium MIB browser / database**
3. identify the useful OIDs required for monitoring
4. test and validate which values were operationally meaningful
5. build Zabbix items, discovery rules, value maps, and dashboards from those OIDs

### AI-assisted template building

To speed up the template creation process, **AI was used as an accelerator**, especially for:

- generating template YAML structure faster
- building discovery prototypes more quickly
- producing initial value maps
- iterating on vendor-specific monitoring logic
- helping maintain **value consistency across templates** for unified dashboards

AI made the process faster, but the monitoring logic still depended on:

- understanding the vendor MIBs
- validating OIDs manually
- checking extracted values against actual device behavior
- aligning value maps so dashboards would stay visually consistent

So this project was not simply "generate a template and import it". It was a structured process of:

> **finding the correct MIB path, selecting useful OIDs, validating outputs, and then shaping the result into dashboard-friendly templates.**

---

## Monitoring approach

### 1. SNMP templates for vendor hardware
These templates monitor out-of-band or appliance hardware through SNMP:

- Dell PowerEdge R720 / iDRAC
- Dell PowerEdge R740
- HPE ProLiant DL380
- IBM IMM
- Lenovo XCC SR650
- Synology NAS

### 2. Agent-based monitoring for Proxmox RAID disks
For Proxmox RAID-backed disks, SNMP alone is not always enough. In this setup:

- a custom shell script runs on the Linux host
- the script uses `smartctl` against MegaRAID disks
- `zabbix-agent2` exposes the data through `UserParameter`
- Zabbix discovers disks and shows **HDD health** and **SSD wear** in a unified way

### 3. Shared dashboard semantics
Where possible, templates normalize component states into a common dashboard model such as:

- `0` = Unknown / not available
- `1` = OK / normal / online
- `2` = Spare / standby / unused where applicable
- `3` = Warning / degraded
- `4` = Rebuilding / in progress
- `5` = Failed / critical / offline

That makes it much easier to build **consistent tiles and honeycomb views** across vendors.

---

## Repository structure

```text
zabbix-hardware-monitoring/
├── README.md
├── .gitignore
├── docs/
│   ├── architecture.md
│   ├── deployment-guide.md
│   └── template-mapping.md
├── templates/
│   ├── dell/
│   │   └── DELL PowerEdge R720.yaml
│   │   └── DELL PowerEdge R740.yaml
│   ├── hpe/
│   │   └── HPE ProLiant DL380 SNMP.yaml
│   ├── ibm/
│   │   └── IBM IMM SNMPv3.yaml
│   ├── lenovo/
│   │   └── Lenovo XCC SNMPv3.yaml
│   ├── proxmox/
│   │   └── Proxmox RAID.yaml
│   └── synology/
│       └── Synology NAS SNMP.yaml
├── scripts/
│   └── proxmox/
│       └── proxmox_raid_pd_attr.sh.
├── configs/
│   └── zabbix-agent2/
│       └── proxmox-raid-smart.conf
│       └── zabbix_agent2.conf
└── sudoers/
    └── zabbix-smart-raid
```

---

## Included templates

| Vendor / Platform | Method | Main coverage |
|---|---|---|
| Dell PowerEdge R720 | SNMP | System health, controllers, virtual disks, physical disks, fan/temperature/power |
| Dell PowerEdge R740 | SNMP | System health, controllers, virtual disks, physical disks, fan/temperature/power |
| HPE ProLiant DL380 | SNMP | Unified health model, array cache, controllers, disks, network adapters, fans |
| IBM IMM | SNMPv3 | System health, storage pools, RAID PD/VD, PSU, temp, fan, SSD wear |
| Lenovo XCC | SNMPv3 | Hardware, PSU, fan, memory, CPU, firmware, RAID PD/VD, SSD wear |
| Synology NAS | SNMP | System, disks, RAID health, temperature, fans, DSM info, SSD wear |
| Proxmox RAID SMART | Agent2 + smartctl | MegaRAID disk discovery, HDD health, SSD wear, dynamic disk status |

---

### Get Zabbix Up and running

```bash
git clone https://github.com/Rafi-Siddiki/zabbix-infrastructure-monitoring.git
```
```bash
git cd /zabbix-infrastructure-monitoring/docker/
```
```bash
git docker compose up -d
```

#### Log into zabbix using

Username :
```bash
Admin
```
Password: 
```bash
zabbix
```

## Key design decisions

### ✅ Value normalization for dashboard colors
Different vendors report different states. This repository maps them into predictable dashboard values so tiles can use a common visual language:

- 🟩 **Green** → OK / normal
- 🟦 **Blue** → hot-spare / unconfigured-good / standby / in a healthy non-active role
- 🟨 **Yellow / orange** → warning / degraded / rebuilding
- 🟥 **Red** → failed / critical / offline
- ⬜ **Gray** → unknown / unavailable

### ✅ Discovery-first design
Low-level discovery is heavily used for:

- physical disks
- virtual disks
- RAID arrays / controllers
- fans
- PSUs
- memory modules
- network adapters
- firmware blocks

### ✅ Separation of vendor logic and dashboard logic
Vendor-specific logic stays inside each template, while normalized items make dashboards easier to share and maintain.

### ✅ Consistent value mapping for unified dashboards
One important design goal in this project was to keep dashboard semantics as consistent as possible across vendors.

That means the templates were adjusted so that, where reasonable:

- the same numeric status means the same visual severity
- honeycomb tiles can use the same threshold logic
- cross-vendor dashboards remain easier to understand operationally

This is especially important in mixed environments where Dell, HPE, Lenovo, IBM, Synology, and Proxmox systems may all appear in the same monitoring platform.

---

## Proxmox RAID SMART setup

The Proxmox part of this repository expects a custom script and `zabbix-agent2` configuration on the Linux host.

### Install required packages

```bash
sudo apt update
```
```bash
sudo apt install zabbix-agent2 smartmontools sudo -y
```

### Place the custom script

```bash
sudo nano /usr/local/bin/proxmox_raid_pd_attr.sh
```
```bash
sudo chown root:root /usr/local/bin/proxmox_raid_pd_attr.sh
```
```bash
sudo chmod 755 /usr/local/bin/proxmox_raid_pd_attr.sh
```

### Allow Zabbix to run the script

```bash
sudo visudo -f /etc/sudoers.d/zabbix-smart-raid
```

Expected content:

```sudoers
zabbix ALL=(ALL) NOPASSWD: /usr/local/bin/proxmox_raid_pd_attr.sh
```

Then set correct permission:

```bash
sudo chmod 440 /etc/sudoers.d/zabbix-smart-raid
```

### Configure Zabbix Agent 2

```bash
sudo cp /etc/zabbix/zabbix_agent2.conf /etc/zabbix/zabbix_agent2.conf.bak
```
```bash
sudo nano /etc/zabbix/zabbix_agent2.conf
```
```bash
sudo nano /etc/zabbix/zabbix_agent2.d/proxmox-raid-smart.conf
```

### Test manually

```bash
/usr/local/bin/proxmox_raid_pd_attr.sh discover /dev/sda
```
```bash
sudo zabbix_agent2 -t raid.pd.discovery
```
```bash
sudo zabbix_agent2 -t 'raid.pd.wear[0]'
```

### Restart and verify

```bash
sudo systemctl enable zabbix-agent2
```
```bash
sudo systemctl restart zabbix-agent2
```
```bash
sudo ss -tulpn | grep :10050
```

---

## Importing templates into Zabbix

1. Open **Zabbix → Data collection → Templates**
2. Click **Import**
3. Select the YAML file from the relevant vendor folder under `templates/`
4. Review value maps, dashboards, items, and discovery rules
5. Import the template
6. Link the template to the matching host
7. Verify latest data, discovery, and dashboard tiles

---

## Adding a device into Zabbix

Before adding a device in the Zabbix UI, the most important prerequisite is that the device must already be prepared for monitoring.

### Step 0: Create an SNMP monitoring account on the device

For SNMP-based monitoring, you first need to create or enable an **SNMP monitoring account / SNMP configuration** on the server, appliance, or management controller.

This part is vendor-specific.

Different devices have different:

- web interfaces
- menu paths
- authentication methods
- SNMP version support
- security settings
- permission models

So in practice, this means you often need to do some **device-specific research** to find the correct method for that particular hardware.

Examples:

- Dell iDRAC SNMP configuration is different from Lenovo XCC
- Lenovo XCC setup is different from IBM IMM
- Synology DSM SNMP setup is different from server BMC interfaces
- HPE iLO / SNMP process differs again

So the real onboarding flow is usually:

1. identify the device vendor and model
2. search for the proper SNMP enablement process for that device
3. create the monitoring account or configure SNMP community / SNMPv3 user
4. confirm network reachability from Zabbix to the target
5. test SNMP access
6. then add the host in Zabbix

### Recommended preparation checklist

Before creating the host in Zabbix, make sure you know:

- device IP / DNS name
- vendor and model
- whether it uses **SNMPv2c** or **SNMPv3**
- community string or SNMPv3 credentials
- the correct template to apply
- whether firewall rules allow Zabbix to reach UDP/161

---

### 1. Navigate to **Data collection → Hosts**

![Screenshot](images/image1.png)

---

### 2. Click **Create host**

![Screenshot](images/image2.png)

---

### 3. Fill in the basic host information

Provide the following carefully:

1. **Hostname** — must be unique for every device
2. **Visible name** — the display name you want shown in Zabbix
3. **Template** — select the correct vendor template from this repository
4. **Host group** — choose a group that makes filtering easier later (for example: Lenovo Servers, Dell Servers, NAS, Proxmox)
5. **Interface type** — choose the required interface type, most commonly **SNMP** for these templates

![Screenshot](images/image3.png)

---

### 4. Fill in the SNMP interface details

Enter the required SNMP fields according to the SNMP version used by the device:

- for **SNMPv2c**, configure the community string
- for **SNMPv3**, configure the username, authentication, privacy method, and related credentials

Make sure the SNMP settings entered in Zabbix match exactly what was configured on the device.

![Screenshot](images/image4.png)

---

### 5. Validate after adding the host

After saving the host:

- confirm the template linked successfully
- check **Latest data**
- confirm discovery rules start creating items
- verify that dashboard tiles and honeycomb widgets show expected values
- test whether the value mapping looks correct for that device type

---

## Maintainer note

This repository reflects a practical hardware monitoring implementation where templates were developed by:

- understanding the operational monitoring need
- containerizing Zabbix on a VM for easier replication
- reading vendor MIBs
- identifying useful OIDs
- checking MIB trees through the Observium MIB browser/database
- generating and refining template logic with AI assistance
- validating extracted values against actual hardware behavior
- mapping hardware states into consistent dashboard values

In other words, this repository is the result of both **monitoring design** and **template engineering**, built to reduce manual hardware checking and provide clearer, more unified infrastructure visibility.
