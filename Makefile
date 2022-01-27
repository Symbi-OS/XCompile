# Following guide https://preshing.com/20141119/how-to-build-a-gcc-cross-compiler/

# ifndef MY_FLAG
# $(error MY_FLAG is not set)
# endif

NPROC=$(shell nproc)

# Binutils 2.37
BINUTILS_TAR =mirror.us-midwest-1.nexcess.net/gnu/binutils/binutils-2.37.tar.gz
# GCC 11.2.0
GCC_TAR =mirror.us-midwest-1.nexcess.net/gnu/gcc/gcc-11.2.0/gcc-11.2.0.tar.gz
# Linux 5.14.0
LINUX_TAR =mirrors.edge.kernel.org/pub/linux/kernel/v5.x/linux-5.14.tar.gz
# Glibc 2.34
GLIBC_TAR =mirrors.kernel.org/gnu/glibc/glibc-2.34.tar.gz

ALL_TAR_URL= $(BINUTILS_TAR) $(GCC_TAR) $(LINUX_TAR) $(GLIBC_TAR)

ALL_TAR=$(notdir $(ALL_TAR_URL))

#dropping the suffixes
ALL_SRC=$(basename $(basename  $(ALL_TAR)))

ALL_BUILD=$(addprefix build-, $(ALL_SRC))

.PHONY: all build_all

BINUTILS_BUILD_DIR=build-binutils-2.37
# 1)
# Specifying diff arch will force building cross assembler / linker.
# Disabling multilib says only AArch64 not related ones like AArch32
build_binutils: #build-binutils-2.37
	cd $(BINUTILS_BUILD_DIR) && ../binutils-2.37/configure --prefix=/opt/cross --target=aarch64-linux --disable-multilib
	make -C $(BINUTILS_BUILD_DIR) -j$(NPROC)
	make -C $(BINUTILS_BUILD_DIR) install

# 2)
# Can happen before or after binutils. Not used until building C standard library.
LINUX_SRC_DIR=linux-5.14
install_kern_headers:
	make -C $(LINUX_SRC_DIR) ARCH=arm64 INSTALL_HDR_PATH=/opt/cross/aarch64-linux headers_install

# GCC and Glibc have interdependencies. Need to go back and forth.

# 3)
# Requires GMP MPFR and MPC
# sudo dnf install gmp-devel
# sudo dnf install libmpc-devel
GCC_BUILD_DIR=build-gcc-11.2.0
# Build and install c and c++ cross compilers
build_gcc:
	cd $(GCC_BUILD_DIR) && ../gcc-11.2.0/configure --prefix=/opt/cross --target=aarch64-linux --enable-languages=c,c++ --disable-multilib
	make -C $(GCC_BUILD_DIR) -j$(NPROC) all-gcc
	make -C $(GCC_BUILD_DIR) install-gcc

# 4)
# Std C library headers and startup files
GLIBC_BUILD_DIR=build-glibc-2.34
MYHOST=x86_64-redhat-linux-gnu
install_glibc_headers_and_startups:
	cd $(GLIBC_BUILD_DIR) && ../glibc-2.34/configure --prefix=/opt/cross/aarch64-linux --build=$(MYHOST) --host=aarch64-linux --target=aarch64-linux --with-headers=/opt/cross/aarch64-linux/include --disable-multilib libc_cv_forced_unwind=yes
	make -C $(GLIBC_BUILD_DIR) install-bootstrap-headers=yes install-headers
	make -C $(GLIBC_BUILD_DIR) -j$(NPROC) csu/subdir_lib
	cd $(GLIBC_BUILD_DIR) && install csu/crt1.o csu/crti.o csu/crtn.o /opt/cross/aarch64-linux/lib
	cd $(GLIBC_BUILD_DIR) && aarch64-linux-gcc -nostdlib -nostartfiles -shared -x c /dev/null -o /opt/cross/aarch64-linux/lib/libc.so
	cd $(GLIBC_BUILD_DIR) && touch /opt/cross/aarch64-linux/include/gnu/stubs.h

# 5)
# Compiler support library
# Use cross-compiler built in 3) to build compiler support lib.
# Depends on startup files from 4)
# This will be used in step 6)
# No need to run configure again
# libgcc.a and libgcc_eh.a installed at <base>/lib/gcc/aarch64-linux/<version>
# A shared library, libgcc_s.so, is installed to /opt/cross/aarch64-linux/lib64.
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

debug:
	@echo my dog is $(DOGGIE)

# To build we need
prepare_all: $(ALL_BUILD)

# Create build dirs
$(ALL_BUILD): $(ALL_SRC)
	mkdir $@

# Passthrough, tar creates src dirs
$(ALL_SRC): $(ALL_TAR)
	@echo nice, got $@

$(ALL_TAR): $(ALL_TAR_URL)
	tar -xf $@

# Get tarballs and extract
$(ALL_TAR_URL):
	wget $@

clean-build:
	rm -rf $(ALL_BUILD)

clean-src:
	rm -rf $(ALL_SRC)

dist-clean: clean-src clean-build
	rm -rf $(ALL_TAR)

install_clean:
	rm -rf 
