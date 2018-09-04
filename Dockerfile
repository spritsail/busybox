# Pre-define ARGs to ensure correct scope
ARG GLIBC_VER=2.28
ARG BUSYB_VER=1.29.2
ARG SU_EXEC_VER=0.3
ARG TINI_VER=0.18.0

FROM spritsail/debian-builder as builder

ARG ARCH=x86_64
ARG ARCH_ALT=i686

ARG GLIBC_VER
ARG BUSYB_VER
ARG SU_EXEC_VER
ARG TINI_VER

ARG PREFIX=/output
WORKDIR $PREFIX

#Set up our dependencies, configure the output filesystem a bit
RUN mkdir -p dev etc home proc root tmp usr/{bin,lib/pkgconfig,lib32} var && \
    # Set up directories in a very confusing but very worky way
    ln -sv usr/lib lib64 && \
    ln -sv usr/lib lib && \
    ln -sv usr/bin bin && \
    ln -sv usr/bin sbin && \
    ln -sv bin usr/sbin

WORKDIR /tmp/glibc/build

# Download and build glibc from source
RUN apt install -y bison && \
    curl -fL https://ftp.gnu.org/gnu/glibc/glibc-${GLIBC_VER}.tar.xz \
        | tar xJ --strip-components=1 -C .. && \
    \
    echo "slibdir=/usr/lib" >> configparms && \
    echo "rtlddir=/usr/lib" >> configparms && \
    echo "sbindir=/bin" >> configparms && \
    echo "rootsbindir=/sbin" >> configparms && \
    echo "build-programs=yes" >> configparms && \
    \
    ../configure \
        --prefix=/usr \
        --libdir=/usr/lib \
        --libexecdir=/usr/lib \
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
    make -j "$(nproc)" && \
    make -j "$(nproc)" install_root="$(pwd)/out" install

RUN strip -s out/sbin/ldconfig && \
    # Patch ldd to use sh not bash
    sed -i '1s/.*/#!\/bin\/sh/' out/usr/bin/ldd && \
    sed -i 's/lib64/lib/g' out/usr/bin/ldd && \
    # Copy glibc libs & loader
    cp -d out/usr/lib/*.so* "${PREFIX}/usr/lib" && \
    cp -d out/usr/bin/ldd "${PREFIX}/bin" && \
    cp -d out/sbin/ldconfig "${PREFIX}/sbin" && \
    \
    echo /usr/lib32 > "${PREFIX}/etc/ld.so.conf"

WORKDIR /tmp/busybox

# Download and build busybox from source
RUN curl -fL https://busybox.net/downloads/busybox-${BUSYB_VER}.tar.bz2 \
        | tar xj --strip-components=1 && \
    # Use default configuration
    make defconfig && \
    make -j "$(nproc)" && \
    cp busybox "${PREFIX}/bin" && \
    # "Install" busybox, creating symlinks to all binaries it provides
    ./busybox --list-full | xargs -i ln -s /bin/busybox "${PREFIX}/{}"

WORKDIR /tmp/su-exec

# Download and build su-exec from source
RUN apt-get -y install xxd
RUN curl -fL https://github.com/frebib/su-exec/archive/v${SU_EXEC_VER}.tar.gz \
        | tar xz --strip-components=1 && \
    make && \
    strip -s su-exec && \
    mv su-exec "${PREFIX}/sbin"

WORKDIR /tmp/tini

# Download and build tini from source
ADD tini-gnudef.patch /tmp
RUN curl -fL https://github.com/krallin/tini/archive/v${TINI_VER}.tar.gz \
        | tar xz --strip-components=1 && \
    patch -p1 < /tmp/tini-gnudef.patch && \
    cmake . && \
    make tini && \
    mv tini "${PREFIX}/sbin"

WORKDIR $PREFIX

# Generate initial ld.so.cache so ELF binaries work.
# This is important otherwise everything will error with
# 'no such file or directory' when looking for libraries
RUN ${PREFIX}/sbin/ldconfig -r ${PREFIX} && \
    # Copy UTC localtime to output
    cp /usr/share/zoneinfo/Etc/UTC etc/

# =============

FROM scratch

ARG BUSYB_VER
ARG GLIBC_VER
ARG SU_EXEC_VER
ARG TINI_VER

LABEL maintainer="Spritsail <busybox@spritsail.io>" \
      org.label-schema.vendor="Spritsail" \
      org.label-schema.name="Busybox" \
      org.label-schema.url="https://github.com/spritsail/busybox" \
      org.label-schema.description="Busybox and GNU libc built from source" \
      org.label-schema.version=${BUSYB_VER}/${GLIBC_VER} \
      io.spritsail.version.busybox=${BUSYB_VER} \
      io.spritsail.version.glibc=${GLIBC_VER} \
      io.spritsail.version.su-exec=${SU_EXEC_VER} \
      io.spritsail.version.tini=${TINI_VER}

WORKDIR /

SHELL ["/bin/sh", "-exc"]

COPY --from=builder /output/ /
# Add default skeleton configuration files
COPY skel/ /
RUN chmod 1777 /tmp && \
    chmod 775 /usr/bin/*

ENV ENV="/etc/profile"
ENV PATH=/usr/local/sbin:/usr/local/bin:/usr/bin

ENTRYPOINT ["/sbin/tini" , "--"]
CMD ["/bin/sh"]
