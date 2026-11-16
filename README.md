# SIS 3 — Orders system as code (AWS CloudFormation)

Everything from weeks 9–10 rebuilt as code: a container API on **ECS Fargate behind an ALB**
publishes a `PaymentReceived` event to **SNS** → **SQS** queue (with **DLQ**) →
**idempotent Lambda** consumer → **DynamoDB**. No console clicks, no secrets in the repo.

```
client ─HTTP─> ALB ─> ECS Fargate (api) ─sns:Publish─> SNS topic
                                                          │ raw delivery
                                                          ▼
                     DynamoDB <─ Lambda (idempotent) <─ SQS queue ──5 fails──> DLQ
```

## Deploy (one command)

Run in AWS CloudShell (it already has AWS CLI, Docker and git):

```bash
git clone <this-repo-url> sis3 && cd sis3
chmod +x deploy.sh destroy.sh
./deploy.sh dev
```

The script deploys 2 stacks: `sis3-<env>-ecr` (repository) and `sis3-<env>-app` (everything else).
The image tag is the git commit SHA. At the end it prints `ServiceUrl`.

A second, independent copy (reproducibility test): `./deploy.sh defence`

## Test

```bash
URL=<ServiceUrl from the outputs>
curl $URL                                   # service info + version (= git SHA)
curl -X POST $URL/payments -H 'Content-Type: application/json' \
  -d '{"paymentId":"p-1","account":"acc-1","amount":100}'
# send the same paymentId again -> balance does NOT change (DUPLICATE_SKIPPED in Lambda logs)
curl -X POST $URL/payments -H 'Content-Type: application/json' \
  -d '{"paymentId":"p-2","account":"acc-1","amount":5,"poison":true}'
# poison -> fails 5 times -> lands in the DLQ
```

## Clean up

```bash
./destroy.sh dev
./destroy.sh defence
```

## What is where

| Requirement | Where in code |
|---|---|
| SQS + DLQ, maxReceiveCount | `infra/app.yaml` → `PaymentsQueue`, `PaymentsDlq` (maxReceiveCount 5) |
| Domain event | `PaymentEventsTopic` (SNS), published by `app/app.py` on `POST /payments` |
| Idempotent consumer | `ConsumerFunction` — dedup key `paymentId`, conditional write in a transaction |
| ECR immutable tags + lifecycle | `infra/ecr.yaml` (IMMUTABLE, untagged expire 1 day, keep last 20) |
| ECS Fargate behind ALB | `Service`, `LoadBalancer`, `TargetGroup` (type ip), circuit breaker with rollback |
| Two roles | `ExecutionRole` (pull image, write logs) and `TaskRole` (only `sns:Publish` to this topic) |
| Logs with retention | `ApiLogGroup`, `ConsumerLogGroup` (`LogRetentionDays`, default 3) |
| Parameters, no secrets | `EnvName`, `ImageUri`, `DesiredCount`, `LogRetentionDays`; no keys in code |

## Prerequisites (one time)

The IAM user needs permissions for CloudFormation, IAM (create roles), EC2/VPC, ELB, ECS, ECR,
SNS, SQS, Lambda, DynamoDB and CloudWatch Logs (simplest for a lab account: `AdministratorAccess`).
Region: `us-east-1` (change with `export AWS_REGION=...`).

Cost: ~$0.03–0.05/hour while running (ALB + 1 small Fargate task). Run `destroy.sh` after the demo.
