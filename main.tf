provider "aws" {
  region = "eu-central-1"
}

# VPC
resource "aws_vpc" "demo_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
}

# Subnets
resource "aws_subnet" "demo_subnet_1" {
  vpc_id     = aws_vpc.demo_vpc.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "eu-central-1a"
}

resource "aws_subnet" "demo_subnet_2" {
  vpc_id     = aws_vpc.demo_vpc.id
  cidr_block = "10.0.2.0/24"
  availability_zone = "eu-central-1b"
}

# Internet Gateway
resource "aws_internet_gateway" "demo_igw" {
  vpc_id = aws_vpc.demo_vpc.id
}

# Route Table
resource "aws_route_table" "demo_rt" {
  vpc_id = aws_vpc.demo_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.demo_igw.id
  }
}

# Route Table Association
resource "aws_route_table_association" "demo_rta_subnet1" {
  subnet_id      = aws_subnet.demo_subnet_1.id
  route_table_id = aws_route_table.demo_rt.id
}

resource "aws_route_table_association" "demo_rta_subnet2" {
  subnet_id      = aws_subnet.demo_subnet_2.id
  route_table_id = aws_route_table.demo_rt.id
}

# Security Group
resource "aws_security_group" "demo_sg" {
  vpc_id = aws_vpc.demo_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# EC2 Instance
resource "aws_instance" "demo_instance" {
  ami           = data.aws_ami.amazon_linux_2.id
  instance_type = "t3.micro"
  subnet_id     = aws_subnet.demo_subnet_1.id
  vpc_security_group_ids = [aws_security_group.demo_sg.id]
  associate_public_ip_address = true

  root_block_device {
    volume_type = "gp2"
    volume_size = 8
  }

  tags = {
    Name = "demo-instance"
  }
}

# RDS MySQL Instance
resource "aws_db_subnet_group" "demo_subnet_group" {
  name       = "demo-subnet-group-${random_id.suffix.hex}"
  subnet_ids = [aws_subnet.demo_subnet_1.id, aws_subnet.demo_subnet_2.id]
}

# Add this resource to generate a random suffix
resource "random_id" "suffix" {
  byte_length = 4
}

resource "aws_db_instance" "demo_db" {
  allocated_storage    = 20
  engine               = "mysql"
  instance_class       = "db.t3.micro"
  db_name              = "mydb"
  username             = "admin"
  password             = "password"
  vpc_security_group_ids = [aws_security_group.demo_sg.id]
  skip_final_snapshot   = true
  publicly_accessible   = true
  multi_az              = false
  db_subnet_group_name  = aws_db_subnet_group.demo_subnet_group.name
}

# CloudWatch Alarm for CPU Utilization
resource "aws_cloudwatch_metric_alarm" "cpu_alarm" {
  alarm_name          = "cpu-utilization-alarm"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "120"  # Changed from 300 to 120 seconds (2 minutes)
  statistic           = "Average"
  threshold           = "10"
  alarm_description   = "This metric monitors ec2 cpu utilization"
  alarm_actions       = [aws_sns_topic.resize_topic.arn]

  dimensions = {
    InstanceId = aws_instance.demo_instance.id
  }
}

# SNS Topic for alarm notifications
resource "aws_sns_topic" "resize_topic" {
  name = "resize-instance-topic"
}

# IAM role for Lambda
resource "aws_iam_role" "resize_instance_lambda_role" {
  name = "resize_instance_lambda_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# IAM policy for Lambda
resource "aws_iam_role_policy" "lambda_policy" {
  role = aws_iam_role.resize_instance_lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:StopInstances",
          "ec2:StartInstances",
          "ec2:ModifyInstanceAttribute"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# Lambda function to resize the instance
resource "aws_lambda_function" "resize_instance" {
  filename         = "${path.module}/lambda/resize_function.zip"
  function_name    = "resize_instance_function"
  role             = aws_iam_role.resize_instance_lambda_role.arn
  handler          = "resize_function.lambda_handler"
  runtime          = "python3.9"
  source_code_hash = filebase64sha256("${path.module}/lambda/resize_function.zip")
  timeout          = 60  # Increase timeout to 60 seconds
  memory_size      = 256 # Optionally increase memory if needed
}

# SNS subscription for Lambda
resource "aws_sns_topic_subscription" "resize_subscription" {
  topic_arn = aws_sns_topic.resize_topic.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.resize_instance.arn
}

# Lambda permission for SNS
resource "aws_lambda_permission" "with_sns" {
  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.resize_instance.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.resize_topic.arn
}

# Data source for the latest Amazon Linux 2 AMI
data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# CloudWatch Events Rule to trigger Lambda periodically
resource "aws_cloudwatch_event_rule" "periodic_lambda_trigger" {
  name                = "trigger-resize-lambda-periodically"
  description         = "Trigger the resize Lambda function every minute"
  schedule_expression = "rate(1 minute)"
}

# CloudWatch Events Target
resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.periodic_lambda_trigger.name
  target_id = "TriggerResizeLambda"
  arn       = aws_lambda_function.resize_instance.arn
}

# Lambda permission for CloudWatch Events
resource "aws_lambda_permission" "allow_cloudwatch_to_call_lambda" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.resize_instance.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.periodic_lambda_trigger.arn
}
