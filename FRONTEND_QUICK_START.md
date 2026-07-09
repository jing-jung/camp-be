# ⚡ 프론트엔드 배포 Quick Start

**5분 안에 프론트엔드를 Lambda + CloudFront로 배포하세요!** 🚀

---

## 🎯 자동 배포 (권장)

### Windows (PowerShell)

```powershell
# 1. 프로젝트 디렉토리로 이동
cd camp-be

# 2. 배포 스크립트 실행
.\scripts\deploy-frontend-manual.ps1

# 3. Terraform 배포
cd infra\terraform\envs\dev
terraform init -backend-config=..\..\backends\dev.hcl
terraform apply  # "yes" 입력

# 4. CloudFront URL 확인
terraform output frontend_hosted_url
```

**배포 시간:** 약 5-10분

---

## 🖱️ 수동 배포 (상세 제어)

### Step 1: Docker 이미지 빌드 및 푸시 (5분)

```powershell
cd camp-be

# ECR 로그인
aws ecr get-login-password --region ap-northeast-2 | `
    docker login --username AWS --password-stdin `
    "560271561793.dkr.ecr.ap-northeast-2.amazonaws.com"

# Docker 빌드
cd ..\camp-fe
docker build -f ..\camp-be\Dockerfile.frontend-lambda `
    -t stockbrief-dev-frontend:latest .

# ECR 푸시
docker tag stockbrief-dev-frontend:latest `
    560271561793.dkr.ecr.ap-northeast-2.amazonaws.com/stockbrief-dev-frontend:latest
docker push `
    560271561793.dkr.ecr.ap-northeast-2.amazonaws.com/stockbrief-dev-frontend:latest

cd ..\camp-be
```

### Step 2: Terraform 배포 (3분)

```powershell
cd infra\terraform\envs\dev

# 초기화 (최초 1회)
terraform init -backend-config=..\..\backends\dev.hcl

# 배포
terraform apply  # "yes" 입력
```

### Step 3: CloudFront URL 확인

```powershell
terraform output frontend_hosted_url
```

**출력 예시:** `https://d1234567890abc.cloudfront.net`

---

## 🔄 코드 업데이트 (2분)

```powershell
cd camp-be

# Docker 재빌드
cd ..\camp-fe
docker build -f ..\camp-be\Dockerfile.frontend-lambda -t stockbrief-dev-frontend:latest .
docker tag stockbrief-dev-frontend:latest 560271561793.dkr.ecr.ap-northeast-2.amazonaws.com/stockbrief-dev-frontend:latest
docker push 560271561793.dkr.ecr.ap-northeast-2.amazonaws.com/stockbrief-dev-frontend:latest

# Lambda 업데이트
cd ..\camp-be
aws lambda update-function-code `
    --function-name stockbrief-dev-frontend-lambda `
    --image-uri 560271561793.dkr.ecr.ap-northeast-2.amazonaws.com/stockbrief-dev-frontend:latest `
    --region ap-northeast-2
```

---

## ⚠️ Cognito Callback URL 설정 (필수!)

프론트엔드 배포 후 **반드시** Cognito에 URL을 등록해야 로그인이 작동합니다.

### 1. CloudFront URL 확인

```powershell
cd infra\terraform\envs\dev
terraform output frontend_hosted_url
```

### 2. AWS Console에서 설정

1. **AWS Console → Cognito → User Pools → `stockbrief-dev-userpool`**
2. **App Integration 탭 → App Clients → 클라이언트 선택**
3. **Hosted UI → Edit**

**추가할 URL:**

- **Callback URLs:**
  ```
  https://[cloudfront-url]/auth/callback
  ```

- **Sign-out URLs:**
  ```
  https://[cloudfront-url]/account
  ```

**또는 CLI로 설정:**

```powershell
$CLOUDFRONT_URL = (terraform output -raw frontend_hosted_url)

aws cognito-idp update-user-pool-client `
    --user-pool-id ap-northeast-2_MT59vnjQg `
    --client-id 3vhl76s71q3r4r53t05ms29m5f `
    --callback-urls "${CLOUDFRONT_URL}/auth/callback" "http://localhost:3000/auth/callback" `
    --logout-urls "${CLOUDFRONT_URL}/account" "http://localhost:3000/account" `
    --region ap-northeast-2
```

---

## ✅ 테스트

```powershell
# 1. 브라우저에서 CloudFront URL 열기
# https://d1234567890abc.cloudfront.net

# 2. Lambda 로그 확인
aws logs tail /aws/lambda/stockbrief-dev-frontend-lambda --follow
```

---

## 🐛 문제 해결

### ❌ Docker 빌드 실패

```powershell
cd ..\camp-fe
npm install
```

### ❌ 로그인 실패 (redirect_uri_mismatch)

→ Cognito Callback URL 설정 확인 (위 섹션 참고)

### ❌ 504 Timeout

→ `deploy.auto.tfvars.json`에서 메모리 증가:

```json
{
  "frontend_lambda_memory_mb": 3008,
  "frontend_lambda_timeout_seconds": 60
}
```

그리고 `terraform apply` 재실행.

---

## 📚 상세 문서

더 자세한 내용은 아래 문서를 참고하세요:

- 📋 [배포 체크리스트](./docs/FRONTEND_DEPLOYMENT_CHECKLIST.md)
- 📘 [수동 배포 가이드](./docs/MANUAL_FRONTEND_DEPLOYMENT.md)
- 📗 [프론트엔드 Lambda 배포 가이드](./docs/FRONTEND_LAMBDA_DEPLOYMENT.md)

---

## 💰 예상 비용

- **개발 환경 (낮은 트래픽):** ~$1-5/월
- **프로덕션 (월 100만 페이지뷰):** ~$100/월

자세한 내용은 [비용 가이드](./docs/FRONTEND_LAMBDA_DEPLOYMENT.md#-비용-예상)를 참고하세요.

---

## 🎉 완료!

프론트엔드가 성공적으로 배포되었습니다! 🚀

**다음 단계:**
- 실제 사용자 테스트
- CloudWatch 모니터링 설정
- 알림 설정

Happy Deploying! 🎊
