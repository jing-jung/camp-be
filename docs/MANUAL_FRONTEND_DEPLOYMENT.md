# 🚀 프론트엔드 수동 배포 가이드

이 문서는 프론트엔드를 **수동으로 단계별 배포**하는 방법을 설명합니다.

## 📋 배포 계획

1. ✅ Lambda 함수 생성 (ECR 이미지 사용)
2. ✅ Lambda Function URL 활성화
3. ✅ CloudFront 배포 (선택 사항)
4. ✅ Cognito Callback URL 업데이트

---

## 🎯 배포 방식 선택

### Option A: 자동 스크립트 (권장) ⭐

```powershell
cd camp-be
.\scripts\deploy-frontend-manual.ps1
```

### Option B: 수동 단계별 배포

아래 단계를 순서대로 진행합니다.

---

## 📦 사전 준비

### 1. AWS CLI 로그인 확인

```powershell
aws sts get-caller-identity
```

예상 출력:
```json
{
    "UserId": "...",
    "Account": "560271561793",
    "Arn": "arn:aws:iam::560271561793:user/..."
}
```

### 2. Docker Desktop 실행 확인

```powershell
docker version
```

### 3. 프론트엔드 프로젝트 확인

```powershell
# camp-be 디렉토리에서 실행
ls ..\camp-fe
```

`package.json`, `next.config.ts` 등이 있어야 합니다.

### 4. Next.js Standalone 출력 설정 확인

`camp-fe/next.config.ts` 파일에 다음 설정이 있는지 확인:

```typescript
const nextConfig = {
  output: 'standalone',  // ✅ 이 설정이 필요!
  // ... 기타 설정
};
```

---

## 🚀 배포 단계

### Step 1: ECR Repository 생성 (최초 1회만)

```powershell
# 변수 설정
$AWS_REGION = "ap-northeast-2"
$AWS_ACCOUNT_ID = "560271561793"
$ENVIRONMENT = "dev"
$ECR_REPOSITORY = "stockbrief-$ENVIRONMENT-frontend"

# ECR Repository 확인
aws ecr describe-repositories --repository-names $ECR_REPOSITORY --region $AWS_REGION
```

**리포지토리가 없다면 생성:**

```powershell
aws ecr create-repository `
    --repository-name $ECR_REPOSITORY `
    --region $AWS_REGION `
    --image-scanning-configuration scanOnPush=true `
    --encryption-configuration encryptionType=AES256
```

예상 출력:
```json
{
    "repository": {
        "repositoryArn": "arn:aws:ecr:ap-northeast-2:560271561793:repository/stockbrief-dev-frontend",
        "repositoryName": "stockbrief-dev-frontend",
        "repositoryUri": "560271561793.dkr.ecr.ap-northeast-2.amazonaws.com/stockbrief-dev-frontend"
    }
}
```

---

### Step 2: Docker 이미지 빌드 및 ECR 푸시

#### 2.1 ECR 로그인

```powershell
$AWS_REGION = "ap-northeast-2"
$AWS_ACCOUNT_ID = "560271561793"

aws ecr get-login-password --region $AWS_REGION | `
    docker login --username AWS --password-stdin `
    "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"
```

**성공 시:** `Login Succeeded`

#### 2.2 Docker 이미지 빌드

```powershell
$ENVIRONMENT = "dev"
$ECR_REPOSITORY = "stockbrief-$ENVIRONMENT-frontend"
$IMAGE_TAG = "latest"

# 프론트엔드 디렉토리로 이동
cd ..\camp-fe

# Docker 빌드 (camp-be의 Dockerfile 사용)
docker build -f ..\camp-be\Dockerfile.frontend-lambda -t "${ECR_REPOSITORY}:${IMAGE_TAG}" .
```

**빌드 시간:** 약 2-5분 (첫 빌드)

#### 2.3 ECR에 이미지 푸시

```powershell
$AWS_REGION = "ap-northeast-2"
$AWS_ACCOUNT_ID = "560271561793"
$ECR_IMAGE_URI = "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/${ECR_REPOSITORY}:${IMAGE_TAG}"

# 이미지 태그
docker tag "${ECR_REPOSITORY}:${IMAGE_TAG}" $ECR_IMAGE_URI

# ECR에 푸시
docker push $ECR_IMAGE_URI
```

**푸시 시간:** 약 1-3분

#### 2.4 프로젝트 루트로 복귀

```powershell
cd ..\camp-be
```

---

### Step 3: Terraform으로 Lambda 함수 생성

#### 3.1 Terraform 설정 확인

`camp-be/infra/terraform/envs/dev/deploy.auto.tfvars.json` 파일 확인:

```json
{
  "enable_frontend_lambda": true,
  "enable_frontend_cloudfront_lambda": true,
  "frontend_container_image": "560271561793.dkr.ecr.ap-northeast-2.amazonaws.com/stockbrief-dev-frontend",
  "frontend_image_tag": "latest",
  "frontend_lambda_memory_mb": 2048,
  "frontend_lambda_timeout_seconds": 30
}
```

#### 3.2 Terraform 배포

```powershell
cd infra\terraform\envs\dev

# 초기화 (최초 1회)
terraform init -backend-config=..\..\backends\dev.hcl

# 변경사항 미리보기
terraform plan

# 배포
terraform apply
```

**확인 메시지:** `Do you want to perform these actions?` → `yes` 입력

**배포 시간:** 약 2-5분

#### 3.3 Lambda 함수 확인

```powershell
aws lambda get-function --function-name stockbrief-dev-frontend-lambda --region ap-northeast-2
```

---

### Step 4: Lambda Function URL 확인

Lambda Function URL은 Terraform이 자동으로 생성합니다.

```powershell
aws lambda get-function-url-config `
    --function-name stockbrief-dev-frontend-lambda `
    --region ap-northeast-2
```

예상 출력:
```json
{
    "FunctionUrl": "https://abcd1234efgh.lambda-url.ap-northeast-2.on.aws/",
    "AuthType": "NONE",
    "CreationTime": "2024-01-15T10:30:00.000Z"
}
```

**또는 Terraform 출력으로 확인:**

```powershell
# infra/terraform/envs/dev 디렉토리에서
terraform output frontend_lambda_function_url
```

---

### Step 5: CloudFront 배포 (선택 사항, 권장)

CloudFront는 CDN을 제공하여 전 세계에서 빠른 액세스를 보장합니다.

#### 5.1 CloudFront URL 확인

```powershell
# infra/terraform/envs/dev 디렉토리에서
terraform output frontend_hosted_url
```

예상 출력:
```
https://d1234567890abc.cloudfront.net
```

#### 5.2 CloudFront 배포 상태 확인 (선택)

```powershell
# CloudFront Distribution ID 가져오기
$DISTRIBUTION_ID = (terraform output -raw frontend_cloudfront_distribution_id)

# 배포 상태 확인
aws cloudfront get-distribution --id $DISTRIBUTION_ID --region us-east-1
```

**Status가 `Deployed`일 때 사용 가능합니다.**

---

### Step 6: Cognito Callback URL 업데이트 ⚠️ **중요!**

프론트엔드 배포 후 Cognito에 새로운 URL을 등록해야 로그인이 작동합니다.

#### 6.1 CloudFront URL 확인

```powershell
terraform output frontend_hosted_url
```

예: `https://d1234567890abc.cloudfront.net`

#### 6.2 AWS Console에서 Cognito 설정

1. **AWS Console → Cognito → User Pools**
2. **User Pool 선택:** `stockbrief-dev-userpool`
3. **App Integration 탭**
4. **App Clients → 클라이언트 선택**
5. **Hosted UI 섹션 편집**

**추가할 URL:**

- **Callback URLs:**
  ```
  https://d1234567890abc.cloudfront.net/auth/callback
  ```

- **Sign-out URLs:**
  ```
  https://d1234567890abc.cloudfront.net/account
  ```

#### 6.3 CLI로 업데이트 (대안)

```powershell
$USER_POOL_ID = "ap-northeast-2_MT59vnjQg"
$CLIENT_ID = "3vhl76s71q3r4r53t05ms29m5f"
$CLOUDFRONT_URL = "https://d1234567890abc.cloudfront.net"

aws cognito-idp update-user-pool-client `
    --user-pool-id $USER_POOL_ID `
    --client-id $CLIENT_ID `
    --callback-urls "${CLOUDFRONT_URL}/auth/callback" "http://localhost:3000/auth/callback" `
    --logout-urls "${CLOUDFRONT_URL}/account" "http://localhost:3000/account" `
    --region ap-northeast-2
```

---

## ✅ 배포 완료 확인

### 1. 프론트엔드 접속 테스트

브라우저에서 CloudFront URL 열기:

```
https://d1234567890abc.cloudfront.net
```

### 2. Health Check (선택)

Lambda Function URL로 직접 접근:

```powershell
$FUNCTION_URL = (terraform output -raw frontend_lambda_function_url)
curl $FUNCTION_URL
```

### 3. Lambda 로그 확인

```powershell
aws logs tail /aws/lambda/stockbrief-dev-frontend-lambda --follow --region ap-northeast-2
```

**로그 예시:**
```
[INFO] Lambda started
[INFO] Next.js server listening on port 3000
[INFO] Request received: GET /
[INFO] Response sent: 200
```

---

## 🔄 코드 업데이트 배포

프론트엔드 코드를 수정한 후:

### 빠른 업데이트 (Step 2만 반복)

```powershell
# 1. Docker 이미지 재빌드 및 푸시
cd ..\camp-fe
docker build -f ..\camp-be\Dockerfile.frontend-lambda -t "stockbrief-dev-frontend:latest" .
docker tag "stockbrief-dev-frontend:latest" "560271561793.dkr.ecr.ap-northeast-2.amazonaws.com/stockbrief-dev-frontend:latest"
docker push "560271561793.dkr.ecr.ap-northeast-2.amazonaws.com/stockbrief-dev-frontend:latest"

