`timescale 1ns/1ps
`default_nettype none

// ASA Register Access Layer
// Spec: Section 3.1, 8.2 of micro-architecture-register-model.md
//
// Responsibilities:
//   1. Address decoding (domain/subdomain/addr/bit-select)
//   2. Access control enforcement (L vs O, RID, A privilege)
//   3. Side-effect handling (SC clear-on-read, SoftReset selective clear)
//   4. Domain routing to per-domain register banks
//
// This module sits between the OAM bridge / local bus and the domain banks.
// Each domain bank is a separate module that implements storage and HW-write paths.

module asa_reg_access
  import asa_reg_pkg::*;
#(
  parameter int unsigned NUM_DOM1_REGS = 32,
  parameter int unsigned NUM_DOM2_REGS = 64,
  parameter int unsigned NUM_DOM3_REGS = 3
) (
  input  logic        clk,
  input  logic        rst,

  // Request port (unified for local + OAM)
  input  reg_req_t    req_i,
  output reg_resp_t   resp_o,

  // Per-domain bank interfaces — flat storage arrays
  // Domain 1 (PHY)
  output logic        dom1_rd_en,
  output logic        dom1_wr_en,
  output logic [14:0] dom1_addr,
  output logic [15:0] dom1_wr_data,
  output logic [15:0] dom1_wr_mask,
  input  logic [15:0] dom1_rd_data,
  input  logic        dom1_valid,

  // Domain 2 (DLL)
  output logic        dom2_rd_en,
  output logic        dom2_wr_en,
  output logic [14:0] dom2_addr,
  output logic [15:0] dom2_wr_data,
  output logic [15:0] dom2_wr_mask,
  input  logic [15:0] dom2_rd_data,
  input  logic        dom2_valid,

  // Domain 3 (Security)
  output logic        dom3_rd_en,
  output logic        dom3_wr_en,
  output logic [14:0] dom3_addr,
  output logic [15:0] dom3_wr_data,
  output logic [15:0] dom3_wr_mask,
  input  logic [15:0] dom3_rd_data,
  input  logic        dom3_valid,

  // Domain 4 (ASE)
  output logic        dom4_rd_en,
  output logic        dom4_wr_en,
  output logic [5:0]  dom4_subdomain,
  output logic [14:0] dom4_addr,
  output logic [15:0] dom4_wr_data,
  output logic [15:0] dom4_wr_mask,
  input  logic [15:0] dom4_rd_data,
  input  logic        dom4_valid,

  // Domain 5 (ASD)
  output logic        dom5_rd_en,
  output logic        dom5_wr_en,
  output logic [5:0]  dom5_subdomain,
  output logic [14:0] dom5_addr,
  output logic [15:0] dom5_wr_data,
  output logic [15:0] dom5_wr_mask,
  input  logic [15:0] dom5_rd_data,
  input  logic        dom5_valid,

  // Per-register metadata lookup (provided by domain banks)
  input  reg_meta_t   meta_i,
  input  logic        meta_valid_i,

  // Configuration: local nodeID for RID check
  input  logic [4:0]  local_node_id
);

  // =========================================================================
  // Address decode
  // =========================================================================
  reg_domain_e  decoded_domain;
  logic [5:0]   decoded_subdomain;
  logic [14:0]  decoded_addr;
  logic         addr_valid;

  always_comb begin
    decoded_domain    = req_i.addr.domain;
    decoded_subdomain = req_i.addr.subdomain;
    decoded_addr      = req_i.addr.addr;

    // Validate domain range (0-5)
    addr_valid = (decoded_domain <= REG_DOM_ASD);

    // Validate subdomain for ASE/ASD
    if (domain_has_subdomain(decoded_domain)) begin
      addr_valid = addr_valid && valid_subdomain(decoded_subdomain);
    end
  end

  // =========================================================================
  // Bit-field mask generation
  // =========================================================================
  logic [15:0] wr_mask;

  always_comb begin
    if (req_i.bitsel.valid) begin
      wr_mask = '0;
      for (int i = 0; i < 16; i++) begin
        if (i >= int'(req_i.bitsel.lsb) && i <= int'(req_i.bitsel.msb)) begin
          wr_mask[i] = 1'b1;
        end
      end
    end else begin
      wr_mask = 16'hFFFF;
    end
  end

  // =========================================================================
  // Access control (Section 3.1, per-register attributes)
  // =========================================================================
  logic access_denied;

  always_comb begin
    access_denied = 1'b0;

    if (meta_valid_i && (req_i.rd_en || req_i.wr_en)) begin
      // Channel check: if register is L-only, deny OAM access
      if (req_i.oam_path && meta_i.access == REG_ACCESS_L) begin
        access_denied = 1'b1;
      end

      // RID privilege: OAM source must be nodeID=1 (root)
      if (req_i.oam_path && meta_i.privilege == REG_PRIV_RID) begin
        if (req_i.src_node_id != 5'd1) begin
          access_denied = 1'b1;
        end
      end

      // A privilege: link must be authenticated
      if (meta_i.privilege == REG_PRIV_A) begin
        if (!req_i.authenticated) begin
          access_denied = 1'b1;
        end
      end

      // Write to RO register
      if (req_i.wr_en && meta_i.rw_type == REG_RO) begin
        access_denied = 1'b1;
      end
    end
  end

  // =========================================================================
  // Domain routing
  // =========================================================================
  logic active_req;
  assign active_req = (req_i.rd_en || req_i.wr_en) && addr_valid && !access_denied;

  always_comb begin
    // Default: all disabled
    dom1_rd_en = 0; dom1_wr_en = 0; dom1_addr = decoded_addr;
    dom1_wr_data = req_i.wr_data; dom1_wr_mask = wr_mask;

    dom2_rd_en = 0; dom2_wr_en = 0; dom2_addr = decoded_addr;
    dom2_wr_data = req_i.wr_data; dom2_wr_mask = wr_mask;

    dom3_rd_en = 0; dom3_wr_en = 0; dom3_addr = decoded_addr;
    dom3_wr_data = req_i.wr_data; dom3_wr_mask = wr_mask;

    dom4_rd_en = 0; dom4_wr_en = 0; dom4_addr = decoded_addr;
    dom4_subdomain = decoded_subdomain;
    dom4_wr_data = req_i.wr_data; dom4_wr_mask = wr_mask;

    dom5_rd_en = 0; dom5_wr_en = 0; dom5_addr = decoded_addr;
    dom5_subdomain = decoded_subdomain;
    dom5_wr_data = req_i.wr_data; dom5_wr_mask = wr_mask;

    if (active_req) begin
      unique case (decoded_domain)
        REG_DOM_USER: begin end // Domain 0: implementer-defined, not routed here
        REG_DOM_PHY: begin
          dom1_rd_en = req_i.rd_en;
          dom1_wr_en = req_i.wr_en;
        end
        REG_DOM_DLL: begin
          dom2_rd_en = req_i.rd_en;
          dom2_wr_en = req_i.wr_en;
        end
        REG_DOM_SEC: begin
          dom3_rd_en = req_i.rd_en;
          dom3_wr_en = req_i.wr_en;
        end
        REG_DOM_ASE: begin
          dom4_rd_en = req_i.rd_en;
          dom4_wr_en = req_i.wr_en;
        end
        REG_DOM_ASD: begin
          dom5_rd_en = req_i.rd_en;
          dom5_wr_en = req_i.wr_en;
        end
        default: begin end
      endcase
    end
  end

  // =========================================================================
  // Response mux
  // =========================================================================
  logic [15:0] raw_rd_data;
  logic        any_valid;

  always_comb begin
    raw_rd_data = 16'd0;
    any_valid   = 1'b0;

    unique case (decoded_domain)
      REG_DOM_PHY: begin raw_rd_data = dom1_rd_data; any_valid = dom1_valid; end
      REG_DOM_DLL: begin raw_rd_data = dom2_rd_data; any_valid = dom2_valid; end
      REG_DOM_SEC: begin raw_rd_data = dom3_rd_data; any_valid = dom3_valid; end
      REG_DOM_ASE: begin raw_rd_data = dom4_rd_data; any_valid = dom4_valid; end
      REG_DOM_ASD: begin raw_rd_data = dom5_rd_data; any_valid = dom5_valid; end
      default:     begin raw_rd_data = 16'd0;        any_valid = 1'b0; end
    endcase
  end

  // Apply bit-field extraction on read
  logic [15:0] masked_rd_data;
  always_comb begin
    if (req_i.bitsel.valid) begin
      masked_rd_data = (raw_rd_data & wr_mask) >> req_i.bitsel.lsb;
    end else begin
      masked_rd_data = raw_rd_data;
    end
  end

  // =========================================================================
  // Output response
  // =========================================================================
  always_comb begin
    resp_o.rd_data    = masked_rd_data;
    resp_o.ack        = active_req && any_valid;
    resp_o.err_access = (req_i.rd_en || req_i.wr_en) && addr_valid && access_denied;
    resp_o.err_addr   = (req_i.rd_en || req_i.wr_en) && !addr_valid;
  end

endmodule

`default_nettype wire
