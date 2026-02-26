fastapi 실행 명령어
uvicorn main:app --reload

fastapi==0.115.6
uvicorn[standard]==0.30.6


상세 가이드: 항상 Destroy 후 Apply 할 때의 루틴
[Step 1] 인프라 삭제 (S3와 락 테이블은 보존)
파일 주석: dynamodb.tf, variables.tf, backend.tf를 제외한 모든 .tf 파일의 내용을 /* ... */로 감싸 주석 처리합니다.

실행: terraform apply

S3 백엔드가 살아있는 상태이므로 별도의 옵션 없이 바로 실행됩니다.

서버, 네트워크, 람다 등이 모두 삭제됩니다.
+2

[Step 2] 인프라 다시 생성
파일 주석 해제: 모든 파일의 주석(/*, */)을 제거하여 원래 코드로 복구합니다.

실행: terraform apply

이미 S3에 tfstate가 연결되어 있으므로, 테라폼은 현재 인프라가 없음을 확인하고 새로 싹 생성합니다.


PEM 키 권한 복구: provider.tf에서 새로운 키가 생성될 수 있으므로, 다시 권한 설정을 수행합니다.

icacls .\Hello_kt.pem /inheritance:r
icacls .\Hello_kt.pem /grant:r "${env:USERNAME}:R"

앤서블 플레이북 실행
cd ../ansible
ansible -i inventory/aws.ini all -m ping
-> 먼저 연결 되었는지 확인, 되어있음 생략
ansible-playbook -i inventory/aws.ini site.yml
-> 전체 구축 실행 명령어 (k3s 설치 + 워커 조인 + 모니터링 등)

# 🔗 Ansible과 애플리케이션 배포 연동 구조

## 1. 전체 배포 파이프라인

본 프로젝트는 다음 파이프라인을 통해 애플리케이션이 배포됩니다.

```
Terraform → Ansible → K3s → Pods → External Access
```

### 상세 흐름

```
1. Terraform (인프라 프로비저닝)
   ├─ VPC / Subnet 생성
   ├─ EC2 인스턴스 생성 (Master, Worker ×2, Monitoring)
   ├─ Security Group 구성
   └─ Ansible Inventory 파일 자동 생성

2. Ansible (서버 구성 & 앱 배포)
   ├─ 시간 동기화 (Chrony)
   ├─ K3s Master 설치
   ├─ K3s Worker Join
   ├─ Node Exporter 설치
   ├─ Monitoring Stack 구성 (Prometheus + Grafana)
   └─ App Deployment (kubectl apply)

3. Kubernetes / K3s (컨테이너 오케스트레이션)
   ├─ Namespace 생성
   ├─ Deployment 생성 (replicas=2)
   ├─ Service 생성 (NodePort 30080)
   └─ Worker 노드에 Pod 분산 배치
```

---

## 2. Terraform → Ansible 연결 구조

Terraform은 인프라를 생성한 뒤, **Ansible Inventory 파일을 자동으로 생성**합니다.

```hcl
# terraform/ansible_gen.tf
resource "local_file" "ansible_inventory" {
  filename = "${path.module}/../ansible/inventory/aws.ini"
  # ...
}
```

생성되는 인벤토리 예시:

```ini
[master]
10.0.2.126

[worker]
10.0.3.27
10.0.4.185

[monitoring]
43.203.196.101

[k3s_cluster:children]
master
worker

[k3s_cluster:vars]
ansible_ssh_common_args='-o ProxyCommand="ssh -W %h:%p -q ubuntu@43.203.196.101 ..."'
```

Terraform이 생성한 EC2의 IP가 Ansible 배포 대상으로 자동 연결되며, Private Subnet의 노드들은 Monitoring 서버(Bastion)를 경유하여 접속합니다.

---

## 3. Ansible Role 구조

애플리케이션 배포는 `app_deploy` Role에서 수행됩니다.

