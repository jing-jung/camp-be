#!/bin/bash
# Lambda Web Adapter 기반 프론트엔드 배포 스크립트

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# 기본 변수
AWS_REGION="${AWS_REGION:-ap-northeast-2}"
# 터미널에 설정된 AWS 인증 정보를 이용해 자동으로 계정 ID를 가져옵니다.
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}"
ENVIRONMENT="${ENVIRONMENT:-dev}"
ECR_REPOSITORY="stockbrief-${ENVIRONMENT}-frontend"
IMAGE_TAG="${IMAGE_TAG:-latest}"

echo "🚀 Lambda Web Adapter 프론트엔드 배포 시작"
echo "  - Region: ${AWS_REGION}"
echo "  - Account: ${AWS_ACCOUNT_ID}"
echo "  - Environment: ${ENVIRONMENT}"
echo "  - ECR Repository: ${ECR_REPOSITORY}"
echo "  - Image Tag: ${IMAGE_TAG}"
echo ""

# ECR 로그인
echo "📦 ECR 로그인 중..."
aws ecr get-login-password --region "${AWS_REGION}" | \
  docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

# ECR Repository 존재 확인 및 생성
echo "🔍 ECR Repository 확인 중..."
if ! aws ecr describe-repositories --repository-names "${ECR_REPOSITORY}" --region "${AWS_REGION}" &>/dev/null; then
  echo "  ⚠️  Repository가 없습니다. 생성 중..."
  aws ecr create-repository \
    --repository-name "${ECR_REPOSITORY}" \
    --region "${AWS_REGION}" \
    --image-scanning-configuration scanOnPush=true \
    --encryption-configuration encryptionType=AES256
  echo "  ✅ Repository 생성 완료"
else
  echo "  ✅ Repository 존재 확인"
fi

# Docker 이미지 빌드
echo ""
echo "🔨 Docker 이미지 빌드 중..."
FRONTEND_DIR="${PROJECT_ROOT}/../camp-fe"
cd "${FRONTEND_DIR}"

docker build \
  -f "${PROJECT_ROOT}/Dockerfile.frontend-lambda" \
  -t "${ECR_REPOSITORY}:${IMAGE_TAG}" \
  .

# ECR에 태그 및 푸시
echo ""
echo "📤 ECR에 이미지 푸시 중..."
ECR_IMAGE_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPOSITORY}:${IMAGE_TAG}"
docker tag "${ECR_REPOSITORY}:${IMAGE_TAG}" "${ECR_IMAGE_URI}"
docker push "${ECR_IMAGE_URI}"

echo ""
echo "✅ 이미지 푸시 완료: ${ECR_IMAGE_URI}"
echo ""

# Lambda 함수 업데이트 (존재하는 경우)
LAMBDA_FUNCTION_NAME="stockbrief-${ENVIRONMENT}-frontend-lambda"
echo "🔄 Lambda 함수 업데이트 확인 중..."
if aws lambda get-function --function-name "${LAMBDA_FUNCTION_NAME}" --region "${AWS_REGION}" &>/dev/null; then
  echo "  📦 Lambda 함수 이미지 업데이트 중..."
  aws lambda update-function-code \
    --function-name "${LAMBDA_FUNCTION_NAME}" \
    --image-uri "${ECR_IMAGE_URI}" \
    --region "${AWS_REGION}" \
    --no-cli-pager
  
  echo "  ⏳ Lambda 함수 업데이트 대기 중..."
  aws lambda wait function-updated \
    --function-name "${LAMBDA_FUNCTION_NAME}" \
    --region "${AWS_REGION}"
  
  echo "  ✅ Lambda 함수 업데이트 완료"
else
  echo "  ⚠️  Lambda 함수가 아직 생성되지 않았습니다."
  echo "  👉 Terraform apply를 먼저 실행해주세요."
fi

echo ""
echo "🎉 배포 완료!"
echo ""
echo "다음 단계:"
echo "  1. Terraform apply로 인프라 생성/업데이트:"
echo "     cd ${PROJECT_ROOT}/infra/terraform/envs/dev"
echo "     terraform apply"
echo ""
echo "  2. CloudFront URL 확인:"
echo "     terraform output frontend_hosted_url"
