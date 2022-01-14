## IAM Policies and Roles ##
locals {
  account_id = "${data.aws_caller_identity.current.account_id}"
}



resource "aws_iam_role" "ecsTaskExecutionRole" {
  name                = "ec2_role"
  path                = "/"
  assume_role_policy  = data.aws_iam_policy_document.ecs_service_role_pd.json
  managed_policy_arns = ["arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"]

  inline_policy {
    name = "dynamo-access"

    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Action = [
            "logs:CreateLogStream",
            "logs:PutLogEvents",
            "dynamodb:Query",
            "dynamodb:Scan",
            "dynamodb:GetItem",
            "dynamodb:PutItem",
            "dynamodb:UpdateItem",
            "dynamodb:DeleteItem"
          ]
          Effect   = "Allow"
          Resource = [
            "arn:aws:logs:us-east-1:${local.account_id}:*/*",
            "arn:aws:dynamodb:us-east-1:${local.account_id}:*/*"
          ]
        }
      ]
    })
  }

  inline_policy {
    name = "ECS-SecretsManager-Permission"

    policy = jsonencode({
      "Version": "2012-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Action": [
            "kms:Decrypt",
            "secretsmanager:GetSecretValue"
          ],
          "Resource": [
            "arn:aws:secretsmanager:us-east-1:12345678909:secret:dev/DockerHubSecrets-abCdef",
            "arn:aws:kms:us-east-1:12345678909:key/1234abcd-12ab-12ab-12ab-12345678909"     
          ]
        }
      ]
    })
  }
}

# Create a VPC.
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = var.vpc_dns_support
  enable_dns_hostnames = var.vpc_dns_hostnames
  tags = {
    Name = "terraform"
  }
}

# Create an Internet Gateway.
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
}

# Create the first public subnet in the VPC for external traffic.
resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_cidr_1
  availability_zone       = var.availability_zone[0]
  map_public_ip_on_launch = var.map_public_ip
}

# Create the second public subnet in the VPC for external traffic.
resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_cidr_2
  availability_zone       = var.availability_zone[1]
  map_public_ip_on_launch = var.map_public_ip
}

# Create the first private subnet in the VPC for internal traffic.
resource "aws_subnet" "private_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_cidr_1
  availability_zone = var.availability_zone[0]
}

# Create the second private subnet in the VPC for internal traffic.
resource "aws_subnet" "private_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_cidr_2
  availability_zone = var.availability_zone[1]
}

# A NAT gateway is required for the private subnet.
# Configure EIP for the first NAT Gateway.
resource "aws_eip" "nat_1" {
  vpc = true
}

# configure EIP for the second NAT gateway.
resource "aws_eip" "nat_2" {
  vpc = true
}

# Create the first NAT gateway.
resource "aws_nat_gateway" "ngw_1" {
  subnet_id     = aws_subnet.public_1.id
  allocation_id = aws_eip.nat_1.id
  # Requires a resource dependency.
  depends_on = [aws_internet_gateway.igw]
}

# Create the second NAT gateway.
resource "aws_nat_gateway" "ngw_2" {
  subnet_id     = aws_subnet.public_2.id
  allocation_id = aws_eip.nat_2.id
  # Requires a resource dependency.
  depends_on = [aws_internet_gateway.igw]
}

# Create the route tables for the subnets.
# Create the first private subnet route table.
resource "aws_route_table" "private_1" {
  vpc_id = aws_vpc.main.id
}

# Cerate the second private subnet route table.
resource "aws_route_table" "private_2" {
  vpc_id = aws_vpc.main.id
}

# Create the first private subnet route.
resource "aws_route" "private_1" {
  route_table_id         = aws_route_table.private_1.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.ngw_1.id
}

# create the second perivate subnet route.
resource "aws_route" "private_2" {
  route_table_id         = aws_route_table.private_2.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.ngw_2.id
}

# Associate the private subnet route table to the first private subnet.
resource "aws_route_table_association" "private_1" {
  subnet_id      = aws_subnet.private_1.id
  route_table_id = aws_route_table.private_1.id
}

# Associate the private subnet route table to the second private subnet.
resource "aws_route_table_association" "private_2" {
  subnet_id      = aws_subnet.private_2.id
  route_table_id = aws_route_table.private_2.id
}

# Create the public subnet route table.
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
}

# Create the public subnet route.
resource "aws_route" "public" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

# Associate the public subnet route table to the first public subnet.
resource "aws_route_table_association" "public_1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id
}

# Associate the public subnet route table to the second public subnet.
resource "aws_route_table_association" "public_2" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public.id
}

# Create a public NACL.
resource "aws_network_acl" "public" {
  vpc_id = aws_vpc.main.id
}

# Create the NACL rules for the public NACL.
resource "aws_network_acl_rule" "public_ingress" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 100
  protocol       = "-1"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
}

resource "aws_network_acl_rule" "public_egress" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 100
  egress         = true
  protocol       = "-1"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"

}

# Create a private NACL.
resource "aws_network_acl" "private" {
  vpc_id = aws_vpc.main.id
}

# Create the NACL rules for the private NACL.
resource "aws_network_acl_rule" "private_ingress" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 100
  protocol       = "-1"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
}

resource "aws_network_acl_rule" "private_egress" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 100
  egress         = true
  protocol       = "-1"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"

}

# Create a security group for the ALB.
resource "aws_security_group" "ecs_sg" {
  name        = "ecs-sg"
  description = "ECS security group for the ALB."
  vpc_id      = aws_vpc.main.id

  ingress {
    protocol    = "tcp"
    from_port   = 80
    to_port     = 80
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    protocol    = "tcp"
    from_port   = 8080
    to_port     = 8080
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    protocol  = "tcp"
    from_port = 31000
    to_port   = 61000
    self      = true
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Create a security group for the task.
resource "aws_security_group" "ecs_tasks" {
  name   = "ecs-task-sg"
  vpc_id = aws_vpc.main.id

  ingress {
   protocol         = "tcp"
   from_port        = 5000
   to_port          = 5000
   cidr_blocks      = ["0.0.0.0/0"]
   ipv6_cidr_blocks = ["::/0"]
  }
 
  egress {
   protocol         = "-1"
   from_port        = 0
   to_port          = 0
   cidr_blocks      = ["0.0.0.0/0"]
   ipv6_cidr_blocks = ["::/0"]
  }
}

# Create a CloudWatch log group.
resource "aws_cloudwatch_log_group" "ecs_logs" {
  name              = "ecs-logs"
  retention_in_days = 14
}

# Create an ECS task definition.
resource "aws_ecs_task_definition" "ecs_task_definition" {
  family                = "${var.service_name}-ecs-demo-app"
  container_definitions = <<DEFINITION
[
  {
    "name": "demo-app",
    "image": "${var.ecs_image_url}",
    "essential": true,
    "memory": 300,
    "cpu": 10,
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-group": "ecs-logs",
        "awslogs-region": "us-east-1",
        "awslogs-stream-prefix": "ecs-demo-app"
      }
    },
    "mountPoints": [
      {
        "containerPath": "/usr/local/apache2/htdocs",
        "sourceVolume": "my-vol"
      }
    ],
    "portMappings": [
      {
        "containerPort": 5000
      }
    ],
    "repositoryCredentials": {
          "credentialsParameter": "arn:aws:secretsmanager:us-east-1:12345678909:secret:dev/DockerHubSecrets-abCdefg"
    }
  }
]
DEFINITION
  # This is needed when using a private repository
  execution_role_arn       = aws_iam_role.ecsTaskExecutionRole.arn 
  requires_compatibilities = ["FARGATE"] # Stating that we are using ECS Fargate
  network_mode             = "awsvpc"    # Using awsvpc as our network mode as this is required for Fargate
  memory                   = 512         # Specifying the memory our container requires
  cpu                      = 256         # Specifying the CPU our container requires
  volume {
    name = "my-vol"
  }
}

# Create the Application Load Balancer.
resource "aws_lb" "main" {
  name                       = "ecsalb"
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.ecs_sg.id]
  subnets                    = [aws_subnet.public_1.id, aws_subnet.public_2.id]
  idle_timeout               = 30
  enable_deletion_protection = false
}

# Create the ALB target group.
resource "aws_lb_target_group" "ecs_rest_api_tg" {
  name     = "ecs-tg"
  port     = 5000
  protocol = "HTTP"
  target_type = "ip"
  vpc_id   = aws_vpc.main.id
  health_check {
    path                = "/"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 2
    interval            = 10
    matcher             = "200"
  }
}

# Create the ALB listener.
resource "aws_lb_listener" "alb_listener" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    target_group_arn = aws_lb_target_group.ecs_rest_api_tg.arn
    type             = "forward"
  }
}

# Create the ECS cluster.
resource "aws_ecs_cluster" "ecs_cluster" {
  name = "ecs_cluster"
}

# Create the ECS service.
resource "aws_ecs_service" "service" {
  name            = var.service_name
  cluster         = aws_ecs_cluster.ecs_cluster.id
  task_definition = aws_ecs_task_definition.ecs_task_definition.arn
  desired_count   = var.desired_capacity
  launch_type     = "FARGATE"
  depends_on      = [aws_lb_listener.alb_listener]
  load_balancer {
    container_name   = "demo-app"
    container_port   = 5000
    target_group_arn = aws_lb_target_group.ecs_rest_api_tg.arn
  }

  network_configuration {
    subnets          = ["${aws_subnet.public_1.id}", "${aws_subnet.public_2.id}", "${aws_subnet.private_1.id}","${aws_subnet.private_2.id}"]
    security_groups  = ["${aws_security_group.ecs_tasks.id}"]
    assign_public_ip = true # Providing our containers with public IPs
  }
}

# Create a CloudWatch alarm for ECS service CPU scale out.
resource "aws_cloudwatch_metric_alarm" "ecs_service_cpu_scale_out_alarm" {
  alarm_name          = "CPU utilization greater than 50%"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = "60"
  statistic           = "Average"
  threshold           = "50"
  alarm_description   = "Alarm if CPU utilization is greater than 50% of reserved CPU"
}

# Create a CloudWatch alarm for ECS service CPU scale out.
resource "aws_cloudwatch_metric_alarm" "ecs_infra_cpu_alarm_high" {
  alarm_name          = "CPU utilization greater than 50%"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "60"
  statistic           = "Average"
  threshold           = "10"
  alarm_description   = "Alarm if CPU too high or metric disappears indicating instance is down"
}

# Create a DynamoDB table.
resource "aws_dynamodb_table" "music_table" {
  name           = var.dynamodb_table_name
  billing_mode   = "PROVISIONED"
  read_capacity  = 1
  write_capacity = 1
  hash_key       = "artist"

  attribute {
    name = "artist"
    type = "S"
  }
}
