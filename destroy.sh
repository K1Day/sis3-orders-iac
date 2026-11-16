#!/usr/bin/env bash
# Delete everything for one environment:  ./destroy.sh <env>
set -euo pipefail

ENV_NAME="${1:-dev}"
REGION="${AWS_REGION:-us-east-1}"
PREFIX="sis3-${ENV_NAME}"

echo "== Deleting ${PREFIX}-app (ECS, ALB, VPC, SNS, SQS, Lambda, DynamoDB, logs) ..."
aws cloudformation delete-stack --region "$REGION" --stack-name "${PREFIX}-app"
aws cloudformation wait stack-delete-complete --region "$REGION" --stack-name "${PREFIX}-app"

echo "== Deleting ${PREFIX}-ecr (repository + images) ..."
aws cloudformation delete-stack --region "$REGION" --stack-name "${PREFIX}-ecr"
aws cloudformation wait stack-delete-complete --region "$REGION" --stack-name "${PREFIX}-ecr"

echo "== Done. Nothing left for env '${ENV_NAME}'."
