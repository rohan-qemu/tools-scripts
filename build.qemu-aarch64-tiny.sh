#!/bin/bash
# Copyright (c) 2018 Nexell Co., Ltd.
# Author: Junghyun, Kim <jhkim@nexell.co.kr>
#

BASE_DIR=$(realpath $(dirname $(realpath "$BASH_SOURCE"))/../..)
RESULT_TOP="${BASE_DIR}/result"
OUTPUT_TOP="${BASE_DIR}/output"
TARGET_ARCH="aarch64"
RESULT_DIR="${RESULT_TOP}/${TARGET_ARCH}"
OUTPUT_DIR="${OUTPUT_TOP}/${TARGET_ARCH}"

TOOLCHAIN_DIR="${BASE_DIR}/tools/toolchain/gcc-11.0.1_aarch64-linux-gnu/bin"
TOOLCHAIN_PREFIX=aarch64-linux-gnu-
TOOLCHAIN_LINUX="${TOOLCHAIN_DIR}/${TOOLCHAIN_PREFIX}"

TOOLS_DIR="${BASE_DIR}/tools"
TOOLS_SCRIPT_DIR="${TOOLS_DIR}/scripts"
TOOLS_SCRIPT_COMMON_DIR="${TOOLS_DIR}/common"

# buildroot configs
BR2_PATH=buildroot
BR2_DIR="${BASE_DIR}/${BR2_PATH}"
BR2_OUT="${OUTPUT_DIR}/${BR2_PATH}"
BR2_DEFCONFIG="qemu_aarch64_tiny_defconfig"
BR2_SDK="sdk-buildroot-${TARGET_ARCH}"

KERNEL_DIR="${BASE_DIR}/linux"
KERNEL_OUT="${OUTPUT_DIR}/linux"
# default search from <linux>/arch/arm64/configs/
KERNEL_DEFCONFIG="../../../../${BR2_PATH}/board/rohan/configs/linux_selinux_defconfig"
KERNEL_BIN="Image"

QEMU_DIR="${BASE_DIR}/qemu"
QEMU_OUT="${OUTPUT_DIR}/qemu"
QEMU_VERSION=v6.1.0
QEMU_ISNTALL_DIR="${RESULT_TOP}/tools/qemu-${QEMU_VERSION}"
QEMU_CONFIG="--target-list=aarch64-softmmu,aarch64-linux-user --enable-debug"

# littlekernel
LK_DIR="${BASE_DIR}/lk"
LK_BUILDROOT="${OUTPUT_DIR}/lk"
LK_PROJECT="qemu-virt-arm64-test"
LK_OPTIONS="
	BUILDROOT=${LK_BUILDROOT}
	ARCH_arm64_TOOLCHAIN_PREFIX=${TOOLCHAIN_PREFIX}
	ARCH_arm64_COMPILEFLAGS='-mno-outline-atomics -fno-stack-protector'
	LK_HEAP_IMPLEMENTATION=miniheap"

LK_PROJECT_UZ="uz-evb-tiny"
LK_OPTIONS_UZ="
	BUILDROOT=${LK_BUILDROOT}
	ARCH_arm64_TOOLCHAIN_PREFIX=${TOOLCHAIN_PREFIX}
	ARCH_arm64_COMPILEFLAGS='-mno-outline-atomics -fno-stack-protector'
	NOECHO= DEBUG=2 ARCH_OPTFLAGS=-O0"
#	NOECHO= DEBUG=2 ARCH_OPTFLAGS=-rdynamic"
#	NOECHO= DEBUG=2 ARCH_OPTFLAGS=-O0"

ROOT_DIR="${RESULT_DIR}/rootfs"
ROOT_INITRD="${RESULT_DIR}/initrd.img"

function qemu_configure () {
	logmsg "QEMU configure"
	mkdir -p ${QEMU_OUT}
	pushd ${QEMU_OUT} 2>/dev/null
        bash -c "${QEMU_DIR}/configure ${QEMU_CONFIG}"
	popd
}

function qemu_build () {
	logmsg "QEMU build"
	pushd ${QEMU_OUT} 2>/dev/null
	bash -c "make -j$(grep -c processor /proc/cpuinfo)"
	popd
}

