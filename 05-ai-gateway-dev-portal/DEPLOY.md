# Deploy this portal to Azure Static Web App

Reproducible steps to host the AI Gateway Dev Portal against your APIM AI gateway
— the exact flow used for this repo's deployment. Run from this folder
(`05-ai-gateway-dev-portal/`).

## Prerequisites

- [Node.js](https://nodejs.org/) 20+ and npm
- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) (`az login`)
- A deployed APIM instance (this repo's `00-infra` + `02-apim`) in your subscription
- Rights to create an Entra app registration and a Static Web App

Set a few variables:

```bash
RG=rg-apim-rag-poc      # your resource group
SWA=stapp-apimragpoc    # Static Web App name
LOCATION=westeurope     # SWA region: westus2 | centralus | eastus2 | westeurope | eastasia
```

## 1. Entra app registration (MSAL sign-in)

The portal signs in with Microsoft Entra ID and calls Azure Resource Manager on
your behalf, so it needs an app registration (a Single-Page Application).

```bash
# Single-tenant — use this if your tenant policy blocks multi-tenant apps.
CLIENT_ID=$(az ad app create \
  --display-name "AI Gateway Dev Portal" \
  --sign-in-audience AzureADMyOrg \
  --query appId -o tsv)

OBJECT_ID=$(az ad app show --id "$CLIENT_ID" --query id -o tsv)
echo "client id: $CLIENT_ID"

# SPA redirect URI for local dev (the deployed URL is added in step 4).
az rest --method PATCH \
  --uri "https://graph.microsoft.com/v1.0/applications/$OBJECT_ID" \
  --headers "Content-Type=application/json" \
  --body '{"spa":{"redirectUris":["http://localhost:5173"]}}'

# Delegated permission to Azure Service Management (user_impersonation).
az ad app permission add --id "$CLIENT_ID" \
  --api 797f4846-ba00-4fd7-ba43-dac1f8f63013 \
  --api-permissions 41094075-9dad-400e-a0bd-54e686782033=Scope
```

> The client ID is a public SPA identifier, not a secret. Users consent to the
> ARM permission at first sign-in (or an admin can pre-consent).

## 2. Build

Vite inlines `VITE_AZURE_CLIENT_ID` at build time:

```bash
npm install
VITE_AZURE_CLIENT_ID=$CLIENT_ID npm run build   # -> dist/
```

## 3. Create + deploy the Static Web App

```bash
az staticwebapp create -n "$SWA" -g "$RG" -l "$LOCATION" --sku Free

TOKEN=$(az staticwebapp secrets list -n "$SWA" -g "$RG" --query properties.apiKey -o tsv)
npx -y @azure/static-web-apps-cli deploy ./dist --deployment-token "$TOKEN" --env production

HOST=$(az staticwebapp show -n "$SWA" -g "$RG" --query defaultHostname -o tsv)
echo "portal: https://$HOST"
```

## 4. Register the deployed URL

Add the Static Web App URL as a SPA redirect URI so MSAL sign-in works in
production:

```bash
az rest --method PATCH \
  --uri "https://graph.microsoft.com/v1.0/applications/$OBJECT_ID" \
  --headers "Content-Type=application/json" \
  --body "{\"spa\":{\"redirectUris\":[\"http://localhost:5173\",\"https://$HOST\"]}}"
```

## 5. Use it

Open `https://$HOST` and sign in with your Azure account (same tenant), or use
the **Access token** option (`az account get-access-token`) — no app registration
needed for that path. Then pick **subscription → APIM instance → workspace** to
load the dashboards. Token / latency / availability charts populate as traffic
flows through the gateway.

## Re-deploy after changes

```bash
VITE_AZURE_CLIENT_ID=$CLIENT_ID npm run build
TOKEN=$(az staticwebapp secrets list -n "$SWA" -g "$RG" --query properties.apiKey -o tsv)
npx -y @azure/static-web-apps-cli deploy ./dist --deployment-token "$TOKEN" --env production
```

## Clean up

```bash
az staticwebapp delete -n "$SWA" -g "$RG" --yes
az ad app delete --id "$CLIENT_ID"
```
