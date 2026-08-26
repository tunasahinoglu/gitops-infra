# gitops-infra

Terraform for the AWS infrastructure behind a GitOps deployment setup: VPC,
EKS cluster and the IAM roles the cluster needs (including IRSA for the EBS
CSI driver).

Part of a three repo GitOps project:
- **gitops-infra** (this repo) - the cluster and networking
- [gitops-config](https://github.com/tunasahinoglu/gitops-config) - Helm
  chart and ArgoCD manifests, the repo ArgoCD watches
- [gitops-app](https://github.com/tunasahinoglu/gitops-app) - the
  application and its CI pipeline

## What this creates

- A VPC with public subnets across two AZs
- An EKS cluster and a managed node group
- An OIDC provider so pods can assume IAM roles (IRSA)
- The EBS CSI driver addon, wired up via IRSA for persistent volumes

## Before running

Update `backend.tf` with your own S3 bucket name.

```bash
terraform init
terraform plan
terraform apply
```

## About `iam_policy.json`

This is the IAM policy for the AWS Load Balancer Controller. Terraform
doesn't install the controller itself. That's done separately with Helm,
once the cluster exists. This file is here so the policy can be created
and attached to the controller's IAM role as part of that setup:

```bash
aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicy \
  --policy-document file://iam_policy.json
```

`argocd-ingress.yaml` assumes the controller is installed and exposes ArgoCD
through an ALB.
