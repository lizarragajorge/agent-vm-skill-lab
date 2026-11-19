# Agent-to-VM reference demo

**Setting this up in your own environment?** Start with
[README-FOUNDRY.md](README-FOUNDRY.md). The quick start shows how to select a
model, connect an agent to your existing Azure Linux VM, and test it in
Playground. Adding a native Foundry skill is an optional follow-up.

## What this demo proved

A Foundry prompt agent called an OpenAPI tool, which used Logic Apps and
Azure Run Command to run `uname -s && hostname` on a private Azure VM. The
live test used the Foundry Responses API and returned `Linux`,
`vm-agent-skill-lab`, and no stderr. No public IP or inbound SSH was needed.
The original demo did not attach a native Foundry skill.

## Test in the Foundry Playground

1. If you have access to the deployed lab, open **VM Lab Sandbox > Build >
   Agents > vm-lab > Playground** in [Microsoft Foundry](https://ai.azure.com/).
2. Send: **Run the Azure VM diagnostic now and report what the guest returned.**
3. Open `identify_vm` in the tool trace. Its output should show `Linux` and the
   guest hostname (`vm-agent-skill-lab` in the demo), with no stderr.

## Run a command directly in the Azure portal

For a running Azure Linux VM you can administer, open the
[Azure portal](https://portal.azure.com/) and select **Virtual machines → your
VM → Operations → Run command → RunShellScript**. Paste `uname -s && hostname`
and select **Run**. This verifies Azure can reach the guest, not that the
Foundry agent can.

To recreate the demo, see [deploy the reference lab](README-FOUNDRY.md#deploy-from-this-repo).
For local Copilot over SSH instead of Foundry, see [EXISTING-VM.md](EXISTING-VM.md).
