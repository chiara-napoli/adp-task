terraform {
	required_providers {
		aws = {
			source  = "hashicorp/aws"
			version = "~> 6.0"
		}
	}
}

provider "aws" {
	region 	= "eu-west-1"
	profile = "aptsapienza"
}

variable "project_name" {
    type 		= string
    description = "The name of the project"
}

variable "docker_image_tag" {
    type 		= string
    description = "The tag of the Docker image"
}

variable "docker_image_architecture" {
    type 		= string
    description = "The CPU architecture of the Docker image"
}

# =========================================================================
# 1. NETWORK STACK (VPC, Subnets, IGW)
# =========================================================================

# Create the VPC
resource "aws_vpc" "main" {
	cidr_block           = "10.0.0.0/16"
	enable_dns_hostnames = true
	enable_dns_support   = true
	tags 				 = { Name = "${var.project_name}-vpc" }
}

# Create an Internet Gateway (to allow internet access for image pulling)
resource "aws_internet_gateway" "igw" {
	vpc_id 	= aws_vpc.main.id
	tags 	= { Name = "${var.project_name}-igw" }
}

# Create a Public Subnet
resource "aws_subnet" "public" {
	vpc_id                  = aws_vpc.main.id
	cidr_block              = "10.0.1.0/24"
	map_public_ip_on_launch = true # Required for Fargate tasks in public subnets
	availability_zone       = "eu-west-1a"
	tags                    = { Name = "${var.project_name}-public-subnet" }
}

# Create a Route Table for the public subnet
resource "aws_route_table" "public_rt" {
	vpc_id = aws_vpc.main.id
	route {
		cidr_block = "0.0.0.0/0"
		gateway_id = aws_internet_gateway.igw.id
	}
	tags = { Name = "${var.project_name}-public-rt" }
}

# Associate the Route Table with the Subnet
resource "aws_route_table_association" "public_association" {
	subnet_id      = aws_subnet.public.id
	route_table_id = aws_route_table.public_rt.id
}

# Security Group for Batch/Fargate
resource "aws_security_group" "batch_sg" {
	name        = "${var.project_name}-batch-sg"
	description = "Allow outbound traffic for Fargate"
	vpc_id      = aws_vpc.main.id
	egress {
		from_port   = 0
		to_port     = 0
		protocol    = "-1"
		cidr_blocks = ["0.0.0.0/0"]
	}
}

# =========================================================================
# 2. STORAGE & REGISTRY (S3 & ECR)
# =========================================================================

resource "aws_s3_bucket" "bio_bucket" {
	bucket_prefix = "${var.project_name}-data-"
	force_destroy = true 	# Allows deleting bucket even if it contains files, for lab cleanup.
							# ---> Not safe for production
}

resource "aws_ecr_repository" "bio_image_repo" {
	name         = "${var.project_name}-image-repo"
	force_delete = true 	# Allows deleting the repository even if it contains images, for lab cleanup.
							# ---> Not safe for production
}

# =========================================================================
# 3. IAM ROLES (Permissions)
# =========================================================================

# Note: For Fargate-based Batch compute environments, we use the AWS-managed
# service-linked role (AWSServiceRoleForBatch) instead of a custom service role.
# This role is automatically created by AWS and has all the required permissions
# (including ecs:ListClusters) to manage Fargate resources.

# --- ECS Task Execution Role (Allows Fargate to pull images & write logs) ---
data "aws_iam_policy_document" "ecs_task_execution_role_policy_document" {
	statement {
		actions = ["sts:AssumeRole"]
		principals {
			type        = "Service"
			identifiers = ["ecs-tasks.amazonaws.com"]
		}
	}
}

resource "aws_iam_role" "ecs_task_execution_role" {
	name = "${var.project_name}-execution-role"
	assume_role_policy = data.aws_iam_policy_document.ecs_task_execution_role_policy_document.json
}

resource "aws_iam_role_policy_attachment" "ecs_task_exec_policy_attachment" {
	role       = aws_iam_role.ecs_task_execution_role.name
	policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Grant S3 Full Access to the Job
resource "aws_iam_role_policy_attachment" "s3_full_access_policy_attachment" {
	role       = aws_iam_role.ecs_task_execution_role.name
	policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess" 	# For educational purposes only, in production restrict permissions to what is strictly necessary.
																# ---> Not safe for production
}

# =========================================================================
# 4. COMPUTE ENVIRONMENT & QUEUE
# =========================================================================

resource "aws_batch_compute_environment" "bio_compute" {
	name                     = "${var.project_name}-compute-env"
	type                     = "MANAGED"
	
	compute_resources {
		type               = "FARGATE"
		max_vcpus          = 16
		subnets            = [aws_subnet.public.id]
		security_group_ids = [aws_security_group.batch_sg.id]
	}
}

resource "aws_batch_job_queue" "bio_queue" {
	name                 = "${var.project_name}-queue"
	state                = "ENABLED"
	priority             = 1
	
	compute_environment_order {
		compute_environment = aws_batch_compute_environment.bio_compute.arn
		order               = 1
	}
}

# =========================================================================
# 5. JOB DEFINITION
# =========================================================================

resource "aws_batch_job_definition" "bio_job" {
	name = "${var.project_name}-job"
	type = "container"
	platform_capabilities = ["FARGATE"]

	container_properties = jsonencode({
		image = "${aws_ecr_repository.bio_image_repo.repository_url}:${var.docker_image_tag}"
		# Resource requirements
		resourceRequirements = [
			{ type = "VCPU", value = "0.25" },
			{ type = "MEMORY", value = "512" }
		]
		# Runtime platform for Fargate to run the container
		runtimePlatform = {
			operatingSystemFamily = "LINUX"
			cpuArchitecture       = var.docker_image_architecture
		}
		# Roles
		jobRoleArn       = aws_iam_role.ecs_task_execution_role.arn
		executionRoleArn = aws_iam_role.ecs_task_execution_role.arn
		# Environment Variables to pass into Python script
		environment = [
			{ name = "BUCKET_NAME", value = aws_s3_bucket.bio_bucket.bucket },
			{ name = "INPUT_PREFIX", value = "input/" },
			{ name = "OUTPUT_PREFIX", value = "output/" }
		]
		# Networking configuration required to receive public IP address.
		networkConfiguration = {
			assignPublicIp = "ENABLED"
		}
	})
}

# =========================================================================
# OUTPUTS
# =========================================================================

output "ecr_repository_url" {
	value = aws_ecr_repository.bio_image_repo.repository_url
	description = "Use this URL to tag and push your container image"
}

output "s3_bucket_name" {
	value = aws_s3_bucket.bio_bucket.bucket
	description = "The S3 bucket created for input/output"
}

output "job_queue_name" {
	value = aws_batch_job_queue.bio_queue.name
	description = "Submit jobs to this queue"
}