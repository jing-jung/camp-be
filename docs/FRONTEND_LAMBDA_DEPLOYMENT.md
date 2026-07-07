# Lambda Web Adapter 프론트엔드 배포 가이드

## 📋 개요

이 문서는 **Lambda Web Adapter + API Gateway** 방식으로 Next.js 프론트엔드를 서버리스 배포하는 방법을 설명합니다.

### 🎯 장점

- **💰 비용 효율**: 평상시 거의 0원, 사용량 기반 과금
- **🚀 자동 스케일링**: 트래픽 급증 시 자동으로 수천 개 인스턴스로 확장
- **⚡ 빠른 배포**: Docker 이미지 기반 간단한 배포
- **🔒 안전성**: Lambda의 격리된 실행 환경

## 🏗️ 아키텍처

```
사용자
  ↓
CloudFront (CDN)
  ↓
Lambda Function URL
  ↓
Lambda + Lambda Web Adapter
  ↓
Next.js Standalone (Node.js Server)
```

## 📦 필수 준비사항

1. **AWS CLI 설치 및 구성**
   ```bash
   aws configure
   ```

2. **Docker Desktop 설치** (Windows/Mac)
   - https://www.docker.com/products/docker-desktop

3. **Next.js standalone 출력 설정**
   
   `camp-fe/next.config.ts` 파일 확인:
   ```typescript
   const nextConfig = {
     output: 'standalone',  // 이 설정이 필요합니다!
     // ... 기타 설정
   };
   ```

## 🚀 배포 단계

### 1단계: ECR Repository 생성 (최초 1회)

```bash
aws ecr create-repository \
  --repository-name stockbrief-dev-frontend \
  --region ap-northeast-2 \
  --image-scanning-configuration scanOnPush=true \
  --encryption-configuration encryptionType=AES256
```

### 2단계: Docker 이미지 빌드 및 푸시

#### Windows (PowerShell)

```powershell
# 변수 설정
$AWS_REGION = "ap-northeast-2"
$AWS_ACCOUNT_ID = "560271561793"
$ENVIRONMENT = "dev"
$ECR_REPOSITORY = "stockbrief-$ENVIRONMENT-frontend"
$IMAGE_TAG = "latest"
$ECR_IMAGE_URI = "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/${ECR_REPOSITORY}:${IMAGE_TAG}"

# ECR 로그인
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"

# 프론트엔드 디렉토리로 이동
cd ../camp-fe

# Docker 이미지 빌드
docker build -f ../camp-be/Dockerfile.frontend-lambda -t "${ECR_REPOSITORY}:${IMAGE_TAG}" .

# ECR에 태그 및 푸시
docker tag "${ECR_REPOSITORY}:${IMAGE_TAG}" $ECR_IMAGE_URI
docker push $ECR_IMAGE_URI

# 빌드 디렉토리로 복귀
cd ../camp-be
```

#### Linux/Mac (Bash)

```bash
# 변수 설정
export AWS_REGION="ap-northeast-2"
export AWS_ACCOUNT_ID="560271561793"
export ENVIRONMENT="dev"
export ECR_REPOSITORY="stockbrief-${ENVIRONMENT}-frontend"
export IMAGE_TAG="latest"
export ECR_IMAGE_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPOSITORY}:${IMAGE_TAG}"

# ECR 로그인
aws ecr get-login-password --region "${AWS_REGION}" | \
  docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

# 프론트엔드 디렉토리로 이동
cd ../camp-fe

# Docker 이미지 빌드
docker build -f ../camp-be/Dockerfile.frontend-lambda -t "${ECR_REPOSITORY}:${IMAGE_TAG}" .

# ECR에 태그 및 푸시
docker tag "${ECR_REPOSITORY}:${IMAGE_TAG}" "${ECR_IMAGE_URI}"
docker push "${ECR_IMAGE_URI}"

# 빌드 디렉토리로 복귀
cd ../camp-be
```

또는 스크립트 실행:
```bash
./scripts/deploy_frontend_lambda.sh
```

### 3단계: Terraform으로 인프라 배포

```bash
cd infra/terraform/envs/dev

# 초기화 (최초 1회)
terraform init -backend-config=../../backends/dev.hcl

# 변경사항 확인
terraform plan

# 배포
terraform apply
```

### 4단계: CloudFront URL 확인

```bash
terraform output frontend_hosted_url
```

출력 예시:
```
https://d1234567890abc.cloudfront.net
```

이 URL로 프론트엔드에 접근할 수 있습니다!

## 🔄 업데이트 배포

코드를 수정한 후:

1. **Docker 이미지만 재빌드 및 푸시** (2단계)
2. **Lambda 함수 자동 업데이트**
   ```bash
   aws lambda update-function-code \
     --function-name stockbrief-dev-frontend-lambda \
     --image-uri $ECR_IMAGE_URI \
     --region ap-northeast-2
   ```

Terraform apply는 인프라 변경이 있을 때만 필요합니다.

## 📊 모니터링

### CloudWatch Logs 확인

```bash
aws logs tail /aws/lambda/stockbrief-dev-frontend-lambda --follow
```

### Lambda 메트릭 확인

