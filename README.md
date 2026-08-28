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

## After `terraform apply`

Terraform only creates the cluster itself. A few things run on top of it,
installed separately since they're cluster add-ons and not infrastructure:

**Storage class.** No default StorageClass exists yet, so PVCs stay pending
until one is created:

```bash
cat << 'EOF' | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: ebs.csi.aws.com
volumeBindingMode: WaitForFirstConsumer
parameters:
  type: gp3
EOF
```

**AWS Load Balancer Controller.** Needed before any Ingress works:

```bash
aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicy \
  --policy-document file://iam_policy.json

eksctl utils associate-iam-oidc-provider --cluster gitops-eks-cluster --region us-east-1 --approve

eksctl create iamserviceaccount \
  --cluster gitops-eks-cluster --region us-east-1 --namespace kube-system \
  --name aws-load-balancer-controller --role-name AmazonEKSLoadBalancerControllerRole \
  --attach-policy-arn arn:aws:iam::<ACCOUNT_ID>:policy/AWSLoadBalancerControllerIAMPolicy --approve

helm repo add eks https://aws.github.io/eks-charts
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system --set clusterName=gitops-eks-cluster \
  --set serviceAccount.create=false --set serviceAccount.name=aws-load-balancer-controller \
  --set region=us-east-1 --set vpcId=<VPC_ID>
```

**ArgoCD.** Watches `gitops-config` and deploys the app:

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl apply -f argocd-ingress.yaml
```

**SonarQube.** Runs in-cluster rather than on a separate EC2 instance:

```bash
helm repo add sonarqube https://SonarSource.github.io/helm-chart-sonarqube
helm install sonarqube sonarqube/sonarqube -n sonarqube --create-namespace \
  --set community.enabled=true --set persistence.enabled=true
```

## About `iam_policy.json`

This is the IAM policy for the AWS Load Balancer Controller, used in the
`eksctl create iamserviceaccount` step above.

`argocd-ingress.yaml` assumes the controller is installed and exposes ArgoCD
through an ALB.

## Cleanup

Delete the Ingresses before running `terraform destroy`. Their ALBs aren't
tracked by Terraform, so destroying the VPC first can leave them orphaned:

```bash
kubectl delete ingress accounts-ingress -n accounts
kubectl delete ingress argocd-ingress -n argocd
```

Then:

```bash
terraform destroy
```