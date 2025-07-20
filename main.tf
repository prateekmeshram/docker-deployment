provider "aws" {
  profile = "terraform"
  region  = "ap-south-1"
}

# Create VPC
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "docker-vpc"
  }
}

# Create Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "docker-igw"
  }
}

# Create Public Subnet
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.subnet_cidr
  availability_zone       = "${var.region}a"
  map_public_ip_on_launch = true

  tags = {
    Name = "docker-public-subnet"
  }
}

# Create Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "docker-public-rt"
  }
}

# Associate Route Table with Subnet
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "httpd_sg" {
  name_prefix = "httpd-sg"
  description = "Security group for HTTP and SSH access"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "httpd_server" {
  ami           = var.ami_id
  instance_type = var.instance_type
  subnet_id     = aws_subnet.public.id
  key_name      = var.key_name
  vpc_security_group_ids = [aws_security_group.httpd_sg.id]

  user_data = <<-EOF
              #!/bin/bash
              exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
              echo "Starting user data script execution..."
              yum update -y
              echo "Installing Docker..."
              amazon-linux-extras install docker -y
              echo "Starting Docker service..."
              service docker start
              usermod -a -G docker ec2-user
              mkdir -p /home/ec2-user/docker
              cat > /home/ec2-user/docker/index.html << 'HTMLEOF'
              <!DOCTYPE html>
              <html lang="en">
              <head>
                  <meta charset="UTF-8">
                  <meta name="viewport" content="width=device-width, initial-scale=1.0">
                  <title>Welcome to My Docker Website</title>
                  <style>
                      body {
                          font-family: Arial, sans-serif;
                          line-height: 1.6;
                          margin: 0;
                          padding: 20px;
                          background-color: #f0f2f5;
                      }
                      .container {
                          max-width: 800px;
                          margin: 0 auto;
                          background-color: white;
                          padding: 20px;
                          border-radius: 8px;
                          box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);
                      }
                      h1 {
                          color: #1a73e8;
                          text-align: center;
                      }
                      p {
                          color: #333;
                      }
                  </style>
              </head>
              <body>
                  <div class="container">
                      <h1>Welcome to My Docker Website!</h1>
                      <p>This is a custom web page being served from an Apache container running on AWS EC2.</p>
                      <p>Key features of this setup:</p>
                      <ul>
                          <li>Running on Amazon Linux 2</li>
                          <li>Docker container with Apache</li>
                          <li>Custom HTML content</li>
                          <li>Terraform-managed infrastructure</li>
                      </ul>
                      <p>Thanks for visiting!</p>
                  </div>
              </body>
              </html>
              HTMLEOF
              
              cat > /home/ec2-user/docker/Dockerfile << 'DOCKEREOF'
              FROM httpd:2.4
              COPY index.html /usr/local/apache2/htdocs/
              DOCKEREOF
              
              cd /home/ec2-user/docker
              echo "Building Docker image..."
              docker build -t my-apache-site .
              echo "Running Docker container..."
              docker run -d -p 80:80 my-apache-site
              echo "Checking Docker container status..."
              docker ps
              echo "User data script completed."
              EOF

  tags = {
    Name = "httpd-docker-server"
  }
}
