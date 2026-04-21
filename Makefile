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
ROS2_BASE_IMAGE := $(IMAGE_PREFIX)/l4t-ros2-base-$(IMAGE_SUFFIX):latest

CALIB_PREP_IMAGE := $(IMAGE_PREFIX)/calib-lidar-imu-init-prep-$(IMAGE_SUFFIX):latest

CALIB_PREP_ARCHIVE := $(IMAGE_DIR)/calib-lidar-imu-init-prep-$(IMAGE_SUFFIX).tar

BASE_REMOTE_BUILD_DIR := $(REMOTE_DIR)/l4t-ros2-base
CALIB_REMOTE_BUILD_DIR := $(REMOTE_DIR)/calib-native
LIO_REMOTE_BUILD_DIR := $(REMOTE_DIR)/lio-native
PX4_CONNECTOR_REMOTE_BUILD_DIR := $(REMOTE_DIR)/px4-connector-native

BASE_CONTEXT_FILES := dockerfiles
LIO_CONTEXT_FILES := dockerfiles lidar_connector
PX4_CONNECTOR_CONTEXT_FILES := dockerfiles px4_connector
CALIB_NATIVE_CONTEXT_FILES := dockerfiles

# ==============================================================================
# Shipping macro
# ==============================================================================
# ship-context-to-device: copy only required build context to device
# $(1) = remote build directory
# $(2) = file and directory list relative to repo root
define ship-context-to-device
  @ssh $(SSH_OPTS) $(DEVICE_USER)@$(DEVICE_IP) "rm -rf $(1) && mkdir -p $(1)"
  @rsync -avzR -e "ssh $(SSH_OPTS)" $(2) $(DEVICE_USER)@$(DEVICE_IP):$(1)/
endef

# ship-calib-native-to-device: copy prep archive and minimal native context
# $(1) = prep archive path (local)
# $(2) = remote build directory
define ship-calib-native-to-device
  @ssh $(SSH_OPTS) $(DEVICE_USER)@$(DEVICE_IP) "rm -rf $(2) && mkdir -p $(2)"
  @scp $(SSH_OPTS) $(1) $(DEVICE_USER)@$(DEVICE_IP):$(REMOTE_DIR)/
  @rsync -avzR -e "ssh $(SSH_OPTS)" $(CALIB_NATIVE_CONTEXT_FILES) $(DEVICE_USER)@$(DEVICE_IP):$(2)/
endef

# ==============================================================================
# Build targets
# ==============================================================================

.PHONY: docker-build-base-jetson
docker-build-base-jetson: check-network
	@echo "[1/2] Shipping build context to $(DEVICE_USER)@$(DEVICE_IP)..."
	$(call ship-context-to-device,$(BASE_REMOTE_BUILD_DIR),$(BASE_CONTEXT_FILES))
	@echo "[2/2] Building shared L4T ROS2 base image on Jetson..."
	@ssh $(SSH_OPTS) $(DEVICE_USER)@$(DEVICE_IP) "cd $(BASE_REMOTE_BUILD_DIR) && docker build --network=host -f dockerfiles/l4t_ros2_base.Dockerfile -t $(ROS2_BASE_IMAGE) ."

.PHONY: docker-build-lio-jetson
docker-build-lio-jetson: check-network
	@echo "[1/3] Shipping build context to $(DEVICE_USER)@$(DEVICE_IP)..."
	$(call ship-context-to-device,$(LIO_REMOTE_BUILD_DIR),$(LIO_CONTEXT_FILES))
	@echo "[2/3] Building shared L4T ROS2 base image on Jetson..."
	@ssh $(SSH_OPTS) $(DEVICE_USER)@$(DEVICE_IP) "cd $(LIO_REMOTE_BUILD_DIR) && docker build --network=host -f dockerfiles/l4t_ros2_base.Dockerfile -t $(ROS2_BASE_IMAGE) ."
	@echo "[3/3] Building final LIO image natively on Jetson..."
	@ssh $(SSH_OPTS) $(DEVICE_USER)@$(DEVICE_IP) "cd $(LIO_REMOTE_BUILD_DIR) && docker build --network=host -f dockerfiles/lio.Dockerfile --build-arg BASE_IMAGE=$(ROS2_BASE_IMAGE) -t $(LIO_IMAGE) ."

.PHONY: docker-build-px4-connector-jetson
docker-build-px4-connector-jetson: check-network
	@echo "[1/3] Shipping build context to $(DEVICE_USER)@$(DEVICE_IP)..."
	$(call ship-context-to-device,$(PX4_CONNECTOR_REMOTE_BUILD_DIR),$(PX4_CONNECTOR_CONTEXT_FILES))
	@echo "[2/3] Building shared L4T ROS2 base image on Jetson..."
	@ssh $(SSH_OPTS) $(DEVICE_USER)@$(DEVICE_IP) "cd $(PX4_CONNECTOR_REMOTE_BUILD_DIR) && docker build --network=host -f dockerfiles/l4t_ros2_base.Dockerfile -t $(ROS2_BASE_IMAGE) ."
	@echo "[3/3] Building final PX4 image natively on Jetson..."
	@ssh $(SSH_OPTS) $(DEVICE_USER)@$(DEVICE_IP) "cd $(PX4_CONNECTOR_REMOTE_BUILD_DIR) && docker build --network=host -f dockerfiles/px4_connector.Dockerfile --build-arg BASE_IMAGE=$(ROS2_BASE_IMAGE) -t $(PX4_CONNECTOR_IMAGE) ."


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
	$(call ship-calib-native-to-device,$(CALIB_PREP_ARCHIVE),$(CALIB_REMOTE_BUILD_DIR))
	@echo "[3/4] Loading calibration prep image on Jetson..."
	@ssh $(SSH_OPTS) $(DEVICE_USER)@$(DEVICE_IP) "docker load -i $(REMOTE_DIR)/$(notdir $(CALIB_PREP_ARCHIVE))"
	@echo "[4/4] Building final calibration image natively on Jetson..."
	@ssh $(SSH_OPTS) $(DEVICE_USER)@$(DEVICE_IP) "docker build --network=host -f $(CALIB_REMOTE_BUILD_DIR)/dockerfiles/calib_lidar_imu_init.native.Dockerfile --build-arg PREP_IMAGE=$(CALIB_PREP_IMAGE) -t $(CALIB_IMAGE) $(CALIB_REMOTE_BUILD_DIR)"


.PHONY: docker-test-lio-jetson
docker-test-lio-jetson:
	$(DOCKER) run --rm \
		--net=host \
		--ipc=host \
		$(LIO_IMAGE)

.PHONY: check-bag docker-test-calib-jetson
check-bag:
	@if [ -z "$(strip $(BAG))" ]; then \
		echo "BAG is required. Usage: make docker-test-calib-jetson BAG=calibration.bag"; \
		exit 1; \
	fi

docker-test-calib-jetson: check-bag
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


.PHONY: docker-test-px4-connector-jetson
docker-test-px4-connector-jetson:
	$(DOCKER) run --rm \
		--net=host \
		--ipc=host \
		--privileged \
		$(PX4_CONNECTOR_IMAGE)


.PHONY: docker-test-px4-connector-jetson-shell
docker-test-px4-connector-jetson-shell:
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
