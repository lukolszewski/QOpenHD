#!/bin/bash

QT_VERSION=Qt5.15.0

export LC_ALL=C.UTF-8
export LANG=C.UTF-8

PACKAGE_ARCH=$1
OS=$2
DISTRO=$3
BUILD_TYPE=$4


if [ "${BUILD_TYPE}" == "docker" ]; then
    cat << EOF > /etc/resolv.conf
options rotate
options timeout:1
nameserver 8.8.8.8
nameserver 8.8.4.4
EOF
fi

apt-get install -y apt-utils curl
curl -1sLf 'https://dl.cloudsmith.io/public/openhd/openhd-2-1-testing/setup.deb.sh' | sudo -E bash && \
curl -1sLf 'https://dl.cloudsmith.io/public/openhd/openhd-2-1/setup.deb.sh' | sudo -E bash && \
apt update

apt-get install -y gnupg
apt-get install -y gnupg1
apt-get install -y gnupg2
apt-get install -y apt-transport-https curl
apt-get install qt5-qmake
if [[ "${DISTRO}" != "bullseye" ]]; then
    apt-get install qt5-default
fi
if [[ "${DISTRO}" == "bullseye" ]]; then
    apt-get install qtbase5-dev qtchooser qtbase5-dev-tools
fi

if [[ "${OS}" == "raspbian" ]]; then
    PLATFORM_DEV_PACKAGES="openhd-qt"
    PLATFORM_PACKAGES="-d openhd-qt"
fi

if [[ "${OS}" == "debian" ]]; then
    PLATFORM_DEV_PACKAGES="openhd-qt"
    PLATFORM_PACKAGES="-d openhd-qt"
fi

if [[ "${OS}" == "ubuntu" ]] && [[ "${PACKAGE_ARCH}" == "armhf" || "${PACKAGE_ARCH}" == "arm64" ]]; then
    PLATFORM_DEV_PACKAGES="openhd-qt-jetson-nano"
    PLATFORM_PACKAGES="-d openhd-qt-jetson-nano"
fi

apt -y install ${PLATFORM_DEV_PACKAGES} libgstreamer-plugins-base1.0-dev libgles2-mesa-dev libegl1-mesa-dev libgbm-dev libboost-dev libsdl2-dev libsdl1.2-dev

PACKAGE_NAME=qopenhd

TMPDIR=/tmp/${PACKAGE_NAME}-installdir

rm -rf ${TMPDIR}/*

mkdir -p ${TMPDIR}/usr/local/bin || exit 1
mkdir -p ${TMPDIR}/etc/systemd/system || exit 1
mkdir -p ${TMPDIR}/usr/local/share/openhd || exit 1

/opt/${QT_VERSION}/bin/qmake

#make clean || exit 1

make -j4 || exit 1
cp release/QOpenHD ${TMPDIR}/usr/local/bin/ || exit 1

# included in the same package since it's sharing code and not independently versioned
pushd OpenHDBoot
/opt/${QT_VERSION}/bin/qmake
#make clean || exit 1
make -j4 || exit 1
cp OpenHDBoot ${TMPDIR}/usr/local/bin/ || exit 1
popd

cp systemd/* ${TMPDIR}/etc/systemd/system/ || exit 1
cp qt.json ${TMPDIR}/usr/local/share/openhd/ || exit 1

VERSION=$(git describe)

rm ${PACKAGE_NAME}_${VERSION//v}_${PACKAGE_ARCH}.deb > /dev/null 2>&1

fpm -a ${PACKAGE_ARCH} -s dir -t deb -n ${PACKAGE_NAME} -v ${VERSION//v} -C ${TMPDIR} \
  --after-install after-install.sh \
  -p ${PACKAGE_NAME}_VERSION_ARCH.deb \
  -d "libboost-dev" \
  -d "gstreamer1.0-plugins-base" \
  -d "gstreamer1.0-plugins-good" \
  -d "gstreamer1.0-plugins-bad" \
  -d "gstreamer1.0-plugins-ugly" \
  -d "gstreamer1.0-libav" \
  -d "gstreamer1.0-tools" \
  -d "gstreamer1.0-alsa" \
  -d "gstreamer1.0-pulseaudio" \
  ${PLATFORM_PACKAGES} || exit 1

#
# Only push to cloudsmith for tags. If you don't want something to be pushed to the repo, 
# don't create a tag. You can build packages and test them locally without tagging.
#
git describe --exact-match HEAD > /dev/null 2>&1
if [[ $? -eq 0 ]]; then
    echo "Pushing package to OpenHD repository"
    cloudsmith push deb openhd/openhd-2-1/${OS}/${DISTRO} ${PACKAGE_NAME}_${VERSION//v}_${PACKAGE_ARCH}.deb
else
    echo "Pushing package to OpenHD testing repository"
    cloudsmith push deb openhd/openhd-2-1-testing/${OS}/${DISTRO} ${PACKAGE_NAME}_${VERSION//v}_${PACKAGE_ARCH}.deb
fi
