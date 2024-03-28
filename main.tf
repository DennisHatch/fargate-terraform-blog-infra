// When you create a Fargate task you need to link an ALB to access the container.
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
  name               = "ftb-alb-client"
  load_balancer_type = "application"
  security_groups = [
    aws_security_group.ftb_client_alb_sg.id
  ]
  subnets = split(",", var.subnet_ids)
}
// Health check endpoint should be defined for your specific application
// Instances will go unhealthy when the healthcheck fails
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
    port                = 80
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
// This is only necessary if you deploy ECS in a private subnet
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
resource "aws_vpc_endpoint" "s3_api_vpce_gw" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.eu-west-1.s3"
  vpc_endpoint_type = "Gateway"
  tags = {
    "Name" : "ftb-ecs-api-s3-gw"
  }
}
// Here we link the default routing table to the VPC GW Endpoint.
// This makes sure that our network can route traffic from ECR to S3
resource "aws_vpc_endpoint_route_table_association" "example" {
  vpc_endpoint_id = aws_vpc_endpoint.s3_api_vpce_gw.id
  route_table_id  = var.routing_table_id
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
// ECR stores image layers in S3
resource "aws_vpc_endpoint" "ecr_s3_vpce" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.eu-west-1.s3"
  vpc_endpoint_type = "Gateway"

  tags = {
    "Name" : "ftb-ecs-s3"
  }
}

resource "aws_vpc_endpoint" "ecr_logs_vpce" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.eu-west-1.logs"
  vpc_endpoint_type = "Interface"
  security_group_ids = [
    aws_security_group.ecs_vpce_service_sg.id
  ]
  subnet_ids = split(",", var.subnet_ids)
  private_dns_enabled = true

  tags = {
    "Name" : "ftb-ecs-logs"
  }
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

// Start making the ECR
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

// Start making the ECS
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
// Create a cloudwatch log group our containers can log into
resource "aws_cloudwatch_log_group" "yada" {
  name              = "/ecs/ftb/client"
  retention_in_days = 7
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
resource "aws_iam_policy" "custom_policy_task_execution_role" {
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
resource "aws_iam_policy" "custom_policy_task_role" {
  name        = "ftbClientECSTaskRole-policy"
  description = "Custom IAM policy for Fargate client task role"

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
resource "aws_iam_role_policy_attachment" "custom_policy_attachment_task_execution_role" {
  policy_arn = aws_iam_policy.custom_policy_task_execution_role.arn
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
resource "aws_iam_role_policy_attachment" "custom_policy_attachment_task_role" {
  policy_arn = aws_iam_policy.custom_policy_task_role.arn
  role       = aws_iam_role.ecs_task_role.name
}
// Important that we add the lifecycle rule to ignore all changes.
// This will prevent a new task definition update every time we deploy our infrastructure
// This is needed since our Terraform state tracks the task definition revision number, which will change whenever we push
resource "aws_ecs_task_definition" "client_task_definition" {
  container_definitions = jsonencode([{
    essential    = true,
    image        = aws_ecr_repository.client_ecr_repository.repository_url,
    name         = "ftb-client-container",
    logConfiguration : {
      "logDriver" : "awslogs",
      "options" : {
        "awslogs-group" : "/ecs/ftb/client",
        "awslogs-region" : "eu-west-1",
        "awslogs-stream-prefix" : "/ecs/ftb/client"
      }
    }
    portMappings = [{ containerPort = 80,
        hostPort: 80, }]  }])
  network_mode             = "awsvpc"
  cpu                      = 256
  family                   = "ftb-client-task-definition"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn
  memory                   = 512
  requires_compatibilities = ["FARGATE"]
  lifecycle {
    ignore_changes = all
  }
}
// Create te service
resource "aws_ecs_service" "client_ecs_service" {
  cluster         = aws_ecs_cluster.client_cluster.name
  name            = "ftb-client-service"
  launch_type     = "FARGATE"
  task_definition = aws_ecs_task_definition.client_task_definition.arn

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

// Add an auto scaling rule.
resource "aws_appautoscaling_target" "ecs_service_target" {
  max_capacity       = 10
  min_capacity       = 1
  resource_id        = "service/${aws_ecs_cluster.client_cluster.name}/${aws_ecs_service.client_ecs_service.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "ecs_service_scaling_policy" {
  name               = "ftb-ecs-service-scaling-policy"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_service_target.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_service_target.scalable_dimension
  service_namespace  = "ecs"

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    scale_in_cooldown  = 60
    scale_out_cooldown = 60
    target_value       = 70
  }
}
