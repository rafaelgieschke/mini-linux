# ./build --build-arg image=ubuntu --build-arg kernel=linux-generic
# ./build --build-arg image=fedora --build-arg kernel=kernel
# ./build --build-arg image=archlinux --build-arg kernel=linux

ARG image="ubuntu"
# ARG image="fedora"
# ARG image="archlinux"

FROM "$image" as kernel

# In Ubuntu, linux-generic installs linux-image-generic and linux-headers-generic
# and provides exactly the same kernel as linux-kvm/linux-virtual.
ARG kernel="linux-generic"
# ARG kernel="kernel"
# ARG kernel="linux"

WORKDIR /kernel
RUN if type apt-get; then \
    apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y "$kernel"; \
  elif type dnf; then \
    dnf install -y "$kernel"; \
  elif type pacman; then \
    pacman --noconfirm -Sy "$kernel"; \
  fi
RUN basename -- /lib/modules/* > version \
  && ( cp -v "/boot/vmlinuz-$(cat version)" kernel \
    || cp -v "/boot/vmlinuz-linux" kernel \
    || cp -v "/lib/modules/$(cat version)/vmlinuz" kernel ) \
  && ( cp -v "/boot/config-$(cat version)" config \
    || cp -v "/lib/modules/$(cat version)/config" config \
    || touch config )

# $modules are present and loaded on-demand by the kernel using modprobe,
# see <https://github.com/torvalds/linux/blob/5e321ded302da4d8c5d5dd953423d9b748ab3775/kernel/kmod.c#L61>.
ARG modules="iso9660"
# $modules_load are loaded by init on start-up
ARG modules_load="loop fuse ahci msdos vfat ne2k-pci 8139cp e1000 virtio_rng bochs cirrus simpledrm i8042 atkbd"
WORKDIR /modules
# See https://www.kernel.org/doc/Documentation/kbuild/kbuild.txt
RUN cp -v --parents "/lib/modules/$(cat /kernel/version)/modules.order" .
RUN cp -v --parents "/lib/modules/$(cat /kernel/version)/modules.builtin" .
RUN modprobe -aDS "$(cat /kernel/version)" $modules_load \
  | awk '!seen[$0]++' | sed "s/^builtin /# &/;s/^insmod //" >> /tmp/modules \
  && cp -v --parents $(sed "/^#/d" /tmp/modules) . \
  && mkdir -p etc \
  && sed -E 's/^[^#].+\///;s/\.ko(.zst|.xz)?\s*$//' /tmp/modules | tee etc/modules
RUN modprobe -aDS "$(cat /kernel/version)" $modules \
  | awk '!seen[$0]++' | sed "s/^builtin /# &/" \
  | sed "/^#/d;s/^insmod //" \
  | xargs --no-run-if-empty cp -v --parents -t .
RUN cp -v --parents "/lib/modules/$(cat /kernel/version)/kernel/fs/nls/"*.ko* . || :
RUN zstd --rm -d "lib/modules/$(cat /kernel/version)/kernel/fs/nls/"*.ko.zst || :

###############################################################################

FROM alpine as initrd
# initrd needs /sbin/modprobe and depmod
RUN ln -s /bin /sbin
RUN apk add kmod
COPY --from=kernel /modules .
RUN depmod "$(basename -- /lib/modules/*/)"

WORKDIR /
RUN apk add curl openssh-server screen
# ADD https://github.com/opencontainers/runc/releases/latest/download/runc.amd64 runc
# RUN chmod a+x runc
RUN apk add runc

COPY init /init

FROM ubuntu as image
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y cpio grub2 grub-efi-amd64-bin xorriso mtools

WORKDIR /output
COPY --from=kernel /kernel .
RUN rm version

WORKDIR /initrd
COPY --from=initrd / .
RUN find . | cpio -o -H newc | gzip -c > /output/initrd

WORKDIR /image
RUN ln /output/* .
RUN mkdir -p boot/grub && printf 'linux /kernel\ninitrd /initrd\nboot\n' > boot/grub/grub.cfg
# RUN truncate --size 10M /tmp/part
# RUN mkfs.ext4 -d /output /tmp/part 50M
RUN grub-mkrescue -o /output/mini-linux.iso . -- -hfsplus off `#--append_partition 1 0fc63daf-8483-4772-8e79-3d69d8477de4 /tmp/part` -boot_image any appended_part_as=gpt -boot_image any partition_cyl_align=all -padding 0
RUN chmod -R +r /output

###############################################################################

FROM scratch
COPY --from=image /output /
