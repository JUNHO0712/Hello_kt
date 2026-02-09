# Ansible 인벤토리 파일 자동 생성
resource "local_file" "ansible_inventory" {
  content = <<-EOT
[master]
# 앱 서버는 프라이빗 서브넷에 있으므로 private_ip를 써야 합니다.
${aws_instance.web_server[0].private_ip} ansible_user=ubuntu ansible_ssh_private_key_file=../k3s-deployer.pem

[worker]
${aws_instance.web_server[1].private_ip} ansible_user=ubuntu ansible_ssh_private_key_file=../k3s-deployer.pem

[monitoring]
# 모니터링 서버는 외부에서 접속해야 하므로 public_ip를 씁니다.
${aws_instance.monitoring_server.public_ip} ansible_user=ubuntu ansible_ssh_private_key_file=../k3s-deployer.pem

[k3s_cluster:children]
master
worker

[k3s_cluster:vars]
ansible_user=ubuntu
ansible_ssh_private_key_file=../k3s-deployer.pem
# ★핵심: 모니터링 서버를 경유(ProxyJump)해서 프라이빗 서버로 접속하는 설정
ansible_ssh_common_args='-o StrictHostKeyChecking=no -o ProxyCommand="ssh -W %h:%p -q ubuntu@${aws_instance.monitoring_server.public_ip} -i ../k3s-deployer.pem"'
EOT

  filename   = "${path.module}/ansible/inventory/aws.ini"
  depends_on = [aws_instance.web_server, aws_instance.monitoring_server, local_file.ssh_key]
}