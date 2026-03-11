# Passwordless Authentication Upgrade - Summary

## 🎯 What Was Done

The Kubernetes YAML files have been upgraded to use **passwordless authentication** with Azure PostgreSQL Flexible Server using **Azure Entra ID** and **Workload Identity**.

## 📋 Files Modified

### 1. **k8s/db.yml**
- **Before:** Contained a local PostgreSQL deployment with username/password in a Kubernetes Secret
- **After:** Removed local PostgreSQL deployment (now using Azure PostgreSQL Flexible Server)
- **Reason:** Azure Service Connector manages the database connection

### 2. **k8s/petclinic.yml**
- **Before:** Used local PostgreSQL with password-based authentication via volume-mounted secrets
- **After:** Configured to use Azure PostgreSQL with passwordless authentication via Workload Identity

#### Key Changes in petclinic.yml:

| Aspect | Before | After |
|--------|--------|-------|
| **Service Type** | NodePort | LoadBalancer |
| **Service Account** | (default) | `sc-account-acda3ed9-e3d0-4f77-8887-37e2db05f5df` |
| **Workload Identity** | Not configured | Label: `azure.workload.identity/use: "true"` |
| **Database Connection** | Volume-mounted secret | Environment variables from Service Connector secret |
| **Authentication** | Password | Azure Managed Identity (passwordless) |
| **Image** | dsyer/petclinic | Ready to use your ACR image |
| **Node Selector** | None | Linux nodes only |
| **Resource Limits** | None | Requests and limits defined |
| **Probes** | Basic | Enhanced with timeouts and startup probe |

## 🏗️ Infrastructure Components

These components were created by the `setup.ps1` script:

### Azure Resources
1. **Azure Managed Identity:** `mi-petclinic189769`
   - Client ID: `acda3ed9-e3d0-4f77-8887-37e2db05f5df`
   - Has permissions to access PostgreSQL

2. **PostgreSQL Flexible Server:** `db-petclinic189769.postgres.database.azure.com`
   - Database: `petclinic`
   - Authentication: Entra ID only (passwords disabled)
   - User: `aad_pg`

3. **AKS Cluster:** `aks-petclinic-1897692303`
   - Workload Identity: Enabled
   - OIDC Issuer: Enabled
   - ACR Integration: Enabled

### Kubernetes Resources

Created by Azure Service Connector:

1. **Service Account:** `sc-account-acda3ed9-e3d0-4f77-8887-37e2db05f5df`
   - Federated with Azure Managed Identity
   - Annotated for workload identity

2. **Secret:** `sc-pg-secret`
   - Contains connection parameters (NO passwords)
   - Keys: HOST, PORT, DATABASE, USERNAME, CLIENTID

## 🔐 Security Improvements

| Security Aspect | Before | After | Benefit |
|-----------------|--------|-------|---------|
| **Passwords** | Stored in YAML and Secrets | None, token-based auth | Zero credential exposure |
| **Credential Rotation** | Manual password changes | Automatic token refresh | No downtime |
| **Audit Trail** | Generic database user | Managed identity tracking | Better compliance |
| **Least Privilege** | Single admin user | Managed identity per app | Principle of least privilege |
| **Secret Management** | Stored in cluster | Managed by Azure | Centralized secret management |

## 🚀 How to Deploy

### Option 1: Automated Deployment Script

```powershell
cd spring-petclinic
.\deploy-to-aks.ps1
```

This script will:
1. Build the Docker image
2. Push to Azure Container Registry
3. Update the Kubernetes manifest
4. Deploy to AKS
5. Wait for the deployment to be ready
6. Open your browser to the application

### Option 2: Manual Deployment

```powershell
# 1. Build and push image
docker build -t spring-petclinic:v1 .
az acr login --name acrpetclinic189769
docker tag spring-petclinic:v1 acrpetclinic189769.azurecr.io/spring-petclinic:v1
docker push acrpetclinic189769.azurecr.io/spring-petclinic:v1

# 2. Update image in k8s/petclinic.yml
# Change: image: dsyer/petclinic
# To: image: acrpetclinic189769.azurecr.io/spring-petclinic:v1

# 3. Set kubeconfig
$env:KUBECONFIG = "..\aks-petclinic-1897692303.config"

# 4. Deploy
kubectl apply -f k8s/petclinic.yml

# 5. Get service IP
kubectl get service petclinic
```

## 🔍 Verification Steps

### 1. Verify Service Connector Resources

