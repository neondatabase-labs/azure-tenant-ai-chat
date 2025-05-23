param name string

param openai_api_version string
param userPrincipalName string
param neonPostgresName string
param openAiLocation string
param openAiSkuName string 
param chatGptDeploymentCapacity int 
param chatGptDeploymentName string
param chatGptModelName string 
param chatGptModelVersion string
param embeddingDeploymentName string 
param embeddingDeploymentCapacity int
param embeddingModelName string 

param dalleLocation string
param dalleDeploymentCapacity int
param dalleDeploymentName string
param dalleModelName string
param dalleApiVersion string

param speechServiceSkuName string = 'S0'

param formRecognizerSkuName string = 'S0'

param storageServiceSku object
param storageServiceImageContainerName string

param location string = resourceGroup().location

@secure()
param nextAuthHash string = uniqueString(newGuid())

param tags object = {}

var openai_name = toLower('${name}-aillm')
var openai_dalle_name = toLower('${name}-aidalle')

var form_recognizer_name = toLower('${name}-form')
var speech_service_name = toLower('${name}-speech')
var webapp_name = toLower('${name}-webapp')
var appservice_name = toLower('${name}-app')
// storage name must be < 24 chars, alphanumeric only. 'sto' is 3 and resourceToken is 13
var clean_name = replace(replace(name, '-', ''), '_', '')
var storage_prefix = take(clean_name, 8)
var storage_name = toLower('${storage_prefix}storage')
// keyvault name must be less than 24 chars - token is 13
var kv_prefix = take(name, 7)
var keyVaultName = toLower('${kv_prefix}-kv')
var la_workspace_name = toLower('${name}-la')
var diagnostic_setting_name = 'AppServiceConsoleLogs'

var keyVaultSecretsOfficerRole = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7')

var validStorageServiceImageContainerName = toLower(replace(storageServiceImageContainerName, '-', ''))

var llmDeployments = [
  {
    name: chatGptDeploymentName
    model: {
      format: 'OpenAI'
      name: chatGptModelName
      version: chatGptModelVersion
    }
    sku: {
      name: 'GlobalStandard'
      capacity: chatGptDeploymentCapacity
    }
  }
  {
    name: embeddingDeploymentName
    model: {
      format: 'OpenAI'
      name: embeddingModelName
      version: '2'
    }
    capacity: embeddingDeploymentCapacity
  }
]

resource appServicePlan 'Microsoft.Web/serverfarms@2020-06-01' = {
  name: appservice_name
  location: location
  tags: tags
  properties: {
    reserved: true
  }
  sku: {
    name: 'P0v3'
    tier: 'Premium0V3'
    size: 'P0v3'
    family: 'Pv3'
    capacity: 1
  }
  kind: 'linux'
}