# 2. Lambda 함수 코드 업데이트
cd ..\camp-be
aws lambda update-function-code `
    --function-name stockbrief-dev-frontend-lambda `
    --image-uri "560271561793.dkr.ecr.ap-northeast-2.amazonaws.com/stockbrief-dev-frontend:latest" `
    --region ap-northeast-2
```

**업데이트 시간:** 약 2-5분

### Lambda 업데이트 상태 확인

```powershell
aws lambda get-function --function-name stockbrief-dev-frontend-lambda --region ap-northeast-2 --query 'Configuration.LastUpdateStatus' --output text
```

**출력이 `Successful`이면 완료**

---

## 📊 모니터링 및 디버깅

### CloudWatch Logs 실시간 확인

```powershell
aws logs tail /aws/lambda/stockbrief-dev-frontend-lambda --follow --region ap-northeast-2
```

### Lambda 메트릭 확인

```powershell
# 최근 1시간 호출 횟수
aws cloudwatch get-metric-statistics `
    --namespace AWS/Lambda `
    --metric-name Invocations `
    --dimensions Name=FunctionName,Value=stockbrief-dev-frontend-lambda `
    --start-time (Get-Date).AddHours(-1).ToString("yyyy-MM-ddTHH:mm:ss") `
    --end-time (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss") `
    --period 3600 `
    --statistics Sum `
    --region ap-northeast-2
```

### CloudFront 캐시 무효화 (필요 시)

```powershell
$DISTRIBUTION_ID = (terraform output -raw frontend_cloudfront_distribution_id)

aws cloudfront create-invalidation `
    --distribution-id $DISTRIBUTION_ID `
    --paths "/*"
```

---

## 🐛 트러블슈팅

### ❌ "ECR repository not found"

**해결:** Step 1 재실행

```powershell
aws ecr create-repository `
    --repository-name stockbrief-dev-frontend `
    --region ap-northeast-2
```

### ❌ Docker build 실패 - "Cannot find module 'next'"

**원인:** Next.js 의존성 미설치

**해결:**
```powershell
cd ..\camp-fe
npm install
# 또는
pnpm install
```

### ❌ Lambda 함수 404 Not Found

**원인:** Terraform 배포 미완료

**해결:** Step 3 재실행

### ❌ 로그인 실패 - "redirect_uri_mismatch"

**원인:** Cognito Callback URL 미등록

**해결:** Step 6 재실행

### ❌ 504 Gateway Timeout

**원인:** Lambda 메모리 부족 또는 Cold Start

**해결:** `deploy.auto.tfvars.json`에서 메모리 증가

```json
{
  "frontend_lambda_memory_mb": 3008,
  "frontend_lambda_timeout_seconds": 60
}
```

그리고 `terraform apply` 재실행.

---

## 💰 예상 비용

### 개발 환경 (낮은 트래픽)

- **Lambda**: 무료 티어 내 (~$0/월)
- **CloudFront**: ~$1-5/월
- **ECR 스토리지**: ~$0.10/월
- **총 예상 비용**: ~$1-5/월

### 프로덕션 (월 100만 페이지뷰)

- **Lambda**: ~$17/월
- **CloudFront**: ~$85/월
- **ECR**: ~$0.10/월
- **총 예상 비용**: ~$102/월

자세한 비용 계산은 [FRONTEND_LAMBDA_DEPLOYMENT.md](./FRONTEND_LAMBDA_DEPLOYMENT.md#-비용-예상)를 참고하세요.

---

## 📚 관련 문서

- [프론트엔드 Lambda 배포 가이드](./FRONTEND_LAMBDA_DEPLOYMENT.md) - 상세 기술 문서
- [Lambda Web Adapter 마이그레이션](./LAMBDA_WEB_ADAPTER_MIGRATION.md)
- [전체 배포 가이드](./DEPLOYMENT_GUIDE.md)

---

## 🎉 배포 완료!

축하합니다! 🎊 프론트엔드가 성공적으로 배포되었습니다.

**다음 단계:**

1. ✅ CloudFront URL 브라우저에서 확인
2. ✅ 로그인/로그아웃 테스트
3. ✅ 주요 기능 동작 확인
4. ✅ CloudWatch 로그 모니터링 설정

**문제가 발생하면:**
- CloudWatch Logs 확인
- 이 문서의 트러블슈팅 섹션 참고
- GitHub Issues에 문의

Happy Deploying! 🚀
