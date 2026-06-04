# ASA Project - Simulation Makefile
# Structure follows OpenTitan/PULP conventions:
#   hw/common/rtl/    — shared packages and utilities
#   hw/{module}/rtl/  — per-module RTL
#   hw/{module}/dv/   — per-module testbenches
#   hw/top/dv/        — integration testbenches

VERILATOR := verilator
IVERILOG  := iverilog
VVP       := vvp
OBJ_DIR   := obj_dir
OBJ_DIR_REG := $(OBJ_DIR)/regbank
OBJ_DIR_OAM := $(OBJ_DIR)/oam
OBJ_DIR_PHY := $(OBJ_DIR)/phy_startup
OBJ_DIR_PTB := $(OBJ_DIR)/ptb
OBJ_DIR_LLS := $(OBJ_DIR)/lls
OBJ_DIR_KEYEX := $(OBJ_DIR)/keyex
OBJ_DIR_ASEP := $(OBJ_DIR)/asep
OBJ_DIR_ASEP_GPIO := $(OBJ_DIR)/asep_gpio
OBJ_DIR_ASEP_SPI := $(OBJ_DIR)/asep_spi
OBJ_DIR_ASEP_I2C := $(OBJ_DIR)/asep_i2c
OBJ_DIR_ASEP_I2S := $(OBJ_DIR)/asep_i2s
OBJ_DIR_ASEP_VIDEO := $(OBJ_DIR)/asep_video
OBJ_DIR_ASEP_EDP := $(OBJ_DIR)/asep_edp
OBJ_DIR_MLE_PCS := $(OBJ_DIR)/mle_pcs
OBJ_DIR_MLE_XMII := $(OBJ_DIR)/mle_xmii

# ============================================================================
# Source file lists (dependency order)
# ============================================================================

# Shared packages (must compile first)
COMMON_PKGS := hw/common/rtl/asa_node_pkg.sv \
               hw/common/rtl/asa_reg_pkg.sv \
               hw/common/rtl/asa_intf_pkg.sv \
               hw/common/rtl/asa_error_pkg.sv

COMMON_MODS := hw/common/rtl/asa_error_aggregator.sv

# Register model
REG_MODS := hw/register_model/rtl/asa_reg_access.sv \
            hw/register_model/rtl/asa_reg_bank.sv \
            hw/register_model/rtl/asa_soft_reset_ctrl.sv

# Node FSM
NODE_MODS := hw/node_fsm/rtl/asa_node_fsm.sv \
             hw/node_fsm/rtl/asa_node_fsm_top.sv

# OAM
OAM_PKGS := hw/oam/rtl/asa_oam_pkg.sv
OAM_MODS := hw/oam/rtl/oam_header_gen.sv \
            hw/oam/rtl/oam_header_check.sv \
            hw/oam/rtl/oam_resp_fifo.sv \
            hw/oam/rtl/oam_error_counters.sv \
            hw/oam/rtl/oam_cad_parser.sv \
            hw/oam/rtl/oam_reg_bridge.sv \
            hw/oam/rtl/oam_longatom.sv \
            hw/oam/rtl/oam_keyex_bridge.sv \
            hw/oam/rtl/oam_ls_bridge.sv \
            hw/oam/rtl/oam_rx_fsm.sv \
            hw/oam/rtl/oam_tx_fsm.sv \
            hw/oam/rtl/oam_top.sv

# PHY Startup
PHY_STARTUP_PKGS := hw/phy_startup/rtl/asa_phy_startup_pkg.sv
PHY_STARTUP_MODS := hw/phy_startup/rtl/phy_startup_top.sv

# PTB Clock Service
PTB_PKGS := hw/ptb/rtl/asa_ptb_pkg.sv
PTB_MODS := hw/ptb/rtl/ptb_delay_calc.sv \
            hw/ptb/rtl/ptb_counter_48.sv \
            hw/ptb/rtl/ptb_follow_fsm.sv \
            hw/ptb/rtl/ptb_oam_header_if.sv \
            hw/ptb/rtl/ptb_timer_compare.sv \
            hw/ptb/rtl/ptb_top.sv

# Light Sleep FSM
LS_PKGS := hw/light_sleep/rtl/asa_ls_pkg.sv
LS_MODS := hw/light_sleep/rtl/ls_ctrl_fsm.sv \
           hw/light_sleep/rtl/ls_oam_bridge.sv \
           hw/light_sleep/rtl/ls_ptb_if.sv \
           hw/light_sleep/rtl/ls_top.sv

# Link Layer Security
LLS_PKGS := hw/security/rtl/asa_lls_pkg.sv
LLS_MODS := hw/security/rtl/lls_keyslot_ctrl.sv \
            hw/security/rtl/lls_tx_protect.sv \
            hw/security/rtl/lls_rx_verify.sv \
            hw/security/rtl/lls_top.sv

