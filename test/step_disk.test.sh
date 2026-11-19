#!/bin/sh
# Snippets are single-quoted on purpose: they are expanded in the containers.
# shellcheck disable=SC2016

# Tests of the disk step. Unprivileged tests use 64M image files in /dev as
# disks, real mkfs and blkid, and stubs for mount and umount (see
# test/data/disk/setup.sh). The privileged test uses a real loop device.

# Install the disks of test/data/disk/disks.db, check formatting, fstab, mount
# points and that a second run changes nothing. $1 is the image.
_disk_install() {
    in_container "$1" '
        . test/data/disk/setup.sh
        primer_run -s disk --disk:db /primer/test/data/disk/disks.db install
        assert_equal 0 "$PRIMER_RC" "install status"

        assert_match "TYPE=.ext4." "$(blkid /dev/fakedisk)"
        assert_match "TYPE=.ext2." "$(blkid /dev/fakedisk2)" "per-line filesystem"
        uuid1=$(blkid -s UUID -o value /dev/fakedisk)
        uuid2=$(blkid -s UUID -o value /dev/fakedisk2)
        assert_true grep -qxF "UUID=$uuid1 /mnt/disks/fakedisk ext4 defaults,nofail 0 2" /etc/fstab
        assert_true grep -qxF "UUID=$uuid2 /srv/data ext2 defaults 0 2" /etc/fstab
        assert_match "Reserved block count: +0$" "$(dumpe2fs -h /dev/fakedisk 2>/dev/null)" "ext4 options"
        assert_equal "777 0 0" "$(stat -c "%a %u %g" /mnt/disks/fakedisk)"
        assert_equal "750 1000 1000" "$(stat -c "%a %u %g" /srv/data)"
        calls=$(mock_calls)
        assert_contains "mount /mnt/disks/fakedisk" "$calls"
        assert_contains "mount /srv/data" "$calls"
        assert_contains "/dev/fakedisk2 on /srv/data type ext2" "$(mount)" "symlink resolved"

        # Second run: mounted disks are left alone.
        fstab=$(cat /etc/fstab)
        primer_run -s disk --disk:db /primer/test/data/disk/disks.db install
        assert_equal 0 "$PRIMER_RC" "second install status"
        assert_contains "already mounted" "$PRIMER_ERR"
        assert_equal "$fstab" "$(cat /etc/fstab)" "fstab after second run"
        assert_equal "$uuid1" "$(blkid -s UUID -o value /dev/fakedisk)" "not reformatted"'
}

test_disk_install_alpine() {
    _disk_install "$IMG_ALPINE"
}

test_disk_install_debian() {
    _disk_install "$IMG_TRIXIE"
}

test_disk_keeps_existing_filesystem() {
    in_container "$IMG_ALPINE" '
        . test/data/disk/setup.sh
        mkfs.ext3 -F -q /dev/fakedisk
        uuid=$(blkid -s UUID -o value /dev/fakedisk)
        echo "fakedisk:ext4:/data" > /tmp/disks.db
        primer_run -s disk --disk:db /tmp/disks.db install
        assert_equal 0 "$PRIMER_RC"
        assert_contains "already formatted as ext3, keeping it" "$PRIMER_ERR"
        assert_equal "$uuid" "$(blkid -s UUID -o value /dev/fakedisk)" "not reformatted"
        assert_true grep -qxF "UUID=$uuid /data ext3 defaults,nofail 0 2" /etc/fstab'
}

test_disk_overwrite() {
    in_container "$IMG_ALPINE" '
        . test/data/disk/setup.sh
        echo "fakedisk:ext4:/data" > /tmp/disks.db
        primer_run -s disk --disk:db /tmp/disks.db install
        assert_equal 0 "$PRIMER_RC" "first install"
        old=$(blkid -s UUID -o value /dev/fakedisk)
        umount /data
        primer_run -s disk --disk:db /tmp/disks.db --disk:overwrite 1 install
        assert_equal 0 "$PRIMER_RC" "overwrite install"
        new=$(blkid -s UUID -o value /dev/fakedisk)
        assert_false [ "$old" = "$new" ]
        assert_equal 1 "$(grep -c " /data " /etc/fstab)" "fstab entries for /data"
        assert_true grep -qxF "UUID=$new /data ext4 defaults,nofail 0 2" /etc/fstab'
}

