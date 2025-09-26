# kxboot-pipa - kexec-based bootloader for Xiaomi Pad 6
# Makefile for building initramfs

# Configuration
TARGET_ARCH := aarch64
HOST_ARCH := $(shell uname -m)

# Directories
BUILD_DIR := build
INIT_DIR := $(BUILD_DIR)/initramfs
SRC_DIR := $(BUILD_DIR)/src
DOWNLOAD_DIR := $(BUILD_DIR)/downloads

# Versions (can be overridden)
BUSYBOX_VERSION := 1.36.1
KEXEC_TOOLS_VERSION := 2.0.27

# URLs
BUSYBOX_URL := https://busybox.net/downloads/busybox-$(BUSYBOX_VERSION).tar.bz2
KEXEC_TOOLS_URL := https://www.kernel.org/pub/linux/utils/kernel/kexec/kexec-tools-$(KEXEC_TOOLS_VERSION).tar.xz

# Cross-compilation setup
ifeq ($(HOST_ARCH),aarch64)
    NEED_CROSS_COMPILE := no
    CROSS_COMPILE := 
else
    NEED_CROSS_COMPILE := yes
    CROSS_COMPILE := aarch64-linux-gnu-
endif

# Cross-compilation variables
CC := $(CROSS_COMPILE)gcc
CXX := $(CROSS_COMPILE)g++
AR := $(CROSS_COMPILE)ar
STRIP := $(CROSS_COMPILE)strip
ARCH := arm64

# Export variables for sub-makes
export CC CXX AR STRIP ARCH CROSS_COMPILE

