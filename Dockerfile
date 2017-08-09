FROM debian:stretch-slim as builder

ARG ARCH=x86_64
ARG ARCH_ALT=i686
ARG DEBIAN_FRONTEND=noninteractive

ARG GLIBC_VER=2.26
ARG BUSYB_VER=1.27.1
ARG SU_EXEC_VER=v0.2
ARG TINI_VER=v0.15.0

ARG PREFIX=/output
WORKDIR $PREFIX

#Set up our dependencies, configure the output filesystem a bit
RUN apt-get update -qy && \
    apt-get install -qy curl build-essential gawk linux-libc-dev && \
    mkdir -p bin dev etc home lib proc root sbin tmp usr/bin usr/sbin usr/lib var && \
    # This is probably only relevant on 64bit systems?
    ln -sv lib lib64

# Pull busybox and some other utilities
RUN curl -sSL https://busybox.net/downloads/binaries/${BUSYB_VER}-${ARCH_ALT}/busybox > bin/busybox && \
    curl -sSL https://github.com/javabean/su-exec/releases/download/${SU_EXEC_VER}/su-exec.amd64 > sbin/su-exec && \
    curl -sSL https://github.com/krallin/tini/releases/download/${TINI_VER}/tini-amd64 > sbin/tini && \
    chmod +x bin/busybox sbin/su-exec sbin/tini && \
    # "Install" busybox, creating symlinks to all binaries it provides
    bin/busybox --list-full | xargs -i ln -s /bin/busybox "${PREFIX}/{}"

WORKDIR /tmp

ARG CFLAGS="-Os -pipe -fstack-protector-strong"
ARG LDFLAGS="-Wl,-O1,--sort-common -Wl,-s"

# Download and build glibc from source
RUN curl -sSL https://ftp.gnu.org/gnu/glibc/glibc-${GLIBC_VER}.tar.xz | tar xJ && \
    mkdir -p glibc-build && cd glibc-build && \
	\
    echo "slibdir=/lib" >> configparms && \
    echo "rtlddir=/lib" >> configparms && \
    echo "sbindir=/bin" >> configparms && \
    echo "rootsbindir=/bin" >> configparms && \
	\
    # Fix debian lib path weirdness
    rm -rf /usr/include/${ARCH}-linux-gnu/c++ && \
    ln -s /usr/include/${ARCH}-linux-gnu/* /usr/include && \
    \
    ../glibc-${GLIBC_VER}/configure \
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
RUN cp -d glibc-build/out/lib/*.so "${PREFIX}/lib" && \
    echo '/usr/lib' > "${PREFIX}/etc/ld.so.conf" && \
    ldconfig -r "${PREFIX}"

WORKDIR $PREFIX

# Add default skeleton configuration files
RUN for f in passwd shadow group profile; do \
		curl -sSL -o "${PREFIX}/etc/$f" "https://git.busybox.net/buildroot/plain/system/skeleton/etc/$f"; \
	done && \
	\
	# Copy UTC localtime to output
	cp /usr/share/zoneinfo/Etc/UTC etc/

# =============

FROM scratch
WORKDIR /

COPY --from=builder /output/ /
RUN mkdir -p /tmp && \
	chmod 1777 /tmp

CMD ["/bin/sh"]
