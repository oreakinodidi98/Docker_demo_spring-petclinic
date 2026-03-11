# Spring PetClinic - Passwordless Authentication Guide

## Overview

This guide explains the passwordless authentication setup for Spring PetClinic using **Azure Entra ID** and **Workload Identity** to connect to Azure PostgreSQL Flexible Server.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     Azure Kubernetes Service                    │
│                                                                 │
│  ┌────────────────────────────────────────────────────────┐   │
│  │  Pod: petclinic                                        │   │
│  │  ┌──────────────────────────────────────────────┐     │   │
│  │  │  Label: azure.workload.identity/use: "true"  │     │   │
│  │  └──────────────────────────────────────────────┘     │   │
│  │                                                        │   │
│  │  ServiceAccount: sc-account-acda3ed9-...              │   │
│  │  (Federated with Azure Managed Identity)              │   │
│  │                                                        │   │
│  │  Environment Variables from Secret: sc-pg-secret      │   │
│  │  - AZURE_POSTGRESQL_HOST                              │   │
│  │  - AZURE_POSTGRESQL_USERNAME (aad_pg)                 │   │
│  │  - AZURE_POSTGRESQL_CLIENTID                          │   │
│  └────────────────────────────────────────────────────────┘   │
│                           │                                     │
│                           │ Workload Identity                   │
│                           │ Federation                          │
│                           ▼                                     │
└───────────────────────────────────────────────────────────────┘
                            │
                            │ Azure Managed Identity
                            │ (mi-petclinic189769)
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│          Azure PostgreSQL Flexible Server                       │
│                                                                 │
│  Server: db-petclinic189769.postgres.database.azure.com        │
│  Database: petclinic                                           │
│  Authentication: Entra ID Only (Password Auth Disabled)        │
│  User: aad_pg                                                  │
│                                                                 │
│  ✅ No passwords stored anywhere                               │
│  ✅ Token-based authentication                                 │
│  ✅ Automatic token rotation                                   │
└─────────────────────────────────────────────────────────────────┘
```

## What Changed?

### Before (Password-Based Authentication)
- Local PostgreSQL pod running in Kubernetes
- Username and password stored in Kubernetes Secret
- Password hardcoded in YAML files
- Security risk: credentials exposed in multiple places

### After (Passwordless Authentication)
- Azure PostgreSQL Flexible Server
- No passwords - uses Azure Managed Identity
- Workload Identity for pod-to-Azure authentication
- Automatic token-based authentication
- Secrets managed by Azure Service Connector

## Key Components

### 1. Azure Managed Identity
**Name:** `mi-petclinic189769`
**Client ID:** `acda3ed9-e3d0-4f77-8887-37e2db05f5df`

This is the identity that has been granted access to the PostgreSQL database.

### 2. Kubernetes Service Account
**Name:** `sc-account-acda3ed9-e3d0-4f77-8887-37e2db05f5df`

This service account is federated with the Azure Managed Identity through workload identity federation. Any pod using this service account can authenticate as the managed identity.

### 3. Kubernetes Secret
**Name:** `sc-pg-secret`

Contains connection information (but NO passwords):
- `AZURE_POSTGRESQL_HOST`: db-petclinic189769.postgres.database.azure.com
- `AZURE_POSTGRESQL_PORT`: 5432
- `AZURE_POSTGRESQL_DATABASE`: petclinic
- `AZURE_POSTGRESQL_USERNAME`: aad_pg
- `AZURE_POSTGRESQL_CLIENTID`: acda3ed9-e3d0-4f77-8887-37e2db05f5df

### 4. PostgreSQL Database User
**Username:** `aad_pg`

This is an Entra ID user in PostgreSQL that represents the managed identity.

## How Passwordless Authentication Works

```
1. Pod starts with serviceAccountName: sc-account-acda3ed9-...
   └─> Pod gets annotated with workload identity label

2. Azure Workload Identity webhook injects identity token
   └─> Token projected to pod filesystem

3. Spring Boot app starts, Spring Cloud Azure SDK detects:
   - SPRING_CLOUD_AZURE_CREDENTIAL_MANAGED_IDENTITY_ENABLED=true
   - SPRING_DATASOURCE_AZURE_PASSWORDLESS_ENABLED=true
   - AZURE_POSTGRESQL_CLIENTID from secret

