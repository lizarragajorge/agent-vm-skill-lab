param projectPrincipalId string
param vmName string = 'vm-agent-skill-lab'
param location string = resourceGroup().location

var audience = environment().resourceManager
var oauthClaims = [
  {
    name: 'aud'
    value: 'https://cognitiveservices.azure.com'
  }
  {
    name: 'oid'
    value: projectPrincipalId
  }
]

resource vm 'Microsoft.Compute/virtualMachines@2025-04-01' existing = {
  name: vmName
}

resource workflow 'Microsoft.Logic/workflows@2019-05-01' = {
  name: 'vm-lab-identify'
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    state: 'Enabled'
    accessControl: {
      triggers: {
        sasAuthenticationPolicy: {
          state: 'Disabled'
        }
        openAuthenticationPolicies: {
          policies: {
            FoundryProject: {
              type: 'AAD'
              claims: concat(oauthClaims, [
                {
                  name: 'iss'
                  value: 'https://sts.windows.net/${subscription().tenantId}/'
                }
              ])
            }
          }
        }
      }
    }
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      triggers: {
        identify: {
          type: 'Request'
          kind: 'Http'
          description: 'Identify the private lab VM. No command or VM name is accepted.'
          inputs: {
            method: 'POST'
            schema: {
              type: 'object'
              additionalProperties: false
            }
          }
        }
      }
      actions: {
        Identify_VM: {
          type: 'Http'
          inputs: {
            method: 'POST'
            uri: '${audience}${substring(vm.id, 1)}/runCommand?api-version=2025-04-01'
            authentication: {
              type: 'ManagedServiceIdentity'
              audience: audience
            }
            body: {
              commandId: 'RunShellScript'
              script: [
                'uname -s && hostname'
              ]
            }
            retryPolicy: {
              type: 'none'
            }
          }
          runAfter: {}
        }
        Respond: {
          type: 'Response'
          kind: 'Http'
          inputs: {
            statusCode: 200
            body: '@body(\'Identify_VM\')'
          }
          runAfter: {
            Identify_VM: [
              'Succeeded'
            ]
          }
        }
        Respond_Error: {
          type: 'Response'
          kind: 'Http'
          inputs: {
            statusCode: 502
            body: {
              error: 'Azure did not complete the VM diagnostic. Check the workflow run history.'
            }
          }
          runAfter: {
            Identify_VM: [
              'Failed'
              'TimedOut'
            ]
          }
        }
      }
      outputs: {}
    }
  }
}

resource role 'Microsoft.Authorization/roleDefinitions@2022-04-01' = {
  name: guid(resourceGroup().id, 'vm-lab-run-command')
  properties: {
    roleName: 'VM Lab Identify Run Command'
    description: 'Invoke Run Command on the assigned VM.'
    type: 'CustomRole'
    assignableScopes: [
      resourceGroup().id
    ]
    permissions: [
      {
        actions: [
          'Microsoft.Compute/virtualMachines/runCommand/action'
        ]
      }
    ]
  }
}

resource grant 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(vm.id, workflow.id, role.id)
  scope: vm
  properties: {
    roleDefinitionId: role.id
    principalId: workflow.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

output workflowId string = workflow.id
