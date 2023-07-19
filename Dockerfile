FROM ubuntu as image
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y cpio grub2 grub-efi-amd64-bin xorriso mtools

WORKDIR /output

WORKDIR /image
RUN mkdir -p boot/grub && printf 'halt\n' > boot/grub/grub.cfg
RUN grub-mkrescue -o /output/image.iso .
RUN chmod -R +r /output

###############################################################################

FROM scratch
COPY --from=image /output /
