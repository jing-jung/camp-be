# Frontend Lambda Deployment Script (PowerShell)
# Deploy frontend to Lambda + CloudFront

param(
    [string]$Environment = "dev",
    [string]$AwsRegion = "ap-northeast-2",
    [string]$AwsAccountId = "",  # 자동 감지됨
    [string]$ImageTag = "latest",
    [string]$FrontendDir = "..\camp-fe"
)

$ErrorActionPreference = "Stop"

# 파라미터 검증
if ([string]::IsNullOrWhiteSpace($ImageTag)) {
    $ImageTag = "latest"
}

if ([string]::IsNullOrWhiteSpace($Environment)) {
    $Environment = "dev"
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "StockBrief Frontend Lambda Deployment" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host ""

# AWS 계정 ID 자동 감지
if ([string]::IsNullOrEmpty($AwsAccountId)) {
    Write-Host "Detecting AWS Account ID..." -ForegroundColor Yellow
    try {
        $accountInfo = aws sts get-caller-identity --output json | ConvertFrom-Json
        $AwsAccountId = $accountInfo.Account
        Write-Host "[OK] AWS Account ID detected: $AwsAccountId" -ForegroundColor Green
    } catch {
        Write-Host "[ERROR] Failed to detect AWS Account ID" -ForegroundColor Red
        Write-Host "[HINT] Make sure you're logged in with 'aws configure'" -ForegroundColor Yellow
        exit 1
    }
}
Write-Host ""

# 변수 설정
$ECR_REPOSITORY = "stockbrief-$Environment-frontend"
$ECR_IMAGE_URI = "$AwsAccountId.dkr.ecr.$AwsRegion.amazonaws.com/${ECR_REPOSITORY}:${ImageTag}"
$LAMBDA_FUNCTION_NAME = "stockbrief-$Environment-frontend-lambda"

Write-Host "Configuration:" -ForegroundColor Yellow
Write-Host "  Environment: $Environment" -ForegroundColor White
Write-Host "  Region: $AwsRegion" -ForegroundColor White
Write-Host "  Account ID: $AwsAccountId" -ForegroundColor White
Write-Host "  ECR Repository: $ECR_REPOSITORY" -ForegroundColor White
Write-Host "  Image Tag: $ImageTag" -ForegroundColor White
Write-Host "  Frontend Directory: $FrontendDir" -ForegroundColor White
Write-Host ""

# 프론트엔드 디렉토리 확인
if (-not (Test-Path $FrontendDir)) {
    Write-Host "[ERROR] Frontend directory not found: $FrontendDir" -ForegroundColor Red
    Write-Host "[HINT] Run this script from camp-be directory" -ForegroundColor Yellow
    exit 1
}

Write-Host "[OK] Frontend directory found" -ForegroundColor Green
Write-Host ""

# ═══════════════════════════════════════════════════════════
# Step 1: ECR Repository 확인/생성
# ═══════════════════════════════════════════════════════════
Write-Host "----------------------------------------------------------" -ForegroundColor Cyan
Write-Host "Step 1/5: ECR Repository" -ForegroundColor Cyan
Write-Host "----------------------------------------------------------" -ForegroundColor Cyan

try {
    $null = aws ecr describe-repositories --repository-names $ECR_REPOSITORY --region $AwsRegion 2>&1
    Write-Host "[OK] ECR repository already exists: $ECR_REPOSITORY" -ForegroundColor Green
} catch {
    Write-Host "Creating ECR repository: $ECR_REPOSITORY" -ForegroundColor Yellow
    aws ecr create-repository `
        --repository-name $ECR_REPOSITORY `
        --region $AwsRegion `
        --image-scanning-configuration scanOnPush=true `
        --encryption-configuration encryptionType=AES256
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[OK] ECR repository created successfully" -ForegroundColor Green
    } else {
        Write-Host "[ERROR] Failed to create ECR repository" -ForegroundColor Red
        exit 1
    }
}
Write-Host ""

