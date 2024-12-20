################################################################################
#
# xenomai
#
################################################################################

XENOMAI_VERSION = $(call qstrip,$(BR2_PACKAGE_XENOMAI_VERSION))
ifeq ($(BR2_PACKAGE_XENOMAI_CUSTOM_TARBALL),y)
XENOMAI_TARBALL = $(call qstrip,$(BR2_PACKAGE_XENOMAI_CUSTOM_TARBALL_URL))
XENOMAI_SOURCE = $(notdir $(XENOMAI_TARBALL))
XENOMAI_SITE = $(patsubst %/,%,$(dir $(XENOMAI_TARBALL)))
else ifeq ($(BR2_PACKAGE_XENOMAI_CUSTOM_GIT),y)
XENOMAI_SITE = $(call qstrip,$(BR2_PACKAGE_XENOMAI_REPOSITORY))
XENOMAI_SITE_METHOD = git
else
XENOMAI_SOURCE = xenomai-$(XENOMAI_VERSION).tar.bz2
XENOMAI_SITE = http://xenomai.org/downloads/xenomai/stable
endif
# We're patching configure.ac
XENOMAI_AUTORECONF = YES

# Exclude all from the hash check, but the latest version.
ifeq ($(BR2_PACKAGE_XENOMAI)$(BR2_PACKAGE_XENOMAI_LATEST_VERSION),y)
BR_NO_CHECK_HASH_FOR += $(XENOMAI_SOURCE)
endif

XENOMAI_LICENSE = GPL-2.0+ with exception (headers), LGPL-2.1+ (libraries), GPL-2.0+ (kernel), GFDL-1.2+ (docs), GPL-2.0 (ipipe patch, can driver)
# GFDL is not included but refers to gnu.org
XENOMAI_LICENSE_FILES = debian/copyright include/COPYING kernel/cobalt/COPYING \
	kernel/cobalt/posix/COPYING kernel/cobalt/rtdm/COPYING \
	lib/alchemy/COPYING lib/analogy/COPYING \
	lib/boilerplate/iniparser/LICENSE lib/boilerplate/COPYING \
	lib/cobalt/COPYING lib/copperplate/COPYING lib/psos/COPYING \
	lib/smokey/COPYING lib/trank/COPYING lib/vxworks/COPYING

XENOMAI_DEPENDENCIES = host-pkgconf

XENOMAI_INSTALL_STAGING = YES
XENOMAI_INSTALL_TARGET_OPTS = DESTDIR=$(TARGET_DIR) install-user
XENOMAI_INSTALL_STAGING_OPTS = DESTDIR=$(STAGING_DIR) install-user

ifeq ($(BR2_PACKAGE_XENOMAI_MERCURY),y)
XENOMAI_CONF_OPTS += --with-core=mercury
else
XENOMAI_CONF_OPTS += --with-core=cobalt
endif

ifeq ($(BR2_PACKAGE_XENOMAI_ENABLE_SMP),y)
XENOMAI_CONF_OPTS += --enable-smp
else
XENOMAI_CONF_OPTS += --disable-smp
endif

ifeq ($(BR2_PACKAGE_XENOMAI_ENABLE_REGISTRY),y)
XENOMAI_DEPENDENCIES += libfuse
XENOMAI_REGISTRY_PATH = $(call qstrip,$(BR2_PACKAGE_XENOMAI_ENABLE_REGISTRY_PATH))
ifeq ($(XENOMAI_REGISTRY_PATH),)
XENOMAI_CONF_OPTS += --enable-registry
else
XENOMAI_CONF_OPTS += --enable-registry=$(XENOMAI_REGISTRY_PATH)
endif
else
XENOMAI_CONF_OPTS += --disable-registry
endif

XENOMAI_CONF_OPTS += $(call qstrip,$(BR2_PACKAGE_XENOMAI_ADDITIONAL_CONF_OPTS))

XENOMAI_PREFIX = /usr/xenomai
define XENOMAI_CONFIGURE_CMDS
	(cd $(@D) && rm -rf config.cache && \
	$(TARGET_CONFIGURE_OPTS) \
	$(TARGET_CONFIGURE_ARGS) \
	./configure \
		--target=$(GNU_TARGET_NAME) \
		--host=$(GNU_TARGET_NAME) \
		--build=$(GNU_HOST_NAME) \
		--prefix=$(XENOMAI_PREFIX) \
		--exec-prefix=$(XENOMAI_PREFIX) \
		--program-prefix="" \
		$(XENOMAI_CONF_OPTS) \
	)
endef

# Some of these files may be desired by some users -- at that point specific
# config options need to be added to keep a particular set.
define XENOMAI_REMOVE_UNNEEDED_FILES
	for i in xeno xeno-config xeno-info wrap-link.sh ; do \
		rm -f $(TARGET_DIR)/$(XENOMAI_PREFIX)/bin/$$i ; \
	done
	for i in cobalt modechk ; do \
		rm -f $(TARGET_DIR)/$(XENOMAI_PREFIX)/lib/$$i.wrappers ; \
	done
	for i in autotune corectl hdb rtnet nomaccfg rtcfg rtifconfig \
		rtiwconfig rtping rtroute tdmacfg rtps slackspot version; do \
		rm -f $(TARGET_DIR)/$(XENOMAI_PREFIX)/sbin/$$i ; \
	done
