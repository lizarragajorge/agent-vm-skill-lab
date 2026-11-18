# Agent + VM skill lab

A minimal proof of remote command execution:

```text
Foundry prompt agent -> OpenAPI tool -> Logic Apps -> Azure Run Command -> private Ubuntu VM
Copilot custom agent -> azure-vm-diagnostic skill -> Azure Run Command -> same VM
```

Start with the [existing Foundry sandbox](#test-in-the-foundry-playground), or
set up another copy [through the portals](#set-up-through-the-portals) or
[from this repo](#deploy-from-this-repo). The Foundry agent does not load the
local Copilot skill; its equivalent is the `identify_vm` OpenAPI tool.

## Test in the Foundry Playground

1. Sign in to [Microsoft Foundry](https://ai.azure.com/) in the lab tenant and
   select **VM Lab Sandbox** (`vm-lab-sandbox`).
2. Go to **Build > Agents > vm-lab** and open its **Playground**. Use the latest
   version and make sure `vm-agent-skill-lab` is running in the Azure portal.
3. Send this prompt:

   > Run the Azure VM diagnostic now and report what the guest returned.

4. Expand the tool call in the run trace. Look for `identify_vm` (the API
   reports it as `vm-lab-identify_identify_vm`) and check the **tool output**,
   not just the agent's reply. The saved agent was verified through the Foundry
   Responses API with one successful tool call, empty stderr, and this stdout:

   ```text
   Linux
   vm-agent-skill-lab
   ```

The VM has no public IP or inbound SSH rule. The workflow endpoint requires
Microsoft Entra authentication from the Foundry project's managed identity;
SAS authentication is disabled. The workflow accepts no command or VM name
and uses its own identity to invoke Run Command on the lab VM only. Run Command
has elevated guest privileges, so keep the role scoped to the VM and don't
give the Foundry identity direct Run Command permission.

## Set up through the portals

This route uses the Azure portal to deploy infrastructure and the Foundry
portal to create the agent and its tool. Azure custom deployment accepts
compiled ARM JSON, not Bicep; the two build commands below only generate files
and do not deploy anything.

1. In the [Azure portal](https://portal.azure.com/), create a dedicated
   resource group, then create an **Ubuntu Server 24.04 LTS** VM named
   `vm-agent-skill-lab` in it. The lab used **Sweden Central**, **Standard_B2as_v2**
   and **No infrastructure redundancy required**. On **Networking**, use
   **Public IP: None** and **Public inbound ports: None**. Choose SSH public-key
   authentication at creation even though this test doesn't use SSH.
2. From the repo root, compile the templates:

   ```sh
   mkdir -p .vm-lab/azure
   az bicep build --file foundry/project.bicep --outfile .vm-lab/azure/project.arm.json
   az bicep build --file foundry/workflow.bicep --outfile .vm-lab/azure/workflow.arm.json
   ```

3. In Azure portal search, open **Deploy a custom template > Build your own
   template in the editor > Load file**. Load `project.arm.json`, select the
   lab resource group, then **Review + create > Create**. When deployment
   succeeds, copy `projectPrincipalId` from **Outputs**.

   ![Azure portal option to build a custom template in the editor](https://learn.microsoft.com/en-us/azure/azure-resource-manager/templates/media/deploy-portal/see-options.png)

   *Microsoft Learn example: [Deploy a custom template in the Azure portal](https://learn.microsoft.com/en-us/azure/azure-resource-manager/templates/deploy-portal).*

4. Repeat with `workflow.arm.json` in the same resource group, supplying the
   copied `projectPrincipalId`. The deployment creates the workflow identity,
   its custom role, and the VM-scoped assignment. Your deployment identity needs
   permission to create custom roles and role assignments.
5. In Azure portal, open **Logic apps > vm-lab-identify > Logic app designer**
   and copy the **HTTP URL** from the `identify` trigger. It should have only
   the `api-version` query parameter; if it includes `sig`, stop and check that
   the workflow deployment disabled SAS. For the next steps, split the URL into
   its HTTPS origin (omit `:443`), path, and `api-version` value.
6. In Foundry, open **VM Lab Sandbox** and go to **Tools > Custom > OpenAPI**.
   Name the tool `vm-lab-identify`. Choose **Managed identity > Create a new
   connection**, then enter:

   | Field | Value |
   | --- | --- |
   | Connection name | `vm-lab-identify` |
   | Authentication type | Managed identity (project identity) |
   | Target URL | The trigger's HTTPS origin, without the path or query |
   | Audience | `https://cognitiveservices.azure.com` |

   ![Microsoft Foundry OpenAPI connection form with managed identity selected](https://learn.microsoft.com/en-us/azure/foundry/agents/media/tools/openapi/managed-identity-connection.png)

   *Microsoft Learn example: [Configure managed identity authentication](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/tools/openapi#configure-managed-identity-authentication). Use the lab values above rather than the sample API values.*

7. Select that connection, paste this OpenAPI schema after replacing
   `https://WORKFLOW-HOST`, `/WORKFLOW-PATH`, and both `CALLBACK-API-VERSION`
   placeholders, then create the tool. Keep the leading `/` on the path.

   ```json
   {
     "openapi": "3.0.3",
     "info": {"title": "VM Lab Identify", "version": "1.0.0"},
     "servers": [{"url": "https://WORKFLOW-HOST"}],
     "paths": {
       "/WORKFLOW-PATH": {
         "post": {
           "operationId": "identify_vm",
           "description": "Identify the private lab VM.",
           "parameters": [
             {"name": "api-version", "in": "query", "required": true,
              "schema": {"type": "string", "enum": ["CALLBACK-API-VERSION"],
                         "default": "CALLBACK-API-VERSION"}}
           ],
           "requestBody": {"required": true, "content": {
             "application/json": {"schema": {"type": "object", "additionalProperties": false}}
           }},
           "responses": {
             "200": {"description": "Azure VM Run Command result", "content": {
               "application/json": {"schema": {"type": "object"}}
             }},
             "502": {"description": "The VM diagnostic did not complete."}
           }
         }
       }
     }
   }
   ```

8. Under **Build > Agents**, create a prompt agent called `vm-lab`, select
   `gpt-4o-mini`, add the `vm-lab-identify` tool, and save. Use these instructions:

   > When asked to identify the lab VM, call `identify_vm` exactly once with the
   > documented API version and an empty JSON object. Report the guest stdout
   > and stderr from the tool. Report failures as failures; never guess.

   Then [test in the Playground](#test-in-the-foundry-playground).

## Deploy from this repo

Run from the repo root with Azure CLI (including Bicep), Bash, `jq`, `curl`,
and `ssh-keygen` if creating a VM. Sign in to the intended tenant. You need
permission to create the resources, define and assign the VM role, and create
agents and connections in the Foundry project. The VM SKU and model deployment
also need capacity in your subscription. The commands below use Bash; replace
the subscription placeholder before running them.

Set these variables first. If you already have the lab VM, use its existing
resource group and region:

```bash
set -euo pipefail
umask 077
SUBSCRIPTION='YOUR_LAB_SUBSCRIPTION'
RG='rg-agent-vm-skill-lab-se'
LOCATION='swedencentral'
VM='vm-agent-skill-lab'
mkdir -p .vm-lab/azure
```

Only run this next block if you need to create the VM. Use a dedicated lab
resource group:

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

In the same shell, deploy the [Foundry project and model](foundry/project.bicep),
then the [workflow and role](foundry/workflow.bicep). The
[registration script](foundry/register-agent.sh) creates the managed identity
connection and registers the prompt agent (or creates a new version):

```bash
mkdir -p .vm-lab/azure
az deployment group create --subscription "$SUBSCRIPTION" --resource-group "$RG" \
  --name vm-lab-foundry --template-file foundry/project.bicep \
  --parameters location="$LOCATION" \
  --query properties.outputs --output json > .vm-lab/azure/foundry-project.json
PRINCIPAL=$(jq -er '.projectPrincipalId.value' .vm-lab/azure/foundry-project.json)
az deployment group create --subscription "$SUBSCRIPTION" --resource-group "$RG" \
  --name vm-lab-tool --template-file foundry/workflow.bicep \
  --parameters projectPrincipalId="$PRINCIPAL" location="$LOCATION" \
  --query properties.outputs --output json > .vm-lab/azure/foundry-workflow.json
bash foundry/register-agent.sh
```

Test in the [Foundry Playground](#test-in-the-foundry-playground) or call the
saved agent from the same shell:

```bash
ENDPOINT=$(jq -er '.projectEndpoint.value' .vm-lab/azure/foundry-project.json)
VERSION=$(jq -er '.version // .versions.latest.version' .vm-lab/azure/agent.json)
REQUEST=$(jq -cn --arg version "$VERSION" \
  '{input:"Run the Azure VM diagnostic now and report what the guest returned.",
    agent_reference:{type:"agent_reference",name:"vm-lab",version:$version}}')
az rest --subscription "$SUBSCRIPTION" --resource https://ai.azure.com \
  --method post --uri "$ENDPOINT/openai/v1/responses" \
  --body "$REQUEST" --output json
```

Check for `openapi_call_output` containing the guest output. If the tool fails
and there is no corresponding Logic Apps run, check the project connection,
audience, and trigger URL. If there is a run, inspect its `Identify_VM` action
and check that the VM is running and the workflow identity has the custom role.

When finished, select **Stop** in the VM's Azure portal overview and confirm
**Stopped (deallocated)** to stop compute charges. Disks can still incur charges.

## Run the repo's Copilot skill

The local [VM Lab agent](.github/agents/vm-lab.agent.md) and
[Azure diagnostic skill](.github/skills/azure-vm-diagnostic/SKILL.md) use your
signed-in Azure CLI identity directly, without Foundry or Logic Apps. The local
skill is pinned to the original lab resource group `rg-agent-vm-skill-lab-se`.
From the repo root, set `SUBSCRIPTION` to the subscription containing that lab VM:

```bash
mkdir -p .vm-lab/azure
az vm show --subscription "$SUBSCRIPTION" \
  --resource-group rg-agent-vm-skill-lab-se --name vm-agent-skill-lab \
  --query id --output tsv > .vm-lab/azure/resource-id
```

In Copilot, select **VM Lab** and send the same diagnostic prompt. Your identity
needs permission to invoke Run Command on the VM.

## Optional SSH test without a VM

From this directory, using Python 3.9+:

```sh
python3 .github/skills/vm-command/scripts/run.py --host vm.example.com --user vmuser --dry-run
python3 -m unittest discover -s tests -v
```

Select **VM Lab** in a compatible Copilot agent picker and ask:

> Use the vm-command skill to dry-run the diagnostic for vmuser@vm.example.com.

If the agent or skill does not appear in Copilot, reload the client.

## Optional live SSH test

Requires OpenSSH, a reachable POSIX VM, existing SSH key/agent authentication, and
an independently verified host key already in known_hosts. The runner does not
provision VMs. Keep SSH credentials out of tracked project files.

Replace the placeholders with your VM details:

```sh
python3 .github/skills/vm-command/scripts/run.py --host YOUR_VM_HOST --user YOUR_VM_USER
```

Or explicitly ask the agent to execute the diagnostic on that host and username.
The only remote command is `uname -s && hostname`; arbitrary remote commands are
intentionally not exposed. SSH configuration may affect routing and authentication.

To test SSH against the Azure lab VM, first establish an approved private
route, such as a VPN or Bastion Standard tunnel, and verify the host key.
