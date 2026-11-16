#!/usr/bin/env bash
# One command deploy:  ./deploy.sh <env>     e.g. ./deploy.sh dev  or  ./deploy.sh defence
# 1) ECR stack  2) build + push image tagged with the git SHA  3) app stack
set -euo pipefail

ENV_NAME="${1:-dev}"
if [[ ! "$ENV_NAME" =~ ^[a-z0-9-]{2,12}$ ]]; then
  echo "Env name must be lowercase letters/digits/-, 2-12 chars (got: $ENV_NAME)"; exit 1
fi

REGION="${AWS_REGION:-us-east-1}"
PREFIX="sis3-${ENV_NAME}"
ECR_STACK="${PREFIX}-ecr"
APP_STACK="${PREFIX}-app"
cd "$(dirname "$0")"

echo "== [1/3] ECR repository stack: $ECR_STACK"
aws cloudformation deploy --region "$REGION" \
  --stack-name "$ECR_STACK" \
  --template-file infra/ecr.yaml \
  --no-fail-on-empty-changeset

REPO_URI=$(aws cloudformation describe-stacks --region "$REGION" --stack-name "$ECR_STACK" \
  --query "Stacks[0].Outputs[?OutputKey=='RepositoryUri'].OutputValue" --output text)
REPO_NAME="${REPO_URI#*/}"

# immutable tag = short git commit SHA (falls back to a timestamp if not a git repo)
TAG=$(git rev-parse --short HEAD 2>/dev/null || date -u +%Y%m%d%H%M%S)
IMAGE="${REPO_URI}:${TAG}"

echo "== [2/3] Image: $IMAGE"
if aws ecr describe-images --region "$REGION" --repository-name "$REPO_NAME" \
     --image-ids imageTag="$TAG" >/dev/null 2>&1; then
  echo "Tag $TAG already in ECR (tags are immutable) - skipping build/push"
else
  aws ecr get-login-password --region "$REGION" \
    | docker login --username AWS --password-stdin "${REPO_URI%%/*}"
  docker build --platform linux/amd64 -t "$IMAGE" app/
  docker push "$IMAGE"
fi

echo "== [3/3] App stack: $APP_STACK (takes ~5-8 min the first time)"
aws cloudformation deploy --region "$REGION" \
  --stack-name "$APP_STACK" \
  --template-file infra/app.yaml \
  --capabilities CAPABILITY_IAM \
  --parameter-overrides EnvName="$ENV_NAME" ImageUri="$IMAGE" \
  --no-fail-on-empty-changeset

echo
echo "== Done. Outputs:"
aws cloudformation describe-stacks --region "$REGION" --stack-name "$APP_STACK" \
  --query "Stacks[0].Outputs[].[OutputKey,OutputValue]" --output table
