`timescale 1ns/1ps
`default_nettype none

// PCS PAM2/PAM4 Mapper
// Spec: Sections 4.2.2.6 (PAM2), 4.2.2.7 (PAM4 Gray)
//
// PAM2 (SG1/2/3 downstream, all upstream):
//   0 → +1, 1 → -1
//
// PAM4 Gray (SG4/5 downstream):
//   {MSB,LSB}={0,0} → +1    (level +3 in integer scale)
//   {MSB,LSB}={0,1} → +1/3  (level +1)
//   {MSB,LSB}={1,1} → -1/3  (level -1)
//   {MSB,LSB}={1,0} → -1    (level -3)
//
// Resync header bits: PAM2 always (0→+1, 1→-1), regardless of SG mode.
// (PDF p99: "Each bit of tx_phy_rsync_hdr is mapped to one PAM2 symbol M(j)")

module pcs_pam_map
  import asa_pcs_pkg::*;
(
  // Mode selection
  input  logic        is_pam4_i,      // 1=PAM4 (SG4/5 Dn), 0=PAM2
  input  logic        is_resync_hdr_i, // 1=resync header region (always PAM2)

  // Input bits (one or two per symbol)
  input  logic        bit_msb_i,      // MSB (used in PAM4) or single bit (PAM2)
  input  logic        bit_lsb_i,      // LSB (PAM4 only)

  // Output symbol (signed integer representation)
  output pam2_sym_t   pam2_sym_o,     // Valid when !is_pam4 or is_resync_hdr
  output pam4_sym_t   pam4_sym_o,     // Valid when is_pam4 and !is_resync_hdr
  output logic        use_pam4_o      // Which output is valid
);

  assign use_pam4_o = is_pam4_i && !is_resync_hdr_i;

  // PAM2 mapping: always computed
  assign pam2_sym_o = pam2_map(bit_msb_i);

  // PAM4 mapping: computed when relevant
  assign pam4_sym_o = pam4_map({bit_msb_i, bit_lsb_i});

endmodule

`default_nettype wire
