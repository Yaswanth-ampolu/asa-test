#!/usr/bin/env bash
# QuestaSim simulation script for ASA project
# Usage: ./scripts/questa_sim.sh [target]
#   targets: oam (default), node_fsm, regbank, phy_startup, ptb, lls, keyex, asep_common, asep_gpio, asep_spi, asep_i2c, asep_i2s, all

set -e

export PATH="/silicogenplayground/questasim/bin:$PATH"
export LM_LICENSE_FILE="/silicogenplayground/questasim/license.dat"

PROJ_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="$PROJ_ROOT/questa_work"
TARGET="${1:-oam}"

# ============================================================
# Source file lists
# ============================================================
COMMON_PKGS=(
  hw/common/rtl/asa_node_pkg.sv
  hw/common/rtl/asa_reg_pkg.sv
  hw/common/rtl/asa_intf_pkg.sv
  hw/common/rtl/asa_error_pkg.sv
)

COMMON_MODS=(
  hw/common/rtl/asa_error_aggregator.sv
)

REG_MODS=(
  hw/register_model/rtl/asa_reg_access.sv
  hw/register_model/rtl/asa_reg_bank.sv
  hw/register_model/rtl/asa_soft_reset_ctrl.sv
)

NODE_FSM_MODS=(
  hw/node_fsm/rtl/asa_node_fsm.sv
  hw/node_fsm/rtl/asa_node_fsm_top.sv
)

OAM_PKGS=(hw/oam/rtl/asa_oam_pkg.sv)
OAM_MODS=(
  hw/oam/rtl/oam_header_gen.sv
  hw/oam/rtl/oam_header_check.sv
  hw/oam/rtl/oam_resp_fifo.sv
  hw/oam/rtl/oam_error_counters.sv
  hw/oam/rtl/oam_cad_parser.sv
  hw/oam/rtl/oam_reg_bridge.sv
  hw/oam/rtl/oam_longatom.sv
  hw/oam/rtl/oam_keyex_bridge.sv
  hw/oam/rtl/oam_ls_bridge.sv
  hw/oam/rtl/oam_rx_fsm.sv
  hw/oam/rtl/oam_tx_fsm.sv
  hw/oam/rtl/oam_top.sv
)

DLL_PKGS=(hw/dll_mapper/rtl/asa_dll_pkg.sv)
DLL_MODS=(
  hw/dll_mapper/rtl/dll_header_parse.sv
  hw/dll_mapper/rtl/dll_header_build.sv
  hw/dll_mapper/rtl/dll_rx_demux.sv
  hw/dll_mapper/rtl/dll_tx_mapper.sv
  hw/dll_mapper/rtl/dll_security_if.sv
  hw/dll_mapper/rtl/dll_top.sv
)

PCS_PKGS=(hw/phy_pcs/rtl/asa_pcs_pkg.sv)
PCS_MODS=(
  hw/phy_pcs/rtl/pcs_prbs11.sv
  hw/phy_pcs/rtl/pcs_prbs9.sv
  hw/phy_pcs/rtl/pcs_scrambler.sv
  hw/phy_pcs/rtl/pcs_pam_map.sv
  hw/phy_pcs/rtl/pcs_crc32.sv
  hw/phy_pcs/rtl/pcs_rs_encoder.sv
  hw/phy_pcs/rtl/pcs_resync_header.sv
  hw/phy_pcs/rtl/pcs_ptb_vector_if.sv
  hw/phy_pcs/rtl/pcs_tx_top.sv
  hw/phy_pcs/rtl/pcs_rx_top.sv
  hw/phy_pcs/rtl/pcs_top.sv
)

PHY_STARTUP_PKGS=(hw/phy_startup/rtl/asa_phy_startup_pkg.sv)
PHY_STARTUP_MODS=(
  hw/phy_startup/rtl/phy_startup_top.sv
)

PTB_PKGS=(hw/ptb/rtl/asa_ptb_pkg.sv)
PTB_MODS=(
  hw/ptb/rtl/ptb_delay_calc.sv
  hw/ptb/rtl/ptb_counter_48.sv
  hw/ptb/rtl/ptb_follow_fsm.sv
  hw/ptb/rtl/ptb_oam_header_if.sv
  hw/ptb/rtl/ptb_timer_compare.sv
  hw/ptb/rtl/ptb_top.sv
)

