`timescale 1ns/1ps
`default_nettype none

// PCS Resynchronization Header Generator
// Spec: Section 4.2.2.3, Equations 4-1 and 4-2, Figure 4-3
//
// Constructs tx_phy_rsync_hdr<0:resylen-1> by filling:
//   [0, n-1]          = rsync_prbs (PRBS11 stream)
//   [n, n+79]         = sy_double  (sync seq doubled, 80 bits)
//   [n+80, n+159]     = sy_double  (SG3/4/5 only: second occurrence)
//   [n+160 or n+80, m-1] = rsync_prbs
//   [m, m+39]         = sy         (sync seq, 40 bits)
//   [m+40, m+79]      = sy         (SG3/4/5 only: second occurrence)
//   [m+80 or m+40, resylen-33] = rsync_prbs
//   [resylen-32, resylen-17] = m_ptb[15:0]  (PTB message)
//   [resylen-16, resylen-1]  = ~m_ptb[15:0] (inverted)
//
// n = 64 + 2*offset  (offset 0-31 from PRBS9 dithering)
// m = second_sync_base(sg) + offset
//
// The header is output as a bit-serial stream with a valid/ready handshake.
// The caller drives advance each cycle the header is being sent.
//
// NOTE: resync header bits are mapped PAM2 (0→+1, 1→-1) regardless of SG.
// (PDF p99: "Each bit of tx_phy_rsync_hdr is mapped to one PAM2 symbol M(j)")

module pcs_resync_header
  import asa_pcs_pkg::*;
