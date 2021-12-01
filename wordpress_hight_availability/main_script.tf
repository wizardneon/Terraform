provider "aws" {
    region     = "${var.region}"
    shared_credentials_file="${var.shared_credentials_file}" 
}

data "aws_availability_zones" "available" {}
# ****************Creating Security group
resource "aws_security_group" "web" {
  name = "DynSG"

  dynamic "ingress" {
    for_each = ["80", "443", "3306", "22", "2049"]
    content {
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name  = "Dyn SGroup"
    
  }
}
resource "aws_security_group" "RDS_SG" {

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = ["${aws_security_group.web.id}"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "allow ec2"
  }
}

resource "aws_security_group" "efs" {

   ingress {
     security_groups = ["${aws_security_group.web.id}"]
     from_port = 2049
     to_port = 2049 
     protocol = "tcp"
   }     
        
   egress {
     security_groups = ["${aws_security_group.web.id}"]
     from_port = 0
     to_port = 0
     protocol = "-1"
   }
 }

#*************** Creating & mount EFS
resource "aws_efs_file_system" "efs" {
   creation_token = "efs"
   performance_mode = "generalPurpose"
   throughput_mode = "bursting"
   encrypted = "false"
 tags = {
     Name = "efs"
   }
}
data "aws_vpc" "default" {
  default = true
}

data "aws_subnet_ids" "example" {
  vpc_id = data.aws_vpc.default.id
}
resource "aws_efs_mount_target" "efs-mt" {
  for_each        = data.aws_subnet_ids.example.ids
  file_system_id  = "${aws_efs_file_system.efs.id}"
  subnet_id       = each.value
  security_groups = ["${aws_security_group.efs.id}"]
}



# **************Creating RDS instance
resource "aws_db_instance" "wordpressdb" {
  allocated_storage    = 10
  engine               = "mysql"
  engine_version       = "5.7"
  instance_class       = "db.t2.micro"
  vpc_security_group_ids      =["${aws_security_group.RDS_SG.id}"]
  name                 = "${var.database_name}"
  username             = "${var.database_user}"
  password             = "${var.database_password}"
  skip_final_snapshot  = true
}

resource "aws_efs_access_point" "point" {
  file_system_id = aws_efs_file_system.efs.id
}

# **************Change USERDATA varible 
data "template_file" "user_data" {
  template = "${file("${path.module}/user_data.tpl")}"
  vars = {
    db_username="${var.database_user}"
    db_user_password="${var.database_password}"
    db_name="${var.database_name}"
    db_RDS="${aws_db_instance.wordpressdb.endpoint}"
    access_point_id="${aws_efs_file_system.efs.id}"
   }
depends_on = [aws_db_instance.wordpressdb]
}

# *************Creating autoscaling group & launch configuration
resource "aws_launch_configuration" "web" {
  name_prefix     = "WorldPresServer"
  image_id        = "${var.ami}"
  instance_type   = "t2.micro"
  security_groups = [aws_security_group.web.id]
  user_data = "${data.template_file.user_data.rendered}"
  key_name="${var.key_name}"
depends_on = [data.template_file.user_data]
}

resource "aws_autoscaling_group" "web" {
  name                 = "ASG-${aws_launch_configuration.web.name}"
  launch_configuration = aws_launch_configuration.web.name
  min_size             = 2
  max_size             = 2
  min_elb_capacity     = 2
  health_check_type    = "EC2"
  vpc_zone_identifier  = [aws_default_subnet.default_az1.id, aws_default_subnet.default_az2.id]
  load_balancers       = [aws_elb.web.name]
   
depends_on = [data.template_file.user_data] 
}
# ***********Creating Load Balancer
resource "aws_elb" "web" {
  name               = "WorldPressServer-ELB"
  availability_zones = [data.aws_availability_zones.available.names[0], data.aws_availability_zones.available.names[1]]
  security_groups    = [aws_security_group.web.id]
  listener {
    lb_port           = 80
    lb_protocol       = "http"
    instance_port     = 80
    instance_protocol = "http"
  }
depends_on = [data.template_file.user_data]
}
# **********Subnet for Load Balancer
resource "aws_default_subnet" "default_az1" {
  availability_zone = data.aws_availability_zones.available.names[0]
}

resource "aws_default_subnet" "default_az2" {
  availability_zone = data.aws_availability_zones.available.names[1]
}
#**************Outputs***************
output "web_loadbalancer_url" {
  value = aws_elb.web.dns_name


}
output "RDS-Endpoint" {
    value = aws_db_instance.wordpressdb.endpoint
}