LLS_PKGS=(hw/security/rtl/asa_lls_pkg.sv)
LLS_MODS=(
  hw/security/rtl/lls_keyslot_ctrl.sv
  hw/security/rtl/lls_tx_protect.sv
  hw/security/rtl/lls_rx_verify.sv
  hw/security/rtl/lls_top.sv
)

KEYEX_PKGS=(
  hw/common/rtl/asa_node_pkg.sv
  hw/common/rtl/asa_reg_pkg.sv
  hw/common/rtl/asa_intf_pkg.sv
  hw/common/rtl/asa_error_pkg.sv
  hw/oam/rtl/asa_oam_pkg.sv
  hw/keyex/rtl/asa_keyex_pkg.sv
)
KEYEX_MODS=(
  hw/keyex/rtl/keyex_top.sv
)

ASEP_PKGS=(hw/asep/rtl/asa_asep_pkg.sv)
ASEP_MODS=(
  hw/asep/rtl/asep_frag_encode.sv
  hw/asep/rtl/asep_frag_decode.sv
  hw/asep/rtl/asep_reassembly.sv
  hw/asep/rtl/asep_tx_common.sv
  hw/asep/rtl/asep_rx_common.sv
  hw/asep/rtl/asep_common_top.sv
)

GPIO_ASEP_PKGS=(hw/asep/rtl/asa_gpio_asep_pkg.sv)
GPIO_ASEP_MODS=(
  hw/asep/rtl/gpio_pkt_id_counter.sv
  hw/asep/rtl/gpio_sample_clk_gen.sv
  hw/asep/rtl/gpio_cfg_codec.sv
  hw/asep/rtl/gpio_fs_codec.sv
  hw/asep/rtl/gpio_eg_codec.sv
  hw/asep/rtl/gpio_ase_tx.sv
  hw/asep/rtl/gpio_asd_rx.sv
  hw/asep/rtl/gpio_asep_top.sv
)

SPI_ASEP_PKGS=(hw/asep/rtl/asa_spi_asep_pkg.sv)
SPI_ASEP_MODS=(
  hw/asep/rtl/spi_pkt_id_counter.sv
  hw/asep/rtl/spi_irq_counter.sv
  hw/asep/rtl/spi_cfg_codec.sv
  hw/asep/rtl/spi_dcp_timer.sv
  hw/asep/rtl/spi_tat_timer.sv
  hw/asep/rtl/spi_data_codec.sv
  hw/asep/rtl/spi_ase_tx.sv
  hw/asep/rtl/spi_asd_rx.sv
  hw/asep/rtl/spi_asep_top.sv
)

I2C_ASEP_PKGS=(hw/asep/rtl/asa_i2c_asep_pkg.sv)
I2C_ASEP_MODS=(
  hw/asep/rtl/i2c_cmd_id_mgr.sv
  hw/asep/rtl/i2c_byte_codec.sv
  hw/asep/rtl/i2c_bulk_codec.sv
  hw/asep/rtl/i2c_cfg_codec.sv
  hw/asep/rtl/i2c_ase_tx.sv
  hw/asep/rtl/i2c_asd_rx.sv
  hw/asep/rtl/i2c_asep_top.sv
)

I2S_ASEP_PKGS=(hw/asep/rtl/asa_i2s_asep_pkg.sv)
I2S_ASEP_MODS=(
  hw/asep/rtl/i2s_pkt_id_counter.sv
  hw/asep/rtl/i2s_cfg_codec.sv
  hw/asep/rtl/i2s_data_codec.sv
  hw/asep/rtl/i2s_ptb_sync.sv
  hw/asep/rtl/i2s_ase_tx.sv
  hw/asep/rtl/i2s_asd_rx.sv
  hw/asep/rtl/i2s_asep_top.sv
)

VIDEO_ASEP_PKGS=(hw/asep/rtl/asa_video_asep_pkg.sv)
VIDEO_ASEP_MODS=(
  hw/asep/rtl/video_payload_codec.sv
  hw/asep/rtl/video_line_hdr.sv
  hw/asep/rtl/video_pixelclk_codec.sv
  hw/asep/rtl/video_ase_tx.sv
  hw/asep/rtl/video_asd_rx.sv
  hw/asep/rtl/video_asep_top.sv
)

