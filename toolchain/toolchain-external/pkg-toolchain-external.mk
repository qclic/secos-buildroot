################################################################################
# External toolchain package infrastructure
#
# This package infrastructure implements the support for external
# toolchains, i.e toolchains that are available pre-built, ready to
# use. Such toolchain may either be readily available on the Web
# (Linaro, Sourcery CodeBench, from processor vendors) or may be built
# with tools like Crosstool-NG or Buildroot itself. So far, we have
# tested this with:
#
#  * Toolchains generated by Crosstool-NG
#  * Toolchains generated by Buildroot
#  * Toolchains provided by Linaro for the ARM and AArch64
#    architectures
#  * Sourcery CodeBench toolchains (from Mentor Graphics) for the ARM,
#    MIPS, PowerPC, x86_64 and NIOS 2 architectures. For the MIPS
#    toolchain, the -muclibc variant isn't supported yet, only the
#    default glibc-based variant is.
#  * Synopsys DesignWare toolchains for ARC cores
#
# The basic principle is the following
#
#  1. If the toolchain is not pre-installed, download and extract it
#  in $(TOOLCHAIN_EXTERNAL_INSTALL_DIR). Otherwise,
#  $(TOOLCHAIN_EXTERNAL_INSTALL_DIR) points to were the toolchain has
#  already been installed by the user.
#
#  2. For all external toolchains, perform some checks on the
#  conformity between the toolchain configuration described in the
#  Buildroot menuconfig system, and the real configuration of the
#  external toolchain. This is for example important to make sure that
#  the Buildroot configuration system knows whether the toolchain
#  supports RPC, IPv6, locales, large files, etc. Unfortunately, these
#  things cannot be detected automatically, since the value of these
#  options (such as BR2_TOOLCHAIN_HAS_NATIVE_RPC) are needed at
#  configuration time because these options are used as dependencies
#  for other options. And at configuration time, we are not able to
#  retrieve the external toolchain configuration.
#
#  3. Copy the libraries needed at runtime to the target directory,
#  $(TARGET_DIR). Obviously, things such as the C library, the dynamic
#  loader and a few other utility libraries are needed if dynamic
#  applications are to be executed on the target system.
#
#  4. Copy the libraries and headers to the staging directory. This
#  will allow all further calls to gcc to be made using --sysroot
#  $(STAGING_DIR), which greatly simplifies the compilation of the
#  packages when using external toolchains. So in the end, only the
#  cross-compiler binaries remains external, all libraries and headers
#  are imported into the Buildroot tree.
#
#  5. Build a toolchain wrapper which executes the external toolchain
#  with a number of arguments (sysroot/march/mtune/..) hardcoded,
#  so we're sure the correct configuration is always used and the
#  toolchain behaves similar to an internal toolchain.
#  This toolchain wrapper and symlinks are installed into
#  $(HOST_DIR)/bin like for the internal toolchains, and the rest
#  of Buildroot is handled identical for the 2 toolchain types.
################################################################################

#
# Definitions of where the toolchain can be found
#

TOOLCHAIN_EXTERNAL_PREFIX = $(call qstrip,$(BR2_TOOLCHAIN_EXTERNAL_PREFIX))
TOOLCHAIN_EXTERNAL_DOWNLOAD_INSTALL_DIR = $(HOST_DIR)/opt/ext-toolchain

ifeq ($(BR2_TOOLCHAIN_EXTERNAL_DOWNLOAD),y)
TOOLCHAIN_EXTERNAL_INSTALL_DIR = $(TOOLCHAIN_EXTERNAL_DOWNLOAD_INSTALL_DIR)
else
TOOLCHAIN_EXTERNAL_INSTALL_DIR = $(abspath $(call qstrip,$(BR2_TOOLCHAIN_EXTERNAL_PATH)))
endif

ifeq ($(TOOLCHAIN_EXTERNAL_INSTALL_DIR),)
ifneq ($(TOOLCHAIN_EXTERNAL_PREFIX),)
# if no path set, figure it out from path
TOOLCHAIN_EXTERNAL_BIN := $(dir $(shell which $(TOOLCHAIN_EXTERNAL_PREFIX)-gcc))
endif
else
TOOLCHAIN_EXTERNAL_REL_BIN_PATH = $(call qstrip,$(BR2_TOOLCHAIN_EXTERNAL_REL_BIN_PATH))
ifeq ($(TOOLCHAIN_EXTERNAL_REL_BIN_PATH),)
TOOLCHAIN_EXTERNAL_REL_BIN_PATH = bin
endif
TOOLCHAIN_EXTERNAL_BIN = $(TOOLCHAIN_EXTERNAL_INSTALL_DIR)/$(TOOLCHAIN_EXTERNAL_REL_BIN_PATH)
endif

