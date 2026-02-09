#!/usr/bin/env bash
# lib/06-zram.sh — Configure zram swap with zstd compression
# Sourced by install.sh. Defines run_zram() only.

# ---------------------------------------------------------------------------
# run_zram — Write zram-generator and sysctl config for zram swap
# ---------------------------------------------------------------------------
# Takes effect after reboot only. Overwrite-idempotent (same content on re-run).

run_zram() {
    info "Configuring zram swap..."

    # -- zram-generator config ------------------------------------------------
    info "Writing /etc/systemd/zram-generator.conf..."
    sudo tee /etc/systemd/zram-generator.conf >/dev/null <<'EOF'
# Surface Go 3 zram configuration
# 4GB RAM -> 4GB zram (1:1 ratio with zstd compression)
[zram0]
zram-size = ram
compression-algorithm = zstd
EOF
    success "zram-generator.conf written"

    # -- sysctl tuning for zram workload --------------------------------------
    info "Writing /etc/sysctl.d/99-zram.conf..."
    sudo tee /etc/sysctl.d/99-zram.conf >/dev/null <<'EOF'
# Tuned sysctl values for zram swap workload
# Higher swappiness is optimal with zram (compressed RAM is cheap)
vm.swappiness = 180
vm.watermark_boost_factor = 0
vm.watermark_scale_factor = 125
vm.page-cluster = 0
EOF
    success "sysctl zram tuning written"

    info "zram configuration complete. Takes effect after reboot."
}