# KeyEx
KEYEX_PKGS := $(COMMON_PKGS) \
              hw/oam/rtl/asa_oam_pkg.sv \
              hw/keyex/rtl/asa_keyex_pkg.sv
KEYEX_MODS := hw/keyex/rtl/keyex_top.sv

# ASEP Common Framing
ASEP_PKGS := hw/asep/rtl/asa_asep_pkg.sv
ASEP_MODS := hw/asep/rtl/asep_frag_encode.sv \
             hw/asep/rtl/asep_frag_decode.sv \
             hw/asep/rtl/asep_reassembly.sv \
             hw/asep/rtl/asep_tx_common.sv \
             hw/asep/rtl/asep_rx_common.sv \
             hw/asep/rtl/asep_common_top.sv

GPIO_ASEP_PKGS := hw/asep/rtl/asa_gpio_asep_pkg.sv
GPIO_ASEP_MODS := hw/asep/rtl/gpio_pkt_id_counter.sv \
                  hw/asep/rtl/gpio_sample_clk_gen.sv \
                  hw/asep/rtl/gpio_cfg_codec.sv \
                  hw/asep/rtl/gpio_fs_codec.sv \
                  hw/asep/rtl/gpio_eg_codec.sv \
                  hw/asep/rtl/gpio_ase_tx.sv \
                  hw/asep/rtl/gpio_asd_rx.sv \
                  hw/asep/rtl/gpio_asep_top.sv

SPI_ASEP_PKGS := hw/asep/rtl/asa_spi_asep_pkg.sv
SPI_ASEP_MODS := hw/asep/rtl/spi_pkt_id_counter.sv \
                 hw/asep/rtl/spi_irq_counter.sv \
                 hw/asep/rtl/spi_cfg_codec.sv \
                 hw/asep/rtl/spi_dcp_timer.sv \
                 hw/asep/rtl/spi_tat_timer.sv \
                 hw/asep/rtl/spi_data_codec.sv \
                 hw/asep/rtl/spi_ase_tx.sv \
                 hw/asep/rtl/spi_asd_rx.sv \
                 hw/asep/rtl/spi_asep_top.sv

I2C_ASEP_PKGS := hw/asep/rtl/asa_i2c_asep_pkg.sv
I2C_ASEP_MODS := hw/asep/rtl/i2c_cmd_id_mgr.sv \
                 hw/asep/rtl/i2c_byte_codec.sv \
                 hw/asep/rtl/i2c_bulk_codec.sv \
                 hw/asep/rtl/i2c_cfg_codec.sv \
                 hw/asep/rtl/i2c_ase_tx.sv \
                 hw/asep/rtl/i2c_asd_rx.sv \
                 hw/asep/rtl/i2c_asep_top.sv

I2S_ASEP_PKGS := hw/asep/rtl/asa_i2s_asep_pkg.sv
I2S_ASEP_MODS := hw/asep/rtl/i2s_pkt_id_counter.sv \
                 hw/asep/rtl/i2s_cfg_codec.sv \
                 hw/asep/rtl/i2s_data_codec.sv \
                 hw/asep/rtl/i2s_ptb_sync.sv \
                 hw/asep/rtl/i2s_ase_tx.sv \
                 hw/asep/rtl/i2s_asd_rx.sv \
                 hw/asep/rtl/i2s_asep_top.sv

VIDEO_ASEP_PKGS := hw/asep/rtl/asa_video_asep_pkg.sv
VIDEO_ASEP_MODS := hw/asep/rtl/video_payload_codec.sv \
                   hw/asep/rtl/video_line_hdr.sv \
                   hw/asep/rtl/video_pixelclk_codec.sv \
                   hw/asep/rtl/video_ase_tx.sv \
                   hw/asep/rtl/video_asd_rx.sv \
                   hw/asep/rtl/video_asep_top.sv

EDP_ASEP_PKGS := hw/asep/rtl/asa_edp_asep_pkg.sv
EDP_ASEP_MODS := hw/asep/rtl/edp_vb_codec.sv \
                 hw/asep/rtl/edp_edm_data_codec.sv \
                 hw/asep/rtl/edp_aux_codec.sv \
                 hw/asep/rtl/edp_stream_clock_codec.sv \
                 hw/asep/rtl/edp_plm_8b10b_codec.sv \
                 hw/asep/rtl/edp_plm_128b132b_codec.sv \
                 hw/asep/rtl/edp_ase_tx.sv \
                 hw/asep/rtl/edp_asd_rx.sv \
                 hw/asep/rtl/edp_asep_top.sv

