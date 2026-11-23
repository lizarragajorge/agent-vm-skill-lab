# Foundry agent-to-VM lab

Ask a Foundry agent to identify a Linux VM and see the OS and hostname returned
by the guest. A standard Foundry prompt agent calls the `identify_vm`
OpenAPI tool, which uses a Logic App and Azure Run Command to run
`uname -s && hostname`. No inbound SSH or VM public IP is needed.

**What you need:** A running Azure Linux VM with working Run Command, a
Foundry project with a deployed model, and a VM tool configured for that VM.
To set up the included tool, you or an administrator need permission to deploy
the workflow and assign its VM-scoped role, and to create a connection in
Foundry.

**What this repo provides:** [A workflow template](foundry/workflow.bicep)
that wires up the fixed VM command and managed identity, plus
[a project template](foundry/project.bicep) and
[registration script](foundry/register-agent.sh) to recreate the full demo.

**Already have Foundry and a VM?** Start with the
[fresh-setup checklist](README-FOUNDRY.md#start-here). Reuse your VM and any
existing Foundry project and model deployment. You don't need a repository
of your own.

## Deploy from this repo

<details>
<summary>Recreate the reference lab with Azure CLI</summary>

Download or clone the lab and open a Bash terminal in its folder. You'll need
Azure CLI with Bicep, `jq`, `curl`, `ssh-keygen` if creating a VM, and permission
to deploy resources and create custom roles and role assignments. Use a
subscription and region with capacity for the VM and model.

```bash
set -euo pipefail
umask 077
az login
SUBSCRIPTION='YOUR_LAB_SUBSCRIPTION'
RG='rg-agent-vm-skill-lab-se'
LOCATION='swedencentral'
VM='vm-agent-skill-lab'
mkdir -p .vm-lab/azure
```

If you don't already have a lab VM, create it in a dedicated resource group.
Otherwise, set `RG`, `LOCATION`, and `VM` to match the VM you plan to use and
skip this block.

```bash
test -f .vm-lab/azure/id_ed25519.pub ||
  ssh-keygen -t ed25519 -f .vm-lab/azure/id_ed25519
az group create --subscription "$SUBSCRIPTION" --name "$RG" --location "$LOCATION"
az vm create --subscription "$SUBSCRIPTION" --resource-group "$RG" \
  --name "$VM" --location "$LOCATION" --image Ubuntu2404 --size Standard_B2as_v2 \
  --admin-username vmuser --authentication-type ssh \
  --ssh-key-values .vm-lab/azure/id_ed25519.pub \
  --public-ip-address '' --nsg-rule NONE --storage-sku StandardSSD_LRS
```

In the same terminal, deploy the Foundry project and model, deploy the VM
workflow, and register the agent. The registration script uses the reference
VM hostname in its instructions; if you selected a different VM, update the
agent instructions in Foundry to report its actual tool output.

```bash
az deployment group create --subscription "$SUBSCRIPTION" --resource-group "$RG" \
  --name vm-lab-foundry --template-file foundry/project.bicep \
  --parameters location="$LOCATION" \
  --query properties.outputs --output json > .vm-lab/azure/foundry-project.json
PRINCIPAL=$(jq -er '.projectPrincipalId.value' .vm-lab/azure/foundry-project.json)
az deployment group create --subscription "$SUBSCRIPTION" --resource-group "$RG" \
  --name vm-lab-tool --template-file foundry/workflow.bicep \
  --parameters projectPrincipalId="$PRINCIPAL" vmName="$VM" location="$LOCATION" \
  --query properties.outputs --output json > .vm-lab/azure/foundry-workflow.json
bash foundry/register-agent.sh
```

## Test in the Foundry Playground

1. In [Microsoft Foundry](https://ai.azure.com/), open **VM Lab Sandbox >
   Build > Agents > vm-lab > Playground**.
2. With the VM running, send: **Run the Azure VM diagnostic and report what
   the guest returned.**
3. Open `identify_vm` in the tool trace. Expect `Linux`, the guest hostname,
   and empty stderr. The [live reference test](#what-this-demo-proved) used
   the Foundry Responses API. To repeat that test from the same terminal:

   ```bash
   ENDPOINT=$(jq -er '.projectEndpoint.value' .vm-lab/azure/foundry-project.json)
   VERSION=$(jq -er '.version // .versions.latest.version' .vm-lab/azure/agent.json)
   REQUEST=$(jq -cn --arg version "$VERSION" \
     '{input:"Run the Azure VM diagnostic and report what the guest returned.",
       agent_reference:{type:"agent_reference",name:"vm-lab",version:$version}}')
   az rest --subscription "$SUBSCRIPTION" --resource https://ai.azure.com \
     --method post --uri "$ENDPOINT/openai/v1/responses" --body "$REQUEST"
   ```

Deallocate the lab VM when you're done to stop compute charges. Disks can
still incur charges.

</details>

## What this demo proved

The standard Foundry prompt agent called its OpenAPI tool once and the
private VM returned `Linux` and `vm-agent-skill-lab`, with empty stderr.