AWS Console → Lambda → stockbrief-dev-frontend-lambda → Monitoring

- Invocations (호출 횟수)
- Duration (실행 시간)
- Errors (에러 발생)
- Concurrent executions (동시 실행 수)

## 💰 비용 예상

### Lambda 비용 (ap-northeast-2 기준)

- **요청**: $0.20 per 1M requests
- **실행 시간**: $0.0000166667 per GB-second
- **무료 티어**: 
  - 월 1M requests
  - 월 400,000 GB-seconds

### 예시 계산

**월 10만 페이지뷰, 평균 응답시간 500ms, 2GB 메모리 사용:**

```
요청 비용 = (100,000 - 1,000,000) × $0.20 / 1,000,000 = $0 (무료 티어)
실행 비용 = 100,000 × 0.5s × 2GB × $0.0000166667 = $1.67
총 비용 ≈ $1.67/월
```

**월 100만 페이지뷰:**
```
요청 비용 = 0 (무료 티어 내)
실행 비용 = 1,000,000 × 0.5s × 2GB × $0.0000166667 = $16.67
총 비용 ≈ $16.67/월
```

### CloudFront 비용

- **데이터 전송**: 
  - 첫 10TB: $0.085/GB (ap-northeast-2)
  - HTTPS 요청: $0.0125 per 10,000 requests

**월 100만 페이지뷰, 평균 페이지 크기 1MB:**
```
데이터 전송 = 1,000,000 × 1MB = 1TB
전송 비용 = 1,000 × $0.085 = $85
요청 비용 = 1,000,000 / 10,000 × $0.0125 = $1.25
총 비용 ≈ $86.25/월
```

**전체 예상 비용 (월 100만 페이지뷰)**: ~$103/월

## 🔧 트러블슈팅

### 1. Docker 빌드 실패

**증상**: `Error: Cannot find module 'next'`

**해결**:
```bash
# camp-fe 디렉토리에서
npm install
# 또는
pnpm install
```

### 2. Lambda 함수 타임아웃

**증상**: 504 Gateway Timeout

**해결**: `deploy.auto.tfvars.json`에서 타임아웃 증가
```json
"frontend_lambda_timeout_seconds": 60
```

### 3. 메모리 부족

**증상**: Lambda 로그에 "Process exited before completing request"

**해결**: `deploy.auto.tfvars.json`에서 메모리 증가
```json
"frontend_lambda_memory_mb": 3008
```

### 4. Cold Start 지연

**증상**: 첫 요청이 느림 (5-10초)

**해결책**:
- Lambda SnapStart 사용 (Node.js 20 미지원)
- Provisioned Concurrency 설정 (비용 증가)
- 워밍 함수 구현 (EventBridge로 주기적 호출)

## 📝 설정 파일 요약

### `deploy.auto.tfvars.json`

```json
{
  "enable_frontend_lambda": true,
  "enable_frontend_cloudfront_lambda": true,
  "frontend_container_image": "560271561793.dkr.ecr.ap-northeast-2.amazonaws.com/stockbrief-dev-frontend",
  "frontend_image_tag": "latest",
  "frontend_lambda_memory_mb": 2048,
  "frontend_lambda_timeout_seconds": 30,
  "frontend_lambda_reserved_concurrent_executions": -1
}
```

### 주요 설정 설명

- `enable_frontend_lambda`: Lambda 기반 프론트엔드 활성화
- `enable_frontend_cloudfront_lambda`: CloudFront 배포 활성화
- `frontend_lambda_memory_mb`: Lambda 메모리 (최소 512MB, 권장 2048MB)
- `frontend_lambda_timeout_seconds`: Lambda 타임아웃 (최대 900초)
- `reserved_concurrent_executions`: -1 = 무제한 오토스케일링

## 🎓 Lambda Web Adapter 작동 원리

Lambda Web Adapter는 일반적인 웹 서버(Node.js, Python Flask/Django 등)를 Lambda에서 실행할 수 있게 해주는 레이어입니다.

1. Lambda가 시작되면 Lambda Web Adapter가 먼저 실행됩니다
2. Adapter가 `server.js` (Next.js standalone)를 실행합니다
3. HTTP 요청이 들어오면:
   - Lambda Function URL → Lambda Web Adapter
   - Adapter → localhost:3000 (Next.js 서버)
   - Next.js 서버 → 응답 생성
   - Adapter → Lambda Function URL

이를 통해 **기존 Next.js 코드를 수정하지 않고** Lambda에서 실행할 수 있습니다!

## 📚 참고 자료

- [AWS Lambda Web Adapter](https://github.com/awslabs/aws-lambda-web-adapter)
- [Next.js Standalone Output](https://nextjs.org/docs/pages/api-reference/next-config-js/output)
- [Lambda Function URLs](https://docs.aws.amazon.com/lambda/latest/dg/lambda-urls.html)
- [CloudFront with Lambda Function URLs](https://aws.amazon.com/blogs/compute/using-cloudfront-with-lambda-function-urls/)

## 🤝 문의

배포 중 문제가 발생하면:
1. CloudWatch Logs 확인
2. Terraform 에러 메시지 확인
3. 이슈 등록 또는 팀에 문의
