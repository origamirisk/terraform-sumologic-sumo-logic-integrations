# *************** Steps are as Below to create Sumo Logic CloudTrail source *************** #
# 1. Create AWS S3 Bucket. If the Bucket is created, create SNS Topic and SNS policy to attach to Bucket.
# 2. Create CloudTrail in AWS. Create CloudTrail only when the bucket is created.
# 3. Create IAM role in AWS with access to the bucket name provided.
# 4. Create a Collector. If the Collector ID is provided, do not create a Collector.
# 5. Create the source either in the collector created or in the collector id provided.
# 6. Create SNS Subscription to be attached to the source and SNS Topic.

resource "aws_s3_bucket" "s3_bucket" {
  for_each = toset(var.source_details.bucket_details.create_bucket ? ["this"] : [])

  bucket        = local.bucket_name
  force_destroy = var.source_details.bucket_details.force_destroy_bucket

  policy = templatefile("${path.module}/templates/cloudtrail_bucket_policy.tmpl", {
    BUCKET_NAME = local.bucket_name
  })
}

resource "aws_sns_topic" "sns_topic" {
  for_each = toset(local.create_sns_topic ? ["this"] : [])

  name = "SumoLogic-Terraform-CloudTrail-Module-${local.aws_account_id}"
}

resource "aws_sns_topic_policy" "sns_topic_policy" {
  for_each = toset(local.create_sns_topic ? ["this"] : [])

  arn = aws_sns_topic.sns_topic["this"].arn
  policy = templatefile("${path.module}/templates/sns_topic_policy.tmpl", {
    BUCKET_NAME   = local.bucket_name,
    SNS_TOPIC_ARN = aws_sns_topic.sns_topic["this"].arn,
    AWS_ACCOUNT   = local.aws_account_id
  })
}

resource "aws_cloudtrail" "cloudtrail" {
  for_each = toset(local.create_trail ? ["this"] : [])

  name                          = var.cloudtrail_details.name
  include_global_service_events = var.cloudtrail_details.include_global_service_events
  s3_bucket_name                = var.source_details.bucket_details.create_bucket ? aws_s3_bucket.s3_bucket["this"].id : local.bucket_name
  is_multi_region_trail         = var.cloudtrail_details.is_multi_region_trail
  is_organization_trail         = var.cloudtrail_details.is_organization_trail
}

resource "aws_iam_role" "source_iam_role" {
  for_each = toset(local.create_iam_role ? ["this"] : [])

  name = "SumoLogic-Terraform-CloudTrail-Module-${local.aws_account_id}-${local.aws_region}"
  path = "/"

  assume_role_policy = templatefile("${path.module}/templates/sumologic_assume_role.tmpl", {
    SUMO_LOGIC_ACCOUNT_ID = var.source_details.sumo_account_id,
    ENVIRONMENT           = data.sumologic_caller_identity.current.environment,
    SUMO_LOGIC_ORG_ID     = var.sumologic_organization_id
  })
}

resource "aws_iam_policy" "iam_policy" {
  for_each = toset(local.create_iam_role ? ["this"] : [])

  name = "SumoLogicCloudTrailSource-${local.aws_account_id}-${local.aws_region}"
  policy = templatefile("${path.module}/templates/sumologic_source_policy.tmpl", {
    BUCKET_NAME = local.bucket_name
  })
}

resource "aws_iam_role_policy_attachment" "policy_attachment" {
  for_each = toset(local.create_iam_role ? ["this"] : [])

  role       = aws_iam_role.source_iam_role["this"].name
  policy_arn = aws_iam_policy.iam_policy["this"].arn
}

resource "sumologic_collector" "hosted" {
  for_each    = toset(var.create_collector ? ["this"] : [])
  name        = local.collector_name
  description = var.collector_details.description
  fields      = var.collector_details.fields
  timezone    = "UTC"
}

resource "sumologic_cloudtrail_source" "source" {
  lifecycle {
    ignore_changes = [cutoff_timestamp, cutoff_relative_time]
  }
  category             = var.source_details.source_category
  collector_id         = var.create_collector ? sumologic_collector.hosted["this"].id : var.source_details.collector_id
  content_type         = "AwsCloudTrailBucket"
  cutoff_relative_time = var.source_details.cutoff_relative_time
  description          = var.source_details.description
  fields               = var.source_details.fields
  name                 = var.source_details.source_name
  paused               = var.source_details.paused
  scan_interval        = var.source_details.scan_interval
  authentication {
    type     = "AWSRoleBasedAuthentication"
    role_arn = local.create_iam_role ? aws_iam_role.source_iam_role["this"].arn : var.source_details.iam_role_arn
  }

  path {
    type            = "S3BucketPathExpression"
    bucket_name     = var.source_details.bucket_details.create_bucket ? aws_s3_bucket.s3_bucket["this"].id : local.bucket_name
    path_expression = local.logs_path_expression
  }
}

resource "aws_sns_topic_subscription" "subscription" {
  delivery_policy = jsonencode({
    "guaranteed" = false,
    "healthyRetryPolicy" = {
      "numRetries"         = 40,
      "minDelayTarget"     = 10,
      "maxDelayTarget"     = 300,
      "numMinDelayRetries" = 3,
      "numMaxDelayRetries" = 5,
      "numNoDelayRetries"  = 0,
      "backoffFunction"    = "exponential"
    },
    "sicklyRetryPolicy" = null,
    "throttlePolicy"    = null
  })
  endpoint               = sumologic_cloudtrail_source.source.url
  endpoint_auto_confirms = true
  protocol               = "https"
  topic_arn              = local.create_sns_topic ? aws_sns_topic.sns_topic["this"].arn : var.source_details.sns_topic_arn
}