```powershell
# Check service account
kubectl get serviceaccount sc-account-acda3ed9-e3d0-4f77-8887-37e2db05f5df

# Check secret
kubectl get secret sc-pg-secret

# View secret contents (no passwords!)
kubectl get secret sc-pg-secret -o yaml
```

### 2. Check Pod Status

```powershell
# View pods
kubectl get pods

# Check pod details
kubectl describe pod -l app=petclinic

# View logs
kubectl logs -l app=petclinic
```

### 3. Verify Database Connection

```powershell
# Check logs for database connection
kubectl logs -l app=petclinic | Select-String "postgres"
kubectl logs -l app=petclinic | Select-String "Started PetClinicApplication"
```

### 4. Test the Application

```powershell
# Get the LoadBalancer IP
kubectl get service petclinic

# Open in browser
Start-Process "http://<EXTERNAL-IP>"
```

## 📊 Environment Variables Reference

The application now uses these environment variables from the Service Connector secret:

| Variable | Value | Purpose |
|----------|-------|---------|
| `AZURE_POSTGRESQL_HOST` | db-petclinic189769.postgres.database.azure.com | Database server |
| `AZURE_POSTGRESQL_PORT` | 5432 | Database port |
| `AZURE_POSTGRESQL_DATABASE` | petclinic | Database name |
| `AZURE_POSTGRESQL_USERNAME` | aad_pg | Entra ID user |
| `AZURE_POSTGRESQL_CLIENTID` | acda3ed9-... | Managed identity client ID |
| `SPRING_CLOUD_AZURE_CREDENTIAL_MANAGED_IDENTITY_ENABLED` | true | Enable managed identity |
| `SPRING_DATASOURCE_AZURE_PASSWORDLESS_ENABLED` | true | Enable passwordless auth |

## 🛠️ Troubleshooting

### Pod Not Starting

```powershell
kubectl describe pod -l app=petclinic
kubectl logs -l app=petclinic
```

**Common Issues:**
- Image pull errors: Check ACR permissions
- Service account not found: Verify Service Connector setup
- Secret not found: Check if sc-pg-secret exists

### Authentication Failures

```powershell
kubectl logs -l app=petclinic | Select-String "authentication"
```

**Common Issues:**
- Workload identity not configured: Check pod has the label `azure.workload.identity/use: "true"`
- Managed identity permissions: Verify the identity has database access
- Token refresh issues: Check AKS OIDC issuer is enabled

### Database Connection Issues

```powershell
# Test PostgreSQL connectivity from a pod
kubectl run -it --rm debug --image=postgres:15 --restart=Never -- \
  psql "host=db-petclinic189769.postgres.database.azure.com dbname=petclinic user=aad_pg sslmode=require"
```

## 📚 Documentation Files Created

1. **PASSWORDLESS_AUTH_GUIDE.md** - Comprehensive guide on passwordless authentication
2. **CONTAINERIZATION_SUMMARY.md** - Docker containerization documentation
3. **deploy-to-aks.ps1** - Automated deployment script
4. **PASSWORDLESS_UPGRADE_SUMMARY.md** (this file) - Quick reference guide

## 🔗 Related Resources

- **Setup Script:** `../setup.ps1` - Infrastructure provisioning
- **Service Connector Log:** `../sc.log` - Connection details
- **Environment Variables:** `../.envrc` - Resource names
- **Kubernetes Config:** `../aks-petclinic-1897692303.config` - AKS access

## ✅ Success Criteria

Your deployment is successful when:

1. ✅ Pod is running: `kubectl get pods` shows `Running` status
2. ✅ Database connected: Logs show "Started PetClinicApplication"
3. ✅ LoadBalancer ready: `kubectl get service petclinic` shows EXTERNAL-IP
4. ✅ Application accessible: Browser opens the PetClinic UI
5. ✅ No passwords used: No authentication errors in logs

## 🎓 Key Concepts Learned

### Workload Identity
- Kubernetes pods can authenticate as Azure Managed Identities
- Uses OIDC token exchange (no secrets required)
- Automatic token rotation

### Service Connector
- Automates the setup of connections between Azure services
- Creates necessary Kubernetes resources
- Manages configuration and secrets

### Passwordless Authentication
- Uses Azure AD tokens instead of passwords
- More secure and easier to manage
- Supports automatic credential rotation

---

**Need Help?**
- Check [PASSWORDLESS_AUTH_GUIDE.md](PASSWORDLESS_AUTH_GUIDE.md) for detailed information
- Review pod logs: `kubectl logs -l app=petclinic`
- Verify Service Connector status: `az aks connection list --source-id <AKS_CLUSTER_ID>`

**Last Updated:** March 10, 2026
