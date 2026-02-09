# EC2 인스턴스, 보안 그룹 (실제 서버)

# 보안 그룹: 80번(HTTP)과 22번(SSH) 문을 엽니다.
resource "aws_security_group" "web_sg" {
  name = "web_server_sg"
  vpc_id = aws_vpc.main.id
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
    cidr_blocks = ["0.0.0.0/0"] # 실제로는 본인 IP만 허용하는 게 좋습니다.
  }

 # Node Exporter -  서버의 건강 상태 수집기
  ingress {
    from_port       = 9100
    to_port         = 9100
    protocol        = "tcp"
    # 모니터링 서버만 접근 허용
    security_groups = [aws_security_group.monitoring_sg.id] 
  
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
# 모니터링 서버 전용 보안 그룹 
resource "aws_security_group" "monitoring_sg" {
  name = "monitoring_server_sg"
  vpc_id = aws_vpc.main.id
  ingress {
    from_port   = 9090 # 프로메테우스 기본 포트
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22 # SSH 접속용            
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] 
    description = "Grafana Access"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"] 
  }
}
# EC2 설정에 보안 그룹 연결
# 통합된 EC2 생성 코드
resource "aws_instance" "web_server" {
  count                  = 2
  ami                    = "ami-040c33c6a51fd5d96" 
  instance_type          = "t3.micro"
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  subnet_id = element([aws_subnet.private_1.id, aws_subnet.private_2.id], count.index)
  tags = { 
    Name = "My-Web-Server-${count.index}" 
  }
}
resource "aws_instance" "monitoring_server" {
  ami                    = "ami-040c33c6a51fd5d96" # 동일한 Ubuntu 이미지 사용 [cite: 2, 5]
  instance_type          = "t3.micro"             # 프로메테우스는 메모리를 많이 쓰므로 t2.medium 추천
  vpc_security_group_ids = [aws_security_group.monitoring_sg.id]
  subnet_id            = aws_subnet.public_1.id 
  iam_instance_profile = aws_iam_instance_profile.monitoring_profile.name 
  tags = {
    Name = "Monitoring-Server-Prometheus" # 모니터링 전용 태그 [cite: 3]
  }
}

# 1. 모니터링 서버용 역할
resource "aws_iam_role" "monitoring_role" {
  name = "monitoring_server_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

# 2. EC2 정보를 읽을 수 있는 권한 부여 (Read Only)
resource "aws_iam_role_policy_attachment" "ec2_read" {
  role       = aws_iam_role.monitoring_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess"
}

# 3. EC2에 이 신분증을 부착할 '프로필' 생성
resource "aws_iam_instance_profile" "monitoring_profile" {
  name = "monitoring_instance_profile"
  role = aws_iam_role.monitoring_role.name
}
