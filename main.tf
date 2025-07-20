# Create a VPC to host our application
resource "aws_vpc" "app_vpc" {
  cidr_block = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support = true
  tags = {
    Name = "php-app-vpc"
  }
} 

# Create a public subnet for our EC2 instance
resource "aws_subnet" "app_public_subnet" {
  vpc_id     = aws_vpc.app_vpc.id
  cidr_block = "10.0.0.0/24"
  availability_zone = "ap-south-1a"
  map_public_ip_on_launch = true
  tags = {
    Name = "php-app-public-subnet"
  }
}

# Create Internet Gateway to allow internet access for our VPC
resource "aws_internet_gateway" "app_igw" {
  vpc_id = aws_vpc.app_vpc.id
  tags = {
    Name = "php-app-igw"
  }
}

# Create Route Table to direct traffic through the Internet Gateway
resource "aws_route_table" "app_rt" {
  vpc_id = aws_vpc.app_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.app_igw.id
  }

  tags = {
    Name = "php-app-rt"
  }
}

# Associate the Route Table with our public subnet
resource "aws_route_table_association" "app_rta" {
  subnet_id      = aws_subnet.app_public_subnet.id
  route_table_id = aws_route_table.app_rt.id
}

# Create Security Group to allow HTTP and SSH access
resource "aws_security_group" "app_sg" {
  name        = "php-app-sg"
  description = "Allow SSH and HTTP inbound traffic"
  vpc_id      = aws_vpc.app_vpc.id

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
resource "aws_instance" "app_server" {
  ami                    = "ami-0f918f7e67a3323f0"  # Ubuntu 24 AMI in ap-south-1
  instance_type          = "t2.micro"
  key_name              = var.key_name     # Use the key pair variable
  vpc_security_group_ids = [aws_security_group.app_sg.id]
  subnet_id             = aws_subnet.app_public_subnet.id
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

  depends_on = [aws_security_group.app_sg]  # Ensure security group is created before instance
} 

# Output the public IP of the EC2 instance
output "instance_public_ip" {
  description = "Public IP of the PHP application server"
  value       = aws_instance.app_server.public_ip
}

resource "aws_key_pair" "app_key" {
  key_name   = var.key_name
  public_key = file("~/.ssh/${var.key_name}.pub")  # Ensure the public key file exists

  lifecycle {
    create_before_destroy = true
    # This prevents recreation of the key pair if it already exists
    # and only updates if the public key content changes
    prevent_destroy = true
  }

  # Add tags to help identify the key pair
  tags = {
    Name = "${var.key_name}-key-pair"
    ManagedBy = "terraform"
  }
} 
