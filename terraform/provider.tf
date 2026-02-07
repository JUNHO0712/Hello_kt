# AWS 및 키 페어 설정

provider "aws" {
  region = var.aws_region
}
# SSH 키 생성
resource "tls_private_key" "deployer" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# AWS에 공개키 등록
resource "aws_key_pair" "deployer" {
  key_name   = "k3s-deployer"
  public_key = tls_private_key.deployer.public_key_openssh
}

# [추가 필수] 테라폼이 만든 열쇠를 내 컴퓨터에 실물 .pem 파일로 저장
resource "local_file" "ssh_key" {
  content         = tls_private_key.deployer.private_key_pem
  filename        = "${path.module}/k3s-deployer.pem"
  file_permission = "0600"
}