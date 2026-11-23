# Test a Foundry agent on an existing Azure VM

## Start here

Use your existing Azure Linux VM and Foundry environment in the same
Microsoft Entra tenant. If they're freshly created, do these steps in order:

1. **Check the VM.** In the Azure portal, open the running VM and choose
   **Operations > Run command > RunShellScript**. Run `uname -s && hostname`
   and note the hostname. If it doesn't return `Linux` and the hostname,
   resolve that first. This checks your Azure-to-VM access, not Foundry.
2. **Open a Foundry project.** In [New Foundry](https://ai.azure.com/nextgen),
   choose your existing project from the project picker. If you have only
   a Foundry account and no usable project, select **Create a new project**
   or ask your admin for one. See the [Foundry setup quickstart](https://learn.microsoft.com/en-us/azure/foundry/tutorials/quickstart-create-foundry-resources).
3. **Check the model.** Reuse an existing model deployment that
   [supports OpenAPI tools](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/limits-quotas-regions#tool-support-by-region-and-model).
   If there isn't one, go to **Build > Catalog > Model Catalog**, pick a
   supported model available to your project, and select **Deploy >
   Default settings**. Note the deployment name. If deployment is blocked
   by permissions or quota, ask your Foundry admin.
4. **Get the VM tool.** If `vm-lab-identify` is already available in the
   project, confirm it points to the Logic App configured for your VM.
   Otherwise, check the permissions under [one-time tool setup](#one-time-tool-setup)
   and use the [recommended Bicep path](#option-a-deploy-with-bicep-recommended),
   or give that section to the administrator setting up the tool.
5. **[Test in Playground](#create-the-agent-and-test-in-playground).**
   Create a standard Foundry agent, select your deployment, and attach
   the tool. No preview feature is required.

## Create the agent and test in Playground

Use a **standard Foundry prompt agent** with the OpenAPI tool. The
[reference lab](README.md#what-this-demo-proved) verified this setup
through the Foundry API. No preview features are required.

1. In [New Foundry](https://ai.azure.com/nextgen), open your project and
   select **Create an agent**. Name it `vm-diagnostic-agent`, choose
   **Text**, and select your deployed model in Playground.
2. In the agent's **Tools > Add > Add tools**, add `vm-lab-identify`.
3. Paste this into the agent's **Instructions**:

   ```text
   When asked to identify the VM, call identify_vm once with its documented
   API version and an empty JSON object. Report the guest stdout and stderr
   from the tool. If the call fails, say so. Never invent guest output.
   ```

4. Select **Save and start new chat**. Once the saved version is active,
   send: **Identify the configured VM. Report what the guest returned.**
5. Expand `identify_vm` in the tool trace. Pass means the call succeeded
   and the guest stdout contains `Linux` and the expected hostname, with
   empty stderr. A successful HTTP status or a plausible chat reply alone
   is not proof.

### Troubleshoot by where the call stopped

| What you see | What to check |
| --- | --- |
| No tool call in Playground | Confirm the saved agent version is active in the new chat and `vm-lab-identify` is attached. |
| Tool call, but no Logic App run | Check the callback host, path, and API version, then the Foundry project identity connection and Logic App authorization policy. |
| Logic App ran, but `Identify_VM` failed | Open **Runs history** and inspect the action error. Check that the VM is running and the Logic App identity has Run Command permission on that VM. |
| Tool succeeded, but the hostname is wrong | Check the VM resource ID in `Identify_VM` and confirm the expected guest hostname with Azure Run Command. |

A [native Foundry skill (preview)](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/tools/skills)
can package these instructions for reuse, but it does not run the command
or grant VM access. You don't need it for this test.

## One-time tool setup

The custom OpenAPI tool calls a Logic App as the Foundry **project** identity.
The Logic App uses its **own** identity to invoke Azure VM Run Command. The
workflow fixes both the target VM and the script; the caller supplies neither.

**Check permissions before starting.** **Foundry User** lets you create
and test the agent. **Foundry Project Manager** (or equivalent) is needed
to create the project's OpenAPI connection. In Azure, the deployer needs
permission to create the Logic App, define a custom role in the VM's
resource group, and assign it on the target VM. If you only have Foundry
access, ask your admins to complete this section; you can then use the tool.

Get the [Foundry project principal ID](#foundry-project-principal-id), choose
one backend setup option, then [create the OpenAPI tool](#create-the-openapi-tool-in-foundry-both-options).

### Option A: Deploy with Bicep (recommended)

Download or clone this lab and open Bash in its folder. You need Azure CLI
with Bicep and `jq`; sign in with `az login` if needed. If a Logic App named
`vm-lab-identify` already exists in the VM's resource group, confirm you
intend to update it before continuing. Replace the four placeholders and run:

```bash
WORKFLOW_ID=$(az deployment group create \
  --subscription "<VM subscription>" \
  --resource-group "<VM resource group>" \
  --template-file foundry/workflow.bicep \
  --parameters vmName="<VM resource name>" projectPrincipalId="<Foundry project principal ID>" \
  --query properties.outputs.workflowId.value --output tsv) &&
bash foundry/generate-openapi.sh "$WORKFLOW_ID" > vm-lab-openapi.json
```

This deploys the authenticated Logic App, assigns its Run Command role on
the target VM, and generates `vm-lab-openapi.json`. The generator retrieves
the trigger URL using Azure CLI and stops if SAS is still enabled. On
success, go straight to [Create the OpenAPI tool](#create-the-openapi-tool-in-foundry-both-options)
with that file; no callback URL editing is needed.

### Option B: Build the Logic App manually

No Bicep or repo download is needed. Use the Azure portal for workflow
design and IAM, plus an Azure REST update to disable SAS. Don't grant the
workflow access to the VM until the trigger is locked down.

1. In Azure portal, create a **Consumption** Logic App. Under **Identity**,
   enable its **System assigned** identity. Leave its VM role unassigned
   until step 6.
2. In **Logic app designer**, add **When an HTTP request is received**, set
   the method to `POST`, and set the request schema to
   `{"type":"object","additionalProperties":false}`.
3. Add a built-in **HTTP** action named `Identify_VM`. Set the method to
   `POST` and the URI to
   `https://management.azure.com<VM_RESOURCE_ID>/runCommand?api-version=2025-04-01`,
   replacing `<VM_RESOURCE_ID>` with the [VM's full Azure resource ID](#vm-resource-id).
   Set **Authentication** to **Managed identity**,
   select the system-assigned identity, and use `https://management.azure.com/`
   as the audience. Set `Content-Type` to `application/json` and the retry
   policy to **None**. Keep the default asynchronous handling enabled so
   the action can follow the initial `202 Accepted` response. Set the body to:

   ```json
   {"commandId":"RunShellScript","script":["uname -s && hostname"]}
   ```

4. Add a **Response** action after the HTTP action succeeds. Set the status
   to `200` and the body to the `Identify_VM` action's **Body** output. Add a
   separate Response with status `502` and a short error message, and set it
   to run after `Identify_VM` fails or times out. Save the workflow. Do not
   populate the command or VM ID from the trigger body.
5. [Require the Foundry project identity and disable SAS](#logic-app-trigger-authentication).
   Verify that an unauthenticated POST is rejected before granting VM access.
6. [Grant the Logic App Run Command access](#vm-scoped-run-command-role)
   on the target VM only.

### Create the OpenAPI tool in Foundry (both options)

1. **Bicep:** Open `vm-lab-openapi.json`. The `servers[0].url` value is your
   **Target URL**, and the whole file is the schema to paste.
   **Manual setup:** Use the instructions below to prepare those values.

   <details>
   <summary>Manual setup only: build the OpenAPI schema from the callback</summary>

   Open your Logic App in **Logic app designer** and copy the HTTP request
   trigger URL. If it includes `sig`, stop and verify SAS is disabled.
   For example, split this sample callback:

   ```text
   https://logic-app.example:443/workflows/abc123/triggers/manual/paths/invoke?api-version=2016-10-01
   ```

   | Field | Value from the example |
   | --- | --- |
   | Connection **Target URL** and OpenAPI `servers` URL | `https://logic-app.example` (omit `:443`) |
   | OpenAPI path | `/workflows/abc123/triggers/manual/paths/invoke` |
   | Callback `api-version` (both schema placeholders) | `2016-10-01` |

   Replace the host, path, and both API version placeholders in the
   schema below. Use the actual callback path, including its trigger name.
   The callback `api-version` is not the Compute API version in `Identify_VM`.

   ```json
   {
     "openapi": "3.0.3",
     "info": {"title": "VM Lab Identify", "version": "1.0.0"},
     "servers": [{"url": "https://WORKFLOW-HOST"}],
     "paths": {
       "/WORKFLOW-PATH": {
         "post": {
           "operationId": "identify_vm",
           "description": "Identify the configured Linux VM.",
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

   </details>

2. In Foundry, open **Tools > Custom > OpenAPI**. Name the tool
   `vm-lab-identify`. Create a **Managed identity** connection with your
   **Target URL** and `https://cognitiveservices.azure.com` as the **Audience**.
   Select the connection, paste the complete schema, and select **Create tool**.

[Foundry managed identity form screenshot](https://learn.microsoft.com/en-us/azure/foundry/agents/media/tools/openapi/managed-identity-connection.png)

Once the tool is created, return to [Create the agent and test in
Playground](#create-the-agent-and-test-in-playground).

## Appendix: One-time setup details

### Foundry project principal ID

**What it is:** The Microsoft Entra object ID (a GUID) of the Foundry
**project's system-assigned managed identity**. Azure creates it when you
enable that identity. It's not a secret, the Foundry account's principal
ID, an agent identity, or the project's Azure resource ID.

**Where to find it:** In the Azure portal, open the Foundry **project**
resource, not its parent account. Under **Identity > System assigned**,
copy **Object (principal) ID**. If the project doesn't show an Identity
page, use Azure CLI or Bash in Azure Cloud Shell. Use the Foundry project's
subscription and resource group, which can differ from the VM's:

```bash
az cognitiveservices account project show \
  --subscription "<Foundry subscription>" \
  --resource-group "<Foundry resource group>" \
  --name "<Foundry account resource name>" \
  --project-name "<Foundry project resource name>" \
  --query '{resourceId:id,identity:identity}' --output json
```

Look for `identity.principalId` and `identity.tenantId` in the output.
The `resourceId` ends in `/accounts/<account>/projects/<project>`.

**How to enable it:** If **System assigned** is off, set **Status** to
**On** and save on the project's Identity page. If the page isn't
available, an admin with write access to the project can use the
[Projects Update API](https://learn.microsoft.com/en-us/rest/api/microsoftfoundry/accountmanagement/projects/update?view=rest-microsoftfoundry-accountmanagement-2025-06-01).
For a project with **no managed identity**, run the following using the
`resourceId` from the lookup above:

```bash
PROJECT_ID="<Foundry project resource ID>"
az rest --method patch \
  --uri "https://management.azure.com${PROJECT_ID}?api-version=2025-06-01" \
  --body '{"identity":{"type":"SystemAssigned"}}'
```

If the project already has a user-assigned identity, ask the project admin
to preserve it when enabling the system-assigned identity. After the
update finishes, rerun the lookup and confirm `identity.principalId` is
populated. No new Foundry project is needed.

**Where to use it:** In Option A, pass the GUID as `projectPrincipalId`.
In Option B, use it for the Logic App's `oid` claim. You don't paste the
GUID into the OpenAPI tool: its **Managed identity** connection uses the
project identity automatically. The Logic App's separate identity is the
one that gets the VM role.

### VM resource ID

In the Azure portal, open the VM and select **Overview > JSON View**.
Copy **Resource ID**, which looks like
`/subscriptions/<subscription>/resourceGroups/<group>/providers/Microsoft.Compute/virtualMachines/<vm>`.
Paste the entire path in place of `<VM_RESOURCE_ID>` in `Identify_VM`.
Don't use the guest hostname or paste an Azure portal URL. For Bicep,
use the VM's subscription, resource group, and resource name separately.

### Logic App trigger authentication

In the Consumption Logic App's **Authorization** settings, add a
Microsoft Entra authorization policy with all three claims:

| Claim | Value |
| --- | --- |
| `iss` (issuer) | `https://sts.windows.net/<tenant-id>/`, using `identity.tenantId` from the [project lookup](#foundry-project-principal-id). Keep the trailing slash. |
| `aud` (audience) | `https://cognitiveservices.azure.com`, exactly as set in the Foundry connection. This is separate from the outbound Azure Resource Manager audience. |
| `oid` (object ID) | `identity.principalId` from the project lookup. |

The Entra policy doesn't turn off shared access signature (SAS)
authentication. Follow Microsoft's [Consumption workflow instructions](https://learn.microsoft.com/en-us/azure/logic-apps/set-up-security-permissions#add-the-sasauthenticationpolicy-property-to-your-workflow-definition)
to update the workflow resource so
`properties.accessControl.triggers.sasAuthenticationPolicy.state` is
`Disabled`. Keep the existing workflow definition and Entra policy.
Reopen the trigger and copy its current URL. Confirm there's no `sig`
parameter and a POST with no `Authorization` header is rejected before
assigning the VM role.

### VM-scoped Run Command role

The **Logic App's** system-assigned identity (not Foundry's) needs the
Azure permission `Microsoft.Compute/virtualMachines/runCommand/action`.
Under the Logic App's **Identity > System assigned**, confirm the
identity is on and note its **Object (principal) ID**.

1. If your admin hasn't provided a suitable role, use the VM's
   **resource group > Access control (IAM) > Add > Add custom role**.
   [Create a custom role](https://learn.microsoft.com/en-us/azure/role-based-access-control/custom-roles-portal)
   with the action above. Use the VM's resource group as an **assignable
   scope** so the role is available on its VMs; this does not grant access
   to anything.
2. On the **VM itself**, open **Access control (IAM) > Add > Add role
   assignment**. Select the custom role, choose **Managed identity** as
   the member type, and select the Logic App's system-assigned identity.
   Confirm it matches the Logic App before saving. The **assignment**
   belongs on the VM, not the resource group.
