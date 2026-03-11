# Spring PetClinic - Passwordless Deployment Script
# This script deploys the Spring PetClinic application to AKS with passwordless authentication

Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "Spring PetClinic - Passwordless Deploy" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host ""

# Load environment variables from .envrc
if (Test-Path "../.envrc") {
    Write-Host "✅ Loading environment variables from .envrc" -ForegroundColor Green
    Get-Content "../.envrc" | ForEach-Object {
        if ($_ -match "export\s+(\w+)=(.+)") {
            $name = $matches[1]
            $value = $matches[2].Trim('"')
            Set-Item -Path "env:$name" -Value $value
            Write-Host "   Set $name" -ForegroundColor Gray
        }
    }
} else {
    Write-Host "❌ .envrc file not found. Have you run setup.ps1?" -ForegroundColor Red
    exit 1
}

# Verify required variables
$requiredVars = @("ACR_NAME", "AKS_CLUSTER_NAME", "POSTGRES_SERVER_NAME")
$missingVars = @()
foreach ($var in $requiredVars) {
    if (-not (Test-Path "env:$var")) {
        $missingVars += $var
    }
}

if ($missingVars.Count -gt 0) {
    Write-Host "❌ Missing required environment variables: $($missingVars -join ', ')" -ForegroundColor Red
    Write-Host "   Please run setup.ps1 first." -ForegroundColor Yellow
    exit 1
}

Write-Host ""
Write-Host "📋 Configuration:" -ForegroundColor Cyan
Write-Host "   ACR: $env:ACR_NAME" -ForegroundColor Gray
Write-Host "   AKS Cluster: $env:AKS_CLUSTER_NAME" -ForegroundColor Gray
Write-Host "   PostgreSQL Server: $env:POSTGRES_SERVER_NAME" -ForegroundColor Gray
Write-Host ""

# Step 1: Build Docker image
Write-Host "🔨 Step 1: Building Docker image..." -ForegroundColor Cyan
docker build -t spring-petclinic:latest .
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Docker build failed" -ForegroundColor Red
    exit 1
}
Write-Host "✅ Docker image built successfully" -ForegroundColor Green
Write-Host ""

# Step 2: Login to ACR
Write-Host "🔐 Step 2: Logging in to Azure Container Registry..." -ForegroundColor Cyan
az acr login --name $env:ACR_NAME
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ ACR login failed" -ForegroundColor Red
    exit 1
}
Write-Host "✅ Logged in to ACR" -ForegroundColor Green
Write-Host ""

# Step 3: Tag and push image
Write-Host "📤 Step 3: Pushing image to ACR..." -ForegroundColor Cyan
$acrLoginServer = "$env:ACR_NAME.azurecr.io"
$imageName = "spring-petclinic"
$imageTag = "v1"

docker tag spring-petclinic:latest "$acrLoginServer/$imageName`:$imageTag"
docker tag spring-petclinic:latest "$acrLoginServer/$imageName`:latest"

docker push "$acrLoginServer/$imageName`:$imageTag"
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Failed to push image" -ForegroundColor Red
    exit 1
}

docker push "$acrLoginServer/$imageName`:latest"
Write-Host "✅ Image pushed to ACR" -ForegroundColor Green
Write-Host ""

# Step 4: Update YAML with correct image
Write-Host "📝 Step 4: Updating Kubernetes manifest..." -ForegroundColor Cyan
$yamlPath = "k8s/petclinic.yml"
$yamlContent = Get-Content $yamlPath -Raw

# Replace the image reference
$newImage = "$acrLoginServer/$imageName`:$imageTag"
$yamlContent = $yamlContent -replace "image:\s*dsyer/petclinic", "image: $newImage"
$yamlContent = $yamlContent -replace "image:\s*acrpetclinic\d+\.azurecr\.io/spring-petclinic:v\d+", "image: $newImage"

$yamlContent | Set-Content $yamlPath -NoNewline
Write-Host "✅ Kubernetes manifest updated with image: $newImage" -ForegroundColor Green
Write-Host ""

# Step 5: Set kubeconfig
Write-Host "🔧 Step 5: Configuring kubectl..." -ForegroundColor Cyan
$env:KUBECONFIG = "..\$env:AKS_CLUSTER_NAME.config"
if (-not (Test-Path $env:KUBECONFIG)) {
    Write-Host "❌ Kubeconfig not found at $env:KUBECONFIG" -ForegroundColor Red
    Write-Host "   Getting credentials from AKS..." -ForegroundColor Yellow
    
    # Extract resource group from AKS cluster name
    $rgName = "rg-" + ($env:AKS_CLUSTER_NAME -replace "aks-", "")
    
    az aks get-credentials `
        --resource-group $rgName `
        --name $env:AKS_CLUSTER_NAME `
        --overwrite-existing `
        --file $env:KUBECONFIG
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ Failed to get AKS credentials" -ForegroundColor Red
        exit 1
    }
}
Write-Host "✅ kubectl configured" -ForegroundColor Green
Write-Host ""