```
ansible/
├── site.yml                          # 전체 플레이북
├── inventory/
│   └── aws.ini                       # Terraform이 자동 생성
├── group_vars/
│   └── all.yml                       # 전역 변수 (K3s 버전 등)
└── roles/
    ├── chrony/                       # 시간 동기화
    ├── k3s_master/                   # K3s Master 설치
    ├── k3s_worker/                   # K3s Worker Join
    ├── node_exporter/                # 메트릭 수집 에이전트
    ├── monitoring/                   # Prometheus + Grafana
    └── app_deploy/                   # ← 앱 배포 담당
         ├── defaults/main.yml        #    기본 변수 (이미지, 레플리카 수 등)
         ├── tasks/main.yml           #    배포 태스크
         └── templates/
              ├── namespace.yaml.j2   #    Namespace 매니페스트
              ├── deployment.yaml.j2  #    Deployment 매니페스트
              └── service.yaml.j2     #    Service 매니페스트
```

---

## 4. Ansible → Kubernetes 연결 방식

Ansible은 K3s Master 노드에 SSH 접속한 뒤 `kubectl` 명령을 실행하여 Kubernetes 리소스를 생성합니다.

```yaml
# site.yml (발췌)
- name: Deploy Lunch App to K3s
  hosts: master
  become: yes
  environment:
    KUBECONFIG: /etc/rancher/k3s/k3s.yaml
  roles:
    - app_deploy
```

`app_deploy` Role 내부 실행 순서:

```
1. Jinja2 템플릿 렌더링 → K8s 매니페스트 생성
2. kubectl apply -f namespace.yaml
3. kubectl apply -f deployment.yaml
4. kubectl apply -f service.yaml
5. kubectl rollout status 로 배포 완료 확인
```

> Ansible은 단순히 EC2에 접속하는 것이 아니라, Master 노드에서 `kubectl`을 실행하여 Kubernetes 리소스를 선언적으로 관리합니다.

---

## 5. GHCR 이미지 Pull 과정

Deployment에서 지정된 컨테이너 이미지:

```yaml
image: ghcr.io/hjh6709/lunch_app_second/lunch-api:latest
```

Pull 과정:

```
GitHub Actions (CI)
  └─ Docker Build & Push → GHCR

K3s Worker Node (CD)
  └─ containerd가 GHCR에서 이미지 Pull
     └─ Pod 내 컨테이너로 실행
```

```
GHCR ──Pull──→ K3s Node (containerd) ──→ Pod 실행
```

---

## 6. 실행 명령어 요약

```bash
# 1단계: 인프라 생성
cd terraform
terraform apply

# 2단계: 전체 설치 (K3s + 모니터링 + 앱 배포)
cd ../ansible
ansible-playbook -i inventory/aws.ini site.yml

# --- 또는 단계별 실행 ---

# K3s 클러스터만 설치
ansible-playbook -i inventory/aws.ini site.yml --tags k3s

# 모니터링만 설치
ansible-playbook -i inventory/aws.ini site.yml --tags monitoring

# 앱 배포만 실행
ansible-playbook -i inventory/aws.ini site.yml --tags deploy

# 클러스터 상태 검증
ansible-playbook -i inventory/aws.ini site.yml --tags verify
```

---

## 7. 계층별 역할 분리

| Layer | 역할 | 도구 |
|-------|------|------|
| **Infrastructure** | VPC, EC2, SG, NAT, Lambda 등 AWS 리소스 프로비저닝 | Terraform |
| **Configuration** | OS 설정, K3s 설치, 모니터링 구성, 앱 배포 | Ansible |
| **Orchestration** | 컨테이너 스케줄링, Pod 관리, Service 라우팅 | K3s (Kubernetes) |
| **Registry** | 컨테이너 이미지 빌드 및 저장 | GitHub Actions + GHCR |
| **Application** | 점심 메뉴 추천 API 서비스 | FastAPI (Python) |