# MLE PCS
MLE_PCS_PKGS := hw/phy_pcs/rtl/asa_pcs_pkg.sv \
                hw/mle/rtl/asa_mle_pcs_pkg.sv
MLE_PCS_MODS := hw/mle/rtl/mle_4b5b_codec.sv \
                hw/mle/rtl/mle_crc8.sv \
                hw/mle/rtl/mle_phase1g_info.sv \
                hw/mle/rtl/mle_plb_codec.sv \
                hw/mle/rtl/mle_pcs_top.sv

MLE_XMII_PKGS := $(MLE_PCS_PKGS) \
                 hw/mle/rtl/asa_mle_xmii_pkg.sv
MLE_XMII_MODS := hw/mle/rtl/mle_xmii_normalize_tx.sv \
                 hw/mle/rtl/mle_64b65b_encode.sv \
                 hw/mle/rtl/mle_rate_match_tx.sv \
                 hw/mle/rtl/mle_64b65b_decode.sv \
                 hw/mle/rtl/mle_rate_match_rx.sv \
                 hw/mle/rtl/mle_xmii_denormalize_rx.sv \
                 hw/mle/rtl/mle_oam_tx_adapt.sv \
                 hw/mle/rtl/mle_oam_rx_adapt.sv \
                 hw/mle/rtl/mle_xmii_tx_top.sv \
                 hw/mle/rtl/mle_xmii_rx_top.sv \
                 hw/mle/rtl/mle_xmii_top.sv

# DLL Forwarding Fabric
FOFA_PKGS := hw/dll_forwarding/rtl/asa_fofa_pkg.sv
FOFA_MODS := hw/dll_forwarding/rtl/fofa_queue.sv \
             hw/dll_forwarding/rtl/fofa_switch_ctrl.sv \
             hw/dll_forwarding/rtl/fofa_local_reinject.sv \
             hw/dll_forwarding/rtl/fofa_top.sv

# DLL Mapper/Demux
DLL_PKGS := hw/dll_mapper/rtl/asa_dll_pkg.sv
DLL_MODS := hw/dll_mapper/rtl/dll_header_parse.sv \
            hw/dll_mapper/rtl/dll_header_build.sv \
            hw/dll_mapper/rtl/dll_rx_demux.sv \
            hw/dll_mapper/rtl/dll_tx_mapper.sv \
            hw/dll_mapper/rtl/dll_security_if.sv \
            hw/dll_mapper/rtl/dll_top.sv

# PHY PCS Datapath
PCS_PKGS := hw/phy_pcs/rtl/asa_pcs_pkg.sv
PCS_MODS := hw/phy_pcs/rtl/pcs_prbs11.sv \
            hw/phy_pcs/rtl/pcs_prbs9.sv \
            hw/phy_pcs/rtl/pcs_scrambler.sv \
            hw/phy_pcs/rtl/pcs_pam_map.sv \
            hw/phy_pcs/rtl/pcs_crc32.sv \
            hw/phy_pcs/rtl/pcs_rs_encoder.sv \
            hw/phy_pcs/rtl/pcs_resync_header.sv \
            hw/phy_pcs/rtl/pcs_ptb_vector_if.sv \
            hw/phy_pcs/rtl/pcs_tx_top.sv \
            hw/phy_pcs/rtl/pcs_rx_top.sv \
            hw/phy_pcs/rtl/pcs_top.sv

# Order-preserving list dedup for aggregate lint composition.
uniq = $(if $1,$(firstword $1) $(call uniq,$(filter-out $(firstword $1),$1)))

# Aggregate RTL lists (deduplicated for lint)
ALL_PKGS := $(call uniq, \
	$(COMMON_PKGS) $(OAM_PKGS) $(PHY_STARTUP_PKGS) $(PTB_PKGS) $(PCS_PKGS) \
	$(DLL_PKGS) $(FOFA_PKGS) $(LS_PKGS) $(LLS_PKGS) $(KEYEX_PKGS) $(ASEP_PKGS) \
	$(GPIO_ASEP_PKGS) $(SPI_ASEP_PKGS) $(I2C_ASEP_PKGS) $(I2S_ASEP_PKGS) \
	$(VIDEO_ASEP_PKGS) $(EDP_ASEP_PKGS) $(MLE_PCS_PKGS) $(MLE_XMII_PKGS))

ALL_MODS := $(call uniq, \
	$(COMMON_MODS) $(REG_MODS) $(NODE_MODS) $(OAM_MODS) $(PHY_STARTUP_MODS) \
	$(PTB_MODS) $(PCS_MODS) $(DLL_MODS) $(FOFA_MODS) $(LS_MODS) $(LLS_MODS) \
	$(KEYEX_MODS) $(ASEP_MODS) $(GPIO_ASEP_MODS) $(SPI_ASEP_MODS) \
	$(I2C_ASEP_MODS) $(I2S_ASEP_MODS) $(VIDEO_ASEP_MODS) $(EDP_ASEP_MODS) \
	$(MLE_PCS_MODS) $(MLE_XMII_MODS))

