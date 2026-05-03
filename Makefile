CLUSTER_NAME  ?= rt-platform
AWS_REGION    ?= us-east-1
NAMESPACE     ?= real-time-platform
ARGOCD_NS     ?= argocd

.PHONY: help \
        terraform-init terraform-plan terraform-apply terraform-destroy \
        kubeconfig update-context \
        argocd-password argocd-ui \
        status logs health-check get-all \
        port-forward port-forward-grafana port-forward-argocd \
        port-forward-api port-forward-ws \
        load-test \
		health-check \
        deploy cleanup

help:
	@echo ""
	@echo "Infrastructure"
	@echo "  make terraform-init     terraform init"
	@echo "  make terraform-plan     terraform plan  (export TF_VAR_* secrets first)"
	@echo "  make terraform-apply    staged apply - ArgoCD first, then everything else"
	@echo "  make terraform-destroy  full teardown via cleanup.sh"
	@echo ""
	@echo "Cluster"
	@echo "  make kubeconfig         configure kubectl for the EKS cluster"
	@echo "  make status             pod status across all namespaces"
	@echo "  make health-check       pod status + ArgoCD sync state"
	@echo "  make get-all            full resource list across all namespaces"
	@echo "  make logs SVC=api-gateway   tail logs for a specific service"
	@echo ""
	@echo "ArgoCD"
	@echo "  make argocd-password    print ArgoCD admin password"
	@echo "  make argocd-ui          port-forward ArgoCD UI to localhost:8088"
	@echo ""
	@echo "Port forwarding"
	@echo "  make port-forward       port-forward all services at once"
	@echo "  make port-forward-api   api-gateway        → localhost:5000"
	@echo "  make port-forward-ws    websocket-server   → localhost:8080"
	@echo "  make port-forward-argocd  argocd-server    → localhost:8088"
	@echo "  make port-forward-grafana grafana          → localhost:3000"
	@echo ""
	@echo "Testing"
	@echo "  make load-test          fire 100 test events at the API"
	@echo "  make health-check       full health check
	@echo ""
	@echo "Lifecycle"
	@echo "  make deploy             full provision + wait for ArgoCD sync"
	@echo "  make cleanup            destroy everything (prompts for confirmation)"
	@echo ""
	@echo "Deployments are fully automated."
	@echo "push code → CI builds + scans + updates kustomization.yaml → ArgoCD syncs cluster."
	@echo ""

# ── Infrastructure ────────────────────────────────────────────────────────────

terraform-init:
	cd terraform && terraform init

terraform-plan:
	@echo "Reminder: export sensitive variables before planning:"
	@echo "  export TF_VAR_db_username=..."
	@echo "  export TF_VAR_db_password=..."
	@echo "  export TF_VAR_redis_password=..."
	@echo "  export TF_VAR_grafana_admin_password=..."
	@echo "  export TF_VAR_github_token=..."
	@echo "  export TF_VAR_argocd_admin_password_bcrypt=..."
	@echo "  export TF_VAR_argocd_webhook_secret=..."
	@echo ""
	cd terraform && terraform plan

terraform-apply:
	@echo "==> Step 1: Core infrastructure (networking, ECR)..."
	cd terraform && terraform init
	cd terraform && terraform apply \
		-target=module.networking \
		-target=module.eks \
		-target=module.ecr \
		-auto-approve

	echo "==> EKS cluster module"
	cd terraform && terraform apply -auto-approve \
  		-target=module.eks
		
	@echo "==> Step 2: Configure kubectl..."
	aws eks update-kubeconfig --region $(AWS_REGION) --name $(shell cd terraform && terraform output -raw cluster_name)
	@echo "==> Step 3: Install Strimzi operator..."
	kubectl create namespace kafka --dry-run=client -o yaml | kubectl apply -f -
	kubectl apply -f "https://github.com/strimzi/strimzi-kafka-operator/releases/download/0.43.0/strimzi-cluster-operator-0.43.0.yaml" -n kafka
	kubectl wait deployment/strimzi-cluster-operator --for=condition=available --timeout=120s -n kafka
	@echo "==> Step 4: Remaining resources..."
	cd terraform && terraform apply -auto-approve

terraform-destroy:
	@chmod +x scripts/cleanup.sh
	@./scripts/cleanup.sh

# ── Cluster ───────────────────────────────────────────────────────────────────

kubeconfig:
	aws eks update-kubeconfig --region $(AWS_REGION) --name $(shell cd terraform && terraform output -raw cluster_name)

status:
	kubectl get pods -A

health-check:
	@chmod +x scripts/health-check.sh
	@./scripts/health-check.sh

get-all:
	@echo "==> $(NAMESPACE)..."
	@kubectl get all -n $(NAMESPACE)
	@echo ""
	@echo "==> Kafka..."
	@kubectl get all -n kafka
	@echo ""
	@echo "==> Redis..."
	@kubectl get all -n redis
	@echo ""
	@echo "==> Monitoring..."
	@kubectl get all -n monitoring
	@echo ""
	@echo "==> ArgoCD..."
	@kubectl get all -n $(ARGOCD_NS)
	@echo ""
	@echo "==> ArgoCD application status..."
	@kubectl get application -n $(ARGOCD_NS) \
		-o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status

logs:
	kubectl logs -f -l app=$(SVC) -n $(NAMESPACE) --all-containers

# ── ArgoCD ────────────────────────────────────────────────────────────────────

argocd-password:
	@kubectl get secret argocd-initial-admin-secret -n $(ARGOCD_NS) \
		-o jsonpath="{.data.password}" | base64 -d && echo

argocd-ui:
	@echo "ArgoCD UI → http://localhost:8088"
	@echo "Username:   admin"
	@echo "Password:   run 'make argocd-password'"
	kubectl port-forward svc/argocd-server -n $(ARGOCD_NS) 8088:80

# ── Port forwarding ───────────────────────────────────────────────────────────

port-forward:
	./scripts/port-forward.sh

port-forward-api:
	kubectl port-forward svc/api-gateway -n $(NAMESPACE) 5000:5000

port-forward-ws:
	kubectl port-forward svc/websocket-server -n $(NAMESPACE) 8080:8080

port-forward-argocd:
	kubectl port-forward svc/argocd-server -n $(ARGOCD_NS) 8088:80

port-forward-grafana:
	kubectl port-forward svc/kube-prometheus-stack-grafana -n monitoring 3000:80

port-forward-prometheus:
	kubectl port-forward svc/kube-prometheus-stack-prometheus -n monitoring 9090:9090

# ── Testing ───────────────────────────────────────────────────────────────────

load-test:
	./scripts/load-test.sh

# ── Lifecycle ─────────────────────────────────────────────────────────────────

deploy:
	./scripts/deploy.sh

cleanup:
	./scripts/cleanup.sh