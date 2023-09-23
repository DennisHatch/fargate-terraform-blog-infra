// When you create a Fargate task you can link an ALB to access the container.
// In this example we will create an ALB first
resource "aws_security_group" "ftb_client_alb_sg" {
  name        = "ftb-alb-client-sg"
  description = "Allow incoming http traffic"
  vpc_id      = var.vpc_id
  ingress {
    from_port        = 80
    to_port          = 80
    protocol         = "TCP"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
  egress {
    from_port        = 80
    to_port          = 80
    protocol         = "TCP"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}
resource "aws_lb" "client_alb" {
  name               = "atb-alb-client"
  load_balancer_type = "application"
  security_groups = [
    aws_security_group.ftb_client_alb_sg.id
  ]
  subnets = split(",", var.subnet_ids)
}
resource "aws_lb_target_group" "alb_client_target_group" {
  name        = "ftb-alb-client-tg"
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = var.vpc_id

  health_check {
    enabled             = true
    interval            = 30
    path                = "/"
    port                = 3000
    protocol            = "HTTP"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 6
    matcher             = "200,307"
  }
}
resource "aws_lb_listener" "alb_client_listener_http" {
  load_balancer_arn = aws_lb.client_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb_client_target_group.arn
  }
}

// ECS service needs to be able to communicate with ECR service.
// For this we create VPC Endpoints
resource "aws_security_group" "ecs_vpce_service_sg" {
  name        = "ftb-ecs-vpce-sg"
  description = "Allow incoming http/HTTPS traffic"
  vpc_id      = var.vpc_id

  ingress {
    from_port        = 80
    to_port          = 80
    protocol         = "TCP"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
  ingress {
    from_port        = 443
    to_port          = 443
    protocol         = "TCP"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
  egress {
    from_port        = 80
    to_port          = 80
    protocol         = "TCP"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
  egress {
    from_port        = 443
    to_port          = 443
    protocol         = "TCP"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

resource "aws_vpc_endpoint" "ecr_dkr_vpce" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.eu-west-1.ecr.dkr"
  vpc_endpoint_type = "Interface"
  security_group_ids = [
    aws_security_group.ecs_vpce_service_sg.id
  ]
  subnet_ids = split(",", var.subnet_ids)

  tags = {
    "Name" : "ftb-ecs-dkr-vpce"
  }
  private_dns_enabled = true
}
resource "aws_vpc_endpoint" "ecr_api_vpce" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.eu-west-1.ecr.api"
  vpc_endpoint_type = "Interface"
  security_group_ids = [
    aws_security_group.ecs_vpce_service_sg.id
  ]
  subnet_ids = split(",", var.subnet_ids)
  tags = {
    "Name" : "ftb-ecs-api-vpce"
  }
  private_dns_enabled = true
}


// Create ECR repository where Client docker file will be uploaded
resource "aws_ecr_repository" "client_ecr_repository" {
  name = "ftb-client"
}
// Only keep the 5 latest images in our ECR repository
resource "aws_ecr_lifecycle_policy" "ecr_lifecycle_policy" {
  repository = aws_ecr_repository.client_ecr_repository.name

  policy = <<EOF
{
    "rules": [
        {
            "rulePriority": 1,
            "description": "Keep last 5 images",
            "selection": {
                "tagStatus": "tagged",
                "tagPrefixList": ["ftb"],
                "countType": "imageCountMoreThan",
                "countNumber": 5
            },
            "action": {
                "type": "expire"
            }
        }
    ]
}
EOF
}

// Security group for service allowing communication on HTTP port
resource "aws_security_group" "ecs_client_service_sg" {
  name        = "fargate-terraform-blog-ECS-Service-sg"
  description = "Allow incoming http traffic"
  vpc_id      = var.vpc_id

  ingress {
    from_port        = 80
    to_port          = 80
    protocol         = "TCP"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
  egress {
    from_port        = 80
    to_port          = 80
    protocol         = "TCP"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
    ingress {
    from_port        = 443
    to_port          = 443
    protocol         = "TCP"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
  egress {
    from_port        = 443
    to_port          = 443
    protocol         = "TCP"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

// Create ECS cluster
resource "aws_ecs_cluster" "client_cluster" {
  name = "ftb-Client-cluster"
}

// Create the task execution role
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ftbClientECSTaskExecutionRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      // The underlying statement allows the ecs tasks to assume this role. Otherwise AWS will block it by default
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}
resource "aws_iam_policy" "custom_policy" {
  name        = "ftbClientECSTaskExecutionRole-policy"
  description = "Custom IAM policy for Fargate client task execution role"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action   = ["ecs:RunTask", "ecs:StopTask", "ecs:DescribeTasks", "ssm:GetParameters", "ecr:GetAuthorizationToken", "ecr:BatchCheckLayerAvailability", "ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage"],
        Effect   = "Allow",
        Resource = "*",
      },
      {
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"],
        Effect   = "Allow",
        Resource = "arn:aws:logs:*:*:*",
      }
    ],
  })
}
resource "aws_iam_role_policy_attachment" "custom_policy_attachment" {
  policy_arn = aws_iam_policy.custom_policy.arn
  role       = aws_iam_role.ecs_task_execution_role.name
}

resource "aws_iam_role" "ecs_task_role" {
  name = "ftbClientECSTaskRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

// Define to Fargate what it needs to run by creating a task definition
// We don't link the task definition to the service since if we would update other parts of the infra
// Terraform wants to udpate the task definition again. This is just used to create the resource.
resource "aws_ecs_task_definition" "client_task_definition" {
  container_definitions = jsonencode([{
    essential    = true,
    image        = aws_ecr_repository.client_ecr_repository.repository_url,
    name         = "ftb-client-container",
    portMappings = [{ containerPort = 80 }]
  }])
  network_mode             = "awsvpc"
  cpu                      = 256
  family                   = "ftb-client-task-definition"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn
  memory                   = 512
  requires_compatibilities = ["FARGATE"]
}
// This parts is to help is in further infrastructure deployments.
// Image you create updates in another part of your infra (ex. create an s3 bucket). Terraform needs to know
// that the task definition linked to the service should always be the one with the latest revision.
// To achieve this we fetch the latest task definition here and link it to our service.
// It's important to not link the task definition we created above since that ARN will be linked to revision 1
data "aws_ecs_task_definition" "previous" {
  count           = var.first_run == "0" ? 1 : 0
  task_definition = "ftb-client-task-definition"
}
// Create te service
resource "aws_ecs_service" "client_ecs_service" {
  cluster         = aws_ecs_cluster.client_cluster.name
  name            = "ftb-client-service"
  launch_type     = "FARGATE"
  task_definition = var.first_run == "1" ? aws_ecs_task_definition.client_task_definition.arn : var.first_run == "0" ? data.aws_ecs_task_definition.previous[0].arn : ""

  desired_count = 1
  network_configuration {
    security_groups = [aws_security_group.ecs_client_service_sg.id]
    subnets         = split(",", var.subnet_ids)
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.alb_client_target_group.arn
    container_name   = "ftb-client-container"
    container_port   = 80
  }
}
