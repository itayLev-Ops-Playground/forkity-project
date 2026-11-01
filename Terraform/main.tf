locals {
  instance_names = [
    "jenkins-server",
    "monitoring-server",
    "kubernetes-master-node",
    "kubernetes-worker-node"
  ]
}

resource "aws_instance" "ec2" {
  count                  = var.ec2-instance-count
  ami                    = data.aws_ami.ubuntu.id
  subnet_id              = aws_subnet.public-subnet[count.index].id
  instance_type          = var.ec2_instance_type[count.index]
  iam_instance_profile   = aws_iam_instance_profile.iam-instance-profile.name
  vpc_security_group_ids = [aws_security_group.default-ec2-sg.id]
  depends_on             = [aws_iam_role_policy.jenkins_secret_read]
  user_data = local.instance_names[count.index] == "jenkins-server" ? replace(
    replace(
      file("${path.module}/../scripts/jenkins-user-data.sh"),
      "__AWS_REGION__",
      var.aws-region
    ),
    "__JENKINS_SECRET_NAME__",
    var.jenkins_secret_name
  ) : null
  user_data_replace_on_change = local.instance_names[count.index] == "jenkins-server"

  lifecycle {
    precondition {
      condition     = local.instance_names[count.index] != "jenkins-server" || var.ec2_instance_type[count.index] == "t3a.xlarge"
      error_message = "The jenkins-server instance must use t3a.xlarge."
    }
  }

  root_block_device {
    volume_size = var.ec2_volume_size
    volume_type = var.ec2_volume_type
  }

  tags = {
    Name = "${local.org}-${local.project}-${local.env}-${local.instance_names[count.index]}"
    Env  = "${local.env}"
  }
}