ALL_RTL := $(ALL_PKGS) $(ALL_MODS)

# Verilator common flags
VL_FLAGS := --timing \
            -Wno-TIMESCALEMOD -Wno-UNUSEDPARAM -Wno-UNUSEDSIGNAL \
            -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-MULTITOP \
            -Wno-UNOPTFLAT -Wno-VARHIDDEN -Wno-UNSIGNED -Wno-CMPCONST \
            -Wno-LATCH -Wno-WIDTHCONCAT

# ============================================================================
# Targets
# ============================================================================

.PHONY: all clean lint test test_node test_regbank test_oam test_phy_startup test_ptb test_phy_pcs test_dll_mapper test_dll_fwd test_light_sleep test_lls test_keyex test_asep_common test_asep_gpio test_asep_spi test_asep_i2c test_asep_i2s test_asep_video test_asep_edp test_mle_pcs test_mle_xmii test_foundation lint_phy_pcs lint_asep_gpio lint_asep_spi lint_asep_i2c lint_asep_i2s lint_asep_video lint_asep_edp lint_mle_pcs lint_mle_xmii

all: test

test: test_node test_regbank test_oam test_phy_startup test_ptb test_phy_pcs test_dll_mapper test_dll_fwd test_light_sleep test_lls test_keyex test_asep_common test_asep_gpio test_asep_spi test_asep_i2c test_asep_i2s test_asep_video test_asep_edp test_mle_pcs test_mle_xmii

# Node FSM (iverilog — no packed struct issues)
test_node:
	@echo "=== Node FSM (iverilog) ==="
	@mkdir -p $(OBJ_DIR)
	$(IVERILOG) -g2012 -o $(OBJ_DIR)/node_fsm_tb.vvp \
		hw/common/rtl/asa_node_pkg.sv \
		hw/node_fsm/rtl/asa_node_fsm.sv \
		hw/node_fsm/dv/asa_node_fsm_tb.sv
	$(VVP) $(OBJ_DIR)/node_fsm_tb.vvp
	$(IVERILOG) -g2012 -o $(OBJ_DIR)/node_fsm_top_tb.vvp \
		hw/common/rtl/asa_node_pkg.sv \
		hw/node_fsm/rtl/asa_node_fsm.sv \
		hw/node_fsm/rtl/asa_node_fsm_top.sv \
		hw/node_fsm/dv/asa_node_fsm_top_tb.sv
	$(VVP) $(OBJ_DIR)/node_fsm_top_tb.vvp
	@rm -f $(OBJ_DIR)/node_fsm_tb.vvp $(OBJ_DIR)/node_fsm_top_tb.vvp

# Register bank (Verilator — uses packed structs)
test_regbank:
	@echo "=== Register Bank (verilator) ==="
	@mkdir -p $(OBJ_DIR_REG)
	$(VERILATOR) --binary $(VL_FLAGS) --Mdir $(OBJ_DIR_REG) --top-module asa_reg_bank_tb \
		hw/common/rtl/asa_reg_pkg.sv \
		hw/register_model/rtl/asa_reg_bank.sv \
		hw/register_model/dv/asa_reg_bank_tb.sv \
		-o asa_reg_bank_tb
	./$(OBJ_DIR_REG)/asa_reg_bank_tb
	@rm -rf $(OBJ_DIR_REG)

# OAM tests (Verilator)
test_oam:
	@echo "=== OAM (verilator) ==="
	@mkdir -p $(OBJ_DIR_OAM)
	$(VERILATOR) --binary $(VL_FLAGS) --Mdir $(OBJ_DIR_OAM) -Wno-PINCONNECTEMPTY --top-module oam_tb \
		$(COMMON_PKGS) $(OAM_PKGS) $(REG_MODS) $(OAM_MODS) \
		hw/oam/dv/oam_tb.sv \
		-o oam_tb
	./$(OBJ_DIR_OAM)/oam_tb
	@rm -rf $(OBJ_DIR_OAM)

# PHY startup tests (Verilator)
test_phy_startup:
	@echo "=== PHY Startup (verilator) ==="
	@mkdir -p $(OBJ_DIR_PHY)
	$(VERILATOR) --binary $(VL_FLAGS) --Mdir $(OBJ_DIR_PHY) --top-module phy_startup_tb \
		$(COMMON_PKGS) $(PHY_STARTUP_PKGS) $(PHY_STARTUP_MODS) \
		hw/phy_startup/dv/phy_startup_tb.sv \
		-o phy_startup_tb
	./$(OBJ_DIR_PHY)/phy_startup_tb
	@rm -rf $(OBJ_DIR_PHY)

