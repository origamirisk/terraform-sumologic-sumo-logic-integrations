data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

data "sumologic_caller_identity" "current" {}

# data "aws_serverlessapplicationrepository_application" "app" {
#   application_id   = "arn:aws:serverlessrepo:us-east-1:956882708938:applications/sumologic-loggroup-connector"
#   semantic_version = "1.0.11"
# }