# If this is a buildroot toolchain, it already has a wrapper which we want to
# bypass. Since this is only evaluated after it has been extracted, we can use
# $(wildcard ...) here.
TOOLCHAIN_EXTERNAL_SUFFIX = \
	$(if $(wildcard $(TOOLCHAIN_EXTERNAL_BIN)/*.br_real),.br_real)

TOOLCHAIN_EXTERNAL_CROSS = $(TOOLCHAIN_EXTERNAL_BIN)/$(TOOLCHAIN_EXTERNAL_PREFIX)-
TOOLCHAIN_EXTERNAL_CC = $(TOOLCHAIN_EXTERNAL_CROSS)gcc$(TOOLCHAIN_EXTERNAL_SUFFIX)
TOOLCHAIN_EXTERNAL_CXX = $(TOOLCHAIN_EXTERNAL_CROSS)g++$(TOOLCHAIN_EXTERNAL_SUFFIX)
TOOLCHAIN_EXTERNAL_GDC = $(TOOLCHAIN_EXTERNAL_CROSS)gdc$(TOOLCHAIN_EXTERNAL_SUFFIX)
TOOLCHAIN_EXTERNAL_FC = $(TOOLCHAIN_EXTERNAL_CROSS)gfortran$(TOOLCHAIN_EXTERNAL_SUFFIX)
TOOLCHAIN_EXTERNAL_READELF = $(TOOLCHAIN_EXTERNAL_CROSS)readelf

# Normal handling of downloaded toolchain tarball extraction.
ifeq ($(BR2_TOOLCHAIN_EXTERNAL_DOWNLOAD),y)
# As a regular package, the toolchain gets extracted in $(@D), but
# since it's actually a fairly special package, we need it to be moved
# into TOOLCHAIN_EXTERNAL_DOWNLOAD_INSTALL_DIR.
define TOOLCHAIN_EXTERNAL_MOVE
	rm -rf $(TOOLCHAIN_EXTERNAL_DOWNLOAD_INSTALL_DIR)
	mkdir -p $(TOOLCHAIN_EXTERNAL_DOWNLOAD_INSTALL_DIR)
	mv $(@D)/* $(TOOLCHAIN_EXTERNAL_DOWNLOAD_INSTALL_DIR)/
endef
endif

#
# Definitions of the list of libraries that should be copied to the target.
#

TOOLCHAIN_EXTERNAL_LIBS += ld*.so.* libgcc_s.so.* libatomic.so.*

ifneq ($(BR2_SSP_NONE),y)
TOOLCHAIN_EXTERNAL_LIBS += libssp.so.*
endif

ifeq ($(BR2_TOOLCHAIN_EXTERNAL_GLIBC)$(BR2_TOOLCHAIN_EXTERNAL_UCLIBC),y)
TOOLCHAIN_EXTERNAL_LIBS += libc.so.* libcrypt.so.* libdl.so.* libm.so.* libnsl.so.* libresolv.so.* librt.so.* libutil.so.*
ifeq ($(BR2_TOOLCHAIN_HAS_THREADS),y)
TOOLCHAIN_EXTERNAL_LIBS += libpthread.so.*
ifneq ($(BR2_PACKAGE_GDB)$(BR2_TOOLCHAIN_EXTERNAL_GDB_SERVER_COPY),)
TOOLCHAIN_EXTERNAL_LIBS += libthread_db.so.*
endif # gdbserver
endif # ! no threads
endif

ifeq ($(BR2_TOOLCHAIN_EXTERNAL_GLIBC),y)
TOOLCHAIN_EXTERNAL_LIBS += libnss_files.so.* libnss_dns.so.* libmvec.so.* libanl.so.*
endif

ifeq ($(BR2_TOOLCHAIN_EXTERNAL_MUSL),y)
TOOLCHAIN_EXTERNAL_LIBS += libc.so
endif

ifeq ($(BR2_INSTALL_LIBSTDCPP),y)
TOOLCHAIN_EXTERNAL_LIBS += libstdc++.so.*
endif

ifeq ($(BR2_TOOLCHAIN_HAS_FORTRAN),y)
TOOLCHAIN_EXTERNAL_LIBS += libgfortran.so.*
# fortran needs quadmath on x86 and x86_64
ifeq ($(BR2_TOOLCHAIN_HAS_LIBQUADMATH),y)
TOOLCHAIN_EXTERNAL_LIBS += libquadmath.so*
endif
endif

ifeq ($(BR2_TOOLCHAIN_HAS_OPENMP),y)
TOOLCHAIN_EXTERNAL_LIBS += libgomp.so.*
endif

ifeq ($(BR2_TOOLCHAIN_HAS_DLANG),y)
TOOLCHAIN_EXTERNAL_LIBS += libgdruntime.so* libgphobos.so*
endif

TOOLCHAIN_EXTERNAL_LIBS += $(addsuffix .so*,$(call qstrip,$(BR2_TOOLCHAIN_EXTRA_LIBS)))


#
# Definition of the CFLAGS to use with the external toolchain, as well as the
# common toolchain wrapper build arguments
#

# march/mtune/floating point mode needs to be passed to the external toolchain
# to select the right multilib variant
ifeq ($(BR2_x86_64),y)
TOOLCHAIN_EXTERNAL_CFLAGS += -m64
TOOLCHAIN_EXTERNAL_TOOLCHAIN_WRAPPER_ARGS += -DBR_64
endif
ifneq ($(GCC_TARGET_ARCH),)
TOOLCHAIN_EXTERNAL_CFLAGS += -march=$(GCC_TARGET_ARCH)
TOOLCHAIN_EXTERNAL_TOOLCHAIN_WRAPPER_ARGS += -DBR_ARCH='"$(GCC_TARGET_ARCH)"'
endif
ifneq ($(GCC_TARGET_CPU),)
TOOLCHAIN_EXTERNAL_CFLAGS += -mcpu=$(GCC_TARGET_CPU)
TOOLCHAIN_EXTERNAL_TOOLCHAIN_WRAPPER_ARGS += -DBR_CPU='"$(GCC_TARGET_CPU)"'
endif
ifneq ($(GCC_TARGET_ABI),)
TOOLCHAIN_EXTERNAL_CFLAGS += -mabi=$(GCC_TARGET_ABI)
TOOLCHAIN_EXTERNAL_TOOLCHAIN_WRAPPER_ARGS += -DBR_ABI='"$(GCC_TARGET_ABI)"'
endif
ifeq ($(BR2_TOOLCHAIN_HAS_MNAN_OPTION),y)
ifneq ($(GCC_TARGET_NAN),)
TOOLCHAIN_EXTERNAL_CFLAGS += -mnan=$(GCC_TARGET_NAN)
TOOLCHAIN_EXTERNAL_TOOLCHAIN_WRAPPER_ARGS += -DBR_NAN='"$(GCC_TARGET_NAN)"'
endif
endif
ifneq ($(GCC_TARGET_FP32_MODE),)
TOOLCHAIN_EXTERNAL_CFLAGS += -mfp$(GCC_TARGET_FP32_MODE)
TOOLCHAIN_EXTERNAL_TOOLCHAIN_WRAPPER_ARGS += -DBR_FP32_MODE='"$(GCC_TARGET_FP32_MODE)"'
endif
ifneq ($(GCC_TARGET_FPU),)
TOOLCHAIN_EXTERNAL_CFLAGS += -mfpu=$(GCC_TARGET_FPU)
TOOLCHAIN_EXTERNAL_TOOLCHAIN_WRAPPER_ARGS += -DBR_FPU='"$(GCC_TARGET_FPU)"'
endif
ifneq ($(GCC_TARGET_FLOAT_ABI),)
TOOLCHAIN_EXTERNAL_CFLAGS += -mfloat-abi=$(GCC_TARGET_FLOAT_ABI)
TOOLCHAIN_EXTERNAL_TOOLCHAIN_WRAPPER_ARGS += -DBR_FLOAT_ABI='"$(GCC_TARGET_FLOAT_ABI)"'
endif
ifneq ($(GCC_TARGET_MODE),)
TOOLCHAIN_EXTERNAL_CFLAGS += -m$(GCC_TARGET_MODE)
TOOLCHAIN_EXTERNAL_TOOLCHAIN_WRAPPER_ARGS += -DBR_MODE='"$(GCC_TARGET_MODE)"'
endif
ifeq ($(BR2_BINFMT_FLAT),y)
TOOLCHAIN_EXTERNAL_CFLAGS += -Wl,-elf2flt
TOOLCHAIN_EXTERNAL_TOOLCHAIN_WRAPPER_ARGS += -DBR_BINFMT_FLAT
endif
ifeq ($(BR2_mipsel)$(BR2_mips64el),y)
TOOLCHAIN_EXTERNAL_TOOLCHAIN_WRAPPER_ARGS += -DBR_MIPS_TARGET_LITTLE_ENDIAN
TOOLCHAIN_EXTERNAL_CFLAGS += -EL
endif
ifeq ($(BR2_mips)$(BR2_mips64),y)
TOOLCHAIN_EXTERNAL_TOOLCHAIN_WRAPPER_ARGS += -DBR_MIPS_TARGET_BIG_ENDIAN
TOOLCHAIN_EXTERNAL_CFLAGS += -EB
endif
ifeq ($(BR2_arceb),y)
TOOLCHAIN_EXTERNAL_TOOLCHAIN_WRAPPER_ARGS += -DBR_ARC_TARGET_BIG_ENDIAN
TOOLCHAIN_EXTERNAL_CFLAGS += -EB
endif

TOOLCHAIN_EXTERNAL_CFLAGS += $(call qstrip,$(BR2_TARGET_OPTIMIZATION))

ifeq ($(BR2_SOFT_FLOAT),y)
TOOLCHAIN_EXTERNAL_CFLAGS += -msoft-float
TOOLCHAIN_EXTERNAL_TOOLCHAIN_WRAPPER_ARGS += -DBR_SOFTFLOAT=1
endif

TOOLCHAIN_EXTERNAL_TOOLCHAIN_WRAPPER_ARGS += \
	-DBR_CROSS_PATH_SUFFIX='"$(TOOLCHAIN_EXTERNAL_SUFFIX)"'

ifeq ($(filter $(HOST_DIR)/%,$(TOOLCHAIN_EXTERNAL_BIN)),)
# TOOLCHAIN_EXTERNAL_BIN points outside HOST_DIR => absolute path
TOOLCHAIN_EXTERNAL_TOOLCHAIN_WRAPPER_ARGS += \
	-DBR_CROSS_PATH_ABS='"$(TOOLCHAIN_EXTERNAL_BIN)"'
else
# TOOLCHAIN_EXTERNAL_BIN points inside HOST_DIR => relative path
TOOLCHAIN_EXTERNAL_TOOLCHAIN_WRAPPER_ARGS += \
	-DBR_CROSS_PATH_REL='"$(TOOLCHAIN_EXTERNAL_BIN:$(HOST_DIR)/%=%)"'
endif


#
# The following functions creates the symbolic links needed to get the
# cross-compilation tools visible in $(HOST_DIR)/bin. Some of
# links are done directly to the corresponding tool in the external
# toolchain installation directory, while some other links are done to
# the toolchain wrapper (preprocessor, C, C++ and Fortran compiler)
#
# We skip gdb symlink when we are building our own gdb to prevent two
# gdb's in $(HOST_DIR)/bin.
#
# The LTO support in gcc creates wrappers for ar, ranlib and nm which load
# the lto plugin. These wrappers are called *-gcc-ar, *-gcc-ranlib, and
# *-gcc-nm and should be used instead of the real programs when -flto is
# used. However, we should not add the toolchain wrapper for them, and they
# match the *cc-* pattern. Therefore, an additional case is added for *-ar,
# *-ranlib and *-nm.
define TOOLCHAIN_EXTERNAL_INSTALL_WRAPPER
	$(Q)cd $(HOST_DIR)/bin; \
	for i in $(TOOLCHAIN_EXTERNAL_CROSS)*; do \
		base=$${i##*/}; \
		case "$$base" in \
		*-ar|*-ranlib|*-nm) \
			ln -sf $$(echo $$i | sed 's%^$(HOST_DIR)%..%') .; \
			;; \
		*cc|*cc-*|*++|*++-*|*cpp|*-gfortran|*-gdc) \
			ln -sf toolchain-wrapper $$base; \
			;; \
		*gdb|*gdbtui) \
			if test "$(BR2_PACKAGE_HOST_GDB)" != "y"; then \
				ln -sf $$(echo $$i | sed 's%^$(HOST_DIR)%..%') .; \
			fi \
			;; \
		*) \
			ln -sf $$(echo $$i | sed 's%^$(HOST_DIR)%..%') .; \
			;; \
		esac; \
	done