# PTB tests (Verilator)
test_ptb:
	@echo "=== PTB Clock Service (verilator) ==="
	@mkdir -p $(OBJ_DIR_PTB)
	$(VERILATOR) --binary $(VL_FLAGS) --Mdir $(OBJ_DIR_PTB) --top-module ptb_tb \
		$(COMMON_PKGS) $(PTB_PKGS) $(PTB_MODS) \
		hw/ptb/dv/ptb_tb.sv \
		-o ptb_tb
	./$(OBJ_DIR_PTB)/ptb_tb
	@rm -rf $(OBJ_DIR_PTB)

test_asep_gpio:
	@echo "=== ASEP GPIO (verilator) ==="
	@mkdir -p $(OBJ_DIR_ASEP_GPIO)
	$(VERILATOR) --binary $(VL_FLAGS) --Mdir $(OBJ_DIR_ASEP_GPIO) --top-module asep_gpio_tb \
		$(COMMON_PKGS) $(ASEP_PKGS) $(GPIO_ASEP_PKGS) $(GPIO_ASEP_MODS) \
		hw/asep/dv/asep_gpio_tb.sv \
		-o asep_gpio_tb
	./$(OBJ_DIR_ASEP_GPIO)/asep_gpio_tb
	@rm -rf $(OBJ_DIR_ASEP_GPIO)

test_asep_spi:
	@echo "=== ASEP SPI (verilator) ==="
	@mkdir -p $(OBJ_DIR_ASEP_SPI)
	$(VERILATOR) --binary $(VL_FLAGS) --Mdir $(OBJ_DIR_ASEP_SPI) --top-module asep_spi_tb \
		$(COMMON_PKGS) $(ASEP_PKGS) $(SPI_ASEP_PKGS) $(SPI_ASEP_MODS) \
		hw/asep/dv/asep_spi_tb.sv \
		-o asep_spi_tb
	./$(OBJ_DIR_ASEP_SPI)/asep_spi_tb
	@rm -rf $(OBJ_DIR_ASEP_SPI)

test_asep_i2c:
	@echo "=== ASEP I2C (verilator) ==="
	@mkdir -p $(OBJ_DIR_ASEP_I2C)
	$(VERILATOR) --binary $(VL_FLAGS) --Mdir $(OBJ_DIR_ASEP_I2C) --top-module asep_i2c_tb \
		$(COMMON_PKGS) $(ASEP_PKGS) $(I2C_ASEP_PKGS) $(I2C_ASEP_MODS) \
		hw/asep/dv/asep_i2c_tb.sv \
		-o asep_i2c_tb
	./$(OBJ_DIR_ASEP_I2C)/asep_i2c_tb
	@rm -rf $(OBJ_DIR_ASEP_I2C)

test_asep_i2s:
	@echo "=== ASEP I2S (verilator) ==="
	@mkdir -p $(OBJ_DIR_ASEP_I2S)
	$(VERILATOR) --binary $(VL_FLAGS) --Mdir $(OBJ_DIR_ASEP_I2S) --top-module asep_i2s_tb \
		$(COMMON_PKGS) $(ASEP_PKGS) $(I2S_ASEP_PKGS) $(I2S_ASEP_MODS) \
		hw/asep/dv/asep_i2s_tb.sv \
		-o asep_i2s_tb
	./$(OBJ_DIR_ASEP_I2S)/asep_i2s_tb
	@rm -rf $(OBJ_DIR_ASEP_I2S)

test_asep_video:
	@echo "=== ASEP Video (verilator) ==="
	@mkdir -p $(OBJ_DIR_ASEP_VIDEO)
	$(VERILATOR) --binary $(VL_FLAGS) --Mdir $(OBJ_DIR_ASEP_VIDEO) --top-module asep_video_tb \
		$(COMMON_PKGS) $(ASEP_PKGS) $(VIDEO_ASEP_PKGS) $(VIDEO_ASEP_MODS) \
		hw/asep/dv/asep_video_tb.sv \
		-o asep_video_tb
	./$(OBJ_DIR_ASEP_VIDEO)/asep_video_tb
	@rm -rf $(OBJ_DIR_ASEP_VIDEO)

test_asep_edp:
	@echo "=== ASEP eDP (verilator) ==="
	@mkdir -p $(OBJ_DIR_ASEP_EDP)_core
	$(VERILATOR) --binary $(VL_FLAGS) --Mdir $(OBJ_DIR_ASEP_EDP)_core --top-module asep_edp_tb \
		$(COMMON_PKGS) $(ASEP_PKGS) $(EDP_ASEP_PKGS) \
		hw/asep/rtl/edp_vb_codec.sv hw/asep/rtl/edp_aux_codec.sv hw/asep/rtl/edp_stream_clock_codec.sv \
		hw/asep/dv/asep_edp_tb.sv \
		-o asep_edp_tb
	./$(OBJ_DIR_ASEP_EDP)_core/asep_edp_tb
	@mkdir -p $(OBJ_DIR_ASEP_EDP)_edm
	$(VERILATOR) --binary $(VL_FLAGS) --Mdir $(OBJ_DIR_ASEP_EDP)_edm --top-module asep_edp_edm_tb \
		$(COMMON_PKGS) $(ASEP_PKGS) $(EDP_ASEP_PKGS) \
		hw/asep/rtl/edp_edm_data_codec.sv \
		hw/asep/dv/asep_edp_edm_tb.sv \
		-o asep_edp_edm_tb
	./$(OBJ_DIR_ASEP_EDP)_edm/asep_edp_edm_tb
	@mkdir -p $(OBJ_DIR_ASEP_EDP)_plm8
	$(VERILATOR) --binary $(VL_FLAGS) --Mdir $(OBJ_DIR_ASEP_EDP)_plm8 --top-module asep_edp_plm8_tb \
		$(COMMON_PKGS) $(ASEP_PKGS) $(EDP_ASEP_PKGS) \
		hw/asep/rtl/edp_plm_8b10b_codec.sv \
		hw/asep/dv/asep_edp_plm8_tb.sv \
		-o asep_edp_plm8_tb
	./$(OBJ_DIR_ASEP_EDP)_plm8/asep_edp_plm8_tb
	@mkdir -p $(OBJ_DIR_ASEP_EDP)_plm132
	$(VERILATOR) --binary $(VL_FLAGS) --Mdir $(OBJ_DIR_ASEP_EDP)_plm132 --top-module asep_edp_plm132_tb \
		$(COMMON_PKGS) $(ASEP_PKGS) $(EDP_ASEP_PKGS) \
		hw/asep/rtl/edp_plm_128b132b_codec.sv \
		hw/asep/dv/asep_edp_plm132_tb.sv \
		-o asep_edp_plm132_tb
	./$(OBJ_DIR_ASEP_EDP)_plm132/asep_edp_plm132_tb
	@rm -rf $(OBJ_DIR_ASEP_EDP)_core $(OBJ_DIR_ASEP_EDP)_edm $(OBJ_DIR_ASEP_EDP)_plm8 $(OBJ_DIR_ASEP_EDP)_plm132

test_mle_pcs:
	@echo "=== MLE PCS (verilator) ==="
	@mkdir -p $(OBJ_DIR_MLE_PCS)
	$(VERILATOR) --binary $(VL_FLAGS) --Mdir $(OBJ_DIR_MLE_PCS) --top-module mle_pcs_tb \
		$(MLE_PCS_PKGS) $(MLE_PCS_MODS) \
		hw/mle/dv/mle_pcs_tb.sv \
		-o mle_pcs_tb
	./$(OBJ_DIR_MLE_PCS)/mle_pcs_tb
	@rm -rf $(OBJ_DIR_MLE_PCS)

test_mle_xmii:
	@echo "=== MLE xMII Adaptation (verilator) ==="
	@mkdir -p $(OBJ_DIR_MLE_XMII)
	$(VERILATOR) --binary $(VL_FLAGS) --Mdir $(OBJ_DIR_MLE_XMII) --top-module mle_xmii_tb \
		$(MLE_XMII_PKGS) $(MLE_PCS_MODS) $(MLE_XMII_MODS) \
		hw/mle/dv/mle_xmii_tb.sv \
		-o mle_xmii_tb
	./$(OBJ_DIR_MLE_XMII)/mle_xmii_tb
	@rm -rf $(OBJ_DIR_MLE_XMII)

lint_asep_gpio:
	$(VERILATOR) --lint-only -Wall $(VL_FLAGS) -Wno-PINCONNECTEMPTY \
		$(COMMON_PKGS) $(ASEP_PKGS) $(GPIO_ASEP_PKGS) $(GPIO_ASEP_MODS)

lint_asep_spi:
	$(VERILATOR) --lint-only -Wall $(VL_FLAGS) -Wno-PINCONNECTEMPTY \
		$(COMMON_PKGS) $(ASEP_PKGS) $(SPI_ASEP_PKGS) $(SPI_ASEP_MODS)

lint_asep_i2c:
	$(VERILATOR) --lint-only -Wall $(VL_FLAGS) -Wno-PINCONNECTEMPTY \
		$(COMMON_PKGS) $(ASEP_PKGS) $(I2C_ASEP_PKGS) $(I2C_ASEP_MODS)

lint_asep_i2s:
	$(VERILATOR) --lint-only -Wall $(VL_FLAGS) -Wno-PINCONNECTEMPTY \
		$(COMMON_PKGS) $(ASEP_PKGS) $(I2S_ASEP_PKGS) $(I2S_ASEP_MODS)

lint_asep_video:
	$(VERILATOR) --lint-only -Wall $(VL_FLAGS) -Wno-PINCONNECTEMPTY \
		$(COMMON_PKGS) $(ASEP_PKGS) $(VIDEO_ASEP_PKGS) $(VIDEO_ASEP_MODS)

lint_asep_edp:
	$(VERILATOR) --lint-only -Wall $(VL_FLAGS) -Wno-PINCONNECTEMPTY \
		$(COMMON_PKGS) $(ASEP_PKGS) $(EDP_ASEP_PKGS) $(EDP_ASEP_MODS)

lint_mle_pcs:
	$(VERILATOR) --lint-only -Wall $(VL_FLAGS) -Wno-PINCONNECTEMPTY \
		$(MLE_PCS_PKGS) $(MLE_PCS_MODS)

lint_mle_xmii:
	$(VERILATOR) --lint-only -Wall $(VL_FLAGS) -Wno-PINCONNECTEMPTY \
		$(MLE_XMII_PKGS) $(MLE_PCS_MODS) $(MLE_XMII_MODS)

# PHY PCS tests (Verilator)
OBJ_DIR_PCS := $(OBJ_DIR)/pcs

test_phy_pcs:
	@echo "=== PHY PCS (verilator) ==="
	@mkdir -p $(OBJ_DIR_PCS)
	$(VERILATOR) --binary $(VL_FLAGS) --Mdir $(OBJ_DIR_PCS) --top-module pcs_tb \
		hw/common/rtl/asa_error_pkg.sv \
		$(PCS_PKGS) $(PCS_MODS) \
		hw/phy_pcs/dv/pcs_tb.sv \
		-o pcs_tb
	./$(OBJ_DIR_PCS)/pcs_tb
	@rm -rf $(OBJ_DIR_PCS)

lint_phy_pcs:
	$(VERILATOR) --lint-only -Wall $(VL_FLAGS) -Wno-PINCONNECTEMPTY \
		hw/common/rtl/asa_error_pkg.sv $(PCS_PKGS) $(PCS_MODS)

# DLL Mapper/Demux tests
OBJ_DIR_DLL := $(OBJ_DIR)/dll

test_dll_mapper:
	@echo "=== DLL Mapper/Demux (verilator) ==="
	@mkdir -p $(OBJ_DIR_DLL)
	$(VERILATOR) --binary $(VL_FLAGS) --Mdir $(OBJ_DIR_DLL) --top-module dll_tb \
		$(DLL_PKGS) $(DLL_MODS) \
		hw/dll_mapper/dv/dll_tb.sv \
		-o dll_tb
	./$(OBJ_DIR_DLL)/dll_tb
	@rm -rf $(OBJ_DIR_DLL)

lint_dll_mapper:
	$(VERILATOR) --lint-only -Wall $(VL_FLAGS) -Wno-PINCONNECTEMPTY \
		$(DLL_PKGS) $(DLL_MODS)

# DLL Forwarding Fabric tests
OBJ_DIR_FOFA := $(OBJ_DIR)/fofa

test_dll_fwd:
	@echo "=== DLL Forwarding Fabric (verilator) ==="
	@mkdir -p $(OBJ_DIR_FOFA)
	$(VERILATOR) --binary $(VL_FLAGS) --Mdir $(OBJ_DIR_FOFA) --top-module fofa_tb \
		$(DLL_PKGS) $(FOFA_PKGS) $(FOFA_MODS) \
		hw/dll_forwarding/dv/fofa_tb.sv \
		-o fofa_tb
	./$(OBJ_DIR_FOFA)/fofa_tb
	@rm -rf $(OBJ_DIR_FOFA)

lint_dll_fwd:
	$(VERILATOR) --lint-only -Wall $(VL_FLAGS) -Wno-PINCONNECTEMPTY \
		$(DLL_PKGS) $(FOFA_PKGS) $(FOFA_MODS)

# Light Sleep FSM tests
OBJ_DIR_LS := $(OBJ_DIR)/ls

test_light_sleep:
	@echo "=== Light Sleep FSM (verilator) ==="
	@mkdir -p $(OBJ_DIR_LS)
	$(VERILATOR) --binary $(VL_FLAGS) --Mdir $(OBJ_DIR_LS) --top-module ls_tb \
		$(LS_PKGS) $(LS_MODS) \
		hw/light_sleep/dv/ls_tb.sv \
		-o ls_tb
	./$(OBJ_DIR_LS)/ls_tb
	@rm -rf $(OBJ_DIR_LS)

test_lls:
	@echo "=== Link Layer Security (verilator) ==="
	@mkdir -p $(OBJ_DIR_LLS)
	$(VERILATOR) --binary $(VL_FLAGS) --Mdir $(OBJ_DIR_LLS) --top-module lls_tb \
		$(LLS_PKGS) $(LLS_MODS) \
		hw/security/dv/lls_tb.sv \
		-o lls_tb
	./$(OBJ_DIR_LLS)/lls_tb
	@rm -rf $(OBJ_DIR_LLS)

test_keyex:
	@echo "=== KeyEx Entity (verilator) ==="
	@mkdir -p $(OBJ_DIR_KEYEX)
	$(VERILATOR) --binary $(VL_FLAGS) --Mdir $(OBJ_DIR_KEYEX) --top-module keyex_tb \
		$(KEYEX_PKGS) $(KEYEX_MODS) \
		hw/keyex/dv/keyex_tb.sv \
		-o keyex_tb
	./$(OBJ_DIR_KEYEX)/keyex_tb
	@rm -rf $(OBJ_DIR_KEYEX)

test_asep_common:
	@echo "=== ASEP Common Framing (verilator) ==="
	@mkdir -p $(OBJ_DIR_ASEP)
	$(VERILATOR) --binary $(VL_FLAGS) --Mdir $(OBJ_DIR_ASEP) --top-module asep_common_tb \
		$(COMMON_PKGS) $(ASEP_PKGS) $(ASEP_MODS) \
		hw/asep/dv/asep_common_tb.sv \
		-o asep_common_tb
	./$(OBJ_DIR_ASEP)/asep_common_tb
	@rm -rf $(OBJ_DIR_ASEP)

lint_light_sleep:
	$(VERILATOR) --lint-only -Wall $(VL_FLAGS) -Wno-PINCONNECTEMPTY \
		$(LS_PKGS) $(LS_MODS)

.PHONY: test_dll_fwd lint_dll_fwd test_light_sleep lint_light_sleep test_lls lint_lls test_keyex lint_keyex

# Integration (Verilator)
test_foundation:
	@echo "=== Foundation Integration (verilator) ==="
	$(VERILATOR) --binary $(VL_FLAGS) --top-module asa_foundation_tb \
		$(COMMON_PKGS) $(COMMON_MODS) $(REG_MODS) \
		hw/top/dv/asa_foundation_tb.sv \
		-o asa_foundation_tb
	./$(OBJ_DIR)/asa_foundation_tb
	@rm -rf $(OBJ_DIR)

# Lint all RTL
lint:
	$(VERILATOR) --lint-only -Wall $(VL_FLAGS) -Wno-PINCONNECTEMPTY $(ALL_RTL)

clean:
	rm -rf $(OBJ_DIR) work

# ============================================================================
# Module-level convenience targets
# ============================================================================

.PHONY: lint_node lint_reg lint_oam lint_phy_startup lint_ptb lint_lls lint_keyex lint_asep_common

lint_node:
	$(VERILATOR) --lint-only -Wall $(VL_FLAGS) \
		$(COMMON_PKGS) hw/node_fsm/rtl/*.sv

lint_reg:
	$(VERILATOR) --lint-only -Wall $(VL_FLAGS) \
		$(COMMON_PKGS) $(REG_MODS)

lint_oam:
	$(VERILATOR) --lint-only -Wall $(VL_FLAGS) -Wno-PINCONNECTEMPTY \
		$(COMMON_PKGS) $(OAM_PKGS) $(REG_MODS) $(OAM_MODS)

lint_phy_startup:
	$(VERILATOR) --lint-only -Wall $(VL_FLAGS) \
		$(COMMON_PKGS) $(PHY_STARTUP_PKGS) $(PHY_STARTUP_MODS)

lint_ptb:
	$(VERILATOR) --lint-only -Wall $(VL_FLAGS) \
		$(COMMON_PKGS) $(PTB_PKGS) $(PTB_MODS)

lint_lls:
	$(VERILATOR) --lint-only -Wall $(VL_FLAGS) -Wno-PINCONNECTEMPTY \
		$(LLS_PKGS) $(LLS_MODS)

lint_keyex:
	$(VERILATOR) --lint-only -Wall $(VL_FLAGS) \
		$(KEYEX_PKGS) $(KEYEX_MODS)

lint_asep_common:
	$(VERILATOR) --lint-only -Wall $(VL_FLAGS) -Wno-PINCONNECTEMPTY \
		$(COMMON_PKGS) $(ASEP_PKGS) $(ASEP_MODS)