function qemu_install () {
	local destdir="${QEMU_ISNTALL_DIR}"

	logmsg "QEMU install: ${destdir}"
	mkdir -p ${destdir}

	pushd ${QEMU_OUT} 2>/dev/null
	bash -c "make install DESTDIR=${destdir}"
	popd
}

function qemu_clean () {
	logmsg "QEMU clean: $(pwd)"
	pushd ${QEMU_OUT} 2>/dev/null
	bash -c "make distclean"
	popd
}

function br2_initrd () {
	logmsg "Build initrd: $(pwd)"
	${TOOLS_SCRIPT_COMMON_DIR}/mk_ramimg.sh -r ${ROOT_DIR} -o ${ROOT_INITRD}
}

function lk_clean () {
	declare -n local var="${1}"
	local project=${var['MAKE_TARGET']}

	logmsg "LK Clean: ${project} "
	eval "make -C ${LK_DIR} BUILDROOT=${LK_BUILDROOT} ${project} clean"
}

function lk_complete_uz () {
	logmsg "LK Complete: $(pwd)"
	cp ${RESULT_DIR}/lk.uz.bin /data/jhk/deepx/m1/devel/rt_fw.git/firmware/build_fpga/dxfw_fpga.bin
}

###############################################################################
# Build Image and Targets
###############################################################################
BUILD_IMAGES=(
	"CROSS_TOOL	= ${TOOLCHAIN_LINUX}",
	"RESULT_DIR 	= ${RESULT_DIR}",

	"qemu	=
		BUILD_MANUAL   : true,
		MAKE_PATH      : ${QEMU_DIR},
		BUILD_PREP     : qemu_configure,
		BUILD_POST     : qemu_build,
		BUILD_COMPLETE : qemu_install,
		BUILD_CLEAN    : qemu_clean",

	"kernel	=
		MAKE_ARCH      : arm64,
		MAKE_PATH      : ${KERNEL_DIR},
		MAKE_DEFCONFIG : ${KERNEL_DEFCONFIG},
		MAKE_TARGET    : ${KERNEL_BIN},
		MAKE_OUTDIR    : ${KERNEL_OUT},
		BUILD_OUTPUT   : arch/arm64/boot/${KERNEL_BIN}",

	"br2   	=
		MAKE_PATH      : ${BR2_DIR},
		MAKE_DEFCONFIG : ${BR2_DEFCONFIG},
		MAKE_OUTDIR    : ${BR2_OUT},
		BUILD_OUTPUT   : target; images/disk.img,
		BUILD_RESULT   : rootfs; disk.img,
		BUILD_COMPLETE : br2_initrd",

	"lk =
		MAKE_PATH      : ${LK_DIR},
		MAKE_TARGET    : ${LK_PROJECT},
		MAKE_OPTION    : ${LK_OPTIONS},
		MAKE_CLEANOPT  : ${LK_PROJECT},
		BUILD_OUTPUT   : ${LK_BUILDROOT}/build-${LK_PROJECT}/lk.bin; ${LK_BUILDROOT}/build-${LK_PROJECT}/lk.elf",

	"uz =
		MAKE_PATH      : ${LK_DIR},
		MAKE_TARGET    : ${LK_PROJECT_UZ},
		MAKE_OPTION    : ${LK_OPTIONS_UZ},
		MAKE_CLEANOPT  : ${LK_PROJECT_UZ},
		BUILD_OUTPUT   : ${LK_BUILDROOT}/build-${LK_PROJECT_UZ}/lk.bin; ${LK_BUILDROOT}/build-${LK_PROJECT}/lk.elf,
		BUILD_RESULT   : lk.uz.bin; lk.uz.elf,
		BUILD_COMPLETE : lk_complete_uz",

	"sdk   	=
		BUILD_MANUAL   : true,
		BUILD_DEPEND   : br2,
                MAKE_NOCLEAN   : true,
		MAKE_PATH      : ${BR2_DIR},
		MAKE_TARGET    : sdk,
		MAKE_OPTION    : BR2_SDK_PREFIX=${BR2_SDK},
		MAKE_OUTDIR    : ${BR2_OUT},
		BUILD_OUTPUT   : images/${BR2_SDK}.tar.gz",
)