endef


# Various utility functions used by the external toolchain package
# infrastructure. Those functions are mainly responsible for:
#
#   - installation the toolchain libraries to $(TARGET_DIR)
#   - copying the toolchain sysroot to $(STAGING_DIR)
#   - installing a gdbinit file
#
# Details about sysroot directory selection.
#
# To find the sysroot directory, we use the trick of looking for the
# 'libc.a' file with the -print-file-name gcc option, and then
# mangling the path to find the base directory of the sysroot.
#
# Note that we do not use the -print-sysroot option, because it is
# only available since gcc 4.4.x, and we only recently dropped support
# for 4.2.x and 4.3.x.
#
# When doing this, we don't pass any option to gcc that could select a
# multilib variant (such as -march) as we want the "main" sysroot,
# which contains all variants of the C library in the case of multilib
# toolchains. We use the TARGET_CC_NO_SYSROOT variable, which is the
# path of the cross-compiler, without the --sysroot=$(STAGING_DIR),
# since what we want to find is the location of the original toolchain
# sysroot. This "main" sysroot directory is stored in SYSROOT_DIR.
#
# Then, multilib toolchains are a little bit more complicated, since
# they in fact have multiple sysroots, one for each variant supported
# by the toolchain. So we need to find the particular sysroot we're
# interested in.
#
# To do so, we ask the compiler where its sysroot is by passing all
# flags (including -march and al.), except the --sysroot flag since we
# want to the compiler to tell us where its original sysroot
# is. ARCH_SUBDIR will contain the subdirectory, in the main
# SYSROOT_DIR, that corresponds to the selected architecture
# variant. ARCH_SYSROOT_DIR will contain the full path to this
# location.
#
# One might wonder why we don't just bother with ARCH_SYSROOT_DIR. The
# fact is that in multilib toolchains, the header files are often only
# present in the main sysroot, and only the libraries are available in
# each variant-specific sysroot directory.


