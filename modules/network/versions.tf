terraform {
  # 1.6 is where `terraform test` and mock providers arrived, and the test
  # suite is the only way this repository is verified — see the README.
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
