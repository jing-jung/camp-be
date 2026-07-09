# Complete Frontend Deployment Script
# Rebuilds Docker image and deploys to Lambda + CloudFront

param(
    [string]$FrontendDir = "C:\Users\한국전파진흥협회\Desktop\camp-fe",
    [string]$CampBeDir = "C:\Users\한국전파진흥협회\Desktop\camp-be\camp-be",
    [string]$AwsRegion = "ap-northeast-2",
    [string]$Environment = "dev"
)

$ErrorActionPreference = "Stop"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "Complete Frontend Deployment (Docker + Terraform)" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host ""

# AWS 계정 ID 감지
Write-Host "Step 1: Detecting AWS Account ID..." -ForegroundColor Yellow
try {
    $accountInfo = aws sts get-caller-identity --output json | ConvertFrom-Json
    $AwsAccountId = $accountInfo.Account
    Write-Host "[OK] AWS Account ID: $AwsAccountId" -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Failed to detect AWS Account ID" -ForegroundColor Red
    Write-Host "[HINT] Run 'aws configure' first" -ForegroundColor Yellow
    exit 1
}
Write-Host ""

# 변수 설정
$ECR_REPOSITORY = "stockbrief-${Environment}-frontend"
$ECR_IMAGE_URI = "${AwsAccountId}.dkr.ecr.${AwsRegion}.amazonaws.com/${ECR_REPOSITORY}:latest"
$DockerImageName = "${ECR_REPOSITORY}:latest"

Write-Host "Configuration:" -ForegroundColor Yellow
Write-Host "  Frontend Dir: $FrontendDir" -ForegroundColor White
Write-Host "  Camp-Be Dir: $CampBeDir" -ForegroundColor White
Write-Host "  ECR Repository: $ECR_REPOSITORY" -ForegroundColor White
Write-Host "  ECR Image URI: $ECR_IMAGE_URI" -ForegroundColor White
Write-Host ""

# 디렉토리 확인
if (-not (Test-Path $FrontendDir)) {
    Write-Host "[ERROR] Frontend directory not found: $FrontendDir" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $CampBeDir)) {
    Write-Host "[ERROR] Camp-Be directory not found: $CampBeDir" -ForegroundColor Red
    exit 1
}

$DockerfilePath = Join-Path $CampBeDir "Dockerfile.frontend-lambda"
if (-not (Test-Path $DockerfilePath)) {
    Write-Host "[ERROR] Dockerfile not found: $DockerfilePath" -ForegroundColor Red
    exit 1
}

Write-Host "[OK] All directories found" -ForegroundColor Green
Write-Host ""

# ========================================
# STEP 2: Docker Build (Linux AMD64)
# ========================================
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "Step 2: Building Docker Image (Linux AMD64 for Lambda)" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host ""