# toolchain_find_sysroot returns the sysroot location for the given
# compiler + flags. We need to handle cases where libc.a is in:
#
#  - lib/
#  - usr/lib/
#  - lib32/
#  - lib64/
#  - lib32-fp/ (Cavium toolchain)
#  - lib64-fp/ (Cavium toolchain)
#  - usr/lib/<tuple>/ (Linaro toolchain)
#
# And variations on these.
define toolchain_find_sysroot
$$(printf $(call toolchain_find_libc_a,$(1)) | sed -r -e 's:/(usr/)?lib(32|64)?([^/]*)?/([^/]*/)?libc\.a:/:')
endef

# Returns the lib subdirectory for the given compiler + flags (i.e
# typically lib32 or lib64 for some toolchains)
define toolchain_find_libdir
$$(printf $(call toolchain_find_libc_a,$(1)) | sed -r -e 's:.*/(usr/)?(lib(32|64)?([^/]*)?(/[^/]*)?)/libc.a:\2:')
endef

# Returns the location of the libc.a file for the given compiler + flags
define toolchain_find_libc_a
$$(readlink -f $$(LANG=C $(1) -print-file-name=libc.a))
endef

# Integration of the toolchain into Buildroot: find the main sysroot
# and the variant-specific sysroot, then copy the needed libraries to
# the $(TARGET_DIR) and copy the whole sysroot (libraries and headers)
# to $(STAGING_DIR).
#
# Variables are defined as follows:
#
# SYSROOT_DIR:          the main sysroot directory, deduced from the location of
#                       the libc.a file in the default multilib variant, by
#                       removing the usr/lib[32|64]/libc.a part of the path.
#                       Ex: /x-tools/mips-2011.03/mips-linux-gnu/libc/
#
# ARCH_SYSROOT_DIR:     the sysroot of the selected multilib variant,
#                       deduced from the location of the libc.a file in the
#                       selected multilib variant (taking into account the
#                       CFLAGS), by removing usr/lib[32|64]/libc.a at the end
#                       of the path.
#                       Ex: /x-tools/mips-2011.03/mips-linux-gnu/libc/mips16/soft-float/el/
#
# ARCH_LIB_DIR:         'lib', 'lib32' or 'lib64' depending on where libraries
#                       are stored. Deduced from the location of the libc.a file
#                       in the selected multilib variant, by looking at
#                       usr/lib??/libc.a.
#                       Ex: lib
#
# ARCH_SUBDIR:          the relative location of the sysroot of the selected
#                       multilib variant compared to the main sysroot.
#                       Ex: mips16/soft-float/el
#
# SUPPORT_LIB_DIR:      some toolchains, such as recent Linaro toolchains,
#                       store GCC support libraries (libstdc++,
#                       libgcc_s, etc.) outside of the sysroot. In
#                       this case, SUPPORT_LIB_DIR is set to a
#                       non-empty value, and points to the directory
#                       where these support libraries are
#                       available. Those libraries will be copied to
#                       our sysroot, and the directory will also be
#                       considered when searching libraries for copy
#                       to the target filesystem.
#
# Please be very careful to check the major toolchain sources:
# Buildroot, Crosstool-NG, CodeSourcery and Linaro
# before doing any modification on the below logic.

