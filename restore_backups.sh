#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUPS_DIR="$SCRIPT_DIR/backups"

if [[ ! -d "$BACKUPS_DIR" ]]; then
  echo "No backups directory at $BACKUPS_DIR" >&2
  exit 1
fi

LATEST=$(ls -1dt "$BACKUPS_DIR"/* 2>/dev/null | head -n1 || true)
if [[ -z "$LATEST" ]]; then
  echo "No timestamped backup directories found." >&2
  exit 1
fi

echo "Using backup set: $LATEST"

read -p "Enter target disk (e.g. /dev/mmcblk0) to restore GPT+boot (or leave blank to skip GPT): " TARGET

if [[ -n "$TARGET" ]]; then
  if [[ -f "$LATEST/gpt-backup.bin" ]]; then
    echo "Restoring GPT from $LATEST/gpt-backup.bin -> $TARGET";
    sudo sgdisk --load-backup="$LATEST/gpt-backup.bin" "$TARGET" || echo "GPT restore failed";
    sudo partprobe "$TARGET" || true
  else
    echo "GPT backup not found in $LATEST" >&2
  fi
fi

if [[ -f "$LATEST/boot-p4-backup.img" ]]; then
  read -p "Enter boot partition device (e.g. /dev/mmcblk0p4) to restore (blank skip): " BOOTDEV
  if [[ -n "${BOOTDEV}" ]]; then
    echo "Restoring boot partition...";
    sudo dd if="$LATEST/boot-p4-backup.img" of="$BOOTDEV" bs=4M conv=fsync status=progress
  fi
fi

if [[ -f "$LATEST/rootfs-p5-backup.img" ]]; then
  read -p "Enter rootfs partition device (e.g. /dev/mmcblk0p5) to restore full image (blank skip): " ROOTDEV
  if [[ -n "${ROOTDEV}" ]]; then
    echo "Restoring rootfs (this overwrites filesystem)";
    sudo dd if="$LATEST/rootfs-p5-backup.img" of="$ROOTDEV" bs=4M conv=fsync status=progress
  fi
fi

echo "Optionally restore only modules directory from modules-backup.tar.gz (y/N)?"; read -r MODS
if [[ "$MODS" =~ ^[Yy]$ && -f "$LATEST/modules-backup.tar.gz" ]]; then
  read -p "Mount point of target rootfs (must be mounted): " MOUNT
  if [[ -d "$MOUNT/lib" ]]; then
    echo "Restoring modules into $MOUNT/lib/modules";
    tar -xzf "$LATEST/modules-backup.tar.gz" -C "$MOUNT"
  else
    echo "Mount point invalid or lib/ missing" >&2
  fi
fi

echo "Recovery operations complete."