# ═══════════════════════════════════════════════════════════
# Step 2: Docker 이미지 빌드 및 푸시
# ═══════════════════════════════════════════════════════════
Write-Host "----------------------------------------------------------" -ForegroundColor Cyan
Write-Host "Step 2/5: Docker Build & Push" -ForegroundColor Cyan
Write-Host "----------------------------------------------------------" -ForegroundColor Cyan

# ECR 로그인
Write-Host "Logging in to ECR..." -ForegroundColor Yellow
aws ecr get-login-password --region $AwsRegion | docker login --username AWS --password-stdin "$AwsAccountId.dkr.ecr.$AwsRegion.amazonaws.com"

if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] ECR login failed" -ForegroundColor Red
    exit 1
}
Write-Host "[OK] ECR login successful" -ForegroundColor Green
Write-Host ""

# Docker 이미지 빌드
Write-Host "Building Docker image..." -ForegroundColor Yellow
Write-Host "   Context: $FrontendDir" -ForegroundColor Gray
Write-Host "   Dockerfile: Dockerfile.frontend-lambda" -ForegroundColor Gray

# Docker 이미지 이름 구성
$DockerImageName = "${ECR_REPOSITORY}:${ImageTag}"
Write-Host "   Image Name: $DockerImageName" -ForegroundColor Gray
Write-Host ""

Push-Location $FrontendDir
try {
    # Dockerfile 경로 확인 (스크립트 위치 기준)
    $ScriptDir = Split-Path -Parent $PSCommandPath
    $ProjectRoot = Split-Path -Parent $ScriptDir
    $DockerfilePath = Join-Path $ProjectRoot "Dockerfile.frontend-lambda"
    
    if (-not (Test-Path $DockerfilePath)) {
        Write-Host "[ERROR] Dockerfile not found: $DockerfilePath" -ForegroundColor Red
        Write-Host "[HINT] Make sure Dockerfile.frontend-lambda exists in camp-be directory" -ForegroundColor Yellow
        exit 1
    }
    
    Write-Host "   Dockerfile Path: $DockerfilePath" -ForegroundColor Gray
    
    # Docker 빌드 실행
    docker build -f $DockerfilePath -t $DockerImageName .
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] Docker build failed" -ForegroundColor Red
        exit 1
    }
    Write-Host "[OK] Docker image built successfully" -ForegroundColor Green
} finally {
    Pop-Location
}
Write-Host ""

# ECR에 태그 및 푸시
Write-Host "Pushing image to ECR..." -ForegroundColor Yellow
Write-Host "   Source: $DockerImageName" -ForegroundColor Gray
Write-Host "   Target: $ECR_IMAGE_URI" -ForegroundColor Gray
docker tag $DockerImageName $ECR_IMAGE_URI
docker push $ECR_IMAGE_URI

if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Docker push failed" -ForegroundColor Red
    exit 1
}
Write-Host "[OK] Image pushed to ECR: $ECR_IMAGE_URI" -ForegroundColor Green
Write-Host ""

# ═══════════════════════════════════════════════════════════
# Step 3: Lambda 함수 확인/생성
# ═══════════════════════════════════════════════════════════
Write-Host "----------------------------------------------------------" -ForegroundColor Cyan
Write-Host "Step 3/5: Lambda Function" -ForegroundColor Cyan
Write-Host "----------------------------------------------------------" -ForegroundColor Cyan

Write-Host "[NOTE] Lambda function should be created via Terraform" -ForegroundColor Yellow
Write-Host "   If not exists, run: cd infra/terraform/envs/dev && terraform apply" -ForegroundColor Yellow
Write-Host ""