Push-Location $FrontendDir
try {
    Write-Host "Building with buildx for Lambda compatibility..." -ForegroundColor Yellow
    Write-Host "   Platform: linux/amd64" -ForegroundColor Gray
    Write-Host "   Dockerfile: $DockerfilePath" -ForegroundColor Gray
    Write-Host "   Image: $DockerImageName" -ForegroundColor Gray
    Write-Host ""
    
    # Docker buildx build
    docker buildx build `
        --platform linux/amd64 `
        -f $DockerfilePath `
        -t $DockerImageName `
        --load `
        .
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] Docker build failed" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "[OK] Docker image built successfully" -ForegroundColor Green
} finally {
    Pop-Location
}
Write-Host ""

# ========================================
# STEP 3: ECR Login
# ========================================
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "Step 3: Logging in to ECR" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Authenticating with ECR..." -ForegroundColor Yellow
$ecrLogin = aws ecr get-login-password --region $AwsRegion | docker login --username AWS --password-stdin "${AwsAccountId}.dkr.ecr.${AwsRegion}.amazonaws.com"

if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] ECR login failed" -ForegroundColor Red
    exit 1
}

Write-Host "[OK] ECR login successful" -ForegroundColor Green
Write-Host ""

# ========================================
# STEP 4: Tag and Push to ECR
# ========================================
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "Step 4: Pushing Image to ECR" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Tagging image..." -ForegroundColor Yellow
docker tag $DockerImageName $ECR_IMAGE_URI

if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Docker tag failed" -ForegroundColor Red
    exit 1
}

Write-Host "Pushing to ECR: $ECR_IMAGE_URI" -ForegroundColor Yellow
docker push $ECR_IMAGE_URI

if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Docker push failed" -ForegroundColor Red
    exit 1
}

Write-Host "[OK] Image pushed to ECR successfully" -ForegroundColor Green
Write-Host ""

# ========================================
# STEP 5: Terraform Deployment
# ========================================
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "Step 5: Deploying with Terraform" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host ""

$TerraformDir = Join-Path $CampBeDir "infra\terraform"
if (-not (Test-Path $TerraformDir)) {
    Write-Host "[ERROR] Terraform directory not found: $TerraformDir" -ForegroundColor Red
    exit 1
}

Push-Location $TerraformDir
try {
    Write-Host "Terraform directory: $TerraformDir" -ForegroundColor Gray
    Write-Host ""
    
    # Refresh state
    Write-Host "Refreshing Terraform state..." -ForegroundColor Yellow
    terraform refresh -var-file="envs\dev\deploy.auto.tfvars.json"
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[WARNING] Terraform refresh had issues, continuing..." -ForegroundColor Yellow
    }
    Write-Host ""
    
    # Apply only frontend resources
    Write-Host "Applying Terraform (Frontend resources only)..." -ForegroundColor Yellow
    Write-Host "[NOTE] This will only deploy Lambda and CloudFront" -ForegroundColor Cyan
    Write-Host ""
    
    terraform apply `
        -target=module.frontend_lambda[0] `
        -target=module.frontend_cloudfront_lambda[0] `
        -var-file="envs\dev\deploy.auto.tfvars.json" `
        -auto-approve
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] Terraform apply failed" -ForegroundColor Red
        Write-Host ""
        Write-Host "Common issues:" -ForegroundColor Yellow
        Write-Host "  1. CloudFront cache policy error - check modules/frontend_cloudfront_lambda/main.tf" -ForegroundColor Gray
        Write-Host "  2. ElastiCache already exists - needs import" -ForegroundColor Gray
        Write-Host "  3. VPC dependencies - may need manual cleanup" -ForegroundColor Gray
        exit 1
    }
    
    Write-Host "[OK] Terraform apply completed" -ForegroundColor Green
    Write-Host ""
    
    # Get outputs
    Write-Host "Getting deployment outputs..." -ForegroundColor Yellow
    $frontendUrl = terraform output -raw frontend_hosted_url 2>$null
    
    if ($frontendUrl) {
        Write-Host ""
        Write-Host "==========================================================" -ForegroundColor Green
        Write-Host "Deployment Successful!" -ForegroundColor Green
        Write-Host "==========================================================" -ForegroundColor Green
        Write-Host ""
        Write-Host "Frontend URL: $frontendUrl" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Next Steps:" -ForegroundColor Yellow
        Write-Host "  1. Test the URL in your browser" -ForegroundColor White
        Write-Host "  2. Update Cognito callback URLs:" -ForegroundColor White
        Write-Host "     ${frontendUrl}/auth/callback" -ForegroundColor Gray
        Write-Host "  3. Check Lambda logs:" -ForegroundColor White
        Write-Host "     aws logs tail /aws/lambda/stockbrief-dev-frontend-lambda --follow" -ForegroundColor Gray
    } else {
        Write-Host "[WARNING] Could not retrieve frontend URL" -ForegroundColor Yellow
        Write-Host "Run: terraform output frontend_hosted_url" -ForegroundColor Gray
    }
    
} finally {
    Pop-Location
}

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Magenta
Write-Host "Deployment Complete!" -ForegroundColor Magenta
Write-Host "==========================================================" -ForegroundColor Magenta