ifeq ($(BR2_STATIC_LIBS),)
define TOOLCHAIN_EXTERNAL_INSTALL_TARGET_LIBS
	$(Q)$(call MESSAGE,"Copying external toolchain libraries to target...")
	$(Q)for libpattern in $(TOOLCHAIN_EXTERNAL_LIBS); do \
		$(call copy_toolchain_lib_root,$$libpattern); \
	done
endef
endif

ifeq ($(BR2_TOOLCHAIN_EXTERNAL_GDB_SERVER_COPY),y)
define TOOLCHAIN_EXTERNAL_INSTALL_TARGET_GDBSERVER
	$(Q)$(call MESSAGE,"Copying gdbserver")
	$(Q)ARCH_SYSROOT_DIR="$(call toolchain_find_sysroot,$(TOOLCHAIN_EXTERNAL_CC) $(TOOLCHAIN_EXTERNAL_CFLAGS))" ; \
	ARCH_LIB_DIR="$(call toolchain_find_libdir,$(TOOLCHAIN_EXTERNAL_CC) $(TOOLCHAIN_EXTERNAL_CFLAGS))" ; \
	gdbserver_found=0 ; \
	for d in $${ARCH_SYSROOT_DIR}/usr \
		 $${ARCH_SYSROOT_DIR}/../debug-root/usr \
		 $${ARCH_SYSROOT_DIR}/usr/$${ARCH_LIB_DIR} \
		 $(TOOLCHAIN_EXTERNAL_INSTALL_DIR); do \
		if test -f $${d}/bin/gdbserver ; then \
			install -m 0755 -D $${d}/bin/gdbserver $(TARGET_DIR)/usr/bin/gdbserver ; \
			gdbserver_found=1 ; \
			break ; \
		fi ; \
	done ; \
	if [ $${gdbserver_found} -eq 0 ] ; then \
		echo "Could not find gdbserver in external toolchain" ; \
		exit 1 ; \
	fi
