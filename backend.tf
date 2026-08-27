terraform {
  backend "s3" {
    bucket = "tuna-gitops-tfstate"
    key    = "eks/terraform.tfstate"
    region = "us-east-1"
  }
}