# Colors for output
RED := \033[0;31m
GREEN := \033[0;32m
YELLOW := \033[1;33m
BLUE := \033[0;34m
NC := \033[0m

# Logging functions
define log
	@printf "$(BLUE)[INFO]$(NC) %s\n" "$(1)"
endef

define warn
	@printf "$(YELLOW)[WARN]$(NC) %s\n" "$(1)"
endef

define error
	@printf "$(RED)[ERROR]$(NC) %s\n" "$(1)" && exit 1
endef

define success
	@printf "$(GREEN)[SUCCESS]$(NC) %s\n" "$(1)"
endef

# Default target
.PHONY: all
all: initramfs

# Help target
.PHONY: help
help:
	@echo "kxboot-pipa - kexec-based bootloader for Xiaomi Pad 6"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@echo "  all          Build complete initramfs (default)"
	@echo "  busybox      Download and build busybox"
	@echo "  kexec-tools  Download and build kexec-tools"
	@echo "  kxmenu       Build kxmenu bootloader"
	@echo "  initramfs    Assemble final initramfs.cpio.zst"
	@echo "  android-boot Create Android boot image using build/zImage and boot.conf"
	@echo "  clean        Remove build artifacts but keep downloads"
	@echo "  distclean    Remove everything including downloads"
	@echo "  help         Show this help message"
	@echo ""
	@echo "Optional directories:"
	@echo "  firmwares/   If present, contents will be copied to /usr/lib/firmware in initramfs"
	@echo "  modules/     If present, contents will be copied to /usr/lib/modules in initramfs"
	@echo ""
	@echo "Configuration:"
	@echo "  TARGET_ARCH=$(TARGET_ARCH)"
	@echo "  HOST_ARCH=$(HOST_ARCH)"
	@echo "  NEED_CROSS_COMPILE=$(NEED_CROSS_COMPILE)"
	@echo "  CROSS_COMPILE=$(CROSS_COMPILE)"
	@echo ""
	@echo "Versions:"
	@echo "  BUSYBOX_VERSION=$(BUSYBOX_VERSION)"
	@echo "  KEXEC_TOOLS_VERSION=$(KEXEC_TOOLS_VERSION)"

# Check cross-compilation tools
.PHONY: check-cross-tools
check-cross-tools:
ifeq ($(NEED_CROSS_COMPILE),yes)
	$(call log,Checking cross-compilation tools for $(TARGET_ARCH))
	@command -v $(CC) >/dev/null 2>&1 || { \
		printf "$(RED)[ERROR]$(NC) Cross-compiler $(CC) not found. Please install aarch64 cross-compilation tools.\n"; \
		exit 1; \
	}
	$(call success,Cross-compilation tools found)
else
	$(call log,Native compilation on $(TARGET_ARCH) - no cross-compilation needed)
endif

# Create build directories
$(BUILD_DIR):
	$(call log,Creating build directories)
	@mkdir -p $(BUILD_DIR)
	@mkdir -p $(INIT_DIR)
	@mkdir -p $(SRC_DIR)
	@mkdir -p $(DOWNLOAD_DIR)
	$(call success,Build directories created)

# Copy base files
$(INIT_DIR)/.base-copied: | $(BUILD_DIR)
	$(call log,Copying base files to initramfs)
	@if [ ! -d "base" ]; then \
		printf "$(RED)[ERROR]$(NC) Base directory not found\n"; \
		exit 1; \
	fi
	@mkdir -p $(INIT_DIR)
	@cp -r base/. $(INIT_DIR)/
	@touch $(INIT_DIR)/.base-copied
	$(call success,Base files copied)

# Copy firmware files
$(INIT_DIR)/.firmware-copied: $(INIT_DIR)/.base-copied
	$(call log,Copying firmware files to initramfs)
	@if [ -d "firmwares" ]; then \
		mkdir -p $(INIT_DIR)/usr/lib/firmware; \
		cp -r firmwares/. $(INIT_DIR)/usr/lib/firmware/; \
		printf "$(GREEN)[SUCCESS]$(NC) Firmware files copied\n"; \
	else \
		printf "$(YELLOW)[WARN]$(NC) No firmwares directory found, skipping firmware installation\n"; \
	fi
	@touch $(INIT_DIR)/.firmware-copied

# Copy modules files
$(INIT_DIR)/.modules-copied: $(INIT_DIR)/.base-copied
	$(call log,Copying modules files to initramfs)
	@if [ -d "modules" ]; then \
		mkdir -p $(INIT_DIR)/usr/lib/modules; \
		cp -r modules/. $(INIT_DIR)/usr/lib/modules/; \
		printf "$(GREEN)[SUCCESS]$(NC) Modules files copied\n"; \
	else \
		printf "$(YELLOW)[WARN]$(NC) No modules directory found, skipping modules installation\n"; \
	fi
	@touch $(INIT_DIR)/.modules-copied

# Download busybox
$(DOWNLOAD_DIR)/busybox-$(BUSYBOX_VERSION).tar.bz2: | $(BUILD_DIR)
	$(call log,Downloading busybox $(BUSYBOX_VERSION))
	@wget -O $@ $(BUSYBOX_URL) || curl -L -o $@ $(BUSYBOX_URL)
	$(call success,Busybox downloaded)

# Extract busybox
$(SRC_DIR)/busybox-$(BUSYBOX_VERSION)/Makefile: $(DOWNLOAD_DIR)/busybox-$(BUSYBOX_VERSION).tar.bz2 | $(BUILD_DIR)
	$(call log,Extracting busybox)
	@mkdir -p $(SRC_DIR)
	@tar -xf $< -C $(SRC_DIR)
	@touch $@
	$(call success,Busybox extracted)

# Configure busybox
$(SRC_DIR)/busybox-$(BUSYBOX_VERSION)/.config: $(SRC_DIR)/busybox-$(BUSYBOX_VERSION)/Makefile
	$(call log,Configuring busybox)
	@if [ -f "configs/busybox.config" ]; then \
		cp configs/busybox.config $@; \
	else \
		$(call warn,No busybox config found, using defconfig); \
		$(MAKE) -C $(SRC_DIR)/busybox-$(BUSYBOX_VERSION) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) defconfig; \
	fi
	$(call success,Busybox configured)

# Build busybox
$(SRC_DIR)/busybox-$(BUSYBOX_VERSION)/busybox: $(SRC_DIR)/busybox-$(BUSYBOX_VERSION)/.config
	$(call log,Building busybox)
	@$(MAKE) -C $(SRC_DIR)/busybox-$(BUSYBOX_VERSION) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) -j$(shell nproc)
	$(call success,Busybox built)

# Install busybox
$(INIT_DIR)/bin/busybox: $(SRC_DIR)/busybox-$(BUSYBOX_VERSION)/busybox $(INIT_DIR)/.base-copied check-cross-tools
	$(call log,Installing busybox)
	@$(MAKE) -C $(SRC_DIR)/busybox-$(BUSYBOX_VERSION) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) CONFIG_PREFIX=$(abspath $(INIT_DIR)) install
	$(call success,Busybox installed)

# Busybox target (convenience alias)
.PHONY: busybox
busybox: $(INIT_DIR)/bin/busybox

# Download kexec-tools
$(DOWNLOAD_DIR)/kexec-tools-$(KEXEC_TOOLS_VERSION).tar.xz: | $(BUILD_DIR)
	$(call log,Downloading kexec-tools $(KEXEC_TOOLS_VERSION))
	@wget -O $@ $(KEXEC_TOOLS_URL) || curl -L -o $@ $(KEXEC_TOOLS_URL)
	$(call success,Kexec-tools downloaded)

# Extract kexec-tools
$(SRC_DIR)/kexec-tools-$(KEXEC_TOOLS_VERSION)/configure: $(DOWNLOAD_DIR)/kexec-tools-$(KEXEC_TOOLS_VERSION).tar.xz | $(BUILD_DIR)
	$(call log,Extracting kexec-tools)
	@mkdir -p $(SRC_DIR)
	@tar -xf $< -C $(SRC_DIR)
	@touch $@
	$(call success,Kexec-tools extracted)

# Configure kexec-tools
$(SRC_DIR)/kexec-tools-$(KEXEC_TOOLS_VERSION)/Makefile: $(SRC_DIR)/kexec-tools-$(KEXEC_TOOLS_VERSION)/configure
	$(call log,Configuring kexec-tools)
	@cd $(SRC_DIR)/kexec-tools-$(KEXEC_TOOLS_VERSION) && \
	CC="$(CC)" CXX="$(CXX)" AR="$(AR)" STRIP="$(STRIP)" BUILD_CFLAGS="-O2 -Wall" LDFLAGS="-static" \
		./configure --host=$(CROSS_COMPILE:%-=%) --build=$(HOST_ARCH)
	$(call success,Kexec-tools configured)

# Build kexec-tools
$(SRC_DIR)/kexec-tools-$(KEXEC_TOOLS_VERSION)/build/sbin/kexec: $(SRC_DIR)/kexec-tools-$(KEXEC_TOOLS_VERSION)/Makefile
	$(call log,Building kexec-tools)
	@$(MAKE) -C $(SRC_DIR)/kexec-tools-$(KEXEC_TOOLS_VERSION) -j$(shell nproc)
	$(call success,Kexec-tools built)

# Install kexec-tools
$(INIT_DIR)/sbin/kexec: $(SRC_DIR)/kexec-tools-$(KEXEC_TOOLS_VERSION)/build/sbin/kexec $(INIT_DIR)/.base-copied check-cross-tools
	$(call log,Installing kexec-tools)
	@mkdir -p $(INIT_DIR)/sbin
	@cp $< $@
	@$(STRIP) $@ 2>/dev/null || true
	$(call success,Kexec-tools installed)

# Kexec-tools target (convenience alias)
.PHONY: kexec-tools
kexec-tools: $(INIT_DIR)/sbin/kexec

# Build kxmenu
kxmenu/build/kxmenu: check-cross-tools
	$(call log,Building kxmenu for $(TARGET_ARCH))
	@if [ ! -d "kxmenu" ]; then \
		printf "$(RED)[ERROR]$(NC) kxmenu submodule not found. Please run: git submodule update --init\n"; \
		exit 1; \
	fi
	@$(MAKE) -C kxmenu GOOS=linux GOARCH=arm64 CGO_ENABLED=0 build
	$(call success,kxmenu built)

# Install kxmenu
$(INIT_DIR)/sbin/kxmenu: kxmenu/build/kxmenu $(INIT_DIR)/.base-copied
	$(call log,Installing kxmenu)
	@mkdir -p $(INIT_DIR)/sbin
	@cp kxmenu/build/kxmenu $@
	$(call success,kxmenu installed)

# kxmenu target (convenience alias)
.PHONY: kxmenu
kxmenu: $(INIT_DIR)/sbin/kxmenu

# Create initramfs archive
$(BUILD_DIR)/initramfs.cpio.zst: $(INIT_DIR)/bin/busybox $(INIT_DIR)/sbin/kexec $(INIT_DIR)/sbin/kxmenu $(INIT_DIR)/menu $(INIT_DIR)/.firmware-copied $(INIT_DIR)/.modules-copied
	$(call log,Creating initramfs archive with zstd compression)
	@cd $(INIT_DIR) && find . | cpio -o -H newc | zstd -19 > ../initramfs.cpio.zst
	$(call success,Initramfs created at $(BUILD_DIR)/initramfs.cpio.zst)

# Initramfs target
.PHONY: initramfs
initramfs: $(BUILD_DIR)/initramfs.cpio.zst

# Process menu file with BOOT_PART_LABEL replacement
$(INIT_DIR)/menu: $(INIT_DIR)/.base-copied
	$(call log,Processing menu file with BOOT_PART_LABEL replacement)
	@if [ ! -f "boot.conf" ]; then \
		printf "$(RED)[ERROR]$(NC) boot.conf not found\n"; \
		exit 1; \
	fi
	@BOOT_PART_LABEL=$$(grep "^BOOT_PART_LABEL" boot.conf | cut -d'=' -f2 | tr -d ' '); \
	sed "s/{{ BOOT_PART_LABEL }}/$$BOOT_PART_LABEL/g" base/menu > $(INIT_DIR)/menu
	@chmod +x $(INIT_DIR)/menu
	$(call success,Menu file processed with BOOT_PART_LABEL)

# Android boot image target
$(BUILD_DIR)/boot.img: $(BUILD_DIR)/initramfs.cpio.zst $(INIT_DIR)/menu
	$(call log,Creating Android boot image)
	@if [ ! -f "build/zImage" ]; then \
		printf "$(RED)[ERROR]$(NC) build/zImage not found. Please provide kernel image.\n"; \
		exit 1; \
	fi
	@if [ ! -f "boot.conf" ]; then \
		printf "$(RED)[ERROR]$(NC) boot.conf not found\n"; \
		exit 1; \
	fi
	@# Source boot.conf parameters
	@eval $$(grep "^CMDLINE" boot.conf | tr -d ' ') && \
	eval $$(grep "^HEADER_VERSION" boot.conf | tr -d ' ') && \
	eval $$(grep "^KERNEL_OFFSET" boot.conf | tr -d ' ') && \
	eval $$(grep "^BASE_ADDRESS" boot.conf | tr -d ' ') && \
	eval $$(grep "^RAMDISK_OFFSET" boot.conf | tr -d ' ') && \
	eval $$(grep "^SECOND_OFFSET" boot.conf | tr -d ' ') && \
	eval $$(grep "^TAGS_OFFSET" boot.conf | tr -d ' ') && \
	eval $$(grep "^PAGE_SIZE" boot.conf | tr -d ' ') && \
	mkbootimg \
		--kernel build/zImage \
		--ramdisk $(BUILD_DIR)/initramfs.cpio.zst \
		--cmdline "$$CMDLINE" \
		--base $$BASE_ADDRESS \
		--kernel_offset $$KERNEL_OFFSET \
		--ramdisk_offset $$RAMDISK_OFFSET \
		--second_offset $$SECOND_OFFSET \
		--tags_offset $$TAGS_OFFSET \
		--pagesize $$PAGE_SIZE \
		--header_version $$HEADER_VERSION \
		--output $@
	$(call success,Android boot image created at $(BUILD_DIR)/boot.img)

# Android boot target (convenience alias)
.PHONY: android-boot
android-boot: $(BUILD_DIR)/boot.img

# Clean target
.PHONY: clean
clean:
	$(call log,Cleaning build artifacts)
	@rm -rf $(BUILD_DIR)/initramfs $(BUILD_DIR)/src $(BUILD_DIR)/*.cpio.gz $(BUILD_DIR)/*.cpio.zst $(BUILD_DIR)/*.img
	@if [ -d "kxmenu" ]; then $(MAKE) -C kxmenu clean 2>/dev/null || true; fi
	$(call success,Build artifacts cleaned)

# Distclean target
.PHONY: distclean
distclean:
	$(call log,Cleaning everything including downloads)
	@rm -rf $(BUILD_DIR)
	$(call success,Everything cleaned)

# Show build info
.PHONY: info
info:
	@echo "Build Information:"
	@echo "  Project: kxboot-pipa"
	@echo "  Target Architecture: $(TARGET_ARCH)"
	@echo "  Host Architecture: $(HOST_ARCH)"
	@echo "  Cross-compile needed: $(NEED_CROSS_COMPILE)"
	@echo "  Cross-compiler: $(CROSS_COMPILE)"
	@echo "  Busybox version: $(BUSYBOX_VERSION)"
	@echo "  Kexec-tools version: $(KEXEC_TOOLS_VERSION)"
	@echo "  Build directory: $(BUILD_DIR)"
	@echo "  Initramfs directory: $(INIT_DIR)"