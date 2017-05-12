FROM debian:jessie-slim as builder

ARG ARCH=x86_64
ARG DEBIAN_FRONTEND=noninteractive

ARG GLIBC_VER=2.25
ARG BUSYB_VER=1.26.2
ARG SU_EXEC_VER=v0.2
ARG TINI_VER=v0.14.0

WORKDIR /output

#Set up our dependencies, configure the output filesystem a bit
RUN apt-get update -qy && \
    apt-get install -qy curl build-essential gawk linux-libc-dev && \
    mkdir -p dev etc home proc root tmp usr/bin usr/sbin usr/lib var && \
    ln -sv usr/bin bin && \
    ln -sv usr/sbin sbin && \
    ln -sv usr/lib lib && \
    ln -sv usr/lib lib64

# Pull busybox and some other utilities
RUN curl -L https://busybox.net/downloads/binaries/$BUSYB_VER-defconfig-multiarch/busybox-$ARCH > bin/busybox && \
    curl -L https://github.com/javabean/su-exec/releases/download/${SU_EXEC_VER}/su-exec.amd64 > sbin/su-exec && \
    curl -L https://github.com/krallin/tini/releases/download/${TINI_VER}/tini-amd64 > sbin/tini && \
    chmod +x bin/busybox sbin/su-exec sbin/tini && \
    bin/busybox --list-full | xargs -i ln -s /bin/busybox "$(pwd)/{}"

WORKDIR /tmp

ARG CFLAGS="-Os -pipe -fstack-protector-strong"
ARG LDFLAGS="-Wl,-O1,--sort-common -Wl,-s"

# Download and build glibc from source
RUN curl -L https://ftp.gnu.org/gnu/glibc/glibc-$GLIBC_VER.tar.xz | tar xJ && \
    mkdir -p glibc-build && cd glibc-build && \
	\
    echo "slibdir=/lib" >> configparms && \
    echo "rtlddir=/lib" >> configparms && \
    echo "sbindir=/bin" >> configparms && \
    echo "rootsbindir=/bin" >> configparms && \
	\
    rm -rf /usr/include/x86_64-linux-gnu/c++ && \
    ln -s /usr/include/x86_64-linux-gnu/* /usr/include && \
    ../glibc-$GLIBC_VER/configure \
        --prefix="$(pwd)/root" \
        --libdir="$(pwd)/root/lib" \
        --libexecdir=/lib \
        --with-headers=/usr/include \
        --enable-add-ons \
        --enable-obsolete-rpc \
        --enable-kernel=3.10.0 \
        --enable-bind-now \
        --disable-profile \
        --enable-stackguard-randomization \
        --enable-stack-protector=strong \
        --enable-lock-elision \
        --enable-multi-arch \
        --disable-werror && \
    make && make install_root=$(pwd)/out install

# Copy glibc libs & generate ld cache
RUN cp -d glibc-build/out/lib/*.so /output/lib && \
    echo '/usr/lib' > /output/etc/ld.so.conf && \
    ldconfig -r /output

# =============

FROM scratch
WORKDIR /
COPY --from=builder /output/ /
CMD ["sh"]