endef

# XENOMAI_POST_INSTALL_TARGET_HOOKS += XENOMAI_REMOVE_UNNEEDED_FILES

ifeq ($(BR2_PACKAGE_XENOMAI_TESTSUITE),)
define XENOMAI_REMOVE_TESTSUITE
	rm -rf $(TARGET_DIR)/$(XENOMAI_PREFIX)/share/xenomai/
	for i in clocktest gpiotest latency smokey spitest switchtest \
		xeno-test-run-wrapper dohell xeno-test-run xeno-test ; do \
		rm -f $(TARGET_DIR)/$(XENOMAI_PREFIX)/bin/$$i ; \
	done
	rm -rf $(TARGET_DIR)/$(XENOMAI_PREFIX)/demo/
endef

XENOMAI_POST_INSTALL_TARGET_HOOKS += XENOMAI_REMOVE_TESTSUITE
endif

ifeq ($(BR2_PACKAGE_XENOMAI_RTCAN),)
define XENOMAI_REMOVE_RTCAN_PROGS
	for i in rtcanrecv rtcansend ; do \
		rm -f $(TARGET_DIR)/$(XENOMAI_PREFIX)/bin/$$i ; \
	done
	rm -f $(TARGET_DIR)/$(XENOMAI_PREFIX)/sbin/rtcanconfig
endef

XENOMAI_POST_INSTALL_TARGET_HOOKS += XENOMAI_REMOVE_RTCAN_PROGS
endif

ifeq ($(BR2_PACKAGE_XENOMAI_ANALOGY),)
define XENOMAI_REMOVE_ANALOGY
	for i in cmd_read cmd_write cmd_bits insn_read insn_write insn_bits \
			wf_generate ; do \
		rm -f $(TARGET_DIR)/$(XENOMAI_PREFIX)/bin/$$i ; \
	done
	for i in analogy_config analogy_calibrate ; do \
		rm -f $(TARGET_DIR)/$(XENOMAI_PREFIX)/sbin/$$i ; \
	done
	rm -f $(TARGET_DIR)/$(XENOMAI_PREFIX)/lib/libanalogy.*
endef

XENOMAI_POST_INSTALL_TARGET_HOOKS += XENOMAI_REMOVE_ANALOGY
endif

XENOMAI_REMOVE_LIBS_LIST += $(if $(BR2_PACKAGE_XENOMAI_NATIVE_SKIN),,alchemy)
XENOMAI_REMOVE_LIBS_LIST += $(if $(BR2_PACKAGE_XENOMAI_POSIX_SKIN),,posix)
XENOMAI_REMOVE_LIBS_LIST += $(if $(BR2_PACKAGE_XENOMAI_PSOS_SKIN),,psos)
XENOMAI_REMOVE_LIBS_LIST += $(if $(BR2_PACKAGE_XENOMAI_RTAI_SKIN),,rtai)
XENOMAI_REMOVE_LIBS_LIST += $(if $(BR2_PACKAGE_XENOMAI_TESTSUITE),,smokey)
XENOMAI_REMOVE_LIBS_LIST += $(if $(BR2_PACKAGE_XENOMAI_UITRON_SKIN),,uitron)
XENOMAI_REMOVE_LIBS_LIST += $(if $(BR2_PACKAGE_XENOMAI_VXWORKS_SKIN),,vxworks)
XENOMAI_REMOVE_LIBS_LIST += $(if $(BR2_PACKAGE_XENOMAI_VRTX_SKIN),,vrtx)

define XENOMAI_REMOVE_LIBS
	for i in $(XENOMAI_REMOVE_LIBS_LIST) ; do \
		rm -f $(TARGET_DIR)/$(XENOMAI_PREFIX)/lib/lib$$i.* ; \
	done
endef

XENOMAI_POST_INSTALL_TARGET_HOOKS += XENOMAI_REMOVE_LIBS

define XENOMAI_DEVICES
	/dev/rtheap  c  666  0  0  10  254  0  0  -
	/dev/rtscope c  666  0  0  10  253  0  0  -
	/dev/rtp     c  666  0  0  150 0    0  1  32
endef

ifeq ($(BR2_PACKAGE_HAS_UDEV),y)
XENOMAI_DEPENDENCIES += udev

define XENOMAI_INSTALL_UDEV_RULES
	if test -d $(TARGET_DIR)/etc/udev/rules.d ; then \
		for f in $(@D)/kernel/cobalt/udev/*.rules ; do \
			cp $$f $(TARGET_DIR)/etc/udev/rules.d/ || exit 1 ; \
		done ; \
	fi;
endef

XENOMAI_POST_INSTALL_TARGET_HOOKS += XENOMAI_INSTALL_UDEV_RULES
endif # udev

$(eval $(autotools-package))
