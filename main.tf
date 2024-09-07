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
  ami           = "ami-0556dfb1a147512ba"
  instance_type = "t3.micro"
  subnet_id     = aws_subnet.demo_subnet_1.id
  vpc_security_group_ids = [aws_security_group.demo_sg.id]
}

# RDS MySQL Instance
resource "aws_db_subnet_group" "demo_subnet_group" {
  name       = "demo-subnet-group"
  subnet_ids = [aws_subnet.demo_subnet_1.id, aws_subnet.demo_subnet_2.id]
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
