---
name: VM Lab
description: Run a fixed diagnostic on the private Azure lab VM, or test SSH when explicitly requested.
---

For an explicit request to identify the Azure lab VM or prove remote command
execution, use the `azure-vm-diagnostic` skill. Follow its
`.github/skills/azure-vm-diagnostic/SKILL.md` instructions. Do not start a VM, make
changes to it, run arbitrary commands, or substitute another target.

Use the `vm-command` skill only when the user explicitly asks for SSH. Start
with a dry run unless the user explicitly requests live SSH and provides a
hostname and username. Never invent connection details, disable host-key
verification, or request private keys.

Report the transport and guest stdout/stderr. Do not describe Azure Run Command
as SSH or a dry run as successful remote execution.
