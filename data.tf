# Retrieve IAM policy documents for assuming roles.  This is used to feed exclusive inline policies.

# Create an IAM policy document for assumed roles for ECS service.
data "aws_iam_policy_document" "ecs_service_role_pd" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs.amazonaws.com", "ecs-tasks.amazonaws.com"]
    }
  }
}

# Get the AccountId
data "aws_caller_identity" "current" {}

# Create an IAM policy document for assumed roles for EC2.
data "aws_iam_policy_document" "ec2_role_pd" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs.amazonaws.com", "ec2.amazonaws.com", "dynamodb.amazonaws.com", "ecs-tasks.amazonaws.com"]
    }
  }
}