endef
endif

define TOOLCHAIN_EXTERNAL_INSTALL_SYSROOT_LIBS
	$(Q)SYSROOT_DIR="$(call toolchain_find_sysroot,$(TOOLCHAIN_EXTERNAL_CC))" ; \
	ARCH_SYSROOT_DIR="$(call toolchain_find_sysroot,$(TOOLCHAIN_EXTERNAL_CC) $(TOOLCHAIN_EXTERNAL_CFLAGS))" ; \
	ARCH_LIB_DIR="$(call toolchain_find_libdir,$(TOOLCHAIN_EXTERNAL_CC) $(TOOLCHAIN_EXTERNAL_CFLAGS))" ; \
	SUPPORT_LIB_DIR="" ; \
	if test `find $${ARCH_SYSROOT_DIR} -name 'libstdc++.a' | wc -l` -eq 0 ; then \
		LIBSTDCPP_A_LOCATION=$$(LANG=C $(TOOLCHAIN_EXTERNAL_CC) $(TOOLCHAIN_EXTERNAL_CFLAGS) -print-file-name=libstdc++.a) ; \
		if [ -e "$${LIBSTDCPP_A_LOCATION}" ]; then \
			SUPPORT_LIB_DIR=`readlink -f $${LIBSTDCPP_A_LOCATION} | sed -r -e 's:libstdc\+\+\.a::'` ; \
		fi ; \
	fi ; \
	if [ "$${SYSROOT_DIR}" == "$${ARCH_SYSROOT_DIR}" ] ; then \
		ARCH_SUBDIR="" ; \
	elif [ "`dirname $${ARCH_SYSROOT_DIR}`" = "`dirname $${SYSROOT_DIR}`" ] ; then \
		SYSROOT_DIR_DIRNAME=`dirname $${SYSROOT_DIR}`/ ; \
		ARCH_SUBDIR=`echo $${ARCH_SYSROOT_DIR} | sed -r -e "s:^$${SYSROOT_DIR_DIRNAME}(.*)/$$:\1:"` ; \
	else \
		ARCH_SUBDIR=`echo $${ARCH_SYSROOT_DIR} | sed -r -e "s:^$${SYSROOT_DIR}(.*)/$$:\1:"` ; \
	fi ; \
	$(call MESSAGE,"Copying external toolchain sysroot to staging...") ; \
	$(call copy_toolchain_sysroot,$${SYSROOT_DIR},$${ARCH_SYSROOT_DIR},$${ARCH_SUBDIR},$${ARCH_LIB_DIR},$${SUPPORT_LIB_DIR})
endef

# Create a symlink from (usr/)$(ARCH_LIB_DIR) to lib.
# Note: the skeleton package additionally creates lib32->lib or lib64->lib
# (as appropriate)
#
# $1: destination directory (TARGET_DIR / STAGING_DIR)
create_lib_symlinks = \
	$(Q)DESTDIR="$(strip $1)" ; \
	ARCH_LIB_DIR="$(call toolchain_find_libdir,$(TOOLCHAIN_EXTERNAL_CC) $(TOOLCHAIN_EXTERNAL_CFLAGS))" ; \
	if [ ! -e "$${DESTDIR}/$${ARCH_LIB_DIR}" -a ! -e "$${DESTDIR}/usr/$${ARCH_LIB_DIR}" ]; then \
		relpath="$(call relpath_prefix,$${ARCH_LIB_DIR})" ; \
		ln -snf $${relpath}lib "$${DESTDIR}/$${ARCH_LIB_DIR}" ; \
		ln -snf $${relpath}lib "$${DESTDIR}/usr/$${ARCH_LIB_DIR}" ; \
	fi

define TOOLCHAIN_EXTERNAL_CREATE_STAGING_LIB_SYMLINK
	$(call create_lib_symlinks,$(STAGING_DIR))
endef

define TOOLCHAIN_EXTERNAL_CREATE_TARGET_LIB_SYMLINK
	$(call create_lib_symlinks,$(TARGET_DIR))
