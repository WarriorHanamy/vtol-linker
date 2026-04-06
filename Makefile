DOCKER := docker
PLATFORM := linux/arm64
IMAGE_PREFIX ?= vtol
IMAGE_SUFFIX ?= jetson
DATA_DIR ?= $(CURDIR)/data

BAG ?=
LAUNCH ?= mid360.launch
PLAY_RATE ?=

# Deployment configuration (fixed convention)
HOST_IP := 192.168.55.100
DEVICE_IP := 192.168.55.1
DEVICE_USER := nv
IMAGE_DIR := /tmp/vtol-images
REMOTE_DIR := /tmp/vtol-images
SSH_KEY := ~/.ssh/id_ed25519
SSH_OPTS := $(if $(wildcard $(SSH_KEY)),-i $(SSH_KEY),)

CALIB_IMAGE := $(IMAGE_PREFIX)/calib-lidar-imu-init-$(IMAGE_SUFFIX):latest
LIO_IMAGE := $(IMAGE_PREFIX)/lio-$(IMAGE_SUFFIX):latest
PX4_CONNECTOR_IMAGE := $(IMAGE_PREFIX)/px4-connector-$(IMAGE_SUFFIX):latest

# ==============================================================================
# Build targets
# ==============================================================================

.PHONY: docker-build-lio-jetson
docker-build-lio-jetson:
	$(DOCKER) run --rm --privileged tonistiigi/binfmt --install arm64 || true
	$(DOCKER) buildx build \
		--platform $(PLATFORM) \
		-f dockerfiles/lio.dockerfile \
		-t $(LIO_IMAGE) \
		--load \
		.


.PHONY: docker-build-px4-connector-jetson
docker-build-px4-connector-jetson:
	$(DOCKER) run --rm --privileged tonistiigi/binfmt --install arm64 || true
	$(DOCKER) buildx build \
		--platform $(PLATFORM) \
		-f dockerfiles/px4_connector.dockerfile \
		-t $(PX4_CONNECTOR_IMAGE) \
		--load \
		.


.PHONY: docker-build-calib-jetson
docker-build-calib-jetson:
	$(DOCKER) run --rm --privileged tonistiigi/binfmt --install arm64 || true
	$(DOCKER) buildx build \
		--platform $(PLATFORM) \
		-f calibration/dockerfiles/calib_lidar_imu_init.dockerfile \
		-t $(CALIB_IMAGE) \
		--load \
		.


.PHONY: docker-run-calib
docker-run-calib:
ifndef BAG
	$(error BAG is required. Usage: make docker-run-calib BAG=calibration.bag)
endif
	@mkdir -p $(DATA_DIR)
	$(DOCKER) run --rm \
		--net=host \
		--ipc=host \
		-v $(DATA_DIR):/data:rw \
		$(CALIB_IMAGE) \
		/usr/local/bin/calib_run.sh \
		$(if $(LAUNCH),--launch $(LAUNCH)) \
		$(if $(PLAY_RATE),--rate $(PLAY_RATE)) \
		/data/$(BAG)


.PHONY: docker-run-px4-connector-jetson
docker-run-px4-connector-jetson:
	$(DOCKER) run --rm \
		--net=host \
		--ipc=host \
		--privileged \
		$(PX4_CONNECTOR_IMAGE)


.PHONY: docker-run-px4-connector-jetson-test
docker-run-px4-connector-jetson-test:
	$(DOCKER) run --rm -it \
		--net=host \
		--ipc=host \
		--privileged \
		--entrypoint bash \
		$(PX4_CONNECTOR_IMAGE)


.PHONY: detect-px4-serial
detect-px4-serial:
	@echo "[INFO] Scanning for serial devices..."
	@echo "[INFO] UART (ttyTHS):"
	@ls -la /dev/ttyTHS* 2>/dev/null || echo "  (none)"
	@echo "[INFO] USB (ttyACM):"
	@ls -la /dev/ttyACM* 2>/dev/null || echo "  (none)"
	@echo "[INFO] USB-Serial (ttyUSB):"
	@ls -la /dev/ttyUSB* 2>/dev/null || echo "  (none)"
	@echo ""
	@echo "[INFO] To create fixed symlink, run on Jetson:"
	@echo "  udevadm info -a -n /dev/ttyTHS1 | grep KERNELS"
	@echo "  echo 'KERNELS==\"3100000.serial\", SYMLINK+=\"px4\"' | sudo tee /etc/udev/rules.d/99-px4.rules"
	@echo "  sudo udevadm control --reload-rules && sudo udevadm trigger"

# ==============================================================================
# Deployment targets (fixed convention: host=192.168.55.100, device=192.168.55.1)
# ==============================================================================


