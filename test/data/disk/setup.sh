#!/bin/sh

# Sourced inside test containers (with test/lib.sh) to fake a host with two
# empty disks: /dev/fakedisk and /dev/fakedisk2 (also reachable as the
# /dev/bylabel symlink) are 64M image files. e2fsprogs is installed for real
# mkfs.ext* and dumpe2fs. mount and umount are replaced by stubs that maintain
# a fake mount table at /tmp/mounted, using /etc/fstab to find the device of a
# mount point, and log their calls to $MOCK_LOG.

for _d in fakedisk fakedisk2; do
    rm -f "/dev/$_d"
    dd if=/dev/zero of="/dev/$_d" bs=1M count=0 seek=64 2>/dev/null
done
ln -sf fakedisk2 /dev/bylabel

if command -v apk >/dev/null 2>&1; then
    apk add -q e2fsprogs e2fsprogs-extra blkid >/dev/null
else
    apt-get update -qq >/dev/null && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq e2fsprogs >/dev/null
fi

: > /tmp/mounted
stub_bin mount "if [ \$# = 0 ]; then cat /tmp/mounted; exit 0; fi
printf '%s\\n' \"mount \$*\" >> $MOCK_LOG
entry=\$(awk -v m=\"\$1\" '\$2 == m' /etc/fstab)
uuid=\$(printf %s \"\$entry\" | awk '{print \$1}' | sed 's/^UUID=//')
fs=\$(printf %s \"\$entry\" | awk '{print \$3}')
for d in /dev/fakedisk /dev/fakedisk2; do
    if blkid \"\$d\" | grep -q \"UUID=.\$uuid.\"; then
        printf '%s on %s type %s (rw)\\n' \"\$d\" \"\$1\" \"\$fs\" >> /tmp/mounted
        exit 0
    fi
done
echo \"mount: \$1: cannot find device\" >&2
exit 32"
stub_bin umount "printf '%s\\n' \"umount \$*\" >> $MOCK_LOG
grep -v \" on \$1 type \" /tmp/mounted > /tmp/mounted.new || true
mv /tmp/mounted.new /tmp/mounted"