resource webApp 'Microsoft.Web/sites@2020-06-01' = {
  name: webapp_name
  location: location
  tags: union(tags, { 'azd-service-name': 'frontend' })
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'node|18-lts'
      alwaysOn: true
      appCommandLine: 'next start'
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      appSettings: [ 
        { 
          name: 'AZURE_KEY_VAULT_NAME'
          value: keyVaultName
        }
        { 
          name: 'SCM_DO_BUILD_DURING_DEPLOYMENT'
          value: 'true'
        }
        {
          name: 'AZURE_OPENAI_API_KEY'
          value: '@Microsoft.KeyVault(VaultName=${kv.name};SecretName=${kv::AZURE_OPENAI_API_KEY.name})'
        }
        {
          name: 'AZURE_OPENAI_API_INSTANCE_NAME'
          value: openai_name
        }
        {
          name: 'AZURE_OPENAI_API_DEPLOYMENT_NAME'
          value: chatGptDeploymentName
        }
        {
          name: 'AZURE_OPENAI_API_EMBEDDINGS_DEPLOYMENT_NAME'
          value: embeddingDeploymentName
        }
        {
          name: 'AZURE_OPENAI_API_VERSION'
          value: openai_api_version
        }
        {
          name: 'AZURE_OPENAI_DALLE_API_KEY'
          value: '@Microsoft.KeyVault(VaultName=${kv.name};SecretName=${kv::AZURE_OPENAI_DALLE_API_KEY.name})'
        }
        {
          name: 'AZURE_OPENAI_DALLE_API_INSTANCE_NAME'
          value: openai_dalle_name
        }
        {
          name: 'AZURE_OPENAI_DALLE_API_DEPLOYMENT_NAME'
          value: dalleDeploymentName
        }
        {
          name: 'AZURE_OPENAI_DALLE_API_VERSION'
          value: dalleApiVersion
        }
        {
          name: 'NEXTAUTH_SECRET'
          value: '@Microsoft.KeyVault(VaultName=${kv.name};SecretName=${kv::NEXTAUTH_SECRET.name})'
        }
        {
          name: 'NEXTAUTH_URL'
          value: 'https://${webapp_name}.azurewebsites.net'
        }
        { 
          name: 'AZURE_DOCUMENT_INTELLIGENCE_ENDPOINT'
          value: 'https://${form_recognizer_name}.cognitiveservices.azure.com/'
        }        
        {
          name: 'AZURE_DOCUMENT_INTELLIGENCE_KEY'
          value: '@Microsoft.KeyVault(VaultName=${kv.name};SecretName=${kv::AZURE_DOCUMENT_INTELLIGENCE_KEY.name})'
        }
        {
          name: 'AZURE_SPEECH_REGION'
          value: location
        }
        {
          name: 'AZURE_SPEECH_KEY'
          value: '@Microsoft.KeyVault(VaultName=${kv.name};SecretName=${kv::AZURE_SPEECH_KEY.name})'
        }
        {
          name: 'AZURE_STORAGE_ACCOUNT_NAME'
          value: storage_name
        }
        {
          name: 'AZURE_STORAGE_ACCOUNT_KEY'
          value: '@Microsoft.KeyVault(VaultName=${kv.name};SecretName=${kv::AZURE_STORAGE_ACCOUNT_KEY.name})'
        }
      ]
    }
  }
  identity: { type: 'SystemAssigned'}

  resource configLogs 'config' = {
    name: 'logs'
    properties: {
      applicationLogs: { fileSystem: { level: 'Verbose' } }
      detailedErrorMessages: { enabled: true }
      failedRequestsTracing: { enabled: true }
      httpLogs: { fileSystem: { enabled: true, retentionInDays: 1, retentionInMb: 35 } }
    }
  }
}

resource symbolicname 'Neon.Postgres/organizations@2024-08-01-preview' = {
  location: location
  name: neonPostgresName
  tags: tags
  properties: {
    companyDetails: {
    }
    marketplaceDetails: {
      offerDetails: {
        offerId: 'neon_serverless_postgres_azure_prod'
        planId: 'neon_serverless_postgres_azure_prod_free'
        planName: 'Free Plan'
        publisherId: 'neon1722366567200'
        termId: 'gmz7xq9ge3py'
        termUnit: 'P1M'
      }
      subscriptionId: subscription().id
    }
    partnerOrganizationProperties: {
      organizationName: 'string'
    }
    userDetails: {
      upn: userPrincipalName
    }
  }
}

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2021-12-01-preview' = {
  name: la_workspace_name
  location: location
}

resource webDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: diagnostic_setting_name
  scope: webApp
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'AppServiceConsoleLogs'
        enabled: true
      }
    ]
    metrics: []
  }
}

resource kvFunctionAppPermissions 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  name: guid(kv.id, webApp.name, keyVaultSecretsOfficerRole)
  scope: kv
  properties: {
    principalId: webApp.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: keyVaultSecretsOfficerRole
  }
}