endef

#
# Generate gdbinit file for use with Buildroot
#
define TOOLCHAIN_EXTERNAL_INSTALL_GDBINIT
	$(Q)if test -f $(TARGET_CROSS)gdb ; then \
		$(call MESSAGE,"Installing gdbinit"); \
		$(gen_gdbinit_file); \
	fi
endef

# GCC installs a libstdcxx-...so-gdb.py file that gdb will load automatically,
# but it contains hardcoded paths referring to the location where the (external)
# toolchain was built. Fix up these paths so that the pretty printers can be
# loaded automatically.
# By default, the pretty printers are installed in
# $(datadir)/gcc-$(gcc_version)/python but this could have been overwritten with
# the gcc configure option: --with-python-dir. We thus have to search the
# correct path first.
define TOOLCHAIN_EXTERNAL_FIXUP_PRETTY_PRINTER_LOADER
	$(Q)loadfiles=$$(find $(STAGING_DIR) -name 'libstdc++.so*-gdb.py' 2>/dev/null); \
	pythondir=$$(find $(TOOLCHAIN_EXTERNAL_DOWNLOAD_INSTALL_DIR) -path '*/libstdcxx/__init__.py' 2>/dev/null | sed 's%/libstdcxx/__init__.py%%' | head -n1); \
	if [ -n "$$loadfiles" ] && [ -n "$$pythondir" ]; then \
		echo "Fixing up hardcoded paths in GDB pretty-printer auto-load file(s) for libstdcxx: $$loadfiles"; \
		sed -ri \
			-e 's%^libdir\s*=.*%libdir = "$(STAGING_DIR)/lib"%' \
			-e "s%^pythondir\s*=.*%pythondir = '$$pythondir'%" \
			$$loadfiles; \
	fi
endef

# uClibc-ng dynamic loader is called ld-uClibc.so.1, but gcc is not
# patched specifically for uClibc-ng, so it continues to generate
# binaries that expect the dynamic loader to be named ld-uClibc.so.0,
# like with the original uClibc. Therefore, we create an additional
# symbolic link to make uClibc-ng systems work properly.
define TOOLCHAIN_EXTERNAL_FIXUP_UCLIBCNG_LDSO
	$(Q)if test -e $(TARGET_DIR)/lib/ld-uClibc.so.1; then \
		ln -sf ld-uClibc.so.1 $(TARGET_DIR)/lib/ld-uClibc.so.0 ; \
	fi
	$(Q)if test -e $(TARGET_DIR)/lib/ld64-uClibc.so.1; then \
		ln -sf ld64-uClibc.so.1 $(TARGET_DIR)/lib/ld64-uClibc.so.0 ; \
	fi
endef

define TOOLCHAIN_EXTERNAL_INSTALL_TARGET_LDD
	$(Q)if test -f $(STAGING_DIR)/usr/bin/ldd ; then \
		$(INSTALL) -D $(STAGING_DIR)/usr/bin/ldd $(TARGET_DIR)/usr/bin/ldd ; \
		$(SED) 's:.*/bin/bash:#!/bin/sh:' $(TARGET_DIR)/usr/bin/ldd ; \
	fi
endef

################################################################################
# inner-toolchain-external-package -- defines the generic installation rules
# for external toolchain packages
#
#  argument 1 is the lowercase package name
#  argument 2 is the uppercase package name, including a HOST_ prefix
#             for host packages
#  argument 3 is the uppercase package name, without the HOST_ prefix
#             for host packages
#  argument 4 is the type (target or host)
################################################################################
define inner-toolchain-external-package

$(2)_INSTALL_STAGING = YES
$(2)_ADD_TOOLCHAIN_DEPENDENCY = NO

# In fact, we don't need to download the toolchain, since it is already
# available on the system, so force the site and source to be empty so
# that nothing will be downloaded/extracted.
ifeq ($$(BR2_TOOLCHAIN_EXTERNAL_PREINSTALLED),y)
$(2)_SITE =
$(2)_SOURCE =
endif

