# Following guide https://preshing.com/20141119/how-to-build-a-gcc-cross-compiler/

INSTALL_DIR=$(PWD)/install_here

# ifndef MY_FLAG
# $(error MY_FLAG is not set)
# endif

NPROC=$(shell nproc)

GNU_FTP=ftp.gnu.org/gnu

BINUTILS_VERSION=binutils-2.37
GCC_VERSION=gcc-11.2.0
LINUX_KERNEL_VERSION=linux-5.14
GLIBC_VERSION=glibc-2.34
# TODO pipe through linux and glibc.

COMPRESS_TYPE=.tar.gz

# Binutils 2.37
BINUTILS_TAR=$(BINUTILS_VERSION)$(COMPRESS_TYPE)
BINUTILS_URL=$(GNU_FTP)/binutils/$(BINUTILS_TAR)

# GCC
GCC_TAR=$(GCC_VERSION)$(COMPRESS_TYPE)
GCC_URL=$(GNU_FTP)/gcc/$(GCC_VERSION)/$(GCC_TAR)

# Glibc
GLIBC_TAR=$(GLIBC_VERSION)$(COMPRESS_TYPE)
GLIBC_URL=$(GNU_FTP)/glibc/$(GLIBC_TAR)

# Linux kern
LINUX_KERNEL_TAR=$(LINUX_KERNEL_VERSION)$(COMPRESS_TYPE)
MAJOR_VERSION=v5.x
LINUX_KERNEL_URL=www.kernel.org/pub/linux/kernel/$(MAJOR_VERSION)/$(LINUX_KERNEL_TAR)

ALL_URL=$(BINUTILS_URL) $(GCC_URL) $(GLIBC_URL) $(LINUX_KERNEL_URL)
ALL_TAR=$(notdir $(ALL_URL))
ALL_SRC=$(basename $(basename  $(ALL_TAR)))
ALL_BUILD=$(addprefix build-, $(ALL_SRC))

all: prepare

prepare: $(ALL_BUILD)
	mkdir $(INSTALL_DIR)

# Where projects build
$(ALL_BUILD): $(ALL_SRC)
	mkdir $@

# Src dirs
$(LINUX_KERNEL_VERSION): | $(LINUX_KERNEL_TAR)
	tar xf $|

$(GLIBC_VERSION): | $(GLIBC_TAR)
	tar xf $|

$(GCC_VERSION): | $(GCC_TAR)
	tar xf $|

$(BINUTILS_VERSION): | $(BINUTILS_TAR)
	tar xf $|

# How we get the tar balls
$(LINUX_KERNEL_TAR):
	wget $(LINUX_KERNEL_URL)

$(GLIBC_TAR):
	wget $(GLIBC_URL)

$(GCC_TAR):
	wget $(GCC_URL)

$(BINUTILS_TAR):
	wget $(BINUTILS_URL)

clean:
	rm -rf $(ALL_SRC) $(ALL_TAR) $(ALL_BUILD) $(INSTALL_DIR)

debug:
	echo $(ALL_SRC)
	echo $(ALL_TAR)
	echo $(ALL_BUILD)
	echo $(INSTALL_DIR)

.PHONY: all build_all

BINUTILS_BUILD_DIR=build-binutils-2.37
# 1)
# Specifying diff arch will force building cross assembler / linker.
# Disabling multilib says only AArch64 not related ones like AArch32
build_install_binutils: #build-binutils-2.37
	cd $(BINUTILS_BUILD_DIR) && ../binutils-2.37/configure --prefix=$(INSTALL_DIR) --target=aarch64-linux --disable-multilib
	make -C $(BINUTILS_BUILD_DIR) -j$(NPROC)
	make -C $(BINUTILS_BUILD_DIR) install

# 2)
# Can happen before or after binutils. Not used until building C standard library.
LINUX_SRC_DIR=linux-5.14
install_kern_headers:
	make -C $(LINUX_SRC_DIR) ARCH=arm64 INSTALL_HDR_PATH=$(INSTALL_DIR)/aarch64-linux headers_install

# GCC and Glibc have interdependencies. Need to go back and forth.

# 3)
# Requires GMP MPFR and MPC
# sudo dnf install gmp-devel
# sudo dnf install libmpc-devel
GCC_BUILD_DIR=build-gcc-11.2.0
# Build and install c and c++ cross compilers
build_gcc:
	cd $(GCC_BUILD_DIR) && ../gcc-11.2.0/configure --prefix=$(INSTALL_DIR) --target=aarch64-linux --enable-languages=c,c++ --disable-multilib
	make -C $(GCC_BUILD_DIR) -j$(NPROC) all-gcc
	make -C $(GCC_BUILD_DIR) install-gcc

# 4)
# Std C library headers and startup files
GLIBC_BUILD_DIR=build-glibc-2.34
MYHOST=x86_64-redhat-linux-gnu
install_glibc_headers_and_startups:
	cd $(GLIBC_BUILD_DIR) && ../glibc-2.34/configure --prefix=$(INSTALL_DIR)/aarch64-linux --build=$(MYHOST) --host=aarch64-linux --target=aarch64-linux --with-headers=$(INSTALL_DIR)/aarch64-linux/include --disable-multilib libc_cv_forced_unwind=yes
	make -C $(GLIBC_BUILD_DIR) install-bootstrap-headers=yes install-headers
	make -C $(GLIBC_BUILD_DIR) -j$(NPROC) csu/subdir_lib
	cd $(GLIBC_BUILD_DIR) && install csu/crt1.o csu/crti.o csu/crtn.o $(INSTALL_DIR)/aarch64-linux/lib
	cd $(GLIBC_BUILD_DIR) && aarch64-linux-gcc -nostdlib -nostartfiles -shared -x c /dev/null -o $(INSTALL_DIR)/aarch64-linux/lib/libc.so
	cd $(GLIBC_BUILD_DIR) && touch $(INSTALL_DIR)/aarch64-linux/include/gnu/stubs.h

# 5)
# Compiler support library
# Use cross-compiler built in 3) to build compiler support lib.
# Depends on startup files from 4)
# This will be used in step 6)
# No need to run configure again
# libgcc.a and libgcc_eh.a installed at <base>/lib/gcc/aarch64-linux/<version>
# A shared library, libgcc_s.so, is installed to $(INSTALL_DIR)/aarch64-linux/lib64.
install_gcc_support:
	make -C $(GCC_BUILD_DIR) -j$(NPROC) all-target-libgcc
	make -C $(GCC_BUILD_DIR) install-target-libgcc

# 6)
# Standard C library
# Finish Glibc package build and install
install_glibc:
	make -C $(GLIBC_BUILD_DIR) -j$(NPROC)
	make -C $(GLIBC_BUILD_DIR) install

# 7)
# Standard C++ lib
# Installs libstdc++.a and libstdc++.so to <base>/aarch64-linux/lib64
# TODO: Figure this out so you can have the c++ std lib!
# install_cpp:
# 	make -C $(GCC_BUILD_DIR) -j$(NPROC)
# 	make -C $(GCC_BUILD_DIR) install
