
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 3.36.0"
    }
  }
}
#----------Provider-----------#
provider "aws" {
  access_key = "AKIAVJSVFFVPT67XGMU5"    #old access_key
  secret_key = "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"    #old secret_key
  region     = "us-east-1"

}


#Creating and Saving Key
resource "tls_private_key" "task1_p_key" {
  algorithm = "RSA"
}


resource "aws_key_pair" "task1-key" {
  key_name   = "task1-key"
  public_key = tls_private_key.task1_p_key.public_key_openssh
}


resource "local_file" "private_key" {
  depends_on = [
    tls_private_key.task1_p_key,
  ]
  content  = tls_private_key.task1_p_key.private_key_pem
  filename = "webserver.pem"
}


# Creating VPC,name, CIDR and Tags
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "My_VPC"
  cidr = "10.0.0.0/16"

  azs             = ["us-east-1a", "us-east-1b", "us-east-1c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]       #PRIVATE
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"] #PUBLIC

  enable_dns_hostnames = true
  enable_dns_support   = true
  enable_nat_gateway   = true
  enable_vpn_gateway   = true
  single_nat_gateway   = false
  reuse_nat_ips        = true             # <= Skip creation of EIPs for the NAT Gateways
  external_nat_ip_ids  = aws_eip.nat.*.id # <= IPs specified here as input to the module

  tags = {
    Terraform   = "true"
    Environment = "dev"
    Name        = "My VPC"
  }
}

resource "aws_eip" "nat" {
  public_ipv4_pool = "amazon"
  vpc              = true
}

#Creating NAT gateway
resource "aws_nat_gateway" "natgateway" {
  depends_on    = [aws_eip.nat]
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_subnets.id
  tags = {
    Name = "natgateway"
  }
}


# Route table for SNAT in private subnet
resource "aws_route_table" "private_subnet_route_table" {
  depends_on = [aws_nat_gateway.natgateway]
  vpc_id     = aws_vpc.My_VPC.id


  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.natgateway.id
  }


  tags = {
    Name = "private_subnet_route_table"
  }
}

# Creating Route Associations private subnets
resource "aws_route_table_association" "private_subnet_route_table_association" {
  depends_on     = [aws_route_table.private_subnet_route_table]
  subnet_id      = aws_subnet.private_subnets.id
  route_table_id = aws_route_table.private_subnet_route_table.id
}



# Default bastion
# Creating Bastion
resource "aws_instance" "BASTION" {
  ami                    = "ami-0b05ae060f07f72c7"
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.public_subnets.id
  vpc_security_group_ids = [aws_security_group.only_ssh_bositon.id]
  key_name               = "task1-key"

  tags = {
    Name = "bastionhost"
  }
}


# Creating Internet Gateway in AWS VPC
resource "aws_internet_gateway" "My_VPC_GW" {
  vpc_id = aws_vpc.My_VPC.id
  tags = {
    Name = "My VPC Internet Gateway"
  }
}


# Creating Route Tables for Internet gateway
resource "aws_route_table" "My_VPC_route_table" {
  vpc_id = aws_vpc.My_VPC.id
  tags = {
    Name = "My VPC Route Table"
  }
}

resource "aws_route" "My_VPC_internet_access" {
  route_table_id         = aws_route_table.My_VPC_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.My_VPC_GW.id
}

resource "aws_route_table_association" "My_VPC_association" {
  subnet_id      = aws_subnet.public_subnets.id
  route_table_id = aws_route_table.My_VPC_route_table.id
}


#Creating AWS Security group (SSH)
resource "aws_security_group" "only_ssh_bositon" {
  depends_on = [aws_subnet.public_subnets]
  name       = "only_ssh_bositon"
  vpc_id     = aws_vpc.My_VPC.id

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

  tags = {
    Name = "only_ssh_bositon"
  }
}


resource "aws_security_group" "allow_word" {
  name   = "allow_word"
  vpc_id = aws_vpc.My_VPC.id

  ingress {

    from_port   = 3306
    to_port     = 3306
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

resource "aws_security_group" "allow_http" {
  name   = "allow_http"
  vpc_id = aws_vpc.My_VPC.id
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
  ingress {
    from_port   = 8080
    to_port     = 8080
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
    Name = "allow_http"
  }
}

resource "aws_security_group" "only_ssh_sql_bositon" {
  depends_on  = [aws_subnet.public_subnets]
  name        = "only_ssh_sql_bositon"
  description = "allow ssh bositon inbound traffic"
  vpc_id      = aws_vpc.My_VPC.id




  ingress {
    description     = "Only ssh_sql_bositon in public subnet"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.only_ssh_bositon.id]

  }



  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }



  tags = {
    Name = "only_ssh_sql_bositon"
  }
}


######################################################################################

# Creating EC2 instances in public subnets
resource "aws_instance" "my_server" {
  ami                    = data.aws_ami.packer_image.id
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.public_subnets.id
  vpc_security_group_ids = [aws_security_group.allow_http.id]
  key_name               = "task1-key"

  tags = {
    Name = "Server-nginx-Packer"
  }
}


data "aws_ami" "packer_image" {
  filter {
    name   = "name"
    values = ["my-nginx-server-nginx"]
  }
  owners = ["self"]
}



######################################################################################


module "web_server_sg" {
  source = "terraform-aws-modules/security-group/aws//modules/http-80"

  name        = "web-server"
  description = "Security group for web-server with HTTP ports open within VPC"
  vpc_id      = "My_VPC" #### arrumar

  ingress_cidr_blocks = ["10.10.0.0/16"] #### arrumar
}



module "alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "~> 8.0"

  name = "my-alb"

  load_balancer_type = "application"

  vpc_id          = "My_VPC"
  subnets         = ["subnet-abcde012", "subnet-bcde012a"] #### arrumar
  security_groups = ["sg-edcd9784", "sg-edcd9785"]

  access_logs = {
    bucket = "my-alb-logs"
  }

  target_groups = [
    {
      name_prefix      = "pref-"
      backend_protocol = "HTTP"
      backend_port     = 80
      target_type      = "instance"
      targets = {
        my_target = {
          target_id = "i-0123456789abcdefg"
          port      = 80
        }
        my_other_target = {
          target_id = "i-a1b2c3d4e5f6g7h8i"
          port      = 8080
        }
      }
    }
  ]

  https_listeners = [
    {
      port               = 443
      protocol           = "HTTPS"
      certificate_arn    = "arn:aws:iam::123456789012:server-certificate/test_cert-123456789012"
      target_group_index = 0
    }
  ]

  http_tcp_listeners = [
    {
      port               = 80
      protocol           = "HTTP"
      target_group_index = 0
    }
  ]

  tags = {
    Environment = "Test"
  }
}


output "public_ip" {
  value = aws_instance.my_server.public_ip
}