ifeq ($$(BR2_TOOLCHAIN_EXTERNAL_DOWNLOAD),y)
$(2)_EXCLUDES = usr/lib/locale/*

$(2)_POST_EXTRACT_HOOKS += \
	TOOLCHAIN_EXTERNAL_MOVE
endif

# Checks for an already installed toolchain: check the toolchain
# location, check that it is usable, and then verify that it
# matches the configuration provided in Buildroot: ABI, C++ support,
# kernel headers version, type of C library and all C library features.
define $(2)_CONFIGURE_CMDS
	$$(Q)$$(call check_cross_compiler_exists,$$(TOOLCHAIN_EXTERNAL_CC))
	$$(Q)$$(call check_unusable_toolchain,$$(TOOLCHAIN_EXTERNAL_CC))
	$$(Q)SYSROOT_DIR="$$(call toolchain_find_sysroot,$$(TOOLCHAIN_EXTERNAL_CC))" ; \
	$$(call check_kernel_headers_version,\
		$$(BUILD_DIR),\
		$$(call toolchain_find_sysroot,$$(TOOLCHAIN_EXTERNAL_CC)),\
		$$(call qstrip,$$(BR2_TOOLCHAIN_HEADERS_AT_LEAST)),\
		$$(if $$(BR2_TOOLCHAIN_EXTERNAL_CUSTOM),loose,strict)); \
	$$(call check_gcc_version,$$(TOOLCHAIN_EXTERNAL_CC),\
		$$(call qstrip,$$(BR2_TOOLCHAIN_GCC_AT_LEAST))); \
	if test "$$(BR2_arm)" = "y" ; then \
		$$(call check_arm_abi,\
			"$$(TOOLCHAIN_EXTERNAL_CC) $$(TOOLCHAIN_EXTERNAL_CFLAGS)") ; \
	fi ; \
	if test "$$(BR2_INSTALL_LIBSTDCPP)" = "y" ; then \
		$$(call check_cplusplus,$$(TOOLCHAIN_EXTERNAL_CXX)) ; \
	fi ; \
	if test "$$(BR2_TOOLCHAIN_HAS_DLANG)" = "y" ; then \
		$$(call check_dlang,$$(TOOLCHAIN_EXTERNAL_GDC)) ; \
	fi ; \
	if test "$$(BR2_TOOLCHAIN_HAS_FORTRAN)" = "y" ; then \
		$$(call check_fortran,$$(TOOLCHAIN_EXTERNAL_FC)) ; \
	fi ; \
	if test "$$(BR2_TOOLCHAIN_HAS_OPENMP)" = "y" ; then \
		$$(call check_openmp,$$(TOOLCHAIN_EXTERNAL_CC)) ; \
	fi ; \
	if test "$$(BR2_TOOLCHAIN_EXTERNAL_UCLIBC)" = "y" ; then \
		$$(call check_uclibc,$$$${SYSROOT_DIR}) ; \
	elif test "$$(BR2_TOOLCHAIN_EXTERNAL_MUSL)" = "y" ; then \
		$$(call check_musl,\
			"$$(TOOLCHAIN_EXTERNAL_CC) $$(TOOLCHAIN_EXTERNAL_CFLAGS)") ; \
	else \
		$$(call check_glibc,$$$${SYSROOT_DIR}) ; \
	fi
	$$(Q)$$(call check_toolchain_ssp,$$(TOOLCHAIN_EXTERNAL_CC),$(BR2_SSP_OPTION))
endef

$(2)_TOOLCHAIN_WRAPPER_ARGS += $$(TOOLCHAIN_EXTERNAL_TOOLCHAIN_WRAPPER_ARGS)

$(2)_BUILD_CMDS = $$(TOOLCHAIN_WRAPPER_BUILD)

define $(2)_INSTALL_STAGING_CMDS
	$$(TOOLCHAIN_WRAPPER_INSTALL)
	$$(TOOLCHAIN_EXTERNAL_CREATE_STAGING_LIB_SYMLINK)
	$$(TOOLCHAIN_EXTERNAL_INSTALL_SYSROOT_LIBS)
	$$(TOOLCHAIN_EXTERNAL_INSTALL_WRAPPER)
	$$(TOOLCHAIN_EXTERNAL_INSTALL_GDBINIT)
	$$(TOOLCHAIN_EXTERNAL_FIXUP_PRETTY_PRINTER_LOADER)
endef

# Even though we're installing things in both the staging, the host
# and the target directory, we do everything within the
# install-staging step, arbitrarily.
ifeq ($(BR2_ROOTFS_SKELETON_CUSTOM),y)
define $(2)_INSTALL_TARGET_CMDS

endef
else
define $(2)_INSTALL_TARGET_CMDS
	$$(TOOLCHAIN_EXTERNAL_CREATE_TARGET_LIB_SYMLINK)
	$$(TOOLCHAIN_EXTERNAL_INSTALL_TARGET_LIBS)
	$$(TOOLCHAIN_EXTERNAL_INSTALL_TARGET_GDBSERVER)
	$$(TOOLCHAIN_EXTERNAL_FIXUP_UCLIBCNG_LDSO)
	$$(TOOLCHAIN_EXTERNAL_INSTALL_TARGET_LDD)
endef
endif
# Call the generic package infrastructure to generate the necessary
# make targets
$(call inner-generic-package,$(1),$(2),$(3),$(4))

endef

toolchain-external-package = $(call inner-toolchain-external-package,$(pkgname),$(call UPPERCASE,$(pkgname)),$(call UPPERCASE,$(pkgname)),target)