4. SDK exchanges identity token for Azure AD token
   └─> Uses OIDC token exchange with AKS OIDC issuer

5. SDK uses Azure AD token to get PostgreSQL access token
   └─> Token scope: https://ossrdbms-aad.database.windows.net/.default

6. SDK connects to PostgreSQL using access token as password
   └─> PostgreSQL validates token with Azure AD

7. Connection established - no password ever used!
   └─> Tokens auto-refresh before expiration
```

## Updated Kubernetes Manifests

### k8s/db.yml
The local PostgreSQL deployment has been **removed** since we're now using Azure PostgreSQL Flexible Server. The file contains documentation about the Azure setup.

### k8s/petclinic.yml

#### Key Changes:

**1. Service Account**
```yaml
spec:
  serviceAccountName: sc-account-acda3ed9-e3d0-4f77-8887-37e2db05f5df
```

**2. Workload Identity Label**
```yaml
metadata:
  labels:
    azure.workload.identity/use: "true"
```

**3. Environment Variables from Service Connector Secret**
```yaml
env:
  - name: AZURE_POSTGRESQL_HOST
    valueFrom:
      secretKeyRef:
        name: sc-pg-secret
        key: AZURE_POSTGRESQL_HOST
  # ... more variables
```

**4. Azure Managed Identity Configuration**
```yaml
  - name: SPRING_CLOUD_AZURE_CREDENTIAL_MANAGED_IDENTITY_ENABLED
    value: "true"
  - name: SPRING_DATASOURCE_AZURE_PASSWORDLESS_ENABLED
    value: "true"
```

**5. Service Type Changed**
```yaml
spec:
  type: LoadBalancer  # Changed from NodePort for easier access
```

## Deployment Instructions

### Prerequisites
1. Run the `setup.ps1` script (already completed)
2. Build and push the Docker image to ACR
3. Update the image reference in `petclinic.yml`

### Step 1: Build and Push Image to ACR

```powershell
# Set variables from .envrc
$env:ACR_NAME = "acrpetclinic189769"

# Login to ACR
az acr login --name $env:ACR_NAME

# Build the image (from spring-petclinic directory)
cd spring-petclinic
docker build -t spring-petclinic:v1 .

# Tag for ACR
docker tag spring-petclinic:v1 ${env:ACR_NAME}.azurecr.io/spring-petclinic:v1
docker tag spring-petclinic:v1 ${env:ACR_NAME}.azurecr.io/spring-petclinic:latest

# Push to ACR
docker push ${env:ACR_NAME}.azurecr.io/spring-petclinic:v1
docker push ${env:ACR_NAME}.azurecr.io/spring-petclinic:latest
```

### Step 2: Update Image Reference in YAML

Edit `k8s/petclinic.yml` and replace:
```yaml
image: dsyer/petclinic
```

With:
```yaml
image: acrpetclinic189769.azurecr.io/spring-petclinic:v1
```

### Step 3: Deploy to AKS

```powershell
# Set KUBECONFIG
$env:KUBECONFIG = "$PWD\aks-petclinic-1897692303.config"

# Verify connection to AKS
kubectl get nodes

# Verify Service Connector resources exist
kubectl get serviceaccount sc-account-acda3ed9-e3d0-4f77-8887-37e2db05f5df
kubectl get secret sc-pg-secret

# Deploy the application (no need to deploy db.yml)
kubectl apply -f k8s/petclinic.yml

# Watch the deployment
kubectl get pods -w
```

### Step 4: Verify Deployment

```powershell
# Check pod status
kubectl get pods

# View pod logs
kubectl logs -l app=petclinic --tail=100 -f

# Check for successful database connection
kubectl logs -l app=petclinic | Select-String "postgres"
kubectl logs -l app=petclinic | Select-String "Connected"

# Get the LoadBalancer IP
kubectl get service petclinic