# A whole disk with a partition table, but no filesystem of its own, is not
# blank: it is only formatted when overwriting.
test_disk_partition_table() {
    in_container "$IMG_ALPINE" '
        . test/data/disk/setup.sh
        apk add -q sfdisk >/dev/null
        printf "label: gpt\n,\n" | sfdisk -q /dev/fakedisk
        echo "fakedisk:ext4:/data" > /tmp/disks.db
        primer_run -s disk --disk:db /tmp/disks.db install
        assert_equal 0 "$PRIMER_RC" "install status"
        assert_contains "has a gpt partition table, not formatting it" "$PRIMER_ERR"
        assert_match "PTTYPE=.gpt." "$(blkid /dev/fakedisk)" "partition table kept"
        assert_false grep -q " /data " /etc/fstab
        assert_not_contains "mount /data" "$(mock_calls)"
        primer_run -s disk --disk:db /tmp/disks.db --disk:overwrite 1 install
        assert_equal 0 "$PRIMER_RC" "overwrite status"
        assert_contains "has a gpt partition table, overwriting" "$PRIMER_ERR"
        assert_match "TYPE=.ext4." "$(blkid /dev/fakedisk)"
        assert_true grep -q " /data ext4 " /etc/fstab'
}

# Encrypted volumes, swap and other non-filesystems are never formatted or
# mounted, unless overwriting. Blank devices are formatted without forcing.
test_disk_keeps_non_filesystems() {
    in_container "$IMG_ALPINE" '
        . test/data/disk/setup.sh
        apk add -q cryptsetup >/dev/null
        printf secretpassphrase | cryptsetup luksFormat --batch-mode --pbkdf pbkdf2 \
            --pbkdf-force-iterations 1000 /dev/fakedisk - >/dev/null
        mkswap /dev/fakedisk2 >/dev/null
        printf "fakedisk:ext4:/secret\nfakedisk2:ext4:/swap\n" > /tmp/disks.db
        primer_run -s disk --disk:db /tmp/disks.db install
        assert_equal 0 "$PRIMER_RC" "install status"
        assert_contains "contains crypto_LUKS, which is not a filesystem, not touching it" "$PRIMER_ERR"
        assert_contains "contains swap, which is not a filesystem, not touching it" "$PRIMER_ERR"
        assert_match "TYPE=.crypto_LUKS." "$(blkid /dev/fakedisk)" "LUKS kept"
        assert_match "TYPE=.swap." "$(blkid /dev/fakedisk2)" "swap kept"
        assert_false grep -qE " /(secret|swap) " /etc/fstab
        primer_run -s disk --disk:db /tmp/disks.db --disk:overwrite 1 install
        assert_equal 0 "$PRIMER_RC" "overwrite status"
        assert_contains "already formatted as crypto_LUKS, overwriting" "$PRIMER_ERR"
        assert_contains "with options: -F" "$PRIMER_ERR" "forced when overwriting"
        assert_match "TYPE=.ext4." "$(blkid /dev/fakedisk)"
        # Blank devices are not forced
        dd if=/dev/zero of=/dev/fakedisk2 bs=1M count=1 conv=notrunc 2>/dev/null
        umount /secret
        umount /swap
        printf "fakedisk2:ext4:/blank\n" > /tmp/disks.db
        primer_run -s disk --disk:db /tmp/disks.db install
        assert_equal 0 "$PRIMER_RC" "blank status"
        assert_contains "Formatting /dev/fakedisk2 as ext4" "$PRIMER_ERR"
        assert_not_contains "-F" "$(echo "$PRIMER_ERR" | grep Formatting)" "not forced on blank devices"
        assert_match "TYPE=.ext4." "$(blkid /dev/fakedisk2)"'
}