# Step 6: Verify Service Connector resources
Write-Host "🔍 Step 6: Verifying Service Connector resources..." -ForegroundColor Cyan
$serviceAccount = kubectl get serviceaccount -o name 2>$null | Select-String "sc-account-"
$secret = kubectl get secret sc-pg-secret -o name 2>$null

if (-not $serviceAccount) {
    Write-Host "❌ Service Connector service account not found" -ForegroundColor Red
    Write-Host "   The Azure Service Connector may not have been created properly." -ForegroundColor Yellow
    Write-Host "   Please check the setup.ps1 output and sc.log file." -ForegroundColor Yellow
    exit 1
}

if (-not $secret) {
    Write-Host "❌ Service Connector secret (sc-pg-secret) not found" -ForegroundColor Red
    exit 1
}

Write-Host "✅ Service account found: $serviceAccount" -ForegroundColor Green
Write-Host "✅ Secret found: $secret" -ForegroundColor Green
Write-Host ""

# Step 7: Deploy the application
Write-Host "🚀 Step 7: Deploying application to AKS..." -ForegroundColor Cyan
kubectl apply -f k8s/petclinic.yml
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Deployment failed" -ForegroundColor Red
    exit 1
}
Write-Host "✅ Application deployed" -ForegroundColor Green
Write-Host ""

# Step 8: Wait for deployment
Write-Host "⏳ Step 8: Waiting for deployment to be ready..." -ForegroundColor Cyan
Write-Host "   This may take 2-3 minutes..." -ForegroundColor Gray
Write-Host ""

$timeout = 300  # 5 minutes
$elapsed = 0
$interval = 5

while ($elapsed -lt $timeout) {
    $status = kubectl get deployment petclinic -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>$null
    
    if ($status -eq "True") {
        Write-Host "✅ Deployment is ready!" -ForegroundColor Green
        break
    }
    
    Start-Sleep -Seconds $interval
    $elapsed += $interval
    Write-Host "   Waiting... ($elapsed seconds)" -ForegroundColor Gray
}

if ($elapsed -ge $timeout) {
    Write-Host "⚠️  Deployment did not become ready within timeout" -ForegroundColor Yellow
    Write-Host "   Checking pod status..." -ForegroundColor Yellow
    kubectl get pods -l app=petclinic
    Write-Host ""
    Write-Host "   Checking pod logs..." -ForegroundColor Yellow
    kubectl logs -l app=petclinic --tail=50
}

Write-Host ""

# Step 9: Get service information
Write-Host "🌐 Step 9: Getting service endpoint..." -ForegroundColor Cyan
Write-Host "   Waiting for LoadBalancer IP..." -ForegroundColor Gray

$timeout = 180  # 3 minutes
$elapsed = 0
$interval = 5
$externalIP = $null

while ($elapsed -lt $timeout) {
    $externalIP = kubectl get service petclinic -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>$null
    
    if ($externalIP) {
        break
    }
    
    Start-Sleep -Seconds $interval
    $elapsed += $interval
    Write-Host "   Waiting... ($elapsed seconds)" -ForegroundColor Gray
}

Write-Host ""
Write-Host "=====================================" -ForegroundColor Green
Write-Host "✅ Deployment Complete!" -ForegroundColor Green
Write-Host "=====================================" -ForegroundColor Green
Write-Host ""

if ($externalIP) {
    Write-Host "🌐 Application URL: http://$externalIP" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Opening browser..." -ForegroundColor Gray
    Start-Sleep -Seconds 2
    Start-Process "http://$externalIP"
} else {
    Write-Host "⚠️  LoadBalancer IP not assigned yet. Run this command to check:" -ForegroundColor Yellow
    Write-Host "   kubectl get service petclinic" -ForegroundColor Gray
}

Write-Host ""
Write-Host "📊 Useful commands:" -ForegroundColor Cyan
Write-Host "   View pods:          kubectl get pods" -ForegroundColor Gray
Write-Host "   View logs:          kubectl logs -l app=petclinic -f" -ForegroundColor Gray
Write-Host "   View service:       kubectl get service petclinic" -ForegroundColor Gray
Write-Host "   Describe pod:       kubectl describe pod -l app=petclinic" -ForegroundColor Gray
Write-Host "   Delete deployment:  kubectl delete -f k8s/petclinic.yml" -ForegroundColor Gray
Write-Host ""
Write-Host "📚 Documentation:" -ForegroundColor Cyan
Write-Host "   Passwordless Auth Guide: PASSWORDLESS_AUTH_GUIDE.md" -ForegroundColor Gray
Write-Host "   Containerization Summary: CONTAINERIZATION_SUMMARY.md" -ForegroundColor Gray
Write-Host ""