(
  input  logic              clk,
  input  logic              rst,

  // Control
  input  logic              init_i,       // Reset LFSRs (at startup_INIT)
  input  logic              start_i,      // Begin generating a new header
  input  logic              advance_i,    // Consume one symbol (clock output)
  input  speed_grade_e      sg_i,         // Speed grade selects header length & positions
  input  logic [15:0]       m_ptb_i,      // PTB message vector from PTB service

  // Output
  output logic              bit_o,        // Current header bit (mapped PAM2 externally)
  output logic              valid_o,      // Header symbol available
  output logic              done_o        // All header symbols sent

);

  // Internal LFSRs
  logic [10:0] prbs11_q;
  logic [8:0]  prbs9_q;

  // Position counter
  logic [10:0] pos_q;            // Current symbol position (0..resylen-1)
  logic [10:0] resylen_q;        // Cached resylen for current burst
  logic [10:0] n_pos_q;          // First sync position
  logic [10:0] m_pos_q;          // Second sync position
  logic [4:0]  offset_q;         // Dithering offset
  logic        is_sg345_q;       // SG3/4/5 flag (double sync sequences)
  logic        active_q;

  assign valid_o = active_q;
  assign done_o  = active_q && (pos_q >= resylen_q - 1) && advance_i;

  // Determine which region pos falls in and output the correct bit.
  // Use registered values (n_pos_q, m_pos_q, resylen_q) to avoid latch.
  always_comb begin
    bit_o = 1'b0; // Default: avoids latch

    if (active_q) begin
      if (is_sg345_q) begin
        // SG3/4/5: Equation 4-2
        // sy_double<0:79> = {sy<0>,sy<0>,sy<1>,sy<1>,...} — each bit doubled
        // Two occurrences of sy_double at [n..n+79] and [n+80..n+159]
        // Then single sy at [m..m+39] and [m+40..m+79]
        if (pos_q < n_pos_q)
          bit_o = prbs11_q[0];
        else if (pos_q < n_pos_q + 11'd80)
          bit_o = SYNC_SEQUENCE[(pos_q - n_pos_q) / 2];        // sy_double: bit k → sy[k/2]
        else if (pos_q < n_pos_q + 11'd160)
          bit_o = SYNC_SEQUENCE[(pos_q - n_pos_q - 11'd80) / 2]; // sy_double again
        else if (pos_q < m_pos_q)
          bit_o = prbs11_q[0];
        else if (pos_q < m_pos_q + 11'd40)
          bit_o = SYNC_SEQUENCE[(pos_q - m_pos_q) % 40];       // sy single
        else if (pos_q < m_pos_q + 11'd80)
          bit_o = SYNC_SEQUENCE[(pos_q - m_pos_q - 11'd40) % 40]; // sy single again
        else if (pos_q < resylen_q - 11'd32)
          bit_o = prbs11_q[0];
        else if (pos_q < resylen_q - 11'd16)
          bit_o = m_ptb_i[(pos_q - (resylen_q - 11'd32)) % 16];
        else
          bit_o = ~m_ptb_i[(pos_q - (resylen_q - 11'd16)) % 16];
      end else begin
        // SG1/2: Equation 4-1
        // sy_double at [n..n+79]: each sy bit doubled → sy_double<k> = sy<k/2>
        // sy single at [m..m+39]
        if (pos_q < n_pos_q)
          bit_o = prbs11_q[0];
        else if (pos_q < n_pos_q + 11'd80)
          bit_o = SYNC_SEQUENCE[(pos_q - n_pos_q) / 2];        // sy_double: bit k → sy[k/2]
        else if (pos_q < m_pos_q)
          bit_o = prbs11_q[0];
        else if (pos_q < m_pos_q + 11'd40)
          bit_o = SYNC_SEQUENCE[(pos_q - m_pos_q) % 40];       // sy single
        else if (pos_q < resylen_q - 11'd32)
          bit_o = prbs11_q[0];
        else if (pos_q < resylen_q - 11'd16)
          bit_o = m_ptb_i[(pos_q - (resylen_q - 11'd32)) % 16];
        else
          bit_o = ~m_ptb_i[(pos_q - (resylen_q - 11'd16)) % 16];
      end
    end
  end

  // State update
  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      prbs11_q  <= PRBS11_INIT;
      prbs9_q   <= PRBS9_INIT;
      active_q  <= 1'b0;
      pos_q     <= 11'd0;
      resylen_q <= 11'd0;
      n_pos_q   <= 11'd0;
      m_pos_q   <= 11'd0;
      offset_q  <= 5'd0;
      is_sg345_q<= 1'b0;
    end else if (init_i) begin
      prbs11_q  <= PRBS11_INIT;
      prbs9_q   <= PRBS9_INIT;
      active_q  <= 1'b0;
    end else if (start_i && !active_q) begin
      // Capture dithering offset, compute positions, start generation
      begin
        automatic logic [4:0] off;
        automatic logic [10:0] rl, n_val, m_val;
        off   = prbs9_offset(prbs9_q);
        rl    = resync_len(sg_i);
        n_val = 64 + 11'(off) * 2;
        m_val = second_sync_base(sg_i) + 11'(off);

        offset_q   <= off;
        resylen_q  <= rl;
        n_pos_q    <= n_val;
        m_pos_q    <= m_val;
        is_sg345_q <= (sg_i == SG3 || sg_i == SG4 || sg_i == SG5);
        active_q   <= 1'b1;
        pos_q      <= 11'd0;

        // Advance PRBS9 for next burst (5 steps consumed for offset)
        begin
          automatic logic [8:0] ps;
          ps = prbs9_q;
          for (int i = 0; i < 5; i++) ps = prbs9_step(ps);
          prbs9_q <= ps;
        end
      end
    end else if (active_q && advance_i) begin
      // Advance PRBS11 only when in a PRBS-fill region
      // (PRBS11 is advanced 1 step per rsync_prbs bit emitted)
      begin
        automatic logic [10:0] p = pos_q;
        automatic logic [10:0] n = n_pos_q;
        automatic logic [10:0] m = m_pos_q;
        automatic logic [10:0] rl = resylen_q;
        automatic logic is_prbs_region;

        if (is_sg345_q) begin
          is_prbs_region = (p < n) ||
                           (p >= n+160 && p < m) ||
                           (p >= m+80  && p < rl-32);
        end else begin
          is_prbs_region = (p < n) ||
                           (p >= n+80  && p < m) ||
                           (p >= m+40  && p < rl-32);
        end

        if (is_prbs_region)
          prbs11_q <= prbs11_step(prbs11_q);
      end

      if (pos_q >= resylen_q - 1)
        active_q <= 1'b0;
      else
        pos_q <= pos_q + 11'd1;
    end
  end

endmodule

`default_nettype wire
