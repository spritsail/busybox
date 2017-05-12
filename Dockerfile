FROM debian:jessie-slim as builder

ARG ARCH=x86_64
ARG PACKAGES="core/glibc"
ARG DEBIAN_FRONTEND=noninteractive

ARG BUSYB_VER=1.26.2
ARG SU_EXEC_VER=v0.2
ARG TINI_VER=v0.14.0

WORKDIR /output

#Set up our dependencies, configure the output filesystem a bit
RUN apt-get update -qy && \
    apt-get install -qy curl build-essential && \
    mkdir -p usr/bin usr/lib dev proc root etc && \
    ln -sv usr/bin bin && \
    ln -sv usr/bin sbin && \
    ln -sv usr/lib lib && \
    ln -sv lib lib64

# Removing this :P
RUN for pkg in $PACKAGES; do \
        repo=$(echo $pkg | cut -d/ -f1); \
        name=$(echo $pkg | cut -d/ -f2); \
        curl -L https://archlinux.org/packages/$repo/$ARCH/$name/download \
            | tar xJ -C . ; \
    done && \
    rm -f .BUILDINFO .INSTALL .PKGINFO .MTREE && \
    rm -rf usr/share usr/include lib/*.a lib/*.o lib/gconv \
           bin/ldconfig bin/sln bin/localedef bin/nscd

# Pull busybox and some other utilities
RUN curl -L https://busybox.net/downloads/binaries/$BUSYB_VER-defconfig-multiarch/busybox-$ARCH > /output/usr/bin/busybox && \
    curl -L https://github.com/javabean/su-exec/releases/download/${SU_EXEC_VER}/su-exec.amd64 > /output/bin/su-exec && \
    curl -L https://github.com/krallin/tini/releases/download/${TINI_VER}/tini-amd64 > /output/bin/tini && \
    chmod +x /output/bin/busybox /output/bin/su-exec /output/bin/tini

WORKDIR /tmp

# Build and install openssl
ARG DESTDIR=/output/libressl
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
# Needed cos we dont have /bin/sh yet
RUN ["/bin/busybox", "--install", "-s", "/bin"]
CMD ["sh"]
