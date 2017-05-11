FROM debian:jessie-slim as builder


ARG ARCH=x86_64
ARG PACKAGES="core/glibc community/busybox"
ARG DEBIAN_FRONTEND=noninteractive

WORKDIR /output

RUN apt-get update -qy && \
    apt-get install -qy curl build-essential

# Download and install glibc & busybox from Arch Linux
RUN mkdir -p usr/bin usr/lib dev proc root etc && \
    ln -sv usr/bin bin && \
    ln -sv usr/bin sbin && \
    ln -sv usr/lib lib && \
    ln -sv usr/lib lib64 && \
    for pkg in $PACKAGES; do \
        repo=$(echo $pkg | cut -d/ -f1); \
        name=$(echo $pkg | cut -d/ -f2); \
        curl -L https://archlinux.org/packages/$repo/$ARCH/$name/download \
            | tar xJ -C . ; \
    done && \
    rm -f .BUILDINFO .INSTALL .PKGINFO .MTREE && \
    for i in $(bin/busybox --list); do ln -s /bin/busybox bin/$i; done && \
    rm -rf usr/share usr/include lib/*.a lib/*.o lib/gconv \
           bin/ldconfig bin/sln bin/localedef bin/nscd

ARG DESTDIR=/output/libressl

WORKDIR /tmp

# Build and install openssl
RUN curl -L https://www.openssl.org/source/openssl-1.1.0e.tar.gz | \
    tar xz -C /tmp --strip-components=1 && \
    ./config --prefix=/output && \
    make install_sw && \
    rm /output/lib/*.a && \
    rm -r /output/include
    
# =============

FROM scratch
WORKDIR /
COPY --from=builder /output/ / 
CMD ["sh"]
