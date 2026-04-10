DOCKER := docker
PLATFORM := linux/arm64
IMAGE_PREFIX ?= vtol
IMAGE_SUFFIX ?= jetson
DATA_DIR ?= $(CURDIR)/data

BAG ?=
LAUNCH ?= calib_with_imu.launch
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

CALIB_PREP_IMAGE := $(IMAGE_PREFIX)/calib-lidar-imu-init-prep-$(IMAGE_SUFFIX):latest
LIO_PREP_IMAGE := $(IMAGE_PREFIX)/lio-prep-$(IMAGE_SUFFIX):latest
PX4_CONNECTOR_PREP_IMAGE := $(IMAGE_PREFIX)/px4-connector-prep-$(IMAGE_SUFFIX):latest

CALIB_PREP_ARCHIVE := $(IMAGE_DIR)/calib-lidar-imu-init-prep-$(IMAGE_SUFFIX).tar
LIO_PREP_ARCHIVE := $(IMAGE_DIR)/lio-prep-$(IMAGE_SUFFIX).tar
PX4_CONNECTOR_PREP_ARCHIVE := $(IMAGE_DIR)/px4-connector-prep-$(IMAGE_SUFFIX).tar

CALIB_REMOTE_BUILD_DIR := $(REMOTE_DIR)/calib-native
LIO_REMOTE_BUILD_DIR := $(REMOTE_DIR)/lio-native
PX4_CONNECTOR_REMOTE_BUILD_DIR := $(REMOTE_DIR)/px4-connector-native

# ==============================================================================
# Build targets
# ==============================================================================

.PHONY: docker-build-lio-jetson
docker-build-lio-jetson: check-network
	@echo "[1/4] Building prep image locally for $(PLATFORM)..."
	@mkdir -p $(IMAGE_DIR)
	$(DOCKER) run --rm --privileged tonistiigi/binfmt --install arm64 || true
	$(DOCKER) buildx build \
		--platform $(PLATFORM) \
		-f dockerfiles/lio.perp.Dockerfile \
		--target prep \
		-t $(LIO_PREP_IMAGE) \
		--output type=docker,dest=$(LIO_PREP_ARCHIVE) \
		.
	@echo "[2/4] Shipping prep image and native Dockerfile to $(DEVICE_USER)@$(DEVICE_IP)..."
	@ssh $(SSH_OPTS) $(DEVICE_USER)@$(DEVICE_IP) "rm -rf $(LIO_REMOTE_BUILD_DIR) && mkdir -p $(LIO_REMOTE_BUILD_DIR)/dockerfiles"
	@scp $(SSH_OPTS) $(LIO_PREP_ARCHIVE) $(DEVICE_USER)@$(DEVICE_IP):$(REMOTE_DIR)/
	@scp $(SSH_OPTS) dockerfiles/lio.native.Dockerfile dockerfiles/ros_entrypoint.sh $(DEVICE_USER)@$(DEVICE_IP):$(LIO_REMOTE_BUILD_DIR)/dockerfiles/
	@echo "[3/4] Loading prep image on Jetson..."
	@ssh $(SSH_OPTS) $(DEVICE_USER)@$(DEVICE_IP) "docker load -i $(REMOTE_DIR)/$(notdir $(LIO_PREP_ARCHIVE))"
	@echo "[4/4] Building final LIO image natively on Jetson..."
	@ssh $(SSH_OPTS) $(DEVICE_USER)@$(DEVICE_IP) "docker build --network=host -f $(LIO_REMOTE_BUILD_DIR)/dockerfiles/lio.native.Dockerfile --build-arg PREP_IMAGE=$(LIO_PREP_IMAGE) -t $(LIO_IMAGE) $(LIO_REMOTE_BUILD_DIR)"