test_disk_missing_device() {
    in_container "$IMG_ALPINE" '
        . test/data/disk/setup.sh
        echo "nosuchdisk" > /tmp/disks.db
        primer_run -s disk --disk:db /tmp/disks.db install
        assert_equal 0 "$PRIMER_RC"
        assert_contains "nosuchdisk is not an existing device" "$PRIMER_ERR"
        primer_run -s disk install
        assert_equal 0 "$PRIMER_RC"
        assert_contains "No user disk specification" "$PRIMER_ERR"'
}

test_disk_unknown_filesystem() {
    in_container "$IMG_ALPINE" '
        . test/data/disk/setup.sh
        echo "fakedisk:nosuchfs" > /tmp/disks.db
        primer_run -s disk --disk:db /tmp/disks.db install
        assert_equal 0 "$PRIMER_RC"
        assert_contains "nosuchfs is an unknown filesystem type" "$PRIMER_ERR"
        assert_false grep -q fakedisk /etc/fstab'
}

test_disk_clean() {
    in_container "$IMG_TRIXIE" '
        . test/data/disk/setup.sh
        # Start from an empty fstab, owned by a group and with a specific mode
        : > /etc/fstab
        chgrp 1000 /etc/fstab
        chmod 640 /etc/fstab
        primer_run -s disk --disk:db /primer/test/data/disk/disks.db install
        assert_equal 0 "$PRIMER_RC" "install status"
        # A mount point already gone (unmounted and removed by hand)
        umount /srv/data && rmdir /srv/data
        primer_run -s disk --disk:db /primer/test/data/disk/disks.db clean
        assert_equal 0 "$PRIMER_RC" "clean status"
        assert_contains "umount /mnt/disks/fakedisk" "$(mock_calls)"
        assert_equal "" "$(cat /etc/fstab)" "fstab after clean"
        assert_equal "640 0 1000" "$(stat -c "%a %u %g" /etc/fstab)" "fstab mode and owner"
        assert_false [ -d /mnt/disks/fakedisk ]
        assert_equal "" "$(mount)" "nothing mounted"

        # Cleaning again is harmless
        primer_run -s disk --disk:db /primer/test/data/disk/disks.db clean
        assert_equal 0 "$PRIMER_RC" "second clean status"'
}

test_disk_loop_device() {
    require_privileged
    in_container -P "$IMG_TRIXIE" '
        apt-get update -qq >/dev/null
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq e2fsprogs mount >/dev/null
        dd if=/dev/zero of=/tmp/primer-test-disk.img bs=1M count=0 seek=64 2>/dev/null
        loop=$(losetup -f --show /tmp/primer-test-disk.img) || skip "cannot attach a loop device"
        # Always detach: loop devices are shared with the host. Cleaning must
        # not stop at the first error (the container script runs with set -e).
        trap "rc=\$?; set +e; umount /mnt/loop 2>/dev/null; losetup -d $loop; exit \$rc" EXIT
        name=${loop#/dev/}
        # The device node may not exist in the container
        if ! [ -b "$loop" ]; then
            mknod "$loop" b 7 "${name#loop}"
        fi
        echo "$name:ext4:/mnt/loop" > /tmp/disks.db
        primer_run -s disk --disk:db /tmp/disks.db install
        assert_equal 0 "$PRIMER_RC" "install status"
        assert_match "^$loop on /mnt/loop type ext4" "$(mount)"
        assert_true touch /mnt/loop/file
        primer_run -s disk --disk:db /tmp/disks.db clean
        assert_equal 0 "$PRIMER_RC" "clean status"
        assert_false grep -q " /mnt/loop " /proc/mounts
        assert_false grep -q " /mnt/loop " /etc/fstab'
}