EDP_ASEP_PKGS=(hw/asep/rtl/asa_edp_asep_pkg.sv)
EDP_ASEP_MODS=(
  hw/asep/rtl/edp_vb_codec.sv
  hw/asep/rtl/edp_edm_data_codec.sv
  hw/asep/rtl/edp_aux_codec.sv
  hw/asep/rtl/edp_stream_clock_codec.sv
  hw/asep/rtl/edp_plm_8b10b_codec.sv
  hw/asep/rtl/edp_plm_128b132b_codec.sv
  hw/asep/rtl/edp_ase_tx.sv
  hw/asep/rtl/edp_asd_rx.sv
  hw/asep/rtl/edp_asep_top.sv
)

# ============================================================
# Helper: compile a list of files
# ============================================================
compile() {
  local files=("$@")
  local abs_files=()
  for f in "${files[@]}"; do
    abs_files+=("$PROJ_ROOT/$f")
  done
  vlog -sv -suppress 2892 -suppress 7061 "${abs_files[@]}"
}

# ============================================================
# Helper: run simulation
# ============================================================
simulate() {
  local tb="$1"
  echo "=== Simulating $tb ==="
  vsim -batch "work.$tb" -do "run -all; quit" 2>&1 | grep -v "^# $" | grep -v "^# Loading"
}

# ============================================================
# Setup work library
# ============================================================
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"
vlib work 2>/dev/null || true

# ============================================================
# Targets
# ============================================================
run_node_fsm() {
  echo "=== Compiling Node FSM ==="
  compile "${COMMON_PKGS[@]}" "${NODE_FSM_MODS[@]}" hw/node_fsm/dv/asa_node_fsm_tb.sv
  simulate asa_node_fsm_tb
}

run_regbank() {
  echo "=== Compiling Register Bank ==="
  compile "${COMMON_PKGS[@]}" hw/register_model/rtl/asa_reg_bank.sv \
          hw/register_model/dv/asa_reg_bank_tb.sv
  simulate asa_reg_bank_tb
}

run_oam() {
  echo "=== Compiling OAM ==="
  compile "${COMMON_PKGS[@]}" "${OAM_PKGS[@]}" "${REG_MODS[@]}" \
          "${OAM_MODS[@]}" hw/oam/dv/oam_tb.sv
  simulate oam_tb
}

run_light_sleep() {
  echo "=== Compiling Light Sleep FSM ==="
  compile hw/light_sleep/rtl/asa_ls_pkg.sv \
          hw/light_sleep/rtl/ls_ctrl_fsm.sv \
          hw/light_sleep/rtl/ls_oam_bridge.sv \
          hw/light_sleep/rtl/ls_ptb_if.sv \
          hw/light_sleep/rtl/ls_top.sv \
          hw/light_sleep/dv/ls_tb.sv
  simulate ls_tb
}

run_dll_fwd() {
  echo "=== Compiling DLL Forwarding Fabric ==="
  compile "${DLL_PKGS[@]}" hw/dll_forwarding/rtl/asa_fofa_pkg.sv \
          hw/dll_forwarding/rtl/fofa_queue.sv \
          hw/dll_forwarding/rtl/fofa_switch_ctrl.sv \
          hw/dll_forwarding/rtl/fofa_local_reinject.sv \
          hw/dll_forwarding/rtl/fofa_top.sv \
          hw/dll_forwarding/dv/fofa_tb.sv
  simulate fofa_tb
}

run_dll_mapper() {
  echo "=== Compiling DLL Mapper ==="
  compile "${DLL_PKGS[@]}" "${DLL_MODS[@]}" hw/dll_mapper/dv/dll_tb.sv
  simulate dll_tb
}

run_phy_pcs() {
  echo "=== Compiling PHY PCS ==="
  compile hw/common/rtl/asa_error_pkg.sv "${PCS_PKGS[@]}" "${PCS_MODS[@]}" \
          hw/phy_pcs/dv/pcs_tb.sv
  simulate pcs_tb
}

run_phy_startup() {
  echo "=== Compiling PHY Startup ==="
  compile "${COMMON_PKGS[@]}" "${PHY_STARTUP_PKGS[@]}" "${PHY_STARTUP_MODS[@]}" \
          hw/phy_startup/dv/phy_startup_tb.sv
  simulate phy_startup_tb
}

run_ptb() {
  echo "=== Compiling PTB Clock Service ==="
  compile "${COMMON_PKGS[@]}" "${PTB_PKGS[@]}" "${PTB_MODS[@]}" \
          hw/ptb/dv/ptb_tb.sv
  simulate ptb_tb
}

run_lls() {
  echo "=== Compiling Link Layer Security ==="
  compile "${LLS_PKGS[@]}" "${LLS_MODS[@]}" \
          hw/security/dv/lls_tb.sv
  simulate lls_tb
}

run_keyex() {
  echo "=== Compiling KeyEx Entity ==="
  compile "${KEYEX_PKGS[@]}" "${KEYEX_MODS[@]}" \
          hw/keyex/dv/keyex_tb.sv
  simulate keyex_tb
}

run_asep_common() {
  echo "=== Compiling ASEP Common Framing ==="
  compile "${COMMON_PKGS[@]}" "${ASEP_PKGS[@]}" "${ASEP_MODS[@]}" \
          hw/asep/dv/asep_common_tb.sv
  simulate asep_common_tb
}

run_asep_gpio() {
  echo "=== Compiling ASEP GPIO ==="
  compile "${COMMON_PKGS[@]}" "${ASEP_PKGS[@]}" "${GPIO_ASEP_PKGS[@]}" "${GPIO_ASEP_MODS[@]}" \
          hw/asep/dv/asep_gpio_tb.sv
  simulate asep_gpio_tb
}

run_asep_spi() {
  echo "=== Compiling ASEP SPI ==="
  compile "${COMMON_PKGS[@]}" "${ASEP_PKGS[@]}" "${SPI_ASEP_PKGS[@]}" "${SPI_ASEP_MODS[@]}" \
          hw/asep/dv/asep_spi_tb.sv
  simulate asep_spi_tb
}

run_asep_i2c() {
  echo "=== Compiling ASEP I2C ==="
  compile "${COMMON_PKGS[@]}" "${ASEP_PKGS[@]}" "${I2C_ASEP_PKGS[@]}" "${I2C_ASEP_MODS[@]}" \
          hw/asep/dv/asep_i2c_tb.sv
  simulate asep_i2c_tb
}

run_asep_i2s() {
  echo "=== Compiling ASEP I2S ==="
  compile "${COMMON_PKGS[@]}" "${ASEP_PKGS[@]}" "${I2S_ASEP_PKGS[@]}" "${I2S_ASEP_MODS[@]}" \
          hw/asep/dv/asep_i2s_tb.sv
  simulate asep_i2s_tb
}

run_asep_video() {
  echo "=== Compiling ASEP Video ==="
  compile "${COMMON_PKGS[@]}" "${ASEP_PKGS[@]}" "${VIDEO_ASEP_PKGS[@]}" "${VIDEO_ASEP_MODS[@]}" \
          hw/asep/dv/asep_video_tb.sv
  simulate asep_video_tb
}

run_asep_edp() {
  echo "=== Compiling ASEP eDP ==="
  compile "${COMMON_PKGS[@]}" "${ASEP_PKGS[@]}" "${EDP_ASEP_PKGS[@]}" "${EDP_ASEP_MODS[@]}" \
          hw/asep/dv/asep_edp_tb.sv
  simulate asep_edp_tb
}

case "$TARGET" in
  node_fsm) run_node_fsm ;;
  regbank)  run_regbank  ;;
  oam)      run_oam      ;;
  phy_pcs)     run_phy_pcs     ;;
  dll_mapper)  run_dll_mapper  ;;
  dll_fwd)     run_dll_fwd     ;;
  light_sleep) run_light_sleep ;;
  phy_startup) run_phy_startup ;;
  ptb)      run_ptb      ;;
  lls)      run_lls      ;;
  keyex)    run_keyex    ;;
  asep_common) run_asep_common ;;
  asep_gpio) run_asep_gpio ;;
  asep_spi) run_asep_spi ;;
  asep_i2c) run_asep_i2c ;;
  asep_i2s) run_asep_i2s ;;
  asep_video) run_asep_video ;;
  asep_edp) run_asep_edp ;;
  all)
    run_node_fsm
    run_regbank
    run_oam
    run_phy_pcs
    run_phy_startup
    run_ptb
    run_lls
    run_keyex
    run_asep_common
    run_asep_gpio
    run_asep_spi
    run_asep_i2c
    run_asep_i2s
    run_asep_video
    run_asep_edp
    ;;
  *)
    echo "Unknown target: $TARGET"
    echo "Usage: $0 [node_fsm|regbank|oam|phy_pcs|dll_mapper|dll_fwd|light_sleep|phy_startup|ptb|lls|keyex|asep_common|asep_gpio|asep_spi|asep_i2c|asep_i2s|asep_video|asep_edp|all]"
    exit 1
    ;;
esac

echo ""
echo "=== QuestaSim simulation complete ==="
