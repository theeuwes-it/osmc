# (c) 2014-2015 Sam Nazarko
# email@samnazarko.co.uk

#!/bin/bash

. ../../scripts/common.sh

# Available options for building
export BUILD_OPTION_LANGC=1
export BUILD_OPTION_BUILD_FRESH=2
export BUILD_OPTION_USE_GOLD=4
export BUILD_OPTION_USE_O3=8
export BUILD_OPTION_USE_NOFP=16
export BUILD_OPTION_USE_MULTIARCH=32
export BUILD_OPTION_USE_CCACHE=64
export BUILD_OPTION_PREFER_LIBOSMC=128
export BUILD_OPTION_FASTER_APT=256
export BUILD_OPTION_NEEDS_SWAP=512
export BUILD_OPTION_DEFAULTS=$(($BUILD_OPTION_LANGC + $BUILD_OPTION_USE_O3 + $BUILD_OPTION_USE_NOFP + $BUILD_OPTION_USE_CCACHE + $BUILD_OPTION_PREFER_LIBOSMC + $BUILD_OPTION_FASTER_APT))

function fix_arch_ctl()
{
	sed '/Architecture/d' -i $1
	test $(arch)x == i686x && echo "Architecture: i386" >> $1
	test $(arch)x == armv7lx && echo "Architecture: armhf" >> $1
	test $(arch)x == x86_64x && echo "Architecture: amd64" >> $1
	test $(arch)x == aarch64x && echo "Architecture: arm64" >> $1
	sed '$!N; /^\(.*\)\n\1$/!P; D' -i $1
}

function strip_files()
{
	echo -e "Stripping binaries"
	for file in $(find ${1}/usr/osmc/lib/ -type f -name "*.so*"); do strip -s $file; done
	for file in $(find ${1}/usr/osmc/lib/ -type f -name "*.a"); do strip -s $file; done
        for file in $(find ${1}/usr/lib/ -type f -name "*.so*"); do strip -s $file; done
        for file in $(find ${1}/usr/lib/ -type f -name "*.a"); do strip -s $file; done
	strip -s "${1}/usr/bin/*" >/dev/null 2>&1
	strip -s "${1}/usr/sbin/*" >/dev/null 2>&1
}

function strip_libs()
{
	echo -e "Stripping libaries"
	strip "*.so.*" > /dev/null 2>&1
	strip "*.a" > /dev/null 2>&1
}