.PHONY: docker-build-px4-connector-jetson
docker-build-px4-connector-jetson: check-network
	@echo "[1/4] Building PX4 prep image locally for $(PLATFORM)..."
	@mkdir -p $(IMAGE_DIR)
	$(DOCKER) run --rm --privileged tonistiigi/binfmt --install arm64 || true
	$(DOCKER) buildx build \
		--platform $(PLATFORM) \
		-f dockerfiles/px4_connector.perp.Dockerfile \
		--target prep \
		-t $(PX4_CONNECTOR_PREP_IMAGE) \
		--output type=docker,dest=$(PX4_CONNECTOR_PREP_ARCHIVE) \
		.
	@echo "[2/4] Shipping PX4 prep image and native Dockerfile to $(DEVICE_USER)@$(DEVICE_IP)..."
	@ssh $(SSH_OPTS) $(DEVICE_USER)@$(DEVICE_IP) "rm -rf $(PX4_CONNECTOR_REMOTE_BUILD_DIR) && mkdir -p $(PX4_CONNECTOR_REMOTE_BUILD_DIR)/dockerfiles"
	@scp $(SSH_OPTS) $(PX4_CONNECTOR_PREP_ARCHIVE) $(DEVICE_USER)@$(DEVICE_IP):$(REMOTE_DIR)/
	@scp $(SSH_OPTS) dockerfiles/px4_connector.native.Dockerfile dockerfiles/px4_connector_entrypoint.sh $(DEVICE_USER)@$(DEVICE_IP):$(PX4_CONNECTOR_REMOTE_BUILD_DIR)/dockerfiles/
	@echo "[3/4] Loading PX4 prep image on Jetson..."
	@ssh $(SSH_OPTS) $(DEVICE_USER)@$(DEVICE_IP) "docker load -i $(REMOTE_DIR)/$(notdir $(PX4_CONNECTOR_PREP_ARCHIVE))"
	@echo "[4/4] Building final PX4 image natively on Jetson..."
	@ssh $(SSH_OPTS) $(DEVICE_USER)@$(DEVICE_IP) "docker build --network=host -f $(PX4_CONNECTOR_REMOTE_BUILD_DIR)/dockerfiles/px4_connector.native.Dockerfile --build-arg PREP_IMAGE=$(PX4_CONNECTOR_PREP_IMAGE) -t $(PX4_CONNECTOR_IMAGE) $(PX4_CONNECTOR_REMOTE_BUILD_DIR)"


.PHONY: docker-build-calib-jetson
docker-build-calib-jetson: check-network
	@echo "[1/4] Building calibration prep image locally for $(PLATFORM)..."
	@mkdir -p $(IMAGE_DIR)
	$(DOCKER) run --rm --privileged tonistiigi/binfmt --install arm64 || true
	$(DOCKER) buildx build \
		--platform $(PLATFORM) \
		-f dockerfiles/calib_lidar_imu_init.perp.Dockerfile \
		--target prep \
		-t $(CALIB_PREP_IMAGE) \
		--output type=docker,dest=$(CALIB_PREP_ARCHIVE) \
		.
	@echo "[2/4] Shipping calibration prep image and native Dockerfile to $(DEVICE_USER)@$(DEVICE_IP)..."
	@ssh $(SSH_OPTS) $(DEVICE_USER)@$(DEVICE_IP) "rm -rf $(CALIB_REMOTE_BUILD_DIR) && mkdir -p $(CALIB_REMOTE_BUILD_DIR)/dockerfiles"
	@scp $(SSH_OPTS) $(CALIB_PREP_ARCHIVE) $(DEVICE_USER)@$(DEVICE_IP):$(REMOTE_DIR)/
	@scp $(SSH_OPTS) -r dockerfiles/* $(DEVICE_USER)@$(DEVICE_IP):$(CALIB_REMOTE_BUILD_DIR)/dockerfiles/
	@echo "[3/4] Loading calibration prep image on Jetson..."
	@ssh $(SSH_OPTS) $(DEVICE_USER)@$(DEVICE_IP) "docker load -i $(REMOTE_DIR)/$(notdir $(CALIB_PREP_ARCHIVE))"
	@echo "[4/4] Building final calibration image natively on Jetson..."
	@ssh $(SSH_OPTS) $(DEVICE_USER)@$(DEVICE_IP) "docker build --network=host -f $(CALIB_REMOTE_BUILD_DIR)/dockerfiles/calib_lidar_imu_init.native.Dockerfile --build-arg PREP_IMAGE=$(CALIB_PREP_IMAGE) -t $(CALIB_IMAGE) $(CALIB_REMOTE_BUILD_DIR)"


.PHONY: docker-run-lio-jetson
docker-run-lio-jetson:
	$(DOCKER) run --rm \
		--net=host \
		--ipc=host \
		$(LIO_IMAGE)

.PHONY: check-bag docker-run-calib-jetson
check-bag:
	@if [ -z "$(strip $(BAG))" ]; then \
		echo "BAG is required. Usage: make docker-run-calib-jetson BAG=calibration.bag"; \
		exit 1; \
	fi

docker-run-calib-jetson: check-bag
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


.PHONY: docker-run-px4-connector-jetson-shell
docker-run-px4-connector-jetson-shell:
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
