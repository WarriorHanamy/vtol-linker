DOCKER := docker
PLATFORM := linux/arm64
IMAGE_PREFIX ?= vtol
IMAGE_SUFFIX ?= jetson
DATA_DIR ?= $(CURDIR)/data

BAG ?=
LAUNCH ?= mid360.launch
PLAY_RATE ?=

CALIB_IMAGE := $(IMAGE_PREFIX)/calib-lidar-imu-init-$(IMAGE_SUFFIX):latest
LIO_IMAGE := $(IMAGE_PREFIX)/lio-$(IMAGE_SUFFIX):latest
PX4_CONNECTOR_IMAGE := $(IMAGE_PREFIX)/px4-connector-$(IMAGE_SUFFIX):latest

.PHONY: docker-build-lio-jetson docker-build-px4-connector-jetson docker-build-calib-jetson docker-run-calib

docker-build-lio-jetson:
	$(DOCKER) run --rm --privileged tonistiigi/binfmt --install arm64 || true
	$(DOCKER) buildx build \
		--platform $(PLATFORM) \
		-f dockerfiles/lio.dockerfile \
		-t $(LIO_IMAGE) \
		--load \
		.

docker-build-px4-connector-jetson:
	$(DOCKER) run --rm --privileged tonistiigi/binfmt --install arm64 || true
	$(DOCKER) buildx build \
		--platform $(PLATFORM) \
		-f dockerfiles/px4_connector.dockerfile \
		-t $(PX4_CONNECTOR_IMAGE) \
		--load \
		.

docker-build-calib-jetson:
	$(DOCKER) run --rm --privileged tonistiigi/binfmt --install arm64 || true
	$(DOCKER) buildx build \
		--platform $(PLATFORM) \
		-f calibration/dockerfiles/calib_lidar_imu_init.dockerfile \
		-t $(CALIB_IMAGE) \
		--load \
		.

docker-run-calib:
ifndef BAG
	$(error BAG is required. Usage: make docker-run-calib BAG=calibration.bag)
endif
	@mkdir -p $(DATA_DIR)
	$(DOCKER) run --rm \
		--net=host \
		-v $(DATA_DIR):/data:rw \
		$(CALIB_IMAGE) \
		/usr/local/bin/calib_run.sh \
		$(if $(LAUNCH),--launch $(LAUNCH)) \
		$(if $(PLAY_RATE),--rate $(PLAY_RATE)) \
		/data/$(BAG)
