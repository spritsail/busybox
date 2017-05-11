FROM busybox:glibc

ARG REPO=http://ftp.de.debian.org/debian/pool/main
ARG ARCH=amd64

ARG LIBC6_VER=2.19-18+deb8u9
ARG LIBGCC_VER=4.9.2-10
ARG LIBSSL_VER=1.0.1t-1+deb8u6

ADD pkgextract /usr/local/bin/

WORKDIR /tmp
RUN mkdir -p /var/lib/dpkg/info && \
    # Fetch dependencies
    wget ${REPO}/g/glibc/libc6_${LIBC6_VER}_${ARCH}.deb && \
    wget ${REPO}/g/glibc/libc6-${ARCH}_${LIBC6_VER}_i386.deb && \
    wget ${REPO}/g/glibc/multiarch-support_${LIBC6_VER}_${ARCH}.deb && \
    wget ${REPO}/g/gcc-4.9/libgcc1_${LIBGCC_VER}_${ARCH}.deb && \
    wget ${REPO}/g/gcc-4.9/gcc-4.9-base_${LIBGCC_VER}_${ARCH}.deb && \
    wget ${REPO}/o/openssl/libssl1.0.0_${LIBSSL_VER}_${ARCH}.deb && \
    wget ${REPO}/o/openssl/openssl_${LIBSSL_VER}_${ARCH}.deb && \
    \
    # Lie about libc6 being installed 
    dpkg-deb -f libc6_*.deb | sed '/Depends: .*/d' > /var/lib/dpkg/status && \
    echo "Status: install ok installed" >> /var/lib/dpkg/status && \
    \
    # Install multiarch && gcc
    pkgextract libc6-${ARCH}*.deb && \
    pkgextract multiarch-support*.deb && \
    pkgextract gcc-4.9-base*.deb && \
    pkgextract libgcc1*.deb && \
    \
    # Lie about libssl being installed to dpkg
    dpkg-deb -f libssl1.0*.deb | sed 's|, debconf.*||g' >> /var/lib/dpkg/status && \
    echo "Status: install ok installed" >> /var/lib/dpkg/status && \
    # Actually 'install' libssl by extracting the files
    dpkg-deb -x libssl1.0*.deb / && \
    # Manually link the library files
    ln -sfv /usr/lib/x86_64-linux-gnu/libssl.so.1.0.0 /lib && \
    ln -sfv /usr/lib/x86_64-linux-gnu/libcrypto.so.1.0.0 /lib && \
    # Install openssl
    pkgextract openssl*.deb && \
    \
    # Cleanup
    rm -f *.deb && \
    rm -rf /usr/share && \
    rm -rf /usr/lib64/gconv # Hopefully this isn't required

WORKDIR /
ENV LD_LIBRARY_PATH=/lib:/lib/x86_64-linux-gnu:/usr/lib:/usr/lib/x86_64-linux-gnu