# Wait for EXTERNAL-IP to be assigned (may take 2-3 minutes)
# Then access the application
Start-Process "http://<EXTERNAL-IP>"
```

## Troubleshooting

### Pod Not Starting

```powershell
# Check pod events
kubectl describe pod -l app=petclinic

# Check logs
kubectl logs -l app=petclinic
```

### Database Connection Issues

```powershell
# Verify secret exists and has correct data
kubectl get secret sc-pg-secret -o yaml

# Verify service account exists
kubectl get serviceaccount sc-account-acda3ed9-e3d0-4f77-8887-37e2db05f5df -o yaml

# Check for workload identity annotation
kubectl get serviceaccount sc-account-acda3ed9-e3d0-4f77-8887-37e2db05f5df -o yaml | Select-String "azure.workload.identity"
```

### Authentication Failures

```powershell
# Check pod logs for authentication errors
kubectl logs -l app=petclinic | Select-String "authentication"

# Verify the managed identity has database permissions
az postgres flexible-server ad-admin list \
  --resource-group rg-petclinic1897692303 \
  --server-name db-petclinic189769
```

### Workload Identity Not Working

```powershell
# Verify AKS has workload identity enabled
az aks show --resource-group rg-petclinic1897692303 \
  --name aks-petclinic-1897692303 \
  --query "oidcIssuerProfile.enabled"

# Should return: true

# Verify workload identity is enabled
az aks show --resource-group rg-petclinic1897692303 \
  --name aks-petclinic-1897692303 \
  --query "securityProfile.workloadIdentity.enabled"

# Should return: true
```

## Security Benefits

✅ **No Passwords in Code or Config**
- Zero credentials stored in YAML, code, or environment

✅ **Automatic Token Rotation**
- Access tokens expire after 1 hour and are automatically refreshed

✅ **Audit Trail**
- All database access is logged with managed identity details

✅ **Principle of Least Privilege**
- Each application gets its own managed identity with minimal permissions

✅ **No Credential Management**
- No need to rotate passwords or manage secrets

✅ **Defense in Depth**
- Multiple layers: Workload Identity + Entra ID + PostgreSQL permissions

## Additional Configuration Options

### Using Different Azure Clouds

If deploying to Azure Government, China, or Germany, add:

```yaml
env:
  - name: SPRING_CLOUD_AZURE_PROFILE_CLOUD_TYPE
    value: "azure_us_government"  # or azure_china, azure_germany
  
  - name: SPRING_DATASOURCE_AZURE_SCOPES
    value: "https://ossrdbms-aad.database.usgovcloudapi.net/.default"
```

### Custom Connection String

Instead of individual environment variables, you can use a full connection string:

```yaml
env:
  - name: POSTGRES_URL
    value: "jdbc:postgresql://db-petclinic189769.postgres.database.azure.com:5432/petclinic?sslmode=require"
```

## Monitoring and Observability

### Application Insights Integration

The application is configured with Application Insights for monitoring:

```powershell
# View application logs in Azure Portal
# Navigate to: Application Insights > Logs

# Query failed database connections
AzureDiagnostics
| where Category == "PostgreSQLLogs"
| where Message contains "authentication failed"
| order by TimeGenerated desc
```

### Prometheus Metrics

The AKS cluster has Azure Monitor Prometheus enabled:

```powershell
# Access Grafana dashboard
az aks show --resource-group rg-petclinic1897692303 \
  --name aks-petclinic-1897692303 \
  --query "azureMonitorProfile.metrics.grafanaResourceId"
```

## References

- [Azure Service Connector Documentation](https://learn.microsoft.com/en-us/azure/service-connector/)
- [Workload Identity for AKS](https://learn.microsoft.com/en-us/azure/aks/workload-identity-overview)
- [Azure PostgreSQL Flexible Server Authentication](https://learn.microsoft.com/en-us/azure/postgresql/flexible-server/concepts-azure-ad-authentication)
- [Spring Cloud Azure PostgreSQL](https://learn.microsoft.com/en-us/azure/developer/java/spring-framework/configure-spring-data-jdbc-with-azure-postgresql)

---

**Last Updated:** March 10, 2026
**Infrastructure Version:** AKS 1.30+, PostgreSQL 15, Spring Boot 3.5.6
