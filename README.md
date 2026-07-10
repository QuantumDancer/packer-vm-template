# Packer RHEL 9 VM Template for Proxmox

Automated creation of a RHEL 9 UEFI VM template in Proxmox using Packer, ready
for cloud-init based cloning (e.g. via
[terraform-infra](../terraform-infra)).

## How it works

1. Packer creates a VM (ID 9001) on the Proxmox node and boots the RHEL 9 ISO.
2. The kickstart file is attached as a second CD labeled `OEMDRV` — anaconda
   picks it up automatically, so the installer needs **no network access back
   to the machine running Packer**. (This matters here: the VM VLAN blocks
   traffic to private subnets, so the classic Packer HTTP kickstart server is
   unreachable from the build VM.)
3. Kickstart performs a minimal UEFI install with `qemu-guest-agent`,
   `cloud-init`, and `cloud-utils-growpart`, plus a temporary `packer`
   provisioning user.
4. Packer connects over SSH and runs the provisioning scripts (cloud-init
   configuration, template cleanup).
5. The VM is converted to the template `rhel-9-template`.

A full build takes about 6 minutes.

## Key design decisions

- **UEFI/OVMF** with a 4M EFI disk. Old BIOS/MBR VMs cannot be switched to
  this template.
- **No cloud-init drive is baked into the template.** Proxmox places Packer's
  cloud-init drive on the IDE bus, which RHEL 9 guests booted via OVMF cannot
  see. Clones must attach their own drive on the SCSI bus — the terraform
  `proxmox-vm` module does this on `scsi30`.
- **The `packer` build user removes itself** on the first boot of every clone
  (via a cloud-init per-instance script installed during cleanup).
- **Root is locked** (`rootpw --lock`); all access goes through the
  cloud-init provisioned user.
- **kdump is disabled** to avoid the permanent crashkernel RAM reservation on
  every clone.

## Prerequisites

1. **Proxmox VE** with:
   - RHEL 9 ISO uploaded to `local` storage
   - API token for Packer (e.g. `root@pam!packer`)
   - Network bridge configured (default: `vmbr1`)
2. **Packer** (with the `proxmox` plugin, installed by `packer init`) and
   `mkisofs`/`xorriso` on the build machine (used to generate the kickstart
   CD).
3. Network-wise the build machine only needs to reach the **Proxmox API**
   (port 8006); the build VM never connects back to it.

## Directory Structure

```
packer-vm-template/
├── rhel9-template.pkr.hcl          # Main Packer template
├── variables.pkr.hcl               # Variable definitions
├── variables.pkrvars.hcl.example   # Example configuration
├── kickstart/
│   └── ks.cfg                      # Kickstart file (delivered via OEMDRV CD)
├── scripts/
│   ├── cloud-init-setup.sh         # Cloud-init configuration
│   └── template-cleanup.sh         # Template preparation
└── build-scripts/
    ├── build-template.sh           # Delete old template + run packer build
    └── cleanup-vm.sh               # Delete VM/template with the build VM ID
```

## Setup

```bash
# 1. Configure variables
cp variables.pkrvars.hcl.example variables.pkrvars.hcl
$EDITOR variables.pkrvars.hcl

# 2. Install the Proxmox plugin
packer init .

# 3. Validate
packer validate -var-file=variables.pkrvars.hcl .
```

The SSH password in `variables.pkrvars.hcl` must match the `packer` user's
hash in `kickstart/ks.cfg`. Generate a new hash with:

```bash
openssl passwd -6 'your-temporary-password'
```

(The password only exists during the build; the user is deleted on first boot
of every clone.)

## Building

```bash
./build-scripts/build-template.sh
```

**Warning:** this deletes the existing template (VM ID 9001) before building
its replacement. If the build fails, there is no template until a rebuild
succeeds. Full clones made earlier are unaffected.

Alternatively, run the steps manually:

```bash
./build-scripts/cleanup-vm.sh                  # delete old template 9001
packer build -var-file=variables.pkrvars.hcl . # build the new one
```

## Using the template

The intended path is the `proxmox-vm` module in
[terraform-infra](../terraform-infra), which attaches the cloud-init drive on
`scsi30` and configures user, SSH keys, IP, and DNS.

For a manual clone, you must attach a cloud-init drive **on the SCSI bus**
(an IDE cloud-init drive is invisible to the guest under OVMF):

```bash
qm clone 9001 100 --name my-vm --full
qm set 100 --scsi30 local-zfs:cloudinit
qm set 100 --ciuser benjamin --sshkeys ~/.ssh/id_ed25519.pub --ipconfig0 ip=dhcp
qm start 100
```

## Customization

- **Packages**: edit the `%packages` section in `kickstart/ks.cfg`.
- **Partitioning, timezone, keyboard**: also in `kickstart/ks.cfg`.
- **Extra provisioning**: add scripts under `scripts/` and reference them as
  `shell` provisioners in `rhel9-template.pkr.hcl`.
- **Hardware defaults** (4 cores, 4 GB RAM, 10G disk on `local-zfs`): override
  in `variables.pkrvars.hcl`.

Note that cloud-init's package-upgrade module is disabled in the template
(`scripts/cloud-init-setup.sh`) because clones may not be subscription-
registered; see the comment there for details.

## Troubleshooting

- **Build fails with "ISO not found"** — check the exact ISO volid:
  `pvesm list local --content iso`.
- **SSH timeout during build** — the install likely failed or the kickstart
  was not applied. Watch the VM console in the Proxmox UI, or grab a
  screenshot from the node:
  `ssh root@<node> 'echo "screendump /tmp/vm.ppm" | qm monitor 9001'`.
- **Cloud-init not working after a manual clone** — make sure the cloud-init
  drive is on the SCSI bus (`scsi30`), not IDE; see "Using the template".

## Files to secure

`variables.pkrvars.hcl` contains the Proxmox API token and build password and
is excluded by `.gitignore` (along with `*.auto.pkrvars.hcl` and logs). Never
commit it.

## References

- [Packer Proxmox Builder Documentation](https://developer.hashicorp.com/packer/integrations/hashicorp/proxmox)
- [RHEL 9 Kickstart Documentation](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html/performing_an_advanced_rhel_installation/index)
- [Cloud-init Documentation](https://cloudinit.readthedocs.io/)
- [Proxmox Cloud-Init Support](https://pve.proxmox.com/wiki/Cloud-Init_Support)
