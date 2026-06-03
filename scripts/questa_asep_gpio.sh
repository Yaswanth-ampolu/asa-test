#!/usr/bin/env bash
set -euo pipefail

export PATH="/silicogenplayground/questasim/bin:$PATH"
export LM_LICENSE_FILE="/silicogenplayground/questasim/license.dat"

PROJ_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="$PROJ_ROOT/questa_work_asep_gpio"
LOG_FILE="$WORK_DIR/asep_gpio_vsim.log"

mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

rm -rf work
vlib work

vlog -sv -suppress 2892 -suppress 7061 \
  "$PROJ_ROOT/hw/common/rtl/asa_node_pkg.sv" \
  "$PROJ_ROOT/hw/common/rtl/asa_reg_pkg.sv" \
  "$PROJ_ROOT/hw/common/rtl/asa_intf_pkg.sv" \
  "$PROJ_ROOT/hw/common/rtl/asa_error_pkg.sv" \
  "$PROJ_ROOT/hw/asep/rtl/asa_asep_pkg.sv" \
  "$PROJ_ROOT/hw/asep/rtl/asa_gpio_asep_pkg.sv" \
  "$PROJ_ROOT/hw/asep/rtl/gpio_pkt_id_counter.sv" \
  "$PROJ_ROOT/hw/asep/rtl/gpio_sample_clk_gen.sv" \
  "$PROJ_ROOT/hw/asep/rtl/gpio_cfg_codec.sv" \
  "$PROJ_ROOT/hw/asep/rtl/gpio_fs_codec.sv" \
  "$PROJ_ROOT/hw/asep/rtl/gpio_eg_codec.sv" \
  "$PROJ_ROOT/hw/asep/rtl/gpio_ase_tx.sv" \
  "$PROJ_ROOT/hw/asep/rtl/gpio_asd_rx.sv" \
  "$PROJ_ROOT/hw/asep/rtl/gpio_asep_top.sv" \
  "$PROJ_ROOT/hw/asep/dv/asep_gpio_tb.sv"

: > "$LOG_FILE"
vsim -batch work.asep_gpio_tb -do "run -all; quit" 2>&1 | tee "$LOG_FILE"
