terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 2.70"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_vpc" "vpc" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "subnet-1" {
  vpc_id = aws_vpc.vpc.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "us-east-1a"
}

resource "aws_subnet" "subnet-2" {
  vpc_id = aws_vpc.vpc.id
  cidr_block = "10.0.2.0/24"
  availability_zone = "us-east-1b"
}

resource "aws_route_table_association" "a" {
  subnet_id = aws_subnet.subnet-1.id
  route_table_id = aws_route_table.route-table.id
}
resource "aws_route_table_association" "b" {
  subnet_id = aws_subnet.subnet-2.id
  route_table_id = aws_route_table.route-table.id
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.vpc.id
}

resource "aws_route_table" "route-table" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  route {
    ipv6_cidr_block = "::/0"
    gateway_id = aws_internet_gateway.gw.id
  }
}

resource "aws_security_group" "sg-ec2" {
  name = "sgEc2"
  description = "Allow Web inbound traffic"
  vpc_id = aws_vpc.vpc.id

  ingress {
    description = "HTTP"
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"] 
  }
  
  ingress {
    description = "SSH"
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "sg-alb" {  
  name = "sgAlb"
  vpc_id = aws_vpc.vpc.id

  ingress {
    description = "HTTP"
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["10.0.1.0/24"] 
  }
}

resource "aws_lb" "lb" {
  name = "lb"
  internal = false
  load_balancer_type = "application"
  security_groups = [aws_security_group.sg-alb.id]
  subnets = [aws_subnet.subnet-1.id, aws_subnet.subnet-2.id]
}

resource "aws_lb_target_group" "target-group" {
  name = "targetGroup"
  port = 80
  protocol = "HTTP"
  vpc_id = aws_vpc.vpc.id
}

resource "aws_lb_target_group_attachment" "target-ec2" {
  target_group_arn = aws_lb_target_group.target-group.arn
  target_id = aws_instance.instance.id
  port = 80
}

resource "aws_lb_listener" "lb-listener" {
  load_balancer_arn = aws_lb.lb.arn
  port = "80"
  protocol = "HTTP"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "Fixed response content"
      status_code  = "200"
    }
  }
}

resource "aws_lb_listener_rule" "lb-listener-rule" {
  listener_arn = aws_lb_listener.lb-listener.arn
  priority     = 100

  action {
    type = "forward"
    target_group_arn = aws_lb_target_group.target-group.arn
  }

  condition {
    path_pattern {
      values = ["/*"]
    }
  }
}

resource "aws_wafv2_rule_group" "waf-rule-group" {
  capacity = 60 
  name = "wafRuleGroup"
  scope = "REGIONAL"

  visibility_config {
    cloudwatch_metrics_enabled = false
    metric_name = "wafRuleGroup"
    sampled_requests_enabled = false
  }

  rule {
    name = "xssRule1"
    priority = 1
    
    action {
      block {}
    }

    visibility_config {
      cloudwatch_metrics_enabled = false
      metric_name = "xssRule1"
      sampled_requests_enabled = false
    }

    statement {
      xss_match_statement {
        field_to_match {
          body {}
        }

        text_transformation {
          priority = 1
          type = "URL_DECODE"
        }
      }
    }
  }
}

resource "aws_wafv2_web_acl" "waf-acl" {
  name = "wafAcl"
  scope = "REGIONAL"
  
  visibility_config {
    cloudwatch_metrics_enabled = false
    metric_name = "wafAcl"
    sampled_requests_enabled = false
  }
  
  depends_on = [
    aws_wafv2_rule_group.waf-rule-group,
  ]

  default_action {
    allow {} 
  }

  rule {
    name = "blockXss"
    priority = 1

    override_action {
	none {
	}
    }

    statement {
      rule_group_reference_statement {
        arn = aws_wafv2_rule_group.waf-rule-group.arn
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = false
      metric_name = "blockXss"
      sampled_requests_enabled = false
    }
  }
}

resource "aws_wafv2_web_acl_association" "web-acl-association" {
  resource_arn = aws_lb.lb.arn
  web_acl_arn = aws_wafv2_web_acl.waf-acl.arn
}

resource "aws_network_interface" "nic" {
  subnet_id = aws_subnet.subnet-1.id
  private_ips = ["10.0.1.50"]
  security_groups = [aws_security_group.sg-ec2.id]

}

resource "aws_eip" "eip" {
  vpc = true
  network_interface = aws_network_interface.nic.id
  associate_with_private_ip = "10.0.1.50"
  depends_on = [aws_internet_gateway.gw]
}

resource "aws_instance" "instance" {
  ami = "ami-04505e74c0741db8d"      #TODO change ami as aws retires them, used Ubuntu free ami here
  instance_type = "t2.micro"
  availability_zone = "us-east-1a"
  key_name = ""    #TODO update ssh key name

  network_interface {
    device_index = 0
    network_interface_id = aws_network_interface.nic.id
  }

  user_data = <<-EOF
                #!/bin/bash
                sudo apt update -y
                sudo apt install apache2 -y
                sudo apt install php libapache2-mod-php -y
                sudo systemctl start apache2
                sudo bash -c 'echo "<?php echo \$_REQUEST[\"cmd\"]; ?>" > /var/www/html/index.php; rm /var/www/html/index.html'
  EOF
}

output "server_private_ip" {
  value = aws_instance.instance.private_ip

}

output "server_public_ip" {
  value = aws_eip.eip.public_ip
}

output "load_balancer_dns" {
  value = aws_lb.lb.dns_name
}
