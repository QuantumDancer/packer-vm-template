# Packer RHEL 9 VM Template for Proxmox

Automated creation of a RHEL 9 UEFI VM template in Proxmox using Packer, ready
for cloud-init based cloning (e.g. via
[terraform-infra](../terraform-infra)).

## How it works

1. Packer creates a VM under a **temporary ID** (`vm_id + 1`, i.e. 9002) on
   the Proxmox node and boots the RHEL 9 ISO. The live template (ID 9001)
   keeps serving clones during the whole build.
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
5. The VM is converted to the template `rhel-9-template` (still at 9002).
6. Only after a successful build is the new template promoted to the live ID:
   delete the old 9001, full-clone 9002 → 9001, convert to template, delete
   9002. Proxmox cannot renumber VMs, hence the clone. A failed build leaves
   the old template untouched; the only template-less window is the few
   seconds of the swap after a build has already succeeded.

Terraform's `proxmox-vm` module references the template **by VM ID**, so the
ID must stay stable across rebuilds — that is what the promotion step
guarantees.

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
├── .gitlab-ci.yml                  # CI: validate on branches, build on main
├── rhel9-template.pkr.hcl          # Main Packer template
├── variables.pkr.hcl               # Variable definitions
├── variables.ci.pkrvars.hcl        # Non-secret values used by CI builds
├── kickstart/
│   └── ks.cfg                      # Kickstart file (delivered via OEMDRV CD)
├── scripts/
│   ├── cloud-init-setup.sh         # Cloud-init configuration
│   └── template-cleanup.sh         # Template preparation
└── build-scripts/
    ├── build-template.sh           # Entry point: cleanup → build → promote
    ├── cleanup-vm.sh               # Remove leftover temp build VM (9002)
    ├── promote-template.sh         # Swap successful build into live ID 9001
    └── proxmox-lib.sh              # Shared var parsing + Proxmox API helpers
```

## Configuration

Build values live in two places:

- `variables.pkr.hcl` declares the variables (types, defaults).
- `variables.ci.pkrvars.hcl` holds the actual, secret-free values (Proxmox
  URL and node, ISO, VM IDs, hardware sizing). Hardware defaults are 4 cores,
  4 GB RAM, and a 10G disk on `local-zfs`.

The two secrets — the Proxmox API token and the `packer` build password — are
never stored in the repo. They come from the masked+protected GitLab CI
variables `PROXMOX_TOKEN` and `PACKER_SSH_PASSWORD`, which the pipeline
appends to a generated `variables.pkrvars.hcl` at build time.

`PACKER_SSH_PASSWORD` must match the `packer` user's hash in
`kickstart/ks.cfg`. To rotate it, generate a new hash, commit it, and update
the CI variable to the matching plaintext:

```bash
openssl passwd -6 'your-temporary-password'
```

(The password only exists during the build; the user is deleted on first boot
of every clone.)

## Building

Builds run in GitLab CI — that is the only supported path, since the runner
lives on the packer VM and has the network access and secrets the build needs.

Every push runs `packer fmt -check` + `packer validate`; a push to `main`
additionally runs the full build on the shell-executor runner (tag `packer`,
`resource_group` prevents overlapping builds). See `.gitlab-ci.yml`.

The build itself is `build-scripts/build-template.sh`: it removes any leftover
temp VM, runs Packer under the temporary ID 9002, then promotes the result to
the live ID 9001. The existing template survives a failed build, and a build
that dies mid-way is cleaned up by the next run.

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
- **Hardware defaults** (4 cores, 4 GB RAM, 10G disk on `local-zfs`): edit
  `variables.ci.pkrvars.hcl`.

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

Nothing in the repo carries a secret. The Proxmox API token and the build
password live only in GitLab CI variables and in the `variables.pkrvars.hcl`
the pipeline generates on the runner, which `.gitignore` excludes (along with
`*.auto.pkrvars.hcl` and logs).

## References

- [Packer Proxmox Builder Documentation](https://developer.hashicorp.com/packer/integrations/hashicorp/proxmox)
- [RHEL 9 Kickstart Documentation](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html/performing_an_advanced_rhel_installation/index)
- [Cloud-init Documentation](https://cloudinit.readthedocs.io/)
- [Proxmox Cloud-Init Support](https://pve.proxmox.com/wiki/Cloud-Init_Support)
