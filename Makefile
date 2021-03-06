#
# Copyright © 2017 Samuel Holland <samuel@sholland.org>
# SPDX-License-Identifier: BSD-3-Clause
#

# File locations
ATF		 = arm-trusted-firmware
ATF_URL		 = https://github.com/crust-firmware/arm-trusted-firmware
SCP		 = crust
SCP_URL		 = https://github.com/crust-firmware/crust
U-BOOT		 = u-boot
U-BOOT_URL	 = https://github.com/crust-firmware/u-boot

BUILDDIR	?= build
OUTDIR		 = $(BUILDDIR)/$(BOARD)
OUTFILE		 = $(BUILDDIR)/firmware_$(BOARD).img

# Cross compiler
CROSS_aarch64	 = aarch64-linux-musl-
CROSS_or1k	 = or1k-linux-musl-

# General options
DEBUG		?= 0
REPRODUCIBLE	?= 0

# Board selection
BOARD		?= orangepi_zero_plus

# Board-specific options
PLAT		 = sun50i
FLASH_SIZE_KB	 = 2048
SPL_SIZE_KB	 = 32

###############################################################################

BL31 = build/$(PLAT)/$(if $(filter-out 0,$(DEBUG)),debug,release)/bl31.bin
DATE = $(if $(filter-out 0,$(REPRODUCIBLE)),0,$(shell stat -c '%Y' .config))

M := @$(if $(filter-out 0,$(V)),:,printf '  %-7s %s\n')
Q :=  $(if $(filter-out 0,$(V)),,@)

all: $(OUTFILE)
	$(M) DONE

clean:
	$(Q) $(MAKE) -C $(ATF) clean
	$(Q) $(MAKE) -C $(SCP) clean
	$(Q) $(MAKE) -C $(U-BOOT) clean
	$(Q) rm -fr $(OUTDIR) $(OUTFILE)
	$(Q) rmdir $(BUILDDIR) 2>/dev/null || true

distclean:
	$(Q) $(MAKE) -C $(ATF) distclean
	$(Q) $(MAKE) -C $(SCP) distclean
	$(Q) $(MAKE) -C $(U-BOOT) distclean
	$(Q) rm -fr .config $(BUILDDIR)

.config: FORCE
	$(M) CHECK board
	$(Q) grep -Fqsx BOARD=$(BOARD) $@ || printf 'BOARD=%s\n' $(BOARD) >$@

$(ATF):
	$(M) CLONE $@
	$(Q) git clone $(ATF_URL) $@

$(SCP):
	$(M) CLONE $@
	$(Q) git clone $(SCP_URL) $@

$(U-BOOT):
	$(M) CLONE $@
	$(Q) git clone $(U-BOOT_URL) $@

%/.config: .config | %
	$(M) CONFIG $|
	$(Q) $(MAKE) -C $| $(BOARD)_defconfig

$(ATF)/$(BL31): .config FORCE | $(ATF)
	$(M) MAKE $@
	$(Q) $(MAKE) -C $| CROSS_COMPILE=$(CROSS_aarch64) \
		BUILD_MESSAGE_TIMESTAMP='"$(DATE)"' PLAT=$(PLAT) \
		bl31

$(SCP)/build/scp.bin: $(SCP)/.config FORCE | $(SCP)
	$(M) MAKE $@
	$(Q) $(MAKE) -C $| CROSS_COMPILE=$(CROSS_or1k) \
		build/scp.bin

%/spl/sunxi-spl.bin %/u-boot.itb: %/.config \
		$(OUTDIR)/bl31.bin $(OUTDIR)/scp.bin FORCE | %
	$(M) MAKE $@
	$(Q) $(MAKE) -C $| CROSS_COMPILE=$(CROSS_aarch64) \
		BL31=$(CURDIR)/$(OUTDIR)/bl31.bin SOURCE_DATE_EPOCH=$(DATE) \
		SCP=$(CURDIR)/$(OUTDIR)/scp.bin \
		spl/sunxi-spl.bin u-boot.itb

$(BUILDDIR) $(OUTDIR):
	$(M) MKDIR $@
	$(Q) mkdir -p $@

$(OUTDIR)/blank.img: | $(OUTDIR)
	$(M) DD $@
	$(Q) dd count=1 ibs=$(FLASH_SIZE_KB)k if=/dev/zero | \
		tr '\0' '\377' >$@ 2>/dev/null

$(OUTDIR)/bl31.bin: $(ATF)/$(BL31) | $(OUTDIR)
	$(M) CP $@
	$(Q) cp -f $< $@

$(OUTDIR)/scp.bin: $(SCP)/build/scp.bin | $(OUTDIR)
	$(M) CP $@
	$(Q) cp -f $< $@

$(OUTDIR)/sunxi-spl.bin: $(U-BOOT)/spl/sunxi-spl.bin | $(OUTDIR)
	$(M) CP $@
	$(Q) cp -f $< $@

$(OUTDIR)/u-boot.itb: $(U-BOOT)/u-boot.itb | $(OUTDIR)
	$(M) CP $@
	$(Q) cp -f $< $@

$(OUTFILE): $(OUTDIR)/blank.img \
		$(OUTDIR)/sunxi-spl.bin $(OUTDIR)/u-boot.itb | $(BUILDDIR)
	$(M) DD $@
	$(Q) cp -f $< $@.tmp
	$(Q) dd bs=$(SPL_SIZE_KB)k conv=notrunc \
		if=$(OUTDIR)/sunxi-spl.bin of=$@.tmp 2>/dev/null
	$(Q) dd bs=$(SPL_SIZE_KB)k conv=notrunc \
		if=$(OUTDIR)/u-boot.itb of=$@.tmp seek=1 2>/dev/null
	$(Q) mv -f $@.tmp $@

FORCE:

.PHONY: all clean distclean FORCE
.SECONDARY:
.SUFFIXES:
