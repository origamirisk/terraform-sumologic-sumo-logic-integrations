terraform {
  required_version = ">= 0.13.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 3.42.0"
    }
    sumologic = {
      version = ">= 2.9.0"
      source  = "SumoLogic/sumologic"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.1.0"
    }
  }
}