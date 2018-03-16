FROM spritsail/debian-builder as builder

ARG ARCH=x86_64
ARG ARCH_ALT=i686

ARG GLIBC_VER=2.27
ARG BUSYB_VER=1.28.1
ARG SU_EXEC_VER=v0.3
ARG TINI_VER=v0.17.0

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

# Pull tini and su-exec utilities
RUN curl -fL https://github.com/frebib/su-exec/releases/download/${SU_EXEC_VER}/su-exec-x86_64 > sbin/su-exec && \
    curl -fL https://github.com/krallin/tini/releases/download/${TINI_VER}/tini-amd64 > sbin/tini && \
    chmod +x sbin/su-exec sbin/tini

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

WORKDIR $PREFIX

# Generate initial ld.so.cache so ELF binaries work.
# This is important otherwise everything will error with
# 'no such file or directory' when looking for libraries
RUN ${PREFIX}/sbin/ldconfig -r ${PREFIX} && \
    # Copy UTC localtime to output
    cp /usr/share/zoneinfo/Etc/UTC etc/

# =============

FROM scratch
WORKDIR /

COPY --from=builder /output/ /
# Add default skeleton configuration files
ADD skel/* /etc/
RUN chmod 1777 /tmp

ADD https://gist.githubusercontent.com/frebib/2b4ba154a9d62b31b1edcb50477e7f01/raw/647c3f8ee4dc7e325cd41f40fe47735f75a7f607/ppwd.sh /usr/bin/ppwd
RUN chmod 755 /usr/bin/ppwd

ENV ENV="/etc/profile"
ENV PATH=/usr/local/sbin:/usr/local/bin:/usr/bin 

CMD ["/bin/sh"]
