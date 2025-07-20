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
  ami                    = "ami-0f918f7e67a3323f0"  # Ubuntu 24 AMI in ap-south-1
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
              
              # Enable logging of user data script
              exec > >(tee /var/log/user-data.log) 2>&1
              
              echo "[$(date)] Starting user data script execution..."
              
              # Update system
              echo "[$(date)] Updating system packages..."
              sudo apt-get update -y
              
              # Install Docker
              echo "[$(date)] Installing Docker and Git..."
              sudo apt-get install -y docker.io git
              
              # Start and enable Docker
              echo "[$(date)] Starting Docker service..."
              sudo systemctl start docker
              sudo systemctl enable docker
              
              # Add ubuntu user to docker group
              echo "[$(date)] Adding ubuntu user to docker group..."
              sudo usermod -aG docker ubuntu
              
              # Clone the repository
              echo "[$(date)] Cloning repository..."
              sudo rm -rf /app
              sudo git clone https://github.com/prateekmeshram/docker-deployment.git /app
              
              echo "[$(date)] Changing to app directory..."
              cd /app || exit 1
              
              # Build and run Docker container
              echo "[$(date)] Building Docker image..."
              sudo docker build -t php-app . || exit 1
              
              echo "[$(date)] Running Docker container..."
              # Stop any existing container
              sudo docker stop $(sudo docker ps -q --filter ancestor=php-app) 2>/dev/null || true
              sudo docker rm $(sudo docker ps -aq --filter ancestor=php-app) 2>/dev/null || true
              
              # Run new container
              sudo docker run -d -p 80:80 php-app
              
              echo "[$(date)] User data script completed!"
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