.PHONY: check-network
check-network:
	@echo "[INFO] Checking network convention..."
	@echo "[INFO] Host IP: $(HOST_IP)"
	@echo "[INFO] Device IP: $(DEVICE_IP)"
	@if ! ip addr show | grep -q "inet $(HOST_IP)/"; then \
		echo "[ERROR] Host does not have IP $(HOST_IP)"; \
		echo "[ERROR] This is a deployment convention - host must have $(HOST_IP)"; \
		exit 1; \
	fi
	@echo "[INFO] Host IP $(HOST_IP) found"
	@if ! ping -c 2 -W 3 $(DEVICE_IP) >/dev/null 2>&1; then \
		echo "[ERROR] Cannot reach device at $(DEVICE_IP)"; \
		echo "[ERROR] Check physical connection and device power"; \
		exit 1; \
	fi
	@echo "[INFO] Device $(DEVICE_IP) reachable"
	@echo "[INFO] Network convention check passed"


.PHONY: export-images
export-images: check-network
	@echo "[INFO] Exporting Docker images..."
	@mkdir -p $(IMAGE_DIR)
	@for image in $(LIO_IMAGE) $(PX4_CONNECTOR_IMAGE) $(CALIB_IMAGE); do \
		filename=$$(echo "$$image" | tr '/:' '--').tar; \
		echo "[INFO] Exporting: $$image -> $$filename"; \
		$(DOCKER) save -o $(IMAGE_DIR)/$$filename $$image || exit 1; \
	done
	@echo "[INFO] Generating checksums..."
	@cd $(IMAGE_DIR) && sha256sum *.tar > checksums.sha256
	@echo "[INFO] Generating manifest..."
	@cd $(IMAGE_DIR) && \
		echo "# VTOL Docker Image Manifest" > manifest.txt && \
		echo "# Generated: $$(date -Iseconds)" >> manifest.txt && \
		echo "# Host: $$(hostname)" >> manifest.txt && \
		echo "" >> manifest.txt && \
		for image in $(LIO_IMAGE) $(PX4_CONNECTOR_IMAGE) $(CALIB_IMAGE); do \
			filename=$$(echo "$$image" | tr '/:' '--').tar; \
			echo "$$filename $$image" >> manifest.txt; \
		done
	@echo "[INFO] Export completed: $(IMAGE_DIR)"


.PHONY: transfer-images
transfer-images: export-images
	@echo "[INFO] Transferring images to $(DEVICE_USER)@$(DEVICE_IP)..."
	@ssh $(SSH_OPTS) $(DEVICE_USER)@$(DEVICE_IP) "mkdir -p $(REMOTE_DIR)"
	@for file in $(IMAGE_DIR)/*.tar $(IMAGE_DIR)/checksums.sha256 $(IMAGE_DIR)/manifest.txt; do \
		if [ -f "$$file" ]; then \
			filename=$$(basename "$$file"); \
			echo "[INFO] Transferring: $$filename"; \
			scp $(SSH_OPTS) -v "$$file" $(DEVICE_USER)@$(DEVICE_IP):$(REMOTE_DIR)/$$filename 2>&1 | \
				grep -E "^(.*%|Transferring|Bytes)" || true; \
		fi; \
	done
	@echo "[INFO] Transfer completed"


.PHONY: load-images
load-images:
	@echo "[INFO] Loading images on device..."
	@echo "[INFO] Run on device: cd $(REMOTE_DIR) && sha256sum -c checksums.sha256 && for f in *.tar; do docker load -i \$$f; done"


.PHONY: deploy-all
deploy-all: transfer-images
	@echo "[INFO] Deployment completed"
	@echo "[INFO] Images deployed to: $(DEVICE_IP):$(REMOTE_DIR)"
	@echo "[INFO] Next step on device:"
	@echo "[INFO]   cd $(REMOTE_DIR) && sha256sum -c checksums.sha256 && for f in *.tar; do docker load -i \$$f; done"


.PHONY: deploy-skip-build
deploy-skip-build: check-network
	@echo "[INFO] Deploying without build..."
	@if [ ! -d "$(IMAGE_DIR)" ] || [ -z "$$(ls $(IMAGE_DIR)/*.tar 2>/dev/null)" ]; then \
		echo "[ERROR] No exported images found in $(IMAGE_DIR)"; \
		echo "[ERROR] Run 'make export-images' first"; \
		exit 1; \
	fi
	@$(MAKE) --no-print-directory transfer-images
	@echo "[INFO] Deployment completed (build skipped)"
	@echo "[INFO] Images deployed to: $(DEVICE_IP):$(REMOTE_DIR)"
	@echo "[INFO] Next step on device:"
	@echo "[INFO]   cd $(REMOTE_DIR) && sha256sum -c checksums.sha256 && for f in *.tar; do docker load -i \$$f; done"