try {
    $lambdaInfo = aws lambda get-function --function-name $LAMBDA_FUNCTION_NAME --region $AwsRegion 2>&1 | ConvertFrom-Json
    Write-Host "[OK] Lambda function exists: $LAMBDA_FUNCTION_NAME" -ForegroundColor Green
    
    # Lambda 함수 업데이트
    Write-Host "Updating Lambda function code..." -ForegroundColor Yellow
    aws lambda update-function-code `
        --function-name $LAMBDA_FUNCTION_NAME `
        --image-uri $ECR_IMAGE_URI `
        --region $AwsRegion `
        --no-cli-pager
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[OK] Lambda function updated successfully" -ForegroundColor Green
    } else {
        Write-Host "[ERROR] Failed to update Lambda function" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "[WARNING] Lambda function not found: $LAMBDA_FUNCTION_NAME" -ForegroundColor Yellow
    Write-Host "[ACTION] Deploy Lambda using Terraform" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Run these commands:" -ForegroundColor Cyan
    Write-Host "  cd infra\terraform\envs\dev" -ForegroundColor White
    Write-Host "  terraform init -backend-config=..\..\backends\dev.hcl" -ForegroundColor White
    Write-Host "  terraform apply" -ForegroundColor White
    Write-Host ""
}
Write-Host ""

# ═══════════════════════════════════════════════════════════
# Step 4: Lambda Function URL 확인
# ═══════════════════════════════════════════════════════════
Write-Host "----------------------------------------------------------" -ForegroundColor Cyan
Write-Host "Step 4/5: Lambda Function URL" -ForegroundColor Cyan
Write-Host "----------------------------------------------------------" -ForegroundColor Cyan

try {
    $funcUrlInfo = aws lambda get-function-url-config --function-name $LAMBDA_FUNCTION_NAME --region $AwsRegion 2>&1 | ConvertFrom-Json
    
    if ($funcUrlInfo.FunctionUrl) {
        Write-Host "[OK] Lambda Function URL is configured" -ForegroundColor Green
        Write-Host "   URL: $($funcUrlInfo.FunctionUrl)" -ForegroundColor White
    }
} catch {
    Write-Host "[WARNING] Lambda Function URL not configured" -ForegroundColor Yellow
    Write-Host "[NOTE] This will be created by Terraform" -ForegroundColor Yellow
}
Write-Host ""

# ═══════════════════════════════════════════════════════════
# Step 5: CloudFront 배포 확인
# ═══════════════════════════════════════════════════════════
Write-Host "----------------------------------------------------------" -ForegroundColor Cyan
Write-Host "Step 5/5: CloudFront Distribution" -ForegroundColor Cyan
Write-Host "----------------------------------------------------------" -ForegroundColor Cyan

Write-Host "[NOTE] CloudFront distribution should be managed by Terraform" -ForegroundColor Yellow
Write-Host "   To get the CloudFront URL:" -ForegroundColor Yellow
Write-Host ""
Write-Host "   cd infra\terraform\envs\dev" -ForegroundColor White
Write-Host "   terraform output frontend_hosted_url" -ForegroundColor White
Write-Host ""

# ═══════════════════════════════════════════════════════════
# 완료 및 다음 단계
# ═══════════════════════════════════════════════════════════
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "Deployment Steps Completed!" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
Write-Host ""

Write-Host "Next Steps:" -ForegroundColor Cyan
Write-Host ""
Write-Host "1. Deploy Infrastructure (if not done yet):" -ForegroundColor Yellow
Write-Host "   cd infra\terraform\envs\dev" -ForegroundColor White
Write-Host "   terraform apply" -ForegroundColor White
Write-Host ""

Write-Host "2. Get Frontend URL:" -ForegroundColor Yellow
Write-Host "   terraform output frontend_hosted_url" -ForegroundColor White
Write-Host ""

Write-Host "3. Update Cognito Callback URLs:" -ForegroundColor Yellow
Write-Host "   - Go to AWS Console → Cognito → User Pool" -ForegroundColor White
Write-Host "   - Add CloudFront URL to Callback URLs" -ForegroundColor White
Write-Host "   - Format: https://[cloudfront-domain]/auth/callback" -ForegroundColor White
Write-Host ""

Write-Host "4. Test Deployment:" -ForegroundColor Yellow
Write-Host "   Open CloudFront URL in browser" -ForegroundColor White
Write-Host ""

Write-Host "Monitoring:" -ForegroundColor Cyan
Write-Host "   Lambda Logs: aws logs tail /aws/lambda/$LAMBDA_FUNCTION_NAME --follow" -ForegroundColor White
Write-Host ""

Write-Host "Happy Deploying!" -ForegroundColor Magenta