function build_in_env()
{
	if [ -n "$4" ]
	then
	    BUILD_OPTS=$4
	else
	    BUILD_OPTS=$BUILD_OPTION_DEFAULTS
	fi
	# Don't get stuck in an endless loop
	mount -t proc proc /proc -o ro >/dev/null 2>&1
	ischroot
	chrootval=$?
	if [ $chrootval == 2 ] || [ $chrootval == 0 ]
	then
            if ((($BUILD_OPTS & $BUILD_OPTION_LANGC) == $BUILD_OPTION_LANGC))
            then
                export LANG=C
            fi
	    if ((($BUILD_OPTS & $BUILD_OPTION_USE_GOLD) == $BUILD_OPTION_USE_GOLD))
	    then
		export LD="ld.gold "
	    fi
            if ((($BUILD_OPTS & $BUILD_OPTION_USE_O3) == $BUILD_OPTION_USE_O3))
            then
                export BUILD_FLAGS+="-O3 "
            fi
            if ((($BUILD_OPTS & $BUILD_OPTION_USE_NOFP) == $BUILD_OPTION_USE_NOFP))
            then
                export BUILD_FLAGS+="-fomit-frame-pointer "
            fi
            if ((($BUILD_OPTS & $BUILD_OPTION_USE_CCACHE) == $BUILD_OPTION_USE_CCACHE))
	    then
		export CCACHE_DIR="/root/.ccache"
		export PATH=/usr/lib/ccache:$PATH
	    fi
	    if ((($BUILD_OPTS & $BUILD_OPTION_PREFER_LIBOSMC) == $BUILD_OPTION_PREFER_LIBOSMC))
	    then
		export BUILD_FLAGS+="-I/usr/osmc/include -L/usr/osmc/lib "
		export LD_LIBRARY_PATH+="/usr/osmc/lib"
		export PKG_CONFIG_PATH+="/usr/osmc/lib/pkgconfig"
	    fi
            if ((($BUILD_OPTS & $BUILD_OPTION_FASTER_APT) == $BUILD_OPTION_FASTER_APT))
            then
               export use_faster_apt=1 # handle_dep() cannot get access to $BUILD_OPTS directly
           else
               export use_faster_apt=0 # Ensure reset
            fi
            export CFLAGS+="$BUILD_FLAGS"
            export CXXFLAGS+="$BUILD_FLAGS"
            export CPPFLAGS+="$BUILD_FLAGS"
	    return 99
	fi
	# Set swap outside of chroot() if needed
	if ((($BUILD_OPTS & $BUILD_OPTION_NEEDS_SWAP) == $BUILD_OPTION_NEEDS_SWAP))
        then
            if [ ! -f /opt/osmc-tc/swap ]
            then
		mkdir -p /opt/osmc-tc
                dd if=/dev/zero of=/opt/osmc-tc/swap bs=1M count=384
                mkswap /opt/osmc-tc/swap
                chmod 0600 /opt/osmc-tc/swap
            fi
            if ! grep -q /opt/osmc-tc/swap /proc/swaps
            then
                swapon /opt/osmc-tc/swap
            fi
        else
            # This build doesn't want it, but we might still be swapping
            if grep -q /opt/osmc-tc/swap /proc/swaps
            then
                swapoff /opt/osmc-tc/swap
            fi
        fi
	umount /proc >/dev/null 2>&1
	update_sources
	DEP=${1}
	test $DEP == rbp2 && DEP="armv7"
	test $DEP == vero && DEP="armv7"
	test $DEP == vero1 && DEP="armv7"
	test $DEP == vero2 && DEP="armv7"
	test $DEP == vero3 && DEP="armv7"
	test $DEP == vero5 && DEP="armv7"
        test $DEP == vero564 && DEP="aarch64"
	test $DEP == vero364 && DEP="aarch64"
	test $DEP == rbp4 && DEP="armv7"
	test $DEP == rbp464 && DEP="aarch64"
	test $DEP == rbp5 && DEP="aarch64"
	test $DEP == rbp1 && DEP="armv6l"
	test $DEP == atv && DEP="i386"
	test $DEP == pc && DEP="amd64"
	TCDIR="/opt/osmc-tc/$DEP-toolchain-osmc"
	CCACHEDIR="/opt/osmc-tc/$DEP-ccache-osmc"
	mkdir -p $CCACHEDIR
	if ((($BUILD_OPTS & $BUILD_OPTION_BUILD_FRESH) == $BUILD_OPTION_BUILD_FRESH))
	then
	    apt-get -y remove --purge "$DEP-toolchain-osmc"
	    umount ${TCDIR}/mnt >/dev/null 2>&1
	    umount ${TCDIR}/root/.ccache >/dev/null 2>&1
	    umount ${TCDIR}/opt >/dev/null 2>&1
	    umount ${TCDIR}/proc >/dev/null 2>&1
	    rm -rf ${TCDIR}
	fi
	export use_faster_apt=0 # This is only exported if in chroot, so we need to guard handle_dep for TC
	handle_dep "$DEP-toolchain-osmc"
	if [ $? != 0 ]; then echo -e "Can't get upstream toolchain. Is apt.osmc.tv in your sources.list?" && exit 1; fi
	configure_build_env_nw "$TCDIR"
	umount ${TCDIR}/mnt >/dev/null 2>&1 # May be dirty
	umount ${TCDIR}/root/.ccache >/dev/null 2>&1 # Shouldn't be dirty, as 1.1, but play it safe and ensure we mount right thing later
	mount --bind "$2/../../" "$TCDIR"/mnt
	mount --bind "$CCACHEDIR" "$TCDIR"/root/.ccache
	chroot $TCDIR /usr/bin/make $1 -C /mnt/package/$3
	return=$?
	if [ $return == 99 ]; then return 1; else return $return; fi
}

function teardown_env()
{
	TCDIR="/opt/osmc-tc/$1-toolchain-osmc"
	swapoff /opt/osmc-tc/swap >/dev/null 2>&1
	umount ${TCDIR}/mnt >/dev/null 2>&1
}

