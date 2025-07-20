# Infrastructure configuration for AWS PHP Docker deployment
provider "aws" {
  region = "ap-south-1"
  profile = "terraform"
}

# GitHub repository information for cloning the application code
variable "github_username" {
  description = "GitHub username where the repository is hosted"
  type        = string
  default     = "prateekmeshram"
}

variable "key_name" {
  description = "Name of the AWS key pair to use for SSH access"
  type        = string
  default     = "id_rsa"  # Default key name, change as needed  

}

variable "repo_name" {
  description = "Name of the repository containing the Dockerfile"
  type        = string
  default     = "docker-deployment"
}

# Create a VPC to host our application
resource "aws_vpc" "php_app_vpc" {
  cidr_block = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support = true
  tags = {
    Name = "php-app-vpc"
  }
} 

# Create a public subnet for our EC2 instance
resource "aws_subnet" "php_app_public_subnet" {
  vpc_id     = aws_vpc.php_app_vpc.id
  cidr_block = "10.0.0.0/24"
  availability_zone = "ap-south-1a"
  map_public_ip_on_launch = true
  tags = {
    Name = "php-app-public-subnet"
  }
}

# Create Internet Gateway to allow internet access for our VPC
resource "aws_internet_gateway" "php_app_igw" {
  vpc_id = aws_vpc.php_app_vpc.id
  tags = {
    Name = "php-app-igw"
  }
}

# Create Route Table to direct traffic through the Internet Gateway
resource "aws_route_table" "php_app_rt" {
  vpc_id = aws_vpc.php_app_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.php_app_igw.id
  }

  tags = {
    Name = "php-app-rt"
  }
}

# Associate the Route Table with our public subnet
resource "aws_route_table_association" "php_app_rta" {
  subnet_id      = aws_subnet.php_app_public_subnet.id
  route_table_id = aws_route_table.php_app_rt.id
}

# Create Security Group to allow HTTP and SSH access
resource "aws_security_group" "php_app_sg" {
  name        = "php-app-sg"
  description = "Allow SSH and HTTP inbound traffic"
  vpc_id      = aws_vpc.php_app_vpc.id

  ingress {
    description = "SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow-web"
  }
}

# Create EC2 instance to host our Docker container with PHP application
resource "aws_instance" "php_app_server" {
  ami                    = "ami-03f4878755434977f"  # Amazon Linux 2023 AMI in ap-south-1
  instance_type          = "t2.micro"
  key_name              = var.key_name     # Use the key pair variable
  vpc_security_group_ids = [aws_security_group.php_app_sg.id]
  subnet_id             = aws_subnet.php_app_public_subnet.id
  associate_public_ip_address = true
  
  tags = {
    Name = "web-server"
  }

  user_data = <<-EOF
              #!/bin/bash
              # Update system
              apt-get update -y
              
              # Install Docker
              apt-get install -y docker.io
              systemctl start docker
              systemctl enable docker
              
              # Install Git
              yum install -y git
              
              # Clone the repository
              git clone https://github.com/${var.github_username}/${var.repo_name}.git /app
              cd /app
              
              # Build and run Docker container
              docker build -t php-app .
              docker run -d -p 80:80 php-app
              EOF

  depends_on = [aws_security_group.php_app_sg]  # Ensure security group is created before instance
} 

# Output the public IP of the EC2 instance
output "instance_public_ip" {
  description = "Public IP of the PHP application server"
  value       = aws_instance.php_app_server.public_ip
}

# Create a key pair for SSH access
resource "aws_key_pair" "php_app_key" {
  key_name   = var.key_name
  public_key = file("~/.ssh/${var.key_name}.pub")  # Ensure the public key file exists
} 