resource kv 'Microsoft.KeyVault/vaults@2021-06-01-preview' = {
  name: keyVaultName
  location: location
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    enableRbacAuthorization: true
    enabledForDeployment: false
    enabledForDiskEncryption: true
    enabledForTemplateDeployment: false
  }

  resource AZURE_OPENAI_API_KEY 'secrets' = {
    name: 'AZURE-OPENAI-API-KEY'
    properties: {
      contentType: 'text/plain'
      value: azureopenai.listKeys().key1
    }
  }

  resource AZURE_OPENAI_DALLE_API_KEY 'secrets' = {
    name: 'AZURE-OPENAI-DALLE-API-KEY'
    properties: {
      contentType: 'text/plain'
      value: azureopenaidalle.listKeys().key1
    }
  }

  resource NEXTAUTH_SECRET 'secrets' = {
    name: 'NEXTAUTH-SECRET'
    properties: {
      contentType: 'text/plain'
      value: nextAuthHash
    }
  }

  resource AZURE_DOCUMENT_INTELLIGENCE_KEY 'secrets' = {
    name: 'AZURE-DOCUMENT-INTELLIGENCE-KEY'
    properties: {
      contentType: 'text/plain'
      value: formRecognizer.listKeys().key1
    }
  }

  resource AZURE_SPEECH_KEY 'secrets' = {
    name: 'AZURE-SPEECH-KEY'
    properties: {
      contentType: 'text/plain'
      value: speechService.listKeys().key1
    }
  }

  resource AZURE_STORAGE_ACCOUNT_KEY 'secrets' = {
    name: 'AZURE-STORAGE-ACCOUNT-KEY'
    properties: {
      contentType: 'text/plain'
      value: storage.listKeys().keys[0].value
    }
  }
}

resource formRecognizer 'Microsoft.CognitiveServices/accounts@2023-05-01' = {
  name: form_recognizer_name
  location: location
  tags: tags
  kind: 'FormRecognizer'
  properties: {
    customSubDomainName: form_recognizer_name
    publicNetworkAccess: 'Enabled'
  }
  sku: {
    name: formRecognizerSkuName
  }
}

resource azureopenai 'Microsoft.CognitiveServices/accounts@2023-05-01' = {
  name: openai_name
  location: openAiLocation
  tags: tags
  kind: 'OpenAI'
  properties: {
    customSubDomainName: openai_name
    publicNetworkAccess: 'Enabled'
  }
  sku: {
    name: openAiSkuName
  }
}

@batchSize(1)
resource llmdeployment 'Microsoft.CognitiveServices/accounts/deployments@2023-05-01' = [for deployment in llmDeployments: {
  parent: azureopenai
  name: deployment.name
  properties: {
    model: deployment.model
  }
  sku: contains(deployment, 'sku') ? deployment.sku : {
    name: 'Standard'
    capacity: deployment.capacity
  }
}]

resource azureopenaidalle 'Microsoft.CognitiveServices/accounts@2023-05-01' = {
  name: openai_dalle_name
  location: dalleLocation
  tags: tags
  kind: 'OpenAI'
  properties: {
    customSubDomainName: openai_dalle_name
    publicNetworkAccess: 'Enabled'
  }
  sku: {
    name: openAiSkuName
  }

  resource dalleDeployment 'deployments' = {
    name: dalleDeploymentName
    properties: {
      model: {
        format: 'OpenAI'
        name: dalleModelName
      }
    }
    sku: {
      name: 'Standard'
      capacity: dalleDeploymentCapacity
    }
  }
}



resource speechService 'Microsoft.CognitiveServices/accounts@2023-05-01' = {
  name: speech_service_name
  location: location
  tags: tags
  kind: 'SpeechServices'
  properties: {
    customSubDomainName: speech_service_name
    publicNetworkAccess: 'Enabled'
  }
  sku: {
    name: speechServiceSkuName
  }
}

// TODO: define good default Sku and settings for storage account
resource storage 'Microsoft.Storage/storageAccounts@2022-05-01' = {
  name: storage_name
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: storageServiceSku

  resource blobServices 'blobServices' = {
    name: 'default'
    resource container 'containers' = {
      name: validStorageServiceImageContainerName
      properties: {
        publicAccess: 'None'
      }
    }
  }
}

output url string = 'https://${webApp.properties.defaultHostName}'