function handle_dep()
{
	# Used by packages that need other packages to be built first
	# Check dpkg-query for the existence of the package, try install, otherwise bail.
	if ! dpkg-query -W -f='${Status}' "${1}" 2>/dev/null | grep -q "ok installed" >/dev/null 2>&1
	then
		echo -e "Package ${1} is not found on the system, checking APT"
		# apt-cache search always returns 0. Ugh.
		if ! apt-cache search "${1}" | grep -q "^${1} "
		then
			echo -e "Can't find the package in APT repo. It needs to be built first or you need to wait for upstream to add it"
			exit 1
		else
			echo -e "Found in APT and will install"
			# armv7 conflicts -- not caused by lib or headers, but rather, /etc/kernel-img.conf etc
			if [ "$1" == "vero3-userland-dev-osmc" ]; then remove_conflicting "rbp-userland-dev-osmc" && remove_conflicting "rbp-userland-osmc" && remove_conflicting "rbp2-mesa-dev-osmc" && remove_conflicting "rbp2-mesa-osmc" && remove_conflicting "vero5-userland-dev-osmc" && remove_conflicting "vero5-userland-osmc"; fi
			if [ "$1" == "vero5-userland-dev-osmc" ]; then remove_conflicting "rbp-userland-dev-osmc" && remove_conflicting "rbp-userland-osmc" && remove_conflicting "rbp2-mesa-dev-osmc" && remove_conflicting "rbp2-mesa-osmc" && remove_conflicting "vero3-userland-dev-osmc" && remove_conflicting "vero3-userland-osmc"; fi
			if [ "$1" == "rbp2-libcec-dev-osmc" ]; then remove_conflicting "vero3-libcec-dev-osmc" && remove_conflicting "vero3-libcec-osmc" && remove_conflicting "vero5-libcec-dev-osmc" && remove_conflicting "vero5-libcec-osmc"; fi
			if [ "$1" == "vero3-libcec-dev-osmc" ]; then remove_conflicting "rbp2-libcec-dev-osmc" && remove_conflicting "rbp2-libcec-osmc" && remove_conflicting "vero5-libcec-dev-osmc" && remove_conflicting "vero5-libcec-osmc"; fi
			if [ "$1" == "vero5-libcec-dev-osmc" ]; then remove_conflicting "rbp2-libcec-dev-osmc" && remove_conflicting "rbp2-libcec-osmc" && remove_conflicting "vero3-libcec-dev-osmc" && remove_conflicting "vero3-libcec-osmc"; fi
			if [ "$1" == "rbp2-mesa-dev-osmc" ]; then remove_conflicting "vero3-userland-dev-osmc" && remove_conflicting "vero3-userland-osmc" && remove_conflicting "vero5-userland-dev-osmc" && remove_conflicting "vero5-userland-osmc"; fi
			if [ "$use_faster_apt" -eq 1 ]
			then
				install_package "${1}" "1"
			else
				install_package ${1}
			fi
			if [ $? -ne 0 ]; then exit 1; fi
		fi
	else
		echo -e "Package ${1} is already installed in the environment"
		return 0
	fi
}

function publish_applications_any()
{
	# Used by applications that are architecture independent. These are usually metapackages with some configuration files shipped.
	PKG_TARGETS="rbp1 rbp2 atv vero vero2"
	for TARGET in $PKG_TARGETS
	do
		echo -e "Publishing application for platform ${TARGET}"
		# No need to change id. Architecture is Any.
		cp ${1}/app.json ${1}/${TARGET}-${2}.json
	done
}

function publish_applications_targeted()
{
	# Used by applications that are architecture dependent.
	echo -e "Publishing application for platform ${TARGET}"
	# This is a tad hacky. Architecture specific, platform independent
	if [ "$2" == "armv6l" ]; then devices="rbp1"; fi
	if [ "$2" == "armv7" ]; then devices="rbp2 vero vero2"; fi
	if [ "$2" == "i386" ]; then devices="atv"; fi
	if [ "$2" == "amd64" ]; then devices="pc"; fi
	# Architecture specific, platform specific
	devices="$2"
	for device in $devices
	do
	    cp ${1}/app.json ${1}/${device}-${3}.json
	    sed -e s/\"id\":\ \"/\"id\":\ \"${2}-/ -i ${device}-${3}.json # set the correct package id
	done
}

function remove_conflicting()
{
	# This is not ideal...
	ischroot
	chrootval=$?
	# guard
	if [ $chrootval == 2 ] || [ $chrootval == 0 ]
	then
		dpkg --list | grep -q $1
		if [ $? == 0 ]; then echo -e "Removing conflicting package $1" && apt-get remove -y --purge $1; fi
	fi
}

function dpkg_build()
{
	# Calculate package size and update control file before packaging.
	if [ ! -e "$1" -o ! -e "$1/DEBIAN/control" ]; then exit 1; fi
	sed '/^Installed-Size/d' -i "$1/DEBIAN/control"
	size=$(du -s --apparent-size "$1" | awk '{print $1}')
	echo "Installed-Size: $size" >> "$1/DEBIAN/control"
	sudo dpkg -b "$1" "$2"
}

export -f fix_arch_ctl
export -f strip_files
export -f strip_libs
export -f build_in_env
export -f teardown_env
export -f handle_dep
export -f publish_applications_any
export -f publish_applications_targeted
export -f remove_conflicting
export -f dpkg_build
